; -----------------------------------------------------------------------------
; PROJECT: Pugputer 6309 video card
;    FILE: vidcard.d
;
; The video card's registers, settings and drawing commands, for programs:
;   INCLUDE "vidcard.d"
; What they do is in VIDCARD.TXT, in /ASM/VIDEO on the demo disk (vidcard/README.md
; in the project).
;
; Two rules for the data ports and the command port: write them with ST
; (STA, STB, STD to two of them...), never with CLR, INC, COM and the like --
; those read the register first, and a read of a data port moves it on.
; -----------------------------------------------------------------------------

VC_BASE     equ  $FF80      ; ff80 - ff9f: the video card

; The data ports: a 24-bit address (high byte first), a signed 16-bit step
; added after each read or write of DATA, and the data.
VC_ADDR0    equ  VC_BASE+$00 ; 3 bytes: H, M, L
VC_ADDR0M   equ  VC_BASE+$01 ; (STD here sets M and L)
VC_INC0     equ  VC_BASE+$03 ; 2 bytes (STD)
VC_DATA0    equ  VC_BASE+$05
VC_ADDR1    equ  VC_BASE+$06
VC_ADDR1M   equ  VC_BASE+$07
VC_INC1     equ  VC_BASE+$09
VC_DATA1    equ  VC_BASE+$0B
VC_CTRL     equ  VC_BASE+$0C ; write $80: reset the card
VC_STATUS   equ  VC_BASE+$0D ; bit 7 vertical blank, 6 commands busy, 5 queue full
VC_IEN      equ  VC_BASE+$0E ; interrupt enables (VC_I_...)
VC_ISR      equ  VC_BASE+$0F ; interrupt flags (write 1s to clear)
VC_LINE     equ  VC_BASE+$10 ; 2 bytes: read the line being drawn, write the line interrupt's
VC_CMD      equ  VC_BASE+$12 ; drawing commands
VC_FRAME    equ  VC_BASE+$13 ; frames shown, modulo 256
VC_INCTRL   equ  VC_BASE+$14 ; input: bit 0 sprite 0 follows the mouse, bit 1 keys
                             ; go to the card (VC_IN_...); write $80: empty the key queue
VC_MOUSEX   equ  VC_BASE+$15 ; 2 bytes, 0-639: LDD it first -- reading it takes a
                             ; snapshot of X and Y together
VC_MOUSEY   equ  VC_BASE+$17 ; 2 bytes, 0-479 (then LDD this)
VC_MOUSEB   equ  VC_BASE+$19 ; buttons: bit 0 left, 1 right, 2 middle; 7 a mouse seen
VC_WHEEL    equ  VC_BASE+$1A ; wheel clicks since the last read (signed; + away)
VC_KEY      equ  VC_BASE+$1B ; read: the next key event's USB usage code (0: none)
VC_KEYCHAR  equ  VC_BASE+$1C ; its character (0: none); bit 7 set: a release
VC_KEYMODS  equ  VC_BASE+$1D ; modifier keys held now (VC_MOD_...)
VC_ID       equ  VC_BASE+$1E ; reads 'V'
VC_VERSION  equ  VC_BASE+$1F ; reads $11 (1.1; 1.0 had no input registers)

VC_S_VBLANK equ  $80
VC_S_BUSY   equ  $40
VC_S_FULL   equ  $20
VC_S_KEY    equ  $10        ; a key event is waiting in VC_KEY
VC_I_VSYNC  equ  $01        ; vertical blank begins (line 480)
VC_I_LINE   equ  $02        ; the line in VC_LINE begins
VC_I_CMD    equ  $04        ; the command queue has emptied
VC_I_INPUT  equ  $08        ; a key event queued, or the mouse moved or clicked

; VC_INCTRL
VC_IN_PTR   equ  $01        ; sprite 0's X, Y set to the mouse's at each vertical blank
VC_IN_KEYS  equ  $02        ; keys typed go to the card's queue (the emulator: not the UART)
VC_IN_FLUSH equ  $80        ; (written) empty the key queue
; VC_MOUSEB
VC_MB_LEFT  equ  $01
VC_MB_RIGHT equ  $02
VC_MB_MID   equ  $04
; VC_KEYMODS: the USB keyboard's modifier byte
VC_MOD_LCTL equ  $01
VC_MOD_LSHF equ  $02
VC_MOD_LALT equ  $04
VC_MOD_LGUI equ  $08
VC_MOD_RCTL equ  $10
VC_MOD_RSHF equ  $20
VC_MOD_RALT equ  $40
VC_MOD_RGUI equ  $80
VC_MOD_CTL  equ  $11        ; either Ctrl, either Shift, either Alt
VC_MOD_SHF  equ  $22
VC_MOD_ALT  equ  $44
; Some USB usage codes (VC_KEY) of keys that type no character, or the same one as
; another: the letters are $04 (A) to $1D (Z), the digits $1E (1) to $27 (0).
K_ENTER     equ  $28
K_ESC       equ  $29
K_BKSP      equ  $2A
K_TAB       equ  $2B
K_SPACE     equ  $2C
K_CAPS      equ  $39
K_F1        equ  $3A        ; ... to F12, $45
K_INSERT    equ  $49
K_HOME      equ  $4A
K_PGUP      equ  $4B
K_DELETE    equ  $4C
K_END       equ  $4D
K_PGDN      equ  $4E
K_RIGHT     equ  $4F
K_LEFT      equ  $50
K_DOWN      equ  $51
K_UP        equ  $52
K_KPENTER   equ  $58
K_LCTRL     equ  $E0        ; the modifiers, $E0-$E7, in VC_MOD_... order
K_LSHIFT    equ  $E1
K_LALT      equ  $E2
K_RCTRL     equ  $E4
K_RSHIFT    equ  $E5
K_RALT      equ  $E6

