;------------------------------------------------------------------------------
; PROJECT: VIDEO CARD DEMOS
;    FILE: vidgfx.asm
;
; (Made by vidcard/tools/make_vidgfx.py, which works out the drawing commands'
; numbers: change that, not this.)
;
; The video card's bitmaps, drawing commands, palette, interrupts and PSRAM,
; in two pages (a key goes on to the next; after the last, back to the shell):
;
;   1  640x480 in 16 colors (4 bits a pixel, palette offset 1): a panel for
;      each drawing command, labelled with CHAR -- PLOT (stars placed by the
;      program as it runs), LINE, RECT, FILLRECT, CIRCLE, DISC, TRIANGLE, and
;      a stamp drawn in the PSRAM then BLITted with see-through 0s, stripes
;      FILLed straight into the bitmap's bytes and rows of it COPYed. The
;      rings and some stars turn by palette: 8 colors rotated every 3 frames.
;      It waits for the card to say the commands are done (STATUS and ISR)
;   2  three bitmaps: a tunnel of 8 bits a pixel at 320x240, turned by
;      rotating 64 colors of the palette each frame; bars of color behind it
;      set every 8 lines by an interrupt handler (the card's line interrupt,
;      through the BIOS's RAM jump table); a spinner of 2 bits a pixel whose
;      8 frames were drawn into the PSRAM, COPYed in, shown by turns from two
;      buffers and moved by scrolling; and the words, 1 bit a pixel at 640x480
;
;   ASM -f com vidgfx.asm          makes VIDGFX.COM
;------------------------------------------------------------------------------
            INCLUDE "VIDCARD.D"
RAM_IRQV    equ  $0026      ; where the BIOS's IRQ entry jumps (see /ASM/DEFINES.D)

SPINA       equ  $014000    ; page 2: the spinner's two buffers
SPINB       equ  $014800
FRAMES      equ  $800000    ; its 8 frames, in the PSRAM, 1280 bytes each
;------------------------------------------------------------------------------
            ORG  $4000
START       LDA  #$80
            STA  VC_CTRL
;------------------------------------------------------------------------------
; Page 1: the drawing commands.
;------------------------------------------------------------------------------
            LDX  #PAL1
            JSR  COLORS
            LDA  #VC_CFG/$10000
            LDX  #DC_CTRL
            JSR  PORT0
            LDX  #SETTINGS1
            LDW  #SET1END-SETTINGS1
            JSR  SENDDAT
            LDX  #RAMP8         ; the cycling colors, entries 24-31
            LDA  #24
            LDB  #8
            JSR  COLORRUN
            LDA  #VC_I_CMD      ; (so the flag says these commands are done)
            STA  VC_ISR
            LDX  #PAGE1CMDS
            LDW  #PAGE1END-PAGE1CMDS
            JSR  SENDCMD
; PLOT: 256 stars at random in the first panel, in colors 2-9 (8 and 9 cycle).
            LDE  #0
STARS       JSR  RANDOM
            PSHS D
            ANDB #7
            ADDB #2
            LDA  #C_COLOR
            JSR  CMDD
            LDA  #C_PLOT
            STA  VC_CMD
            PULS D
            ANDB #127           ; x: 12 + 0..127
            CLRA
            ADDD #4+8
            JSR  CMDD
            JSR  RANDOM
            ANDB #127           ; y: 48 + 0..127 + 0..63
            ANDA #63
            PSHS A
            CLRA
            ADDB ,S+
            ADCA #0
            ADDD #22+26
            JSR  CMDD
            DECE
            BNE  STARS
; The card has done them all when STATUS stops saying busy; ISR's flag says so too.
DONE        LDA  VC_STATUS
            BITA #VC_S_BUSY
            BNE  DONE
            LDA  VC_ISR
            BITA #VC_I_CMD
            BEQ  DONE1
            LDX  #TEXTS1
            JSR  TEXTS
DONE1       LDX  #TEXTS1A
            JSR  TEXTS
; Each frame: every third, the cycling colors move on one.
PAGE1       JSR  VBLANK
            INC  CYCLE3
            LDA  CYCLE3
            CMPA #3
            BLO  PAGE1A
            CLR  CYCLE3
            INC  RAMPPOS
            LDB  RAMPPOS
            ANDB #7
            LSLB
            LDX  #RAMP8
            ABX
            LDA  #24
            LDB  #8
            JSR  COLORRUN
PAGE1A      JSR  GETKEY
            BCS  PAGE1
            BRA  PAGE2GO
CYCLE3      FCB  0
RAMPPOS     FCB  0
;------------------------------------------------------------------------------
; Page 2: three bitmaps, raster bars, the PSRAM.
;------------------------------------------------------------------------------
PAGE2GO     LDA  #$80
            STA  VC_CTRL
            LDX  #PAL2
            JSR  COLORS
            LDX  #BARS          ; the bars' colors, entries 128-159
            LDA  #128
            LDB  #32
            JSR  COLORRUN
            LDX  #RAMP64        ; the tunnel's, 32-95
            LDA  #32
            LDB  #64
            JSR  COLORRUN
            LDA  #VC_CFG/$10000
            LDX  #DC_CTRL
            JSR  PORT0
            LDX  #SETTINGS2
            LDW  #SET2END-SETTINGS2
            JSR  SENDDAT
            LDX  #PAGE2CMDS
            LDW  #PAGE2END-PAGE2CMDS
            JSR  SENDCMD
; The interrupt handler writes the backdrop through port 1, set here once for
; good: at DC_BACK, stepping 0, so every write goes there.
            LDA  #VC_CFG/$10000
            STA  VC_ADDR1
            LDX  #DC_BACK
            STX  VC_ADDR1M
            LDX  #0
            STX  VC_INC1
            PSHS CC             ; take the IRQ: ours first, then the one before it
            ORCC #$50
            LDX  >RAM_IRQV      ; (">": $0026 is below $100, but DP isn't 0)
            STX  OLDIRQ
            LDX  #IRQ
            STX  >RAM_IRQV
            LDD  #0             ; the first line interrupt: line 0
            STD  VC_LINE
            LDA  #VC_I_LINE+VC_I_VSYNC
            STA  VC_ISR
            LDA  #VC_I_LINE
            STA  VC_IEN
            PULS CC
PAGE2       JSR  VBLANK
            INC  BARFRAME       ; the bars move down a line... every frame
            LDD  VL_FRAMES      ; the tunnel: 64 colors, rotated one each frame
            ANDB #63
            LSLB
            LDX  #RAMP64
            ABX
            LDA  #32
            LDB  #64
            JSR  COLORRUN
            LDA  VL_FRAMES+1    ; every 4th frame the spinner's next frame
            ANDA #3
            BNE  PAGE2A
            JSR  SPIN
PAGE2A      JSR  MOVESPIN
            JSR  GETKEY
            BCS  PAGE2
            PSHS CC             ; put the IRQ back, and go
            ORCC #$50
            CLR  VC_IEN
            LDX  OLDIRQ
            STX  >RAM_IRQV
            PULS CC
            JMP  QUIT
;------------------------------------------------------------------------------
; IRQ: the line interrupt. Sets the backdrop for the next 8 lines (one of the
; bars' 32 colors, by line and frame), and asks for the interrupt again 8 lines
; on (line 0 again after the last). Anything else: the handler before this.
IRQ         LDA  VC_ISR
            BITA #VC_I_LINE
            BEQ  IRQ9
            LDA  #VC_I_LINE
            STA  VC_ISR         ; (a 1 clears the flag)
            LDD  VC_LINE        ; the line now
            LSRD
            LSRD
            LSRD
            ADDB BARFRAME
            ANDB #31
            ADDB #128
            STB  VC_DATA1       ; (port 1: the backdrop)
            LDD  VC_LINE
            ADDD #8
            CMPD #480
            BLO  IRQ1
            CLRD
IRQ1        STD  VC_LINE
IRQ9        JMP  [OLDIRQ]
OLDIRQ      FDB  0
BARFRAME    FCB  0
;------------------------------------------------------------------------------
; SPIN: the spinner's next frame, COPYed from the PSRAM into the buffer not
; being shown; when the card has done it, show that buffer.
SPIN        LDA  SPINFRAME
            INCA
            ANDA #7
            STA  SPINFRAME
            LDB  #5             ; its address: FRAMES + frame * 1280
            MUL
            TFR  B,A
            CLRB
            ADDD #FRAMES&$FFFF
            STD  SPINCOPY+2
            LDD  SPINBACK       ; into the spare buffer
            STD  SPINCOPY+5
            LDX  #SPINCOPY
            LDW  #10
            JSR  SENDCMD
SPIN1       LDA  VC_STATUS      ; (wait for the card)
            BITA #VC_S_BUSY
            BNE  SPIN1
            LDA  #VC_CFG/$10000 ; show it
            LDX  #LAYER1+L_MAPBASE
            JSR  PORT0
            LDA  #SPINA/$10000
            STA  VC_DATA0
            LDD  SPINBACK
            STA  VC_DATA0
            STB  VC_DATA0
            EORA #((SPINA^SPINB)/$100)&$FF ; and the other is the spare now
            STD  SPINBACK
            RTS
SPINFRAME   FCB  0
SPINBACK    FDB  SPINB&$FFFF
SPINCOPY    FCB  C_COPY,FRAMES/$10000,0,0,SPINA/$10000,0,0,0,$05,$00
; MOVESPIN: it bounces around, placed by scrolling its layer (negative: to the
; right and down).
MOVESPIN    LDD  SPINX
            ADDD SPINDX
            BGE  MOVE1
            LDD  SPINDX
            NEGD
            STD  SPINDX
            CLRD
MOVE1       CMPD #320-80
            BLE  MOVE2
            LDD  SPINDX
            NEGD
            STD  SPINDX
            LDD  #320-80
MOVE2       STD  SPINX
            LDD  SPINY
            ADDD SPINDY
            BGE  MOVE3
            LDD  SPINDY
            NEGD
            STD  SPINDY
            CLRD
MOVE3       CMPD #240-64
            BLE  MOVE4
            LDD  SPINDY
            NEGD
            STD  SPINDY
            LDD  #240-64
MOVE4       STD  SPINY
            LDA  #VC_CFG/$10000
            LDX  #LAYER1+L_HSCROLL
            JSR  PORT0
            LDD  SPINX
            NEGD
            STA  VC_DATA0
            STB  VC_DATA0
            LDD  SPINY
            NEGD
            STA  VC_DATA0
            STB  VC_DATA0
            RTS
SPINX       FDB  20
SPINY       FDB  30
SPINDX      FDB  1
SPINDY      FDB  1
;------------------------------------------------------------------------------
; COLORS: palette entries from a list at X: entry (0 ends it), RGB565.
COLORS      LDA  ,X+
            BEQ  COLORS9
            PSHS X
            LDX  ,X
            JSR  SETCOLOR
            PULS X
            LEAX 2,X
            BRA  COLORS
COLORS9     RTS
; COLORRUN: B palette entries from A on, from the RGB565 words at X.
COLORRUN    PSHS B
            LDB  #2
            MUL
            ADDD #VC_PAL&$FFFF
            PSHS X
            TFR  D,X
            LDA  #VC_PAL/$10000
            JSR  PORT0
            PULS X
            PULS B
            CLRA
            LSLB
            ROLA
            TFR  D,W
            JMP  SENDDAT
; TEXTS: the strings listed at X, each: column, row, color, background, the
; words (0 at their end); a column of $FF ends the list.
TEXTS       LDA  ,X+
            CMPA #$FF
            BEQ  TEXTS9
            LDB  ,X+
            PSHS X
            JSR  TEXTAT
            PULS X
            LDB  ,X+
            LDE  ,X+
            JSR  PRINT
            BRA  TEXTS
TEXTS9      RTS
;------------------------------------------------------------------------------
            INCLUDE "VIDLIB.ASM"
;------------------------------------------------------------------------------
TEXTS1      FCB  50,29,120,236
            FCN  "(COMMANDS DONE: STATUS, ISR)"
            FCB  $FF
TEXTS1A     FCB  0,0,231,236
            FCN  "  640x480 IN 16 COLORS: THE CARD'S DRAWING COMMANDS, ONE PANEL EACH            "
            FCB  0,29,231,236
            FCN  "  A KEY: THE NEXT PAGE"
            FCB  $FF
; Page 1's settings from DC_CTRL: layers 0 and 2, the backdrop color 16; then
; layer 0, a 640x480 bitmap of 4 bits a pixel, palette offset 1 (16-31); then
; layer 2, the text screen.
SETTINGS1   FCB  $05,16,0,0
            FCB  VC_SPRITES/$10000,(VC_SPRITES/$100)&$FF,VC_SPRITES&$FF
            FCB  0,0,0,0,0,0,0,0,0
            FCB  LM_BITMAP+LM_HIRES+LM_4BPP,0,0,0,0,0,0,0
            FDB  0,0,320
            FCB  1,0
            FCB  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
            FCB  LM_TEXT+LM_HIRES+LM_BIG,LW_128+LH_32
            FCB  VC_TEXTMAP/$10000,(VC_TEXTMAP/$100)&$FF,VC_TEXTMAP&$FF
            FCB  VC_FONT/$10000,(VC_FONT/$100)&$FF,VC_FONT&$FF
            FDB  0,0,0
            FCB  0,0
SET1END
; Page 2's: all three layers, the backdrop 128 (the bars change it); layer 0
; the tunnel, 320x240 of 8 bits; layer 1 the spinner, 80x64 of 2 bits, palette
; offset 7 (113-115); layer 2 the words, 640x480 of 1 bit, palette offset 15.
SETTINGS2   FCB  $07,128,0,0
            FCB  VC_SPRITES/$10000,(VC_SPRITES/$100)&$FF,VC_SPRITES&$FF
            FCB  0,0,0,0,0,0,0,0,0
            FCB  LM_BITMAP+LM_8BPP,0,0,0,0,0,0,0
            FDB  0,0,320
            FCB  0,0
            FCB  LM_BITMAP+LM_2BPP,0
            FCB  SPINA/$10000,(SPINA/$100)&$FF,SPINA&$FF,0,0,0
            FDB  -20,-30,20
            FCB  7,0
            FCB  LM_BITMAP+LM_HIRES+LM_1BPP,0,$01,$80,$00,0,0,0
            FDB  0,0,80
            FCB  15,0
SET2END
PAL1        EQU  *
            FCB  16
            FDB  $0007
            FCB  17
            FDB  $FFFF
            FCB  18
            FDB  $E145
            FCB  19
            FDB  $FCA3
            FCB  20
            FDB  $FF25
            FCB  21
            FDB  $3E47
            FCB  22
            FDB  $2E5C
            FCB  23
            FDB  $8ADF
            FCB  0
PAL2        EQU  *
            FCB  113
            FDB  $394D
            FCB  114
            FDB  $FEEB
            FCB  115
            FDB  $FFFF
            FCB  241
            FDB  $FFFF
            FCB  0
RAMP8       EQU  *
            FDB  $FA08,$DD00,$8762,$27CB,$05F7,$22FF,$789D,$D834
            FDB  $FA08,$DD00,$8762,$27CB,$05F7,$22FF,$789D,$D834
RAMP64      EQU  *
            FDB  $FA08,$FA46,$FAA5,$FB04,$F363,$F3C2,$EC41,$E4A1
            FDB  $DD00,$D560,$C5C0,$BE00,$B660,$A6A0,$9EE0,$8F21
            FDB  $8762,$7783,$67C4,$5FC5,$4FE6,$47E7,$3FE8,$2FEA
            FDB  $27CB,$1FAD,$178E,$0F50,$0F32,$06F3,$0695,$0656
            FDB  $05F7,$05B9,$055A,$04FB,$0C9C,$0C3D,$13BE,$1B5E
            FDB  $22FF,$2A9F,$3A3F,$41FF,$499F,$595F,$611F,$70DE
            FDB  $789D,$887C,$983B,$A03A,$B019,$B818,$C017,$D015
            FDB  $D834,$E052,$E871,$F0AF,$F0CD,$F90C,$F96A,$F9A9
            FDB  $FA08,$FA46,$FAA5,$FB04,$F363,$F3C2,$EC41,$E4A1
            FDB  $DD00,$D560,$C5C0,$BE00,$B660,$A6A0,$9EE0,$8F21
            FDB  $8762,$7783,$67C4,$5FC5,$4FE6,$47E7,$3FE8,$2FEA
            FDB  $27CB,$1FAD,$178E,$0F50,$0F32,$06F3,$0695,$0656
            FDB  $05F7,$05B9,$055A,$04FB,$0C9C,$0C3D,$13BE,$1B5E
            FDB  $22FF,$2A9F,$3A3F,$41FF,$499F,$595F,$611F,$70DE
            FDB  $789D,$887C,$983B,$A03A,$B019,$B818,$C017,$D015
            FDB  $D834,$E052,$E871,$F0AF,$F0CD,$F90C,$F96A,$F9A9
BARS        EQU  *
            FDB  $28A7,$5148,$7A0A,$9AAB,$C34C,$DBAD,$EC0E,$FC4E
            FDB  $FC6F,$FC4E,$EC0E,$DBAD,$C34C,$9AAB,$7A0A,$5148
            FDB  $114A,$1A6E,$2BB2,$34B6,$3DB9,$467C,$4F1E,$4F7F
            FDB  $579F,$4F7F,$4F1E,$467C,$3DB9,$34B6,$2BB2,$1A6E
PAGE1CMDS   EQU  *
            FCB  C_TARGET,$00,$00,$00    ; the bitmap
            FDB  320,640,480
            FCB  4
            FCB  C_FONT,$03,$F0,$00,16          ; the card's font, for CHAR
            FCB  C_COLOR,0
            FCB  C_CLEAR
            FCB  C_COLOR,1
            FCB  C_RECT             ; panel 0: PLOT
            FDB  4,22,155,215
            FCB  C_CHAR
            FDB  10,26
            FCB  80
            FCB  C_CHAR
            FDB  18,26
            FCB  76
            FCB  C_CHAR
            FDB  26,26
            FCB  79
            FCB  C_CHAR
            FDB  34,26
            FCB  84
            FCB  C_COLOR,1
            FCB  C_RECT             ; panel 1: LINE
            FDB  163,22,155,215
            FCB  C_CHAR
            FDB  169,26
            FCB  76
            FCB  C_CHAR
            FDB  177,26
            FCB  73
            FCB  C_CHAR
            FDB  185,26
            FCB  78
            FCB  C_CHAR
            FDB  193,26
            FCB  69
            FCB  C_COLOR,1
            FCB  C_RECT             ; panel 2: RECT
            FDB  322,22,155,215
            FCB  C_CHAR
            FDB  328,26
            FCB  82
            FCB  C_CHAR
            FDB  336,26
            FCB  69
            FCB  C_CHAR
            FDB  344,26
            FCB  67
            FCB  C_CHAR
            FDB  352,26
            FCB  84
            FCB  C_COLOR,1
            FCB  C_RECT             ; panel 3: FILLRECT
            FDB  481,22,155,215
            FCB  C_CHAR
            FDB  487,26
            FCB  70
            FCB  C_CHAR
            FDB  495,26
            FCB  73
            FCB  C_CHAR
            FDB  503,26
            FCB  76
            FCB  C_CHAR
            FDB  511,26
            FCB  76
            FCB  C_CHAR
            FDB  519,26
            FCB  82
            FCB  C_CHAR
            FDB  527,26
            FCB  69
            FCB  C_CHAR
            FDB  535,26
            FCB  67
            FCB  C_CHAR
            FDB  543,26
            FCB  84
            FCB  C_COLOR,1
            FCB  C_RECT             ; panel 4: CIRCLE
            FDB  4,243,155,215
            FCB  C_CHAR
            FDB  10,247
            FCB  67
            FCB  C_CHAR
            FDB  18,247
            FCB  73
            FCB  C_CHAR
            FDB  26,247
            FCB  82
            FCB  C_CHAR
            FDB  34,247
            FCB  67
            FCB  C_CHAR
            FDB  42,247
            FCB  76
            FCB  C_CHAR
            FDB  50,247
            FCB  69
            FCB  C_COLOR,1
            FCB  C_RECT             ; panel 5: DISC
            FDB  163,243,155,215
            FCB  C_CHAR
            FDB  169,247
            FCB  68
            FCB  C_CHAR
            FDB  177,247
            FCB  73
            FCB  C_CHAR
            FDB  185,247
            FCB  83
            FCB  C_CHAR
            FDB  193,247
            FCB  67
            FCB  C_COLOR,1
            FCB  C_RECT             ; panel 6: TRIANGLE
            FDB  322,243,155,215
            FCB  C_CHAR
            FDB  328,247
            FCB  84
            FCB  C_CHAR
            FDB  336,247
            FCB  82
            FCB  C_CHAR
            FDB  344,247
            FCB  73
            FCB  C_CHAR
            FDB  352,247
            FCB  65
            FCB  C_CHAR
            FDB  360,247
            FCB  78
            FCB  C_CHAR
            FDB  368,247
            FCB  71
            FCB  C_CHAR
            FDB  376,247
            FCB  76
            FCB  C_CHAR
            FDB  384,247
            FCB  69
            FCB  C_COLOR,1
            FCB  C_RECT             ; panel 7: BLIT COPY FILL
            FDB  481,243,155,215
            FCB  C_CHAR
            FDB  487,247
            FCB  66
            FCB  C_CHAR
            FDB  495,247
            FCB  76
            FCB  C_CHAR
            FDB  503,247
            FCB  73
            FCB  C_CHAR
            FDB  511,247
            FCB  84
            FCB  C_CHAR
            FDB  519,247
            FCB  32
            FCB  C_CHAR
            FDB  527,247
            FCB  67
            FCB  C_CHAR
            FDB  535,247
            FCB  79
            FCB  C_CHAR
            FDB  543,247
            FCB  80
            FCB  C_CHAR
            FDB  551,247
            FCB  89
            FCB  C_CHAR
            FDB  559,247
            FCB  32
            FCB  C_CHAR
            FDB  567,247
            FCB  70
            FCB  C_CHAR
            FDB  575,247
            FCB  73
            FCB  C_CHAR
            FDB  583,247
            FCB  76
            FCB  C_CHAR
            FDB  591,247
            FCB  76
            FCB  C_COLOR,2
            FCB  C_LINE
            FDB  167,232,171,46
            FCB  C_COLOR,3
            FCB  C_LINE
            FDB  167,232,178,46
            FCB  C_COLOR,4
            FCB  C_LINE
            FDB  167,232,185,46
            FCB  C_COLOR,5
            FCB  C_LINE
            FDB  167,232,192,46
            FCB  C_COLOR,6
            FCB  C_LINE
            FDB  167,232,199,46
            FCB  C_COLOR,7
            FCB  C_LINE
            FDB  167,232,206,46
            FCB  C_COLOR,2
            FCB  C_LINE
            FDB  167,232,213,46
            FCB  C_COLOR,3
            FCB  C_LINE
            FDB  167,232,220,46
            FCB  C_COLOR,4
            FCB  C_LINE
            FDB  167,232,227,46
            FCB  C_COLOR,5
            FCB  C_LINE
            FDB  167,232,234,46
            FCB  C_COLOR,6
            FCB  C_LINE
            FDB  167,232,241,46
            FCB  C_COLOR,7
            FCB  C_LINE
            FDB  167,232,248,46
            FCB  C_COLOR,2
            FCB  C_LINE
            FDB  167,232,255,46
            FCB  C_COLOR,3
            FCB  C_LINE
            FDB  167,232,262,46
            FCB  C_COLOR,4
            FCB  C_LINE
            FDB  167,232,269,46
            FCB  C_COLOR,5
            FCB  C_LINE
            FDB  167,232,276,46
            FCB  C_COLOR,6
            FCB  C_LINE
            FDB  167,232,283,46
            FCB  C_COLOR,7
            FCB  C_LINE
            FDB  167,232,290,46
            FCB  C_COLOR,2
            FCB  C_LINE
            FDB  167,232,297,46
            FCB  C_COLOR,3
            FCB  C_LINE
            FDB  167,232,304,46
            FCB  C_COLOR,4
            FCB  C_LINE
            FDB  167,232,311,46
            FCB  C_COLOR,5
            FCB  C_LINE
            FDB  167,232,313,46
            FCB  C_COLOR,6
            FCB  C_LINE
            FDB  167,232,313,53
            FCB  C_COLOR,7
            FCB  C_LINE
            FDB  167,232,313,60
            FCB  C_COLOR,2
            FCB  C_LINE
            FDB  167,232,313,67
            FCB  C_COLOR,3
            FCB  C_LINE
            FDB  167,232,313,74
            FCB  C_COLOR,4
            FCB  C_LINE
            FDB  167,232,313,81
            FCB  C_COLOR,5
            FCB  C_LINE
            FDB  167,232,313,88
            FCB  C_COLOR,6
            FCB  C_LINE
            FDB  167,232,313,95
            FCB  C_COLOR,7
            FCB  C_LINE
            FDB  167,232,313,102
            FCB  C_COLOR,2
            FCB  C_LINE
            FDB  167,232,313,109
            FCB  C_COLOR,3
            FCB  C_LINE
            FDB  167,232,313,116
            FCB  C_COLOR,4
            FCB  C_LINE
            FDB  167,232,313,123
            FCB  C_COLOR,5
            FCB  C_LINE
            FDB  167,232,313,130
            FCB  C_COLOR,6
            FCB  C_LINE
            FDB  167,232,313,137
            FCB  C_COLOR,7
            FCB  C_LINE
            FDB  167,232,313,144
            FCB  C_COLOR,2
            FCB  C_LINE
            FDB  167,232,313,151
            FCB  C_COLOR,3
            FCB  C_LINE
            FDB  167,232,313,158
            FCB  C_COLOR,4
            FCB  C_LINE
            FDB  167,232,313,165
            FCB  C_COLOR,5
            FCB  C_LINE
            FDB  167,232,313,172
            FCB  C_COLOR,6
            FCB  C_LINE
            FDB  167,232,313,179
            FCB  C_COLOR,7
            FCB  C_LINE
            FDB  167,232,313,186
            FCB  C_COLOR,2
            FCB  C_LINE
            FDB  167,232,313,193
            FCB  C_COLOR,3
            FCB  C_LINE
            FDB  167,232,313,200
            FCB  C_COLOR,4
            FCB  C_LINE
            FDB  167,232,313,207
            FCB  C_COLOR,5
            FCB  C_LINE
            FDB  167,232,313,214
            FCB  C_COLOR,6
            FCB  C_LINE
            FDB  167,232,313,221
            FCB  C_COLOR,2
            FCB  C_RECT
            FDB  330,48,139,181
            FCB  C_COLOR,3
            FCB  C_RECT
            FDB  335,54,129,169
            FCB  C_COLOR,4
            FCB  C_RECT
            FDB  340,60,119,157
            FCB  C_COLOR,5
            FCB  C_RECT
            FDB  345,66,109,145
            FCB  C_COLOR,6
            FCB  C_RECT
            FDB  350,72,99,133
            FCB  C_COLOR,7
            FCB  C_RECT
            FDB  355,78,89,121
            FCB  C_COLOR,2
            FCB  C_RECT
            FDB  360,84,79,109
            FCB  C_COLOR,3
            FCB  C_RECT
            FDB  365,90,69,97
            FCB  C_COLOR,4
            FCB  C_RECT
            FDB  370,96,59,85
            FCB  C_COLOR,5
            FCB  C_RECT
            FDB  375,102,49,73
            FCB  C_COLOR,6
            FCB  C_RECT
            FDB  380,108,39,61
            FCB  C_COLOR,7
            FCB  C_RECT
            FDB  385,114,29,49
            FCB  C_COLOR,2
            FCB  C_RECT
            FDB  390,120,19,37
            FCB  C_COLOR,3
            FCB  C_RECT
            FDB  395,126,9,25
            FCB  C_COLOR,2
            FCB  C_FILLRECT
            FDB  489,169,14,60
            FCB  C_COLOR,3
            FCB  C_FILLRECT
            FDB  507,109,14,120
            FCB  C_COLOR,4
            FCB  C_FILLRECT
            FDB  525,139,14,90
            FCB  C_COLOR,5
            FCB  C_FILLRECT
            FDB  543,59,14,170
            FCB  C_COLOR,6
            FCB  C_FILLRECT
            FDB  561,189,14,40
            FCB  C_COLOR,7
            FCB  C_FILLRECT
            FDB  579,89,14,140
            FCB  C_COLOR,2
            FCB  C_FILLRECT
            FDB  597,129,14,100
            FCB  C_COLOR,3
            FCB  C_FILLRECT
            FDB  615,79,14,150
            FCB  C_COLOR,8
            FCB  C_CIRCLE
            FDB  81,361,4
            FCB  C_COLOR,9
            FCB  C_CIRCLE
            FDB  81,361,8
            FCB  C_COLOR,10
            FCB  C_CIRCLE
            FDB  81,361,12
            FCB  C_COLOR,11
            FCB  C_CIRCLE
            FDB  81,361,16
            FCB  C_COLOR,12
            FCB  C_CIRCLE
            FDB  81,361,20
            FCB  C_COLOR,13
            FCB  C_CIRCLE
            FDB  81,361,24
            FCB  C_COLOR,14
            FCB  C_CIRCLE
            FDB  81,361,28
            FCB  C_COLOR,15
            FCB  C_CIRCLE
            FDB  81,361,32
            FCB  C_COLOR,8
            FCB  C_CIRCLE
            FDB  81,361,36
            FCB  C_COLOR,9
            FCB  C_CIRCLE
            FDB  81,361,40
            FCB  C_COLOR,10
            FCB  C_CIRCLE
            FDB  81,361,44
            FCB  C_COLOR,11
            FCB  C_CIRCLE
            FDB  81,361,48
            FCB  C_COLOR,12
            FCB  C_CIRCLE
            FDB  81,361,52
            FCB  C_COLOR,13
            FCB  C_CIRCLE
            FDB  81,361,56
            FCB  C_COLOR,14
            FCB  C_CIRCLE
            FDB  81,361,60
            FCB  C_COLOR,15
            FCB  C_CIRCLE
            FDB  81,361,64
            FCB  C_COLOR,8
            FCB  C_CIRCLE
            FDB  81,361,68
            FCB  C_COLOR,9
            FCB  C_CIRCLE
            FDB  81,361,72
            FCB  C_COLOR,2
            FCB  C_DISC
            FDB  203,311,30
            FCB  C_COLOR,1
            FCB  C_DISC
            FDB  193,301,5
            FCB  C_COLOR,3
            FCB  C_DISC
            FDB  263,321,38
            FCB  C_COLOR,1
            FCB  C_DISC
            FDB  251,309,6
            FCB  C_COLOR,4
            FCB  C_DISC
            FDB  233,371,26
            FCB  C_COLOR,1
            FCB  C_DISC
            FDB  225,363,4
            FCB  C_COLOR,5
            FCB  C_DISC
            FDB  193,411,22
            FCB  C_COLOR,1
            FCB  C_DISC
            FDB  186,404,3
            FCB  C_COLOR,6
            FCB  C_DISC
            FDB  273,411,34
            FCB  C_COLOR,1
            FCB  C_DISC
            FDB  262,400,5
            FCB  C_COLOR,7
            FCB  C_DISC
            FDB  223,441,14
            FCB  C_COLOR,1
            FCB  C_DISC
            FDB  219,437,2
            FCB  C_COLOR,2
            FCB  C_DISC
            FDB  293,361,12
            FCB  C_COLOR,1
            FCB  C_DISC
            FDB  289,357,2
            FCB  C_COLOR,3
            FCB  C_DISC
            FDB  183,351,10
            FCB  C_COLOR,1
            FCB  C_DISC
            FDB  180,348,1
            FCB  C_COLOR,4
            FCB  C_DISC
            FDB  253,281,8
            FCB  C_COLOR,1
            FCB  C_DISC
            FDB  251,279,1
            FCB  C_COLOR,5
            FCB  C_DISC
            FDB  288,286,6
            FCB  C_COLOR,1
            FCB  C_DISC
            FDB  286,284,1
            FCB  C_COLOR,2
            FCB  C_TRIANGLE
            FDB  399,363,469,363,467,381
            FCB  C_COLOR,3
            FCB  C_TRIANGLE
            FDB  399,363,460,398,448,412
            FCB  C_COLOR,4
            FCB  C_TRIANGLE
            FDB  399,363,434,424,417,431
            FCB  C_COLOR,5
            FCB  C_TRIANGLE
            FDB  399,363,399,433,381,431
            FCB  C_COLOR,6
            FCB  C_TRIANGLE
            FDB  399,363,364,424,350,412
            FCB  C_COLOR,7
            FCB  C_TRIANGLE
            FDB  399,363,338,398,331,381
            FCB  C_COLOR,2
            FCB  C_TRIANGLE
            FDB  399,363,329,363,331,345
            FCB  C_COLOR,3
            FCB  C_TRIANGLE
            FDB  399,363,338,328,350,314
            FCB  C_COLOR,4
            FCB  C_TRIANGLE
            FDB  399,363,364,302,381,295
            FCB  C_COLOR,5
            FCB  C_TRIANGLE
            FDB  399,363,399,293,417,295
            FCB  C_COLOR,6
            FCB  C_TRIANGLE
            FDB  399,363,434,302,448,314
            FCB  C_COLOR,7
            FCB  C_TRIANGLE
            FDB  399,363,460,328,467,345
            FCB  C_TARGET,$80,$00,$00    ; the stamp, in the PSRAM
            FDB  8,16,16
            FCB  4
            FCB  C_COLOR,0
            FCB  C_CLEAR
            FCB  C_COLOR,4
            FCB  C_DISC
            FDB  7,7,7
            FCB  C_COLOR,3
            FCB  C_CIRCLE
            FDB  7,7,7
            FCB  C_COLOR,1
            FCB  C_DISC
            FDB  5,5,1
            FCB  C_TARGET,$00,$00,$00    ; the bitmap again
            FDB  320,640,480
            FCB  4
            FCB  C_BLIT,$80,$00,$00
            FDB  8,16,16,489,269
            FCB  1              ; (0 is transparent)
            FCB  C_BLIT,$80,$00,$00
            FDB  8,16,16,506,269
            FCB  1              ; (0 is transparent)
            FCB  C_BLIT,$80,$00,$00
            FDB  8,16,16,523,269
            FCB  1              ; (0 is transparent)
            FCB  C_BLIT,$80,$00,$00
            FDB  8,16,16,540,269
            FCB  1              ; (0 is transparent)
            FCB  C_BLIT,$80,$00,$00
            FDB  8,16,16,557,269
            FCB  1              ; (0 is transparent)
            FCB  C_BLIT,$80,$00,$00
            FDB  8,16,16,574,269
            FCB  1              ; (0 is transparent)
            FCB  C_BLIT,$80,$00,$00
            FDB  8,16,16,591,269
            FCB  1              ; (0 is transparent)
            FCB  C_BLIT,$80,$00,$00
            FDB  8,16,16,608,269
            FCB  1              ; (0 is transparent)
            FCB  C_BLIT,$80,$00,$00
            FDB  8,16,16,489,287
            FCB  1              ; (0 is transparent)
            FCB  C_BLIT,$80,$00,$00
            FDB  8,16,16,506,287
            FCB  1              ; (0 is transparent)
            FCB  C_BLIT,$80,$00,$00
            FDB  8,16,16,523,287
            FCB  1              ; (0 is transparent)
            FCB  C_BLIT,$80,$00,$00
            FDB  8,16,16,540,287
            FCB  1              ; (0 is transparent)
            FCB  C_BLIT,$80,$00,$00
            FDB  8,16,16,557,287
            FCB  1              ; (0 is transparent)
            FCB  C_BLIT,$80,$00,$00
            FDB  8,16,16,574,287
            FCB  1              ; (0 is transparent)
            FCB  C_BLIT,$80,$00,$00
            FDB  8,16,16,591,287
            FCB  1              ; (0 is transparent)
            FCB  C_BLIT,$80,$00,$00
            FDB  8,16,16,608,287
            FCB  1              ; (0 is transparent)
            FCB  C_BLIT,$80,$00,$00
            FDB  8,16,16,489,305
            FCB  1              ; (0 is transparent)
            FCB  C_BLIT,$80,$00,$00
            FDB  8,16,16,506,305
            FCB  1              ; (0 is transparent)
            FCB  C_BLIT,$80,$00,$00
            FDB  8,16,16,523,305
            FCB  1              ; (0 is transparent)
            FCB  C_BLIT,$80,$00,$00
            FDB  8,16,16,540,305
            FCB  1              ; (0 is transparent)
            FCB  C_BLIT,$80,$00,$00
            FDB  8,16,16,557,305
            FCB  1              ; (0 is transparent)
            FCB  C_BLIT,$80,$00,$00
            FDB  8,16,16,574,305
            FCB  1              ; (0 is transparent)
            FCB  C_BLIT,$80,$00,$00
            FDB  8,16,16,591,305
            FCB  1              ; (0 is transparent)
            FCB  C_BLIT,$80,$00,$00
            FDB  8,16,16,608,305
            FCB  1              ; (0 is transparent)
            FCB  C_FILL,$01,$99,$B4,$00,$00,70,$56
            FCB  C_FILL,$01,$9A,$F4,$00,$00,70,$65
            FCB  C_FILL,$01,$9C,$34,$00,$00,70,$56
            FCB  C_FILL,$01,$9D,$74,$00,$00,70,$65
            FCB  C_FILL,$01,$9E,$B4,$00,$00,70,$56
            FCB  C_FILL,$01,$9F,$F4,$00,$00,70,$65
            FCB  C_FILL,$01,$A1,$34,$00,$00,70,$56
            FCB  C_FILL,$01,$A2,$74,$00,$00,70,$65
            FCB  C_FILL,$01,$A3,$B4,$00,$00,70,$56
            FCB  C_FILL,$01,$A4,$F4,$00,$00,70,$65
            FCB  C_FILL,$01,$A6,$34,$00,$00,70,$56
            FCB  C_FILL,$01,$A7,$74,$00,$00,70,$65
            FCB  C_COPY,$01,$62,$15,$01,$B2,$B4,$00,$00,70
            FCB  C_COPY,$01,$63,$55,$01,$B3,$F4,$00,$00,70
            FCB  C_COPY,$01,$64,$95,$01,$B5,$34,$00,$00,70
            FCB  C_COPY,$01,$65,$D5,$01,$B6,$74,$00,$00,70
            FCB  C_COPY,$01,$67,$15,$01,$B7,$B4,$00,$00,70
            FCB  C_COPY,$01,$68,$55,$01,$B8,$F4,$00,$00,70
            FCB  C_COPY,$01,$69,$95,$01,$BA,$34,$00,$00,70
            FCB  C_COPY,$01,$6A,$D5,$01,$BB,$74,$00,$00,70
            FCB  C_COPY,$01,$6C,$15,$01,$BC,$B4,$00,$00,70
            FCB  C_COPY,$01,$6D,$55,$01,$BD,$F4,$00,$00,70
            FCB  C_COPY,$01,$6E,$95,$01,$BF,$34,$00,$00,70
            FCB  C_COPY,$01,$6F,$D5,$01,$C0,$74,$00,$00,70
            FCB  C_COPY,$01,$71,$15,$01,$C1,$B4,$00,$00,70
            FCB  C_COPY,$01,$72,$55,$01,$C2,$F4,$00,$00,70
            FCB  C_COPY,$01,$73,$95,$01,$C4,$34,$00,$00,70
            FCB  C_COPY,$01,$74,$D5,$01,$C5,$74,$00,$00,70
            FCB  C_COPY,$01,$76,$15,$01,$C6,$B4,$00,$00,70
            FCB  C_COPY,$01,$77,$55,$01,$C7,$F4,$00,$00,70
            FCB  C_COPY,$01,$78,$95,$01,$C9,$34,$00,$00,70
            FCB  C_COPY,$01,$79,$D5,$01,$CA,$74,$00,$00,70
            FCB  C_COPY,$01,$7B,$15,$01,$CB,$B4,$00,$00,70
            FCB  C_COPY,$01,$7C,$55,$01,$CC,$F4,$00,$00,70
            FCB  C_COPY,$01,$7D,$95,$01,$CE,$34,$00,$00,70
            FCB  C_COPY,$01,$7E,$D5,$01,$CF,$74,$00,$00,70
            FCB  C_COPY,$01,$80,$15,$01,$D0,$B4,$00,$00,70
            FCB  C_COPY,$01,$81,$55,$01,$D1,$F4,$00,$00,70
            FCB  C_COPY,$01,$82,$95,$01,$D3,$34,$00,$00,70
            FCB  C_COPY,$01,$83,$D5,$01,$D4,$74,$00,$00,70
            FCB  C_COPY,$01,$85,$15,$01,$D5,$B4,$00,$00,70
            FCB  C_COPY,$01,$86,$55,$01,$D6,$F4,$00,$00,70
            FCB  C_COPY,$01,$87,$95,$01,$D8,$34,$00,$00,70
            FCB  C_COPY,$01,$88,$D5,$01,$D9,$74,$00,$00,70
            FCB  C_COPY,$01,$8A,$15,$01,$DA,$B4,$00,$00,70
            FCB  C_COPY,$01,$8B,$55,$01,$DB,$F4,$00,$00,70
            FCB  C_COPY,$01,$8C,$95,$01,$DD,$34,$00,$00,70
            FCB  C_COPY,$01,$8D,$D5,$01,$DE,$74,$00,$00,70
            FCB  C_COPY,$01,$8F,$15,$01,$DF,$B4,$00,$00,70
            FCB  C_COPY,$01,$90,$55,$01,$E0,$F4,$00,$00,70
            FCB  C_COPY,$01,$91,$95,$01,$E2,$34,$00,$00,70
            FCB  C_COPY,$01,$92,$D5,$01,$E3,$74,$00,$00,70
            FCB  C_COPY,$01,$94,$15,$01,$E4,$B4,$00,$00,70
            FCB  C_COPY,$01,$95,$55,$01,$E5,$F4,$00,$00,70
            FCB  C_COPY,$01,$96,$95,$01,$E7,$34,$00,$00,70
            FCB  C_COPY,$01,$97,$D5,$01,$E8,$74,$00,$00,70
            FCB  C_COPY,$01,$99,$15,$01,$E9,$B4,$00,$00,70
            FCB  C_COPY,$01,$9A,$55,$01,$EA,$F4,$00,$00,70
            FCB  C_COPY,$01,$9B,$95,$01,$EC,$34,$00,$00,70
            FCB  C_COPY,$01,$9C,$D5,$01,$ED,$74,$00,$00,70
            FCB  C_COPY,$01,$9E,$15,$01,$EE,$B4,$00,$00,70
            FCB  C_COPY,$01,$9F,$55,$01,$EF,$F4,$00,$00,70
            FCB  C_COPY,$01,$A0,$95,$01,$F1,$34,$00,$00,70
            FCB  C_COPY,$01,$A1,$D5,$01,$F2,$74,$00,$00,70
            FCB  C_COPY,$01,$A3,$15,$01,$F3,$B4,$00,$00,70
            FCB  C_COPY,$01,$A4,$55,$01,$F4,$F4,$00,$00,70
            FCB  C_COPY,$01,$A5,$95,$01,$F6,$34,$00,$00,70
            FCB  C_COPY,$01,$A6,$D5,$01,$F7,$74,$00,$00,70
            FCB  C_COPY,$01,$A8,$15,$01,$F8,$B4,$00,$00,70
            FCB  C_COPY,$01,$A9,$55,$01,$F9,$F4,$00,$00,70
            FCB  C_COPY,$01,$AA,$95,$01,$FB,$34,$00,$00,70
            FCB  C_COPY,$01,$AB,$D5,$01,$FC,$74,$00,$00,70
            FCB  C_COPY,$01,$AD,$15,$01,$FD,$B4,$00,$00,70
            FCB  C_COPY,$01,$AE,$55,$01,$FE,$F4,$00,$00,70
            FCB  C_COPY,$01,$AF,$95,$02,$00,$34,$00,$00,70
            FCB  C_COPY,$01,$B0,$D5,$02,$01,$74,$00,$00,70
            FCB  C_COPY,$01,$B2,$15,$02,$02,$B4,$00,$00,70
            FCB  C_COPY,$01,$B3,$55,$02,$03,$F4,$00,$00,70
            FCB  C_COPY,$01,$B4,$95,$02,$05,$34,$00,$00,70
            FCB  C_COPY,$01,$B5,$D5,$02,$06,$74,$00,$00,70
            FCB  C_COPY,$01,$B7,$15,$02,$07,$B4,$00,$00,70
            FCB  C_COPY,$01,$B8,$55,$02,$08,$F4,$00,$00,70
            FCB  C_COPY,$01,$B9,$95,$02,$0A,$34,$00,$00,70
            FCB  C_COPY,$01,$BA,$D5,$02,$0B,$74,$00,$00,70
            FCB  C_COPY,$01,$BC,$15,$02,$0C,$B4,$00,$00,70
            FCB  C_COPY,$01,$BD,$55,$02,$0D,$F4,$00,$00,70
            FCB  C_COPY,$01,$BE,$95,$02,$0F,$34,$00,$00,70
            FCB  C_COPY,$01,$BF,$D5,$02,$10,$74,$00,$00,70
            FCB  C_COPY,$01,$C1,$15,$02,$11,$B4,$00,$00,70
            FCB  C_COPY,$01,$C2,$55,$02,$12,$F4,$00,$00,70
            FCB  C_COPY,$01,$C3,$95,$02,$14,$34,$00,$00,70
            FCB  C_COPY,$01,$C4,$D5,$02,$15,$74,$00,$00,70
            FCB  C_COPY,$01,$C6,$15,$02,$16,$B4,$00,$00,70
            FCB  C_COPY,$01,$C7,$55,$02,$17,$F4,$00,$00,70
            FCB  C_COPY,$01,$C8,$95,$02,$19,$34,$00,$00,70
            FCB  C_COPY,$01,$C9,$D5,$02,$1A,$74,$00,$00,70
            FCB  C_COPY,$01,$CB,$15,$02,$1B,$B4,$00,$00,70
            FCB  C_COPY,$01,$CC,$55,$02,$1C,$F4,$00,$00,70
            FCB  C_COPY,$01,$CD,$95,$02,$1E,$34,$00,$00,70
            FCB  C_COPY,$01,$CE,$D5,$02,$1F,$74,$00,$00,70
            FCB  C_COPY,$01,$D0,$15,$02,$20,$B4,$00,$00,70
            FCB  C_COPY,$01,$D1,$55,$02,$21,$F4,$00,$00,70
            FCB  C_COPY,$01,$D2,$95,$02,$23,$34,$00,$00,70
            FCB  C_COPY,$01,$D3,$D5,$02,$24,$74,$00,$00,70
            FCB  C_COPY,$01,$D5,$15,$02,$25,$B4,$00,$00,70
            FCB  C_COPY,$01,$D6,$55,$02,$26,$F4,$00,$00,70
            FCB  C_COPY,$01,$D7,$95,$02,$28,$34,$00,$00,70
            FCB  C_COPY,$01,$D8,$D5,$02,$29,$74,$00,$00,70
            FCB  C_COPY,$01,$DA,$15,$02,$2A,$B4,$00,$00,70
            FCB  C_COPY,$01,$DB,$55,$02,$2B,$F4,$00,$00,70
            FCB  C_COPY,$01,$DC,$95,$02,$2D,$34,$00,$00,70
            FCB  C_COPY,$01,$DD,$D5,$02,$2E,$74,$00,$00,70
PAGE1END
PAGE2CMDS   EQU  *
            FCB  C_TARGET,$00,$00,$00    ; the tunnel: rings in colors 32-95
            FDB  320,320,240
            FCB  8
            FCB  C_COLOR,32
            FCB  C_DISC
            FDB  160,120,110
            FCB  C_COLOR,33
            FCB  C_DISC
            FDB  160,120,108
            FCB  C_COLOR,34
            FCB  C_DISC
            FDB  160,120,106
            FCB  C_COLOR,35
            FCB  C_DISC
            FDB  160,120,104
            FCB  C_COLOR,36
            FCB  C_DISC
            FDB  160,120,102
            FCB  C_COLOR,37
            FCB  C_DISC
            FDB  160,120,100
            FCB  C_COLOR,38
            FCB  C_DISC
            FDB  160,120,98
            FCB  C_COLOR,39
            FCB  C_DISC
            FDB  160,120,96
            FCB  C_COLOR,40
            FCB  C_DISC
            FDB  160,120,94
            FCB  C_COLOR,41
            FCB  C_DISC
            FDB  160,120,92
            FCB  C_COLOR,42
            FCB  C_DISC
            FDB  160,120,90
            FCB  C_COLOR,43
            FCB  C_DISC
            FDB  160,120,88
            FCB  C_COLOR,44
            FCB  C_DISC
            FDB  160,120,86
            FCB  C_COLOR,45
            FCB  C_DISC
            FDB  160,120,84
            FCB  C_COLOR,46
            FCB  C_DISC
            FDB  160,120,82
            FCB  C_COLOR,47
            FCB  C_DISC
            FDB  160,120,80
            FCB  C_COLOR,48
            FCB  C_DISC
            FDB  160,120,78
            FCB  C_COLOR,49
            FCB  C_DISC
            FDB  160,120,76
            FCB  C_COLOR,50
            FCB  C_DISC
            FDB  160,120,74
            FCB  C_COLOR,51
            FCB  C_DISC
            FDB  160,120,72
            FCB  C_COLOR,52
            FCB  C_DISC
            FDB  160,120,70
            FCB  C_COLOR,53
            FCB  C_DISC
            FDB  160,120,68
            FCB  C_COLOR,54
            FCB  C_DISC
            FDB  160,120,66
            FCB  C_COLOR,55
            FCB  C_DISC
            FDB  160,120,64
            FCB  C_COLOR,56
            FCB  C_DISC
            FDB  160,120,62
            FCB  C_COLOR,57
            FCB  C_DISC
            FDB  160,120,60
            FCB  C_COLOR,58
            FCB  C_DISC
            FDB  160,120,58
            FCB  C_COLOR,59
            FCB  C_DISC
            FDB  160,120,56
            FCB  C_COLOR,60
            FCB  C_DISC
            FDB  160,120,54
            FCB  C_COLOR,61
            FCB  C_DISC
            FDB  160,120,52
            FCB  C_COLOR,62
            FCB  C_DISC
            FDB  160,120,50
            FCB  C_COLOR,63
            FCB  C_DISC
            FDB  160,120,48
            FCB  C_COLOR,64
            FCB  C_DISC
            FDB  160,120,46
            FCB  C_COLOR,65
            FCB  C_DISC
            FDB  160,120,44
            FCB  C_COLOR,66
            FCB  C_DISC
            FDB  160,120,42
            FCB  C_COLOR,67
            FCB  C_DISC
            FDB  160,120,40
            FCB  C_COLOR,68
            FCB  C_DISC
            FDB  160,120,38
            FCB  C_COLOR,69
            FCB  C_DISC
            FDB  160,120,36
            FCB  C_COLOR,70
            FCB  C_DISC
            FDB  160,120,34
            FCB  C_COLOR,71
            FCB  C_DISC
            FDB  160,120,32
            FCB  C_COLOR,72
            FCB  C_DISC
            FDB  160,120,30
            FCB  C_COLOR,73
            FCB  C_DISC
            FDB  160,120,28
            FCB  C_COLOR,74
            FCB  C_DISC
            FDB  160,120,26
            FCB  C_COLOR,75
            FCB  C_DISC
            FDB  160,120,24
            FCB  C_COLOR,76
            FCB  C_DISC
            FDB  160,120,22
            FCB  C_COLOR,77
            FCB  C_DISC
            FDB  160,120,20
            FCB  C_COLOR,78
            FCB  C_DISC
            FDB  160,120,18
            FCB  C_COLOR,79
            FCB  C_DISC
            FDB  160,120,16
            FCB  C_COLOR,80
            FCB  C_DISC
            FDB  160,120,14
            FCB  C_COLOR,81
            FCB  C_DISC
            FDB  160,120,12
            FCB  C_COLOR,82
            FCB  C_DISC
            FDB  160,120,10
            FCB  C_COLOR,83
            FCB  C_DISC
            FDB  160,120,8
            FCB  C_COLOR,84
            FCB  C_DISC
            FDB  160,120,6
            FCB  C_COLOR,85
            FCB  C_DISC
            FDB  160,120,4
            FCB  C_COLOR,86
            FCB  C_DISC
            FDB  160,120,2
            FCB  C_TARGET,$01,$80,$00    ; the words, 1 bit a pixel
            FDB  80,640,480
            FCB  1
            FCB  C_COLOR,1
            FCB  C_RECT
            FDB  2,2,636,476
            FCB  C_RECT
            FDB  5,5,630,470
            FCB  C_CHAR
            FDB  24,14
            FCB  66
            FCB  C_CHAR
            FDB  32,14
            FCB  73
            FCB  C_CHAR
            FDB  40,14
            FCB  84
            FCB  C_CHAR
            FDB  48,14
            FCB  77
            FCB  C_CHAR
            FDB  56,14
            FCB  65
            FCB  C_CHAR
            FDB  64,14
            FCB  80
            FCB  C_CHAR
            FDB  72,14
            FCB  83
            FCB  C_CHAR
            FDB  80,14
            FCB  32
            FCB  C_CHAR
            FDB  88,14
            FCB  79
            FCB  C_CHAR
            FDB  96,14
            FCB  70
            FCB  C_CHAR
            FDB  104,14
            FCB  32
            FCB  C_CHAR
            FDB  112,14
            FCB  56
            FCB  C_CHAR
            FDB  120,14
            FCB  44
            FCB  C_CHAR
            FDB  128,14
            FCB  32
            FCB  C_CHAR
            FDB  136,14
            FCB  50
            FCB  C_CHAR
            FDB  144,14
            FCB  32
            FCB  C_CHAR
            FDB  152,14
            FCB  65
            FCB  C_CHAR
            FDB  160,14
            FCB  78
            FCB  C_CHAR
            FDB  168,14
            FCB  68
            FCB  C_CHAR
            FDB  176,14
            FCB  32
            FCB  C_CHAR
            FDB  184,14
            FCB  49
            FCB  C_CHAR
            FDB  192,14
            FCB  32
            FCB  C_CHAR
            FDB  200,14
            FCB  66
            FCB  C_CHAR
            FDB  208,14
            FCB  73
            FCB  C_CHAR
            FDB  216,14
            FCB  84
            FCB  C_CHAR
            FDB  224,14
            FCB  83
            FCB  C_CHAR
            FDB  232,14
            FCB  32
            FCB  C_CHAR
            FDB  240,14
            FCB  65
            FCB  C_CHAR
            FDB  248,14
            FCB  32
            FCB  C_CHAR
            FDB  256,14
            FCB  80
            FCB  C_CHAR
            FDB  264,14
            FCB  73
            FCB  C_CHAR
            FDB  272,14
            FCB  88
            FCB  C_CHAR
            FDB  280,14
            FCB  69
            FCB  C_CHAR
            FDB  288,14
            FCB  76
            FCB  C_CHAR
            FDB  296,14
            FCB  44
            FCB  C_CHAR
            FDB  304,14
            FCB  32
            FCB  C_CHAR
            FDB  312,14
            FCB  82
            FCB  C_CHAR
            FDB  320,14
            FCB  65
            FCB  C_CHAR
            FDB  328,14
            FCB  83
            FCB  C_CHAR
            FDB  336,14
            FCB  84
            FCB  C_CHAR
            FDB  344,14
            FCB  69
            FCB  C_CHAR
            FDB  352,14
            FCB  82
            FCB  C_CHAR
            FDB  360,14
            FCB  32
            FCB  C_CHAR
            FDB  368,14
            FCB  73
            FCB  C_CHAR
            FDB  376,14
            FCB  78
            FCB  C_CHAR
            FDB  384,14
            FCB  84
            FCB  C_CHAR
            FDB  392,14
            FCB  69
            FCB  C_CHAR
            FDB  400,14
            FCB  82
            FCB  C_CHAR
            FDB  408,14
            FCB  82
            FCB  C_CHAR
            FDB  416,14
            FCB  85
            FCB  C_CHAR
            FDB  424,14
            FCB  80
            FCB  C_CHAR
            FDB  432,14
            FCB  84
            FCB  C_CHAR
            FDB  440,14
            FCB  83
            FCB  C_CHAR
            FDB  448,14
            FCB  44
            FCB  C_CHAR
            FDB  456,14
            FCB  32
            FCB  C_CHAR
            FDB  464,14
            FCB  84
            FCB  C_CHAR
            FDB  472,14
            FCB  72
            FCB  C_CHAR
            FDB  480,14
            FCB  69
            FCB  C_CHAR
            FDB  488,14
            FCB  32
            FCB  C_CHAR
            FDB  496,14
            FCB  80
            FCB  C_CHAR
            FDB  504,14
            FCB  83
            FCB  C_CHAR
            FDB  512,14
            FCB  82
            FCB  C_CHAR
            FDB  520,14
            FCB  65
            FCB  C_CHAR
            FDB  528,14
            FCB  77
            FCB  C_CHAR
            FDB  24,440
            FCB  84
            FCB  C_CHAR
            FDB  32,440
            FCB  72
            FCB  C_CHAR
            FDB  40,440
            FCB  69
            FCB  C_CHAR
            FDB  48,440
            FCB  32
            FCB  C_CHAR
            FDB  56,440
            FCB  83
            FCB  C_CHAR
            FDB  64,440
            FCB  80
            FCB  C_CHAR
            FDB  72,440
            FCB  73
            FCB  C_CHAR
            FDB  80,440
            FCB  78
            FCB  C_CHAR
            FDB  88,440
            FCB  78
            FCB  C_CHAR
            FDB  96,440
            FCB  69
            FCB  C_CHAR
            FDB  104,440
            FCB  82
            FCB  C_CHAR
            FDB  112,440
            FCB  58
            FCB  C_CHAR
            FDB  120,440
            FCB  32
            FCB  C_CHAR
            FDB  128,440
            FCB  56
            FCB  C_CHAR
            FDB  136,440
            FCB  32
            FCB  C_CHAR
            FDB  144,440
            FCB  70
            FCB  C_CHAR
            FDB  152,440
            FCB  82
            FCB  C_CHAR
            FDB  160,440
            FCB  65
            FCB  C_CHAR
            FDB  168,440
            FCB  77
            FCB  C_CHAR
            FDB  176,440
            FCB  69
            FCB  C_CHAR
            FDB  184,440
            FCB  83
            FCB  C_CHAR
            FDB  192,440
            FCB  32
            FCB  C_CHAR
            FDB  200,440
            FCB  73
            FCB  C_CHAR
            FDB  208,440
            FCB  78
            FCB  C_CHAR
            FDB  216,440
            FCB  32
            FCB  C_CHAR
            FDB  224,440
            FCB  84
            FCB  C_CHAR
            FDB  232,440
            FCB  72
            FCB  C_CHAR
            FDB  240,440
            FCB  69
            FCB  C_CHAR
            FDB  248,440
            FCB  32
            FCB  C_CHAR
            FDB  256,440
            FCB  80
            FCB  C_CHAR
            FDB  264,440
            FCB  83
            FCB  C_CHAR
            FDB  272,440
            FCB  82
            FCB  C_CHAR
            FDB  280,440
            FCB  65
            FCB  C_CHAR
            FDB  288,440
            FCB  77
            FCB  C_CHAR
            FDB  296,440
            FCB  44
            FCB  C_CHAR
            FDB  304,440
            FCB  32
            FCB  C_CHAR
            FDB  312,440
            FCB  67
            FCB  C_CHAR
            FDB  320,440
            FCB  79
            FCB  C_CHAR
            FDB  328,440
            FCB  80
            FCB  C_CHAR
            FDB  336,440
            FCB  73
            FCB  C_CHAR
            FDB  344,440
            FCB  69
            FCB  C_CHAR
            FDB  352,440
            FCB  68
            FCB  C_CHAR
            FDB  360,440
            FCB  32
            FCB  C_CHAR
            FDB  368,440
            FCB  73
            FCB  C_CHAR
            FDB  376,440
            FCB  78
            FCB  C_CHAR
            FDB  384,440
            FCB  46
            FCB  C_CHAR
            FDB  392,440
            FCB  32
            FCB  C_CHAR
            FDB  400,440
            FCB  32
            FCB  C_CHAR
            FDB  408,440
            FCB  32
            FCB  C_CHAR
            FDB  416,440
            FCB  32
            FCB  C_CHAR
            FDB  424,440
            FCB  65
            FCB  C_CHAR
            FDB  432,440
            FCB  32
            FCB  C_CHAR
            FDB  440,440
            FCB  75
            FCB  C_CHAR
            FDB  448,440
            FCB  69
            FCB  C_CHAR
            FDB  456,440
            FCB  89
            FCB  C_CHAR
            FDB  464,440
            FCB  58
            FCB  C_CHAR
            FDB  472,440
            FCB  32
            FCB  C_CHAR
            FDB  480,440
            FCB  66
            FCB  C_CHAR
            FDB  488,440
            FCB  65
            FCB  C_CHAR
            FDB  496,440
            FCB  67
            FCB  C_CHAR
            FDB  504,440
            FCB  75
            FCB  C_CHAR
            FDB  512,440
            FCB  32
            FCB  C_CHAR
            FDB  520,440
            FCB  84
            FCB  C_CHAR
            FDB  528,440
            FCB  79
            FCB  C_CHAR
            FDB  536,440
            FCB  32
            FCB  C_CHAR
            FDB  544,440
            FCB  84
            FCB  C_CHAR
            FDB  552,440
            FCB  72
            FCB  C_CHAR
            FDB  560,440
            FCB  69
            FCB  C_CHAR
            FDB  568,440
            FCB  32
            FCB  C_CHAR
            FDB  576,440
            FCB  83
            FCB  C_CHAR
            FDB  584,440
            FCB  72
            FCB  C_CHAR
            FDB  592,440
            FCB  69
            FCB  C_CHAR
            FDB  600,440
            FCB  76
            FCB  C_CHAR
            FDB  608,440
            FCB  76
            FCB  C_TARGET,$80,$00,$00    ; spinner frame 0
            FDB  20,80,64
            FCB  2
            FCB  C_COLOR,0
            FCB  C_CLEAR
            FCB  C_COLOR,1
            FCB  C_DISC
            FDB  40,32,30
            FCB  C_COLOR,2
            FCB  C_TRIANGLE
            FDB  40,32,67,25,67,39
            FCB  C_TRIANGLE
            FDB  40,32,32,59,20,52
            FCB  C_TRIANGLE
            FDB  40,32,20,12,32,5
            FCB  C_COLOR,3
            FCB  C_DISC
            FDB  40,32,6
            FCB  C_TARGET,$80,$05,$00    ; spinner frame 1
            FDB  20,80,64
            FCB  2
            FCB  C_COLOR,0
            FCB  C_CLEAR
            FCB  C_COLOR,1
            FCB  C_DISC
            FDB  40,32,30
            FCB  C_COLOR,2
            FCB  C_TRIANGLE
            FDB  40,32,68,32,64,46
            FCB  C_TRIANGLE
            FDB  40,32,26,56,16,46
            FCB  C_TRIANGLE
            FDB  40,32,26,8,40,4
            FCB  C_COLOR,3
            FCB  C_DISC
            FDB  40,32,6
            FCB  C_TARGET,$80,$0A,$00    ; spinner frame 2
            FDB  20,80,64
            FCB  2
            FCB  C_COLOR,0
            FCB  C_CLEAR
            FCB  C_COLOR,1
            FCB  C_DISC
            FDB  40,32,30
            FCB  C_COLOR,2
            FCB  C_TRIANGLE
            FDB  40,32,67,40,60,52
            FCB  C_TRIANGLE
            FDB  40,32,20,52,13,40
            FCB  C_TRIANGLE
            FDB  40,32,33,5,47,5
            FCB  C_COLOR,3
            FCB  C_DISC
            FDB  40,32,6
            FCB  C_TARGET,$80,$0F,$00    ; spinner frame 3
            FDB  20,80,64
            FCB  2
            FCB  C_COLOR,0
            FCB  C_CLEAR
            FCB  C_COLOR,1
            FCB  C_DISC
            FDB  40,32,30
            FCB  C_COLOR,2
            FCB  C_TRIANGLE
            FDB  40,32,64,46,54,56
            FCB  C_TRIANGLE
            FDB  40,32,16,46,12,32
            FCB  C_TRIANGLE
            FDB  40,32,40,4,54,8
            FCB  C_COLOR,3
            FCB  C_DISC
            FDB  40,32,6
            FCB  C_TARGET,$80,$14,$00    ; spinner frame 4
            FDB  20,80,64
            FCB  2
            FCB  C_COLOR,0
            FCB  C_CLEAR
            FCB  C_COLOR,1
            FCB  C_DISC
            FDB  40,32,30
            FCB  C_COLOR,2
            FCB  C_TRIANGLE
            FDB  40,32,60,52,48,59
            FCB  C_TRIANGLE
            FDB  40,32,13,39,13,25
            FCB  C_TRIANGLE
            FDB  40,32,48,5,60,12
            FCB  C_COLOR,3
            FCB  C_DISC
            FDB  40,32,6
            FCB  C_TARGET,$80,$19,$00    ; spinner frame 5
            FDB  20,80,64
            FCB  2
            FCB  C_COLOR,0
            FCB  C_CLEAR
            FCB  C_COLOR,1
            FCB  C_DISC
            FDB  40,32,30
            FCB  C_COLOR,2
            FCB  C_TRIANGLE
            FDB  40,32,54,56,40,60
            FCB  C_TRIANGLE
            FDB  40,32,12,32,16,18
            FCB  C_TRIANGLE
            FDB  40,32,54,8,64,18
            FCB  C_COLOR,3
            FCB  C_DISC
            FDB  40,32,6
            FCB  C_TARGET,$80,$1E,$00    ; spinner frame 6
            FDB  20,80,64
            FCB  2
            FCB  C_COLOR,0
            FCB  C_CLEAR
            FCB  C_COLOR,1
            FCB  C_DISC
            FDB  40,32,30
            FCB  C_COLOR,2
            FCB  C_TRIANGLE
            FDB  40,32,47,59,33,59
            FCB  C_TRIANGLE
            FDB  40,32,13,24,20,12
            FCB  C_TRIANGLE
            FDB  40,32,60,12,67,24
            FCB  C_COLOR,3
            FCB  C_DISC
            FDB  40,32,6
            FCB  C_TARGET,$80,$23,$00    ; spinner frame 7
            FDB  20,80,64
            FCB  2
            FCB  C_COLOR,0
            FCB  C_CLEAR
            FCB  C_COLOR,1
            FCB  C_DISC
            FDB  40,32,30
            FCB  C_COLOR,2
            FCB  C_TRIANGLE
            FDB  40,32,40,60,26,56
            FCB  C_TRIANGLE
            FDB  40,32,16,18,26,8
            FCB  C_TRIANGLE
            FDB  40,32,64,18,68,32
            FCB  C_COLOR,3
            FCB  C_DISC
            FDB  40,32,6
PAGE2END

            END  START
