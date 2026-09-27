// The small utility programs in utils/ (HEXDUMP.COM, MOVE.COM), run from the shell through
// the whole boot chain on a disk image of their own.
#include <cstdio>
#include <fstream>
#include <iterator>
#include <string>
#include <vector>

#include "basic309_session.hpp"
#include "disk_images.hpp"
#include "fat16_reader.hpp"
#include "test_framework.hpp"

namespace {

using Bytes = std::vector<uint8_t>;

pugputer::Fat16File file(const std::string& name, const Bytes& data) {
    pugputer::Fat16File f;
    f.name = name;
    f.data = data;
    return f;
}
pugputer::Fat16File text(const std::string& name, const std::string& t) { return file(name, Bytes(t.begin(), t.end())); }

// A host file for the disk.
bool add(std::vector<pugputer::Fat16File>& files, const std::string& host, const std::string& name) {
    std::ifstream f(host, std::ios::binary);
    if (!f) {
        std::fprintf(stderr, "  can't read %s\n", host.c_str());
        return false;
    }
    files.push_back(file(name, Bytes((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>())));
    return true;
}

bool ends_with(const std::string& s, const std::string& suffix) {
    return s.size() >= suffix.size() && s.compare(s.size() - suffix.size(), suffix.size(), suffix) == 0;
}

// Types a line at the shell and returns what it printed, without the echo of the
// line and without the shell's banner and prompt when the program has ended.
// "<<TIMEOUT>>" if the prompt never came back.
std::string cmd(Basic309Session& s, const std::string& line, uint64_t budget = 400000000) {
    s.received.clear();
    s.type(line);
    uint64_t spent = 0;
    while (!ends_with(s.received, "> ") && spent < budget) spent += s.bus.run(20000);
    if (!ends_with(s.received, "> ")) return "<<TIMEOUT>>";
    std::string out = s.received;
    size_t nl = out.find("\r\n");
    if (nl == std::string::npos) return "<<NO ECHO>>";
    out.erase(0, nl + 2);
    size_t banner = out.find("\r\nPugputer 6309 shell"); // (the shell, started again)
    if (banner != std::string::npos) return out.substr(0, banner);
    size_t last = out.rfind("\r\n");
    out.erase(last == std::string::npos ? 0 : last + 2); // the prompt line
    return out;
}

// A Pugputer with the utilities and `files` on a fresh disk, at the shell's prompt.
bool boot(Basic309Session& s, const char* image_name, std::vector<pugputer::Fat16File> files) {
    if (!add(files, HEXDUMP_BIN_PATH, "HEXDUMP.COM")) return false;
    if (!add(files, MOVE_BIN_PATH, "MOVE.COM")) return false;
    std::string img = build_image(image_name, 16384, 2, std::move(files));
    return !img.empty() && s.boot_shell(PUGBIOS_S19_PATH, img.c_str());
}

std::string disk_path(const char* image_name) { return std::string(PUGPUTER_TEST_BUILD_DIR) + "/" + image_name; }

} // namespace

TEST(hexdump_shows_offsets_hex_and_ascii) {
    Bytes data;
    for (char c : std::string("Hello, world!")) data.push_back(static_cast<uint8_t>(c));
    for (int b : {0x0D, 0x0A, 0x00, 0x7F, 0x80, 0xFF, 0x20, 0x7E}) data.push_back(static_cast<uint8_t>(b));
    Bytes sixteen;
    for (int i = 0; i < 16; ++i) sixteen.push_back(static_cast<uint8_t>('A' + i));
    Basic309Session s;
    CHECK(boot(s, "hexdump1.img", {file("DATA.BIN", data), file("SIXTEEN.BIN", sixteen), text("EMPTY.TXT", "")}));
    CHECK(cmd(s, "hexdump data.bin") ==
          "000000  48 65 6C 6C 6F 2C 20 77  6F 72 6C 64 21 0D 0A 00  |Hello, world!...|\r\n"
          "000010  7F 80 FF 20 7E                                    |... ~|\r\n");
    CHECK(cmd(s, "hexdump sixteen.bin") ==
          "000000  41 42 43 44 45 46 47 48  49 4A 4B 4C 4D 4E 4F 50  |ABCDEFGHIJKLMNOP|\r\n");
    CHECK(cmd(s, "hexdump empty.txt") == "");
    CHECK(cmd(s, "hexdump") == "Usage: HEXDUMP file\r\n");
    CHECK(cmd(s, "hexdump nope.bin") == "nope.bin: File not found\r\n");
}

TEST(hexdump_offsets_go_past_64k) {
    Bytes big(65536 + 20);
    for (size_t i = 0; i < big.size(); ++i) big[i] = static_cast<uint8_t>(i >> 4);
    Basic309Session s;
    CHECK(boot(s, "hexdump2.img", {file("BIG.BIN", big)}));
    std::string out = cmd(s, "hexdump big.bin", 20000000000ull);
    CHECK(out.find("00FFF0  FF FF FF FF FF FF FF FF  FF FF FF FF FF FF FF FF  |................|\r\n"
                   "010000  00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  |................|\r\n"
                   "010010  01 01 01 01                                       |....|\r\n") != std::string::npos);
    CHECK(ends_with(out, "|....|\r\n"));
}

TEST(move_renames_in_place_and_moves_between_directories) {
    Bytes big(70000);
    for (size_t i = 0; i < big.size(); ++i) big[i] = static_cast<uint8_t>(i * 7 + (i >> 9));
    const std::string hello = "Hello\r\n";
    Basic309Session s;
    CHECK(boot(s, "move1.img", {text("HELLO.TXT", hello), text("A.TXT", "a"), text("B.TXT", "b"),
                                file("BIG.BIN", big)}));
    const std::string moved = "        1 file moved\r\n";
    CHECK(cmd(s, "path /") == ""); // (the programs are in the root on this disk)
    CHECK(cmd(s, "move") == "Usage: MOVE from [to]\r\n");
    CHECK(cmd(s, "move nope.txt x.txt") == "File not found\r\n");
    // In one directory: a rename.
    CHECK(cmd(s, "move hello.txt hi.txt") == moved);
    // To a directory, by its name or with a "/": copied there, the original deleted.
    CHECK(cmd(s, "md d1") == "");
    CHECK(cmd(s, "move hi.txt d1") == moved);            // /D1/HI.TXT
    CHECK(cmd(s, "cd d1") == "");
    CHECK(cmd(s, "move hi.txt ..") == moved);            // /HI.TXT
    CHECK(cmd(s, "move /hi.txt") == moved);              // here: /D1/HI.TXT
    CHECK(cmd(s, "move hi.txt") == "Already exists\r\n"); // (onto itself)
    CHECK(cmd(s, "move hi.txt ../hi2.txt") == moved);    // another directory, another name
    CHECK(cmd(s, "cd") == "/D1\r\n");                   // (MOVE leaves the current directory be)
    CHECK(cmd(s, "cd /") == "");
    // Nothing is overwritten.
    CHECK(cmd(s, "move a.txt b.txt") == "Already exists\r\n");
    CHECK(cmd(s, "move a.txt nodir/") == "File not found\r\n");
    // A big file, to a directory and a new name.
    CHECK(cmd(s, "move big.bin d1/big2.bin", 4000000000ull) == moved);
    // Directories: renamed in place, not moved elsewhere.
    CHECK(cmd(s, "move d1 d2") == moved);
    CHECK(cmd(s, "md d3") == "");
    CHECK(cmd(s, "move d2 d3") == "A directory can only be renamed in place\r\n");

    Fat16Volume v;
    CHECK(v.load(disk_path("move1.img").c_str()));
    Fat16Volume::Entry e;
    CHECK(!v.find("/HELLO.TXT", e) && !v.find("/HI.TXT", e) && !v.find("/BIG.BIN", e) && !v.find("/D1", e));
    CHECK(v.find("/HI2.TXT", e) && v.read(e) == Bytes(hello.begin(), hello.end()));
    CHECK(v.find("/D2/BIG2.BIN", e) && v.read(e) == big);
    CHECK(v.find("/A.TXT", e) && v.read(e) == Bytes{'a'});
    CHECK(v.find("/B.TXT", e) && v.read(e) == Bytes{'b'});
    CHECK(v.find("/D3", e));
    CHECK(v.fats_match());
}
