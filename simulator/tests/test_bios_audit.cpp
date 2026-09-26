// BIOS robustness (step 7's audit): what the BIOS does when the hardware or a program
// misbehaves. SD failures (retries, no card, a card stuck BUSY, buffers that would
// spill into the ROM/I/O area), UART error flags, the S-record loader fed malformed or
// dangerous records, the disk-boot path given a corrupt boot sector or a card that dies
// mid-load, a crashing program (the BIOS recovers to the shell with the banks, direct
// page and stack put right), and how much stack a BIOS+DOS call needs.
#include <algorithm>
#include <cstdio>
#include <fstream>
#include <string>
#include <vector>

#include "basic309_session.hpp"
#include "disk_images.hpp"
#include "dos_session.hpp"
#include "test_framework.hpp"

namespace {

using Bytes = std::vector<uint8_t>;

bool has(const std::string& hay, const std::string& needle) { return hay.find(needle) != std::string::npos; }

void patch_image(const std::string& path, size_t offset, const Bytes& bytes) {
    std::fstream f(path, std::ios::in | std::ios::out | std::ios::binary);
    f.seekp(static_cast<std::streamoff>(offset));
    f.write(reinterpret_cast<const char*>(bytes.data()), static_cast<std::streamsize>(bytes.size()));
}

// One S1 record line (no CR): S1, count, 16-bit address, data, checksum.
std::string srec(uint16_t addr, const Bytes& data, int checksum_error = 0) {
    char buf[16];
    std::string line = "S1";
    uint32_t sum = 0;
    auto put = [&](uint8_t b) {
        std::snprintf(buf, sizeof buf, "%02X", b);
        line += buf;
        sum += b;
    };
    put(static_cast<uint8_t>(data.size() + 3));
    put(static_cast<uint8_t>(addr >> 8));
    put(static_cast<uint8_t>(addr & 0xFF));
    for (uint8_t b : data) put(b);
    std::snprintf(buf, sizeof buf, "%02X", static_cast<uint8_t>(~sum + checksum_error));
    return line + buf;
}

void send_line(Basic309Session& s, const std::string& line) {
    for (char c : line) s.send_byte(static_cast<uint8_t>(c));
    s.send_byte('\r');
    s.bus.run(60000);
}

bool ends_with(const std::string& s, const std::string& suffix) {
    return s.size() >= suffix.size() && s.compare(s.size() - suffix.size(), suffix.size(), suffix) == 0;
}

// One byte "arriving" at the UART, paced like the other harnesses: wait for RDRF to be set, then read.
void feed(DosSession& d, uint8_t byte) {
    d.uart.rx_enqueue(byte);
    uint32_t spent = 0;
    while (!(d.uart.status_register() & 0x08) && spent < 400000) spent += static_cast<uint32_t>(d.bus.step());
    spent = 0;
    while ((d.uart.status_register() & 0x08) && spent < 400000) spent += static_cast<uint32_t>(d.bus.step());
}

std::string audit_image(const char* name, uint32_t sectors = 4400) { return build_image(name, sectors, 1, {}); }

} // namespace

