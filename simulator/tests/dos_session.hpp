// Harness for testing the resident DOS layer directly: boots the real chain
// (BIOS -> SD_BOOT_TRY -> dos.asm -> BASIC.COM, so dos.asm has genuinely
// patched the BIOS's JT_DOS_* vectors), waits for BASIC's prompt, then makes
// BIOS calls itself by loading CPU registers and running a tiny stub in RAM
// (SWI2 ; BRA *) -- the same way BASIC reaches DOS, minus BASIC. BASIC is left
// idle and never resumed. Works on the shared disk.img, so tests must clean up
// (or overwrite) the files they use before relying on them.
#pragma once

#include <algorithm>
#include <cstdint>
#include <cstring>
#include <string>
#include <vector>

#include "pugputer/rom_device.hpp"
#include "pugputer/sdcard_device.hpp"
#include "pugputer/srec_loader.hpp"
#include "pugputer/system_bus.hpp"
#include "pugputer/uart_r65c51.hpp"

// BIOS call codes / errors / modes, mirroring bios/defines.d (the DOS layer's
// interface). If these drift from defines.d the tests fail loudly.
namespace bios {
constexpr uint8_t B_FOPEN_NAME = 0x13, B_READLINE = 0x14, B_WRITELINE = 0x15, B_FCLOSE_NAME = 0x16;
constexpr uint8_t B_DIR_FIRST = 0x17, B_DIR_NEXT = 0x18, B_KILL_NAME = 0x19, B_RENAME_NAME = 0x1A;
constexpr uint8_t B_FGETC = 0x1B, B_FPUTC = 0x1C, B_FREAD = 0x1D, B_FWRITE = 0x1E, B_FSEEK_NAME = 0x1F,
                  B_FSTAT_NAME = 0x20;
constexpr uint8_t ERR_BADDEV = 0x02, ERR_NOTFOUND = 0x05, ERR_NOSPACE = 0x06, ERR_NOSLOT = 0x07, ERR_EXISTS = 0x08,
                  ERR_EOF = 0x09, ERR_ISOPEN = 0x0A, ERR_BADMODE = 0x0B;
constexpr uint8_t READ = 0, WRITE = 1, APPEND = 2, UPDATE = 3;
} // namespace bios

struct DosSession {
    static constexpr uint16_t kBiosBase = 0xF000;
    static constexpr uint32_t kBiosSize = 0x1000;
    static constexpr uint16_t kStub = 0x9F00;     // SWI2 ; BRA *
    static constexpr uint16_t kNameBuf = 0x9E00;  // 11-byte names for open/kill/rename
    static constexpr uint16_t kNameBuf2 = 0x9E10; // second name (rename)
    static constexpr uint16_t kData = 0xA000;     // scratch for data going to/from DOS

    pugputer::RomDevice bios_rom{static_cast<uint16_t>(kBiosSize)};
    pugputer::SdCardDevice sd;
    pugputer::SystemBus bus;
    pugputer::UartR65C51 uart;
    std::string console;

    struct Result {
        uint8_t a = 0;
        uint16_t x = 0, y = 0;
        bool carry = false;
        bool ok() const { return !carry; }
    };

    bool boot(const char* bios_s19, const char* disk_img) {
        std::vector<uint8_t> image(65536, 0);
        if (!pugputer::load_srec_file(bios_s19, image.data(), image.size()).ok) return false;
        bios_rom.load(image.data() + kBiosBase, kBiosSize);
        if (!sd.open(disk_img)) return false;
        bus.map_device("bios_rom", kBiosBase, static_cast<uint16_t>(kBiosSize), &bios_rom, pugputer::IrqLine::None);
        bus.map_device("sdcard", 0xFFD8, 4, &sd, pugputer::IrqLine::None);
        bus.map_device("uart", 0xFFE8, 4, &uart, pugputer::IrqLine::IRQ);
        bus.map_bank_registers(); // $FFEC-$FFEF: the BIOS programs the RAM banks at reset
        uart.set_tx_callback([this](uint8_t b) { console += static_cast<char>(b); });
        bus.reset();
        bus.run(6000000); // BIOS, disk boot, DOS start, BASIC banner and prompt
        if (console.find("OK") == std::string::npos) return false;
        uint8_t* ram = bus.ram();
        ram[kStub] = 0x10; // SWI2
        ram[kStub + 1] = 0x3F;
        ram[kStub + 2] = 0x20; // BRA *
        ram[kStub + 3] = 0xFE;
        return true;
    }

