;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 game kit
;    FILE: tk_file.asm
;
; TILEKIT's tile sets and maps: making them, the card set up for them, saving
; and opening them (the .TLS and .MAP files: see tilekit.asm), and the
; questions asked on the way -- the new set's kind, a file name, "are you
; sure". INCLUDEd by tilekit.asm.
;------------------------------------------------------------------------------
DLGROW      equ  9          ; the new set's questions: rows 9-18, columns 6-51
DLGCOL      equ  6
DLGW        equ  46
;------------------------------------------------------------------------------
; A set, and the card for it.
;------------------------------------------------------------------------------
; NEWPROJ: an empty set of the kind TSIZE, BPP, HIRES say: one blank tile, the
; card's own palette (xterm's).
NEWPROJ     LDA  #$80
            STA  VC_CTRL        ; the card as it starts: its memory 0 (the map's
            LDD  #1             ; cells all tile 0), its colors
            STD  NTILES
            BSR  FRESH
            CLR  MAPNAME
            CLR  MAPMOD
            CLR  FOCUS
            JSR  SETPROJ
            JMP  SETUPDISP
; FRESH: what a set just made or opened starts with.
FRESH       CLRD
            STD  TILE
            STD  TSTOP
            STD  SCRX
            STD  SCRY
            CLR  FLIPS
            CLR  MODIFIED
            CLR  UCOUNT
            CLR  UHEAD
            CLR  TDIRTY
            LDA  #15            ; white, in row 0
            STA  COLOR
            RTS
; SETPROJ: what follows from TSIZE and BPP.
SETPROJ     LDA  TSIZE
            CMPA #16
            BEQ  SETPROJ16
            LDD  #$0307         ; TSHIFT 3, TSMASK 7
            STD  TSHIFT
            LDD  #64
            STD  TPIX
            LDD  #$0410         ; ZSHIFT 4, ZOOM 16
            STD  ZSHIFT
            LDA  #6             ; log2 of the bytes, at 8 bits a pixel
            BRA  SETPROJ1
SETPROJ16   LDD  #$040F
            STD  TSHIFT
            LDD  #256
            STD  TPIX
            LDD  #$0308
            STD  ZSHIFT
            LDA  #8
SETPROJ1    LDB  BPP
            CMPB #8
            BEQ  SETPROJ2
            DECA                ; (half that at 4)
SETPROJ2    STA  TBSHIFT
            LDD  #1             ; TB = 1 << TBSHIFT
            LDF  TBSHIFT
SETPROJ3    LSLD
            DECF
            BNE  SETPROJ3
            STD  TB
            LDD  #$8000         ; MAXT = 65536 >> TBSHIFT, at most 1024
            LDF  TBSHIFT
            DECF
SETPROJ4    LSRD
            DECF
            BNE  SETPROJ4
            CMPD #1024
            BLS  SETPROJ5
            LDD  #1024
SETPROJ5    STD  MAXT
            LDD  #512           ; CHUNKT = 512 >> TBSHIFT
            LDF  TBSHIFT
SETPROJ6    LSRD
            DECF
            BNE  SETPROJ6
            STB  CHUNKT
            RTS
; SETUPDISP: the card's layers, sprites and input for the set (after a reset,
; with its tiles and palette in place), and everything drawn.
SETUPDISP   LDX  #TARGETCMD     ; drawing goes into the panel
            LDY  #VC_CMD
            LDW  #TARGETEND-TARGETCMD
            TFM  X+,Y
            LDA  #VC_CFG/$10000 ; the layers
            LDX  #DC_CTRL
            JSR  PORT0
            LDX  #SETTINGS
            LDY  #VC_DATA0
            LDW  #SETEND-SETTINGS
            TFM  X+,Y
            LDA  #VC_CFG/$10000 ; layer 0 as the set's tiles are
            LDX  #LAYER0+L_MODE
            JSR  PORT0
            LDA  #LM_TILE+LM_4BPP
            LDB  BPP
            CMPB #8
            BNE  SETUPDISP1
            LDA  #LM_TILE+LM_8BPP
SETUPDISP1  TST  HIRES
            BEQ  SETUPDISP2
            ORA  #LM_HIRES
SETUPDISP2  LDB  TSIZE
            CMPB #16
            BNE  SETUPDISP3
            ORA  #LM_BIG
SETUPDISP3  STA  VC_DATA0
            LDA  #VC_SPRITES/$10000 ; sprite 0: the pointer
            LDX  #VC_SPRITES&$FFFF
            JSR  PORT0
            LDX  #SPRITE0
            LDY  #VC_DATA0
            LDW  #8
            TFM  X+,Y
            LDA  #VC_IN_PTR+VC_IN_KEYS+VC_IN_FLUSH
            STA  VC_INCTRL      ; the pointer follows the mouse; the keys are ours
            JSR  RDPAL
            JSR  UICOLORS
            JSR  LOADTILE
            LDA  #1
            STA  STATDIRTY
            JMP  REDRAWALL
