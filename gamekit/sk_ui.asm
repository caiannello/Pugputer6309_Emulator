;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 game kit
;    FILE: sk_ui.asm
;
; SONGKIT's screen and input: the card's text layer 0 (80x30 cells of 8x16,
; the map at VC_TEXTMAP as the card starts), the mouse and keys, the mouse
; pointer (sprite 0), and a line of typing on the bottom row.
;
;   UISTART            the card as SONGKIT has it (reset, the pointer, the keys)
;   UIEND              the card as it was, for the shell
;   TXAT TXCH TXSTR    text: the cell at column A, row B; a character; a string
;   TXSPC TXDEC TXSGN  spaces; a number; a signed one
;   TXCLR TXROWCLR     the screen, a row, blank
;   POLLIN GETKEY      the mouse, and the next key event
;   PRSTART PRKEY      a line of typing
;
; Routines change any register but S unless they say otherwise.
;------------------------------------------------------------------------------
UI_PTRIMG   equ  $03E800    ; the pointer's image: 16x16, 8 bits a pixel
UI_BACK     equ  234        ; the colors: the backdrop (behind every blank cell)
C_LABEL     equ  250        ;   labels
C_VALUE     equ  15         ;   values
C_DIM       equ  240        ;   what doesn't apply
C_CURBG     equ  25         ;   the field being edited, behind it
C_BARBG     equ  24         ;   the title bar's
C_HEAD      equ  117        ;   headings
C_OUT       equ  214        ;   an operator that is heard (a carrier)
C_HELP      equ  245        ;   the keys
C_MSG       equ  222        ;   messages and questions
PR_MAX      equ  40         ; the longest line PRKEY takes

