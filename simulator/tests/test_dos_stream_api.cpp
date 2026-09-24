// Tests for the byte-stream half of the resident DOS API (B_FGETC/FPUTC/FREAD/
// FWRITE/FSEEK_NAME/FSTAT_NAME, and the append/update open modes), called
// straight through the BIOS's SWI2 interface via dos_session.hpp. The scenarios
// are the ones BASIC's file statements will lean on: multi-sector and
// multi-cluster files, several files open and interleaved at once, appending
// at sector/cluster boundaries, in-place update, and seeking past the end
// (which must never expose stale bytes from a previous file's clusters).
#include <cstdio>
#include <string>
#include <vector>

#include "dos_session.hpp"
#include "test_framework.hpp"

namespace {

using bios::APPEND;
using bios::READ;
using bios::UPDATE;
using bios::WRITE;

std::vector<uint8_t> bytes(const std::string& s) { return std::vector<uint8_t>(s.begin(), s.end()); }

void kill_all(DosSession& d, std::initializer_list<const char*> names) {
    for (const char* n : names) d.kill(n); // "not found" is fine
}

bool same(const std::vector<uint8_t>& a, const std::vector<uint8_t>& b, const char* what) {
    if (a == b) return true;
    size_t i = 0;
    while (i < a.size() && i < b.size() && a[i] == b[i]) ++i;
    std::fprintf(stderr, "  %s: differ (sizes %zu vs %zu), first difference at offset %zu\n", what, a.size(), b.size(),
                 i);
    return false;
}

} // namespace

TEST(dos_stream_write_then_read_bytes_and_eof) {
    DosSession d;
    CHECK(d.boot(PUGBIOS_S19_PATH, DISK_IMG_PATH));
    kill_all(d, {"S1.DAT"});

    auto o = d.open("S1.DAT", WRITE);
    CHECK(o.ok());
    CHECK(d.write(o.a, bytes("HELLO")).ok());
    CHECK(d.putc(o.a, '!').ok());
    auto st = d.stat(o.a);
    CHECK(st.ok() && st.x == 6 && st.y == 6); // size 6, position 6
    CHECK(d.close(o.a).ok());

    o = d.open("S1.DAT", READ);
    CHECK(o.ok());
    st = d.stat(o.a);
    CHECK(st.ok() && st.x == 6 && st.y == 0);
    bool ok = false;
    CHECK(same(d.read(o.a, 100, &ok), bytes("HELLO!"), "short read at EOF"));
    CHECK(ok);
    auto g = d.getc(o.a);
    CHECK(g.carry && g.a == bios::ERR_EOF);
    CHECK(d.close(o.a).ok());

    // A zero-length file is legal and reads as immediate EOF.
    kill_all(d, {"S1E.DAT"});
    o = d.open("S1E.DAT", WRITE);
    CHECK(o.ok());
    CHECK(d.close(o.a).ok());
    o = d.open("S1E.DAT", READ);
    CHECK(o.ok());
    g = d.getc(o.a);
    CHECK(g.carry && g.a == bios::ERR_EOF);
    CHECK(d.close(o.a).ok());
    kill_all(d, {"S1.DAT", "S1E.DAT"});
}

TEST(dos_stream_multi_sector_multi_cluster_round_trip_and_survives_reboot) {
    std::vector<uint8_t> data = pattern(3000, 5); // crosses sectors and 1KB clusters
    {
        DosSession d;
        CHECK(d.boot(PUGBIOS_S19_PATH, DISK_IMG_PATH));
        kill_all(d, {"S2.DAT"});
        CHECK(d.write_file("S2.DAT", data));
        std::vector<uint8_t> back;
        CHECK(d.read_file("S2.DAT", back));
        CHECK(same(back, data, "same-session read-back"));
    }
    {
        // A fresh boot sees only what's really on disk: proves the last
        // (partial) sector, the FAT chain and the directory size all landed.
        DosSession d;
        CHECK(d.boot(PUGBIOS_S19_PATH, DISK_IMG_PATH));
        std::vector<uint8_t> back;
        CHECK(d.read_file("S2.DAT", back));
        CHECK(same(back, data, "read-back after reboot"));
        kill_all(d, {"S2.DAT"});
    }
}

