;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 game kit
;    FILE: tk_src.asm
;
; TILEKIT's export: the tile set and the map as assembly source, for a game to
; INCLUDE (after VIDCARD.D). Each is a module of its own, its labels starting
; with its file's name, so maps can share a set's module:
;
;   SET.ASM   SET_TSIZE, SET_BPP, SET_NTILES, SET_TBYTES, SET_LMODE (a tile
;             layer's L_MODE for them), SET_TOCARD (the palette into the card
;             and the tiles to A:X in video memory), SET_PAL, SET_TILES
;   LV1.ASM   LV1_W, LV1_H, LV1_LMAP (a tile layer's L_MAP), LV1_BYTES,
;             LV1_TOCARD (the cells to A:X in video memory), LV1_CELLS
;
; The text goes out through IOBUF, 512 bytes at a time. INCLUDEd by tilekit.asm.
;------------------------------------------------------------------------------
; EXPORTCMD: the project as assembly source: its name asked for (the
; project's, .ASM, to start with); then a module for each tile set in use and
; each map, named after it (GAME.ASM: GAME1T.ASM ... the sets, GAME1M.ASM ...
; the maps), and the project's own module, GAME.ASM, which INCLUDEs them.
EXPORTCMD   LDX  #PROJNAME
            LDY  #T_DEFPROJ
            JSR  ASMNAME
            LDX  #T_EXPPROJ
            LDY  #EXPNAME
            LDU  #T_EXTASM
            STU  PREXT
            LDU  #EXPPROJ
            JMP  ASKNAME
; EXPPROJ: the project's modules, the project's own at X.
EXPPROJ     LDY  #EPATH
            JSR  STRCPY
            LDX  #EPATH         ; ESTEM: its name, 6 characters at most
            TFR  X,Y
EXPPROJ1    LDA  ,X+
            BEQ  EXPPROJ2
            CMPA #'/
            BNE  EXPPROJ1
            TFR  X,Y
            BRA  EXPPROJ1
EXPPROJ2    LDX  #ESTEM
            LDB  #6
EXPPROJ3    LDA  ,Y+
            BEQ  EXPPROJ4
            CMPA #'.
            BEQ  EXPPROJ4
            STA  ,X+
            DECB
            BNE  EXPPROJ3
EXPPROJ4    CLR  ,X
            LDA  CURL
            STA  PORIG
            CLR  PSLOT          ; each tile set in use: GAMEnT.ASM
EXPPROJ5    LDB  PSLOT
            JSR  SLOTUSER
            BCS  EXPPROJ6
            JSR  SWITCHQ
            LDB  PSLOT
            LDA  #'T
            JSR  COMPNAME
            LDX  #EXPNAME
            JSR  EXPSET
            LBCS EXPPROJ99
EXPPROJ6    INC  PSLOT
            LDA  PSLOT
            CMPA #3
            BLO  EXPPROJ5
            CLR  PSLOT          ; each map: GAMEnM.ASM
EXPPROJ7    LDB  PSLOT
            JSR  SWITCHQ
            LDB  PSLOT
            LDA  #'M
            JSR  COMPNAME
            LDX  #EXPNAME
            JSR  EXPMAP
            LBCS EXPPROJ99
            INC  PSLOT
            LDA  PSLOT
            CMPA #3
            BLO  EXPPROJ7
            JSR  STOREREC       ; the project's own module
            LDX  #EPATH
            JSR  OUTOPEN
            LBCS EXPPROJE
            LDX  #T_PRJHEAD
            JSR  OUTTEXT
            CLR  PSLOT          ; INCLUDE "GAMEnT.ASM" ...
EXPPROJ8    LDB  PSLOT
            JSR  SLOTUSER
            BCS  EXPPROJ9
            LDA  #'T
            LDB  PSLOT
            JSR  OUTINC
EXPPROJ9    INC  PSLOT
            LDA  PSLOT
            CMPA #3
            BLO  EXPPROJ8
            CLR  PSLOT
EXPPROJ10   LDA  #'M
            LDB  PSLOT
            JSR  OUTINC
            INC  PSLOT
            LDA  PSLOT
            CMPA #3
            BLO  EXPPROJ10
            LDX  #T_PRJVBASE    ; where they go: one after another
            JSR  OUTTEXT
            LDA  #'V
            STA  PREVK
            CLR  PSLOT
EXPPROJ11   LDB  PSLOT
            JSR  SLOTUSER
            BCS  EXPPROJ12
            LDA  #'T
            LDB  PSLOT
            JSR  OUTPLACE
EXPPROJ12   INC  PSLOT
            LDA  PSLOT
            CMPA #3
            BLO  EXPPROJ11
            CLR  PSLOT
EXPPROJ13   LDA  #'M
            LDB  PSLOT
            JSR  OUTPLACE
            INC  PSLOT
            LDA  PSLOT
            CMPA #3
            BLO  EXPPROJ13
            LDX  #T_PRJEND      ; @_END
            JSR  OUTTEXT
            JSR  OUTPREV
            JSR  OUTNL
            LDX  #T_PRJSHOW     ; @_SHOW: the layers shown
            JSR  OUTTEXT
            CLRB
            LDA  #1
            STA  LBIT
            CLR  LDCBITS
EXPPROJ14   PSHS B
            LDX  #ORDER
            LDB  B,X
            JSR  LREC
            TST  LR_SHOW,X
            BEQ  EXPPROJ15
            LDA  LDCBITS
            ORA  LBIT
            STA  LDCBITS
EXPPROJ15   LSL  LBIT
            PULS B
            INCB
            CMPB #3
            BLO  EXPPROJ14
            CLRA
            LDB  LDCBITS
            JSR  OUTDEC
            JSR  OUTNL
            LDX  #T_PRJCODE     ; @_TOCARD: each set, each map, the palette, the layers
            JSR  OUTTEXT
            CLR  PSLOT
EXPPROJ16   LDB  PSLOT
            JSR  SLOTUSER
            BCS  EXPPROJ17
            LDA  #'T
            LDB  PSLOT
            JSR  OUTTOCARD
EXPPROJ17   INC  PSLOT
            LDA  PSLOT
            CMPA #3
            BLO  EXPPROJ16
            CLR  PSLOT
EXPPROJ18   LDA  #'M
            LDB  PSLOT
            JSR  OUTTOCARD
            INC  PSLOT
            LDA  PSLOT
            CMPA #3
            BLO  EXPPROJ18
            LDX  #T_PRJCODE2
            JSR  OUTTEXT
            CLRB                ; @_LAYERS: the card's layers, from the back
EXPPROJ19   PSHS B
            LDX  #ORDER
            LDB  B,X
            STB  LTHIS
            JSR  LREC
            STX  LRP
            JSR  OUTFCB         ; its mode, its map's size
            LDB  LR_SET,X
            STB  GK_BITS
            JSR  TSREC
            LDA  #LM_TILE+LM_4BPP
            LDB  TS_BPP,X
            CMPB #8
            BNE  EXPPROJ20
            LDA  #LM_TILE+LM_8BPP
EXPPROJ20   LDB  TS_TSIZE,X
            CMPB #16
            BNE  EXPPROJ21
            ORA  #LM_BIG
EXPPROJ21   LDX  LRP
            TST  LR_HIRES,X
            BEQ  EXPPROJ22
            ORA  #LM_HIRES
EXPPROJ22   JSR  OUTHEX2
            LDA  #',
            JSR  OUTCH
            LDX  LRP
            LDA  LR_HC,X
            LSLA
            LSLA
            ORA  LR_WC,X
            JSR  OUTHEX2
            JSR  OUTNL
            JSR  OUTFCB         ; its map's place, its tiles'
            LDA  #'M
            LDB  LTHIS
            JSR  OUTADDR3
            JSR  OUTNL
            JSR  OUTFCB
            LDA  #'T
            LDB  GK_BITS
            JSR  OUTADDR3
            JSR  OUTNL
            LDX  #T_PRJLREST
            JSR  OUTTEXT
            PULS B
            INCB
            CMPB #3
            LBLO EXPPROJ19
            LDX  #T_PRJPAL      ; @_PAL: the palette
            JSR  OUTTEXT
            LDX  #PALBUF
            LDE  #32
EXPPROJ23   JSR  OUTFDB
            LDF  #8
EXPPROJ24   LDD  ,X++
            JSR  OUTHEX4
            DECF
            BEQ  EXPPROJ25
            LDA  #',
            JSR  OUTCH
            BRA  EXPPROJ24
EXPPROJ25   JSR  OUTNL
            DECE
            BNE  EXPPROJ23
            JSR  OUTCLOSE
            BRA  EXPPROJ99
EXPPROJE    JSR  FILEERR
EXPPROJ99   LDB  PORIG          ; back to the layer being edited
            JSR  SWITCHQ
            JMP  REDRAWBACK
; COMPNAME: EXPNAME = ESTEM, the digit B+1, the letter A, .ASM.
COMPNAME    PSHS D
            LDX  #ESTEM
            LDY  #EXPNAME
COMPNAME1   LDA  ,X+
            BEQ  COMPNAME2
            STA  ,Y+
            BRA  COMPNAME1
COMPNAME2   LDB  1,S
            ADDB #'1
            STB  ,Y+
            LDA  ,S
            STA  ,Y+
            LEAS 2,S
            LDX  #T_EXTASM
            JMP  STRCPY
; OUTCOMP: a component module's name (labels' start): ESTEM, B+1, A.
OUTCOMP     PSHS D
            LDX  #ESTEM
            JSR  OUTTEXT
            LDA  1,S
            ADDA #'1
            JSR  OUTCH
            PULS D
            JMP  OUTCH
; OUTINC: |INCLUDE "GAMEnX.ASM"
OUTINC      PSHS D
            LDX  #T_PRJINC
            JSR  OUTTEXT
            PULS D
            BSR  OUTCOMP
            LDX  #T_PRJINC2
            JMP  OUTTEXT
; OUTPLACE: @_Xn|EQU  (the one before), and this one is the one before now.
OUTPLACE    STA  PLACEK
            STB  PLACED
            LDX  #T_AT_
            JSR  OUTTEXT
            LDA  PLACEK
            JSR  OUTCH
            LDA  PLACED
            ADDA #'1
            JSR  OUTCH
            LDX  #T_EQU
            JSR  OUTTEXT
            BSR  OUTPREV
            JSR  OUTNL
            LDA  PLACEK
            STA  PREVK
            LDA  PLACED
            STA  PREVD
            RTS
; OUTPREV: where the one before ends: @_VBASE, or @_Tn+GAMEnT_TBYTES, or
; @_Mn+GAMEnM_BYTES.
OUTPREV     LDA  PREVK
            CMPA #'V
            BNE  OUTPREV1
            LDX  #T_PRJVB
            JMP  OUTTEXT
OUTPREV1    LDX  #T_AT_
            JSR  OUTTEXT
            LDA  PREVK
            JSR  OUTCH
            LDA  PREVD
            ADDA #'1
            JSR  OUTCH
            LDA  #'+
            JSR  OUTCH
            LDA  PREVK
            LDB  PREVD
            JSR  OUTCOMP
            LDX  #T_PRJTB
            LDA  PREVK
            CMPA #'T
            BEQ  OUTPREV2
            LDX  #T_PRJMB
OUTPREV2    JMP  OUTTEXT
; OUTTOCARD: |LDA #@_Xn/$10000 |LDX #@_Xn&$FFFF |JSR GAMEnX_TOCARD
OUTTOCARD   STA  PLACEK
            STB  PLACED
            LDX  #T_PRJLDA
            JSR  OUTTEXT
            BSR  OUTPLACEN
            LDX  #T_PRJLDA2
            JSR  OUTTEXT
            LDX  #T_PRJLDX
            JSR  OUTTEXT
            BSR  OUTPLACEN
            LDX  #T_PRJLDX2
            JSR  OUTTEXT
            LDX  #T_PRJJSR
            JSR  OUTTEXT
            LDA  PLACEK
            LDB  PLACED
            JSR  OUTCOMP
            LDX  #T_PRJJSR2
            JMP  OUTTEXT
; OUTPLACEN: @_Xn
OUTPLACEN   LDX  #T_AT_
            JSR  OUTTEXT
            LDA  PLACEK
            JSR  OUTCH
            LDA  PLACED
            ADDA #'1
            JMP  OUTCH
; OUTADDR3: @_Xn/$10000,(@_Xn/$100)&$FF,@_Xn&$FF
OUTADDR3    STA  PLACEK
            STB  PLACED
            BSR  OUTPLACEN
            LDX  #T_PRJA1
            JSR  OUTTEXT
            BSR  OUTPLACEN
            LDX  #T_PRJA2
            JSR  OUTTEXT
            BSR  OUTPLACEN
            LDX  #T_PRJA3
            JMP  OUTTEXT
; ASMNAME: EXPNAME = the name of the file at X without its extension (or the one
; at Y, if X is empty), and .ASM.
ASMNAME     TST  ,X
            BNE  ASMNAME1
            TFR  Y,X
ASMNAME1    LDY  #EXPNAME
ASMNAME2    LDA  ,X+
            BEQ  ASMNAME3
            CMPA #'.
            BEQ  ASMNAME3
            STA  ,Y+
            CMPY #EXPNAME+PR_MAX-4
            BLO  ASMNAME2
ASMNAME3    LDX  #T_EXTASM
            JMP  STRCPY
;------------------------------------------------------------------------------
; The tile set's module.
;------------------------------------------------------------------------------
EXPSET      JSR  FLUSHTILE
            JSR  OUTOPEN
            LBCS FILEERR
            LDX  #T_SETHEAD     ; what it is
            JSR  OUTTEXT
            LDX  #FILENAME
            JSR  OUTNAME
            JSR  OUTNL
            LDX  #T_SETHEAD2
            JSR  OUTTEXT
            CLRA
            LDB  TSIZE
            JSR  OUTDEC
            LDA  #'x
            JSR  OUTCH
            CLRA
            LDB  TSIZE
            JSR  OUTDEC
            LDX  #T_SETHEAD3
            JSR  OUTTEXT
            LDX  #T_16COLS
            LDA  BPP
            CMPA #8
            BNE  EXPSET1
            LDX  #T_256COLS
EXPSET1     JSR  OUTTEXT
            LDX  #T_LORES+2
            TST  HIRES
            BEQ  EXPSET2
            LDX  #T_HIRES+2
EXPSET2     JSR  OUTTEXT
            LDX  #T_SETHEAD4
            JSR  OUTTEXT
            LDD  NTILES
            JSR  OUTDEC
            LDX  #T_SETHEAD5
            JSR  OUTTEXT
            LDD  TB
            JSR  OUTDEC
            LDX  #T_SETHEAD6
            JSR  OUTTEXT
            LDX  #T_TSIZE       ; the numbers
            CLRA
            LDB  TSIZE
            JSR  OUTEQU
            LDX  #T_BPP
            CLRA
            LDB  BPP
            JSR  OUTEQU
            LDX  #T_NTILES
            LDD  NTILES
            JSR  OUTEQU
            LDD  NTILES         ; (half of all their bytes: all of them can be
            LDF  TBSHIFT        ; 65536, too many for 16 bits -- TOCARD takes
            DECF                ; half at a time)
EXPSET3     LSLD
            DECF
            BNE  EXPSET3
            LDX  #T_THALF
            JSR  OUTEQU
            LDX  #T_LMODE
            JSR  LAYERMODE
            JSR  OUTEQU
            LDX  #T_SETCODE     ; the routine
            JSR  OUTTEXT
            LDX  #T_PALLAB      ; the palette: 8 colors a line
            JSR  OUTTEXT
            LDX  #PALBUF
            LDE  #32
EXPSET4     JSR  OUTFDB
            LDF  #8
EXPSET5     LDD  ,X++
            JSR  OUTHEX4
            DECF
            BEQ  EXPSET6
            LDA  #',
            JSR  OUTCH
            BRA  EXPSET5
EXPSET6     JSR  OUTNL
            DECE
            BNE  EXPSET4
            LDX  #T_TILESLAB    ; the tiles, as the card holds them: 16 bytes a line
            JSR  OUTTEXT
            JSR  TBASEAX
            JSR  PORT1
            CLRD
            STD  EXPN
EXPSET7     LDX  #T_TILECOM     ; "; tile n"
            JSR  OUTTEXT
            LDD  EXPN
            JSR  OUTDEC
            JSR  OUTNL
            LDD  TB             ; its lines
            LSRD
            LSRD
            LSRD
            LSRD
            TFR  B,E
EXPSET8     JSR  OUTFCB
            LDF  #16
EXPSET9     LDA  VC_DATA1
            JSR  OUTHEX2
            DECF
            BEQ  EXPSET10
            LDA  #',
            JSR  OUTCH
            BRA  EXPSET9
EXPSET10    JSR  OUTNL
            DECE
            BNE  EXPSET8
            LDD  EXPN
            ADDD #1
            STD  EXPN
            CMPD NTILES
            BNE  EXPSET7
            JMP  OUTCLOSE
; LAYERMODE: D = L_MODE for a tile layer of the set.
LAYERMODE   LDB  #LM_TILE+LM_4BPP
            LDA  BPP
            CMPA #8
            BNE  LAYERMODE1
            LDB  #LM_TILE+LM_8BPP
LAYERMODE1  TST  HIRES
            BEQ  LAYERMODE2
            ORB  #LM_HIRES
LAYERMODE2  LDA  TSIZE
            CMPA #16
            BNE  LAYERMODE3
            ORB  #LM_BIG
LAYERMODE3  CLRA
            RTS
;------------------------------------------------------------------------------
; The map's module.
;------------------------------------------------------------------------------
EXPMAP      JSR  OUTOPEN
            LBCS FILEERR
            LDX  #T_MAPHEAD
            JSR  OUTTEXT
            LDX  #MAPNAME
            JSR  OUTNAME
            LDX  #T_MAPHEAD2
            JSR  OUTTEXT
            LDD  MAPW
            JSR  OUTDEC
            LDA  #'x
            JSR  OUTCH
            LDD  MAPH
            JSR  OUTDEC
            LDX  #T_MAPHEAD3
            JSR  OUTTEXT
            LDX  #FILENAME
            JSR  OUTNAME
            LDX  #T_MAPHEAD4
            JSR  OUTTEXT
            LDX  #T_MAPW
            LDD  MAPW
            JSR  OUTEQU
            LDX  #T_MAPH
            LDD  MAPH
            JSR  OUTEQU
            LDX  #T_LMAP
            LDA  MAPHC
            LSLA
            LSLA
            ORA  MAPWC
            TFR  A,B
            CLRA
            JSR  OUTEQU
            LDX  #T_MBYTES
            LDD  MAPBYTES
            JSR  OUTEQU
            LDX  #T_MAPCODE
            JSR  OUTTEXT
            LDX  #T_CELLSLAB
            JSR  OUTTEXT
            JSR  MBASEAX   ; the cells, a row at a time, 8 a line
            JSR  PORT1
            CLRD
            STD  EXPN
EXPMAP1     LDX  #T_ROWCOM      ; "; row n"
            JSR  OUTTEXT
            LDD  EXPN
            JSR  OUTDEC
            JSR  OUTNL
            LDD  MAPW
            LSRD
            LSRD
            LSRD
            TFR  B,E            ; (its lines: 4 to 32)
EXPMAP2     JSR  OUTFDB
            LDF  #8
EXPMAP3     LDA  VC_DATA1
            LDB  VC_DATA1
            JSR  OUTHEX4
            DECF
            BEQ  EXPMAP4
            LDA  #',
            JSR  OUTCH
            BRA  EXPMAP3
EXPMAP4     JSR  OUTNL
            DECE
            BNE  EXPMAP2
            LDD  EXPN
            ADDD #1
            STD  EXPN
            CMPD MAPH
            BNE  EXPMAP1
;------------------------------------------------------------------------------
; Writing the text.
;------------------------------------------------------------------------------
; OUTCLOSE: the rest out, the file closed, and said how it went.
OUTCLOSE    JSR  OUTFLUSH
            LDB  OHANDLE
            LDA  #B_FCLOSE_NAME
            SWI2
            BCS  OUTCLOSE9
            LDA  OERR
            BNE  OUTCLOSE9
            LDX  OUTMSG
            JSR  MESSAGE
            ANDCC #$FE
            RTS
OUTCLOSE9   TST  OERR
            BEQ  OUTCLOSE8
            LDA  OERR
OUTCLOSE8   JMP  FILEERR
; OUTOPEN: the file named at X opened to be written; OPFX its labels' start (the
; name's letters and digits, up to its extension; X first if it starts with a
; digit). Carry set (A the error) if it couldn't be.
OUTOPEN     PSHS X
            LDE  #FOPEN_WRITE
            LDA  #B_FOPEN_NAME
            SWI2
            PULS X
            BCS  OUTOPEN9
            STA  OHANDLE
            CLR  OERR
            CLR  OCOL
            LDY  #IOBUF
            STY  OPTR
            TFR  X,Y            ; the last name in the path