TARGETCMD   FCB  C_TARGET,PANEL/$10000,(PANEL/$100)&$FF,PANEL&$FF
            FDB  PANELW,PANELW,480
            FCB  8
TARGETEND
; From DC_CTRL: the three layers and the sprites on; the backdrop (REDRAWALL);
; sprites in 640x480, two of them (the pointer, the cell's frame), the table
; where it is at reset. Layer 0: the map (its mode set apart, its size and
; scrolling by MAPSETUP); layer 1: the panel, a bitmap
; only 176 wide, moved to the right edge; layer 2: the reset text screen.
SETTINGS    FCB  $0F,0,1,2
            FCB  VC_SPRITES/$10000,(VC_SPRITES/$100)&$FF,VC_SPRITES&$FF
            FCB  0,0,0,0,0,0,0,0,0
            FCB  0,0            ; (MAPSETUP: its size, scrolling)
            FCB  MAPV/$10000,(MAPV/$100)&$FF,MAPV&$FF
            FCB  TILES/$10000,(TILES/$100)&$FF,TILES&$FF
            FDB  0,0,0
            FCB  0,0
            FCB  LM_BITMAP+LM_HIRES+LM_8BPP,0
            FCB  PANEL/$10000,(PANEL/$100)&$FF,PANEL&$FF
            FCB  0,0,0
            FDB  -PANELX,0,PANELW
            FCB  0,0
            FCB  LM_TEXT+LM_HIRES+LM_BIG,LW_128+LH_32
            FCB  VC_TEXTMAP/$10000,(VC_TEXTMAP/$100)&$FF,VC_TEXTMAP&$FF
            FCB  VC_FONT/$10000,(VC_FONT/$100)&$FF,VC_FONT&$FF
            FDB  0,0,0
            FCB  0,0
SETEND
SPRITE0     FDB  GK_PTR/32,0,0
            FCB  SS_W16+SS_H16+SS_FRONT,SC_8BPP
;------------------------------------------------------------------------------
; The new set's questions: what kind of tiles, how big a map -- or a new map
; for the tile set there is.
;------------------------------------------------------------------------------
NEWDIALOG   JSR  DLGCUR
            LDA  MAPWC
            STA  NWC
            LDA  MAPHC
            STA  NHC
            CLR  NKEEP
            LDA  #M_DIALOG
            STA  MODE
SHOWDLG     JSR  BARTEXT
            LDB  #0
            LDX  #T_DLG0
            BSR  DLGLINE
            LDB  #1
            LDX  #T_EMPTY
            BSR  DLGLINE
            LDB  #2
            LDX  #T_DLG1
            LDY  #T_D8
            LDA  NTS
            CMPA #8
            BEQ  SHOWDLG1
            LDY  #T_D16
SHOWDLG1    BSR  DLGLINE2
            LDB  #3
            LDX  #T_DLG2
            LDY  #T_D4BIT
            LDA  NBPP
            CMPA #8
            BNE  SHOWDLG2
            LDY  #T_D8BIT
SHOWDLG2    BSR  DLGLINE2
            LDB  #4
            LDX  #T_DLG3
            LDY  #T_LORES+2
            TST  NHIRES
            BEQ  SHOWDLG3
            LDY  #T_HIRES+2
SHOWDLG3    BSR  DLGLINE2
            LDB  #5
            LDX  #T_DLG5
            LDA  NWC
            BSR  DLGSIZE
            LDB  #6
            LDX  #T_DLG6
            LDA  NHC
            BSR  DLGSIZE
            LDB  #7
            LDX  #T_DLG7
            LDY  #T_KEEPNO
            TST  NKEEP
            BEQ  SHOWDLG4
            LDY  #T_KEEPYES
SHOWDLG4    BSR  DLGLINE2
            LDB  #8
            LDX  #T_EMPTY
            BSR  DLGLINE
            LDB  #9
            LDX  #T_DLG4
; DLGLINE: the question box's row B: the string at X. DLGLINE2: X (19
; characters), then Y. DLGSIZE: X, then 32 << A cells.
DLGLINE     PSHS X
            LDA  #DLGCOL
            ADDB #DLGROW
            JSR  TXAT
            PULS X
            LDB  #DLGW
            JMP  TXFIELD
DLGSIZE     LDY  #T_SIZES       ; (10 bytes each)
            PSHS B
            LDB  #10
            MUL
            LEAY D,Y
            PULS B
DLGLINE2    PSHS Y,X
            LDA  #DLGCOL
            ADDB #DLGROW
            JSR  TXAT
            PULS X
            JSR  TXSTR
            PULS X
            LDB  #DLGW-19
            JMP  TXFIELD
; DLGCUR: the answers about the tiles as the set there is has them.
DLGCUR      LDA  TSIZE
            STA  NTS
            LDA  BPP
            STA  NBPP
            LDA  HIRES
            STA  NHIRES
            RTS
