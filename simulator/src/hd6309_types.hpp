// Internal register/flag definitions shared across the CPU core.
#pragma once

#include <cstdint>

namespace hd6309 {

// CC (condition code) register bits.
enum CCBit : uint8_t {
    CC_C = 0x01, // carry
    CC_V = 0x02, // overflow
    CC_Z = 0x04, // zero
    CC_N = 0x08, // negative
    CC_I = 0x10, // IRQ mask
    CC_H = 0x20, // half carry
    CC_F = 0x40, // FIRQ mask
    CC_E = 0x80, // entire (full register set stacked)
};

// MD (6309 mode) register bits.
enum MDBit : uint8_t {
    MD_NATIVE = 0x01,      // 0=emulation(6809-compatible), 1=native
    MD_FIRQ_NATIVE = 0x02, // 1=FIRQ stacks the full register set like IRQ
    MD_ILLEGAL = 0x40,     // set by illegal-opcode trap, cleared by BITMD test
    MD_DIVZERO = 0x80,     // set by division-by-zero trap, cleared by BITMD test
};

struct Regs {
    uint16_t pc = 0, x = 0, y = 0, u = 0, s = 0, v = 0;
    uint8_t a = 0, b = 0, dp = 0, cc = 0, e = 0, f = 0, md = 0;

    uint16_t d() const { return static_cast<uint16_t>((a << 8) | b); }
    void set_d(uint16_t val) {
        a = static_cast<uint8_t>(val >> 8);
        b = static_cast<uint8_t>(val & 0xFF);
    }
    uint16_t w() const { return static_cast<uint16_t>((e << 8) | f); }
    void set_w(uint16_t val) {
        e = static_cast<uint8_t>(val >> 8);
        f = static_cast<uint8_t>(val & 0xFF);
    }
    uint32_t q() const { return (static_cast<uint32_t>(d()) << 16) | w(); }
    void set_q(uint32_t val) {
        set_d(static_cast<uint16_t>(val >> 16));
        set_w(static_cast<uint16_t>(val & 0xFFFF));
    }
};

using ReadFn = uint8_t (*)(void*, uint16_t);
using WriteFn = void (*)(void*, uint16_t, uint8_t);

// Shared read-modify-write ALU operations (NEG/COM/LSR/ROR/ASR/ASL/ROL/
// DEC/INC/TST/CLR), used for both 8-bit (A/B/E/F/mem) and 16-bit (D/W/mem)
// widths so the flag logic lives in one place.
enum class RmwOp { NEG, COM, LSR, ROR, ASR, ASL, ROL, DEC, INC, TST, CLR };

// Shared "accumulator OP memory-operand" ALU ops (the SUBx/CMPx/.../ADDx
// families), parametrized so the addressing-mode dispatch code in
// hd6309_opcodes.cpp doesn't need to repeat the flag logic per register.
enum class AluOp { SUB, CMP, SBC, AND, BIT, LD, EOR, ADC, OR, ADD };

enum class StopReason {
    CycleBudget = 0,
    Breakpoint = 1,
    IllegalOpcodeTrap = 2,
    Sync = 3,
    Halted = 4,
};

} // namespace hd6309
