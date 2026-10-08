// The video card (vidcard/core, and VideoDevice putting it on the bus): its registers and
// ports, what each kind of layer and the sprites draw, the drawing commands, and the beam's
// timing and interrupts. What these check is what vidcard/README.md promises a program.
#include <algorithm>
#include <cstdint>
#include <cstdlib>
#include <vector>

#include "pugputer/video_device.hpp"
#include "test_framework.hpp"
#include "vc.h"

using pugputer::VideoDevice;

namespace {

// A card of its own, on the heap (it holds 256KB of video memory), with PSRAM.
struct Card {
    vc_card* c;
    std::vector<uint8_t> psram;
    Card() : c(static_cast<vc_card*>(std::calloc(1, sizeof(vc_card)))), psram(VC_PSRAM_SIZE) {
        c->psram = psram.data();
        vc_reset(c);
    }
    ~Card() { std::free(c); }
    vc_card* operator->() { return c; }

    void port0(uint32_t addr, int16_t inc = 1) {
        vc_write(c, VC_ADDR0_H, static_cast<uint8_t>(addr >> 16));
        vc_write(c, VC_ADDR0_M, static_cast<uint8_t>(addr >> 8));
        vc_write(c, VC_ADDR0_L, static_cast<uint8_t>(addr));
        vc_write(c, VC_INC0_H, static_cast<uint8_t>(static_cast<uint16_t>(inc) >> 8));
        vc_write(c, VC_INC0_L, static_cast<uint8_t>(inc));
    }
    void put(uint32_t addr, std::initializer_list<uint8_t> bytes) {
        port0(addr);
        for (uint8_t b : bytes) vc_write(c, VC_DATA0, b);
    }
    void cmd(std::initializer_list<int> bytes) {
        for (int b : bytes) vc_write(c, VC_CMD, static_cast<uint8_t>(b));
    }
    uint16_t color(int i) const { return static_cast<uint16_t>(c->cfg[0x200 + 2 * i] << 8 | c->cfg[0x201 + 2 * i]); }
    std::vector<uint16_t> line(int y) const {
        std::vector<uint16_t> out(VC_WIDTH);
        vc_render_line(c, y, out.data());
        return out;
    }
    uint8_t* layer(int n) { return c->cfg + VC_LAYER0 + VC_LAYER_SIZE * n; }
};

// 16-bit big-endian command parameters.
#define W(v) ((v) >> 8) & 0xFF, (v) & 0xFF

void target8(Card& k, int w, int h) { k.cmd({VC_C_TARGET, 0, 0, 0, W(w), W(w), W(h), 8}); }

int count_set(Card& k, int w, int h) {
    int n = 0;
    for (int i = 0; i < w * h; ++i) n += k->vram[i] != 0;
    return n;
}

} // namespace

TEST(vidcard_resets_to_a_blank_text_screen_with_the_xterm_palette) {
    Card k;
    CHECK(vc_read(k.c, VC_ID) == 'V' && vc_read(k.c, VC_VERSION) == 0x11);
    CHECK(k.color(0) == 0x0000 && k.color(9) == 0xF800 && k.color(15) == 0xFFFF);
    CHECK(k.color(16) == 0x0000 && k.color(196) == 0xF800 && k.color(21) == 0x001F);
    CHECK(k.color(244) == 0x8410); // gray 128
    CHECK(k->cfg[VC_DC_CTRL] == 0x01 && k->cfg[VC_SPR_COUNT] == 128);
    // 80x30 cells of 8x16: a space in color 7 on 0 (transparent, so the black backdrop).
    CHECK(k->vram[VC_RESET_TEXT_MAP] == ' ' && k->vram[VC_RESET_TEXT_MAP + 1] == 7);
    CHECK(k->vram[VC_RESET_FONT + 'A' * 16 + 2] == 0x7C);
    for (int y : {0, 240, 479})
        for (uint16_t p : k.line(y)) CHECK(p == 0);
}

