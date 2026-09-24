// Ties an HD6309 CPU (via the existing hd6309.h C API) to a flat 64KB RAM
// backing store plus zero or more memory-mapped IO devices. The device
// mapping list (name, address window, IrqLine) *is* the "system-level
// metadata" describing how each device is wired in -- reconfiguring or
// adding devices later is a map_device() call, not a change to the bus's
// dispatch logic.
#pragma once

#include <array>
#include <cstdint>
#include <string>
#include <vector>

#include "hd6309/hd6309.h"
#include "pugputer/device.hpp"

namespace pugputer {

struct DeviceMapping {
    std::string name;
    uint16_t base;
    uint16_t size; // window is [base, base+size); must not exceed the address space
    IDevice* device; // not owned
    IrqLine irq_line = IrqLine::None;
};

class SystemBus {
public:
    SystemBus();
    ~SystemBus();
    SystemBus(const SystemBus&) = delete;
    SystemBus& operator=(const SystemBus&) = delete;

    // Maps `device` at [base, base+size) and records how its interrupt
    // output (if any) is wired to the CPU. Later mappings take priority
    // over earlier ones that overlap the same address (last-registered
    // wins), and any address not covered by a mapping falls through to
    // the flat RAM array.
    void map_device(const std::string& name, uint16_t base, uint16_t size, IDevice* device,
                     IrqLine irq_line = IrqLine::None);
    void unmap_device(const std::string& name);
    const std::vector<DeviceMapping>& mappings() const { return devices_; }

    uint8_t* ram() { return ram_.data(); }        // raw 64KB array, e.g. for loading a ROM/program image directly
    const uint8_t* ram() const { return ram_.data(); }
    hd6309_t* cpu() { return cpu_; }

    // Resets the CPU and every mapped device. RAM contents are left
    // alone (matching hd6309_reset()'s own CPU-register-only semantics)
    // -- callers that want a clean RAM state should clear ram() first.
    void reset();

    // Executes exactly one CPU instruction, ticks every mapped device by
    // the cycles that instruction consumed, then recomputes and pushes
    // each interrupt line. Returns the cycle count, same as hd6309_step().
    uint64_t step();

    // Loops step() until max_cycles have been consumed. No breakpoint
    // support here (that's simple for a caller to add itself by checking
    // hd6309_get_regs(bus.cpu()).pc between step() calls) -- kept
    // deliberately simple.
    uint64_t run(uint64_t max_cycles);

private:
    hd6309_t* cpu_;
    std::array<uint8_t, 65536> ram_{};
    std::vector<DeviceMapping> devices_;
    bool nmi_prev_ = false; // for edge-detecting a device's NMI output

    uint8_t read8(uint16_t addr);
    void write8(uint16_t addr, uint8_t value);
    void update_irq_lines();
    DeviceMapping* find_mapping(uint16_t addr);

    static uint8_t s_read(void* ctx, uint16_t addr);
    static void s_write(void* ctx, uint16_t addr, uint8_t value);
};

} // namespace pugputer
