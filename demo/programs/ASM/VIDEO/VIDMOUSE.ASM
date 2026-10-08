;------------------------------------------------------------------------------
; PROJECT: VIDEO CARD DEMOS
;    FILE: vidmouse.asm
;
; The video card's mouse and keyboard: a canvas to draw on with the mouse.
;
;   left button    draws, in the color shown at the top
;   right button   rubs out
;   wheel, + / -   the next or the previous color
;   C              clears the canvas
;   Esc            back to the shell
;
; A 320x240 bitmap of 8 bits a pixel on layer 0, and a line of text on layer 1
; with where the mouse is, its buttons, and the last key event: its USB usage
; code, the character it typed (bit 7 set for a release) and the modifier keys
; held. The pointer is sprite 0, which the card itself keeps where the mouse
; is (VC_INCTRL bit 0); the keys come from the card's queue (bit 1), so in the
; emulator they are the video window's, not the terminal's.
;
;   ASM -f com vidmouse.asm        makes VIDMOUSE.COM
;------------------------------------------------------------------------------
            INCLUDE "vidcard.d"

CANVAS      equ  $000000    ; the bitmap: 320x240, 8 bits a pixel
ARROW       equ  $030000    ; the pointer's image: 16x16, 4 bits a pixel
TEXTBG      equ  17         ; the status line's background (dark blue)
;------------------------------------------------------------------------------
            ORG  $4000
START       LDA  #$80
            STA  VC_CTRL        ; the card as it starts
            LDA  #1             ; the pointer's outline: color 1, black
            LDX  #0
            JSR  SETCOLOR
            LDA  #VC_CFG/$10000 ; the settings: layers, sprites, backdrop
            LDX  #DC_CTRL
            JSR  PORT0
            LDX  #SETTINGS
            LDW  #SETEND-SETTINGS
            JSR  SENDDAT
            LDA  #ARROW/$10000  ; the pointer's image
            LDX  #ARROW&$FFFF
            JSR  PORT0
            LDX  #ARROWIMG
            LDW  #128
            JSR  SENDDAT
            LDA  #VC_SPRITES/$10000 ; sprite 0: the pointer
            LDX  #VC_SPRITES&$FFFF
            JSR  PORT0
            LDX  #SPRITE0
            LDW  #8
            JSR  SENDDAT
            LDX  #CANVASCMD     ; drawing goes to the canvas; clear it
            LDW  #CANVASEND-CANVASCMD
            JSR  SENDCMD
            LDA  #VC_IN_PTR+VC_IN_KEYS+VC_IN_FLUSH
            STA  VC_INCTRL      ; the pointer follows the mouse; the keys are ours
            LDA  VC_WHEEL       ; (forget the wheel's clicks so far)
;------------------------------------------------------------------------------
; Each frame: the mouse, then the keys, then the status line.
;------------------------------------------------------------------------------
FRAME       JSR  VBLANK
            LDD  VC_MOUSEX      ; (this takes the snapshot of X and Y)
            LSRD                ; the canvas is 320x240: half the mouse's pixels
            STD  MX
            LDD  VC_MOUSEY
            LSRD
            STD  MY
            LDA  VC_WHEEL       ; the wheel turns the color
            ADDA COLOR
            STA  COLOR
            LDA  VC_MOUSEB
            STA  BUTTONS
            BITA #VC_MB_LEFT
            BEQ  NOTDRAW
            LDA  #C_COLOR       ; draw: a line from where the mouse was, or
            STA  VC_CMD         ; a dot where the button went down
            LDA  COLOR
            STA  VC_CMD
            LDA  #C_LINE
            STA  VC_CMD
            LDD  LX
            TST  WASDOWN
            BNE  FROM
            LDD  MX
FROM        JSR  CMDD
            LDD  LY
            TST  WASDOWN
            BNE  FROM2
            LDD  MY
FROM2       JSR  CMDD
            LDD  MX
            JSR  CMDD
            LDD  MY
            JSR  CMDD
NOTDRAW     LDA  BUTTONS
            BITA #VC_MB_RIGHT
            BEQ  NOTRUB
            LDA  #C_COLOR       ; rub out: a 7x7 square of color 0 (see-through,
            STA  VC_CMD         ; so the backdrop shows)
            CLRA
            STA  VC_CMD
            LDA  #C_FILLRECT
            STA  VC_CMD
            LDD  MX
            SUBD #3
            JSR  CMDD
            LDD  MY
            SUBD #3
            JSR  CMDD
            LDD  #7
            JSR  CMDD
            LDD  #7
            JSR  CMDD
