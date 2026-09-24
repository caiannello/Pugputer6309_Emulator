// The BIOS's RAM-bank service (bios/banks.asm): B_BANK_GET / B_BANK_SET, the page
// allocator (B_PAGE_ALLOC / FREE / INFO) and B_PAGE_COPY, called through the real
// SWI2 interface (dos_session.hpp boots the real chain and makes the calls). The
// simulator's own view -- bus.bank_register(), bus.phys_ram() -- is the referee.
//
// These tests run the SWI2 stub in bank 0 (which is never remapped) and choose the
// stack's bank explicitly, since the service must refuse to remap the bank the
// caller's stack is in.
#include <cstdio>
#include <fstream>
#include <regex>
#include <sstream>
#include <string>
#include <vector>

#include "dos_session.hpp"
#include "test_framework.hpp"

namespace {

constexpr size_t kPage = pugputer::SystemBus::kPageSize;
constexpr uint16_t kStackBank0 = 0x3E00; // one place per bank for the stack
constexpr uint16_t kStackBank1 = 0x7E00;
constexpr uint16_t kStackBank2 = 0xBE00;
constexpr uint16_t kStackBank3 = 0xEF00; // (below the ROM at $F000)

using Result = DosSession::Result;

// A session whose SWI2 stub and stack are in bank 0.
bool boot_banks(DosSession& d) {
    if (!d.boot(PUGBIOS_S19_PATH, DISK_IMG_PATH)) return false;
    d.stub = DosSession::kStub0;
    d.stack = kStackBank0;
    return true;
}

Result bank_get(DosSession& d, uint8_t bank) { return d.call(bios::B_BANK_GET, bank); }
Result bank_set(DosSession& d, uint8_t bank, uint8_t page) { return d.call(bios::B_BANK_SET, bank, page); }
Result page_alloc(DosSession& d) { return d.call(bios::B_PAGE_ALLOC); }
Result page_free(DosSession& d, uint8_t page) { return d.call(bios::B_PAGE_FREE, page); }
Result page_info(DosSession& d) { return d.call(bios::B_PAGE_INFO); }
Result page_copy(DosSession& d, uint8_t src, uint8_t dst, uint16_t soff, uint16_t doff, uint16_t len) {
    return d.call(bios::B_PAGE_COPY, src, dst, soff, doff, len);
}

bool err_is(const Result& r, uint8_t code) { return r.carry && r.a == code; }

bool identity_banks(DosSession& d) {
    for (int b = 0; b < 4; ++b)
        if (d.bus.bank_register(b) != b) return false;
    return true;
}

uint8_t cc_now(DosSession& d) {
    hd6309_regs_t r{};
    hd6309_get_regs(d.bus.cpu(), &r);
    return r.cc;
}
void set_cc(DosSession& d, uint8_t cc) {
    hd6309_regs_t r{};
    hd6309_get_regs(d.bus.cpu(), &r);
    r.cc = cc;
    hd6309_set_regs(d.bus.cpu(), &r);
}

// Fills physical page `page` with a pattern that depends on the page and offset.
void fill_page(DosSession& d, uint8_t page, uint8_t seed) {
    uint8_t* p = d.bus.phys_ram() + page * kPage;
    for (size_t i = 0; i < kPage; ++i) p[i] = static_cast<uint8_t>(seed + i * 3 + (i >> 8) * 5);
}
uint8_t pat(uint8_t seed, size_t i) { return static_cast<uint8_t>(seed + i * 3 + (i >> 8) * 5); }

} // namespace

TEST(bios_banks_page_info_after_boot) {
    DosSession d;
    CHECK(boot_banks(d));
    Result r = page_info(d);
    CHECK(r.ok());
    CHECK(r.x == 64); // installed
    CHECK(r.y == 60); // pages 0..3 are the system's and the reset mapping's
    CHECK(identity_banks(d));
}

