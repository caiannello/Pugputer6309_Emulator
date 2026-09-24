// Subdirectories and paths in the resident DOS (B_MKDIR/RMDIR/CHDIR/GETCWD,
// path resolution in every file call, directory scans, STAT, FFLUSH), called
// straight through the BIOS's SWI2 interface via dos_session.hpp -- and, for what
// ends up on the disk, checked with an independent FAT16 reader
// (fat16_reader.hpp) that shares no code with DOS.
//
// disk.img is shared, so every test removes what it created (in the right order:
// files, then directories from the inside out) and checks nothing leaked.
#include <cstdio>
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

std::vector<uint8_t> bytes(const std::string& s) { return std::vector<uint8_t>(s.begin(), s.end()); }

// Best effort: kill each file, rmdir each directory, in the order given.
void wipe(DosSession& d, const std::vector<std::string>& files, const std::vector<std::string>& dirs) {
    d.chdir("/");
    for (const auto& f : files) d.kill(f);
    for (const auto& r : dirs) d.rmdir(r);
}

struct Volume {
    Fat16Volume v;
    bool load() { return v.load(DISK_IMG_PATH); }
};

bool has(const std::vector<DosSession::DirEntry>& list, const std::string& name, bool dir) {
    for (const auto& e : list)
        if (e.name == name) return e.is_dir() == dir;
    return false;
}

size_t count_named(const std::vector<DosSession::DirEntry>& list) {
    size_t n = 0;
    for (const auto& e : list)
        if (e.name != "." && e.name != "..") ++n;
    return n;
}

} // namespace

TEST(dos_dirs_mkdir_chdir_getcwd_and_dot_entries) {
    DosSession d;
    CHECK(d.boot(PUGBIOS_S19_PATH, DISK_IMG_PATH));
    wipe(d, {"F1.TXT"}, {"D1"});
    Volume before;
    CHECK(before.load());

    CHECK(d.getcwd() == "/");
    CHECK(d.mkdir("D1").ok());
    CHECK(d.mkdir("D1").carry && d.mkdir("D1").a == bios::ERR_EXISTS);
    bool ok = false;
    auto root = d.list("", &ok);
    CHECK(ok && has(root, "D1", true));

    CHECK(d.chdir("D1").ok());
    CHECK(d.getcwd() == "/D1");
    auto sub = d.list(".", &ok);
    CHECK(ok && has(sub, ".", true) && has(sub, "..", true) && count_named(sub) == 0);
    CHECK(d.chdir("..").ok());
    CHECK(d.getcwd() == "/");
    CHECK(d.chdir("/D1").ok() && d.getcwd() == "/D1");
    CHECK(d.chdir("/").ok() && d.getcwd() == "/");
    CHECK(d.chdir("NOPE").carry && d.chdir("NOPE").a == bios::ERR_NOTFOUND);
    CHECK(d.getcwd() == "/"); // a failed CHDIR changes nothing
    CHECK(d.write_file("F1.TXT", bytes("x")));
    CHECK(d.chdir("F1.TXT").carry && d.chdir("F1.TXT").a == bios::ERR_NOTDIR);

    // What's on the disk: D1 is a directory whose "." names itself and ".." the root (0).
    Volume mid;
    CHECK(mid.load());
    Fat16Volume::Entry d1;
    CHECK(mid.v.find("/D1", d1) && d1.is_dir() && d1.cluster >= 2 && d1.size == 0);
    auto raw = mid.v.entries(d1.cluster);
    CHECK(raw.size() == 2 && raw[0].name == "." && raw[0].cluster == d1.cluster && raw[1].name == ".." &&
          raw[1].cluster == 0 && raw[0].is_dir() && raw[1].is_dir());
    CHECK(mid.v.fats_match());

    wipe(d, {"F1.TXT"}, {"D1"});
    Volume after;
    CHECK(after.load());
    CHECK(after.v.free_clusters() == before.v.free_clusters());
    CHECK(after.v.fats_match());
}

