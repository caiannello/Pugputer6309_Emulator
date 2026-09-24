// Big files and big volumes in the resident DOS: 32-bit sizes and positions (files
// well past 64KB), 32-bit block numbers (volumes past 32MB, so the SD device's
// high address word is exercised), the FAT sector cache and the free-cluster search
// hint under long allocation runs, and a full disk. Everything on the disk is also
// checked with the independent FAT16 reader (fat16_reader.hpp).
//
// The big volumes are built here (a 100MB image with two 33MB files already on it),
// not by mkdiskimg: reading a file at its end means DOS follows a chain of 16,000+
// clusters and asks the BIOS for blocks whose numbers need the high word.
#include <cstdio>
#include <string>
#include <vector>

#include "disk_images.hpp"
#include "dos_session.hpp"
#include "fat16_reader.hpp"
#include "pugputer/fat16_image.hpp"
#include "pugputer/srec_loader.hpp"
#include "test_framework.hpp"

namespace {

using bios::READ;
using bios::UPDATE;
using bios::WRITE;
using Bytes = std::vector<uint8_t>;

// Deterministic content as a function of the byte's offset, so a 33MB file can be
// checked at any offset without keeping a copy.
uint8_t bigbyte(uint32_t off, uint8_t seed) {
    return static_cast<uint8_t>(seed + off * 7 + (off >> 8) * 13 + (off >> 16) * 29 + (off >> 24) * 101);
}
Bytes bigdata(uint32_t from, size_t n, uint8_t seed) {
    Bytes v(n);
    for (size_t i = 0; i < n; ++i) v[i] = bigbyte(from + static_cast<uint32_t>(i), seed);
    return v;
}

// The 100MB volume with LOW.BIN and HIGH.BIN on it (built once per run).
const std::string& big_volume() {
    static std::string path;
    if (path.empty()) {
        pugputer::Fat16File low, high;
        low.name = "LOW.BIN";
        low.data = bigdata(0, 33u * 1024 * 1024, 1);
        high.name = "HIGH.BIN";
        high.data = bigdata(0, 33u * 1024 * 1024, 2);
        path = build_image("bigvolume.img", 204800, 4, {std::move(low), std::move(high)});
    }
    return path;
}

// Reads n bytes at `off` from an open file and compares with the pattern.
bool check_at(DosSession& d, uint8_t h, uint32_t off, size_t n, uint8_t seed) {
    auto r = d.seek32(h, bios::FROM_START, off);
    if (!r.ok() || r.x != (off >> 16) || r.y != (off & 0xFFFF)) return false;
    bool ok = false;
    Bytes got = d.read(h, n, &ok);
    return ok && got == bigdata(off, n, seed);
}

} // namespace

