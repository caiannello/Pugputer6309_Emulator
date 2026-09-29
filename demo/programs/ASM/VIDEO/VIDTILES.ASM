;------------------------------------------------------------------------------
; PROJECT: VIDEO CARD DEMOS
;    FILE: vidtiles.asm
;
; The video card's tile layers and sprites, in two pages (a key goes on to the
; next; after the last, back to the shell):
;
;   1  parallax, at 320x240: layer 0, 16x16 tiles of 8 bits a pixel (clouds,
;      hills), scrolls slowly over the backdrop's sky; layer 1, 8x8 tiles of 2
;      bits a pixel in palettes of their own (ground, a ceiling of grass flipped
;      upside down, bricks, bushes made of one tile and its mirror image),
;      scrolls faster; layer 2 is text. Sprites: a runner of two frames that
;      turns round (flipped across), another running upside down on the
;      ceiling (flipped down), and four orbs of 8, 16, 32 and 64 pixels, in
;      front of layer 0 only, of layer 1 and of everything
;   2  128 sprites at 640x480: 88 round two ellipses, and a row of 40 on the
;      same lines, of which the card draws the first 32. Their table is written
;      into a spare one while the other is shown, and the card switched to it
;      at vertical blank. Behind them, a tile layer of 1 bit a pixel, hires,
;      scrolling
;
;   ASM -f com vidtiles.asm        makes VIDTILES.COM
;------------------------------------------------------------------------------
            INCLUDE "vidcard.d"

BIGMAP      equ  $020000    ; page 1, layer 0: 64x32 entries
BIGTILES    equ  $021000    ;   16x16 tiles, 8 bits a pixel: 256 bytes each
SMALLMAP    equ  $022000    ; page 1, layer 1: 64x32 entries
SMALLTILES  equ  $023000    ;   8x8 tiles, 2 bits a pixel: 16 bytes each
RUNNER      equ  $024000    ; sprite images, 4 bits a pixel: the runner's two
RUNNER2     equ  $024080    ;   frames (16x16: 128 bytes each)
ORB8        equ  $025000    ;   and the orbs: 8x8 (32 bytes), 16x16 (128),
ORB16       equ  $025100    ;   32x32 (512), 64x64 (2048)
ORB32       equ  $025200
ORB64       equ  $025400
DOTMAP      equ  $020000    ; page 2, layer 0: 128x64 entries
DOTTILES    equ  $024000    ;   8x8 tiles, 1 bit a pixel: 8 bytes each
STAR        equ  $025000    ;   the sprites' image: 16x16, 4 bits a pixel
TABLEA      equ  $037000    ;   and their two tables
TABLEB      equ  $037400
;------------------------------------------------------------------------------
            ORG  $4000
START       LDA  #$80
            STA  VC_CTRL
;------------------------------------------------------------------------------
; Page 1: parallax.
;------------------------------------------------------------------------------
            LDX  #PALETTE1      ; the tiles' and the runner's colors
PAL1        LDA  ,X+
            BEQ  PAL2
            PSHS X
            LDX  ,X
            JSR  SETCOLOR
            PULS X
            LEAX 2,X
            BRA  PAL1
PAL2        LDA  #VC_CFG/$10000 ; the settings: layers, sprites, backdrop
            LDX  #DC_CTRL
            JSR  PORT0
            LDX  #SETTINGS1
            LDW  #SET1END-SETTINGS1
            JSR  SENDDAT
            LDX  #PICTURES1     ; the tiles and sprite images, drawn by the card
            LDW  #PIC1END-PICTURES1
            JSR  SENDCMD
; Layer 0's map: clouds high up, hills lower down.
            LDA  #BIGMAP/$10000
            LDX  #BIGMAP&$FFFF
            JSR  PORT0
            CLRB                ; the row
BIG1        CLRA                ; the column
BIG2        PSHS D
            JSR  BIGTILE
            STA  VC_DATA0
            STB  VC_DATA0
            PULS D
            INCA
            CMPA #64
            BNE  BIG2
            INCB
            CMPB #32
            BNE  BIG1