TEST(dos_dirs_files_in_subdirectories_and_relative_paths) {
    DosSession d;
    CHECK(d.boot(PUGBIOS_S19_PATH, DISK_IMG_PATH));
    wipe(d, {"D2/A.TXT", "D2/B.TXT", "A.TXT"}, {"D2"});

    std::vector<uint8_t> in_sub = pattern(1500, 3), in_root = pattern(700, 90);
    CHECK(d.mkdir("D2").ok());
    CHECK(d.write_file("D2/A.TXT", in_sub));
    CHECK(d.write_file("A.TXT", in_root)); // the same name in the root: a different file
    std::vector<uint8_t> back;
    CHECK(d.read_file("/D2/A.TXT", back) && back == in_sub);
    CHECK(d.read_file("/A.TXT", back) && back == in_root);
    CHECK(d.read_file("d2/a.txt", back) && back == in_sub);       // upper-cased for you
    CHECK(d.read_file("D2//A.TXT", back) && back == in_sub);       // doubled slash
    CHECK(d.read_file("./D2/./A.TXT", back) && back == in_sub);
    CHECK(d.read_file("D2/../A.TXT", back) && back == in_root);

    CHECK(d.chdir("D2").ok());
    CHECK(d.read_file("A.TXT", back) && back == in_sub);           // relative to the current directory
    CHECK(d.read_file("../A.TXT", back) && back == in_root);
    CHECK(d.read_file("/A.TXT", back) && back == in_root);
    CHECK(d.write_file("B.TXT", bytes("in D2")));
    bool ok = false;
    auto sub = d.list("", &ok);
    CHECK(ok && count_named(sub) == 2 && has(sub, "A.TXT", false) && has(sub, "B.TXT", false));
    CHECK(d.chdir("/").ok());
    auto root = d.list("/", &ok);
    CHECK(ok && !has(root, "B.TXT", false)); // B.TXT is not in the root

    // What the disk says: two different A.TXT files, and they hold what we wrote.
    Volume vol;
    CHECK(vol.load());
    Fat16Volume::Entry ea, eb, er;
    CHECK(vol.v.find("/D2/A.TXT", ea) && vol.v.read(ea) == in_sub);
    CHECK(vol.v.find("/D2/B.TXT", eb) && vol.v.read(eb) == bytes("in D2"));
    CHECK(vol.v.find("/A.TXT", er) && vol.v.read(er) == in_root);

    // Errors.
    CHECK(d.open("D2", READ).carry && d.open("D2", READ).a == bios::ERR_ISDIR);
    CHECK(d.open("/", READ).carry && d.open("/", READ).a == bios::ERR_ISDIR);
    CHECK(d.open("", READ).carry && d.open("", READ).a == bios::ERR_ISDIR);
    CHECK(d.open("..", READ).carry && d.open("..", READ).a == bios::ERR_ISDIR);
    CHECK(d.kill("D2").carry && d.kill("D2").a == bios::ERR_ISDIR);
    CHECK(d.open("D2/NOPE/X.TXT", WRITE).carry && d.open("D2/NOPE/X.TXT", WRITE).a == bios::ERR_NOTFOUND);
    CHECK(d.open("A.TXT/X.TXT", WRITE).carry && d.open("A.TXT/X.TXT", WRITE).a == bios::ERR_NOTDIR);
    CHECK(d.open("D2/NOPE.TXT", READ).carry && d.open("D2/NOPE.TXT", READ).a == bios::ERR_NOTFOUND);
    CHECK(d.kill("D2/NOPE.TXT").carry && d.kill("D2/NOPE.TXT").a == bios::ERR_NOTFOUND);

    wipe(d, {"D2/A.TXT", "D2/B.TXT", "A.TXT"}, {"D2"});
    Volume after;
    CHECK(after.load());
    Fat16Volume::Entry gone;
    CHECK(!after.v.find("/D2", gone));
}

