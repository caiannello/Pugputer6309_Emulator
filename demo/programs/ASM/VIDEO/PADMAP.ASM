;------------------------------------------------------------------------------
; PROJECT: VIDEO CARD
;    FILE: padmap.asm
;
; Sets up a gamepad: which of its buttons is which, so that every game sees the
; same South, East, Start and so on. It asks for each in turn, tells the card,
; and saves them all in /CMD/PADMAP.INI.
;
;   Esc            back to the shell, nothing changed
;   Space          this pad doesn't have the button being asked for
;
; Starting it also gives the card what /CMD/PADMAP.INI says, so PADMAP then Esc
; puts the saved maps back after a power cycle. The file is text, one line a
; pad (see T_HEAD below for what the numbers are):
;
;   2DC8 6001  01 00 FF 03 02 FF 04 05 06 07 08 09 0A 0B 0C FF
;
;   ASM -f com padmap.asm        makes PADMAP.COM
;------------------------------------------------------------------------------
            INCLUDE "vidcard.d"

B_FOPEN_NAME equ $13        ; the BIOS calls used, besides VIDLIB's
B_FCLOSE_NAME equ $16
B_FREAD     equ  $1D
B_FWRITE    equ  $1E
FOPEN_READ  equ  $00
FOPEN_WRITE equ  $01

TEXTBG      equ  17         ; the lines' background (dark blue)
NBUTTONS    equ  13         ; the standard buttons asked for
NMAPS       equ  8          ; the card's maps, and 20 bytes in each
MAPSIZE     equ  20
TABSIZE     equ  NMAPS*MAPSIZE
;------------------------------------------------------------------------------
            ORG  $4000
START       LDA  #$80
            STA  VC_CTRL        ; the card as it starts: a text screen
            LDA  #VC_IN_KEYS+VC_IN_FLUSH
            STA  VC_INCTRL      ; the keys are ours
            JSR  LOADINI        ; what was saved, to the card
            LDB  #0
            LDX  #T_TITLE
            JSR  LINE
;------------------------------------------------------------------------------
; Which pad: the first with a button held.
;------------------------------------------------------------------------------
            LDB  #2
            LDX  #T_CHOOSE
            JSR  LINE
CHOOSE      JSR  VBLANK
            JSR  READIDS
            JSR  KEYPRESS
            CMPA #K_ESC
            LBEQ QUIT
            LDY  #IDS
            CLRA
CHOOSE1     LDB  ID_RAW1,Y
            ORB  ID_RAW2,Y
            BNE  CHOSEN
            LEAY 8,Y
            INCA
            CMPA #4
            BLO  CHOOSE1
            BRA  CHOOSE
CHOSEN      STA  PADNO
            LDA  #$FF           ; no button is anything yet
            LDX  #ENTRY+4
            LDB  #16
CHOSEN1     STA  ,X+
            DECB
            BNE  CHOSEN1
            LDD  ID_VID,Y       ; the map's first 4 bytes: which pad
            STD  ENTRY
            LDD  ID_PID,Y
            STD  ENTRY+2
            LDU  #LINEBUF       ; " PAD 0  2DC8:6001"
            LDX  #T_PADIS
CHOSEN2     LDA  ,X+
            BEQ  CHOSEN3
            STA  ,U+
            BRA  CHOSEN2
CHOSEN3     LDA  PADNO
            ADDA #'0
            STA  ,U+
            LDA  #' '
            STA  ,U+
            STA  ,U+
            LDA  ENTRY
            JSR  HEXBYTE
            LDA  ENTRY+1
            JSR  HEXBYTE
            LDA  #':
            STA  ,U+
            LDA  ENTRY+2
            JSR  HEXBYTE
            LDA  ENTRY+3
            JSR  HEXBYTE
            CLR  ,U
            LDB  #2
            LDX  #LINEBUF
            JSR  LINE
            LDB  #6
            LDX  #T_SKIP
            JSR  LINE
;------------------------------------------------------------------------------
; Each button in turn.
;------------------------------------------------------------------------------
            CLR  BUTTON
ASK         LDB  BUTTON         ; "press ..."
            LSLB
            LDX  #NAMES
            ABX
            LDX  ,X
            LDB  #4
            JSR  LINE
RELEASE     JSR  VBLANK         ; every button let go first
            JSR  READIDS
            JSR  KEYPRESS
            CMPA #K_ESC
            LBEQ QUIT
            JSR  RAWNOW
            CMPD #0
            BNE  RELEASE
PRESS       JSR  VBLANK
            JSR  READIDS
            JSR  KEYPRESS
            CMPA #K_ESC
            LBEQ QUIT
            CMPA #K_SPACE
            BEQ  NEXT
            JSR  RAWNOW         ; the first held that isn't something already
            STD  RAWBITS
            CLR  BITNUM
