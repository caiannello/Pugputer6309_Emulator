;------------------------------------------------------------------------------
; PROJECT: VIDEO CARD DEMOS
;    FILE: vidtext.asm
;
; The video card's text layers, in two pages (a key goes on to the next;
; after the last, back to the shell):
;
;   1  the 256 characters of the font and the 256 colors, framed with the
;      font's box-drawing characters (80x30 cells of 8x16, hires); over them a
;      second text layer at 320x240 -- every pixel doubled -- scrolls a
;      marquee across, each letter its own color on a see-through background;
;      and what the card says its ID and version are, read from its registers
;   2  an 8x8 font the program makes from the card's own 8x16 one (reading it
;      back through a data port), for an 80x60 text layer that scrolls up a
;      pixel a frame, under a heading and a footer on a second layer that
;      stays put
;
;   ASM -f com vidtext.asm         makes VIDTEXT.COM
;------------------------------------------------------------------------------
            INCLUDE "VIDCARD.D"

MARQMAP     equ  $030000    ; page 1's marquee layer: a 64x32 cell map
MARQROW     equ  11         ; its row (lores: hires rows 22 and 23)
FONT8       equ  $03E000    ; page 2's 8x8 font
ROLLMAP     equ  $020000    ; page 2's rolling text: a 128x64 cell map
;------------------------------------------------------------------------------
            ORG  $4000
START       LDA  #$80
            STA  VC_CTRL        ; the card as it starts: the 80x30 text screen
;------------------------------------------------------------------------------
; Page 1: the characters and the colors.
;------------------------------------------------------------------------------
            LDA  #VC_CFG/$10000 ; layer 1: the marquee, lores text, 64x32 cells
            LDX  #LAYER1
            JSR  PORT0
            LDX  #MARQLAYER
            LDW  #16
            JSR  SENDDAT
            LDA  #VC_CFG/$10000
            LDX  #DC_CTRL
            JSR  PORT0
            LDA  #$03           ; layers 0 and 1 on
            STA  VC_DATA0
            LDX  #TEXTS1        ; the words
            JSR  TEXTS
            JSR  FRAMES         ; the two boxes
; The characters: 16 rows of 16, each followed by a space.
            CLRF                ; the character
CHARROW     TFR  F,B
            LSRB
            LSRB
            LSRB
            LSRB
            ADDB #4             ; row 4 + char / 16
            LDA  #5             ; from column 5
            JSR  TEXTAT
            LDE  #16            ; 16 of them
CHARCOL     STF  VC_DATA0       ; the character, in white on black
            LDA  #15
            STA  VC_DATA0
            LDA  #16
            STA  VC_DATA0
            CLRA
            STA  VC_DATA0
            LDA  #$20
            STA  VC_DATA0       ; and a space
            LDA  #15
            STA  VC_DATA0
            LDA  #16
            STA  VC_DATA0
            CLRA
            STA  VC_DATA0
            INCF
            DECE
            BNE  CHARCOL
            TSTF
            BNE  CHARROW
; The colors: 16 rows of 16, each a cell of two spaces in that background.
            CLRF                ; the color
COLROW      TFR  F,B
            LSRB
            LSRB
            LSRB
            LSRB
            ADDB #4
            LDA  #44            ; from column 44
            JSR  TEXTAT
            LDE  #16
COLCOL      LDB  #2
COLCELL     LDA  #$20
            STA  VC_DATA0
            LDA  #15
            STA  VC_DATA0
            STF  VC_DATA0       ; background: this color
            CLRA
            STA  VC_DATA0
            DECB
            BNE  COLCELL
            INCF
            DECE
            BNE  COLCOL
            TSTF
            BNE  COLROW
; The card's own ID and version, after "THE CARD SAYS" (row 26).
            LDA  #23
            LDB  #26
            JSR  TEXTAT
            LDA  VC_ID          ; its ID ...
            JSR  YELLOW
            LDX  #VERSION
            LDB  #250
            LDE  #0
            JSR  PRINT
            LDA  VC_VERSION     ; ... and version: $10 is 1.0
            LSRA
            LSRA
            LSRA
            LSRA
            ADDA #'0
            JSR  YELLOW
            LDA  #'.
            JSR  YELLOW
            LDA  VC_VERSION
            ANDA #$0F
            ADDA #'0
            JSR  YELLOW
