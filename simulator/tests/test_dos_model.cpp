// Model-based randomized test of the resident DOS: a long random sequence of file
// and directory operations (create/overwrite, append, update with gaps, read, kill,
// rename, mkdir, rmdir, chdir, listings, two files written in alternation, error
// probes) is run against DOS through its real BIOS call interface AND against a
// trivial in-memory model, and every result is compared. At the end, and now and
// then along the way, the disk image is checked with the independent FAT16 reader
// (fat16_reader.hpp): the directory tree and every file's bytes must match the
// model, no cluster may belong to two chains or leak, and the FAT copies must agree.
//
// Fixed seeds, so a failure reproduces exactly; the failure report names the seed and
// the operation number and prints the last few operations.
#include <algorithm>
#include <cstdio>
#include <map>
#include <random>
#include <set>
#include <string>
#include <vector>

#include "dos_session.hpp"
#include "fat16_reader.hpp"
#include "test_framework.hpp"

namespace {

using bios::APPEND;
using bios::READ;
using bios::UPDATE;
using bios::WRITE;
using Bytes = std::vector<uint8_t>;

struct Model {
    std::map<std::string, Bytes> files; // absolute path -> contents
    std::set<std::string> dirs;         // absolute paths of directories (never "/" itself)
    std::string cwd = "/";

    static std::string parent(const std::string& p) {
        size_t s = p.rfind('/');
        return s == 0 ? "/" : p.substr(0, s);
    }
    static std::string base(const std::string& p) { return p.substr(p.rfind('/') + 1); }
    static std::string join(const std::string& dir, const std::string& name) {
        return dir == "/" ? "/" + name : dir + "/" + name;
    }
    bool exists(const std::string& p) const { return files.count(p) || dirs.count(p) || p == "/"; }
    bool is_dir(const std::string& p) const { return dirs.count(p) || p == "/"; }
    // Names directly inside `dir`.
    std::vector<std::string> children(const std::string& dir) const {
        std::vector<std::string> out;
        for (const auto& f : files)
            if (parent(f.first) == dir) out.push_back(f.first);
        for (const auto& d : dirs)
            if (parent(d) == dir) out.push_back(d);
        return out;
    }
};

struct Runner {
    DosSession d;
    Model m;
    std::mt19937 rng;
    uint32_t seed;
    int op_no = 0;
    bool failed = false;
    std::vector<std::string> log;
    std::set<std::string> root_before; // the root's other entries (left by other tests): must not change
    uint32_t foreign_used = 0;          // clusters in use outside /RND before we started

    explicit Runner(uint32_t s) : rng(s), seed(s) {}

    uint32_t pick(uint32_t n) { return static_cast<uint32_t>(rng() % n); }

    void note(const std::string& s) {
        log.push_back(std::to_string(op_no) + ": " + s);
        if (log.size() > 12) log.erase(log.begin());
    }
    // Records a failed expectation once, with context, and lets the loop stop.
    bool expect(bool cond, const std::string& what) {
        if (!cond && !failed) {
            failed = true;
            std::fprintf(stderr, "  MODEL MISMATCH (seed %u, op %d): %s\n", seed, op_no, what.c_str());
            for (const auto& l : log) std::fprintf(stderr, "    %s\n", l.c_str());
        }
        return cond;
    }

