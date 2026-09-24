// Like basic309_demo, but boots through the REAL disk chain instead of a
// hand-wired PC hijack: bios/pugbios.s19's own $FFFE reset vector runs its
// cold-start, its SD_BOOT_TRY (bios/sdcard.asm) finds and loads
// dos/dos.asm from disk.img's reserved sectors, and dos.asm's own FAT16
// root-directory scan finds and loads BASIC.COM before jumping to it --
// nothing here tells the emulator where BASIC.COM is. Build disk.img
// first with mkdiskimg.
//
//   basic309_sdboot_demo                     -- console bridge, default paths
//   basic309_sdboot_demo --com COM10         -- COM port bridge
//   basic309_sdboot_demo --bios path\to.s19  -- load a different BIOS image
//   basic309_sdboot_demo --disk path\to.img  -- load a different disk image
//   basic309_sdboot_demo --help
//
// Unless --bios / --disk say otherwise, pugbios.s19 and disk.img are looked for
// next to the executable first (that is how the binary release is laid out), and
// then at the paths this build was configured with (the source tree).
#ifndef NOMINMAX
#define NOMINMAX
#endif
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>

#include <conio.h>

#include <cstdio>
#include <cstring>
#include <fstream>
#include <string>
#include <vector>

#include "pugputer/rom_device.hpp"
#include "pugputer/sdcard_device.hpp"
#include "pugputer/srec_loader.hpp"
#include "pugputer/system_bus.hpp"
#include "pugputer/uart_r65c51.hpp"
#ifdef PUGPUTER_HAVE_COM_BRIDGE
#include "pugputer/com_port_bridge.hpp"
#endif

using pugputer::IrqLine;
using pugputer::load_srec_file;
using pugputer::RomDevice;
using pugputer::SdCardDevice;
using pugputer::SrecLoadResult;
using pugputer::SystemBus;
using pugputer::UartR65C51;

namespace {
constexpr uint16_t kBiosBase = 0xF000;
constexpr uint32_t kBiosSize = 0x1000; // $F000-$FFFF

// `name` next to the executable if it is there, else `fallback`.
std::string find_default(const char* name, const char* fallback) {
    char path[MAX_PATH] = {0};
    DWORD n = GetModuleFileNameA(nullptr, path, MAX_PATH);
    if (n > 0 && n < MAX_PATH) {
        std::string beside(path, n);
        size_t slash = beside.find_last_of("\\/");
        if (slash != std::string::npos) {
            beside = beside.substr(0, slash + 1) + name;
            if (std::ifstream(beside, std::ios::binary).good()) return beside;
        }
    }
    return fallback;
}

void usage() {
    std::printf(
        "Pugputer 6309 emulator: boots the BIOS, DOS, the shell and BASIC.\n"
        "\n"
        "  --com COMn       connect the UART to a COM port (e.g. one end of a com0com pair)\n"
        "                   instead of this console\n"
        "  --bios FILE      BIOS image, Motorola S-record (default: pugbios.s19 beside this program)\n"
        "  --disk FILE      FAT16 disk image (default: disk.img beside this program)\n"
        "  --help           this text\n"
        "\n"
        "In console mode, type at the prompt; Ctrl+C quits.\n");
}
} // namespace

int main(int argc, char** argv) {
    std::string com_port;
    std::string bios_path = find_default("pugbios.s19", PUGBIOS_S19_DEFAULT);
    std::string disk_path = find_default("disk.img", DISK_IMG_DEFAULT);
    for (int i = 1; i < argc; ++i) {
        if (std::strcmp(argv[i], "--help") == 0 || std::strcmp(argv[i], "-h") == 0 || std::strcmp(argv[i], "/?") == 0) {
            usage();
            return 0;
        } else if (std::strcmp(argv[i], "--com") == 0 && i + 1 < argc) {
            com_port = argv[++i];
        } else if (std::strcmp(argv[i], "--bios") == 0 && i + 1 < argc) {
            bios_path = argv[++i];
        } else if (std::strcmp(argv[i], "--disk") == 0 && i + 1 < argc) {
            disk_path = argv[++i];
        }
    }

    std::vector<uint8_t> bios_image(65536, 0);
    SrecLoadResult bios_load = load_srec_file(bios_path, bios_image.data(), bios_image.size());
    if (!bios_load.ok) {
        std::fprintf(stderr, "Failed to load BIOS image '%s': %s\n", bios_path.c_str(), bios_load.error.c_str());
        return 1;
    }
    std::printf("Loaded %s ($%04X-$%04X)\n", bios_path.c_str(), bios_load.min_addr, bios_load.max_addr);

    RomDevice bios_rom(static_cast<uint16_t>(kBiosSize));
    bios_rom.load(bios_image.data() + kBiosBase, kBiosSize);

    SdCardDevice sdcard;
    if (!sdcard.open(disk_path)) {
        std::fprintf(stderr, "Failed to open disk image '%s' (is it next to the program? see --help)\n", disk_path.c_str());
        return 1;
    }
    std::printf("Attached disk image %s\n", disk_path.c_str());

    SystemBus bus; // RAM starts entirely zeroed
    UartR65C51 uart;
    bus.map_device("bios_rom", kBiosBase, static_cast<uint16_t>(kBiosSize), &bios_rom, IrqLine::None);
    bus.map_device("sdcard", 0xFFD8, 4, &sdcard, IrqLine::None);
    bus.map_device("uart", 0xFFE8, 4, &uart, IrqLine::IRQ);
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
        std::printf("Bridging UART to this console. Type to send bytes; Ctrl+C to quit.\n"
                    "(At the shell prompt, type BASIC to start BASIC; SYSTEM leaves it.)\n\n");
        uart.set_tx_callback([](uint8_t b) {
            std::putchar(b);
            std::fflush(stdout);
        });
    }
    std::fflush(stdout);
    std::fflush(stderr);

    bus.reset(); // PC comes from the real BIOS $FFFE vector -- the whole
                 // boot chain (BIOS -> SD_BOOT_TRY -> dos.asm -> BASIC.COM)
                 // runs for real from here, no PC hijack.

    for (;;) {
        bus.run(20000);
        if (use_com) {
#ifdef PUGPUTER_HAVE_COM_BRIDGE
            bridge.poll(uart);
#endif
        } else {
            while (_kbhit()) {
                int ch = _getch();
                if (ch == 0 || ch == 0xE0) { // an arrow / function key: two codes, neither is text
                    (void)_getch();
                    continue;
                }
                uart.rx_enqueue(static_cast<uint8_t>(ch));
            }
        }
    }
}
