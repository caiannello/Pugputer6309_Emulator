// Builds basic309/disk.img: a fresh FAT16 disk image (see
// pugputer/fat16_image.hpp) containing dos/dos.bin in its reserved
// sectors (loaded by bios/sdcard.asm's SD_BOOT_TRY) and, in /CMD, SHELL.COM,
// EDIT.COM, ASM.COM, LINK.COM, HEXDUMP.COM, MOVE.COM, TILEKIT.COM and SONGPLAY.COM
// (shell/shell.bin, edit/edit.bin, asmlink/asm.bin, asmlink/link.bin, utils/hexdump.bin,
// utils/move.bin, gamekit/build/tilekit.bin and gamekit/build/songplay.bin as assembled -- they carry their own
// program headers), TILEKIT.INI (TILEKIT's default palettes, gamekit/TILEKIT.INI) and
// BASIC.COM (the BASIC_LOAD-$EFFF window of basic309's S-record, given a program
// header: load BASIC_LOAD, entry $C000 -- see pugputer/basic309_layout.hpp and EXE_* in
// bios/defines.d).
// DOS starts /CMD/SHELL.COM at boot, and the shell finds programs through its PATH
// (/CMD by default).
//
//   mkdiskimg                                  -- default paths below
//   mkdiskimg --dos path/to/dos.bin --basic path/to/exbasrom309.s19
//             --shell path/to/shell.bin --edit path/to/edit.bin
//             --asm path/to/asm.bin --link path/to/link.bin
//             --hexdump path/to/hexdump.bin --move path/to/move.bin
//             --tilekit path/to/tilekit.bin --songplay path/to/songplay.bin
//             --out path/to/disk.img
//             [--sources path/to/repository] [--demo NAME]... [--add-dir path/to/folder]...
//
// --sources adds the programs' sources from the repository, in /ASM (see
// pugputer/demo_sources.hpp), for rebuilding them on the Pugputer, and the demo
// programs, built (demo/compile.bat or .sh), in /DEMO, with the files they use
// (/DEMO/VGMPLAY's songs, SWAMP's pictures).
// --demo adds just one of those demos, /DEMO/NAME.COM, with its files in /DEMO (those
// named NAME...), from the repository this was built in (or --sources's): reinit_disk
// puts SWAMP on basic309/disk.img this way.
// --add-dir copies a folder onto the disk as well: its files (8.3 names) into the
// root directory and its subfolders, recursively, into directories of the same
// names -- the binary release does this with demo/programs (BASIC/, ASM/). It can
// be given more than once.
// A file added at a path the disk already has replaces it: the sources and demos go
// on first, then the folders, in order (reinit_disk and make_release add local/disk/,
// if there is one, last).
#include <algorithm>
#include <cctype>
#include <cstdio>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <string>
#include <vector>

#include "pugputer/basic309_layout.hpp"
#include "pugputer/demo_sources.hpp"
#include "pugputer/fat16_image.hpp"
#include "pugputer/srec_loader.hpp"

using pugputer::build_fat16_image;
using pugputer::Fat16File;
using pugputer::load_srec_file;
using pugputer::SrecLoadResult;

