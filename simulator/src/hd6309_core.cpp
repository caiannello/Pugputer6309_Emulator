// Helper machinery for the HD6309 CPU core: memory/fetch, addressing
// modes, stack push/pull, register-code helpers, flag/ALU primitives,
// interrupt handling, and the top-level reset()/step()/run() loop.
//
// Opcode dispatch itself (execute/execute_page10/execute_page11) lives in
// hd6309_opcodes.cpp.
#include "hd6309_core.hpp"

#include <algorithm>

namespace hd6309 {

namespace {
constexpr uint16_t VEC_TRAP = 0xFFF0;
constexpr uint16_t VEC_SWI3 = 0xFFF2;
constexpr uint16_t VEC_SWI2 = 0xFFF4;
constexpr uint16_t VEC_FIRQ = 0xFFF6;
constexpr uint16_t VEC_IRQ = 0xFFF8;
constexpr uint16_t VEC_SWI = 0xFFFA;
constexpr uint16_t VEC_NMI = 0xFFFC;
constexpr uint16_t VEC_RESET = 0xFFFE;
} // namespace

CPU::CPU(ReadFn read_fn, WriteFn write_fn, void* ctx)
    : read_fn_(read_fn), write_fn_(write_fn), ctx_(ctx), cycles_(0) {
    reset();
}

void CPU::reset() {
    r_ = Regs{};
    r_.cc = CC_I | CC_F; // interrupts masked out of reset, matching real hardware
    r_.md = 0;           // HD6309 always resets into 6809-compatible emulation mode
    r_.pc = read16(VEC_RESET);

    irq_line_ = false;
    firq_line_ = false;
    nmi_pending_ = false;
    wait_sync_ = false;
    halted_ = false;
    cwai_pushed_pending_ = false;
    total_cycles_ = 0;
    stop_reason_ = StopReason::CycleBudget;
}

// --- memory / fetch --------------------------------------------------

uint16_t CPU::read16(uint16_t addr) {
    uint16_t hi = read8(addr);
    uint16_t lo = read8(static_cast<uint16_t>(addr + 1));
    return static_cast<uint16_t>((hi << 8) | lo);
}

void CPU::write16(uint16_t addr, uint16_t v) {
    write8(addr, static_cast<uint8_t>(v >> 8));
    write8(static_cast<uint16_t>(addr + 1), static_cast<uint8_t>(v & 0xFF));
}

uint8_t CPU::fetch8() {
    uint8_t v = read8(r_.pc);
    r_.pc = static_cast<uint16_t>(r_.pc + 1);
    return v;
}

uint16_t CPU::fetch16() {
    uint16_t hi = fetch8();
    uint16_t lo = fetch8();
    return static_cast<uint16_t>((hi << 8) | lo);
}

// --- addressing modes --------------------------------------------------

uint16_t CPU::ea_direct() {
    return static_cast<uint16_t>((r_.dp << 8) | fetch8());
}

uint16_t CPU::ea_extended() {
    return fetch16();
}

int8_t CPU::rel8() {
    return static_cast<int8_t>(fetch8());
}

int16_t CPU::rel16() {
    return static_cast<int16_t>(fetch16());
}

int CPU::indexed_extra_cycles(uint8_t pb) const {
    if ((pb & 0x80) == 0) return 1; // 5-bit offset

    switch (pb) {
        case 0x8F: return 0; // ,W
        case 0xAF: return 2; // n16,W
        case 0xCF: case 0xEF: return 1; // ,W++  ,--W
        case 0x90: return 3; // [,W]
        case 0xB0: return 5; // [n16,W]
        case 0xD0: case 0xF0: return 4; // [,W++]  [,--W]
        default: break;
    }

    // Indexed by SSSS (postbyte bits 3-0); indexed_* used when bit4=0,
    // indirect_* when bit4=1. Ground truth: lwtools-4.20/lwasm/cycle.c indtab[].
    static const int idx_em[16]   = { 2, 3, 2, 3, 0, 1, 1, 1, 1, 4, 1, 4, 1, 5, 4, -1 };
    static const int idx_nm[16]   = { 1, 2, 1, 2, 0, 1, 1, 1, 1, 3, 1, 2, 1, 3, 1, -1 };
    static const int indir_em[16] = { -1, 6, -1, 6, 3, 4, 4, 1, 4, 7, 1, 4, 4, 8, 4, 5 };
    static const int indir_nm[16] = { -1, 6, -1, 6, 3, 4, 4, 1, 4, 7, 1, 4, 4, 8, 4, 5 };

    int ssss = pb & 0x0F;
    bool indirect = (pb & 0x10) != 0;
    bool nm = native();
    int v = indirect ? (nm ? indir_nm[ssss] : indir_em[ssss]) : (nm ? idx_nm[ssss] : idx_em[ssss]);
    return v < 0 ? 0 : v; // combinations lwasm never emits; treat as zero-cost
}

int CPU::rlist_extra_cycles(uint8_t pb) const {
    int c = 0;
    for (int i = 0; i < 8; ++i) {
        if (pb & (1 << i)) c += (i <= 3) ? 1 : 2;
    }
    return c;
}

uint16_t CPU::ea_indexed() {
    uint8_t pb = fetch8();
    cycles_ += indexed_extra_cycles(pb);

    uint16_t* regs4[4] = { &r_.x, &r_.y, &r_.u, &r_.s };

    if ((pb & 0x80) == 0) {
        int off5 = pb & 0x1F;
        if (off5 & 0x10) off5 -= 32;
        return static_cast<uint16_t>(*regs4[(pb >> 5) & 3] + off5);
    }

    switch (pb) {
        case 0x8F: return r_.w();
        case 0xAF: { int16_t off = static_cast<int16_t>(fetch16()); return static_cast<uint16_t>(r_.w() + off); }
        case 0xCF: { uint16_t v = r_.w(); r_.set_w(static_cast<uint16_t>(v + 2)); return v; }
        case 0xEF: { uint16_t v = static_cast<uint16_t>(r_.w() - 2); r_.set_w(v); return v; }
        case 0x90: return read16(r_.w());
        case 0xB0: { int16_t off = static_cast<int16_t>(fetch16()); return read16(static_cast<uint16_t>(r_.w() + off)); }
        case 0xD0: { uint16_t v = r_.w(); r_.set_w(static_cast<uint16_t>(v + 2)); return read16(v); }
        case 0xF0: { uint16_t v = static_cast<uint16_t>(r_.w() - 2); r_.set_w(v); return read16(v); }
        default: break;
    }

    bool indirect = (pb & 0x10) != 0;
    int ssss = pb & 0x0F;
    uint16_t* rp = regs4[(pb >> 5) & 3];
    uint16_t addr = 0;
    switch (ssss) {
        case 0x0: addr = *rp; *rp = static_cast<uint16_t>(*rp + 1); break;               // ,R+
        case 0x1: addr = *rp; *rp = static_cast<uint16_t>(*rp + 2); break;               // ,R++
        case 0x2: *rp = static_cast<uint16_t>(*rp - 1); addr = *rp; break;               // ,-R
        case 0x3: *rp = static_cast<uint16_t>(*rp - 2); addr = *rp; break;               // ,--R
        case 0x4: addr = *rp; break;                                                     // ,R
        case 0x5: addr = static_cast<uint16_t>(*rp + static_cast<int8_t>(r_.b)); break;  // B,R
        case 0x6: addr = static_cast<uint16_t>(*rp + static_cast<int8_t>(r_.a)); break;  // A,R
        case 0x7: addr = static_cast<uint16_t>(*rp + static_cast<int8_t>(r_.e)); break;  // E,R
        case 0x8: { int8_t off = static_cast<int8_t>(fetch8()); addr = static_cast<uint16_t>(*rp + off); break; } // n8,R
        case 0x9: { int16_t off = static_cast<int16_t>(fetch16()); addr = static_cast<uint16_t>(*rp + off); break; } // n16,R
        case 0xA: addr = static_cast<uint16_t>(*rp + static_cast<int8_t>(r_.f)); break;  // F,R
        case 0xB: addr = static_cast<uint16_t>(*rp + static_cast<int16_t>(r_.d())); break; // D,R
        case 0xC: { int8_t off = static_cast<int8_t>(fetch8()); addr = static_cast<uint16_t>(r_.pc + off); break; } // n8,PCR
        case 0xD: { int16_t off = static_cast<int16_t>(fetch16()); addr = static_cast<uint16_t>(r_.pc + off); break; } // n16,PCR
        case 0xE: addr = static_cast<uint16_t>(*rp + static_cast<int16_t>(r_.w())); break; // W,R
        case 0xF: addr = fetch16(); break; // [n16], always indirect
        default: break;
    }
    if (indirect) addr = read16(addr);
    return addr;
}

// --- stack --------------------------------------------------

void CPU::push8(uint16_t& sp, uint8_t v) {
    sp = static_cast<uint16_t>(sp - 1);
    write8(sp, v);
}

uint8_t CPU::pull8(uint16_t& sp) {
    uint8_t v = read8(sp);
    sp = static_cast<uint16_t>(sp + 1);
    return v;
}

void CPU::push16(uint16_t& sp, uint16_t v) {
    push8(sp, static_cast<uint8_t>(v & 0xFF));
    push8(sp, static_cast<uint8_t>(v >> 8));
}

uint16_t CPU::pull16(uint16_t& sp) {
    uint8_t hi = pull8(sp);
    uint8_t lo = pull8(sp);
    return static_cast<uint16_t>((hi << 8) | lo);
}

// --- register-code helpers (TFR/EXG/ADDR-family/TFM; codes 0-15) -----------
// 0=D 1=X 2=Y 3=U 4=S 5=PC 6=W 7=V 8=A 9=B 10=CC 11=DP 12/13=unused 14=E 15=F

bool CPU::reg_code_is_16bit(int code) const {
    return code >= 0 && code <= 7;
}

uint16_t CPU::get_reg_by_code(int code) const {
    switch (code & 0xF) {
        case 0: return r_.d();
        case 1: return r_.x;
        case 2: return r_.y;
        case 3: return r_.u;
        case 4: return r_.s;
        case 5: return r_.pc;
        case 6: return r_.w();
        case 7: return r_.v;
        // 8-bit registers read back as $FFxx when used in a 16-bit context
        // (TFR/EXG/register-register ops) -- a documented 6809/6309 quirk.
        case 8: return static_cast<uint16_t>(0xFF00 | r_.a);
        case 9: return static_cast<uint16_t>(0xFF00 | r_.b);
        case 10: return static_cast<uint16_t>(0xFF00 | r_.cc);
        case 11: return static_cast<uint16_t>(0xFF00 | r_.dp);
        case 12: case 13: return 0xFFFF; // reserved/unused codes
        case 14: return static_cast<uint16_t>(0xFF00 | r_.e);
        default: return static_cast<uint16_t>(0xFF00 | r_.f);
    }
}

uint8_t CPU::get_reg_raw8(int code) const {
    switch (code & 0xF) {
        case 8: return r_.a;
        case 9: return r_.b;
        case 10: return r_.cc;
        case 11: return r_.dp;
        case 14: return r_.e;
        default: return r_.f; // 15; codes 12/13 (unused) also fall here, harmless
    }
}

void CPU::set_reg_by_code(int code, uint16_t v) {
    switch (code & 0xF) {
        case 0: r_.set_d(v); break;
        case 1: r_.x = v; break;
        case 2: r_.y = v; break;
        case 3: r_.u = v; break;
        case 4: r_.s = v; break;
        case 5: r_.pc = v; break;
        case 6: r_.set_w(v); break;
        case 7: r_.v = v; break;
        case 8: r_.a = static_cast<uint8_t>(v); break;
        case 9: r_.b = static_cast<uint8_t>(v); break;
        case 10: r_.cc = static_cast<uint8_t>(v); break;
        case 11: r_.dp = static_cast<uint8_t>(v); break;
        case 12: case 13: break;
        case 14: r_.e = static_cast<uint8_t>(v); break;
        default: r_.f = static_cast<uint8_t>(v); break;
    }
}

// --- flags --------------------------------------------------

void CPU::set_nz8(uint8_t v) {
    set_flag(CC_N, (v & 0x80) != 0);
    set_flag(CC_Z, v == 0);
}

void CPU::set_nz16(uint16_t v) {
    set_flag(CC_N, (v & 0x8000) != 0);
    set_flag(CC_Z, v == 0);
}

bool CPU::test_condition(uint8_t cond4) const {
    bool c = get_flag(CC_C), z = get_flag(CC_Z), v = get_flag(CC_V), n = get_flag(CC_N);
    switch (cond4 & 0xF) {
        case 0x0: return true;       // BRA
        case 0x1: return false;      // BRN
        case 0x2: return !c && !z;   // BHI
        case 0x3: return c || z;     // BLS
        case 0x4: return !c;         // BHS/BCC
        case 0x5: return c;          // BLO/BCS
        case 0x6: return !z;         // BNE
        case 0x7: return z;          // BEQ
        case 0x8: return !v;         // BVC
        case 0x9: return v;          // BVS
        case 0xA: return !n;         // BPL
        case 0xB: return n;          // BMI
        case 0xC: return n == v;     // BGE
        case 0xD: return n != v;     // BLT
        case 0xE: return !z && (n == v); // BGT
        default: return z || (n != v);   // BLE
    }
}

// --- ALU primitives --------------------------------------------------

uint8_t CPU::add8(uint8_t a, uint8_t b, bool carry_in, bool affect_h) {
    unsigned r16 = static_cast<unsigned>(a) + b + (carry_in ? 1u : 0u);
    uint8_t r8 = static_cast<uint8_t>(r16);
    if (affect_h) {
        unsigned hc = (a & 0xF) + (b & 0xF) + (carry_in ? 1u : 0u);
        set_flag(CC_H, hc > 0xF);
    }
    set_flag(CC_C, r16 > 0xFF);
    set_flag(CC_V, ((~(a ^ b)) & (a ^ r8) & 0x80) != 0);
    set_nz8(r8);
    return r8;
}

uint8_t CPU::sub8(uint8_t a, uint8_t b, bool borrow_in) {
    int diff = static_cast<int>(a) - b - (borrow_in ? 1 : 0);
    uint8_t r8 = static_cast<uint8_t>(diff);
    set_flag(CC_C, diff < 0);
    set_flag(CC_V, ((a ^ b) & (a ^ r8) & 0x80) != 0);
    set_nz8(r8);
    return r8;
}

uint16_t CPU::add16(uint16_t a, uint16_t b, bool carry_in) {
    unsigned r32 = static_cast<unsigned>(a) + b + (carry_in ? 1u : 0u);
    uint16_t r16 = static_cast<uint16_t>(r32);
    set_flag(CC_C, r32 > 0xFFFF);
    set_flag(CC_V, ((~(a ^ b)) & (a ^ r16) & 0x8000) != 0);
    set_nz16(r16);
    return r16;
}

uint16_t CPU::sub16(uint16_t a, uint16_t b, bool borrow_in) {
    int diff = static_cast<int>(a) - b - (borrow_in ? 1 : 0);
    uint16_t r16 = static_cast<uint16_t>(diff);
    set_flag(CC_C, diff < 0);
    set_flag(CC_V, ((a ^ b) & (a ^ r16) & 0x8000) != 0);
    set_nz16(r16);
    return r16;
}

uint8_t CPU::and8(uint8_t a, uint8_t b) { uint8_t r = static_cast<uint8_t>(a & b); set_flag(CC_V, false); set_nz8(r); return r; }
uint8_t CPU::or8(uint8_t a, uint8_t b)  { uint8_t r = static_cast<uint8_t>(a | b); set_flag(CC_V, false); set_nz8(r); return r; }
uint8_t CPU::eor8(uint8_t a, uint8_t b) { uint8_t r = static_cast<uint8_t>(a ^ b); set_flag(CC_V, false); set_nz8(r); return r; }
void CPU::bit8(uint8_t a, uint8_t b) { uint8_t r = static_cast<uint8_t>(a & b); set_flag(CC_V, false); set_nz8(r); }
void CPU::cmp8(uint8_t a, uint8_t b) { sub8(a, b, false); }
void CPU::cmp16(uint16_t a, uint16_t b) { sub16(a, b); }
uint16_t CPU::and16(uint16_t a, uint16_t b) { uint16_t r = static_cast<uint16_t>(a & b); set_flag(CC_V, false); set_nz16(r); return r; }
uint16_t CPU::or16(uint16_t a, uint16_t b)  { uint16_t r = static_cast<uint16_t>(a | b); set_flag(CC_V, false); set_nz16(r); return r; }
uint16_t CPU::eor16(uint16_t a, uint16_t b) { uint16_t r = static_cast<uint16_t>(a ^ b); set_flag(CC_V, false); set_nz16(r); return r; }
void CPU::bit16(uint16_t a, uint16_t b) { uint16_t r = static_cast<uint16_t>(a & b); set_flag(CC_V, false); set_nz16(r); }

uint8_t CPU::rmw8(RmwOp op, uint8_t v) {
    uint8_t r = v;
    switch (op) {
        case RmwOp::NEG: r = static_cast<uint8_t>(0 - v); set_flag(CC_C, v != 0); set_flag(CC_V, v == 0x80); set_nz8(r); break;
        case RmwOp::COM: r = static_cast<uint8_t>(~v); set_flag(CC_C, true); set_flag(CC_V, false); set_nz8(r); break;
        case RmwOp::LSR: set_flag(CC_C, (v & 1) != 0); r = static_cast<uint8_t>(v >> 1); set_nz8(r); break;
        case RmwOp::ROR: { bool oldc = get_flag(CC_C); set_flag(CC_C, (v & 1) != 0); r = static_cast<uint8_t>((v >> 1) | (oldc ? 0x80 : 0)); set_nz8(r); break; }
        case RmwOp::ASR: set_flag(CC_C, (v & 1) != 0); r = static_cast<uint8_t>((v >> 1) | (v & 0x80)); set_nz8(r); break;
        case RmwOp::ASL: { bool b7 = (v & 0x80) != 0, b6 = (v & 0x40) != 0; set_flag(CC_C, b7); set_flag(CC_V, b7 != b6); r = static_cast<uint8_t>(v << 1); set_nz8(r); break; }
        case RmwOp::ROL: { bool oldc = get_flag(CC_C); bool b7 = (v & 0x80) != 0, b6 = (v & 0x40) != 0; set_flag(CC_C, b7); set_flag(CC_V, b7 != b6); r = static_cast<uint8_t>((v << 1) | (oldc ? 1 : 0)); set_nz8(r); break; }
        case RmwOp::DEC: r = static_cast<uint8_t>(v - 1); set_flag(CC_V, v == 0x80); set_nz8(r); break;
        case RmwOp::INC: r = static_cast<uint8_t>(v + 1); set_flag(CC_V, v == 0x7F); set_nz8(r); break;
        case RmwOp::TST: set_flag(CC_V, false); set_nz8(v); r = v; break;
        case RmwOp::CLR: r = 0; set_flag(CC_N, false); set_flag(CC_Z, true); set_flag(CC_V, false); set_flag(CC_C, false); break;
    }
    return r;
}

uint16_t CPU::rmw16(RmwOp op, uint16_t v) {
    uint16_t r = v;
    switch (op) {
        case RmwOp::NEG: r = static_cast<uint16_t>(0 - v); set_flag(CC_C, v != 0); set_flag(CC_V, v == 0x8000); set_nz16(r); break;
        case RmwOp::COM: r = static_cast<uint16_t>(~v); set_flag(CC_C, true); set_flag(CC_V, false); set_nz16(r); break;
        case RmwOp::LSR: set_flag(CC_C, (v & 1) != 0); r = static_cast<uint16_t>(v >> 1); set_nz16(r); break;
        case RmwOp::ROR: { bool oldc = get_flag(CC_C); set_flag(CC_C, (v & 1) != 0); r = static_cast<uint16_t>((v >> 1) | (oldc ? 0x8000 : 0)); set_nz16(r); break; }
        case RmwOp::ASR: set_flag(CC_C, (v & 1) != 0); r = static_cast<uint16_t>((v >> 1) | (v & 0x8000)); set_nz16(r); break;
        case RmwOp::ASL: { bool b15 = (v & 0x8000) != 0, b14 = (v & 0x4000) != 0; set_flag(CC_C, b15); set_flag(CC_V, b15 != b14); r = static_cast<uint16_t>(v << 1); set_nz16(r); break; }
        case RmwOp::ROL: { bool oldc = get_flag(CC_C); bool b15 = (v & 0x8000) != 0, b14 = (v & 0x4000) != 0; set_flag(CC_C, b15); set_flag(CC_V, b15 != b14); r = static_cast<uint16_t>((v << 1) | (oldc ? 1 : 0)); set_nz16(r); break; }
        case RmwOp::DEC: r = static_cast<uint16_t>(v - 1); set_flag(CC_V, v == 0x8000); set_nz16(r); break;
        case RmwOp::INC: r = static_cast<uint16_t>(v + 1); set_flag(CC_V, v == 0x7FFF); set_nz16(r); break;
        case RmwOp::TST: set_flag(CC_V, false); set_nz16(v); r = v; break;
        case RmwOp::CLR: r = 0; set_flag(CC_N, false); set_flag(CC_Z, true); set_flag(CC_V, false); set_flag(CC_C, false); break;
    }
    return r;
}

uint8_t CPU::apply_alu8(AluOp op, uint8_t reg, uint8_t operand) {
    switch (op) {
        case AluOp::SUB: return sub8(reg, operand, false);
        case AluOp::CMP: cmp8(reg, operand); return reg;
        case AluOp::SBC: return sub8(reg, operand, get_flag(CC_C));
        case AluOp::AND: return and8(reg, operand);
        case AluOp::BIT: bit8(reg, operand); return reg;
        case AluOp::LD: set_flag(CC_V, false); set_nz8(operand); return operand;
        case AluOp::EOR: return eor8(reg, operand);
        case AluOp::ADC: return add8(reg, operand, get_flag(CC_C), true);
        case AluOp::OR: return or8(reg, operand);
        case AluOp::ADD: return add8(reg, operand, false, true);
    }
    return reg;
}

uint16_t CPU::apply_alu16(AluOp op, uint16_t reg, uint16_t operand) {
    switch (op) {
        case AluOp::SUB: return sub16(reg, operand);
        case AluOp::CMP: cmp16(reg, operand); return reg;
        case AluOp::SBC: return sub16(reg, operand, get_flag(CC_C));
        case AluOp::AND: return and16(reg, operand);
        case AluOp::BIT: bit16(reg, operand); return reg;
        case AluOp::LD: set_flag(CC_V, false); set_nz16(operand); return operand;
        case AluOp::EOR: return eor16(reg, operand);
        case AluOp::ADC: return add16(reg, operand, get_flag(CC_C));
        case AluOp::OR: return or16(reg, operand);
        case AluOp::ADD: return add16(reg, operand);
    }
    return reg;
}

// --- DAA --------------------------------------------------

void CPU::do_daa() {
    uint8_t a = r_.a;
    uint8_t lo = a & 0x0F;
    uint8_t hi = static_cast<uint8_t>((a >> 4) & 0x0F);
    uint8_t correction = 0;
    bool carry_out = get_flag(CC_C);

    if (get_flag(CC_H) || lo > 9) correction |= 0x06;
    if (carry_out || hi > 9 || (hi >= 9 && lo > 9)) { correction |= 0x60; carry_out = true; }

    unsigned result = static_cast<unsigned>(a) + correction;
    r_.a = static_cast<uint8_t>(result);
    set_flag(CC_C, carry_out);
    set_nz8(r_.a);
}

// --- TFR/EXG/TFM/BAND-family/DIVD/DIVQ/MULD --------------------------------

void CPU::do_tfr_exg(uint8_t postbyte, bool is_exg) {
    int src = (postbyte >> 4) & 0xF;
    int dst = postbyte & 0xF;
    uint16_t sv = get_reg_by_code(src);
    if (is_exg) {
        uint16_t dv = get_reg_by_code(dst);
        set_reg_by_code(dst, sv);
        set_reg_by_code(src, dv);
    } else {
        set_reg_by_code(dst, sv);
    }
}

void CPU::do_tfm(int opcode) {
    uint8_t pb = fetch8();
    int src = (pb >> 4) & 0xF;
    int dst = pb & 0xF;
    uint16_t sp = get_reg_by_code(src);
    uint16_t dp = get_reg_by_code(dst);
    int src_step = 0, dst_step = 0;
    switch (opcode) {
        case 0x1138: src_step = 1; dst_step = 1; break;  // r0+,r1+
        case 0x1139: src_step = -1; dst_step = -1; break; // r0-,r1-
        case 0x113A: src_step = 1; dst_step = 0; break;   // r0+,r1
        case 0x113B: src_step = 0; dst_step = 1; break;   // r0,r1+
        default: break;
    }

    uint16_t count = r_.w();
    cycles_ += 6; // base overhead; see README for TFM timing caveat
    bool interrupted = false;
    while (count != 0) {
        uint8_t v = read8(sp);
        write8(dp, v);
        sp = static_cast<uint16_t>(sp + src_step);
        dp = static_cast<uint16_t>(dp + dst_step);
        --count;
        cycles_ += 3;
        set_reg_by_code(src, sp);
        set_reg_by_code(dst, dp);
        r_.set_w(count);
        if (count != 0 && (nmi_pending_ || (firq_line_ && !get_flag(CC_F)) || (irq_line_ && !get_flag(CC_I)))) {
            interrupted = true;
            break;
        }
    }
    if (interrupted) {
        // Real HD6309 TFM is interruptible: re-execute this instruction next
        // step() so it resumes from the (already updated) registers/count.
        r_.pc = insn_pc_;
    }
}

void CPU::do_bitbit(int opcode) {
    uint8_t pb = fetch8();
    int reg_sel = (pb >> 6) & 0x3;
    int membit = (pb >> 3) & 0x7;
    int regbit = pb & 0x7;
    uint16_t addr = ea_direct();
    uint8_t mem = read8(addr);
    bool mbit = ((mem >> membit) & 1) != 0;

    uint8_t* regp = &r_.cc;
    if (reg_sel == 1) regp = &r_.a;
    else if (reg_sel == 2) regp = &r_.b;

    bool rbit = ((*regp >> regbit) & 1) != 0;

    switch (opcode) {
        case 0x1130: rbit = rbit && mbit; break;   // BAND
        case 0x1131: rbit = rbit && !mbit; break;  // BIAND
        case 0x1132: rbit = rbit || mbit; break;   // BOR
        case 0x1133: rbit = rbit || !mbit; break;  // BIOR
        case 0x1134: rbit = rbit != mbit; break;   // BEOR
        case 0x1135: rbit = rbit != !mbit; break;  // BIEOR
        case 0x1136: rbit = mbit; break;           // LDBT
        case 0x1137: {                             // STBT: mem bit = reg bit
            uint8_t newmem = static_cast<uint8_t>((mem & ~(1u << membit)) | (rbit ? (1u << membit) : 0));
            write8(addr, newmem);
            cycles_ += native() ? 7 : 8;
            return;
        }
        default: break;
    }
    *regp = static_cast<uint8_t>((*regp & ~(1u << regbit)) | (rbit ? (1u << regbit) : 0));
    cycles_ += native() ? 6 : 7;
}

void CPU::do_divd(uint8_t divisor) {
    if (divisor == 0) { division_by_zero_trap(); return; }
    int16_t dividend = static_cast<int16_t>(r_.d());
    int div = static_cast<int8_t>(divisor);
    int quotient = dividend / div;
    int remainder = dividend % div;
    bool overflow = (quotient < -128 || quotient > 127);
    r_.b = static_cast<uint8_t>(quotient);
    r_.a = static_cast<uint8_t>(remainder);
    set_flag(CC_V, overflow);
    set_flag(CC_C, false);
    set_nz8(r_.b);
}

void CPU::do_divq(uint16_t divisor) {
    if (divisor == 0) { division_by_zero_trap(); return; }
    int32_t sdividend = static_cast<int32_t>(r_.q());
    int32_t div = static_cast<int16_t>(divisor);
    int32_t quotient = sdividend / div;
    int32_t remainder = sdividend % div;
    bool overflow = (quotient < -32768 || quotient > 32767);
    r_.set_d(static_cast<uint16_t>(quotient));
    r_.set_w(static_cast<uint16_t>(remainder));
    set_flag(CC_V, overflow);
    set_flag(CC_C, false);
    set_nz16(r_.d());
}

void CPU::do_muld(uint16_t multiplier) {
    int32_t a = static_cast<int16_t>(r_.d());
    int32_t b = static_cast<int16_t>(multiplier);
    int32_t result = a * b;
    r_.set_q(static_cast<uint32_t>(result));
    set_flag(CC_N, result < 0);
    set_flag(CC_Z, result == 0);
    set_flag(CC_V, false);
    set_flag(CC_C, false);
}

// --- interrupts --------------------------------------------------

void CPU::push_full_set() {
    set_flag(CC_E, true);
    push16(r_.s, r_.pc);
    push16(r_.s, r_.u);
    push16(r_.s, r_.y);
    push16(r_.s, r_.x);
    push8(r_.s, r_.dp);
    if (native()) {
        push8(r_.s, r_.f);
        push8(r_.s, r_.e);
    }
    push8(r_.s, r_.b);
    push8(r_.s, r_.a);
    push8(r_.s, r_.cc);
}

void CPU::push_partial_set() {
    set_flag(CC_E, false);
    push16(r_.s, r_.pc);
    push8(r_.s, r_.cc);
}

void CPU::enter_interrupt(uint16_t vector, uint8_t cc_set_mask, bool full_stack) {
    bool skip_push = cwai_pushed_pending_;
    cwai_pushed_pending_ = false;
    if (!skip_push) {
        if (full_stack) push_full_set();
        else push_partial_set();
    }
    r_.cc |= cc_set_mask;
    r_.pc = read16(vector);
}

void CPU::illegal_opcode_trap() {
    r_.md |= MD_ILLEGAL;
    enter_interrupt(VEC_TRAP, static_cast<uint8_t>(CC_I | CC_F), true);
    stop_reason_ = StopReason::IllegalOpcodeTrap;
    cycles_ += native() ? 21 : 19; // approximated on the SWI entry cost; see README
}

void CPU::division_by_zero_trap() {
    r_.md |= MD_DIVZERO;
    enter_interrupt(VEC_TRAP, static_cast<uint8_t>(CC_I | CC_F), true);
    stop_reason_ = StopReason::IllegalOpcodeTrap;
    cycles_ += native() ? 21 : 19;
}

bool CPU::service_interrupts() {
    if (nmi_pending_) {
        nmi_pending_ = false;
        wait_sync_ = false;
        enter_interrupt(VEC_NMI, static_cast<uint8_t>(CC_I | CC_F), true);
        cycles_ += native() ? 21 : 19;
        return true;
    }
    if (firq_line_ && !get_flag(CC_F)) {
        wait_sync_ = false;
        bool full = (r_.md & MD_FIRQ_NATIVE) != 0;
        enter_interrupt(VEC_FIRQ, static_cast<uint8_t>(CC_I | CC_F), full);
        cycles_ += full ? (native() ? 21 : 19) : (native() ? 8 : 10);
        return true;
    }
    if (irq_line_ && !get_flag(CC_I)) {
        wait_sync_ = false;
        enter_interrupt(VEC_IRQ, CC_I, true);
        cycles_ += native() ? 21 : 19;
        return true;
    }
    return false;
}

// --- breakpoints --------------------------------------------------

int CPU::add_breakpoint(uint16_t addr) {
    int id = next_bp_id_++;
    breakpoints_.push_back({ id, addr });
    return id;
}

void CPU::remove_breakpoint(int id) {
    breakpoints_.erase(std::remove_if(breakpoints_.begin(), breakpoints_.end(),
                                       [id](const Breakpoint& b) { return b.id == id; }),
                        breakpoints_.end());
}

// --- top-level step/run --------------------------------------------------

uint64_t CPU::step() {
    cycles_ = 0;
    stop_reason_ = StopReason::CycleBudget;

    if (halted_) {
        stop_reason_ = StopReason::Halted;
        return 0;
    }

    if (service_interrupts()) {
        total_cycles_ += cycles_;
        return cycles_;
    }

    if (wait_sync_) {
        cycles_ = 1;
        total_cycles_ += cycles_;
        stop_reason_ = StopReason::Sync;
        return cycles_;
    }

    insn_pc_ = r_.pc;
    uint8_t opcode = fetch8();
    execute(opcode);

    total_cycles_ += cycles_;
    return cycles_;
}

uint64_t CPU::run(uint64_t max_cycles) {
    uint64_t consumed = 0;
    stop_reason_ = StopReason::CycleBudget;
    while (consumed < max_cycles) {
        if (halted_) {
            stop_reason_ = StopReason::Halted;
            return consumed;
        }
        for (const auto& bp : breakpoints_) {
            if (bp.addr == r_.pc) {
                stop_reason_ = StopReason::Breakpoint;
                return consumed;
            }
        }
        consumed += step();
    }
    stop_reason_ = StopReason::CycleBudget;
    return consumed;
}

} // namespace hd6309