; Layer 1's map: the ceiling, bricks, bushes, the ground.
            LDA  #SMALLMAP/$10000
            LDX  #SMALLMAP&$FFFF
            JSR  PORT0
            CLRB
SMALL1      CLRA
SMALL2      PSHS D
            JSR  SMALLTILE
            STA  VC_DATA0
            STB  VC_DATA0
            PULS D
            INCA
            CMPA #64
            BNE  SMALL2
            INCB
            CMPB #32
            BNE  SMALL1
            LDX  #TEXTS1
            JSR  TEXTS
; Each frame: scroll, run, float.
PAGE1       JSR  VBLANK
            LDD  VL_FRAMES      ; layer 0 a pixel every 4 frames, layer 1 every frame
            LSRD
            LSRD
            PSHS D
            LDA  #VC_CFG/$10000
            LDX  #LAYER0+L_HSCROLL
            JSR  PORT0
            PULS D
            STA  VC_DATA0
            STB  VC_DATA0
            LDA  #VC_CFG/$10000
            LDX  #LAYER1+L_HSCROLL
            JSR  PORT0
            LDD  VL_FRAMES
            STA  VC_DATA0
            STB  VC_DATA0
            JSR  RUN
            JSR  FLOAT
            LDA  #VC_SPRITES/$10000
            LDX  #VC_SPRITES&$FFFF
            JSR  PORT0
            LDX  #SPRITES1
            LDW  #6*8
            JSR  SENDDAT
            JSR  GETKEY
            BCS  PAGE1
;------------------------------------------------------------------------------
; Page 2: 128 sprites.
;------------------------------------------------------------------------------
            LDA  #$80
            STA  VC_CTRL
            LDA  #VC_CFG/$10000
            LDX  #DC_CTRL
            JSR  PORT0
            LDX  #SETTINGS2
            LDW  #SET2END-SETTINGS2
            JSR  SENDDAT
            LDX  #PICTURES2
            LDW  #PIC2END-PICTURES2
            JSR  SENDCMD
; Layer 0: every entry the dot tile, its colors changing row by row.
            LDA  #DOTMAP/$10000
            LDX  #DOTMAP&$FFFF
            JSR  PORT0
            CLRB                ; the row
DOTS1       TFR  B,A
            ANDA #7
            INCA                ; palettes 1-8
            LSLA
            LSLA
            LSLA
            LSLA
            LDE  #128
DOTS2       STA  VC_DATA0
            LDF  #1             ; tile 1
            STF  VC_DATA0
            DECE
            BNE  DOTS2
            INCB
            CMPB #64
            BNE  DOTS1
; The sprite table's fixed parts: image and size; the row of 40 fixed places.
            LDX  #TABLE2
            CLRF                ; the sprite
TAB1        LDD  #STAR/32
            STD  S_IMAGE,X
            LDA  #SS_W16+SS_H16+SS_MID
            STA  S_SIZE,X
            TFR  F,A            ; palette 1-11, round and round
TAB2        CMPA #11
            BLO  TAB3
            SUBA #11
            BRA  TAB2
TAB3        INCA
            STA  S_COLOR,X
            CMPF #88
            BLO  TAB4
            TFR  F,B            ; one of the row: x = 8 + (n - 88) * 15, y = 440
            SUBB #88
            LDA  #15
            MUL
            ADDD #8
            STD  S_X,X
            LDD  #440
            STD  S_Y,X
TAB4        LEAX 8,X
            INCF
            CMPF #128
            BNE  TAB1
            LDX  #TEXTS2
            JSR  TEXTS
