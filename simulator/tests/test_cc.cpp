// CC (cc/): CPP and CC1, the C compiler, on the emulated machine. The C
// programs in test_cc/ are compiled there as CC will do it (CPP, CC1, ASM -f
// obj, LINK with /LIB/CRT0.O and LIBC.A) and run, and what they print is
// compared with their .out files. CPP's output is compared with the .i files,
// and CC1's assembly must make the same object file with lwasm as with ASM, so
// the two assemblers keep checking each other. A file with an error must fail,
// with the right message, and leave no output.
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
std::string host_text(const std::string& path) {
    std::string s;
    if (!read_host(path, s)) std::fprintf(stderr, "  can't read %s\n", path.c_str());
    return s;
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

std::string upper(std::string s) {
    for (char& c : s) c = static_cast<char>(std::toupper(static_cast<unsigned char>(c)));
    return s;
}

// test_cc/NAME on the disk as NAME (upper case).
pugputer::Fat16File test_file(const std::string& name) {
    return file(upper(name), host_text(repo("simulator/tests/test_cc/" + name)));
}

// Lines as the console shows them: each ending CR LF.
std::string crlf(const std::string& s) {
    std::string o;
    for (char c : s) {
        if (c == '\r') continue;
        if (c == '\n') o += '\r';
        o += c;
    }
    return o;
}

// A Pugputer with CPP, CC1, ASM, LINK, the library (/LIB) and its headers
// (/INCLUDE), and the files asked for, on a fresh disk.
struct Machine {
    Basic309Session s;
    std::string img;

    bool start(const char* name, std::vector<pugputer::Fat16File> files = {}) {
        if (!add(files, repo("cc/cpp.bin"), "CPP.COM")) return false;
        if (!add(files, repo("cc/cc1.bin"), "CC1.COM")) return false;
        if (!add(files, ASM_BIN_PATH, "ASM.COM")) return false;
        if (!add(files, LINK_BIN_PATH, "LINK.COM")) return false;
        std::string error;
        if (!pugputer::c_library_files(REPO_DIR, files, error) || !pugputer::c_header_files(REPO_DIR, files, error)) {
            std::fprintf(stderr, "  %s\n", error.c_str());
            return false;
        }
        img = build_image(name, 32768, 4, std::move(files));
        return !img.empty() && s.boot_shell(PUGBIOS_S19_PATH, img.c_str());
    }
    // Types a command, then `input` (what the program will read); what came
    // back up to the next prompt ("<<TIMEOUT>>" if it didn't).
    uint64_t cycles = 0; // what the last run() took
    std::string run(const std::string& cmd, const std::string& input = "", uint64_t budget = 20000000000ull) {
        s.received.clear();
        for (char c : cmd) s.send_byte(static_cast<uint8_t>(c));
        s.send_byte('\r');
        for (char c : input) s.send_byte(static_cast<uint8_t>(c));
        uint64_t spent = 0;
        while (spent < budget) {
            spent += s.bus.run(20000);
            const std::string& r = s.received;
            if (r.size() > cmd.size() + 2 && r.compare(r.size() - 2, 2, "> ") == 0) {
                cycles = spent;
                return r;
            }
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
    // NAME.C -> NAME.COM, as CC will do it: true if no step said anything was
    // wrong.
    bool compile(const std::string& name) {
        const std::string steps[] = {
            "CPP " + name + ".c",
            "CC1 " + name + ".i",
            "ASM -f obj " + name + ".asm",
            "LINK -f com -o " + upper(name) + ".COM -s /lib/cc.scr -L /lib /lib/crt0.o " + name + ".o -lc",
        };
        for (const std::string& step : steps) {
            std::string said = run(step);
            if (std::getenv("CC_TIMING")) std::printf("  %s: %.1f s at 3.58 MHz\n", step.c_str(), cycles / 3.58e6);
            if (said.find("rror") != std::string::npos || said.find("not found") != std::string::npos ||
                said.find("Warning") != std::string::npos || said == "<<TIMEOUT>>") {
                std::fprintf(stderr, "  %s said: %s\n", step.c_str(), said.c_str());
                return false;
            }
        }
        return disk_file(upper(name) + ".COM") != "<none>";
    }
};

// What a command printed: everything after the echoed command line, to the
// prompt (and the shell's banner when a program ends).
std::string printed(const std::string& said, const std::string& cmd) {
    size_t i = said.find(cmd + "\r\n");
    std::string out = i == std::string::npos ? said : said.substr(i + cmd.size() + 2);
    size_t p = out.rfind("/> ");
    if (p != std::string::npos) out.erase(p);
    p = out.rfind("\r\nPugputer 6309 shell");
    if (p != std::string::npos) out.erase(p);
    if (std::getenv("CC_SHOW")) std::fprintf(stderr, "  printed: [%s]\n", out.c_str());
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

// A C program in test_cc/ compiled and run: what it prints must be its .out.
bool runs_as_expected(const char* name, const char* img) {
    Machine m;
    if (!m.start(img, {test_file(std::string(name) + ".c")})) return false;
    if (!m.compile(name)) return false;
    std::string expected = crlf(host_text(repo("simulator/tests/test_cc/" + std::string(name) + ".out")));
    return same(name, expected, printed(m.run(upper(name)), upper(name)));
}

} // namespace

TEST(cpp_expands_macros_as_the_standard_says) {
    // The C standard's own examples (6.10.3.5): # and ##, rescanning, the
    // arguments expanded first, "...", and redefinitions.
    Machine m;
    CHECK(m.start("cc_cppstd.img", {test_file("cppstd.c")}));
    std::string said = m.run("CPP cppstd.c");
    CHECK(said.find("error") == std::string::npos);
    CHECK(same("cppstd.i", host_text(repo("simulator/tests/test_cc/cppstd.i")), m.disk_file("CPPSTD.I")));
}

TEST(cpp_includes_files_and_keeps_the_line_numbers) {
    // #include "..." (next to the file) and <...> (-I, then /INCLUDE), #if's
    // arithmetic, -D, #pragma passed on, #line, and the #line markers CC1 reads.
    Machine m;
    std::vector<pugputer::Fat16File> files = {test_file("cppinc.c"), test_file("cppa.h"), test_file("cppc.h")};
    pugputer::Fat16File b = test_file("cppb.h");
    b.name = "INC/CPPB.H";
    files.push_back(b);
    CHECK(m.start("cc_cppinc.img", files));
    std::string said = m.run("CPP -I inc -D FROMCMD=7 cppinc.c");
    CHECK(said.find("error") == std::string::npos);
    CHECK(same("cppinc.i", host_text(repo("simulator/tests/test_cc/cppinc.i")), m.disk_file("CPPINC.I")));
}

TEST(cpp_reports_errors_and_writes_nothing) {
    Machine m;
    CHECK(m.start("cc_cpperr.img", {file("E.C", "#define two(a,b) a b\n"
                                                "int x = two(1);\n"
                                                "#error stop \"here\"\n"
                                                "#bogus\n"
                                                "#include \"nope.h\"\n"
                                                "#if 1 +\n"
                                                "#endif\n"
                                                "#endif\n"
                                                "#define f(x,) x\n"
                                                "#define g(x) #y\n"
                                                "#if 1\n"
                                                "/* never closed\n")}));
    std::string said = printed(m.run("CPP e.c"), "CPP e.c");
    CHECK(same("CPP's errors",
               "e.c:2: error: wrong number of arguments to macro 'two'\r\n"
               "e.c:3: error: #error stop \"here\"\r\n"
               "e.c:4: error: invalid preprocessing directive\r\n"
               "e.c:5: error: cannot find include file 'nope.h'\r\n"
               "e.c:6: error: invalid #if expression\r\n"
               "e.c:8: error: #elif, #else or #endif without #if\r\n"
               "e.c:9: error: invalid macro parameter list\r\n"
               "e.c:10: error: '#' is not followed by a macro parameter\r\n"
               "e.c:12: error: unterminated comment\r\n"
               "e.c:13: error: unterminated #if\r\n"
               "10 error(s)\r\n",
               said));
    CHECK(m.disk_file("E.I") == "<none>");
}

TEST(cc_compiles_expressions_and_statements) {
    // Every operator (signed and unsigned), char and unsigned char, pointers
    // and arrays, globals with initializers, static locals, loops, switch,
    // goto, recursion, and the library's printf and strings.
    CHECK(runs_as_expected("ops", "cc_ops.img"));
}

TEST(cc_compiles_types_declarators_and_pointers_to_functions) {
    // typedef, arrays of arrays and of strings, pointers to pointers and to
    // functions (called both ways), locals' initializers, blocks' own
    // locals, casts, sizeof, the comma operator, abs/atoi and exit.
    CHECK(runs_as_expected("more", "cc_more.img"));
}

TEST(cc_compiles_structs_unions_enums_and_longs) {
    // struct and union members (. and ->, nested), struct assignment, structs
    // passed and returned by value, enum constants, and long arithmetic in
    // Q: * / % and shifts (the library's helpers), comparisons, casts, ++ --.
    CHECK(runs_as_expected("structs", "cc_structs.img"));
}

TEST(cc_compiles_initializers_asm_blocks_and_the_rest) {
    // Initializers with nested braces and without (brace elision), arrays
    // sized by them (locals too), unions; asm { } with C names; interrupt;
    // switch on a long; extern in a block; long op= of every kind.
    CHECK(runs_as_expected("inits", "cc_inits.img"));
}

TEST(cc_programs_seek_in_files_and_use_longs_in_the_library) {
    // fseek (back from the end and the current place: DOS's offsets are
    // signed) and ftell, atol and labs, and limits.h's longs.
    CHECK(runs_as_expected("files", "cc_files.img"));
}

TEST(cc_compiles_variadic_functions_and_reads_argv_and_stdin) {
    Machine m;
    CHECK(m.start("cc_vararg.img", {test_file("vararg.c")}));
    CHECK(m.compile("vararg"));
    std::string cmd = "VARARG one \"two words\" 3";
    CHECK(same("vararg",
               "0 6 150\r\n"
               "[note] the answer is 42\r\n"
               "argc 4: <one> <two words> <3>\r\n"
               "Hello, C!\r\nHELLO, C!\r\n",
               printed(m.run(cmd, "Hello, C!\r"), cmd)));
}

TEST(cc_programs_are_small) {
    // A program with printf only links what it uses of the library.
    Machine m;
    CHECK(m.start("cc_small.img", {file("HI.C", "#include <stdio.h>\n"
                                                "int main(void) { printf(\"hi %d\\n\", 42); return 0; }\n")}));
    CHECK(m.compile("hi"));
    CHECK(same("hi", "hi 42\r\n", printed(m.run("HI"), "HI")));
    CHECK(m.disk_file("HI.COM").size() < 2000);
}

#if PUGPUTER_HAVE_LWASM
TEST(cc1_output_assembles_alike_with_asm_and_lwasm) {
    for (const char* name : {"ops", "structs", "inits"}) {
        Machine m;
        CHECK(m.start("cc_lwasm.img", {test_file(std::string(name) + ".c")}));
        CHECK(m.compile(name));
        std::string dir = std::string(PUGPUTER_TEST_BUILD_DIR);
        std::string base = std::string("cc_") + name;
#ifdef _WIN32
        std::system(("mkdir \"" + dir + "\" >NUL 2>NUL").c_str());
        std::string cmd = "\"cd /d \"" + dir + "\" && \"" + LWASM_EXE_PATH + "\" " + base +
                          ".asm --6309 --format=obj --output=" + base + ".o >NUL 2>NUL\"";
#else
        std::system(("mkdir -p \"" + dir + "\"").c_str());
        std::string cmd = "cd \"" + dir + "\" && \"" + LWASM_EXE_PATH + "\" " + base +
                          ".asm --6309 --format=obj --output=" + base + ".o >/dev/null 2>&1";
#endif
        std::string asm_text = m.disk_file(upper(name) + ".ASM");
        CHECK(asm_text.size() > 1000);
        {
            std::ofstream o(dir + "/" + base + ".asm", std::ios::binary);
            o << asm_text;
        }
        CHECK(std::system(cmd.c_str()) == 0);
        CHECK(same((std::string(name) + ".o (lwasm and ASM)").c_str(), host_text(dir + "/" + base + ".o"),
                   m.disk_file(upper(name) + ".O")));
    }
}
#endif

TEST(cc1_reports_errors_and_writes_nothing) {
    // Each: CC1 stops at its first error, says where and what, and leaves no
    // .ASM.
    const std::pair<const char*, const char*> cases[] = {
        {"int main(void) { return x; }", "t.c:1: error: undeclared: 'x'"},
        {"int main(void) { int a a = 1; }", "t.c:1: error: expected ';'"},
        {"int f(int); int main(void) { return f(); }", "t.c:1: error: wrong number of arguments"},
        {"int main(void) { 3 = 4; return 0; }", "t.c:1: error: that can't be assigned to"},
        {"int main(void) { break; }", "t.c:1: error: break outside a loop or a switch"},
        {"int g = 1; int g = 2;", "t.c:1: error: redefinition of 'g'"},
        {"int main(void) { int *p; return p * 2; }", "t.c:1: error: an integer was expected"},
        {"int main(void) { char c; return *c; }", "t.c:1: error: a pointer was expected"},
        {"int main(void) {\ngoto nowhere;\n}", "t.c:3: error: label used but not defined: 'nowhere'"},
        {"int main(void) { int a; int a; return 0; }", "t.c:1: error: redeclared: 'a'"},
        {"void f(void) { return 1; }", "t.c:1: error: a value returned from a void function"},
        {"int main(void) {\nreturn 0;\n", "t.c:3: error: the file ends inside a block"},
        {"int main(void) { float f; }", "t.c:1: error: floating point is not supported yet"},
        {"struct s { int a; }; int f(struct s v) { return v.b; }", "t.c:1: error: no such member: 'b'"},
        {"int main(void) { int i; return i.x; }", "t.c:1: error: a struct or union was expected"},
        {"struct s { int a; char a; };", "t.c:1: error: duplicate member 'a'"},
        {"struct s { int a : 3; };", "t.c:1: error: bit-fields are not supported"},
        {"enum e { A }; struct e *p;", "t.c:1: error: used as the wrong kind of tag: 'e'"},
        {"struct s { int a; }; struct s { int b; };", "t.c:1: error: redefinition of 's'"},
        {"struct s; int main(void) { struct s v; return 0; }", "t.c:1: error: no size for 'v'"},
        {"struct s { int a; }; int main(void) { struct s v; return v + 1; }",
         "t.c:1: error: an integer was expected"},
        {"enum { A, B }; enum { B };", "t.c:1: error: redeclared: 'B'"},
        {"int main(void) {\nasm { nop\n", "t.c:2: error: the file ends inside asm { }"},
    };
    std::vector<pugputer::Fat16File> files;
    int n = 0;
    for (const auto& c : cases) files.push_back(file("T" + std::to_string(n++) + ".I", std::string("#line 1 \"t.c\"\n") + c.first + "\n"));
    Machine m;
    CHECK(m.start("cc_errors.img", files));
    n = 0;
    for (const auto& c : cases) {
        std::string name = "t" + std::to_string(n++);
        std::string cmd = "CC1 " + name + ".i";
        CHECK(same(c.first, std::string(c.second) + "\r\n", printed(m.run(cmd), cmd)));
        CHECK(m.disk_file(upper(name) + ".ASM") == "<none>");
    }
}