; HIDEDLG: the box away (and the cover past the map's end back).
HIDEDLG     CLR  TXBG
            LDE  #DLGROW
HIDEDLG1    LDA  #DLGCOL
            LDB  #DLGW
            JSR  TXROW
            INCE
            CMPE #DLGROW+10
            BNE  HIDEDLG1
            JMP  MASKMAP
DLGKEY      JSR  UPCHAR
            LDA  KCODE
            CMPA #K_ESC
            LBEQ DLGCANCEL
            CMPA #K_ENTER
            LBEQ DLGMAKE
            CMPA #K_KPENTER
            LBEQ DLGMAKE
            CMPB #'O
            BEQ  DLGOPEN
            CMPB #'K            ; a new map only, for this set: or not
            BNE  DLGKEY0
            LDA  NKEEP
            EORA #1
            STA  NKEEP
            BSR  DLGCUR
DLGKEY0     CMPB #'W            ; the map's width: 32, 64, 128, 256, 32 ...
            BNE  DLGKEY4
            LDA  NWC
            INCA
            ANDA #3
            STA  NWC
DLGKEY41    LDA  NWC            ; (16384 cells at most: the height gives way)
            ADDA NHC
            CMPA #4
            BLS  DLGKEY4
            DEC  NHC
            BRA  DLGKEY41
DLGKEY4     CMPB #'H            ; and its height
            BNE  DLGKEY5
            LDA  NHC
            INCA
            ANDA #3
            STA  NHC
DLGKEY51    LDA  NWC
            ADDA NHC
            CMPA #4
            BLS  DLGKEY5
            DEC  NWC
            BRA  DLGKEY51
DLGKEY5     TST  NKEEP          ; (keeping the set: its kind stays)
            BNE  DLGKEY3
            CMPB #'T
            BNE  DLGKEY1
            LDA  NTS            ; 8 <-> 16
            EORA #$18
            STA  NTS
DLGKEY1     CMPB #'D
            BNE  DLGKEY2
            LDA  NBPP           ; 4 <-> 8
            EORA #$0C
            STA  NBPP
DLGKEY2     CMPB #'R
            BNE  DLGKEY3
            LDA  NHIRES
            EORA #1
            STA  NHIRES
DLGKEY3     JMP  SHOWDLG
DLGCANCEL   JSR  HIDEDLG
            CLR  MODE
            JMP  DRAWHELP
DLGOPEN     JSR  HIDEDLG
            CLR  MODE
            JMP  OPENPROMPT
DLGMAKE     CLR  MODE
            LDA  NWC
            STA  MAPWC
            LDA  NHC
            STA  MAPHC
            LDA  KEEPNAME       ; (names given that are not files yet: they will be)
            BITA #2
            BNE  DLGMAKE0
            CLR  MAPNAME
DLGMAKE0    TST  NKEEP
            BNE  DLGMAKEMAP
            LDA  NTS
            STA  TSIZE
            LDA  NBPP
            STA  BPP
            LDA  NHIRES
            STA  HIRES
            LDA  KEEPNAME
            BITA #1
            BNE  DLGMAKE1
            CLR  FILENAME
DLGMAKE1    LDX  #MAPNAME       ; (NEWPROJ forgets the map's name: kept here)
            LDY  #MPATHBUF
            JSR  STRCPY
            JSR  NEWPROJ        ; (the reset clears the box away)
            LDX  #MPATHBUF
            LDY  #MAPNAME
            JSR  STRCPY
            LDA  KEEPNAME       ; (a name kept is a file still to be written)
            ANDA #1
            STA  MODIFIED
            LDA  KEEPNAME
            LSRA
            STA  MAPMOD
            CLR  KEEPNAME
            LDA  #1
            STA  STATDIRTY
            JMP  DRAWHELP
DLGMAKEMAP  CLR  KEEPNAME       ; a new map, the set as it is
            JSR  NEWMAP
            JMP  DRAWHELP
; NEWMAP: a new map of MAPWC x MAPHC cells, every one tile 0.
NEWMAP      LDA  #C_FILL
            STA  VC_CMD
            LDA  #MAPV/$10000
            STA  VC_CMD
            LDD  #MAPV&$FFFF
            JSR  CMDD
            LDD  #$0080         ; 32KB
            JSR  CMDD
            CLRA
            STA  VC_CMD
            STA  VC_CMD
            JSR  WAITCMD
            CLRD
            STD  SCRX
            STD  SCRY
            CLR  MAPMOD
            CLR  UCOUNT
            CLR  UHEAD
            JSR  MAPSETUP
            LDA  #1
            STA  STATDIRTY
            RTS
; STRCPY: the string at X to Y.
STRCPY      LDA  ,X+
            STA  ,Y+
            BNE  STRCPY
            RTS
; DLGMOUSE: a click in the box is its key.
DLGMOUSE    LDA  PRESSED
            BITA #VC_MB_LEFT
            BEQ  DLGMOUSE9
            CLR  KCODE
            CLR  KCHAR
            LDD  MOUSEX
            LSRD
            LSRD
            LSRD
            SUBB #DLGCOL        ; the column in the box
            BLO  DLGMOUSE9
            CMPB #DLGW
            BHS  DLGMOUSE9
            STB  HCOL
            LDD  MOUSEY
            LSRD
            LSRD
            LSRD
            LSRD
            SUBB #DLGROW        ; the row: its key
            CMPB #9
            BEQ  DLGMOUSE3
            CMPB #2
            BLO  DLGMOUSE9
            CMPB #7
            BHI  DLGMOUSE9
            LDX  #DLGKEYS-2
            LDA  B,X
DLGMOUSE1   STA  KCHAR
            JMP  DLGKEY
DLGMOUSE3   LDA  #'O            ; the bottom row: ENTER, O, or ESC
            LDB  HCOL
            CMPB #15
            BHS  DLGMOUSE2
            LDA  #K_ENTER
            STA  KCODE
            JMP  DLGKEY
DLGMOUSE2   CMPB #30
            BLO  DLGMOUSE1
            LDA  #K_ESC
            STA  KCODE
            JMP  DLGKEY
DLGMOUSE9   RTS
DLGKEYS     FCB  'T,'D,'R,'W,'H,'K
;------------------------------------------------------------------------------
; Commands: save, open, new, quit.
;------------------------------------------------------------------------------
; SAVECMD: the tile set and the map, each if it has changed (asking for its
; name if it has none: a map's file names its tile set's, so the set needs one).
; SAVEASCMD: both, asking for both names.
SAVECMD     CLR  SAVEAS
            BRA  SAVETS
SAVEASCMD   LDA  #1
            STA  SAVEAS
SAVETS      TST  SAVEAS
            BNE  SAVETS1
            TST  FILENAME
            BEQ  SAVETS1
            TST  MODIFIED
            BEQ  SAVEMAPQ       ; (nothing to save in the set)
            LDX  #FILENAME
            JSR  SAVEFILE
            BCC  SAVEMAPQ
            RTS
SAVETS1     LDX  #T_SAVETS
            LDY  #FILENAME
            LDU  #T_EXT
            STU  PREXT
            LDU  #DOSAVETS
            JMP  ASKNAME
DOSAVETS    JSR  SAVEFILE
            BCC  SAVEMAPQ
            RTS
SAVEMAPQ    TST  SAVEAS         ; then the map
            BNE  SAVEMAPQ1
            TST  MAPMOD
            BEQ  SAVEMAPQ9
            TST  MAPNAME
            BEQ  SAVEMAPQ1
            LDX  #MAPNAME
            JMP  SAVEMAP
SAVEMAPQ1   LDX  #T_SAVEMAP
            LDY  #MAPNAME
            LDU  #T_EXTMAP
            STU  PREXT
            LDU  #SAVEMAP
            JMP  ASKNAME
SAVEMAPQ9   RTS
OPENCMD     LDU  #OPENPROMPT
            BRA  IFSAVED
NEWCMD      CLR  KEEPNAME
            LDU  #NEWDIALOG
            BRA  IFSAVED
QUITCMD     LDU  #QUITNOW
IFSAVED     TST  MODIFIED       ; changes not saved: ask first
            BNE  IFSAVED0
            TST  MAPMOD
            BEQ  IFSAVED1
IFSAVED0    LDX  #T_DISCARD
            BRA  CONFIRM
IFSAVED1    JMP  ,U
OPENPROMPT  LDX  #T_OPEN
            LDY  #FILENAME
            LDU  #T_EXT
            STU  PREXT
            LDU  #OPENANY
; ASKNAME: question X, a file name to type (Y to start with; PREXT added if it
; has no extension), then U with X the name.
ASKNAME     STU  PRDONE
            JSR  PRSTART
            LDA  #M_PROMPT
            STA  MODE
            CLR  MSGTIME
            CLR  PR_COL
            LDA  #HELPROW
            STA  PR_ROW
            LDA  #58
            STA  PR_WIDE
; PRSHOWC: the bottom-but-one row as the question being asked is.
PRSHOWC     JSR  BARTEXT
            LDA  MODE
            CMPA #M_CONFIRM
            BEQ  PRSHOWC1
            JMP  PRSHOW
PRSHOWC1    LDX  CONFMSG
            JMP  HELPLINE
; CONFIRM: question X, then U if the answer is Y.
CONFIRM     STX  CONFMSG
            STU  CONFOK
            LDA  #M_CONFIRM
            STA  MODE
            CLR  MSGTIME
            BRA  PRSHOWC
CONFKEY     JSR  UPCHAR
            CMPB #'Y
            BEQ  CONFKEY1
            LDA  KCODE
            CMPA #K_ESC
            BEQ  CONFKEY2
            CMPB #'N
            BEQ  CONFKEY2
            RTS                 ; (anything else: still asking)
CONFKEY1    CLR  MODE
            JSR  DRAWHELP
            JMP  [CONFOK]
CONFKEY2    CLR  MODE
            JMP  DRAWHELP
PROMPTKEY   LDA  KCODE
            LDB  KCHAR
            JSR  PRKEY
            CMPA #1
            BEQ  PROMPTKEY1
            CMPA #2
            BEQ  PROMPTKEY2
            JMP  PRSHOWC
PROMPTKEY2  CLR  MODE
            JMP  DRAWHELP
PROMPTKEY1  CLR  MODE
            TST  PR_BUF
            BEQ  PROMPTKEY2
            JSR  DRAWHELP
            LDX  #PR_BUF
            LDY  PREXT
            JSR  DEFEXT
            LDX  #PR_BUF
            JMP  [PRDONE]
; OPENANY: the file named at X: a map (.MAP), with its tile set; anything else,
; a tile set (and a new map for it). Carry set (A the error) if it couldn't be.
OPENANY     PSHS X
            BSR  ISMAP
            PULS X
            LBEQ LOADMAP
            JMP  LOADFILE
; ISMAP: the name at X ends in ".MAP"? (Z set if so.)
ISMAP       LDA  ,X+            ; (to its end)
            BNE  ISMAP
            LDD  -5,X
            CMPD #$2E4D         ; ".M"
            BNE  ISMAP9
            LDD  -3,X
            CMPD #$4150         ; "AP"
ISMAP9      RTS
QUITNOW     LDA  #$80           ; the card as it was (and the keys back to the UART)
            STA  VC_CTRL
            LDA  #B_EXIT
            SWI2
; DEFEXT: the extension at Y (".TLS") on the end of the path at X if its name
; has none (and there is room).
DEFEXT      STY  DEXT
            CLRB                ; its length
            LDY  #0             ; a "." in its last name
DEFEXT1     LDA  ,X+
            BEQ  DEFEXT2
            INCB
            CMPA #'/
            BNE  DEFEXT3
            LDY  #0
            BRA  DEFEXT1
DEFEXT3     CMPA #'.
            BNE  DEFEXT1
            LEAY ,X
            BRA  DEFEXT1
DEFEXT2     CMPY #0
            BNE  DEFEXT9
            CMPB #PR_MAX-4
            BHI  DEFEXT9
            LEAX -1,X
            LDY  DEXT
DEFEXT4     LDA  ,Y+
            STA  ,X+
            BNE  DEFEXT4
DEFEXT9     RTS
;------------------------------------------------------------------------------
; Files.
;------------------------------------------------------------------------------
; SAVEFILE: the set to the file named at X (FILENAME, if that works).
SAVEFILE    STX  FPATH
            JSR  FLUSHTILE
            LDE  #FOPEN_WRITE
            LDA  #B_FOPEN_NAME
            SWI2
            LBCS FILEERR
            STA  FHANDLE
            LDX  #HDRBUF        ; the header
            LDD  #$5054         ; "PT"
            STD  ,X
            LDD  #$5331         ; "S1"
            STD  2,X
            LDA  TSIZE
            STA  4,X
            LDA  BPP
            STA  5,X
            LDA  HIRES
            STA  6,X
            CLR  7,X
            LDD  NTILES
            STD  8,X
            CLRD
            STD  10,X
            STD  12,X
            STD  14,X
            LDY  #16
            BSR  FWRITE
            BCS  SAVEERR
            LDX  #PALBUF        ; the palette
            LDY  #512
            BSR  FWRITE
            BCS  SAVEERR
            LDA  #TILES/$10000  ; the tiles, from the card, 512 bytes at a time
            LDX  #TILES&$FFFF
            JSR  PORT1
            LDD  NTILES
            STD  FLEFT
SAVE1       LDD  FLEFT
            BEQ  SAVE9
            BSR  FCHUNK
            LDW  FBYTES
            LDX  #VC_DATA1
            LDY  #IOBUF
            TFM  X,Y+
            LDX  #IOBUF
            LDY  FBYTES
            BSR  FWRITE
            BCS  SAVEERR
            BRA  SAVE1
SAVE9       LDB  FHANDLE
            LDA  #B_FCLOSE_NAME
            SWI2
            BCS  FILEERR
            BSR  NAMEIT
            LDX  #T_SAVED
            JMP  MESSAGE
SAVEERR     PSHS A
            LDB  FHANDLE
            LDA  #B_FCLOSE_NAME
            SWI2
            PULS A
            BRA  FILEERR
FWRITE      LDB  FHANDLE
            LDA  #B_FWRITE
            SWI2
            RTS
FREAD       LDB  FHANDLE
            LDA  #B_FREAD
            SWI2
            RTS
; FCHUNK: the next lot of FLEFT tiles to move: FBYTES bytes, at most 512.
FCHUNK      CLRA
            LDB  CHUNKT
            CMPD FLEFT
            BLS  FCHUNK1
            LDD  FLEFT
FCHUNK1     PSHS D
            LDD  FLEFT
            SUBD ,S
            STD  FLEFT
            PULS D
            LDF  TBSHIFT
FCHUNK2     LSLD
            DECF
            BNE  FCHUNK2
            STD  FBYTES
            RTS
; NAMEIT: FPATH is the set's file now; nothing unsaved.
NAMEIT      LDX  FPATH
            LDY  #FILENAME
NAMEIT1     LDA  ,X+
            STA  ,Y+
            BNE  NAMEIT1
            CLR  MODIFIED
            LDA  #1
            STA  STATDIRTY
            RTS
; FILEERR: say what error A was. (Carry set.)
FILEERR     PSHS A
            LDX  #ERRTAB
FILEERR1    LDB  ,X
            BEQ  FILEERR2
            CMPB ,S
            BEQ  FILEERR3
            LEAX 3,X
            BRA  FILEERR1
FILEERR3    LDX  1,X
            JSR  MESSAGE
            BRA  FILEERR4
FILEERR2    LDX  #T_FERR        ; (any other: its number)
            JSR  MESSAGE
            LDA  #12            ; (after the words)
            LDB  #HELPROW
            JSR  TXAT
            LDA  ,S
            JSR  TXHEX2
FILEERR4    PULS A
            ORCC #$01
            RTS
ERRTAB      FCB  ERR_NOTFOUND
            FDB  T_NOTFOUND
            FCB  ERR_NOSPACE
            FDB  T_DISKFULL
            FCB  ERR_BADPATH
            FDB  T_BADNAME
            FCB  ERR_NOTDIR
            FDB  T_NOTFOUND
            FCB  ERR_ISDIR
            FDB  T_ISDIR
            FCB  0
; LOADFILE: the set in the file named at X. Carry set (A the error) if it
; couldn't be: then, unless the file was opened, the set is as it was.
LOADFILE    STX  FPATH
            LDE  #FOPEN_READ
            LDA  #B_FOPEN_NAME
            SWI2
            BCS  FILEERR
            STA  FHANDLE
            LDX  #HDRBUF        ; its header: a tile set we can hold?
            LDY  #16
            JSR  FREAD
            LBCS LOADERR
            CMPX #16
            LBNE NOTSET
            LDD  HDRBUF
            CMPD #$5054
            LBNE NOTSET
            LDD  HDRBUF+2
            CMPD #$5331
            LBNE NOTSET
            LDX  #1024          ; the most tiles
            LDA  HDRBUF+5
            CMPA #4
            BEQ  LOADFILE1
            CMPA #8
            LBNE NOTSET
LOADFILE1   LDB  HDRBUF+4
            CMPB #8
            BEQ  LOADFILE2
            CMPB #16
            LBNE NOTSET
            LDX  #512
            CMPA #4
            BEQ  LOADFILE2
            LDX  #256
LOADFILE2   LDD  HDRBUF+8
            LBEQ NOTSET
            PSHS X
            CMPD ,S++
            LBHI NOTSET
            STD  NTILES         ; yes: it is the set from here on
            LDA  HDRBUF+4
            STA  TSIZE
            LDA  HDRBUF+5
            STA  BPP
            LDA  HDRBUF+6
            ANDA #1
            STA  HIRES
            JSR  SETPROJ
            JSR  FRESH
            LDA  #$80           ; the card fresh, then the palette
            STA  VC_CTRL
            LDX  #PALBUF
            LDY  #512
            JSR  FREAD
            BCS  LOADSHORT
            CMPX #512
            BNE  LOADSHORT
            JSR  WRPAL
            LDA  #TILES/$10000  ; and the tiles
            LDX  #TILES&$FFFF
            JSR  PORT0
            LDD  NTILES
            STD  FLEFT
LOAD1       LDD  FLEFT
            BEQ  LOAD9
            JSR  FCHUNK
            LDX  #IOBUF
            LDY  FBYTES
            JSR  FREAD
            BCS  LOADSHORT
            CMPX FBYTES
            BNE  LOADSHORT
            LDW  FBYTES
            LDX  #IOBUF
            LDY  #VC_DATA0
            TFM  X+,Y
            BRA  LOAD1
LOAD9       BSR  CLOSEF
            JSR  NAMEIT
            CLR  MAPNAME        ; (the card reset: the map is blank)
            CLR  MAPMOD
            JSR  SETUPDISP
            LDX  #T_OPENED
            JSR  MESSAGE
            ANDCC #$FE
            RTS
LOADSHORT   BSR  CLOSEF         ; (what there was of it, anyway)
            JSR  NAMEIT
            CLR  MAPNAME
            CLR  MAPMOD
            JSR  SETUPDISP
            LDX  #T_SHORT
            JSR  MESSAGE
            ORCC #$01
            RTS
NOTSET      BSR  CLOSEF
            LDX  #T_NOTSET
            JSR  MESSAGE
            LDA  #ERR_BADEXE
            ORCC #$01
            RTS
LOADERR     PSHS A
            BSR  CLOSEF
            PULS A
            JMP  FILEERR
CLOSEF      LDB  FHANDLE
            LDA  #B_FCLOSE_NAME
            SWI2
            RTS
; SAVEMAP: the map to the file named at X (MAPNAME, if that works).
SAVEMAP     STX  MPATH
            LDE  #FOPEN_WRITE
            LDA  #B_FOPEN_NAME
            SWI2
            LBCS FILEERR
            STA  MHANDLE
            LDX  #MHDR          ; the header: its size, its tile set's file
            LDW  #48
SAVEMAP1    CLR  ,X+
            DECW
            BNE  SAVEMAP1
            LDD  #$5054         ; "PT"
            STD  MHDR
            LDD  #$4D31         ; "M1"
            STD  MHDR+2
            LDD  MAPW
            STD  MHDR+4
            LDD  MAPH
            STD  MHDR+6
            LDX  #FILENAME
            LDY  #MHDR+8
            LDB  #39            ; (39 characters at most, and a 0)
SAVEMAP3    LDA  ,X+
            BEQ  SAVEMAP4
            STA  ,Y+
            DECB
            BNE  SAVEMAP3
SAVEMAP4    LDX  #MHDR
            LDY  #48
            BSR  MWRITE
            BCS  SAVEMAPE
            LDA  #MAPV/$10000   ; the cells, from the card, 512 bytes at a time
            LDX  #MAPV&$FFFF
            JSR  PORT1
            LDD  MAPBYTES
            STD  FLEFT
SAVEMAP2    LDW  #512
            LDX  #VC_DATA1
            LDY  #IOBUF
            TFM  X,Y+
            LDX  #IOBUF
            LDY  #512
            BSR  MWRITE
            BCS  SAVEMAPE
            LDD  FLEFT
            SUBD #512
            STD  FLEFT
            BNE  SAVEMAP2
            BSR  MCLOSE
            LBCS FILEERR
            BSR  MAPNAMED
            LDX  #T_SAVED
            JSR  MESSAGE
            ANDCC #$FE
            RTS
SAVEMAPE    PSHS A
            BSR  MCLOSE
            PULS A
            JMP  FILEERR
MWRITE      LDB  MHANDLE
            LDA  #B_FWRITE
            SWI2
            RTS
MREAD       LDB  MHANDLE
            LDA  #B_FREAD
            SWI2
            RTS
MCLOSE      LDB  MHANDLE
            LDA  #B_FCLOSE_NAME
            SWI2
            RTS
; MAPNAMED: MPATH is the map's file now; nothing unsaved in it.
MAPNAMED    LDX  MPATH
            LDY  #MAPNAME
            JSR  STRCPY
            CLR  MAPMOD
            LDA  #1
            STA  STATDIRTY
            RTS
; LOADMAP: the map in the file named at X, and its tile set (unless that is the
; one open already). Carry set (A the error) if it couldn't be.
LOADMAP     LDY  #MPATHBUF      ; (its name kept apart: opening its tile set
            JSR  STRCPY         ; may change what X points at)
            LDX  #MPATHBUF
            STX  MPATH
            LDE  #FOPEN_READ
            LDA  #B_FOPEN_NAME
            SWI2
            LBCS FILEERR
            STA  MHANDLE
            LDX  #MHDR          ; its header: a map we can hold?
            LDY  #48
            BSR  MREAD
            LBCS LOADMAPE
            CMPX #48
            LBNE NOTMAP
            LDD  MHDR
            CMPD #$5054
            LBNE NOTMAP
            LDD  MHDR+2
            CMPD #$4D31
            LBNE NOTMAP
            LDD  MHDR+4
            JSR  SIZECODE
            LBCS NOTMAP
            STA  NWC
            LDD  MHDR+6
            JSR  SIZECODE
            LBCS NOTMAP
            STA  NHC
            ADDA NWC
            CMPA #4
            LBHI NOTMAP
            CLR  MHDR+47
            LDX  #MHDR+8        ; its tile set: the one open?
            LDY  #FILENAME
            JSR  STRCMP
            BEQ  LOADMAP1
            LDX  #MHDR+8        ; no: that one
            JSR  LOADFILE
            LBCS NOSETFOR
