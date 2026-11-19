// ASM.COM and LINK.COM (asmlink/), the Pugputer's own assembler and linker,
// run on the emulated machine through the whole boot chain. ASM assembles the
// project's sources (the shell, the editor, DOS, BASIC, itself, LINK, and the
// BIOS's modules as object files) and must produce exactly the bytes and listings
// lwasm did at build time; LINK links the BIOS to exactly lwlink's S-records
// and map -- and the two build the whole BIOS on the Pugputer. With lwtools on
// hand, they also have to match lwasm and lwlink on test_asm/asmlink (every
// operation in every operand form, for each CPU; directives, macros and
// expressions; object files; links with the default and other scripts). The
// rest: what they make runs, errors are reported and leave no output, and the
// copy ASM makes of itself works. AR makes lwar's archives, and LINK links
// libraries (-L, -l, and archives named as files) exactly as lwlink does.
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <iterator>
#include <string>
#include <utility>
#include <vector>

#include "basic309_session.hpp"
#include "disk_images.hpp"
#include "pugputer/c_library.hpp"
#include "pugputer/demo_sources.hpp"
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

// ASM's sources, as they go on a disk.
bool add_asm_sources(std::vector<pugputer::Fat16File>& files) {
    static const char* kParts[] = {"asm", "pa_util", "pa_heap", "pa_io", "pa_strm", "pa_sym", "pa_expr",
                                   "pa_line", "pa_insn", "pa_dir", "pa_out", "pa_obj", "pa_itab"};
    for (const char* p : kParts) {
        std::string up = p;
        for (char& c : up) c = static_cast<char>(std::toupper(static_cast<unsigned char>(c)));
        if (!add(files, repo(std::string("asmlink/") + p + ".asm"), up + ".ASM")) return false;
    }
    return true;
}

// A Pugputer with ASM.COM and `files` on a fresh disk, at the shell's prompt.
struct Machine {
    Basic309Session s;
    std::string img;

