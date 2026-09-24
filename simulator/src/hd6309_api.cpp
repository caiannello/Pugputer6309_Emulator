// C ABI implementation wrapping the internal CPU class, plus the
// convenience flat-RAM bus used by tests and simple standalone tools.
// HD6309_BUILD_SHARED (for dllexport) is supplied by CMake only when
// building the hd6309_shared target; the static target gets plain,
// unexported symbols.
#include "hd6309/hd6309.h"

#include <array>
#include <new>

#include "hd6309_core.hpp"

using hd6309::CPU;
using hd6309::StopReason;

struct hd6309_t {
    CPU cpu;
    hd6309_t(hd6309::ReadFn r, hd6309::WriteFn w, void* ctx) : cpu(r, w, ctx) {}
};

extern "C" {

hd6309_t* hd6309_create(hd6309_read_fn read_fn, hd6309_write_fn write_fn, void* ctx) {
    if (!read_fn || !write_fn) return nullptr;
    return new (std::nothrow) hd6309_t(read_fn, write_fn, ctx);
}

void hd6309_destroy(hd6309_t* cpu) {
    delete cpu;
}

void hd6309_reset(hd6309_t* cpu) {
    if (cpu) cpu->cpu.reset();
}

uint64_t hd6309_step(hd6309_t* cpu) {
    return cpu ? cpu->cpu.step() : 0;
}

uint64_t hd6309_run(hd6309_t* cpu, uint64_t max_cycles) {
    return cpu ? cpu->cpu.run(max_cycles) : 0;
}

hd6309_stop_reason_t hd6309_get_stop_reason(hd6309_t* cpu) {
    if (!cpu) return HD6309_STOP_CYCLE_BUDGET;
    switch (cpu->cpu.stop_reason()) {
        case StopReason::CycleBudget: return HD6309_STOP_CYCLE_BUDGET;
        case StopReason::Breakpoint: return HD6309_STOP_BREAKPOINT;
        case StopReason::IllegalOpcodeTrap: return HD6309_STOP_ILLEGAL_OPCODE_TRAP;
        case StopReason::Sync: return HD6309_STOP_SYNC;
        case StopReason::Halted: return HD6309_STOP_HALTED;
    }
    return HD6309_STOP_CYCLE_BUDGET;
}

void hd6309_halt(hd6309_t* cpu) { if (cpu) cpu->cpu.halt(); }
void hd6309_resume(hd6309_t* cpu) { if (cpu) cpu->cpu.resume(); }
int hd6309_is_halted(hd6309_t* cpu) { return cpu && cpu->cpu.halted() ? 1 : 0; }

void hd6309_set_irq(hd6309_t* cpu, int asserted) { if (cpu) cpu->cpu.set_irq(asserted != 0); }
void hd6309_set_firq(hd6309_t* cpu, int asserted) { if (cpu) cpu->cpu.set_firq(asserted != 0); }
void hd6309_nmi_pulse(hd6309_t* cpu) { if (cpu) cpu->cpu.nmi_pulse(); }

void hd6309_get_regs(hd6309_t* cpu, hd6309_regs_t* out) {
    if (!cpu || !out) return;
    const auto& r = cpu->cpu.regs();
    out->pc = r.pc; out->x = r.x; out->y = r.y; out->u = r.u; out->s = r.s; out->v = r.v;
    out->a = r.a; out->b = r.b; out->dp = r.dp; out->cc = r.cc; out->e = r.e; out->f = r.f; out->md = r.md;
}

void hd6309_set_regs(hd6309_t* cpu, const hd6309_regs_t* in) {
    if (!cpu || !in) return;
    auto& r = cpu->cpu.regs();
    r.pc = in->pc; r.x = in->x; r.y = in->y; r.u = in->u; r.s = in->s; r.v = in->v;
    r.a = in->a; r.b = in->b; r.dp = in->dp; r.cc = in->cc; r.e = in->e; r.f = in->f; r.md = in->md;
}

uint64_t hd6309_total_cycles(hd6309_t* cpu) {
    return cpu ? cpu->cpu.total_cycles() : 0;
}

int hd6309_add_breakpoint(hd6309_t* cpu, uint16_t addr) {
    return cpu ? cpu->cpu.add_breakpoint(addr) : -1;
}

void hd6309_remove_breakpoint(hd6309_t* cpu, int id) {
    if (cpu) cpu->cpu.remove_breakpoint(id);
}

void hd6309_clear_breakpoints(hd6309_t* cpu) {
    if (cpu) cpu->cpu.clear_breakpoints();
}

uint8_t hd6309_peek(hd6309_t* cpu, uint16_t addr) {
    return cpu ? cpu->cpu.peek(addr) : 0;
}

void hd6309_poke(hd6309_t* cpu, uint16_t addr, uint8_t value) {
    if (cpu) cpu->cpu.poke(addr, value);
}

// --- convenience flat-RAM bus --------------------------------------------

struct hd6309_ram_bus_t {
    std::array<uint8_t, 65536> data{};
};

hd6309_ram_bus_t* hd6309_ram_bus_create(void) {
    return new (std::nothrow) hd6309_ram_bus_t();
}

void hd6309_ram_bus_destroy(hd6309_ram_bus_t* bus) {
    delete bus;
}

uint8_t* hd6309_ram_bus_data(hd6309_ram_bus_t* bus) {
    return bus ? bus->data.data() : nullptr;
}

static uint8_t hd6309_ram_bus_read(void* ctx, uint16_t addr) {
    return static_cast<hd6309_ram_bus_t*>(ctx)->data[addr];
}

static void hd6309_ram_bus_write(void* ctx, uint16_t addr, uint8_t value) {
    static_cast<hd6309_ram_bus_t*>(ctx)->data[addr] = value;
}

hd6309_read_fn hd6309_ram_bus_read_fn(void) { return &hd6309_ram_bus_read; }
hd6309_write_fn hd6309_ram_bus_write_fn(void) { return &hd6309_ram_bus_write; }

} // extern "C"
