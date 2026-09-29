;------------------------------------------------------------------------------
; PROJECT: VIDEO CARD DEMO
;    FILE: viddemo.asm
;
; The video card's three layers, its sprites and its drawing commands, all at
; once (see VIDCARD.D, and the card's description in VIDCARD.TXT):
;
;   layer 0  a 320x240 bitmap, 8 bits a pixel, drawn with commands: a sky,
;            a sun, mountains and a grid
;   layer 1  a tile map (4 bits a pixel, 8x8 tiles) with one row of beads,
;            scrolled a pixel a frame
;   layer 2  the 80x30 text screen the card starts with, for the words
;   sprites  eight balls, drawn with commands too, bouncing around
;
; ON THE PUGPUTER 6309 (and in its emulator, which shows the card in a window):
;
;   ASM -f com viddemo.asm         makes VIDDEMO.COM
;   VIDDEMO                        runs it; any key stops it
;------------------------------------------------------------------------------
            INCLUDE "vidcard.d"
F_STDIN     equ  $02        ; the BIOS calls used (see /ASM/DEFINES.D)
B_GETC      equ  $0C
B_EXIT      equ  $2B

NBALLS      equ  8
TILEMAP     equ  $014000    ; layer 1's map, 64x32 entries of 2 bytes
TILES       equ  $015000    ; layer 1's tiles, 32 bytes each
BALLS       equ  $016000    ; the balls' images: 16x16, 8 bits a pixel, 256 bytes each
BEADROW     equ  3          ; the tile row with the beads
;------------------------------------------------------------------------------
            ORG  $4000
START       LDA  #$80
            STA  VC_CTRL        ; the card as it starts
; The display settings, all at once.
            LDA  #VC_CFG/$10000
            LDX  #VC_CFG&$FFFF
            JSR  PORT0
            LDX  #SETTINGS
            LDY  #VC_DATA0
            LDW  #SETTEND-SETTINGS
            TFM  X+,Y
; The bitmap and the tile, drawn by the card.
            LDX  #SCENE
            LDW  #SCENEEND-SCENE
            JSR  COMMANDS
; The balls: a disc each in its color, with a white shine.
            LDU  #BALLCOLS
            LDA  #(BALLS/$100)&$FF
BALL        LDB  #C_TARGET
            STB  VC_CMD
            LDB  #BALLS/$10000
            STB  VC_CMD
            STA  VC_CMD         ; this one's address: 256 bytes on from the last
            CLRB
            STB  VC_CMD
            LDX  #BALLTGT
            LDW  #BALLTEND-BALLTGT
            JSR  COMMANDS
            LDB  ,U+
            STB  VC_CMD         ; (the color the last command asks for)
            LDX  #BALLPIC
            LDW  #BALLPEND-BALLPIC
            JSR  COMMANDS
            INCA
            CMPA #((BALLS/$100)&$FF)+NBALLS
            BNE  BALL
; The beads: tile 1 in every other column of one row, in eight palettes.
            LDA  #TILEMAP/$10000
            LDX  #(TILEMAP&$FFFF)+BEADROW*64*2
            JSR  PORT0
            CLRE                ; the column
MAP         TFR  E,A
            BITA #1
            BNE  MAPGAP
            LSRA
            ANDA #7
            ADDA #6             ; palettes 6-13
            LSLA
            LSLA
            LSLA
            LSLA                ; (the entry's top 4 bits)
            LDB  #1             ; tile 1
            BRA  MAPPUT
MAPGAP      CLRA                ; tile 0: nothing
            CLRB
MAPPUT      STA  VC_DATA0
            STB  VC_DATA0
            INCE
            CMPE #64
            BNE  MAP
; The words, on the text layer.
            LDA  #VC_TEXTMAP/$10000
            LDX  #(VC_TEXTMAP&$FFFF)+(1*128+27)*4
            JSR  PORT0
            LDX  #TITLE
            LDB  #231           ; white
            JSR  PRINT
            LDA  #VC_TEXTMAP/$10000
            LDX  #(VC_TEXTMAP&$FFFF)+(28*128+29)*4
            JSR  PORT0
            LDX  #QUIT
            LDB  #250           ; light gray
            JSR  PRINT
;------------------------------------------------------------------------------
; Each frame: wait for vertical blank, scroll the beads, move the balls.
;------------------------------------------------------------------------------
LOOP        LDA  VC_ISR
            BITA #VC_I_VSYNC
            BEQ  LOOP
            LDA  #VC_I_VSYNC
            STA  VC_ISR         ; (a 1 clears the flag)
            LDA  #VC_CFG/$10000
            LDX  #LAYER1+L_HSCROLL
            JSR  PORT1
            LDD  SCROLL
            ADDD #1
            STD  SCROLL
            STA  VC_DATA1
            STB  VC_DATA1
            LDU  #SPRITES
            LDY  #SPEEDS
            LDE  #NBALLS
MOVE        LDB  ,Y             ; across: bounce off the sides
            SEX
            ADDD S_X,U
            BGE  MOVEX1
            NEG  ,Y
            CLRD
            BRA  MOVEX2
MOVEX1      CMPD #320-16
            BLE  MOVEX2
            NEG  ,Y
            LDD  #320-16
MOVEX2      STD  S_X,U
            LDB  1,Y            ; down: bounce off the top and the bottom
            SEX
            ADDD S_Y,U
            BGE  MOVEY1
            NEG  1,Y
            CLRD
            BRA  MOVEY2
MOVEY1      CMPD #240-16
            BLE  MOVEY2
            NEG  1,Y
            LDD  #240-16
MOVEY2      STD  S_Y,U
            LEAU 8,U
            LEAY 2,Y
            DECE
            BNE  MOVE
            LDA  #VC_SPRITES/$10000
            LDX  #VC_SPRITES&$FFFF
            JSR  PORT1
            LDX  #SPRITES       ; the sprite table, all at once
            LDY  #VC_DATA1
            LDW  #NBALLS*8
            TFM  X+,Y
            LDB  #F_STDIN       ; a key?
            LDA  #B_GETC
            SWI2
            LBCS LOOP
            LDA  #$80           ; yes: the card as it started, and back to the shell
            STA  VC_CTRL
            LDA  #B_EXIT
            SWI2
;------------------------------------------------------------------------------
; PORT0, PORT1: point a data port at A:X (the address's bits 23-16, 15-0), step 1.
PORT0       STA  VC_ADDR0
            STX  VC_ADDR0M
            LDD  #1
            STD  VC_INC0
            RTS
PORT1       STA  VC_ADDR1
            STX  VC_ADDR1M
            LDD  #1
            STD  VC_INC1
            RTS
; COMMANDS: sends W bytes at X to the card's command port.
COMMANDS    LDY  #VC_CMD
            TFM  X+,Y
            RTS
; PRINT: the string at X (0 at its end) into text cells from port 0 on, in color
; B on black.
PRINT       LDA  ,X+
            BEQ  PRINTED
            STA  VC_DATA0       ; the character
            STB  VC_DATA0       ; its color
            LDA  #16
            STA  VC_DATA0       ; the background: black (16, as 0 is see-through)
            CLRA
            STA  VC_DATA0
            BRA  PRINT
PRINTED     RTS
;------------------------------------------------------------------------------
SCROLL      FDB  0
TITLE       FCN  " PUGPUTER 6309 VIDEO CARD "
QUIT        FCN  " PRESS ANY KEY TO QUIT "

; The settings, from VC_CFG on: 64 bytes.
SETTINGS    FCB  $0F            ; DC_CTRL: layers 0-2 and the sprites on
            FCB  0              ; DC_BACK
            FCB  0              ; SPR_CTRL: 320x240 coordinates
            FCB  NBALLS         ; SPR_COUNT
            FCB  VC_SPRITES/$10000,(VC_SPRITES/$100)&$FF,VC_SPRITES&$FF
            FCB  0,0,0,0,0,0,0,0,0
; layer 0: the 320x240 bitmap at 0
            FCB  LM_BITMAP+LM_8BPP,0
            FCB  0,0,0,0,0,0
            FDB  0,0,320
            FCB  0,0
; layer 1: 64x32 tiles
            FCB  LM_TILE+LM_4BPP,LW_64+LH_32
            FCB  TILEMAP/$10000,(TILEMAP/$100)&$FF,TILEMAP&$FF
            FCB  TILES/$10000,(TILES/$100)&$FF,TILES&$FF
            FDB  0,0,0
            FCB  0,0
; layer 2: the text screen, in front
            FCB  LM_TEXT+LM_HIRES+LM_BIG,LW_128+LH_32
            FCB  VC_TEXTMAP/$10000,(VC_TEXTMAP/$100)&$FF,VC_TEXTMAP&$FF
            FCB  VC_FONT/$10000,(VC_FONT/$100)&$FF,VC_FONT&$FF
            FDB  0,0,0
            FCB  0,0
SETTEND

; The pictures, as drawing commands.
SCENE       FCB  C_TARGET,0,0,0 ; the bitmap
            FDB  320,320,240
            FCB  8
; the sky: 15 bands, from deep blue down to pink
            FCB  C_COLOR,17,C_FILLRECT
            FDB  0,0,320,10
            FCB  C_COLOR,18,C_FILLRECT
            FDB  0,10,320,10
            FCB  C_COLOR,19,C_FILLRECT
            FDB  0,20,320,10
            FCB  C_COLOR,54,C_FILLRECT
            FDB  0,30,320,10
            FCB  C_COLOR,55,C_FILLRECT
            FDB  0,40,320,10
            FCB  C_COLOR,56,C_FILLRECT
            FDB  0,50,320,10
            FCB  C_COLOR,91,C_FILLRECT
            FDB  0,60,320,10
            FCB  C_COLOR,92,C_FILLRECT
            FDB  0,70,320,10
            FCB  C_COLOR,127,C_FILLRECT
            FDB  0,80,320,10
            FCB  C_COLOR,128,C_FILLRECT
            FDB  0,90,320,10
            FCB  C_COLOR,163,C_FILLRECT
            FDB  0,100,320,10
            FCB  C_COLOR,164,C_FILLRECT
            FDB  0,110,320,10
            FCB  C_COLOR,199,C_FILLRECT
            FDB  0,120,320,10
            FCB  C_COLOR,200,C_FILLRECT
            FDB  0,130,320,10
            FCB  C_COLOR,205,C_FILLRECT
            FDB  0,140,320,10
; the sun, striped by the sky
            FCB  C_COLOR,214,C_DISC
            FDB  160,116,44
            FCB  C_COLOR,199,C_FILLRECT
            FDB  110,124,100,2
            FCB  C_COLOR,200,C_FILLRECT
            FDB  110,132,100,3
            FCB  C_COLOR,205,C_FILLRECT
            FDB  110,141,100,4
; mountains
            FCB  C_COLOR,90,C_TRIANGLE
            FDB  -20,150,40,108,110,150
            FCB  C_TRIANGLE
            FDB  60,150,95,126,130,150
            FCB  C_TRIANGLE
            FDB  210,150,275,102,340,150
; the ground, and its grid
            FCB  C_COLOR,16,C_FILLRECT
            FDB  0,150,320,90
            FCB  C_COLOR,201,C_LINE
            FDB  0,150,319,150
            FCB  C_LINE
            FDB  0,152,319,152
            FCB  C_LINE
            FDB  0,155,319,155
            FCB  C_LINE
            FDB  0,159,319,159
            FCB  C_LINE
            FDB  0,164,319,164
            FCB  C_LINE
            FDB  0,170,319,170
            FCB  C_LINE
            FDB  0,177,319,177
            FCB  C_LINE
            FDB  0,185,319,185
            FCB  C_LINE
            FDB  0,194,319,194
            FCB  C_LINE
            FDB  0,204,319,204
            FCB  C_LINE
            FDB  0,215,319,215
            FCB  C_LINE
            FDB  0,227,319,227
            FCB  C_LINE
            FDB  0,239,319,239
            FCB  C_LINE
            FDB  104,150,-288,239
            FCB  C_LINE
            FDB  112,150,-224,239
            FCB  C_LINE
            FDB  120,150,-160,239
            FCB  C_LINE
            FDB  128,150,-96,239
            FCB  C_LINE
            FDB  136,150,-32,239
            FCB  C_LINE
            FDB  144,150,32,239
            FCB  C_LINE
            FDB  152,150,96,239
            FCB  C_LINE
            FDB  160,150,160,239
            FCB  C_LINE
            FDB  168,150,224,239
            FCB  C_LINE
            FDB  176,150,288,239
            FCB  C_LINE
            FDB  184,150,352,239
            FCB  C_LINE
            FDB  192,150,416,239
            FCB  C_LINE
            FDB  200,150,480,239
            FCB  C_LINE
            FDB  208,150,544,239
            FCB  C_LINE
            FDB  216,150,608,239
; tile 1, a bead: 8x8, 4 bits a pixel (so 4 bytes a row)
            FCB  C_TARGET,(TILES+32)/$10000,((TILES+32)/$100)&$FF,(TILES+32)&$FF
            FDB  4,8,8
            FCB  4
            FCB  C_COLOR,1,C_DISC
            FDB  3,3,3
            FCB  C_COLOR,2,C_DISC
            FDB  2,2,1
SCENEEND

; A ball's target, after its address (16x16, 8 bits a pixel), and COLOR.
BALLTGT     FDB  16,16,16
            FCB  8,C_COLOR
BALLTEND
; ... then its color, and this.
BALLPIC     FCB  C_DISC
            FDB  7,7,7
            FCB  C_COLOR,231,C_DISC
            FDB  5,5,2
BALLPEND
BALLCOLS    FCB  196,208,226,46,51,33,129,201

; The sprite table as the card is to have it, and how fast each ball goes.
SPRITES     FDB  BALLS/32+0*8,20,30
            FCB  SS_W16+SS_H16+SS_FRONT,SC_8BPP
            FDB  BALLS/32+1*8,60,90
            FCB  SS_W16+SS_H16+SS_FRONT,SC_8BPP
            FDB  BALLS/32+2*8,100,40
            FCB  SS_W16+SS_H16+SS_FRONT,SC_8BPP
            FDB  BALLS/32+3*8,140,160
            FCB  SS_W16+SS_H16+SS_FRONT,SC_8BPP
            FDB  BALLS/32+4*8,180,70
            FCB  SS_W16+SS_H16+SS_FRONT,SC_8BPP
            FDB  BALLS/32+5*8,220,120
            FCB  SS_W16+SS_H16+SS_FRONT,SC_8BPP
            FDB  BALLS/32+6*8,260,200
            FCB  SS_W16+SS_H16+SS_FRONT,SC_8BPP
            FDB  BALLS/32+7*8,290,20
            FCB  SS_W16+SS_H16+SS_FRONT,SC_8BPP
SPEEDS      FCB  2,1,-1,2,3,-2,-2,-1,1,3,-3,1,2,-2,-1,-3

            END  START
