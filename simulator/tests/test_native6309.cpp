// HD6309-native instruction coverage: register-to-register ALU (ADDR/
// CMPR family), AIM/OIM/EIM/TIM, the BAND single-bit family, TFM block
// transfer, DIVD/DIVQ/MULD, SEXW, LDQ/STQ, and LDMD/BITMD.
#include "test_framework.hpp"
#include "test_harness.hpp"

namespace {
constexpr uint8_t CC_C = 0x01, CC_V = 0x02, CC_Z = 0x04, CC_N = 0x08;
constexpr uint8_t MD_NATIVE = 0x01, MD_ILLEGAL = 0x40, MD_DIVZERO = 0x80;
}

TEST(addr_register_to_register) {
    Harness h;
    h.boot_at(0x8000, { 0x10, 0x30, 0x89 }); // ADDR A,B  (src=A, dst=B)
    hd6309_regs_t r = h.regs();
    r.a = 0x05;
    r.b = 0x03;
    h.set_regs(r);
    hd6309_step(h.cpu);
    r = h.regs();
    CHECK_EQ_HEX(r.b, 0x08);
    CHECK_EQ_HEX(r.a, 0x05); // source unchanged
}

TEST(andd_ord_eord_16bit_logic_family) {
    // ANDD/ORD/EORD are 6309-native additions filling the gap that D had
    // no logical ops in the base 6809 set (A/B alone had AND/OR/EOR).
    Harness h;
    h.boot_at(0x8000, {
        0x10, 0x84, 0x0F, 0x0F, // ANDD #$0F0F
        0x10, 0x8A, 0xF0, 0xF0, // ORD  #$F0F0
        0x10, 0x88, 0xFF, 0xFF, // EORD #$FFFF
    });
    hd6309_regs_t r = h.regs();
    r.a = 0xFF; r.b = 0xFF; // D = $FFFF
    h.set_regs(r);

    hd6309_step(h.cpu); // ANDD -> $0F0F
    r = h.regs();
    CHECK_EQ_HEX(static_cast<uint16_t>((r.a << 8) | r.b), 0x0F0F);
    CHECK(!(r.cc & CC_V));

    hd6309_step(h.cpu); // ORD -> $FFFF
    r = h.regs();
    CHECK_EQ_HEX(static_cast<uint16_t>((r.a << 8) | r.b), 0xFFFF);
    CHECK(r.cc & CC_N);

    hd6309_step(h.cpu); // EORD -> $0000
    r = h.regs();
    CHECK_EQ_HEX(static_cast<uint16_t>((r.a << 8) | r.b), 0x0000);
    CHECK(r.cc & CC_Z);
}

TEST(cmpr_discards_result) {
    Harness h;
    h.boot_at(0x8000, { 0x10, 0x37, 0x12 }); // CMPR X,Y (src=X, dst=Y)
    hd6309_regs_t r = h.regs();
    r.x = 0x1234;
    r.y = 0x1234;
    h.set_regs(r);
    hd6309_step(h.cpu);
    r = h.regs();
    CHECK(r.cc & CC_Z);
    CHECK_EQ_HEX(r.y, 0x1234); // dest unchanged (compare-only)
}

TEST(aim_ands_memory_with_immediate_mask) {
    Harness h;
    h.boot_at(0x8000, { 0x02, 0x0F, 0x50 }); // AIM #$0F,<$50
    h.mem()[0x0050] = 0xFF;
    hd6309_step(h.cpu);
    CHECK_EQ_HEX(h.mem()[0x0050], 0x0F);
}

TEST(oim_ors_memory_indexed) {
    Harness h;
    h.boot_at(0x8000, { 0x61, 0x0F, 0x84 }); // OIM #$0F,[,X]-style zero offset on X
    hd6309_regs_t r = h.regs();
    r.x = 0x2000;
    h.set_regs(r);
    h.mem()[0x2000] = 0xF0;
    hd6309_step(h.cpu);
    CHECK_EQ_HEX(h.mem()[0x2000], 0xFF);
}

