// TILEKIT (gamekit/): the tile set and map editor, run on the emulated machine with the video card
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
            disk_file("TK_MAP.ASM", host_file(repo + "/gamekit/tk_map.asm")),
            disk_file("TK_SRC.ASM", host_file(repo + "/gamekit/tk_src.asm")),
            disk_file("TK_INI.ASM", host_file(repo + "/gamekit/tk_ini.asm")),
            disk_file("TK_LAYER.ASM", host_file(repo + "/gamekit/tk_layer.asm")),
            disk_file("TK_LDLG.ASM", host_file(repo + "/gamekit/tk_ldlg.asm")),
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
    // A variable of TILEKIT's, by its name in the listing lwasm made.
    uint32_t sym(const std::string& name) {
        std::string lst = host_file(std::string(REPO_DIR) + "/gamekit/build/tilekit.lst");
        std::string key = "[ G] " + name + " ";
        size_t at = lst.find(key);
        if (at == std::string::npos) return 0;
        size_t nl = lst.find('\n', at);
        std::string line = lst.substr(at, nl - at);
        return static_cast<uint32_t>(std::stoul(line.substr(line.find_last_of(' ') + 1), nullptr, 16));
    }
    uint8_t ram(const std::string& name, int offset = 0) {
        return s.bus.read_cpu(static_cast<uint16_t>(sym(name) + offset));
    }
    uint16_t ram16(const std::string& name) { return static_cast<uint16_t>(ram(name) << 8 | ram(name, 1)); }
    // A 24-bit video memory address TILEKIT keeps (TBASE, MBASE: the layer being edited's).
    uint32_t var24(const std::string& name) {
        return static_cast<uint32_t>(ram(name) << 16 | ram(name, 1) << 8 | ram(name, 2));
    }
    const vc_card& c() { return v.card(); }
    // A cell of the map (64 wide unless said; at `base`, or TILEKIT's), and the layer's scrolling.
    uint16_t cell(int x, int y, int w = 64, int64_t base = -1) {
        uint32_t a = (base < 0 ? var24("MBASE") : static_cast<uint32_t>(base)) + static_cast<uint32_t>((y * w + x) * 2);
        return static_cast<uint16_t>(vram(a) << 8 | vram(a + 1));
    }
    // The screen place of map cell x, y: 8x8 tiles at 320x240, 16 screen pixels a cell.
    static int mx(int x) { return x * 16 + 8; }
    static int my(int y) { return y * 16 + 8; }
    uint8_t vram(uint32_t a) { return c().vram[a & (VC_VRAM_SIZE - 1)]; }
    // A text row of the 80x30 screen (what TILEKIT has written there: its shadow).
    std::string row(int r) {
        std::string t;
        uint32_t at = sym("TXSHADOW") + static_cast<uint32_t>(r * 80);
        for (int col = 0; col < 80; ++col) t += static_cast<char>(s.bus.read_cpu(static_cast<uint16_t>(at + col)));
        return t;
    }
    bool shows(int r, const std::string& what) { return row(r).find(what) != std::string::npos; }
    // A pixel of the panel (its own coordinates), as a palette index: in its columns' bitmaps.
    uint8_t panel(int x, int y) {
        if (x < 64) return vram(sym("PCOL0") + static_cast<uint32_t>(y * 64 + x));
        if (x < 128) return vram(sym("PCOL1") + static_cast<uint32_t>(y * 64 + x - 64));
        if (x < 160) return vram(sym("PCOL2") + static_cast<uint32_t>(y * 32 + x - 128));
        return vram(sym("PCOL3") + static_cast<uint32_t>(y * 16 + x - 160));
    }
    // A pixel value of tile t of an 8x8, 4-bit set (the tiles at `base`, or TILEKIT's).
    int pix4(int t, int x, int y, int64_t base = -1) {
        uint32_t b0 = base < 0 ? var24("TBASE") : static_cast<uint32_t>(base);
        uint8_t b = vram(b0 + static_cast<uint32_t>(t * 32 + (y * 8 + x) / 2));
        return x & 1 ? b & 15 : b >> 4;
    }
    // The sprite table.
    const uint8_t* sprite(int n) { return c().vram + sym("GK_SPRTAB") + n * 8; }
    // The magnified tile's pixel x, y (8x8 tiles: 16 screen pixels each), on the screen.
    static int zx(int x) { return kPanelX + 24 + x * 16 + 8; }
    static int zy(int y) { return 60 + y * 16 + 8; }
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
    CHECK(k.s.received.find("rror") == std::string::npos && k.s.received.find("Cannot") == std::string::npos);
    std::vector<uint8_t> made = k.disk("/TK.BIN");
    CHECK(!made.empty() && std::string(made.begin(), made.end()) == k.bin);

}

