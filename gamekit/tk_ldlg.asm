;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 game kit
;    FILE: tk_ldlg.asm
;
; TILEKIT's layer questions (the ... in the layer bar, or ^L), in the panel:
; the layer being edited's tile set (its own, or another layer's), the kind of
; tiles, the screen, the map's size. What can be kept is: a map made larger
; or smaller keeps its cells (cut off, or tile 0 around them), tiles of 16
; colors become tiles of 256 (each in the row it was last used in); tiles of
; 256 colors made 16, or another size, can't be -- the tile set starts again,
; once you say so. INCLUDEd by tilekit.asm.
;------------------------------------------------------------------------------
PSTEMP      equ  $880000    ; (the PSRAM, past the undo steps) a map, while it is resized
;------------------------------------------------------------------------------
; LAYERDLG: the questions about the layer being edited.
LAYERDLG    LDB  CURL
            JSR  LREC
            LDA  LR_SET,X
            STA  PSRC
            LDA  LR_WC,X
            STA  NWC
            LDA  LR_HC,X
            STA  NHC
            LDA  HIRES
            STA  NHIRES
            BSR  PSRCFMT
            LDA  #1
            STA  DLGKIND
            LDA  #M_DIALOG
            STA  MODE
            JMP  REDRAWALL
; PSRCFMT: NTS, NBPP as the tile set PSRC is now (slot not in use: 8x8, 16).
PSRCFMT     LDB  PSRC
            JSR  TSREC
            LDA  TS_TSIZE,X
            STA  NTS
            LDA  TS_BPP,X
            STA  NBPP
            LDD  TS_NTILES,X
            BNE  PSRCFMT9
            LDA  #8
            STA  NTS
            LDA  #4
            STA  NBPP
PSRCFMT9    RTS
; SHOWLDLG: the layer questions, in the panel.
SHOWLDLG    JSR  BARTEXT
            LDA  #DLGCOL
            LDB  #DLGROW
            JSR  TXAT
            LDX  #T_LDLG0
            JSR  TXSTR
            LDA  CURL
            ADDA #'1
            JSR  TXCH
            LDB  #DLGW-7
            JSR  TXSPC
            LDB  #1
            LDX  #T_EMPTY
            JSR  DLGLINE
            LDB  #2             ; its tile set
            LDX  #T_LDLGS
            LDY  #T_OWN
            LDA  PSRC
            CMPA CURL
            BEQ  SHOWLDLG1
            LDY  #T_OFLAYER
            ADDA #'1
            STA  T_OFLAYER+6
SHOWLDLG1   JSR  DLGLINE2
            LDB  #3
            LDX  #T_DLG1
            LDY  #T_D8
            LDA  NTS
            CMPA #8
            BEQ  SHOWLDLG2
            LDY  #T_D16
SHOWLDLG2   JSR  DLGLINE2
            LDB  #4
            LDX  #T_DLG2
            LDY  #T_D4BIT
            LDA  NBPP
            CMPA #8
            BNE  SHOWLDLG3
            LDY  #T_D8BIT
SHOWLDLG3   JSR  DLGLINE2
            LDB  #5
            LDX  #T_DLG3
            LDY  #T_LORES+2
            TST  NHIRES
            BEQ  SHOWLDLG4
            LDY  #T_HIRES+2
SHOWLDLG4   JSR  DLGLINE2
            LDB  #6
            LDX  #T_DLG5
            LDA  NWC
            JSR  DLGSIZE
            LDB  #7
            LDX  #T_DLG6
            LDA  NHC
            JSR  DLGSIZE
            LDB  #8
            LDX  #T_EMPTY
            JSR  DLGLINE
            LDB  #9
            LDX  #T_LDLGOK
            JSR  DLGLINE
            LDB  #10
            LDX  #T_DLG9
            JSR  DLGLINE
            LDB  #11
            LDX  #T_EMPTY
            JMP  DLGLINE