TEST(dos_dirs_nested_directories_dotdot_rmdir_rules) {
    DosSession d;
    CHECK(d.boot(PUGBIOS_S19_PATH, DISK_IMG_PATH));
    wipe(d, {"N1/N2/LEAF.TXT"}, {"N1/N2/N3", "N1/N2", "N1"});
    Volume before;
    CHECK(before.load());

    CHECK(d.mkdir("N1").ok() && d.mkdir("N1/N2").ok() && d.mkdir("N1/N2/N3").ok());
    CHECK(d.mkdir("N1/NOPE/X").carry && d.mkdir("N1/NOPE/X").a == bios::ERR_NOTFOUND);
    CHECK(d.mkdir("").carry && d.mkdir("..").carry && d.mkdir("/").carry); // those exist already
    CHECK(d.chdir("N1/N2/N3").ok() && d.getcwd() == "/N1/N2/N3");
    CHECK(d.chdir("../..").ok() && d.getcwd() == "/N1");
    CHECK(d.chdir("/N1/N2/../N2/./N3").ok() && d.getcwd() == "/N1/N2/N3");
    CHECK(d.chdir("../../..").ok() && d.getcwd() == "/");
    CHECK(d.chdir("/..").ok() && d.getcwd() == "/"); // the root is its own parent
    CHECK(d.chdir("N1/").ok() && d.getcwd() == "/N1"); // a trailing slash is fine
    CHECK(d.chdir("/").ok());

    // The disk: each ".." names its parent's first cluster.
    Volume vol;
    CHECK(vol.load());
    Fat16Volume::Entry e1, e2, e3;
    CHECK(vol.v.find("/N1", e1) && vol.v.find("/N1/N2", e2) && vol.v.find("/N1/N2/N3", e3));
    CHECK(vol.v.entries(e3.cluster)[1].cluster == e2.cluster);
    CHECK(vol.v.entries(e2.cluster)[1].cluster == e1.cluster);
    CHECK(vol.v.entries(e1.cluster)[1].cluster == 0);

    // RMDIR rules.
    CHECK(d.write_file("N1/N2/LEAF.TXT", bytes("leaf")));
    CHECK(d.rmdir("N1").carry && d.rmdir("N1").a == bios::ERR_NOTEMPTY);
    CHECK(d.rmdir("N1/N2").carry && d.rmdir("N1/N2").a == bios::ERR_NOTEMPTY);
    CHECK(d.chdir("/N1/N2/N3").ok());
    CHECK(d.rmdir("/N1/N2/N3").carry && d.rmdir("/N1/N2/N3").a == bios::ERR_ISOPEN); // it's the current directory
    CHECK(d.chdir("/").ok());
    CHECK(d.rmdir("N1/N2/LEAF.TXT").carry && d.rmdir("N1/N2/LEAF.TXT").a == bios::ERR_NOTDIR);
    CHECK(d.rmdir("N1/GHOST").carry && d.rmdir("N1/GHOST").a == bios::ERR_NOTFOUND);
    CHECK(d.rmdir("/").carry && d.rmdir("..").carry);
    CHECK(d.kill("N1/N2/LEAF.TXT").ok());
    CHECK(d.rmdir("N1/N2/N3").ok());
    CHECK(d.rmdir("N1/N2").ok());
    CHECK(d.rmdir("N1").ok());
    CHECK(d.chdir("N1").carry);

    Volume after;
    CHECK(after.load());
    CHECK(after.v.free_clusters() == before.v.free_clusters()); // nothing leaked
    CHECK(after.v.fats_match());
}