TEST(vidcard_data_ports_step_through_every_part_of_the_address_space) {
    Card k;
    k.put(0x000100, {1, 2, 3});
    CHECK(k->vram[0x100] == 1 && k->vram[0x102] == 3);
    CHECK(vc_read(k.c, VC_ADDR0_L) == 0x03 && vc_read(k.c, VC_ADDR0_M) == 0x01);
    // Port 1 reads them back; a negative step goes down.
    vc_write(k.c, VC_ADDR1_H, 0);
    vc_write(k.c, VC_ADDR1_M, 0x01);
    vc_write(k.c, VC_ADDR1_L, 0x02);
    vc_write(k.c, VC_INC1_H, 0xFF);
    vc_write(k.c, VC_INC1_L, 0xFF);
    CHECK(vc_read(k.c, VC_DATA1) == 3 && vc_read(k.c, VC_DATA1) == 2 && vc_read(k.c, VC_DATA1) == 1);
    // A step of 320 (a bitmap's row).
    k.port0(0x000000, 320);
    vc_write(k.c, VC_DATA0, 9);
    vc_write(k.c, VC_DATA0, 9);
    CHECK(k->vram[0] == 9 && k->vram[320] == 9 && vc_read(k.c, VC_ADDR0_M) == 0x02 && vc_read(k.c, VC_ADDR0_L) == 0x80);
    // The settings, the palette and the PSRAM are in the same space; the address wraps at 24 bits.
    k.put(VC_CFG_BASE + VC_DC_BACK, {12});
    k.put(VC_PAL_BASE + 2 * 12, {0x12, 0x34});
    CHECK(k->cfg[VC_DC_BACK] == 12 && k.color(12) == 0x1234);
    CHECK(k.line(0)[0] == 0x1234); // the backdrop
    k.put(0xFFFFFF, {0x55, 0x66});
    CHECK(k.psram[VC_PSRAM_SIZE - 1] == 0x55 && k->vram[0] == 0x66);
    k.put(0x050000, {0x77}); // nothing there
    k.port0(0x050000);
    CHECK(vc_read(k.c, VC_DATA0) == 0);
}

TEST(vidcard_text_layer_draws_cells_in_their_colors) {
    Card k;
    k.put(VC_RESET_TEXT_MAP, {'A', 9, 4, 0});
    // 'A', row 2 of its glyph: .#####.. -- red on navy, then the next cell (a space on 0).
    std::vector<uint16_t> l = k.line(2);
    CHECK(l[0] == k.color(4) && l[1] == k.color(9) && l[5] == k.color(9) && l[6] == k.color(4) && l[7] == k.color(4));
    CHECK(l[8] == 0);
    CHECK(k.line(0)[1] == k.color(4)); // an empty row of the glyph is the background
    // Scrolled one pixel left.
    k.layer(0)[VC_L_HSCROLL + 1] = 1;
    CHECK(k.line(2)[0] == k.color(9));
    // The second row of cells starts at line 16; the map is 128 cells wide.
    k.layer(0)[VC_L_HSCROLL + 1] = 0;
    k.put(VC_RESET_TEXT_MAP + 4 * 128, {'A', 10, 0, 0});
    CHECK(k.line(18)[1] == k.color(10) && k.line(18)[0] == 0);
}

TEST(vidcard_tile_layer_draws_tiles_with_flips_and_palette_offsets) {
    Card k;
    uint8_t* l = k.layer(1);
    l[VC_L_MODE] = VC_TILE | (2 << 3); // lores, 4 bits per pixel, 8x8 tiles
    l[VC_L_MAP] = 0x00;                // 32x32
    l[VC_L_MAPBASE] = 0x01;            // $010000
    l[VC_L_TILEBASE] = 0x01;
    l[VC_L_TILEBASE + 1] = 0x10;       // $011000
    k->cfg[VC_DC_CTRL] = 0x02;
    // Tile 1: the left half of each row is 3, the right half transparent.
    for (int r = 0; r < 8; ++r) k.put(0x011000 + 32 + 4 * r, {0x33, 0x33, 0x00, 0x00});
    k.put(0x010000, {0x20, 0x01, 0x24, 0x01}); // (0,0): tile 1, palette 2; (1,0): flipped
    std::vector<uint16_t> l0 = k.line(0);
    CHECK(l0[0] == k.color(35) && l0[7] == k.color(35) && l0[8] == 0); // 4 lores pixels, doubled
    CHECK(l0[16] == 0 && l0[23] == 0 && l0[24] == k.color(35) && l0[31] == k.color(35));
    CHECK(l0[32] == 0);
    CHECK(k.line(15)[0] == k.color(35) && k.line(16)[0] == 0); // 8 lores rows
    // Scrolling wraps around the map (32 tiles = 256 pixels).
    l[VC_L_HSCROLL] = 0x01; // 256
    CHECK(k.line(0)[0] == k.color(35));
}

