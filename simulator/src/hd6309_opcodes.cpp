// Opcode dispatch for all three pages (unprefixed, $10-prefixed,
// $11-prefixed). Opcode assignments and per-addressing-mode cycle counts
// (both 6809-emulation and 6309-native) are taken directly from the
// HD6309-mode cross-assembler lwasm (William Astle's lwtools,
// lwasm/{instab.c,cycle.c}), which is ground truth rather
// than the OCR'd programming manual. See simulator/README.md for the
// handful of documented approximations (interrupt response latency, TFM
// per-byte cost, DIVD/DIVQ/MULD's less-documented flag corners).
#include "hd6309_core.hpp"

namespace hd6309 {

// ============================================================================
// 8-bit "accumulator OP operand" family (SUBA/CMPA/.../ADDA and B/E/F
// equivalents). The cycle pattern is identical across every op within a
// given family, so one macro per addressing mode covers all of them; REG
// is a plain lvalue (r_.a, r_.b, r_.e or r_.f).
// ============================================================================
#define ALU8_IMM(OPC, REG, OP, C) \
    case OPC: { uint8_t v = fetch8(); REG = apply_alu8(AluOp::OP, REG, v); cycles_ += C; break; }
#define ALU8_DIR(OPC, REG, OP, EM, NM) \
    case OPC: { uint16_t a = ea_direct(); uint8_t v = read8(a); REG = apply_alu8(AluOp::OP, REG, v); cycles_ += native() ? (NM) : (EM); break; }
#define ALU8_IDX(OPC, REG, OP, C) \
    case OPC: { uint16_t a = ea_indexed(); uint8_t v = read8(a); REG = apply_alu8(AluOp::OP, REG, v); cycles_ += C; break; }
#define ALU8_EXT(OPC, REG, OP, EM, NM) \
    case OPC: { uint16_t a = ea_extended(); uint8_t v = read8(a); REG = apply_alu8(AluOp::OP, REG, v); cycles_ += native() ? (NM) : (EM); break; }

#define ST8_DIR(OPC, REG, EM, NM) \
    case OPC: { uint16_t a = ea_direct(); write8(a, REG); set_flag(CC_V, false); set_nz8(REG); cycles_ += native() ? (NM) : (EM); break; }
#define ST8_IDX(OPC, REG, C) \
    case OPC: { uint16_t a = ea_indexed(); write8(a, REG); set_flag(CC_V, false); set_nz8(REG); cycles_ += C; break; }
#define ST8_EXT(OPC, REG, EM, NM) \
    case OPC: { uint16_t a = ea_extended(); write8(a, REG); set_flag(CC_V, false); set_nz8(REG); cycles_ += native() ? (NM) : (EM); break; }

// ============================================================================
// 8-bit read-modify-write memory family (NEG/COM/LSR/ROR/ASR/ASL/ROL/DEC/INC/CLR/TST)
// ============================================================================
#define RMW8_DIR(OPC, OP) \
    case OPC: { uint16_t a = ea_direct(); write8(a, rmw8(RmwOp::OP, read8(a))); cycles_ += native() ? 5 : 6; break; }
#define RMW8_IDX(OPC, OP) \
    case OPC: { uint16_t a = ea_indexed(); write8(a, rmw8(RmwOp::OP, read8(a))); cycles_ += 6; break; }
#define RMW8_EXT(OPC, OP) \
    case OPC: { uint16_t a = ea_extended(); write8(a, rmw8(RmwOp::OP, read8(a))); cycles_ += native() ? 6 : 7; break; }
#define RMW8_INH(OPC, OP, REG, C) \
    case OPC: { REG = rmw8(RmwOp::OP, REG); cycles_ += C; break; }

// ============================================================================
// 16-bit read-modify-write inherent family (D and W registers only)
// ============================================================================
#define RMW16D_INH(OPC, OP) \
    case OPC: { r_.set_d(rmw16(RmwOp::OP, r_.d())); cycles_ += native() ? 2 : 3; break; }
#define RMW16W_INH(OPC, OP) \
    case OPC: { r_.set_w(rmw16(RmwOp::OP, r_.w())); cycles_ += native() ? 2 : 3; break; }

// ============================================================================
// 8-bit inherent RMW subset used by E and F (COM/DEC/INC/TST/CLR only)
// ============================================================================
#define RMW8E_INH(OPC, OP) \
    case OPC: { r_.e = rmw8(RmwOp::OP, r_.e); cycles_ += native() ? 2 : 3; break; }
#define RMW8F_INH(OPC, OP) \
    case OPC: { r_.f = rmw8(RmwOp::OP, r_.f); cycles_ += native() ? 2 : 3; break; }

// ============================================================================
// 16-bit "accumulator OP operand" family for D and W (method-backed via
// r_.d()/r_.set_d() and r_.w()/r_.set_w()).
// ============================================================================
#define ALU16_IMM(OPC, GET, SET, OP, EM, NM) \
    case OPC: { uint16_t v = fetch16(); SET(apply_alu16(AluOp::OP, GET(), v)); cycles_ += native() ? (NM) : (EM); break; }
#define ALU16_DIR(OPC, GET, SET, OP, EM, NM) \
    case OPC: { uint16_t a = ea_direct(); uint16_t v = read16(a); SET(apply_alu16(AluOp::OP, GET(), v)); cycles_ += native() ? (NM) : (EM); break; }
#define ALU16_IDX(OPC, GET, SET, OP, C) \
    case OPC: { uint16_t a = ea_indexed(); uint16_t v = read16(a); SET(apply_alu16(AluOp::OP, GET(), v)); cycles_ += C; break; }
#define ALU16_EXT(OPC, GET, SET, OP, EM, NM) \
    case OPC: { uint16_t a = ea_extended(); uint16_t v = read16(a); SET(apply_alu16(AluOp::OP, GET(), v)); cycles_ += native() ? (NM) : (EM); break; }

// LD/ST/CMP on a plain 16-bit lvalue register (X, Y, U, S)
#define LD16_IMM(OPC, LV, C) \
    case OPC: { uint16_t v = fetch16(); set_flag(CC_V, false); set_nz16(v); LV = v; cycles_ += C; break; }
#define LD16_DIR(OPC, LV, EM, NM) \
    case OPC: { uint16_t a = ea_direct(); uint16_t v = read16(a); set_flag(CC_V, false); set_nz16(v); LV = v; cycles_ += native() ? (NM) : (EM); break; }
#define LD16_IDX(OPC, LV, C) \
    case OPC: { uint16_t a = ea_indexed(); uint16_t v = read16(a); set_flag(CC_V, false); set_nz16(v); LV = v; cycles_ += C; break; }
#define LD16_EXT(OPC, LV, EM, NM) \
    case OPC: { uint16_t a = ea_extended(); uint16_t v = read16(a); set_flag(CC_V, false); set_nz16(v); LV = v; cycles_ += native() ? (NM) : (EM); break; }
#define ST16_DIR(OPC, LV, EM, NM) \
    case OPC: { uint16_t a = ea_direct(); write16(a, LV); set_flag(CC_V, false); set_nz16(LV); cycles_ += native() ? (NM) : (EM); break; }
#define ST16_IDX(OPC, LV, C) \
    case OPC: { uint16_t a = ea_indexed(); write16(a, LV); set_flag(CC_V, false); set_nz16(LV); cycles_ += C; break; }
#define ST16_EXT(OPC, LV, EM, NM) \
    case OPC: { uint16_t a = ea_extended(); write16(a, LV); set_flag(CC_V, false); set_nz16(LV); cycles_ += native() ? (NM) : (EM); break; }
#define CMP16_IMM(OPC, LV, EM, NM) \
    case OPC: { uint16_t v = fetch16(); cmp16(LV, v); cycles_ += native() ? (NM) : (EM); break; }
#define CMP16_DIR(OPC, LV, EM, NM) \
    case OPC: { uint16_t a = ea_direct(); uint16_t v = read16(a); cmp16(LV, v); cycles_ += native() ? (NM) : (EM); break; }
#define CMP16_IDX(OPC, LV, C) \
    case OPC: { uint16_t a = ea_indexed(); uint16_t v = read16(a); cmp16(LV, v); cycles_ += C; break; }
#define CMP16_EXT(OPC, LV, EM, NM) \
    case OPC: { uint16_t a = ea_extended(); uint16_t v = read16(a); cmp16(LV, v); cycles_ += native() ? (NM) : (EM); break; }

// LD/ST on a method-backed 16-bit register (D via r_.d()/r_.set_d(), W via r_.w()/r_.set_w())
#define LD16M_IMM(OPC, SET, C) \
    case OPC: { uint16_t v = fetch16(); set_flag(CC_V, false); set_nz16(v); SET(v); cycles_ += C; break; }
#define LD16M_DIR(OPC, SET, EM, NM) \
    case OPC: { uint16_t a = ea_direct(); uint16_t v = read16(a); set_flag(CC_V, false); set_nz16(v); SET(v); cycles_ += native() ? (NM) : (EM); break; }
#define LD16M_IDX(OPC, SET, C) \
    case OPC: { uint16_t a = ea_indexed(); uint16_t v = read16(a); set_flag(CC_V, false); set_nz16(v); SET(v); cycles_ += C; break; }
#define LD16M_EXT(OPC, SET, EM, NM) \
    case OPC: { uint16_t a = ea_extended(); uint16_t v = read16(a); set_flag(CC_V, false); set_nz16(v); SET(v); cycles_ += native() ? (NM) : (EM); break; }
#define ST16M_DIR(OPC, GET, EM, NM) \
    case OPC: { uint16_t a = ea_direct(); uint16_t v = GET(); write16(a, v); set_flag(CC_V, false); set_nz16(v); cycles_ += native() ? (NM) : (EM); break; }
#define ST16M_IDX(OPC, GET, C) \
    case OPC: { uint16_t a = ea_indexed(); uint16_t v = GET(); write16(a, v); set_flag(CC_V, false); set_nz16(v); cycles_ += C; break; }
#define ST16M_EXT(OPC, GET, EM, NM) \
    case OPC: { uint16_t a = ea_extended(); uint16_t v = GET(); write16(a, v); set_flag(CC_V, false); set_nz16(v); cycles_ += native() ? (NM) : (EM); break; }

// ============================================================================
// AIM/OIM/EIM/TIM ("logic immediate memory"): opcode, mask byte, then address.
// WRITE=false for TIM (test only, no memory write-back).
// ============================================================================
#define LOGICMEM_DIR(OPC, OPSYM, WRITE) \
    case OPC: { uint8_t mask = fetch8(); uint16_t a = ea_direct(); uint8_t v = read8(a); uint8_t res = static_cast<uint8_t>(v OPSYM mask); if (WRITE) write8(a, res); set_flag(CC_V, false); set_nz8(res); cycles_ += 6; break; }
#define LOGICMEM_IDX(OPC, OPSYM, WRITE) \
    case OPC: { uint8_t mask = fetch8(); uint16_t a = ea_indexed(); uint8_t v = read8(a); uint8_t res = static_cast<uint8_t>(v OPSYM mask); if (WRITE) write8(a, res); set_flag(CC_V, false); set_nz8(res); cycles_ += 7; break; }
#define LOGICMEM_EXT(OPC, OPSYM, WRITE) \
    case OPC: { uint8_t mask = fetch8(); uint16_t a = ea_extended(); uint8_t v = read8(a); uint8_t res = static_cast<uint8_t>(v OPSYM mask); if (WRITE) write8(a, res); set_flag(CC_V, false); set_nz8(res); cycles_ += 7; break; }

void CPU::execute(uint8_t opcode) {
    switch (opcode) {
        // --- $00-$0F: direct-mode RMW / logicmem / JMP -----------------
        RMW8_DIR(0x00, NEG)
        LOGICMEM_DIR(0x01, |, true)  // OIM
        LOGICMEM_DIR(0x02, &, true)  // AIM
        RMW8_DIR(0x03, COM)
        RMW8_DIR(0x04, LSR)
        LOGICMEM_DIR(0x05, ^, true)  // EIM
        RMW8_DIR(0x06, ROR)
        RMW8_DIR(0x07, ASR)
        RMW8_DIR(0x08, ASL)
        RMW8_DIR(0x09, ROL)
        RMW8_DIR(0x0A, DEC)
        LOGICMEM_DIR(0x0B, &, false) // TIM
        RMW8_DIR(0x0C, INC)
        case 0x0D: { uint16_t a = ea_direct(); rmw8(RmwOp::TST, read8(a)); cycles_ += native() ? 4 : 6; break; } // TST
        case 0x0E: { r_.pc = ea_direct(); cycles_ += native() ? 2 : 3; break; } // JMP
        RMW8_DIR(0x0F, CLR)

        // --- $10/$11: page prefixes -------------------------------------
        case 0x10: execute_page10(fetch8()); break;
        case 0x11: execute_page11(fetch8()); break;

        case 0x12: cycles_ += native() ? 1 : 2; break; // NOP
        case 0x13: wait_sync_ = true; cycles_ += native() ? 1 : 2; break; // SYNC
        case 0x14: { uint16_t d = (r_.w() & 0x8000) ? 0xFFFFu : 0x0000u; r_.set_d(d); set_nz16(d); set_flag(CC_V, false); cycles_ += 4; break; } // SEXW
        case 0x16: { int16_t off = rel16(); r_.pc = static_cast<uint16_t>(r_.pc + off); cycles_ += native() ? 4 : 5; break; } // LBRA
        case 0x17: { int16_t off = rel16(); push16(r_.s, r_.pc); r_.pc = static_cast<uint16_t>(r_.pc + off); cycles_ += native() ? 7 : 9; break; } // LBSR
        case 0x19: do_daa(); cycles_ += native() ? 1 : 2; break; // DAA
        case 0x1A: { uint8_t m = fetch8(); r_.cc |= m; cycles_ += native() ? 2 : 3; break; } // ORCC
        case 0x1C: { uint8_t m = fetch8(); r_.cc &= m; cycles_ += native() ? 2 : 3; break; } // ANDCC
        case 0x1D: { r_.set_d(static_cast<uint16_t>(static_cast<int8_t>(r_.b))); set_nz16(r_.d()); set_flag(CC_V, false); cycles_ += native() ? 1 : 2; break; } // SEX
        case 0x1E: { uint8_t pb = fetch8(); do_tfr_exg(pb, true); cycles_ += native() ? 5 : 8; break; } // EXG
        case 0x1F: { uint8_t pb = fetch8(); do_tfr_exg(pb, false); cycles_ += native() ? 4 : 6; break; } // TFR

        // --- $20-$2F: short branches -------------------------------------
        case 0x20: case 0x21: case 0x22: case 0x23: case 0x24: case 0x25: case 0x26: case 0x27:
        case 0x28: case 0x29: case 0x2A: case 0x2B: case 0x2C: case 0x2D: case 0x2E: case 0x2F: {
            int8_t off = rel8();
            if (test_condition(opcode)) r_.pc = static_cast<uint16_t>(r_.pc + off);
            cycles_ += 3;
            break;
        }

        // --- $30-$3F: indexed LEA, stack ops, misc inherent ---------------
        case 0x30: { r_.x = ea_indexed(); set_flag(CC_Z, r_.x == 0); cycles_ += 4; break; } // LEAX
        case 0x31: { r_.y = ea_indexed(); set_flag(CC_Z, r_.y == 0); cycles_ += 4; break; } // LEAY
        case 0x32: { r_.s = ea_indexed(); cycles_ += 4; break; } // LEAS (no flags)
        case 0x33: { r_.u = ea_indexed(); cycles_ += 4; break; } // LEAU (no flags)
        case 0x34: { // PSHS
            uint8_t pb = fetch8();
            if (pb & 0x80) push16(r_.s, r_.pc);
            if (pb & 0x40) push16(r_.s, r_.u);
            if (pb & 0x20) push16(r_.s, r_.y);
            if (pb & 0x10) push16(r_.s, r_.x);
            if (pb & 0x08) push8(r_.s, r_.dp);
            if (pb & 0x04) push8(r_.s, r_.b);
            if (pb & 0x02) push8(r_.s, r_.a);
            if (pb & 0x01) push8(r_.s, r_.cc);
            cycles_ += (native() ? 4 : 5) + rlist_extra_cycles(pb);
            break;
        }
        case 0x35: { // PULS
            uint8_t pb = fetch8();
            if (pb & 0x01) r_.cc = pull8(r_.s);
            if (pb & 0x02) r_.a = pull8(r_.s);
            if (pb & 0x04) r_.b = pull8(r_.s);
            if (pb & 0x08) r_.dp = pull8(r_.s);
            if (pb & 0x10) r_.x = pull16(r_.s);
            if (pb & 0x20) r_.y = pull16(r_.s);
            if (pb & 0x40) r_.u = pull16(r_.s);
            if (pb & 0x80) r_.pc = pull16(r_.s);
            cycles_ += (native() ? 4 : 5) + rlist_extra_cycles(pb);
            break;
        }
        case 0x36: { // PSHU
            uint8_t pb = fetch8();
            if (pb & 0x80) push16(r_.u, r_.pc);
            if (pb & 0x40) push16(r_.u, r_.s);
            if (pb & 0x20) push16(r_.u, r_.y);
            if (pb & 0x10) push16(r_.u, r_.x);
            if (pb & 0x08) push8(r_.u, r_.dp);
            if (pb & 0x04) push8(r_.u, r_.b);
            if (pb & 0x02) push8(r_.u, r_.a);
            if (pb & 0x01) push8(r_.u, r_.cc);
            cycles_ += (native() ? 4 : 5) + rlist_extra_cycles(pb);
            break;
        }
        case 0x37: { // PULU
            uint8_t pb = fetch8();
            if (pb & 0x01) r_.cc = pull8(r_.u);
            if (pb & 0x02) r_.a = pull8(r_.u);
            if (pb & 0x04) r_.b = pull8(r_.u);
            if (pb & 0x08) r_.dp = pull8(r_.u);
            if (pb & 0x10) r_.x = pull16(r_.u);
            if (pb & 0x20) r_.y = pull16(r_.u);
            if (pb & 0x40) r_.s = pull16(r_.u);
            if (pb & 0x80) r_.pc = pull16(r_.u);
            cycles_ += (native() ? 4 : 5) + rlist_extra_cycles(pb);
            break;
        }
        case 0x39: r_.pc = pull16(r_.s); cycles_ += native() ? 4 : 5; break; // RTS
        case 0x3A: r_.x = static_cast<uint16_t>(r_.x + r_.b); cycles_ += native() ? 1 : 3; break; // ABX (unsigned, no flags)
        case 0x3B: { // RTI
            uint8_t cc = pull8(r_.s);
            r_.cc = cc;
            if (cc & CC_E) {
                r_.a = pull8(r_.s);
                r_.b = pull8(r_.s);
                if (native()) { r_.e = pull8(r_.s); r_.f = pull8(r_.s); } // push order was F,E so E is pulled first
                r_.dp = pull8(r_.s);
                r_.x = pull16(r_.s);
                r_.y = pull16(r_.s);
                r_.u = pull16(r_.s);
                r_.pc = pull16(r_.s);
                cycles_ += native() ? 17 : 15;
            } else {
                r_.pc = pull16(r_.s);
                cycles_ += 6;
            }
            break;
        }
        case 0x3C: { // CWAI
            uint8_t mask = fetch8();
            r_.cc &= mask;
            push_full_set();
            cwai_pushed_pending_ = true;
            wait_sync_ = true;
            cycles_ += native() ? 20 : 22;
            break;
        }
        case 0x3D: { // MUL
            uint16_t result = static_cast<uint16_t>(static_cast<unsigned>(r_.a) * r_.b);
            r_.set_d(result);
            set_flag(CC_Z, result == 0);
            set_flag(CC_C, (result & 0x80) != 0);
            cycles_ += native() ? 10 : 11;
            break;
        }
        case 0x3F: { // SWI
            push_full_set();
            r_.cc |= (CC_I | CC_F);
            r_.pc = read16(0xFFFA);
            cycles_ += native() ? 21 : 19;
            break;
        }

        // --- $40-$4F: A-register inherent RMW ------------------------------
        RMW8_INH(0x40, NEG, r_.a, native() ? 1 : 2)
        RMW8_INH(0x43, COM, r_.a, native() ? 1 : 2)
        RMW8_INH(0x44, LSR, r_.a, native() ? 1 : 2)
        RMW8_INH(0x46, ROR, r_.a, native() ? 1 : 2)
        RMW8_INH(0x47, ASR, r_.a, native() ? 1 : 2)
        RMW8_INH(0x48, ASL, r_.a, native() ? 1 : 2)
        RMW8_INH(0x49, ROL, r_.a, native() ? 1 : 2)
        RMW8_INH(0x4A, DEC, r_.a, native() ? 1 : 2)
        RMW8_INH(0x4C, INC, r_.a, native() ? 1 : 2)
        RMW8_INH(0x4D, TST, r_.a, native() ? 1 : 2)
        RMW8_INH(0x4F, CLR, r_.a, native() ? 1 : 2)

        // --- $50-$5F: B-register inherent RMW ------------------------------
        RMW8_INH(0x50, NEG, r_.b, native() ? 1 : 2)
        RMW8_INH(0x53, COM, r_.b, native() ? 1 : 2)
        RMW8_INH(0x54, LSR, r_.b, native() ? 1 : 2)
        RMW8_INH(0x56, ROR, r_.b, native() ? 1 : 2)
        RMW8_INH(0x57, ASR, r_.b, native() ? 1 : 2)
        RMW8_INH(0x58, ASL, r_.b, native() ? 1 : 2)
        RMW8_INH(0x59, ROL, r_.b, native() ? 1 : 2)
        RMW8_INH(0x5A, DEC, r_.b, native() ? 1 : 2)
        RMW8_INH(0x5C, INC, r_.b, native() ? 1 : 2)
        RMW8_INH(0x5D, TST, r_.b, native() ? 1 : 2)
        RMW8_INH(0x5F, CLR, r_.b, native() ? 1 : 2)

        // --- $60-$6F: indexed-mode RMW / logicmem / JMP --------------------
        RMW8_IDX(0x60, NEG)
        LOGICMEM_IDX(0x61, |, true)
        LOGICMEM_IDX(0x62, &, true)
        RMW8_IDX(0x63, COM)
        RMW8_IDX(0x64, LSR)
        LOGICMEM_IDX(0x65, ^, true)
        RMW8_IDX(0x66, ROR)
        RMW8_IDX(0x67, ASR)
        RMW8_IDX(0x68, ASL)
        RMW8_IDX(0x69, ROL)
        RMW8_IDX(0x6A, DEC)
        LOGICMEM_IDX(0x6B, &, false)
        RMW8_IDX(0x6C, INC)
        case 0x6D: { uint16_t a = ea_indexed(); rmw8(RmwOp::TST, read8(a)); cycles_ += 5; break; } // TST
        case 0x6E: { r_.pc = ea_indexed(); cycles_ += 3; break; } // JMP
        RMW8_IDX(0x6F, CLR)

        // --- $70-$7F: extended-mode RMW / logicmem / JMP --------------------
        RMW8_EXT(0x70, NEG)
        LOGICMEM_EXT(0x71, |, true)
        LOGICMEM_EXT(0x72, &, true)
        RMW8_EXT(0x73, COM)
        RMW8_EXT(0x74, LSR)
        LOGICMEM_EXT(0x75, ^, true)
        RMW8_EXT(0x76, ROR)
        RMW8_EXT(0x77, ASR)
        RMW8_EXT(0x78, ASL)
        RMW8_EXT(0x79, ROL)
        RMW8_EXT(0x7A, DEC)
        LOGICMEM_EXT(0x7B, &, false)
        RMW8_EXT(0x7C, INC)
        case 0x7D: { uint16_t a = ea_extended(); rmw8(RmwOp::TST, read8(a)); cycles_ += native() ? 5 : 7; break; } // TST
        case 0x7E: { r_.pc = ea_extended(); cycles_ += native() ? 3 : 4; break; } // JMP
        RMW8_EXT(0x7F, CLR)

        // --- $80-$8F: A-accumulator immediate, SUBD/CMPX imm, BSR, LDX imm ---
        ALU8_IMM(0x80, r_.a, SUB, 2)
        ALU8_IMM(0x81, r_.a, CMP, 2)
        ALU8_IMM(0x82, r_.a, SBC, 2)
        ALU16_IMM(0x83, r_.d, r_.set_d, SUB, 4, 3)  // SUBD
        ALU8_IMM(0x84, r_.a, AND, 2)
        ALU8_IMM(0x85, r_.a, BIT, 2)
        ALU8_IMM(0x86, r_.a, LD, 2)
        CMP16_IMM(0x8C, r_.x, 4, 3)                 // CMPX
        case 0x8D: { int8_t off = rel8(); push16(r_.s, r_.pc); r_.pc = static_cast<uint16_t>(r_.pc + off); cycles_ += native() ? 6 : 7; break; } // BSR
        LD16_IMM(0x8E, r_.x, 3)                     // LDX
        ALU8_IMM(0x88, r_.a, EOR, 2)
        ALU8_IMM(0x89, r_.a, ADC, 2)
        ALU8_IMM(0x8A, r_.a, OR, 2)
        ALU8_IMM(0x8B, r_.a, ADD, 2)

        // --- $90-$9F: A-accumulator direct, SUBD/CMPX/JSR/LDX/STX direct -----
        ALU8_DIR(0x90, r_.a, SUB, 4, 3)
        ALU8_DIR(0x91, r_.a, CMP, 4, 3)
        ALU8_DIR(0x92, r_.a, SBC, 4, 3)
        ALU16_DIR(0x93, r_.d, r_.set_d, SUB, 6, 4)  // SUBD
        ALU8_DIR(0x94, r_.a, AND, 4, 3)
        ALU8_DIR(0x95, r_.a, BIT, 4, 3)
        ALU8_DIR(0x96, r_.a, LD, 4, 3)
        ST8_DIR(0x97, r_.a, 4, 3)
        ALU8_DIR(0x98, r_.a, EOR, 4, 3)
        ALU8_DIR(0x99, r_.a, ADC, 4, 3)
        ALU8_DIR(0x9A, r_.a, OR, 4, 3)
        ALU8_DIR(0x9B, r_.a, ADD, 4, 3)
        CMP16_DIR(0x9C, r_.x, 6, 4)                 // CMPX
        case 0x9D: { uint16_t a = ea_direct(); push16(r_.s, r_.pc); r_.pc = a; cycles_ += native() ? 6 : 7; break; } // JSR
        LD16_DIR(0x9E, r_.x, 5, 4)                  // LDX
        ST16_DIR(0x9F, r_.x, 5, 4)                  // STX

        // --- $A0-$AF: A-accumulator indexed, SUBD/CMPX/JSR/LDX/STX indexed ---
        ALU8_IDX(0xA0, r_.a, SUB, 4)
        ALU8_IDX(0xA1, r_.a, CMP, 4)
        ALU8_IDX(0xA2, r_.a, SBC, 4)
        ALU16_IDX(0xA3, r_.d, r_.set_d, SUB, 6)     // SUBD
        ALU8_IDX(0xA4, r_.a, AND, 4)
        ALU8_IDX(0xA5, r_.a, BIT, 4)
        ALU8_IDX(0xA6, r_.a, LD, 4)
        ST8_IDX(0xA7, r_.a, 4)
        ALU8_IDX(0xA8, r_.a, EOR, 4)
        ALU8_IDX(0xA9, r_.a, ADC, 4)
        ALU8_IDX(0xAA, r_.a, OR, 4)
        ALU8_IDX(0xAB, r_.a, ADD, 4)
        CMP16_IDX(0xAC, r_.x, 6)                    // CMPX
        case 0xAD: { uint16_t a = ea_indexed(); push16(r_.s, r_.pc); r_.pc = a; cycles_ += native() ? 6 : 7; break; } // JSR
        LD16_IDX(0xAE, r_.x, 5)                     // LDX
        ST16_IDX(0xAF, r_.x, 5)                     // STX

        // --- $B0-$BF: A-accumulator extended, SUBD/CMPX/JSR/LDX/STX extended -
        ALU8_EXT(0xB0, r_.a, SUB, 5, 4)
        ALU8_EXT(0xB1, r_.a, CMP, 5, 4)
        ALU8_EXT(0xB2, r_.a, SBC, 5, 4)
        ALU16_EXT(0xB3, r_.d, r_.set_d, SUB, 7, 5)  // SUBD
        ALU8_EXT(0xB4, r_.a, AND, 5, 4)
        ALU8_EXT(0xB5, r_.a, BIT, 5, 4)
        ALU8_EXT(0xB6, r_.a, LD, 5, 4)
        ST8_EXT(0xB7, r_.a, 5, 4)
        ALU8_EXT(0xB8, r_.a, EOR, 5, 4)
        ALU8_EXT(0xB9, r_.a, ADC, 5, 4)
        ALU8_EXT(0xBA, r_.a, OR, 5, 4)
        ALU8_EXT(0xBB, r_.a, ADD, 5, 4)
        CMP16_EXT(0xBC, r_.x, 7, 5)                 // CMPX
        case 0xBD: { uint16_t a = ea_extended(); push16(r_.s, r_.pc); r_.pc = a; cycles_ += native() ? 7 : 8; break; } // JSR
        LD16_EXT(0xBE, r_.x, 6, 5)                  // LDX
        ST16_EXT(0xBF, r_.x, 6, 5)                  // STX

        // --- $C0-$CF: B-accumulator immediate, ADDD/LDD/LDQ/LDU immediate ----
        ALU8_IMM(0xC0, r_.b, SUB, 2)
        ALU8_IMM(0xC1, r_.b, CMP, 2)
        ALU8_IMM(0xC2, r_.b, SBC, 2)
        ALU16_IMM(0xC3, r_.d, r_.set_d, ADD, 4, 3)  // ADDD
        ALU8_IMM(0xC4, r_.b, AND, 2)
        ALU8_IMM(0xC5, r_.b, BIT, 2)
        ALU8_IMM(0xC6, r_.b, LD, 2)
        ALU8_IMM(0xC8, r_.b, EOR, 2)
        ALU8_IMM(0xC9, r_.b, ADC, 2)
        ALU8_IMM(0xCA, r_.b, OR, 2)
        ALU8_IMM(0xCB, r_.b, ADD, 2)
        LD16M_IMM(0xCC, r_.set_d, 3)                // LDD
        case 0xCD: { // LDQ immediate (D:W, big-endian: A,B,E,F)
            uint32_t v = static_cast<uint32_t>(fetch16()) << 16;
            v |= fetch16();
            set_flag(CC_V, false);
            set_flag(CC_Z, v == 0);
            set_flag(CC_N, (v & 0x80000000u) != 0);
            r_.set_q(v);
            cycles_ += 5;
            break;
        }
        LD16_IMM(0xCE, r_.u, 3)                     // LDU

        // --- $D0-$DF: B-accumulator direct, ADDD/LDD/STD/LDU/STU direct ------
        ALU8_DIR(0xD0, r_.b, SUB, 4, 3)
        ALU8_DIR(0xD1, r_.b, CMP, 4, 3)
        ALU8_DIR(0xD2, r_.b, SBC, 4, 3)
        ALU16_DIR(0xD3, r_.d, r_.set_d, ADD, 6, 4)  // ADDD
        ALU8_DIR(0xD4, r_.b, AND, 4, 3)
        ALU8_DIR(0xD5, r_.b, BIT, 4, 3)
        ALU8_DIR(0xD6, r_.b, LD, 4, 3)
        ST8_DIR(0xD7, r_.b, 4, 3)
        ALU8_DIR(0xD8, r_.b, EOR, 4, 3)
        ALU8_DIR(0xD9, r_.b, ADC, 4, 3)
        ALU8_DIR(0xDA, r_.b, OR, 4, 3)
        ALU8_DIR(0xDB, r_.b, ADD, 4, 3)
        LD16M_DIR(0xDC, r_.set_d, 5, 4)              // LDD
        ST16M_DIR(0xDD, r_.d, 5, 4)                  // STD
        LD16_DIR(0xDE, r_.u, 5, 4)                   // LDU
        ST16_DIR(0xDF, r_.u, 5, 4)                   // STU

        // --- $E0-$EF: B-accumulator indexed, ADDD/LDD/STD/LDU/STU indexed ----
        ALU8_IDX(0xE0, r_.b, SUB, 4)
        ALU8_IDX(0xE1, r_.b, CMP, 4)
        ALU8_IDX(0xE2, r_.b, SBC, 4)
        ALU16_IDX(0xE3, r_.d, r_.set_d, ADD, 6)     // ADDD
        ALU8_IDX(0xE4, r_.b, AND, 4)
        ALU8_IDX(0xE5, r_.b, BIT, 4)
        ALU8_IDX(0xE6, r_.b, LD, 4)
        ST8_IDX(0xE7, r_.b, 4)
        ALU8_IDX(0xE8, r_.b, EOR, 4)
        ALU8_IDX(0xE9, r_.b, ADC, 4)
        ALU8_IDX(0xEA, r_.b, OR, 4)
        ALU8_IDX(0xEB, r_.b, ADD, 4)
        LD16M_IDX(0xEC, r_.set_d, 5)                 // LDD
        ST16M_IDX(0xED, r_.d, 5)                      // STD
        LD16_IDX(0xEE, r_.u, 5)                      // LDU
        ST16_IDX(0xEF, r_.u, 5)                      // STU

        // --- $F0-$FF: B-accumulator extended, ADDD/LDD/STD/LDU/STU extended --
        ALU8_EXT(0xF0, r_.b, SUB, 5, 4)
        ALU8_EXT(0xF1, r_.b, CMP, 5, 4)
        ALU8_EXT(0xF2, r_.b, SBC, 5, 4)
        ALU16_EXT(0xF3, r_.d, r_.set_d, ADD, 7, 5)  // ADDD
        ALU8_EXT(0xF4, r_.b, AND, 5, 4)
        ALU8_EXT(0xF5, r_.b, BIT, 5, 4)
        ALU8_EXT(0xF6, r_.b, LD, 5, 4)
        ST8_EXT(0xF7, r_.b, 5, 4)
        ALU8_EXT(0xF8, r_.b, EOR, 5, 4)
        ALU8_EXT(0xF9, r_.b, ADC, 5, 4)
        ALU8_EXT(0xFA, r_.b, OR, 5, 4)
        ALU8_EXT(0xFB, r_.b, ADD, 5, 4)
        LD16M_EXT(0xFC, r_.set_d, 6, 5)              // LDD
        ST16M_EXT(0xFD, r_.d, 6, 5)                  // STD
        LD16_EXT(0xFE, r_.u, 6, 5)                   // LDU
        ST16_EXT(0xFF, r_.u, 6, 5)                   // STU

        default:
            illegal_opcode_trap();
            break;
    }
}

void CPU::execute_page10(uint8_t opcode) {
    switch (opcode) {
        // --- LBcc: long conditional branches ($1021-$102F; $1020 unused) ----
        case 0x21: case 0x22: case 0x23: case 0x24: case 0x25: case 0x26: case 0x27:
        case 0x28: case 0x29: case 0x2A: case 0x2B: case 0x2C: case 0x2D: case 0x2E: case 0x2F: {
            int16_t off = rel16();
            bool taken = test_condition(opcode);
            if (taken) r_.pc = static_cast<uint16_t>(r_.pc + off);
            cycles_ += native() ? 5 : (taken ? 6 : 5);
            break;
        }

        // --- register-to-register ALU family ($30-$37, i.e. $1030-$1037) -----
        case 0x30: case 0x31: case 0x32: case 0x33: case 0x34: case 0x35: case 0x36: case 0x37: {
            uint8_t pb = fetch8();
            int src = (pb >> 4) & 0xF;
            int dst = pb & 0xF;
            bool wide = reg_code_is_16bit(dst);
            AluOp op;
            switch (opcode) {
                case 0x30: op = AluOp::ADD; break; // ADDR
                case 0x31: op = AluOp::ADC; break; // ADCR
                case 0x32: op = AluOp::SUB; break; // SUBR
                case 0x33: op = AluOp::SBC; break; // SBCR
                case 0x34: op = AluOp::AND; break; // ANDR
                case 0x35: op = AluOp::OR;  break; // ORR
                case 0x36: op = AluOp::EOR; break; // EORR
                default:   op = AluOp::CMP; break; // CMPR
            }
            if (wide) {
                uint16_t result = apply_alu16(op, get_reg_by_code(dst), get_reg_by_code(src));
                set_reg_by_code(dst, result);
            } else {
                uint8_t result = apply_alu8(op, get_reg_raw8(dst), get_reg_raw8(src));
                set_reg_by_code(dst, result);
            }
            cycles_ += 4;
            break;
        }

        case 0x38: push16(r_.s, r_.w()); cycles_ += 6; break; // PSHSW
        case 0x39: r_.set_w(pull16(r_.s)); cycles_ += 6; break; // PULSW
        case 0x3A: push16(r_.u, r_.w()); cycles_ += 6; break; // PSHUW
        case 0x3B: r_.set_w(pull16(r_.u)); cycles_ += 6; break; // PULUW
        case 0x3F: { // SWI2
            push_full_set();
            r_.pc = read16(0xFFF4);
            cycles_ += native() ? 22 : 20;
            break;
        }

        // --- D-register inherent RMW ($1040-$104F) ----------------------------
        RMW16D_INH(0x40, NEG)
        RMW16D_INH(0x43, COM)
        RMW16D_INH(0x44, LSR)
        RMW16D_INH(0x46, ROR)
        RMW16D_INH(0x47, ASR)
        RMW16D_INH(0x48, ASL)
        RMW16D_INH(0x49, ROL)
        RMW16D_INH(0x4A, DEC)
        RMW16D_INH(0x4C, INC)
        RMW16D_INH(0x4D, TST)
        RMW16D_INH(0x4F, CLR)

        // --- W-register inherent RMW subset ($1050-$105F) ----------------------
        // Real HD6309 silicon does not implement NEGW/ASRW/ASLW (confirmed
        // absent from both instab.c and cycle.c in lwtools-4.20) -- they trap.
        RMW16W_INH(0x53, COM)
        RMW16W_INH(0x54, LSR)
        RMW16W_INH(0x56, ROR)
        RMW16W_INH(0x59, ROL)
        RMW16W_INH(0x5A, DEC)
        RMW16W_INH(0x5C, INC)
        RMW16W_INH(0x5D, TST)
        RMW16W_INH(0x5F, CLR)

        // --- $1080-$108F: SUBW/CMPW/SBCD/CMPD/ANDD/BITD/LDW/EORD/ADCD/ORD/ADDW/CMPY/LDY immediate
        ALU16_IMM(0x80, r_.w, r_.set_w, SUB, 5, 4) // SUBW
        ALU16_IMM(0x81, r_.w, r_.set_w, CMP, 5, 4) // CMPW
        ALU16_IMM(0x82, r_.d, r_.set_d, SBC, 5, 4) // SBCD
        ALU16_IMM(0x83, r_.d, r_.set_d, CMP, 5, 4) // CMPD
        ALU16_IMM(0x84, r_.d, r_.set_d, AND, 5, 4) // ANDD
        ALU16_IMM(0x85, r_.d, r_.set_d, BIT, 5, 4) // BITD
        LD16M_IMM(0x86, r_.set_w, 4)                // LDW
        ALU16_IMM(0x88, r_.d, r_.set_d, EOR, 5, 4) // EORD
        ALU16_IMM(0x89, r_.d, r_.set_d, ADC, 5, 4) // ADCD
        ALU16_IMM(0x8A, r_.d, r_.set_d, OR, 5, 4)  // ORD
        ALU16_IMM(0x8B, r_.w, r_.set_w, ADD, 5, 4) // ADDW
        CMP16_IMM(0x8C, r_.y, 5, 4)                 // CMPY
        LD16_IMM(0x8E, r_.y, 4)                     // LDY

        // --- $1090-$109F: same family, direct -----------------------------------
        ALU16_DIR(0x90, r_.w, r_.set_w, SUB, 7, 5)
        ALU16_DIR(0x91, r_.w, r_.set_w, CMP, 7, 5)
        ALU16_DIR(0x92, r_.d, r_.set_d, SBC, 7, 5)
        ALU16_DIR(0x93, r_.d, r_.set_d, CMP, 7, 5)
        ALU16_DIR(0x94, r_.d, r_.set_d, AND, 7, 5)
        ALU16_DIR(0x95, r_.d, r_.set_d, BIT, 7, 5)
        LD16M_DIR(0x96, r_.set_w, 6, 5)
        ST16M_DIR(0x97, r_.w, 6, 5)
        ALU16_DIR(0x98, r_.d, r_.set_d, EOR, 7, 5)
        ALU16_DIR(0x99, r_.d, r_.set_d, ADC, 7, 5)
        ALU16_DIR(0x9A, r_.d, r_.set_d, OR, 7, 5)
        ALU16_DIR(0x9B, r_.w, r_.set_w, ADD, 7, 5)
        CMP16_DIR(0x9C, r_.y, 7, 5)
        LD16_DIR(0x9E, r_.y, 6, 5)
        ST16_DIR(0x9F, r_.y, 6, 5)

        // --- $10A0-$10AF: same family, indexed -----------------------------------
        ALU16_IDX(0xA0, r_.w, r_.set_w, SUB, 7)
        ALU16_IDX(0xA1, r_.w, r_.set_w, CMP, 7)
        ALU16_IDX(0xA2, r_.d, r_.set_d, SBC, 7)
        ALU16_IDX(0xA3, r_.d, r_.set_d, CMP, 7)
        ALU16_IDX(0xA4, r_.d, r_.set_d, AND, 7)
        ALU16_IDX(0xA5, r_.d, r_.set_d, BIT, 7)
        LD16M_IDX(0xA6, r_.set_w, 6)
        ST16M_IDX(0xA7, r_.w, 6)
        ALU16_IDX(0xA8, r_.d, r_.set_d, EOR, 7)
        ALU16_IDX(0xA9, r_.d, r_.set_d, ADC, 7)
        ALU16_IDX(0xAA, r_.d, r_.set_d, OR, 7)
        ALU16_IDX(0xAB, r_.w, r_.set_w, ADD, 7)
        CMP16_IDX(0xAC, r_.y, 7)
        LD16_IDX(0xAE, r_.y, 6)
        ST16_IDX(0xAF, r_.y, 6)

        // --- $10B0-$10BF: same family, extended -----------------------------------
        ALU16_EXT(0xB0, r_.w, r_.set_w, SUB, 8, 6)
        ALU16_EXT(0xB1, r_.w, r_.set_w, CMP, 8, 6)
        ALU16_EXT(0xB2, r_.d, r_.set_d, SBC, 8, 6)
        ALU16_EXT(0xB3, r_.d, r_.set_d, CMP, 8, 6)
        ALU16_EXT(0xB4, r_.d, r_.set_d, AND, 8, 6)
        ALU16_EXT(0xB5, r_.d, r_.set_d, BIT, 8, 6)
        LD16M_EXT(0xB6, r_.set_w, 7, 6)
        ST16M_EXT(0xB7, r_.w, 7, 6)
        ALU16_EXT(0xB8, r_.d, r_.set_d, EOR, 8, 6)
        ALU16_EXT(0xB9, r_.d, r_.set_d, ADC, 8, 6)
        ALU16_EXT(0xBA, r_.d, r_.set_d, OR, 8, 6)
        ALU16_EXT(0xBB, r_.w, r_.set_w, ADD, 8, 6)
        CMP16_EXT(0xBC, r_.y, 8, 6)
        LD16_EXT(0xBE, r_.y, 7, 6)
        ST16_EXT(0xBF, r_.y, 7, 6)

        // --- $10CE: LDS immediate -------------------------------------------
        LD16_IMM(0xCE, r_.s, 4)                      // LDS

        // --- $10DC-$10DF: LDQ/STQ/LDS/STS direct --------------------------------
        case 0xDC: { uint16_t a = ea_direct(); uint32_t v = static_cast<uint32_t>(read16(a)) << 16 | read16(static_cast<uint16_t>(a + 2));
            set_flag(CC_V, false); set_flag(CC_Z, v == 0); set_flag(CC_N, (v & 0x80000000u) != 0); r_.set_q(v); cycles_ += native() ? 7 : 8; break; } // LDQ
        case 0xDD: { uint16_t a = ea_direct(); uint32_t v = r_.q(); write16(a, static_cast<uint16_t>(v >> 16)); write16(static_cast<uint16_t>(a + 2), static_cast<uint16_t>(v));
            set_flag(CC_V, false); set_flag(CC_Z, v == 0); set_flag(CC_N, (v & 0x80000000u) != 0); cycles_ += native() ? 7 : 8; break; } // STQ
        LD16_DIR(0xDE, r_.s, 6, 5)                    // LDS
        ST16_DIR(0xDF, r_.s, 6, 5)                    // STS

        // --- $10EC-$10EF: LDQ/STQ/LDS/STS indexed -------------------------------
        case 0xEC: { uint16_t a = ea_indexed(); uint32_t v = static_cast<uint32_t>(read16(a)) << 16 | read16(static_cast<uint16_t>(a + 2));
            set_flag(CC_V, false); set_flag(CC_Z, v == 0); set_flag(CC_N, (v & 0x80000000u) != 0); r_.set_q(v); cycles_ += 8; break; } // LDQ
        case 0xED: { uint16_t a = ea_indexed(); uint32_t v = r_.q(); write16(a, static_cast<uint16_t>(v >> 16)); write16(static_cast<uint16_t>(a + 2), static_cast<uint16_t>(v));
            set_flag(CC_V, false); set_flag(CC_Z, v == 0); set_flag(CC_N, (v & 0x80000000u) != 0); cycles_ += 8; break; } // STQ
        LD16_IDX(0xEE, r_.s, 6)                       // LDS
        ST16_IDX(0xEF, r_.s, 6)                       // STS

        // --- $10FC-$10FF: LDQ/STQ/LDS/STS extended ------------------------------
        case 0xFC: { uint16_t a = ea_extended(); uint32_t v = static_cast<uint32_t>(read16(a)) << 16 | read16(static_cast<uint16_t>(a + 2));
            set_flag(CC_V, false); set_flag(CC_Z, v == 0); set_flag(CC_N, (v & 0x80000000u) != 0); r_.set_q(v); cycles_ += native() ? 8 : 9; break; } // LDQ
        case 0xFD: { uint16_t a = ea_extended(); uint32_t v = r_.q(); write16(a, static_cast<uint16_t>(v >> 16)); write16(static_cast<uint16_t>(a + 2), static_cast<uint16_t>(v));
            set_flag(CC_V, false); set_flag(CC_Z, v == 0); set_flag(CC_N, (v & 0x80000000u) != 0); cycles_ += native() ? 8 : 9; break; } // STQ
        LD16_EXT(0xFE, r_.s, 7, 6)                    // LDS
        ST16_EXT(0xFF, r_.s, 7, 6)                    // STS

        default:
            illegal_opcode_trap();
            break;
    }
}

void CPU::execute_page11(uint8_t opcode) {
    switch (opcode) {
        // --- $1130-$1137: single-bit BAND family -------------------------------
        case 0x30: case 0x31: case 0x32: case 0x33: case 0x34: case 0x35: case 0x36: case 0x37:
            do_bitbit(0x1100 | opcode);
            break;

        // --- $1138-$113B: TFM block transfer -----------------------------------
        case 0x38: case 0x39: case 0x3A: case 0x3B:
            do_tfm(0x1100 | opcode);
            break;

        case 0x3C: { // BITMD
            uint8_t imm = fetch8();
            uint8_t test = static_cast<uint8_t>(r_.md & imm);
            set_flag(CC_Z, test == 0);
            r_.md &= static_cast<uint8_t>(~test);
            cycles_ += 4;
            break;
        }
        case 0x3D: r_.md = fetch8(); cycles_ += 5; break; // LDMD
        case 0x3F: { // SWI3
            push_full_set();
            r_.pc = read16(0xFFF2);
            cycles_ += native() ? 22 : 20;
            break;
        }

        // --- $1140-$114F: E-register inherent RMW subset ------------------------
        RMW8E_INH(0x43, COM)
        RMW8E_INH(0x4A, DEC)
        RMW8E_INH(0x4C, INC)
        RMW8E_INH(0x4D, TST)
        RMW8E_INH(0x4F, CLR)

        // --- $1150-$115F: F-register inherent RMW subset ------------------------
        RMW8F_INH(0x53, COM)
        RMW8F_INH(0x5A, DEC)
        RMW8F_INH(0x5C, INC)
        RMW8F_INH(0x5D, TST)
        RMW8F_INH(0x5F, CLR)

        // --- $1180-$118F: SUBE/CMPE/CMPU/LDE/ADDE/CMPS/DIVD/DIVQ/MULD immediate --
        ALU8_IMM(0x80, r_.e, SUB, 3)                 // SUBE
        ALU8_IMM(0x81, r_.e, CMP, 3)                 // CMPE
        CMP16_IMM(0x83, r_.u, 5, 4)                  // CMPU
        ALU8_IMM(0x86, r_.e, LD, 3)                  // LDE
        ALU8_IMM(0x8B, r_.e, ADD, 3)                 // ADDE
        CMP16_IMM(0x8C, r_.s, 5, 4)                  // CMPS
        case 0x8D: { uint8_t v = fetch8(); do_divd(v); cycles_ += 25; break; } // DIVD
        case 0x8E: { uint16_t v = fetch16(); do_divq(v); cycles_ += 34; break; } // DIVQ
        case 0x8F: { uint16_t v = fetch16(); do_muld(v); cycles_ += 28; break; } // MULD

        // --- $1190-$119F: same family, direct -----------------------------------
        ALU8_DIR(0x90, r_.e, SUB, 5, 4)
        ALU8_DIR(0x91, r_.e, CMP, 5, 4)
        CMP16_DIR(0x93, r_.u, 7, 5)
        ALU8_DIR(0x96, r_.e, LD, 5, 4)
        ST8_DIR(0x97, r_.e, 5, 4)
        ALU8_DIR(0x9B, r_.e, ADD, 5, 4)
        CMP16_DIR(0x9C, r_.s, 7, 5)
        case 0x9D: { uint16_t a = ea_direct(); do_divd(read8(a)); cycles_ += native() ? 26 : 27; break; }
        case 0x9E: { uint16_t a = ea_direct(); do_divq(read16(a)); cycles_ += native() ? 35 : 36; break; }
        case 0x9F: { uint16_t a = ea_direct(); do_muld(read16(a)); cycles_ += native() ? 29 : 30; break; }

        // --- $11A0-$11AF: same family, indexed -----------------------------------
        ALU8_IDX(0xA0, r_.e, SUB, 5)
        ALU8_IDX(0xA1, r_.e, CMP, 5)
        CMP16_IDX(0xA3, r_.u, 7)
        ALU8_IDX(0xA6, r_.e, LD, 5)
        ST8_IDX(0xA7, r_.e, 5)
        ALU8_IDX(0xAB, r_.e, ADD, 5)
        CMP16_IDX(0xAC, r_.s, 7)
        case 0xAD: { uint16_t a = ea_indexed(); do_divd(read8(a)); cycles_ += 27; break; }
        case 0xAE: { uint16_t a = ea_indexed(); do_divq(read16(a)); cycles_ += 36; break; }
        case 0xAF: { uint16_t a = ea_indexed(); do_muld(read16(a)); cycles_ += 30; break; }

        // --- $11B0-$11BF: same family, extended -----------------------------------
        ALU8_EXT(0xB0, r_.e, SUB, 6, 5)
        ALU8_EXT(0xB1, r_.e, CMP, 6, 5)
        CMP16_EXT(0xB3, r_.u, 8, 6)
        ALU8_EXT(0xB6, r_.e, LD, 6, 5)
        ST8_EXT(0xB7, r_.e, 6, 5)
        ALU8_EXT(0xBB, r_.e, ADD, 6, 5)
        CMP16_EXT(0xBC, r_.s, 8, 6)
        case 0xBD: { uint16_t a = ea_extended(); do_divd(read8(a)); cycles_ += native() ? 27 : 28; break; }
        case 0xBE: { uint16_t a = ea_extended(); do_divq(read16(a)); cycles_ += native() ? 36 : 37; break; }
        case 0xBF: { uint16_t a = ea_extended(); do_muld(read16(a)); cycles_ += native() ? 30 : 31; break; }

        // --- $11C0-$11CF: SUBF/CMPF/LDF/ADDF immediate ---------------------------
        ALU8_IMM(0xC0, r_.f, SUB, 3)
        ALU8_IMM(0xC1, r_.f, CMP, 3)
        ALU8_IMM(0xC6, r_.f, LD, 3)
        ALU8_IMM(0xCB, r_.f, ADD, 3)

        // --- $11D0-$11DF: same family, direct -----------------------------------
        ALU8_DIR(0xD0, r_.f, SUB, 5, 4)
        ALU8_DIR(0xD1, r_.f, CMP, 5, 4)
        ALU8_DIR(0xD6, r_.f, LD, 5, 4)
        ST8_DIR(0xD7, r_.f, 5, 4)
        ALU8_DIR(0xDB, r_.f, ADD, 5, 4)

        // --- $11E0-$11EF: same family, indexed -----------------------------------
        ALU8_IDX(0xE0, r_.f, SUB, 5)
        ALU8_IDX(0xE1, r_.f, CMP, 5)
        ALU8_IDX(0xE6, r_.f, LD, 5)
        ST8_IDX(0xE7, r_.f, 5)
        ALU8_IDX(0xEB, r_.f, ADD, 5)

        // --- $11F0-$11FF: same family, extended -----------------------------------
        ALU8_EXT(0xF0, r_.f, SUB, 6, 5)
        ALU8_EXT(0xF1, r_.f, CMP, 6, 5)
        ALU8_EXT(0xF6, r_.f, LD, 6, 5)
        ST8_EXT(0xF7, r_.f, 6, 5)
        ALU8_EXT(0xFB, r_.f, ADD, 6, 5)

        default:
            illegal_opcode_trap();
            break;
    }
}

#undef ALU8_IMM
#undef ALU8_DIR
#undef ALU8_IDX
#undef ALU8_EXT
#undef ST8_DIR
#undef ST8_IDX
#undef ST8_EXT
#undef RMW8_DIR
#undef RMW8_IDX
#undef RMW8_EXT
#undef RMW8_INH
#undef RMW16D_INH
#undef RMW16W_INH
#undef RMW8E_INH
#undef RMW8F_INH
#undef ALU16_IMM
#undef ALU16_DIR
#undef ALU16_IDX
#undef ALU16_EXT
#undef LD16_IMM
#undef LD16_DIR
#undef LD16_IDX
#undef LD16_EXT
#undef ST16_DIR
#undef ST16_IDX
#undef ST16_EXT
#undef CMP16_IMM
#undef CMP16_DIR
#undef CMP16_IDX
#undef CMP16_EXT
#undef LD16M_IMM
#undef LD16M_DIR
#undef LD16M_IDX
#undef LD16M_EXT
#undef ST16M_DIR
#undef ST16M_IDX
#undef ST16M_EXT
#undef LOGICMEM_DIR
#undef LOGICMEM_IDX
#undef LOGICMEM_EXT

} // namespace hd6309