; The card's address space.
VC_VRAM     equ  $000000    ; $000000-$03FFFF video memory (256KB)
VC_CFG      equ  $040000    ; the display settings (below)
VC_PAL      equ  $040200    ; 256 colors, RGB565, 2 bytes each (high first)
VC_PSRAM    equ  $800000    ; $800000-$FFFFFF the 8MB PSRAM

; The display settings, at VC_CFG + these.
DC_CTRL     equ  $00        ; bits 0-2 layers 0-2 on, bit 3 sprites on
DC_BACK     equ  $01        ; backdrop color
SPR_CTRL    equ  $02        ; bit 0: sprite coordinates in 640x480 (else 320x240)
SPR_COUNT   equ  $03        ; sprite table entries in use (0-128)
SPR_BASE    equ  $04        ; 3 bytes: the sprite table's address
LAYER0      equ  $10        ; then 16 bytes a layer:
LAYER1      equ  $20
LAYER2      equ  $30
L_MODE      equ  $00        ;   type, hires, depth, big (below)
L_MAP       equ  $01        ;   map size: width bits 0-1, height bits 2-3 (L_32...)
L_MAPBASE   equ  $02        ;   3 bytes: map, or pixels for a bitmap
L_TILEBASE  equ  $05        ;   3 bytes: tiles, or font
L_HSCROLL   equ  $08        ;   2 bytes
L_VSCROLL   equ  $0A        ;   2 bytes
L_STRIDE    equ  $0C        ;   2 bytes: a bitmap's bytes per row
L_PALOFS    equ  $0E        ;   a bitmap's palette offset (x16), below 8 bits a pixel

; L_MODE: add up one of each
LM_TEXT     equ  $00
LM_TILE     equ  $01
LM_BITMAP   equ  $02
LM_HIRES    equ  $04        ; 640x480 pixels (else 320x240, each pixel doubled)
LM_1BPP     equ  $00
LM_2BPP     equ  $08
LM_4BPP     equ  $10
LM_8BPP     equ  $18
LM_BIG      equ  $20        ; 16x16 tiles; a text layer's 8x16 font (else 8x8)
; L_MAP
LW_32       equ  $00
LW_64       equ  $01
LW_128      equ  $02
LW_256      equ  $03
LH_32       equ  $00
LH_64       equ  $04
LH_128      equ  $08
LH_256      equ  $0C

; A sprite: 8 bytes in the sprite table.
S_IMAGE     equ  0          ; 2 bytes: the image's address / 32
S_X         equ  2          ; 2 bytes, signed
S_Y         equ  4          ; 2 bytes, signed
S_SIZE      equ  6          ; width bits 0-1, height bits 2-3 (8, 16, 32, 64),
                            ; bit 4 flip across, 5 flip down, bits 6-7 priority
S_COLOR     equ  7          ; bits 0-3 palette offset (x16), bit 7: 8 bits a pixel
SS_W8       equ  $00
SS_W16      equ  $01
SS_W32      equ  $02
SS_W64      equ  $03
SS_H8       equ  $00
SS_H16      equ  $04
SS_H32      equ  $08
SS_H64      equ  $0C
SS_HFLIP    equ  $10
SS_VFLIP    equ  $20
SS_OFF      equ  $00        ; priority: not shown ...
SS_BACK     equ  $40        ; ... in front of layer 0
SS_MID      equ  $80        ; ... in front of layer 1
SS_FRONT    equ  $C0        ; ... in front of everything
SC_8BPP     equ  $80

; Where things are at reset: an 80x30 text screen on layer 0.
VC_TEXTMAP  equ  $038000    ; 128x32 cells of 4 bytes: char, fg, bg, 0
VC_FONT     equ  $03F000    ; 8x16, 256 characters (code page 437)
VC_SPRITES  equ  $037C00    ; the sprite table

; Drawing commands: the opcode, then its parameters (2-byte ones high first,
; coordinates signed -- FDB them).
C_NOP       equ  $00
C_TARGET    equ  $01        ; addr:3 stride:2 width:2 height:2 bpp:1
C_COLOR     equ  $02        ; color:1
C_PLOT      equ  $03        ; x y
C_LINE      equ  $04        ; x0 y0 x1 y1
C_RECT      equ  $05        ; x y w h
C_FILLRECT  equ  $06        ; x y w h
C_CIRCLE    equ  $07        ; x y r
C_DISC      equ  $08        ; x y r
C_CLEAR     equ  $09
C_COPY      equ  $0A        ; src:3 dst:3 len:3
C_FILL      equ  $0B        ; dst:3 len:3 value:1
C_BLIT      equ  $0C        ; src:3 stride:2 w h x y flags:1 (bit 0: 0 is clear)
C_TRIANGLE  equ  $0D        ; x0 y0 x1 y1 x2 y2
C_FONT      equ  $0E        ; addr:3 height:1
C_CHAR      equ  $0F        ; x y char:1