TEST(tilekit_makes_a_set_and_draws_with_the_pen_line_and_fill) {
    Kit k;
    if (!k.ok) return;
    k.type("TILEKIT");
    k.frames(60);
    // The questions: an 8x8, 16-color set for 320x240 unless changed.
    CHECK(k.shows(2, "NEW TILE SET AND MAP") && k.shows(4, "8x8") && k.shows(5, "16 (4 BIT)") && k.shows(6, "320x240"));
    k.dump("1-dialog");
    CHECK(k.c().in_ctrl == (VC_IN_POINTER | VC_IN_KEYS));
    k.key(0x28); // Enter
    k.frames(30);
    CHECK(!k.shows(2, "NEW TILE SET AND MAP"));
    CHECK(k.shows(29, "TILE 0000/0001") && k.shows(29, " 8x8 16 ") && k.ram("TOOL") == 0);
    CHECK(k.shows(1, "TILES (NEW)") && k.shows(28, "MAP   (NEW)") && k.shows(29, "MAP 064x064"));
    const uint8_t* l0 = k.c().cfg + VC_LAYER0;
    CHECK(l0[VC_L_MODE] == (VC_TILE | 0x10) && k.c().cfg[VC_DC_CTRL] == 0x0F); // (3 layers, sprites)
    // The pointer follows the mouse.
    k.mouse(300, 200);
    const uint8_t* s0 = k.sprite(0);
    CHECK(s0[2] == 1 && s0[3] == 300 - 256 && s0[5] == 200);
    // The pen: a dot at 2,3 in white (color 15).
    k.mouse(Kit::zx(2), Kit::zy(3));
    k.mouse(Kit::zx(2), Kit::zy(3), 1);
    k.mouse(Kit::zx(2), Kit::zy(3), 0);
    CHECK(k.pix4(0, 2, 3) == 15 && k.pix4(0, 3, 3) == 0);
    CHECK(k.shows(1, "TILES (NEW)*"));
    // Magnified, it is white; the tile layer on the left shows it too.
    CHECK(k.panel(24 + 2 * 16 + 4, 60 + 3 * 16 + 4) == 15);
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
    CHECK(k.ram("TOOL") == 1);
    k.mouse(Kit::zx(0), Kit::zy(0), 1);
    k.mouse(Kit::zx(3), Kit::zy(2), 1);
    k.mouse(Kit::zx(5), Kit::zy(5), 1); // (the line follows the mouse until let go)
    k.mouse(Kit::zx(5), Kit::zy(5), 0);
    CHECK(k.pix4(0, 0, 0) == 9 && k.pix4(0, 5, 5) == 9 && k.pix4(0, 3, 3) == 9);
    CHECK(k.pix4(0, 3, 2) == 0); // (the line to 3,2 is gone)
    // Fill: everything 0 that touches 7,0 becomes 9, up to the line and the row of white.
    k.click(kPanelX + 1 + 2 * 25 + 10, 34 + 10); // the fill button
    CHECK(k.ram("TOOL") == 2);
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
    CHECK(k.shows(4, "16x16") && k.shows(5, "256 (8 BIT)"));
    k.key(0x28);
    k.frames(30);
    CHECK(k.shows(29, " 16x16 256"));
    // 16x16 tiles: 8 screen pixels a pixel. Color 196 (red), a dot at 15,15.
    k.click(kPanelX + 8 + 4 * 10 + 4, 192 + 12 * 8 + 3);
    CHECK(k.shows(29, "COLOR 196"));
    auto zx = [](int x) { return kPanelX + 24 + x * 8 + 4; };
    auto zy = [](int y) { return 60 + y * 8 + 4; };
    k.click(zx(15), zy(15));
    CHECK(k.vram(k.var24("TBASE") + 255) == 196);
    // NEW (the button), then D (a copy of it): three tiles, the third like the second.
    k.click(70 * 8 + 4, 21 * 16 + 8);
    CHECK(k.shows(29, "TILE 0001/0002") && k.shows(21, "0002 TILES"));
    k.click(zx(0), zy(0));
    k.key(0x07); // D
    k.frames(10);
    CHECK(k.shows(29, "TILE 0002/0003"));
    CHECK(k.vram(k.var24("TBASE") + 256) == 196 && k.vram(k.var24("TBASE") + 512) == 196 && k.vram(k.var24("TBASE") + 511) == 0);
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
    CHECK(k.shows(28, "SAVE THE TILE SET AS: _"));
    k.text("SET1");
    CHECK(k.shows(28, "SAVE THE TILE SET AS: SET1_"));
    k.key(0x28);
    k.frames(30);
    CHECK(k.shows(28, "SAVED") && k.shows(1, "SET1.TLS ") && !k.shows(1, "SET1.TLS*")); // (the map: unchanged)
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
    CHECK(k.shows(2, "NEW TILE SET AND MAP"));
    k.key(0x17); // T: back to 8x8
    k.key(0x28);
    k.frames(30);
    CHECK(k.shows(29, "TILE 0000/0001") && k.shows(29, " 8x8") && k.shows(1, "(NEW)"));
    k.key(0x12, false, true); // ^O
    CHECK(k.shows(28, "OPEN: _"));
    k.text("SET1");
    k.key(0x28);
    k.frames(60);
    CHECK(k.shows(28, "OPENED") && k.shows(29, "0000/0003") && k.shows(29, " 16x16 256"));
    k.dump("3-opened");
    CHECK(k.vram(k.var24("TBASE") + 255) == 196 && k.c().cfg[0x200 + 2 * 196] == 0xFF && k.c().cfg[0x201 + 2 * 196] == 0xE0);
    // A file that isn't there: said so, and the set stays.
    k.key(0x12, false, true);
    for (int i = 0; i < 8; ++i) k.key(0x2A); // (backspace the name away)
    k.text("NOPE");
    k.key(0x28);
    CHECK(k.shows(28, "NO SUCH FILE") && k.shows(1, "SET1.TLS"));
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
    CHECK(k.shows(2, "NEW TILE SET AND MAP") && k.shows(28, "A NEW FILE"));
    k.key(0x28);
    k.frames(30);
    CHECK(k.shows(1, "NEWONE.TLS"));
    CHECK(k.shows(1, "NEWONE.TLS*")); // (not written yet)
    k.key(0x16, false, true); // ^S: it has a name, so no question
    k.frames(30);
    CHECK(k.shows(28, "SAVED") && k.shows(1, "NEWONE.TLS "));
    CHECK(k.disk("/NEWONE.TLS").size() == 16 + 512 + 32 + 1); // (+ the tile's row)
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
    CHECK(k.shows(6, "640x480"));
    k.key(0x28);
    k.frames(30);
    CHECK(k.c().cfg[VC_LAYER0 + VC_L_MODE] & 0x04);
    // A green dot (color 2, row 0) at 1,1; then pick it back up after choosing another color.
    k.click(kPanelX + 8 + 2 * 10 + 4, 192 + 3);
    k.click(Kit::zx(1), Kit::zy(1));
    CHECK(k.pix4(0, 1, 1) == 2);
    k.key(0x2E); // = : the next color
    CHECK(k.shows(29, "COLOR 003"));
    k.key(0x0E); // K: pick
    k.click(Kit::zx(1), Kit::zy(1));
    CHECK(k.shows(29, "COLOR 002") && k.ram("TOOL") == 3);
    // PgDn: the next row of the palette, the same place in it; the tile's dot is drawn in it.
    k.key(0x4E);
    CHECK(k.shows(29, "COLOR 018"));
    // The clear button empties the tile; undo brings it back.
    k.click(kPanelX + 1 + 5 * 25 + 10, 34 + 10);
    CHECK(k.pix4(0, 1, 1) == 0);
    k.click(kPanelX + 1 + 6 * 25 + 10, 34 + 10);
    CHECK(k.pix4(0, 1, 1) == 2);
    // 70 tiles (N), the set scrolled to the end to show the newest; the arrows move about.
    for (int i = 0; i < 69; ++i) {
        k.v.key(0x11, true);
        k.v.key(0x11, false);
        k.frames(2);
    }
    k.frames(10);
    CHECK(k.shows(29, "TILE 0069/0070") && k.shows(21, "0070 TILES"));
    k.key(0x36); // ,
    CHECK(k.shows(29, "TILE 0068/0070"));
    k.key(0x36, true); // <
    CHECK(k.shows(29, "TILE 0067/0070"));
    k.key(0x37); // .
    CHECK(k.shows(29, "TILE 0068/0070"));
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
    k.click(kPanelX + 3 + 8, 352 + 8); // the first in sight now: row 2 (5 rows of 10 in sight)
    CHECK(k.shows(29, "TILE 0020/0070"));
    k.dump("4-many");
}


