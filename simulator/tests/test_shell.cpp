// The program loader (B_EXEC / B_ARGS / B_EXIT in the resident DOS) and the shell
// (shell/shell.asm, /SHELL.COM), driven with real keystrokes through the whole boot
// chain: BIOS -> SD boot -> DOS -> SHELL.COM. Each test builds its own small disk
// image (disk_images.hpp) with the extra files it needs, so nothing depends on -- or
// disturbs -- the shared disk.img.
//
// Small test programs are assembled here by hand (a few instructions each): a program
// file is an 8-byte header ("PX", load, entry, flags -- see EXE_* in bios/defines.d)
// followed by the body.
#include <cstdio>
#include <fstream>
#include <string>
#include <vector>

#include "basic309_session.hpp"
#include "disk_images.hpp"
#include "dos_session.hpp"
#include "fat16_reader.hpp"
#include "test_framework.hpp"

namespace {

using Bytes = std::vector<uint8_t>;

constexpr uint8_t SWI2_0 = 0x10, SWI2_1 = 0x3F;

Bytes program(uint16_t load, uint16_t entry, const Bytes& body, uint16_t flags = 0, const char* magic = "PX") {
    Bytes v{static_cast<uint8_t>(magic[0]),  static_cast<uint8_t>(magic[1]),  static_cast<uint8_t>(load >> 8),
            static_cast<uint8_t>(load & 0xFF), static_cast<uint8_t>(entry >> 8), static_cast<uint8_t>(entry & 0xFF),
            static_cast<uint8_t>(flags >> 8), static_cast<uint8_t>(flags & 0xFF)};
    v.insert(v.end(), body.begin(), body.end());
    return v;
}

// ECHO.COM: prints its command tail (B_ARGS, then B_PUTS) and exits (B_EXIT).
//   LDA #B_ARGS ; SWI2 ; LDB #F_STDOUT ; LDA #B_PUTS ; SWI2 ; LDA #B_EXIT ; SWI2
Bytes echo_program(uint16_t at = 0x5000) {
    return program(at, at,
                   {0x86, 0x2A, SWI2_0, SWI2_1, 0xC6, 0x01, 0x86, 0x0A, SWI2_0, SWI2_1, 0x86, 0x2B, SWI2_0, SWI2_1});
}

// WRITER.COM: creates OUT.TXT, writes the single byte 'A' and exits WITHOUT closing it
// (B_EXIT must flush and close it).
Bytes writer_program() {
    Bytes body = {0x8E, 0x50, 0x20,       // LDX #$5020 ("OUT.TXT")
                  0x11, 0x86, 0x01,       // LDE #1 (FOPEN_WRITE)
                  0x86, 0x13, SWI2_0, SWI2_1, // LDA #B_FOPEN_NAME ; SWI2 -> A = handle
                  0x1F, 0x89,             // TFR A,B
                  0x11, 0x86, 0x41,       // LDE #'A'
                  0x86, 0x1C, SWI2_0, SWI2_1, // LDA #B_FPUTC ; SWI2
                  0x86, 0x2B, SWI2_0, SWI2_1}; // LDA #B_EXIT ; SWI2
    while (body.size() < 0x20) body.push_back(0x12); // NOP up to $5020
    for (char c : std::string("OUT.TXT")) body.push_back(static_cast<uint8_t>(c));
    body.push_back(0);
    return program(0x5000, 0x5000, body);
}

pugputer::Fat16File file(const std::string& name, const Bytes& data) {
    pugputer::Fat16File f;
    f.name = name;
    f.data = data;
    return f;
}
pugputer::Fat16File text(const std::string& name, const std::string& t) { return file(name, Bytes(t.begin(), t.end())); }

std::string image(const char* name, std::vector<pugputer::Fat16File> extra) {
    return build_image(name, 16384, 2, std::move(extra));
}

bool ends_with(const std::string& s, const std::string& suffix) {
    return s.size() >= suffix.size() && s.compare(s.size() - suffix.size(), suffix.size(), suffix) == 0;
}

// Types a line at the shell and returns what it printed, without the echo of the
// line and without the next prompt. "<<TIMEOUT>>" if the prompt never came back.
std::string cmd(Basic309Session& s, const std::string& line) {
    s.received.clear();
    s.type(line);
    uint64_t spent = 0;
    while (!ends_with(s.received, "> ") && spent < 400000000) spent += s.bus.run(20000);
    if (!ends_with(s.received, "> ")) return "<<TIMEOUT>>";
    std::string out = s.received;
    size_t nl = out.find("\r\n");
    if (nl == std::string::npos) return "<<NO ECHO>>";
    out.erase(0, nl + 2);
    size_t last = out.rfind("\r\n");
    out.erase(last == std::string::npos ? 0 : last + 2); // the prompt line
    return out;
}

bool has(const std::string& hay, const std::string& needle) { return hay.find(needle) != std::string::npos; }

} // namespace