TEST(bios_banks_alloc_hands_out_the_lowest_free_page_and_free_returns_it) {
    DosSession d;
    CHECK(boot_banks(d));
    Result a = page_alloc(d), b = page_alloc(d), c = page_alloc(d);
    CHECK(a.ok() && a.a == 4);
    CHECK(b.ok() && b.a == 5);
    CHECK(c.ok() && c.a == 6);
    CHECK(page_info(d).y == 57);
    CHECK(page_free(d, 5).ok());
    CHECK(page_info(d).y == 58);
    Result again = page_alloc(d);
    CHECK(again.ok() && again.a == 5); // the lowest free page again
    CHECK(page_alloc(d).a == 7);

    // Freeing what isn't allocated (or was never allocatable) is refused.
    CHECK(err_is(page_free(d, 40), bios::ERR_BADPARAM));  // never allocated
    CHECK(err_is(page_free(d, 3), bios::ERR_BADPARAM));   // a system page
    CHECK(err_is(page_free(d, 0), bios::ERR_BADPARAM));
    CHECK(err_is(page_free(d, 64), bios::ERR_BADPARAM));  // not installed
    CHECK(err_is(page_free(d, 255), bios::ERR_BADPARAM));
    CHECK(page_free(d, 6).ok());
    CHECK(err_is(page_free(d, 6), bios::ERR_BADPARAM));   // twice
    CHECK(page_info(d).y == 57); // 4, 5 and 7 are still allocated
    for (int p : {4, 5, 7}) CHECK(page_free(d, static_cast<uint8_t>(p)).ok());
    CHECK(page_info(d).y == 60);
}

TEST(bios_banks_alloc_runs_out_cleanly) {
    DosSession d;
    CHECK(boot_banks(d));
    std::vector<bool> seen(64, false);
    int got = 0;
    for (;;) {
        Result r = page_alloc(d);
        if (!r.ok()) {
            CHECK(err_is(r, bios::ERR_NOSPACE));
            break;
        }
        CHECK(r.a >= 4 && r.a < 64);
        CHECK(!seen[r.a]);
        seen[r.a] = true;
        CHECK(r.a == 4 + got); // ascending, no gaps
        if (++got > 70) break;
    }
    CHECK(got == 60);
    CHECK(page_info(d).y == 0);
    CHECK(page_free(d, 33).ok());
    Result r = page_alloc(d);
    CHECK(r.ok() && r.a == 33);
    CHECK(err_is(page_alloc(d), bios::ERR_NOSPACE));
    for (uint8_t p = 4; p < 64; ++p) CHECK(page_free(d, p).ok());
    CHECK(page_info(d).y == 60);
}

TEST(bios_banks_get_and_set_agree_with_the_hardware_registers) {
    DosSession d;
    CHECK(boot_banks(d));
    for (uint8_t b = 0; b < 4; ++b) {
        Result r = bank_get(d, b);
        CHECK(r.ok() && r.a == b);
    }
    CHECK(err_is(bank_get(d, 4), bios::ERR_BADPARAM));
    CHECK(err_is(bank_get(d, 255), bios::ERR_BADPARAM));

    CHECK(bank_set(d, 1, 20).ok());
    CHECK(bank_set(d, 2, 33).ok());
    CHECK(bank_set(d, 3, 63).ok());
    CHECK(d.bus.bank_register(1) == 20 && d.bus.bank_register(2) == 33 && d.bus.bank_register(3) == 63);
    CHECK(d.bus.bank_register(0) == 0);
    CHECK(bank_get(d, 1).a == 20 && bank_get(d, 2).a == 33 && bank_get(d, 3).a == 63 && bank_get(d, 0).a == 0);

    // The CPU really sees the new pages: write through bank 1 and find it in physical page 20.
    d.bus.write_cpu(0x4123, 0x5A);
    CHECK(d.bus.phys_ram()[20 * kPage + 0x123] == 0x5A);
    d.bus.write_cpu(0xBFFF, 0xC3);
    CHECK(d.bus.phys_ram()[33 * kPage + 0x3FFF] == 0xC3);

    // Several banks may show the same page.
    CHECK(bank_set(d, 1, 9).ok() && bank_set(d, 2, 9).ok());
    d.bus.write_cpu(0x4000, 0x77);
    CHECK(d.bus.read_cpu(0x8000) == 0x77);

    // Put things back.
    for (uint8_t b = 1; b < 4; ++b) CHECK(bank_set(d, b, b).ok());
    CHECK(identity_banks(d));
}

