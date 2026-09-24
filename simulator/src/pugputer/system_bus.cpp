#include "pugputer/system_bus.hpp"

#include <algorithm>

namespace pugputer {

// The four write-only bank registers, as seen by the CPU.
class SystemBus::BankRegisters : public IDevice {
public:
    explicit BankRegisters(std::array<uint8_t, 4>& regs) : regs_(regs) {}
    uint8_t read(uint16_t) override { return 0xFF; } // write-only on the real board
    void write(uint16_t offset, uint8_t value) override { regs_[offset & 3] = value; }
    void reset() override {} // SystemBus::reset() restores the registers itself

private:
    std::array<uint8_t, 4>& regs_;
};

SystemBus::SystemBus(size_t ram_pages)
    : ram_(std::min(ram_pages, kAddressablePages) * kPageSize, 0) {
    if (ram_pages < 4) ram_.resize(4 * kPageSize, 0); // the reset mapping needs pages 0..3
    cpu_ = hd6309_create(&SystemBus::s_read, &SystemBus::s_write, this);
}

SystemBus::~SystemBus() {
    hd6309_destroy(cpu_);
}

void SystemBus::map_bank_registers(uint16_t base) {
    if (!bank_device_) bank_device_ = std::make_unique<BankRegisters>(bank_regs_);
    map_device("bank_registers", base, 4, bank_device_.get());
}

void SystemBus::map_device(const std::string& name, uint16_t base, uint16_t size, IDevice* device,
                            IrqLine irq_line) {
    unmap_device(name); // replace any existing mapping with the same name
    devices_.push_back({ name, base, size, device, irq_line });
}

void SystemBus::unmap_device(const std::string& name) {
    devices_.erase(std::remove_if(devices_.begin(), devices_.end(),
                                   [&](const DeviceMapping& m) { return m.name == name; }),
                    devices_.end());
}

DeviceMapping* SystemBus::find_mapping(uint16_t addr) {
    // Last-registered mapping wins on overlap: scan back-to-front.
    for (auto it = devices_.rbegin(); it != devices_.rend(); ++it) {
        uint32_t base = it->base;
        uint32_t end = base + it->size; // may exceed 0xFFFF for a mapping that runs to the top of the space
        if (addr >= base && addr < end) return &(*it);
    }
    return nullptr;
}

uint8_t SystemBus::read8(uint16_t addr) {
    if (DeviceMapping* m = find_mapping(addr)) {
        return m->device->read(static_cast<uint16_t>(addr - m->base));
    }
    uint8_t* p = phys_byte(addr);
    return p ? *p : 0xFF; // an uninstalled page floats high
}

void SystemBus::write8(uint16_t addr, uint8_t value) {
    if (DeviceMapping* m = find_mapping(addr)) {
        m->device->write(static_cast<uint16_t>(addr - m->base), value);
        return;
    }
    if (uint8_t* p = phys_byte(addr)) *p = value;
}

uint8_t SystemBus::s_read(void* ctx, uint16_t addr) {
    return static_cast<SystemBus*>(ctx)->read8(addr);
}

void SystemBus::s_write(void* ctx, uint16_t addr, uint8_t value) {
    static_cast<SystemBus*>(ctx)->write8(addr, value);
}

void SystemBus::reset() {
    hd6309_reset(cpu_);
    bank_regs_ = { 0, 1, 2, 3 };
    for (auto& m : devices_) m.device->reset();
    nmi_prev_ = false;
}

void SystemBus::update_irq_lines() {
    bool irq = false, firq = false, nmi = false;
    for (const auto& m : devices_) {
        bool asserted = m.device->irq_asserted();
        if (m.irq_line == IrqLine::IRQ) irq = irq || asserted;
        else if (m.irq_line == IrqLine::FIRQ) firq = firq || asserted;
        else if (m.irq_line == IrqLine::NMI) nmi = nmi || asserted;
    }
    hd6309_set_irq(cpu_, irq ? 1 : 0);
    hd6309_set_firq(cpu_, firq ? 1 : 0);
    if (nmi && !nmi_prev_) hd6309_nmi_pulse(cpu_);
    nmi_prev_ = nmi;
}

uint64_t SystemBus::step() {
    uint64_t cycles = hd6309_step(cpu_);
    for (auto& m : devices_) m.device->tick(static_cast<uint32_t>(cycles));
    update_irq_lines();
    return cycles;
}

uint64_t SystemBus::run(uint64_t max_cycles) {
    uint64_t consumed = 0;
    while (consumed < max_cycles) {
        if (hd6309_is_halted(cpu_)) break;
        consumed += step();
    }
    return consumed;
}

} // namespace pugputer
