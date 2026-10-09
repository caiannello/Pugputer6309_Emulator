;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 game kit
;    FILE: tk_proj.asm
;
; TILEKIT's projects: a .TKT file, text, naming everything -- each layer's tile
; set and map files, how it is shown, the layers' order, the palette:
;
;   ; a comment
;   [PROJECT]
;   ORDER 1 2 3          the layers from the back
;   EDIT 1               the one being edited
;   [LAYER1]             (and [LAYER2], [LAYER3])
;   TILES SET1.TLS       its tile set (layers naming the same file share it)
;   MAP LV1.MAP          its map
;   SCREEN 320           320 (x240) or 640 (x480)
;   SHOW YES             shown, or NO
;   [PALETTE]
;   000000 800000 ...    the palette, RRGGBB, from color 0
;
; (= and , count as spaces.) Saving one saves the tile sets and maps that have
; changed too -- those with no names yet named after the project: LEVEL.TKT's
; are LEVEL1.TLS, LEVEL1.MAP, LEVEL2.MAP ... INCLUDEd by tilekit.asm.
;------------------------------------------------------------------------------
TOKMAX      equ  40
;------------------------------------------------------------------------------
; Switching layers quietly (while a project is saved or opened).
;------------------------------------------------------------------------------
; SWITCHQ: layer B to edit, nothing drawn.
SWITCHQ     CMPB CURL
            BEQ  SWITCHQ9
            PSHS B
            JSR  FLUSHTILE
            JSR  STOREREC
            JSR  TROWOUT
            PULS B
            STB  CURL
            JSR  LOADREC
            JSR  TROWIN
            JSR  SETPROJ
            JSR  MAPCALC        ; (where its map is)
            JSR  LOADTILE
