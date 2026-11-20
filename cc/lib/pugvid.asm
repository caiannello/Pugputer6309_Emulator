;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 C library (LIBPUG.A)
;    FILE: pugvid.asm -- <pug/video.h>: the video card
;
; An address in the card's space is a long (24 bits: video memory, the
; settings, the palette, the PSRAM). These use data port 0 and the command
; port; a program's interrupt handler that writes the card should keep to
; port 1. See vidcard/README.md for the card itself.
;------------------------------------------------------------------------------
            INCLUDE defines.d
            INCLUDE vidcard.d
            EXPORT _vc_reset,_vc_poke,_vc_peek,_vc_poke16,_vc_write,_vc_read
            EXPORT _vc_fill,_vc_copy,_vc_layer,_vc_scroll,_vc_stride,_vc_show
            EXPORT _vc_backdrop,_vc_color,_vc_vsync,_vc_frame,_vc_wait,_vc_text
            EXPORT _vc_idle,__vc_inctrl
            EXPORT _gfx_target,_gfx_color,_gfx_plot,_gfx_line,_gfx_rect
            EXPORT _gfx_fillrect,_gfx_circle,_gfx_disc,_gfx_triangle,_gfx_clear
            EXPORT _gfx_font,_gfx_char,_gfx_text,_gfx_blit
            EXPORT _spr_set,_spr_move,_spr_count,_spr_hires
            SECTION code
;------------------------------------------------------------------------------
; The card as it starts (a blank text screen; the keys back to the console).
_vc_reset   LDA  #$80
            STA  VC_CTRL
            CLR  __vc_inctrl
            RTS
; X -> a long, an address: port 0 there, stepping 1.
SETP0       LDA  1,X
            STA  VC_ADDR0
            LDD  2,X
            STD  VC_ADDR0M
            LDD  #1
            STD  VC_INC0
            RTS
; B = an offset in the display settings: port 0 there, stepping 1.
SETCFG      LDA  #VC_CFG/$10000
            STA  VC_ADDR0
            CLRA
            STD  VC_ADDR0M
            LDD  #1
            STD  VC_INC0
            RTS
; void vc_poke(long addr, int value); int vc_peek(long addr);
; void vc_poke16(long addr, unsigned value) (high byte first)
_vc_poke    LEAX 2,S
            JSR  SETP0
            LDB  7,S
            STB  VC_DATA0
            RTS
_vc_peek    LEAX 2,S
            JSR  SETP0
            LDB  VC_DATA0
            CLRA
            RTS
_vc_poke16  LEAX 2,S
            JSR  SETP0
            LDD  6,S
            STA  VC_DATA0
            STB  VC_DATA0
            RTS
; void vc_write(long addr, const void *src, unsigned n)
_vc_write   LEAX 2,S
            JSR  SETP0
            LDW  8,S
            BEQ  VW_RET
            PSHS Y
            LDX  8,S
            LDY  #VC_DATA0
            TFM  X+,Y
            PULS Y
VW_RET      RTS
; void vc_read(void *dst, long addr, unsigned n)
_vc_read    LEAX 4,S
            JSR  SETP0
            LDW  8,S
            BEQ  VW_RET
            PSHS Y
            LDY  4,S
            LDX  #VC_DATA0
            TFM  X,Y+
            PULS Y
            RTS
;------------------------------------------------------------------------------
; Commands: X -> bytes, B = how many, to the command port.
SENDB       LDA  ,X+
            STA  VC_CMD
            DECB
            BNE  SENDB
            RTS
; A = an opcode, then B words from X (the arguments).
SENDW       STA  VC_CMD
            LSLB
            BRA  SENDB