TEST(shell_boots_prints_a_banner_and_prompts_with_the_current_directory) {
    std::string img = image("shell1.img", {});
    Basic309Session s;
    CHECK(s.boot_shell(PUGBIOS_S19_PATH, img.c_str()));
    CHECK(has(s.received, "Pugputer 6309 shell"));
    CHECK(ends_with(s.received, "/> "));
    CHECK(cmd(s, "") == "");           // a blank line just prompts again
    CHECK(cmd(s, "   ") == "");
    CHECK(cmd(s, "md sub") == "");
    CHECK(cmd(s, "cd sub") == "");
    CHECK(ends_with(s.received, "/SUB> "));
    CHECK(cmd(s, "cd") == "/SUB\r\n");    // CD alone shows where you are
    CHECK(cmd(s, "cd ..") == "");
    CHECK(ends_with(s.received, "\r\n/> "));
}

TEST(shell_info_commands) {
    std::string img = image("shell2.img", {});
    Basic309Session s;
    CHECK(s.boot_shell(PUGBIOS_S19_PATH, img.c_str()));
    CHECK(cmd(s, "ver") == "Pugputer 6309 DOS 2.2\r\n");
    CHECK(cmd(s, "MEM") == "RAM: 1024 KB installed, 960 KB free for programs\r\n");
    std::string help = cmd(s, "help");
    CHECK(has(help, "DIR [path]") && has(help, "COPY from to") && has(help, "name [args]"));
    CHECK(cmd(s, "frobnicate") == "Bad command or file name\r\n");
    CHECK(cmd(s, "x/y/z") == "Bad command or file name\r\n");
    CHECK(cmd(s, "averyveryverylongcommandwordthatgoesonandonandonforever") == "Bad command or file name\r\n");
}

TEST(shell_dir_lists_names_sizes_and_directories) {
    Bytes big(70000, 'x'); // more than 16 bits of size
    std::string img = image("shell3.img", {text("HELLO.TXT", "Hello\r\nworld\r\n"), file("BIG.DAT", big), text("A", "1")});
    Basic309Session s;
    CHECK(s.boot_shell(PUGBIOS_S19_PATH, img.c_str()));
    CHECK(cmd(s, "md games") == "");
    std::string dir = cmd(s, "dir");
    std::ifstream sf(SHELL_BIN_PATH, std::ios::binary | std::ios::ate);
    CHECK(has(dir, "SHELL.COM    " + std::to_string(static_cast<long>(sf.tellg())) + "\r\n"));
    CHECK(has(dir, "BASIC.COM    12296\r\n"));
    CHECK(has(dir, "HELLO.TXT    14\r\n"));
    CHECK(has(dir, "BIG.DAT      70000\r\n"));
    CHECK(has(dir, "A            1\r\n"));
    CHECK(has(dir, "GAMES        <DIR>\r\n"));
    CHECK(!has(dir, ". ") && !has(dir, "..")); // "." and ".." aren't shown
    CHECK(cmd(s, "dir games") == "");
    CHECK(cmd(s, "dir /games") == "");
    CHECK(cmd(s, "dir nope") == "File not found\r\n");
    CHECK(cmd(s, "dir hello.txt") == "Not a directory\r\n");
}

