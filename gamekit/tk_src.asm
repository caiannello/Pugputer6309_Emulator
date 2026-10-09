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
; EXPORTCMD: ask for the tile set's module's name, then the map's (Esc skips one).
EXPORTCMD   LDX  #FILENAME      ; the set's: its file's name, .ASM
            LDY  #T_DEFSET
            JSR  ASMNAME
            LDX  #T_EXPSET
            LDY  #EXPNAME
            LDU  #T_EXTASM
            STU  PREXT
            LDU  #EXPMAPQ       ; (Esc: on to the map)
            STU  PRSKIP
            LDU  #DOEXPSET
            JMP  ASKNAME
DOEXPSET    JSR  EXPSET
            BCC  EXPMAPQ
            RTS                 ; (it failed: said so)
EXPMAPQ     LDX  #MAPNAME       ; the map's
            LDY  #T_DEFMAP
            JSR  ASMNAME
            LDX  #T_EXPMAP
            LDY  #EXPNAME
            LDU  #T_EXTASM
            STU  PREXT
            LDU  #0             ; (Esc: done)
            STU  PRSKIP
            LDU  #EXPMAP
            JMP  ASKNAME
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
            LDX  #T_EXPORTED
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
T_EXPSET    FCN  "EXPORT THE TILE SET AS: "
T_EXPMAP    FCN  "EXPORT THE MAP AS: "
T_EXPORTED  FCN  "EXPORTED"
T_EXTASM    FCN  ".ASM"
T_DEFSET    FCN  "TILES"
T_DEFMAP    FCN  "MAP"
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
;------------------------------------------------------------------------------
OHANDLE     FCB  0
OERR        FCB  0          ; a write failed: its error
OPTR        FDB  0          ; where the next character goes in IOBUF
OCOL        FCB  0          ; the column it is in
OCOUNT      FCB  0
ODIGIT      FCB  0
EXPN        FDB  0
OPFX        FCB  0,0,0,0,0,0,0,0,0,0 ; the labels' start