; The marquee: its words on layer 1, each letter in the next color of a
; rainbow, on background 0 (see-through).
            LDA  #MARQMAP/$10000
            LDX  #(MARQMAP&$FFFF)+MARQROW*64*4
            JSR  PORT0
            LDX  #MARQUEE
            LDU  #RAINBOW
MARQ1       LDA  ,X+
            BEQ  MARQ3
            STA  VC_DATA0
            LDA  ,U+
            BNE  MARQ2
            LDU  #RAINBOW
            LDA  ,U+
MARQ2       STA  VC_DATA0
            CLRA
            STA  VC_DATA0
            STA  VC_DATA0
            BRA  MARQ1
MARQ3       CLRW                ; scroll it a pixel a frame, until a key
PAGE1       JSR  VBLANK
            INCW
            LDA  #VC_CFG/$10000
            LDX  #LAYER1+L_HSCROLL
            JSR  PORT0
            STE  VC_DATA0
            STF  VC_DATA0
            PSHSW
            JSR  GETKEY
            PULSW
            BCS  PAGE1
;------------------------------------------------------------------------------
; Page 2: an 8x8 font, made from the 8x16 one, and 80x60 cells rolling up.
;------------------------------------------------------------------------------
            LDA  #$80
            STA  VC_CTRL
; Each 8x8 character is the 16-line one with every two lines ORed into one:
; read through port 0 (a read steps on too), written through port 1.
            LDA  #VC_FONT/$10000
            LDX  #VC_FONT&$FFFF
            JSR  PORT0
            LDA  #FONT8/$10000
            STA  VC_ADDR1
            LDX  #FONT8&$FFFF
            STX  VC_ADDR1M
            LDX  #1
            STX  VC_INC1
            LDX  #256*8         ; 8 lines of 256 characters
SQUASH      LDA  VC_DATA0
            ORA  VC_DATA0
            STA  VC_DATA1
            LEAX -1,X
            BNE  SQUASH
