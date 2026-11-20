;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 C library (LIBPUG.A)
;    FILE: pugsnd.asm -- <pug/sound.h>: the OPL3, and SONGKIT's songs
;
; SONGKIT's player is gamekit/sk_play.asm, included here as it is (with
; SK_LIBRARY: its variables in bss). A song's ticks come from the OPL3's
; Timer 2, which song_poll looks at: song_start makes vc_vsync call it while
; it waits, so a program that waits for each frame keeps the song going.
;------------------------------------------------------------------------------
            INCLUDE defines.d
SK_LIBRARY  equ  1
            EXPORT _song_start,_song_pstart,_song_poll,_song_tick,_song_stop
            EXPORT _song_off,_opl_write
            IMPORT _vc_idle
            SECTION code
; int song_start(const void *song): a .SNG's contents, in memory -> 0, or -1
; (it isn't a song)
_song_start PSHS Y,U
            LDX  6,S
            JSR  SK_START
            BCS  SN_FAIL
SN_ON       LDD  #_song_poll           ; (vc_vsync keeps it going)
            STD  _vc_idle
            CLRD
            PULS Y,U,PC
SN_FAIL     LDD  #-1
            PULS Y,U,PC
; int song_pstart(const unsigned char *pages, int n, int bank): a song in n
; RAM pages of its own (in order), seen through bank 1-3 (the player's while
; it plays) -> 0, or -1
_song_pstart PSHS Y,U
            LDX  6,S
            LDA  9,S
            LDB  11,S
            JSR  SK_PSTART
            BCS  SN_FAIL
            BRA  SN_ON
; void song_poll(void): a tick, if one is due (often: at least every few ms)
_song_poll  PSHS Y,U
            JSR  SK_POLL
            PULS Y,U,PC
; void song_tick(void): one tick now (a program keeping its own time)
_song_tick  PSHS Y,U
            JSR  SK_TICK
            PULS Y,U,PC
; void song_stop(void): its notes let go
_song_stop  PSHS Y,U
            JSR  SK_STOP
            PULS Y,U,PC
; void song_off(void): the chip silent and as it starts (before a program
; ends)
_song_off   PSHS Y,U
            JSR  SK_OFF
            CLRD
            STD  _vc_idle
            PULS Y,U,PC
; void opl_write(int reg, int value): reg 0-0xFF the first array, 0x100-0x1FF
; the second
_opl_write  LDE  2,S
            LDA  3,S
            LDB  5,S
            JMP  SKW
            INCLUDE sk_play.asm
            ENDSECT                    ; (sk_play's bss)
;------------------------------------------------------------------------------
; End of pugsnd.asm
;------------------------------------------------------------------------------
