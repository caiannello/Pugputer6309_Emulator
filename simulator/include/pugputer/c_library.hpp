// The C library (cc/lib) as it goes on a disk: /LIB/CRT0.O, /LIB/CC.SCR (LINK's
// script for a C program) and /LIB/LIBC.A, an archive in lwar's format (what
// asmlink/ar.asm makes) of the members cc/lib/libc.rsp lists, in that order. That
// file is AR's response file: "AR @libc.rsp" makes the same archive on the Pugputer.
// /LIB/LIBPUG.A (video, input, sound) is the same, from libpug.rsp.
// The objects are cc/lib's compile.bat's (or compile.sh's), made by lwasm.
// mkdiskimg puts them on every disk, with the C headers in /INCLUDE; test_libc.cpp
// and test_cc.cpp use them the same way.
#pragma once

#include <cctype>
#include <cstdint>
#include <fstream>
#include <iterator>
#include <string>
#include <utility>
#include <vector>

#include "pugputer/fat16_image.hpp"

namespace pugputer {

// An archive as lwar makes it: "LWAR1V"; each member's name, a NUL, its length
// (32 bits, high byte first) and its bytes; then a NUL.
inline std::vector<uint8_t> make_lwar(const std::vector<std::pair<std::string, std::vector<uint8_t>>>& members) {
    std::vector<uint8_t> a = {'L', 'W', 'A', 'R', '1', 'V'};
    for (const auto& m : members) {
        a.insert(a.end(), m.first.begin(), m.first.end());
        a.push_back(0);
        uint32_t n = static_cast<uint32_t>(m.second.size());
        for (int sh = 24; sh >= 0; sh -= 8) a.push_back(static_cast<uint8_t>((n >> sh) & 0xFF));
        a.insert(a.end(), m.second.begin(), m.second.end());
    }
    a.push_back(0);
    return a;
}

// The library's three files from the repository at `repo`; false (and `error`
// says why) if one can't be read.
inline bool c_library_files(const std::string& repo, std::vector<Fat16File>& out, std::string& error) {
    auto read = [&](const std::string& rel, std::vector<uint8_t>& data) {
        std::ifstream f(repo + "/" + rel, std::ios::binary);
        if (!f) {
            error = "can't read " + rel + " (cc/lib/compile.bat or compile.sh makes the objects)";
            return false;
        }
        data.assign((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
        return true;
    };
    // An archive from a response file's members (its words: AR's options, the
    // archive, then each member's .o).
    auto archive = [&](const std::string& rsp, std::vector<uint8_t>& data) {
        std::vector<uint8_t> list;
        if (!read("cc/lib/" + rsp, list)) return false;
        std::vector<std::pair<std::string, std::vector<uint8_t>>> members;
        std::string word;
        for (size_t i = 0; i <= list.size(); ++i) {
            char c = i < list.size() ? static_cast<char>(list[i]) : ' ';
            if (c == ' ' || c == '\t' || c == '\r' || c == '\n') {
                if (word.size() > 2 && word.compare(word.size() - 2, 2, ".o") == 0) {
                    std::vector<uint8_t> o;
                    if (!read("cc/lib/" + word, o)) return false;
                    members.push_back({word, std::move(o)});
                }
                word.clear();
            } else {
                word += c;
            }
        }
        data = make_lwar(members);
        return true;
    };
    Fat16File crt0, script, libc, libpug;
    crt0.name = "LIB/CRT0.O";
    script.name = "LIB/CC.SCR";
    libc.name = "LIB/LIBC.A";
    libpug.name = "LIB/LIBPUG.A";
    if (!read("cc/lib/crt0.o", crt0.data) || !read("cc/lib/cc.scr", script.data)) return false;
    if (!archive("libc.rsp", libc.data) || !archive("libpug.rsp", libpug.data)) return false;
    out.push_back(std::move(crt0));
    out.push_back(std::move(script));
    out.push_back(std::move(libc));
    out.push_back(std::move(libpug));
    return true;
}

// The C headers (cc/include), as /INCLUDE/NAME.H: where CPP looks for them.
inline const char* const kCHeaders[] = {"stddef.h", "stdio.h", "string.h", "ctype.h", "stdlib.h",
                                        "limits.h", "stdarg.h", "stdbool.h", "stdint.h", "float.h", "math.h",
                                        "pug/sys.h", "pug/bank.h", "pug/video.h", "pug/input.h",
                                        "pug/sound.h"};

inline bool c_header_files(const std::string& repo, std::vector<Fat16File>& out, std::string& error) {
    for (const char* name : kCHeaders) {
        std::ifstream f(repo + "/cc/include/" + name, std::ios::binary);
        if (!f) {
            error = std::string("can't read cc/include/") + name;
            return false;
        }
        Fat16File h;
        h.name = "INCLUDE/";
        for (const char* c = name; *c; ++c) h.name += static_cast<char>(std::toupper(static_cast<unsigned char>(*c)));
        h.data.assign((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
        out.push_back(std::move(h));
    }
    return true;
}

} // namespace pugputer