; UISTART: the card reset (the text screen blank, xterm's colors), the
; backdrop, the pointer (sprite 0, which the card moves), the keys the
; program's.
UISTART     LDA  #$80
            STA  VC_CTRL
            LDD  #1
            STD  VC_INC0
            JSR  MKPTR
            LDA  #VC_SPRITES/$10000 ; sprite 0: the pointer, in front
            LDX  #VC_SPRITES&$FFFF
            JSR  UIPORT
            LDX  #UISPR0
            LDY  #VC_DATA0
            LDW  #8
            TFM  X+,Y
            LDA  #VC_CFG/$10000
            LDX  #DC_CTRL
            JSR  UIPORT
            LDA  #$09           ; layer 0 and the sprites on
            STA  VC_DATA0
            LDA  #UI_BACK
            STA  VC_DATA0
            LDA  #1             ; sprites in 640x480
            STA  VC_DATA0
            LDA  #1             ; one of them
            STA  VC_DATA0
            LDA  #VC_IN_PTR+VC_IN_KEYS+VC_IN_FLUSH
            STA  VC_INCTRL
            CLR  KEYMODS
            JMP  TXCLR
; UIEND: the card as it starts (and the keys back to the console).
UIEND       LDA  #$80
            STA  VC_CTRL
            RTS
; UIPORT: data port 0 to A:X, step 1.
UIPORT      STA  VC_ADDR0
            STX  VC_ADDR0M
            RTS
UISPR0      FDB  UI_PTRIMG/32,320,240
            FCB  SS_W16+SS_H16+SS_FRONT,SC_8BPP

;------------------------------------------------------------------------------
; Text. Each character in TXFG on TXBG (0: the backdrop shows).
;------------------------------------------------------------------------------
; TXAT: the next character at column A, row B. (All kept.)
TXAT        PSHS D,X
            STA  TXCOL
            TFR  B,A            ; row x 512 + column x 4, in the 128-wide map
            CLRB
            LSLA
            STD  TXTMP
            LDB  TXCOL
            CLRA
            LSLD
            LSLD
            ADDD TXTMP
            ADDD #VC_TEXTMAP&$FFFF
            TFR  D,X
            LDA  #VC_TEXTMAP/$10000
            JSR  UIPORT
            PULS D,X,PC
; TXCH: character A. (All kept.)
TXCH        PSHS A
            STA  VC_DATA0
            LDA  TXFG
            STA  VC_DATA0
            LDA  TXBG
            STA  VC_DATA0
            CLRA
            STA  VC_DATA0
            PULS A,PC
; TXSTR: the string at X (0 at its end); X past it. (D kept.)
TXSTR       PSHS A
TXSTR1      LDA  ,X+
            BEQ  TXSTR9
            BSR  TXCH
            BRA  TXSTR1
TXSTR9      PULS A,PC
; TXSPC: B spaces. (A, X kept.)
TXSPC       TSTB
            BEQ  TXSPC9
            PSHS A
            LDA  #$20
TXSPC1      BSR  TXCH
            DECB
            BNE  TXSPC1
            PULS A
TXSPC9      RTS
; TXDEC: A (0-255) in decimal, as few digits as it takes; B how many. (X kept.)
TXDEC       CLR  TXN
            TFR  A,B
            CLRA
            CMPD #100
            BLO  TXDEC1
            DIVD #100           ; B the hundreds, A the rest
            PSHS A
            TFR  B,A
            BSR  TXDIG
            PULS B
            CLRA
            BRA  TXDEC2         ; (then the tens, 0 or not)
TXDEC1      CMPD #10
            BLO  TXDEC3
TXDEC2      DIVD #10
            PSHS A
            TFR  B,A
            BSR  TXDIG
            PULS B
TXDEC3      TFR  B,A
            BSR  TXDIG
            LDB  TXN
            RTS
TXDIG       ADDA #'0
            INC  TXN
            BRA  TXCH
; TXSGN: A (signed) as +n, -n or 0; B how many characters.
TXSGN       TSTA
            BEQ  TXDEC
            BMI  TXSGN1
            PSHS A
            LDA  #'+
            BRA  TXSGN2
TXSGN1      NEGA
            PSHS A
            LDA  #'-
TXSGN2      BSR  TXCH
            PULS A
            BSR  TXDEC
            INCB
            RTS
; TXCLR: every cell a space on the backdrop.
TXCLR       CLRB
TXCLR1      BSR  TXROWCLR
            INCB
            CMPB #30
            BLO  TXCLR1
            RTS
; TXROWCLR: row B blank. (B kept.)
TXROWCLR    PSHS B
            CLRA
            JSR  TXAT
            CLR  TXBG
            LDB  #80
            BSR  TXSPC
            PULS B,PC

;------------------------------------------------------------------------------
; The mouse and the keys.
;------------------------------------------------------------------------------
; POLLIN: MOUSEX, MOUSEY (640x480), BUTTONS (bit 0 left, 1 right, 2 middle),
; PRESSED (the buttons that went down since the last call), WHEEL (clicks
; since then, signed).
POLLIN      LDD  VC_MOUSEX      ; (this takes the snapshot of X and Y)
            STD  MOUSEX
            LDD  VC_MOUSEY
            STD  MOUSEY
            LDB  BUTTONS
            LDA  VC_MOUSEB
            ANDA #VC_MB_LEFT+VC_MB_RIGHT+VC_MB_MID
            STA  BUTTONS
            COMB
            ANDB BUTTONS
            STB  PRESSED
            LDA  VC_WHEEL
            STA  WHEEL
            RTS
; GETKEY: the next key event, if there is one: Z clear, A its USB usage code,
; B the character it typed (bit 7 set: a release); KEYMODS the modifiers held
; as of that event (followed from the queue's own events). Z set if none.
GETKEY      LDA  VC_KEY
            BEQ  GETKEY9
            LDB  VC_KEYCHAR
            CMPA #K_LCTRL       ; a modifier: its bit in KEYMODS
            BLO  GETKEY8
            PSHS D
            SUBA #K_LCTRL
            LDB  #1
GETKEY1     DECA
            BMI  GETKEY2
            LSLB
            BRA  GETKEY1
GETKEY2     TST  1,S
            BMI  GETKEY3
            ORB  KEYMODS        ; down
            BRA  GETKEY4
GETKEY3     COMB                ; up
            ANDB KEYMODS
GETKEY4     STB  KEYMODS
            PULS D
GETKEY8     TSTA
GETKEY9     RTS

;------------------------------------------------------------------------------
; A line of typing, on row 29: PRSTART with X the question, Y the text to start
; with (or 0), A: 1 for a file's name (upper case, no spaces, 40 at most), 0
; for an instrument's (16), 2 for a song's title (32); then PRKEY with
; each key (A usage, B character) -- it answers A = 0 (go on), 1 (Enter:
; PR_BUF holds the line, 0 at its end) or 2 (Esc).
;------------------------------------------------------------------------------
PRSTART     STX  PR_ASK
            STA  PR_FILE
            LDB  #PR_MAX        ; (a file's name 40 characters, a title 32,
            CMPA #1             ; others 16)
            BEQ  PRSTART0
            LDB  #16
            TSTA
            BEQ  PRSTART0
            LDB  #32
PRSTART0    STB  PR_MAXL
            CLR  PR_LEN
            CMPY #0
            BEQ  PRSTART9
            LDX  #PR_BUF
PRSTART1    LDA  ,Y+
            BEQ  PRSTART9
            STA  ,X+
            INC  PR_LEN
            LDA  PR_LEN
            CMPA #PR_MAX
            BLO  PRSTART1
PRSTART9    LDX  #PR_BUF
            LDB  PR_LEN
            ABX
            CLR  ,X
            JMP  PRSHOW
PRKEY       TSTB                ; (a key let go: nothing)
            BMI  PRKEY0
            CMPA #K_ENTER
            BEQ  PRKEY1
            CMPA #K_KPENTER
            BEQ  PRKEY1
            CMPA #K_ESC
            BEQ  PRKEY2
            CMPA #K_BKSP
            BEQ  PRKEY3
            CMPB #$20
            BLO  PRKEY0         ; (nothing typed)
            CMPB #$7F
            BHS  PRKEY0
            LDA  PR_FILE
            CMPA #1
            BNE  PRKEY4
            CMPB #$20           ; a name: no spaces, upper case
            BEQ  PRKEY0
            CMPB #'a
            BLO  PRKEY4
            CMPB #'z
            BHI  PRKEY4
            SUBB #$20
PRKEY4      LDA  PR_LEN
            CMPA PR_MAXL
            BHS  PRKEY0
            LDX  #PR_BUF
            LEAX A,X
            STB  ,X+
            CLR  ,X
            INC  PR_LEN
            BRA  PRKEY5
PRKEY3      LDA  PR_LEN
            BEQ  PRKEY0
            DECA
            STA  PR_LEN
            LDX  #PR_BUF
            CLR  A,X
PRKEY5      JSR  PRSHOW
PRKEY0      CLRA
            RTS
PRKEY1      LDA  #1
            RTS
PRKEY2      LDA  #2
            RTS
PRSHOW      LDB  #29
            JSR  TXROWCLR
            CLRA
            JSR  TXAT
            LDA  #C_MSG
            STA  TXFG
            LDX  PR_ASK
            JSR  TXSTR
            LDA  #C_VALUE
            STA  TXFG
            LDX  #PR_BUF
            JSR  TXSTR
            LDA  #'_
            JMP  TXCH

;------------------------------------------------------------------------------
; The pointer: an arrow in white outlined in black, its point at the top left.
;------------------------------------------------------------------------------
MKPTR       LDA  #UI_PTRIMG/$10000
            LDX  #UI_PTRIMG&$FFFF
            JSR  UIPORT
            LDX  #PTRMASK
            LDE  #16
MKPTR1      LDD  ,X++
            STD  UI_BITS        ; the inside
            LDD  ,X++
            STD  UI_EDGE        ; the outline
            LDF  #16
MKPTR2      CLRA
            LSL  UI_EDGE+1
            ROL  UI_EDGE
            BCC  MKPTR3
            LDA  #16            ; (black: 0 shows through)
MKPTR3      LSL  UI_BITS+1
            ROL  UI_BITS
            BCC  MKPTR4
            LDA  #15
MKPTR4      STA  VC_DATA0
            DECF
            BNE  MKPTR2
            DECE
            BNE  MKPTR1
            RTS
; Each row: the inside, then the outline.
PTRMASK     FDB  $0000,$8000
            FDB  $0000,$C000
            FDB  $4000,$A000
            FDB  $6000,$9000
            FDB  $7000,$8800
            FDB  $7800,$8400
            FDB  $7C00,$8200
            FDB  $7E00,$8100
            FDB  $7F00,$8080
            FDB  $7C00,$83C0
            FDB  $6C00,$9200
            FDB  $4600,$A900
            FDB  $0300,$C480
            FDB  $0180,$8240
            FDB  $0000,$0180
            FDB  $0000,$0000
;------------------------------------------------------------------------------
; End of sk_ui.asm
;------------------------------------------------------------------------------
