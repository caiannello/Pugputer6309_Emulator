;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 game kit
;    FILE: tk_ini.asm
;
; TILEKIT.INI: the palettes a new tile set starts with, one for 256-color sets
; and one for 16-color sets, as text (in the current directory, else in /CMD):
;
;   ; a comment, to the end of the line
;   [PALETTE8]
;   000000 800000 008000 ...      256 colors, RRGGBB in hex (a # before
;   [PALETTE4]                    one is allowed), in order from color 0,
;   000000 1D2B53 7E2553 ...      as many as are given: the rest are the
;                                 card's own (xterm's)
;
; Read 512 bytes at a time into IOBUF. INCLUDEd by tilekit.asm.
;------------------------------------------------------------------------------
; INILOAD: PAL8BUF / NPAL8 and PAL4BUF / NPAL4 from TILEKIT.INI, if there is one.
INILOAD     CLRD
            STD  NPAL8
            STD  NPAL4
            LDX  #T_INIHERE
            JSR  INIOPEN
            BCC  INILOAD1
            LDX  #T_INICMD
            JSR  INIOPEN
            LBCS INILOAD9
INILOAD1    CLRD
            STD  IDEST          ; (no section yet: colors before one are ignored)
            LDX  #IOBUF
            STX  IPTR
            STX  IEND
INI1        JSR  INICH          ; the next character
            LBCS INIEND
INI2        CMPA #';
            BEQ  INICOMM
            CMPA #'[
            BEQ  INISECT
            JSR  ISHEX
            BCC  INITOKEN
            BRA  INI1           ; (anything else just separates)
INICOMM     JSR  INICH          ; a comment: to the end of the line
            LBCS INIEND
            CMPA #$0A
            BEQ  INI1
            CMPA #$0D
            BEQ  INI1
            BRA  INICOMM
INISECT     LDU  #ISECT         ; a section: its name, to the ] (U: INICH
INISECT1    JSR  INICH          ; uses X and Y)
            LBCS INIEND
            CMPA #']
            BEQ  INISECT2
            CMPA #'a
            BLO  INISECT3
            SUBA #$20           ; (upper case)
INISECT3    CMPU #ISECT+10
            BHS  INISECT1
            STA  ,U+
            BRA  INISECT1
INISECT2    CLR  ,U
            CLRD
            STD  IDEST
            STD  IIDX
            LDX  #ISECT
            LDY  #T_SECT8
            JSR  STRCMP
            BNE  INISECT4
            LDX  #PAL8BUF
            LDY  #NPAL8
            BRA  INISECT5
INISECT4    LDX  #ISECT
            LDY  #T_SECT4
            JSR  STRCMP
            BNE  INI1           ; (another section: ignored)
            LDX  #PAL4BUF
            LDY  #NPAL4
INISECT5    STX  IDEST
            STY  ICOUNT
            BRA  INI1
INITOKEN    CLR  IDIG           ; hex digits, A the first one's value
INITOK1     LDB  IDIG
            CMPB #6
            BHS  INITOK2        ; (more than 6: not a color, as it will be counted)
            LDX  #IHEX
            STA  B,X
INITOK2     INC  IDIG
            JSR  INICH
            BCS  INITOK3
            JSR  ISHEX
            BCC  INITOK1
            PSHS A              ; the end of it: a color?
            BSR  INICOLOR
            PULS A
            LBRA INI2           ; (and on with the character after it)
INITOK3     BSR  INICOLOR
INIEND      LDB  IHANDLE
            LDA  #B_FCLOSE_NAME
            SWI2
INILOAD9    RTS
; INIOPEN: TILEKIT.INI at X opened. Carry set if it isn't there.
INIOPEN     LDE  #FOPEN_READ
            LDA  #B_FOPEN_NAME
            SWI2
            BCS  INIOPEN9
            STA  IHANDLE