TEST(dos_big_volume_reads_files_across_the_64k_block_boundary_and_the_high_address_word) {
    const std::string& img = big_volume();
    CHECK(!img.empty());
    if (img.empty()) return;
    Fat16Volume vol;
    CHECK(vol.load(img.c_str()));
    CHECK(vol.total_sectors == 204800 && vol.total_sectors > 65535);
    CHECK(vol.cluster_lba(vol.clusters + 1) > 0x20000); // some cluster's block number needs bits 17+

    DosSession d;
    CHECK(d.boot(PUGBIOS_S19_PATH, img.c_str()));
    uint32_t size = 0;
    CHECK(d.stat_path("LOW.BIN", &size).ok() && size == 33u * 1024 * 1024);
    CHECK(d.stat_path("HIGH.BIN", &size).ok() && size == 33u * 1024 * 1024);
    CHECK(d.stat_path("BASIC.COM", &size).ok() && size == 12296);

    Fat16Volume::Entry low, high;
    CHECK(vol.find("/LOW.BIN", low) && vol.find("/HIGH.BIN", high));
    // The file layout is what makes the test mean something: LOW.BIN crosses block
    // 65536 and HIGH.BIN lives beyond block 131072 (high word 2).
    auto lowchain = vol.chain(low.cluster), highchain = vol.chain(high.cluster);
    CHECK(vol.cluster_lba(lowchain.front()) < 0x10000 && vol.cluster_lba(lowchain.back()) >= 0x10000);
    CHECK(vol.cluster_lba(highchain.front()) >= 0x10000);
    CHECK(vol.cluster_lba(highchain.back()) >= 0x20000);

    auto lo = d.open("LOW.BIN", READ);
    CHECK(lo.ok());
    const uint32_t total = 33u * 1024 * 1024;
    for (uint32_t off : {0u, 1u, 511u, 65535u, 65536u, 65537u, 1000000u, 0x100000u, 16u * 1024 * 1024 + 7,
                         31u * 1024 * 1024, total - 4096, total - 100}) {
        bool ok = check_at(d, lo.a, off, off + 600 > total ? total - off : 600, 1);
        CHECK(ok);
        if (!ok) std::fprintf(stderr, "  LOW.BIN mismatch at %u\n", off);
    }
    // Read to the very end and past it.
    auto r = d.seek32(lo.a, bios::FROM_END, 0);
    CHECK(r.ok() && ((static_cast<uint32_t>(r.x) << 16) | r.y) == total);
    bool ok = false;
    CHECK(d.read(lo.a, 10, &ok).empty() && ok); // end of file: zero bytes, not an error
    d.close(lo.a);

    auto hi = d.open("HIGH.BIN", READ);
    CHECK(hi.ok());
    for (uint32_t off : {0u, 65536u, 0x123456u, 16u * 1024 * 1024, 32u * 1024 * 1024 + 12345, total - 700}) {
        bool ok2 = check_at(d, hi.a, off, 600, 2);
        CHECK(ok2);
        if (!ok2) std::fprintf(stderr, "  HIGH.BIN mismatch at %u\n", off);
    }
    d.close(hi.a);
}

TEST(dos_big_volume_new_files_land_beyond_block_131072_and_survive) {
    const std::string& img = big_volume();
    CHECK(!img.empty());
    if (img.empty()) return;
    // Work on a copy so other tests keep a pristine image.
    std::string work = std::string(PUGPUTER_TEST_BUILD_DIR) + "/bigvolume_work.img";
    {
        std::ifstream in(img, std::ios::binary);
        std::ofstream out(work, std::ios::binary | std::ios::trunc);
        out << in.rdbuf();
    }
    DosSession d;
    CHECK(d.boot(PUGBIOS_S19_PATH, work.c_str()));
    Fat16Volume before;
    CHECK(before.load(work.c_str()));

    const size_t n = 300 * 1000; // well past 64KB
    Bytes content = bigdata(0, n, 9);
    auto o = d.open("NEW.DAT", WRITE);
    CHECK(o.ok());
    for (size_t i = 0; i < n; i += 5000) {
        Bytes chunk(content.begin() + i, content.begin() + std::min(n, i + 5000));
        CHECK(d.write(o.a, chunk).ok());
    }
    auto st = d.stat(o.a);
    CHECK(st.ok() && st.x == (n & 0xFFFF) && d.be32(DosSession::kStatBuf) == n);
    CHECK(d.close(o.a).ok());

    uint32_t size = 0;
    CHECK(d.stat_path("NEW.DAT", &size).ok() && size == n);
    Bytes back;
    auto r = d.open("NEW.DAT", READ);
    CHECK(r.ok());
    bool same = true;
    for (size_t i = 0; i < n && same; i += 6000) {
        bool ok = false;
        Bytes part = d.read(r.a, 6000, &ok);
        same = ok && part == Bytes(content.begin() + i, content.begin() + std::min(n, i + 6000));
    }
    CHECK(same);
    d.close(r.a);

    Fat16Volume vol;
    CHECK(vol.load(work.c_str()));
    Fat16Volume::Entry e;
    CHECK(vol.find("/NEW.DAT", e) && e.size == n);
    auto chain = vol.chain(e.cluster);
    CHECK(chain.size() == (n + 2047) / 2048);
    CHECK(vol.cluster_lba(chain.front()) >= 0x20000); // the disk address needed the high word
    CHECK(vol.read(e) == content);
    CHECK(vol.fats_match());
    CHECK(before.free_clusters() - vol.free_clusters() == chain.size());

    // Deleting gives every cluster back.
    CHECK(d.kill("NEW.DAT").ok());
    Fat16Volume after;
    CHECK(after.load(work.c_str()));
    CHECK(after.free_clusters() == before.free_clusters());
    CHECK(after.fats_match());
}