TEST(dos_dirs_a_directory_grows_past_one_cluster_and_reuses_freed_entries) {
    DosSession d;
    CHECK(d.boot(PUGBIOS_S19_PATH, DISK_IMG_PATH));
    std::vector<std::string> names;
    for (int i = 0; i < 40; ++i) {
        char buf[16];
        std::snprintf(buf, sizeof buf, "BIG/F%02d.TXT", i);
        names.push_back(buf);
    }
    wipe(d, names, {"BIG"});
    Volume before;
    CHECK(before.load());

    // A cluster is 2 sectors = 32 entries, 2 of them "." and "..": 40 files need a second cluster.
    CHECK(d.mkdir("BIG").ok());
    for (int i = 0; i < 40; ++i) CHECK(d.write_file(names[i], bytes("n" + std::to_string(i))));
    bool ok = false;
    auto all = d.list("BIG", &ok);
    CHECK(ok && count_named(all) == 40);
    for (int i = 0; i < 40; ++i) {
        std::vector<uint8_t> back;
        CHECK(d.read_file(names[i], back) && back == bytes("n" + std::to_string(i)));
    }
    Volume mid;
    CHECK(mid.load());
    Fat16Volume::Entry big;
    CHECK(mid.v.find("/BIG", big));
    CHECK(mid.v.chain(big.cluster).size() == 2); // the directory really is two clusters long
    CHECK(mid.v.entries(big.cluster).size() == 42);

    // Delete every other file, then add new ones: they take the freed slots, so it doesn't grow again.
    for (int i = 0; i < 40; i += 2) CHECK(d.kill(names[i]).ok());
    CHECK(count_named(d.list("BIG")) == 20);
    for (int i = 0; i < 20; ++i) {
        char buf[16];
        std::snprintf(buf, sizeof buf, "BIG/G%02d.TXT", i);
        CHECK(d.write_file(buf, bytes("g")));
        names.push_back(buf);
    }
    CHECK(count_named(d.list("BIG")) == 40);
    Volume mid2;
    CHECK(mid2.load());
    CHECK(mid2.v.chain(big.cluster).size() == 2);

    wipe(d, names, {"BIG"});
    Volume after;
    CHECK(after.load());
    CHECK(after.v.free_clusters() == before.v.free_clusters()); // RMDIR gave both clusters back
    CHECK(after.v.fats_match());
}

TEST(dos_dirs_rename_files_and_directories) {
    DosSession d;
    CHECK(d.boot(PUGBIOS_S19_PATH, DISK_IMG_PATH));
    wipe(d, {"R1/A.TXT", "R1/B.TXT", "R2/A.TXT", "R2/B.TXT", "TOP.TXT"}, {"R1", "R2"});

    CHECK(d.mkdir("R1").ok());
    CHECK(d.write_file("R1/A.TXT", bytes("aaa")));
    CHECK(d.write_file("R1/B.TXT", bytes("bbb")));
    CHECK(d.rename("R1/A.TXT", "C.TXT").ok());                       // stays in R1
    std::vector<uint8_t> back;
    CHECK(d.read_file("R1/C.TXT", back) && back == bytes("aaa"));
    CHECK(d.open("R1/A.TXT", READ).carry);
    CHECK(d.rename("R1/C.TXT", "B.TXT").carry && d.rename("R1/C.TXT", "B.TXT").a == bios::ERR_EXISTS);
    CHECK(d.rename("R1/C.TXT", "SUB/X.TXT").carry && d.rename("R1/C.TXT", "SUB/X.TXT").a == bios::ERR_BADPATH);
    CHECK(d.rename("R1/C.TXT", "TOOLONGNAME.TXT").carry);
    CHECK(d.rename("R1/NOPE.TXT", "X.TXT").carry && d.rename("R1/NOPE.TXT", "X.TXT").a == bios::ERR_NOTFOUND);
    CHECK(d.rename("R1/C.TXT", "A.TXT").ok());

    auto held = d.open("R1/A.TXT", READ);
    CHECK(held.ok());
    CHECK(d.rename("R1/A.TXT", "Z.TXT").carry && d.rename("R1/A.TXT", "Z.TXT").a == bios::ERR_ISOPEN);
    CHECK(d.close(held.a).ok());

    // A directory can be renamed; its contents come along, and its ".." still points home.
    CHECK(d.rename("R1", "R2").ok());
    CHECK(d.read_file("R2/A.TXT", back) && back == bytes("aaa"));
    CHECK(d.open("R1/A.TXT", READ).carry && d.open("R1/A.TXT", READ).a == bios::ERR_NOTFOUND);
    CHECK(d.chdir("R2").ok() && d.getcwd() == "/R2");
    CHECK(d.chdir("..").ok() && d.getcwd() == "/");
    CHECK(d.write_file("TOP.TXT", bytes("t")));
    CHECK(d.rename("TOP.TXT", "R2").carry && d.rename("TOP.TXT", "R2").a == bios::ERR_EXISTS); // a directory's name is taken too

    wipe(d, {"R2/A.TXT", "R2/B.TXT", "TOP.TXT"}, {"R2"});
}

