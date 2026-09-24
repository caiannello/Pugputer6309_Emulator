// Golden test: assembles tests/test_asm/uart_echo.asm with the real
// lwasm cross-assembler, loads it onto a SystemBus with a real
// UartR65C51 mapped at $FFE8 (IRQ), and drives it through host-facing
// rx_enqueue()/tx_dequeue() -- exercising the full path (UART timing ->
// IRQ assertion -> CPU service -> ISR reading the real registers -> TX
// completion) the same way the CPU core's own golden tests validate
// against real assembled code.
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <string>
#include <vector>

#include "test_framework.hpp"
#include "pugputer/system_bus.hpp"
#include "pugputer/uart_r65c51.hpp"

using pugputer::IrqLine;
using pugputer::SystemBus;
using pugputer::UartR65C51;

namespace {

std::vector<uint8_t> assemble(const char* asm_filename) {
    std::string src = std::string(PUGPUTER_TEST_ASM_DIR) + "/" + asm_filename;
    std::string out_dir = PUGPUTER_TEST_BUILD_DIR;

#ifdef _WIN32
    std::string mkdir_cmd = std::string("mkdir \"") + out_dir + "\" >NUL 2>NUL";
#else
    std::string mkdir_cmd = std::string("mkdir -p \"") + out_dir + "\"";
#endif
    std::system(mkdir_cmd.c_str());

    std::string out = out_dir + "/" + asm_filename + ".bin";
    std::string cmd = std::string("\"") + LWASM_EXE_PATH + "\" --raw -o \"" + out + "\" \"" + src + "\"";
#ifdef _WIN32
    cmd = "\"" + cmd + "\""; // see test_asm_golden.cpp for why this outer wrap is needed on Windows
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

TEST(golden_uart_echo) {
    auto bin = assemble("uart_echo.asm");
    CHECK(!bin.empty());
    if (bin.empty()) return;

    SystemBus bus;
    UartR65C51 uart;
    bus.map_device("uart", 0xFFE8, 4, &uart, IrqLine::IRQ);

    uint8_t* m = bus.ram();
    for (size_t i = 0; i < bin.size(); ++i) m[0x8000 + i] = bin[i];
    m[0xFFFE] = 0x80; m[0xFFFF] = 0x00; // reset vector -> $8000 (`start`)
    m[0xFFF8] = 0x80; m[0xFFF9] = 0x12; // IRQ vector -> $8012 (`irqhndl`, per uart_echo.asm's map output)

    bus.reset();
    CHECK(uart.rx_enqueue('Q'));

    bus.run(20000); // comfortably more than init + one RX char-time + ISR + one TX char-time

    uint8_t out = 0;
    CHECK(uart.tx_dequeue(out));
    CHECK(out == 'Q');
}

TEST(golden_uart_echo_multiple_bytes_in_sequence) {
    auto bin = assemble("uart_echo.asm");
    CHECK(!bin.empty());
    if (bin.empty()) return;

    SystemBus bus;
    UartR65C51 uart;
    bus.map_device("uart", 0xFFE8, 4, &uart, IrqLine::IRQ);

    uint8_t* m = bus.ram();
    for (size_t i = 0; i < bin.size(); ++i) m[0x8000 + i] = bin[i];
    m[0xFFFE] = 0x80; m[0xFFFF] = 0x00;
    m[0xFFF8] = 0x80; m[0xFFF9] = 0x12;

    bus.reset();

    const std::string msg = "Hi!";
    for (char c : msg) {
        CHECK(uart.rx_enqueue(static_cast<uint8_t>(c)));
        bus.run(20000);
        uint8_t out = 0;
        CHECK(uart.tx_dequeue(out));
        CHECK(out == static_cast<uint8_t>(c));
    }
}