FIND        LSR  RAWBITS
            ROR  RAWBITS+1
            BCC  FIND1
            LDX  #ENTRY+4
            LDB  BITNUM
            ABX
            LDA  ,X
            CMPA #$FF
            BEQ  FOUND
FIND1       INC  BITNUM
            LDA  BITNUM
            CMPA #16
            BLO  FIND
            BRA  PRESS
FOUND       LDA  BUTTON
            STA  ,X
NEXT        INC  BUTTON
            LDA  BUTTON
            CMPA #NBUTTONS
            LBLO ASK
;------------------------------------------------------------------------------
; Done: into the table (over this pad's old map, or in an empty place, or the
; first if it's full), to the card, to the file.
;------------------------------------------------------------------------------
            JSR  READMAPS
            LDY  #TABLE
            LDB  #NMAPS
SAME        LDA  ,Y
            CMPA ENTRY
            BNE  SAME1
            LDA  1,Y
            CMPA ENTRY+1
            BNE  SAME1
            LDA  2,Y
            CMPA ENTRY+2
            BNE  SAME1
            LDA  3,Y
            CMPA ENTRY+3
            BEQ  STORE
SAME1       LEAY MAPSIZE,Y
            DECB
            BNE  SAME
            LDY  #TABLE
            LDB  #NMAPS
EMPTY       LDA  ,Y
            ORA  1,Y
            ORA  2,Y
            ORA  3,Y
            BEQ  STORE
            LEAY MAPSIZE,Y
            DECB
            BNE  EMPTY
            LDY  #TABLE
STORE       LDX  #ENTRY
            LDB  #MAPSIZE
STORE1      LDA  ,X+
            STA  ,Y+
            DECB
            BNE  STORE1
            JSR  WRITEMAPS
            LDB  #6             ; (nothing to skip now)
            LDX  #T_NONE
            JSR  LINE
            JSR  SAVEINI
            LDX  #T_SAVED
            BCC  DONE
            LDX  #T_NOSAVE
DONE        LDB  #4
            JSR  LINE
WAITKEY     JSR  VBLANK
            JSR  KEYPRESS
            CMPA #0
            BEQ  WAITKEY
            JMP  QUIT           ; (which resets the card; its maps stay)
;------------------------------------------------------------------------------
; The card.
;------------------------------------------------------------------------------
; READIDS: what each pad is, as of now, into IDS.
READIDS     LDA  #VC_PADID/$10000
            LDX  #VC_PADID&$FFFF
            JSR  PORT0
            LDX  #IDS
            LDB  #32
READIDS1    LDA  VC_DATA0
            STA  ,X+
            DECB
            BNE  READIDS1
            RTS
; RAWNOW: D = the chosen pad's own buttons (A 9-16, B 1-8), from IDS.
RAWNOW      LDA  PADNO
            LDB  #8
            MUL
            LDX  #IDS
            ABX
            LDA  ID_RAW2,X
            LDB  ID_RAW1,X
            RTS
; READMAPS, WRITEMAPS: the card's maps, to and from TABLE.
READMAPS    LDA  #VC_PADMAP/$10000
            LDX  #VC_PADMAP&$FFFF
            JSR  PORT0
            LDX  #TABLE
            LDB  #TABSIZE
READMAP1    LDA  VC_DATA0
            STA  ,X+
            DECB
            BNE  READMAP1
            RTS
WRITEMAPS   LDA  #VC_PADMAP/$10000
            LDX  #VC_PADMAP&$FFFF
            JSR  PORT0
            LDX  #TABLE
            LDB  #TABSIZE
WRITEMA1    LDA  ,X+
            STA  VC_DATA0
            DECB
            BNE  WRITEMA1
            RTS
; KEYPRESS: A = the next key pressed (its USB usage code), or 0 if none.
KEYPRESS    LDA  VC_KEY
            BEQ  KEYPRES9
            LDB  VC_KEYCHAR
            BMI  KEYPRESS       ; (a release)
KEYPRES9    RTS
;------------------------------------------------------------------------------
; Text.
;------------------------------------------------------------------------------
; LINE: the string at X on row B, and the rest of the row blank.
LINE        PSHS X
            CLRA
            JSR  TEXTAT
            PULS X
            LDE  #80
LINE1       LDA  ,X
            BEQ  LINE2
            LEAX 1,X
            BSR  PUT
            DECE
            BNE  LINE1
            RTS
LINE2       LDA  #' '
            BSR  PUT
            DECE
            BNE  LINE2
            RTS
; PUT: character A, white on the line's background.
PUT         STA  VC_DATA0
            LDA  #15
            STA  VC_DATA0
            LDA  #TEXTBG
            STA  VC_DATA0
            CLRA
            STA  VC_DATA0
            RTS
; HEXBYTE: A as two hex digits at U+.
HEXBYTE     PSHS A
            LSRA
            LSRA
            LSRA
            LSRA
            BSR  HEXDIGIT
            PULS A
            ANDA #$0F
HEXDIGIT    CMPA #10
            BLO  HEXDIG1
            ADDA #7
HEXDIG1     ADDA #'0
            STA  ,U+
            RTS
;------------------------------------------------------------------------------
; /CMD/PADMAP.INI
;------------------------------------------------------------------------------
; LOADINI: the maps in the file, to the card. If there's no file, the card's are
; left alone. A line is taken if it has exactly 40 hex digits before any ; (the
; spaces between them don't matter).
LOADINI     LDX  #T_FILE
            LDE  #FOPEN_READ
            LDA  #B_FOPEN_NAME
            SWI2
            BCS  LOADINI9
            STA  HANDLE
            LDX  #TABLE         ; the file says all of them
            LDB  #TABSIZE
LOADINI1    CLR  ,X+
            DECB
            BNE  LOADINI1
            LDX  #IOBUF
            STX  IPTR
            STX  IEND
            CLR  NMAPSIN
            CLR  NDIGITS
            CLR  COMMENT
LOADCH      JSR  GETCH
            BCS  LOADEND
            CMPA #$0A
            BEQ  LOADEOL
            CMPA #$0D
            BEQ  LOADEOL
            TST  COMMENT
            BNE  LOADCH
            CMPA #$3B           ; ";"
            BNE  LOADCH1
            STA  COMMENT
            BRA  LOADCH
LOADCH1     JSR  ISHEX
            BCS  LOADCH         ; (anything else just separates)
            LDB  NDIGITS
            CMPB #41
            BHS  LOADCH         ; (too many already: this line won't count)
            INC  NDIGITS
            CMPB #40
            BHS  LOADCH
            LDX  #LINEBUF
            LSRB
            ABX
            BCS  LOADLOW
            LSLA
            LSLA
            LSLA
            LSLA
            STA  ,X
            BRA  LOADCH
LOADLOW     ORA  ,X
            STA  ,X
            BRA  LOADCH
LOADEOL     JSR  TAKELINE
            BRA  LOADCH
LOADEND     JSR  TAKELINE       ; (a last line with no end)
            LDB  HANDLE
            LDA  #B_FCLOSE_NAME
            SWI2
            JSR  WRITEMAPS
LOADINI9    RTS
; TAKELINE: the line just read into the table, if it was one.
TAKELINE    LDA  NDIGITS
            CLR  NDIGITS
            CLR  COMMENT
            CMPA #40
            BNE  TAKE9
            LDA  NMAPSIN
            CMPA #NMAPS
            BHS  TAKE9
            LDB  #MAPSIZE
            MUL
            LDY  #TABLE
            LEAY D,Y
            INC  NMAPSIN
            LDX  #LINEBUF
            LDB  #MAPSIZE
TAKE1       LDA  ,X+
            STA  ,Y+
            DECB
            BNE  TAKE1
TAKE9       RTS
; ISHEX: A a hex digit? Carry clear and A its value if so; carry set if not.
ISHEX       CMPA #'0
            BLO  ISHEX8
            CMPA #'9
            BLS  ISHEX1
            CMPA #'A
            BLO  ISHEX8
            CMPA #'F
            BLS  ISHEX2
            CMPA #'a
            BLO  ISHEX8
            CMPA #'f
            BHI  ISHEX8
            SUBA #87            ; ("a" is 10)
            ANDCC #$FE
            RTS
ISHEX2      SUBA #55            ; ("A" is 10)
            ANDCC #$FE
            RTS
ISHEX1      SUBA #'0
            ANDCC #$FE
            RTS
ISHEX8      ORCC #$01
            RTS
; GETCH: the file's next character in A; carry set at its end.
GETCH       LDX  IPTR
            CMPX IEND
            BLO  GETCH1
            LDX  #IOBUF
            LDY  #512
            LDB  HANDLE
            LDA  #B_FREAD
            SWI2
            BCS  GETCH9
            CMPX #0
            BEQ  GETCH8
            LEAX IOBUF,X
            STX  IEND
            LDX  #IOBUF
GETCH1      LDA  ,X+
            STX  IPTR
            ANDCC #$FE
            RTS
GETCH8      ORCC #$01
GETCH9      RTS
; SAVEINI: TABLE to the file, as text. Carry set if it couldn't be written.
SAVEINI     LDU  #IOBUF
            LDX  #T_HEAD
SAVEINI1    LDA  ,X+
            BEQ  SAVEINI2
            STA  ,U+
            BRA  SAVEINI1
SAVEINI2    LDY  #TABLE
            LDB  #NMAPS
            STB  COUNT
SAVEMAP     LDA  ,Y             ; (an empty one has no line)
            ORA  1,Y
            ORA  2,Y
            ORA  3,Y
            BEQ  SAVEMAP9
            LDA  ,Y
            JSR  HEXBYTE
            LDA  1,Y
            JSR  HEXBYTE
            LDA  #' '
            STA  ,U+
            LDA  2,Y
            JSR  HEXBYTE
            LDA  3,Y
            JSR  HEXBYTE
            LDA  #' '
            STA  ,U+
            LEAX 4,Y
            LDB  #16
SAVEMAP1    PSHS B
            LDA  #' '
            STA  ,U+
            LDA  ,X+
            JSR  HEXBYTE
            PULS B
            DECB
            BNE  SAVEMAP1
            LDA  #$0D
            STA  ,U+
            LDA  #$0A
            STA  ,U+
SAVEMAP9    LEAY MAPSIZE,Y
            DEC  COUNT
            BNE  SAVEMAP
            LDX  #T_FILE
            LDE  #FOPEN_WRITE
            LDA  #B_FOPEN_NAME
            SWI2
            BCS  SAVEINI9
            STA  HANDLE
            TFR  U,D
            SUBD #IOBUF
            TFR  D,Y
            LDX  #IOBUF
            LDB  HANDLE
            LDA  #B_FWRITE
            SWI2
            PSHS CC
            LDB  HANDLE
            LDA  #B_FCLOSE_NAME
            SWI2
            PULS CC
SAVEINI9    RTS
;------------------------------------------------------------------------------
            INCLUDE "VIDLIB.ASM"
;------------------------------------------------------------------------------
NAMES       FDB  T_B0,T_B1,T_B2,T_B3,T_B4,T_B5,T_B6,T_B7,T_B8,T_B9,T_B10,T_B11,T_B12
T_B0        FCN  " PRESS SOUTH: THE FACE BUTTON NEAREST YOU"
T_B1        FCN  " PRESS EAST: THE RIGHT FACE BUTTON"
T_B2        FCN  " PRESS WEST: THE LEFT FACE BUTTON"
T_B3        FCN  " PRESS NORTH: THE FACE BUTTON FURTHEST FROM YOU"
T_B4        FCN  " PRESS L: THE LEFT SHOULDER BUTTON"
T_B5        FCN  " PRESS R: THE RIGHT SHOULDER BUTTON"
T_B6        FCN  " PRESS L2: THE LOWER LEFT SHOULDER BUTTON"
T_B7        FCN  " PRESS R2: THE LOWER RIGHT SHOULDER BUTTON"
T_B8        FCN  " PRESS SELECT"
T_B9        FCN  " PRESS START"
T_B10       FCN  " PRESS HOME: THE BUTTON IN THE MIDDLE"
T_B11       FCN  " PRESS L3: CLICK THE LEFT STICK"
T_B12       FCN  " PRESS R3: CLICK THE RIGHT STICK"

T_TITLE     FCN  " GAMEPAD SETUP    ESC:QUIT, NOTHING CHANGED "
T_CHOOSE    FCN  " PRESS A BUTTON ON THE PAD TO SET UP"
T_PADIS     FCN  " PAD "
T_SKIP      FCN  " SPACE: THIS PAD HAS NO SUCH BUTTON"
T_NONE      FCB  0
T_SAVED     FCN  " SAVED IN /CMD/PADMAP.INI    PRESS A KEY"
T_NOSAVE    FCN  " COULD NOT SAVE IT: THE CARD HAS IT UNTIL POWER OFF    PRESS A KEY"
T_FILE      FCN  "/CMD/PADMAP.INI"
T_HEAD      FCC  "; PADMAP.INI: which button is which on each gamepad. PADMAP writes it."
            FCB  $0D,$0A
            FCC  "; A line a pad: its USB vendor and product IDs, then what its buttons"
            FCB  $0D,$0A
            FCC  "; 1 to 16 are, in hex:"
            FCB  $0D,$0A
            FCC  ";   00 South  01 East  02 West  03 North  04 L  05 R  06 L2  07 R2"
            FCB  $0D,$0A
            FCC  ";   08 Select 09 Start 0A Home  0B L3     0C R3     FF nothing"
            FCB  $0D,$0A,0

PADNO       FCB  0
BUTTON      FCB  0
BITNUM      FCB  0
RAWBITS     FDB  0
COUNT       FCB  0
HANDLE      FCB  0
NMAPSIN     FCB  0
NDIGITS     FCB  0
COMMENT     FCB  0
IPTR        FDB  0
IEND        FDB  0
IDS         RMB  32         ; what each pad is, as of this frame
ENTRY       RMB  MAPSIZE    ; the map being made
LINEBUF     RMB  48         ; a line of the file, or of the screen
TABLE       RMB  TABSIZE    ; all the maps
IOBUF       RMB  1024

            END  START
