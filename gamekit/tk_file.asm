;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 game kit
;    FILE: tk_file.asm
;
; TILEKIT's tile sets: making one, the card set up for it, saving and opening
; them (the .TLS file: see tilekit.asm), and the questions asked on the way --
; the new set's kind, a file name, "are you sure". INCLUDEd by tilekit.asm.
;------------------------------------------------------------------------------
DLGROW      equ  9          ; the new set's questions: rows 9-15, columns 6-51
DLGCOL      equ  6
DLGW        equ  46
;------------------------------------------------------------------------------
; A set, and the card for it.
;------------------------------------------------------------------------------
; NEWPROJ: an empty set of the kind TSIZE, BPP, HIRES say: one blank tile, the
; card's own palette (xterm's).
NEWPROJ     LDA  #$80
            STA  VC_CTRL        ; the card as it starts: its memory 0, its colors
            LDD  #1
            STD  NTILES
            BSR  FRESH
            JSR  SETPROJ
            JMP  SETUPDISP
; FRESH: what a set just made or opened starts with.
FRESH       CLRD
            STD  TILE
            STD  TSTOP
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
; sprites in 640x480, one of them, the table where it is at reset. Layer 0:
; the tile over and over (its mode set apart); layer 1: the panel, a bitmap
; only 176 wide, moved to the right edge; layer 2: the reset text screen.
SETTINGS    FCB  $0F,0,1,1
            FCB  VC_SPRITES/$10000,(VC_SPRITES/$100)&$FF,VC_SPRITES&$FF
            FCB  0,0,0,0,0,0,0,0,0
            FCB  0,LW_32+LH_32
            FCB  PREVMAP/$10000,(PREVMAP/$100)&$FF,PREVMAP&$FF
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
; The new set's questions.
;------------------------------------------------------------------------------
NEWDIALOG   LDA  TSIZE
            STA  NTS
            LDA  BPP
            STA  NBPP
            LDA  HIRES
            STA  NHIRES
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
            LDX  #T_EMPTY
            BSR  DLGLINE
            LDB  #6
            LDX  #T_DLG4
; DLGLINE: the question box's row B: the string at X. DLGLINE2: X (19
; characters), then Y.
DLGLINE     PSHS X
            LDA  #DLGCOL
            ADDB #DLGROW
            JSR  TXAT
            PULS X
            LDB  #DLGW
            JMP  TXFIELD
DLGLINE2    PSHS Y,X
            LDA  #DLGCOL
            ADDB #DLGROW
            JSR  TXAT
            PULS X
            JSR  TXSTR
            PULS X
            LDB  #DLGW-19
            JMP  TXFIELD
HIDEDLG     CLR  TXBG
            LDE  #DLGROW
HIDEDLG1    LDA  #DLGCOL
            LDB  #DLGW
            JSR  TXROW
            INCE
            CMPE #DLGROW+7
            BNE  HIDEDLG1
            RTS
DLGKEY      JSR  UPCHAR
            LDA  KCODE
            CMPA #K_ESC
            BEQ  DLGCANCEL
            CMPA #K_ENTER
            BEQ  DLGMAKE
            CMPA #K_KPENTER
            BEQ  DLGMAKE
            CMPB #'O
            BEQ  DLGOPEN
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
DLGCANCEL   BSR  HIDEDLG
            CLR  MODE
            JMP  DRAWHELP
DLGOPEN     BSR  HIDEDLG
            CLR  MODE
            JMP  OPENPROMPT
DLGMAKE     CLR  MODE           ; (the reset clears the box away)
            LDA  NTS
            STA  TSIZE
            LDA  NBPP
            STA  BPP
            LDA  NHIRES
            STA  HIRES
            TST  KEEPNAME       ; (a name given that is not a file yet: it will be)
            BNE  DLGMAKE1
            CLR  FILENAME
DLGMAKE1    CLR  KEEPNAME
            JSR  NEWPROJ
            JMP  DRAWHELP
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
            SUBB #DLGROW        ; the row
            LDA  #'T
            CMPB #2
            BEQ  DLGMOUSE1
            LDA  #'D
            CMPB #3
            BEQ  DLGMOUSE1
            LDA  #'R
            CMPB #4
            BEQ  DLGMOUSE1
            CMPB #6
            BNE  DLGMOUSE9
            LDA  #'O            ; the bottom row: ENTER, O, or ESC
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
DLGMOUSE1   STA  KCHAR
            JMP  DLGKEY
