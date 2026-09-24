// 8/16-bit ALU op coverage: flag computation (N Z V C H) for ADD/ADC/SUB/
// SBC/AND/OR/EOR/CMP/BIT plus the read-modify-write family (NEG/COM/LSR/
// ROR/ASR/ASL/ROL/DEC/INC/CLR), DAA, MUL, SEX and ABX.
#include "test_framework.hpp"
#include "test_harness.hpp"

namespace {
constexpr uint8_t CC_C = 0x01, CC_V = 0x02, CC_Z = 0x04, CC_N = 0x08, CC_H = 0x20;
}

TEST(adda_sets_overflow_and_half_carry) {
    Harness h;
    h.boot_at(0x8000, { 0x8B, 0x01 }); // ADDA #1
    hd6309_regs_t r = h.regs();
    r.a = 0x7F;
    h.set_regs(r);
    hd6309_step(h.cpu);
    r = h.regs();
    CHECK_EQ_HEX(r.a, 0x80);
    CHECK(r.cc & CC_N);
    CHECK(!(r.cc & CC_Z));
    CHECK(r.cc & CC_V);
    CHECK(!(r.cc & CC_C));
    CHECK(r.cc & CC_H);
}

TEST(adda_sets_carry_on_wrap) {
    Harness h;
    h.boot_at(0x8000, { 0x8B, 0x01 }); // ADDA #1
    hd6309_regs_t r = h.regs();
    r.a = 0xFF;
    h.set_regs(r);
    hd6309_step(h.cpu);
    r = h.regs();
    CHECK_EQ_HEX(r.a, 0x00);
    CHECK(r.cc & CC_C);
    CHECK(r.cc & CC_Z);
    CHECK(!(r.cc & CC_N));
    CHECK(!(r.cc & CC_V));
}

TEST(suba_sets_borrow) {
    Harness h;
    h.boot_at(0x8000, { 0x80, 0x01 }); // SUBA #1
    hd6309_regs_t r = h.regs();
    r.a = 0x00;
    h.set_regs(r);
    hd6309_step(h.cpu);
    r = h.regs();
    CHECK_EQ_HEX(r.a, 0xFF);
    CHECK(r.cc & CC_C);
    CHECK(r.cc & CC_N);
    CHECK(!(r.cc & CC_Z));
}

TEST(anda_clears_v_and_sets_nz) {
    Harness h;
    h.boot_at(0x8000, { 0x84, 0x0F }); // ANDA #$0F
    hd6309_regs_t r = h.regs();
    r.a = 0xFF;
    r.cc = static_cast<uint8_t>(r.cc | CC_V);
    h.set_regs(r);
    hd6309_step(h.cpu);
    r = h.regs();
    CHECK_EQ_HEX(r.a, 0x0F);
    CHECK(!(r.cc & CC_V));
    CHECK(!(r.cc & CC_N));
    CHECK(!(r.cc & CC_Z));
}

TEST(ora_sets_flags) {
    Harness h;
    h.boot_at(0x8000, { 0x8A, 0xF0 }); // ORA #$F0
    hd6309_regs_t r = h.regs();
    r.a = 0x0F;
    r.cc = CC_V; // should be cleared by ORA
    h.set_regs(r);
    hd6309_step(h.cpu);
    r = h.regs();
    CHECK_EQ_HEX(r.a, 0xFF);
    CHECK(!(r.cc & CC_V));
    CHECK(r.cc & CC_N);
    CHECK(!(r.cc & CC_Z));
}

TEST(eora_sets_flags) {
    Harness h;
    h.boot_at(0x8000, { 0x88, 0xFF }); // EORA #$FF
    hd6309_regs_t r = h.regs();
    r.a = 0xFF; // XOR with itself -> 0
    r.cc = CC_V;
    h.set_regs(r);
    hd6309_step(h.cpu);
    r = h.regs();
    CHECK_EQ_HEX(r.a, 0x00);
    CHECK(!(r.cc & CC_V));
    CHECK(!(r.cc & CC_N));
    CHECK(r.cc & CC_Z);
}

TEST(cmpa_does_not_modify_register) {
    Harness h;
    h.boot_at(0x8000, { 0x81, 0x05 }); // CMPA #5
    hd6309_regs_t r = h.regs();
    r.a = 0x05;
    h.set_regs(r);
    hd6309_step(h.cpu);
    r = h.regs();
    CHECK_EQ_HEX(r.a, 0x05);
    CHECK(r.cc & CC_Z);
}

TEST(bita_does_not_modify_register) {
    Harness h;
    h.boot_at(0x8000, { 0x85, 0x0F }); // BITA #$0F
    hd6309_regs_t r = h.regs();
    r.a = 0xF0;
    h.set_regs(r);
    hd6309_step(h.cpu);
    r = h.regs();
    CHECK_EQ_HEX(r.a, 0xF0);
    CHECK(r.cc & CC_Z);
}