TEST(tilekit_puts_tiles_on_the_map_with_every_tool_and_undoes_them) {
    Kit k;
    if (!k.ok) return;
    k.type("TILEKIT");
    k.frames(60);
    CHECK(k.shows(7, "MAP W  64") && k.shows(8, "MAP H  64") && k.shows(9, "KEEP   NO"));
    k.key(0x28);
    k.frames(30);
    CHECK(k.c().cfg[VC_LAYER0 + VC_L_MAP] == 0x05 && k.c().cfg[VC_SPR_COUNT] == 42); // 64x64; 2 + 40 for the surfaces
    // Tile 1: a dot. The map is all tile 0 to start with.
    k.key(0x11); // N
    k.click(Kit::zx(0), Kit::zy(0));
    CHECK(k.pix4(1, 0, 0) == 15 && k.cell(3, 2) == 0);
    // The cell under the mouse: framed by sprite 1, and in the status line.
    k.mouse(Kit::mx(3), Kit::my(2));
    const uint8_t* s1 = k.sprite(1);
    CHECK(s1[3] == 48 && s1[5] == 32 && (s1[6] >> 6) == 3 && (s1[6] & 0x0F) == 0x05); // 16x16, in front
    CHECK(k.shows(29, "AT 003,002"));
    k.mouse(kPanelX + 50, 100);
    CHECK((s1[6] >> 6) == 0 && k.shows(29, "AT ---,---"));
    // The pen: tile 1 at 3,2; flipped across (H) at 4,2; in palette row 1 at 5,2.
    k.click(Kit::mx(3), Kit::my(2));
    CHECK(k.cell(3, 2) == 0x0001 && k.shows(28, "MAP   (NEW)*"));
    k.key(0x0B); // H
    CHECK(k.shows(29, "FLIP H-"));
    k.click(Kit::mx(4), Kit::my(2));
    CHECK(k.cell(4, 2) == 0x0401);
    k.key(0x4E); // PgDn: row 1
    k.click(Kit::mx(5), Kit::my(2));
    CHECK(k.cell(5, 2) == 0x1401);
    k.key(0x0B); // (flips off)
    k.key(0x4B); // (row 0)
    // A drag paints without gaps; the right button rubs out (tile 0).
    k.mouse(Kit::mx(0), Kit::my(4), 1);
    k.mouse(Kit::mx(9), Kit::my(4), 1);
    k.mouse(Kit::mx(9), Kit::my(4), 0);
    for (int x = 0; x <= 9; ++x) CHECK(k.cell(x, 4) == 1);
    k.mouse(Kit::mx(5), Kit::my(4), 2);
    k.mouse(Kit::mx(5), Kit::my(4), 0);
    CHECK(k.cell(5, 4) == 0 && k.cell(6, 4) == 1);
    // The line: from 0,6 to 6,9.
    k.key(0x0F); // L
    k.mouse(Kit::mx(0), Kit::my(6), 1);
    k.mouse(Kit::mx(8), Kit::my(6), 1);
    k.mouse(Kit::mx(6), Kit::my(9), 1);
    k.mouse(Kit::mx(6), Kit::my(9), 0);
    CHECK(k.cell(0, 6) == 1 && k.cell(6, 9) == 1 && k.cell(8, 6) == 0);
    // Fill, in tile 1 flipped down, from 20,20: everything that was tile 0 and touches it
    // (all but the cells drawn on, and the cell 5,4 rubbed out -- it touches the rest).
    k.key(0x09); // F
    k.key(0x19); // V
    k.click(Kit::mx(12), Kit::my(12));
    k.frames(60); // (4000 cells: about half a second)
    int filled = 0, ones = 0;
    for (int y = 0; y < 64; ++y)
        for (int x = 0; x < 64; ++x) {
            filled += k.cell(x, y) == 0x0801;
            ones += k.cell(x, y) == 0x0001;
        }
    CHECK(k.cell(5, 4) == 0x0801 && k.cell(63, 63) == 0x0801 && k.cell(3, 2) == 1);
    CHECK(filled + ones + 2 == 64 * 64); // (+ 4,2 and 5,2)
    k.mouse(Kit::mx(7), Kit::my(7));
    k.dump("5-map-filled");
    // Undo: the fill, then the line.
    k.key(0x18);
    CHECK(k.cell(63, 63) == 0 && k.cell(6, 9) == 1);
    k.key(0x18);
    CHECK(k.cell(6, 9) == 0 && k.cell(6, 4) == 1);
    // Clear is for the map now (drawn on last); undo brings it back.
    k.key(0x06); // C
    CHECK(k.cell(3, 2) == 0 && k.cell(6, 4) == 0);
    k.key(0x18);
    CHECK(k.cell(3, 2) == 1 && k.pix4(1, 0, 0) == 15);
    // Pick: tile, flips and row from the map.
    k.key(0x0E); // K
    k.key(0x36); // , : tile 0
    k.click(Kit::mx(5), Kit::my(2));
    CHECK(k.shows(29, "TILE 0001/0002") && k.shows(29, "FLIP H-") && k.shows(29, "COLOR 031"));
}

