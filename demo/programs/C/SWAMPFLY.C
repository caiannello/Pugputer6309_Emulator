/* SWAMPFLY.C -- the swamp at night, in C: SWAMP.ASM's three tile layers in
   parallax (the same TILEKIT files, read as it starts), its music, and a
   firefly over them that you fly.

     Arrows, or a gamepad's d-pad or left stick: up and down, and left and
     right to slow the swamp down (or turn it round) and speed it up. The
     mouse: the firefly follows it. Esc, Q, or the pad's Start or East
     button: back to the shell.

   It shows LIBPUG.A (<pug/video.h>, <pug/input.h>, <pug/sound.h>) at work:
   tile layers and their scrolling, the palette, the card's drawing commands
   making the firefly's picture, a sprite, the keys, the mouse and the pads,
   and SONGKIT's player.

     CC swampfly.c      makes SWAMPFLY.COM (it looks for the swamp's files in
     SWAMPFLY           /DEMO, then in the current directory)

   The pictures are SWAMP1.TLS/MAP (the sky, at the back) to SWAMP3.TLS/MAP
   (the ground, in front): TILEKIT SWAMP.TKT edits them. The music is
   SWAMP.SNG (SONGKIT SWAMP.SNG); without it, the swamp is silent. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pug/video.h>
#include <pug/input.h>
#include <pug/sound.h>

#define ROOM    0xC000L         /* each layer's video memory: its tiles, its map */
#define FLYPIC  0x030000L       /* the firefly's picture (16x16, 8 bits a pixel) */
#define GLOW    240             /* its colors: 240-243 (the scenery has 1-239) */
#define SONGMAX 16384

unsigned char buf[512];
char path[24];
int wave[16] = { 0, 1, 2, 2, 3, 2, 2, 1, 0, -1, -2, -2, -3, -2, -2, -1 };

/* The file "name" in /DEMO, or else here (0: neither). */
FILE *try_open(char *name)
{
    FILE *f;
    strcpy(path, "/DEMO/");
    strcat(path, name);
    f = fopen(path, "rb");
    if (!f)
        f = fopen(name, "rb");
    return f;
}

void fail(char *name, char *why)
{
    vc_reset();
    printf("%s: %s\n", name, why);
    exit(1);
}

FILE *open_file(char *name)
{
    FILE *f = try_open(name);
    if (!f)
        fail(name, "not found (in /DEMO or here)");
    return f;
}

/* n bytes of a file into buf: all of them, starting with magic (0: any). */
void need(FILE *f, char *name, unsigned n, char *magic)
{
    if (fread(buf, 1, n, f) != n || (magic && memcmp(buf, magic, 4) != 0))
        fail(name, "not a TILEKIT file of the kind expected");
}

/* The rest of a file into video memory at addr. */
void stream(FILE *f, long addr)
{
    unsigned n;
    while ((n = fread(buf, 1, sizeof buf, f)) != 0) {
        vc_write(addr, buf, n);
        addr += n;
    }
    fclose(f);
}

/* A map's width or height (32, 64, 128 or 256 cells) as the card has it: 0-3. */
int size_code(unsigned n)
{
    int c = 0;
    while (n > 32 && c < 3) {
        n >>= 1;
        c++;
    }
    return c;
}

/* Layer n: its tiles at the start of its room, its map at the end; the first
   one's palette is the card's. */
void load_layer(int n)
{
    FILE *f;
    long room = n * ROOM, map;
    int mode, wc, hc;
    char name[14];

    sprintf(name, "SWAMP%d.TLS", n + 1);
    f = open_file(name);
    need(f, name, 16, "PTS1");          /* tile size, bits a pixel, flags */
    mode = LM_TILE;
    if (buf[4] == 16)
        mode |= LM_BIG;
    if (buf[5] >= 2)
        mode += LM_2BPP;
    if (buf[5] >= 4)
        mode += LM_2BPP;
    if (buf[5] >= 8)
        mode += LM_2BPP;
    if (buf[6] & 1)
        mode |= LM_HIRES;
    need(f, name, 512, 0);              /* the palette */
    if (n == 0)
        vc_write(VC_PAL, buf, 512);
    stream(f, room);

    sprintf(name, "SWAMP%d.MAP", n + 1);
    f = open_file(name);
    need(f, name, 48, "PTM1");          /* width, height (cells) */
    wc = size_code(buf[4] * 256 + buf[5]);
    hc = size_code(buf[6] * 256 + buf[7]);
    map = room + ROOM - (2048L << (wc + hc));
    stream(f, map);
    vc_layer(n, mode, wc | (hc << 2), map, room);
}