SWITCHQ9    RTS
; ANYMOD: anything not saved? (Z clear if so: tile sets in use, maps, the
; project's own settings.)
ANYMOD      JSR  STOREREC
            LDA  PROJCHG
            BNE  ANYMOD9
            LDB  #2
ANYMOD1     JSR  LREC
            LDA  LR_MOD,X
            BNE  ANYMOD9
            PSHS B
            LDB  LR_SET,X       ; (its tile set)
            JSR  TSREC
            PULS B
            LDA  TS_MOD,X
            BNE  ANYMOD9
            DECB
            BPL  ANYMOD1
            CLRA                ; (none: Z set)
ANYMOD9     RTS
;------------------------------------------------------------------------------
; Saving.
;------------------------------------------------------------------------------
; SAVEPROJ: the project to the file named at X (PROJNAME, if that works): the
; tile sets and maps first.
SAVEPROJ    LDY  #PPATH         ; (the name kept: the components' come from it)
            JSR  STRCPY
            JSR  PSTEM
            LDA  CURL
            STA  PORIG
            CLR  PFAIL
            CLR  PSLOT          ; each tile set in use: saved if changed, or new
SAVEPROJ1   LDB  PSLOT
            JSR  SLOTUSER       ; (a layer using it: B; carry if none)
            BCS  SAVEPROJ3
            JSR  SWITCHQ
            TST  FILENAME
            BEQ  SAVEPROJ2
            TST  MODIFIED
            BEQ  SAVEPROJ3
SAVEPROJ2   LDB  PSLOT          ; (no name: the project's, the slot's number)
            LDX  #FILENAME
            LDY  #T_EXT
            JSR  PNAME
            LDX  #FILENAME
            JSR  SAVEFILE
            LBCS SAVEPROJ9
SAVEPROJ3   INC  PSLOT
            LDA  PSLOT
            CMPA #3
            BLO  SAVEPROJ1
            CLR  PSLOT          ; each map: the same
SAVEPROJ4   LDB  PSLOT
            JSR  SWITCHQ
            TST  MAPNAME
            BEQ  SAVEPROJ5
            TST  MAPMOD
            BEQ  SAVEPROJ6
SAVEPROJ5   LDB  PSLOT
            LDX  #MAPNAME
            LDY  #T_EXTMAP
            JSR  PNAME
            LDX  #MAPNAME
            JSR  SAVEMAP
            LBCS SAVEPROJ9
SAVEPROJ6   INC  PSLOT
            LDA  PSLOT
            CMPA #3
            BLO  SAVEPROJ4
            JSR  STOREREC       ; the project itself
            LDX  #PPATH
            JSR  OUTOPEN
            LBCS SAVEPROJE
            LDX  #T_TKT0
            JSR  OUTTEXT
            LDX  #ORDER         ; ORDER a b c
            LDE  #3
SAVEPROJ7   LDA  #$20
            JSR  OUTCH
            LDA  ,X+
            ADDA #'1
            JSR  OUTCH
            DECE
            BNE  SAVEPROJ7
            LDX  #T_TKTEDIT     ; EDIT n
            JSR  OUTTEXT
            LDA  PORIG
            ADDA #'1
            JSR  OUTCH
            JSR  OUTNL
            CLR  PSLOT          ; each layer's section
SAVEPROJ8   LDX  #T_TKTLAY
            JSR  OUTTEXT
            LDA  PSLOT
            ADDA #'1
            JSR  OUTCH
            LDX  #T_TKTTILES
            JSR  OUTTEXT
            LDB  PSLOT
            JSR  LREC
            STX  LRP
            LDB  LR_SET,X
            JSR  TSREC
            LEAX TS_NAME,X
            JSR  OUTTEXT
            LDX  #T_TKTMAP
            JSR  OUTTEXT
            LDX  LRP
            LEAX LR_NAME,X
            JSR  OUTTEXT
            LDX  #T_TKTSCR
            JSR  OUTTEXT
            LDX  #T_320
            LDY  LRP
            TST  LR_HIRES,Y
            BEQ  SAVEPROJ10
            LDX  #T_640
SAVEPROJ10  JSR  OUTTEXT
            LDX  #T_TKTSHOW
            JSR  OUTTEXT
            LDX  #T_YES
            LDY  LRP
            TST  LR_SHOW,Y
            BNE  SAVEPROJ11
            LDX  #T_NO
SAVEPROJ11  JSR  OUTTEXT
            JSR  OUTNL
            INC  PSLOT
            LDA  PSLOT
            CMPA #3
            LBLO SAVEPROJ8
            LDX  #T_TKTPAL      ; the palette: 16 lines of 16
            JSR  OUTTEXT
            LDX  #PALBUF
            LDF  #16
SAVEPROJ12  LDE  #16
SAVEPROJ13  LDD  ,X++
            JSR  OUTRGB
            DECE
            BEQ  SAVEPROJ14
            LDA  #$20
            JSR  OUTCH
            BRA  SAVEPROJ13
SAVEPROJ14  JSR  OUTNL
            DECF
            BNE  SAVEPROJ12
            LDX  #T_PSAVED
            STX  OUTMSG
            JSR  OUTCLOSE
            LDX  #T_EXPORTED
            STX  OUTMSG
            BCS  SAVEPROJ9
            LDX  #PPATH         ; it is the project's file now
            LDY  #PROJNAME
            JSR  STRCPY
            CLR  PROJCHG
SAVEPROJ9   LDB  PORIG          ; back to the layer being edited
            JSR  SWITCHQ
            LDA  #1
            STA  STATDIRTY
            JMP  REDRAWBACK
SAVEPROJE   JSR  FILEERR
            BRA  SAVEPROJ9
; OUTRGB: color D (RGB565) as RRGGBB.
OUTRGB      PSHS D
            LSRA                ; red: its 5 bits, twice over in 8
            LSRA
            LSRA
            STA  GK_T
            LSLA
            LSLA
            LSLA
            PSHS A
            LDA  GK_T
            LSRA
            LSRA
            ORA  ,S+
            JSR  OUTHEXA
            LDD  ,S             ; green: its 6 bits
            LSRD
            LSRD
            LSRD
            LSRD
            LSRD
            ANDB #$3F
            TFR  B,A
            STA  GK_T
            LSLA
            LSLA
            PSHS A
            LDA  GK_T
            LSRA
            LSRA
            LSRA
            LSRA
            ORA  ,S+
            JSR  OUTHEXA
            PULS D              ; blue: its 5
            ANDB #$1F
            TFR  B,A
            STA  GK_T
            LSLA
            LSLA
            LSLA
            PSHS A
            LDA  GK_T
            LSRA
            LSRA
            ORA  ,S+
            JMP  OUTHEXA
; SLOTUSER: B = a layer whose tile set is slot B (the first); carry if none.
SLOTUSER    STB  GK_COL
            CLRB
SLOTUSER1   JSR  LREC
            LDA  LR_SET,X
            CMPA GK_COL
            BEQ  SLOTUSER9
            INCB
            CMPB #3
            BLO  SLOTUSER1
            ORCC #$01
            RTS
SLOTUSER9   ANDCC #$FE
            RTS
; PSTEM: PSTEMBUF = the project's name, without its directories or extension,
; at most 7 characters (so that a digit fits after it).
PSTEM       LDX  #PPATH
            TFR  X,Y
PSTEM1      LDA  ,X+            ; (its last name)
            BEQ  PSTEM2
            CMPA #'/
            BNE  PSTEM1
            TFR  X,Y
            BRA  PSTEM1
PSTEM2      LDX  #PSTEMBUF
            LDB  #7
PSTEM3      LDA  ,Y+
            BEQ  PSTEM4
            CMPA #'.
            BEQ  PSTEM4
            STA  ,X+
            DECB
            BNE  PSTEM3
PSTEM4      CLR  ,X
            RTS
; PNAME: the name at X: PSTEMBUF, the digit B+1, then the extension at Y.
PNAME       PSHS Y,B
            LDY  #PSTEMBUF
PNAME1      LDA  ,Y+
            BEQ  PNAME2
            STA  ,X+
            BRA  PNAME1
PNAME2      PULS B
            ADDB #'1
            STB  ,X+
            PULS Y
PNAME3      LDA  ,Y+
            STA  ,X+
            BNE  PNAME3
            RTS
;------------------------------------------------------------------------------
; Opening.
;------------------------------------------------------------------------------
; LOADPROJ: the project in the file named at X: read it all first, then a new
; set of layers, and what it names loaded into them.
LOADPROJ    LDY  #PPATH
            JSR  STRCPY
            LDX  #PPATH
            LDE  #FOPEN_READ
            LDA  #B_FOPEN_NAME
            SWI2
            LBCS FILEERR
            STA  IHANDLE
            LDX  #IOBUF
            STX  IPTR
            STX  IEND
            CLR  PCOMM
            LDX  #STAGE         ; what it says, to start with: nothing
            LDW  #STAGEEND-STAGE
LOADPROJ1   CLR  ,X+
            DECW
            BNE  LOADPROJ1
            LDD  #$0001         ; (the order 1 2 3, all shown)
            STD  SORDER
            LDA  #2
            STA  SORDER+2
            LDD  #$0101
            STD  SSHOW
            STA  SSHOW+2
            CLR  PSECT
LOADPROJ2   JSR  GETTOK         ; each word
            LBCS LOADPROJ8
            TST  TOKSECT
            BEQ  LOADPROJ3
            JSR  SECTOF         ; a section: which
            STA  PSECT
            BRA  LOADPROJ2
LOADPROJ3   LDA  PSECT
            CMPA #1
            LBEQ LPPROJ
            CMPA #5
            LBEQ LPPAL
            CMPA #2
            BLO  LOADPROJ2
            SUBA #2             ; a layer's: A its number (0-2)
            STA  PLAY
            LDX  #T_KTILES
            JSR  TOKIS
            BNE  LPL1
            JSR  GETTOK         ; TILES name
            LBCS LOADPROJ8
            LDB  PLAY
            LDA  #TOKMAX+1
            MUL
            ADDD #STILES
            TFR  D,Y
            LDX  #TOKBUF
            JSR  STRCPY
            BRA  LOADPROJ2
LPL1        LDX  #T_KMAP
            JSR  TOKIS
            BNE  LPL2
            JSR  GETTOK         ; MAP name
            LBCS LOADPROJ8
            LDB  PLAY
            LDA  #TOKMAX+1
            MUL
            ADDD #SMAP
            TFR  D,Y
            LDX  #TOKBUF
            JSR  STRCPY
            BRA  LOADPROJ2
LPL2        LDX  #T_KSCREEN
            JSR  TOKIS
            BNE  LPL3
            JSR  GETTOK         ; SCREEN 640 (or 320)
            LBCS LOADPROJ8
            LDX  #SSCREEN
            LDB  PLAY
            CLR  B,X
            LDA  TOKBUF
            CMPA #'6
            LBNE LOADPROJ2
            INC  B,X
            LBRA LOADPROJ2
LPL3        LDX  #T_KSHOW
            JSR  TOKIS
            LBNE LOADPROJ2
            JSR  GETTOK         ; SHOW YES (or NO, 0)
            LBCS LOADPROJ8
            LDX  #SSHOW
            LDB  PLAY
            CLR  B,X
            LDA  TOKBUF
            CMPA #'N
            LBEQ LOADPROJ2
            CMPA #'0
            LBEQ LOADPROJ2
            INC  B,X
            LBRA LOADPROJ2
LPPROJ      LDX  #T_KORDER
            JSR  TOKIS
            BNE  LPP2
            LDY  #SORDER        ; ORDER a b c
            LDE  #3
LPP1        PSHS Y
            JSR  GETTOK
            PULS Y
            LBCS LOADPROJ8
            LDA  TOKBUF
            SUBA #'1
            STA  ,Y+
            DECE
            BNE  LPP1
            LBRA LOADPROJ2
LPP2        LDX  #T_KEDIT
            JSR  TOKIS
            LBNE LOADPROJ2
            JSR  GETTOK         ; EDIT n
            LBCS LOADPROJ8
            LDA  TOKBUF
            SUBA #'1
            STA  SEDIT
            LBRA LOADPROJ2
LPPAL       LDX  #TOKBUF        ; a color: 6 hex digits
            CLRB
LPPAL1      LDA  ,X+
            BEQ  LPPAL2
            JSR  ISHEX
            LBCS LOADPROJ2
            LDY  #IHEX
            CMPB #6
            BHS  LPPAL15
            STA  B,Y
LPPAL15     INCB
            BRA  LPPAL1
LPPAL2      STB  IDIG
            LDX  #SPAL
            STX  IDEST
            LDX  #SNPAL
            STX  ICOUNT
            LDD  SNPAL
            STD  IIDX
            JSR  INICOLOR
            LBRA LOADPROJ2
LOADPROJ8   LDB  IHANDLE        ; all read: now, what it says
            LDA  #B_FCLOSE_NAME
            SWI2
            LDA  SORDER         ; (the order: 0 1 2 in some order, or not used)
            ADDA SORDER+1
            ADDA SORDER+2
            CMPA #3
            BEQ  LOADPROJ9
            LDD  #$0001
            STD  SORDER
            LDA  #2
            STA  SORDER+2
LOADPROJ9   JSR  NEWPROJ        ; a new set of layers, the card as it starts
            CLR  PSLOT          ; each layer's tile set: one named already by
LOADPROJ10  LDB  PSLOT          ; another layer is shared; else loaded into its
            JSR  SWITCHQ        ; own slot
            LDB  PSLOT
            LDA  #TOKMAX+1
            MUL
            ADDD #STILES
            STD  PNAMEP
            TFR  D,X
            TST  ,X
            BEQ  LOADPROJ13
            CLRB                ; named by an earlier layer?
LOADPROJ11  CMPB PSLOT
            BHS  LOADPROJ12
            PSHS B
            LDA  #TOKMAX+1
            MUL
            ADDD #STILES
            TFR  D,Y
            LDX  PNAMEP
            JSR  STRCMP
            PULS B
            BEQ  LOADPROJ115
            INCB
            BRA  LOADPROJ11
LOADPROJ115 JSR  LREC           ; (yes: layer B's tile set)
            LDA  LR_SET,X
            PSHS A
            LDB  PSLOT
            JSR  LREC
            PULS A
            STA  LR_SET,X
            JSR  LOADREC
            JSR  TROWIN
            JSR  SETPROJ
            BRA  LOADPROJ13
LOADPROJ12  LDB  PSLOT          ; (no: its own)
            JSR  LREC
            STB  LR_SET,X
            JSR  LOADREC
            JSR  TROWIN
            LDX  PNAMEP
            JSR  LOADFILE
LOADPROJ13  INC  PSLOT
            LDA  PSLOT
            CMPA #3
            BLO  LOADPROJ10
            CLR  PSLOT          ; each layer's map
LOADPROJ14  LDB  PSLOT
            JSR  SWITCHQ
            LDB  PSLOT
            LDA  #TOKMAX+1
            MUL
            ADDD #SMAP
            TFR  D,X
            TST  ,X
            BEQ  LOADPROJ15
            JSR  LOADMAP
LOADPROJ15  JSR  STOREREC       ; its screen, shown or not
            LDB  PSLOT
            JSR  LREC
            LDY  #SSCREEN
            LDA  B,Y
            STA  LR_HIRES,X
            LDY  #SSHOW
            LDA  B,Y
            STA  LR_SHOW,X
            JSR  LOADREC
            INC  PSLOT
            LDA  PSLOT
            CMPA #3
            BLO  LOADPROJ14
            LDD  SORDER         ; the order
            STD  ORDER
            LDA  SORDER+2
            STA  ORDER+2
            LDD  SNPAL          ; the palette
            BEQ  LOADPROJ16
            LSLD
            TFR  D,W
            LDA  #VC_PAL/$10000
            LDX  #VC_PAL&$FFFF
            JSR  PORT0
            LDX  #SPAL
            LDY  #VC_DATA0
            TFM  X+,Y
            JSR  RDPAL
            JSR  UICOLORS
LOADPROJ16  LDB  SEDIT          ; the layer edited
            CMPB #3
            BLO  LOADPROJ17
            CLRB
LOADPROJ17  JSR  SWITCHQ
            LDX  #PPATH
            LDY  #PROJNAME
            JSR  STRCPY
            CLR  PROJCHG
            JSR  REDRAWBACK
            LDX  #T_POPENED
            JSR  MESSAGE
            ANDCC #$FE
            RTS
; REDRAWBACK: the screen as the layer being edited is (after quiet switching).
REDRAWBACK  JSR  UICOLORS
            JSR  MKUISPR
            JMP  REDRAWALL
; GETTOK: the next word of the file (IHANDLE) into TOKBUF, in upper case;
; TOKSECT 1 if it was a [section] (its name, without the brackets). Carry set
; at the end of the file.
GETTOK      CLR  TOKSECT
GETTOK1     JSR  INICH          ; past spaces and comments
            BCS  GETTOK9
            TST  PCOMM
            BEQ  GETTOK2
            CMPA #$0A
            BEQ  GETTOK15
            CMPA #$0D
            BNE  GETTOK1
GETTOK15    CLR  PCOMM
            BRA  GETTOK1
GETTOK2     CMPA #';
            BNE  GETTOK3
            INC  PCOMM
            BRA  GETTOK1
GETTOK3     BSR  ISSEP
            BEQ  GETTOK1
            LDU  #TOKBUF
            CMPA #'[
            BNE  GETTOK4
            INC  TOKSECT
            JSR  INICH
            BCS  GETTOK8
GETTOK4     CMPA #']            ; the word, to a space (or the ])
            BEQ  GETTOK7
            CMPA #';
            BNE  GETTOK45
            INC  PCOMM
            BRA  GETTOK8
GETTOK45    BSR  ISSEP
            BEQ  GETTOK8
            CMPA #'a
            BLO  GETTOK5
            CMPA #'z
            BHI  GETTOK5
            SUBA #$20
GETTOK5     CMPU #TOKBUF+TOKMAX
            BHS  GETTOK6
            STA  ,U+
GETTOK6     JSR  INICH
            BCC  GETTOK4
GETTOK7     CLR  ,U             ; (the ] read: the end)
            ANDCC #$FE
            RTS
GETTOK8     CLR  ,U
            ANDCC #$FE
            RTS
GETTOK9     RTS
; ISSEP: A a space, a tab, a line's end, = or ,? (Z set if so.)
ISSEP       CMPA #$20
            BEQ  ISSEP9
            CMPA #$09
            BEQ  ISSEP9
            CMPA #$0D
            BEQ  ISSEP9
            CMPA #$0A
            BEQ  ISSEP9
            CMPA #'=
            BEQ  ISSEP9
            CMPA #',
ISSEP9      RTS
; TOKIS: TOKBUF the word at X? (Z set if so.)
TOKIS       LDY  #TOKBUF
            JMP  STRCMP
; SECTOF: A = section TOKBUF: 1 PROJECT, 2-4 LAYER1-3, 5 PALETTE, 0 another.
SECTOF      LDX  #T_SPROJECT
            BSR  TOKIS
            BNE  SECTOF1
            LDA  #1
            RTS
SECTOF1     LDX  #T_SPALETTE
            BSR  TOKIS
            BNE  SECTOF2
            LDA  #5
            RTS
SECTOF2     LDX  #TOKBUF        ; LAYERn
            LDY  #T_SLAYER
            LDB  #5
SECTOF3     LDA  ,X+
            CMPA ,Y+
            BNE  SECTOF8
            DECB
            BNE  SECTOF3
            LDA  ,X+
            SUBA #'1
            BLO  SECTOF8
            CMPA #3
            BHS  SECTOF8
            TST  ,X
            BNE  SECTOF8
            ADDA #2
            RTS
SECTOF8     CLRA
            RTS
;------------------------------------------------------------------------------
T_TKT0      FCC  "; TILEKIT project"
            FCB  $0A
            FCC  "[PROJECT]"
            FCB  $0A
            FCN  "ORDER"
T_TKTEDIT   FCB  $0A
            FCN  "EDIT "
T_TKTLAY    FCB  $0A
            FCN  "[LAYER"
T_TKTTILES  FCC  "]"
            FCB  $0A
            FCN  "TILES "
T_TKTMAP    FCB  $0A
            FCN  "MAP "
T_TKTSCR    FCB  $0A
            FCN  "SCREEN "
T_TKTSHOW   FCB  $0A
            FCN  "SHOW "
T_TKTPAL    FCB  $0A
            FCC  "[PALETTE]"
            FCB  $0A
            FCB  0
T_320       FCN  "320"
T_640       FCN  "640"
T_YES       FCN  "YES"
T_NO        FCN  "NO"
T_SPROJECT  FCN  "PROJECT"
T_SPALETTE  FCN  "PALETTE"
T_SLAYER    FCN  "LAYER"
T_KTILES    FCN  "TILES"
T_KMAP      FCN  "MAP"
T_KSCREEN   FCN  "SCREEN"
T_KSHOW     FCN  "SHOW"
T_KORDER    FCN  "ORDER"
T_KEDIT     FCN  "EDIT"
T_PSAVED    FCN  "SAVED THE PROJECT"
T_POPENED   FCN  "OPENED THE PROJECT"
T_EXTTKT    FCN  ".TKT"
PROJCHG     FCB  0          ; the project's own settings changed since saved
PORIG       FCB  0
PFAIL       FCB  0
PSLOT       FCB  0
PSECT       FCB  0
PLAY        FCB  0
PCOMM       FCB  0
PNAMEP      FDB  0
TOKSECT     FCB  0