TEST(tilekit_scrolls_the_map_and_covers_what_is_past_its_end) {
    Kit k;
    if (!k.ok) return;
    k.type("TILEKIT");
    k.frames(60);
    k.key(0x1A); // W: 128 across
    CHECK(k.shows(7, "128"));
    k.key(0x28);
    k.frames(30);
    // 128 x 64 cells of 8x8 at 320x240: 1024 x 512 of the layer's pixels; the view 232 x 224.
    CHECK(k.c().cfg[VC_LAYER0 + VC_L_MAP] == 0x06 && k.shows(29, "MAP 128x064"));
    auto hs = [&] { return k.c().cfg[VC_LAYER0 + VC_L_HSCROLL] << 8 | k.c().cfg[VC_LAYER0 + VC_L_HSCROLL + 1]; };
    auto vs = [&] { return k.c().cfg[VC_LAYER0 + VC_L_VSCROLL] << 8 | k.c().cfg[VC_LAYER0 + VC_L_VSCROLL + 1]; };
    k.key(0x4F); // right: a cell
    CHECK(hs() == 8 && vs() == 0);
    k.key(0x4F, true); // Shift: 8 cells
    CHECK(hs() == 72);
    k.key(0x51); // down
    CHECK(vs() == 8);
    for (int i = 0; i < 40; ++i) k.key(0x51); // (a frame or two apart: the card queues 32 events)
    CHECK(vs() == 512 - 224); // (no further than the end)
    k.key(0x4A); // Home
    CHECK(hs() == 0 && vs() == 0);
    // The wheel: down a cell a click; with Shift, across.
    k.mouse(200, 200);
    k.v.mouse_wheel(-2);
    k.frames(3);
    CHECK(vs() == 16);
    k.v.key(0xE1, true);
    k.v.mouse_wheel(-1);
    k.frames(3);
    k.v.key(0xE1, false);
    CHECK(hs() == 8);
    // The middle button drags the map along (a screen pixel is half a layer one).
    k.mouse(300, 300, 4);
    k.mouse(200, 260, 4);
    k.mouse(200, 260, 0);
    CHECK(hs() == 8 + 50 && vs() == 16 + 20);
    // A cell clicked on is the one shown there, scrolled.
    k.click(Kit::mx(1), Kit::my(1));
    CHECK(k.cell(1 + (58 + 8) / 8, 1 + (36 + 8) / 8, 128) == 0); // (pen with tile 0 = nothing; see below)
    k.key(0x11); // N: tile 1
    k.click(16 * 3 + 2, 16 * 3 + 2); // screen 50,50: layer 25+58, 25+36 -> cell 10, 7
    CHECK(k.cell(10, 7, 128) == 1);
    // ^N: a smaller map, 32x32 -- smaller than the view, so what is past it is covered.
    k.key(0x11, false, true);
    CHECK(k.shows(28, "AREN'T SAVED"));
    k.key(0x1C); // Y
    k.key(0x0E); // K: keep the tiles
    CHECK(k.shows(9, "YES: NEW MAP"));
    k.key(0x1A); // W: 256
    k.key(0x1A); // W: 32
    k.key(0x0B); // H: 128
    k.key(0x0B); // H: 256
    CHECK(k.shows(7, "MAP W  32") && k.shows(8, "MAP H  256"));
    k.key(0x0B); // H: 32
    k.key(0x28);
    k.frames(10);
    CHECK(k.c().cfg[VC_LAYER0 + VC_L_MAP] == 0x00 && k.shows(29, "TILE 0001/0002") && k.cell(10, 7, 32) == 0);
    // At 640x480 a 32x32 map of 8x8 tiles is 256 pixels: past it, a click does nothing.
    k.key(0x11, false, true);
    CHECK(k.shows(28, "AREN'T SAVED")); // (the tile set: tile 1 is new)
    k.key(0x1C); // Y
    k.key(0x15); // R: 640x480
    k.key(0x28);
    k.frames(30);
    k.click(40 * 8, 5 * 16); // (past the map: nothing)
    CHECK(k.ram("MAPMOD") == 0);
}

