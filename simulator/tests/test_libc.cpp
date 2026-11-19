// The C library (cc/lib): CRT0.O and LIBC.A, on the emulated machine. Until
// there is a compiler, its programs are written in assembly by C's calling
// convention (test_libc/*.asm); ASM assembles each, LINK links it as CC will
// (crt0.o, the program, -lc, with CC.SCR), and what it prints -- and the files
// it leaves -- are checked: printf's conversions, <string.h>, <ctype.h>, atoi,
// rand, malloc and its friends, files (text and binary, seeking, appending,
// renaming, removing), argc/argv, and stdin read from the keyboard.
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <iterator>
#include <string>
#include <utility>
#include <vector>

#include "basic309_session.hpp"
#include "pugputer/c_library.hpp"
#include "disk_images.hpp"
#include "fat16_reader.hpp"
#include "test_framework.hpp"

namespace {

std::string repo(const std::string& rel) { return std::string(REPO_DIR) + "/" + rel; }

bool read_host(const std::string& path, std::string& out) {
    std::ifstream f(path, std::ios::binary);
    if (!f) return false;
    out.assign((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
    return true;
}

pugputer::Fat16File file(const std::string& name, const std::string& data) {
    pugputer::Fat16File f;
    f.name = name;
    f.data.assign(data.begin(), data.end());
    return f;
}

bool add(std::vector<pugputer::Fat16File>& files, const std::string& host, const std::string& name) {
    std::string d;
    if (!read_host(host, d)) {
        std::fprintf(stderr, "  can't read %s\n", host.c_str());
        return false;
    }
    files.push_back(file(name, d));
    return true;
}

// The library as mkdiskimg puts it on a disk: /LIB/CRT0.O, /LIB/CC.SCR and
// /LIB/LIBC.A (lwar's format: the members of cc/lib/libc.rsp, in order).
bool add_library(std::vector<pugputer::Fat16File>& files) {
    std::string error;
    if (pugputer::c_library_files(REPO_DIR, files, error)) return true;
    std::fprintf(stderr, "  %s\n", error.c_str());
    return false;
}

std::string upper(std::string s) {
    for (char& c : s) c = static_cast<char>(std::toupper(static_cast<unsigned char>(c)));
    return s;
}

// A Pugputer with ASM, LINK, the library and a test program on a fresh disk.
struct Machine {
    Basic309Session s;
    std::string img;

    bool start(const std::string& prog, std::vector<pugputer::Fat16File> files = {}) {
        if (!add(files, ASM_BIN_PATH, "ASM.COM")) return false;
        if (!add(files, LINK_BIN_PATH, "LINK.COM")) return false;
        if (!add_library(files)) return false;
        if (!add(files, repo("simulator/tests/test_libc/calls.d"), "CALLS.D")) return false;
        if (!add(files, repo("simulator/tests/test_libc/" + prog + ".asm"), upper(prog) + ".ASM")) return false;
        img = build_image(("libc_" + prog + ".img").c_str(), 32768, 4, std::move(files));
        return !img.empty() && s.boot_shell(PUGBIOS_S19_PATH, img.c_str());
    }
    // Types a command, then `input` (what the program will read); what came
    // back up to the next prompt ("<<TIMEOUT>>" if it didn't).
    std::string run(const std::string& cmd, const std::string& input = "", uint64_t budget = 20000000000ull) {
        s.received.clear();
        for (char c : cmd) s.send_byte(static_cast<uint8_t>(c));
        s.send_byte('\r');
        for (char c : input) s.send_byte(static_cast<uint8_t>(c));
        uint64_t spent = 0;
        while (spent < budget) {
            spent += s.bus.run(20000);
            const std::string& r = s.received;
            if (r.size() > cmd.size() + 2 && r.compare(r.size() - 2, 2, "> ") == 0) return r;
        }
        return "<<TIMEOUT>>";
    }
    std::string disk_file(const std::string& name) const {
        Fat16Volume v;
        if (!v.load(img.c_str())) return "<no image>";
        Fat16Volume::Entry e;
        if (!v.find(name, e)) return "<none>";
        std::vector<uint8_t> d = v.read(e);
        return std::string(d.begin(), d.end());
    }
    // ASM and LINK make PROG.COM, as CC will: true if both said nothing wrong.
    bool build(const std::string& prog) {
        std::string a = run("ASM -f obj " + prog + ".asm");
        if (a.find("rror") != std::string::npos) {
            std::fprintf(stderr, "  ASM said: %s\n", a.c_str());
            return false;
        }
        std::string l = run("LINK -f com -o " + upper(prog) + ".COM -s /lib/cc.scr -L /lib /lib/crt0.o " + prog + ".o -lc");
        if (l.find("rror") != std::string::npos || l.find("not found") != std::string::npos ||
            l.find("Warning") != std::string::npos) {
            std::fprintf(stderr, "  LINK said: %s\n", l.c_str());
            return false;
        }
        return disk_file(upper(prog) + ".COM") != "<none>";
    }
};

// What the program printed: everything after the echoed command line, to the
// prompt.
std::string printed(const std::string& said, const std::string& cmd) {
    size_t i = said.find(cmd + "\r\n");
    std::string out = i == std::string::npos ? said : said.substr(i + cmd.size() + 2);
    size_t p = out.rfind("/> ");
    if (p != std::string::npos) out.erase(p);
    // (the shell starts again when a program ends, and says so)
    p = out.rfind("\r\nPugputer 6309 shell");
    if (p != std::string::npos) out.erase(p);
    if (std::getenv("LIBC_SHOW")) std::fprintf(stderr, "  printed: [%s]\n", out.c_str());
    return out;
}

bool same(const char* what, const std::string& expected, const std::string& got) {
    if (expected == got) return true;
    size_t i = 0;
    while (i < expected.size() && i < got.size() && expected[i] == got[i]) ++i;
    std::fprintf(stderr, "  %s differs at byte %zu:\n    expected: %s\n    got:      %s\n", what, i,
                 expected.substr(i, 60).c_str(), got.substr(i, 60).c_str());
    return false;
}

} // namespace

TEST(libc_printf_formats_like_c) {
    Machine m;
    CHECK(m.start("prt"));
    CHECK(m.build("prt"));
    CHECK(same("printf", "-123|456|65535|beef|BEEF|10\r\n"
                         "[   42][42   ][-0042][7    ][   ab][ab   ][xy][Q]\r\n"
                         "-100000 4000000000 12345678 5%\r\n"
                         "    99|99  |007|ABCD|(null)\r\n"
                         "x-12\r\n4\r\nabc\r\n4\r\n!33\r\n",
               printed(m.run("PRT"), "PRT")));
    // Small: a program that only prints links no file code
    CHECK(m.disk_file("PRT.COM").size() < 2000);
}

TEST(libc_strings_ctype_and_stdlib) {
    Machine m;
    CHECK(m.start("str"));
    CHECK(m.build("str"));
    CHECK(same("strings", "5\r\nabcdef\r\n-1\r\n1\r\n0\r\n-99\r\n0\r\n0\r\n255\r\n2\r\n3\r\n0\r\n6\r\n0\r\n"
                          "121234589\r\n234584589\r\nzzz584589\r\n"
                          "-1234\r\n77\r\n5\r\n"
                          "2\r\n4\r\n8\r\n0\r\n64\r\n128\r\n0\r\n16\r\n0\r\n81\r\n113\r\n49\r\n"
                          "385\r\n24609\r\n27033\r\n",
               printed(m.run("STR"), "STR")));
}

TEST(libc_malloc_reuses_and_joins_blocks) {
    Machine m;
    CHECK(m.start("mal"));
    CHECK(m.build("mal"));
    CHECK(same("malloc", "12\r\n22\r\n1\r\n1\r\n1\r\n0\r\n0\r\n0\r\n0\r\n", printed(m.run("MAL"), "MAL")));
}

TEST(libc_files_text_and_binary) {
    Machine m;
    CHECK(m.start("fio"));
    CHECK(m.build("fio"));
    CHECK(same("files", "[line 1\r\n][two\r\n][3\r\n]32\r\n16\r\n0\r\n49\r\n6\r\n3\r\n0\r\n0\r\n0\r\n-1\r\n",
               printed(m.run("FIO"), "FIO")));
    CHECK(same("U.TXT (text: CR LF)", "line 1\r\ntwo\r\n3\r\n", m.disk_file("U.TXT")));
    CHECK(m.disk_file("T.TXT") == "<none>");
    CHECK(m.disk_file("A.TXT") == "<none>");
    CHECK(same("B.BIN (binary)", std::string("\x01\x02\x0A\x0D\x00\xFF", 6), m.disk_file("B.BIN")));
}

TEST(libc_argc_and_argv) {
    Machine m;
    CHECK(m.start("arg"));
    CHECK(m.build("arg"));
    CHECK(same("argv", "4 [] [one] [two three] [four]\r\n", printed(m.run("ARG one \"two three\"  four"),
                                                                    "ARG one \"two three\"  four")));
    CHECK(same("no arguments", "1 []\r\n", printed(m.run("ARG"), "ARG")));
}

TEST(libc_stdin_reads_lines_from_the_keyboard) {
    Machine m;
    CHECK(m.start("in"));
    CHECK(m.build("in"));
    // A line with a Backspace, then "hi" and Enter a character at a time, then
    // Ctrl-D: each echoed as it's typed.
    std::string said = printed(m.run("IN", "abX\x08" "c\rhi\r\x04"), "IN");
    CHECK(same("stdin", "abX\x08 \x08" "c\r\n<abc\r\n>hi\r\n(104)(105)(10)EOF", said));
}