TEST(shell_file_commands_copy_type_rename_delete) {
    std::string img = image("shell4.img", {text("HELLO.TXT", "Hello\r\nworld\r\n")});
    Basic309Session s;
    CHECK(s.boot_shell(PUGBIOS_S19_PATH, img.c_str()));
    CHECK(cmd(s, "type hello.txt") == "Hello\r\nworld\r\n\r\n"); // (TYPE adds a final newline)
    CHECK(cmd(s, "copy hello.txt copy.txt") == "        1 file copied\r\n");
    CHECK(cmd(s, "type copy.txt") == "Hello\r\nworld\r\n\r\n");
    CHECK(cmd(s, "copy hello.txt copy.txt") == "        1 file copied\r\n"); // overwrites
    CHECK(cmd(s, "ren copy.txt moved.txt") == "");
    CHECK(cmd(s, "type copy.txt") == "File not found\r\n");
    CHECK(cmd(s, "type moved.txt") == "Hello\r\nworld\r\n\r\n");
    CHECK(cmd(s, "ren moved.txt hello.txt") == "Already exists\r\n");
    CHECK(cmd(s, "del moved.txt") == "");
    CHECK(cmd(s, "erase moved.txt") == "File not found\r\n");
    CHECK(cmd(s, "copy nope.txt x.txt") == "File not found\r\n");
    CHECK(cmd(s, "copy hello.txt") == "Missing argument\r\n");
    CHECK(cmd(s, "ren hello.txt") == "Missing argument\r\n");
    CHECK(cmd(s, "type") == "Missing argument\r\n");
    CHECK(cmd(s, "del") == "Missing argument\r\n");

    // A big file copies exactly (across sectors and clusters).
    CHECK(cmd(s, "copy basic.com big.com") == "        1 file copied\r\n");
    CHECK(has(cmd(s, "dir"), "BIG.COM      12296\r\n"));

    // Directories.
    CHECK(cmd(s, "mkdir d1") == "");
    CHECK(cmd(s, "md d1") == "Already exists\r\n");
    CHECK(cmd(s, "copy hello.txt d1/h.txt") == "        1 file copied\r\n");
    CHECK(cmd(s, "rd d1") == "Directory not empty\r\n");
    CHECK(cmd(s, "del d1/h.txt") == "");
    CHECK(cmd(s, "rmdir d1") == "");
    CHECK(cmd(s, "cd d1") == "File not found\r\n");
    CHECK(cmd(s, "cd hello.txt") == "Not a directory\r\n");
    CHECK(cmd(s, "del ../../bad name") != "");

    // What's on the disk.
    Fat16Volume v;
    CHECK(v.load(img.c_str()));
    Fat16Volume::Entry e, e2;
    CHECK(v.find("/HELLO.TXT", e) && v.read(e) == Bytes({'H', 'e', 'l', 'l', 'o', '\r', '\n', 'w', 'o', 'r', 'l', 'd', '\r', '\n'}));
    CHECK(v.find("/BIG.COM", e) && v.find("/BASIC.COM", e2) && v.read(e) == v.read(e2));
    CHECK(!v.find("/MOVED.TXT", e) && !v.find("/D1", e));
    CHECK(v.fats_match());
}

