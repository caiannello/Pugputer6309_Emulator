// PUGASM.COM (pugasm/), the Pugputer's own assembler, run on the emulated machine
// through the whole boot chain: it assembles the project's sources (the shell, the
// editor, DOS, BASIC and itself) and must produce exactly the bytes and the listing
// that lwasm did at build time. With lwasm on hand, it also has to match lwasm on
// test_asm/pugasm (every operation in every operand form, for each CPU, and the
// directives, macros and expressions). The rest: what it runs is runnable, errors
// are reported and leave no output, and the copy it makes of itself works.
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <iterator>
#include <string>
#include <vector>

#include "basic309_session.hpp"
#include "disk_images.hpp"
#include "fat16_reader.hpp"
#include "test_framework.hpp"

namespace {

bool read_host(const std::string& path, std::vector<uint8_t>& out) {
    std::ifstream f(path, std::ios::binary);
    if (!f) return false;
    out.assign((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
    return true;
}

std::string repo(const std::string& rel) { return std::string(REPO_DIR) + "/" + rel; }

// A host file for the disk, under an 8.3 name.
bool add(std::vector<pugputer::Fat16File>& files, const std::string& host, const std::string& name) {
    pugputer::Fat16File f;
    f.name = name;
    if (!read_host(host, f.data)) {
        std::fprintf(stderr, "  can't read %s\n", host.c_str());
        return false;
    }
    files.push_back(std::move(f));
    return true;
}

pugputer::Fat16File text(const std::string& name, const std::string& t) {
    pugputer::Fat16File f;
    f.name = name;
    f.data.assign(t.begin(), t.end());
    return f;
}

// pugasm's sources, as they go on a disk.
bool add_pugasm_sources(std::vector<pugputer::Fat16File>& files) {
    static const char* kParts[] = {"pugasm", "pa_util", "pa_heap", "pa_io", "pa_sym", "pa_expr",
                                   "pa_line", "pa_insn", "pa_dir", "pa_out", "pa_itab"};
    for (const char* p : kParts) {
        std::string up = p;
        for (char& c : up) c = static_cast<char>(std::toupper(static_cast<unsigned char>(c)));
        if (!add(files, repo(std::string("pugasm/") + p + ".asm"), up + ".ASM")) return false;
    }
    return true;
}

// A Pugputer with PUGASM.COM and `files` on a fresh disk, at the shell's prompt.
struct Machine {
    Basic309Session s;
    std::string img;

    bool start(const char* image_name, std::vector<pugputer::Fat16File> files) {
        if (!add(files, PUGASM_BIN_PATH, "PUGASM.COM")) return false;
        img = build_image(image_name, 32768, 4, std::move(files));
        return !img.empty() && s.boot_shell(PUGBIOS_S19_PATH, img.c_str());
    }
    // Types a shell command; what it printed up to the next prompt ("<<TIMEOUT>>"
    // if the prompt never came back).
    std::string run(const std::string& cmd, uint64_t budget = 20000000000ull) {
        s.received.clear();
        for (char c : cmd) s.send_byte(static_cast<uint8_t>(c));
        s.send_byte('\r');
        uint64_t spent = 0;
        while (spent < budget) {
            spent += s.bus.run(20000);
            const std::string& r = s.received;
            if (r.size() > cmd.size() + 2 && r.compare(r.size() - 2, 2, "> ") == 0) return r;
        }
        return "<<TIMEOUT>>";
    }
    // A file on the disk ("<none>" if it isn't there).
    std::string file(const std::string& name) const {
        Fat16Volume v;
        if (!v.load(img.c_str())) return "<no image>";
        Fat16Volume::Entry e;
        if (!v.find(name, e)) return "<none>";
        std::vector<uint8_t> d = v.read(e);
        return std::string(d.begin(), d.end());
    }
};

std::string host_text(const std::string& path) {
    std::vector<uint8_t> d;
    if (!read_host(path, d)) return "<unreadable " + path + ">";
    return std::string(d.begin(), d.end());
}

std::string no_cr(std::string t) {
    std::string o;
    for (char c : t)
        if (c != '\r') o += c;
    return o;
}

// S-records without the S0 (header) record, which names the tool that made them.
std::string no_s0(const std::string& t) {
    std::string o, line;
    for (size_t i = 0; i < t.size();) {
        size_t e = t.find('\n', i);
        if (e == std::string::npos) e = t.size();
        line = t.substr(i, e - i);
        if (line.compare(0, 2, "S0") != 0) o += line + "\n";
        i = e + 1;
    }
    return o;
}

// Where two texts first differ (for the failure message).
void show_difference(const char* what, const std::string& a, const std::string& b) {
    size_t i = 0;
    while (i < a.size() && i < b.size() && a[i] == b[i]) ++i;
    size_t ls = a.rfind('\n', i == 0 ? 0 : i - 1);
    ls = ls == std::string::npos ? 0 : ls + 1;
    std::fprintf(stderr, "  %s differs at byte %zu (sizes %zu, %zu):\n    expected: %s\n    got:      %s\n", what, i,
                 a.size(), b.size(), a.substr(ls, a.find('\n', i) - ls).c_str(),
                 b.substr(ls, b.find('\n', i) - ls).c_str());
}

bool same(const char* what, const std::string& expected, const std::string& got) {
    if (expected == got) return true;
    show_difference(what, expected, got);
    return false;
}

// Assembles `src` (already on the disk as SRC) and compares the output and the
// listing with lwasm's (`bin`, `lst`, from the build).
void check_like_lwasm(Machine& m, const std::string& src, const std::string& stem, const std::string& bin,
                      const std::string& lst) {
    std::string out = m.run("PUGASM -o " + stem + ".BIN -l" + stem + ".LST -s " + src);
    CHECK(out.find("error") == std::string::npos);
    CHECK(same((src + " output").c_str(), host_text(bin), m.file(stem + ".BIN")));
    CHECK(same((src + " listing").c_str(), no_cr(host_text(lst)), no_cr(m.file(stem + ".LST"))));
}

#if PUGPUTER_HAVE_LWASM
// lwasm on a test_asm/pugasm source (copied into the build directory, so the
// listing names it the same way), then pugasm on the same source.
void check_against_lwasm(const char* name, bool m6809) {
    std::string dir = std::string(PUGPUTER_TEST_BUILD_DIR) + "/pugasm";
#ifdef _WIN32
    std::string mk = "mkdir \"" + dir + "\" >NUL 2>NUL";
#else
    std::string mk = "mkdir -p \"" + dir + "\"";
#endif
    std::system(mk.c_str());
    std::string src = std::string(PUGPUTER_TEST_ASM_DIR) + "/pugasm/" + name;
    std::string body = host_text(src);
    {
        std::ofstream o(dir + "/" + name, std::ios::binary);
        o << body;
    }
    std::string cmd = std::string("cd \"") + dir + "\" && \"" + LWASM_EXE_PATH + "\" " + name +
                      (m6809 ? " --6809" : " --6309") + " --format=raw --output=lw.bin --list=lw.lst --symbols";
#ifdef _WIN32
    cmd = "cd /d \"" + dir + "\" && \"" + LWASM_EXE_PATH + "\" " + name + (m6809 ? " --6809" : " --6309") +
          " --format=raw --output=lw.bin --list=lw.lst --symbols";
    cmd = "\"" + cmd + "\"";
#endif
    CHECK(std::system(cmd.c_str()) == 0);

    std::string up = name;
    for (char& c : up) c = static_cast<char>(std::toupper(static_cast<unsigned char>(c)));
    Machine m;
    CHECK(m.start("pugasm_ops.img", {text(up, body)}));
    std::string out = m.run(std::string("PUGASM ") + (m6809 ? "-9 " : "") + "-o T.BIN -lT.LST -s " + name);
    CHECK(out.find("error") == std::string::npos);
    CHECK(same((std::string(name) + " output").c_str(), host_text(dir + "/lw.bin"), m.file("T.BIN")));
    CHECK(same((std::string(name) + " listing").c_str(), no_cr(host_text(dir + "/lw.lst")), no_cr(m.file("T.LST"))));
}
#endif

} // namespace

TEST(pugasm_assembles_the_shell_editor_and_dos_like_lwasm) {
    std::vector<pugputer::Fat16File> files;
    CHECK(add(files, repo("shell/shell.asm"), "SHELL.ASM"));
    CHECK(add(files, repo("edit/edit.asm"), "EDIT.ASM"));
    CHECK(add(files, repo("dos/dos.asm"), "DOS.ASM"));
    CHECK(add(files, BIOS_DEFINES_PATH, "DEFINES.D"));
    Machine m;
    CHECK(m.start("pugasm_progs.img", files));
    check_like_lwasm(m, "shell.asm", "SHELL", repo("shell/shell.bin"), repo("shell/shell.lst"));
    check_like_lwasm(m, "edit.asm", "EDIT", EDIT_BIN_PATH, EDIT_LST_PATH);
    check_like_lwasm(m, "dos.asm", "DOS", DOS_BIN_PATH, DOS_LST_PATH);
}

TEST(pugasm_assembles_basic_as_s_records_like_lwasm) {
    std::vector<pugputer::Fat16File> files;
    CHECK(add(files, repo("basic309/exbasrom309.asm"), "EXBAS.ASM"));
    Machine m;
    CHECK(m.start("pugasm_basic.img", files));
    std::string out = m.run("PUGASM -f srec -o EXBAS.S19 -l -s exbas.asm");
    CHECK(out.find("error") == std::string::npos);
    CHECK(same("BASIC's S-records", no_s0(no_cr(host_text(EXBASROM309_S19_PATH))), no_s0(no_cr(m.file("EXBAS.S19")))));
    CHECK(m.file("EXBAS.S19").compare(0, 2, "S0") == 0);
    // (the listing names the source as it was given: exbas.asm here)
    std::string lst = no_cr(host_text(EXBASROM309_LST_PATH));
    const std::string from = "(  exbasrom309.asm)", to = "(        exbas.asm)";
    for (size_t k = 0; (k = lst.find(from, k)) != std::string::npos; k += to.size()) lst.replace(k, from.size(), to);
    CHECK(same("BASIC's listing", lst, no_cr(m.file("EXBAS.LST"))));
}

TEST(pugasm_assembles_itself_and_the_copy_works) {
    std::vector<pugputer::Fat16File> files;
    CHECK(add_pugasm_sources(files));
    CHECK(add(files, BIOS_DEFINES_PATH, "DEFINES.D"));
    CHECK(add(files, repo("shell/shell.asm"), "SHELL.ASM"));
    Machine m;
    CHECK(m.start("pugasm_self.img", files));
    // Its own source (which carries its program header): raw output is PUGASM.COM.
    std::string out = m.run("PUGASM -o PUGASM2.COM -lPUGASM.LST -s pugasm.asm");
    CHECK(out.find("error") == std::string::npos);
    CHECK(same("pugasm's own output", host_text(PUGASM_BIN_PATH), m.file("PUGASM2.COM")));
    CHECK(same("pugasm's own listing", no_cr(host_text(repo("pugasm/pugasm.lst"))), no_cr(m.file("PUGASM.LST"))));
    // The copy, run: it makes the same copy again, and assembles the shell.
    out = m.run("PUGASM2 -o PUGASM3.COM pugasm.asm");
    CHECK(out.find("error") == std::string::npos);
    CHECK(same("the copy's copy", host_text(PUGASM_BIN_PATH), m.file("PUGASM3.COM")));
    out = m.run("PUGASM3 -o SHELL.BIN shell.asm");
    CHECK(same("the shell by the copy", host_text(repo("shell/shell.bin")), m.file("SHELL.BIN")));
}

TEST(pugasm_makes_programs_that_run) {
    Machine m;
    CHECK(m.start("pugasm_run.img",
                  {text("HELLO.ASM", "* A program for the shell to run\n"
                                     "        INCLUDE defines.d\n"
                                     "        ORG     $4000\n"
                                     "msg     FCC     /Hello from pugasm/\n"
                                     "        FCB     13,10,0\n"
                                     "start   LDB     #F_STDOUT\n"
                                     "        LDX     #msg\n"
                                     "        LDA     #B_PUTS\n"
                                     "        SWI2\n"
                                     "        LDA     #B_EXIT\n"
                                     "        SWI2\n"
                                     "        END     start\n")}));
    // defines.d isn't on this disk: the INCLUDE fails, and nothing is written.
    std::string out = m.run("PUGASM -f com hello.asm");
    CHECK(out.find("defines.d") != std::string::npos);
    CHECK(m.file("HELLO.COM") == "<none>");

    std::vector<pugputer::Fat16File> files;
    CHECK(add(files, BIOS_DEFINES_PATH, "DEFINES.D"));
    files.push_back(text("HELLO.ASM", "        INCLUDE defines.d\n"
                                      "        ORG     $4000\n"
                                      "msg     FCC     /Hello from pugasm/\n"
                                      "        FCB     13,10,0\n"
                                      "start   LDB     #F_STDOUT\n"
                                      "        LDX     #msg\n"
                                      "        LDA     #B_PUTS\n"
                                      "        SWI2\n"
                                      "        LDA     #B_EXIT\n"
                                      "        SWI2\n"
                                      "        END     start\n"));
    Machine m2;
    CHECK(m2.start("pugasm_run2.img", files));
    out = m2.run("PUGASM -f com hello.asm");
    CHECK(out.find("error") == std::string::npos);
    std::string com = m2.file("HELLO.COM");
    // The header: "PX", load $4000, entry `start` ($4000 + 20), flags 0.
    CHECK(com.size() == 8 + 20 + 13);
    CHECK(com.compare(0, 8, std::string("PX\x40\x00\x40\x14\x00\x00", 8)) == 0);
    out = m2.run("HELLO");
    CHECK(out.find("Hello from pugasm") != std::string::npos);
    // S-records and a raw file of the same program.
    out = m2.run("PUGASM -fsrec -o HELLO.S19 hello.asm");
    std::string s19 = m2.file("HELLO.S19");
    CHECK(s19.find("S1") != std::string::npos);
    CHECK(s19.find("S9034014A8") != std::string::npos);
    out = m2.run("PUGASM hello.asm");
    CHECK(m2.file("HELLO.BIN") == com.substr(8));
}

TEST(pugasm_builds_the_demo_program) {
    std::vector<pugputer::Fat16File> files;
    CHECK(add(files, std::string(DEMO_DIR) + "/GREET.ASM", "GREET.ASM"));
    Machine m;
    CHECK(m.start("pugasm_demo.img", files));
    std::string out = m.run("PUGASM -f com greet.asm");
    CHECK(out.find("error") == std::string::npos);
    CHECK(m.run("GREET Ada").find("Hello, Ada!") != std::string::npos);
    CHECK(m.run("GREET").find("Hello, world!") != std::string::npos);
}

TEST(pugasm_reports_errors_and_writes_nothing) {
    Machine m;
    CHECK(m.start("pugasm_errs.img",
                  {text("ERRS.ASM", "        ORG     $1000\n"
                                    "        LDA     #1,\n"
                                    "        FOO     1\n"
                                    "        FCB     1/0\n"
                                    "dup     NOP\n"
                                    "dup     NOP\n"
                                    "        PSHS    Q\n"
                                    "        LDA     #$123\n"
                                    "        LDA     undefd\n"
                                    "        END\n"),
                   text("CPU.ASM", "        LDW     #1\n"
                                   "        LDA     #1\n"),
                   text("OK.ASM", "        LDA     #1\n")}));
    std::string out = m.run("PUGASM -l errs.asm");
    CHECK(out.find("errs.asm(2) : ERROR : Bad operand") != std::string::npos);
    CHECK(out.find("errs.asm(3) : ERROR : Bad opcode") != std::string::npos);
    CHECK(out.find("errs.asm(4) : ERROR : Division by zero") != std::string::npos);
    CHECK(out.find("errs.asm(6) : ERROR : Multiply defined symbol") != std::string::npos);
    CHECK(out.find("errs.asm(7) : ERROR : Bad register") != std::string::npos);
    CHECK(out.find("errs.asm(8) : ERROR : Byte overflow") != std::string::npos);
    CHECK(out.find("errs.asm(9) : ERROR : Undefined symbol") != std::string::npos);
    CHECK(out.find("Not doing output due to assembly errors.") != std::string::npos);
    CHECK(m.file("ERRS.BIN") == "<none>");
    CHECK(m.file("ERRS.LST") == "<none>"); // (nor a listing, as with lwasm)

    out = m.run("PUGASM -9 cpu.asm");
    CHECK(out.find("cpu.asm(1) : ERROR : Illegal use of 6309 instruction in 6809 mode") != std::string::npos);
    CHECK(m.file("CPU.BIN") == "<none>");
    out = m.run("PUGASM cpu.asm");
    CHECK(out.find("ERROR") == std::string::npos);
    CHECK(m.file("CPU.BIN") == std::string("\x10\x86\x00\x01\x86\x01", 6));

    out = m.run("PUGASM nosuch.asm");
    CHECK(out.find("nosuch.asm") != std::string::npos);
    out = m.run("PUGASM");
    CHECK(out.find("Usage: PUGASM") != std::string::npos);
    out = m.run("PUGASM -f bogus ok.asm");
    CHECK(out.find("Invalid output format") != std::string::npos);
    CHECK(m.file("OK.BIN") == "<none>");
}

#if PUGPUTER_HAVE_LWASM
TEST(pugasm_matches_lwasm_on_every_6309_operation) { check_against_lwasm("allops.asm", false); }
TEST(pugasm_matches_lwasm_on_every_6809_operation) { check_against_lwasm("allops9.asm", true); }
TEST(pugasm_matches_lwasm_on_directives_macros_and_expressions) { check_against_lwasm("feat.asm", false); }
#endif
