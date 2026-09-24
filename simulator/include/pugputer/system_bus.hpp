// Ties an HD6309 CPU (via the existing hd6309.h C API) to a banked RAM
// backing store plus zero or more memory-mapped IO devices. The device
// mapping list (name, address window, IrqLine) *is* the "system-level
// metadata" describing how each device is wired in -- reconfiguring or
// adding devices later is a map_device() call, not a change to the bus's
// dispatch logic.
//
// RAM banking (Pugputer6309 hardware): the CPU's 64KB address space is four
// 16KB banks. A CPU address's top two bits (A15,A14) pick one of four 8-bit
// bank registers; its contents are physical address bits A21..A14, and the
// CPU's own A13..A0 supply the offset within the 16KB page. So each bank can
// be pointed at any of 256 pages (a 22-bit, 4MB space), of which
// `ram_pages` (default 64 = 1MB) are populated. The registers are
// write-only on the real board. ROM and IO are decoded from the CPU address
// alone, so they are unaffected by banking: any device mapped with
// map_device() takes priority over the banked RAM at its addresses.
#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <memory>
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
    static constexpr size_t kPageSize = 16384;     // one bank's worth of RAM
    static constexpr size_t kAddressablePages = 256; // 8-bit bank register -> 22-bit physical space
    static constexpr uint16_t kBankRegistersBase = 0xFFEC; // 4 registers, banks 0..3

    // `ram_pages` = how many 16KB pages of RAM are installed (default 64 = 1MB).
    explicit SystemBus(size_t ram_pages = 64);
    ~SystemBus();
    SystemBus(const SystemBus&) = delete;
    SystemBus& operator=(const SystemBus&) = delete;

    // Maps `device` at [base, base+size) and records how its interrupt
    // output (if any) is wired to the CPU. Later mappings take priority
    // over earlier ones that overlap the same address (last-registered
    // wins), and any address not covered by a mapping falls through to
    // the banked RAM.
    void map_device(const std::string& name, uint16_t base, uint16_t size, IDevice* device,
                     IrqLine irq_line = IrqLine::None);
    void unmap_device(const std::string& name);
    const std::vector<DeviceMapping>& mappings() const { return devices_; }

    // Physical RAM. ram() is the start of physical page 0, so ram()[a] for
    // a < 64KB is what the CPU sees at address a *while the banks are still at
    // their reset mapping (banks 0..3 -> pages 0..3)* -- convenient for
    // loading an image or poking a test value. Once a program has remapped a
    // bank, use phys_ram() (physical addresses) or read_cpu()/write_cpu()
    // (through the current banking).
    uint8_t* ram() { return ram_.data(); }
    const uint8_t* ram() const { return ram_.data(); }
    uint8_t* phys_ram() { return ram_.data(); }
    size_t ram_pages() const { return ram_.size() / kPageSize; }

    // Makes the four bank registers visible to the CPU at `base`..base+3
    // (write-only; a read returns $FF, which is not a defined value on the
    // real board -- don't depend on it). Until this is called the registers
    // can't be written, so the banks stay at their reset mapping.
    void map_bank_registers(uint16_t base = kBankRegistersBase);

    // Current value of bank register `bank` (0..3). Simulator-side only: the
    // real registers can't be read, which is why the BIOS keeps shadow copies.
    uint8_t bank_register(int bank) const { return bank_regs_[bank & 3]; }

    // What the CPU would read/write at `addr` right now: devices first, then
    // banked RAM. (Same path the CPU takes, side effects included.)
    uint8_t read_cpu(uint16_t addr) { return read8(addr); }
    void write_cpu(uint16_t addr, uint8_t value) { write8(addr, value); }

    hd6309_t* cpu() { return cpu_; }

    // Resets the CPU and every mapped device. RAM contents are left
    // alone (matching hd6309_reset()'s own CPU-register-only semantics)
    // -- callers that want a clean RAM state should clear ram() first.
    // Bank registers return to banks 0..3 -> pages 0..3. (The real
    // registers power up undefined; the BIOS writes all four during its own
    // reset code, so nothing may depend on this.)
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
    class BankRegisters;

    hd6309_t* cpu_;
    std::vector<uint8_t> ram_; // installed physical RAM, page 0 first
    std::array<uint8_t, 4> bank_regs_{ 0, 1, 2, 3 };
    std::unique_ptr<BankRegisters> bank_device_;
    std::vector<DeviceMapping> devices_;
    bool nmi_prev_ = false; // for edge-detecting a device's NMI output

    // Physical byte for a CPU address through the banks; nullptr if that
    // page isn't installed (reads then float high, writes are dropped).
    uint8_t* phys_byte(uint16_t addr) {
        size_t page = bank_regs_[addr >> 14];
        if (page >= ram_pages()) return nullptr;
        return &ram_[page * kPageSize + (addr & (kPageSize - 1))];
    }

    uint8_t read8(uint16_t addr);
    void write8(uint16_t addr, uint8_t value);
    void update_irq_lines();
    DeviceMapping* find_mapping(uint16_t addr);

    static uint8_t s_read(void* ctx, uint16_t addr);
    static void s_write(void* ctx, uint16_t addr, uint8_t value);
};

} // namespace pugputer
