// Shared harness for basic309 interpreter tests that don't need a disk:
// boots the real BIOS, copies BASIC.COM's $C000-$EFFF image into RAM (the
// same bytes mkdiskimg puts on a disk, and just as writable as when dos.asm
// loads it), hijacks PC to BASIC's cold-start entry, and drives it with
// paced UART keystrokes (each byte waits for the UART's RDRF flag to clear, so
// none is dropped as an overrun).
// No SD device is mapped, so nothing here can touch disk.img.
#pragma once

#include <cstdint>
#include <string>
#include <vector>

#include "pugputer/rom_device.hpp"
#include "pugputer/sdcard_device.hpp"
#include "pugputer/srec_loader.hpp"
#include "pugputer/system_bus.hpp"
#include "pugputer/uart_r65c51.hpp"

struct Basic309Session {
    static constexpr uint16_t kBiosBase = 0xF000;
    static constexpr uint32_t kBiosSize = 0x1000;
    static constexpr uint16_t kBasicBase = 0xC000;
    static constexpr uint32_t kBasicSize = 0x3000;
    static constexpr uint16_t kBasicEntry = 0xC000; // fixed entry: JMP RESVEC (see exbasrom309.asm)

    pugputer::RomDevice bios_rom{static_cast<uint16_t>(kBiosSize)};
    pugputer::SdCardDevice sd; // only mapped by boot_disk()
    pugputer::SystemBus bus;
    pugputer::UartR65C51 uart;
    std::string received;

    // Returns false (after printing why) if an image can't be loaded.
    bool boot(const char* bios_s19, const char* basic_s19) {
        std::vector<uint8_t> bios_image(65536, 0);
        std::vector<uint8_t> basic_image(65536, 0);
        if (!pugputer::load_srec_file(bios_s19, bios_image.data(), bios_image.size()).ok) return false;
        if (!pugputer::load_srec_file(basic_s19, basic_image.data(), basic_image.size()).ok) return false;
        bios_rom.load(bios_image.data() + kBiosBase, kBiosSize);
        for (uint32_t i = 0; i < kBasicSize; ++i) bus.ram()[kBasicBase + i] = basic_image[kBasicBase + i];

        bus.map_device("bios_rom", kBiosBase, static_cast<uint16_t>(kBiosSize), &bios_rom, pugputer::IrqLine::None);
        bus.map_device("uart", 0xFFE8, 4, &uart, pugputer::IrqLine::IRQ);
        bus.map_bank_registers(); // $FFEC-$FFEF: the BIOS programs the RAM banks at reset
        uart.set_tx_callback([this](uint8_t b) { received += static_cast<char>(b); });

        bus.reset();
        bus.run(500000); // BIOS cold start
        hd6309_regs_t regs{};
        hd6309_get_regs(bus.cpu(), &regs);
        regs.pc = kBasicEntry;
        hd6309_set_regs(bus.cpu(), &regs);
        return run_until_ok(20000000);
    }

    // The whole real chain instead: BIOS -> SD boot -> dos.asm -> SHELL.COM, from
    // `disk_img` (SHELL.COM and BASIC.COM must be on it). boot_shell() stops at the
    // shell's prompt; boot_disk() goes on to start BASIC from it. Needed for anything
    // that touches files. The shared disk.img is used in place, so tests must clean
    // up after themselves (or KILL what they use before starting).
    bool boot_shell(const char* bios_s19, const char* disk_img) {
        std::vector<uint8_t> bios_image(65536, 0);
        if (!pugputer::load_srec_file(bios_s19, bios_image.data(), bios_image.size()).ok) return false;
        bios_rom.load(bios_image.data() + kBiosBase, kBiosSize);
        if (!sd.open(disk_img)) return false;
        bus.map_device("bios_rom", kBiosBase, static_cast<uint16_t>(kBiosSize), &bios_rom, pugputer::IrqLine::None);
        bus.map_device("sdcard", 0xFFD8, 4, &sd, pugputer::IrqLine::None);
        bus.map_device("uart", 0xFFE8, 4, &uart, pugputer::IrqLine::IRQ);
        bus.map_bank_registers(); // $FFEC-$FFEF: the BIOS programs the RAM banks at reset
        uart.set_tx_callback([this](uint8_t b) { received += static_cast<char>(b); });
        bus.reset();
        return wait_for("> ", 20000000);
    }

