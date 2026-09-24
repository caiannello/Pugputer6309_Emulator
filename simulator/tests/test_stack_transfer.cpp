// PSHS/PULS/PSHU/PULU register-list stack ops, and TFR/EXG including the
// documented "8-bit register reads as $FFxx in a 16-bit context" quirk
// and the 6309-native W/V/E/F registers.
#include "test_framework.hpp"
#include "test_harness.hpp"

TEST(pshs_puls_round_trip_full_set) {
    Harness h;
    h.boot_at(0x8000, {
        0x34, 0xFF, // PSHS PC,U,Y,X,DP,B,A,CC (postbyte handled here just as a full set push against a pre-seeded S)
        0x35, 0xFF, // PULS restores same set
    });
    hd6309_regs_t r = h.regs();
    r.s = 0x7F00;
    r.pc = 0x8000; // will be overwritten by boot_at's reset anyway; re-set after
    r.x = 0x1111; r.y = 0x2222; r.u = 0x3333;
    r.a = 0x44; r.b = 0x55; r.dp = 0x66; r.cc = 0x00;
    h.set_regs(r);
    hd6309_regs_t before = h.regs();

    hd6309_step(h.cpu); // PSHS
    hd6309_regs_t mid = h.regs();
    CHECK_EQ_HEX(mid.s, before.s - 12); // PC+U+Y+X (2 each) + DP+B+A+CC (1 each) = 8+4 = 12

    // Corrupt the registers so PULS has something to prove
    mid.x = 0; mid.y = 0; mid.u = 0; mid.a = 0; mid.b = 0; mid.dp = 0;
    h.set_regs(mid);

    hd6309_step(h.cpu); // PULS
    hd6309_regs_t after = h.regs();
    CHECK_EQ_HEX(after.x, 0x1111);
    CHECK_EQ_HEX(after.y, 0x2222);
    CHECK_EQ_HEX(after.u, 0x3333);
    CHECK_EQ_HEX(after.a, 0x44);
    CHECK_EQ_HEX(after.b, 0x55);
    CHECK_EQ_HEX(after.dp, 0x66);
    CHECK_EQ_HEX(after.s, before.s);
}

TEST(pshu_uses_s_for_the_bit6_slot) {
    Harness h;
    h.boot_at(0x8000, { 0x36, 0x40 }); // PSHU with only the "S" bit set
    hd6309_regs_t r = h.regs();
    r.u = 0x6000;
    r.s = 0xABCD;
    h.set_regs(r);
    hd6309_step(h.cpu);
    CHECK_EQ_HEX(h.mem()[0x5FFE], 0xAB);
    CHECK_EQ_HEX(h.mem()[0x5FFF], 0xCD);
    r = h.regs();
    CHECK_EQ_HEX(r.u, 0x5FFE);
}

TEST(tfr_x_to_y) {
    Harness h;
    h.boot_at(0x8000, { 0x1F, 0x12 }); // TFR X,Y  (src=1(X), dst=2(Y))
    hd6309_regs_t r = h.regs();
    r.x = 0xBEEF;
    r.y = 0x0000;
    h.set_regs(r);
    hd6309_step(h.cpu);
    r = h.regs();
    CHECK_EQ_HEX(r.y, 0xBEEF);
    CHECK_EQ_HEX(r.x, 0xBEEF); // source unchanged
}

TEST(tfr_8bit_source_pads_with_ff_high_byte) {
    Harness h;
    h.boot_at(0x8000, { 0x1F, 0x81 }); // TFR A,X (src=8(A), dst=1(X))
    hd6309_regs_t r = h.regs();
    r.a = 0x42;
    r.x = 0;
    h.set_regs(r);
    hd6309_step(h.cpu);
    r = h.regs();
    CHECK_EQ_HEX(r.x, 0xFF42);
}

TEST(exg_d_and_x_swaps_both) {
    Harness h;
    h.boot_at(0x8000, { 0x1E, 0x01 }); // EXG D,X (src=0(D), dst=1(X))
    hd6309_regs_t r = h.regs();
    r.a = 0x12; r.b = 0x34; // D = 0x1234
    r.x = 0x5678;
    h.set_regs(r);
    hd6309_step(h.cpu);
    r = h.regs();
    CHECK_EQ_HEX(r.x, 0x1234);
    CHECK_EQ_HEX(static_cast<uint16_t>((r.a << 8) | r.b), 0x5678);
}

TEST(tfr_w_register_native_pair) {
    Harness h;
    h.boot_at(0x8000, { 0x1F, 0x67 }); // TFR W,V (src=6(W), dst=7(V))
    hd6309_regs_t r = h.regs();
    r.e = 0x11; r.f = 0x22; // W = 0x1122
    r.v = 0;
    h.set_regs(r);
    hd6309_step(h.cpu);
    r = h.regs();
    CHECK_EQ_HEX(r.v, 0x1122);
}

TEST(pshsw_pulsw_round_trip) {
    Harness h;
    h.boot_at(0x8000, { 0x10, 0x38, 0x10, 0x39 }); // PSHSW ; PULSW
    hd6309_regs_t r = h.regs();
    r.s = 0x7F00;
    r.e = 0xAA; r.f = 0xBB;
    h.set_regs(r);
    hd6309_step(h.cpu); // PSHSW
    hd6309_regs_t mid = h.regs();
    CHECK_EQ_HEX(mid.s, 0x7EFE);
    mid.e = 0; mid.f = 0;
    h.set_regs(mid);
    hd6309_step(h.cpu); // PULSW
    hd6309_regs_t after = h.regs();
    CHECK_EQ_HEX(after.e, 0xAA);
    CHECK_EQ_HEX(after.f, 0xBB);
    CHECK_EQ_HEX(after.s, 0x7F00);
}
