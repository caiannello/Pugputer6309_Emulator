// Crash safety: what a power cut between any two disk writes leaves behind.
//
// A script of file and directory operations runs once through the real DOS while the
// SD device logs every block write in order. Because DOS's disk writes are the only
// thing that survives a power cut, the disk after a cut at write k is exactly the
// original image plus the first k logged writes -- so every possible cut point is
// checked, without re-running DOS, by building that image and inspecting it with the
// independent FAT16 reader:
//
//  * structure: every directory entry is well-formed, every cluster chain ends
//    properly, no chain runs into a free cluster (a freed cluster still reachable), no
//    cluster is in two chains, sizes never exceed what the chain holds, "." and ".."
//    are right, and no directory contains garbage (a new directory cluster must be
//    zeroed before it is linked in);
//  * contents: everything the script had completed before the cut (its call returned
//    with all its writes done) is still there and intact, except what the one operation
//    in flight was changing, and nothing unexpected appeared.
//
// Lost clusters (allocated, in no file) are allowed in the middle of an operation -- the
// price of the write ordering -- but never once an operation has completed.
#include <algorithm>
#include <cstdio>
#include <fstream>
#include <functional>
#include <map>
#include <set>
#include <string>
#include <vector>

#include "disk_images.hpp"
#include "dos_session.hpp"
#include "fat16_reader.hpp"
#include "test_framework.hpp"