    // The same, then starts BASIC from the shell like a user would (type BASIC).
    bool boot_disk(const char* bios_s19, const char* disk_img) {
        if (!boot_shell(bios_s19, disk_img)) return false;
        type("BASIC");
        return run_until_ok(20000000);
    }

    // Runs until the console output (since the last clear) contains `needle`,
    // e.g. an INPUT prompt, or the budget runs out.
    bool wait_for(const std::string& needle, uint64_t budget = 40000000) {
        uint64_t spent = 0;
        while (spent < budget) {
            if (received.find(needle) != std::string::npos) return true;
            spent += bus.run(20000);
        }
        return received.find(needle) != std::string::npos;
    }

    bool ends_with_ok() const {
        static const std::string kOk = "OK\r\n";
        return received.size() >= kOk.size() && received.compare(received.size() - kOk.size(), kOk.size(), kOk) == 0;
    }

    // Runs in small chunks until the console output ends with the "OK"
    // prompt (BASIC is idle again), or the cycle budget runs out.
    bool run_until_ok(uint64_t budget) {
        uint64_t spent = 0;
        while (spent < budget) {
            spent += bus.run(20000);
            if (ends_with_ok()) return true;
        }
        return false;
    }

    void send_byte(uint8_t ch) {
        constexpr uint32_t kStepBudget = 400000;
        uart.rx_enqueue(ch);
        uint32_t spent = 0;
        while (!(uart.status_register() & 0x08) && spent < kStepBudget) spent += static_cast<uint32_t>(bus.step());
        spent = 0;
        while ((uart.status_register() & 0x08) && spent < kStepBudget) spent += static_cast<uint32_t>(bus.step());
    }

    // Types a line + Enter, then gives BASIC a moment to settle (long enough
    // for its between-statement break-key poll, which would otherwise eat
    // the next keystroke -- see test_basic309_load_save_golden.cpp).
    void type(const std::string& line) {
        for (char c : line) send_byte(static_cast<uint8_t>(c));
        send_byte('\r');
        bus.run(50000);
    }

    // Types one line and waits for the prompt; returns everything BASIC
    // printed in response, minus the echo of the line itself and the final
    // "OK" prompt line. Empty string if the prompt never came back.
    std::string run_line(const std::string& line, uint64_t budget = 40000000) {
        received.clear();
        type(line);
        if (!ends_with_ok() && !run_until_ok(budget)) return "<<TIMEOUT>>";
        std::string out = received;
        out.erase(0, echo_length(out, line));
        out.erase(out.size() - 4); // trailing "OK\r\n"
        return out;
    }

    // How much of the start of `out` is the echo of `line` plus its Enter. The
    // tail of the previous line's echo can still be in flight ahead of it, and
    // a line longer than the 80-column console width is echoed with a CR LF
    // where it wraps -- so find where this line's echo starts, then match it
    // character by character, skipping the wrap breaks.
    static size_t echo_length(const std::string& out, const std::string& line) {
        size_t start = out.find(line.substr(0, 20));
        if (start == std::string::npos) start = 0;
        size_t j = start, k = 0;
        while (k < line.size() && j < out.size()) {
            if (out[j] == line[k]) {
                ++j;
                ++k;
            } else if (out[j] == '\r' || out[j] == '\n') {
                ++j;
            } else {
                break;
            }
        }
        if (k < line.size()) { // couldn't match it all: fall back to dropping the first line
            size_t nl = out.find("\r\n");
            return nl == std::string::npos ? 0 : nl + 2;
        }
        size_t nl = out.find("\r\n", j);
        return nl == std::string::npos ? j : nl + 2;
    }

    // Types every line but the last with no output capture, then returns
    // the last line's output (typically "RUN" or a direct-mode statement).
    std::string run_program(const std::vector<std::string>& lines, uint64_t budget = 40000000) {
        for (size_t i = 0; i + 1 < lines.size(); ++i) exec(lines[i], budget);
        return run_line(lines.back(), budget);
    }

    // Types one line without capturing its output. A numbered program line
    // produces no "OK" prompt, so only direct-mode lines wait for one.
    void exec(const std::string& line, uint64_t budget = 40000000) {
        received.clear();
        type(line);
        bool numbered = !line.empty() && line[0] >= '0' && line[0] <= '9';
        if (!numbered) run_until_ok(budget);
    }
};