TEST(dos_files_past_64kb_append_update_seek_gap_truncate_and_delete) {
    DosSession d;
    CHECK(d.boot(PUGBIOS_S19_PATH, DISK_IMG_PATH));
    d.kill("BIG.DAT");
    Fat16Volume before;
    CHECK(before.load(DISK_IMG_PATH));

    // Create 200,000 bytes with writes of odd sizes.
    Bytes model = bigdata(0, 200000, 3);
    auto o = d.open("BIG.DAT", WRITE);
    CHECK(o.ok());
    size_t at = 0;
    for (size_t chunk : {1u, 511u, 512u, 513u, 7000u, 5000u, 1u, 4096u}) {
        chunk = std::min(chunk, model.size() - at);
        CHECK(d.write(o.a, Bytes(model.begin() + at, model.begin() + at + chunk)).ok());
        at += chunk;
    }
    while (at < model.size()) {
        size_t chunk = std::min<size_t>(6000, model.size() - at);
        CHECK(d.write(o.a, Bytes(model.begin() + at, model.begin() + at + chunk)).ok());
        at += chunk;
    }
    CHECK(d.close(o.a).ok());

    // Append past 64KB, then update in the middle of it and far beyond the end
    // (the gap must read as zeros, even though the clusters held other data before).
    auto ap = d.open("BIG.DAT", bios::APPEND);
    CHECK(ap.ok());
    Bytes more = bigdata(200000, 5500, 3);
    CHECK(d.write(ap.a, more).ok());
    CHECK(d.close(ap.a).ok());
    model.insert(model.end(), more.begin(), more.end());

    auto up = d.open("BIG.DAT", UPDATE);
    CHECK(up.ok());
    Bytes mid(3000, 0xA5);
    CHECK(d.seek32(up.a, bios::FROM_START, 150000).ok());
    CHECK(d.write(up.a, mid).ok());
    std::copy(mid.begin(), mid.end(), model.begin() + 150000);
    CHECK(d.seek32(up.a, bios::FROM_START, 260000).ok()); // 51,000 bytes past the end
    Bytes tail(100, 0x5A);
    CHECK(d.write(up.a, tail).ok());
    model.resize(260000, 0);
    model.insert(model.end(), tail.begin(), tail.end());
    CHECK(d.stat(up.a).ok() && d.be32(DosSession::kStatBuf) == model.size());
    // Read back through the same handle, backwards then forwards.
    CHECK(d.seek32(up.a, bios::FROM_START, 199990).ok());
    bool ok = false;
    Bytes got = d.read(up.a, 200, &ok);
    CHECK(ok && got == Bytes(model.begin() + 199990, model.begin() + 200190));
    CHECK(d.seek32(up.a, bios::FROM_END, 0).ok());
    CHECK(d.close(up.a).ok());

    Fat16Volume vol;
    CHECK(vol.load(DISK_IMG_PATH));
    Fat16Volume::Entry e;
    CHECK(vol.find("/BIG.DAT", e) && e.size == model.size());
    {
        Bytes ondisk = vol.read(e);
        size_t bad = 0;
        while (bad < ondisk.size() && bad < model.size() && ondisk[bad] == model[bad]) ++bad;
        if (bad < model.size() || ondisk.size() != model.size())
            std::fprintf(stderr, "  first difference at %zu (disk size %zu, model %zu): disk %02X model %02X\n", bad, ondisk.size(),
                         model.size(), bad < ondisk.size() ? ondisk[bad] : 0, bad < model.size() ? model[bad] : 0);
        CHECK(ondisk == model);
    }
    CHECK(vol.chain(e.cluster).size() == (model.size() + 1023) / 1024); // 1KB clusters here
    CHECK(vol.fats_match());

    // Whole-file read through DOS agrees too.
    Bytes viaDos;
    CHECK(d.read_file("BIG.DAT", viaDos) && viaDos == model);

    // Truncate by opening for WRITE: every cluster comes back.
    auto tr = d.open("BIG.DAT", WRITE);
    CHECK(tr.ok() && d.close(tr.a).ok());
    Fat16Volume trunc;
    CHECK(trunc.load(DISK_IMG_PATH));
    CHECK(trunc.find("/BIG.DAT", e) && e.size == 0 && e.cluster == 0);
    CHECK(trunc.free_clusters() == before.free_clusters());
    CHECK(d.kill("BIG.DAT").ok());
}