TEST(tim_does_not_write_back) {
    Harness h;
    h.boot_at(0x8000, { 0x0B, 0xF0, 0x50 }); // TIM #$F0,<$50
    h.mem()[0x0050] = 0x0F;
    hd6309_step(h.cpu);
    CHECK_EQ_HEX(h.mem()[0x0050], 0x0F); // unchanged
    hd6309_regs_t r = h.regs();
    CHECK(r.cc & CC_Z); // 0x0F & 0xF0 == 0
}

TEST(band_ands_register_bit_with_memory_bit) {
    Harness h;
    // BAND A.0, <$50>.0  -- postbyte = (reg=1<<6)|(membit=0<<3)|(regbit=0)
    h.boot_at(0x8000, { 0x11, 0x30, 0x40, 0x50 });
    hd6309_regs_t r = h.regs();
    r.dp = 0;
    r.a = 0x01; // bit 0 set
    h.set_regs(r);
    h.mem()[0x0050] = 0x00; // bit 0 clear
    hd6309_step(h.cpu);
    r = h.regs();
    CHECK_EQ_HEX(r.a & 0x01, 0x00); // 1 AND 0 = 0
}

TEST(ldbt_loads_register_bit_from_memory) {
    Harness h;
    // LDBT A.2, <$50>.5 -- postbyte = (reg=1<<6)|(membit=5<<3)|(regbit=2)
    h.boot_at(0x8000, { 0x11, 0x36, static_cast<uint8_t>((1 << 6) | (5 << 3) | 2), 0x50 });
    hd6309_regs_t r = h.regs();
    r.a = 0x00;
    h.set_regs(r);
    h.mem()[0x0050] = 0x20; // bit 5 set
    hd6309_step(h.cpu);
    r = h.regs();
    CHECK_EQ_HEX(r.a & 0x04, 0x04); // bit 2 now set
}

TEST(stbt_stores_register_bit_to_memory) {
    Harness h;
    // STBT A.0, <$50>.3 -- postbyte = (reg=1<<6)|(membit=3<<3)|(regbit=0)
    h.boot_at(0x8000, { 0x11, 0x37, static_cast<uint8_t>((1 << 6) | (3 << 3) | 0), 0x50 });
    hd6309_regs_t r = h.regs();
    r.a = 0x01;
    h.set_regs(r);
    h.mem()[0x0050] = 0x00;
    hd6309_step(h.cpu);
    CHECK_EQ_HEX(h.mem()[0x0050] & 0x08, 0x08);
}

TEST(tfm_copies_bytes_and_increments_both_pointers) {
    Harness h;
    h.boot_at(0x8000, { 0x11, 0x38, 0x12 }); // TFM X+,Y+ (src=X=1, dst=Y=2)
    hd6309_regs_t r = h.regs();
    r.x = 0x3000;
    r.y = 0x4000;
    r.e = 0x00; r.f = 0x04; // W = 4 bytes to copy
    h.set_regs(r);
    h.mem()[0x3000] = 0x11;
    h.mem()[0x3001] = 0x22;
    h.mem()[0x3002] = 0x33;
    h.mem()[0x3003] = 0x44;
    hd6309_step(h.cpu);
    CHECK_EQ_HEX(h.mem()[0x4000], 0x11);
    CHECK_EQ_HEX(h.mem()[0x4001], 0x22);
    CHECK_EQ_HEX(h.mem()[0x4002], 0x33);
    CHECK_EQ_HEX(h.mem()[0x4003], 0x44);
    r = h.regs();
    CHECK_EQ_HEX(r.x, 0x3004);
    CHECK_EQ_HEX(r.y, 0x4004);
    CHECK_EQ_HEX(static_cast<uint16_t>((r.e << 8) | r.f), 0x0000);
}

TEST(divd_normal_division) {
    Harness h;
    h.boot_at(0x8000, { 0x11, 0x8D, 7 }); // DIVD #7
    hd6309_regs_t r = h.regs();
    r.a = 0x00; r.b = 0x64; // D = 100
    h.set_regs(r);
    hd6309_step(h.cpu);
    r = h.regs();
    CHECK_EQ_HEX(r.b, 14); // quotient
    CHECK_EQ_HEX(r.a, 2);  // remainder
    CHECK(!(r.cc & CC_V));
}