PAGE2       JSR  RING           ; the positions, into the spare table
            LDA  BACKH
            LDX  BACKML
            JSR  PORT0
            LDX  #TABLE2
            LDW  #128*8
            JSR  SENDDAT
            JSR  VBLANK         ; then show it
            LDA  #VC_CFG/$10000
            LDX  #SPR_BASE
            JSR  PORT0
            LDA  BACKH
            STA  VC_DATA0
            LDD  BACKML
            STA  VC_DATA0
            STB  VC_DATA0
            EORB #(TABLEA^TABLEB)&$FF ; and the other one is the spare
            EORA #((TABLEA^TABLEB)/$100)&$FF
            STD  BACKML
            LDA  #VC_CFG/$10000 ; the dots drift down and across
            LDX  #LAYER0+L_HSCROLL
            JSR  PORT0
            LDD  VL_FRAMES
            STA  VC_DATA0
            STB  VC_DATA0
            STA  VC_DATA0
            STB  VC_DATA0
            JSR  GETKEY
            BCS  PAGE2
            JMP  QUIT
BACKH       FCB  TABLEB/$10000  ; the spare table
BACKML      FDB  TABLEB&$FFFF
;------------------------------------------------------------------------------
; BIGTILE: layer 0's entry at column A, row B: a cloud (tile 1, mirrored in
; places) in rows 1-4, hilltops (2) in row 8, hill (3) below.
BIGTILE     CMPB #8
            BLO  BIGT2
            BEQ  BIGT1
            LDD  #3
            RTS
BIGT1       LDD  #2
            RTS
BIGT2       CMPB #1             ; clouds: a row a cloud here and there
            BLO  BIGT9
            CMPB #4
            BHI  BIGT9
            LSLA                ; column * 2 + row * 5, modulo 13
            PSHS A
            LDA  #5
            MUL
            ADDB ,S+
            TFR  B,A
BIGT3       CMPA #13
            BLO  BIGT4
            SUBA #13
            BRA  BIGT3
BIGT4       CMPA #0
            BEQ  BIGT5
            CMPA #6
            BEQ  BIGT6
BIGT9       CLRA
            CLRB
            RTS
BIGT5       LDD  #1
            RTS
BIGT6       LDD  #$0401         ; mirrored across
            RTS
; SMALLTILE: layer 1's entry at column A, row B.
SMALLTILE   CMPB #0
            BNE  SMT1
            LDD  #$D002         ; row 0: dirt (palette 13)
            RTS
SMT1        CMPB #1
            BNE  SMT2
            LDD  #$C801         ; row 1: grass, upside down (flipped down, palette 12)
            RTS
SMT2        CMPB #18            ; row 18: bricks, 8 of every 32 columns
            BNE  SMT3
            TFR  A,B
            ANDB #31
            CMPB #8
            BLO  SMT9
            CMPB #16
            BHS  SMT9
            LDD  #$E003         ; (palette 14)
            RTS
SMT3        CMPB #24            ; row 24: bushes, a tile and its mirror image
            BNE  SMT4
            TFR  A,B
            ANDB #15
            CMPB #3
            BEQ  SMT5
            CMPB #4
            BNE  SMT9
            LDD  #$C404         ; the right half: the left one, flipped across
            RTS
SMT5        LDD  #$C004
            RTS
SMT4        CMPB #25
            BNE  SMT6
            LDD  #$C001         ; row 25: grass
            RTS
SMT6        CMPB #25
            BLO  SMT9
            LDD  #$D002         ; below: dirt
            RTS
SMT9        CLRA
            CLRB
            RTS
;------------------------------------------------------------------------------
; RUN: the runners. Sprite 0 goes back and forth along the ground, facing the
; way it goes; sprite 1 the other way along the ceiling, upside down. Each
; takes a step (the other frame) every 8 pixels.
RUN         LDD  RUNX
            ADDD RUNDX
            CMPD #0
            BGE  RUN1
            LDD  #0
            BRA  RUN2
RUN1        CMPD #320-16
            BLE  RUN3
            LDD  #320-16
RUN2        PSHS D              ; turn round
            LDD  RUNDX
            NEGD
            STD  RUNDX
            PULS D
RUN3        STD  RUNX
            STD  SPRITES1+S_X
            PSHS D
            LDD  #320-16
            SUBD ,S++
            STD  SPRITES1+8+S_X ; the other one, mirror-wise
            LDA  RUNX+1         ; the frame
            ANDA #8
            BEQ  RUN3A
            LDD  #RUNNER2/32
            BRA  RUN4
