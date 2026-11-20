/* LIBPUG: the video card's memory, settings and palette, drawing into a
   bitmap and reading it back, a sprite's entry, frames, the input devices
   (none here), and a SONGKIT song played for half a second. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pug/video.h>
#include <pug/input.h>
#include <pug/sound.h>

#define BMP 0x10000L

unsigned char buf[64];

void row(int y, int x, int n)
{
    int i;
    vc_read(buf, BMP + (long)y * 64 + x, n);
    for (i = 0; i < n; i++)
        printf("%d", buf[i]);
    printf("\n");
}

int main(void)
{
    struct pad p;
    int i, f0, ch, x, y;
    char *song;
    FILE *fp;
    long n;

    vc_reset();
    vc_poke(0x20000L, 0x5A);
    vc_poke16(0x20001L, 0x1234);
    printf("peek %x %x %x\n", vc_peek(0x20000L), vc_peek(0x20001L), vc_peek(0x20002L));
    vc_write(0x20010L, "hello", 6);
    vc_read(buf, 0x20010L, 6);
    printf("read %s\n", buf);
    vc_fill(0x20100L, 7, 300L);
    vc_copy(0x20300L, 0x20010L, 6L);
    vc_wait();
    printf("fill %d %d %d copy %c\n", vc_peek(0x20100L), vc_peek(0x2022BL), vc_peek(0x2022CL), vc_peek(0x20301L));
    vc_layer(1, LM_BITMAP | LM_8BPP, LW_64 | LH_32, BMP, 0x30000L);
    vc_scroll(1, 3, -2);
    vc_stride(1, 64);
    vc_show(SHOW_L0 | SHOW_L1 | SHOW_SPR);
    vc_backdrop(17);
    vc_read(buf, VC_CFG, 2);
    printf("cfg %d %d", buf[0], buf[1]);
    vc_read(buf, VC_CFG + 0x20, 14);
    for (i = 0; i < 14; i++)
        printf(" %x", buf[i]);
    printf("\n");
    vc_color(200, VC_RGB(255, 0, 255));
    printf("pal %x\n", vc_peek(VC_PAL + 400) * 256 + vc_peek(VC_PAL + 401));

    gfx_target(BMP, 64, 64, 32, 8);
    gfx_color(0);
    gfx_clear();
    gfx_color(5);
    gfx_fillrect(2, 1, 4, 2);
    gfx_color(9);
    gfx_line(0, 5, 7, 5);
    gfx_color(3);
    gfx_plot(10, 0);
    vc_wait();
    row(0, 0, 12);
    row(1, 0, 8);
    row(2, 0, 8);
    row(3, 0, 8);
    row(5, 0, 9);
    gfx_color(1);
    gfx_text(16, 8, "Hi");
    vc_wait();
    for (y = 8, n = 0; y < 24; y++) {
        vc_read(buf, BMP + (long)y * 64 + 16, 16);
        for (i = 0; i < 16; i++)
            n += buf[i];
    }
    printf("text %ld\n", n);

    spr_set(3, 0x1000L, 100, -20, SS_W16 | SS_H16 | SS_FRONT, SC_8BPP);
    spr_move(3, 120, 40);
    spr_count(8);
    vc_read(buf, VC_SPRITES + 24, 8);
    printf("spr");
    for (i = 0; i < 8; i++)
        printf(" %x", buf[i]);
    vc_read(buf, VC_CFG + 3, 1);
    printf(" count %d\n", buf[0]);

    f0 = vc_frame();
    for (i = 0; i < 3; i++)
        vc_vsync();
    printf("frames %d\n", (vc_frame() - f0) & 255);

    key_grab(1);
    i = key_get(&ch);
    printf("key %d %d mods %d\n", i, ch, key_mods());
    key_grab(0);
    i = mouse_get(&x, &y);
    printf("mouse %d %d wheel %d\n", x >= 0 && x < 640, y >= 0 && y < 480, mouse_wheel());
    i = pad_get(0, &p);
    printf("pad %d %d\n", i, p.flags);

    printf("notsong %d\n", song_start("nothing here, not a song"));
    fp = fopen("SWAMP.SNG", "rb");
    if (fp) {
        song = malloc(12000);
        n = fread(song, 1, 12000, fp);
        fclose(fp);
        printf("song %ld %d\n", n, song_start(song));
        for (i = 0; i < 30; i++)
            vc_vsync();
        song_stop();
        song_off();
        printf("idle %d\n", vc_idle == 0);
    }
    vc_reset();
    return 0;
}
