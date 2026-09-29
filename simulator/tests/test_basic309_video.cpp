// basic309's statements for the video card (SCREEN, COLOR, GCLS, PSET, LINE (..)-(..),
// CIRCLE, TRIANGLE, GPRINT, TPRINT, PALETTE, SPRITE, IMAGE, VSYNC, VPOKE and VPEEK), run
// by BASIC with the card at $FF80: what each one leaves on the card.
#include <cstdio>
#include <string>
#include <vector>

#include "basic309_session.hpp"
#include "pugputer/video_device.hpp"
#include "test_framework.hpp"
#include "vc.h"

using pugputer::VideoDevice;

namespace {

struct Machine {
    Basic309Session s;
    VideoDevice v;
    bool ok = false;
    Machine() {
        ok = s.boot(PUGBIOS_S19_PATH, EXBASROM309_S19_PATH);
        s.bus.map_device("video", VideoDevice::kBase, VideoDevice::kSize, &v, pugputer::IrqLine::IRQ);
    }
    std::string run(const std::string& line) { return s.run_line(line); }
    const vc_card& c() { return v.card(); }
    uint8_t vram(uint32_t a) { return c().vram[a]; }
    uint8_t px8(int x, int y) { return vram(static_cast<uint32_t>(y) * 320 + x); } // SCREEN 1
    int count8(uint8_t color, int w = 320, int h = 240) {
        int n = 0;
        for (int y = 0; y < h; ++y)
            for (int x = 0; x < w; ++x) n += px8(x, y) == color;
        return n;
    }
    uint16_t pal(int i) { return static_cast<uint16_t>(c().cfg[0x200 + 2 * i] << 8 | c().cfg[0x201 + 2 * i]); }
};

} // namespace

TEST(basic309_video_screen_modes_set_up_the_card) {
    Machine m;
    CHECK(m.ok);
    CHECK(m.run("SCREEN 1") == "");
    const vc_card& c = m.c();
    CHECK(c.cfg[VC_DC_CTRL] == 0x0D && c.cfg[VC_SPR_CTRL] == 0 && c.cfg[VC_SPR_COUNT] == 128);
    CHECK(c.cfg[VC_LAYER0 + VC_L_MODE] == 0x1A && c.cfg[VC_LAYER0 + VC_L_STRIDE + 1] == 0x40);
    CHECK(c.cfg[VC_LAYER0 + 2 * VC_LAYER_SIZE + VC_L_MODE] == 0x24); // the text screen in front
    CHECK(c.t_w == 320 && c.t_h == 240 && c.t_bpp == 8 && c.t_stride == 320 && c.color == 15);
    // SCREEN 2: 640x480 in 16 colors, sprites in its coordinates.
    CHECK(m.run("SCREEN 2:PSET (639,479),12") == "");
    CHECK(c.cfg[VC_LAYER0 + VC_L_MODE] == 0x16 && c.cfg[VC_SPR_CTRL] == 1 && c.t_w == 640 && c.t_bpp == 4);
    CHECK(m.vram(479 * 320 + 319) == 0x0C);
    // SCREEN 0: the card as it starts.
    CHECK(m.run("SCREEN 0") == "");
    CHECK(c.cfg[VC_DC_CTRL] == 0x01 && c.cfg[VC_LAYER0 + VC_L_MODE] == 0x24 && c.t_w == 0);
    CHECK(m.run("SCREEN 3") == "?FC ERROR\r\n");
}