    // ---- names and paths ----
    static const char* file_name(uint32_t i) {
        static const char* names[] = {"F1.TXT", "F2.TXT", "F3.BIN", "F4", "LONGNAME.DAT", "F6.C"};
        return names[i % 6];
    }
    static const char* dir_name(uint32_t i) {
        static const char* names[] = {"D1", "D2", "D3", "SUB"};
        return names[i % 4];
    }
    std::string pick_dir() {
        std::vector<std::string> all{"/RND"};
        for (const auto& x : m.dirs)
            if (x != "/RND" && x.rfind("/RND/", 0) == 0) all.push_back(x);
        return all[pick(static_cast<uint32_t>(all.size()))];
    }
    std::string pick_file_path() { return Model::join(pick_dir(), file_name(pick(6))); }
    std::vector<std::string> existing_files() const {
        std::vector<std::string> v;
        for (const auto& f : m.files)
            if (f.first.rfind("/RND/", 0) == 0) v.push_back(f.first);
        return v;
    }
    std::string pick_existing_file(bool* have) {
        auto v = existing_files();
        *have = !v.empty();
        return v.empty() ? "" : v[pick(static_cast<uint32_t>(v.size()))];
    }

    // How to spell an absolute path to DOS: absolute, or relative to the current
    // directory when it is under it; sometimes in lower case (DOS upper-cases).
    std::string spell(const std::string& abs) {
        std::string s = abs;
        if (m.cwd != "/" && abs.size() > m.cwd.size() && abs.compare(0, m.cwd.size() + 1, m.cwd + "/") == 0 && pick(2))
            s = abs.substr(m.cwd.size() + 1);
        else if (m.cwd == "/" && pick(3) == 0)
            s = abs.substr(1);
        else if (m.cwd != "/" && pick(6) == 0) {
            // via ".." to the root, e.g. "../../RND/F1.TXT"
            int depth = 0;
            for (char c : m.cwd) depth += c == '/';
            std::string up;
            for (int i = 0; i < depth; ++i) up += "../";
            s = up + abs.substr(1);
        }
        if (pick(4) == 0)
            for (char& c : s) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
        return s;
    }

    Bytes data_of(size_t n) { return pattern(n, static_cast<uint8_t>(pick(256))); }
    size_t pick_size() {
        static const size_t sizes[] = {0, 1, 7, 100, 511, 512, 513, 1000, 1023, 1024, 1025, 1500, 2047, 2048, 2049, 3000, 5000};
        if (pick(4) == 0) return pick(9000);
        return sizes[pick(sizeof(sizes) / sizeof(sizes[0]))];
    }

    bool write_chunks(uint8_t h, const Bytes& data) {
        size_t i = 0;
        while (i < data.size()) {
            size_t n = std::min<size_t>(data.size() - i, 1 + pick(pick(3) == 0 ? 700 : 200));
            Bytes chunk(data.begin() + i, data.begin() + i + n);
            if (!expect(d.write(h, chunk).ok(), "write failed")) return false;
            i += n;
        }
        return true;
    }