TEST(bios_sd_retries_transient_errors_and_reports_the_kind_of_failure) {
    std::string img = audit_image("audit1.img");
    CHECK(!img.empty());
    DosSession d;
    CHECK(d.boot(PUGBIOS_S19_PATH, img.c_str()));
    d.call(bios::B_DOS_VERSION); // (parks the CPU: nothing else runs while we poke the card)
    const uint16_t buf = DosSession::kData;
    auto issued = [&] { return d.sd.commands_issued(); };

    // A failing read command is tried again, up to three times in all.
    uint64_t c0 = issued();
    d.sd.fail_next_reads(2);
    auto r = d.call(bios::B_BLK_READ, 0, 0, 0, buf);
    CHECK(r.ok() && issued() - c0 == 3);
    CHECK(d.peek(buf + 510, 2) == Bytes({0x55, 0xAA})); // and it read the boot sector
    c0 = issued();
    d.sd.fail_next_reads(3);
    r = d.call(bios::B_BLK_READ, 0, 0, 0, buf);
    CHECK(r.carry && r.a == bios::ERR_IOERR && issued() - c0 == 3);
    d.sd.fail_next_reads(0);

    // The same for writes (to the volume's last block), with the data re-sent on a retry.
    Bytes block(512);
    for (size_t i = 0; i < 512; ++i) block[i] = static_cast<uint8_t>(i * 7 + 1);
    d.poke(buf, block);
    c0 = issued();
    d.sd.fail_next_writes(1);
    r = d.call(bios::B_BLK_WRITE, 0, 0, 4399, buf);
    CHECK(r.ok() && issued() - c0 == 2);
    d.poke(buf + 0x400, Bytes(512, 0));
    CHECK(d.call(bios::B_BLK_READ, 0, 0, 4399, buf + 0x400).ok());
    CHECK(d.peek(buf + 0x400, 512) == block);
    c0 = issued();
    d.sd.fail_next_writes(3);
    r = d.call(bios::B_BLK_WRITE, 0, 0, 4399, buf);
    CHECK(r.carry && r.a == bios::ERR_IOERR && issued() - c0 == 3);
    d.sd.fail_next_writes(0);

    // The 32-bit forms too; a block far beyond the card fails (after its retries).
    CHECK(d.call(bios::B_BLK_READ32, 0, 0, 0, buf).ok());
    c0 = issued();
    r = d.call(bios::B_BLK_READ32, 0, 0x01, 5, buf); // high word $0100
    CHECK(r.carry && r.a == bios::ERR_IOERR && issued() - c0 == 3);

    // No card: the error says so (no retries -- there is nothing to retry).
    d.sd.set_card_present(false);
    r = d.call(bios::B_BLK_READ, 0, 0, 0, buf);
    CHECK(r.carry && r.a == bios::ERR_NOCARD);
    r = d.call(bios::B_BLK_WRITE, 0, 0, 4399, buf);
    CHECK(r.carry && r.a == bios::ERR_NOCARD);
    d.sd.set_card_present(true);
    CHECK(d.call(bios::B_BLK_READ, 0, 0, 0, buf).ok());

    // A card that never comes back from BUSY: a timeout, not a hang.
    d.sd.set_stuck_busy(true);
    r = d.call(bios::B_BLK_READ, 0, 0, 0, buf);
    CHECK(r.carry && r.a == bios::ERR_TIMEOUT);
    r = d.call(bios::B_BLK_WRITE, 0, 0, 4399, buf);
    CHECK(r.carry && r.a == bios::ERR_TIMEOUT);
    d.sd.set_stuck_busy(false);
    CHECK(d.call(bios::B_BLK_READ, 0, 0, 0, buf).ok());
}

TEST(bios_block_calls_refuse_buffers_that_would_reach_the_rom_or_io_area) {
    std::string img = audit_image("audit2.img");
    DosSession d;
    CHECK(d.boot(PUGBIOS_S19_PATH, img.c_str()));
    d.call(bios::B_DOS_VERSION);
    uint64_t c0 = d.sd.commands_issued();
    // A 512-byte buffer must end below $F000; anything else could spray the hardware registers.
    for (uint16_t bad : {uint16_t(0xEE01), uint16_t(0xEF00), uint16_t(0xF000), uint16_t(0xFE00), uint16_t(0xFFEC), uint16_t(0xFFFF)}) {
        for (uint8_t fn : {bios::B_BLK_READ, bios::B_BLK_WRITE, bios::B_BLK_READ32, bios::B_BLK_WRITE32}) {
            auto r = d.call(fn, 0, 0, 0, bad);
            CHECK(r.carry && r.a == bios::ERR_BADPARAM);
        }
    }
    CHECK(d.sd.commands_issued() == c0); // none of them reached the card
    CHECK(d.bus.bank_register(1) == 1 && d.bus.bank_register(2) == 2 && d.bus.bank_register(3) == 3);
    // The last legal buffer is fine.
    CHECK(d.call(bios::B_BLK_READ, 0, 0, 0, 0xEE00).ok());
    CHECK(d.call(bios::B_BLK_READ32, 0, 0, 0, 0xEE00).ok());
}