TEST(vidcard_bitmap_layer_draws_pixels_and_color_0_is_transparent) {
    Card k;
    uint8_t* l = k.layer(0);
    l[VC_L_MODE] = VC_BITMAP | (3 << 3); // lores, 8 bits per pixel
    l[VC_L_MAPBASE] = l[VC_L_MAPBASE + 1] = l[VC_L_MAPBASE + 2] = 0;
    l[VC_L_STRIDE] = 320 >> 8;
    l[VC_L_STRIDE + 1] = 320 & 0xFF;
    k->cfg[VC_DC_BACK] = 4;
    k->vram[3 * 320 + 5] = 200;
    std::vector<uint16_t> row = k.line(6);
    CHECK(row[10] == k.color(200) && row[11] == k.color(200) && row[9] == k.color(4) && row[12] == k.color(4));
    CHECK(k.line(7)[10] == k.color(200) && k.line(8)[10] == k.color(4));
    // 4 bits per pixel, hires, with a palette offset: pixel 1 of row 0 is the low nibble.
    l[VC_L_MODE] = VC_BITMAP | 0x04 | (2 << 3);
    l[VC_L_STRIDE] = 0;
    l[VC_L_STRIDE + 1] = 64;
    l[VC_L_PALOFS] = 3;
    k->vram[0] = 0x0A;
    CHECK(k.line(0)[0] == k.color(4) && k.line(0)[1] == k.color(58));
    CHECK(k.line(0)[128] == k.color(4)); // past the row's 128 pixels
}

TEST(vidcard_sprites_sit_between_layers_by_priority_and_in_table_order) {
    Card k;
    // Layer 1: a hires 8bpp bitmap, all color 1 in its first 16 pixels.
    uint8_t* l = k.layer(1);
    l[VC_L_MODE] = VC_BITMAP | 0x04 | (3 << 3);
    l[VC_L_MAPBASE] = 0x02; // $020000
    l[VC_L_STRIDE + 1] = 16;
    for (int y = 0; y < 480; ++y)
        for (int x = 0; x < 16; ++x) k->vram[0x020000 + 16 * y + x] = 1;
    k->cfg[VC_DC_CTRL] = 0x02 | 0x08;
    k->cfg[VC_SPR_CTRL] = 1; // hires coordinates
    // An 8x8 4bpp image of 1s at $030000 (address / 32 = $1800).
    for (int i = 0; i < 32; ++i) k->vram[0x030000 + i] = 0x11;
    uint8_t* t = k->vram + VC_RESET_SPR_BASE;
    // Sprite 0 at (4,0), palette 1, priority 1 (below layer 1); sprite 1 at (10,0), palette 2,
    // priority 3; sprite 2 at (12,0), palette 3, priority 3: sprite 1 is in front of it.
    uint8_t s0[8] = {0x18, 0x00, 0, 4, 0, 0, 0x40, 0x01};
    uint8_t s1[8] = {0x18, 0x00, 0, 10, 0, 0, 0xC0, 0x02};
    uint8_t s2[8] = {0x18, 0x00, 0, 12, 0, 0, 0xC0, 0x03};
    std::copy(s0, s0 + 8, t);
    std::copy(s1, s1 + 8, t + 8);
    std::copy(s2, s2 + 8, t + 16);
    std::vector<uint16_t> row = k.line(0);
    CHECK(row[4] == k.color(1));            // sprite 0 is behind layer 1
    CHECK(row[10] == k.color(33));          // sprite 1 in front of it
    CHECK(row[12] == k.color(33));          // ... and of sprite 2
    CHECK(row[18] == k.color(49) && row[19] == k.color(49) && row[20] == 0);
    CHECK(k.line(7)[10] == k.color(33) && k.line(8)[10] == k.color(1));
    // Priority 2 is also above layer 1.
    t[6] = 0x80;
    CHECK(k.line(0)[4] == k.color(17));
    // 16 rows high (height code 1): only its top 8 have 1s -- and flipped, its bottom 8.
    t[6] = 0x80 | 0x04;
    CHECK(k.line(7)[4] == k.color(17) && k.line(8)[4] == k.color(1));
    t[6] = 0x80 | 0x04 | 0x20;
    CHECK(k.line(7)[4] == k.color(1) && k.line(8)[4] == k.color(17) && k.line(15)[4] == k.color(17));
    CHECK(k.line(16)[4] == k.color(1));
}

