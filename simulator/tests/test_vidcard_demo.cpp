// The video card's demos (demo/programs/ASM/VIDEO) as the demo disk has them: ASM assembles
// each on the machine -- byte for byte what the release disk's /DEMO/*.COM is -- and it runs
// with the card at $FF80, a page at a time, while these check what is on the card.
//
// VIDCARD_DUMP_DIR=folder saves each page's picture there (NAME-PAGE.rgb: 640x480 RGB bytes).
#include <algorithm>
#include <cstdio>
#include <cstdlib>
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

    explicit Demo(const std::string& n) : name(n) {
        std::string dir = std::string(DEMO_DIR) + "/ASM/VIDEO/";
        std::string src = host_text(dir + name + ".ASM");
        std::string lib = host_text(dir + "VIDLIB.ASM");
        std::string inc = host_text(std::string(REPO_DIR) + "/vidcard/vidcard.d");
        std::string asm_com = host_text(ASM_BIN_PATH);
        CHECK(!src.empty() && !lib.empty() && !inc.empty() && !asm_com.empty());
        std::string file = name + ".ASM";
        img = build_image((name + ".img").c_str(), 32768, 4,
                          {disk_file(file.c_str(), src), disk_file("VIDLIB.ASM", lib), disk_file("VIDCARD.D", inc),
                           disk_file("ASM.COM", asm_com)});
        CHECK(s.boot_shell(PUGBIOS_S19_PATH, img.c_str()));
        v.set_draw_all(true);
        s.bus.map_device("video", VideoDevice::kBase, VideoDevice::kSize, &v, pugputer::IrqLine::IRQ);
        type("ASM -f com " + name + ".ASM");
        CHECK(prompt(8000000000ull));
        CHECK(s.received.find("rror") == std::string::npos);
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
    // The ID and version the card gave, "V" and "1.0".
    CHECK(d.cell(VC_RESET_TEXT_MAP, 23, 26)[0] == 'V' && d.cell(VC_RESET_TEXT_MAP, 23, 26)[1] == 226);
    CHECK(d.cell(VC_RESET_TEXT_MAP, 34, 26)[0] == '1' && d.cell(VC_RESET_TEXT_MAP, 36, 26)[0] == '0');
    // The marquee moves; its letters show, doubled, at rows 22-23.
    uint16_t hs = be16(d.layer(1) + VC_L_HSCROLL);
    CHECK(hs > 60);
    d.run(0.5);
    CHECK(be16(d.layer(1) + VC_L_HSCROLL) - hs >= 29);
    const uint8_t* marquee = d.c().vram + 0x030000 + (11 * 64 + 2) * 4; // (a 64-cell-wide map)
    CHECK(marquee[0] == '*' && marquee[2] == 0);
    CHECK(d.v.pixel(4 * 8 + 5, 3 * 16 + 8) == d.shown(75)); // a side of the first box
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