TEST(dos_stream_two_files_open_and_interleaved) {
    DosSession d;
    CHECK(d.boot(PUGBIOS_S19_PATH, DISK_IMG_PATH));
    kill_all(d, {"S3A.DAT", "S3B.DAT"});
    std::vector<uint8_t> a = pattern(1700, 11), b = pattern(1700, 200);

    // Write both, alternating chunks -- each file must keep its own buffer.
    auto fa = d.open("S3A.DAT", WRITE), fb = d.open("S3B.DAT", WRITE);
    CHECK(fa.ok() && fb.ok() && fa.a != fb.a);
    for (size_t i = 0; i < a.size(); i += 100) {
        size_t n = std::min<size_t>(100, a.size() - i);
        CHECK(d.write(fa.a, std::vector<uint8_t>(a.begin() + i, a.begin() + i + n)).ok());
        CHECK(d.write(fb.a, std::vector<uint8_t>(b.begin() + i, b.begin() + i + n)).ok());
    }
    CHECK(d.close(fa.a).ok() && d.close(fb.a).ok());

    // Read both, alternating odd-sized chunks.
    fa = d.open("S3A.DAT", READ);
    fb = d.open("S3B.DAT", READ);
    CHECK(fa.ok() && fb.ok());
    std::vector<uint8_t> ra, rb;
    for (int i = 0; i < 100; ++i) {
        bool ok = false;
        auto ca = d.read(fa.a, 37, &ok);
        CHECK(ok);
        ra.insert(ra.end(), ca.begin(), ca.end());
        auto cb = d.read(fb.a, 41, &ok);
        CHECK(ok);
        rb.insert(rb.end(), cb.begin(), cb.end());
    }
    // Finish off whatever's left of each.
    bool ok = false;
    for (auto& c : d.read(fa.a, 2000, &ok)) ra.push_back(c);
    for (auto& c : d.read(fb.a, 2000, &ok)) rb.push_back(c);
    CHECK(same(ra, a, "file A"));
    CHECK(same(rb, b, "file B"));
    CHECK(d.close(fa.a).ok() && d.close(fb.a).ok());
    kill_all(d, {"S3A.DAT", "S3B.DAT"});
}

TEST(dos_stream_append_including_sector_and_cluster_boundaries) {
    DosSession d;
    CHECK(d.boot(PUGBIOS_S19_PATH, DISK_IMG_PATH));
    kill_all(d, {"S4A.DAT", "S4B.DAT", "S4C.DAT", "S4D.DAT"});

    // Plain append.
    CHECK(d.write_file("S4A.DAT", bytes("ABC")));
    auto o = d.open("S4A.DAT", APPEND);
    CHECK(o.ok());
    auto st = d.stat(o.a);
    CHECK(st.x == 3 && st.y == 3); // positioned at the end
    CHECK(d.write(o.a, bytes("DEF")).ok());
    CHECK(d.close(o.a).ok());
    std::vector<uint8_t> back;
    CHECK(d.read_file("S4A.DAT", back));
    CHECK(same(back, bytes("ABCDEF"), "append small"));

    // Append exactly at a sector boundary (512) and at a cluster boundary (1024).
    for (auto [name, size] : {std::pair<const char*, size_t>{"S4B.DAT", 512}, {"S4C.DAT", 1024}}) {
        std::vector<uint8_t> base = pattern(size, 3);
        CHECK(d.write_file(name, base));
        o = d.open(name, APPEND);
        CHECK(o.ok());
        std::vector<uint8_t> tail = pattern(10, 99);
        CHECK(d.write(o.a, tail).ok());
        CHECK(d.close(o.a).ok());
        std::vector<uint8_t> expect = base;
        expect.insert(expect.end(), tail.begin(), tail.end());
        CHECK(d.read_file(name, back));
        CHECK(same(back, expect, name));
    }

    // Append creates a missing file.
    o = d.open("S4D.DAT", APPEND);
    CHECK(o.ok());
    CHECK(d.write(o.a, bytes("NEW")).ok());
    CHECK(d.close(o.a).ok());
    CHECK(d.read_file("S4D.DAT", back));
    CHECK(same(back, bytes("NEW"), "append creates"));
    kill_all(d, {"S4A.DAT", "S4B.DAT", "S4C.DAT", "S4D.DAT"});
}