TEST(basic309_video_draws_with_the_pen_or_a_color) {
    Machine m;
    CHECK(m.ok);
    CHECK(m.run("SCREEN 1:PSET (10,20),5:PSET (11,20)") == "");
    CHECK(m.px8(10, 20) == 5 && m.px8(11, 20) == 15); // a color given, else the pen
    CHECK(m.c().color == 15);                          // (the pen again after)
    CHECK(m.run("COLOR 9:PSET (1,1)") == "");
    CHECK(m.px8(1, 1) == 9);
    // Lines, and boxes from any two corners.
    CHECK(m.run("GCLS:LINE (0,0)-(9,0)") == "");
    CHECK(m.count8(9) == 10);
    CHECK(m.run("GCLS:LINE (0,0)-(4,4),3,B") == "");
    CHECK(m.count8(3) == 16 && m.px8(2, 2) == 0);
    CHECK(m.run("GCLS:LINE (5,5)-(1,1),,BF") == "");
    CHECK(m.count8(9) == 25 && m.px8(1, 1) == 9 && m.px8(5, 5) == 9 && m.px8(6, 6) == 0);
    // Circles and discs.
    CHECK(m.run("GCLS:CIRCLE (50,50),10,7") == "");
    CHECK(m.px8(60, 50) == 7 && m.px8(40, 50) == 7 && m.px8(50, 50) == 0);
    CHECK(m.run("CIRCLE (50,50),10,7,F") == "");
    CHECK(m.px8(50, 50) == 7);
    CHECK(m.run("GCLS:CIRCLE (50,50),5,,F") == "");
    CHECK(m.px8(50, 50) == 9 && m.px8(55, 50) == 9);
    // A triangle.
    CHECK(m.run("GCLS:TRIANGLE (0,100)-(20,100)-(0,120),6") == "");
    CHECK(m.px8(0, 100) == 6 && m.px8(20, 100) == 6 && m.px8(0, 120) == 6 && m.px8(15, 115) == 0);
    // Clipped at the edges.
    CHECK(m.run("GCLS:LINE (-10,-10)-(400,400),4") == "");
    CHECK(m.px8(0, 0) == 4 && m.px8(239, 239) == 4);
    // GCLS c: all of it.
    CHECK(m.run("GCLS 2") == "");
    CHECK(m.count8(2) == 320 * 240 && m.c().color == 9);
    // The syntax.
    CHECK(m.run("LINE (1,2)(3,4)") == "?SN ERROR\r\n");
    CHECK(m.run("LINE (1,2)-(3,4),5,X") == "?SN ERROR\r\n");
    CHECK(m.run("CIRCLE (1,2),3,4,X") == "?SN ERROR\r\n");
    CHECK(m.run("PSET (1,2),300") == "?FC ERROR\r\n");
    CHECK(m.run("PSET (1,40000)") == "?FC ERROR\r\n");
}

TEST(basic309_video_text_on_the_bitmap_and_on_the_text_screen) {
    Machine m;
    CHECK(m.ok);
    // GPRINT: the font's pixels in the color; the rest untouched. 'A', row 2: .#####..
    CHECK(m.run("SCREEN 1:GCLS 1:GPRINT (8,200),\"XA\",11") == "");
    CHECK(m.px8(17, 202) == 11 && m.px8(16, 202) == 1 && m.px8(18, 202) == 11);
    // TPRINT: cells of the text screen: character, color, background.
    CHECK(m.run("TPRINT (5,3),\"HI\",10,4") == "");
    uint32_t cell = VC_RESET_TEXT_MAP + (3 * 128 + 5) * 4;
    CHECK(m.vram(cell) == 'H' && m.vram(cell + 1) == 10 && m.vram(cell + 2) == 4 && m.vram(cell + 4) == 'I');
    // ... in COLOR's pen and background when none are given.
    CHECK(m.run("COLOR 12,17:A$=\"OK!\":TPRINT (79,29),A$") == "");
    cell = VC_RESET_TEXT_MAP + (29 * 128 + 79) * 4;
    CHECK(m.vram(cell) == 'O' && m.vram(cell + 1) == 12 && m.vram(cell + 2) == 17);
    // GCLS in a sprite image clears just the image; on the screen, the text screen too
    // (all 0: transparent).
    CHECK(m.run("IMAGE 1:GCLS 3:IMAGE") == "");
    CHECK(m.vram(VC_RESET_TEXT_MAP + (3 * 128 + 5) * 4) == 'H' && m.vram(0x030100) == 3 && m.px8(0, 0) == 1);
    CHECK(m.run("GCLS") == "");
    CHECK(m.vram(VC_RESET_TEXT_MAP + (3 * 128 + 5) * 4) == 0 && m.vram(VC_RESET_TEXT_MAP + (3 * 128 + 5) * 4 + 1) == 0);
    CHECK(m.run("TPRINT (1,1),5") == "?TM ERROR\r\n");
}

