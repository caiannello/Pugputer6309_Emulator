// Builds throwaway FAT16 disk images for tests (in the build directory): the real
// dos.bin and BASIC.COM, so the whole boot chain works, plus any extra files, on a
// volume of any size the tests want.
#pragma once

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <iterator>
#include <string>
#include <vector>

#include "pugputer/basic309_layout.hpp"
#include "pugputer/fat16_image.hpp"
#include "pugputer/srec_loader.hpp"

// A fresh disk image in the build directory: dos.bin, SHELL.COM and BASIC.COM (so the
// boot chain works, as on mkdiskimg's disk) and `extra`. Returns its path ("" on failure).
inline std::string build_image(const char* name, uint32_t sectors, uint8_t spc, std::vector<pugputer::Fat16File> extra) {
    std::string path = std::string(PUGPUTER_TEST_BUILD_DIR) + "/" + name;
#ifdef _WIN32
    std::string mk = std::string("mkdir \"") + PUGPUTER_TEST_BUILD_DIR + "\" >NUL 2>NUL";
#else
    std::string mk = std::string("mkdir -p \"") + PUGPUTER_TEST_BUILD_DIR + "\"";
#endif
    std::system(mk.c_str());
    std::ifstream dos_file(DOS_BIN_PATH, std::ios::binary);
    if (!dos_file) return "";
    std::vector<uint8_t> dos((std::istreambuf_iterator<char>(dos_file)), std::istreambuf_iterator<char>());
    std::vector<uint8_t> image(65536, 0);
    if (!pugputer::load_srec_file(EXBASROM309_S19_PATH, image.data(), image.size()).ok) return "";
    pugputer::Fat16File basic;
    basic.name = "BASIC.COM";
    // Program header: load at BASIC_LOAD, start at BASIC_ENTRY.
    basic.data = {'P', 'X', pugputer::kBasicLoad >> 8, pugputer::kBasicLoad & 0xFF,
                  pugputer::kBasicEntry >> 8, pugputer::kBasicEntry & 0xFF, 0, 0};
    basic.data.insert(basic.data.end(), image.begin() + pugputer::kBasicLoad, image.begin() + 0xF000);
    pugputer::Fat16File shell;
    shell.name = "SHELL.COM";
    std::ifstream shell_file(SHELL_BIN_PATH, std::ios::binary);
    if (!shell_file) return "";
    shell.data.assign((std::istreambuf_iterator<char>(shell_file)), std::istreambuf_iterator<char>());
    std::vector<pugputer::Fat16File> files{shell, basic};
    for (auto& f : extra) files.push_back(std::move(f));
    auto r = pugputer::build_fat16_image(path, dos, files, sectors, spc);
    if (!r.ok) {
        std::fprintf(stderr, "  image build failed: %s\n", r.error.c_str());
        return "";
    }
    return path;
}