TEST(vidcard_draws_at_most_32_sprites_on_a_line) {
    Card k;
    k->cfg[VC_DC_CTRL] = 0x08;
    k->cfg[VC_SPR_CTRL] = 1;
    for (int i = 0; i < 32; ++i) k->vram[0x030000 + i] = 0x11;
    for (int i = 0; i < 40; ++i) {
        uint8_t* a = k->vram + VC_RESET_SPR_BASE + 8 * i;
        uint8_t s[8] = {0x18, 0x00, static_cast<uint8_t>((i * 10) >> 8), static_cast<uint8_t>(i * 10), 0, 0, 0xC0, 0x01};
        std::copy(s, s + 8, a);
    }
    std::vector<uint16_t> row = k.line(0);
    CHECK(row[310] == k.color(17)); // sprite 31
    CHECK(row[320] == 0);           // sprite 32: over the limit
    // SPR_COUNT limits how much of the table is looked at.
    k->cfg[VC_SPR_COUNT] = 10;
    CHECK(k.line(0)[90] == k.color(17) && k.line(0)[100] == 0);
}

TEST(vidcard_drawing_commands_draw_clipped_to_the_target) {
    Card k;
    target8(k, 32, 32);
    k.cmd({VC_C_COLOR, 5, VC_C_PLOT, W(3), W(4)});
    CHECK(k->vram[4 * 32 + 3] == 5 && count_set(k, 32, 32) == 1);
    k.cmd({VC_C_CLEAR}); // in color 5
    CHECK(count_set(k, 32, 32) == 32 * 32 && k->vram[32 * 32] == 0);
    k.cmd({VC_C_COLOR, 0, VC_C_CLEAR, VC_C_COLOR, 1});
    CHECK(count_set(k, 32, 32) == 0);
    // A line includes both ends; a diagonal has one pixel a row.
    k.cmd({VC_C_LINE, W(0), W(0), W(9), W(9)});
    CHECK(count_set(k, 32, 32) == 10 && k->vram[9 * 32 + 9] == 1);
    k.cmd({VC_C_COLOR, 0, VC_C_CLEAR, VC_C_COLOR, 1});
    // Lines every way: both ends, one pixel a step of the longer side. (A 168x89 one off the
    // target's left edge once never ended.)
    target8(k, 64, 64);
    const int ends[][4] = {{32, 32, 60, 40}, {32, 32, 40, 60}, {32, 32, 4, 40}, {32, 32, 24, 60},
                           {32, 32, 60, 24}, {32, 32, 40, 4},  {32, 32, 4, 24}, {32, 32, 24, 4},
                           {32, 32, 32, 60}, {32, 32, 60, 32}, {10, 10, 10, 10}};
    for (const auto& e : ends) {
        k.cmd({VC_C_COLOR, 0, VC_C_CLEAR, VC_C_COLOR, 1});
        k.cmd({VC_C_LINE, W(e[0]), W(e[1]), W(e[2]), W(e[3])});
        int steps = std::max(std::abs(e[2] - e[0]), std::abs(e[3] - e[1])) + 1;
        CHECK(count_set(k, 64, 64) == steps && k->vram[e[1] * 64 + e[0]] && k->vram[e[3] * 64 + e[2]]);
    }
    k.cmd({VC_C_LINE, W(136), W(150), W(0xFFE0), W(239)}); // ends (off the target entirely)
    target8(k, 32, 32);
    k.cmd({VC_C_COLOR, 0, VC_C_CLEAR, VC_C_COLOR, 1});
    // A rectangle half off the top left: only what's on the target.
    k.cmd({VC_C_FILLRECT, W(0xFFFB), W(0xFFFB), W(10), W(10)});
    CHECK(count_set(k, 32, 32) == 25 && k->vram[4 * 32 + 4] == 1 && k->vram[5] == 0);
    k.cmd({VC_C_COLOR, 0, VC_C_CLEAR, VC_C_COLOR, 1});
    k.cmd({VC_C_RECT, W(2), W(2), W(4), W(3)});
    CHECK(count_set(k, 32, 32) == 10 && k->vram[3 * 32 + 3] == 0);
    k.cmd({VC_C_COLOR, 0, VC_C_CLEAR, VC_C_COLOR, 1});
    // A circle: symmetrical, its four extremes on it, the middle empty.
    k.cmd({VC_C_CIRCLE, W(16), W(16), W(10)});
    CHECK(k->vram[16 * 32 + 26] && k->vram[16 * 32 + 6] && k->vram[6 * 32 + 16] && k->vram[26 * 32 + 16]);
    CHECK(!k->vram[16 * 32 + 16]);
    int circle = count_set(k, 32, 32);
    std::vector<uint8_t> outline(k->vram, k->vram + 32 * 32);
    k.cmd({VC_C_COLOR, 0, VC_C_CLEAR, VC_C_COLOR, 1});
    // A disc is that circle, filled: x*x + y*y <= 10.5*10.5 has 349 points.
    k.cmd({VC_C_DISC, W(16), W(16), W(10)});
    int disc = count_set(k, 32, 32);
    CHECK(k->vram[16 * 32 + 16] && disc == 349 && circle > 50 && circle < 70);
    for (int i = 0; i < 32 * 32; ++i) CHECK(!outline[i] || k->vram[i]);
    for (int y = 0; y < 32; ++y)
        for (int x = 0; x < 32; ++x) CHECK(k->vram[y * 32 + x] == k->vram[y * 32 + (32 - x) % 32] || x == 0);
    k.cmd({VC_C_COLOR, 0, VC_C_CLEAR, VC_C_COLOR, 1});
    // A triangle: its corners, and what's inside.
    k.cmd({VC_C_TRIANGLE, W(0), W(0), W(10), W(0), W(0), W(10)});
    CHECK(k->vram[0] && k->vram[10] && k->vram[10 * 32] && k->vram[3 * 32 + 3] && !k->vram[6 * 32 + 6]);
    // STATUS says busy while a command is half sent.
    vc_write(k.c, VC_CMD, VC_C_PLOT);
    CHECK(vc_read(k.c, VC_STATUS) & VC_STATUS_BUSY);
    k.cmd({W(1), W(1)});
    CHECK(!(vc_read(k.c, VC_STATUS) & VC_STATUS_BUSY));
}