/* The song, if there is one, in memory -> it, or 0. */
char *load_song(void)
{
    FILE *f = try_open("SWAMP.SNG");
    char *song;
    if (!f)
        return 0;
    song = malloc(SONGMAX);
    if (song && fread(song, 1, SONGMAX, f) == 0) {
        free(song);
        song = 0;
    }
    fclose(f);
    return song;
}

/* The firefly: discs in its four colors, drawn by the card into its picture. */
void make_firefly(void)
{
    vc_color(GLOW, VC_RGB(255, 255, 200));
    vc_color(GLOW + 1, VC_RGB(220, 255, 80));
    vc_color(GLOW + 2, VC_RGB(120, 200, 20));
    vc_color(GLOW + 3, VC_RGB(40, 90, 0));
    gfx_target(FLYPIC, 16, 16, 16, 8);
    gfx_color(0);
    gfx_clear();
    gfx_color(GLOW + 3);
    gfx_disc(7, 7, 7);
    gfx_color(GLOW + 2);
    gfx_disc(7, 7, 5);
    gfx_color(GLOW + 1);
    gfx_disc(7, 7, 3);
    gfx_color(GLOW);
    gfx_disc(7, 7, 1);
    vc_wait();
    spr_set(0, FLYPIC, 152, 112, SS_W16 | SS_H16 | SS_FRONT, SC_8BPP);
    spr_count(1);
}

int main(void)
{
    struct pad pad;
    unsigned pos = 0, frame = 0;
    int speed = 1, x = 160, y = 120, held = 0, quit = 0;
    int code, ch, b, mx, my, lastx = -1, lasty = -1, glow;
    char *song;

    vc_reset();
    printf("Loading the swamp...\n");
    for (b = 0; b < 3; b++)
        load_layer(b);
    song = load_song();
    make_firefly();
    key_grab(1);
    vc_vsync();                         /* all on together, at a vertical blank */
    vc_backdrop(0);
    vc_show(SHOW_L0 | SHOW_L1 | SHOW_L2 | SHOW_SPR);
    if (song && song_start(song) != 0) {
        free(song);                     /* (not a song: the swamp silent) */
        song = 0;
    }
    while (!quit) {
        vc_vsync();                     /* (the song plays while it waits) */
        frame++;

        /* The keys held (each press and release comes as an event). */
        while ((code = key_get(&ch)) != 0) {
            b = 0;
            if (code == KEY_UP)
                b = PAD_UP;
            else if (code == KEY_DOWN)
                b = PAD_DOWN;
            else if (code == KEY_LEFT)
                b = PAD_LEFT;
            else if (code == KEY_RIGHT)
                b = PAD_RIGHT;
            else if (!(ch & KEY_RELEASE) && (code == KEY_ESC || code == KEY_A + 'Q' - 'A'))
                quit = 1;
            if (ch & KEY_RELEASE)
                held &= ~b;
            else
                held |= b;
        }
        /* And the first gamepad, the same way. */
        b = held;
        if (pad_get(0, &pad)) {
            b |= pad.dpad;
            if (pad.ly < -40)
                b |= PAD_UP;
            if (pad.ly > 40)
                b |= PAD_DOWN;
            if (pad.lx < -40)
                b |= PAD_LEFT;
            if (pad.lx > 40)
                b |= PAD_RIGHT;
            if ((pad.btn2 & BT_START) || (pad.btn1 & BT_EAST))
                quit = 1;
        }
        if ((b & PAD_UP) && y > 16)
            y -= 2;
        if ((b & PAD_DOWN) && y < 224)
            y += 2;
        if ((frame & 7) == 0) {
            if ((b & PAD_RIGHT) && speed < 6)
                speed++;
            if ((b & PAD_LEFT) && speed > -4)
                speed--;
        }

        /* The mouse: when it moves, the firefly goes where it is. Otherwise it
           drifts to the place for its speed. */
        if ((mouse_get(&mx, &my) & MB_SEEN) && (mx != lastx || my != lasty)) {
            if (lastx >= 0) {
                x = mx / 2;
                y = my / 2;
            }
            lastx = mx;
            lasty = my;
        } else
            x += (160 + speed * 16 - x) / 8;
        spr_move(0, x - 8, y - 8 + wave[(frame >> 1) & 15]);

        /* The swamp: the sky still, the bayou at half the speed, the ground
           at twice it. (The maps wrap, and so does pos, at a multiple of
           their width: no jumps.) */
        pos += speed;
        vc_scroll(1, pos >> 1, 0);
        vc_scroll(2, pos << 1, 0);

        /* It glows, on and off. */
        glow = frame & 31;
        if (glow > 15)
            glow = 31 - glow;
        vc_color(GLOW + 3, VC_RGB(20 + glow * 6, 50 + glow * 8, 0));
    }
    if (song)
        song_off();
    key_grab(0);
    vc_reset();
    return 0;
}
