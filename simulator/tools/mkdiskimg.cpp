// Builds basic309/disk.img: a fresh FAT16 disk image (see
// pugputer/fat16_image.hpp) containing dos/dos.bin in its reserved
// sectors (loaded by bios/sdcard.asm's SD_BOOT_TRY) and, in /CMD, SHELL.COM,
// EDIT.COM, ASM.COM, LINK.COM and HEXDUMP.COM (shell/shell.bin, edit/edit.bin,
// asmlink/asm.bin, asmlink/link.bin and utils/hexdump.bin as assembled -- they
// carry their own program headers) and BASIC.COM (the $C000-$EFFF window of basic309's S-record,
// given a program header: load $C000, entry $C000 -- see EXE_* in bios/defines.d).
// DOS starts /CMD/SHELL.COM at boot, and the shell finds programs through its PATH
// (/CMD by default).
//
//   mkdiskimg                                  -- default paths below
//   mkdiskimg --dos path/to/dos.bin --basic path/to/exbasrom309.s19
//             --shell path/to/shell.bin --edit path/to/edit.bin
//             --asm path/to/asm.bin --link path/to/link.bin
//             --hexdump path/to/hexdump.bin
//             --out path/to/disk.img
//             [--add-dir path/to/folder]
//
// --add-dir copies a folder onto the disk as well: its files (8.3 names) into the
// root directory and its subfolders, recursively, into directories of the same
// names -- the binary release does this with demo/programs (BASIC/, ASM/).
#include <algorithm>
#include <cstdio>
#include <cstring>
#include <filesystem>
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

bool is_8_3(const std::filesystem::path& path) {
    std::string stem = path.stem().string();
    std::string ext = path.extension().string(); // with its dot
    return !stem.empty() && stem.size() <= 8 && ext.size() <= 4;
}

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
    std::string add_dir;
    // The other programs in /CMD, each assembled with its own header: the option that
    // names another file for it, the file, and its name on the disk.
    struct Program {
        const char* option;
        std::string path;
        const char* name;
    };
    std::vector<Program> programs = {{"--edit", EDIT_BIN_DEFAULT, "EDIT.COM"},
                                     {"--asm", ASM_BIN_DEFAULT, "ASM.COM"},
                                     {"--link", LINK_BIN_DEFAULT, "LINK.COM"},
                                     {"--hexdump", HEXDUMP_BIN_DEFAULT, "HEXDUMP.COM"}};
    for (int i = 1; i < argc; ++i) {
        bool program = false;
        for (auto& p : programs)
            if (std::strcmp(argv[i], p.option) == 0 && i + 1 < argc) {
                p.path = argv[++i];
                program = true;
            }
        if (program) continue;
        if (std::strcmp(argv[i], "--dos") == 0 && i + 1 < argc) {
            dos_path = argv[++i];
        } else if (std::strcmp(argv[i], "--basic") == 0 && i + 1 < argc) {
            basic_path = argv[++i];
        } else if (std::strcmp(argv[i], "--shell") == 0 && i + 1 < argc) {
            shell_path = argv[++i];
        } else if (std::strcmp(argv[i], "--add-dir") == 0 && i + 1 < argc) {
            add_dir = argv[++i];
        } else if (std::strcmp(argv[i], "--out") == 0 && i + 1 < argc) {
            out_path = argv[++i];
        }
    }

    std::vector<uint8_t> dos_payload;
    if (!read_file(dos_path, dos_payload)) return 1;
    std::printf("Loaded %s (%zu bytes)\n", dos_path.c_str(), dos_payload.size());

    Fat16File shell_com;
    shell_com.name = "CMD/SHELL.COM";
    if (!read_file(shell_path, shell_com.data)) return 1;
    std::printf("Loaded %s (%zu bytes) as /CMD/SHELL.COM\n", shell_path.c_str(), shell_com.data.size());

    std::vector<uint8_t> basic_image(65536, 0);
    SrecLoadResult basic_load = load_srec_file(basic_path, basic_image.data(), basic_image.size());
    if (!basic_load.ok) {
        std::fprintf(stderr, "Failed to load '%s': %s\n", basic_path.c_str(), basic_load.error.c_str());
        return 1;
    }
    Fat16File basic_com;
    basic_com.name = "CMD/BASIC.COM";
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
    std::printf("Loaded %s ($%04X-$%04X) as /CMD/BASIC.COM (%zu bytes with its header)\n", basic_path.c_str(),
                basic_load.min_addr, basic_load.max_addr, basic_com.data.size());

    std::vector<Fat16File> files = {shell_com, basic_com};
    for (const auto& p : programs) {
        Fat16File f;
        f.name = std::string("CMD/") + p.name;
        if (!read_file(p.path, f.data)) return 1;
        std::printf("Loaded %s (%zu bytes) as /CMD/%s\n", p.path.c_str(), f.data.size(), p.name);
        files.push_back(std::move(f));
    }
    if (!add_dir.empty()) {
        // Everything under the folder, in a stable order; a file's path relative to
        // the folder (with "/" separators) is its path on the disk.
        std::vector<std::filesystem::path> extra;
        for (const auto& entry : std::filesystem::recursive_directory_iterator(add_dir))
            if (entry.is_regular_file()) extra.push_back(std::filesystem::relative(entry.path(), add_dir));
        std::sort(extra.begin(), extra.end());
        for (const auto& rel : extra) {
            Fat16File f;
            f.name = rel.generic_string();
            bool ok = true;
            for (const auto& part : rel) ok = ok && is_8_3(part);
            if (!ok) {
                std::fprintf(stderr, "Skipping '%s': not an 8.3 name\n", f.name.c_str());
                continue;
            }
            if (!read_file((std::filesystem::path(add_dir) / rel).string(), f.data)) return 1;
            std::printf("Added /%s (%zu bytes)\n", f.name.c_str(), f.data.size());
            files.push_back(std::move(f));
        }
    }
    auto result = build_fat16_image(out_path, dos_payload, files);
    if (!result.ok) {
        std::fprintf(stderr, "Failed to build '%s': %s\n", out_path.c_str(), result.error.c_str());
        return 1;
    }
    std::printf("Wrote %s\n", out_path.c_str());
    return 0;
}
