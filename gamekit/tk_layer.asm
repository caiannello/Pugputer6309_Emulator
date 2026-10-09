;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 game kit
;    FILE: tk_layer.asm
;
; TILEKIT's three layers: the card's three tile layers, each with a map, and a
; tile set of its own or another layer's (the same kind of tiles: sharing
; saves room). The layer being edited is worked on through the program's
; variables (TSIZE ... MAPNAME, TROW); the others are kept in records:
;
;   a tile set's (TSRECS, by its slot -- slot n is in layer n's room):
;     TS_TSIZE TS_BPP TS_NTILES TS_MOD TS_TILE TS_TSTOP TS_NAME
;   a layer's (LRECS): LR_SET (its tile set's slot) LR_HIRES LR_WC LR_HC
;     LR_SHOW LR_MOD LR_NAME (its map's file)
;
; Video memory: each layer has SLICE bytes from (layer x SLICE), its tile set's
; slot at the start (if it has one of its own) and its map at the end.
; ORDER: the layers from the back (the card's layer 0) to the front.
; INCLUDEd by tilekit.asm.
;------------------------------------------------------------------------------
SLICE       equ  $C000      ; each layer's room: 48KB
TS_TSIZE    equ  0
TS_BPP      equ  1
TS_NTILES   equ  2
TS_MOD      equ  4
TS_TILE     equ  5
TS_TSTOP    equ  7
TS_NAME     equ  9
TSRSIZE     equ  9+PR_MAX+1
LR_SET      equ  0
LR_HIRES    equ  1
LR_WC       equ  2
LR_HC       equ  3
LR_SHOW     equ  4
LR_MOD      equ  5
LR_NAME     equ  6
LRSIZE      equ  6+PR_MAX+1
LAYBARCOL   equ  66         ; the layer bar's buttons: 3 columns each, from here
;------------------------------------------------------------------------------
; Addresses.
;------------------------------------------------------------------------------
; TBASEAX, MBASEAX: A:X = the tile set's, the map's start in video memory.
TBASEAX     LDA  TBASE
            LDX  TBASE+1
            RTS
MBASEAX     LDA  MBASE
            LDX  MBASE+1
            RTS
; MBASECMD: the map's start, 3 bytes, to the command port.
MBASECMD    LDA  MBASE
            STA  VC_CMD
            LDD  MBASE+1
            JMP  CMDD
; TSREC: X = slot B's record. LREC: X = layer B's. (B kept.)
TSREC       PSHS B
            LDA  #TSRSIZE
            MUL
            ADDD #TSRECS
            TFR  D,X
            PULS B,PC
LREC        PSHS B
            LDA  #LRSIZE
            MUL
            ADDD #LRECS
            TFR  D,X
            PULS B,PC
; SLICEOF: D = layer B's room's start, / 256 (its bits 23-8). (B lost.)
SLICEOF     LDA  #SLICE/256
            MUL
            RTS
;------------------------------------------------------------------------------
; The layer being edited, to and from the records.
;------------------------------------------------------------------------------
; STOREREC: the variables into the records.
STOREREC    LDB  CURSET
            BSR  TSREC
            LDA  TSIZE
            STA  TS_TSIZE,X
            LDA  BPP
            STA  TS_BPP,X
            LDD  NTILES
            STD  TS_NTILES,X
            LDA  MODIFIED
            STA  TS_MOD,X
            LDD  TILE
            STD  TS_TILE,X
            LDD  TSTOP
            STD  TS_TSTOP,X
            LEAY TS_NAME,X
            LDX  #FILENAME
            JSR  STRCPY
            LDB  CURL
            BSR  LREC
            LDA  HIRES
            STA  LR_HIRES,X
            LDA  MAPWC
            STA  LR_WC,X
            LDA  MAPHC
            STA  LR_HC,X
            LDA  MAPMOD
            STA  LR_MOD,X
            LEAY LR_NAME,X
            LDX  #MAPNAME
            JMP  STRCPY
; LOADREC: the variables from the records of layer CURL (and its tile set's).
LOADREC     LDB  CURL
            BSR  LREC
            LDA  LR_SET,X
            STA  CURSET
            LDA  LR_HIRES,X
            STA  HIRES
            LDA  LR_WC,X
            STA  MAPWC
            LDA  LR_HC,X
            STA  MAPHC
            LDA  LR_MOD,X
            STA  MAPMOD
            LEAX LR_NAME,X
            LDY  #MAPNAME
            JSR  STRCPY
            LDB  CURSET
            JSR  TSREC
            LDA  TS_TSIZE,X
            STA  TSIZE
            LDA  TS_BPP,X
            STA  BPP
            LDD  TS_NTILES,X
            STD  NTILES
            LDA  TS_MOD,X
            STA  MODIFIED
            LDD  TS_TILE,X
            STD  TILE
            LDD  TS_TSTOP,X
            STD  TSTOP
            LEAX TS_NAME,X
            LDY  #FILENAME
            JSR  STRCPY
            LDB  CURSET         ; TBASE: its slot's room
            JSR  SLICEOF
            STD  TBASE
            CLR  TBASE+2
            RTS
; TROWOUT, TROWIN: TROW to and from the tile set's own copy.
TROWOUT     BSR  TROWAT
            LDX  #TROW
            TFM  X+,Y+
            RTS
TROWIN      BSR  TROWAT
            EXG  X,Y
            LDY  #TROW
            TFM  X+,Y+
            RTS
TROWAT      LDA  CURSET         ; Y = TROWS + slot * 1024, W = 1024
            CLRB
            LSLA
            LSLA
            ADDD #TROWS
            TFR  D,Y
            LDW  #1024
            RTS
; SELLAYER: layer B to edit.
SELLAYER    CMPB CURL
            BEQ  SELLAYER9
            PSHS B
            JSR  FLUSHTILE
            LDA  UI_BG          ; (the color's frame off: it may move)
            JSR  PALFRAME
            JSR  STOREREC
            JSR  TROWOUT
            PULS B
            STB  CURL
            JSR  LOADREC
            JSR  TROWIN
            JSR  SETPROJ
            JSR  LOADTILE
            LDA  BPP            ; (16 colors: the row its tile was last in)
            CMPA #8
            BEQ  SELLAYER1
            LDX  #TROW
            LDD  TILE
            LDA  D,X
            LSLA
            LSLA
            LSLA
            LSLA
            STA  OLDROW
            LDA  COLOR
            ANDA #$0F
            ORA  OLDROW
            STA  COLOR
SELLAYER1   LDA  UI_HI          ; what changes with the layer: its tiles, its map
            JSR  PALFRAME
            JSR  DRAWSLID
            JSR  MAPSETUP
            JSR  DRAWZOOM
            JSR  DRAWTSET
            JSR  DRAWTSLABEL
            JSR  DRAWTITLE
            LDA  #1
            STA  STATDIRTY
SELLAYER9   RTS
;------------------------------------------------------------------------------
; The card's layers, from the records.
;------------------------------------------------------------------------------
; LAYERS: the card's three tile layers as ORDER and the records have them,
; scrolled to SCRX, SCRY (the screen's pixels), and DC_CTRL: the ones shown,
; and the sprites.
LAYERS      JSR  STOREREC
            LDA  #VC_CFG/$10000
            LDX  #LAYER0
            JSR  PORT0
            LDA  #$08           ; (the sprites)
            STA  LDCBITS
            LDA  #1
            STA  LBIT
            CLRB                ; the card's layer
LAYERS1     PSHS B
            LDX  #ORDER
            LDB  B,X            ; the layer shown there
            STB  LTHIS
            JSR  LREC
            STX  LRP
            LDB  LR_SET,X
            JSR  TSREC
            STX  TSP
            LDA  #LM_TILE+LM_4BPP ; its mode
            LDB  TS_BPP,X
            CMPB #8
            BNE  LAYERS2
            LDA  #LM_TILE+LM_8BPP
LAYERS2     LDB  TS_TSIZE,X
            CMPB #16
            BNE  LAYERS3
            ORA  #LM_BIG
LAYERS3     LDX  LRP
            TST  LR_HIRES,X
            BEQ  LAYERS4
            ORA  #LM_HIRES
LAYERS4     STA  VC_DATA0
            LDA  LR_HC,X        ; its map's size
            LSLA
            LSLA
            ORA  LR_WC,X
            STA  VC_DATA0
            JSR  LMAPBASE       ; where its map is
            STA  VC_DATA0
            STB  VC_DATA0
            CLRA
            STA  VC_DATA0
            LDX  LRP            ; where its tiles are
            LDB  LR_SET,X
            JSR  SLICEOF
            STA  VC_DATA0
            STB  VC_DATA0
            CLRA
            STA  VC_DATA0
            LDX  LRP            ; scrolled: the screen's pixels, halved at 320x240
            LDD  SCRX
            TST  LR_HIRES,X
            BNE  LAYERS5
            LSRD
LAYERS5     STA  VC_DATA0
            STB  VC_DATA0
            LDD  SCRY
            TST  LR_HIRES,X
            BNE  LAYERS6
            LSRD
LAYERS6     STA  VC_DATA0
            STB  VC_DATA0
            CLRA                ; (stride, palette offset, spare: bitmaps')
            LDB  #4
LAYERS7     STA  VC_DATA0
            DECB
            BNE  LAYERS7
            TST  LR_SHOW,X      ; shown?
            BEQ  LAYERS8
            LDA  LDCBITS
            ORA  LBIT
            STA  LDCBITS
LAYERS8     LSL  LBIT
            PULS B
            INCB
            CMPB #3
            LBNE LAYERS1
            LDA  #VC_CFG/$10000
            LDX  #DC_CTRL
            JSR  PORT0
            LDA  LDCBITS
            STA  VC_DATA0
            RTS
; LMAPBYTES: D = the bytes of the map of the layer whose record is at X.
LMAPBYTES   LDD  #2048
            PSHS X
            LDF  LR_WC,X
            ADDF LR_HC,X
            BEQ  LMAPBYTES9
LMAPBYTES1  LSLD
            DECF
            BNE  LMAPBYTES1
LMAPBYTES9  PULS X,PC
; LMAPBASE: D = where (bits 23-8) the map of layer LTHIS (record at LRP) is:
; the end of its room less its bytes.
LMAPBASE    LDX  LRP
            BSR  LMAPBYTES
            TFR  A,B            ; (its bytes / 256)
            CLRA
            PSHS D
            LDB  LTHIS
            INCB
            JSR  SLICEOF
            SUBD ,S++
            RTS
; LEXTENT: D = how far layer B reaches across the screen (W: down), in the
; screen's pixels.
LEXTENT     JSR  LREC
            STX  LRP
            LDB  LR_SET,X
            JSR  TSREC
            LDA  TS_TSIZE,X     ; the tile size's shift: 3 or 4, +1 at 320x240
            LDB  #3
            CMPA #16
            BNE  LEXTENT1
            INCB
LEXTENT1    LDX  LRP
            TST  LR_HIRES,X
            BNE  LEXTENT2
            INCB
LEXTENT2    STB  LTHIS
            LDD  #32            ; down: 32 << HC << that
            LDF  LR_HC,X
            ADDF LTHIS
LEXTENT3    LSLD
            DECF
            BNE  LEXTENT3
            TFR  D,W
            LDD  #32            ; across
            LDF  LR_WC,X
            ADDF LTHIS
LEXTENT4    LSLD
            DECF
            BNE  LEXTENT4
            RTS
; CAPACITY: MAXT for the tile set being edited: what fits in its slot's room
; beside that layer's map (at most 1024).
CAPACITY    JSR  STOREREC       ; (the records as the variables are)
            LDB  CURSET
            JSR  LREC
            BSR  LMAPBYTES
            PSHS D
            LDD  #SLICE
            SUBD ,S++
            LDF  TBSHIFT
CAPACITY1   LSRD
            DECF
            BNE  CAPACITY1
            CMPD #1024
            BLS  CAPACITY2
            LDD  #1024
CAPACITY2   STD  MAXT
            RTS
; NEWLAYERS: a new set's layers: layer 1 as the variables are, layers 2 and 3
; the same size, with its tile set, shown; in order 1 2 3 from the back.
NEWLAYERS   CLR  CURL
            CLR  CURSET
            LDX  #LRECS         ; every record 0
            LDW  #3*LRSIZE+3*TSRSIZE
NEWLAYERS1  CLR  ,X+
            DECW
            BNE  NEWLAYERS1
            LDX  #TROWS
            LDW  #3*1024
NEWLAYERS2  CLR  ,X+
            DECW
            BNE  NEWLAYERS2
            LDB  #2
NEWLAYERS3  JSR  LREC           ; each: shown, as layer 1 is
            LDA  #1
            STA  LR_SHOW,X
            LDA  HIRES
            STA  LR_HIRES,X
            LDA  MAPWC
            STA  LR_WC,X
            LDA  MAPHC
            STA  LR_HC,X
            JSR  TSREC          ; (an empty slot: valid, if unused)
            LDA  #8
            STA  TS_TSIZE,X
            LDA  #4
            STA  TS_BPP,X
            DECB
            BPL  NEWLAYERS3
            CLR  ORDER
            LDD  #$0102
            STD  ORDER+1
            CLR  UNDOLAY
            JMP  STOREREC
;------------------------------------------------------------------------------
; The layer bar: the panel's top row -- the layers from the back, the one being
; edited lit up, the hidden ones dim. Click: edit it; right click: show or
; hide it. Keys: 1 2 3 edit, Shift with them show or hide, [ ] move the one
; being edited back or forward.
;------------------------------------------------------------------------------
DRAWLAYERS  JSR  PANELTEXT
            LDA  #58
            CLRB
            JSR  TXAT
            LDX  #T_LAYERS
            JSR  TXSTR
            CLRB
DRAWLAY1    PSHS B
            LDX  #ORDER
            LDB  B,X
            STB  LTHIS
            JSR  LREC
            LDA  UI_MID         ; shown
            LDB  UI_FG
            TST  LR_SHOW,X
            BNE  DRAWLAY2
            LDA  UI_BG          ; hidden
            LDB  UI_MID
DRAWLAY2    PSHS A
            LDA  LTHIS
            CMPA CURL
            PULS A
            BNE  DRAWLAY3
            LDA  UI_HI          ; being edited
            LDB  UI_BG
DRAWLAY3    STA  TXBG
            STB  TXFG
            LDA  #$20
            JSR  TXCH
            LDA  LTHIS
            ADDA #'1
            JSR  TXCH
            LDA  #$20
            JSR  TXCH
            PULS B
            INCB
            CMPB #3
            BNE  DRAWLAY1
            JSR  PANELTEXT      ; and ..., the layer's questions
            LDA  #$20
            JSR  TXCH
            LDA  UI_MID
            STA  TXBG
            LDX  #T_DOTS
            JSR  TXSTR
            JSR  PANELTEXT
            LDB  #2
            JMP  TXSPC
; LAYERCLICK: the button at place B in the bar: edit that layer, or (the right
; button) show or hide it.
LAYERCLICK  CMPB #3            ; (the ...)
            LBEQ LAYERDLG
            LDX  #ORDER
            LDB  B,X
            LDA  PRESSED
            BITA #VC_MB_RIGHT
            BNE  TOGGLESHOW
            JMP  SELLAYER
; TOGGLESHOW: layer B shown, or not.
TOGGLESHOW  JSR  LREC
            LDA  LR_SHOW,X
            EORA #1
            STA  LR_SHOW,X
            JSR  LAYERS
            LBRA DRAWLAYERS
; LAYERKEY: 1 2 3 (A the usage code): edit that layer, or with Shift show or
; hide it. Carry set if A isn't one of them.
LAYERKEY    SUBA #$1E           ; (the usage code of 1)
            BLO  LAYERKEY8
            CMPA #3
            BHS  LAYERKEY8
            TFR  A,B
            LDA  KEYMODS
            BITA #VC_MOD_SHF
            BEQ  LAYERKEY1
            BSR  TOGGLESHOW
            ANDCC #$FE
            RTS
LAYERKEY1   JSR  SELLAYER
            ANDCC #$FE
            RTS
LAYERKEY8   ORCC #$01
            RTS
; LAYERBACK, LAYERFWD: the layer being edited a place further back, or forward.
LAYERBACK   BSR  LAYERPOS
            BEQ  LAYERMOVE9     ; (at the back already)
            LEAY -1,X
            BRA  LAYERMOVE
LAYERFWD    BSR  LAYERPOS
            CMPB #2
            BEQ  LAYERMOVE9     ; (at the front already)
            LEAY 1,X
LAYERMOVE   LDA  ,X             ; (swapped with its neighbor)
            LDB  ,Y
            STB  ,X
            STA  ,Y
            JSR  LAYERS
            JSR  DRAWLAYERS
            LDA  #1
            STA  STATDIRTY
LAYERMOVE9  RTS
; LAYERPOS: X = where CURL is in ORDER, B its place (Z set if 0).
LAYERPOS    LDX  #ORDER
            CLRB
LAYERPOS1   LDA  ,X
            CMPA CURL
            BEQ  LAYERPOS9
            LEAX 1,X
            INCB
            BRA  LAYERPOS1
LAYERPOS9   TSTB
            RTS
;------------------------------------------------------------------------------
T_LAYERS    FCN  " LAYERS "
T_DOTS      FCN  "..."
CURL        FCB  0          ; the layer being edited (0-2)
CURSET      FCB  0          ; its tile set's slot
ORDER       FCB  0,1,2      ; the layers, from the back
TBASE       FCB  0,0,0      ; where its tile set is in video memory
MBASE       FCB  0,0,0      ; and its map
UNDOLAY     FCB  0
LDCBITS     FCB  0
LBIT        FCB  0
LTHIS       FCB  0
LRP         FDB  0
TSP         FDB  0