OUTOPEN1    LDA  ,X+
            BEQ  OUTOPEN2
            CMPA #'/
            BNE  OUTOPEN1
            TFR  X,Y
            BRA  OUTOPEN1
OUTOPEN2    LDX  #OPFX
            LDA  ,Y
            CMPA #'0
            BLO  OUTOPEN3
            CMPA #'9
            BHI  OUTOPEN3
            LDA  #'X
            STA  ,X+
OUTOPEN3    LDA  ,Y+
            BEQ  OUTOPEN5
            CMPA #'.
            BEQ  OUTOPEN5
            CMPA #'_
            BEQ  OUTOPEN4
            CMPA #'0
            BLO  OUTOPEN3
            CMPA #'9
            BLS  OUTOPEN4
            CMPA #'A
            BLO  OUTOPEN3
            CMPA #'Z
            BHI  OUTOPEN3
OUTOPEN4    STA  ,X+
            CMPX #OPFX+9
            BLO  OUTOPEN3
OUTOPEN5    CLR  ,X
            ANDCC #$FE
OUTOPEN9    RTS
; OUTCH: character A out. (Every register kept.)
OUTCH       PSHS X,A
            LDX  OPTR
            STA  ,X+
            STX  OPTR
            INC  OCOL
            CMPA #$0A
            BNE  OUTCH1
            CLR  OCOL
