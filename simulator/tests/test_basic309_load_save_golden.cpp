// End-to-end LOAD/SAVE test: boots the real disk chain (BIOS -> SD_BOOT_TRY
// -> dos.asm -> BASIC.COM), then drives actual BASIC keystrokes through
// the emulated UART -- typing a short program, SAVE-ing it, clearing the
// interpreter's own program (NEW), LOAD-ing it back, and LIST-ing it --
// confirming the listing round-trips byte-for-byte. This exercises the
// full stack no other test does in combination: BASIC's tokenizer/
// detokenizer (LACA5/LB7C2, reused as-is), the LINEDONE_VEC redirect that
// lets LOAD feed multiple lines through LACA5 without it returning to the
// interactive prompt between each one, and the resident DOS file API
// underneath (already covered in isolation by test_dos_file_api.cpp).
#include <string>

#include "test_framework.hpp"
#include "pugputer/rom_device.hpp"
#include "pugputer/sdcard_device.hpp"
#include "pugputer/srec_loader.hpp"
#include "pugputer/system_bus.hpp"
#include "pugputer/uart_r65c51.hpp"

using pugputer::IrqLine;
using pugputer::load_srec_file;
using pugputer::RomDevice;
using pugputer::SdCardDevice;
using pugputer::SrecLoadResult;
using pugputer::SystemBus;
using pugputer::UartR65C51;

namespace {
constexpr uint16_t kBiosBase = 0xF000;
constexpr uint32_t kBiosSize = 0x1000;
} // namespace

TEST(basic309_load_save_round_trips_a_program_through_disk) {
    std::vector<uint8_t> bios_image(65536, 0);
    SrecLoadResult bios_load = load_srec_file(PUGBIOS_S19_PATH, bios_image.data(), bios_image.size());
    CHECK(bios_load.ok);
    if (!bios_load.ok) return;

    RomDevice bios_rom(static_cast<uint16_t>(kBiosSize));
    bios_rom.load(bios_image.data() + kBiosBase, kBiosSize);

    SdCardDevice sdcard;
    CHECK(sdcard.open(DISK_IMG_PATH));
    if (!sdcard.is_open()) return;

    SystemBus bus;
    UartR65C51 uart;
    bus.map_device("bios_rom", kBiosBase, static_cast<uint16_t>(kBiosSize), &bios_rom, IrqLine::None);
    bus.map_device("sdcard", 0xFFD8, 4, &sdcard, IrqLine::None);
    bus.map_device("uart", 0xFFE8, 4, &uart, IrqLine::IRQ);
    bus.map_bank_registers(); // $FFEC-$FFEF: the BIOS programs the RAM banks at reset

    std::string received;
    uart.set_tx_callback([&](uint8_t b) { received += static_cast<char>(b); });

    bus.reset();
    for (int i = 0; i < 100 && received.find("/> ") == std::string::npos; ++i) bus.run(200000); // boot to the shell
    CHECK(received.find("/> ") != std::string::npos);

    // Handshake off the real RDRF flag (wait for it to go 1 -- the byte
    // arrived -- then wait for it to go 0 -- BASIC actually read it)
    // instead of injecting a whole line at once. A tight injection loop
    // risks the next byte "arriving" before BASIC reads the previous one,
    // which -- per real R65C51 overrun semantics this UART model
    // faithfully reproduces -- silently drops it exactly like real
    // hardware would.
    constexpr uint32_t kStepBudget = 400000;
    auto send_byte = [&](uint8_t ch) {
        uart.rx_enqueue(ch);
        uint32_t spent = 0;
        while (!(uart.status_register() & 0x08) && spent < kStepBudget) spent += static_cast<uint32_t>(bus.step());
        spent = 0;
        while ((uart.status_register() & 0x08) && spent < kStepBudget) spent += static_cast<uint32_t>(bus.step());
    };
    // After the CR, let the interpreter fully finish that line (including
    // the break-key poll every command completion does between statements
    // -- LAD9E's BSR LADEB/KEYIN -- before the next character arrives) and
    // settle into its own steady-state "waiting for input" loop, the same
    // way a human pausing between typed lines naturally would. Without
    // this, a character sent right as the previous line finishes can be
    // consumed by that one-shot break-check poll instead of the next
    // actual line read -- not a bug, the same race a real fast typist
    // hitting keys immediately after Enter could also occasionally hit.
    auto type = [&](const std::string& line) {
        for (char c : line) send_byte(static_cast<uint8_t>(c));
        send_byte('\r');
        bus.run(50000);
    };

    // Start BASIC from the shell, as a user would.
    type("BASIC");
    bus.run(6000000);
    CHECK(received.find("OK") != std::string::npos);

    received.clear();
    type("10 PRINT \"HELLO FROM DISK\"");
    type("SAVE \"ROUNDTRP\"");
    bus.run(8000000);
    CHECK(received.find("OK") != std::string::npos);

    received.clear();
    type("NEW");
    type("LOAD \"ROUNDTRP\"");
    type("LIST");
    bus.run(12000000);

    hd6309_regs_t regs{};
    hd6309_get_regs(bus.cpu(), &regs);
    CHECK((regs.md & 0x40) == 0); // no illegal-opcode trap
    CHECK(received.find("10 PRINT \"HELLO FROM DISK\"") != std::string::npos);
}
