// Exercises the new FILES/KILL/NAME BASIC commands end-to-end (via real
// keystrokes, same pattern as test_basic309_load_save_golden.cpp): save
// two files, list them, rename one, list again, delete the other, list
// again, then confirm the renamed file still loads correctly and that
// KILL/NAME each report a sensible error for a bad target.
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

TEST(basic309_files_kill_name_round_trip) {
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

    std::string received;
    uart.set_tx_callback([&](uint8_t b) { received += static_cast<char>(b); });

    bus.reset();
    bus.run(6000000);
    CHECK(received.find("OK") != std::string::npos);

    constexpr uint32_t kStepBudget = 400000;
    auto send_byte = [&](uint8_t ch) {
        uart.rx_enqueue(ch);
        uint32_t spent = 0;
        while (!(uart.status_register() & 0x08) && spent < kStepBudget) spent += static_cast<uint32_t>(bus.step());
        spent = 0;
        while ((uart.status_register() & 0x08) && spent < kStepBudget) spent += static_cast<uint32_t>(bus.step());
    };
    auto type = [&](const std::string& line) {
        for (char c : line) send_byte(static_cast<uint8_t>(c));
        send_byte('\r');
        bus.run(50000);
    };

    // Start from a known state even if an earlier run left these behind
    // (KILL of a missing file just reports ?NE, which we ignore here).
    for (const char* name : {"A.BAS", "B.BAS", "C.BAS"}) {
        type(std::string("KILL\"") + name + "\"");
        bus.run(1500000);
    }

    // Save two small files.
    type("10 PRINT 1");
    received.clear();
    type("SAVE\"A.BAS\"");
    bus.run(1500000);
    CHECK(received.find("OK") != std::string::npos);

    received.clear();
    type("NEW");
    type("20 PRINT 2");
    type("SAVE\"B.BAS\"");
    bus.run(1500000);
    CHECK(received.find("OK") != std::string::npos);

    // FILES should list BASIC.COM, A.BAS, B.BAS.
    received.clear();
    type("FILES");
    bus.run(2000000);
    CHECK(received.find("BASIC.COM") != std::string::npos);
    CHECK(received.find("A.BAS") != std::string::npos);
    CHECK(received.find("B.BAS") != std::string::npos);

    // Rename A.BAS -> C.BAS.
    received.clear();
    type("NAME\"A.BAS\" AS \"C.BAS\"");
    bus.run(1500000);
    CHECK(received.find("OK") != std::string::npos);
    CHECK(received.find("ERROR") == std::string::npos);

    received.clear();
    type("FILES");
    bus.run(2000000);
    CHECK(received.find("C.BAS") != std::string::npos);
    CHECK(received.find("A.BAS") == std::string::npos);
    CHECK(received.find("B.BAS") != std::string::npos);

    // C.BAS should still load with its original content (rename only
    // touches the name field).
    received.clear();
    type("NEW");
    type("LOAD\"C.BAS\"");
    bus.run(2000000);
    CHECK(received.find("OK") != std::string::npos);
    CHECK(received.find("ERROR") == std::string::npos);

    received.clear();
    type("LIST");
    bus.run(1500000);
    CHECK(received.find("10 PRINT 1") != std::string::npos);

    // Delete B.BAS.
    received.clear();
    type("KILL\"B.BAS\"");
    bus.run(1500000);
    CHECK(received.find("OK") != std::string::npos);
    CHECK(received.find("ERROR") == std::string::npos);

    received.clear();
    type("FILES");
    bus.run(2000000);
    CHECK(received.find("B.BAS") == std::string::npos);
    CHECK(received.find("C.BAS") != std::string::npos);
    CHECK(received.find("BASIC.COM") != std::string::npos);

    // KILL of a nonexistent file -> ?NE ERROR.
    received.clear();
    type("KILL\"NOPE.BAS\"");
    bus.run(1500000);
    CHECK(received.find("?NE ERROR") != std::string::npos);

    // NAME onto an existing target -> ?FE ERROR.
    received.clear();
    type("NAME\"C.BAS\" AS \"BASIC.COM\"");
    bus.run(1500000);
    CHECK(received.find("?FE ERROR") != std::string::npos);
}