RUN3A       LDD  #RUNNER/32
RUN4        STD  SPRITES1+S_IMAGE
            STD  SPRITES1+8+S_IMAGE
            LDA  #SS_W16+SS_H16+SS_FRONT
            LDB  RUNDX          ; going left: flipped across
            BPL  RUN5
            ORA  #SS_HFLIP
RUN5        STA  SPRITES1+S_SIZE
            EORA #SS_HFLIP+SS_VFLIP ; the ceiling one: the other way, and down
            STA  SPRITES1+8+S_SIZE
            RTS
RUNX        FDB  40
RUNDX       FDB  1
; FLOAT: the orbs (sprites 2-5) bounce around the screen.
FLOAT       LDU  #SPRITES1+2*8
            LDY  #ORBMOVES
            LDE  #4
FLOAT1      LDB  ,Y             ; across
            SEX
            ADDD S_X,U
            BGE  FLOAT2
            NEG  ,Y
            CLRD
FLOAT2      CMPD 2,Y            ; (the farthest it goes)
            BLE  FLOAT3
            NEG  ,Y
            LDD  2,Y
FLOAT3      STD  S_X,U
            LDB  1,Y            ; down
            SEX
            ADDD S_Y,U
            BGE  FLOAT4
            NEG  1,Y
            CLRD
FLOAT4      CMPD 4,Y
            BLE  FLOAT5
            NEG  1,Y
            LDD  4,Y
FLOAT5      STD  S_Y,U
            LEAU 8,U
            LEAY 6,Y
            DECE
            BNE  FLOAT1
            RTS
; each orb: dx, dy, the farthest x, the farthest y
ORBMOVES    FCB  2,1
            FDB  320-8,240-8
            FCB  -1,2
            FDB  320-16,240-16
            FCB  1,-1
            FDB  320-32,240-32
            FCB  -1,1
            FDB  320-64,240-64
;------------------------------------------------------------------------------
; RING: the 88 sprites of page 2 round two ellipses, the outer one turning one
; way and the inner one the other.
RING        LDX  #TABLE2
            LDA  VL_FRAMES+1
            STA  ANGLE
            LDA  #44
            STA  COUNT
RING1       LDD  #2*290         ; the outer one: 290 across, 170 down (twice:
                                ; PLACE keeps the top 16 bits of RX * sin * 32767)
            STD  RX
            LDD  #2*170
            STD  RY
            BSR  PLACE
            LDA  ANGLE
            ADDA #6
            STA  ANGLE
            DEC  COUNT
            BNE  RING1
            LDA  VL_FRAMES+1
            LSLA
            NEGA
            STA  ANGLE
            LDA  #44
            STA  COUNT
RING2       LDD  #2*180         ; the inner one: 180 across, 100 down
            STD  RX
            LDD  #2*100
            STD  RY
            BSR  PLACE
            LDA  ANGLE
            ADDA #6
            STA  ANGLE
            DEC  COUNT
            BNE  RING2
            RTS