; void vc_fill(long addr, int value, long n): the card's FILL
_vc_fill    LDA  #C_FILL
            STA  VC_CMD
            LEAX 3,S                   ; (the long's three low bytes)
            LDB  #3
            JSR  SENDB
            LEAX 9,S
            LDB  #3
            JSR  SENDB
            LDB  7,S
            STB  VC_CMD
            RTS
; void vc_copy(long dst, long src, long n): the card's COPY
_vc_copy    LDA  #C_COPY
            STA  VC_CMD
            LEAX 7,S
            LDB  #3
            JSR  SENDB
            LEAX 3,S
            LDB  #3
            JSR  SENDB
            LEAX 11,S
            LDB  #3
            BRA  SENDB
;------------------------------------------------------------------------------
; Display settings.
; void vc_layer(int layer, int mode, int map, long mapbase, long tilebase)
_vc_layer   LDB  3,S
            LSLB
            LSLB
            LSLB
            LSLB
            ADDB #LAYER0+L_MODE
            JSR  SETCFG
            LDB  5,S
            STB  VC_DATA0
            LDB  7,S
            STB  VC_DATA0
            LEAX 9,S
            LDB  #3
            JSR  TODATA
            LEAX 13,S
            LDB  #3
TODATA      LDA  ,X+                   ; (B bytes from X to the port)
            STA  VC_DATA0
            DECB
            BNE  TODATA
            RTS
; void vc_scroll(int layer, int x, int y)
_vc_scroll  LDB  3,S
            LSLB
            LSLB
            LSLB
            LSLB
            ADDB #LAYER0+L_HSCROLL
            JSR  SETCFG
            LEAX 4,S
            LDB  #4
            BRA  TODATA
; void vc_stride(int layer, unsigned stride) (a bitmap's)
_vc_stride  LDB  3,S
            LSLB
            LSLB
            LSLB
            LSLB
            ADDB #LAYER0+L_STRIDE
            JSR  SETCFG
            LEAX 4,S
            LDB  #2
            BRA  TODATA
; void vc_show(int what): layers 0-2 (bits 0-2) and the sprites (bit 3) on
_vc_show    LDB  #DC_CTRL
VS_BYTE     JSR  SETCFG
            LDB  3,S
            STB  VC_DATA0
            RTS
; void vc_backdrop(int color)
_vc_backdrop LDB #DC_BACK
            BRA  VS_BYTE
; void vc_color(int index, unsigned rgb565)
_vc_color   LDA  #VC_PAL/$10000
            STA  VC_ADDR0
            LDD  2,S
            LSLD
            ADDD #VC_PAL&$FFFF
            STD  VC_ADDR0M
            LDD  #1
            STD  VC_INC0
            LDD  4,S
            STA  VC_DATA0
            STB  VC_DATA0
            RTS
;------------------------------------------------------------------------------
; void vc_vsync(void): waits for vertical blank (if one began since the last
; wait, at once), calling vc_idle (if set) while it waits.
_vc_vsync   PSHS Y,U
VY_LOOP     LDA  VC_ISR
            BITA #VC_I_VSYNC
            BNE  VY_DONE
            LDX  _vc_idle
            BEQ  VY_LOOP
            JSR  ,X
            BRA  VY_LOOP
VY_DONE     LDA  #VC_I_VSYNC
            STA  VC_ISR
            PULS Y,U,PC
; int vc_frame(void): frames shown, modulo 256
_vc_frame   LDB  VC_FRAME
            CLRA
            RTS
; void vc_wait(void): until the card's commands are done
_vc_wait    LDA  VC_STATUS
            BITA #VC_S_BUSY
            BNE  _vc_wait
            RTS
; void vc_text(int col, int row, const char *s, int fg, int bg): into the
; text screen the card starts with (VC_TEXTMAP: 128 cells a row)
_vc_text    LDA  #VC_TEXTMAP/$10000
            STA  VC_ADDR0
            LDD  4,S                   ; ((row * 128 + col) * 4)
            LSLD
            LSLD
            LSLD
            LSLD
            LSLD
            LSLD
            LSLD
            ADDD 2,S
            LSLD
            LSLD
            ADDD #VC_TEXTMAP&$FFFF
            STD  VC_ADDR0M
            LDD  #1
            STD  VC_INC0
            LDX  6,S
VT_LOOP     LDA  ,X+
            BEQ  VT_RET
            STA  VC_DATA0
            LDA  9,S
            STA  VC_DATA0
            LDA  11,S
            STA  VC_DATA0
            CLRA
            STA  VC_DATA0
            BRA  VT_LOOP
VT_RET      RTS
;------------------------------------------------------------------------------
; Drawing (the card's commands, into the target).
; void gfx_target(long addr, int stride, int w, int h, int bits)
_gfx_target LDA  #C_TARGET
            STA  VC_CMD
            LEAX 3,S
            LDB  #9
            JSR  SENDB
            LDB  13,S
            STB  VC_CMD
            RTS
; void gfx_color(int c)
_gfx_color  LDA  #C_COLOR
            STA  VC_CMD
            LDB  3,S
            STB  VC_CMD
            RTS
_gfx_plot   LDA  #C_PLOT               ; (x, y)
            LDB  #2
            BRA  G_ARGS
_gfx_line   LDA  #C_LINE               ; (x0, y0, x1, y1)
            LDB  #4
            BRA  G_ARGS
_gfx_rect   LDA  #C_RECT               ; (x, y, w, h)
            LDB  #4
            BRA  G_ARGS
_gfx_fillrect LDA #C_FILLRECT
            LDB  #4
            BRA  G_ARGS
_gfx_circle LDA  #C_CIRCLE             ; (x, y, r)
            LDB  #3
            BRA  G_ARGS
_gfx_disc   LDA  #C_DISC
            LDB  #3
            BRA  G_ARGS
_gfx_triangle LDA #C_TRIANGLE          ; (x0, y0, x1, y1, x2, y2)
            LDB  #6
G_ARGS      LEAX 2,S
            JMP  SENDW
_gfx_clear  LDA  #C_CLEAR
            STA  VC_CMD
            RTS
; void gfx_font(long addr, int height)
_gfx_font   LDA  #C_FONT
            STA  VC_CMD
            LEAX 3,S
            LDB  #3
            JSR  SENDB
            LDB  7,S
            STB  VC_CMD
            RTS
; void gfx_char(int x, int y, int c)
_gfx_char   LDA  #C_CHAR
            LEAX 2,S
            LDB  #2
            JSR  SENDW
            LDB  7,S
            STB  VC_CMD
            RTS
; void gfx_text(int x, int y, const char *s): 8 pixels a character
_gfx_text   LDX  6,S
GT_LOOP     LDB  ,X+
            BEQ  GT_RET
            LDA  #C_CHAR
            STA  VC_CMD
            LDA  2,S
            STA  VC_CMD
            LDA  3,S
            STA  VC_CMD
            LDA  4,S
            STA  VC_CMD
            LDA  5,S
            STA  VC_CMD
            STB  VC_CMD
            LDD  2,S
            ADDD #8
            STD  2,S
            BRA  GT_LOOP
GT_RET      RTS
; void gfx_blit(long src, int stride, int w, int h, int x, int y, int flags)
_gfx_blit   LDA  #C_BLIT
            STA  VC_CMD
            LEAX 3,S
            LDB  #13
            JSR  SENDB
            LDB  17,S
            STB  VC_CMD
            RTS
;------------------------------------------------------------------------------
; Sprites, in the table the card starts with (VC_SPRITES).
; B = a sprite (A: 0), A... -> port 0 at its entry + X's low byte.
SPRP        LSLD
            LSLD
            LSLD
            ADDD #VC_SPRITES&$FFFF
            PSHS X
            ADDD ,S++
            STD  VC_ADDR0M
            LDA  #VC_SPRITES/$10000
            STA  VC_ADDR0
            LDD  #1
            STD  VC_INC0
            RTS
; void spr_set(int n, long image, int x, int y, int size, int color): the
; image's address (in video memory, a multiple of 32), where, its size (SS_...:
; width, height, flips, priority) and its color byte (palette offset, SC_8BPP)
_spr_set    LDD  2,S
            LDX  #0
            JSR  SPRP
            LDQ  4,S                   ; the image / 32
            LDX  #5
SS_SHIFT    LSRD
            RORW
            LEAX -1,X
            BNE  SS_SHIFT
            STE  VC_DATA0
            STF  VC_DATA0
            LEAX 8,S                   ; x, y
            LDB  #4
            JSR  TODATA
            LDB  13,S
            STB  VC_DATA0
            LDB  15,S
            STB  VC_DATA0
            RTS
; void spr_move(int n, int x, int y)
_spr_move   LDD  2,S
            LDX  #S_X
            JSR  SPRP
            LEAX 4,S
            LDB  #4
            JMP  TODATA
; void spr_count(int n): sprite table entries in use (0-128)
_spr_count  LDB  #SPR_COUNT
            JMP  VS_BYTE
; void spr_hires(int on): sprites placed in 640x480 (else 320x240)
_spr_hires  LDB  #SPR_CTRL
            JMP  VS_BYTE
            ENDSECT
;------------------------------------------------------------------------------
            SECTION data
_vc_idle    FDB  0                     ; called while vc_vsync waits (0: none)
__vc_inctrl FCB  0                     ; INCTRL as last written (pugin.asm's)
            ENDSECT
;------------------------------------------------------------------------------
; End of pugvid.asm
;------------------------------------------------------------------------------