LOADMAP1    LDA  NWC
            STA  MAPWC
            LDA  NHC
            STA  MAPHC
            CLRD
            STD  SCRX
            STD  SCRY
            JSR  MAPSETUP
            LDA  #MAPV/$10000   ; the cells, into the card
            LDX  #MAPV&$FFFF
            JSR  PORT0
            LDD  MAPBYTES
            STD  FLEFT
LOADMAP2    LDX  #IOBUF
            LDY  #512
            JSR  MREAD
            BCS  LMSHORT
            CMPX #512
            BNE  LMSHORT
            LDX  #IOBUF
            LDY  #VC_DATA0
            LDW  #512
            TFM  X+,Y
            LDD  FLEFT
            SUBD #512
            STD  FLEFT
            BNE  LOADMAP2
            JSR  MCLOSE
            JSR  MAPNAMED
            CLR  UCOUNT
            CLR  UHEAD
            LDX  #T_OPENED
            JSR  MESSAGE
            ANDCC #$FE
            RTS
LMSHORT     JSR  MCLOSE         ; (what there was of it)
            JSR  MAPNAMED
            CLR  UCOUNT
            LDX  #T_SHORT
            BRA  LMFAIL
NOTMAP      JSR  MCLOSE
            LDX  #T_NOTMAP