TEST(vidcard_commands_pack_pixels_and_move_memory) {
    Card k;
    // 4 bits per pixel: pixel 0 is the high nibble.
    k.cmd({VC_C_TARGET, 0, 0x10, 0, W(8), W(16), W(8), 4, VC_C_COLOR, 0xA, VC_C_PLOT, W(1), W(0)});
    k.cmd({VC_C_COLOR, 0x13, VC_C_PLOT, W(2), W(0)}); // (only its low 4 bits)
    CHECK(k->vram[0x1000] == 0x0A && k->vram[0x1001] == 0x30);
    // A character in the current color, over what's there.
    k.cmd({VC_C_TARGET, 0, 0x20, 0, W(8), W(8), W(16), 8, VC_C_COLOR, 7, VC_C_CHAR, W(0), W(0), 'A'});
    CHECK(k->vram[0x2000 + 2 * 8 + 1] == 7 && k->vram[0x2000 + 2 * 8] == 0);
    // COPY overlapping upwards and downwards, FILL.
    k.put(0x3000, {1, 2, 3, 4, 5});
    k.cmd({VC_C_COPY, 0, 0x30, 0x00, 0, 0x30, 0x01, 0, 0, 4});
    CHECK(k->vram[0x3001] == 1 && k->vram[0x3004] == 4);
    k.cmd({VC_C_COPY, 0, 0x30, 0x01, 0, 0x30, 0x00, 0, 0, 4});
    CHECK(k->vram[0x3000] == 1 && k->vram[0x3003] == 4);
    k.cmd({VC_C_FILL, 0x80, 0, 0, 0, 0, 3, 0xEE, VC_C_COPY, 0x80, 0, 0, 0, 0x40, 0, 0, 0, 3});
    CHECK(k.psram[2] == 0xEE && k->vram[0x4002] == 0xEE && k->vram[0x4003] == 0);
    // BLIT: a 2x2 source; 0 is skipped when asked.
    k.put(0x5000, {9, 0, 0, 9});
    k.cmd({VC_C_TARGET, 0, 0x60, 0, W(4), W(4), W(4), 8, VC_C_COLOR, 3, VC_C_CLEAR});
    k.cmd({VC_C_BLIT, 0, 0x50, 0, W(2), W(2), W(2), W(1), W(1), 1});
    CHECK(k->vram[0x6005] == 9 && k->vram[0x6006] == 3 && k->vram[0x6009] == 3 && k->vram[0x600A] == 9);
    k.cmd({VC_C_BLIT, 0, 0x50, 0, W(2), W(2), W(2), W(1), W(1), 0});
    CHECK(k->vram[0x6006] == 0);
    // An unknown opcode is one byte; a TARGET of an odd depth draws nothing.
    k.cmd({0x7F, VC_C_TARGET, 0, 0x70, 0, W(8), W(8), W(8), 3, VC_C_PLOT, W(0), W(0)});
    CHECK(k->vram[0x7000] == 0 && !(vc_read(k.c, VC_STATUS) & VC_STATUS_BUSY));
}

