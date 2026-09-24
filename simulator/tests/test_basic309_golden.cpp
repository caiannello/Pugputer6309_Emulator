// Integration test against the real bios/pugbios.s19 + basic309/
// exbasrom309.s19 (only compiled/run when both files exist -- see
// tests/CMakeLists.txt). Boots the real BIOS from its own $FFFE reset
// vector, lets
// its cold-start run to completion, then hands off to basic309's entry
// point ($C000, a JMP RESVEC) -- standing in
// for what a future loader integration would do -- and confirms
// basic309's real startup banner comes out through the same BIOS-owned
// UART, proving the DP relocation, fixed-TOPRAM cold-start, and SWI2
// console-IO calls all work together against the real assembled images.
#include <cstdio>
#include <string>

#include "test_framework.hpp"
#include "pugputer/rom_device.hpp"
#include "pugputer/srec_loader.hpp"
#include "pugputer/system_bus.hpp"
#include "pugputer/uart_r65c51.hpp"

using pugputer::IrqLine;
using pugputer::load_srec_file;
using pugputer::RomDevice;
using pugputer::SrecLoadResult;
using pugputer::SystemBus;
using pugputer::UartR65C51;

namespace {
constexpr uint16_t kBiosBase = 0xF000;
constexpr uint32_t kBiosSize = 0x1000; // $F000-$FFFF
constexpr uint16_t kBasicBase = 0xC000;
constexpr uint32_t kBasicSize = 0x3000; // $C000-$EFFF
constexpr uint16_t kBasic309Entry = 0xC000; // fixed entry: JMP RESVEC (see exbasrom309.asm)
} // namespace

TEST(basic309_boots_after_bios_and_prints_its_banner_via_bios_console_calls) {
    std::vector<uint8_t> bios_image(65536, 0);
    SrecLoadResult bios_load = load_srec_file(PUGBIOS_S19_PATH, bios_image.data(), bios_image.size());
    CHECK(bios_load.ok);
    if (!bios_load.ok) return;

    std::vector<uint8_t> basic_image(65536, 0);
    SrecLoadResult basic_load = load_srec_file(EXBASROM309_S19_PATH, basic_image.data(), basic_image.size());
    CHECK(basic_load.ok);
    if (!basic_load.ok) return;

    RomDevice bios_rom(static_cast<uint16_t>(kBiosSize));
    bios_rom.load(bios_image.data() + kBiosBase, kBiosSize);

    RomDevice basic_rom(static_cast<uint16_t>(kBasicSize));
    basic_rom.load(basic_image.data() + kBasicBase, kBasicSize);

    SystemBus bus; // RAM starts entirely zeroed
    UartR65C51 uart;
    bus.map_device("bios_rom", kBiosBase, static_cast<uint16_t>(kBiosSize), &bios_rom, IrqLine::None);
    bus.map_device("basic_rom", kBasicBase, static_cast<uint16_t>(kBasicSize), &basic_rom, IrqLine::None);
    bus.map_device("uart", 0xFFE8, 4, &uart, IrqLine::IRQ); // registered last: overrides bios_rom's window here
    bus.map_bank_registers(); // $FFEC-$FFEF: the BIOS programs the RAM banks at reset

    std::string received;
    uart.set_tx_callback([&](uint8_t b) { received += static_cast<char>(b); });

    bus.reset(); // PC comes from the real BIOS $FFFE vector this time
    bus.run(500000); // BIOS cold-start (RAM zero, bank setup, UART init, its own banner)

    // Hand off to basic309's entry point, standing in for a future loader
    // integration (see simulator/README.md / the plan this implements).
    hd6309_regs_t regs{};
    hd6309_get_regs(bus.cpu(), &regs);
    regs.pc = kBasic309Entry;
    hd6309_set_regs(bus.cpu(), &regs);

    bus.run(4000000); // basic309's own cold-start + banner + idle input loop

    hd6309_get_regs(bus.cpu(), &regs);
    CHECK((regs.md & 0x40) == 0); // no illegal-opcode trap
    CHECK(received.find("6809 EXTENDED BASIC") != std::string::npos);
    CHECK(received.find("MICROSOFT") != std::string::npos);
    CHECK(received.find("OK") != std::string::npos);
}