TEST(bios_uart_reports_receive_errors_through_ioctl) {
    std::string img = audit_image("audit3.img");
    DosSession d;
    CHECK(d.boot(PUGBIOS_S19_PATH, img.c_str()));
    // Park the CPU in the SWI2 stub with interrupts ENABLED (the CPU was stopped somewhere
    // inside the shell's polling, where the mask may happen to be set): nobody reads the UART.
    hd6309_regs_t regs{};
    hd6309_get_regs(d.bus.cpu(), &regs);
    regs.cc &= static_cast<uint8_t>(~0x50);
    hd6309_set_regs(d.bus.cpu(), &regs);
    d.call(bios::B_DOS_VERSION);
    auto geterr = [&] {
        auto r = d.call(bios::B_IOCTL, bios::F_UART, bios::UT_IOC_GETERR);
        CHECK(r.ok());
        return r.b;
    };
    geterr(); // (discard whatever the boot left)
    CHECK(geterr() == 0);

    // More bytes than the 126-byte ring buffer holds, with nobody reading: the extra ones are lost, and noted.
    for (int i = 0; i < 200; ++i) feed(d, 0x41);
    uint8_t flags = geterr();
    if ((flags & 0x08) == 0) std::fprintf(stderr, "  flags after flood: %02X\n", flags);
    CHECK((flags & 0x08) != 0);
    CHECK(geterr() == 0); // reading the flags cleared them

    // Two bytes back to back with interrupts masked: the receiver overruns.
    hd6309_get_regs(d.bus.cpu(), &regs);
    regs.cc |= 0x10;
    hd6309_set_regs(d.bus.cpu(), &regs);
    d.uart.rx_enqueue('a');
    d.uart.rx_enqueue('b');
    d.bus.run(400000);
    hd6309_get_regs(d.bus.cpu(), &regs);
    regs.cc &= static_cast<uint8_t>(~0x10);
    hd6309_set_regs(d.bus.cpu(), &regs);
    d.bus.run(100000);
    CHECK((geterr() & 0x04) != 0);
    // An unknown ioctl function is refused.
    auto r = d.call(bios::B_IOCTL, bios::F_UART, 0x7F);
    CHECK(r.carry);
}

TEST(bios_srecord_loader_rejects_malformed_and_dangerous_records) {
    Basic309Session s;
    CHECK(s.boot_raw(PUGBIOS_S19_PATH, nullptr, "Send S-Record now"));
    uint8_t* ram = s.bus.ram();
    auto bad_rec = [&] { return has(s.received, "<- bad rec"); };

    // A good record loads, silently.
    s.received.clear();
    send_line(s, srec(0x2000, {0x01, 0x02, 0x03}));
    CHECK(!bad_rec() && ram[0x2000] == 1 && ram[0x2001] == 2 && ram[0x2002] == 3);

    // A wrong checksum: reported, nothing loaded.
    s.received.clear();
    send_line(s, srec(0x2100, {0xAA, 0xBB}, 1));
    CHECK(bad_rec() && ram[0x2100] == 0);

    // The BIOS's own RAM is off limits.
    Bytes before(ram + 0x100, ram + 0x110);
    s.received.clear();
    send_line(s, srec(0x0100, Bytes(16, 0xFF)));
    CHECK(bad_rec() && Bytes(ram + 0x100, ram + 0x110) == before);

    // So is anything that reaches the ROM and the I/O registers (the bank registers are at $FFEC).
    s.received.clear();
    send_line(s, srec(0xFFEC, {0x09, 0x09, 0x09, 0x09}));
    CHECK(bad_rec());
    CHECK(s.bus.bank_register(1) == 1 && s.bus.bank_register(2) == 2 && s.bus.bank_register(3) == 3);
    s.received.clear();
    send_line(s, srec(0xEFFE, {1, 2, 3, 4})); // starts in RAM, ends in the ROM
    CHECK(bad_rec() && ram[0xEFFE] == 0);
    s.received.clear();
    send_line(s, srec(0xF000, {1}));
    CHECK(bad_rec());

    // A record with no data bytes at all (this once looped 256 times, writing over 256 bytes).
    s.received.clear();
    send_line(s, "S1032100DB");
    CHECK(bad_rec() && ram[0x2100] == 0 && ram[0x2101] == 0);

    // A byte count claiming more than the line holds, or more than the decode buffer can.
    s.received.clear();
    send_line(s, "S128200011223344"); // says 0x28 bytes, has four
    CHECK(bad_rec() && ram[0x2000] == 1); // (still the first record's data)
    s.received.clear();
    send_line(s, "S1FF" + std::string(300, 'A')); // 255 bytes: far too many
    CHECK(bad_rec());

    // A line far longer than the line buffer doesn't overrun anything.
    s.received.clear();
    send_line(s, std::string(300, 'A'));
    // ":" is not a hex digit (it used to be read as 3).
    s.received.clear();
    std::string colon = srec(0x2400, {0x03});
    colon[9] = ':'; // "03" -> "0:"
    send_line(s, colon);
    CHECK(bad_rec() && ram[0x2400] == 0);

    // The loader is still alive and well after all that: a good record, then '.' runs it.
    s.received.clear();
    send_line(s, srec(0x2000, {0x86, 0x42, 0xB7, 0x31, 0x00, 0x39})); // LDA #$42 ; STA $3100 ; RTS (at the run address)
    CHECK(!bad_rec() && ram[0x2000] == 0x86);
    s.received.clear();
    s.send_byte('.');
    s.bus.run(300000);
    CHECK(has(s.received, "running..."));
    CHECK(ram[0x3100] == 0x42);
}