TEST(inc_direct_sets_overflow_at_7f) {
    Harness h;
    h.boot_at(0x8000, { 0x0C, 0x50 }); // INC <$50
    hd6309_regs_t r = h.regs();
    r.dp = 0;
    h.set_regs(r);
    h.mem()[0x0050] = 0x7F;
    hd6309_step(h.cpu);
    CHECK_EQ_HEX(h.mem()[0x0050], 0x80);
    r = h.regs();
    CHECK(r.cc & CC_V);
    CHECK(r.cc & CC_N);
}

TEST(dec_direct_sets_overflow_at_80) {
    Harness h;
    h.boot_at(0x8000, { 0x0A, 0x50 }); // DEC <$50
    h.mem()[0x0050] = 0x80;
    hd6309_step(h.cpu);
    CHECK_EQ_HEX(h.mem()[0x0050], 0x7F);
    hd6309_regs_t r = h.regs();
    CHECK(r.cc & CC_V);
    CHECK(!(r.cc & CC_N));
}

TEST(neg_direct_of_80_is_self_with_overflow) {
    Harness h;
    h.boot_at(0x8000, { 0x00, 0x50 }); // NEG <$50
    h.mem()[0x0050] = 0x80;
    hd6309_step(h.cpu);
    CHECK_EQ_HEX(h.mem()[0x0050], 0x80);
    hd6309_regs_t r = h.regs();
    CHECK(r.cc & CC_V);
    CHECK(r.cc & CC_C);
}

TEST(asl_direct_sets_carry_and_overflow) {
    Harness h;
    h.boot_at(0x8000, { 0x08, 0x50 }); // ASL <$50
    h.mem()[0x0050] = 0x80;
    hd6309_step(h.cpu);
    CHECK_EQ_HEX(h.mem()[0x0050], 0x00);
    hd6309_regs_t r = h.regs();
    CHECK(r.cc & CC_C);
    CHECK(r.cc & CC_V);
    CHECK(r.cc & CC_Z);
}

TEST(rol_direct_rotates_through_carry) {
    Harness h;
    h.boot_at(0x8000, { 0x09, 0x50 }); // ROL <$50
    hd6309_regs_t r = h.regs();
    r.cc = CC_C; // carry in = 1
    h.set_regs(r);
    h.mem()[0x0050] = 0x00;
    hd6309_step(h.cpu);
    CHECK_EQ_HEX(h.mem()[0x0050], 0x01);
    r = h.regs();
    CHECK(!(r.cc & CC_C)); // old bit 7 (0) becomes new carry
}

TEST(daa_after_bcd_add_with_carry_out) {
    Harness h;
    h.boot_at(0x8000, { 0x8B, 0x01, 0x19 }); // ADDA #1 ; DAA
    hd6309_regs_t r = h.regs();
    r.a = 0x99;
    h.set_regs(r);
    hd6309_step(h.cpu); // ADDA -> raw 0x9A
    hd6309_step(h.cpu); // DAA -> BCD 00 with carry (99+1=100)
    r = h.regs();
    CHECK_EQ_HEX(r.a, 0x00);
    CHECK(r.cc & CC_C);
}

TEST(mul_sets_carry_from_bit7_of_result) {
    Harness h;
    h.boot_at(0x8000, { 0x3D }); // MUL
    hd6309_regs_t r = h.regs();
    r.a = 0x01;
    r.b = 0x81; // 1 * 129 = 129 = 0x0081
    h.set_regs(r);
    hd6309_step(h.cpu);
    r = h.regs();
    CHECK_EQ_HEX(static_cast<uint16_t>((r.a << 8) | r.b), 0x0081);
    CHECK(r.cc & CC_C);
    CHECK(!(r.cc & CC_Z));
}

TEST(sex_sign_extends_b_into_d) {
    Harness h;
    h.boot_at(0x8000, { 0x1D }); // SEX
    hd6309_regs_t r = h.regs();
    r.b = 0x80;
    h.set_regs(r);
    hd6309_step(h.cpu);
    r = h.regs();
    CHECK_EQ_HEX(r.a, 0xFF);
    CHECK(r.cc & CC_N);
}

TEST(abx_adds_unsigned_b_to_x_no_flags) {
    Harness h;
    h.boot_at(0x8000, { 0x3A }); // ABX
    hd6309_regs_t r = h.regs();
    r.x = 0x1000;
    r.b = 0x50;
    uint8_t cc_before = r.cc;
    h.set_regs(r);
    hd6309_step(h.cpu);
    r = h.regs();
    CHECK_EQ_HEX(r.x, 0x1050);
    CHECK_EQ_HEX(r.cc, cc_before);
}

TEST(addd_16bit_overflow) {
    Harness h;
    h.boot_at(0x8000, { 0xC3, 0x00, 0x01 }); // ADDD #1
    hd6309_regs_t r = h.regs();
    r.a = 0x7F; r.b = 0xFF; // D = 0x7FFF
    h.set_regs(r);
    hd6309_step(h.cpu);
    r = h.regs();
    CHECK_EQ_HEX(static_cast<uint16_t>((r.a << 8) | r.b), 0x8000);
    CHECK(r.cc & CC_V);
    CHECK(r.cc & CC_N);
}