TEST(divd_by_zero_traps) {
    Harness h;
    h.boot_at(0x8000, { 0x11, 0x8D, 0 }); // DIVD #0
    h.poke16(0xFFF0, 0x9000);
    h.mem()[0x9000] = 0x3F; // SWI-equivalent halt marker not needed; just confirm PC redirect
    hd6309_regs_t r = h.regs();
    r.a = 0x00; r.b = 0x64;
    h.set_regs(r);
    hd6309_step(h.cpu);
    r = h.regs();
    CHECK_EQ_HEX(r.pc, 0x9000);
    CHECK(r.md & MD_DIVZERO);
}

TEST(divq_normal_division) {
    Harness h;
    h.boot_at(0x8000, { 0x11, 0x8E, 0x00, 0x0A }); // DIVQ #10
    hd6309_regs_t r = h.regs();
    r.a = 0x00; r.b = 0x00; // D = 0 (quotient high)
    r.e = 0x00; r.f = 100;  // W = 100 (dividend low / eventually remainder)
    h.set_regs(r);
    // Dividend is the full 32-bit D:W = 100; divide by 10 -> quotient 10, remainder 0
    hd6309_step(h.cpu);
    r = h.regs();
    CHECK_EQ_HEX(static_cast<uint16_t>((r.a << 8) | r.b), 10);
    CHECK_EQ_HEX(static_cast<uint16_t>((r.e << 8) | r.f), 0);
}

TEST(muld_signed_multiply) {
    Harness h;
    h.boot_at(0x8000, { 0x11, 0x8F, 0x00, 0x03 }); // MULD #3
    hd6309_regs_t r = h.regs();
    r.a = 0x00; r.b = 0x05; // D = 5
    h.set_regs(r);
    hd6309_step(h.cpu);
    r = h.regs();
    uint32_t q = (static_cast<uint32_t>((r.a << 8) | r.b) << 16) | static_cast<uint16_t>((r.e << 8) | r.f);
    CHECK_EQ_HEX(q, 15u);
}

TEST(sexw_sign_extends_w_into_d) {
    Harness h;
    h.boot_at(0x8000, { 0x14 }); // SEXW
    hd6309_regs_t r = h.regs();
    r.e = 0x80; r.f = 0x00; // W negative
    h.set_regs(r);
    hd6309_step(h.cpu);
    r = h.regs();
    CHECK_EQ_HEX(r.a, 0xFF);
    CHECK_EQ_HEX(r.b, 0xFF);
}

TEST(ldq_immediate_and_stq_direct_round_trip) {
    Harness h;
    h.boot_at(0x8000, {
        0xCD, 0x11, 0x22, 0x33, 0x44,       // LDQ #$11223344
        0x10, 0xDD, 0x50,                    // STQ <$50
    });
    hd6309_regs_t r = h.regs();
    r.dp = 0;
    h.set_regs(r);
    hd6309_step(h.cpu); // LDQ
    r = h.regs();
    CHECK_EQ_HEX(r.a, 0x11);
    CHECK_EQ_HEX(r.b, 0x22);
    CHECK_EQ_HEX(r.e, 0x33);
    CHECK_EQ_HEX(r.f, 0x44);
    hd6309_step(h.cpu); // STQ
    CHECK_EQ_HEX(h.mem()[0x0050], 0x11);
    CHECK_EQ_HEX(h.mem()[0x0051], 0x22);
    CHECK_EQ_HEX(h.mem()[0x0052], 0x33);
    CHECK_EQ_HEX(h.mem()[0x0053], 0x44);
}

TEST(ldmd_sets_native_mode) {
    Harness h;
    h.boot_at(0x8000, { 0x11, 0x3D, 0x01 }); // LDMD #1
    hd6309_step(h.cpu);
    hd6309_regs_t r = h.regs();
    CHECK(r.md & MD_NATIVE);
}

TEST(bitmd_tests_and_clears_trap_flags) {
    Harness h;
    h.boot_at(0x8000, { 0x11, 0x3C, 0x40 }); // BITMD #%01000000
    hd6309_regs_t r = h.regs();
    r.md = MD_ILLEGAL;
    h.set_regs(r);
    hd6309_step(h.cpu);
    r = h.regs();
    CHECK(!(r.cc & CC_Z));    // MD.6 was set, so AND test is non-zero
    CHECK(!(r.md & MD_ILLEGAL)); // BITMD clears the bit it tested
}