TEST(bios_disk_boot_refuses_a_corrupt_boot_sector_and_survives_a_dying_card) {
    auto boot_with = [&](const char* name, size_t offset, const Bytes& patch, const std::string& needle, Basic309Session& s) {
        std::string img = audit_image(name);
        if (!patch.empty()) patch_image(img, offset, patch);
        return s.boot_raw(PUGBIOS_S19_PATH, img.c_str(), needle);
    };
    // Control: an unmodified image boots to the shell.
    {
        Basic309Session s;
        CHECK(boot_with("audit_ok.img", 0, {}, "/> ", s));
        CHECK(has(s.received, "Pugputer 6309 shell"));
    }
    // A boot sector claiming 40 reserved sectors (more than DOS may take in bank 0), 1 (no DOS at all),
    // or 1024-byte sectors: no disk boot, straight to the S-record prompt, nothing loaded over RAM.
    for (auto patch : {std::make_pair(size_t(14), Bytes{40, 0}), std::make_pair(size_t(14), Bytes{0xFF, 0xFF}),
                       std::make_pair(size_t(14), Bytes{1, 0}), std::make_pair(size_t(11), Bytes{0, 4})}) {
        Basic309Session s;
        CHECK(boot_with("audit_bad.img", patch.first, patch.second, "Send S-Record now", s));
        CHECK(!has(s.received, "shell"));
        CHECK(s.bus.ram()[0x0600] == 0 && s.bus.ram()[0x0700] == 0); // nothing was loaded at DOS_LOAD
    }
    // Transient read errors during the boot are retried away: it still boots.
    {
        Basic309Session s;
        s.sd.fail_next_reads(2);
        CHECK(boot_with("audit_transient.img", 0, {}, "/> ", s));
    }
    // A card that dies after a few sectors: the failure is reported, and the loader prompt comes up.
    {
        Basic309Session s;
        s.sd.fail_reads_after(4);
        CHECK(boot_with("audit_dead.img", 0, {}, "Send S-Record now", s));
        CHECK(has(s.received, "Disk boot failed"));
        CHECK(!has(s.received, "shell"));
    }
    // No card at all is silent: just the prompt.
    {
        Basic309Session s;
        CHECK(s.boot_raw(PUGBIOS_S19_PATH, nullptr, "Send S-Record now"));
        CHECK(!has(s.received, "Disk boot failed"));
    }
}