; Layer 0: 80x60 cells of it (a 128x64 map), rolling; layer 1: the 8x16
; heading and footer (the card's own text screen), still.
            LDA  #VC_CFG/$10000
            LDX  #DC_CTRL
            JSR  PORT0
            LDX  #PAGE2SET
            LDW  #PAGE2END-PAGE2SET
            JSR  SENDDAT
            LDA  #VC_CFG/$10000
            LDX  #LAYER1
            JSR  PORT0
            LDX  #TEXTLAYER
            LDW  #16
            JSR  SENDDAT
; The words: the lines of ROLLTEXT down the map's 64 rows, over and over, in
; colors that change from line to line.
            LDA  #ROLLMAP/$10000
            STA  VL_MAPH
            LDX  #ROLLMAP&$FFFF
            STX  VL_MAP
            LDX  #ROLLTEXT
            LDU  #RAINBOW       ; the lines' colors
            CLRB                ; the row
ROLL1       PSHS B,X
            LDA  #4
            JSR  TEXTAT
            PULS B,X
            PSHS B
            LDB  ,U+            ; its color: the next of the rainbow
            BNE  ROLL1A
            LDU  #RAINBOW
            LDB  ,U+
ROLL1A      LDE  #0
            JSR  PRINT          ; (X goes on to the next line)
            LDA  ,X
            CMPA #$FF
            BNE  ROLL2
            LDX  #ROLLTEXT      ; the end: from the top again
ROLL2       PULS B
            INCB
            CMPB #64
            BNE  ROLL1
            LDA  #VC_TEXTMAP/$10000
            STA  VL_MAPH
            LDX  #VC_TEXTMAP&$FFFF
            STX  VL_MAP
            LDX  #TEXTS2        ; the heading and the footer
            JSR  TEXTS
            CLRW                ; roll up a pixel a frame, until a key
PAGE2       JSR  VBLANK
            INCW
            LDA  #VC_CFG/$10000
            LDX  #LAYER0+L_VSCROLL
            JSR  PORT0
            STE  VC_DATA0
            STF  VC_DATA0
            PSHSW
            JSR  GETKEY
            PULSW
            BCS  PAGE2
            JMP  QUIT
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
; YELLOW: the character in A, yellow on see-through, at port 0.
YELLOW      STA  VC_DATA0
            LDA  #226
            STA  VC_DATA0
            CLRA
            STA  VC_DATA0
            STA  VC_DATA0
            RTS
; FRAMES: the two boxes on page 1, drawn with the font's box characters.
FRAMES      LDX  #BOXES
FRAME1      LDA  ,X+            ; column, top row, width, height inside
            CMPA #$FF
            LBEQ FRAME9
            STA  FCOL
            LDA  ,X+
            STA  FTOP
            LDA  ,X+
            STA  FWIDTH
            LDA  ,X+
            STA  FHEIGHT
            PSHS X
            LDA  FCOL           ; the top: a corner, a line, a corner
            LDB  FTOP
            JSR  TEXTAT
            LDA  #$C9
            BSR  FCELL
            LDB  FWIDTH
FRAME2      LDA  #$CD
            BSR  FCELL
            DECB
            BNE  FRAME2
            LDA  #$BB
            BSR  FCELL
            LDB  FHEIGHT        ; the sides
            STB  FROW
FRAME3      LDB  FTOP
            ADDB FROW
            PSHS B
            LDA  FCOL
            JSR  TEXTAT
            LDA  #$BA
            BSR  FCELL
            PULS B
            LDA  FCOL
            ADDA FWIDTH
            INCA
            JSR  TEXTAT
            LDA  #$BA
            BSR  FCELL
            DEC  FROW
            BNE  FRAME3
            LDA  FCOL           ; the bottom
            LDB  FTOP
            ADDB FHEIGHT
            INCB
            JSR  TEXTAT
            LDA  #$C8
            BSR  FCELL
            LDB  FWIDTH
FRAME4      LDA  #$CD
            BSR  FCELL
            DECB
            BNE  FRAME4
            LDA  #$BC
            BSR  FCELL
            PULS X
            LBRA FRAME1
FRAME9      RTS
; FCELL: the character in A, in light blue on black, at port 0.
FCELL       STA  VC_DATA0
            LDA  #75
            STA  VC_DATA0
            LDA  #16
            STA  VC_DATA0
            CLRA
            STA  VC_DATA0
            RTS
FCOL        FCB  0
FTOP        FCB  0
FWIDTH      FCB  0
FHEIGHT     FCB  0
FROW        FCB  0
;------------------------------------------------------------------------------
            INCLUDE "VIDLIB.ASM"
;------------------------------------------------------------------------------
; Page 1's words: column, row, color, background, text.
TEXTS1      FCB  0,0,231,18
            FCN  "  THE VIDEO CARD'S TEXT: 256 CHARACTERS (CODE PAGE 437) AND 256 COLORS          "
            FCB  5,21,250,0
            FCN  "THE FONT, 8x16"
            FCB  44,21,250,0
            FCN  "THE PALETTE: XTERM'S 256 COLORS"
            FCB  5,26,250,0
            FCN  "THE CARD SAYS: ID"
            FCB  0,29,231,18
            FCN  "  A KEY: THE NEXT PAGE                                                          "
            FCB  $FF
VERSION     FCN  ", VERSION "
; Page 2's heading and footer.
TEXTS2      FCB  0,0,231,18
            FCN  "  AN 8x8 FONT MADE FROM THE 8x16 ONE: 80x60 CELLS, SCROLLED A PIXEL A FRAME      "
            FCB  0,29,231,18
            FCN  "  A KEY: BACK TO THE SHELL                                                      "
            FCB  $FF
MARQUEE     FCN  "  * 320x240 TEXT, EVERY PIXEL DOUBLED, SCROLLING OVER THE PAGE *"
RAINBOW     FCB  196,202,208,214,220,226,190,154,118,82,46,47,48,49,50,51,45,39
            FCB  33,27,21,57,93,129,165,201,0
; The boxes: column, top row, width, height inside ($FF ends the list).
BOXES       FCB  4,3,32,16,43,3,32,16,$FF
; Layer 1 on page 1: text, lores, 8x16 font, 64x32 cells, at MARQMAP.
MARQLAYER   FCB  LM_TEXT+LM_BIG,LW_64+LH_32
            FCB  MARQMAP/$10000,(MARQMAP/$100)&$FF,MARQMAP&$FF
            FCB  VC_FONT/$10000,(VC_FONT/$100)&$FF,VC_FONT&$FF
            FDB  0,0,0
            FCB  0,0
; Page 2's settings from DC_CTRL: layers 0 and 1, then the sprite settings (as
; at reset), then layer 0: hires text, 8x8 font, 128x64 cells.
PAGE2SET    FCB  $03,0,0,128
            FCB  VC_SPRITES/$10000,(VC_SPRITES/$100)&$FF,VC_SPRITES&$FF
            FCB  0,0,0,0,0,0,0,0,0
            FCB  LM_TEXT+LM_HIRES,LW_128+LH_64
            FCB  ROLLMAP/$10000,(ROLLMAP/$100)&$FF,ROLLMAP&$FF
            FCB  FONT8/$10000,(FONT8/$100)&$FF,FONT8&$FF
            FDB  0,0,0
            FCB  0,0