TEST(tilekit_saves_maps_that_share_a_tile_set_and_opens_them_again) {
    Kit k;
    if (!k.ok) return;
    k.type("TILEKIT");
    k.frames(60);
    k.key(0x28);
    k.frames(30);
    k.key(0x11); // N: tile 1, a dot
    k.click(Kit::zx(2), Kit::zy(2));
    k.click(Kit::mx(1), Kit::my(1));
    CHECK(k.cell(1, 1) == 1);
    // ^S: the tile set's name, then the map's.
    k.key(0x16, false, true);
    CHECK(k.shows(28, "SAVE THE TILE SET AS: _"));
    k.text("LV");
    k.key(0x28);
    k.frames(20);
    CHECK(k.shows(28, "SAVE THE MAP AS: _"));
    k.text("LV1");
    k.key(0x28);
    k.frames(20);
    CHECK(k.shows(1, "LV.TLS ") && k.shows(28, "LV1.MAP "));
    std::vector<uint8_t> m = k.disk("/LV1.MAP");
    CHECK(m.size() == 48 + 64 * 64 * 2);
    if (m.size() == 48 + 64 * 64 * 2) {
        CHECK(std::string(m.begin(), m.begin() + 4) == "PTM1" && m[5] == 64 && m[7] == 64);
        CHECK(std::string(reinterpret_cast<const char*>(&m[8])) == "LV.TLS");
        CHECK(m[48 + (1 * 64 + 1) * 2] == 0 && m[49 + (1 * 64 + 1) * 2] == 1);
    }
    CHECK(k.disk("/LV.TLS").size() == 16 + 512 + 2 * 32 + 2);
    // A second map for the same set: ^N, K, a wider map.
    k.key(0x11, false, true);
    k.key(0x0E); // K
    k.key(0x1A); // W: 128
    k.key(0x28);
    k.frames(20);
    CHECK(k.shows(1, "LV.TLS ") && k.shows(28, "MAP   (NEW)") && k.shows(29, "MAP 128x064") && k.cell(1, 1, 128) == 0);
    k.click(Kit::mx(2), Kit::my(3));
    CHECK(k.cell(2, 3, 128) == 1);
    k.key(0x16, false, true); // ^S: the set is saved already; just the map's name
    CHECK(k.shows(28, "SAVE THE MAP AS: _"));
    k.text("LV2");
    k.key(0x28);
    k.frames(20);
    CHECK(k.disk("/LV2.MAP").size() == 48 + 128 * 64 * 2);
    // ^O the first map again: its cells and size; the set as it was.
    k.key(0x12, false, true);
    for (int i = 0; i < 8; ++i) k.key(0x2A);
    k.text("LV1.MAP");
    k.key(0x28);
    k.frames(60);
    CHECK(k.shows(28, "OPENED") && k.shows(29, "MAP 064x064") && k.cell(1, 1) == 1 && k.shows(28, "LV1.MAP "));
    CHECK(k.shows(29, "TILE 0001/0002") || k.shows(29, "/0002"));
    k.key(0x29);
    CHECK(k.prompt(200000000));
    // From the shell: a map opens with its tile set.
    k.type("TILEKIT LV2.MAP");
    k.frames(120);
    CHECK(k.shows(1, "LV.TLS ") && k.shows(28, "LV2.MAP ") && k.shows(29, "MAP 128x064") && k.cell(2, 3, 128) == 1);
    CHECK(k.pix4(1, 2, 2) == 15);
    k.key(0x29);
    CHECK(k.prompt(200000000));
    // A map whose set is gone: said so.
    k.type("TILEKIT NOSUCH.MAP");
    k.frames(60);
    CHECK(k.shows(2, "NEW TILE SET AND MAP"));
    k.key(0x28);
    k.frames(20);
    CHECK(k.shows(28, "NOSUCH.MAP") && k.shows(1, "TILES (NEW)"));
}


TEST(tilekit_exports_assembly_source_that_a_game_includes) {
    // A game: the two modules, put into the card by their own routines.
    const char* game = "            INCLUDE \"VIDCARD.D\"\r\n"
                       "            ORG  $4000\r\n"
                       "START       LDA  #$02\r\n"
                       "            LDX  #$0000\r\n"
                       "            JSR  TILES_TOCARD\r\n"
                       "            LDA  #$01\r\n"
                       "            LDX  #$6000\r\n"
                       "            JSR  LV_TOCARD\r\n"
                       "            LDA  #$2B\r\n" // B_EXIT
                       "            SWI2\r\n"
                       "            FCB  TILES_LMODE,LV_LMAP,TILES_NTILES,LV_W\r\n"
                       "            INCLUDE \"TILES.ASM\"\r\n"
                       "            INCLUDE \"LV.ASM\"\r\n"
                       "            END  START\r\n";
    Kit k({disk_file("GAME.ASM", game)});
    if (!k.ok) return;
    k.type("TILEKIT");
    k.frames(60);
    k.key(0x1A); // W: 128, 256, 32
    k.key(0x1A);
    k.key(0x1A);
    k.key(0x0B); // H: 128, 256, 32
    k.key(0x0B);
    k.key(0x0B);
    CHECK(k.shows(7, "MAP W  32") && k.shows(8, "MAP H  32"));
    k.key(0x28);
    k.frames(30);
    k.key(0x11); // N: tile 1, a dot at 1,0
    k.click(Kit::zx(1), Kit::zy(0));
    k.key(0x0B); // H
    k.click(Kit::mx(2), Kit::my(3));
    CHECK(k.cell(2, 3, 32) == 0x0401);
    // ^E: the set's module (TILES.ASM, as the set has no name), then the map's.
    k.key(0x08, false, true);
    CHECK(k.shows(28, "EXPORT THE TILE SET AS: TILES.ASM_"));
    k.key(0x28);
    k.frames(30);
    CHECK(k.shows(28, "EXPORT THE MAP AS: MAP.ASM_"));
    for (int i = 0; i < 7; ++i) k.key(0x2A);
    k.text("LV");
    k.key(0x28);
    k.frames(30);
    CHECK(k.shows(28, "EXPORTED"));
    std::vector<uint8_t> t = k.disk("/TILES.ASM"), m = k.disk("/LV.ASM");
    std::string ts(t.begin(), t.end()), ms(m.begin(), m.end());
    CHECK(ts.find("TILES_LMODE EQU  17\r\n") != std::string::npos); // a tile layer, 4 bits a pixel
    CHECK(ts.find("TILES_NTILES EQU  2\r\n") != std::string::npos);
    CHECK(ts.find("TILES_PAL\r\n            FDB  $0000,$8000,$0400,$8400") != std::string::npos);
    CHECK(ts.find("; tile 1\r\n            FCB  $0F,$00,$00,$00") != std::string::npos);
    CHECK(ms.find("LV_LMAP     EQU  0\r\n") != std::string::npos && ms.find("LV_W        EQU  32") != std::string::npos);
    CHECK(ms.find("; row 3\r\n            FDB  $0000,$0000,$0401,$0000") != std::string::npos);
    // ^E again, Esc at the first: straight on to the map's.
    k.key(0x08, false, true);
    k.key(0x29);
    CHECK(k.shows(28, "EXPORT THE MAP AS: "));
    k.key(0x29);
    CHECK(k.shows(28, "P L F K E U"));
    k.key(0x29); // quit (Y: not saved)
    k.key(0x1C);
    CHECK(k.prompt(200000000));
    CHECK(k.vram(0x020000 + 32) == 0); // (the card is reset)
    // ASM on the machine makes the game from the modules; it puts them into the card.
    k.type("ASM -f com GAME.ASM");
    CHECK(k.prompt(20000000000ull));
    CHECK(k.s.received.find("rror") == std::string::npos);
    std::vector<uint8_t> com = k.disk("/GAME.COM");
    CHECK(com.size() > 8 + 512 + 64 + 2048);
    if (com.size() > 30) CHECK(com[8 + 20] == 17 && com[8 + 21] == 0 && com[8 + 22] == 2 && com[8 + 23] == 32); // (after 20 bytes of code)
    k.type("GAME");
    CHECK(k.prompt(200000000));
    CHECK(k.pix4(1, 1, 0, 0x020000) == 15 && k.pix4(1, 0, 0, 0x020000) == 0);
    CHECK(k.cell(2, 3, 32, 0x016000) == 0x0401);
    CHECK(k.c().cfg[0x200 + 2 * 9] == 0xF8 && k.c().cfg[0x201 + 2 * 9] == 0x00); // (xterm's red)
}