; PLACE: the sprite at X to (312 + RX/2*cos(ANGLE), 190 + RY/2*sin(ANGLE)); X goes on.
PLACE       PSHS X
            LDX  #SINTAB
            LDB  ANGLE
            ADDB #64            ; cos = sin + a quarter turn
            ABX
            ABX
            LDD  ,X
            MULD RX             ; (the product's top 16 bits: RX/2 * cos)
            ADDD #312
            PULS X
            STD  S_X,X
            PSHS X
            LDX  #SINTAB
            LDB  ANGLE
            ABX
            ABX
            LDD  ,X
            MULD RY
            ADDD #190
            PULS X
            STD  S_Y,X
            LEAX 8,X
            RTS
ANGLE       FCB  0
COUNT       FCB  0
RX          FDB  0
RY          FDB  0
;------------------------------------------------------------------------------
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
TEXTS1      FCB  0,0,231,18
            FCN  "  TILES AND SPRITES: THREE LAYERS, SCROLLED AT THEIR OWN SPEEDS               "
            FCB  1,27,231,16
            FCN  "ORBS 8 AND 16: BEHIND THE GROUND. 32: IN FRONT OF IT. 64: IN FRONT OF THIS TOO"
            FCB  0,29,231,18
            FCN  "  A KEY: THE NEXT PAGE                                                          "
            FCB  $FF
TEXTS2      FCB  0,0,231,18
            FCN  "  128 SPRITES AT 640x480, THEIR TABLE DOUBLE-BUFFERED                          "
            FCB  2,26,231,16
            FCN  "THESE 40 SPRITES SHARE THEIR LINES: THE CARD DRAWS THE FIRST 32 OF THEM"
            FCB  0,29,231,18
            FCN  "  A KEY: BACK TO THE SHELL                                                      "
            FCB  $FF
; Page 1's settings from DC_CTRL: all three layers and the sprites, a sky
; blue backdrop, 320x240 sprite coordinates, 6 sprites; then the layers.
SETTINGS1   FCB  $0F,153,0,6
            FCB  VC_SPRITES/$10000,(VC_SPRITES/$100)&$FF,VC_SPRITES&$FF
            FCB  0,0,0,0,0,0,0,0,0
            FCB  LM_TILE+LM_8BPP+LM_BIG,LW_64+LH_32
            FCB  BIGMAP/$10000,(BIGMAP/$100)&$FF,BIGMAP&$FF
            FCB  BIGTILES/$10000,(BIGTILES/$100)&$FF,BIGTILES&$FF
            FDB  0,0,0
            FCB  0,0
            FCB  LM_TILE+LM_2BPP,LW_64+LH_32
            FCB  SMALLMAP/$10000,(SMALLMAP/$100)&$FF,SMALLMAP&$FF
            FCB  SMALLTILES/$10000,(SMALLTILES/$100)&$FF,SMALLTILES&$FF
            FDB  0,0,0
            FCB  0,0
            FCB  LM_TEXT+LM_HIRES+LM_BIG,LW_128+LH_32
            FCB  VC_TEXTMAP/$10000,(VC_TEXTMAP/$100)&$FF,VC_TEXTMAP&$FF
            FCB  VC_FONT/$10000,(VC_FONT/$100)&$FF,VC_FONT&$FF
            FDB  0,0,0
            FCB  0,0
SET1END
; Page 1's pictures, drawn by the card.
PICTURES1   FCB  C_TARGET,(BIGTILES+256)/$10000,((BIGTILES+256)/$100)&$FF,(BIGTILES+256)&$FF
            FDB  16,16,16
            FCB  8              ; tile 1, a cloud
            FCB  C_COLOR,254,C_DISC
            FDB  5,10,4
            FCB  C_DISC
            FDB  11,9,5
            FCB  C_COLOR,231,C_DISC
            FDB  8,8,5
            FCB  C_DISC
            FDB  4,10,3
            FCB  C_TARGET,(BIGTILES+512)/$10000,((BIGTILES+512)/$100)&$FF,(BIGTILES+512)&$FF
            FDB  16,16,16
            FCB  8              ; tile 2, a hilltop
            FCB  C_COLOR,65,C_TRIANGLE
            FDB  -1,15,7,3,16,15
            FCB  C_COLOR,71,C_LINE
            FDB  7,3,1,9
            FCB  C_TARGET,(BIGTILES+768)/$10000,((BIGTILES+768)/$100)&$FF,(BIGTILES+768)&$FF
            FDB  16,16,16
            FCB  8              ; tile 3, hill
            FCB  C_COLOR,65,C_CLEAR
            FCB  C_COLOR,71,C_PLOT
            FDB  3,4
            FCB  C_PLOT
            FDB  11,10
            FCB  C_TARGET,(SMALLTILES+16)/$10000,((SMALLTILES+16)/$100)&$FF,(SMALLTILES+16)&$FF
            FDB  2,8,8
            FCB  2              ; tile 1: grass (2 bits a pixel: 1 dark, 2 mid, 3 light)
            FCB  C_COLOR,2,C_FILLRECT
            FDB  0,3,8,5
            FCB  C_COLOR,1,C_LINE
            FDB  0,7,7,7
            FCB  C_PLOT
            FDB  2,5
            FCB  C_PLOT
            FDB  6,4
            FCB  C_COLOR,3,C_PLOT
            FDB  0,2
            FCB  C_PLOT
            FDB  2,1
            FCB  C_PLOT
            FDB  3,2
            FCB  C_PLOT
            FDB  5,0
            FCB  C_PLOT
            FDB  6,1
            FCB  C_PLOT
            FDB  7,2
            FCB  C_TARGET,(SMALLTILES+32)/$10000,((SMALLTILES+32)/$100)&$FF,(SMALLTILES+32)&$FF
            FDB  2,8,8
            FCB  2              ; tile 2: dirt
            FCB  C_COLOR,1,C_CLEAR
            FCB  C_COLOR,2,C_PLOT
            FDB  1,1
            FCB  C_PLOT
            FDB  5,3
            FCB  C_PLOT
            FDB  2,6
            FCB  C_COLOR,3,C_PLOT
            FDB  6,6
            FCB  C_PLOT
            FDB  3,3
            FCB  C_TARGET,(SMALLTILES+48)/$10000,((SMALLTILES+48)/$100)&$FF,(SMALLTILES+48)&$FF
            FDB  2,8,8
            FCB  2              ; tile 3: bricks
            FCB  C_COLOR,1,C_CLEAR
            FCB  C_COLOR,2,C_FILLRECT
            FDB  0,0,3,3
            FCB  C_FILLRECT
            FDB  4,0,3,3
            FCB  C_FILLRECT
            FDB  0,4,1,3
            FCB  C_FILLRECT
            FDB  2,4,3,3
            FCB  C_FILLRECT
            FDB  6,4,2,3
            FCB  C_COLOR,3,C_LINE
            FDB  0,0,2,0
            FCB  C_LINE
            FDB  4,0,6,0
            FCB  C_TARGET,(SMALLTILES+64)/$10000,((SMALLTILES+64)/$100)&$FF,(SMALLTILES+64)&$FF
            FDB  2,8,8
            FCB  2              ; tile 4: the left half of a bush
            FCB  C_COLOR,1,C_DISC
            FDB  7,7,7
            FCB  C_COLOR,2,C_DISC
            FDB  6,6,5
            FCB  C_COLOR,3,C_DISC
            FDB  5,4,2
            FCB  C_TARGET,RUNNER/$10000,(RUNNER/$100)&$FF,RUNNER&$FF
            FDB  8,16,16
            FCB  4              ; the runner, frame 1 (colors 1-3 of palette 15)
            FCB  C_COLOR,1,C_DISC
            FDB  8,3,3
            FCB  C_FILLRECT
            FDB  7,6,3,5
            FCB  C_LINE
            FDB  4,8,12,6
            FCB  C_COLOR,2,C_LINE
            FDB  8,11,5,15
            FCB  C_LINE
            FDB  9,11,12,15
            FCB  C_COLOR,3,C_PLOT
            FDB  9,2
            FCB  C_TARGET,RUNNER2/$10000,(RUNNER2/$100)&$FF,RUNNER2&$FF
            FDB  8,16,16
            FCB  4              ; frame 2: the legs together
            FCB  C_COLOR,1,C_DISC
            FDB  8,3,3
            FCB  C_FILLRECT
            FDB  7,6,3,5
            FCB  C_LINE
            FDB  5,7,11,7
            FCB  C_COLOR,2,C_LINE
            FDB  8,11,8,15
            FCB  C_LINE
            FDB  9,11,10,15
            FCB  C_COLOR,3,C_PLOT
            FDB  9,2
            FCB  C_TARGET,ORB8/$10000,(ORB8/$100)&$FF,ORB8&$FF
            FDB  4,8,8
            FCB  4              ; the orbs: a disc, a ring, a shine
            FCB  C_COLOR,1,C_DISC
            FDB  3,3,3
            FCB  C_COLOR,3,C_PLOT
            FDB  2,2
            FCB  C_TARGET,ORB16/$10000,(ORB16/$100)&$FF,ORB16&$FF
            FDB  8,16,16
            FCB  4
            FCB  C_COLOR,1,C_DISC
            FDB  7,7,7
            FCB  C_COLOR,2,C_CIRCLE
            FDB  7,7,7
            FCB  C_COLOR,3,C_DISC
            FDB  5,5,1
            FCB  C_TARGET,ORB32/$10000,(ORB32/$100)&$FF,ORB32&$FF
            FDB  16,32,32
            FCB  4
            FCB  C_COLOR,1,C_DISC
            FDB  15,15,15
            FCB  C_COLOR,2,C_CIRCLE
            FDB  15,15,15
            FCB  C_CIRCLE
            FDB  15,15,10
            FCB  C_COLOR,3,C_DISC
            FDB  10,10,3
            FCB  C_TARGET,ORB64/$10000,(ORB64/$100)&$FF,ORB64&$FF
            FDB  32,64,64
            FCB  4
            FCB  C_COLOR,1,C_DISC
            FDB  31,31,31
            FCB  C_COLOR,2,C_CIRCLE
            FDB  31,31,31
            FCB  C_CIRCLE
            FDB  31,31,24
            FCB  C_CIRCLE
            FDB  31,31,17
            FCB  C_COLOR,3,C_DISC
            FDB  20,20,6
PIC1END
; Page 1's sprites: the two runners, then the orbs (palettes 1, 5, 7, 11).
SPRITES1    FDB  RUNNER/32,40,200-16
            FCB  SS_W16+SS_H16+SS_FRONT,15
            FDB  RUNNER/32,240,16
            FCB  SS_W16+SS_H16+SS_FRONT+SS_VFLIP,15
            FDB  ORB8/32,30,60
            FCB  SS_W8+SS_H8+SS_BACK,1
            FDB  ORB16/32,120,150
            FCB  SS_W16+SS_H16+SS_BACK,5
            FDB  ORB32/32,200,40
            FCB  SS_W32+SS_H32+SS_MID,7
            FDB  ORB64/32,60,90
            FCB  SS_W64+SS_H64+SS_FRONT,11
; Page 2's settings: layers 0 and 2 and the sprites, 640x480 sprite
; coordinates, 128 of them from TABLEA; layer 0 hires tiles of 1 bit a pixel.
SETTINGS2   FCB  $0D,16,1,128
            FCB  TABLEA/$10000,(TABLEA/$100)&$FF,TABLEA&$FF
            FCB  0,0,0,0,0,0,0,0,0
            FCB  LM_TILE+LM_HIRES+LM_1BPP,LW_128+LH_64
            FCB  DOTMAP/$10000,(DOTMAP/$100)&$FF,DOTMAP&$FF
            FCB  DOTTILES/$10000,(DOTTILES/$100)&$FF,DOTTILES&$FF
            FDB  0,0,0
            FCB  0,0
            FCB  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
            FCB  LM_TEXT+LM_HIRES+LM_BIG,LW_128+LH_32
            FCB  VC_TEXTMAP/$10000,(VC_TEXTMAP/$100)&$FF,VC_TEXTMAP&$FF
            FCB  VC_FONT/$10000,(VC_FONT/$100)&$FF,VC_FONT&$FF
            FDB  0,0,0
            FCB  0,0
SET2END
PICTURES2   FCB  C_TARGET,(DOTTILES+8)/$10000,((DOTTILES+8)/$100)&$FF,(DOTTILES+8)&$FF
            FDB  1,8,8
            FCB  1              ; the dot tile: a plus sign
            FCB  C_COLOR,1,C_PLOT
            FDB  3,3
            FCB  C_PLOT
            FDB  2,3
            FCB  C_PLOT
            FDB  4,3
            FCB  C_PLOT
            FDB  3,2
            FCB  C_PLOT
            FDB  3,4
            FCB  C_TARGET,STAR/$10000,(STAR/$100)&$FF,STAR&$FF
            FDB  8,16,16
            FCB  4              ; the sprites' image
            FCB  C_COLOR,1,C_DISC
            FDB  7,7,7
            FCB  C_COLOR,2,C_DISC
            FDB  7,7,4
            FCB  C_COLOR,3,C_DISC
            FDB  6,6,1
PIC2END
; The tiles' and runner's colors: entry, RGB565 (0 ends the list).
PALETTE1    FCB  193
            FDB  $12C2
            FCB  194
            FDB  $2CA5
            FCB  195
            FDB  $7EEB
            FCB  209
            FDB  $59A3
            FCB  210
            FDB  $82A5
            FCB  211
            FDB  $ABC8
            FCB  225
            FDB  $CDF5
            FCB  226
            FDB  $A9E5
            FCB  227
            FDB  $DB6A
            FCB  241
            FDB  $F647
            FCB  242
            FDB  $39F9
            FCB  243
            FDB  $FFFF
            FCB  0
; sin(i * 360 / 256) * 32767, for i = 0..255 (cos(i) is sin(i + 64)).
SINTAB      FDB  0,804,1608,2410,3212,4011,4808,5602
            FDB  6393,7179,7962,8739,9512,10278,11039,11793
            FDB  12539,13279,14010,14732,15446,16151,16846,17530
            FDB  18204,18868,19519,20159,20787,21403,22005,22594
            FDB  23170,23731,24279,24811,25329,25832,26319,26790
            FDB  27245,27683,28105,28510,28898,29268,29621,29956
            FDB  30273,30571,30852,31113,31356,31580,31785,31971
            FDB  32137,32285,32412,32521,32609,32678,32728,32757
            FDB  32767,32757,32728,32678,32609,32521,32412,32285
            FDB  32137,31971,31785,31580,31356,31113,30852,30571
            FDB  30273,29956,29621,29268,28898,28510,28105,27683
            FDB  27245,26790,26319,25832,25329,24811,24279,23731
            FDB  23170,22594,22005,21403,20787,20159,19519,18868
            FDB  18204,17530,16846,16151,15446,14732,14010,13279
            FDB  12539,11793,11039,10278,9512,8739,7962,7179
            FDB  6393,5602,4808,4011,3212,2410,1608,804
            FDB  0,-804,-1608,-2410,-3212,-4011,-4808,-5602
            FDB  -6393,-7179,-7962,-8739,-9512,-10278,-11039,-11793
            FDB  -12539,-13279,-14010,-14732,-15446,-16151,-16846,-17530
            FDB  -18204,-18868,-19519,-20159,-20787,-21403,-22005,-22594
            FDB  -23170,-23731,-24279,-24811,-25329,-25832,-26319,-26790
            FDB  -27245,-27683,-28105,-28510,-28898,-29268,-29621,-29956
            FDB  -30273,-30571,-30852,-31113,-31356,-31580,-31785,-31971
            FDB  -32137,-32285,-32412,-32521,-32609,-32678,-32728,-32757
            FDB  -32767,-32757,-32728,-32678,-32609,-32521,-32412,-32285
            FDB  -32137,-31971,-31785,-31580,-31356,-31113,-30852,-30571
            FDB  -30273,-29956,-29621,-29268,-28898,-28510,-28105,-27683
            FDB  -27245,-26790,-26319,-25832,-25329,-24811,-24279,-23731
            FDB  -23170,-22594,-22005,-21403,-20787,-20159,-19519,-18868
            FDB  -18204,-17530,-16846,-16151,-15446,-14732,-14010,-13279
            FDB  -12539,-11793,-11039,-10278,-9512,-8739,-7962,-7179
            FDB  -6393,-5602,-4808,-4011,-3212,-2410,-1608,-804
; Page 2's sprite table, as it is built.
TABLE2      RMB  128*8

            END  START