    // ---- operations ----
    void op_write_new() {
        std::string p = pick_file_path();
        Bytes data = data_of(pick_size());
        note("WRITE " + p + " len " + std::to_string(data.size()));
        auto o = d.open(spell(p), WRITE);
        if (!expect(o.ok(), "open WRITE failed, err " + std::to_string(o.a))) return;
        if (!write_chunks(o.a, data)) return;
        if (!expect(d.close(o.a).ok(), "close failed")) return;
        m.files[p] = data;
    }
    void op_append() {
        std::string p = pick_file_path();
        Bytes data = data_of(pick_size() % 2500);
        note("APPEND " + p + " len " + std::to_string(data.size()));
        auto o = d.open(spell(p), APPEND);
        if (!expect(o.ok(), "open APPEND failed, err " + std::to_string(o.a))) return;
        if (!write_chunks(o.a, data)) return;
        if (!expect(d.close(o.a).ok(), "close failed")) return;
        Bytes& f = m.files[p];
        f.insert(f.end(), data.begin(), data.end());
    }
    static void apply_write(Bytes& f, size_t off, const Bytes& data) {
        if (off > f.size()) f.resize(off, 0);
        if (off + data.size() > f.size()) f.resize(off + data.size());
        std::copy(data.begin(), data.end(), f.begin() + off);
    }
    void op_update() {
        bool have = false;
        std::string p = pick(4) ? pick_existing_file(&have) : pick_file_path();
        if (p.empty()) p = pick_file_path();
        Bytes& cur = m.files[p]; // (creates an empty entry if UPDATE will create the file)
        size_t off = pick(4) == 0 ? cur.size() + pick(700) : (cur.empty() ? 0 : pick(static_cast<uint32_t>(cur.size()) + 1));
        Bytes data = data_of(pick_size() % 2000);
        note("UPDATE " + p + " at " + std::to_string(off) + " len " + std::to_string(data.size()) + " (size " +
             std::to_string(cur.size()) + ")");
        auto o = d.open(spell(p), UPDATE);
        if (!expect(o.ok(), "open UPDATE failed, err " + std::to_string(o.a))) return;
        if (!expect(d.seek32(o.a, bios::FROM_START, static_cast<uint32_t>(off)).ok(), "seek failed")) return;
        if (!write_chunks(o.a, data)) return;
        if (!data.empty()) apply_write(cur, off, data);
        // Read it straight back through the same handle.
        if (!data.empty()) {
            if (!expect(d.seek(o.a, static_cast<uint16_t>(off)).ok(), "seek back failed")) return;
            bool ok = false;
            Bytes back = d.read(o.a, data.size(), &ok);
            if (!expect(ok && back == data, "update read-back differs")) return;
        }
        if (!expect(d.close(o.a).ok(), "close failed")) return;
    }
    void op_read() {
        bool have;
        std::string p = pick_existing_file(&have);
        if (!have) return;
        const Bytes& want = m.files[p];
        note("READ " + p + " (size " + std::to_string(want.size()) + ")");
        Bytes got;
        if (!expect(d.read_file(spell(p), got), "read_file failed")) return;
        if (!expect(got == want, "file contents differ")) return;
        // A random window through seek.
        auto o = d.open(spell(p), READ);
        if (!expect(o.ok(), "open READ failed")) return;
        size_t off = pick(static_cast<uint32_t>(want.size()) + 20);
        size_t n = 1 + pick(1500);
        if (!expect(d.seek(o.a, static_cast<uint16_t>(off)).ok(), "seek failed")) return;
        bool ok = false;
        Bytes part = d.read(o.a, n, &ok);
        Bytes exp;
        if (off < want.size()) exp.assign(want.begin() + off, want.begin() + std::min(want.size(), off + n));
        if (!expect(ok && part == exp, "windowed read differs at " + std::to_string(off))) return;
        auto st = d.stat(o.a);
        if (!expect(st.ok() && st.x == want.size(), "FSTAT size differs")) return;
        d.close(o.a);
        uint32_t sz = 0;
        if (!expect(d.stat_path(spell(p), &sz).ok() && sz == want.size(), "STAT size differs")) return;
    }
    void op_kill() {
        bool have;
        std::string p = pick_existing_file(&have);
        if (!have || pick(6) == 0) {
            std::string ghost = pick_file_path();
            if (m.files.count(ghost)) return;
            note("KILL (missing) " + ghost);
            auto r = d.kill(spell(ghost));
            expect(r.carry && r.a == bios::ERR_NOTFOUND, "kill of a missing file: wrong error");
            return;
        }
        note("KILL " + p);
        if (!expect(d.kill(spell(p)).ok(), "kill failed")) return;
        m.files.erase(p);
    }
    void op_rename() {
        bool have;
        std::string p = pick_existing_file(&have);
        if (!have) return;
        std::string nn = file_name(pick(6));
        std::string target = Model::join(Model::parent(p), nn);
        note("RENAME " + p + " -> " + nn);
        auto r = d.rename(spell(p), nn);
        if (target == p || m.files.count(target)) {
            expect(r.carry && r.a == bios::ERR_EXISTS, "rename onto an existing name: wrong result");
            return;
        }
        if (!expect(r.ok(), "rename failed, err " + std::to_string(r.a))) return;
        m.files[target] = m.files[p];
        m.files.erase(p);
    }
    void op_mkdir() {
        std::string parent = pick_dir();
        int depth = 0;
        for (char c : parent) depth += c == '/';
        std::string p = Model::join(parent, dir_name(pick(4)));
        if (depth >= 3 && !m.dirs.count(p)) return;
        note("MKDIR " + p);
        auto r = d.mkdir(spell(p));
        if (m.exists(p)) {
            expect(r.carry && r.a == bios::ERR_EXISTS, "mkdir of an existing name: wrong result");
            return;
        }
        if (!expect(r.ok(), "mkdir failed, err " + std::to_string(r.a))) return;
        m.dirs.insert(p);
    }
    void op_rmdir() {
        std::vector<std::string> cands;
        for (const auto& x : m.dirs)
            if (x != "/RND") cands.push_back(x);
        if (cands.empty()) return;
        std::string p = cands[pick(static_cast<uint32_t>(cands.size()))];
        bool empty = m.children(p).empty();
        if (p == m.cwd && !empty) return; // which error DOS reports first isn't specified
        note("RMDIR " + p);
        auto r = d.rmdir(spell(p));
        if (!empty) {
            expect(r.carry && r.a == bios::ERR_NOTEMPTY, "rmdir of a non-empty directory: wrong result");
        } else if (p == m.cwd) {
            expect(r.carry && r.a == bios::ERR_ISOPEN, "rmdir of the current directory: wrong result");
        } else {
            if (!expect(r.ok(), "rmdir failed, err " + std::to_string(r.a))) return;
            m.dirs.erase(p);
        }
    }
    void op_chdir() {
        std::vector<std::string> all{"/", "/RND"};
        for (const auto& x : m.dirs) all.push_back(x);
        std::string p = all[pick(static_cast<uint32_t>(all.size()))];
        note("CHDIR " + p);
        if (!expect(d.chdir(spell(p)).ok(), "chdir failed")) return;
        m.cwd = p;
        std::string got = d.getcwd();
        expect(got == p, "getcwd is " + got + ", model says " + p);
    }
    void op_chdir_dotdot() {
        if (m.cwd == "/") return;
        note("CHDIR ..");
        if (!expect(d.chdir("..").ok(), "chdir .. failed")) return;
        m.cwd = Model::parent(m.cwd);
        expect(d.getcwd() == m.cwd, "getcwd after .. differs");
    }
    void op_list() {
        std::string dir = pick_dir();
        note("LIST " + dir);
        bool ok = false;
        auto entries = d.list(spell(dir), &ok);
        if (!expect(ok, "opendir failed")) return;
        std::map<std::string, std::pair<bool, uint32_t>> got;
        for (const auto& e : entries) got[e.name] = {e.is_dir(), e.size};
        std::map<std::string, std::pair<bool, uint32_t>> want;
        for (const auto& c : m.children(dir)) {
            bool isd = m.dirs.count(c) != 0;
            want[Model::base(c)] = {isd, isd ? 0u : static_cast<uint32_t>(m.files[c].size())};
        }
        want["."] = {true, 0};
        want[".."] = {true, 0};
        expect(got == want, "directory listing of " + dir + " differs (" + std::to_string(got.size()) + " vs " +
                                std::to_string(want.size()) + " entries)");
    }
    void op_interleave() {
        std::string a = pick_file_path(), b = pick_file_path();
        if (a == b) return;
        note("INTERLEAVE " + a + " " + b);
        auto oa = d.open(spell(a), WRITE);
        if (!expect(oa.ok(), "open a failed")) return;
        auto ob = d.open(spell(b), WRITE);
        if (!expect(ob.ok(), "open b failed")) return;
        Bytes da, db;
        for (int i = 0; i < 6; ++i) {
            Bytes ca = data_of(1 + pick(900)), cb = data_of(1 + pick(900));
            if (!expect(d.write(oa.a, ca).ok() && d.write(ob.a, cb).ok(), "interleaved write failed")) return;
            da.insert(da.end(), ca.begin(), ca.end());
            db.insert(db.end(), cb.begin(), cb.end());
        }
        // Opening a file that is already open is refused.
        auto again = d.open(spell(a), READ);
        expect(again.carry && again.a == bios::ERR_ISOPEN, "double open not refused");
        if (pick(2)) {
            d.close(oa.a);
            d.close(ob.a);
        } else {
            d.close(ob.a);
            d.close(oa.a);
        }
        m.files[a] = da;
        m.files[b] = db;
    }
    void op_error_probes() {
        note("PROBES");
        std::string missing = Model::join(pick_dir(), "NOPE.TXT");
        if (!m.files.count(missing)) {
            auto r = d.open(spell(missing), READ);
            expect(r.carry && r.a == bios::ERR_NOTFOUND, "open of a missing file for READ: wrong result");
        }
        std::string dpath = pick_dir();
        auto r2 = d.open(spell(dpath), READ);
        expect(r2.carry && r2.a == bios::ERR_ISDIR, "open of a directory: wrong result");
        auto r3 = d.kill(spell(dpath));
        expect(r3.carry && r3.a == bios::ERR_ISDIR, "kill of a directory: wrong result");
        bool have;
        std::string f = pick_existing_file(&have);
        if (have) {
            auto r4 = d.chdir(spell(f));
            expect(r4.carry && r4.a == bios::ERR_NOTDIR, "chdir to a file: wrong result");
            auto r5 = d.open(spell(f + "/X.TXT"), WRITE);
            expect(r5.carry && r5.a == bios::ERR_NOTDIR, "file used as a directory: wrong result");
        }
    }