namespace {

using Bytes = std::vector<uint8_t>;

struct Model {
    std::map<std::string, Bytes> files;
    std::set<std::string> dirs; // "/A", "/A/B", ...
};

struct Op {
    std::string what;
    std::function<bool(DosSession&)> run;
    std::function<void(Model&)> apply;
    std::set<std::string> touched; // paths whose state is in flux while this op runs
};

std::string parent_of(const std::string& p) {
    size_t s = p.rfind('/');
    return s == 0 ? "/" : p.substr(0, s);
}

// ---- structure checks ------------------------------------------------------
struct Walk {
    std::string err;
    std::set<uint32_t> used;
    std::map<std::string, Fat16Volume::Entry> found; // absolute path -> entry
};

bool valid_name(const uint8_t* e) {
    static const std::string bad = "\"*+,/:;<=>?[\\]|";
    if (e[0] == ' ') return false;
    for (int i = 0; i < 11; ++i) {
        uint8_t c = e[i];
        if (c < 0x20 || c > 0x7E) return false;
        if (c >= 'a' && c <= 'z') return false;
        if (bad.find(static_cast<char>(c)) != std::string::npos) return false;
    }
    return true;
}

bool walk_chain(const Fat16Volume& v, uint16_t first, Walk& w, std::vector<uint16_t>& out, const std::string& who) {
    uint32_t c = first;
    for (;;) {
        if (c < 2 || c >= v.clusters + 2) {
            w.err = who + ": chain link to invalid cluster " + std::to_string(c);
            return false;
        }
        if (!w.used.insert(c).second) {
            w.err = who + ": cluster " + std::to_string(c) + " is in two chains (or a cycle)";
            return false;
        }
        out.push_back(static_cast<uint16_t>(c));
        uint16_t n = v.fat(c);
        if (n >= 0xFFF8) return true;
        if (n == 0) {
            w.err = who + ": chain runs into free cluster after " + std::to_string(c);
            return false;
        }
        c = n;
    }
}

bool walk_dir(const Fat16Volume& v, const std::string& path, uint16_t cluster, uint16_t parent_cluster, Walk& w) {
    std::vector<uint32_t> sectors;
    if (cluster == 0) {
        for (uint32_t i = 0; i < v.root_entries / 16; ++i) sectors.push_back(v.root_lba + i);
    } else {
        std::vector<uint16_t> chain;
        if (!walk_chain(v, cluster, w, chain, path)) return false;
        for (uint16_t c : chain)
            for (uint32_t i = 0; i < v.sec_per_clus; ++i) sectors.push_back(v.cluster_lba(c) + i);
    }
    int index = 0;
    for (uint32_t lba : sectors) {
        for (int i = 0; i < 16; ++i, ++index) {
            const uint8_t* e = &v.img[static_cast<size_t>(lba) * 512 + i * 32];
            if (e[0] == 0) return true; // end of the directory
            if (e[0] == 0xE5) continue;
            if (!valid_name(e)) {
                w.err = path + ": garbage directory entry #" + std::to_string(index);
                return false;
            }
            uint8_t attr = e[11];
            std::string name = Fat16Volume::dotted(e);
            uint16_t first = static_cast<uint16_t>(e[26] | (e[27] << 8));
            uint32_t size = e[28] | (e[29] << 8) | (e[30] << 16) | (static_cast<uint32_t>(e[31]) << 24);
            if (attr != 0x20 && attr != 0x10) {
                w.err = path + "/" + name + ": bad attribute " + std::to_string(attr);
                return false;
            }
            if (name == "." || name == "..") {
                if (cluster == 0 || index > 1 || (name == "." && first != cluster) ||
                    (name == ".." && first != parent_cluster)) {
                    w.err = path + ": wrong '.' or '..' entry";
                    return false;
                }
                continue;
            }
            std::string full = path == "/" ? "/" + name : path + "/" + name;
            Fat16Volume::Entry en;
            en.name = name;
            en.attr = attr;
            en.cluster = first;
            en.size = size;
            w.found[full] = en;
            if (attr == 0x10) {
                if (!walk_dir(v, full, first, cluster, w)) return false;
            } else if (size > 0 || first != 0) {
                if (first == 0) {
                    w.err = full + ": size " + std::to_string(size) + " but no clusters";
                    return false;
                }
                std::vector<uint16_t> chain;
                if (!walk_chain(v, first, w, chain, full)) return false;
                if (static_cast<uint64_t>(size) > static_cast<uint64_t>(chain.size()) * v.sec_per_clus * 512) {
                    w.err = full + ": size " + std::to_string(size) + " exceeds its " + std::to_string(chain.size()) + " clusters";
                    return false;
                }
            }
        }
    }
    return true;
}

// ---- the script ------------------------------------------------------------
Bytes data(size_t n, uint8_t seed) {
    Bytes v(n);
    for (size_t i = 0; i < n; ++i) v[i] = static_cast<uint8_t>(seed + i * 7 + (i >> 8));
    return v;
}

std::vector<Op> build_script() {
    std::vector<Op> ops;
    auto mkdir = [&](const std::string& p) {
        ops.push_back({"mkdir " + p, [p](DosSession& d) { return d.mkdir(p).ok(); }, [p](Model& m) { m.dirs.insert(p); }, {p}});
    };
    auto rmdir = [&](const std::string& p) {
        ops.push_back({"rmdir " + p, [p](DosSession& d) { return d.rmdir(p).ok(); }, [p](Model& m) { m.dirs.erase(p); }, {p}});
    };
    auto write = [&](const std::string& p, size_t n, uint8_t seed) {
        Bytes b = data(n, seed);
        ops.push_back({"write " + p, [p, b](DosSession& d) { return d.write_file(p, b); }, [p, b](Model& m) { m.files[p] = b; }, {p}});
    };
    auto append = [&](const std::string& p, size_t n, uint8_t seed) {
        Bytes b = data(n, seed);
        ops.push_back({"append " + p,
                       [p, b](DosSession& d) {
                           auto o = d.open(p, bios::APPEND);
                           return o.ok() && d.write(o.a, b).ok() && d.close(o.a).ok();
                       },
                       [p, b](Model& m) { m.files[p].insert(m.files[p].end(), b.begin(), b.end()); }, {p}});
    };
    auto update = [&](const std::string& p, uint16_t off, size_t n, uint8_t seed) {
        Bytes b = data(n, seed);
        ops.push_back({"update " + p,
                       [p, off, b](DosSession& d) {
                           auto o = d.open(p, bios::UPDATE);
                           return o.ok() && d.seek(o.a, off).ok() && d.write(o.a, b).ok() && d.close(o.a).ok();
                       },
                       [p, off, b](Model& m) {
                           Bytes& f = m.files[p];
                           if (f.size() < off + b.size()) f.resize(off + b.size());
                           std::copy(b.begin(), b.end(), f.begin() + off);
                       },
                       {p}});
    };
    auto kill = [&](const std::string& p) {
        ops.push_back({"kill " + p, [p](DosSession& d) { return d.kill(p).ok(); }, [p](Model& m) { m.files.erase(p); }, {p}});
    };
    auto rename = [&](const std::string& p, const std::string& to) {
        std::string dest = parent_of(p) == "/" ? "/" + to : parent_of(p) + "/" + to;
        ops.push_back({"rename " + p + " " + to, [p, to](DosSession& d) { return d.rename(p, to).ok(); },
                       [p, dest](Model& m) {
                           m.files[dest] = m.files[p];
                           m.files.erase(p);
                       },
                       {p, dest}});
    };

    mkdir("/A");
    write("/A/F1.TXT", 1500, 1);
    write("/F2.DAT", 3000, 2);
    mkdir("/A/B");
    write("/A/B/F3.TXT", 700, 3);
    write("/F2.DAT", 2100, 4); // truncate and rewrite
    rename("/A/F1.TXT", "G1.TXT");
    kill("/F2.DAT");
    write("/A/F1.TXT", 5000, 5); // recreate; freed clusters get reused
    append("/A/F1.TXT", 3000, 6);
    update("/A/G1.TXT", 100, 2000, 7); // grows it
    // Enough files to make /A grow past its first cluster (16 entries) more than once.
    for (int i = 0; i < 30; ++i) {
        char name[32];
        std::snprintf(name, sizeof name, "/A/N%02d.TXT", i);
        write(name, 10 + i, static_cast<uint8_t>(20 + i));
    }
    kill("/A/B/F3.TXT");
    rmdir("/A/B");
    for (int i = 0; i < 5; ++i) {
        char name[32];
        std::snprintf(name, sizeof name, "/A/N%02d.TXT", i * 3);
        kill(name);
    }
    write("/BIG.DAT", 20000, 8); // a chain long enough to span FAT sectors' worth of writes
    kill("/BIG.DAT");
    return ops;
}

} // namespace