OUTCH1      CMPX #IOBUF+512
            BLO  OUTCH9
            BSR  OUTFLUSH
OUTCH9      PULS A,X,PC
; OUTFLUSH: IOBUF so far to the file (unless a write has failed already).
OUTFLUSH    PSHS D,X,Y
            LDD  OPTR
            SUBD #IOBUF
            BEQ  OUTFLUSH9
            TST  OERR
            BNE  OUTFLUSH8
            TFR  D,Y
            LDX  #IOBUF
            LDB  OHANDLE
            LDA  #B_FWRITE
            SWI2
            BCC  OUTFLUSH8
            STA  OERR
OUTFLUSH8   LDX  #IOBUF
            STX  OPTR
OUTFLUSH9   PULS D,X,Y,PC
; OUTNL: the end of a line (CR LF).
OUTNL       PSHS A
            LDA  #$0D
            BSR  OUTCH
            LDA  #$0A
            BSR  OUTCH
            PULS A,PC
; OUTTEXT: the text at X: "@" is the labels' start (OPFX), "|" moves on to the
; opcode column (12), "\n" (a $0A) ends a line. (X is left after its 0.)
OUTTEXT     LDA  ,X+
            BEQ  OUTTEXT9
            CMPA #'@
            BEQ  OUTTEXT1
            CMPA #'|
            BEQ  OUTTEXT2
            CMPA #$0A
            BEQ  OUTTEXT3
            BSR  OUTCH
            BRA  OUTTEXT
