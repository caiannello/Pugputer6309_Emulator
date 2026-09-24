// RomDevice: reads return loaded contents, writes are true no-ops (this
// is what makes a RAM-size-detection scan -- write a probe byte, read it
// back, see it didn't "stick" -- correctly identify a mapped ROM region).
#include "test_framework.hpp"
#include "pugputer/rom_device.hpp"
#include "pugputer/system_bus.hpp"

using pugputer::IrqLine;
using pugputer::RomDevice;
using pugputer::SystemBus;

TEST(rom_device_read_returns_loaded_contents) {
    RomDevice rom(16);
    uint8_t src[16];
    for (int i = 0; i < 16; ++i) src[i] = static_cast<uint8_t>(0x40 + i);
    rom.load(src, sizeof(src));
    for (int i = 0; i < 16; ++i) CHECK(rom.read(static_cast<uint16_t>(i)) == 0x40 + i);
}

TEST(rom_device_write_is_a_true_no_op) {
    RomDevice rom(4);
    uint8_t src[4] = { 0x11, 0x22, 0x33, 0x44 };
    rom.load(src, sizeof(src));
    rom.write(0, 0xFF);
    rom.write(2, 0x00);
    CHECK(rom.read(0) == 0x11);
    CHECK(rom.read(2) == 0x33);
}

TEST(rom_device_mapped_on_system_bus_rejects_probe_writes) {
    SystemBus bus;
    RomDevice rom(0x1000); // $D000-$DFFF for this test
    uint8_t src[0x1000] = {};
    src[0] = 0x42;
    rom.load(src, sizeof(src));
    bus.map_device("rom", 0xD000, 0x1000, &rom, IrqLine::None);

    // The classic RAM-size probe: write a test pattern, read it back.
    bus.ram()[0x8000] = 0x86; bus.ram()[0x8001] = 0xAA;             // LDA #$AA
    bus.ram()[0x8002] = 0xB7; bus.ram()[0x8003] = 0xD0; bus.ram()[0x8004] = 0x00; // STA $D000
    bus.ram()[0x8005] = 0xB6; bus.ram()[0x8006] = 0xD0; bus.ram()[0x8007] = 0x00; // LDA $D000
    bus.ram()[0x8008] = 0x20; bus.ram()[0x8009] = 0xFE;             // BRA *
    bus.ram()[0xFFFE] = 0x80; bus.ram()[0xFFFF] = 0x00;

    bus.reset();
    bus.step(); // LDA #$AA
    bus.step(); // STA $D000 -- write to ROM, must not stick
    bus.step(); // LDA $D000 -- should read back the original ROM byte, not $AA

    hd6309_regs_t r{};
    hd6309_get_regs(bus.cpu(), &r);
    CHECK(r.a == 0x42); // the ROM's real content, not the probe value
    CHECK(rom.read(0) == 0x42); // and the ROM device itself was never modified
}