TEST(bios_a_crashing_program_lands_back_in_the_shell_with_the_machine_put_right) {
    auto prog = [](const Bytes& body) {
        Bytes v{'P', 'X', 0x90, 0x00, 0x90, 0x00, 0, 0};
        v.insert(v.end(), body.begin(), body.end());
        pugputer::Fat16File f;
        f.data = v;
        return f;
    };
    // All of them run at $9000 (bank 2). The first two remap bank 1 (B_BANK_SET) and trash the direct page first.
    Bytes trash = {0xC6, 0x01, 0x11, 0x86, 0x14, 0x86, 0x2E, 0x10, 0x3F, // bank 1 -> page 20
                   0x86, 0xFF, 0x1F, 0x8B};                              // DP = $FF
    auto with = [&](Bytes a, const Bytes& b) {
        a.insert(a.end(), b.begin(), b.end());
        return a;
    };
    auto illegal = prog(with(trash, {0x87}));
    illegal.name = "ILLEGAL.COM";
    auto badstack = prog({0x10, 0xCE, 0xF8, 0x00, 0x87}); // LDS #$F800 (the ROM), then an illegal opcode
    badstack.name = "BADSTACK.COM";
    auto div0 = prog(with(trash, {0x11, 0x8D, 0x00})); // DIVD #0
    div0.name = "DIVZERO.COM";
    auto brk = prog({0x3F}); // SWI
    brk.name = "BREAK.COM";
    std::string img = build_image("audit_crash.img", 16384, 2, {illegal, badstack, div0, brk});
    Basic309Session s;
    CHECK(s.boot_shell(PUGBIOS_S19_PATH, img.c_str()));

    auto run = [&](const std::string& name, const std::string& message) {
        s.received.clear();
        s.type(name);
        CHECK(s.wait_for("Pugputer 6309 shell", 200000000)); // the shell restarted ...
        uint64_t spent = 0;
        while (!ends_with(s.received, "/> ") && spent < 100000000) spent += s.bus.run(20000);
        if (!has(s.received, message)) std::fprintf(stderr, "  [%s] expected [%s], got [%s]\n", name.c_str(), message.c_str(), s.received.c_str());
        CHECK(has(s.received, message));                      // ... after saying what happened
        CHECK(s.bus.bank_register(1) == 1 && s.bus.bank_register(2) == 2 && s.bus.bank_register(3) == 3);
        // The shell works: a command runs and prints normally.
        s.received.clear();
        s.type("ver");
        spent = 0;
        while (!has(s.received, "DOS 2.2") && spent < 100000000) spent += s.bus.run(20000);
        CHECK(has(s.received, "Pugputer 6309 DOS 2.2"));
        spent = 0;
        while (!ends_with(s.received, "/> ") && spent < 100000000) spent += s.bus.run(20000);
    };
    run("illegal", "*** ILLEGAL OPCODE at $90");
    run("badstack", "*** ILLEGAL OPCODE at $");
    run("divzero", "*** DIVIDE BY ZERO at $90");
    run("break", "*** BREAKPOINT at $90");
}

TEST(bios_and_dos_calls_need_only_a_modest_stack) {
    std::string img = audit_image("audit_stack.img");
    DosSession d;
    CHECK(d.boot(PUGBIOS_S19_PATH, img.c_str()));
    const uint16_t top = 0x3E00, low = 0x3A00; // 1KB below the stack top in bank 0, filled with a pattern
    d.stack = top;
    uint8_t* ram = d.bus.ram();
    std::fill(ram + low, ram + top, 0x5A);

    // A battery of the calls that go deepest: file creation in a subdirectory (path
    // resolution, directory growth, FAT allocation), directory scans, rename, delete,
    // stat, a failing B_EXEC, block I/O.
    CHECK(d.mkdir("A").ok() && d.mkdir("A/B").ok() && d.mkdir("A/B/C").ok());
    CHECK(d.chdir("A/B").ok());
    CHECK(d.write_file("C/DEEP.TXT", Bytes(3000, 7)));
    for (int i = 0; i < 20; ++i) CHECK(d.write_file("C/F" + std::to_string(i) + ".TXT", Bytes(10, 1))); // grows the directory
    CHECK(d.list("C").size() >= 21);
    CHECK(d.rename("C/DEEP.TXT", "MOVED.TXT").ok());
    CHECK(d.stat_path("C/MOVED.TXT").ok());
    CHECK(d.getcwd() == "/A/B");
    CHECK(d.kill("C/MOVED.TXT").ok());
    Bytes not_prog = Bytes(10, 1);
    CHECK(d.write_file("/NOTPROG.COM", not_prog));
    d.put_path("/NOTPROG.COM", DosSession::kNameBuf);
    auto r = d.call(bios::B_EXEC, 0, 0, DosSession::kNameBuf, 0); // (a real program would be started, not returned from)
    CHECK(r.carry && r.a == bios::ERR_BADEXE);
    CHECK(d.call(bios::B_BLK_READ, 0, 0, 0, DosSession::kData).ok());

    size_t lowest = low;
    while (lowest < top && ram[lowest] == 0x5A) ++lowest;
    size_t used = top - lowest;
    std::fprintf(stderr, "  (deepest stack use in the battery: %zu bytes, including the SWI2 frame)\n", used);
    CHECK(used > 0);
    CHECK(used <= 128); // programs must leave at least this much stack free for BIOS and DOS calls
}