OUTTEXT1    PSHS X
            LDX  #OPFX
            BSR  OUTTEXT
            PULS X
            BRA  OUTTEXT
OUTTEXT2    BSR  OUTTAB
            BRA  OUTTEXT
OUTTEXT3    BSR  OUTNL
            BRA  OUTTEXT
OUTTEXT9    RTS
; OUTTAB: spaces to column 12 (at least one).
OUTTAB      LDA  #$20
OUTTAB1     BSR  OUTCH
            LDB  OCOL
            CMPB #12
            BLO  OUTTAB1
            RTS
; OUTNAME: the name at X ("(NEW)" if there is none).
OUTNAME     TST  ,X
            BNE  OUTNAME1
            LDX  #T_NONAME
OUTNAME1    BRA  OUTTEXT
; OUTFDB, OUTFCB: the start of a line of data.
OUTFDB      PSHS X
            LDX  #T_FDB
            BRA  OUTFCB1
OUTFCB      PSHS X
            LDX  #T_FCB
OUTFCB1     BSR  OUTTEXT
            PULS X,PC
; OUTEQU: the label X (after "@_"), its value D: "@_name|EQU  value".
OUTEQU      PSHS D
            BSR  OUTTEXT
            LDX  #T_EQU
            BSR  OUTTEXT
            PULS D
            BSR  OUTDEC
            BRA  OUTNL
