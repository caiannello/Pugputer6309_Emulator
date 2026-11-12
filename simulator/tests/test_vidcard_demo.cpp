// The video card's demos (demo/programs/ASM/VIDEO) as the demo disk has them: ASM assembles
// each on the machine -- byte for byte what the release disk's /DEMO/*.COM is -- and it runs
// with the card at $FF80, a page at a time, while these check what is on the card.
//
// VIDCARD_DUMP_DIR=folder saves each page's picture there (NAME-PAGE.rgb: 640x480 RGB bytes).
#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <iterator>
#include <string>
#include <vector>

#include "basic309_session.hpp"
#include "disk_images.hpp"
#include "fat16_reader.hpp"
#include "pugputer/opl3_device.hpp"
#include "pugputer/video_device.hpp"
#include "test_framework.hpp"
#include "vc.h"

using pugputer::VideoDevice;

namespace {

constexpr uint64_t kSecond = 3579545;

std::string host_text(const std::string& path) {
    std::ifstream f(path, std::ios::binary);
    return std::string((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
}

pugputer::Fat16File disk_file(const char* name, const std::string& data) {
    pugputer::Fat16File f;
    f.name = name;
    f.data.assign(data.begin(), data.end());
    return f;
}

uint16_t be16(const uint8_t* p) { return static_cast<uint16_t>(p[0] << 8 | p[1]); }

// A demo, assembled by ASM on the machine and ready to run with the card.
struct Demo {
    std::string name; // e.g. "VIDTEXT"
    std::string img;
    Basic309Session s;
    VideoDevice v;
    bool built = false;

    // (extra: more files for the disk -- what the demo reads)
    explicit Demo(const std::string& n, std::vector<pugputer::Fat16File> extra = {}) : name(n) {
        std::string dir = std::string(DEMO_DIR) + "/ASM/VIDEO/";
        std::string src = host_text(dir + name + ".ASM");
        std::string lib = host_text(dir + "VIDLIB.ASM");
        std::string inc = host_text(std::string(REPO_DIR) + "/vidcard/vidcard.d");
        std::string asm_com = host_text(ASM_BIN_PATH);
        std::string player = host_text(std::string(REPO_DIR) + "/gamekit/sk_play.asm"); // (SWAMP's music)
        CHECK(!src.empty() && !lib.empty() && !inc.empty() && !asm_com.empty() && !player.empty());
        std::string file = name + ".ASM";
        std::vector<pugputer::Fat16File> files = {disk_file(file.c_str(), src), disk_file("VIDLIB.ASM", lib),
                                                  disk_file("VIDCARD.D", inc), disk_file("SK_PLAY.ASM", player),
                                                  disk_file("ASM.COM", asm_com),
                                                  disk_file("CMD/KEEP.TXT", "(so that /CMD is there)")};
        files.insert(files.end(), extra.begin(), extra.end());
        img = build_image((name + ".img").c_str(), 32768, 4, files);
        v.set_draw_all(true);
        s.attach_video(&v);
        CHECK(s.boot_shell(PUGBIOS_S19_PATH, img.c_str()));
        type("ASM -f com " + name + ".ASM");
        CHECK(prompt(8000000000ull));
        CHECK(s.received.find("rror") == std::string::npos);
        if (s.received.find("rror") != std::string::npos) std::printf("%s\n", s.received.c_str()); // (what ASM said)
        Fat16Volume vol;
        Fat16Volume::Entry e;
        CHECK(vol.load(img.c_str()) && vol.find("/" + name + ".COM", e));
        std::string lower = name;
        std::transform(lower.begin(), lower.end(), lower.begin(), [](char c) { return static_cast<char>(c | 0x20); });
        std::string raw = host_text(std::string(REPO_DIR) + "/demo/build/" + lower + ".bin");
        std::vector<uint8_t> made = vol.read(e);
        built = !raw.empty() && std::string(made.begin(), made.end()) == std::string("PX\x40\x00\x40\x00\x00\x00", 8) + raw;
        CHECK(built);
        CHECK(!v.active());
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
    void run(double seconds) { s.bus.run(static_cast<uint64_t>(seconds * kSecond)); }
    void key(char c = ' ') { s.send_byte(static_cast<uint8_t>(c)); }
    const vc_card& c() { return v.card(); }
    uint8_t vram(uint32_t a) { return c().vram[a & (VC_VRAM_SIZE - 1)]; }
    const uint8_t* cfg(int offset) { return c().cfg + offset; }
    const uint8_t* layer(int n) { return c().cfg + VC_LAYER0 + VC_LAYER_SIZE * n; }
    // The color the card shows for palette entry i.
    uint32_t shown(int i) { return vc_rgb888(static_cast<uint16_t>(c().cfg[0x200 + 2 * i] << 8 | c().cfg[0x201 + 2 * i])); }
    // A text cell of a 128-wide map.
    const uint8_t* cell(uint32_t map, int col, int row) { return c().vram + map + (row * 128 + col) * 4; }
    int count(int x0, int y0, int x1, int y1, uint32_t rgb) {
        int n = 0;
        for (int y = y0; y < y1; ++y)
            for (int x = x0; x < x1; ++x) n += v.pixel(x, y) == rgb;
        return n;
    }
    void dump(const std::string& page) {
        const char* dir = std::getenv("VIDCARD_DUMP_DIR");
        if (!dir) return;
        std::ofstream f(std::string(dir) + "/" + name + "-" + page + ".rgb", std::ios::binary);
        for (int i = 0; i < VideoDevice::kWidth * VideoDevice::kHeight; ++i) {
            uint32_t p = v.pixels()[i];
            char rgb[3] = {static_cast<char>(p >> 16), static_cast<char>(p >> 8), static_cast<char>(p)};
            f.write(rgb, 3);
        }
    }
};

} // namespace

TEST(vidcard_demo_viddemo_draws_its_scene) {
    Demo d("VIDDEMO");
    if (!d.built) return;
    d.type("VIDDEMO");
    d.run(1.0);
    CHECK(d.v.active() && d.v.frames_drawn() >= 55);
    CHECK(d.cfg(VC_DC_CTRL)[0] == 0x0F && d.cfg(VC_SPR_COUNT)[0] == 8);
    // Layer 0, the bitmap: the sky's top band, the sun, the black ground.
    CHECK(d.v.pixel(0, 0) == d.shown(17) && d.v.pixel(639, 19) == d.shown(17) && d.v.pixel(0, 20) == d.shown(18));
    CHECK(d.v.pixel(320, 200) == d.shown(214));
    CHECK(d.v.pixel(8, 460) == d.shown(16));
    // Layer 2, the title: white letters on black at row 1, columns 27-52.
    CHECK(d.count(27 * 8, 16, 53 * 8, 32, d.shown(231)) > 200);
    // Layer 1 scrolls a pixel a frame; the balls move.
    const uint8_t* hs = d.layer(1) + VC_L_HSCROLL;
    const uint8_t* ball = d.c().vram + VC_RESET_SPR_BASE;
    uint16_t scroll = be16(hs), bx = be16(ball + 2), by = be16(ball + 4);
    CHECK(scroll >= 45 && scroll <= 61); // (less the time it takes to load and set up)
    CHECK(ball[6] == 0xC5 && ball[7] == 0x80);
    d.run(0.5);
    CHECK(be16(hs) - scroll >= 29 && be16(hs) - scroll <= 31);
    CHECK(be16(ball + 2) != bx && be16(ball + 4) != by);
    CHECK(d.v.pixel(be16(ball + 2) * 2 + 14, be16(ball + 4) * 2 + 14) == d.shown(196));
    d.dump("1");
    d.key();
    CHECK(d.prompt(100000000));
    CHECK(d.cfg(VC_DC_CTRL)[0] == 0x01 && d.cfg(VC_DC_BACK)[0] == 0);
}

TEST(vidcard_demo_vidtext_shows_the_text_layers) {
    Demo d("VIDTEXT");
    if (!d.built) return;
    d.type("VIDTEXT");
    d.run(1.5);
    // Page 1: the characters and the colors, framed, on layer 0; the marquee on layer 1.
    CHECK(d.cfg(VC_DC_CTRL)[0] == 0x03 && d.layer(1)[VC_L_MODE] == (VC_TEXT | 0x20));
    for (int ch : {0, 1, 0x41, 0xC9, 0xFF}) {
        const uint8_t* cell = d.cell(VC_RESET_TEXT_MAP, 5 + 2 * (ch % 16), 4 + ch / 16);
        CHECK(cell[0] == ch && cell[1] == 15 && cell[2] == 16);
        const uint8_t* color = d.cell(VC_RESET_TEXT_MAP, 44 + 2 * (ch % 16), 4 + ch / 16);
        CHECK(color[0] == ' ' && color[2] == ch);
    }
    CHECK(d.cell(VC_RESET_TEXT_MAP, 4, 3)[0] == 0xC9 && d.cell(VC_RESET_TEXT_MAP, 37, 20)[0] == 0xBC);
    CHECK(d.cell(VC_RESET_TEXT_MAP, 37, 10)[0] == 0xBA && d.cell(VC_RESET_TEXT_MAP, 76, 3)[0] == 0xBB);
    // The ID and version the card gave, "V" and "1.2".
    CHECK(d.cell(VC_RESET_TEXT_MAP, 23, 26)[0] == 'V' && d.cell(VC_RESET_TEXT_MAP, 23, 26)[1] == 226);
    CHECK(d.cell(VC_RESET_TEXT_MAP, 34, 26)[0] == '1' && d.cell(VC_RESET_TEXT_MAP, 36, 26)[0] == '2');
    // The marquee moves; its letters show, doubled, at rows 22-23.
    uint16_t hs = be16(d.layer(1) + VC_L_HSCROLL);
    CHECK(hs > 60);
    d.run(0.5);
    CHECK(be16(d.layer(1) + VC_L_HSCROLL) - hs >= 29);
    const uint8_t* marquee = d.c().vram + 0x030000 + (11 * 64 + 2) * 4; // (a 64-cell-wide map)
    CHECK(marquee[0] == '*' && marquee[2] == 0);
    int side = 0; // a side of the first box: the leftmost lit pixel in row 8 of its corner
    while (!(vc_font8x16[0xC9 * 16 + 8] & (0x80 >> side))) ++side;
    CHECK(d.v.pixel(4 * 8 + side, 3 * 16 + 8) == d.shown(75));
    d.dump("1");
    // Page 2: the 8x8 font is the 8x16 one, two lines ORed into one.
    d.key();
    d.run(1.5);
    bool font_ok = true;
    for (int ch = 0; ch < 256; ++ch)
        for (int r = 0; r < 8; ++r)
            font_ok = font_ok && d.vram(0x03E000 + ch * 8 + r) == (vc_font8x16[ch * 16 + 2 * r] | vc_font8x16[ch * 16 + 2 * r + 1]);
    CHECK(font_ok);
    CHECK(d.layer(0)[VC_L_MODE] == (VC_TEXT | 0x04) && d.layer(0)[VC_L_MAP] == 0x06);
    CHECK(d.cell(0x020000, 4, 0)[0] == 'T' && d.cell(0x020000, 4, 2)[0] == 'T');
    uint16_t vs = be16(d.layer(0) + VC_L_VSCROLL);
    CHECK(vs > 60);
    d.run(0.5);
    CHECK(be16(d.layer(0) + VC_L_VSCROLL) - vs >= 29);
    CHECK(d.count(0, 0, 640, 16, d.shown(18)) > 5000); // the heading's bar stays put
    d.dump("2");
    d.key();
    CHECK(d.prompt(100000000));
    CHECK(d.cfg(VC_DC_CTRL)[0] == 0x01);
}

TEST(vidcard_demo_vidtiles_shows_tiles_and_sprites) {
    Demo d("VIDTILES");
    if (!d.built) return;
    d.type("VIDTILES");
    d.run(1.5);
    // Page 1: 16x16 8-bit tiles behind 8x8 2-bit ones, and text; a sky-blue backdrop.
    CHECK(d.cfg(VC_DC_CTRL)[0] == 0x0F && d.cfg(VC_DC_BACK)[0] == 153 && d.cfg(VC_SPR_COUNT)[0] == 6);
    CHECK(d.layer(0)[VC_L_MODE] == (VC_TILE | 0x18 | 0x20) && d.layer(1)[VC_L_MODE] == (VC_TILE | 0x08));
    auto entry = [&](uint32_t map, int col, int row) { return be16(d.c().vram + map + (row * 64 + col) * 2); };
    CHECK(entry(0x020000, 5, 8) == 2 && entry(0x020000, 5, 9) == 3);
    int clouds = 0;
    for (int col = 0; col < 64; ++col)
        for (int row = 1; row <= 4; ++row) clouds += (entry(0x020000, col, row) & 0x3FF) == 1;
    CHECK(clouds > 10);
    CHECK(entry(0x022000, 0, 0) == 0xD002 && entry(0x022000, 0, 1) == 0xC801); // a ceiling of upside-down grass
    CHECK(entry(0x022000, 8, 18) == 0xE003 && entry(0x022000, 7, 18) == 0);  // bricks
    CHECK(entry(0x022000, 3, 24) == 0xC004 && entry(0x022000, 4, 24) == 0xC404); // a bush and its mirror
    CHECK(entry(0x022000, 0, 25) == 0xC001 && entry(0x022000, 0, 29) == 0xD002);
    const uint8_t* pal = d.cfg(0x200 + 2 * 193);
    CHECK(be16(pal) == ((20 >> 3) << 11 | (90 >> 2) << 5 | (20 >> 3)));
    // The layers scroll at their own speeds; the runner runs.
    uint16_t far = be16(d.layer(0) + VC_L_HSCROLL), near = be16(d.layer(1) + VC_L_HSCROLL);
    const uint8_t* runner = d.c().vram + VC_RESET_SPR_BASE;
    uint16_t rx = be16(runner + 2);
    d.run(0.5);
    CHECK(be16(d.layer(1) + VC_L_HSCROLL) - near >= 29 && be16(d.layer(0) + VC_L_HSCROLL) - far <= 8);
    CHECK(be16(runner + 2) != rx);
    CHECK((runner[8 + 6] & 0x20) && runner[6] >> 6 == 3);          // the ceiling one is upside down
    CHECK(runner[16 + 6] >> 6 == 1 && runner[32 + 6] >> 6 == 2 && runner[40 + 6] >> 6 == 3 && (runner[40 + 6] & 15) == 0x0F);
    CHECK(d.count(0, 100, 640, 200, d.shown(153)) > 20000); // sky between the clouds
    d.dump("1");
    // Page 2: 128 sprites, hires, from a table that changes every frame.
    d.key();
    d.run(1.0);
    CHECK(d.cfg(VC_SPR_CTRL)[0] == 1 && d.cfg(VC_SPR_COUNT)[0] == 128);
    uint32_t base = static_cast<uint32_t>(d.cfg(VC_SPR_BASE)[0]) << 16 | be16(d.cfg(VC_SPR_BASE) + 1);
    CHECK(base == 0x037000 || base == 0x037400);
    d.run(1.0 / 60);
    uint32_t base2 = static_cast<uint32_t>(d.cfg(VC_SPR_BASE)[0]) << 16 | be16(d.cfg(VC_SPR_BASE) + 1);
    CHECK(base2 != base && (base2 == 0x037000 || base2 == 0x037400));
    // The row of 40 at y 440: the first 32 are drawn, the last 8 not (their value-2 ring).
    for (int k = 0; k < 40; ++k) {
        int i = 88 + k, p = i % 11 + 1;
        bool drawn = d.v.pixel(8 + k * 15 + 7, 440 + 4) == d.shown(16 * p + 2);
        CHECK(drawn == (k < 32));
    }
    const uint8_t* s0 = d.c().vram + base2;
    uint16_t x0 = be16(s0 + 2), y0 = be16(s0 + 4);
    CHECK(x0 > 0 && x0 < 640 && y0 < 400);
    d.dump("2");
    d.key();
    CHECK(d.prompt(100000000));
    CHECK(d.cfg(VC_DC_CTRL)[0] == 0x01);
}

TEST(vidcard_demo_vidgfx_shows_bitmaps_commands_and_interrupts) {
    Demo d("VIDGFX");
    if (!d.built) return;
    const uint8_t* ram = d.s.bus.ram();
    uint16_t irqv = static_cast<uint16_t>(ram[0x26] << 8 | ram[0x27]); // the BIOS's IRQ target before
    d.type("VIDGFX");
    d.run(2.0);
    // Page 1: 640x480, 16 colors from palette offset 1; a panel for each command.
    CHECK(d.cfg(VC_DC_CTRL)[0] == 0x05 && d.layer(0)[VC_L_MODE] == 0x16 && d.layer(0)[VC_L_PALOFS] == 1);
    const int px[4] = {4, 163, 322, 481}, py[2] = {22, 243};
    CHECK(d.v.pixel(px[0], py[0]) == d.shown(17) && d.v.pixel(px[3] + 154, py[1] + 214) == d.shown(17)); // frames
    CHECK(d.count(px[1] + 6, py[0] + 4, px[1] + 6 + 32, py[0] + 20, d.shown(17)) > 40);                  // "LINE"
    int stars = 0;
    for (int c = 18; c <= 25; ++c) stars += d.count(px[0] + 1, py[0] + 22, px[0] + 154, py[0] + 214, d.shown(c));
    CHECK(stars > 150);
    CHECK(d.v.pixel(px[3] + 8 + 7, py[0] + 215 - 8 - 30) == d.shown(18));          // the first bar
    CHECK(d.v.pixel(px[1] + 40, py[1] + 68) == d.shown(18));                       // the first bubble
    CHECK(d.count(px[2] + 1, py[1] + 22, px[2] + 154, py[1] + 214, d.shown(16)) < 26000); // the pinwheel
    uint32_t ring = d.v.pixel(px[0] + 77 + 4, py[1] + 118);
    bool cycling = false;
    for (int c = 24; c < 32; ++c) cycling = cycling || ring == d.shown(c);
    CHECK(cycling);
    // The stamp, BLITted from the PSRAM with its 0s see-through; FILL's stripes; COPY's rows.
    CHECK(d.v.pixel(px[3] + 8 + 7, py[1] + 26 + 7) == d.shown(20) && d.v.pixel(px[3] + 8, py[1] + 26) == d.shown(16));
    const int fx = (px[3] + 8) / 2 * 2; // (the byte FILL starts at: its first pixel)
    CHECK(d.v.pixel(fx, py[1] + 84) == d.shown(21) && d.v.pixel(fx + 1, py[1] + 84) == d.shown(22));
    CHECK(d.v.pixel(fx, py[1] + 85) == d.shown(22));
    bool copied = true;
    for (int row = 0; row < 90; row += 7)
        for (int x = 0; x < 140; x += 5)
            copied = copied && d.v.pixel(px[3] + 8 + x, py[1] + 104 + row) == d.v.pixel(px[1] + 8 + x, py[1] + 40 + row);
    CHECK(copied);
    CHECK(d.cell(VC_RESET_TEXT_MAP, 50, 29)[0] == '(' && d.cell(VC_RESET_TEXT_MAP, 51, 29)[0] == 'C'); // done
    uint16_t c24 = be16(d.cfg(0x200 + 48));
    d.run(0.2);
    CHECK(be16(d.cfg(0x200 + 48)) != c24);
    d.dump("1");
    // Page 2: 8, 2 and 1 bits a pixel; the line interrupt's handler in the BIOS's IRQ chain.
    d.key();
    d.run(1.5);
    CHECK(d.cfg(VC_DC_CTRL)[0] == 0x07 && d.layer(0)[VC_L_MODE] == (VC_BITMAP | 0x18));
    CHECK(d.layer(1)[VC_L_MODE] == (VC_BITMAP | 0x08) && d.layer(1)[VC_L_PALOFS] == 7);
    CHECK(d.layer(2)[VC_L_MODE] == (VC_BITMAP | 0x04) && d.layer(2)[VC_L_PALOFS] == 15);
    CHECK(d.c().ien == VC_IRQ_LINE && (ram[0x26] << 8 | ram[0x27]) != irqv);
    uint8_t mid = d.vram(120 * 320 + 160);
    CHECK(mid >= 32 && mid < 96); // the tunnel
    std::vector<uint32_t> bars;   // the backdrop down the left side: the bars' colors
    for (int y = 40; y < 440; ++y) {
        uint32_t p = d.v.pixel(20, y);
        bool bar = false;
        for (int c = 128; c < 160; ++c) bar = bar || p == d.shown(c);
        CHECK(bar);
        if (std::find(bars.begin(), bars.end(), p) == bars.end()) bars.push_back(p);
    }
    CHECK(bars.size() >= 12); // (each bar's 16 shades go up and back down: about 9 distinct)
    CHECK(d.v.pixel(2, 100) == d.shown(241)); // the 1-bit layer's border
    // The spinner: 8 frames in the PSRAM, shown from two buffers by turns, placed by scrolling.
    bool frames_ok = true;
    for (int f = 0; f < 8; ++f) {
        int set = 0;
        for (int i = 0; i < 1280; ++i) set += d.c().psram[f * 1280 + i] != 0;
        frames_ok = frames_ok && set > 400;
    }
    CHECK(frames_ok);
    CHECK(std::equal(d.c().psram, d.c().psram + 1280, d.c().psram) &&
          !std::equal(d.c().psram, d.c().psram + 1280, d.c().psram + 1280)); // (they differ)
    uint16_t base = be16(d.layer(1) + VC_L_MAPBASE + 1);
    CHECK(base == 0x4000 || base == 0x4800);
    d.run(5.0 / 60);
    CHECK(be16(d.layer(1) + VC_L_MAPBASE + 1) != base);
    CHECK(static_cast<int16_t>(be16(d.layer(1) + VC_L_HSCROLL)) < 0);
    d.dump("2");
    d.key();
    CHECK(d.prompt(100000000));
    CHECK((ram[0x26] << 8 | ram[0x27]) == irqv && d.cfg(VC_DC_CTRL)[0] == 0x01); // the IRQ put back
}

TEST(vidcard_demo_vidmouse_draws_with_the_mouse_and_takes_the_keys) {
    Demo d("VIDMOUSE");
    if (!d.built) return;
    auto status = [&] { // layer 1's top row, as text
        std::string t;
        for (int col = 0; col < 80; ++col) t += static_cast<char>(d.cell(VC_RESET_TEXT_MAP, col, 0)[0]);
        return t;
    };
    auto press = [&](uint8_t usage) {
        d.v.key(usage, true);
        d.v.key(usage, false);
        d.run(0.1);
    };
    auto canvas = [&](int x, int y) { return d.vram(static_cast<uint32_t>(y * 320 + x)); };
    d.type("VIDMOUSE");
    d.run(1.0);
    CHECK(d.c().in_ctrl == (VC_IN_POINTER | VC_IN_KEYS) && d.cfg(VC_DC_CTRL)[0] == 0x0B);
    // The pointer, sprite 0, follows the mouse (at half its pixels: the sprites are 320x240).
    d.v.mouse_to(200, 100, 0);
    d.run(0.1);
    const uint8_t* s0 = d.c().vram + VC_RESET_SPR_BASE;
    CHECK(be16(s0 + 2) == 100 && be16(s0 + 4) == 50);
    CHECK(status().find(" X 200 Y 100 BTN 80 COLOR 226") != std::string::npos);
    // A drag with the left button draws a line on the canvas, in yellow.
    d.v.mouse_to(200, 100, 1);
    d.run(0.1);
    d.v.mouse_to(300, 100, 1);
    d.run(0.1);
    d.v.mouse_to(300, 100, 0);
    d.run(0.1);
    int drawn = 0;
    for (int x = 100; x <= 150; ++x) drawn += canvas(x, 50) == 226;
    CHECK(drawn == 51 && canvas(99, 50) == 0 && canvas(151, 50) == 0 && canvas(120, 51) == 0);
    // The right button rubs out a 7x7 square.
    d.v.mouse_to(250, 100, 2);
    d.run(0.1);
    d.v.mouse_to(250, 100, 0);
    CHECK(canvas(122, 50) == 0 && canvas(128, 50) == 0 && canvas(121, 50) == 226 && canvas(129, 50) == 226);
    // = (+ without Shift) and the wheel change the color; the key's code and character show.
    press(0x2E);
    CHECK(status().find("COLOR 227") != std::string::npos);
    CHECK(status().find("KEY 2E CHAR BD =") != std::string::npos); // (its release: bit 7)
    d.v.mouse_wheel(3);
    d.run(0.1);
    CHECK(status().find("COLOR 230") != std::string::npos);
    d.v.key(0xE1, true); // Shift held: the modifiers show
    d.run(0.1);
    CHECK(status().find("KEY E1 CHAR 00   MODS 02") != std::string::npos);
    d.v.key(0xE1, false);
    // C clears the canvas; Esc goes back to the shell, and the keys to the UART.
    press(0x06);
    CHECK(canvas(140, 50) == 0);
    press(0x29);
    CHECK(d.prompt(100000000));
    CHECK(d.c().in_ctrl == 0 && d.cfg(VC_DC_CTRL)[0] == 0x01);
}

TEST(vidcard_demo_vidpad_shows_the_gamepads) {
    Demo d("VIDPAD");
    if (!d.built) return;
    auto row = [&](int r) { // a row of the text screen
        std::string t;
        for (int col = 0; col < 80; ++col) t += static_cast<char>(d.cell(VC_RESET_TEXT_MAP, col, r)[0]);
        return t;
    };
    d.type("VIDPAD");
    d.run(1.0);
    CHECK(row(2).find(" PAD 0: NOT CONNECTED") == 0);
    CHECK(row(8).find(" PAD 3: NOT CONNECTED") == 0);
    // Pad 0: up and right on the d-pad, buttons 1 and 16, the sticks.
    const uint8_t s[8] = {0, VC_PAD_UP | VC_PAD_RIGHT, 0x01, 0x80, 127, 0x81, 1, 0};
    d.v.pad(0, s);
    d.run(0.1);
    CHECK(row(2).find(" PAD 0: U..R RAW 1..............F LX +127 LY -127 RX +001 RY +000") == 0);
    CHECK(row(4).find(" PAD 1: NOT CONNECTED") == 0);
    // Buttons 10 and 11 (the labels go 1-9, 0, A-F), left and down, on pad 2.
    const uint8_t s2[8] = {0, VC_PAD_DOWN | VC_PAD_LEFT, 0, 0x06, 0, 0, 0, 0};
    d.v.pad(2, s2);
    d.run(0.1);
    CHECK(row(6).find(" PAD 2: .DL. RAW .........0A..... LX +000 LY +000 RX +000 RY +000") == 0);
    // A pad with a map (the card knows this one): the standard names. Its own buttons 1, 2
    // and 11 are East, South and Select.
    const uint8_t s3[8] = {0, 0, 0x03, 0x04, 0, 0, 0, 0};
    d.v.pad_id(1, 0x2DC8, 0x6001);
    d.v.pad(1, s3);
    d.run(0.1);
    CHECK(row(4).find(" PAD 1: .... BTN SE......-....... LX +000") == 0);
    CHECK(row(10).find(" BTN: SEWN") == 0);
    // Unplugged: the whole line goes back.
    d.v.pad(0, nullptr);
    d.run(0.1);
    CHECK(row(2).find(" PAD 0: NOT CONNECTED") == 0);
    CHECK(row(2).find("BTN") == std::string::npos && row(2).find("RY") == std::string::npos);
    // Esc goes back to the shell, and the keys to the UART.
    d.v.key(0x29, true);
    d.v.key(0x29, false);
    d.run(0.1);
    CHECK(d.prompt(100000000));
    CHECK(d.c().in_ctrl == 0);
}

TEST(vidcard_demo_padmap_sets_up_a_pad_and_saves_it) {
    Demo d("PADMAP");
    if (!d.built) return;
    auto row = [&](int r) {
        std::string t;
        for (int col = 0; col < 80; ++col) t += static_cast<char>(d.cell(VC_RESET_TEXT_MAP, col, r)[0]);
        return t;
    };
    auto press = [&](int button) { // the pad's own button (1-16), then let go
        uint8_t s[8] = {};
        s[button <= 8 ? VC_PAD_BTN1 : VC_PAD_BTN2] = static_cast<uint8_t>(1 << ((button - 1) & 7));
        d.v.pad(1, s);
        d.run(0.05);
        const uint8_t none[8] = {};
        d.v.pad(1, none);
        d.run(0.05);
    };
    auto map_at = [&](int i) { return vc_peek(&d.c(), VC_PADMAP_BASE + i); };
    d.v.pad_id(1, 0x1234, 0xABCD);
    const uint8_t none[8] = {};
    d.v.pad(1, none);
    d.type("PADMAP");
    d.run(1.0);
    CHECK(row(2).find(" PRESS A BUTTON ON THE PAD") == 0);
    press(5); // pad 1 is chosen; that press isn't a button yet
    CHECK(row(2).find(" PAD 1  1234:ABCD") == 0);
    CHECK(row(4).find(" PRESS SOUTH") == 0);
    press(2); // South
    CHECK(row(4).find(" PRESS EAST") == 0);
    press(2); // the same button again: taken, so still East
    CHECK(row(4).find(" PRESS EAST") == 0);
    press(1); // East
    CHECK(row(4).find(" PRESS WEST") == 0);
    d.v.key(0x2C, true); // Space: no West
    d.v.key(0x2C, false);
    d.run(0.1);
    CHECK(row(4).find(" PRESS NORTH") == 0);
    press(3);  // North
    press(4);  // L
    press(5);  // R
    press(6);  // L2
    press(7);  // R2
    press(8);  // Select
    press(9);  // Start
    press(10); // Home
    press(11); // L3
    press(16); // R3
    d.run(0.5);
    CHECK(row(4).find(" SAVED IN /CMD/PADMAP.INI") == 0);
    // On the card now.
    const uint8_t want[VC_PADMAP_SIZE] = {0x12, 0x34, 0xAB, 0xCD, VC_BTN_EAST, VC_BTN_SOUTH, VC_BTN_NORTH, VC_BTN_L, VC_BTN_R,
                                          VC_BTN_L2, VC_BTN_R2, VC_BTN_SELECT, VC_BTN_START, VC_BTN_HOME, VC_BTN_L3, 0xFF, 0xFF,
                                          0xFF, 0xFF, VC_BTN_R3};
    for (int i = 0; i < VC_PADMAP_SIZE; ++i) CHECK(map_at(i) == want[i]);
    uint8_t s[8] = {0, 0, 0x01, 0, 0, 0, 0, 0}; // its own button 1
    d.v.pad(1, s);
    d.run(0.05);
    CHECK(vc_peek(&d.c(), VC_PAD_BASE + VC_PAD_SIZE + VC_PAD_FLAGS) == (VC_PAD_CONNECTED | VC_PAD_MAPPED));
    CHECK(vc_peek(&d.c(), VC_PAD_BASE + VC_PAD_SIZE + VC_PAD_BTN1) == (1 << VC_BTN_EAST));
    d.v.pad(1, none);
    d.run(0.05);
    // A key to leave; the map outlives the card's reset.
    d.v.key(0x28, true);
    d.v.key(0x28, false);
    d.run(0.1);
    CHECK(d.prompt(100000000));
    CHECK(map_at(0) == 0x12);
    // The file: text, a line for the pad.
    Fat16Volume vol;
    Fat16Volume::Entry e;
    CHECK(vol.load(d.img.c_str()) && vol.find("/CMD/PADMAP.INI", e));
    std::vector<uint8_t> ini = vol.read(e);
    CHECK(std::string(ini.begin(), ini.end()).find("\r\n1234 ABCD  01 00 03 04 05 06 07 08 09 0A 0B FF FF FF FF 0C\r\n") !=
          std::string::npos);
    // As after a power cycle: gone from the card, back from the file by running PADMAP, Esc.
    for (int i = 0; i < VC_PADMAP_SIZE; ++i) vc_poke(&d.v.card(), VC_PADMAP_BASE + i, 0);
    CHECK(map_at(0) == 0);
    d.type("PADMAP");
    d.run(1.0);
    for (int i = 0; i < VC_PADMAP_SIZE; ++i) CHECK(map_at(i) == want[i]);
    d.v.key(0x29, true);
    d.v.key(0x29, false);
    d.run(0.1);
    CHECK(d.prompt(100000000));
}

// SWAMP: its pictures are the TILEKIT project in demo/swamp, which the release disk has in
// /DEMO; it reads them into the card and scrolls two of the three layers.
TEST(vidcard_demo_swamp_scrolls_the_swamp) {
    std::string dir = std::string(REPO_DIR) + "/demo/swamp/";
    std::vector<std::string> tls, map;
    std::vector<pugputer::Fat16File> files;
    for (int n = 1; n <= 3; ++n) {
        std::string t = "SWAMP" + std::to_string(n) + ".TLS", m = "SWAMP" + std::to_string(n) + ".MAP";
        tls.push_back(host_text(dir + t));
        map.push_back(host_text(dir + m));
        CHECK(tls.back().size() > 528 && map.back().size() == 48 + 32 * 32 * 2);
        files.push_back(disk_file(("DEMO/" + t).c_str(), tls.back()));
        files.push_back(disk_file(("DEMO/" + m).c_str(), map.back()));
    }
    Demo d("SWAMP", files);
    if (!d.built) return;
    d.type("SWAMP");
    double seconds = 0;
    while (d.cfg(VC_DC_CTRL)[0] != 0x07 && seconds < 20) {
        d.run(0.1);
        seconds += 0.1;
    }
    std::printf("  loaded in about %.1f s\n", seconds);
    CHECK(d.cfg(VC_DC_CTRL)[0] == 0x07 && d.cfg(VC_DC_BACK)[0] == 0);
    CHECK(d.s.received.find("Loading the swamp") != std::string::npos);
    // The palette is the first set's; each layer has 48KB, its tiles at the start and its
    // map (32x32 cells, 2KB) at the end: 16x16 tiles of 8 bits a pixel at 320x240.
    for (int i = 0; i < 512; ++i) CHECK(d.c().cfg[0x200 + i] == static_cast<uint8_t>(tls[0][16 + i]));
    auto addr = [](const uint8_t* p) { return static_cast<uint32_t>(p[0] << 16 | p[1] << 8 | p[2]); };
    for (int n = 0; n < 3; ++n) {
        const uint8_t* l = d.layer(n);
        uint32_t tiles = 0xC000u * n, cells = tiles + 0xC000 - 2048;
        CHECK(l[VC_L_MODE] == (VC_TILE | 3 << 3 | 0x20) && l[VC_L_MAP] == 0);
        CHECK(addr(l + VC_L_TILEBASE) == tiles && addr(l + VC_L_MAPBASE) == cells);
        CHECK(be16(l + VC_L_VSCROLL) == 0);
        bool same = true;
        for (uint32_t i = 528; i < tls[n].size(); ++i) same = same && d.vram(tiles + i - 528) == static_cast<uint8_t>(tls[n][i]);
        for (uint32_t i = 48; i < map[n].size(); ++i) same = same && d.vram(cells + i - 48) == static_cast<uint8_t>(map[n][i]);
        CHECK(same);
    }
    // The sky stays; the bayou moves a pixel every 2 frames, the ground 2 a frame.
    auto hs = [&](int n) { return be16(d.layer(n) + VC_L_HSCROLL); };
    d.run(0.5);
    uint16_t bayou = hs(1), ground = hs(2);
    CHECK(hs(0) == 0 && ground / 4 == bayou && ground >= 2);
    d.run(0.5);
    CHECK(hs(0) == 0 && hs(2) - ground >= 58 && hs(2) - ground <= 62 && hs(1) - bayou >= 14 && hs(1) - bayou <= 16);
    // The picture is the three maps, front to back, at those scrolls -- each line, as the card
    // may be part of the way down a frame: the lines above at these, those below at the frame
    // before's.
    auto matches = [&](int y, uint16_t s1, uint16_t s2) {
        const uint16_t scroll[3] = {0, s1, s2};
        for (int x = 0; x < 320; ++x) {
            int color = 0;
            for (int n = 2; n >= 0 && color == 0; --n) {
                int mx = (x + scroll[n]) & 511;
                uint32_t cell = 0xC000u * n + 0xC000 - 2048 + ((y / 16) * 32 + mx / 16) * 2;
                uint16_t e = static_cast<uint16_t>(d.vram(cell) << 8 | d.vram(cell + 1));
                int tx = mx % 16, ty = y % 16;
                if (e & 0x400) tx = 15 - tx;
                if (e & 0x800) ty = 15 - ty;
                color = d.vram(0xC000u * n + (e & 1023) * 256 + ty * 16 + tx);
            }
            if (d.v.pixel(2 * x, 2 * y) != d.shown(color)) return false;
        }
        return true;
    };
    uint16_t s1 = hs(1), s2 = hs(2), p2 = static_cast<uint16_t>(s2 - 2), p1 = static_cast<uint16_t>(p2 / 4);
    int lines = 0;
    for (int y = 0; y < 240; ++y) lines += matches(y, s1, s2) || matches(y, p1, p2);
    CHECK(lines == 240);
    d.dump("1");
    d.key();
    CHECK(d.prompt(100000000));
    CHECK(d.cfg(VC_DC_CTRL)[0] == 0x01);
}

// With SWAMP.SNG beside its pictures, it plays that -- a SONGKIT song, the demo disk's own --
// over and over, with SONGKIT's player (sk_play.asm, timed by the OPL3's Timer 2), from RAM
// pages of its own (seen through bank 2), while the swamp scrolls as before.
TEST(vidcard_demo_swamp_plays_its_music) {
    std::string dir = std::string(REPO_DIR) + "/demo/swamp/";
    std::vector<pugputer::Fat16File> files;
    for (int n = 1; n <= 3; ++n) {
        std::string t = "SWAMP" + std::to_string(n) + ".TLS", m = "SWAMP" + std::to_string(n) + ".MAP";
        files.push_back(disk_file(("DEMO/" + t).c_str(), host_text(dir + t)));
        files.push_back(disk_file(("DEMO/" + m).c_str(), host_text(dir + m)));
    }
    // The song: a SONGKIT song (PSG1) that loops (to order 0), 4-op pairs all on.
    std::string song = host_text(dir + "SWAMP.SNG");
    CHECK(song.size() > 80 && song.compare(0, 4, "PSG1") == 0 && song[12] == 0 && song[5] == 0x3F);
    files.push_back(disk_file("DEMO/SWAMP.SNG", song));
    Demo d("SWAMP", files);
    if (!d.built) return;
    pugputer::Opl3Device opl3;
    std::vector<pugputer::Opl3Device::Write> log;
    opl3.set_log(&log);
    d.s.bus.map_device("opl3", 0xFFE0, 4, &opl3);
    d.type("SWAMP");
    double seconds = 0;
    while (d.cfg(VC_DC_CTRL)[0] != 0x07 && seconds < 20) {
        d.run(0.1);
        seconds += 0.1;
    }
    CHECK(d.cfg(VC_DC_CTRL)[0] == 0x07);
    // The file is in a RAM page above the program's 64KB, as it is.
    const size_t kPage = pugputer::SystemBus::kPageSize;
    uint8_t* ram = d.s.bus.phys_ram();
    size_t first = 0;
    for (size_t p = 4; p < d.s.bus.ram_pages() && !first; ++p)
        if (std::memcmp(ram + p * kPage, song.data(), song.size()) == 0) first = p;
    CHECK(first >= 4 && song.size() < kPage);
    // It plays: the chip in OPL3 mode with the song's 4-op pairs, Timer 2 ticking at the
    // song's rate (each tick clears the flags: a write of $80 to register 4), and its notes
    // keyed on, row after row.
    d.run(0.5);
    CHECK(opl3.reg(0x105) == 1 && opl3.reg(0x104) == 0x3F && opl3.reg(0x04) == 0x42);
    size_t mark = log.size();
    d.run(2.0);
    int ticks = 0, keys = 0;
    for (size_t i = mark; i < log.size(); ++i) {
        if (log[i].reg == 0x04 && log[i].value == 0x80) ++ticks;
        if ((log[i].reg & 0xFF) >= 0xB0 && (log[i].reg & 0xFF) <= 0xB8 && (log[i].value & 0x20)) ++keys;
    }
    int rate = static_cast<uint8_t>(song[7]);
    std::printf("  %d ticks in 2 s (%d a second expected), %d notes keyed on\n", ticks, rate, keys);
    CHECK(ticks >= 2 * rate - 3 && ticks <= 2 * rate + 3 && keys >= 20);
    // The scrolling keeps its pace with the music going: the bayou a pixel every 2 frames,
    // the ground 2 a frame.
    auto hs = [&](int n) { return be16(d.layer(n) + VC_L_HSCROLL); };
    uint16_t bayou = hs(1), ground = hs(2);
    d.run(1.0);
    CHECK(hs(0) == 0 && hs(2) - ground >= 118 && hs(2) - ground <= 122 && hs(1) - bayou >= 29 && hs(1) - bayou <= 31);
    // A key: quiet (the timers stopped, OPL2 mode, every key off), and back to the shell.
    d.key();
    CHECK(d.prompt(100000000));
    CHECK(opl3.reg(0x04) == 0x60 && opl3.reg(0x105) == 0 && opl3.reg(0xB0) == 0 && opl3.reg(0x1B8) == 0);
    CHECK(d.cfg(VC_DC_CTRL)[0] == 0x01);
    // Bank 2 is back at its own page, and the song's page was given back: a second run
    // takes the same one.
    CHECK(d.s.bus.bank_register(2) == 2);
    std::memset(ram + first * kPage, 0, kPage);
    d.type("SWAMP");
    seconds = 0;
    while (d.cfg(VC_DC_CTRL)[0] != 0x07 && seconds < 20) {
        d.run(0.1);
        seconds += 0.1;
    }
    CHECK(std::memcmp(ram + first * kPage, song.data(), song.size()) == 0);
    d.key();
    CHECK(d.prompt(100000000));
    CHECK(d.s.bus.bank_register(2) == 2);
}

// Without its pictures it says so, on the text screen, and goes back to the shell.
TEST(vidcard_demo_swamp_says_when_its_pictures_are_missing) {
    Demo d("SWAMP");
    if (!d.built) return;
    d.type("SWAMP");
    CHECK(d.prompt(400000000));
    CHECK(d.s.received.find("SWAMP: SWAMP1.TLS: not found (in /DEMO or here)") != std::string::npos);
    CHECK(d.cfg(VC_DC_CTRL)[0] == 0x01);
}

// MANDEL: the MC6839 floating-point ROM sets up each pixel, 8.8 fixed point iterates. ASM
// always builds it; drawing the picture takes about five minutes of CPU time (20 s here),
// so that runs only when PUGPUTER_SLOW_TESTS is set.
TEST(vidcard_demo_mandel_draws_the_set) {
    Demo d("MANDEL");
    if (!d.built) return;
    if (!std::getenv("PUGPUTER_SLOW_TESTS")) {
        std::printf("  (drawing skipped: set PUGPUTER_SLOW_TESTS=1 to run it)\n");
        return;
    }
    d.type("MANDEL");
    // It draws until data port 0 has gone past the last pixel (320x240 bytes from VRAM 0).
    double seconds = 0;
    while (d.c().addr[0] < 320 * 240 && seconds < 3600) {
        d.run(10.0);
        seconds += 10;
    }
    std::printf("  drew it in about %.0f s of CPU time\n", seconds);
    CHECK(d.c().addr[0] == 320 * 240);
    CHECK(d.cfg(VC_DC_CTRL)[0] == 0x01 && d.cfg(VC_DC_BACK)[0] == 0);
    CHECK(d.layer(0)[VC_L_MODE] == (VC_BITMAP | 3 << 3) && be16(d.layer(0) + VC_L_STRIDE) == 320);
    // The palette is the V9958's: GGGRRRBB. 8 (n = 1): red 2 of 7; $E0 (n = 28): green.
    CHECK(d.shown(0) == 0x000000 && d.shown(255) == 0xFFFFFF);
    CHECK(d.shown(0x08) == vc_rgb888(0x4800) && d.shown(0xE0) == vc_rgb888(0x07E0));
    auto px = [&](int x, int y) { return d.vram(static_cast<uint32_t>(y * 320 + x)); };
    // Real -2.25 to 0.75, imaginary -1.125 to 1.125, 3/320 a pixel. In the big cardioid
    // (-0.25, 0) and the circle left of it (-1, 0): in the set, black. Far outside, the corner
    // (-2.25, -1.125): out at once, black too. Just outside, at (0.3, 0) and (-0.75, -0.15), some
    // iterations.
    CHECK(px(213, 120) == 0 && px(133, 120) == 0 && px(0, 0) == 0);
    CHECK(px(272, 120) != 0 && px(160, 104) != 0);
    // Every pixel is an iteration count times 8; many of the 32 show up.
    bool used[32] = {};
    int odd = 0;
    for (int i = 0; i < 320 * 240; ++i) {
        uint8_t p = d.vram(static_cast<uint32_t>(i));
        if (p & 7) ++odd;
        used[p >> 3] = true;
    }
    int colors = 0;
    for (bool u : used) colors += u;
    CHECK(odd == 0 && colors >= 24);
    // The picture is (nearly) the same above and below the real axis -- 8.8 fixed point
    // rounds the two halves a little differently.
    int same = 0;
    for (int y = 1; y < 120; ++y)
        for (int x = 0; x < 320; ++x) same += px(x, y) == px(x, 240 - y);
    CHECK(same > 119 * 320 * 9 / 10);
    d.dump("1");
    d.key();
    CHECK(d.prompt(100000000));
    CHECK(d.cfg(VC_DC_CTRL)[0] == 0x01);
}