namespace {
constexpr uint16_t kBasicBase = pugputer::kBasicLoad;
constexpr uint32_t kBasicSize = pugputer::kBasicImageSize; // up to $EFFF
constexpr uint16_t kBasicEntry = pugputer::kBasicEntry;    // BASIC_ENTRY: JMP RESVEC

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
    std::vector<std::string> add_dirs;
    std::vector<std::string> demos;
    std::string sources;
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
                                     {"--hexdump", HEXDUMP_BIN_DEFAULT, "HEXDUMP.COM"},
                                     {"--move", MOVE_BIN_DEFAULT, "MOVE.COM"},
                                     {"--tilekit", TILEKIT_BIN_DEFAULT, "TILEKIT.COM"},
                                     {"--songplay", SONGPLAY_BIN_DEFAULT, "SONGPLAY.COM"},
                                     {"--tilekit-ini", TILEKIT_INI_DEFAULT, "TILEKIT.INI"}};
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
            add_dirs.push_back(argv[++i]);
        } else if (std::strcmp(argv[i], "--sources") == 0 && i + 1 < argc) {
            sources = argv[++i];
        } else if (std::strcmp(argv[i], "--demo") == 0 && i + 1 < argc) {
            std::string name = argv[++i];
            for (char& c : name) c = static_cast<char>(std::toupper(static_cast<unsigned char>(c)));
            demos.push_back(name);
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
                      static_cast<uint8_t>(kBasicEntry >> 8),
                      static_cast<uint8_t>(kBasicEntry & 0xFF),
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
    // Everything from here on replaces a file already at its path (compared as DOS does,
    // in either case), so the order says which wins: the sources and demos, then the
    // folders of --add-dir (reinit_disk and make_release add local/disk/ last of all).
    auto add = [&](Fat16File f, const char* note) {
        auto same = std::find_if(files.begin(), files.end(), [&](const Fat16File& g) {
            return std::equal(g.name.begin(), g.name.end(), f.name.begin(), f.name.end(), [](char a, char b) {
                return std::toupper(static_cast<unsigned char>(a)) == std::toupper(static_cast<unsigned char>(b));
            });
        });
        std::printf("%s /%s (%zu bytes%s)\n", same == files.end() ? "Added" : "Replaced", f.name.c_str(),
                    f.data.size(), note);
        if (same != files.end())
            *same = std::move(f);
        else
            files.push_back(std::move(f));
    };
    auto add_file = [&](const std::string& repo, const pugputer::DemoSource& src) {
        Fat16File f;
        f.name = src.disk;
        if (!read_file((std::filesystem::path(repo) / src.repo).string(), f.data)) return false;
        add(std::move(f), "");
        return true;
    };
    // A demo program: its raw image, given the program header ASM -f com would give it.
    auto add_program = [&](const std::string& repo, const pugputer::DemoProgram& prog) {
        Fat16File f;
        f.name = prog.disk;
        std::vector<uint8_t> body;
        if (!read_file((std::filesystem::path(repo) / prog.repo).string(), body)) {
            std::fprintf(stderr, "(the demos are built by demo/compile.bat, or compile.sh)\n");
            return false;
        }
        // Program header: "PX", load address, entry address, flags (all big-endian).
        uint8_t hi = static_cast<uint8_t>(prog.load >> 8), lo = static_cast<uint8_t>(prog.load & 0xFF);
        f.data = {'P', 'X', hi, lo, hi, lo, 0, 0};
        f.data.insert(f.data.end(), body.begin(), body.end());
        add(std::move(f), " with its header");
        return true;
    };
    if (!sources.empty()) {
        for (const auto& src : pugputer::kDemoSources)
            if (!add_file(sources, src)) return 1;
        for (const auto& prog : pugputer::kDemoPrograms)
            if (!add_program(sources, prog)) return 1;
        for (const auto& src : pugputer::kDemoFiles)
            if (!add_file(sources, src)) return 1;
    }
    for (const auto& name : demos) {
        // /DEMO/NAME.COM, and the files in /DEMO whose names start with NAME
        std::string repo = sources.empty() ? REPO_DIR_DEFAULT : sources;
        std::string prog_name = "DEMO/" + name + ".COM";
        bool found = false;
        for (const auto& prog : pugputer::kDemoPrograms)
            if (prog_name == prog.disk) {
                if (!add_program(repo, prog)) return 1;
                found = true;
            }
        if (!found) {
            std::fprintf(stderr, "There's no demo /%s (see pugputer/demo_sources.hpp)\n", prog_name.c_str());
            return 1;
        }
        std::string prefix = "DEMO/" + name;
        for (const auto& src : pugputer::kDemoFiles) {
            std::string disk = src.disk;
            if (disk.compare(0, prefix.size(), prefix) == 0 && disk.find('/', 5) == std::string::npos)
                if (!add_file(repo, src)) return 1;
        }
    }
    for (const auto& add_dir : add_dirs) {
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
            add(std::move(f), "");
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