TEST(dos_dirs_path_syntax_is_checked) {
    DosSession d;
    CHECK(d.boot(PUGBIOS_S19_PATH, DISK_IMG_PATH));
    wipe(d, {"OK.TXT", "NOEXT"}, {});

    for (const char* bad : {"TOOLONGNAME.TXT", "A.TOOL", "A..B", "A B.TXT", "A*B.TXT", "A?.TXT", "A:B.TXT", ".HIDDEN",
                            "A.B.C", "A B/F.TXT", "A|B", "A\\B"}) {
        auto r = d.open(bad, WRITE);
        if (!(r.carry && r.a == bios::ERR_BADPATH)) std::fprintf(stderr, "  '%s' should be BADPATH, got a=%d carry=%d\n", bad, r.a, r.carry);
        CHECK(r.carry && r.a == bios::ERR_BADPATH);
    }
    // Valid but unusual names.
    CHECK(d.write_file("OK.TXT", bytes("1")));
    CHECK(d.write_file("NOEXT", bytes("2")));            // no extension
    CHECK(d.write_file("noext.", bytes("3")));           // a trailing dot means the same: no extension
    std::vector<uint8_t> back;
    CHECK(d.read_file("NOEXT", back) && back == bytes("3"));
    CHECK(d.write_file("A-B_C~1.$$$", bytes("4")));
    CHECK(d.read_file("a-b_c~1.$$$", back) && back == bytes("4"));
    CHECK(d.kill("A-B_C~1.$$$").ok());
    CHECK(d.kill("NOEXT").ok() && d.kill("OK.TXT").ok());
}

TEST(dos_dirs_scan_handles_are_independent_and_limited) {
    DosSession d;
    CHECK(d.boot(PUGBIOS_S19_PATH, DISK_IMG_PATH));
    wipe(d, {"S1/X1.TXT", "S1/X2.TXT", "S2/Y1.TXT", "S2/Y2.TXT", "S2/Y3.TXT"}, {"S1", "S2"});
    CHECK(d.mkdir("S1").ok() && d.mkdir("S2").ok());
    for (const char* f : {"S1/X1.TXT", "S1/X2.TXT", "S2/Y1.TXT", "S2/Y2.TXT", "S2/Y3.TXT"}) CHECK(d.write_file(f, bytes("z")));

    // Read two directories in lock step, and open a file between reads.
    auto h1 = d.opendir("S1"), h2 = d.opendir("S2");
    CHECK(h1.ok() && h2.ok() && h1.a != h2.a);
    DosSession::DirEntry e;
    std::vector<std::string> n1, n2;
    for (int i = 0; i < 5; ++i) {
        if (d.readdir(h1.a, e) && e.name[0] != '.') n1.push_back(e.name);
        auto f = d.open("S1/X1.TXT", READ);
        CHECK(f.ok());
        CHECK(d.close(f.a).ok());
        if (d.readdir(h2.a, e) && e.name[0] != '.') n2.push_back(e.name);
    }
    CHECK((n1 == std::vector<std::string>{"X1.TXT", "X2.TXT"}));
    CHECK((n2 == std::vector<std::string>{"Y1.TXT", "Y2.TXT", "Y3.TXT"}));
    uint8_t err = 0;
    CHECK(!d.readdir(h1.a, e, &err) && err == bios::ERR_EOF);
    CHECK(!d.readdir(h1.a, e, &err) && err == bios::ERR_EOF); // and it stays at the end
    CHECK(d.closedir(h1.a).ok() && d.closedir(h2.a).ok());
    CHECK(d.readdir(h1.a, e, &err) == false && err == bios::ERR_BADDEV); // closed
    CHECK(d.closedir(h1.a).carry && d.closedir(h1.a).a == bios::ERR_BADDEV);
    CHECK(d.closedir(bios::NDIRS).carry);

    // Only NDIRS at once.
    std::vector<uint8_t> hs;
    for (int i = 0; i < bios::NDIRS; ++i) {
        auto h = d.opendir("/");
        CHECK(h.ok());
        hs.push_back(h.a);
    }
    auto extra = d.opendir("/");
    CHECK(extra.carry && extra.a == bios::ERR_NOSLOT);
    CHECK(d.closedir(hs[1]).ok());
    CHECK(d.opendir("/").ok());
    for (size_t i = 0; i < hs.size(); ++i) d.closedir(hs[i]);
    for (int i = 0; i < bios::NDIRS; ++i) d.closedir(static_cast<uint8_t>(i));

    CHECK(d.opendir("S1/X1.TXT").carry && d.opendir("S1/X1.TXT").a == bios::ERR_NOTDIR);
    CHECK(d.opendir("NOPE").carry && d.opendir("NOPE").a == bios::ERR_NOTFOUND);
    wipe(d, {"S1/X1.TXT", "S1/X2.TXT", "S2/Y1.TXT", "S2/Y2.TXT", "S2/Y3.TXT"}, {"S1", "S2"});
}