TEST(bios_banks_set_refuses_bank_0_bad_pages_and_the_stack_bank) {
    DosSession d;
    CHECK(boot_banks(d));
    CHECK(err_is(bank_set(d, 0, 9), bios::ERR_BADPARAM));   // bank 0 is fixed
    CHECK(err_is(bank_set(d, 0, 0), bios::ERR_BADPARAM));
    CHECK(err_is(bank_set(d, 4, 9), bios::ERR_BADPARAM));   // no such bank
    CHECK(err_is(bank_set(d, 1, 64), bios::ERR_BADPARAM));  // not installed
    CHECK(err_is(bank_set(d, 1, 200), bios::ERR_BADPARAM));
    CHECK(err_is(bank_set(d, 1, 255), bios::ERR_BADPARAM));
    CHECK(identity_banks(d)); // nothing changed
    CHECK(bank_get(d, 1).a == 1 && bank_get(d, 2).a == 2 && bank_get(d, 3).a == 3);

    // The bank the stack is in cannot be remapped -- the frame would vanish.
    const uint16_t stacks[] = {kStackBank1, kStackBank2, kStackBank3};
    for (int i = 0; i < 3; ++i) {
        d.stack = stacks[i];
        uint8_t bank = static_cast<uint8_t>(i + 1);
        CHECK(err_is(bank_set(d, bank, 40), bios::ERR_BADPARAM));
        CHECK(d.bus.bank_register(bank) == bank);
        uint8_t other = bank == 1 ? 2 : 1;
        CHECK(bank_set(d, other, 41).ok()); // ... but the other banks are fine
        CHECK(d.bus.bank_register(other) == 41);
        CHECK(bank_set(d, other, other).ok());
    }
    d.stack = kStackBank0;
    CHECK(identity_banks(d));
}

TEST(bios_banks_installed_ram_is_probed_at_reset) {
    for (size_t pages : {size_t(4), size_t(5), size_t(16), size_t(37), size_t(128), size_t(255), size_t(256)}) {
        DosSession d(pages);
        CHECK(boot_banks(d));
        Result r = page_info(d);
        CHECK(r.ok());
        CHECK(r.x == pages);
        CHECK(r.y == pages - 4);
        // The last installed page can be mapped; the first missing one can't.
        if (pages > 4) {
            CHECK(bank_set(d, 1, static_cast<uint8_t>(pages - 1)).ok());
            CHECK(bank_set(d, 1, 1).ok());
        }
        if (pages < 256) CHECK(err_is(bank_set(d, 1, static_cast<uint8_t>(pages)), bios::ERR_BADPARAM));
        // The allocator hands out exactly the installed pages and no others.
        size_t n = 0;
        for (;;) {
            Result a = page_alloc(d);
            if (!a.ok()) break;
            CHECK(a.a < pages);
            if (++n > 300) break;
        }
        CHECK(n == pages - 4);
    }
}