namespace {
uint16_t pal(Kit& k, int i) { return static_cast<uint16_t>(k.c().cfg[0x200 + 2 * i] << 8 | k.c().cfg[0x201 + 2 * i]); }
} // namespace

TEST(tilekit_takes_its_default_palettes_from_tilekit_ini) {
    // The one that comes with it, in /CMD: PICO-8's 16 in row 0 of a 16-color set.
    {
        Kit k({disk_file("CMD/TILEKIT.INI", host_file(std::string(REPO_DIR) + "/gamekit/TILEKIT.INI"))});
        if (!k.ok) return;
        k.type("TILEKIT");
        k.frames(90);
        k.key(0x28);
        k.frames(30);
        CHECK(pal(k, 1) == ((0x1D >> 3) << 11 | (0x2B >> 2) << 5 | (0x53 >> 3))); // 1D2B53
        k.click(kPanelX + 8 + 4 * 10 + 4, 192 + 4 * 8 + 3); // (a color in row 4, for the picture)
        k.click(Kit::zx(1), Kit::zy(1));
        k.click(Kit::zx(6), Kit::zy(5));
        k.dump("7-ini-palette");
        CHECK(pal(k, 31) == 0xFFFF && pal(k, 17) == ((0x11 >> 3) << 11 | (0x11 >> 2) << 5 | (0x11 >> 3)));
        // A 256-color set: its own section (xterm's).
        k.key(0x11, false, true);
        k.key(0x1C); // (Y: not saved)
        k.key(0x07); // D: 256 colors
        k.key(0x28);
        k.frames(30);
        CHECK(pal(k, 1) == 0x8000 && pal(k, 196) == 0xF800);
    }
    // One of our own, here: what it gives, in its order; the rest the card's.
    const char* ini = "; mine\r\n[palette4]\r\n#FF0000, 00ff00 ; two\r\nGARBAGE 1234567 0000FF\r\n"
                      "[OTHER]\r\n123456\r\n[PALETTE8]\n00FFFF";
    Kit k({disk_file("TILEKIT.INI", ini)});
    if (!k.ok) return;
    k.type("TILEKIT");
    k.frames(90);
    k.key(0x28);
    k.frames(30);
    CHECK(pal(k, 0) == 0xF800 && pal(k, 1) == 0x07E0 && pal(k, 2) == 0x001F); // (GARBAGE, 1234567: not colors)
    CHECK(pal(k, 3) == 0x8400); // (xterm's 3: 808000)
    k.key(0x11, false, true);
    k.key(0x07);
    k.key(0x28);
    k.frames(30);
    CHECK(pal(k, 0) == 0x07FF && pal(k, 1) == 0x8000);
}