TEST(basic309_video_palette_sprites_and_images) {
    Machine m;
    CHECK(m.ok);
    CHECK(m.run("PALETTE 20,255,0,0:PALETTE 1,8,12,16") == "");
    CHECK(m.pal(20) == 0xF800 && m.pal(1) == 0x0862);
    CHECK(m.run("PALETTE 256,0,0,0") == "?FC ERROR\r\n");
    // A sprite: image 3 (its own number), at 100,50: 16x16, 8 bits, in front.
    CHECK(m.run("SCREEN 1:SPRITE 3,100,50") == "");
    uint32_t e = VC_RESET_SPR_BASE + 3 * 8;
    uint8_t want[8] = {0x18, 0x18, 0, 100, 0, 50, 0xC5, 0x80};
    for (int i = 0; i < 8; ++i) CHECK(m.vram(e + i) == want[i]);
    // Image 7, flipped across, behind the text; negative coordinates.
    CHECK(m.run("SPRITE 3,-5,-6,7,5") == "");
    uint8_t want2[8] = {0x18, 0x38, 0xFF, 0xFB, 0xFF, 0xFA, 0x55, 0x80};
    for (int i = 0; i < 8; ++i) CHECK(m.vram(e + i) == want2[i]);
    CHECK(m.run("SPRITE 3") == "");
    for (int i = 0; i < 8; ++i) CHECK(m.vram(e + i) == 0);
    CHECK(m.run("SPRITE 128,1,1") == "?FC ERROR\r\n");
    CHECK(m.run("SPRITE 1,1,1,64") == "?FC ERROR\r\n");
    // IMAGE n: the drawing statements draw into sprite image n; IMAGE: the screen again.
    CHECK(m.run("IMAGE 2:GCLS 0:CIRCLE (7,7),7,4,F:PSET (3,4),9:IMAGE:PSET (0,0),1") == "");
    CHECK(m.vram(0x030200 + 4 * 16 + 3) == 9 && m.vram(0x030200 + 7 * 16 + 7) == 4 && m.vram(0x030200) == 0);
    CHECK(m.px8(0, 0) == 1 && m.c().t_w == 320);
    // ... and it is on the picture where the sprite is.
    m.v.set_draw_all(true);
    CHECK(m.run("SPRITE 0,20,30,2:VSYNC 2") == "");
    const vc_card& c = m.c();
    const uint8_t* p = c.cfg + 0x200 + 2 * 4;
    CHECK(m.v.pixel(2 * (20 + 7), 2 * (30 + 7)) == vc_rgb888(static_cast<uint16_t>(p[0] << 8 | p[1])));
}

TEST(basic309_video_vsync_and_the_address_space) {
    Machine m;
    CHECK(m.ok);
    // VSYNC n waits for n vertical blanks (the card counts frames in $FF93).
    std::string out = m.run("F=PEEK(65427):VSYNC 3:PRINT (PEEK(65427)-F+256) AND 255");
    CHECK(out == " 3 \r\n" || out == " 4 \r\n");
    CHECK(m.run("VSYNC 0") == "");
    // VPOKE and VPEEK: anywhere in the card's 24 bits.
    CHECK(m.run("VPOKE 262145,5:PRINT VPEEK(262145)") == " 5 \r\n");
    CHECK(m.c().cfg[VC_DC_BACK] == 5);
    CHECK(m.run("VPOKE 16777215,77:PRINT VPEEK(16777215);VPEEK(0)") == " 77  0 \r\n");
    CHECK(m.run("VPOKE 16777216,0") == "?FC ERROR\r\n");
    CHECK(m.run("VPOKE -1,0") == "?FC ERROR\r\n");
    CHECK(m.run("PRINT VPEEK(\"A\")") == "?TM ERROR\r\n");
}

TEST(basic309_video_statements_list_as_typed) {
    Machine m;
    CHECK(m.ok);
    const std::vector<std::string> lines = {
        "10 SCREEN 1:COLOR 5,2:GCLS 3:PSET (1,2):PSET (X,Y),C",
        "20 LINE (1,2)-(3,4),5,BF:LINE (0,0)-(X+1,Y*2),,B:CIRCLE (5,5),3,,F",
        "30 TRIANGLE (1,1)-(2,2)-(3,1),C:GPRINT (0,0),\"HI\":TPRINT (1,2),A$,3,4",
        "40 PALETTE 1,2,3,4:SPRITE N,X,Y,I,F:SPRITE 0:IMAGE 1:IMAGE:VSYNC",
        "50 VPOKE A,VPEEK(A)+1",
    };
    for (const auto& l : lines) m.s.exec(l);
    std::string want;
    for (const auto& l : lines) want += l + "\r\n";
    std::string got = m.run("LIST");
    if (got != want) std::fprintf(stderr, "  LIST:\n%s  wanted:\n%s", got.c_str(), want.c_str());
    CHECK(got == want);
    // The words around them still work.
    CHECK(m.run("PRINT LEN(\"ABC\");INSTR(\"ABC\",\"C\")") == " 3  3 \r\n");
}