TEST(bios_banks_page_copy_copies_between_pages_without_touching_the_mapping) {
    DosSession d;
    CHECK(boot_banks(d));
    fill_page(d, 10, 0x11);
    fill_page(d, 11, 0xEE);
    std::vector<uint8_t> before(d.bus.phys_ram() + 11 * kPage, d.bus.phys_ram() + 12 * kPage);

    // 1000 bytes (several 256-byte chunks and a short one), unaligned on both sides.
    Result r = page_copy(d, 10, 11, 100, 300, 1000);
    CHECK(r.ok());
    const uint8_t* src = d.bus.phys_ram() + 10 * kPage;
    const uint8_t* dst = d.bus.phys_ram() + 11 * kPage;
    bool same = true, untouched = true;
    for (size_t i = 0; i < 1000; ++i) same = same && dst[300 + i] == src[100 + i];
    for (size_t i = 0; i < kPage; ++i)
        if ((i < 300 || i >= 1300) && dst[i] != before[i]) untouched = false;
    CHECK(same);
    CHECK(untouched);
    CHECK(identity_banks(d));
    CHECK(bank_get(d, 1).a == 1 && bank_get(d, 2).a == 2 && bank_get(d, 3).a == 3);
    // The source is unchanged.
    bool src_ok = true;
    for (size_t i = 0; i < kPage; ++i) src_ok = src_ok && src[i] == pat(0x11, i);
    CHECK(src_ok);

    // A whole page, and the copy keeps working when the banks were remapped by the caller.
    CHECK(bank_set(d, 1, 30).ok() && bank_set(d, 2, 31).ok() && bank_set(d, 3, 32).ok());
    fill_page(d, 12, 0x21);
    fill_page(d, 13, 0x00);
    CHECK(page_copy(d, 12, 13, 0, 0, 0x4000).ok());
    bool whole = true;
    for (size_t i = 0; i < kPage; ++i) whole = whole && d.bus.phys_ram()[13 * kPage + i] == pat(0x21, i);
    CHECK(whole);
    CHECK(d.bus.bank_register(1) == 30 && d.bus.bank_register(2) == 31 && d.bus.bank_register(3) == 32);
    CHECK(bank_get(d, 1).a == 30 && bank_get(d, 2).a == 31 && bank_get(d, 3).a == 32);

    // System pages can be a source or a destination too (page 1 is bank 1's reset page).
    for (uint8_t b = 1; b < 4; ++b) CHECK(bank_set(d, b, b).ok());
    d.bus.phys_ram()[1 * kPage + 5] = 0x99;
    CHECK(page_copy(d, 1, 14, 0, 0, 16).ok());
    CHECK(d.bus.phys_ram()[14 * kPage + 5] == 0x99);
    CHECK(identity_banks(d));
}

TEST(bios_banks_page_copy_works_with_the_stack_in_any_bank) {
    for (uint16_t sp : {kStackBank0, kStackBank1, kStackBank2, kStackBank3}) {
        DosSession d;
        CHECK(boot_banks(d));
        d.stack = sp;
        fill_page(d, 20, 0x31);
        fill_page(d, 21, 0x00);
        Result r = page_copy(d, 20, 21, 0x10, 0x20, 700);
        CHECK(r.ok());
        bool ok = true;
        for (size_t i = 0; i < 700; ++i) ok = ok && d.bus.phys_ram()[21 * kPage + 0x20 + i] == pat(0x31, 0x10 + i);
        CHECK(ok);
        CHECK(d.bus.phys_ram()[21 * kPage + 0x1F] == pat(0x00, 0x1F) && d.bus.phys_ram()[21 * kPage + 0x20 + 700] == pat(0x00, 0x20 + 700)); // just outside the range: untouched
        CHECK(identity_banks(d));
    }
}

TEST(bios_banks_page_copy_keeps_the_callers_interrupt_mask) {
    DosSession d;
    CHECK(boot_banks(d));
    fill_page(d, 20, 0x31);
    for (uint8_t mask : {uint8_t(0x00), uint8_t(0x10), uint8_t(0x40), uint8_t(0x50)}) {
        uint8_t cc = static_cast<uint8_t>((cc_now(d) & ~0x50) | mask);
        set_cc(d, cc);
        CHECK(page_copy(d, 20, 21, 0, 0, 3000).ok());
        CHECK((cc_now(d) & 0x50) == mask); // I and F exactly as the caller had them
    }
}