    // ---- the disk, seen by the independent reader ----
    struct Census {
        std::set<uint16_t> clusters;
        bool overlap = false;
    };
    void check_dir(const Fat16Volume& v, const std::string& path, uint16_t cluster, Census& c) {
        auto entries = v.entries(cluster);
        std::map<std::string, Fat16Volume::Entry> byname;
        for (const auto& e : entries) byname[e.name] = e;
        std::vector<std::string> kids = m.children(path);
        std::set<std::string> want;
        for (const auto& k : kids) want.insert(Model::base(k));
        if (path != "/") {
            want.insert(".");
            want.insert("..");
        } else {
            want = root_before;
            want.insert("RND");
        }
        std::set<std::string> have;
        for (const auto& e : entries) have.insert(e.name);
        std::string diff;
        for (const auto& n : have)
            if (!want.count(n)) diff += " +" + n;
        for (const auto& n : want)
            if (!have.count(n)) diff += " -" + n;
        if (!expect(have == want, "on-disk names of " + path + " differ from the model:" + diff)) return;
        if (path != "/") {
            uint16_t parent_cluster = 0;
            if (Model::parent(path) != "/") {
                Fat16Volume::Entry pe;
                if (v.find(Model::parent(path), pe)) parent_cluster = pe.cluster;
            }
            expect(byname["."].cluster == cluster && byname[".."].cluster == parent_cluster, ". / .. entries of " + path + " wrong");
        }
        for (const auto& kv : byname) {
            const auto& e = kv.second;
            if (e.name == "." || e.name == "..") continue;
            std::string child = Model::join(path, e.name);
            if (!(path == "/" && e.name != "RND")) {
                for (uint16_t cl : v.chain(e.cluster)) {
                    if (!c.clusters.insert(cl).second) c.overlap = true;
                }
            }
            if (path == "/" && e.name != "RND") continue; // not ours (and it isn't in the census)
            if (e.is_dir()) {
                if (!expect(m.dirs.count(child) != 0, "unexpected directory on disk: " + child)) return;
                check_dir(v, child, e.cluster, c);
            } else {
                auto it = m.files.find(child);
                if (!expect(it != m.files.end(), "unexpected file on disk: " + child)) return;
                expect(v.read(e) == it->second, "on-disk contents of " + child + " differ");
                uint32_t cbytes = v.sec_per_clus * 512;
                uint32_t need = (e.size + cbytes - 1) / cbytes;
                expect(v.chain(e.cluster).size() == need, "chain length of " + child + " is not what its size needs");
            }
        }
    }
    void check_disk() {
        Fat16Volume v;
        if (!expect(v.load(DISK_IMG_PATH), "can't load the image")) return;
        note("CHECK DISK");
        Census c;
        check_dir(v, "/", 0, c);
        if (failed) return;
        expect(!c.overlap, "a cluster belongs to two chains");
        expect(c.clusters.size() + foreign_used == v.clusters - v.free_clusters(), "used clusters (" + std::to_string(v.clusters - v.free_clusters()) +
                                                                          ") != clusters reachable from the tree (" +
                                                                          std::to_string(c.clusters.size()) + "): a leak");
        expect(v.fats_match(), "FAT copies differ");
    }