NOTRUB      LDD  MX
            STD  LX
            LDD  MY
            STD  LY
            LDA  BUTTONS
            ANDA #VC_MB_LEFT
            STA  WASDOWN
; The keys typed since the last frame.
KEYS        LDA  VC_KEY
            BEQ  STATUS
            STA  LASTKEY
            LDB  VC_KEYCHAR
            STB  LASTCHAR
            LDA  VC_KEYMODS
            STA  LASTMODS
            TSTB
            BMI  KEYS           ; (a release: nothing to do)
            LDA  LASTKEY
            CMPA #K_ESC
            LBEQ BYE
            CMPB #'C
            BEQ  CLEAR
            CMPB #'c
            BEQ  CLEAR
            CMPB #'+
            BEQ  NEXTCOL
            CMPB #'=
            BEQ  NEXTCOL
            CMPB #'-
            BNE  KEYS
            DEC  COLOR
            BRA  KEYS
NEXTCOL     INC  COLOR
            BRA  KEYS
CLEAR       LDX  #CLEARCMD
            LDW  #CLEAREND-CLEARCMD
            JSR  SENDCMD
            BRA  KEYS
; The status line, on layer 1's top row.
STATUS      CLRA
            CLRB
            JSR  TEXTAT
            LDX  #T_X
            JSR  WORDS
            LDD  MX
            LSLD                ; (in the mouse's own pixels)
            JSR  DECIMAL
            LDX  #T_Y
            JSR  WORDS
            LDD  MY
            LSLD
            JSR  DECIMAL
            LDX  #T_BTN
            JSR  WORDS
            LDA  BUTTONS
            JSR  HEX
            LDX  #T_COLOR
            JSR  WORDS
            CLRA
            LDB  COLOR
            JSR  DECIMAL
            LDA  #' '           ; a swatch of it
            LDB  COLOR
            JSR  CELL
            LDA  #' '
            LDB  COLOR
            JSR  CELL
            LDX  #T_KEY
            JSR  WORDS
            LDA  LASTKEY
            JSR  HEX
            LDX  #T_CHAR
            JSR  WORDS
            LDA  LASTCHAR
            JSR  HEX
            LDA  #' '
            JSR  PUT
            LDA  LASTCHAR       ; the character itself, if it shows
            ANDA #$7F
            CMPA #' '
            BLO  NOSHOW
            CMPA #$7F
            BLO  SHOW
NOSHOW      LDA  #' '
SHOW        JSR  PUT
            LDX  #T_MODS
            JSR  WORDS
            LDA  LASTMODS
            JSR  HEX
            LDX  #T_HELP
            JSR  WORDS
            LBRA FRAME
; Back to the shell (QUIT resets the card, which gives the keys back to the UART).
BYE         JMP  QUIT
;------------------------------------------------------------------------------
; Text on the status line, from data port 0 on.
;------------------------------------------------------------------------------
; WORDS: the string at X (0 at its end).
WORDS       LDA  ,X+
            BEQ  WORDSEND
            BSR  PUT
            BRA  WORDS
WORDSEND    RTS
; PUT: character A, white on the line's background. CELL: on background B.
PUT         LDB  #TEXTBG
CELL        STA  VC_DATA0
            LDA  #15
            STA  VC_DATA0
            STB  VC_DATA0
            CLRA
            STA  VC_DATA0
            RTS
; DECIMAL: D (0-999) as three digits.
DECIMAL     DIVD #100           ; B = hundreds, A = the rest
            PSHS A
            TFR  B,A
            ADDA #'0
            BSR  PUT
            PULS B
            CLRA
            DIVD #10            ; B = tens, A = ones
            PSHS A
            TFR  B,A
            ADDA #'0
            BSR  PUT
            PULS A
            ADDA #'0
            BRA  PUT
; HEX: A as two hex digits.
HEX         PSHS A
            LSRA
            LSRA
            LSRA
            LSRA
            BSR  DIGIT
            PULS A
            ANDA #$0F
DIGIT       ADDA #'0
            CMPA #'9
            BLS  PUT
            ADDA #'A-'9-1
            BRA  PUT
;------------------------------------------------------------------------------
            INCLUDE "VIDLIB.ASM"
;------------------------------------------------------------------------------
MX          FDB  0          ; the mouse, in the canvas's pixels
MY          FDB  0
LX          FDB  0          ; and where it was the frame before
LY          FDB  0
WASDOWN     FCB  0          ; the left button was down then
BUTTONS     FCB  0
COLOR       FCB  226        ; yellow
LASTKEY     FCB  0
LASTCHAR    FCB  0
LASTMODS    FCB  0

T_X         FCN  " X "
T_Y         FCN  " Y "
T_BTN       FCN  " BTN "
T_COLOR     FCN  " COLOR "
T_KEY       FCN  " KEY "
T_CHAR      FCN  " CHAR "
T_MODS      FCN  " MODS "
T_HELP      FCN  "  C:CLEAR  ESC:QUIT"

; The settings from DC_CTRL on: layers 0 and 1 and the sprites on, a dark gray
; backdrop, sprites in 320x240 coordinates, one of them, the table where it is
; at reset; then layer 0, the canvas, and layer 1, the reset text screen moved
; up a layer (80x30 cells of 8x16, hires).
SETTINGS    FCB  $0B,236,0,1
            FCB  VC_SPRITES/$10000,(VC_SPRITES/$100)&$FF,VC_SPRITES&$FF
            FCB  0,0,0,0,0,0,0,0,0
            FCB  LM_BITMAP+LM_8BPP,0
            FCB  CANVAS/$10000,(CANVAS/$100)&$FF,CANVAS&$FF
            FCB  0,0,0
            FDB  0,0,320
            FCB  0,0
            FCB  LM_TEXT+LM_HIRES+LM_BIG,LW_128+LH_32
            FCB  VC_TEXTMAP/$10000,(VC_TEXTMAP/$100)&$FF,VC_TEXTMAP&$FF
            FCB  VC_FONT/$10000,(VC_FONT/$100)&$FF,VC_FONT&$FF
            FDB  0,0,0
            FCB  0,0
SETEND
; Sprite 0: the arrow, 16x16, 4 bits a pixel, in front of everything.
SPRITE0     FDB  ARROW/32,0,0
            FCB  SS_W16+SS_H16+SS_FRONT,0
; The drawing target, the canvas; then (CLEARCMD) clear it to see-through.
CANVASCMD   FCB  C_TARGET,CANVAS/$10000,(CANVAS/$100)&$FF,CANVAS&$FF
            FDB  320,320,240
            FCB  8
CLEARCMD    FCB  C_COLOR,0,C_CLEAR
CLEAREND
CANVASEND
; The arrow: 1 the outline (black), F the inside (white), its point at the top left.
ARROWIMG    FDB  $1000,$0000,$0000,$0000
            FDB  $1100,$0000,$0000,$0000
            FDB  $1F10,$0000,$0000,$0000
            FDB  $1FF1,$0000,$0000,$0000
            FDB  $1FFF,$1000,$0000,$0000
            FDB  $1FFF,$F100,$0000,$0000
            FDB  $1FFF,$FF10,$0000,$0000
            FDB  $1FFF,$FFF1,$0000,$0000
            FDB  $1FFF,$FFFF,$1000,$0000
            FDB  $1FFF,$FF11,$1100,$0000
            FDB  $1FF1,$FF10,$0000,$0000
            FDB  $1F10,$1FF1,$0000,$0000
            FDB  $1100,$01FF,$1000,$0000
            FDB  $1000,$001F,$F100,$0000
            FDB  $0000,$0001,$1000,$0000
            FDB  $0000,$0000,$0000,$0000

            END  START