TEST(vidcard_reset_bit_puts_everything_back) {
    Card k;
    k.put(VC_CFG_BASE, {0x0F, 5});
    k.put(VC_RESET_TEXT_MAP, {'X'});
    vc_write(k.c, VC_IEN, 1);
    vc_write(k.c, VC_CTRL, 0x80);
    CHECK(k->cfg[VC_DC_CTRL] == 1 && k->cfg[VC_DC_BACK] == 0 && k->vram[VC_RESET_TEXT_MAP] == ' ' && k->ien == 0);
    CHECK(vc_read(k.c, VC_ADDR0_L) == 0 && vc_read(k.c, VC_INC0_L) == 1);
}

TEST(vidcard_mouse_registers_snapshot_the_position_and_count_the_wheel) {
    Card k;
    auto xy = [&](int& x, int& y) { // as LDD VC_MOUSE_X then LDD VC_MOUSE_Y read them
        x = vc_read(k.c, VC_MOUSE_X_H) << 8;
        x |= vc_read(k.c, VC_MOUSE_X_L);
        y = vc_read(k.c, VC_MOUSE_Y_H) << 8;
        y |= vc_read(k.c, VC_MOUSE_Y_L);
    };
    int x, y;
    CHECK(vc_read(k.c, VC_MOUSE_BTN) == 0); // no mouse seen yet
    vc_mouse_to(k.c, 300, 200, 1);
    CHECK((k->isr & VC_IRQ_INPUT) && vc_read(k.c, VC_MOUSE_BTN) == 0x81);
    xy(x, y);
    CHECK(x == 300 && y == 200);
    // Reading X's high byte takes the snapshot: a move after it doesn't tear X or Y.
    CHECK(vc_read(k.c, VC_MOUSE_X_H) == 1);
    vc_mouse_by(k.c, -100, 50, 2);
    CHECK(vc_read(k.c, VC_MOUSE_X_L) == (300 & 0xFF) && vc_read(k.c, VC_MOUSE_Y_L) == 200);
    xy(x, y);
    CHECK(x == 200 && y == 250 && vc_read(k.c, VC_MOUSE_BTN) == 0x82);
    // Kept on the screen.
    vc_mouse_by(k.c, -1000, 1000, 0);
    xy(x, y);
    CHECK(x == 0 && y == 479);
    vc_mouse_to(k.c, 5000, -3, 0);
    xy(x, y);
    CHECK(x == 639 && y == 0);
    // The wheel: clicks since the last read.
    vc_mouse_wheel(k.c, 2);
    vc_mouse_wheel(k.c, -5);
    CHECK(vc_read(k.c, VC_MOUSE_WHEEL) == 0xFD && vc_read(k.c, VC_MOUSE_WHEEL) == 0);
    // The input interrupt, when enabled.
    vc_write(k.c, VC_ISR, 0xFF);
    vc_write(k.c, VC_IEN, VC_IRQ_INPUT);
    CHECK(!vc_irq(k.c));
    vc_mouse_to(k.c, 10, 10, 0);
    CHECK(vc_irq(k.c));
    // A reset leaves the mouse where it is.
    vc_write(k.c, VC_CTRL, 0x80);
    xy(x, y);
    CHECK(x == 10 && y == 10 && k->ien == 0);
}