; OUTHEX4: $ and D in hex; OUTHEX2: $ and A.
OUTHEX4     PSHS B
            BSR  OUTHEX2
            PULS A
            BRA  OUTHEXA
OUTHEX2     PSHS A
            LDA  #'$
            JSR  OUTCH
            PULS A
OUTHEXA     PSHS A
            LSRA
            LSRA
            LSRA
            LSRA
            BSR  OUTHEX1
            PULS A
            ANDA #$0F
OUTHEX1     ADDA #'0
            CMPA #'9
            BLS  OUTHEX9
            ADDA #'A-'9-1
OUTHEX9     JMP  OUTCH
; OUTDEC: D (0-65535) in decimal.
OUTDEC      PSHS X
            LDX  #T_POWERS
            CLR  ODIGIT         ; (no digit out yet: no leading zeros)
OUTDEC1     CLR  OCOUNT
OUTDEC2     CMPD ,X             ; how many of this power
            BLO  OUTDEC3
            SUBD ,X
            INC  OCOUNT
            BRA  OUTDEC2
OUTDEC3     PSHS D
            LDA  OCOUNT
            BNE  OUTDEC4
            TST  ODIGIT
            BNE  OUTDEC4
            CMPX #T_POWERS+8    ; (the ones: always)
            BNE  OUTDEC5
