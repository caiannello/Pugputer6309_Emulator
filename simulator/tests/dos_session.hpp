// Harness for testing the resident DOS layer directly: boots the real chain
// (BIOS -> SD_BOOT_TRY -> dos.asm -> BASIC.COM, so dos.asm has genuinely
// installed its calls in the BIOS's DOS call table), waits for BASIC's prompt,
// then makes BIOS calls itself by loading CPU registers and running a tiny stub
// in RAM (SWI2 ; BRA *) -- the same way BASIC reaches DOS, minus BASIC. BASIC is
// left idle and never resumed. Works on the shared disk.img, so tests must clean
// up (or overwrite) the files they use before relying on them.
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
constexpr uint8_t B_OPENDIR = 0x17, B_READDIR = 0x18, B_KILL_NAME = 0x19, B_RENAME_NAME = 0x1A;
constexpr uint8_t B_FGETC = 0x1B, B_FPUTC = 0x1C, B_FREAD = 0x1D, B_FWRITE = 0x1E, B_FSEEK_NAME = 0x1F,
                  B_FSTAT_NAME = 0x20, B_FFLUSH = 0x21, B_MKDIR = 0x22, B_RMDIR = 0x23, B_CHDIR = 0x24,
                  B_GETCWD = 0x25, B_CLOSEDIR = 0x26, B_STAT = 0x27, B_DOS_VERSION = 0x28;
constexpr uint8_t ERR_BADDEV = 0x02, ERR_NOTFOUND = 0x05, ERR_NOSPACE = 0x06, ERR_NOSLOT = 0x07, ERR_EXISTS = 0x08,
                  ERR_EOF = 0x09, ERR_ISOPEN = 0x0A, ERR_BADMODE = 0x0B, ERR_NOTDIR = 0x0C, ERR_ISDIR = 0x0D,
                  ERR_NOTEMPTY = 0x0E, ERR_BADPATH = 0x0F, ERR_TOOBIG = 0x10;
constexpr uint8_t READ = 0, WRITE = 1, APPEND = 2, UPDATE = 3;
constexpr uint8_t FROM_START = 0, FROM_CUR = 1, FROM_END = 2; // (SEEK_* are stdio macros)
constexpr uint8_t ATTR_DIR = 0x10;
constexpr int NFILES = 8, NDIRS = 4;
} // namespace bios

struct DosSession {
    static constexpr uint16_t kBiosBase = 0xF000;
    static constexpr uint32_t kBiosSize = 0x1000;
    static constexpr uint16_t kStub = 0x9F00;     // SWI2 ; BRA *
    static constexpr uint16_t kNameBuf = 0x9E00;  // paths for open/kill/mkdir/... (NUL-terminated)
    static constexpr uint16_t kNameBuf2 = 0x9E60; // a second name (rename's new name)
    static constexpr uint16_t kStatBuf = 0x9EC0;  // 16-byte FSTAT/STAT/READDIR results
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

    // A NUL-terminated string in emulated RAM at `addr` (a path, or a bare name).
    void put_path(const std::string& path, uint16_t addr) {
        std::memcpy(bus.ram() + addr, path.c_str(), path.size() + 1);
    }

    void poke(uint16_t addr, const std::vector<uint8_t>& bytes) {
        std::memcpy(bus.ram() + addr, bytes.data(), bytes.size());
    }
    std::vector<uint8_t> peek(uint16_t addr, size_t n) const {
        return std::vector<uint8_t>(bus.ram() + addr, bus.ram() + addr + n);
    }

