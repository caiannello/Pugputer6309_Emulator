// Branch condition logic, JMP/JSR/RTS/BSR/LBSR round trips.
#include "test_framework.hpp"
#include "test_harness.hpp"

namespace {
constexpr uint8_t CC_Z = 0x04;
}

TEST(beq_branches_when_zero_set) {
    Harness h;
    h.boot_at(0x8000, { 0x27, 0x10 }); // BEQ +16
    hd6309_regs_t r = h.regs();
    r.cc = CC_Z;
    h.set_regs(r);
    hd6309_step(h.cpu);
    r = h.regs();
    CHECK_EQ_HEX(r.pc, 0x8012); // 0x8002 + 0x10
}

TEST(beq_does_not_branch_when_zero_clear) {
    Harness h;
    h.boot_at(0x8000, { 0x27, 0x10 }); // BEQ +16
    hd6309_regs_t r = h.regs();
    r.cc = 0;
    h.set_regs(r);
    hd6309_step(h.cpu);
    r = h.regs();
    CHECK_EQ_HEX(r.pc, 0x8002);
}

TEST(bra_negative_offset_branches_backward) {
    Harness h;
    h.boot_at(0x8010, { 0x20, 0xFE }); // BRA -2 (infinite-loop encoding, but we only single-step)
    hd6309_step(h.cpu);
    hd6309_regs_t r = h.regs();
    CHECK_EQ_HEX(r.pc, 0x8010); // 0x8012 - 2
}

TEST(lbra_long_branch) {
    Harness h;
    h.boot_at(0x8000, { 0x16, 0x01, 0x00 }); // LBRA +256
    hd6309_step(h.cpu);
    hd6309_regs_t r = h.regs();
    CHECK_EQ_HEX(r.pc, 0x8103);
}

TEST(jmp_extended) {
    Harness h;
    h.boot_at(0x8000, { 0x7E, 0x90, 0x00 }); // JMP $9000
    hd6309_step(h.cpu);
    hd6309_regs_t r = h.regs();
    CHECK_EQ_HEX(r.pc, 0x9000);
}

TEST(jsr_pushes_return_address_and_rts_restores) {
    Harness h;
    h.boot_at(0x8000, {
        0xBD, 0x90, 0x00, // JSR $9000
        0x12,             // NOP (return lands here)
    });
    h.mem()[0x9000] = 0x39; // RTS
    hd6309_regs_t r = h.regs();
    r.s = 0x7F00;
    h.set_regs(r);
    hd6309_step(h.cpu); // JSR
    r = h.regs();
    CHECK_EQ_HEX(r.pc, 0x9000);
    CHECK_EQ_HEX(r.s, 0x7EFE);
    hd6309_step(h.cpu); // RTS
    r = h.regs();
    CHECK_EQ_HEX(r.pc, 0x8003);
    CHECK_EQ_HEX(r.s, 0x7F00);
}

TEST(bsr_and_rts) {
    Harness h;
    h.boot_at(0x8000, {
        0x8D, 0x02, // BSR +2 -> target 0x8004
        0x12,       // NOP (return address)
        0x12,       // NOP (padding so target isn't the return addr)
        0x39,       // RTS at 0x8004
    });
    hd6309_regs_t r = h.regs();
    r.s = 0x7F00;
    h.set_regs(r);
    hd6309_step(h.cpu); // BSR
    r = h.regs();
    CHECK_EQ_HEX(r.pc, 0x8004);
    hd6309_step(h.cpu); // RTS
    r = h.regs();
    CHECK_EQ_HEX(r.pc, 0x8002);
}