TEST(shell_line_editing) {
    std::string img = image("shell5.img", {});
    Basic309Session s;
    CHECK(s.boot_shell(PUGBIOS_S19_PATH, img.c_str()));
    // Backspace and Delete erase; the echo shows the erasure.
    CHECK(cmd(s, "vex\x08r") == "Pugputer 6309 DOS 2.2\r\n");
    CHECK(cmd(s, "vxx\x7f\x7f" "er") == "Pugputer 6309 DOS 2.2\r\n");
    // Ctrl-C abandons the line.
    s.received.clear();
    for (char c : std::string("del importa")) s.send_byte(static_cast<uint8_t>(c));
    s.send_byte(3);
    s.type("ver");
    uint64_t spent = 0;
    while (!ends_with(s.received, "> ") && spent < 100000000) spent += s.bus.run(20000);
    CHECK(has(s.received, "^C"));
    CHECK(has(s.received, "Pugputer 6309 DOS 2.2"));
    CHECK(!has(s.received, "Missing argument")); // "del importa" never ran
    // A command is case-insensitive; a long line is capped rather than overrun.
    CHECK(cmd(s, "VeR") == "Pugputer 6309 DOS 2.2\r\n");
    std::string longline = "ver " + std::string(120, 'x');
    CHECK(cmd(s, longline) == "Pugputer 6309 DOS 2.2\r\n");
    CHECK(cmd(s, "ver") == "Pugputer 6309 DOS 2.2\r\n");
}

TEST(shell_runs_programs_with_a_command_tail_and_returns_to_the_shell) {
    std::string img = image("shell6.img", {file("ECHO.COM", echo_program()), file("NOEXT", echo_program())});
    Basic309Session s;
    CHECK(s.boot_shell(PUGBIOS_S19_PATH, img.c_str()));
    // The tail is what follows the command word after its blanks, as typed.
    s.received.clear();
    s.type("echo hello   world");
    CHECK(s.wait_for("hello   world"));
    CHECK(s.wait_for("Pugputer 6309 shell")); // B_EXIT started the shell again
    uint64_t spent = 0;
    while (!ends_with(s.received, "/> ") && spent < 100000000) spent += s.bus.run(20000);
    CHECK(ends_with(s.received, "/> "));
    // Name forms: with the extension, lower case, no tail at all.
    for (const std::string& line : {std::string("ECHO.COM abc"), std::string("Echo abc")}) {
        s.received.clear();
        s.type(line);
        CHECK(s.wait_for("abc\r\n") || s.wait_for("abc"));
        CHECK(s.wait_for("shell"));
        spent = 0;
        while (!ends_with(s.received, "/> ") && spent < 100000000) spent += s.bus.run(20000);
    }
    CHECK(cmd(s, "md sub") == "");
    CHECK(cmd(s, "cd sub") == "");
    // From another directory it takes the search path, which doesn't have the root in it ...
    CHECK(cmd(s, "echo from-sub") == "Bad command or file name\r\n");
    CHECK(cmd(s, "path /") == ""); // ... until it does
    s.received.clear();
    s.type("echo from-sub");
    CHECK(s.wait_for("from-sub"));
    CHECK(s.wait_for("shell"));
    spent = 0;
    while (!ends_with(s.received, "/SUB> ") && !ends_with(s.received, "/> ") && spent < 100000000) spent += s.bus.run(20000);
    // DOS keeps the current directory across the restart of the shell.
    CHECK(ends_with(s.received, "/SUB> "));
    // A program path is used as given (no search for an explicit path).
    CHECK(cmd(s, "nope/echo x") == "Bad command or file name\r\n");
}

TEST(shell_path_command_shows_and_sets_the_search_path) {
    std::string img = image("shell_path1.img", {});
    Basic309Session s;
    CHECK(s.boot_shell(PUGBIOS_S19_PATH, img.c_str()));
    CHECK(cmd(s, "path") == "PATH=/CMD\r\n"); // DOS starts it as /CMD
    CHECK(cmd(s, "path /bin;/cmd  ") == "");  // upper-cased, trailing blanks dropped
    CHECK(cmd(s, "PATH") == "PATH=/BIN;/CMD\r\n");
    CHECK(cmd(s, "path ;") == "");            // ";" alone empties it
    CHECK(cmd(s, "path") == "No path\r\n");
    std::string help = cmd(s, "help");
    CHECK(has(help, "PATH [dir;dir]"));
}

