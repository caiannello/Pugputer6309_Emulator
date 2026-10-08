// TILEKIT (gamekit/): the tile set editor, run on the emulated machine with the video card
// and driven through the card's mouse and keyboard, as a person at the video window would.
// ASM on the machine assembles it from its sources -- byte for byte what lwasm made -- and
// what it draws, edits, saves and opens is checked on the card and on the disk.
#include <algorithm>
#include <cstdlib>
#include <cstdio>
#include <fstream>
#include <iterator>
#include <string>
#include <vector>

#include "basic309_session.hpp"
#include "disk_images.hpp"
#include "fat16_reader.hpp"
#include "pugputer/video_device.hpp"
#include "test_framework.hpp"
#include "vc.h"

using pugputer::VideoDevice;

namespace {

constexpr uint64_t kSecond = 3579545;
constexpr uint32_t kTiles = 0x020000;
constexpr int kPanelX = 464;

std::string host_file(const std::string& path) {
    std::ifstream f(path, std::ios::binary);
    return std::string((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
}

pugputer::Fat16File disk_file(const std::string& name, const std::string& data) {
    pugputer::Fat16File f;
    f.name = name;
    f.data.assign(data.begin(), data.end());
    return f;
}

// The machine with TILEKIT.COM (lwasm's) and its sources on the disk.
struct Kit {
    std::string img;
    std::string bin; // lwasm's TILEKIT.COM
    Basic309Session s;
    VideoDevice v;
    bool ok = false;

    explicit Kit(std::vector<pugputer::Fat16File> more = {}) {
        std::string repo = REPO_DIR;
        bin = host_file(repo + "/gamekit/build/tilekit.bin");
        std::vector<pugputer::Fat16File> files = {
            disk_file("TILEKIT.COM", bin),
            disk_file("TILEKIT.ASM", host_file(repo + "/gamekit/tilekit.asm")),
            disk_file("TK_DRAW.ASM", host_file(repo + "/gamekit/tk_draw.asm")),
            disk_file("TK_FILE.ASM", host_file(repo + "/gamekit/tk_file.asm")),
            disk_file("GK_UI.ASM", host_file(repo + "/gamekit/gk_ui.asm")),
            disk_file("DEFINES.D", host_file(repo + "/bios/defines.d")),
            disk_file("VIDCARD.D", host_file(repo + "/vidcard/vidcard.d")),
            disk_file("ASM.COM", host_file(ASM_BIN_PATH))};
        for (auto& f : more) files.push_back(std::move(f));
        CHECK(!bin.empty());
        img = build_image("tilekit.img", 32768, 4, files);
        CHECK(!img.empty());
        CHECK(s.boot_shell(PUGBIOS_S19_PATH, img.c_str()));
        v.set_draw_all(true);
        s.bus.map_device("video", VideoDevice::kBase, VideoDevice::kSize, &v, pugputer::IrqLine::IRQ);
        ok = !bin.empty() && !img.empty();
    }
    void type(const std::string& cmd) {
        s.received.clear();
        for (char ch : cmd) s.send_byte(static_cast<uint8_t>(ch));
        s.send_byte('\r');
    }
    bool prompt(uint64_t budget) {
        for (uint64_t spent = 0; spent < budget;) {
            uint64_t got = s.bus.run(20000);
            if (got == 0) return false;
            spent += got;
            const std::string& r = s.received;
            if (r.size() > 4 && r.compare(r.size() - 3, 3, "/> ") == 0) return true;
        }
        return false;
    }
    void frames(int n = 3) { s.bus.run(static_cast<uint64_t>(n) * kSecond / 60); }
    // The mouse to x, y (640x480) with these buttons held, for a few frames.
    void mouse(int x, int y, uint8_t buttons = 0, int n = 3) {
        v.mouse_to(x, y, buttons);
        frames(n);
    }
    void click(int x, int y, uint8_t button = 1) {
        mouse(x, y, 0);
        mouse(x, y, button);
        mouse(x, y, 0);
    }
    void key(uint8_t usage, bool shift = false, bool ctrl = false) {
        if (shift) v.key(0xE1, true);
        if (ctrl) v.key(0xE0, true);
        v.key(usage, true);
        v.key(usage, false);
        if (ctrl) v.key(0xE0, false);
        if (shift) v.key(0xE1, false);
        frames(4);
    }
    // Letters and digits and . typed (upper case: the name keys are letters anyway).
    void text(const std::string& t) {
        for (char c : t) {
            if (c >= 'A' && c <= 'Z') key(static_cast<uint8_t>(0x04 + c - 'A'));
            else if (c >= '1' && c <= '9') key(static_cast<uint8_t>(0x1E + c - '1'));
            else if (c == '0') key(0x27);
            else if (c == '.') key(0x37);
        }
    }
    const vc_card& c() { return v.card(); }
    uint8_t vram(uint32_t a) { return c().vram[a & (VC_VRAM_SIZE - 1)]; }
    // A text row of the 80x30 screen.
    std::string row(int r) {
        std::string t;
        for (int col = 0; col < 80; ++col) t += static_cast<char>(c().vram[VC_RESET_TEXT_MAP + (r * 128 + col) * 4]);
        return t;
    }
    bool shows(int r, const std::string& what) { return row(r).find(what) != std::string::npos; }
    // A pixel of the panel (its own coordinates), as a palette index.
    uint8_t panel(int x, int y) { return vram(static_cast<uint32_t>(y * 176 + x)); }
    // A pixel value of tile t of an 8x8, 4-bit set.
    int pix4(int t, int x, int y) {
        uint8_t b = vram(kTiles + t * 32 + (y * 8 + x) / 2);
        return x & 1 ? b & 15 : b >> 4;
    }
    // The magnified tile's pixel x, y (8x8 tiles: 16 screen pixels each), on the screen.
    static int zx(int x) { return kPanelX + 24 + x * 16 + 8; }
    static int zy(int y) { return 56 + y * 16 + 8; }
    // TILEKIT_DUMP_DIR=folder saves the picture there (NAME.rgb: 640x480 RGB bytes).
    void dump(const std::string& name) {
        const char* dir = std::getenv("TILEKIT_DUMP_DIR");
        if (!dir) return;
        frames(2);
        std::ofstream f(std::string(dir) + "/" + name + ".rgb", std::ios::binary);
        for (int y = 0; y < 480; ++y)
            for (int x = 0; x < 640; ++x) {
                uint32_t p = v.pixel(x, y);
                char rgb[3] = {static_cast<char>(p >> 16), static_cast<char>(p >> 8), static_cast<char>(p)};
                f.write(rgb, 3);
            }
    }
    std::vector<uint8_t> disk(const std::string& path) {
        Fat16Volume vol;
        Fat16Volume::Entry e;
        if (!vol.load(img.c_str()) || !vol.find(path, e)) return {};
        return vol.read(e);
    }
};

} // namespace

TEST(tilekit_assembles_on_the_machine_as_lwasm_does) {
    Kit k;
    if (!k.ok) return;
    k.type("ASM -f raw -o TK.BIN TILEKIT.ASM");
    CHECK(k.prompt(20000000000ull));
    CHECK(k.s.received.find("rror") == std::string::npos);
    std::vector<uint8_t> made = k.disk("/TK.BIN");
    CHECK(!made.empty() && std::string(made.begin(), made.end()) == k.bin);
}

TEST(tilekit_makes_a_set_and_draws_with_the_pen_line_and_fill) {
    Kit k;
    if (!k.ok) return;
    k.type("TILEKIT");
    k.frames(60);
    // The questions: an 8x8, 16-color set for 320x240 unless changed.
    CHECK(k.shows(9, "A NEW TILE SET") && k.shows(11, "8x8") && k.shows(12, "16 (4 BITS") && k.shows(13, "320x240"));
    k.dump("1-dialog");
    CHECK(k.c().in_ctrl == (VC_IN_POINTER | VC_IN_KEYS));
    k.key(0x28); // Enter
    k.frames(30);
    CHECK(!k.shows(9, "A NEW TILE SET"));
    CHECK(k.shows(29, "TILE 0000/0001") && k.shows(29, "8x8") && k.shows(29, "16 COLORS") && k.shows(29, "PEN"));
    CHECK(k.shows(0, "TILEKIT (NEW)"));
    const uint8_t* l0 = k.c().cfg + VC_LAYER0;
    CHECK(l0[VC_L_MODE] == (VC_TILE | 0x10) && k.c().cfg[VC_DC_CTRL] == 0x0F);
    // The pointer follows the mouse.
    k.mouse(300, 200);
    const uint8_t* s0 = k.c().vram + VC_RESET_SPR_BASE;
    CHECK(s0[2] == 1 && s0[3] == 300 - 256 && s0[5] == 200);
    // The pen: a dot at 2,3 in white (color 15).
    k.mouse(Kit::zx(2), Kit::zy(3));
    k.mouse(Kit::zx(2), Kit::zy(3), 1);
    k.mouse(Kit::zx(2), Kit::zy(3), 0);
    CHECK(k.pix4(0, 2, 3) == 15 && k.pix4(0, 3, 3) == 0);
    CHECK(k.shows(0, "TILEKIT (NEW)*"));
    // Magnified, it is white; the tile layer on the left shows it too.
    CHECK(k.panel(24 + 2 * 16 + 4, 56 + 3 * 16 + 4) == 15);
    // A drag draws without gaps.
    k.mouse(Kit::zx(0), Kit::zy(6), 1);
    k.mouse(Kit::zx(7), Kit::zy(6), 1);
    k.mouse(Kit::zx(7), Kit::zy(6), 0);
    for (int x = 0; x < 8; ++x) CHECK(k.pix4(0, x, 6) == 15);
    // The right button rubs out.
    k.mouse(Kit::zx(4), Kit::zy(6), 2);
    k.mouse(Kit::zx(4), Kit::zy(6), 0);
    CHECK(k.pix4(0, 4, 6) == 0 && k.pix4(0, 3, 6) == 15);
    // Another color (red, 9) from the palette; the line tool, a diagonal.
    k.click(kPanelX + 8 + 9 * 10 + 4, 192 + 3);
    CHECK(k.shows(29, "COLOR 009"));
    k.key(0x0F); // L
    CHECK(k.shows(29, "LINE"));
    k.mouse(Kit::zx(0), Kit::zy(0), 1);
    k.mouse(Kit::zx(3), Kit::zy(2), 1);
    k.mouse(Kit::zx(5), Kit::zy(5), 1); // (the line follows the mouse until let go)
    k.mouse(Kit::zx(5), Kit::zy(5), 0);
    CHECK(k.pix4(0, 0, 0) == 9 && k.pix4(0, 5, 5) == 9 && k.pix4(0, 3, 3) == 9);
    CHECK(k.pix4(0, 3, 2) == 0); // (the line to 3,2 is gone)
    // Fill: everything 0 that touches 7,0 becomes 9, up to the line and the row of white.
    k.click(kPanelX + 1 + 2 * 25 + 10, 20 + 10); // the fill button
    CHECK(k.shows(29, "FILL"));
    k.click(Kit::zx(7), Kit::zy(0));
    CHECK(k.pix4(0, 7, 0) == 9 && k.pix4(0, 7, 5) == 9 && k.pix4(0, 0, 5) == 0 && k.pix4(0, 7, 7) == 0);
    CHECK(k.pix4(0, 2, 3) == 15);
    // Undo, three times: the fill, the line, the rubbing out.
    k.key(0x18); // U
    CHECK(k.pix4(0, 7, 0) == 0 && k.pix4(0, 5, 5) == 9);
    k.key(0x1D, false, true); // ^Z
    CHECK(k.pix4(0, 5, 5) == 0 && k.pix4(0, 0, 0) == 0);
    k.key(0x18);
    CHECK(k.pix4(0, 4, 6) == 15);
    k.mouse(Kit::zx(6), Kit::zy(2));
    k.dump("2-drawn");
}

TEST(tilekit_adds_tiles_saves_and_opens_a_set) {
    Kit k;
    if (!k.ok) return;
    k.type("TILEKIT");
    k.frames(60);
    k.key(0x17); // T: 16x16
    k.key(0x07); // D: 256 colors
    CHECK(k.shows(11, "16x16") && k.shows(12, "256 (8 BITS"));
    k.key(0x28);
    k.frames(30);
    CHECK(k.shows(29, "16x16") && k.shows(29, "256 COLORS"));
    // 16x16 tiles: 8 screen pixels a pixel. Color 196 (red), a dot at 15,15.
    k.click(kPanelX + 8 + 4 * 10 + 4, 192 + 12 * 8 + 3);
    CHECK(k.shows(29, "COLOR 196"));
    auto zx = [](int x) { return kPanelX + 24 + x * 8 + 4; };
    auto zy = [](int y) { return 56 + y * 8 + 4; };
    k.click(zx(15), zy(15));
    CHECK(k.vram(kTiles + 255) == 196);
    // NEW (the button), then D (a copy of it): three tiles, the third like the second.
    k.click(70 * 8 + 4, 21 * 16 + 8);
    CHECK(k.shows(29, "TILE 0001/0002") && k.shows(21, "0002 TILES"));
    k.click(zx(0), zy(0));
    k.key(0x07); // D
    CHECK(k.shows(29, "TILE 0002/0003"));
    CHECK(k.vram(kTiles + 256) == 196 && k.vram(kTiles + 512) == 196 && k.vram(kTiles + 511) == 0);
    // The set: click the first tile.
    k.click(kPanelX + 3 + 8, 352 + 8);
    CHECK(k.shows(29, "TILE 0000/0003"));
    // Changing a color: green all the way up on color 196.
    k.mouse(kPanelX + 48 + 10, 322 + 5, 1);
    k.mouse(kPanelX + 48 + 200, 322 + 5, 1);
    k.mouse(kPanelX + 48 + 200, 322 + 5, 0);
    uint16_t c196 = static_cast<uint16_t>(k.c().cfg[0x200 + 2 * 196] << 8 | k.c().cfg[0x201 + 2 * 196]);
    CHECK(c196 == 0xFFE0); // red 31, green 63, blue 0
    CHECK(k.shows(29, "R31 G63 B00"));
    // ^S: the name, and saved.
    k.key(0x16, false, true);
    CHECK(k.shows(28, "SAVE AS: _"));
    k.text("SET1");
    CHECK(k.shows(28, "SAVE AS: SET1_"));
    k.key(0x28);
    k.frames(30);
    CHECK(k.shows(28, "SAVED") && k.shows(0, "SET1.TLS ") && !k.shows(0, "SET1.TLS*"));
    std::vector<uint8_t> f = k.disk("/SET1.TLS");
    CHECK(f.size() == 16 + 512 + 3 * 256);
    if (f.size() == 16 + 512 + 3 * 256) {
        CHECK(std::string(f.begin(), f.begin() + 4) == "PTS1" && f[4] == 16 && f[5] == 8 && f[6] == 0);
        CHECK(f[8] == 0 && f[9] == 3);
        CHECK(f[16 + 2 * 196] == 0xFF && f[17 + 2 * 196] == 0xE0 && f[16 + 2 * 15] == 0xFF);
        CHECK(f[528 + 255] == 196 && f[528 + 256] == 196 && f[528 + 511] == 0);
    }
    // ^N, a new 8x8 set; then ^O opens the saved one again.
    k.key(0x11, false, true);
    CHECK(k.shows(9, "A NEW TILE SET"));
    k.key(0x17); // T: back to 8x8
    k.key(0x28);
    k.frames(30);
    CHECK(k.shows(29, "TILE 0000/0001") && k.shows(29, "8x8") && k.shows(0, "(NEW)"));
    k.key(0x12, false, true); // ^O
    CHECK(k.shows(28, "OPEN: _"));
    k.text("SET1");
    k.key(0x28);
    k.frames(60);
    CHECK(k.shows(28, "OPENED") && k.shows(29, "0000/0003") && k.shows(29, "16x16") && k.shows(29, "256 COLORS"));
    k.dump("3-opened");
    CHECK(k.vram(kTiles + 255) == 196 && k.c().cfg[0x200 + 2 * 196] == 0xFF && k.c().cfg[0x201 + 2 * 196] == 0xE0);
    // A file that isn't there: said so, and the set stays.
    k.key(0x12, false, true);
    for (int i = 0; i < 8; ++i) k.key(0x2A); // (backspace the name away)
    k.text("NOPE");
    k.key(0x28);
    CHECK(k.shows(28, "NO SUCH FILE") && k.shows(0, "SET1.TLS"));
    // A change, then Esc: asked first; N stays, Y goes back to the shell.
    k.click(zx(1), zy(1));
    k.key(0x29);
    CHECK(k.shows(28, "AREN'T SAVED"));
    k.key(0x11); // N
    CHECK(!k.shows(28, "AREN'T SAVED"));
    k.key(0x29);
    k.key(0x1C); // Y
    CHECK(k.prompt(200000000));
    CHECK(k.c().in_ctrl == 0);
}

TEST(tilekit_opens_the_file_it_is_given_or_makes_it) {
    Kit k;
    if (!k.ok) return;
    k.type("TILEKIT NEWONE");
    k.frames(60);
    CHECK(k.shows(9, "A NEW TILE SET") && k.shows(28, "A NEW FILE"));
    k.key(0x28);
    k.frames(30);
    CHECK(k.shows(0, "NEWONE.TLS"));
    k.key(0x16, false, true);
    CHECK(k.shows(28, "SAVE AS: NEWONE.TLS_"));
    k.key(0x28);
    k.frames(30);
    CHECK(k.disk("/NEWONE.TLS").size() == 16 + 512 + 32);
    k.key(0x29);
    CHECK(k.prompt(200000000));
    k.type("TILEKIT NEWONE.TLS");
    k.frames(90);
    CHECK(k.shows(28, "OPENED") && k.shows(29, "0000/0001"));
}

TEST(tilekit_picks_clears_moves_between_tiles_and_scrolls_the_set) {
    Kit k;
    if (!k.ok) return;
    k.type("TILEKIT");
    k.frames(60);
    k.key(0x15); // R: 640x480
    CHECK(k.shows(13, "640x480"));
    k.key(0x28);
    k.frames(30);
    CHECK(k.shows(29, "640x480") && (k.c().cfg[VC_LAYER0 + VC_L_MODE] & 0x04));
    // A green dot (color 2, row 0) at 1,1; then pick it back up after choosing another color.
    k.click(kPanelX + 8 + 2 * 10 + 4, 192 + 3);
    k.click(Kit::zx(1), Kit::zy(1));
    CHECK(k.pix4(0, 1, 1) == 2);
    k.key(0x2E); // = : the next color
    CHECK(k.shows(29, "COLOR 003"));
    k.key(0x0E); // K: pick
    k.click(Kit::zx(1), Kit::zy(1));
    CHECK(k.shows(29, "COLOR 002") && k.shows(29, "PICK"));
    // PgDn: the next row of the palette, the same place in it; the tile's dot is drawn in it.
    k.key(0x4E);
    CHECK(k.shows(29, "COLOR 018"));
    CHECK(k.c().vram[0x016000] == 0x10 && k.c().vram[0x016001] == 0); // (layer 0's map: row 1, tile 0)
    // The clear button empties the tile; undo brings it back.
    k.click(kPanelX + 1 + 5 * 25 + 10, 20 + 10);
    CHECK(k.pix4(0, 1, 1) == 0);
    k.click(kPanelX + 1 + 6 * 25 + 10, 20 + 10);
    CHECK(k.pix4(0, 1, 1) == 2);
    // 70 tiles (N), the set scrolled to the end to show the newest; the arrows move about.
    for (int i = 0; i < 69; ++i) {
        k.v.key(0x11, true);
        k.v.key(0x11, false);
        k.frames(2);
    }
    k.frames(10);
    CHECK(k.shows(29, "TILE 0069/0070") && k.shows(21, "0070 TILES"));
    k.key(0x50); // left
    CHECK(k.shows(29, "TILE 0068/0070"));
    k.key(0x52); // up: 10 back
    CHECK(k.shows(29, "TILE 0058/0070"));
    k.key(0x4F); // right
    CHECK(k.shows(29, "TILE 0059/0070"));
    // The wheel, over the set: back to the top; a click there is tile 0's.
    k.mouse(kPanelX + 50, 380);
    for (int i = 0; i < 3; ++i) {
        k.v.mouse_wheel(1);
        k.frames(3);
    }
    k.click(kPanelX + 3 + 8, 352 + 8);
    CHECK(k.shows(29, "TILE 0000/0070"));
    k.mouse(kPanelX + 50, 380);
    k.v.mouse_wheel(-5);
    k.frames(5);
    k.click(kPanelX + 3 + 8, 352 + 8); // the first in sight now: row 1
    CHECK(k.shows(29, "TILE 0010/0070"));
    k.dump("4-many");
}

