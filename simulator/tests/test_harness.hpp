// Shared test scaffolding: a CPU wired to a flat 64KB RAM bus (via the
// convenience bus in hd6309.h), plus small helpers for loading code and
// poking the reset vector. Every test goes through the public C API,
// exactly as an external consumer of this library would.
#pragma once

#include <cstdint>
#include <initializer_list>

#include "hd6309/hd6309.h"

struct Harness {
    hd6309_ram_bus_t* bus;
    hd6309_t* cpu;

    Harness() {
        bus = hd6309_ram_bus_create();
        cpu = hd6309_create(hd6309_ram_bus_read_fn(), hd6309_ram_bus_write_fn(), bus);
    }
    ~Harness() {
        hd6309_destroy(cpu);
        hd6309_ram_bus_destroy(bus);
    }
    Harness(const Harness&) = delete;
    Harness& operator=(const Harness&) = delete;

    uint8_t* mem() { return hd6309_ram_bus_data(bus); }

    void load(uint16_t addr, std::initializer_list<uint8_t> bytes) {
        uint8_t* m = mem();
        uint16_t a = addr;
        for (uint8_t b : bytes) m[a++] = b;
    }

    void poke16(uint16_t addr, uint16_t v) {
        uint8_t* m = mem();
        m[addr] = static_cast<uint8_t>(v >> 8);
        m[static_cast<uint16_t>(addr + 1)] = static_cast<uint8_t>(v & 0xFF);
    }

    void set_reset_vector(uint16_t addr) { poke16(0xFFFE, addr); }

    // Loads code at `addr`, points the reset vector at it, and resets.
    void boot_at(uint16_t addr, std::initializer_list<uint8_t> bytes) {
        load(addr, bytes);
        set_reset_vector(addr);
        hd6309_reset(cpu);
    }

    hd6309_regs_t regs() {
        hd6309_regs_t r{};
        hd6309_get_regs(cpu, &r);
        return r;
    }
    void set_regs(const hd6309_regs_t& r) { hd6309_set_regs(cpu, &r); }

    void set_native(bool on) {
        hd6309_regs_t r = regs();
        if (on) r.md |= 0x01; else r.md &= static_cast<uint8_t>(~0x01);
        set_regs(r);
    }
};