LMFAIL      JSR  MESSAGE
            LDA  #ERR_BADEXE
            ORCC #$01
            RTS
NOSETFOR    JSR  MCLOSE         ; its tile set wouldn't open: say which
            LDX  #T_MAPTS
            JSR  MESSAGE
            LDA  #T_MAPTSEND-T_MAPTS-1
            LDB  #HELPROW
            JSR  TXAT
            LDX  #MHDR+8
            JSR  TXSTR
            LDA  #ERR_NOTFOUND
            ORCC #$01
            RTS
LOADMAPE    PSHS A
            JSR  MCLOSE
            PULS A
            JMP  FILEERR
; SIZECODE: A = the map size code for D cells (32 0, 64 1, 128 2, 256 3);
; carry set if D isn't one of those.
SIZECODE    LDX  #T_SIZEVAL
SIZECODE1   CMPD ,X++
            BEQ  SIZECODE2
            CMPX #T_SIZEVAL+8
            BNE  SIZECODE1
            ORCC #$01
            RTS
SIZECODE2   TFR  X,D
            SUBD #T_SIZEVAL+2
            LSRB
            TFR  B,A
            ANDCC #$FE
            RTS
T_SIZEVAL   FDB  32,64,128,256
; STRCMP: the strings at X and Y the same? (Z set if so.)
STRCMP      LDA  ,X+
            CMPA ,Y+
            BNE  STRCMP9
            TSTA
            BNE  STRCMP
