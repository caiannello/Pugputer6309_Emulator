// The C library's floating point (cc/lib/fpcore.asm, which CC1 includes too, to
// fold constants and read numbers), run on the CPU alone and compared, bit for
// bit, with the PC's IEEE single precision: + - * / and comparisons, the
// conversions to and from longs, and decimal scaling. fpcore has no denormals
// (a result that small is a zero), so cases whose exact result is that small
// are left out of the random ones and checked on their own.
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <iterator>
#include <limits>
#include <random>
#include <string>
#include <vector>

#include "test_framework.hpp"
#include "test_harness.hpp"

namespace {

std::vector<uint8_t> assemble_harness() {
    std::string src = std::string(HD6309_TEST_ASM_DIR) + "/fpcore_harness.asm";
    std::string out_dir = HD6309_TEST_BUILD_DIR;
#ifdef _WIN32
    std::string mkdir_cmd = std::string("mkdir \"") + out_dir + "\" >NUL 2>NUL";
#else
    std::string mkdir_cmd = std::string("mkdir -p \"") + out_dir + "\"";
#endif
    std::system(mkdir_cmd.c_str());
    std::string out = out_dir + "/fpcore_harness.bin";
    std::string cmd = std::string("\"") + LWASM_EXE_PATH + "\" --6309 --raw --includedir=\"" + FPCORE_DIR + "\" -o \"" +
                      out + "\" \"" + src + "\"";
#ifdef _WIN32
    cmd = "\"" + cmd + "\"";
#endif
    if (std::system(cmd.c_str()) != 0) {
        std::fprintf(stderr, "  lwasm failed on fpcore_harness.asm\n");
        return {};
    }
    std::ifstream f(out, std::ios::binary);
    return std::vector<uint8_t>((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
}

enum : uint16_t {
    F_ADD = 0x1000, F_SUB = 0x1003, F_MUL = 0x1006, F_DIV = 0x1009, F_CMP = 0x100C,
    F_LTOF = 0x100F, F_ULTOF = 0x1012, F_FTOL = 0x1015, F_FTOUL = 0x1018,
    F_DEC2F = 0x101B, F_XINT = 0x101E, F_INC = 0x1021, F_DEC = 0x1024, F_DONE = 0x1027
};

uint32_t bits(float f) { uint32_t u; std::memcpy(&u, &f, 4); return u; }
float flt(uint32_t u) { float f; std::memcpy(&f, &u, 4); return f; }

struct Fp {
    Harness h;
    bool ok = false;
    uint64_t cycles = 0; // the last call's
    Fp() {
        std::vector<uint8_t> bin = assemble_harness();
        if (bin.empty()) return;
        for (size_t i = 0; i < bin.size(); ++i) h.mem()[0x1000 + i] = bin[i];
        hd6309_add_breakpoint(h.cpu, F_DONE);
        h.set_reset_vector(F_DONE);
        hd6309_reset(h.cpu);
        h.set_native(true);
        ok = true;
    }
    // Calls a routine with Q = q, X = x and (for the helpers) b at 2,S -> Q.
    // Checks that it kept X (unless it takes X), Y and U, and the stack.
    uint32_t call(uint16_t at, uint32_t q, uint32_t b = 0, uint16_t x = 0x1234, uint16_t* d_out = nullptr,
                  uint8_t* cc_out = nullptr) {
        const uint16_t sp = 0x7FF0;
        h.poke16(sp, F_DONE);
        h.poke16(sp + 2, static_cast<uint16_t>(b >> 16));
        h.poke16(sp + 4, static_cast<uint16_t>(b));
        hd6309_regs_t r = h.regs();
        r.pc = at;
        r.s = sp;
        r.x = x;
        r.y = 0x5A5A;
        r.u = 0xA5A5;
        r.a = static_cast<uint8_t>(q >> 24);
        r.b = static_cast<uint8_t>(q >> 16);
        r.e = static_cast<uint8_t>(q >> 8);
        r.f = static_cast<uint8_t>(q);
        h.set_regs(r);
        uint64_t before = hd6309_total_cycles(h.cpu);
        hd6309_run(h.cpu, 200000);
        cycles = hd6309_total_cycles(h.cpu) - before;
        r = h.regs();
        if (r.pc != F_DONE || r.s != sp + 2 || r.y != 0x5A5A || r.u != 0xA5A5 ||
            (at != F_DEC2F && at != F_XINT && r.x != x)) {
            std::fprintf(stderr, "  routine $%04X: pc %04X s %04X x %04X y %04X u %04X\n", at, r.pc, r.s, r.x, r.y,
                         r.u);
            ok = false;
        }
        if (d_out) *d_out = static_cast<uint16_t>((r.a << 8) | r.b);
        if (cc_out) *cc_out = r.cc;
        return (static_cast<uint32_t>(r.a) << 24) | (static_cast<uint32_t>(r.b) << 16) |
               (static_cast<uint32_t>(r.e) << 8) | r.f;
    }
};

// What fpcore should give: IEEE's result, with a denormal operand taken as 0.
float ftz(float f) { return std::fpclassify(f) == FP_SUBNORMAL ? std::copysign(0.0f, f) : f; }
bool same_bits(uint32_t want, uint32_t got) {
    float w = flt(want), g = flt(got);
    if (std::isnan(w)) return std::isnan(g);
    return want == got;
}
// The exact result is a normal number (or 0, or infinite) and not too close
// to the denormals for fpcore's flush to differ from rounding.
bool normal_result(double exact) {
    double a = std::fabs(exact);
    return a == 0 || std::isinf(a) || std::isnan(exact) || a >= 2.0 * std::numeric_limits<float>::min();
}

float random_float(std::mt19937& rng, int emin, int emax) {
    std::uniform_int_distribution<int> e(emin, emax);
    std::uniform_int_distribution<uint32_t> frac(0, 0x7FFFFF), sign(0, 1);
    uint32_t u = (sign(rng) << 31) | (static_cast<uint32_t>(e(rng) + 127) << 23) | frac(rng);
    return flt(u);
}

} // namespace

TEST(fpcore_arithmetic_matches_ieee_single_bit_for_bit) {
    Fp fp;
    CHECK(fp.ok);
    if (!fp.ok) return;
    std::mt19937 rng(6309);
    const uint16_t ops[] = {F_ADD, F_SUB, F_MUL, F_DIV};
    const char* names[] = {"+", "-", "*", "/"};
    uint64_t total[4] = {}, n[4] = {};
    int bad = 0;
    for (int i = 0; i < 40000 && bad < 10; ++i) {
        int op = i % 4;
        // Mostly near each other (so + and - round and cancel), sometimes far.
        int range = (i / 4) % 3 == 0 ? 120 : 12;
        float a = random_float(rng, -range, range), b = random_float(rng, -range, range);
        if (i % 97 == 0) b = a;                   // x - x, x / x
        if (i % 89 == 0) b = -a;
        double da = a, db = b, exact = op == 0 ? da + db : op == 1 ? da - db : op == 2 ? da * db : da / db;
        if (!normal_result(exact)) continue;
        float want = static_cast<float>(exact); // (correctly rounded: a double holds it exactly, or near enough)
        uint32_t got = fp.call(ops[op], bits(a), bits(b));
        total[op] += fp.cycles;
        ++n[op];
        if (!same_bits(bits(want), got)) {
            std::fprintf(stderr, "  %.9g %s %.9g: want %08X got %08X\n", a, names[op], b, bits(want), got);
            ++bad;
        }
    }
    CHECK(bad == 0);
    CHECK(fp.ok);
    for (int op = 0; op < 4; ++op)
        if (std::getenv("FP_TIMING"))
            std::printf("  %s: %llu cycles on average\n", names[op],
                        static_cast<unsigned long long>(total[op] / (n[op] ? n[op] : 1)));
}

TEST(fpcore_handles_zeros_infinities_nans_and_the_edges) {
    Fp fp;
    CHECK(fp.ok);
    if (!fp.ok) return;
    const float inf = std::numeric_limits<float>::infinity(), nan = std::numeric_limits<float>::quiet_NaN();
    const float fmax = std::numeric_limits<float>::max(), fmin = std::numeric_limits<float>::min();
    const float specials[] = {0.0f, -0.0f, 1.0f, -1.0f, 0.5f, 3.0f, inf, -inf, nan, fmax, -fmax, fmin, -fmin,
                              1e-30f, 1e30f, 16777216.0f, 16777217.0f, 1.0000001f, 0.99999994f, 1e-45f /* denormal */};
    const uint16_t ops[] = {F_ADD, F_SUB, F_MUL, F_DIV};
    int bad = 0;
    for (float a : specials)
        for (float b : specials)
            for (int op = 0; op < 4; ++op) {
                float x = ftz(a), y = ftz(b);
                double exact = op == 0 ? double(x) + y : op == 1 ? double(x) - y : op == 2 ? double(x) * y : double(x) / y;
                if (!normal_result(exact)) continue; // (the flush and IEEE's denormals differ here)
                float want = static_cast<float>(exact);
                uint32_t got = fp.call(ops[op], bits(a), bits(b));
                if (!same_bits(bits(want), got) && bad++ < 10)
                    std::fprintf(stderr, "  op %d: %g, %g: want %08X got %08X\n", op, a, b, bits(want), got);
            }
    CHECK(bad == 0);
    bad = 0;
    // Comparisons: -1, 0 or 1 in D, and the flags a signed branch wants (N, Z).
    std::mt19937 rng(9);
    for (int i = 0; i < 4000; ++i) {
        float a = i < 400 ? specials[i % 19] : random_float(rng, -20, 20);
        float b = i < 400 ? specials[(i / 19) % 19] : (i % 5 == 0 ? a : random_float(rng, -20, 20));
        if (std::isnan(a) || std::isnan(b)) continue;
        a = ftz(a), b = ftz(b);
        int want = a < b ? -1 : a > b ? 1 : 0;
        uint16_t d = 0;
        uint8_t cc = 0;
        fp.call(F_CMP, bits(a), bits(b), 0x1234, &d, &cc);
        bool n = cc & 0x08, z = cc & 0x04, v = cc & 0x02;
        if (static_cast<int16_t>(d) != want || z != (want == 0) || (n != v) != (want < 0)) {
            if (bad++ < 10) std::fprintf(stderr, "  cmp %g %g: want %d got %d cc %02X\n", a, b, want, int16_t(d), cc);
        }
    }
    CHECK(bad == 0);
    CHECK(fp.call(F_INC, bits(2.5f)) == bits(3.5f));
    CHECK(fp.call(F_DEC, bits(0.25f)) == bits(-0.75f));
    CHECK(fp.ok);
}

TEST(fpcore_converts_longs_and_floats) {
    Fp fp;
    CHECK(fp.ok);
    if (!fp.ok) return;
    std::mt19937 rng(42);
    int bad = 0;
    std::vector<uint32_t> ints = {0, 1, 2, 3, 0x7FFFFFFF, 0x80000000, 0xFFFFFFFF, 16777216, 16777217, 16777219,
                                  0x7FFFFF80, 0x7FFFFFC0, 12345678, 0xFFFFFF7F};
    for (int i = 0; i < 3000; ++i) ints.push_back(rng() >> (rng() % 32));
    for (uint32_t u : ints) {
        int32_t s = static_cast<int32_t>(u);
        if (fp.call(F_LTOF, u) != bits(static_cast<float>(s)) && bad++ < 10)
            std::fprintf(stderr, "  ltof %d\n", s);
        if (fp.call(F_ULTOF, u) != bits(static_cast<float>(u)) && bad++ < 10)
            std::fprintf(stderr, "  ultof %u\n", u);
    }
    for (int i = 0; i < 3000; ++i) {
        float f = random_float(rng, -4, 33);
        if (i % 7 == 0) f = static_cast<float>(static_cast<int>(rng() % 2000) - 1000) / 8;
        double t = std::trunc(static_cast<double>(f));
        int32_t ws = t >= 2147483647.0 ? 0x7FFFFFFF : t <= -2147483648.0 ? INT32_MIN : static_cast<int32_t>(t);
        if (fp.call(F_FTOL, bits(f)) != static_cast<uint32_t>(ws) && bad++ < 10)
            std::fprintf(stderr, "  ftol %.9g: want %d\n", f, ws);
        if (f >= 0) {
            uint32_t wu = t >= 4294967295.0 ? 0xFFFFFFFF : static_cast<uint32_t>(t);
            if (fp.call(F_FTOUL, bits(f)) != wu && bad++ < 10) std::fprintf(stderr, "  ftoul %.9g: want %u\n", f, wu);
        }
    }
    CHECK(fp.call(F_FTOL, bits(std::numeric_limits<float>::infinity())) == 0x7FFFFFFF);
    CHECK(fp.call(F_FTOL, bits(-1e20f)) == 0x80000000);
    CHECK(fp.call(F_FTOUL, bits(1e20f)) == 0xFFFFFFFF);
    CHECK(fp.call(F_FTOUL, bits(-5.0f)) == static_cast<uint32_t>(-5));
    CHECK(bad == 0);
    CHECK(fp.ok);
}

TEST(fpcore_scales_by_powers_of_ten_for_decimal) {
    Fp fp;
    CHECK(fp.ok);
    if (!fp.ok) return;
    std::mt19937 rng(1977);
    int bad = 0, inexact = 0, n = 0;
    for (int i = 0; i < 4000; ++i) {
        uint32_t m = rng() % 1000000000u;
        if (i % 3 == 0) m %= 100000;
        int e = static_cast<int>(rng() % 84) - 46;
        char text[40];
        std::snprintf(text, sizeof text, "%ue%d", m, e);
        double exact = std::strtod(text, nullptr);
        if (!normal_result(exact) || exact > std::numeric_limits<float>::max()) continue;
        float want = std::strtof(text, nullptr);
        uint32_t got = fp.call(F_DEC2F, m, 0, static_cast<uint16_t>(e));
        ++n;
        int32_t ulps = static_cast<int32_t>(got - bits(want));
        if (ulps != 0) ++inexact;
        if ((ulps < -1 || ulps > 1) && bad++ < 10) std::fprintf(stderr, "  %s: want %08X got %08X\n", text, bits(want), got);
    }
    CHECK(bad == 0);
    CHECK(inexact * 200 <= n); // at most 1 in 200 a unit off in the last place
    if (std::getenv("FP_TIMING")) std::printf("  decimal: %d of %d a unit off\n", inexact, n);
    CHECK(fp.call(F_DEC2F, 0, 0, 5) == 0);
    CHECK(fp.call(F_DEC2F, 15, 0, static_cast<uint16_t>(-1)) == bits(1.5f));
    CHECK(fp.call(F_DEC2F, 1, 0, 39) == bits(std::numeric_limits<float>::infinity()));
    CHECK(fp.call(F_DEC2F, 1, 0, static_cast<uint16_t>(-46)) == 0);
    // round(x * 10^k), as printf wants the digits.
    for (int i = 0; i < 2000; ++i) {
        float x = random_float(rng, -20, 20);
        x = std::fabs(x);
        int k = static_cast<int>(rng() % 16) - 6;
        double want = std::nearbyint(static_cast<double>(x) * std::pow(10.0, k)); // (ties to even)
        if (want >= 4294967295.0) continue;
        uint32_t got = fp.call(F_XINT, bits(x), 0, static_cast<uint16_t>(k));
        double d = static_cast<double>(got) - want;
        if ((d < -1 || d > 1) && bad++ < 10) std::fprintf(stderr, "  xint %.9g e%d: want %.0f got %u\n", x, k, want, got);
    }
    CHECK(fp.call(F_XINT, bits(2.5f), 0, 0) == 2);   // ties to even, as printf's
    CHECK(fp.call(F_XINT, bits(3.5f), 0, 0) == 4);
    CHECK(fp.call(F_XINT, bits(0.5f), 0, 0) == 0);
    CHECK(fp.call(F_XINT, bits(0.125f), 0, 2) == 12);
    CHECK(fp.call(F_XINT, bits(0.375f), 0, 2) == 38);
    CHECK(fp.call(F_XINT, bits(2.5000002f), 0, 0) == 3);
    CHECK(fp.call(F_XINT, bits(0.49f), 0, 0) == 0);
    CHECK(fp.call(F_XINT, bits(123.456f), 0, 3) == 123456);
    CHECK(fp.call(F_XINT, bits(1e10f), 0, 0) == 0xFFFFFFFF);
    CHECK(bad == 0);
    CHECK(fp.ok);
}
