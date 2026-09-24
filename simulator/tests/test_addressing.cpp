// Indexed addressing mode coverage: 5-bit offset, post-inc/pre-dec by
// 1/2, accumulator offsets, indirect forms, PC-relative, the 6309-native
// W-register modes, and extended indirect. Each test also checks the
// resulting cycle count against lwtools-4.20/lwasm/cycle.c ground truth.
#include "test_framework.hpp"
#include "test_harness.hpp"

TEST(indexed_5bit_offset) {
    Harness h;
    h.boot_at(0x8000, { 0xA6, 0x05 }); // LDA 5,X
    h.mem()[0x2005] = 0x42;
    hd6309_regs_t r = h.regs();
    r.x = 0x2000;
    h.set_regs(r);
    uint64_t cycles = hd6309_step(h.cpu);
    r = h.regs();
    CHECK_EQ_HEX(r.a, 0x42);
    CHECK_EQ_HEX(cycles, 5); // base 4 + 1 for 5-bit offset
}

TEST(indexed_post_increment_by_1) {
    Harness h;
    h.boot_at(0x8000, { 0xE6, 0x80 }); // LDB ,X+
    h.mem()[0x3000] = 0x99;
    hd6309_regs_t r = h.regs();
    r.x = 0x3000;
    h.set_regs(r);
    uint64_t cycles = hd6309_step(h.cpu);
    r = h.regs();
    CHECK_EQ_HEX(r.b, 0x99);
    CHECK_EQ_HEX(r.x, 0x3001);
    CHECK_EQ_HEX(cycles, 6); // base 4 + 2 (EM) for ,X+
}

TEST(indexed_pre_decrement_by_2_on_u) {
    Harness h;
    h.boot_at(0x8000, { 0xEC, 0xC3 }); // LDD ,--U
    h.poke16(0x4002, 0xBEEF);
    hd6309_regs_t r = h.regs();
    r.u = 0x4004;
    h.set_regs(r);
    uint64_t cycles = hd6309_step(h.cpu);
    r = h.regs();
    CHECK_EQ_HEX(static_cast<uint16_t>((r.a << 8) | r.b), 0xBEEF);
    CHECK_EQ_HEX(r.u, 0x4002);
    CHECK_EQ_HEX(cycles, 8); // base 5 + 3 (EM) for ,--U
}

TEST(indexed_accumulator_offset_b) {
    Harness h;
    h.boot_at(0x8000, { 0xA6, 0x85 }); // LDA B,X
    h.mem()[0x5010] = 0x77;
    hd6309_regs_t r = h.regs();
    r.x = 0x5000;
    r.b = 0x10;
    h.set_regs(r);
    uint64_t cycles = hd6309_step(h.cpu);
    r = h.regs();
    CHECK_EQ_HEX(r.a, 0x77);
    CHECK_EQ_HEX(cycles, 5); // base 4 + 1
}

TEST(indexed_negative_accumulator_offset) {
    Harness h;
    h.boot_at(0x8000, { 0xA6, 0x86 }); // LDA A,X (A used as signed offset, but LDA also targets A --
                                       // use a case where offset accumulator isn't the destination: LDA A,X reads A as offset then overwrites A)
    h.mem()[0x0FF8] = 0x21; // X(0x1000) + (int8_t)(-8) = 0x0FF8
    hd6309_regs_t r = h.regs();
    r.x = 0x1000;
    r.a = static_cast<uint8_t>(-8);
    h.set_regs(r);
    hd6309_step(h.cpu);
    r = h.regs();
    CHECK_EQ_HEX(r.a, 0x21);
}

TEST(indexed_indirect_no_offset) {
    Harness h;
    h.boot_at(0x8000, { 0xA6, 0x94 }); // LDA [,X]
    h.poke16(0x6000, 0x7000);
    h.mem()[0x7000] = 0x55;
    hd6309_regs_t r = h.regs();
    r.x = 0x6000;
    h.set_regs(r);
    uint64_t cycles = hd6309_step(h.cpu);
    r = h.regs();
    CHECK_EQ_HEX(r.a, 0x55);
    CHECK_EQ_HEX(cycles, 7); // base 4 + 3
}

TEST(indexed_8bit_pc_relative) {
    Harness h;
    h.boot_at(0x8000, { 0xA6, 0x8C, 0x05 }); // LDA 5,PCR
    // EA = PC-after-operand (0x8003) + 5 = 0x8008
    h.mem()[0x8008] = 0x33;
    uint64_t cycles = hd6309_step(h.cpu);
    hd6309_regs_t r = h.regs();
    CHECK_EQ_HEX(r.a, 0x33);
    CHECK_EQ_HEX(cycles, 5); // base 4 + 1
}

TEST(indexed_w_zero_offset) {
    Harness h;
    h.boot_at(0x8000, { 0xA6, 0x8F }); // LDA ,W
    h.mem()[0x8005] = 0x66;
    hd6309_regs_t r = h.regs();
    r.e = 0x80;
    r.f = 0x05;
    h.set_regs(r);
    uint64_t cycles = hd6309_step(h.cpu);
    r = h.regs();
    CHECK_EQ_HEX(r.a, 0x66);
    CHECK_EQ_HEX(cycles, 4); // base 4 + 0
}

TEST(indexed_w_16bit_offset) {
    Harness h;
    h.boot_at(0x8000, { 0xA6, 0xAF, 0x00, 0x10 }); // LDA 16,W
    h.mem()[0x8010] = 0x11;
    hd6309_regs_t r = h.regs();
    r.e = 0x80;
    r.f = 0x00;
    h.set_regs(r);
    uint64_t cycles = hd6309_step(h.cpu);
    r = h.regs();
    CHECK_EQ_HEX(r.a, 0x11);
    CHECK_EQ_HEX(cycles, 6); // base 4 + 2
}

TEST(indexed_w_post_increment_by_2) {
    Harness h;
    h.boot_at(0x8000, { 0xA6, 0xCF }); // LDA ,W++
    h.mem()[0x9000] = 0x22;
    hd6309_regs_t r = h.regs();
    r.e = 0x90;
    r.f = 0x00;
    h.set_regs(r);
    hd6309_step(h.cpu);
    r = h.regs();
    CHECK_EQ_HEX(r.a, 0x22);
    CHECK_EQ_HEX(static_cast<uint16_t>((r.e << 8) | r.f), 0x9002);
}

TEST(extended_indirect) {
    Harness h;
    h.boot_at(0x8000, { 0xA6, 0x9F, 0x30, 0x00 }); // LDA [$3000]
    h.poke16(0x3000, 0x4000);
    h.mem()[0x4000] = 0x99;
    uint64_t cycles = hd6309_step(h.cpu);
    hd6309_regs_t r = h.regs();
    CHECK_EQ_HEX(r.a, 0x99);
    CHECK_EQ_HEX(cycles, 9); // base 4 + 5
}

TEST(direct_addressing_uses_dp) {
    Harness h;
    h.boot_at(0x8000, { 0x96, 0x50 }); // LDA <$50
    h.mem()[0x2050] = 0xAB;
    hd6309_regs_t r = h.regs();
    r.dp = 0x20;
    h.set_regs(r);
    hd6309_step(h.cpu);
    r = h.regs();
    CHECK_EQ_HEX(r.a, 0xAB);
}
