// The small utility programs in utils/ (HEXDUMP.COM, ...), run from the shell through
// the whole boot chain on a disk image of their own.
#include <cstdio>
#include <fstream>
#include <iterator>
#include <string>
#include <vector>

#include "basic309_session.hpp"
#include "disk_images.hpp"
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
    std::string img = build_image(image_name, 16384, 2, std::move(files));
    return !img.empty() && s.boot_shell(PUGBIOS_S19_PATH, img.c_str());
}

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