TEST(dos_stream_update_in_place_and_zero_filled_gaps) {
    DosSession d;
    CHECK(d.boot(PUGBIOS_S19_PATH, DISK_IMG_PATH));
    kill_all(d, {"S5A.DAT", "S5B.DAT", "S5STALE.DAT"});

    // Seek past the end of a NEW file and write: everything before must read
    // as zeros -- even though the clusters we're handed still hold 0xFF from
    // a file we just deleted (stale data is the thing to catch here).
    CHECK(d.write_file("S5STALE.DAT", std::vector<uint8_t>(3000, 0xFF)));
    CHECK(d.kill("S5STALE.DAT").ok());
    auto o = d.open("S5A.DAT", UPDATE);
    CHECK(o.ok());
    CHECK(d.seek(o.a, 2500).ok());
    CHECK(d.putc(o.a, 'Z').ok());
    auto st = d.stat(o.a);
    CHECK(st.x == 2501 && st.y == 2501);
    CHECK(d.close(o.a).ok());
    std::vector<uint8_t> back;
    CHECK(d.read_file("S5A.DAT", back));
    std::vector<uint8_t> expect(2501, 0);
    expect[2500] = 'Z';
    CHECK(same(back, expect, "gap zero-fill"));

    // Update existing contents in place, including across a sector boundary
    // (512), a cluster boundary (1024), and past the old end (extends it).
    std::vector<uint8_t> base = pattern(2000, 40);
    CHECK(d.write_file("S5B.DAT", base));
    o = d.open("S5B.DAT", UPDATE);
    CHECK(o.ok());
    CHECK(d.seek(o.a, 700).ok());
    CHECK(d.write(o.a, bytes("XXXXX")).ok());
    CHECK(d.seek(o.a, 1020).ok());
    CHECK(d.write(o.a, bytes("0123456789")).ok());
    CHECK(d.seek(o.a, 508).ok());
    CHECK(d.write(o.a, bytes("SECT")).ok());
    CHECK(d.seek(o.a, 1990).ok());
    CHECK(d.write(o.a, bytes("--------------------------------")).ok()); // 32 bytes: ends at 2022
    // Reading in update mode sees what was just written (unflushed, or not).
    CHECK(d.seek(o.a, 698).ok());
    bool ok = false;
    CHECK(same(d.read(o.a, 9, &ok), bytes(std::string(reinterpret_cast<const char*>(&base[698]), 2) + "XXXXX" +
                                          std::string(reinterpret_cast<const char*>(&base[705]), 2)),
               "read-your-writes"));
    CHECK(d.close(o.a).ok());
    expect = base;
    auto put = [&](size_t at, const std::string& s) {
        if (expect.size() < at + s.size()) expect.resize(at + s.size());
        for (size_t i = 0; i < s.size(); ++i) expect[at + i] = static_cast<uint8_t>(s[i]);
    };
    put(700, "XXXXX");
    put(1020, "0123456789");
    put(508, "SECT");
    put(1990, "--------------------------------");
    CHECK(d.read_file("S5B.DAT", back));
    CHECK(same(back, expect, "in-place update"));
    kill_all(d, {"S5A.DAT", "S5B.DAT"});
}

TEST(dos_stream_read_mode_seek) {
    DosSession d;
    CHECK(d.boot(PUGBIOS_S19_PATH, DISK_IMG_PATH));
    kill_all(d, {"S6.DAT"});
    std::vector<uint8_t> data = pattern(2000, 17);
    CHECK(d.write_file("S6.DAT", data));

    auto o = d.open("S6.DAT", READ);
    CHECK(o.ok());
    bool ok = false;
    CHECK(same(d.read(o.a, 10, &ok), std::vector<uint8_t>(data.begin(), data.begin() + 10), "start"));
    CHECK(d.seek(o.a, 1500).ok()); // forward, into another cluster
    CHECK(same(d.read(o.a, 10, &ok), std::vector<uint8_t>(data.begin() + 1500, data.begin() + 1510), "forward"));
    CHECK(d.seek(o.a, 3).ok()); // backward, before the cached cluster
    CHECK(same(d.read(o.a, 10, &ok), std::vector<uint8_t>(data.begin() + 3, data.begin() + 13), "backward"));
    CHECK(d.seek(o.a, 1999).ok());
    CHECK(same(d.read(o.a, 5, &ok), std::vector<uint8_t>(data.begin() + 1999, data.end()), "last byte, short read"));
    CHECK(d.seek(o.a, 3000).ok()); // past the end: reads as EOF
    auto g = d.getc(o.a);
    CHECK(g.carry && g.a == bios::ERR_EOF);
    CHECK(d.stat(o.a).y == 3000);
    CHECK(d.close(o.a).ok());
    kill_all(d, {"S6.DAT"});
}