OUTDEC4     ADDA #'0
            JSR  OUTCH
            INC  ODIGIT
OUTDEC5     PULS D
            LEAX 2,X
            CMPX #T_POWERS+10
            BNE  OUTDEC1
            PULS X,PC
T_POWERS    FDB  10000,1000,100,10,1
;------------------------------------------------------------------------------
; Words. (In the text written: @ the labels' start, | the opcode column.)
;------------------------------------------------------------------------------
T_EXPPROJ   FCN  "EXPORT THE PROJECT AS: "
T_DEFPROJ   FCN  "GAME"
T_EXPORTED  FCN  "EXPORTED"
T_EXTASM    FCN  ".ASM"
T_FDB       FCN  "|FDB  "
T_FCB       FCN  "|FCB  "
T_EQU       FCN  "|EQU  "
T_SETHEAD   FCN  "; Tile set "
T_SETHEAD2  FCC  "; from TILEKIT: "
            FCB  0
T_SETHEAD3  FCN  " tiles of "
T_16COLS    FCN  "16 colors (4 bits a pixel), for "
T_256COLS   FCN  "256 colors (8 bits a pixel), for "
T_SETHEAD4  FCC  "."
            FCB  $0A
            FCN  "; "
T_SETHEAD5  FCN  " tiles of "
T_SETHEAD6  FCC  " bytes, rows of pixels packed from the high bits, as the card"
            FCB  $0A
            FCC  "; holds them. INCLUDE this after VIDCARD.D. @_TOCARD puts the palette into"
            FCB  $0A
            FCC  "; the card and the tiles at A:X in video memory; a tile layer showing them"
            FCB  $0A
            FCC  "; has the mode @_LMODE (its L_TILEBASE: A:X)."
            FCB  $0A
            FCB  0
T_TSIZE     FCN  "@_TSIZE"
T_BPP       FCN  "@_BPP"
T_NTILES    FCN  "@_NTILES"
T_THALF     FCN  "@_THALF"
T_LMODE     FCN  "@_LMODE"
T_SETCODE   FCC  "@_TBYTES|EQU  @_THALF*2"
            FCB  $0A
            FCC  "@_TOCARD|PSHS A,X"
            FCB  $0A
            FCC  "|LDA  #VC_PAL/$10000"
            FCB  $0A
            FCC  "|STA  VC_ADDR0"
            FCB  $0A
            FCC  "|LDX  #VC_PAL&$FFFF"
            FCB  $0A
            FCC  "|STX  VC_ADDR0M"
            FCB  $0A
            FCC  "|LDD  #1"
            FCB  $0A
            FCC  "|STD  VC_INC0"
            FCB  $0A
            FCC  "|LDX  #@_PAL"
            FCB  $0A
            FCC  "|LDY  #VC_DATA0"
            FCB  $0A
            FCC  "|LDW  #512"
            FCB  $0A
            FCC  "|TFM  X+,Y"
            FCB  $0A
            FCC  "|PULS A,X"
            FCB  $0A
            FCC  "|STA  VC_ADDR0"
            FCB  $0A
            FCC  "|STX  VC_ADDR0M"
            FCB  $0A
            FCC  "|LDX  #@_TILES"
            FCB  $0A
            FCC  "|LDW  #@_THALF"
            FCB  $0A
            FCC  "|TFM  X+,Y"
            FCB  $0A
            FCC  "|LDW  #@_THALF"
            FCB  $0A
            FCC  "|TFM  X+,Y"
            FCB  $0A
            FCC  "|RTS"
            FCB  $0A
            FCB  0
T_PALLAB    FCC  "; The palette: 256 colors, RGB565"
            FCB  $0A
            FCC  "@_PAL"
            FCB  $0A
            FCB  0
T_TILESLAB  FCC  "; The tiles"
            FCB  $0A
            FCC  "@_TILES"
            FCB  $0A
            FCB  0
T_TILECOM   FCN  "; tile "
T_MAPHEAD   FCN  "; Map "
T_MAPHEAD2  FCN  " from TILEKIT: "
T_MAPHEAD3  FCN  " cells of the tile set "
T_MAPHEAD4  FCC  "."
            FCB  $0A
            FCC  "; Each cell is the card's map entry: the tile (bits 0-9), flipped across (10),"
            FCB  $0A
            FCC  "; flipped down (11), the palette row (12-15). INCLUDE this after VIDCARD.D."
            FCB  $0A
            FCC  "; @_TOCARD puts the cells at A:X in video memory; a tile layer showing them"
            FCB  $0A
            FCC  "; has the map size @_LMAP (its L_MAPBASE: A:X)."
            FCB  $0A
            FCB  0
T_MAPW      FCN  "@_W"
T_MAPH      FCN  "@_H"
T_LMAP      FCN  "@_LMAP"
T_MBYTES    FCN  "@_BYTES"
T_MAPCODE   FCC  "@_TOCARD|STA  VC_ADDR0"
            FCB  $0A
            FCC  "|STX  VC_ADDR0M"
            FCB  $0A
            FCC  "|LDD  #1"
            FCB  $0A
            FCC  "|STD  VC_INC0"
            FCB  $0A
            FCC  "|LDX  #@_CELLS"
            FCB  $0A
            FCC  "|LDY  #VC_DATA0"
            FCB  $0A
            FCC  "|LDW  #@_BYTES"
            FCB  $0A
            FCC  "|TFM  X+,Y"
            FCB  $0A
            FCC  "|RTS"
            FCB  $0A
            FCB  0
T_CELLSLAB  FCC  "; The cells, a row at a time"
            FCB  $0A
            FCC  "@_CELLS"
            FCB  $0A
            FCB  0
T_ROWCOM    FCN  "; row "
T_PRJHEAD   FCC  "; Project @ from TILEKIT: its three tile layers, ready for the card."
            FCB  $0A
            FCC  "; INCLUDE this after VIDCARD.D. @_TOCARD puts the tile sets and maps into"
            FCB  $0A
            FCC  "; video memory one after another from @_VBASE (to @_END), the palette"
            FCB  $0A
            FCC  "; @_PAL into the card, and sets its three layers up as they were in TILEKIT"
            FCB  $0A
            FCC  "; (@_LAYERS, from the back; @_SHOW, the ones shown), scrolled to 0, 0."
            FCB  $0A
            FCB  0
T_PRJINC    FCN  '|INCLUDE "'
T_PRJINC2   FCC  '.ASM"'
            FCB  $0A
            FCB  0
T_PRJVBASE  FCC  "@_VBASE|EQU  $000000"
            FCB  $0A
            FCB  0
T_PRJVB     FCN  "@_VBASE"
T_AT_       FCN  "@_"
T_PRJTB     FCN  "_TBYTES"
T_PRJMB     FCN  "_BYTES"
T_PRJEND    FCN  "@_END|EQU  "
T_PRJSHOW   FCN  "@_SHOW|EQU  "
T_PRJCODE   FCC  "@_TOCARD"
            FCB  $0A
            FCB  0
T_PRJLDA    FCN  "|LDA  #"
T_PRJLDA2   FCC  "/$10000"
            FCB  $0A
            FCB  0
T_PRJLDX    FCN  "|LDX  #"
T_PRJLDX2   FCC  "&$FFFF"
            FCB  $0A
            FCB  0
T_PRJJSR    FCN  "|JSR  "
T_PRJJSR2   FCC  "_TOCARD"
            FCB  $0A
            FCB  0
T_PRJCODE2  FCC  "|LDA  #VC_PAL/$10000"
            FCB  $0A
            FCC  "|STA  VC_ADDR0"
            FCB  $0A
            FCC  "|LDX  #VC_PAL&$FFFF"
            FCB  $0A
            FCC  "|STX  VC_ADDR0M"
            FCB  $0A
            FCC  "|LDD  #1"
            FCB  $0A
            FCC  "|STD  VC_INC0"
            FCB  $0A
            FCC  "|LDX  #@_PAL"
            FCB  $0A
            FCC  "|LDY  #VC_DATA0"
            FCB  $0A
            FCC  "|LDW  #512"
            FCB  $0A
            FCC  "|TFM  X+,Y"
            FCB  $0A
            FCC  "|LDA  #VC_CFG/$10000"
            FCB  $0A
            FCC  "|STA  VC_ADDR0"
            FCB  $0A
            FCC  "|LDX  #LAYER0"
            FCB  $0A
            FCC  "|STX  VC_ADDR0M"
            FCB  $0A
            FCC  "|LDX  #@_LAYERS"
            FCB  $0A
            FCC  "|LDW  #48"
            FCB  $0A
            FCC  "|TFM  X+,Y"
            FCB  $0A
            FCC  "|LDX  #DC_CTRL"
            FCB  $0A
            FCC  "|STX  VC_ADDR0M"
            FCB  $0A
            FCC  "|LDA  #@_SHOW"
            FCB  $0A
            FCC  "|STA  VC_DATA0"
            FCB  $0A
            FCC  "|RTS"
            FCB  $0A
            FCC  "; The card's layers, from the back: mode and map size, the map's place,"
            FCB  $0A
            FCC  "; the tiles' place, scrolling and the rest"
            FCB  $0A
            FCC  "@_LAYERS"
            FCB  $0A
            FCB  0
T_PRJA1     FCN  "/$10000,("
T_PRJA2     FCN  "/$100)&$FF,"
T_PRJA3     FCN  "&$FF"
T_PRJLREST  FCC  "|FDB  0,0,0"
            FCB  $0A
            FCC  "|FCB  0,0"
            FCB  $0A
            FCB  0
T_PRJPAL    FCC  "; The palette: 256 colors, RGB565"
            FCB  $0A
            FCC  "@_PAL"
            FCB  $0A
            FCB  0
;------------------------------------------------------------------------------
OUTMSG      FDB  T_EXPORTED ; what OUTCLOSE says when it is done
OHANDLE     FCB  0
OERR        FCB  0          ; a write failed: its error
OPTR        FDB  0          ; where the next character goes in IOBUF
OCOL        FCB  0          ; the column it is in
OCOUNT      FCB  0
ODIGIT      FCB  0
EXPN        FDB  0
PREVK       FCB  0          ; the project's places: the one before (V, T or M)
PREVD       FCB  0          ;   and its number
PLACEK      FCB  0
PLACED      FCB  0
ESTEM       FCB  0,0,0,0,0,0,0 ; the project module's name, 6 at most
OPFX        FCB  0,0,0,0,0,0,0,0,0,0 ; the labels' start
