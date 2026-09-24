// IRQ/FIRQ/NMI/SWI/SWI2/SWI3 vectoring, emulation-mode (12-byte) vs
// native-mode (14-byte, adds E/F) full-register stacking, FIRQ's normal
// 2-byte stack vs MD.1 native-FIRQ full stack, and CWAI's "pre-stack once,
// don't double-push when the interrupt actually arrives" behavior.
#include "test_framework.hpp"
#include "test_harness.hpp"

namespace {
constexpr uint8_t CC_I = 0x10, CC_F = 0x40, CC_E = 0x80;
}

TEST(reset_loads_vector_and_initializes_state) {
    Harness h;
    // Dirty every register first so reset() has something to prove.
    hd6309_regs_t r{};
    r.pc = 0x1234; r.x = 0x1111; r.y = 0x2222; r.u = 0x3333; r.s = 0x4444; r.v = 0x5555;
    r.a = 0xAA; r.b = 0xBB; r.dp = 0xCC; r.cc = 0x00; r.e = 0xDD; r.f = 0xEE; r.md = 0xFF;
    h.set_regs(r);

    h.load(0x9000, { 0x12 }); // NOP at the reset target
    h.set_reset_vector(0x9000);
    hd6309_reset(h.cpu);

    r = h.regs();
    CHECK_EQ_HEX(r.pc, 0x9000);   // PC loaded from $FFFE
    CHECK_EQ_HEX(r.cc, CC_I | CC_F); // interrupts masked out of reset
    CHECK_EQ_HEX(r.md, 0x00);     // always resets into 6809-compatible emulation mode
    CHECK_EQ_HEX(hd6309_total_cycles(h.cpu), 0u);
}

TEST(irq_masked_after_reset_is_not_serviced) {
    Harness h;
    h.boot_at(0x8000, { 0x12 }); // NOP
    h.poke16(0xFFF8, 0x9000);
    hd6309_set_irq(h.cpu, 1);
    hd6309_step(h.cpu); // reset leaves CC.I set, so IRQ must not fire
    hd6309_regs_t r = h.regs();
    CHECK_EQ_HEX(r.pc, 0x8001); // executed the NOP, not the IRQ vector
}

TEST(irq_full_stack_and_rti_round_trip) {
    Harness h;
    h.boot_at(0x8000, { 0x1C, 0xEF, 0x12 }); // ANDCC #$EF (clear I) ; NOP
    h.poke16(0xFFF8, 0x9000);
    h.mem()[0x9000] = 0x3B; // RTI
    hd6309_regs_t r = h.regs();
    r.s = 0x7F00;
    h.set_regs(r);

    hd6309_step(h.cpu); // ANDCC
    hd6309_set_irq(h.cpu, 1);
    hd6309_step(h.cpu); // services IRQ instead of the NOP
    r = h.regs();
    CHECK_EQ_HEX(r.pc, 0x9000);
    CHECK_EQ_HEX(r.s, 0x7F00 - 12);
    CHECK(r.cc & CC_I);
    CHECK(r.cc & CC_E);

    hd6309_set_irq(h.cpu, 0);
    hd6309_step(h.cpu); // RTI
    r = h.regs();
    CHECK_EQ_HEX(r.pc, 0x8002);
    CHECK_EQ_HEX(r.s, 0x7F00);
}

TEST(firq_default_partial_stack) {
    Harness h;
    h.boot_at(0x8000, { 0x1C, 0xBF, 0x12 }); // ANDCC #$BF (clear F only) ; NOP
    h.poke16(0xFFF6, 0x9100);
    h.mem()[0x9100] = 0x3B;
    hd6309_regs_t r = h.regs();
    r.s = 0x7F00;
    h.set_regs(r);

    hd6309_step(h.cpu); // ANDCC
    hd6309_set_firq(h.cpu, 1);
    hd6309_step(h.cpu); // services FIRQ
    r = h.regs();
    CHECK_EQ_HEX(r.pc, 0x9100);
    CHECK_EQ_HEX(r.s, 0x7F00 - 3); // PC(2) + CC(1)
    CHECK(!(r.cc & CC_E));
    CHECK(r.cc & CC_F);
    CHECK(r.cc & CC_I);

    hd6309_set_firq(h.cpu, 0);
    hd6309_step(h.cpu); // RTI (partial restore)
    r = h.regs();
    CHECK_EQ_HEX(r.pc, 0x8002);
    CHECK_EQ_HEX(r.s, 0x7F00);
}

TEST(firq_native_mode_full_stack) {
    Harness h;
    h.boot_at(0x8000, { 0x11, 0x3D, 0x03, 0x1C, 0xBF, 0x12 }); // LDMD #3 ; ANDCC #$BF ; NOP
    h.poke16(0xFFF6, 0x9200);
    h.mem()[0x9200] = 0x3B;
    hd6309_regs_t r = h.regs();
    r.s = 0x7F00;
    h.set_regs(r);

    hd6309_step(h.cpu); // LDMD
    hd6309_step(h.cpu); // ANDCC
    hd6309_set_firq(h.cpu, 1);
    hd6309_step(h.cpu); // services FIRQ -- native + native-FIRQ mode => full 14-byte stack
    r = h.regs();
    CHECK_EQ_HEX(r.pc, 0x9200);
    CHECK_EQ_HEX(r.s, 0x7F00 - 14);
    CHECK(r.cc & CC_E);

    hd6309_set_firq(h.cpu, 0);
    hd6309_step(h.cpu); // RTI
    r = h.regs();
    CHECK_EQ_HEX(r.pc, 0x8005);
    CHECK_EQ_HEX(r.s, 0x7F00);
}

