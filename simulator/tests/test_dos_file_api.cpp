// Exercises the resident DOS file API (B_FOPEN_NAME/B_READLINE/
// B_WRITELINE/B_FCLOSE_NAME) directly via SWI2, independent of BASIC's
// own LOAD/SAVE commands (which don't exist yet as of this test): boots
// the real BIOS+dos.asm+shell chain from disk.img (so DOS_JTAB is
// genuinely patched by dos.asm, not faked), waits for the boot to reach
// the shell's idle prompt, then hijacks PC to a small hand-assembled test
// program (test_asm/dos_file_api.asm, injected into otherwise-unused
// free RAM at $9000) that writes a two-line file, closes it,
// reopens it for read, and confirms both lines plus EOF round-trip
// correctly.
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <string>
#include <vector>

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
constexpr uint16_t kTestOrg = 0x9000;

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

TEST(dos_file_api_write_close_reopen_read_round_trips) {
    auto bin = assemble("dos_file_api.asm");
    CHECK(!bin.empty());
    if (bin.empty()) return;

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
    // BIOS cold-start + disk boot; DOS patches the BIOS's call table before it starts
    // the shell, and the shell then idles at its prompt.
    for (int i = 0; i < 100 && received.find("/> ") == std::string::npos; ++i) bus.run(200000);
    CHECK(received.find("/> ") != std::string::npos);

    // Inject the test program into BASIC's otherwise-unused free RAM and
    // hijack PC to it.
    uint8_t* ram = bus.ram();
    for (size_t i = 0; i < bin.size(); ++i) ram[kTestOrg + i] = bin[i];
    hd6309_regs_t regs{};
    hd6309_get_regs(bus.cpu(), &regs);
    regs.pc = kTestOrg;
    hd6309_set_regs(bus.cpu(), &regs);

    bool trapped = false;
    for (int i = 0; i < 3000000; ++i) {
        bus.step();
        hd6309_get_regs(bus.cpu(), &regs);
        if (regs.md & 0x40) { // illegal-opcode trap -- stop early
            trapped = true;
            break;
        }
    }
    CHECK(!trapped);

    // RESULT sits at the very end of the assembled program (see
    // dos_file_api.asm) -- locate it via the bin size rather than a
    // hand-computed offset, since FNAME/LINE1/LINE2/FILEREF/RESULT/RBUF
    // are declared in that order right after the code.
    size_t result_off = bin.size() - 32 /*RBUF*/ - 2 /*RESULT*/;
    uint8_t result = ram[kTestOrg + result_off];
    uint8_t result_detail = ram[kTestOrg + result_off + 1];
    if (result != 0xAA) {
        std::fprintf(stderr, "  dos_file_api result=$%02X detail=$%02X ('%c' step %c)\n", result, result_detail,
                     static_cast<char>(result), static_cast<char>(result_detail));
    }
    CHECK(result == 0xAA);
}
