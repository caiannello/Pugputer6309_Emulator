// "Golden" tests: assemble real 6309-native source with the HD6309
// cross-assembler already in this repo (lwtools-4.20/lwasm), load the
// resulting binary into the emulator, run it, and check memory results
// -- closer to "run real assembled code and check it behaves correctly"
// than hand-encoded opcode byte arrays alone. Only compiled/linked when
// lwasm.exe was found at CMake configure time (see tests/CMakeLists.txt).
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <string>
#include <vector>

#include "test_framework.hpp"
#include "test_harness.hpp"

namespace {

std::vector<uint8_t> assemble(const char* asm_filename) {
    std::string src = std::string(HD6309_TEST_ASM_DIR) + "/" + asm_filename;
    std::string out_dir = HD6309_TEST_BUILD_DIR;

    // std::system() already runs the command through the platform shell
    // (cmd.exe on Windows), so no extra "cmd /C" wrapper is needed here --
    // adding one double-wraps quoting and breaks path parsing.
#ifdef _WIN32
    std::string mkdir_cmd = std::string("mkdir \"") + out_dir + "\" >NUL 2>NUL";
#else
    std::string mkdir_cmd = std::string("mkdir -p \"") + out_dir + "\"";
#endif
    std::system(mkdir_cmd.c_str());

    std::string out = out_dir + "/" + asm_filename + ".bin";
    std::string cmd = std::string("\"") + LWASM_EXE_PATH + "\" --raw -o \"" + out + "\" \"" + src + "\"";
#ifdef _WIN32
    // cmd.exe's /C strips a single pair of leading/trailing quotes from the
    // whole command line; since our command already starts with a quoted
    // exe path, that strips the wrong quotes and breaks argument parsing
    // unless the entire line is wrapped in one more, outer pair of quotes.
    cmd = "\"" + cmd + "\"";
#endif
    int rc = std::system(cmd.c_str());
    if (rc != 0) {
        std::fprintf(stderr, "  lwasm failed assembling %s (rc=%d)\n", asm_filename, rc);
        return {};
    }

    std::ifstream f(out, std::ios::binary);
    return std::vector<uint8_t>((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
}

} // namespace

TEST(golden_basic_alu) {
    auto bin = assemble("basic_alu.asm");
    CHECK(!bin.empty());
    if (bin.empty()) return;

    Harness h;
    uint8_t* m = h.mem();
    for (size_t i = 0; i < bin.size(); ++i) m[0x8000 + i] = bin[i];
    h.set_reset_vector(0x8000);
    hd6309_reset(h.cpu);

    hd6309_run(h.cpu, 1000);

    CHECK_EQ_HEX(m[0x2000], 0x08); // 5 + 3
    CHECK_EQ_HEX(m[0x2002], 0x12); // D = $1235, high byte
    CHECK_EQ_HEX(m[0x2003], 0x35); // D = $1235, low byte
    CHECK_EQ_HEX(m[0x2004], 0x10); // X = $1005, high byte
    CHECK_EQ_HEX(m[0x2005], 0x05); // X = $1005, low byte
    CHECK_EQ_HEX(m[0x2006], 0x80); // $7F + 1 overflow
}

TEST(golden_native_ops) {
    auto bin = assemble("native_ops.asm");
    CHECK(!bin.empty());
    if (bin.empty()) return;

    Harness h;
    uint8_t* m = h.mem();
    for (size_t i = 0; i < bin.size(); ++i) m[0x8000 + i] = bin[i];
    // Source bytes for the TFM block copy ($3000 -> $4000, 4 bytes).
    m[0x3000] = 0x11;
    m[0x3001] = 0x22;
    m[0x3002] = 0x33;
    m[0x3003] = 0x44;
    h.set_reset_vector(0x8000);
    hd6309_reset(h.cpu);

    hd6309_run(h.cpu, 1000);

    CHECK_EQ_HEX(m[0x2000], 0x11); // first byte TFM-copied from $3000
    CHECK_EQ_HEX(m[0x2001], 0x01); // BAND: 1 AND 1 = 1
    CHECK_EQ_HEX(m[0x2002], 0x00); // MULD high word of 5*3=15
    CHECK_EQ_HEX(m[0x2003], 0x00);
    CHECK_EQ_HEX(m[0x2004], 0x00); // MULD low word (via STW) of 15
    CHECK_EQ_HEX(m[0x2005], 0x0F);
}