    // ---- convenience wrappers over the BIOS calls ----
    Result open(const std::string& path, uint8_t mode) {
        put_path(path, kNameBuf);
        return call(bios::B_FOPEN_NAME, 0, mode, kNameBuf);
    }
    Result close(uint8_t ref) { return call(bios::B_FCLOSE_NAME, ref); }
    Result kill(const std::string& path) {
        put_path(path, kNameBuf);
        return call(bios::B_KILL_NAME, 0, 0, kNameBuf);
    }
    Result rename(const std::string& from, const std::string& new_name) {
        put_path(from, kNameBuf);
        put_path(new_name, kNameBuf2);
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
    // Seek to an absolute 16-bit position.
    Result seek(uint8_t ref, uint16_t pos) { return call(bios::B_FSEEK_NAME, ref, bios::FROM_START, 0, pos); }
    Result seek32(uint8_t ref, uint8_t whence, uint32_t offset) {
        return call(bios::B_FSEEK_NAME, ref, whence, static_cast<uint16_t>(offset >> 16),
                    static_cast<uint16_t>(offset & 0xFFFF));
    }
    // FSTAT: x = file size, y = current position (the low words of the 32-bit fields).
    Result stat(uint8_t ref) {
        Result r = call(bios::B_FSTAT_NAME, ref, 0, kStatBuf);
        if (r.ok()) {
            r.x = be16(kStatBuf + 2);
            r.y = be16(kStatBuf + 6);
        }
        return r;
    }
    uint16_t be16(uint16_t addr) const { return static_cast<uint16_t>((bus.ram()[addr] << 8) | bus.ram()[addr + 1]); }
    uint32_t be32(uint16_t addr) const { return (static_cast<uint32_t>(be16(addr)) << 16) | be16(addr + 2); }

    Result mkdir(const std::string& path) {
        put_path(path, kNameBuf);
        return call(bios::B_MKDIR, 0, 0, kNameBuf);
    }
    Result rmdir(const std::string& path) {
        put_path(path, kNameBuf);
        return call(bios::B_RMDIR, 0, 0, kNameBuf);
    }
    Result chdir(const std::string& path) {
        put_path(path, kNameBuf);
        return call(bios::B_CHDIR, 0, 0, kNameBuf);
    }
    // The current directory as DOS reports it ("<error N>" if the call fails).
    std::string getcwd() {
        Result r = call(bios::B_GETCWD, 0, 0, kData, 128);
        if (!r.ok()) return "<error " + std::to_string(r.a) + ">";
        std::vector<uint8_t> raw = peek(kData, 128);
        return std::string(reinterpret_cast<const char*>(raw.data()));
    }
    Result opendir(const std::string& path) {
        put_path(path, kNameBuf);
        return call(bios::B_OPENDIR, 0, 0, kNameBuf);
    }
    // One directory entry: the 16-byte READDIR result decoded.
    struct DirEntry {
        std::string name; // "NAME.EXT" (or "NAME"), as a user would type it
        uint8_t attr = 0;
        uint32_t size = 0;
        bool is_dir() const { return (attr & bios::ATTR_DIR) != 0; }
    };
    // Reads the next entry of scan `h`; returns false (and *err) at the end/on error.
    bool readdir(uint8_t h, DirEntry& out, uint8_t* err = nullptr) {
        Result r = call(bios::B_READDIR, h, 0, kStatBuf);
        if (!r.ok()) {
            if (err) *err = r.a;
            return false;
        }
        std::vector<uint8_t> raw = peek(kStatBuf, 16);
        std::string base(reinterpret_cast<const char*>(&raw[0]), 8), ext(reinterpret_cast<const char*>(&raw[8]), 3);
        while (!base.empty() && base.back() == ' ') base.pop_back();
        while (!ext.empty() && ext.back() == ' ') ext.pop_back();
        out.name = ext.empty() ? base : base + "." + ext;
        out.attr = raw[11];
        out.size = be32(kStatBuf + 12);
        return true;
    }
    Result closedir(uint8_t h) { return call(bios::B_CLOSEDIR, h); }
    // All entries of a directory (open, read to the end, close); empty + *ok=false if it can't be opened.
    std::vector<DirEntry> list(const std::string& path, bool* ok = nullptr) {
        std::vector<DirEntry> entries;
        Result o = opendir(path);
        if (ok) *ok = o.ok();
        if (!o.ok()) return entries;
        DirEntry e;
        while (readdir(o.a, e)) entries.push_back(e);
        closedir(o.a);
        return entries;
    }
    // STAT by path: *size / *attr filled when given.
    Result stat_path(const std::string& path, uint32_t* size = nullptr, uint8_t* attr = nullptr) {
        put_path(path, kNameBuf);
        Result r = call(bios::B_STAT, 0, 0, kNameBuf, kStatBuf);
        if (r.ok()) {
            if (size) *size = be32(kStatBuf);
            if (attr) *attr = bus.ram()[kStatBuf + 8];
        }
        return r;
    }
    Result flush(uint8_t ref) { return call(bios::B_FFLUSH, ref); }

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