TEST(tilekit_shows_each_tile_in_its_own_row_and_keeps_them) {
    Kit k;
    if (!k.ok) return;
    k.type("TILEKIT");
    k.frames(60);
    k.key(0x28);
    k.frames(30);
    // Tile 0: a dot in color 2 of row 2 (34).
    k.click(kPanelX + 8 + 2 * 10 + 4, 192 + 2 * 8 + 3);
    CHECK(k.shows(29, "COLOR 034"));
    k.click(Kit::zx(0), Kit::zy(0));
    auto thumb = [&](int t, int x, int y) { return k.panel(3 + (t % 10) * 17 + 2 * x, 352 + (t / 10) * 17 + 2 * y); };
    CHECK(k.pix4(0, 0, 0) == 2 && thumb(0, 0, 0) == 34);
    // Tile 1, drawn in row 5: tile 0 stays in row 2 in the set.
    k.key(0x11); // N
    k.click(kPanelX + 8 + 2 * 10 + 4, 192 + 5 * 8 + 3); // color 82
    k.click(Kit::zx(1), Kit::zy(1));
    CHECK(thumb(1, 1, 1) == 82 && thumb(0, 0, 0) == 34);
    // Another row picked: the tile being edited is shown in it; the others not.
    k.key(0x4E); // PgDn: row 6
    CHECK(thumb(1, 1, 1) == 98 && thumb(0, 0, 0) == 34);
    // Selecting tile 0: its row (2) is picked again, the same place in it.
    k.click(kPanelX + 3 + 8, 352 + 8);
    CHECK(k.shows(29, "TILE 0000/0002") && k.shows(29, "COLOR 034"));
    CHECK(thumb(1, 1, 1) == 82); // (tile 1: drawn in row 5, only looked at in 6)
    // Put on the map in row 7: that is tile 0's row now.
    k.key(0x4E);
    k.key(0x4E);
    k.key(0x4E);
    k.key(0x4E);
    k.key(0x4E); // row 7
    k.click(Kit::mx(1), Kit::my(1));
    CHECK(k.cell(1, 1) == 0x7000);
    k.key(0x37); // . : tile 1 (row 5 again)
    CHECK(k.shows(29, "COLOR 082") && thumb(0, 0, 0) == 114);
    // Saved with the set, and back when it is opened.
    k.key(0x16, false, true);
    k.text("ROWS");
    k.key(0x28);
    k.frames(20);
    std::vector<uint8_t> f = k.disk("/ROWS.TLS");
    CHECK(f.size() == 16 + 512 + 2 * 32 + 2 && f.size() > 7 && (f[6] & 2));
    if (f.size() == 16 + 512 + 2 * 32 + 2) CHECK(f[16 + 512 + 64] == 7 && f[16 + 512 + 65] == 5);
    k.key(0x11, false, true); // ^N (asks: the map isn't saved)
    k.key(0x1C);
    k.key(0x28);
    k.frames(20);
    k.key(0x12, false, true);
    for (int i = 0; i < 8; ++i) k.key(0x2A);
    k.text("ROWS");
    k.key(0x28);
    k.frames(60);
    CHECK(k.shows(28, "OPENED") && thumb(1, 1, 1) == 82 && thumb(0, 0, 0) == 114); // (row 7: tile 0, being edited, in its own row)
}

TEST(tilekit_edits_three_layers_shown_hidden_and_reordered) {
    Kit k;
    if (!k.ok) return;
    k.type("TILEKIT");
    k.frames(60);
    k.key(0x28);
    k.frames(30);
    auto hw = [&](int n) { return k.c().cfg + VC_LAYER0 + VC_LAYER_SIZE * n; };
    auto base = [&](const uint8_t* l, int at) { return static_cast<uint32_t>(l[at] << 16 | l[at + 1] << 8 | l[at + 2]); };
    // Three layers, 64x64 maps at the ends of their 48KB rooms, all on layer 1's tiles.
    CHECK(k.shows(0, "LAYERS  1  2  3") && k.c().cfg[VC_DC_CTRL] == 0x0F);
    CHECK(base(hw(0), VC_L_MAPBASE) == 0x00A000 && base(hw(1), VC_L_MAPBASE) == 0x016000 &&
          base(hw(2), VC_L_MAPBASE) == 0x022000);
    CHECK(base(hw(0), VC_L_TILEBASE) == 0 && base(hw(1), VC_L_TILEBASE) == 0 && base(hw(2), VC_L_TILEBASE) == 0);
    // Tile 1, put on layer 1's map; then layer 2 (key 2), the same tile on its map.
    k.key(0x11); // N
    k.click(Kit::zx(0), Kit::zy(0));
    k.click(Kit::mx(1), Kit::my(1));
    CHECK(k.cell(1, 1, 64, 0x00A000) == 1);
    k.key(0x1F); // 2
    CHECK(k.ram("CURL") == 1 && k.var24("MBASE") == 0x016000 && k.shows(29, "TILE 0001/0002"));
    k.click(Kit::mx(2), Kit::my(2));
    CHECK(k.cell(2, 2, 64, 0x016000) == 1 && k.cell(1, 1, 64, 0x016000) == 0 && k.cell(2, 2, 64, 0x00A000) == 0);
    // Layer 3, clicked in the bar; a cell there.
    k.click(kPanelX + (72 - 58) * 8 + 4, 8);
    CHECK(k.ram("CURL") == 2);
    k.click(Kit::mx(3), Kit::my(3));
    CHECK(k.cell(3, 3, 64, 0x022000) == 1);
    // Undo, twice: layer 3's cell, then layer 2's (going back to layer 2 to do it).
    k.key(0x18);
    CHECK(k.cell(3, 3, 64, 0x022000) == 0 && k.ram("CURL") == 2);
    k.key(0x18);
    CHECK(k.cell(2, 2, 64, 0x016000) == 0 && k.ram("CURL") == 1 && k.cell(1, 1, 64, 0x00A000) == 1);
    // Shift+1 hides layer 1; a right click on its button shows it again.
    k.key(0x1E, true);
    CHECK(k.c().cfg[VC_DC_CTRL] == 0x0E);
    k.click(kPanelX + (66 - 58) * 8 + 4, 8, 2);
    CHECK(k.c().cfg[VC_DC_CTRL] == 0x0F && k.ram("CURL") == 1);
    // ] moves layer 2 in front of layer 3: the card's layers 1 and 2 swap maps.
    k.key(0x30); // ]
    CHECK(k.ram("ORDER", 1) == 2 && k.ram("ORDER", 2) == 1);
    CHECK(base(hw(1), VC_L_MAPBASE) == 0x022000 && base(hw(2), VC_L_MAPBASE) == 0x016000);
    CHECK(k.shows(0, "LAYERS  1  3  2"));
    k.dump("8-layers");
    k.key(0x2F); // [ : back again
    CHECK(base(hw(1), VC_L_MAPBASE) == 0x016000);
    // One view: every layer scrolled with it (320x240: half the screen's pixels).
    k.key(0x4F);
    CHECK(hw(0)[VC_L_HSCROLL + 1] == 8 && hw(1)[VC_L_HSCROLL + 1] == 8 && hw(2)[VC_L_HSCROLL + 1] == 8);
}

