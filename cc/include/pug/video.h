/* pug/video.h -- CC (the Pugputer's C compiler): the video card (LIBPUG.A).

   The card's own address space is 24 bits: video memory (256KB), the display
   settings, the gamepads, the palette, and 8MB of PSRAM. Its addresses are
   longs here. What the card does, and the layouts of its layers, tiles and
   sprites, is in VIDCARD.TXT (vidcard/README.md in the project). */
#ifndef _PUG_VIDEO_H
#define _PUG_VIDEO_H

/* Where things are. */
#define VC_VRAM     0x000000L   /* video memory, 256KB */
#define VC_CFG      0x040000L   /* the display settings */
#define VC_PAL      0x040200L   /* the palette: 256 colors, RGB565, 2 bytes each */
#define VC_PSRAM    0x800000L   /* 8MB, for what isn't on screen yet */
#define VC_TEXTMAP  0x038000L   /* at reset: the text screen, 128x32 cells of 4 */
#define VC_FONT     0x03F000L   /*   its font, 8x16 */
#define VC_SPRITES  0x037C00L   /*   the sprite table */

/* A layer's mode (vc_layer): one of each. */
#define LM_TEXT     0x00
#define LM_TILE     0x01
#define LM_BITMAP   0x02
#define LM_HIRES    0x04        /* 640x480 (else 320x240, its pixels doubled) */
#define LM_1BPP     0x00
#define LM_2BPP     0x08
#define LM_4BPP     0x10
#define LM_8BPP     0x18
#define LM_BIG      0x20        /* 16x16 tiles; a text layer's 8x16 font */
/* Its map's size: a width and a height, in cells. */
#define LW_32       0x00
#define LW_64       0x01
#define LW_128      0x02
#define LW_256      0x03
#define LH_32       0x00
#define LH_64       0x04
#define LH_128      0x08
#define LH_256      0x0C
/* vc_show's bits */
#define SHOW_L0     0x01
#define SHOW_L1     0x02
#define SHOW_L2     0x04
#define SHOW_SPR    0x08
/* A tile map's entry: the tile (0-1023), flips, palette offset (x16). */
#define TILE(n, pal)  ((n) | ((pal) << 12))
#define TILE_HFLIP  0x0400
#define TILE_VFLIP  0x0800
/* A sprite's size (spr_set): a width, a height, flips, and where it is. */
#define SS_W8       0x00
#define SS_W16      0x01
#define SS_W32      0x02
#define SS_W64      0x03
#define SS_H8       0x00
#define SS_H16      0x04
#define SS_H32      0x08
#define SS_H64      0x0C
#define SS_HFLIP    0x10
#define SS_VFLIP    0x20
#define SS_OFF      0x00        /* not shown */
#define SS_BACK     0x40        /* in front of layer 0 */
#define SS_MID      0x80        /* in front of layer 1 */
#define SS_FRONT    0xC0        /* in front of everything */
#define SC_8BPP     0x80        /* its color byte: 8 bits a pixel (else 4, and
                                   the low 4 bits are its palette offset) */
/* A color, RGB565, from 0-255 each. */
#define VC_RGB(r, g, b) \
    ((((unsigned)(r) & 0xF8) << 8) | (((unsigned)(g) & 0xFC) << 3) | ((unsigned)(b) >> 3))

void vc_reset(void);            /* as it starts: a blank text screen */
void vc_poke(long addr, int value);
int vc_peek(long addr);
void vc_poke16(long addr, unsigned value);              /* high byte first */
void vc_write(long addr, const void *src, unsigned n);
void vc_read(void *dst, long addr, unsigned n);
void vc_fill(long addr, int value, long n);             /* the card does these */
void vc_copy(long dst, long src, long n);
void vc_wait(void);             /* until it has done them (and the drawing) */

void vc_layer(int layer, int mode, int map, long mapbase, long tilebase);
void vc_scroll(int layer, int x, int y);
void vc_stride(int layer, unsigned stride);             /* a bitmap's bytes a row */
void vc_show(int what);         /* SHOW_L0 | ... */
void vc_backdrop(int color);
void vc_color(int index, unsigned rgb565);
void vc_text(int col, int row, const char *s, int fg, int bg); /* the text screen */

void vc_vsync(void);            /* waits for vertical blank (at once, if one began
                                   since the last wait), calling vc_idle meanwhile */
int vc_frame(void);             /* frames shown, modulo 256 */
extern void (*vc_idle)(void);   /* (song_start sets it to song_poll) */

/* Drawing, into the target, in the color. */
void gfx_target(long addr, int stride, int w, int h, int bits);
void gfx_color(int c);
void gfx_plot(int x, int y);
void gfx_line(int x0, int y0, int x1, int y1);
void gfx_rect(int x, int y, int w, int h);
void gfx_fillrect(int x, int y, int w, int h);
void gfx_circle(int x, int y, int r);
void gfx_disc(int x, int y, int r);
void gfx_triangle(int x0, int y0, int x1, int y1, int x2, int y2);
void gfx_clear(void);
void gfx_font(long addr, int height);
void gfx_char(int x, int y, int c);
void gfx_text(int x, int y, const char *s);
void gfx_blit(long src, int stride, int w, int h, int x, int y, int flags);

/* Sprites, in the table the card starts with. image: its pixels' address in
   video memory (a multiple of 32). */
void spr_set(int n, long image, int x, int y, int size, int color);
void spr_move(int n, int x, int y);
void spr_count(int n);          /* entries in use, 0-128 */
void spr_hires(int on);         /* placed in 640x480 (else 320x240) */

#endif