TEST(dos_stream_mode_and_handle_rules) {
    DosSession d;
    CHECK(d.boot(PUGBIOS_S19_PATH, DISK_IMG_PATH));
    kill_all(d, {"S7A.DAT", "S7B.DAT", "S7C.DAT", "S7D.DAT", "S7E.DAT", "S7F.DAT", "S7G.DAT", "S7H.DAT", "S7I.DAT",
                 "S7X.DAT"});
    CHECK(d.write_file("S7A.DAT", bytes("data")));

    // Mode enforcement.
    auto r = d.open("S7A.DAT", READ);
    CHECK(r.ok());
    CHECK(d.putc(r.a, 'x').carry && d.putc(r.a, 'x').a == bios::ERR_BADMODE);
    CHECK(d.close(r.a).ok());
    auto w = d.open("S7B.DAT", WRITE);
    CHECK(w.ok());
    CHECK(d.getc(w.a).carry && d.getc(w.a).a == bios::ERR_BADMODE);
    CHECK(d.seek(w.a, 0).carry && d.seek(w.a, 0).a == bios::ERR_BADMODE);
    bool ok = true;
    d.read(w.a, 4, &ok);
    CHECK(!ok);
    CHECK(d.close(w.a).ok());
    auto ap = d.open("S7B.DAT", APPEND);
    CHECK(ap.ok());
    CHECK(d.getc(ap.a).carry && d.getc(ap.a).a == bios::ERR_BADMODE);
    CHECK(d.seek(ap.a, 0).carry && d.seek(ap.a, 0).a == bios::ERR_BADMODE);
    CHECK(d.close(ap.a).ok());
    CHECK(d.open("S7A.DAT", 9).a == bios::ERR_BADMODE && d.open("S7A.DAT", 9).carry);

    // Missing file, bad filerefs.
    auto nf = d.open("S7X.DAT", READ);
    CHECK(nf.carry && nf.a == bios::ERR_NOTFOUND);
    CHECK(d.getc(bios::NFILES).carry && d.getc(bios::NFILES).a == bios::ERR_BADDEV); // out of range
    CHECK(d.getc(4).carry && d.getc(4).a == bios::ERR_BADDEV);  // in range but not open
    CHECK(d.close(4).carry && d.close(4).a == bios::ERR_BADDEV);

    // An open file can't be opened again, killed, or renamed.
    auto held = d.open("S7A.DAT", READ);
    CHECK(held.ok());
    CHECK(d.open("S7A.DAT", READ).carry && d.open("S7A.DAT", READ).a == bios::ERR_ISOPEN);
    CHECK(d.open("S7A.DAT", UPDATE).carry && d.open("S7A.DAT", UPDATE).a == bios::ERR_ISOPEN);
    CHECK(d.kill("S7A.DAT").carry && d.kill("S7A.DAT").a == bios::ERR_ISOPEN);
    CHECK(d.rename("S7A.DAT", "S7X.DAT").carry && d.rename("S7A.DAT", "S7X.DAT").a == bios::ERR_ISOPEN);
    CHECK(d.close(held.a).ok());
    CHECK(d.rename("S7A.DAT", "S7X.DAT").ok()); // fine once closed
    CHECK(d.rename("S7X.DAT", "S7A.DAT").ok());

    // Slot exhaustion: with all 8 files open, the next open fails cleanly,
    // and a slot freed by close is immediately reusable.
    std::vector<uint8_t> refs;
    const char* names[] = {"S7A.DAT", "S7B.DAT", "S7C.DAT", "S7D.DAT", "S7E.DAT", "S7G.DAT", "S7H.DAT", "S7I.DAT"};
    for (const char* n : names) {
        auto o = d.open(n, UPDATE);
        CHECK(o.ok());
        refs.push_back(o.a);
    }
    CHECK(refs.size() == static_cast<size_t>(bios::NFILES));
    auto ninth = d.open("S7F.DAT", WRITE);
    CHECK(ninth.carry && ninth.a == bios::ERR_NOSLOT);
    CHECK(d.close(refs[2]).ok());
    auto again = d.open("S7F.DAT", WRITE);
    CHECK(again.ok() && again.a == refs[2]);
    CHECK(d.close(again.a).ok());
    for (size_t i = 0; i < refs.size(); ++i)
        if (i != 2) CHECK(d.close(refs[i]).ok());
    kill_all(d, {"S7A.DAT", "S7B.DAT", "S7C.DAT", "S7D.DAT", "S7E.DAT", "S7F.DAT", "S7G.DAT", "S7H.DAT", "S7I.DAT",
                 "S7X.DAT"});
}