TEST(dos_dirs_stat_fstat_seek_whence_and_flush) {
    DosSession d;
    CHECK(d.boot(PUGBIOS_S19_PATH, DISK_IMG_PATH));
    wipe(d, {"T1/F.DAT"}, {"T1"});
    CHECK(d.mkdir("T1").ok());

    uint32_t size = 99;
    uint8_t attr = 0;
    CHECK(d.stat_path("/", &size, &attr).ok() && attr == bios::ATTR_DIR && size == 0);
    CHECK(d.stat_path("T1", &size, &attr).ok() && (attr & bios::ATTR_DIR) && size == 0);
    CHECK(d.stat_path("T1/..", &size, &attr).ok() && (attr & bios::ATTR_DIR));
    CHECK(d.stat_path("NOPE").carry && d.stat_path("NOPE").a == bios::ERR_NOTFOUND);
    CHECK(d.write_file("T1/F.DAT", pattern(1000, 5)));
    CHECK(d.stat_path("T1/F.DAT", &size, &attr).ok() && size == 1000 && !(attr & bios::ATTR_DIR));

    auto o = d.open("T1/F.DAT", UPDATE);
    CHECK(o.ok());
    // Seek by whence.
    CHECK(d.seek32(o.a, bios::FROM_END, 0).ok() && d.stat(o.a).y == 1000);
    auto r = d.seek32(o.a, bios::FROM_START, 10);
    CHECK(r.ok() && r.x == 0 && r.y == 10);
    r = d.seek32(o.a, bios::FROM_CUR, 5);
    CHECK(r.ok() && r.y == 15);
    r = d.seek32(o.a, bios::FROM_END, 20);
    CHECK(r.ok() && r.y == 1020);
    r = d.seek32(o.a, bios::FROM_START, 0x10000);                     // positions are 32-bit now
    CHECK(r.ok() && r.x == 1 && r.y == 0);
    r = d.seek32(o.a, bios::FROM_CUR, 0xFFFF);
    CHECK(r.ok() && r.x == 1 && r.y == 0xFFFF);
    r = d.seek32(o.a, bios::FROM_START, 0xFFFFFFFFu);
    CHECK(r.ok() && r.x == 0xFFFF && r.y == 0xFFFF);
    CHECK(d.seek32(o.a, bios::FROM_CUR, 1).carry && d.seek32(o.a, bios::FROM_CUR, 1).a == bios::ERR_TOOBIG); // past 32 bits
    CHECK(d.seek32(o.a, bios::FROM_END, 0xFFFFFFFFu).carry);              // 1000 + 4G-1 overflows
    CHECK(d.seek32(o.a, 9, 0).carry && d.seek32(o.a, 9, 0).a == bios::ERR_BADMODE);

    // FSTAT's 16 bytes.
    CHECK(d.seek32(o.a, bios::FROM_START, 300).ok());
    CHECK(d.stat(o.a).ok());
    CHECK(d.be32(DosSession::kStatBuf) == 1000 && d.be32(DosSession::kStatBuf + 4) == 300);
    CHECK(d.bus.ram()[DosSession::kStatBuf + 9] == UPDATE);

    // FFLUSH updates the directory entry while the file stays open.
    CHECK(d.seek32(o.a, bios::FROM_END, 0).ok());
    CHECK(d.write(o.a, pattern(500, 1)).ok());
    Fat16Volume::Entry e;
    {
        Volume v;
        CHECK(v.load() && v.v.find("/T1/F.DAT", e));
        CHECK(e.size == 1000); // not yet: the size is only written at close
    }
    CHECK(d.flush(o.a).ok());
    {
        Volume v;
        CHECK(v.load() && v.v.find("/T1/F.DAT", e));
        CHECK(e.size == 1500);
        std::vector<uint8_t> want = pattern(1000, 5), more = pattern(500, 1);
        want.insert(want.end(), more.begin(), more.end());
        CHECK(v.v.read(e) == want); // and the data itself is on the disk
    }
    CHECK(d.flush(0xFF).ok()); // all files
    CHECK(d.flush(7).carry && d.flush(7).a == bios::ERR_BADDEV);
    CHECK(d.close(o.a).ok());
    CHECK(d.call(bios::B_DOS_VERSION).a == 0x20);

    wipe(d, {"T1/F.DAT"}, {"T1"});
}

