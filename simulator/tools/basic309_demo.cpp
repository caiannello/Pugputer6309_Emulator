// Boots the real bios/pugbios.s19 from its own $FFFE reset vector, lets its
// cold-start run to completion, then hands off to basic309's entry point
// (RESVEC, see basic309/exbasrom309.lst) -- standing in for what a future
// loader integration would do (see simulator/README.md / the basic309 plan)
// -- and bridges the UART to either this console (default) or a Windows COM
// port (e.g. one end of a com0com pair):
//
//   basic309_demo                     -- console bridge, default ROM paths
//   basic309_demo --com COM10         -- COM port bridge (see simulator/README.md)
//   basic309_demo --bios path\to.s19  -- load a different BIOS image
//   basic309_demo --basic path\to.s19 -- load a different basic309 image
//
// This exercises the BIOS's own cold-start, its SWI2 console-IO calls, and
// basic309's DP relocation / fixed-TOPRAM adaptation together. No disk is
// mapped, so file statements (LOAD/SAVE/OPEN/...) raise a BASIC error; use
// basic309_sdboot_demo for the full boot chain with files.
#include <conio.h>

#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

#include "pugputer/rom_device.hpp"
#include "pugputer/srec_loader.hpp"
#include "pugputer/system_bus.hpp"
#include "pugputer/uart_r65c51.hpp"
#ifdef PUGPUTER_HAVE_COM_BRIDGE
#include "pugputer/com_port_bridge.hpp"
#endif

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

int main(int argc, char** argv) {
    std::string com_port;
    std::string bios_path = PUGBIOS_S19_DEFAULT;
    std::string basic_path = EXBASROM309_S19_DEFAULT;
    for (int i = 1; i < argc; ++i) {
        if (std::strcmp(argv[i], "--com") == 0 && i + 1 < argc) {
            com_port = argv[++i];
        } else if (std::strcmp(argv[i], "--bios") == 0 && i + 1 < argc) {
            bios_path = argv[++i];
        } else if (std::strcmp(argv[i], "--basic") == 0 && i + 1 < argc) {
            basic_path = argv[++i];
        }
    }

    std::vector<uint8_t> bios_image(65536, 0);
    SrecLoadResult bios_load = load_srec_file(bios_path, bios_image.data(), bios_image.size());
    if (!bios_load.ok) {
        std::fprintf(stderr, "Failed to load BIOS image '%s': %s\n", bios_path.c_str(), bios_load.error.c_str());
        return 1;
    }
    std::printf("Loaded %s ($%04X-$%04X)\n", bios_path.c_str(), bios_load.min_addr, bios_load.max_addr);

    std::vector<uint8_t> basic_image(65536, 0);
    SrecLoadResult basic_load = load_srec_file(basic_path, basic_image.data(), basic_image.size());
    if (!basic_load.ok) {
        std::fprintf(stderr, "Failed to load basic309 image '%s': %s\n", basic_path.c_str(), basic_load.error.c_str());
        return 1;
    }
    std::printf("Loaded %s ($%04X-$%04X)\n", basic_path.c_str(), basic_load.min_addr, basic_load.max_addr);

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

    bool use_com = false;
#ifdef PUGPUTER_HAVE_COM_BRIDGE
    pugputer::ComPortBridge bridge;
    if (!com_port.empty()) {
        if (bridge.open(com_port, uart.current_baud_rate())) {
            use_com = true;
            std::printf("Bridging UART to %s. Connect a terminal to the other end of the com0com pair.\n",
                        com_port.c_str());
        } else {
            std::fprintf(stderr, "Failed to open %s: %s\nFalling back to console.\n", com_port.c_str(),
                         bridge.last_error().c_str());
        }
    }
#else
    if (!com_port.empty()) {
        std::fprintf(stderr, "This build has no COM-port bridge support; using the console instead.\n");
    }
#endif

    if (!use_com) {
        std::printf("Bridging UART to this console. Type to send bytes; Ctrl+C to quit.\n");
        uart.set_tx_callback([](uint8_t b) {
            std::putchar(b);
            std::fflush(stdout);
        });
    }
    std::fflush(stdout);
    std::fflush(stderr);

    bus.reset(); // PC comes from the real BIOS $FFFE vector
    bus.run(500000); // BIOS cold-start (RAM zero, bank setup, UART init, its own banner)

    // Hand off to basic309's entry point, standing in for a future loader
    // integration (see simulator/README.md / the basic309 plan).
    hd6309_regs_t regs{};
    hd6309_get_regs(bus.cpu(), &regs);
    regs.pc = kBasic309Entry;
    hd6309_set_regs(bus.cpu(), &regs);

    for (;;) {
        bus.run(20000);
        if (use_com) {
#ifdef PUGPUTER_HAVE_COM_BRIDGE
            bridge.poll(uart);
#endif
        } else {
            while (_kbhit()) {
                int ch = _getch();
                uart.rx_enqueue(static_cast<uint8_t>(ch));
            }
        }
    }
}