TEST(dos_crash_at_every_disk_write_leaves_a_consistent_volume) {
    std::string base_path = build_image("crash_base.img", 4400, 1, {});
    CHECK(!base_path.empty());
    if (base_path.empty()) return;
    std::string work_path = std::string(PUGPUTER_TEST_BUILD_DIR) + "/crash_work.img";
    {
        std::ifstream in(base_path, std::ios::binary);
        std::ofstream out(work_path, std::ios::binary | std::ios::trunc);
        out << in.rdbuf();
    }
    std::ifstream bf(base_path, std::ios::binary | std::ios::ate);
    Bytes base(static_cast<size_t>(bf.tellg()));
    bf.seekg(0);
    bf.read(reinterpret_cast<char*>(base.data()), static_cast<std::streamsize>(base.size()));

    // Run the script through DOS, logging every block write and where each operation ended.
    std::vector<pugputer::SdCardDevice::WriteRecord> log;
    std::vector<Op> ops = build_script();
    std::vector<size_t> marks; // log length when op i had completed
    {
        DosSession d;
        CHECK(d.boot(PUGBIOS_S19_PATH, work_path.c_str()));
        d.sd.record_writes(&log);
        for (const Op& op : ops) {
            bool ok = op.run(d);
            CHECK(ok);
            if (!ok) {
                std::fprintf(stderr, "  script step failed: %s\n", op.what.c_str());
                return;
            }
            marks.push_back(log.size());
        }
        d.sd.record_writes(nullptr);
    }
    std::fprintf(stderr, "  (%zu operations, %zu block writes, %zu cut points)\n", ops.size(), log.size(), log.size() + 1);
    CHECK(log.size() > 100);

    // The disk after the whole script must be exactly what the model says (no cut).
    Bytes img = base;
    size_t applied = 0;
    size_t max_lost = 0;
    int reported = 0;
    for (size_t k = 0; k <= log.size(); ++k) {
        // img = base + first k writes
        for (; applied < k; ++applied)
            std::copy(log[applied].data.begin(), log[applied].data.end(), img.begin() + static_cast<size_t>(log[applied].lba) * 512);

        Fat16Volume v;
        if (!v.load_bytes(img)) {
            CHECK(false);
            return;
        }
        Walk w;
        bool ok = walk_dir(v, "/", 0, 0, w);
        if (!ok) {
            CHECK(false);
            if (reported++ < 3) std::fprintf(stderr, "  cut after write %zu: %s\n", k, w.err.c_str());
            continue;
        }

        // What the model says should be there: every op that completed by write k.
        size_t completed = 0;
        while (completed < ops.size() && marks[completed] <= k) ++completed;
        Model m;
        for (size_t i = 0; i < completed; ++i) ops[i].apply(m);
        std::set<std::string> flux;
        if (completed < ops.size()) flux = ops[completed].touched;
        flux.insert("/BASIC.COM"); // not part of the model

        bool content_ok = true;
        std::string why;
        for (const auto& f : m.files) {
            if (flux.count(f.first)) continue;
            auto it = w.found.find(f.first);
            if (it == w.found.end() || it->second.attr != 0x20) {
                content_ok = false;
                why = "missing file " + f.first;
                break;
            }
            if (v.read(it->second) != f.second) {
                content_ok = false;
                why = "wrong contents in " + f.first;
                break;
            }
        }
        if (content_ok)
            for (const auto& dname : m.dirs)
                if (!flux.count(dname) && (!w.found.count(dname) || w.found[dname].attr != 0x10)) {
                    content_ok = false;
                    why = "missing directory " + dname;
                    break;
                }
        if (content_ok)
            for (const auto& kv : w.found)
                if (!flux.count(kv.first) && !m.files.count(kv.first) && !m.dirs.count(kv.first)) {
                    content_ok = false;
                    why = "unexpected " + kv.first;
                    break;
                }
        if (!content_ok) {
            CHECK(false);
            if (reported++ < 3)
                std::fprintf(stderr, "  cut after write %zu (op %zu '%s' in flight): %s\n", k, completed,
                             completed < ops.size() ? ops[completed].what.c_str() : "-", why.c_str());
            continue;
        }

        // Lost clusters: in use, in no file.
        size_t lost = 0;
        for (uint32_t c = 2; c < v.clusters + 2; ++c)
            if (v.fat(c) != 0 && !w.used.count(c)) ++lost;
        max_lost = std::max(max_lost, lost);
        // Between operations nothing may be lost at all.
        if (std::find(marks.begin(), marks.end(), k) != marks.end() && lost != 0) {
            CHECK(false);
            if (reported++ < 3) std::fprintf(stderr, "  cut after write %zu (an operation boundary): %zu lost clusters\n", k, lost);
        }
    }
    std::fprintf(stderr, "  (at most %zu lost clusters at any cut)\n", max_lost);
    CHECK(max_lost <= 42); // only ever the clusters of the file being written or freed when the power went (20000 bytes = 40)

    // With no cut, nothing is lost at all and both FAT copies agree.
    Fat16Volume whole;
    CHECK(whole.load_bytes(img));
    CHECK(whole.fats_match());
    Walk w;
    CHECK(walk_dir(whole, "/", 0, 0, w));
    size_t lost = 0;
    for (uint32_t c = 2; c < whole.clusters + 2; ++c)
        if (whole.fat(c) != 0 && !w.used.count(c)) ++lost;
    CHECK(lost == 0);
}
