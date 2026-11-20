/* pug/sound.h -- CC (the Pugputer's C compiler): the OPL3 music chip, and
   SONGKIT's songs (LIBPUG.A, with SONGKIT's own player).

   A song is a .SNG file's contents. Its ticks come from the OPL3's Timer 2,
   which song_poll looks at: call it often (every few ms). song_start makes
   vc_vsync call it while it waits, so a program that waits for each frame
   keeps the song going. song_off before the program ends. */
#ifndef _PUG_SOUND_H
#define _PUG_SOUND_H

int song_start(const void *song);       /* -> 0, or -1: not a song */
int song_pstart(const unsigned char *pages, int n, int bank);
                                /* a song in n RAM pages of its own (in order),
                                   seen through bank 1-3 while it plays */
void song_poll(void);
void song_tick(void);           /* one tick now, for a program with its own clock */
void song_stop(void);           /* its notes let go */
void song_off(void);            /* the chip silent, as it starts */

void opl_write(int reg, int value);     /* 0-0xFF, and 0x100-0x1FF the second array */

#endif
