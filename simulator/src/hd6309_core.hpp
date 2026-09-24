// Internal CPU execution engine. Not part of the public API surface;
// hd6309_api.cpp wraps this class behind the C ABI in hd6309.h.
#pragma once

#include <cstdint>
#include <vector>

#include "hd6309_types.hpp"

namespace hd6309 {

class CPU {
public:
    CPU(ReadFn read_fn, WriteFn write_fn, void* ctx);

    void reset();
    uint64_t step();
    uint64_t run(uint64_t max_cycles);

    StopReason stop_reason() const { return stop_reason_; }
    void halt() { halted_ = true; }
    void resume() { halted_ = false; }
    bool halted() const { return halted_; }

    void set_irq(bool asserted) { irq_line_ = asserted; }
    void set_firq(bool asserted) { firq_line_ = asserted; }
    void nmi_pulse() { nmi_pending_ = true; }

    Regs& regs() { return r_; }
    const Regs& regs() const { return r_; }

    uint64_t total_cycles() const { return total_cycles_; }

    int add_breakpoint(uint16_t addr);
    void remove_breakpoint(int id);
    void clear_breakpoints() { breakpoints_.clear(); }

    uint8_t peek(uint16_t addr) { return read8(addr); }
    void poke(uint16_t addr, uint8_t v) { write8(addr, v); }

private:
    Regs r_;
    ReadFn read_fn_;
    WriteFn write_fn_;
    void* ctx_;

    bool irq_line_ = false;
    bool firq_line_ = false;
    bool nmi_pending_ = false;
    bool wait_sync_ = false;
    bool halted_ = false;
    bool cwai_pushed_pending_ = false; // CWAI already pushed the full register set; next interrupt entry must not push again
    uint64_t total_cycles_ = 0;
    StopReason stop_reason_ = StopReason::CycleBudget;

    struct Breakpoint { int id; uint16_t addr; };
    std::vector<Breakpoint> breakpoints_;
    int next_bp_id_ = 0;

    int cycles_;         // accumulated cycles for the instruction currently executing
    uint16_t insn_pc_ = 0; // PC at the start of the instruction currently executing (for TFM resumption)

    // --- memory / fetch -------------------------------------------------
    uint8_t read8(uint16_t addr) { return read_fn_(ctx_, addr); }
    void write8(uint16_t addr, uint8_t v) { write_fn_(ctx_, addr, v); }
    uint16_t read16(uint16_t addr);
    void write16(uint16_t addr, uint16_t v);
    uint8_t fetch8();
    uint16_t fetch16();

    bool native() const { return (r_.md & MD_NATIVE) != 0; }

    // --- addressing modes -------------------------------------------------
    uint16_t ea_direct();
    uint16_t ea_extended();
    uint16_t ea_indexed(); // also adds extra cycles to cycles_
    int8_t rel8();
    int16_t rel16();

    // --- stack -------------------------------------------------
    void push8(uint16_t& sp, uint8_t v);
    uint8_t pull8(uint16_t& sp);
    void push16(uint16_t& sp, uint16_t v);
    uint16_t pull16(uint16_t& sp);

    // --- register-code helpers (TFR/EXG/ADDR family, 0-15 codes) ----------
    bool reg_code_is_16bit(int code) const;
    uint16_t get_reg_by_code(int code) const; // 8-bit regs read back as $FFxx (TFR/EXG quirk)
    uint8_t get_reg_raw8(int code) const;     // unpadded 8-bit register value
    void set_reg_by_code(int code, uint16_t v);

    // --- flags -------------------------------------------------
    void set_flag(uint8_t bit, bool v) { if (v) r_.cc |= bit; else r_.cc &= ~bit; }
    bool get_flag(uint8_t bit) const { return (r_.cc & bit) != 0; }
    void set_nz8(uint8_t v);
    void set_nz16(uint16_t v);
    bool test_condition(uint8_t cond4) const;

    // --- ALU primitives (compute result, set flags, return result) --------
    uint8_t add8(uint8_t a, uint8_t b, bool carry_in, bool affect_h);
    uint8_t sub8(uint8_t a, uint8_t b, bool borrow_in);
    uint16_t add16(uint16_t a, uint16_t b, bool carry_in = false);
    uint16_t sub16(uint16_t a, uint16_t b, bool borrow_in = false);
    uint8_t and8(uint8_t a, uint8_t b);
    uint8_t or8(uint8_t a, uint8_t b);
    uint8_t eor8(uint8_t a, uint8_t b);
    void bit8(uint8_t a, uint8_t b); // flags only
    void cmp8(uint8_t a, uint8_t b); // flags only
    void cmp16(uint16_t a, uint16_t b); // flags only
    uint16_t and16(uint16_t a, uint16_t b);
    uint16_t or16(uint16_t a, uint16_t b);
    uint16_t eor16(uint16_t a, uint16_t b);
    void bit16(uint16_t a, uint16_t b);

    // read-modify-write single-operand ops (NEG/COM/LSR/ROR/ASR/ASL/ROL/DEC/INC/TST/CLR)
    uint8_t rmw8(RmwOp op, uint8_t v);
    uint16_t rmw16(RmwOp op, uint16_t v);

    // "accumulator OP operand" ALU dispatch, shared across every addressing
    // mode and every accumulator (A/B/E/F for 8-bit, D/W for 16-bit).
    uint8_t apply_alu8(AluOp op, uint8_t reg, uint8_t operand);
    uint16_t apply_alu16(AluOp op, uint16_t reg, uint16_t operand);

    int indexed_extra_cycles(uint8_t postbyte) const;
    int rlist_extra_cycles(uint8_t postbyte) const;

    // --- interrupts -------------------------------------------------
    bool service_interrupts(); // returns true if an interrupt was serviced this step
    void push_full_set();    // PC,U,Y,X,DP,(F,E,)B,A,CC -- sets CC.E=1
    void push_partial_set(); // PC,CC -- sets CC.E=0
    void enter_interrupt(uint16_t vector, uint8_t cc_set_mask, bool full_stack);
    void illegal_opcode_trap();
    void division_by_zero_trap();

    // --- execution -------------------------------------------------
    void execute(uint8_t opcode);
    void execute_page10(uint8_t opcode);
    void execute_page11(uint8_t opcode);

    void do_tfr_exg(uint8_t postbyte, bool is_exg);
    void do_tfm(int opcode);          // full opcode incl. page prefix (e.g. 0x1138); reads its own postbyte
    void do_divd(uint8_t divisor);    // A:B = D / divisor (8-bit signed divisor)
    void do_divq(uint16_t divisor);   // D:W = Q / divisor (16-bit signed divisor)
    void do_muld(uint16_t multiplier);// Q = D * multiplier (16x16 signed -> 32)
    void do_bitbit(int opcode);       // full opcode incl. page prefix (e.g. 0x1130); reads its own postbyte + direct addr
    void do_daa();
};

} // namespace hd6309