TEST(vidcard_key_queue_gives_usage_codes_and_the_characters_they_type) {
    Card k;
    auto take = [&](int& ch) {
        int u = vc_read(k.c, VC_KEY);
        ch = vc_read(k.c, VC_KEY_CHAR);
        return u;
    };
    int ch;
    CHECK(take(ch) == 0 && ch == 0 && !(vc_read(k.c, VC_STATUS) & VC_STATUS_KEY));
    vc_key(k.c, 0x04, 1); // a
    vc_key(k.c, 0x04, 0);
    CHECK((vc_read(k.c, VC_STATUS) & VC_STATUS_KEY) && (k->isr & VC_IRQ_INPUT));
    CHECK(take(ch) == 0x04 && ch == 'a');
    CHECK(take(ch) == 0x04 && ch == ('a' | 0x80)); // its release
    // Shift, and the modifiers register.
    vc_key(k.c, 0xE1, 1);
    CHECK(vc_read(k.c, VC_KEY_MODS) == VC_MOD_LSHIFT);
    vc_key(k.c, 0x1F, 1); // 2
    vc_key(k.c, 0xE1, 0);
    vc_key(k.c, 0x38, 1); // /
    CHECK(take(ch) == 0xE1 && ch == 0);
    CHECK(take(ch) == 0x1F && ch == '@');
    CHECK(take(ch) == 0xE1 && ch == 0x80 && vc_read(k.c, VC_KEY_MODS) == 0);
    CHECK(take(ch) == 0x38 && ch == '/');
    // Caps Lock turns letters only; Ctrl makes control characters; arrows type nothing.
    vc_write(k.c, VC_IN_CTRL, VC_IN_FLUSH);
    CHECK(vc_read(k.c, VC_KEY) == 0);
    vc_key(k.c, 0x39, 1);
    vc_key(k.c, 0x05, 1); // b
    vc_key(k.c, 0x1E, 1); // 1
    vc_key(k.c, 0x39, 1);
    vc_key(k.c, 0xE4, 1); // right Ctrl
    vc_key(k.c, 0x06, 1); // c
    vc_key(k.c, 0xE4, 0);
    vc_key(k.c, 0x52, 1); // up
    vc_key(k.c, 0x28, 1); // Enter
    vc_key(k.c, 0x4C, 1); // Delete
    vc_key(k.c, 0x5A, 1); // keypad 2
    int seen[11], chars[11];
    for (int i = 0; i < 11; ++i) seen[i] = take(chars[i]);
    CHECK(seen[1] == 0x05 && chars[1] == 'B' && chars[2] == '1');
    CHECK(seen[5] == 0x06 && chars[5] == 3);
    CHECK(seen[7] == 0x52 && chars[7] == 0 && chars[8] == '\r' && chars[9] == 0x7F && chars[10] == '2');
    // 32 events at most; the rest are lost.
    for (int i = 0; i < 40; ++i) vc_key(k.c, 0x04, 1);
    int n = 0;
    while (vc_read(k.c, VC_KEY)) ++n;
    CHECK(n == VC_KEY_QUEUE);
}