TEST(tilekit_fits_a_layers_tiles_beside_its_map) {
    Kit k;
    if (!k.ok) return;
    k.type("TILEKIT");
    k.frames(60);
    k.key(0x17); // T: 16x16
    k.key(0x07); // D: 256 colors
    k.key(0x1A); // W: 128
    k.key(0x1A); // W: 256 (H stays 64: 16384 cells, 32KB)
    k.key(0x28);
    k.frames(30);
    // 48KB - 32KB for the map: 64 tiles of 256 bytes.
    CHECK(k.ram16("MAXT") == 64 && k.shows(29, "MAP 256x064"));
    for (int i = 0; i < 66; ++i) k.key(0x11, false, false); // (each drawn before the next: 16x16 tiles take a few frames)
    k.frames(10);
    CHECK(k.shows(29, "TILE 0063/0064") && k.shows(28, "TILE SET IS FULL"));
    // A smaller map (^N, K: keep the set; W 32): room for those, and more.
    k.key(0x11, false, true);
    k.key(0x1C);
    k.key(0x0E); // K
    k.key(0x1A); // W: 32
    k.key(0x28);
    k.frames(20);
    CHECK(k.shows(29, "MAP 032x064") && k.ram16("MAXT") > 64);
}

TEST(tilekit_changes_a_layer_keeping_what_converts) {
    Kit k;
    if (!k.ok) return;
    k.type("TILEKIT");
    k.frames(60);
    k.key(0x28);
    k.frames(30);
    auto hw = [&](int n) { return k.c().cfg + VC_LAYER0 + VC_LAYER_SIZE * n; };
    auto base = [&](const uint8_t* l, int at) { return static_cast<uint32_t>(l[at] << 16 | l[at + 1] << 8 | l[at + 2]); };
    // Tile 1: a dot at 0,0 in color 15 of row 2 (47); on the map at 1,1 and 60,60.
    k.key(0x11);
    k.click(kPanelX + 8 + 15 * 10 + 4, 192 + 2 * 8 + 3);
    k.click(Kit::zx(0), Kit::zy(0));
    k.click(Kit::mx(1), Kit::my(1));
    for (int i = 0; i < 4; ++i) k.key(0x4F, true); // (scrolled 32 cells across ...)
    for (int i = 0; i < 2; ++i) k.key(0x51, true); // (... and 16 down)
    k.click(Kit::mx(60 - 32), Kit::my(40 - 16));
    k.key(0x4A); // Home
    CHECK(k.cell(1, 1) == 0x2001 && k.cell(60, 40) == 0x2001);
    // The layer's questions: the ... in the layer bar.
    k.click(kPanelX + (76 - 58) * 8 + 4, 8);
    CHECK(k.shows(2, "LAYER 1") && k.shows(4, "TILES  ITS OWN") && k.shows(8, "MAP W  64"));
    // A wider map: the cells stay where they were.
    k.key(0x1A); // W: 128
    k.key(0x28);
    k.frames(20);
    CHECK(k.shows(29, "MAP 128x064") && k.cell(1, 1, 128) == 0x2001 && k.cell(60, 40, 128) == 0x2001);
    CHECK(k.cell(100, 1, 128) == 0 && base(hw(0), VC_L_MAPBASE) == 0x00C000 - 0x4000);
    // A smaller one (^L): what is past it is cut off.
    k.key(0x0F, false, true); // ^L
    k.key(0x1A); // 256
    k.key(0x1A); // 32
    k.key(0x28);
    k.frames(20);
    CHECK(k.shows(29, "MAP 032x064") && k.cell(1, 1, 32) == 0x2001 && k.cell(28, 28, 32) == 0);
    // 16 colors -> 256: the tiles kept, each pixel in its row.
    k.key(0x0F, false, true);
    k.key(0x07); // D
    k.key(0x28);
    k.frames(30);
    CHECK(k.shows(29, " 8x8 256") && k.vram(k.var24("TBASE") + 64) == 47 && k.vram(k.var24("TBASE") + 65) == 0);
    CHECK((hw(0)[VC_L_MODE] & 0x18) == 0x18);
    // 16x16: the tile set starts again -- once you say so.
    k.key(0x0F, false, true);
    k.key(0x17); // T
    k.key(0x28);
    CHECK(k.shows(28, "STARTS AGAIN"));
    k.key(0x11); // N: no
    CHECK(k.shows(29, " 8x8 256"));
    k.key(0x0F, false, true);
    k.key(0x17);
    k.key(0x28);
    k.key(0x1C); // Y
    k.frames(20);
    CHECK(k.shows(29, "TILE 0000/0001") && k.shows(29, " 16x16 256"));
    // Layer 2: a tile set of its own (S), 640x480 (R).
    k.key(0x1F); // 2
    k.key(0x0F, false, true);
    CHECK(k.shows(2, "LAYER 2") && k.shows(4, "TILES  LAYER 1'S"));
    k.key(0x16); // S: its own
    CHECK(k.shows(4, "TILES  ITS OWN") && k.shows(5, "8x8"));
    k.key(0x15); // R
    k.key(0x28);
    k.frames(30);
    CHECK(k.ram("CURSET") == 1 && base(hw(1), VC_L_TILEBASE) == 0x00C000 && base(hw(0), VC_L_TILEBASE) == 0);
    CHECK(k.shows(29, "TILE 0000/0001") && k.shows(29, " 8x8 16") && (hw(1)[VC_L_MODE] & 0x04) && !(hw(0)[VC_L_MODE] & 0x04));
    k.dump("9-layer-dialog");
}