INIOPEN9    RTS
; INICOLOR: the hex digits read were a color (6 of them, in a section, room for
; it): into the section's palette, RGB565.
INICOLOR    LDA  IDIG
            CMPA #6
            BNE  INICOLOR9
            LDX  IDEST
            BEQ  INICOLOR9
            LDD  IIDX
            CMPD #256
            BHS  INICOLOR9
            LDA  IHEX           ; red: its top 5 bits
            LSLA
            LSLA
            LSLA
            LSLA
            ORA  IHEX+1
            ANDA #$F8
            STA  IHI
            LDA  IHEX+2         ; green: its top 6, 3 in each byte
            LSLA
            LSLA
            LSLA
            LSLA
            ORA  IHEX+3
            STA  ILO
            LSRA
            LSRA
            LSRA
            LSRA
            LSRA
            ORA  IHI
            STA  IHI
            LDA  ILO
            LSLA
            LSLA
            LSLA
            ANDA #$E0
            STA  ILO
            LDA  IHEX+4         ; blue: its top 5
            LSLA
            LSLA
            LSLA
            LSLA
            ORA  IHEX+5
            LSRA
            LSRA
            LSRA
            ORA  ILO
            TFR  A,B
            LDA  IHI
            PSHS D
            LDD  IIDX
            LSLD
            LEAX D,X
            PULS D
            STD  ,X
            LDD  IIDX
            ADDD #1
            STD  IIDX
            STD  [ICOUNT]
INICOLOR9   RTS
; ISHEX: A a hex digit? Carry clear and A its value if so; carry set and A
; kept if not.
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
            SUBA #'a-10
            ANDCC #$FE
            RTS
ISHEX2      SUBA #'A-10
            ANDCC #$FE
            RTS
ISHEX1      SUBA #'0
            ANDCC #$FE
            RTS
ISHEX8      ORCC #$01
            RTS
; INICH: the file's next character in A; carry set at its end.
INICH       LDX  IPTR
            CMPX IEND
            BLO  INICH1
            LDX  #IOBUF         ; the next 512 bytes
            LDY  #512
            LDB  IHANDLE
            LDA  #B_FREAD
            SWI2
            BCS  INICH9
            CMPX #0
            BEQ  INICH8
            LEAX IOBUF,X
            STX  IEND
            LDX  #IOBUF
INICH1      LDA  ,X+
            STX  IPTR
            ANDCC #$FE
            RTS
INICH8      ORCC #$01
INICH9      RTS
; APPLYPAL: the card's palette (just reset: xterm's) with the defaults for this
; kind of set, as many as TILEKIT.INI gave.
APPLYPAL    LDX  #PAL8BUF
            LDD  NPAL8
            PSHS D
            LDA  BPP
            CMPA #8
            PULS D
            BEQ  APPLYPAL2
            LDX  #PAL4BUF
            LDD  NPAL4
APPLYPAL2   CMPD #0
            BEQ  APPLYPAL9
            LSLD                ; 2 bytes a color
            TFR  D,W
            PSHS X
            LDA  #VC_PAL/$10000
            LDX  #VC_PAL&$FFFF
            JSR  PORT0
            PULS X
            LDY  #VC_DATA0
            TFM  X+,Y
APPLYPAL9   RTS
;------------------------------------------------------------------------------
T_INIHERE   FCN  "TILEKIT.INI"
T_INICMD    FCN  "/CMD/TILEKIT.INI"
T_SECT8     FCN  "PALETTE8"
T_SECT4     FCN  "PALETTE4"
NPAL8       FDB  0          ; colors given for 256-color sets
NPAL4       FDB  0          ;   and for 16-color ones
IHANDLE     FCB  0
IPTR        FDB  0
IEND        FDB  0
IDEST       FDB  0          ; the section's palette (0: none)
ICOUNT      FDB  0          ;   and where its count goes
IIDX        FDB  0
IDIG        FCB  0
IHEX        FCB  0,0,0,0,0,0
IHI         FCB  0
ILO         FCB  0
ISECT       FCB  0,0,0,0,0,0,0,0,0,0,0