TEST(vidcard_pointer_puts_sprite_0_where_the_mouse_is_each_frame) {
    Card k;
    uint32_t s0 = VC_RESET_SPR_BASE;
    vc_mouse_to(k.c, 301, 151, 0);
    vc_begin_line(k.c, VC_HEIGHT);
    CHECK(k->vram[s0 + 3] == 0); // not asked for
    vc_write(k.c, VC_IN_CTRL, VC_IN_POINTER | VC_IN_KEYS);
    CHECK(vc_read(k.c, VC_IN_CTRL) == (VC_IN_POINTER | VC_IN_KEYS));
    vc_begin_line(k.c, VC_HEIGHT);
    // 320x240 sprite coordinates: halved.
    CHECK(k->vram[s0 + 2] == 0 && k->vram[s0 + 3] == 150 && k->vram[s0 + 4] == 0 && k->vram[s0 + 5] == 75);
    k->cfg[VC_SPR_CTRL] = 1;
    vc_begin_line(k.c, VC_HEIGHT);
    CHECK(k->vram[s0 + 2] == 1 && k->vram[s0 + 3] == 301 - 256 && k->vram[s0 + 5] == 151);
}

TEST(vidcard_beam_follows_cpu_time_and_raises_its_interrupts) {
    constexpr double kHz = 3579545.0;
    VideoDevice v(kHz);
    auto run = [&](double seconds) {
        for (auto c = static_cast<uint64_t>(seconds * kHz); c > 0; c -= std::min<uint64_t>(c, 50))
            v.tick(static_cast<uint32_t>(std::min<uint64_t>(c, 50)));
    };
    auto line = [&] { return v.read(VC_LINE_H) << 8 | v.read(VC_LINE_L); };
    CHECK(line() == 0 && !(v.read(VC_STATUS) & VC_STATUS_VBLANK));
    run(240.5 / (60 * 525));
    CHECK(line() == 240);
    // Vertical blank from line 480: the flag, the frame count, but no interrupt until enabled.
    run(240.0 / (60 * 525));
    CHECK(line() == 480 && (v.read(VC_STATUS) & VC_STATUS_VBLANK) && v.read(VC_FRAME) == 1);
    CHECK((v.read(VC_ISR) & VC_IRQ_VSYNC) && !v.irq_asserted());
    v.write(VC_IEN, VC_IRQ_VSYNC);
    CHECK(v.irq_asserted());
    v.write(VC_ISR, VC_IRQ_VSYNC);
    CHECK(!v.irq_asserted());
    // A line interrupt at line 100 of the next frame: 1/60 s from line 0, plus 100 lines.
    v.write(VC_IEN, VC_IRQ_LINE);
    v.write(VC_LINE_H, 0);
    v.write(VC_LINE_L, 100);
    v.write(VC_ISR, 0xFF);
    run(144.0 / (60 * 525)); // to line 99 of the next frame
    CHECK(line() == 99 && !v.irq_asserted());
    run(1.0 / (60 * 525));
    CHECK(line() == 100 && v.irq_asserted());
    // 60 frames a second of CPU time.
    uint8_t f = v.read(VC_FRAME);
    run(1.0);
    CHECK(static_cast<uint8_t>(v.read(VC_FRAME) - f) == 60);
}

TEST(vidcard_device_draws_frames_only_once_a_program_has_used_it) {
    struct Sink : pugputer::VideoSink {
        int asked = 0, frames = 0, drawn = 0;
        uint32_t first = 0;
        bool wants_frame() override { return ++asked, true; }
        void frame(const uint32_t* p) override {
            ++frames;
            if (p) ++drawn, first = p[0];
        }
    } sink;
    VideoDevice v;
    v.set_sink(&sink);
    for (int i = 0; i < 60000 * 3; ++i) v.tick(10);
    CHECK(!v.active() && sink.frames == 0 && v.frames_drawn() == 0);
    // A red backdrop.
    v.write(VC_ADDR0_H, 0x04);
    v.write(VC_ADDR0_M, 0x00);
    v.write(VC_ADDR0_L, VC_DC_BACK);
    v.write(VC_DATA0, 9);
    for (int i = 0; i < 60000 * 3; ++i) v.tick(10);
    CHECK(v.active() && sink.frames >= 4 && sink.drawn >= 4 && sink.first == 0xFF0000);
    CHECK(v.pixel(639, 479) == 0xFF0000);
    v.reset();
    CHECK(!v.active());
}
