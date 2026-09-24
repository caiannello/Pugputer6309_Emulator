// Builds basic309/disk.img: a fresh FAT16 disk image (see
// pugputer/fat16_image.hpp) containing dos/dos.bin in its reserved
// sectors (loaded by bios/sdcard.asm's SD_BOOT_TRY), SHELL.COM (shell/shell.bin
// as assembled -- it carries its own program header) and BASIC.COM (the
// $C000-$EFFF window of basic309's S-record, given a program header: load $C000,
// entry $C000 -- see EXE_* in bios/defines.d). DOS starts SHELL.COM at boot.
//
//   mkdiskimg                                  -- default paths below
//   mkdiskimg --dos path/to/dos.bin --basic path/to/exbasrom309.s19
//             --shell path/to/shell.bin --out path/to/disk.img
#include <cstdio>
#include <cstring>
#include <fstream>
#include <iterator>
#include <string>
#include <vector>

#include "pugputer/fat16_image.hpp"
#include "pugputer/srec_loader.hpp"

using pugputer::build_fat16_image;
using pugputer::Fat16File;
using pugputer::load_srec_file;
using pugputer::SrecLoadResult;

namespace {
constexpr uint16_t kBasicBase = 0xC000;
constexpr uint32_t kBasicSize = 0x3000; // $C000-$EFFF, same window the
                                         // existing basic309 tools/tests use

bool read_file(const std::string& path, std::vector<uint8_t>& out) {
    std::ifstream f(path, std::ios::binary);
    if (!f) {
        std::fprintf(stderr, "Failed to open '%s'\n", path.c_str());
        return false;
    }
    out.assign((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
    return true;
}
} // namespace

int main(int argc, char** argv) {
    std::string dos_path = DOS_BIN_DEFAULT;
    std::string basic_path = EXBASROM309_S19_DEFAULT;
    std::string shell_path = SHELL_BIN_DEFAULT;
    std::string out_path = DISK_IMG_DEFAULT;
    for (int i = 1; i < argc; ++i) {
        if (std::strcmp(argv[i], "--dos") == 0 && i + 1 < argc) {
            dos_path = argv[++i];
        } else if (std::strcmp(argv[i], "--basic") == 0 && i + 1 < argc) {
            basic_path = argv[++i];
        } else if (std::strcmp(argv[i], "--shell") == 0 && i + 1 < argc) {
            shell_path = argv[++i];
        } else if (std::strcmp(argv[i], "--out") == 0 && i + 1 < argc) {
            out_path = argv[++i];
        }
    }

    std::vector<uint8_t> dos_payload;
    if (!read_file(dos_path, dos_payload)) return 1;
    std::printf("Loaded %s (%zu bytes)\n", dos_path.c_str(), dos_payload.size());

    Fat16File shell_com;
    shell_com.name = "SHELL.COM";
    if (!read_file(shell_path, shell_com.data)) return 1;
    std::printf("Loaded %s (%zu bytes) as SHELL.COM\n", shell_path.c_str(), shell_com.data.size());

    std::vector<uint8_t> basic_image(65536, 0);
    SrecLoadResult basic_load = load_srec_file(basic_path, basic_image.data(), basic_image.size());
    if (!basic_load.ok) {
        std::fprintf(stderr, "Failed to load '%s': %s\n", basic_path.c_str(), basic_load.error.c_str());
        return 1;
    }
    Fat16File basic_com;
    basic_com.name = "BASIC.COM";
    // Program header: "PX", load address, entry address, flags (all big-endian).
    basic_com.data = {'P',
                      'X',
                      static_cast<uint8_t>(kBasicBase >> 8),
                      static_cast<uint8_t>(kBasicBase & 0xFF),
                      static_cast<uint8_t>(kBasicBase >> 8),
                      static_cast<uint8_t>(kBasicBase & 0xFF),
                      0,
                      0};
    basic_com.data.insert(basic_com.data.end(), basic_image.begin() + kBasicBase,
                          basic_image.begin() + kBasicBase + kBasicSize);
    std::printf("Loaded %s ($%04X-$%04X) as BASIC.COM (%zu bytes with its header)\n", basic_path.c_str(),
                basic_load.min_addr, basic_load.max_addr, basic_com.data.size());

    auto result = build_fat16_image(out_path, dos_payload, {shell_com, basic_com});
    if (!result.ok) {
        std::fprintf(stderr, "Failed to build '%s': %s\n", out_path.c_str(), result.error.c_str());
        return 1;
    }
    std::printf("Wrote %s\n", out_path.c_str());
    return 0;
}
