// Standalone interactive demo: boots a small interrupt-driven UART echo
// program (the same one used by tests/test_asm/uart_echo.asm and its
// golden test -- assembled once and embedded here as bytes, so this tool
// doesn't need lwasm.exe at run time) on a SystemBus, and bridges the
// emulated UART to either this console (default) or a Windows COM port
// (e.g. one end of a com0com virtual port pair):
//
//   uart_demo                  -- console bridge
//   uart_demo --com COM10      -- COM port bridge (see simulator/README.md)
//
// Type at it; it echoes each byte straight back, exactly like
// tests/test_asm/uart_echo.asm's ISR.
#include <conio.h>

#include <cstdio>
#include <cstring>
#include <string>

#include "pugputer/system_bus.hpp"
#include "pugputer/uart_r65c51.hpp"
#ifdef PUGPUTER_HAVE_COM_BRIDGE
#include "pugputer/com_port_bridge.hpp"
#endif

using pugputer::IrqLine;
using pugputer::SystemBus;
using pugputer::UartR65C51;

namespace {

// Assembled from tests/test_asm/uart_echo.asm (org $8000); `irqhndl` is
// at $8012. Re-generate with:
//   lwasm --raw -o uart_echo.bin tests/test_asm/uart_echo.asm
const uint8_t kProgram[] = {
    0x10, 0xce, 0x7f, 0x00, 0x86, 0x1f, 0xb7, 0xff, 0xeb, 0x86, 0x09, 0xb7,
    0xff, 0xea, 0x1c, 0xef, 0x20, 0xfe, 0xb6, 0xff, 0xe9, 0x85, 0x08, 0x27,
    0x06, 0xb6, 0xff, 0xe8, 0xb7, 0xff, 0xe8, 0x3b,
};

} // namespace

int main(int argc, char** argv) {
    std::string com_port;
    for (int i = 1; i < argc; ++i) {
        if (std::strcmp(argv[i], "--com") == 0 && i + 1 < argc) com_port = argv[++i];
    }

    SystemBus bus;
    UartR65C51 uart;
    bus.map_device("uart", 0xFFE8, 4, &uart, IrqLine::IRQ);

    uint8_t* m = bus.ram();
    for (size_t i = 0; i < sizeof(kProgram); ++i) m[0x8000 + i] = kProgram[i];
    m[0xFFFE] = 0x80; m[0xFFFF] = 0x00; // reset vector -> $8000
    m[0xFFF8] = 0x80; m[0xFFF9] = 0x12; // IRQ vector -> $8012 (irqhndl)
    bus.reset();

    bool use_com = false;
#ifdef PUGPUTER_HAVE_COM_BRIDGE
    pugputer::ComPortBridge bridge;
    if (!com_port.empty()) {
        if (bridge.open(com_port, uart.current_baud_rate())) {
            use_com = true;
            std::printf("Bridging UART to %s. Connect a terminal to the other end of the com0com pair.\n",
                        com_port.c_str());
        } else {
            std::fprintf(stderr, "Failed to open %s: %s\nFalling back to console.\n", com_port.c_str(),
                         bridge.last_error().c_str());
        }
    }
#else
    if (!com_port.empty()) {
        std::fprintf(stderr, "This build has no COM-port bridge support; using the console instead.\n");
    }
#endif

    if (!use_com) {
        std::printf("Bridging UART to this console. Type to send bytes; Ctrl+C to quit.\n");
        uart.set_tx_callback([](uint8_t b) {
            std::putchar(b);
            std::fflush(stdout);
        });
    }
    std::fflush(stdout);
    std::fflush(stderr);

    for (;;) {
        bus.run(10000);
        if (use_com) {
#ifdef PUGPUTER_HAVE_COM_BRIDGE
            bridge.poll(uart);
#endif
        } else {
            while (_kbhit()) {
                int ch = _getch();
                uart.rx_enqueue(static_cast<uint8_t>(ch));
            }
        }
    }
}