TEST(dos_a_full_disk_fails_cleanly_and_leaks_nothing) {
    // A tiny volume (about 4,300 clusters of 512 bytes = 2MB).
    std::string img = build_image("smalldisk.img", 4400, 1, {});
    CHECK(!img.empty());
    if (img.empty()) return;
    DosSession d;
    CHECK(d.boot(PUGBIOS_S19_PATH, img.c_str()));
    Fat16Volume before;
    CHECK(before.load(img.c_str()));
    uint32_t free_before = before.free_clusters();
    CHECK(free_before > 4000 && free_before < 4400);

    auto o = d.open("FILL.DAT", WRITE);
    CHECK(o.ok());
    Bytes chunk = bigdata(0, 4096, 4);
    size_t written = 0;
    DosSession::Result r;
    for (int i = 0; i < 1000; ++i) {
        r = d.write(o.a, chunk);
        if (!r.ok()) break;
        written += chunk.size();
    }
    CHECK(!r.ok() && r.a == bios::ERR_NOSPACE);
    CHECK(written + 4096 > free_before * 512 && written <= free_before * 512); // every cluster went into the file
    d.close(o.a); // may report the failed sector, but must free the slot and finish

    // The file that did fit is intact, and the FAT is consistent.
    Fat16Volume vol;
    CHECK(vol.load(img.c_str()));
    Fat16Volume::Entry e;
    CHECK(vol.find("/FILL.DAT", e));
    CHECK(e.size >= written && e.size <= free_before * 512);
    Bytes disk = vol.read(e);
    CHECK(disk.size() == e.size);
    bool intact = true;
    for (size_t i = 0; i < disk.size() && intact; ++i) intact = disk[i] == bigbyte(static_cast<uint32_t>(i % 4096), 4);
    CHECK(intact);
    CHECK(vol.chain(e.cluster).size() * 512 >= e.size);
    CHECK(vol.free_clusters() == 0);
    CHECK(vol.fats_match());

    // Other work fails cleanly rather than corrupting: no room for a new file's data,
    // and deleting the big file gives everything back.
    auto o2 = d.open("SMALL.TXT", WRITE);
    if (o2.ok()) {
        auto w = d.write(o2.a, Bytes(600, 1));
        CHECK(!w.ok() && w.a == bios::ERR_NOSPACE);
        d.close(o2.a);
        d.kill("SMALL.TXT");
    } else {
        CHECK(o2.a == bios::ERR_NOSPACE); // (or refused up front)
    }
    CHECK(d.kill("FILL.DAT").ok());
    Fat16Volume after;
    CHECK(after.load(img.c_str()));
    CHECK(after.free_clusters() == free_before);
    CHECK(after.fats_match());
    // ... and the disk is usable again.
    CHECK(d.write_file("AGAIN.TXT", bigdata(0, 5000, 6)));
    Bytes again;
    CHECK(d.read_file("AGAIN.TXT", again) && again == bigdata(0, 5000, 6));
}