; LDLGKEY: a key in the layer questions.
LDLGKEY     JSR  UPCHAR
            LDA  KCODE
            CMPA #K_ESC
            LBEQ HIDEDLG
            CMPA #K_ENTER
            LBEQ LDLGAPPLY
            CMPA #K_KPENTER
            LBEQ LDLGAPPLY
            CMPB #'S            ; its tile set: its own, then the other layers'
            BNE  LDLGKEY1
            LDA  PSRC
            INCA
            CMPA #3
            BLO  LDLGKEY0
            CLRA
LDLGKEY0    STA  PSRC
            JSR  PSRCFMT
LDLGKEY1    LDA  PSRC           ; (another's: its kind of tiles stays)
            CMPA CURL
            BNE  LDLGKEY3
            CMPB #'T
            BNE  LDLGKEY2
            LDA  NTS
            EORA #$18
            STA  NTS
LDLGKEY2    CMPB #'D
            BNE  LDLGKEY3
            LDA  NBPP
            EORA #$0C
            STA  NBPP
LDLGKEY3    CMPB #'R
            BNE  LDLGKEY4
            LDA  NHIRES
            EORA #1
            STA  NHIRES
LDLGKEY4    CMPB #'W            ; the map's size (16384 cells at most)
            BNE  LDLGKEY5
            LDA  NWC
            INCA
            ANDA #3
            STA  NWC
LDLGKEY41   LDA  NWC
            ADDA NHC
            CMPA #4
            BLS  LDLGKEY5
            DEC  NHC
            BRA  LDLGKEY41
LDLGKEY5    CMPB #'H
            BNE  LDLGKEY6
            LDA  NHC
            INCA
            ANDA #3
            STA  NHC
LDLGKEY51   LDA  NWC
            ADDA NHC
            CMPA #4
            BLS  LDLGKEY6
            DEC  NWC
            BRA  LDLGKEY51
LDLGKEY6    JMP  SHOWLDLG
; LDLGMOUSE: a click on a row is its key.
LDLGMOUSE   LDA  PRESSED
            BITA #VC_MB_LEFT
            BEQ  LDLGMOUSE9
            CLR  KCODE
            CLR  KCHAR
            LDD  MOUSEX
            CMPD #PANELX
            BLO  LDLGMOUSE9
            LDD  MOUSEY
            LSRD
            LSRD
            LSRD
            LSRD
            SUBB #DLGROW
            CMPB #9
            BEQ  LDLGMOUSE3
            CMPB #10
            BEQ  LDLGMOUSE4
            CMPB #2
            BLO  LDLGMOUSE9
            CMPB #7
            BHI  LDLGMOUSE9
            LDX  #LDLGKEYS-2
            LDA  B,X
            STA  KCHAR
            JMP  LDLGKEY
LDLGMOUSE3  LDA  #K_ENTER
            BRA  LDLGMOUSE5
LDLGMOUSE4  LDA  #K_ESC
LDLGMOUSE5  STA  KCODE
            JMP  LDLGKEY
LDLGMOUSE9  RTS
LDLGKEYS    FCB  'S,'T,'D,'R,'W,'H
;------------------------------------------------------------------------------
; Doing it.
;------------------------------------------------------------------------------
; LDLGAPPLY: is there room for it all? Then, if the tile set has to start
; again, ask first; then do it.
LDLGAPPLY   JSR  FLUSHTILE
            JSR  STOREREC
            CLR  LCONV          ; what becomes of the tile set: 0 as it is,
            LDA  PSRC           ; 1 made 256 colors, 2 started again
            CMPA CURL
            BNE  LDLGAPPLY2     ; (another layer's: nothing)
            LDB  CURL
            JSR  TSREC
            LDD  TS_NTILES,X
            BEQ  LDLGAPPLY1     ; (the slot not in use yet: a new one)
            LDA  NTS
            CMPA TS_TSIZE,X
            BNE  LDLGAPPLY1
            LDA  NBPP
            CMPA TS_BPP,X
            BEQ  LDLGAPPLY2
            CMPA #8             ; 16 colors -> 256: kept
            BNE  LDLGAPPLY1
            LDA  #1
            STA  LCONV
            BRA  LDLGAPPLY2
LDLGAPPLY1  LDA  #2
            STA  LCONV
LDLGAPPLY2  JSR  LROOM          ; room for the tiles kept in this layer's room
            BCC  LDLGAPPLY3     ; and the map?
            LDX  #T_NOROOM
            JMP  MESSAGE
LDLGAPPLY3  LDA  LCONV
            CMPA #2
            LBNE LDLGDO
            LDB  CURL           ; starting again: only if there are tiles to lose
            JSR  TSREC
            LDD  TS_NTILES,X
            LBEQ LDLGDO
            LDX  #T_LOSESET
            LDU  #LDLGDO
            JMP  CONFIRM
; LROOM: the tiles in this layer's room (slot CURL: if any layer will use
; it), in the kind they will be, and the new map: within SLICE? Carry if not.
LROOM       CLR  GK_T           ; slot CURL in use, after this?
            LDA  PSRC
            CMPA CURL
            BEQ  LROOM2
            LDB  #2
LROOM1      CMPB CURL           ; (by another layer)
            BEQ  LROOM15
            JSR  LREC
            LDA  LR_SET,X
            CMPA CURL
            BNE  LROOM15
            INC  GK_T
LROOM15     DECB
            BPL  LROOM1
            BRA  LROOM3
LROOM2      INC  GK_T
LROOM3      LDD  #64            ; the map, in 32 bytes
            LDF  NWC
            ADDF NHC
            BEQ  LROOM5
LROOM4      LSLD
            DECF
            BNE  LROOM4
LROOM5      STD  LBYTES
            TST  GK_T
            BEQ  LROOM9
            LDB  CURL           ; the tiles, in 32 bytes, in the kind they will be
            JSR  TSREC
            LDD  TS_NTILES,X
            BNE  LROOM6
            LDD  #1             ; (a new set: one tile)
LROOM6      PSHS D
            LDA  TS_BPP,X       ; their kind: as they are, or as asked
            LDB  TS_TSIZE,X
            TST  LCONV
            BEQ  LROOM7
            LDA  NBPP
            LDB  NTS
LROOM7      JSR  TBSHOF
            SUBA #5
            TFR  A,F
            PULS D
            TSTF
            BEQ  LROOM8
LROOM71     LSLD
            DECF
            BNE  LROOM71
LROOM8      ADDD LBYTES
            STD  LBYTES
LROOM9      LDD  LBYTES
            CMPD #SLICE/32
            BHI  LROOM99
            ANDCC #$FE
            RTS
LROOM99     ORCC #$01
            RTS
; LDLGDO: the layer as asked.
LDLGDO      CLR  MODE
            LDA  #1
            STA  PROJCHG
            JSR  TROWOUT
            LDB  CURL
            JSR  LREC
            LDA  PSRC           ; its tile set
            STA  LR_SET,X
            LDA  NHIRES         ; its screen
            STA  LR_HIRES,X
            LDA  LCONV
            CMPA #1
            BNE  LDLGDO1
            JSR  TO256          ; (16 colors -> 256)
            BRA  LDLGDO2
LDLGDO1     CMPA #2
            BNE  LDLGDO2
            JSR  NEWSLOT        ; (another kind: started again)
LDLGDO2     LDB  CURL           ; a new set of its own, in a slot not in use: one
            JSR  TSREC          ; blank tile
            LDD  TS_NTILES,X
            BNE  LDLGDO3
            LDA  PSRC
            CMPA CURL
            BNE  LDLGDO3
            JSR  NEWSLOT
LDLGDO3     LDB  CURL           ; its map's size: the cells kept
            JSR  LREC
            LDA  NWC
            CMPA LR_WC,X
            BNE  LDLGDO4
            LDA  NHC
            CMPA LR_HC,X
            BEQ  LDLGDO5
LDLGDO4     JSR  RESIZEMAP
LDLGDO5     CLR  UCOUNT         ; (the undo steps don't fit what it is now)
            CLR  UHEAD
            JSR  LOADREC        ; the layer, as it is now
            JSR  TROWIN
            JSR  SETPROJ
            JSR  LOADTILE
            LDA  #1
            STA  STATDIRTY
            JMP  REDRAWALL
; NEWSLOT: slot CURL a new tile set of NTS x NBPP: one blank tile, no file.
NEWSLOT     LDB  CURL
            JSR  TSREC
            LDA  NTS
            STA  TS_TSIZE,X
            LDA  NBPP
            STA  TS_BPP,X
            LDD  #1
            STD  TS_NTILES,X
            CLRD
            STD  TS_TILE,X
            STD  TS_TSTOP,X
            LDA  #1
            STA  TS_MOD,X
            CLR  TS_NAME,X
            LDA  #C_FILL        ; its room's first 256 bytes 0 (tile 0)
            STA  VC_CMD
            LDB  CURL
            JSR  SLICEOF
            JSR  CMDD
            CLRA
            STA  VC_CMD
            STA  VC_CMD
            LDD  #256
            JSR  CMDD
            CLRA
            STA  VC_CMD
            LDA  CURL           ; (its rows: 0)
            CLRB
            LSLA
            LSLA
            ADDD #TROWS
            TFR  D,X
            LDW  #1024
NEWSLOT1    CLR  ,X+
            DECW
            BNE  NEWSLOT1
            JMP  WAITCMD
; TO256: slot CURL's tiles, 16 colors, made 256: each pixel value in the row
; the tile was last used in (its TROWS byte), 0 still 0. The last tile first:
; each grows to twice its bytes, over the ones after it.
TO256       LDB  CURL
            JSR  TSREC
            STX  TSP
            LDA  TS_BPP,X       ; the old and new shifts
            LDB  TS_TSIZE,X
            JSR  TBSHOF
            STA  OLDSH
            INCA
            STA  NEWSH
            LDA  #8
            STA  TS_BPP,X
            LDD  TS_NTILES,X
            STD  TONUM
TO2561      LDD  TONUM
            LBEQ TO2569
            SUBD #1
            STD  TONUM
            LDF  OLDSH          ; its old place: its pixels, unpacked
            BSR  TOADDR
            JSR  PORT1
            LDF  OLDSH
            BSR  POW2
            TFR  D,W
            LDY  #TILEBUF
TO2563      LDA  VC_DATA1
            TFR  A,B
            LSRA
            LSRA
            LSRA
            LSRA
            ANDB #$0F
            STD  ,Y++
            DECW
            BNE  TO2563
            LDA  CURL           ; its row
            CLRB
            LSLA
            LSLA
            ADDD #TROWS
            ADDD TONUM
            TFR  D,X
            LDA  ,X
            LSLA
            LSLA
            LSLA
            LSLA
            STA  OLDROW
            LDF  NEWSH          ; its new place: the pixels, in the row
            BSR  TOADDR
            JSR  PORT0
            LDF  NEWSH
            BSR  POW2
            TFR  D,W
            LDY  #TILEBUF
TO2565      LDA  ,Y+
            BEQ  TO2566
            ORA  OLDROW
TO2566      STA  VC_DATA0
            DECW
            BNE  TO2565
            BRA  TO2561
TO2569      LDX  TSP
            LDA  #1
            STA  TS_MOD,X
            RTS
; POW2: D = 1 << F.
POW2        LDD  #1
POW21       LSLD
            DECF
            BNE  POW21
            RTS
; TOADDR: A:X = where tile TONUM of slot CURL starts, tiles of 1 << F bytes.
TOADDR      LDD  TONUM
TOADDR1     LSLD
            DECF
            BNE  TOADDR1
            PSHS D              ; (its offset)
            LDB  CURL
            JSR  SLICEOF        ; (the room's start: bits 23-8; bits 7-0 are 0)
            STD  GK_T
            PULS D
            ADDA GK_T+1
            TFR  D,X
            LDA  GK_T
            ADCA #0
            RTS
; RESIZEMAP: layer CURL's map from LR_WC x LR_HC to NWC x NHC, the cells kept
; where they are (cut off, or tile 0 around them): out to the PSRAM, the new
; map 0, then back a row at a time.
RESIZEMAP   LDB  CURL
            STB  LTHIS
            JSR  LREC
            STX  LRP
            LDF  LR_WC,X        ; a row's bytes, old and new: 64 << the code
            JSR  RSZ64
            STD  OLDWB
            LDF  NWC
            JSR  RSZ64
            STD  NEWWB
            LDF  LR_HC,X        ; the rows kept: the fewer
            JSR  RSZ32
            STD  ROWS
            LDF  NHC
            JSR  RSZ32
            CMPD ROWS
            BHS  RESIZE1
            STD  ROWS
RESIZE1     LDD  OLDWB          ; and each row's bytes kept: the fewer
            CMPD NEWWB
            BLS  RESIZE2
            LDD  NEWWB
RESIZE2     STD  ROWB
            JSR  LMAPBASE       ; the old map out to the PSRAM
            STD  SRC
            CLR  SRC+2
            LDX  LRP
            JSR  LMAPBYTES
            STD  LBYTES
            LDA  #C_COPY
            STA  VC_CMD
            JSR  CMD3SRC
            LDA  #PSTEMP/$10000
            STA  VC_CMD
            LDD  #PSTEMP&$FFFF
            JSR  CMDD
            CLRA
            STA  VC_CMD
            LDD  LBYTES
            JSR  CMDD
            LDX  LRP            ; the new size: its place, 0 all over
            LDA  NWC
            STA  LR_WC,X
            LDA  NHC
            STA  LR_HC,X
            JSR  LMAPBASE
            STD  DST
            CLR  DST+2
            LDX  LRP
            JSR  LMAPBYTES
            STD  LBYTES
            LDA  #C_FILL
            STA  VC_CMD
            BSR  CMD3DST
            CLRA
            STA  VC_CMD
            LDD  LBYTES
            JSR  CMDD
            CLRA
            STA  VC_CMD
            LDA  #PSTEMP/$10000 ; and the rows back
            STA  SRC
            LDD  #PSTEMP&$FFFF
            STD  SRC+1
RESIZE3     LDD  ROWS
            BEQ  RESIZE9
            SUBD #1
            STD  ROWS
            LDA  #C_COPY
            STA  VC_CMD
            BSR  CMD3SRC
            BSR  CMD3DST
            CLRA
            STA  VC_CMD
            LDD  ROWB
            JSR  CMDD
            LDX  #SRC           ; on to the next rows
            LDD  OLDWB
            BSR  ADD24
            LDX  #DST
            LDD  NEWWB
            BSR  ADD24
            BRA  RESIZE3
RESIZE9     JMP  WAITCMD
; RSZ64, RSZ32: D = 64 << F, 32 << F.
RSZ64       LDD  #64
            BRA  RSZ1
RSZ32       LDD  #32
RSZ1        TSTF
            BEQ  RSZ9
RSZ2        LSLD
            DECF
            BNE  RSZ2
RSZ9        RTS
; CMD3SRC, CMD3DST: SRC, DST (3 bytes) to the command port.
CMD3SRC     LDA  SRC
            STA  VC_CMD
            LDD  SRC+1
            JMP  CMDD
CMD3DST     LDA  DST
            STA  VC_CMD
            LDD  DST+1
            JMP  CMDD
; ADD24: the 24-bit number at X, + D.
ADD24       ADDD 1,X
            STD  1,X
            LDA  ,X
            ADCA #0
            STA  ,X
            RTS
;------------------------------------------------------------------------------
T_LDLG0     FCN  " LAYER "
T_LDLGS     FCN  " S TILES  "
T_OWN       FCN  "ITS OWN"
T_OFLAYER   FCN  "LAYER n'S"
T_LDLGOK    FCN  " ENTER  DO IT"
T_LOSESET   FCN  "THE TILE SET STARTS AGAIN: ITS TILES ARE LOST. GO ON? (Y/N)"
PSRC        FCB  0          ; the layer questions' answers: the tile set's slot
LCONV       FCB  0
LBYTES      FDB  0
OLDSH       FCB  0
NEWSH       FCB  0
TONUM       FDB  0
OLDWB       FDB  0
NEWWB       FDB  0
ROWS        FDB  0
ROWB        FDB  0
SRC         FCB  0,0,0
DST         FCB  0,0,0
DLGKIND     FCB  0          ; the questions being asked: 0 a new set, 1 a layer's