    Result call(uint8_t fn, uint8_t b = 0, uint8_t e = 0, uint16_t x = 0, uint16_t y = 0) {
        hd6309_regs_t r{};
        hd6309_get_regs(bus.cpu(), &r);
        r.a = fn;
        r.b = b;
        r.e = e;
        r.f = 0;
        r.x = x;
        r.y = y;
        r.cc = static_cast<uint8_t>(r.cc & ~0x01); // carry clear going in
        r.pc = kStub;
        hd6309_set_regs(bus.cpu(), &r);
        for (uint64_t spent = 0; spent < 200000000;) {
            spent += bus.step();
            hd6309_get_regs(bus.cpu(), &r);
            if (r.pc == kStub + 2) break;
        }
        Result res;
        res.a = r.a;
        res.x = r.x;
        res.y = r.y;
        res.carry = (r.cc & 0x01) != 0;
        return res;
    }

    // "NAME.EXT" -> the 11-byte space-padded raw form DOS expects, at `addr`.
    void put_name(const std::string& dotted, uint16_t addr) {
        std::string base = dotted, ext;
        size_t dot = dotted.find('.');
        if (dot != std::string::npos) {
            base = dotted.substr(0, dot);
            ext = dotted.substr(dot + 1);
        }
        char raw[11];
        std::memset(raw, ' ', sizeof raw);
        std::memcpy(raw, base.data(), base.size() < 8 ? base.size() : 8);
        std::memcpy(raw + 8, ext.data(), ext.size() < 3 ? ext.size() : 3);
        std::memcpy(bus.ram() + addr, raw, sizeof raw);
    }

    void poke(uint16_t addr, const std::vector<uint8_t>& bytes) {
        std::memcpy(bus.ram() + addr, bytes.data(), bytes.size());
    }
    std::vector<uint8_t> peek(uint16_t addr, size_t n) const {
        return std::vector<uint8_t>(bus.ram() + addr, bus.ram() + addr + n);
    }

    // ---- convenience wrappers over the BIOS calls ----
    Result open(const std::string& name, uint8_t mode) {
        put_name(name, kNameBuf);
        return call(bios::B_FOPEN_NAME, 0, mode, kNameBuf);
    }
    Result close(uint8_t ref) { return call(bios::B_FCLOSE_NAME, ref); }
    Result kill(const std::string& name) {
        put_name(name, kNameBuf);
        return call(bios::B_KILL_NAME, 0, 0, kNameBuf);
    }
    Result rename(const std::string& from, const std::string& to) {
        put_name(from, kNameBuf);
        put_name(to, kNameBuf2);
        return call(bios::B_RENAME_NAME, 0, 0, kNameBuf, kNameBuf2);
    }
    Result putc(uint8_t ref, uint8_t byte) { return call(bios::B_FPUTC, ref, byte); }
    Result getc(uint8_t ref) { return call(bios::B_FGETC, ref); }
    Result write(uint8_t ref, const std::vector<uint8_t>& data) {
        poke(kData, data);
        return call(bios::B_FWRITE, ref, 0, kData, static_cast<uint16_t>(data.size()));
    }
    // Reads up to n bytes; returns them (short at EOF); *ok reports carry clear.
    std::vector<uint8_t> read(uint8_t ref, size_t n, bool* ok = nullptr) {
        Result r = call(bios::B_FREAD, ref, 0, kData, static_cast<uint16_t>(n));
        if (ok) *ok = r.ok();
        return r.ok() ? peek(kData, r.x) : std::vector<uint8_t>{};
    }
    Result seek(uint8_t ref, uint16_t pos) { return call(bios::B_FSEEK_NAME, ref, 0, pos); }
    Result stat(uint8_t ref) { return call(bios::B_FSTAT_NAME, ref); } // x = size, y = position

    // Whole-file helpers.
    bool write_file(const std::string& name, const std::vector<uint8_t>& data) {
        Result o = open(name, bios::WRITE);
        if (!o.ok()) return false;
        bool ok = true;
        // In chunks: the data scratch area is small, and this exercises many calls.
        for (size_t i = 0; i < data.size() && ok; i += 512) {
            std::vector<uint8_t> chunk(data.begin() + i, data.begin() + std::min(data.size(), i + 512));
            ok = write(o.a, chunk).ok();
        }
        return close(o.a).ok() && ok;
    }
    bool read_file(const std::string& name, std::vector<uint8_t>& out) {
        Result o = open(name, bios::READ);
        if (!o.ok()) return false;
        out.clear();
        for (;;) {
            bool ok = false;
            std::vector<uint8_t> chunk = read(o.a, 300, &ok);
            if (!ok) return false;
            out.insert(out.end(), chunk.begin(), chunk.end());
            if (chunk.size() < 300) break;
        }
        return close(o.a).ok();
    }
};

inline std::vector<uint8_t> pattern(size_t n, uint8_t seed) {
    std::vector<uint8_t> v(n);
    for (size_t i = 0; i < n; ++i) v[i] = static_cast<uint8_t>(seed + i * 7 + (i >> 8));
    return v;
}