TEST(dos_dirs_survive_a_reboot_and_the_current_directory_starts_at_the_root) {
    {
        DosSession d;
        CHECK(d.boot(PUGBIOS_S19_PATH, DISK_IMG_PATH));
        wipe(d, {"P1/P2/KEEP.TXT"}, {"P1/P2", "P1"});
        CHECK(d.mkdir("P1").ok() && d.mkdir("P1/P2").ok());
        CHECK(d.write_file("P1/P2/KEEP.TXT", pattern(2500, 12)));
        CHECK(d.chdir("P1/P2").ok() && d.getcwd() == "/P1/P2");
    }
    {
        DosSession d; // a fresh boot: nothing carried over in RAM
        CHECK(d.boot(PUGBIOS_S19_PATH, DISK_IMG_PATH));
        CHECK(d.getcwd() == "/");
        std::vector<uint8_t> back;
        CHECK(d.read_file("P1/P2/KEEP.TXT", back) && back == pattern(2500, 12));
        CHECK(d.chdir("P1/P2").ok() && d.getcwd() == "/P1/P2");
        wipe(d, {"P1/P2/KEEP.TXT"}, {"P1/P2", "P1"});
        CHECK(d.getcwd() == "/");
    }
}

TEST(dos_fat_copies_stay_in_sync_after_file_activity) {
    DosSession d;
    CHECK(d.boot(PUGBIOS_S19_PATH, DISK_IMG_PATH));
    wipe(d, {"FAT1.DAT", "FAT2.DAT"}, {});
    Volume before;
    CHECK(before.load());
    CHECK(d.write_file("FAT1.DAT", pattern(6000, 1)));   // allocates a chain
    CHECK(d.write_file("FAT2.DAT", pattern(3000, 2)));
    CHECK(d.write_file("FAT1.DAT", pattern(100, 3)));    // truncates and frees
    Volume mid;
    CHECK(mid.load());
    CHECK(mid.v.fats_match());
    wipe(d, {"FAT1.DAT", "FAT2.DAT"}, {});
    Volume after;
    CHECK(after.load());
    CHECK(after.v.fats_match());
    CHECK(after.v.free_clusters() == before.v.free_clusters());
}