TEST(bios_banks_page_copy_rejects_bad_arguments_and_changes_nothing) {
    DosSession d;
    CHECK(boot_banks(d));
    fill_page(d, 20, 0x31);
    fill_page(d, 21, 0x77);
    std::vector<uint8_t> p21(d.bus.phys_ram() + 21 * kPage, d.bus.phys_ram() + 22 * kPage);
    auto dst_unchanged = [&] {
        return std::equal(p21.begin(), p21.end(), d.bus.phys_ram() + 21 * kPage);
    };
    CHECK(err_is(page_copy(d, 20, 21, 0x3F00, 0, 0x101), bios::ERR_BADPARAM)); // source runs off the page
    CHECK(err_is(page_copy(d, 20, 21, 0, 0x3F00, 0x101), bios::ERR_BADPARAM)); // destination does
    CHECK(err_is(page_copy(d, 20, 21, 0x4000, 0, 1), bios::ERR_BADPARAM));
    CHECK(err_is(page_copy(d, 20, 21, 1, 0, 0x4000), bios::ERR_BADPARAM));
    CHECK(err_is(page_copy(d, 20, 21, 0, 0, 0xFFFF), bios::ERR_BADPARAM));
    CHECK(err_is(page_copy(d, 64, 21, 0, 0, 16), bios::ERR_BADPARAM));         // source not installed
    CHECK(err_is(page_copy(d, 20, 64, 0, 0, 16), bios::ERR_BADPARAM));         // destination not installed
    CHECK(err_is(page_copy(d, 20, 255, 0, 0, 16), bios::ERR_BADPARAM));
    CHECK(err_is(page_copy(d, 20, 20, 100, 150, 100), bios::ERR_BADPARAM));    // overlap in one page
    CHECK(err_is(page_copy(d, 20, 20, 150, 100, 100), bios::ERR_BADPARAM));
    CHECK(err_is(page_copy(d, 20, 20, 0, 0, 1), bios::ERR_BADPARAM));         // onto itself
    CHECK(dst_unchanged());
    CHECK(identity_banks(d));

    // Edge cases that are fine.
    CHECK(page_copy(d, 20, 21, 5, 5, 0).ok());                  // nothing to copy
    CHECK(dst_unchanged());
    CHECK(page_copy(d, 20, 20, 0, 100, 100).ok());              // adjacent, not overlapping, in one page
    CHECK(d.bus.phys_ram()[20 * kPage + 100] == pat(0x31, 0));
    CHECK(page_copy(d, 20, 21, 0x3FFF, 0x3FFF, 1).ok());        // the very last byte
    CHECK(d.bus.phys_ram()[21 * kPage + 0x3FFF] == pat(0x31, 0x3FFF));
    CHECK(identity_banks(d));
}

TEST(bios_layout_bios_ram_ends_below_where_dos_is_loaded) {
    // pugbios.map: "Symbol: EndOfVars (main.o) = 052B"
    std::ifstream map(PUGBIOS_MAP_PATH);
    CHECK(map.good());
    std::string line;
    long end_of_vars = -1;
    std::regex sym(R"(Symbol: EndOfVars \(.*\) = ([0-9A-Fa-f]+))");
    while (std::getline(map, line)) {
        std::smatch m;
        if (std::regex_search(line, m, sym)) end_of_vars = std::stol(m[1].str(), nullptr, 16);
    }
    CHECK(end_of_vars > 0);

    // defines.d: "DOS_LOAD    equ  $0600 ..."
    std::ifstream defs(BIOS_DEFINES_PATH);
    CHECK(defs.good());
    long dos_load = -1;
    std::regex eq(R"(^DOS_LOAD\s+equ\s+\$([0-9A-Fa-f]+))");
    while (std::getline(defs, line)) {
        std::smatch m;
        if (std::regex_search(line, m, eq)) dos_load = std::stol(m[1].str(), nullptr, 16);
    }
    CHECK(dos_load > 0);
    CHECK(end_of_vars <= dos_load); // else the BIOS's variables and DOS overlap

    // ... and DOS must end below BASIC's workspace ($3000, WORKBASE in exbasrom309.asm).
    std::ifstream dos(DOS_BIN_PATH, std::ios::binary | std::ios::ate);
    CHECK(dos.good());
    long dos_end = dos_load + static_cast<long>(dos.tellg());
    CHECK(dos_end <= 0x3000);
}