TEST(nmi_always_serviced_regardless_of_masks) {
    Harness h;
    h.boot_at(0x8000, { 0x12 }); // NOP; reset leaves I and F both masked
    h.poke16(0xFFFC, 0x9300);
    hd6309_regs_t r = h.regs();
    r.s = 0x7F00;
    h.set_regs(r);

    hd6309_nmi_pulse(h.cpu);
    hd6309_step(h.cpu);
    r = h.regs();
    CHECK_EQ_HEX(r.pc, 0x9300);
    CHECK_EQ_HEX(r.s, 0x7F00 - 12);
}

TEST(swi_masks_irq_and_firq) {
    Harness h;
    h.boot_at(0x8000, { 0x3F }); // SWI
    h.poke16(0xFFFA, 0x9400);
    hd6309_regs_t r = h.regs();
    r.s = 0x7F00;
    r.cc = 0;
    h.set_regs(r);
    hd6309_step(h.cpu);
    r = h.regs();
    CHECK_EQ_HEX(r.pc, 0x9400);
    CHECK_EQ_HEX(r.s, 0x7F00 - 12);
    CHECK(r.cc & CC_I);
    CHECK(r.cc & CC_F);
}

TEST(swi2_does_not_mask_irq_or_firq) {
    Harness h;
    h.boot_at(0x8000, { 0x10, 0x3F }); // SWI2
    h.poke16(0xFFF4, 0x9500);
    hd6309_regs_t r = h.regs();
    r.s = 0x7F00;
    r.cc = 0;
    h.set_regs(r);
    hd6309_step(h.cpu);
    r = h.regs();
    CHECK_EQ_HEX(r.pc, 0x9500);
    CHECK(!(r.cc & CC_I));
    CHECK(!(r.cc & CC_F));
}

TEST(swi3_vectors_correctly) {
    Harness h;
    h.boot_at(0x8000, { 0x11, 0x3F }); // SWI3
    h.poke16(0xFFF2, 0x9600);
    hd6309_regs_t r = h.regs();
    r.s = 0x7F00;
    h.set_regs(r);
    hd6309_step(h.cpu);
    r = h.regs();
    CHECK_EQ_HEX(r.pc, 0x9600);
}

TEST(native_mode_interrupt_stacks_e_and_f) {
    Harness h;
    h.boot_at(0x8000, { 0x11, 0x3D, 0x01, 0x1C, 0xEF, 0x12 }); // LDMD #1 ; ANDCC #$EF ; NOP
    h.poke16(0xFFF8, 0x9700);
    h.mem()[0x9700] = 0x3B;
    hd6309_regs_t r = h.regs();
    r.s = 0x7F00;
    r.e = 0xAA;
    r.f = 0xBB;
    h.set_regs(r);

    hd6309_step(h.cpu); // LDMD
    hd6309_step(h.cpu); // ANDCC
    hd6309_set_irq(h.cpu, 1);
    hd6309_step(h.cpu); // IRQ: native mode => 14-byte stack including E/F
    r = h.regs();
    CHECK_EQ_HEX(r.s, 0x7F00 - 14);

    hd6309_set_irq(h.cpu, 0);
    r.e = 0; r.f = 0;
    h.set_regs(r);
    hd6309_step(h.cpu); // RTI restores E/F since it was a full+native stack
    r = h.regs();
    CHECK_EQ_HEX(r.e, 0xAA);
    CHECK_EQ_HEX(r.f, 0xBB);
    CHECK_EQ_HEX(r.s, 0x7F00);
}

TEST(cwai_pre_stacks_and_interrupt_does_not_double_push) {
    Harness h;
    h.boot_at(0x8000, { 0x3C, 0xEF }); // CWAI #$EF (clear I)
    h.poke16(0xFFF8, 0x9600);
    h.mem()[0x9600] = 0x3B;
    hd6309_regs_t r = h.regs();
    r.s = 0x7F00;
    r.cc = 0x00;
    h.set_regs(r);

    hd6309_step(h.cpu); // CWAI itself: pushes full set once, then enters the wait state
    r = h.regs();
    CHECK_EQ_HEX(r.s, 0x7F00 - 12);

    hd6309_step(h.cpu); // no interrupt pending yet: this step just idles in the wait state
    CHECK_EQ_HEX(static_cast<int>(hd6309_get_stop_reason(h.cpu)), static_cast<int>(HD6309_STOP_SYNC));

    hd6309_set_irq(h.cpu, 1);
    hd6309_step(h.cpu); // interrupt arrives: must NOT push again
    r = h.regs();
    CHECK_EQ_HEX(r.pc, 0x9600);
    CHECK_EQ_HEX(r.s, 0x7F00 - 12); // unchanged from the CWAI push
}