TEST(shell_finds_programs_in_the_current_directory_then_along_the_path) {
    // ECHO.COM in /CMD and /BIN; HERE.COM in both /CMD and the root, printing different things.
    // Hand-assembled: LDX #msg ; LDB #F_STDOUT ; LDA #B_PUTS ; SWI2 ; LDA #B_EXIT ; SWI2 ; msg ($500D)
    auto say = [](const std::string& msg) {
        Bytes body = {0x8E, 0x50, 0x0D, 0xC6, 0x01, 0x86, 0x0A, SWI2_0, SWI2_1, 0x86, 0x2B, SWI2_0, SWI2_1};
        for (char c : msg) body.push_back(static_cast<uint8_t>(c));
        body.push_back(0);
        return program(0x5000, 0x5000, body);
    };
    std::string img = image("shell_path2.img", {file("CMD/ECHO.COM", echo_program()), file("HERE.COM", say("root")),
                                                file("CMD/HERE.COM", say("cmd")), file("BIN/ONLY.COM", say("bin")),
                                                text("NOTDIR", "x")});
    Basic309Session s;
    CHECK(s.boot_shell(PUGBIOS_S19_PATH, img.c_str()));
    auto run = [&](const std::string& line, const std::string& want) {
        s.received.clear();
        s.type(line);
        bool ok = s.wait_for(want) && s.wait_for("shell");
        uint64_t spent = 0;
        while (!ends_with(s.received, "> ") && spent < 100000000) spent += s.bus.run(20000);
        if (!ok) std::fprintf(stderr, "  [%s] expected [%s], got [%s]\n", line.c_str(), want.c_str(), s.received.c_str());
        return ok;
    };
    CHECK(run("echo hi there", "hi there"));   // found in /CMD, the default path
    CHECK(run("here", "root"));                // the current directory comes first
    CHECK(cmd(s, "cd /bin") == "");
    CHECK(run("here", "cmd"));                 // not here: the path
    CHECK(run("only", "bin"));                 // (the current directory)
    CHECK(cmd(s, "cd /") == "");
    CHECK(cmd(s, "only") == "Bad command or file name\r\n");
    // Missing directories and files in the path are passed over; the path survives the shell
    // being reloaded after each program.
    CHECK(cmd(s, "path /nope;notdir;;/bin") == "");
    CHECK(run("only", "bin"));
    CHECK(cmd(s, "path") == "PATH=/NOPE;NOTDIR;;/BIN\r\n");
    CHECK(cmd(s, "echo x") == "Bad command or file name\r\n"); // /CMD isn't in it any more
    CHECK(cmd(s, "path ;") == "");
    CHECK(cmd(s, "cd /bin") == "");
    CHECK(cmd(s, "here") == "Bad command or file name\r\n");   // no path: the current directory only
    CHECK(run("only", "bin"));
}

TEST(basic_starts_in_the_basic_directory_when_the_disk_has_one) {
    std::string img = image("shell_basicdir.img", {text("BASIC/HI.BAS", "10 PRINT \"HI THERE\"\r\n")});
    Basic309Session s;
    CHECK(s.boot_disk(PUGBIOS_S19_PATH, img.c_str()));
    CHECK(s.run_line("CHDIR") == "/BASIC\r\n");
    CHECK(s.run_line("LOAD \"HI\"") == "");
    CHECK(s.run_line("RUN").find("HI THERE") != std::string::npos);
    // SYSTEM goes back to the shell, which is now in /BASIC too (one current directory).
    s.received.clear();
    s.type("SYSTEM");
    CHECK(s.wait_for("Pugputer 6309 shell"));
    uint64_t spent = 0;
    while (!ends_with(s.received, "> ") && spent < 100000000) spent += s.bus.run(20000);
    CHECK(ends_with(s.received, "/BASIC> "));
}

