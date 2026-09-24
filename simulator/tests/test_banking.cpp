// RAM banking in SystemBus: four 16KB CPU banks, each mapped through an 8-bit
// write-only register (at $FFEC..$FFEF) to any of 256 physical pages, 64 of
// which (1MB) are installed by default. ROM/IO are unaffected by banking.
#include <cstdio>

#include "pugputer/rom_device.hpp"
#include "pugputer/system_bus.hpp"
#include "test_framework.hpp"

using pugputer::IrqLine;
using pugputer::RomDevice;
using pugputer::SystemBus;

namespace {
constexpr size_t kPage = SystemBus::kPageSize;
constexpr uint16_t kReg0 = SystemBus::kBankRegistersBase;
} // namespace

TEST(banking_reset_mapping_is_identity_and_ram_pointer_is_the_cpu_view) {
    SystemBus bus;
    CHECK(bus.ram_pages() == 64);
    for (int b = 0; b < 4; ++b) CHECK(bus.bank_register(b) == b);
    bus.write_cpu(0x0123, 0x11);
    bus.write_cpu(0x4123, 0x22);
    bus.write_cpu(0x8123, 0x33);
    bus.write_cpu(0xC123, 0x44);
    CHECK(bus.ram()[0x0123] == 0x11);
    CHECK(bus.ram()[0x4123] == 0x22);
    CHECK(bus.ram()[0x8123] == 0x33);
    CHECK(bus.ram()[0xC123] == 0x44);
}

TEST(banking_registers_are_not_writable_until_mapped) {
    SystemBus bus;
    bus.write_cpu(kReg0 + 1, 9); // plain RAM at this address: no bank effect
    CHECK(bus.bank_register(1) == 1);
    bus.map_bank_registers();
    bus.write_cpu(kReg0 + 1, 9);
    CHECK(bus.bank_register(1) == 9);
}

TEST(banking_remapping_a_bank_changes_which_physical_page_the_cpu_sees) {
    SystemBus bus;
    bus.map_bank_registers();
    bus.write_cpu(0x4000, 0xA1);                 // physical page 1, offset 0
    bus.write_cpu(kReg0 + 1, 9);                 // bank 1 -> page 9
    CHECK(bus.read_cpu(0x4000) != 0xA1);         // page 9 is untouched RAM
    bus.write_cpu(0x4000, 0xB2);
    CHECK(bus.phys_ram()[9 * kPage] == 0xB2);    // it landed in page 9 ...
    CHECK(bus.phys_ram()[1 * kPage] == 0xA1);    // ... and page 1 was not disturbed
    bus.write_cpu(kReg0 + 1, 1);                 // back again
    CHECK(bus.read_cpu(0x4000) == 0xA1);
    bus.write_cpu(kReg0 + 1, 9);
    CHECK(bus.read_cpu(0x4000) == 0xB2);         // and page 9 kept its data
}

TEST(banking_offset_within_the_page_comes_from_cpu_address_bits_13_to_0) {
    SystemBus bus;
    bus.map_bank_registers();
    bus.write_cpu(kReg0 + 2, 20); // bank 2 ($8000-$BFFF) -> page 20
    bus.write_cpu(0x8000, 0x01);
    bus.write_cpu(0x9234, 0x02);
    bus.write_cpu(0xBFFF, 0x03); // last byte of the bank
    CHECK(bus.phys_ram()[20 * kPage + 0x0000] == 0x01);
    CHECK(bus.phys_ram()[20 * kPage + 0x1234] == 0x02);
    CHECK(bus.phys_ram()[20 * kPage + 0x3FFF] == 0x03);
    CHECK(bus.phys_ram()[21 * kPage] == 0x00); // did not spill into the next page
}

TEST(banking_the_four_banks_are_independent_and_can_share_a_page) {
    SystemBus bus;
    bus.map_bank_registers();
    bus.write_cpu(kReg0 + 1, 30);
    bus.write_cpu(kReg0 + 2, 30); // banks 1 and 2 both -> page 30
    bus.write_cpu(kReg0 + 3, 31);
    bus.write_cpu(0x4010, 0x5A);
    CHECK(bus.read_cpu(0x8010) == 0x5A); // the same physical byte through two windows
    bus.write_cpu(0xC010, 0x6B);
    CHECK(bus.phys_ram()[31 * kPage + 0x10] == 0x6B);
    CHECK(bus.bank_register(0) == 0); // bank 0 untouched (the BIOS keeps it at page 0)
}

TEST(banking_reaches_all_of_1mb_and_an_uninstalled_page_floats_high) {
    SystemBus bus;
    bus.map_bank_registers();
    bus.write_cpu(kReg0 + 1, 63); // the last installed page, physical $0FC000
    bus.write_cpu(0x7FFF, 0xEE);
    CHECK(bus.phys_ram()[64 * kPage - 1] == 0xEE);
    bus.write_cpu(kReg0 + 1, 64); // first page beyond the installed 1MB
    CHECK(bus.read_cpu(0x4000) == 0xFF);
    bus.write_cpu(0x4000, 0x12);  // dropped
    CHECK(bus.read_cpu(0x4000) == 0xFF);
    bus.write_cpu(kReg0 + 1, 255); // the top of the 22-bit space: also empty
    CHECK(bus.read_cpu(0x7FFF) == 0xFF);
    bus.write_cpu(kReg0 + 1, 63);
    CHECK(bus.read_cpu(0x7FFF) == 0xEE);
}

