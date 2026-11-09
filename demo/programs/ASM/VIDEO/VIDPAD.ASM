;------------------------------------------------------------------------------
; PROJECT: VIDEO CARD DEMOS
;    FILE: vidpad.asm
;
; The video card's gamepads: what each of the four is doing, read once a frame.
;
;   Esc            back to the shell
;
; A line of text for each pad: its d-pad (U D L R), its buttons (a dot if one
; isn't held), and its two sticks. They are bytes in the card's address space,
; read through data port 0 like any other. BTN: the buttons are the standard
; ones (named along the bottom). RAW: this pad has no map yet, so they are its
; own 1-16 (1-9, 0, A-F): PADMAP sets one up.
;
;   ASM -f com vidpad.asm        makes VIDPAD.COM
;------------------------------------------------------------------------------
            INCLUDE "vidcard.d"

TEXTBG      equ  17         ; the lines' background (dark blue)
;------------------------------------------------------------------------------
            ORG  $4000
START       LDA  #$80
            STA  VC_CTRL        ; the card as it starts: a text screen
            LDA  #VC_IN_KEYS+VC_IN_FLUSH
            STA  VC_INCTRL      ; the keys are ours
            CLRA
            CLRB
            JSR  TEXTAT
            LDX  #T_TITLE
            JSR  WORDS
            CLRA
            LDB  #10
            JSR  TEXTAT
            LDX  #T_KEY1
            JSR  WORDS
            CLRA
            LDB  #11
            JSR  TEXTAT
            LDX  #T_KEY2
            JSR  WORDS
;------------------------------------------------------------------------------
; Each frame: all the pads' bytes, then a line for each, then the keys.
;------------------------------------------------------------------------------
FRAME       JSR  VBLANK
            LDA  #VC_PAD/$10000
            LDX  #VC_PAD&$FFFF
            JSR  PORT0
            LDX  #PADS
            LDB  #32
READ        LDA  VC_DATA0
            STA  ,X+
            DECB
            BNE  READ
            LDY  #PADS
            CLR  PADNUM
DRAW        CLRA                ; rows 2, 4, 6 and 8
            LDB  PADNUM
            LSLB
            ADDB #2
            JSR  TEXTAT
            LDX  #T_PAD
            JSR  WORDS
            LDA  PADNUM
            ADDA #'0
            JSR  PUT
            LDX  #T_COLON
            JSR  WORDS
            LDA  PD_FLAGS,Y
            BMI  HAVEPAD
            LDX  #T_NONE        ; not connected (and the rest of the line cleared)
            JSR  WORDS
            LDE  #44
NONE1       LDA  #' '
            JSR  PUT
            DECE
            BNE  NONE1
            BRA  NEXTPAD
HAVEPAD     LDA  PD_DPAD,Y
            STA  TMP
            LDX  #L_DPAD
            LDE  #4
            JSR  FLAGS
            LDX  #T_RAW         ; the pad's own numbers, or the standard names
            LDU  #L_RAW
            LDA  PD_FLAGS,Y
            BITA #PD_MAPPED
            BEQ  HAVEPAD1
            LDX  #T_BTN
            LDU  #L_BTN
HAVEPAD1    JSR  WORDS
            LDA  PD_BTN1,Y
            STA  TMP
            TFR  U,X
            LDE  #8
            JSR  FLAGS
            LDA  PD_BTN2,Y      ; (X has gone on to the next eight labels)
            STA  TMP
            LDE  #8
            JSR  FLAGS
            LDX  #T_LX
            JSR  WORDS
            LDA  PD_LX,Y
            JSR  SIGNED
            LDX  #T_LY
            JSR  WORDS
            LDA  PD_LY,Y
            JSR  SIGNED
            LDX  #T_RX
            JSR  WORDS
            LDA  PD_RX,Y
            JSR  SIGNED
            LDX  #T_RY
            JSR  WORDS
            LDA  PD_RY,Y
            JSR  SIGNED
NEXTPAD     LEAY 8,Y
            INC  PADNUM
            LDA  PADNUM
            CMPA #4
            LBLO DRAW
; The keys typed since the last frame: only Esc does anything.
KEYS        LDA  VC_KEY
            LBEQ FRAME
            LDB  VC_KEYCHAR
            BMI  KEYS           ; (a release)
            CMPA #K_ESC
            BNE  KEYS
            JMP  QUIT           ; (which resets the card: the keys go back to the UART)
;------------------------------------------------------------------------------
; Text, from data port 0 on.
;------------------------------------------------------------------------------
; FLAGS: E labels from X, each shown if the next bit of TMP (from bit 0) is set.
FLAGS       LDA  ,X+
            LSR  TMP
            BCS  FLAG1
            LDA  #'.
FLAG1       BSR  PUT
            DECE
            BNE  FLAGS
            RTS
; WORDS: the string at X (0 at its end).
WORDS       LDA  ,X+
            BEQ  WORDSEND
            BSR  PUT
            BRA  WORDS
WORDSEND    RTS
; PUT: character A, white on the line's background.
PUT         STA  VC_DATA0
            LDA  #15
            STA  VC_DATA0
            LDA  #TEXTBG
            STA  VC_DATA0
            CLRA
            STA  VC_DATA0
            RTS
; SIGNED: A (-127 to 127) as a sign and three digits.
SIGNED      TSTA
            BPL  SIGNED1
            NEGA
            PSHS A
            LDA  #'-
            BRA  SIGNED2
SIGNED1     PSHS A
            LDA  #'+
SIGNED2     BSR  PUT
            PULS B
            CLRA
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
;------------------------------------------------------------------------------
            INCLUDE "VIDLIB.ASM"
;------------------------------------------------------------------------------
PADNUM      FCB  0
TMP         FCB  0
PADS        RMB  32         ; the four pads' bytes, as of this frame

L_DPAD      FCC  "UDLR"
L_RAW       FCC  "1234567890ABCDEF"
L_BTN       FCC  "SEWNLRlr-+H<>xyz"

T_TITLE     FCN  " GAMEPADS: PRESS BUTTONS, MOVE THE STICKS    ESC:QUIT "
T_KEY1      FCN  " BTN: SEWN FACE BUTTONS  LR SHOULDERS  lr LOWER SHOULDERS  - SELECT  + START"
T_KEY2      FCN  "      H HOME  <> STICK CLICKS    RAW: NO MAP YET, RUN PADMAP"
T_PAD       FCN  " PAD "
T_COLON     FCN  ": "
T_NONE      FCN  "NOT CONNECTED"
T_BTN       FCN  " BTN "
T_RAW       FCN  " RAW "
T_LX        FCN  " LX "
T_LY        FCN  " LY "
T_RX        FCN  " RX "
T_RY        FCN  " RY "

            END  START