    void cleanup() {
        d.chdir("/");
        std::vector<std::string> fl;
        for (const auto& f : m.files) fl.push_back(f.first);
        for (const auto& f : fl) d.kill(f);
        std::vector<std::string> dl(m.dirs.rbegin(), m.dirs.rend()); // deepest / last first
        for (const auto& x : dl) d.rmdir(x);
    }
};

void run_model(uint32_t seed, int ops) {
    Runner r(seed);
    bool booted = r.d.boot(PUGBIOS_S19_PATH, DISK_IMG_PATH);
    CHECK(booted);
    if (!booted) return;
    // A clean scratch area (the shared disk may hold leftovers from a crashed run).
    r.d.chdir("/");
    for (const char* f : {"RND/F1.TXT", "RND/F2.TXT", "RND/F3.BIN", "RND/F4", "RND/LONGNAME.DAT", "RND/F6.C"}) r.d.kill(f);
    r.d.rmdir("RND");
    Fat16Volume before;
    bool loaded = before.load(DISK_IMG_PATH);
    CHECK(loaded);
    if (!loaded) return;
    uint32_t free_before = before.free_clusters();
    r.foreign_used = before.clusters - free_before;
    for (const auto& e : before.entries(0)) r.root_before.insert(e.name);
    bool made = r.d.mkdir("RND").ok();
    CHECK(made);
    if (!made) return;
    r.m.dirs.insert("/RND");
    r.m.cwd = "/";

    for (r.op_no = 1; r.op_no <= ops && !r.failed; ++r.op_no) {
        uint32_t k = r.pick(100);
        if (k < 18) r.op_write_new();
        else if (k < 28) r.op_append();
        else if (k < 42) r.op_update();
        else if (k < 58) r.op_read();
        else if (k < 64) r.op_kill();
        else if (k < 70) r.op_rename();
        else if (k < 76) r.op_mkdir();
        else if (k < 80) r.op_rmdir();
        else if (k < 86) r.op_chdir();
        else if (k < 88) r.op_chdir_dotdot();
        else if (k < 93) r.op_list();
        else if (k < 96) r.op_interleave();
        else r.op_error_probes();
        if (!r.failed && r.op_no % 40 == 0) r.check_disk();
    }
    if (!r.failed) r.check_disk();
    CHECK(!r.failed);

    // Put everything back and make sure nothing leaked.
    r.cleanup();
    Fat16Volume after;
    CHECK(after.load(DISK_IMG_PATH));
    CHECK(after.free_clusters() == free_before);
    CHECK(after.fats_match());
}

} // namespace

TEST(dos_model_random_operations_seed_1) { run_model(1, 250); }
TEST(dos_model_random_operations_seed_2) { run_model(2, 250); }
TEST(dos_model_random_operations_seed_3) { run_model(31337, 250); }