TEST(banking_installed_ram_size_is_configurable) {
    SystemBus small(8); // 128KB
    small.map_bank_registers();
    small.write_cpu(kReg0 + 1, 7);
    small.write_cpu(0x4000, 0x42);
    CHECK(small.phys_ram()[7 * kPage] == 0x42);
    small.write_cpu(kReg0 + 1, 8);
    CHECK(small.read_cpu(0x4000) == 0xFF);
}

TEST(banking_does_not_affect_rom_or_io_which_are_decoded_from_the_cpu_address) {
    SystemBus bus;
    std::vector<uint8_t> image(0x1000, 0x99);
    RomDevice rom(0x1000);
    rom.load(image.data(), image.size());
    bus.map_device("rom", 0xF000, 0x1000, &rom, IrqLine::None);
    bus.map_bank_registers();
    bus.write_cpu(kReg0 + 3, 40); // bank 3 -> page 40: RAM at $C000-$EFFF changes ...
    bus.write_cpu(0xE000, 0x77);
    CHECK(bus.phys_ram()[40 * kPage + 0x2000] == 0x77);
    CHECK(bus.read_cpu(0xF000) == 0x99); // ... the ROM window does not
    CHECK(bus.read_cpu(0xFFF0) == 0x99);
    bus.write_cpu(0xF000, 0x00);          // and stays read-only
    CHECK(bus.read_cpu(0xF000) == 0x99);
    (void)bus.read_cpu(0xFFEB + 1); // reading the write-only register window is harmless
    CHECK(bus.bank_register(3) == 40);
}

TEST(banking_reset_restores_the_identity_mapping_and_keeps_ram) {
    SystemBus bus;
    bus.map_bank_registers();
    bus.write_cpu(kReg0 + 1, 12);
    bus.write_cpu(0x4000, 0xC3);
    bus.reset();
    CHECK(bus.bank_register(1) == 1);
    CHECK(bus.phys_ram()[12 * kPage] == 0xC3); // RAM survives a CPU reset
}

TEST(banking_the_cpu_fetches_and_runs_code_through_a_remapped_bank) {
    SystemBus bus;
    bus.map_bank_registers();
    // Two tiny programs, in physical pages 9 and 11, each: LDA #imm / STA $0400 / BRA *.
    auto put_program = [&](size_t page, uint8_t value) {
        uint8_t* p = bus.phys_ram() + page * kPage;
        const uint8_t code[] = { 0x86, value, 0xB7, 0x04, 0x00, 0x20, 0xFE };
        for (size_t i = 0; i < sizeof code; ++i) p[i] = code[i];
    };
    put_program(9, 0xAA);
    put_program(11, 0xBB);

    auto run_from_bank1 = [&](uint8_t page) {
        bus.write_cpu(kReg0 + 1, page);
        hd6309_regs_t regs{};
        hd6309_get_regs(bus.cpu(), &regs);
        regs.pc = 0x4000;
        hd6309_set_regs(bus.cpu(), &regs);
        for (int i = 0; i < 4; ++i) bus.step();
    };
    run_from_bank1(9);
    CHECK(bus.phys_ram()[0x400] == 0xAA); // stored into bank 0 (page 0), which stays put
    run_from_bank1(11);
    CHECK(bus.phys_ram()[0x400] == 0xBB); // the same address now runs the other page's code
}

TEST(banking_the_cpu_stack_can_live_in_a_remapped_bank) {
    SystemBus bus;
    bus.map_bank_registers();
    // JSR to a subroutine in bank 2, whose RTS returns via the stack in bank 3.
    bus.write_cpu(kReg0 + 3, 50); // bank 3 -> page 50; the stack pointer will be $EFFF
    bus.write_cpu(kReg0 + 2, 51); // bank 2 -> page 51; the subroutine is at $8000
    bus.write_cpu(0x8000, 0x86); bus.write_cpu(0x8001, 0x5C); // LDA #$5C
    bus.write_cpu(0x8002, 0x39);                              // RTS
    // Main (bank 0, page 0): LDS #$EFFF / JSR $8000 / STA $0500 / BRA *
    const uint8_t main_code[] = { 0x10, 0xCE, 0xEF, 0xFF, 0xBD, 0x80, 0x00, 0xB7, 0x05, 0x00, 0x20, 0xFE };
    for (size_t i = 0; i < sizeof main_code; ++i) bus.write_cpu(static_cast<uint16_t>(0x0200 + i), main_code[i]);
    hd6309_regs_t regs{};
    hd6309_get_regs(bus.cpu(), &regs);
    regs.pc = 0x0200;
    hd6309_set_regs(bus.cpu(), &regs);
    for (int i = 0; i < 6; ++i) bus.step();
    CHECK(bus.phys_ram()[0x0500] == 0x5C);
    // The return address ($0207) was pushed just below $EFFF, i.e. into physical page 50.
    CHECK(bus.phys_ram()[50 * kPage + 0x2FFD] == 0x02 && bus.phys_ram()[50 * kPage + 0x2FFE] == 0x07);
}