STRCMP9     RTS
;------------------------------------------------------------------------------
; Words.
;------------------------------------------------------------------------------
T_EMPTY     FCB  0
T_DLG0      FCN  " A NEW TILE SET AND MAP"
T_DLG1      FCN  " T  TILES          "
T_DLG2      FCN  " D  COLORS         "
T_DLG3      FCN  " R  SCREEN         "
T_DLG4      FCN  " ENTER MAKE IT  O OPEN A FILE  ESC CANCEL"
T_DLG5      FCN  " W  MAP WIDTH      "
T_DLG6      FCN  " H  MAP HEIGHT     "
T_DLG7      FCN  " K  KEEP THE TILES "
T_SIZES     FCN  "32 CELLS "        ; (10 bytes each)
            FCN  "64 CELLS "
            FCN  "128 CELLS"
            FCN  "256 CELLS"
T_KEEPNO    FCN  "NO: A NEW TILE SET TOO"
T_KEEPYES   FCN  "YES: JUST A NEW MAP"
T_D8        FCN  "8x8"
T_D16       FCN  "16x16"
T_D4BIT     FCN  "16 (4 BITS A PIXEL)"
T_D8BIT     FCN  "256 (8 BITS A PIXEL)"
T_SAVETS    FCN  "SAVE THE TILE SET AS: "
T_SAVEMAP   FCN  "SAVE THE MAP AS: "
T_OPEN      FCN  "OPEN: "
T_DISCARD   FCN  "THE CHANGES AREN'T SAVED. GO ON ANYWAY? (Y/N)"
T_EXT       FCN  ".TLS"
T_EXTMAP    FCN  ".MAP"
T_SAVED     FCN  "SAVED"
T_OPENED    FCN  "OPENED"
T_SHORT     FCN  "THE FILE ENDS EARLY: THIS IS WHAT THERE WAS OF IT"
T_NOTSET    FCN  "THAT ISN'T A TILE SET FILE (OR NOT ONE THIS CAN HOLD)"
T_NOTFOUND  FCN  "NO SUCH FILE"
T_DISKFULL  FCN  "THE DISK IS FULL"
T_BADNAME   FCN  "NOT A FILE NAME (8.3: NAME.EXT)"
T_ISDIR     FCN  "THAT IS A DIRECTORY"
T_FERR      FCN  "FILE ERROR $"
T_NEWFILE   FCN  "A NEW FILE: WHAT KIND OF TILE SET AND MAP?"
T_NOTMAP    FCN  "THAT ISN'T A MAP FILE (OR NOT ONE THIS CAN HOLD)"
T_MAPTS     FCN  "ITS TILE SET WON'T OPEN: "
T_MAPTSEND
;------------------------------------------------------------------------------
NTS         FCB  8          ; the new set's answers
NBPP        FCB  4
NHIRES      FCB  0
NWC         FCB  1          ;   the map's width and height (codes, as MAPWC)
NHC         FCB  1
NKEEP       FCB  0          ;   1: just a new map, for the set there is
KEEPNAME    FCB  0          ; the name typed with TILEKIT is the new set's (1),
                            ; or the new map's (2)
SAVEAS      FCB  0          ; asking for the names, whether or not they have them
PREXT       FDB  T_EXT      ; the extension for a name typed without one
DEXT        FDB  0
MPATH       FDB  0          ; the map's file being saved or opened
MHANDLE     FCB  0
PRDONE      FDB  0          ; what to do with a name typed
CONFMSG     FDB  0
CONFOK      FDB  0          ; what to do on Y
FPATH       FDB  0
FHANDLE     FCB  0
FLEFT       FDB  0
FBYTES      FDB  0
HDRBUF      FCB  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
MHDR        FCB  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0 ; a map file's header: 48 bytes
            FCB  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
            FCB  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
