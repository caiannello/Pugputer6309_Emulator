// Integration test against the real bios/pugbios.s19 + basic309/disk.img
// (only compiled/run when both exist -- see tests/CMakeLists.txt). Unlike
// test_basic309_golden.cpp's hand-wired hijack (which sets PC to
// basic309's entry point directly), this boots through the REAL disk
// chain end to end: BIOS's own $FFFE reset vector -> SD_BOOT_TRY
// (bios/sdcard.asm) finds and loads dos/dos.asm from disk.img's reserved
// sectors -> dos.asm's FAT16 root-directory scan finds and loads
// BASIC.COM -> jumps to it. Nothing here tells the emulator where
// BASIC.COM is -- proving the whole boot chain, not just basic309 itself.
#include <cstdio>
#include <string>

#include "test_framework.hpp"
#include "pugputer/rom_device.hpp"
#include "pugputer/sdcard_device.hpp"
#include "pugputer/srec_loader.hpp"
#include "pugputer/system_bus.hpp"
#include "pugputer/uart_r65c51.hpp"

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
} // namespace

TEST(basic309_boots_from_disk_image_via_the_real_bios_and_dos_chain) {
    std::vector<uint8_t> bios_image(65536, 0);
    SrecLoadResult bios_load = load_srec_file(PUGBIOS_S19_PATH, bios_image.data(), bios_image.size());
    CHECK(bios_load.ok);
    if (!bios_load.ok) return;

    RomDevice bios_rom(static_cast<uint16_t>(kBiosSize));
    bios_rom.load(bios_image.data() + kBiosBase, kBiosSize);

    SdCardDevice sdcard;
    CHECK(sdcard.open(DISK_IMG_PATH));
    if (!sdcard.is_open()) return;

    SystemBus bus; // RAM starts entirely zeroed
    UartR65C51 uart;
    bus.map_device("bios_rom", kBiosBase, static_cast<uint16_t>(kBiosSize), &bios_rom, IrqLine::None);
    bus.map_device("sdcard", 0xFFD8, 4, &sdcard, IrqLine::None);
    bus.map_device("uart", 0xFFE8, 4, &uart, IrqLine::IRQ);
    bus.map_bank_registers(); // $FFEC-$FFEF: the BIOS programs the RAM banks at reset

    std::string received;
    uart.set_tx_callback([&](uint8_t b) { received += static_cast<char>(b); });

    bus.reset(); // PC comes from the real BIOS $FFFE vector -- the whole
                 // chain runs for real from here.
    bus.run(6000000); // BIOS cold-start + disk boot + basic309's own
                       // cold-start + banner + idle input loop

    hd6309_regs_t regs{};
    hd6309_get_regs(bus.cpu(), &regs);
    CHECK((regs.md & 0x40) == 0); // no illegal-opcode trap
    CHECK(received.find("6809 EXTENDED BASIC") != std::string::npos);
    CHECK(received.find("MICROSOFT") != std::string::npos);
    CHECK(received.find("OK") != std::string::npos);
}