TEST(shell_reports_files_that_are_not_programs) {
    Bytes not_exe = {'h', 'e', 'l', 'l', 'o'};
    std::string img = image("shell7.img", {file("BADMAGIC.COM", program(0x5000, 0x5000, {0x39}, 0, "QQ")),
                                            file("FLAGS.COM", program(0x5000, 0x5000, {0x39}, 1)),
                                            file("LOW.COM", program(0x0100, 0x0100, {0x39})),
                                            file("DOSMEM.COM", program(0x2000, 0x2000, {0x39})),
                                            file("ROM.COM", program(0xEFF0, 0xEFF0, Bytes(0x20, 0x12))),
                                            file("NOENTRY.COM", program(0x5000, 0x5100, {0x39})),
                                            file("EMPTY.COM", program(0x5000, 0x5000, {})),
                                            file("TINY.COM", not_exe),
                                            file("OK.COM", program(0x5000, 0x5000, {0x39}))});
    Basic309Session s;
    CHECK(s.boot_shell(PUGBIOS_S19_PATH, img.c_str()));
    CHECK(cmd(s, "badmagic") == "Not a program file\r\n");
    CHECK(cmd(s, "flags") == "Not a program file\r\n");
    CHECK(cmd(s, "low") == "Too big\r\n");     // would overwrite the BIOS's memory
    CHECK(cmd(s, "dosmem") == "Too big\r\n");  // ... or DOS's
    CHECK(cmd(s, "rom") == "Too big\r\n");     // ... or run into the ROM
    CHECK(cmd(s, "noentry") == "Not a program file\r\n");
    CHECK(cmd(s, "empty") == "Not a program file\r\n");
    CHECK(cmd(s, "tiny") == "Not a program file\r\n"); // shorter than a header
    CHECK(cmd(s, "dir") != "");                        // and the shell is still fine
    CHECK(cmd(s, "md dd") == "");
    CHECK(cmd(s, "dd") == "Bad command or file name\r\n"); // a directory isn't a program
}

TEST(exit_closes_and_flushes_files_the_program_left_open) {
    std::string img = image("shell8.img", {file("WRITER.COM", writer_program())});
    Basic309Session s;
    CHECK(s.boot_shell(PUGBIOS_S19_PATH, img.c_str()));
    s.received.clear();
    s.type("writer");
    CHECK(s.wait_for("shell"));
    uint64_t spent = 0;
    while (!ends_with(s.received, "/> ") && spent < 100000000) spent += s.bus.run(20000);
    CHECK(ends_with(s.received, "/> "));
    CHECK(cmd(s, "type out.txt") == "A\r\n");
    Fat16Volume v;
    CHECK(v.load(img.c_str()));
    Fat16Volume::Entry e;
    CHECK(v.find("/OUT.TXT", e) && v.read(e) == Bytes({'A'}));
    CHECK(v.fats_match());
}

TEST(basic_starts_from_the_shell_and_system_returns_to_it) {
    Basic309Session s;
    CHECK(s.boot_disk(PUGBIOS_S19_PATH, DISK_IMG_PATH));
    CHECK(has(s.received, "6809 EXTENDED BASIC"));
    CHECK(s.ends_with_ok());
    CHECK(s.run_line("PRINT 6*7") == " 42 \r\n");
    // SYSTEM leaves BASIC: DOS restarts the shell.
    s.received.clear();
    s.type("SYSTEM");
    CHECK(s.wait_for("Pugputer 6309 shell"));
    uint64_t spent = 0;
    while (!ends_with(s.received, "/> ") && spent < 100000000) spent += s.bus.run(20000);
    CHECK(ends_with(s.received, "/> "));
    // ... and BASIC can be started again (a fresh cold start).
    s.received.clear();
    s.type("basic");
    CHECK(s.run_until_ok(200000000));
    CHECK(s.run_line("PRINT 1+1") == " 2 \r\n");
}
