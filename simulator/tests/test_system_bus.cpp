// SystemBus dispatch (RAM fallback vs mapped devices) and interrupt-line
// aggregation, tested against a small mock IDevice so it's independent
// of any real device's behavior.
#include "test_framework.hpp"
#include "pugputer/system_bus.hpp"

using pugputer::DeviceMapping;
using pugputer::IDevice;
using pugputer::IrqLine;
using pugputer::SystemBus;

namespace {

class MockDevice : public IDevice {
public:
    uint8_t read(uint16_t offset) override {
        last_read_offset = offset;
        ++read_count;
        return regs[offset & 0x3];
    }
    void write(uint16_t offset, uint8_t value) override {
        last_write_offset = offset;
        last_write_value = value;
        regs[offset & 0x3] = value;
    }
    void reset() override { ++reset_count; }
    void tick(uint32_t cpu_cycles) override { last_tick_cycles = cpu_cycles; ++tick_count; }
    bool irq_asserted() const override { return irq; }

    uint8_t regs[4] = { 0, 0, 0, 0 };
    uint16_t last_read_offset = 0xFFFF, last_write_offset = 0xFFFF;
    uint8_t last_write_value = 0;
    int read_count = 0;
    int reset_count = 0;
    int tick_count = 0;
    uint32_t last_tick_cycles = 0;
    bool irq = false;
};

} // namespace

TEST(unmapped_address_falls_through_to_ram) {
    SystemBus bus;
    bus.ram()[0x1000] = 0x42;
    // Boot a tiny program that reads $1000 into A and halts by looping.
    bus.ram()[0x8000] = 0xB6; bus.ram()[0x8001] = 0x10; bus.ram()[0x8002] = 0x00; // LDA $1000
    bus.ram()[0x8003] = 0x20; bus.ram()[0x8004] = 0xFE;                          // BRA *
    bus.ram()[0xFFFE] = 0x80; bus.ram()[0xFFFF] = 0x00;
    bus.reset();
    bus.step();
    hd6309_regs_t r{};
    hd6309_get_regs(bus.cpu(), &r);
    CHECK(r.a == 0x42);
}

TEST(mapped_device_intercepts_its_window) {
    SystemBus bus;
    MockDevice dev;
    bus.map_device("mock", 0xFFE8, 4, &dev);

    bus.ram()[0x8000] = 0x86; bus.ram()[0x8001] = 0x99;             // LDA #$99
    bus.ram()[0x8002] = 0xB7; bus.ram()[0x8003] = 0xFF; bus.ram()[0x8004] = 0xE9; // STA $FFE9
    bus.ram()[0x8005] = 0x20; bus.ram()[0x8006] = 0xFE;             // BRA *
    bus.ram()[0xFFFE] = 0x80; bus.ram()[0xFFFF] = 0x00;
    bus.reset();
    bus.step(); // LDA
    bus.step(); // STA
    CHECK(dev.last_write_offset == 1); // $FFE9 - $FFE8 = offset 1
    CHECK(dev.last_write_value == 0x99);
    // Underlying RAM at $FFE9 must be untouched -- the device owns this window.
    CHECK(bus.ram()[0xFFE9] == 0);
}

TEST(reset_resets_every_mapped_device) {
    SystemBus bus;
    MockDevice dev;
    bus.map_device("mock", 0xFF00, 16, &dev);
    bus.reset();
    CHECK(dev.reset_count == 1);
}

TEST(step_ticks_every_device_with_the_actual_cycle_count) {
    SystemBus bus;
    MockDevice dev;
    bus.map_device("mock", 0xFF00, 16, &dev);
    bus.ram()[0x8000] = 0x12; // NOP (2 cycles in emulation mode)
    bus.ram()[0xFFFE] = 0x80; bus.ram()[0xFFFF] = 0x00;
    bus.reset();
    uint64_t cycles = bus.step();
    CHECK(dev.tick_count == 1);
    CHECK(dev.last_tick_cycles == cycles);
}

TEST(irq_line_is_or_of_devices_mapped_to_it_and_respects_cpu_mask) {
    SystemBus bus;
    MockDevice dev;
    bus.map_device("mock", 0xFF00, 16, &dev, IrqLine::IRQ);

    bus.ram()[0x8000] = 0x12; // NOP, IRQ still masked after reset
    bus.ram()[0x8001] = 0x1C; bus.ram()[0x8002] = 0xEF; // ANDCC #$EF (unmask IRQ)
    bus.ram()[0x8003] = 0x12; // NOP
    bus.ram()[0xFFFE] = 0x80; bus.ram()[0xFFFF] = 0x00;
    bus.ram()[0xFFF8] = 0x90; bus.ram()[0xFFF9] = 0x00; // IRQ vector -> $9000
    bus.ram()[0x9000] = 0x3B; // RTI

    bus.reset();
    hd6309_regs_t r{};
    hd6309_get_regs(bus.cpu(), &r); // capture the real post-reset state (PC from vector, CC masked, ...)
    r.s = 0x7F00;
    hd6309_set_regs(bus.cpu(), &r);

    dev.irq = true;
    bus.step(); // NOP -- masked, must not vector
    hd6309_get_regs(bus.cpu(), &r);
    CHECK(r.pc == 0x8001);

    bus.step(); // ANDCC: unmask
    bus.step(); // now the still-asserted mock IRQ should be serviced instead of the NOP at $8003
    hd6309_get_regs(bus.cpu(), &r);
    CHECK(r.pc == 0x9000);
}