TEST(dos_stream_write_mode_truncates_existing_file) {
    DosSession d;
    CHECK(d.boot(PUGBIOS_S19_PATH, DISK_IMG_PATH));
    kill_all(d, {"S8.DAT"});
    CHECK(d.write_file("S8.DAT", pattern(3000, 1)));
    CHECK(d.write_file("S8.DAT", bytes("xy"))); // WRITE mode: truncates
    std::vector<uint8_t> back;
    CHECK(d.read_file("S8.DAT", back));
    CHECK(same(back, bytes("xy"), "truncated"));
    kill_all(d, {"S8.DAT"});
}

TEST(dos_readline_handles_cr_lf_and_crlf_terminators) {
    DosSession d;
    CHECK(d.boot(PUGBIOS_S19_PATH, DISK_IMG_PATH));
    kill_all(d, {"S9.TXT"});
    CHECK(d.write_file("S9.TXT", bytes("L1\r\nL2\r\n\r\nL3\nL4")));
    auto o = d.open("S9.TXT", READ);
    CHECK(o.ok());
    std::vector<std::string> lines;
    for (int i = 0; i < 6; ++i) {
        auto r = d.call(bios::B_READLINE, o.a, 0, DosSession::kData, 100);
        CHECK(r.ok());
        std::vector<uint8_t> got = d.peek(DosSession::kData, r.x);
        lines.emplace_back(got.begin(), got.end());
    }
    // CRLF reads as ordinary lines; the blank CRLF line is empty; LF alone
    // also terminates; past the end gives empty lines (X=0).
    CHECK(lines[0] == "L1" && lines[1] == "L2" && lines[2] == "" && lines[3] == "L3" && lines[4] == "L4" &&
          lines[5] == "");
    CHECK(d.close(o.a).ok());
    kill_all(d, {"S9.TXT"});
}

TEST(dos_readline_bare_lf_is_a_blank_line_and_bare_cr_is_a_terminator) {
    DosSession d;
    CHECK(d.boot(PUGBIOS_S19_PATH, DISK_IMG_PATH));
    kill_all(d, {"S9B.TXT"});
    // "A\n" "\n" "B\r" "C\r" "\r\n" "D": LF alone ends a line (and an empty LF
    // line is kept, not swallowed); a CR not followed by LF ends one without
    // eating the next byte; CR LF counts once.
    CHECK(d.write_file("S9B.TXT", bytes("A\n\nB\rC\r\r\nD")));
    auto o = d.open("S9B.TXT", READ);
    CHECK(o.ok());
    std::vector<std::string> lines;
    for (int i = 0; i < 6; ++i) {
        auto r = d.call(bios::B_READLINE, o.a, 0, DosSession::kData, 100);
        CHECK(r.ok());
        std::vector<uint8_t> got = d.peek(DosSession::kData, r.x);
        lines.emplace_back(got.begin(), got.end());
    }
    CHECK(lines[0] == "A" && lines[1] == "" && lines[2] == "B" && lines[3] == "C" && lines[4] == "" &&
          lines[5] == "D");
    // The position ends exactly at the end of the file (no step-back past it).
    CHECK(d.stat(o.a).x == 10 && d.stat(o.a).y == 10);
    CHECK(d.close(o.a).ok());
    kill_all(d, {"S9B.TXT"});
}

TEST(dos_directory_entry_reflects_final_size_and_cluster) {
    DosSession d;
    CHECK(d.boot(PUGBIOS_S19_PATH, DISK_IMG_PATH));
    kill_all(d, {"SA.DAT", "SB.DAT"});
    CHECK(d.write_file("SA.DAT", pattern(1234, 9)));
    auto o = d.open("SB.DAT", WRITE); // empty file: created, never written
    CHECK(o.ok());
    CHECK(d.close(o.a).ok());

    bool listed = false;
    bool found_a = false, found_b = false;
    for (const auto& e : d.list("", &listed)) {
        if (e.name == "SA.DAT") {
            found_a = true;
            CHECK(e.size == 1234 && !e.is_dir());
        }
        if (e.name == "SB.DAT") {
            found_b = true;
            CHECK(e.size == 0 && !e.is_dir());
        }
    }
    CHECK(listed && found_a && found_b);
    kill_all(d, {"SA.DAT", "SB.DAT"});
}