    bool start(const char* image_name, std::vector<pugputer::Fat16File> files) {
        if (!add(files, ASM_BIN_PATH, "ASM.COM")) return false;
        if (!add(files, LINK_BIN_PATH, "LINK.COM")) return false;
        if (!add(files, AR_BIN_PATH, "AR.COM")) return false;
        img = build_image(image_name, 32768, 4, std::move(files));
        return !img.empty() && s.boot_shell(PUGBIOS_S19_PATH, img.c_str());
    }
    // Types a shell command; what it printed up to the next prompt ("<<TIMEOUT>>"
    // if the prompt never came back).
    uint64_t cycles = 0; // what the last run() took
    std::string run(const std::string& cmd, uint64_t budget = 20000000000ull) {
        s.received.clear();
        for (char c : cmd) s.send_byte(static_cast<uint8_t>(c));
        s.send_byte('\r');
        uint64_t spent = 0;
        while (spent < budget) {
            spent += s.bus.run(20000);
            cycles = spent;
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
    std::string out = m.run("ASM -o " + stem + ".BIN -l" + stem + ".LST -s " + src);
    CHECK(out.find("error") == std::string::npos);
    CHECK(same((src + " output").c_str(), host_text(bin), m.file(stem + ".BIN")));
    CHECK(same((src + " listing").c_str(), no_cr(host_text(lst)), no_cr(m.file(stem + ".LST"))));
}

// The BIOS's modules, as the link wants them (a response file: the command
// line is too short for them all).
const char* const kBiosModules[] = {"helpers", "devio", "serio", "sdcard", "time", "loader", "banks", "main"};
const char* const kBiosRsp = "-f srec -o PUGBIOS.S19 -m PUGBIOS.MAP -s LINK.SCR\r\n"
                             "helpers.o devio.o serio.o sdcard.o time.o loader.o banks.o main.o\r\n";

std::string upper(std::string s) {
    for (char& c : s) c = static_cast<char>(std::toupper(static_cast<unsigned char>(c)));
    return s;
}

// An archive as lwar makes it: "LWAR1V", each member's name, a NUL, its length
// (32 bits, high byte first) and its bytes, then a NUL.
using Members = std::vector<std::pair<std::string, std::string>>;
std::string lwar(const Members& members) {
    std::string a = "LWAR1V";
    for (const auto& m : members) {
        a += m.first;
        a += '\0';
        uint32_t n = static_cast<uint32_t>(m.second.size());
        for (int sh = 24; sh >= 0; sh -= 8) a += static_cast<char>((n >> sh) & 0xFF);
        a += m.second;
    }
    a += '\0';
    return a;
}

#if PUGPUTER_HAVE_LWASM
// A scratch directory in the build directory for the host tools' output.
std::string host_dir() {
    std::string dir = std::string(PUGPUTER_TEST_BUILD_DIR) + "/asmlink";
#ifdef _WIN32
    std::string mk = "mkdir \"" + dir + "\" >NUL 2>NUL";
#else
    std::string mk = "mkdir -p \"" + dir + "\"";
#endif
    std::system(mk.c_str());
    return dir;
}
// Runs a host tool in `dir`: true if it succeeded.
bool host_run(const std::string& dir, const char* exe, const std::string& args) {
#ifdef _WIN32
    std::string cmd = "\"cd /d \"" + dir + "\" && \"" + exe + "\" " + args + " >NUL 2>NUL\"";
#else
    std::string cmd = "cd \"" + dir + "\" && \"" + exe + "\" " + args + " >/dev/null 2>&1";
#endif
    return std::system(cmd.c_str()) == 0;
}
// A test_asm/asmlink file: its text, and a copy in `dir`.
std::string test_source(const std::string& dir, const std::string& name) {
    std::string body = host_text(std::string(PUGPUTER_TEST_ASM_DIR) + "/asmlink/" + name);
    std::ofstream o(dir + "/" + name, std::ios::binary);
    o << body;
    return body;
}
// lwasm on a test_asm/asmlink source (copied into the build directory, so the
// listing names it the same way), then ASM on the same source: the same
// output (raw or an object file) and listing.
void check_against_lwasm(const char* name, bool m6809, bool obj = false) {
    std::string dir = host_dir();
    std::string body = test_source(dir, name);
    CHECK(host_run(dir, LWASM_EXE_PATH, std::string(name) + (m6809 ? " --6809" : " --6309") +
                                            (obj ? " --format=obj" : " --format=raw") +
                                            " --output=lw.bin --list=lw.lst --symbols"));
    Machine m;
    CHECK(m.start("asm_ops.img", {text(upper(name), body)}));
    std::string out = m.run(std::string("ASM ") + (m6809 ? "-9 " : "") + (obj ? "-f obj " : "") +
                            "-o T.BIN -lT.LST -s " + name);
    CHECK(out.find("error") == std::string::npos);
    CHECK(same((std::string(name) + " output").c_str(), host_text(dir + "/lw.bin"), m.file("T.BIN")));
    CHECK(same((std::string(name) + " listing").c_str(), no_cr(host_text(dir + "/lw.lst")), no_cr(m.file("T.LST"))));
}
#endif

#if PUGPUTER_HAVE_LWASM
// objf.asm and prov.asm (test_asm/asmlink) as objects by lwasm, linked by lwlink
// and by LINK with the same arguments (`files`: other test_asm/asmlink files
// they need): the same output and map.
void check_link(const std::string& args, const std::string& out, const std::vector<std::string>& files = {}) {
    if (!std::ifstream(LWLINK_EXE_PATH)) {
        std::printf("  (no lwlink: skipped)\n");
        return;
    }
    std::string dir = host_dir();
    std::vector<pugputer::Fat16File> disk;
    for (const char* src : {"objf", "prov"}) {
        test_source(dir, std::string(src) + ".asm");
        CHECK(host_run(dir, LWASM_EXE_PATH, std::string(src) + ".asm --6309 --format=obj --output=" + src + ".o"));
        CHECK(add(disk, dir + "/" + src + ".o", upper(src) + ".O"));
    }
    for (const auto& f : files) {
        test_source(dir, f);
        CHECK(add(disk, dir + "/" + f, upper(f)));
    }
    std::remove((dir + "/" + out).c_str());
    std::remove((dir + "/OUT.MAP").c_str());
    CHECK(host_run(dir, LWLINK_EXE_PATH, args + " -o " + out + " -m OUT.MAP objf.o prov.o"));
    disk.push_back(text("ARGS.RSP", args + " -o " + out + " -m OUT.MAP objf.o prov.o\r\n"));
    Machine m;
    CHECK(m.start("link_cmp.img", disk));
    std::string said = m.run("LINK @args.rsp");
    CHECK(same(("the output of: " + args).c_str(), host_text(dir + "/" + out), m.file(upper(out))));
    CHECK(same(("the map of: " + args).c_str(), no_cr(host_text(dir + "/OUT.MAP")), no_cr(m.file("OUT.MAP"))));
}
#endif

} // namespace

TEST(asm_assembles_the_shell_editor_and_dos_like_lwasm) {
    std::vector<pugputer::Fat16File> files;
    CHECK(add(files, repo("shell/shell.asm"), "SHELL.ASM"));
    CHECK(add(files, repo("edit/edit.asm"), "EDIT.ASM"));
    CHECK(add(files, repo("dos/dos.asm"), "DOS.ASM"));
    CHECK(add(files, BIOS_DEFINES_PATH, "DEFINES.D"));
    Machine m;
    CHECK(m.start("asm_progs.img", files));
    check_like_lwasm(m, "shell.asm", "SHELL", repo("shell/shell.bin"), repo("shell/shell.lst"));
    check_like_lwasm(m, "edit.asm", "EDIT", EDIT_BIN_PATH, EDIT_LST_PATH);
    check_like_lwasm(m, "dos.asm", "DOS", DOS_BIN_PATH, DOS_LST_PATH);
}

TEST(asm_assembles_basic_as_s_records_like_lwasm) {
    std::vector<pugputer::Fat16File> files;
    CHECK(add(files, repo("basic309/exbasrom309.asm"), "EXBAS.ASM"));
    Machine m;
    CHECK(m.start("asm_basic.img", files));
    std::string out = m.run("ASM -f srec -o EXBAS.S19 -l -s exbas.asm");
    CHECK(out.find("error") == std::string::npos);
    CHECK(same("BASIC's S-records", no_s0(no_cr(host_text(EXBASROM309_S19_PATH))), no_s0(no_cr(m.file("EXBAS.S19")))));
    CHECK(m.file("EXBAS.S19").compare(0, 2, "S0") == 0);
    // (the listing names the source as it was given: exbas.asm here)
    std::string lst = no_cr(host_text(EXBASROM309_LST_PATH));
    const std::string from = "(  exbasrom309.asm)", to = "(        exbas.asm)";
    for (size_t k = 0; (k = lst.find(from, k)) != std::string::npos; k += to.size()) lst.replace(k, from.size(), to);
    CHECK(same("BASIC's listing", lst, no_cr(m.file("EXBAS.LST"))));
}

TEST(asm_rebuilds_every_program_from_the_demo_disk_sources) {
    // The sources as the demo disk has them in /ASM (mkdiskimg --sources), rebuilt with
    // the commands /ASM/README.TXT gives: each program comes out as it was built.
    std::vector<pugputer::Fat16File> files;
    for (const auto& src : pugputer::kDemoSources) CHECK(add(files, repo(src.repo), src.disk));
    Machine m;
    CHECK(m.start("asm_sources.img", files));
    m.run("PATH /"); // (ASM.COM and LINK.COM are in the root on this disk)
    m.run("CD /ASM");
    struct Build {
        const char* cmd;
        const char* out;
        std::string built;
    };
    std::vector<uint8_t> image(65536, 0);
    CHECK(pugputer::load_srec_file(EXBASROM309_S19_PATH, image.data(), image.size()).ok);
    std::string basic_com = std::string{'P', 'X', static_cast<char>(pugputer::kBasicLoad >> 8),
                                        static_cast<char>(pugputer::kBasicLoad & 0xFF), '\xC0', 0, 0, 0} +
                            std::string(image.begin() + pugputer::kBasicLoad, image.begin() + 0xF000);
    for (const Build& b : {Build{"ASM -o SHELL.COM shell.asm", "/ASM/SHELL.COM", host_text(repo("shell/shell.bin"))},
                           Build{"ASM -o EDIT.COM edit.asm", "/ASM/EDIT.COM", host_text(EDIT_BIN_PATH)},
                           Build{"ASM -o HEXDUMP.COM hexdump.asm", "/ASM/HEXDUMP.COM", host_text(HEXDUMP_BIN_PATH)},
                           Build{"ASM -o MOVE.COM move.asm", "/ASM/MOVE.COM", host_text(MOVE_BIN_PATH)},
                           Build{"ASM -o BASIC.COM basiccom.asm", "/ASM/BASIC.COM", basic_com}}) {
        std::string out = m.run(b.cmd);
        CHECK(out.find("ERROR") == std::string::npos);
        CHECK(same(b.out, b.built, m.file(b.out)));
        if (std::getenv("ASM_TIMING")) std::printf("  %s: %.1f s at 3.58 MHz\n", b.cmd, m.cycles / 3.58e6);
    }
    m.run("CD ASMLINK");
    CHECK(m.run("ASM -o ASM.COM asm.asm").find("ERROR") == std::string::npos);
    CHECK(same("/ASM/ASMLINK/ASM.COM", host_text(ASM_BIN_PATH), m.file("/ASM/ASMLINK/ASM.COM")));
    CHECK(m.run("ASM -o LINK.COM link.asm").find("ERROR") == std::string::npos);
    CHECK(same("/ASM/ASMLINK/LINK.COM", host_text(LINK_BIN_PATH), m.file("/ASM/ASMLINK/LINK.COM")));
    CHECK(m.run("ASM -o AR.COM ar.asm").find("ERROR") == std::string::npos);
    CHECK(same("/ASM/ASMLINK/AR.COM", host_text(AR_BIN_PATH), m.file("/ASM/ASMLINK/AR.COM")));
    // The C library: each part as lwasm made it, and AR's LIBC.A as mkdiskimg's.
    {
        std::vector<pugputer::Fat16File> lib;
        std::string error;
        CHECK(pugputer::c_library_files(REPO_DIR, lib, error));
        m.run("CD /ASM/LIBC");
        std::string rsp = host_text(repo("cc/lib/libc.rsp"));
        std::vector<std::string> mods = {"crt0"};
        for (size_t i = 0, e; i < rsp.size(); i = e + 1) {
            e = rsp.find('\n', i);
            if (e == std::string::npos) e = rsp.size();
            std::string w = rsp.substr(i, e - i);
            while (!w.empty() && (w.back() == '\r' || w.back() == ' ')) w.pop_back();
            if (w.size() > 2 && w.compare(w.size() - 2, 2, ".o") == 0) mods.push_back(w.substr(0, w.size() - 2));
        }
        for (const std::string& mod : mods) {
            CHECK(m.run("ASM -f obj " + mod + ".asm").find("ERROR") == std::string::npos);
            CHECK(same(("/ASM/LIBC/" + upper(mod) + ".O").c_str(), host_text(repo("cc/lib/" + mod + ".o")),
                       m.file("/ASM/LIBC/" + upper(mod) + ".O")));
        }
        m.run("AR @libc.rsp");
        for (const auto& f : lib)
            if (f.name == "LIB/LIBC.A")
                CHECK(same("/ASM/LIBC/LIBC.A", std::string(f.data.begin(), f.data.end()), m.file("/ASM/LIBC/LIBC.A")));
        m.run("CD /ASM/ASMLINK"); // (where the rest expects to be)
    }
    // The C compiler's two programs.
    m.run("CD /ASM/CC");
    for (const char* prog : {"cpp", "cc1"}) {
        std::string cmd = std::string("ASM -o ") + upper(prog) + ".COM " + prog + ".asm";
        CHECK(m.run(cmd).find("ERROR") == std::string::npos);
        std::string built = "/ASM/CC/" + upper(prog) + ".COM";
        CHECK(same(built.c_str(), host_text(repo(std::string("cc/") + prog + ".bin")), m.file(built)));
        if (std::getenv("ASM_TIMING")) std::printf("  %s: %.1f s at 3.58 MHz\n", cmd.c_str(), m.cycles / 3.58e6);
    }
    m.run("CD /ASM/ASMLINK");
    // A new program runs from where it was made, ahead of the search path.
    m.run("CD ..");
    CHECK(m.run("HEXDUMP basiccom.asm").find("000000  2A 20 42 41 53 49 43 43") != std::string::npos);
    m.run("CD GAMEKIT");
    CHECK(m.run("ASM -o TILEKIT.COM tilekit.asm").find("ERROR") == std::string::npos);
    CHECK(same("/ASM/GAMEKIT/TILEKIT.COM", host_text(repo("gamekit/build/tilekit.bin")),
               m.file("/ASM/GAMEKIT/TILEKIT.COM")));
    CHECK(m.run("ASM -o SONGPLAY.COM songplay.asm").find("ERROR") == std::string::npos);
    CHECK(same("/ASM/GAMEKIT/SONGPLAY.COM", host_text(repo("gamekit/build/songplay.bin")),
               m.file("/ASM/GAMEKIT/SONGPLAY.COM")));
    CHECK(m.run("ASM -o SONGKIT.COM songkit.asm").find("ERROR") == std::string::npos);
    CHECK(same("/ASM/GAMEKIT/SONGKIT.COM", host_text(repo("gamekit/build/songkit.bin")),
               m.file("/ASM/GAMEKIT/SONGKIT.COM")));
}

TEST(asm_assembles_itself_and_the_copy_works) {
    std::vector<pugputer::Fat16File> files;
    CHECK(add_asm_sources(files));
    CHECK(add(files, BIOS_DEFINES_PATH, "DEFINES.D"));
    CHECK(add(files, repo("shell/shell.asm"), "SHELL.ASM"));
    Machine m;
    CHECK(m.start("asm_self.img", files));
    // Its own source (which carries its program header): raw output is ASM.COM.
    std::string out = m.run("ASM -o ASM2.COM -lASM.LST -s asm.asm");
    CHECK(out.find("error") == std::string::npos);
    CHECK(same("ASM's own output", host_text(ASM_BIN_PATH), m.file("ASM2.COM")));
    CHECK(same("ASM's own listing", no_cr(host_text(repo("asmlink/asm.lst"))), no_cr(m.file("ASM.LST"))));
    // The copy, run: it makes the same copy again, and assembles the shell.
    out = m.run("ASM2 -o ASM3.COM asm.asm");
    CHECK(out.find("error") == std::string::npos);
    CHECK(same("the copy's copy", host_text(ASM_BIN_PATH), m.file("ASM3.COM")));
    out = m.run("ASM3 -o SHELL.BIN shell.asm");
    CHECK(same("the shell by the copy", host_text(repo("shell/shell.bin")), m.file("SHELL.BIN")));
}

TEST(asm_makes_programs_that_run) {
    Machine m;
    CHECK(m.start("asm_run.img",
                  {text("HELLO.ASM", "* A program for the shell to run\n"
                                     "        INCLUDE defines.d\n"
                                     "        ORG     $4000\n"
                                     "msg     FCC     /Assembled by ASM!/\n"
                                     "        FCB     13,10,0\n"
                                     "start   LDB     #F_STDOUT\n"
                                     "        LDX     #msg\n"
                                     "        LDA     #B_PUTS\n"
                                     "        SWI2\n"
                                     "        LDA     #B_EXIT\n"
                                     "        SWI2\n"
                                     "        END     start\n")}));
    // defines.d isn't on this disk: the INCLUDE fails, and nothing is written.
    std::string out = m.run("ASM -f com hello.asm");
    CHECK(out.find("defines.d") != std::string::npos);
    CHECK(m.file("HELLO.COM") == "<none>");

    std::vector<pugputer::Fat16File> files;
    CHECK(add(files, BIOS_DEFINES_PATH, "DEFINES.D"));
    files.push_back(text("HELLO.ASM", "        INCLUDE defines.d\n"
                                      "        ORG     $4000\n"
                                      "msg     FCC     /Assembled by ASM!/\n"
                                      "        FCB     13,10,0\n"
                                      "start   LDB     #F_STDOUT\n"
                                      "        LDX     #msg\n"
                                      "        LDA     #B_PUTS\n"
                                      "        SWI2\n"
                                      "        LDA     #B_EXIT\n"
                                      "        SWI2\n"
                                      "        END     start\n"));
    Machine m2;
    CHECK(m2.start("asm_run2.img", files));
    out = m2.run("ASM -f com hello.asm");
    CHECK(out.find("error") == std::string::npos);
    std::string com = m2.file("HELLO.COM");
    // The header: "PX", load $4000, entry `start` ($4000 + 20), flags 0.
    CHECK(com.size() == 8 + 20 + 13);
    CHECK(com.compare(0, 8, std::string("PX\x40\x00\x40\x14\x00\x00", 8)) == 0);
    out = m2.run("HELLO");
    CHECK(out.find("Assembled by ASM!") != std::string::npos);
    // S-records and a raw file of the same program.
    out = m2.run("ASM -fsrec -o HELLO.S19 hello.asm");
    std::string s19 = m2.file("HELLO.S19");
    CHECK(s19.find("S1") != std::string::npos);
    CHECK(s19.find("S9034014A8") != std::string::npos);
    out = m2.run("ASM hello.asm");
    CHECK(m2.file("HELLO.BIN") == com.substr(8));
}

TEST(asm_builds_the_demo_program) {
    std::vector<pugputer::Fat16File> files;
    CHECK(add(files, std::string(DEMO_DIR) + "/ASM/GREET.ASM", "GREET.ASM"));
    Machine m;
    CHECK(m.start("asm_demo.img", files));
    std::string out = m.run("ASM -f com greet.asm");
    CHECK(out.find("error") == std::string::npos);
    CHECK(m.run("GREET Ada").find("Hello, Ada!") != std::string::npos);
    CHECK(m.run("GREET").find("Hello, world!") != std::string::npos);
}

TEST(asm_reports_errors_and_writes_nothing) {
    Machine m;
    CHECK(m.start("asm_errs.img",
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
    std::string out = m.run("ASM -l errs.asm");
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

    out = m.run("ASM -9 cpu.asm");
    CHECK(out.find("cpu.asm(1) : ERROR : Illegal use of 6309 instruction in 6809 mode") != std::string::npos);
    CHECK(m.file("CPU.BIN") == "<none>");
    out = m.run("ASM cpu.asm");
    CHECK(out.find("ERROR") == std::string::npos);
    CHECK(m.file("CPU.BIN") == std::string("\x10\x86\x00\x01\x86\x01", 6));

    out = m.run("ASM nosuch.asm");
    CHECK(out.find("nosuch.asm") != std::string::npos);
    out = m.run("ASM");
    CHECK(out.find("Usage: ASM") != std::string::npos);
    out = m.run("ASM -f bogus ok.asm");
    CHECK(out.find("Invalid output format") != std::string::npos);
    CHECK(m.file("OK.BIN") == "<none>");
}

#if PUGPUTER_HAVE_LWASM
TEST(asm_matches_lwasm_on_every_6309_operation) { check_against_lwasm("allops.asm", false); }
TEST(asm_matches_lwasm_on_every_6809_operation) { check_against_lwasm("allops9.asm", true); }
TEST(asm_matches_lwasm_on_directives_macros_and_expressions) { check_against_lwasm("feat.asm", false); }
#endif

TEST(asm_makes_the_bios_objects_like_lwasm) {
    std::vector<pugputer::Fat16File> files;
    for (const char* mod : kBiosModules) CHECK(add(files, repo(std::string("bios/") + mod + ".asm"), upper(mod) + ".ASM"));
    CHECK(add(files, BIOS_DEFINES_PATH, "DEFINES.D"));
    Machine m;
    CHECK(m.start("asm_bios.img", files));
    for (const char* mod : kBiosModules) {
        std::string name = mod;
        std::string out = m.run("ASM -f obj -o " + name + ".o -l" + name + ".lst " + name + ".asm");
        CHECK(out.find("error") == std::string::npos);
        CHECK(same((name + ".o").c_str(), host_text(repo("bios/" + name + ".o")), m.file(upper(name) + ".O")));
        CHECK(same((name + ".lst").c_str(), no_cr(host_text(repo("bios/" + name + ".lst"))),
                   no_cr(m.file(upper(name) + ".LST"))));
    }
}

TEST(link_links_the_bios_like_lwlink) {
    std::vector<pugputer::Fat16File> files;
    for (const char* mod : kBiosModules) CHECK(add(files, repo(std::string("bios/") + mod + ".o"), upper(mod) + ".O"));
    CHECK(add(files, repo("bios/linker_script"), "LINK.SCR"));
    files.push_back(text("BIOS.RSP", kBiosRsp));
    Machine m;
    CHECK(m.start("link_bios.img", files));
    std::string out = m.run("LINK @bios.rsp");
    CHECK(out.find("LINK @bios.rsp\r\n/> ") != std::string::npos || out.find("rror") == std::string::npos);
    CHECK(same("the BIOS's S-records", host_text(PUGBIOS_S19_PATH), m.file("PUGBIOS.S19")));
    CHECK(same("the BIOS's map", no_cr(host_text(PUGBIOS_MAP_PATH)), no_cr(m.file("PUGBIOS.MAP"))));
}

TEST(the_bios_builds_entirely_on_the_pugputer) {
    std::vector<pugputer::Fat16File> files;
    for (const char* mod : kBiosModules) CHECK(add(files, repo(std::string("bios/") + mod + ".asm"), upper(mod) + ".ASM"));
    CHECK(add(files, BIOS_DEFINES_PATH, "DEFINES.D"));
    CHECK(add(files, repo("bios/linker_script"), "LINK.SCR"));
    files.push_back(text("BIOS.RSP", kBiosRsp));
    Machine m;
    CHECK(m.start("pug_biosbuild.img", files));
    for (const char* mod : kBiosModules) {
        std::string out = m.run(std::string("ASM -f obj -o ") + mod + ".o " + mod + ".asm");
        CHECK(out.find("error") == std::string::npos);
    }
    m.run("LINK @bios.rsp");
    CHECK(same("the BIOS built here", host_text(PUGBIOS_S19_PATH), m.file("PUGBIOS.S19")));
    CHECK(same("its map", no_cr(host_text(PUGBIOS_MAP_PATH)), no_cr(m.file("PUGBIOS.MAP"))));
}

TEST(asm_assembles_LINK_and_that_copy_links_the_bios) {
    std::vector<pugputer::Fat16File> files;
    for (const char* p : {"link", "pa_util", "pa_heap", "pa_strm"})
        CHECK(add(files, repo(std::string("asmlink/") + p + ".asm"), upper(p) + ".ASM"));
    CHECK(add(files, BIOS_DEFINES_PATH, "DEFINES.D"));
    for (const char* mod : kBiosModules) CHECK(add(files, repo(std::string("bios/") + mod + ".o"), upper(mod) + ".O"));
    CHECK(add(files, repo("bios/linker_script"), "LINK.SCR"));
    files.push_back(text("BIOS.RSP", kBiosRsp));
    Machine m;
    CHECK(m.start("link_self.img", files));
    std::string out = m.run("ASM -o LINK2.COM -lLINK.LST -s link.asm");
    CHECK(out.find("error") == std::string::npos);
    CHECK(same("LINK by ASM", host_text(LINK_BIN_PATH), m.file("LINK2.COM")));
    CHECK(same("its listing", no_cr(host_text(repo("asmlink/link.lst"))), no_cr(m.file("LINK.LST"))));
    m.run("LINK2 @bios.rsp");
    CHECK(same("the BIOS by that copy", host_text(PUGBIOS_S19_PATH), m.file("PUGBIOS.S19")));
}

TEST(link_makes_programs_that_run) {
    // Two modules: the program, and the text it prints (another section, another
    // file); a script puts the code at $4000 and the data after it.
    Machine m;
    CHECK(m.start("link_run.img",
                  {text("MAIN.ASM", "F_STDOUT EQU     1\n"
                                    "B_PUTS   EQU     $0A\n"
                                    "B_EXIT   EQU     $2B\n"
                                    "         EXPORT  start\n"
                                    "greeting IMPORT\n"
                                    "         SECTION code\n"
                                    "start    LDX     #greeting\n"
                                    "         LDB     #F_STDOUT\n"
                                    "         LDA     #B_PUTS\n"
                                    "         SWI2\n"
                                    "         LDA     #B_EXIT\n"
                                    "         SWI2\n"
                                    "         ENDSECT\n"),
                   text("TEXT.ASM", "         EXPORT  greeting\n"
                                    "         SECTION data\n"
                                    "greeting FCC     /Linked with LINK!/\n"
                                    "         FCB     13,10,0\n"
                                    "         ENDSECT\n"),
                   text("PROG.SCR", "section code load 4000\nsection data\nentry start\n")}));
    CHECK(m.run("ASM -f obj main.asm").find("error") == std::string::npos);
    CHECK(m.run("ASM -f obj text.asm").find("error") == std::string::npos);
    std::string out = m.run("LINK -f com -o PROG.COM -s prog.scr -m prog.map main.o text.o");
    std::string com = m.file("PROG.COM");
    CHECK(com.size() == 8 + 13 + 20);
    CHECK(com.compare(0, 8, std::string("PX\x40\x00\x40\x00\x00\x00", 8)) == 0);
    CHECK(m.run("PROG").find("Linked with LINK!") != std::string::npos);
    CHECK(m.file("PROG.MAP").find("Symbol: greeting (text.o) = 400D") != std::string::npos);
    // Something missing: an error, and nothing written.
    out = m.run("LINK -f com -o BAD.COM -s prog.scr main.o");
    CHECK(out.find("External symbol greeting not found in main.o:code") != std::string::npos);
    CHECK(out.find("Incomplete reference at main.o:code+01") != std::string::npos);
    CHECK(m.file("BAD.COM") == "<none>");
    out = m.run("LINK");
    CHECK(out.find("Usage: LINK") != std::string::npos);
    out = m.run("LINK -f decb main.o");
    CHECK(out.find("Invalid output format: decb") != std::string::npos);
    out = m.run("LINK nosuch.o");
    CHECK(out.find("Can't open file nosuch.o") != std::string::npos);
}

TEST(ar_makes_lwars_archives) {
    const std::string one = "first\r\n", two = "second!\r\n", three = "the third one\r\n";
    Machine m;
    CHECK(m.start("ar.img", {text("ONE.TXT", one), text("TWO.TXT", two), text("SUB/THREE.TXT", three),
                             text("AR.RSP", "-c R.A one.txt\r\ntwo.txt\r\n")}));
    // -c, then -l (lwar's "NAME: %04lx bytes")
    m.run("AR -c T.A one.txt two.txt");
    CHECK(same("AR -c", lwar({{"one.txt", one}, {"two.txt", two}}), m.file("T.A")));
    std::string out = m.run("AR -l T.A");
    CHECK(out.find("one.txt: 0007 bytes\r\ntwo.txt: 0009 bytes\r\n") != std::string::npos);
    // -a: at the end, the name as given
    m.run("AR -a T.A sub/three.txt");
    CHECK(same("AR -a", lwar({{"one.txt", one}, {"two.txt", two}, {"sub/three.txt", three}}), m.file("T.A")));
    // -r -n: the one replaced goes to the end; every name kept is the last part
    m.run("AR -r -n T.A one.txt");
    CHECK(same("AR -r -n", lwar({{"two.txt", two}, {"three.txt", three}, {"one.txt", one}}), m.file("T.A")));
    CHECK(m.file("ARTEMP.TMP") == "<none>");
    // -m: an archive's members, not the archive
    m.run("AR -cn U.A sub/three.txt");
    m.run("AR --create --merge V.A u.a two.txt");
    CHECK(same("AR -m", lwar({{"three.txt", three}, {"two.txt", two}}), m.file("V.A")));
    // -x: the member named, as a file; then all of them
    m.run("AR -x V.A three.txt");
    CHECK(same("AR -x", three, m.file("THREE.TXT")));
    m.run("DEL two.txt");
    m.run("AR -x T.A");
    CHECK(same("AR -x (all)", two, m.file("TWO.TXT")));
    // @FILE
    m.run("AR @ar.rsp");
    CHECK(same("AR @FILE", lwar({{"one.txt", one}, {"two.txt", two}}), m.file("R.A")));
    // Errors: reported, and no archive (or temporary file) left
    CHECK(m.run("AR -l none.a").find("Cannot open archive file none.a") != std::string::npos);
    CHECK(m.run("AR -l one.txt").find("one.txt is not a valid archive file.") != std::string::npos);
    CHECK(m.run("AR -c W.A one.txt nosuch.txt").find("Cannot open file nosuch.txt") != std::string::npos);
    CHECK(m.file("W.A") == "<none>");
    CHECK(m.file("ARTEMP.TMP") == "<none>");
    CHECK(m.run("AR T.A").find("You must specify an operation.") != std::string::npos);
    CHECK(m.run("AR -l").find("You must specify an archive file.") != std::string::npos);
    CHECK(m.run("AR").find("Usage: AR") != std::string::npos);
}

#if PUGPUTER_HAVE_LWASM
TEST(asm_matches_lwasm_on_object_files) {
    check_against_lwasm("objf.asm", false, true);
    check_against_lwasm("objexpr.asm", false, true);
}
TEST(link_matches_lwlink_with_its_scripts) {
    check_link("-f raw", "OUT.BIN");
    check_link("-f srec", "OUT.S19");
    check_link("-f srec -s link1.scr", "OUT.S19", {"link1.scr"});
    check_link("-f raw --section-base=tab=2000 --section-base=bss=0300 -e start", "OUT.BIN");
    check_link("-f srec -e 4321", "OUT.S19");
}

// lmain.asm and the members of libt.a (ld, lc, la, lk, lb) and libx.a (lx), in
// test_asm/asmlink, made by lwasm; AR makes the libraries from them on the
// Pugputer (they must be what lwar makes), and LINK links them as lwlink does:
// with -L and -l (members brought in only as they are needed, a member needing a
// later one, and another the program's; the first of two exports found wins; a
// constant section; a library that brings nothing in is warned about), with
// -l:NAME, and with an archive named as a file (all of it).
TEST(link_matches_lwlink_with_libraries) {
    if (!std::ifstream(LWLINK_EXE_PATH)) {
        std::printf("  (no lwlink: skipped)\n");
        return;
    }
    std::string dir = host_dir();
#ifdef _WIN32
    std::system(("mkdir \"" + dir + "/LIB\" >NUL 2>NUL").c_str());
#else
    std::system(("mkdir -p \"" + dir + "/LIB\"").c_str());
#endif
    std::vector<pugputer::Fat16File> disk;
    Members libt, libx;
    for (const char* src : {"lmain", "ld", "lc", "la", "lk", "lb", "lx"}) {
        std::string name = src;
        test_source(dir, name + ".asm");
        CHECK(host_run(dir, LWASM_EXE_PATH, name + ".asm --6309 --format=obj --output=" + name + ".o"));
        CHECK(add(disk, dir + "/" + name + ".o", upper(name) + ".O"));
        std::string o = host_text(dir + "/" + name + ".o");
        if (name == "lx")
            libx.push_back({"lx.o", o});
        else if (name != "lmain")
            libt.push_back({name + ".o", o});
    }
    for (const auto& lib : {std::make_pair(std::string("libt.a"), lwar(libt)),
                            std::make_pair(std::string("libx.a"), lwar(libx))}) {
        std::ofstream o(dir + "/LIB/" + lib.first, std::ios::binary);
        o << lib.second;
    }
    const std::vector<std::pair<std::string, std::string>> links = {
        {"-f srec -L LIB lmain.o -lt -lx", "OUT.S19"},
        {"-f raw -L LIB -lx lmain.o -l:libt.a", "OUT.BIN"},
        {"-f srec lmain.o LIB/libt.a", "OUT.S19"},
    };
    for (size_t i = 0; i < links.size(); ++i)
        disk.push_back(text("L" + std::to_string(i) + ".RSP", "-o " + links[i].second + " -m OUT.MAP " + links[i].first + "\r\n"));
    Machine m;
    CHECK(m.start("link_lib.img", disk));
    m.run("MKDIR lib");
    m.run("AR -c lib/libt.a ld.o lc.o la.o lk.o lb.o");
    m.run("AR -c lib/libx.a lx.o");
    CHECK(same("libt.a by AR", lwar(libt), m.file("LIB/LIBT.A")));
    CHECK(same("libx.a by AR", lwar(libx), m.file("LIB/LIBX.A")));
    for (size_t i = 0; i < links.size(); ++i) {
        const std::string& args = links[i].first;
        const std::string& out = links[i].second;
        std::remove((dir + "/" + out).c_str());
        std::remove((dir + "/OUT.MAP").c_str());
        // (lwlink's options take their arguments from the words that aren't
        // options, in order: -o and -m go first, as in check_link)
        CHECK(host_run(dir, LWLINK_EXE_PATH, "-o " + out + " -m OUT.MAP " + args));
        std::string said = m.run("LINK @l" + std::to_string(i) + ".rsp");
        if (m.file(upper(out)) == "<none>") std::fprintf(stderr, "  LINK said: %s\n", said.c_str());
        CHECK(same(("the output of: " + args).c_str(), host_text(dir + "/" + out), m.file(upper(out))));
        CHECK(same(("the map of: " + args).c_str(), no_cr(host_text(dir + "/OUT.MAP")), no_cr(m.file("OUT.MAP"))));
        if (i == 0) CHECK(said.find("Warning: library -lx (1) does not resolve any symbols") != std::string::npos);
        if (i == 1) CHECK(said.find("Warning: library -lx (0) does not resolve any symbols") != std::string::npos);
    }
    // A library that isn't there (and -l looks only in the -L directories, as in
    // lwlink), and one that leaves a symbol missing
    CHECK(m.run("LINK -L lib lmain.o -lnone").find("Can't open library: -lnone") != std::string::npos);
    CHECK(m.run("LINK -o X.BIN lmain.o -lt").find("Can't open library: -lt") != std::string::npos);
    std::string out = m.run("LINK -o X.BIN -L lib lmain.o -lx");
    CHECK(out.find("External symbol geta not found in lmain.o:init") != std::string::npos);
    CHECK(m.file("X.BIN") == "<none>");
}
#endif