PAGE2END
; Layer 1 on page 2: the card's own 80x30 text screen, in front.
TEXTLAYER   FCB  LM_TEXT+LM_HIRES+LM_BIG,LW_128+LH_32
            FCB  VC_TEXTMAP/$10000,(VC_TEXTMAP/$100)&$FF,VC_TEXTMAP&$FF
            FCB  VC_FONT/$10000,(VC_FONT/$100)&$FF,VC_FONT&$FF
            FDB  0,0,0
            FCB  0,0
; What rolls by on page 2: lines, each ending in 0; $FF ends them.
ROLLTEXT    FCN  "THE PUGPUTER 6309 VIDEO CARD"
            FCB  0
            FCN  "THREE LAYERS, EACH OF THEM ONE OF:"
            FCN  "  TEXT    80x30 OR 80x60 CELLS, A FONT OF YOUR OWN, 256 COLORS A CELL"
            FCN  "  TILES   8x8 OR 16x16, 1 TO 8 BITS A PIXEL, FLIPPED, SCROLLED, WRAPPED"
            FCN  "  BITMAP  1 TO 8 BITS A PIXEL, 640x480 OR 320x240"
            FCB  0
            FCN  "128 SPRITES, 8 TO 64 PIXELS SQUARE, BETWEEN THE LAYERS"
            FCN  "256 COLORS OUT OF 65536"
            FCN  "DRAWING COMMANDS: LINES, BOXES, CIRCLES, TRIANGLES, TEXT, BLITS"
            FCN  "INTERRUPTS AT VERTICAL BLANK AND AT ANY LINE"
            FCN  "256KB OF VIDEO MEMORY, 8MB OF PSRAM"
            FCB  0
            FCN  "THIS LAYER'S FONT WAS MADE A MOMENT AGO: EACH 8x8 CHARACTER IS"
            FCN  "THE CARD'S 8x16 ONE WITH EVERY TWO LINES ORED INTO ONE, READ BACK"
            FCN  "THROUGH DATA PORT 0 AND WRITTEN THROUGH DATA PORT 1."
            FCB  0
            FCN  "IT IS 80x60 CELLS, IN A MAP OF 128x64 THAT WRAPS AROUND AS IT"
            FCN  "SCROLLS. THE HEADING AND THE FOOTER ARE ANOTHER LAYER, WHICH DOESN'T."
            FCB  0
            FCB  $C9,$CD,$CD,$CD,$CD,$CD,$CD,$CD,$CD,$CD,$CD,$CD,$CD,$CD,$CD,$CD
            FCB  $CD,$CD,$CD,$CD,$CD,$CD,$CD,$CD,$CD,$CD,$CD,$CD,$CD,$CD,$CD,$CD
            FCB  $CD,$CD,$CD,$BB,$00
            FCB  $BA,$20,$01,$20,$20,$50,$55,$47,$50,$55,$54,$45,$52,$20,$36,$33
            FCB  $30,$39,$20,$20,$02,$20,$20,$56,$49,$44,$45,$4F,$20,$43,$41,$52
            FCB  $44,$20,$03,$BA,$00
            FCB  $C8,$CD,$CD,$CD,$CD,$CD,$CD,$CD,$CD,$CD,$CD,$CD,$CD,$CD,$CD,$CD
            FCB  $CD,$CD,$CD,$CD,$CD,$CD,$CD,$CD,$CD,$CD,$CD,$CD,$CD,$CD,$CD,$CD
            FCB  $CD,$CD,$CD,$BC,$00
            FCB  0
            FCB  $FF

            END  START
