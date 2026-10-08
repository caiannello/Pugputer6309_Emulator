;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 game kit
;    FILE: gk_ui.asm
;
; What the kit's full-screen editors share, for the video card's mouse,
; keyboard and screen (INCLUDE it after DEFINES.D and VIDCARD.D):
;
;   WAITVB WAITCMD          the next vertical blank; the card's commands done
;   PORT0 PORT1             a data port to A:X, step 1
;   FRECTR ORECTR BLIT16    shapes and 16x16 images, by drawing command
;   MASK16                  a 16x16 one-bit picture into GK_SCRATCH, to BLIT16
;   POLLIN GETKEY           the mouse and the keys
;   TXAT TXCH TXSTR ...     text on the 80x30 text layer (the card's reset one)
;   RDPAL SETPAL UICOLORS   the palette, and the colors the editor itself uses
;   MKPTR                   the mouse pointer: sprite 0, which the card moves
;   PRSTART PRKEY PRSHOW    a line of typing (a file name)
;
; Routines change any register but S unless they say otherwise.
;------------------------------------------------------------------------------
GK_PTR      equ  $037800    ; the pointer's image: 16x16, 8 bits a pixel
GK_SCRATCH  equ  $037900    ; 256 bytes for MASK16 and the like, then BLIT16
PR_MAX      equ  40         ; the longest line PRKEY takes

; WAITVB: wait for the next vertical blank.
WAITVB      LDA  #VC_I_VSYNC
            STA  VC_ISR         ; (clear the flag, then wait for the card to set it)
WAITVB1     LDA  VC_ISR
            BITA #VC_I_VSYNC
            BEQ  WAITVB1
            RTS
; WAITCMD: wait until the card has carried out every command sent -- before
; the CPU writes memory a queued command may still read or draw over.
WAITCMD     LDA  VC_STATUS
            BITA #VC_S_BUSY
            BNE  WAITCMD
            RTS
; PORT0, PORT1: the data port to address A:X (bits 23-16, 15-0), step 1. (D kept.)
PORT0       STA  VC_ADDR0
            STX  VC_ADDR0M
            PSHS D
            LDD  #1
            STD  VC_INC0
            PULS D,PC
PORT1       STA  VC_ADDR1
            STX  VC_ADDR1M
            PSHS D
            LDD  #1
            STD  VC_INC1
            PULS D,PC
; CMDD: D (high byte first) to the command port. (D kept.)
CMDD        STA  VC_CMD
            STB  VC_CMD
            RTS
;------------------------------------------------------------------------------
; Shapes, drawn by the card into the current target.
;------------------------------------------------------------------------------
; FRECTR: a filled rectangle at X, Y, W wide, U high, in color A.
; ORECTR: its outline. (Both keep X, Y, W and U.)
FRECTR      LDB  #C_FILLRECT
            BRA  SHAPER
ORECTR      LDB  #C_RECT
SHAPER      STX  GX
            STY  GY
            STW  GW
            STU  GH
            PSHS B
            LDB  #C_COLOR
            STB  VC_CMD
            STA  VC_CMD
            PULS B
            STB  VC_CMD
            LDD  GX
            BSR  CMDD
            LDD  GY
            BSR  CMDD
            LDD  GW
            BSR  CMDD
            LDD  GH
            BRA  CMDD
; BLIT16: GK_SCRATCH, 16x16 at 8 bits a pixel, to X, Y of the target; A: 1 if
; its 0s are to be left out (see-through), else 0.
BLIT16      PSHS A
            LDA  #C_BLIT
            STA  VC_CMD
            LDA  #GK_SCRATCH/$10000
            STA  VC_CMD
            LDD  #GK_SCRATCH&$FFFF
            BSR  CMDD
            LDD  #16            ; its stride, width, height
            BSR  CMDD
            BSR  CMDD
            BSR  CMDD
            TFR  X,D
            BSR  CMDD
            TFR  Y,D
            BSR  CMDD
            PULS A
            STA  VC_CMD
            RTS
; MASK16: the 16x16 one-bit picture at X (16 words, the leftmost pixel in each
; word's top bit) into GK_SCRATCH: its 1s in color A, its 0s 0.
MASK16      STA  GK_COL
            JSR  WAITCMD        ; (a BLIT may still be reading the last one)
            PSHS X
            LDA  #GK_SCRATCH/$10000
            LDX  #GK_SCRATCH&$FFFF
            JSR  PORT0
            PULS X
            LDE  #16
MASK1       LDD  ,X++
            STD  GK_BITS
            LDF  #16
MASK2       CLRA
            LSL  GK_BITS+1
            ROL  GK_BITS
            BCC  MASK3
            LDA  GK_COL
MASK3       STA  VC_DATA0
            DECF
            BNE  MASK2
            DECE
            BNE  MASK1
            RTS
;------------------------------------------------------------------------------
; The mouse and the keys.
;------------------------------------------------------------------------------
; POLLIN: MOUSEX, MOUSEY (640x480), BUTTONS (bit 0 left, 1 right, 2 middle),
; PRESSED and RELEASED (the buttons that went down or up since the last call),
; WHEEL (clicks since then, signed).
POLLIN      LDD  VC_MOUSEX      ; (this takes the snapshot of X and Y)
            STD  MOUSEX
            LDD  VC_MOUSEY
            STD  MOUSEY
            LDA  BUTTONS
            STA  OLDBTN
            LDA  VC_MOUSEB
            ANDA #VC_MB_LEFT+VC_MB_RIGHT+VC_MB_MID
            STA  BUTTONS
            LDB  OLDBTN
            COMB
            ANDB BUTTONS
            STB  PRESSED
            COMA
            ANDA OLDBTN
            STA  RELEASED
            LDA  VC_WHEEL
            STA  WHEEL
            RTS
; GETKEY: the next key event, if there is one: Z clear, A its USB usage code,
; B the character it typed (bit 7 set: a release); KEYMODS the modifiers held
; as of that event (followed from the queue's own events, not VC_KEYMODS, which
; is how they are now -- a quick Shift+key is let go before it is read). Z set
; if there was none.
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
; Text, on the 80x30 text layer at VC_TEXTMAP (128 cells a row): each character
; in TXFG on TXBG (0: see-through).
;------------------------------------------------------------------------------
; TXAT: data port 0 to column A, row B. (D, X kept.)
TXAT        PSHS D,X
            PSHS A
            LDA  #128
            MUL                 ; D = row * 128
            ADDB ,S+
            ADCA #0             ; + column
            LSLD
            LSLD                ; * 4 bytes a cell
            ADDD #VC_TEXTMAP&$FFFF
            TFR  D,X
            LDA  #VC_TEXTMAP/$10000
            JSR  PORT0
            PULS D,X,PC
; TXCH: the character A. (Every register kept.)
TXCH        STA  VC_DATA0
            PSHS A
            LDA  TXFG
            STA  VC_DATA0
            LDA  TXBG
            STA  VC_DATA0
            CLRA
            STA  VC_DATA0
            PULS A,PC
; TXSTR: the string at X (0 at its end); X is left after its 0.
TXSTR       LDA  ,X+
            BEQ  TXSTR9
            BSR  TXCH
            BRA  TXSTR
TXSTR9      RTS
; TXSPC: B spaces.
TXSPC       TSTB
            BEQ  TXSPC9
            LDA  #$20
TXSPC1      BSR  TXCH
            DECB
            BNE  TXSPC1
TXSPC9      RTS
; TXFIELD: the string at X in a field B characters wide: cut short, or padded
; with spaces.
TXFIELD     TSTB
            BEQ  TXSPC9
            LDA  ,X+
            BEQ  TXSPC
            BSR  TXCH
            DECB
            BRA  TXFIELD
; TXDEC4: D (0-9999) as four digits; TXDEC3: D (0-999) as three; TXDEC2:
; B (0-99) as two.
TXDEC4      DIVD #100           ; B = hundreds, A = the rest
            PSHS A
            BSR  TXDEC2
            PULS B
            BRA  TXDEC2
TXDEC3      DIVD #100
            PSHS A
            TFR  B,A
            ADDA #'0
            BSR  TXCH
            PULS B
TXDEC2      CLRA
            DIVD #10            ; B = tens, A = ones
            PSHS A
            TFR  B,A
            ADDA #'0
            BSR  TXCH
            PULS A
            ADDA #'0
            BRA  TXCH
; TXHEX2: A as two hex digits.
TXHEX2      PSHS A
            LSRA
            LSRA
            LSRA
            LSRA
            BSR  TXHEX1
            PULS A
            ANDA #$0F
TXHEX1      ADDA #'0
            CMPA #'9
            BLS  TXCH
            ADDA #'A-'9-1
            BRA  TXCH
; TXROW: blank columns A to A+B-1 of row E, then put port 0 back at column A.
TXROW       PSHS D
            TFR  E,B
            JSR  TXAT
            LDB  1,S
            BSR  TXSPC
            PULS D
            TFR  E,B
            JMP  TXAT
;------------------------------------------------------------------------------
; The palette (PALBUF: the card's 256 colors, RGB565, high byte first), and the
; colors the editor draws itself in, chosen from it so that they show whatever
; it holds: UI_BG the darkest, UI_FG the brightest, UI_MID the nearest 3/8
; of the way between (grays preferred), UI_HI the most yellow. (Never color 0, which shows through.)
;------------------------------------------------------------------------------
; RDPAL: PALBUF from the card.
RDPAL       LDA  #VC_PAL/$10000
            LDX  #VC_PAL&$FFFF
            JSR  PORT1
            LDX  #VC_DATA1
            LDY  #PALBUF
            LDW  #512
            TFM  X,Y+
            RTS
; WRPAL: the card's palette from PALBUF.
WRPAL       LDA  #VC_PAL/$10000
            LDX  #VC_PAL&$FFFF
            JSR  PORT0
            LDX  #PALBUF
            LDY  #VC_DATA0
            LDW  #512
            TFM  X+,Y
            RTS
; SETPAL: color B on the card from PALBUF.
SETPAL      CLRA
            LSLD
            PSHS D
            ADDD #VC_PAL&$FFFF
            TFR  D,X
            LDA  #VC_PAL/$10000
            JSR  PORT0
            PULS X
            LDD  PALBUF,X
            STA  VC_DATA0
            STB  VC_DATA0
            RTS
; RGBOF: color B's parts from PALBUF: GK_R (0-31), GK_G (0-63), GK_B (0-31).
RGBOF       CLRA
            LSLD
            TFR  D,X
            LDD  PALBUF,X
            ANDB #$1F
            STB  GK_B
            LDD  PALBUF,X
            LSRA
            LSRA
            LSRA
            STA  GK_R
            LDD  PALBUF,X
            LSRD
            LSRD
            LSRD
            LSRD
            LSRD
            ANDB #$3F
            STB  GK_G
            RTS
; RGBTO: color B in PALBUF (and on the card) from GK_R, GK_G, GK_B.
RGBTO       PSHS B
            LDA  GK_R
            LSLA
            LSLA
            LSLA                ; RRRRR000
            LDB  GK_G
            LSRB
            LSRB
            LSRB                ; 00000GGG (its top 3)
            PSHS B
            ORA  ,S+
            PSHS A
            LDA  GK_G
            ANDA #$07
            LSLA
            LSLA
            LSLA
            LSLA
            LSLA                ; GGG00000 (its low 3)
            ORA  GK_B
            TFR  A,B
            PULS A              ; D = the color
            PSHS D
            LDB  2,S
            CLRA
            LSLD
            TFR  D,X
            PULS D
            STD  PALBUF,X
            PULS B
            BRA  SETPAL
; LUMA: color B's brightness, 0-2003 (19R + 19G + 7B), in D.
LUMA        JSR  RGBOF
            LDB  GK_R
            ADDB GK_G
            LDA  #19
            MUL
            STD  GK_T
            LDB  GK_B
            LDA  #7
            MUL
            ADDD GK_T
            RTS
; CHROMA: B = how colorful GK_R, GK_G, GK_B are: the most of 2R, G, 2B less
; the least (0-63; 0 a gray).
CHROMA      LDA  GK_R
            LSLA
            LDB  GK_B
            LSLB
            STA  GK_COL         ; (max in A, min in B, of 2R and 2B)
            CMPB GK_COL
            BLS  CHROMA1
            EXG  A,B
CHROMA1     CMPA GK_G
            BHS  CHROMA2
            LDA  GK_G
CHROMA2     CMPB GK_G
            BLS  CHROMA3
            LDB  GK_G
CHROMA3     STB  GK_COL
            SUBA GK_COL
            TFR  A,B
            RTS
; YELLOW: how yellow color B is (2R + G - 2B), signed, in D.
YELLOW      JSR  RGBOF
            LDB  GK_R
            LSLB
            ADDB GK_G
            CLRA
            STD  GK_T
            LDB  GK_B
            LSLB
            CLRA
            PSHS D
            LDD  GK_T
            SUBD ,S++
            RTS
; UICOLORS: UI_BG, UI_FG, UI_MID, UI_HI from PALBUF. A: 1 if any changed, else 0.
UICOLORS    LDQ  UI_BG
            STQ  GK_OLD
            LDD  #$7FFF
            STD  GK_MIN
            LDD  #-1
            STD  GK_MAX
            LDB  #1
UIC1        PSHS B              ; the darkest and the brightest
            JSR  LUMA
            STD  GK_T
            CMPD GK_MIN
            BGE  UIC2
            STD  GK_MIN
            LDA  ,S
            STA  UI_BG
            LDD  GK_T
UIC2        CMPD GK_MAX
            BLE  UIC3
            STD  GK_MAX
            LDA  ,S
            STA  UI_FG
UIC3        PULS B
            INCB
            BNE  UIC1
            LDD  GK_MAX         ; the nearest to 3/8 of the way up
            SUBD GK_MIN
            LSRD
            LSRD
            STD  GK_MID
            LSRD
            ADDD GK_MID
            ADDD GK_MIN
            STD  GK_MID
            LDD  #$7FFF
            STD  GK_MIN
            LDB  #1
UIC4        PSHS B
            JSR  LUMA
            SUBD GK_MID
            BPL  UIC5
            NEGD
UIC5        STD  GK_T           ; (grays first: how colorful, x16, counts against it)
            JSR  CHROMA
            LDA  #16
            MUL
            ADDD GK_T
            CMPD GK_MIN
            BGE  UIC6
            STD  GK_MIN
            LDA  ,S
            STA  UI_MID
UIC6        PULS B
            INCB
            BNE  UIC4
            LDD  #-$7FFF        ; the most yellow
            STD  GK_MAX
            LDB  #1
UIC7        PSHS B
            JSR  YELLOW
            CMPD GK_MAX
            BLE  UIC8
            STD  GK_MAX
            LDA  ,S
            STA  UI_HI
UIC8        PULS B
            INCB
            BNE  UIC7
            LDQ  UI_BG          ; changed?
            CMPD GK_OLD
            BNE  UIC9
            CMPW GK_OLD+2
            BNE  UIC9
            CLRA
            RTS
UIC9        LDA  #1
            RTS
;------------------------------------------------------------------------------
; The pointer: sprite 0 (the program sets the sprites up: GK_PTR is its image),
; an arrow in UI_FG outlined in UI_BG, its point at the top left.
;------------------------------------------------------------------------------
MKPTR       LDA  #GK_PTR/$10000
            LDX  #GK_PTR&$FFFF
            JSR  PORT0
            LDX  #PTRMASK
            LDE  #16
MKPTR1      LDD  ,X++
            STD  GK_BITS        ; the inside
            LDD  ,X++
            STD  GK_T           ; the outline
            LDF  #16
MKPTR2      CLRA
            LSL  GK_T+1
            ROL  GK_T
            BCC  MKPTR3
            LDA  UI_BG
MKPTR3      LSL  GK_BITS+1
            ROL  GK_BITS
            BCC  MKPTR4
            LDA  UI_FG
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
; A line of typing: PRSTART with X the question, Y the text to start with (or
; 0); then PRKEY with each key (A usage, B character) -- it answers A = 0 (go
; on), 1 (Enter: PR_BUF holds the line, 0 at its end) or 2 (Esc) -- and PRSHOW
; to show it at column PR_COL, row PR_ROW, PR_WIDE characters wide.
;------------------------------------------------------------------------------
PRSTART     STX  PR_ASK
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
            RTS
PRKEY       CMPA #K_ENTER
            BEQ  PRKEY1
            CMPA #K_KPENTER
            BEQ  PRKEY1
            CMPA #K_ESC
            BEQ  PRKEY2
            CMPA #K_BKSP
            BEQ  PRKEY3
            CMPB #$20
            BLS  PRKEY0         ; (a space, or nothing typed: not in a name)
            CMPB #$7F
            BHS  PRKEY0
            CMPB #'a            ; names are upper case
            BLO  PRKEY4
            CMPB #'z
            BHI  PRKEY4
            SUBB #$20
PRKEY4      LDA  PR_LEN
            CMPA #PR_MAX
            BHS  PRKEY0
            LDX  #PR_BUF
            LEAX A,X
            STB  ,X+
            CLR  ,X
            INC  PR_LEN
PRKEY0      CLRA
            RTS
PRKEY3      LDA  PR_LEN
            BEQ  PRKEY0
            DECA
            STA  PR_LEN
            LDX  #PR_BUF
            CLR  A,X
            BRA  PRKEY0
PRKEY1      LDA  #1
            RTS
PRKEY2      LDA  #2
            RTS
PRSHOW      LDA  PR_COL
            LDB  PR_WIDE
            LDE  PR_ROW
            JSR  TXROW
            LDX  PR_ASK
            JSR  TXSTR
            LDX  #PR_BUF
            JSR  TXSTR
            LDA  #'_
            JMP  TXCH
;------------------------------------------------------------------------------
; Their variables.
;------------------------------------------------------------------------------
MOUSEX      FDB  0
MOUSEY      FDB  0
BUTTONS     FCB  0
OLDBTN      FCB  0
PRESSED     FCB  0
RELEASED    FCB  0
WHEEL       FCB  0
KEYMODS     FCB  0
TXFG        FCB  15
TXBG        FCB  0
UI_BG       FCB  16         ; (these four in this order: UICOLORS takes them as one)
UI_FG       FCB  15
UI_MID      FCB  244
UI_HI       FCB  226
GK_OLD      FCB  0,0,0,0
GK_MIN      FDB  0
GK_MAX      FDB  0
GK_MID      FDB  0
GK_T        FDB  0
GK_BITS     FDB  0
GK_COL      FCB  0
GK_R        FCB  0
GK_G        FCB  0
GK_B        FCB  0
GX          FDB  0
GY          FDB  0
GW          FDB  0
GH          FDB  0
PR_ASK      FDB  0
PR_LEN      FCB  0
PR_COL      FCB  0
PR_ROW      FCB  0
PR_WIDE     FCB  80
PR_BUF      RMB  PR_MAX+1
PALBUF      RMB  512