DLGMOUSE9   RTS
;------------------------------------------------------------------------------
; Commands: save, open, new, quit.
;------------------------------------------------------------------------------
SAVECMD     LDX  #T_SAVEAS
            LDU  #DOSAVE
            BRA  ASKNAME
OPENCMD     LDU  #OPENPROMPT
            BRA  IFSAVED
NEWCMD      CLR  KEEPNAME
            LDU  #NEWDIALOG
            BRA  IFSAVED
QUITCMD     LDU  #QUITNOW
IFSAVED     TST  MODIFIED       ; changes not saved: ask first
            BEQ  IFSAVED1
            LDX  #T_DISCARD
            BRA  CONFIRM
IFSAVED1    JMP  ,U
OPENPROMPT  LDX  #T_OPEN
            LDU  #DOOPEN
; ASKNAME: question X, a file name to type (FILENAME to start with), then U.
ASKNAME     STU  PRDONE
            LDY  #FILENAME
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
            JSR  DEFEXT
            LDX  #PR_BUF
            JMP  [PRDONE]
DOSAVE      JMP  SAVEFILE
DOOPEN      JMP  LOADFILE
QUITNOW     LDA  #$80           ; the card as it was (and the keys back to the UART)
            STA  VC_CTRL
            LDA  #B_EXIT
            SWI2
; DEFEXT: ".TLS" on the end of the path at X if its name has no extension
; (and there is room).
DEFEXT      CLRB                ; its length
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
            LDY  #T_EXT
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
            JSR  SETUPDISP
            LDX  #T_OPENED
            JSR  MESSAGE
            ANDCC #$FE
            RTS
LOADSHORT   BSR  CLOSEF         ; (what there was of it, anyway)
            JSR  NAMEIT
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
;------------------------------------------------------------------------------
; Words.
;------------------------------------------------------------------------------
T_EMPTY     FCB  0
T_DLG0      FCN  " A NEW TILE SET"
T_DLG1      FCN  " T  TILES          "
T_DLG2      FCN  " D  COLORS         "
T_DLG3      FCN  " R  SCREEN         "
T_DLG4      FCN  " ENTER MAKE IT  O OPEN A FILE  ESC CANCEL"
T_D8        FCN  "8x8"
T_D16       FCN  "16x16"
T_D4BIT     FCN  "16 (4 BITS A PIXEL)"
T_D8BIT     FCN  "256 (8 BITS A PIXEL)"
T_SAVEAS    FCN  "SAVE AS: "
T_OPEN      FCN  "OPEN: "
T_DISCARD   FCN  "THE CHANGES AREN'T SAVED. GO ON ANYWAY? (Y/N)"
T_EXT       FCN  ".TLS"
T_SAVED     FCN  "SAVED"
T_OPENED    FCN  "OPENED"
T_SHORT     FCN  "THE FILE ENDS EARLY: THIS IS WHAT THERE WAS OF IT"
T_NOTSET    FCN  "THAT ISN'T A TILE SET FILE (OR NOT ONE THIS CAN HOLD)"
T_NOTFOUND  FCN  "NO SUCH FILE"
T_DISKFULL  FCN  "THE DISK IS FULL"
T_BADNAME   FCN  "NOT A FILE NAME (8.3: NAME.EXT)"
T_ISDIR     FCN  "THAT IS A DIRECTORY"
T_FERR      FCN  "FILE ERROR $"
T_NEWFILE   FCN  "A NEW FILE: WHAT KIND OF TILE SET?"
;------------------------------------------------------------------------------
NTS         FCB  8          ; the new set's answers
NBPP        FCB  4
NHIRES      FCB  0
KEEPNAME    FCB  0          ; the name typed with TILEKIT is the new set's
PRDONE      FDB  0          ; what to do with a name typed
CONFMSG     FDB  0
CONFOK      FDB  0          ; what to do on Y
FPATH       FDB  0
FHANDLE     FCB  0
FLEFT       FDB  0
FBYTES      FDB  0
HDRBUF      FCB  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
