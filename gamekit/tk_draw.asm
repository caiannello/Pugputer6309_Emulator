;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 game kit
;    FILE: tk_draw.asm
;
; TILEKIT's screen: the panel's parts (a bitmap drawn by the card's commands,
; with tiles put together in GK_SCRATCH and BLIT there), and the text rows. (The
; map on the left is the card's own tile layer: tk_map.asm.) INCLUDEd by
; tilekit.asm.
;------------------------------------------------------------------------------
; REDRAWALL: everything, in the editor's colors as they are now.
REDRAWALL   LDA  #VC_CFG/$10000 ; the backdrop
            LDX  #DC_BACK
            JSR  PORT0
            LDA  UI_BG
            STA  VC_DATA0
            JSR  MKPTR
            LDA  UI_BG          ; the panel
            LDX  #0
            LDY  #0
            LDW  #PANELW
            LDU  #480
            JSR  FRECTR
            JSR  DRAWTOOLS
            JSR  DRAWZOOM
            JSR  DRAWPAL
            JSR  DRAWSLID
            JSR  DRAWTSET
            JSR  DRAWTSLABEL
            JSR  DRAWTITLE
            JSR  DRAWSTATUS
            JSR  MAPSETUP       ; (the cover and the cell's frame in the colors)
            LDA  MODE           ; and the bottom row as it is
            CMPA #M_DIALOG
            BNE  REDRAWALL1
            JSR  SHOWDLG
            LBRA DRAWHELP
REDRAWALL1  CMPA #M_EDIT
            LBEQ DRAWHELP
            JMP  PRSHOWC
; DISPCOL: the color pixel value A shows in: 0 (see-through) as UI_BG; in a
; 16-color set, the value in COLOR's row. (Only A and B change.)
DISPCOL     TSTA
            BEQ  DISPCOL0
            LDB  BPP
            CMPB #8
            BEQ  DISPCOL9
            LDB  COLOR
            ANDB #$F0
            PSHS B
            ORA  ,S+
DISPCOL9    RTS
DISPCOL0    LDA  UI_BG
            RTS
; HOLLOW: a rectangle X, Y, W, U in UI_MID with UI_BG inside: color 0, which
; can't be shown (it shows through).
HOLLOW      LDA  UI_MID
            JSR  FRECTR
            LEAX 1,X
            LEAY 1,Y
            DECW
            DECW
            LEAU -2,U
            LDA  UI_BG
            JMP  FRECTR
;------------------------------------------------------------------------------
; The tools.
;------------------------------------------------------------------------------
DRAWTOOLS   CLRB
DRAWTOOLS1  PSHS B
            BSR  DRAWTOOL
            PULS B
            INCB
            CMPB #7
            BNE  DRAWTOOLS1
            RTS
; DRAWTOOL: button B: lit up if it is the tool in use.
DRAWTOOL    PSHS B
            LDA  #25
            MUL
            ADDD #1
            TFR  D,X
            LDY  #TOOLY
            LDW  #22
            LDU  #22
            LDA  UI_MID
            LDB  ,S
            CMPB TOOL
            BNE  DRAWTOOL1
            LDA  UI_HI
DRAWTOOL1   JSR  FRECTR
            PSHS X
            LDB  2,S            ; its icon
            LDA  #32
            MUL
            ADDD #ICONS
            TFR  D,X
            LDA  UI_BG
            JSR  MASK16
            PULS X
            LEAX 3,X
            LDY  #TOOLY+3
            LDA  #1
            JSR  BLIT16
            PULS B,PC
;------------------------------------------------------------------------------
; The magnified tile: each pixel a square, ZOOM-1 wide, on a grid of UI_MID.
;------------------------------------------------------------------------------
DRAWZOOM    LDA  UI_MID
            LDX  #ZOOMX-1
            LDY  #ZOOMY-1
            LDW  #130
            LDU  #130
            JSR  FRECTR
            LDD  #0
DRAWZOOM1   PSHS D
            BSR  DRAWZPIX
            PULS D
            ADDD #1
            CMPD TPIX
            BNE  DRAWZOOM1
            RTS
; DRAWZPIX: pixel D (0-255) of TILEBUF.
DRAWZPIX    TFR  D,X
            LDA  TILEBUF,X
            JSR  DISPCOL
            STA  DZCOL
            TFR  X,D
            TFR  B,A
            ANDA TSMASK
            STA  DZX            ; x
            LDA  TSHIFT
DRAWZPIX1   LSRB
            DECA
            BNE  DRAWZPIX1      ; B = y
            LDA  ZOOM
            MUL
            ADDD #ZOOMY
            TFR  D,Y
            LDB  DZX
            LDA  ZOOM
            MUL
            ADDD #ZOOMX
            TFR  D,X
            LDB  ZOOM
            DECB
            CLRA
            TFR  D,W
            TFR  D,U
            LDA  DZCOL
            JMP  FRECTR
;------------------------------------------------------------------------------
; The palette: 16 rows of 16 colors, the one in use framed (and its row marked,
; in a 16-color set).
;------------------------------------------------------------------------------
DRAWPAL     LDA  UI_BG
            LDX  #0
            LDY  #PALY-2
            LDW  #PANELW
            LDU  #132
            JSR  FRECTR
            CLRB
DRAWPAL1    PSHS B
            BSR  PALCELL
            LDW  #9
            LDU  #7
            LDA  ,S
            BNE  DRAWPAL2
            JSR  HOLLOW
            BRA  DRAWPAL3
DRAWPAL2    JSR  FRECTR
DRAWPAL3    PULS B
            INCB
            BNE  DRAWPAL1
            LDA  UI_HI
            BRA  PALFRAME
; PALCELL: X, Y = where color B's square is.
PALCELL     PSHS B
            ANDB #$0F
            LDA  #10
            MUL
            ADDD #PALX
            TFR  D,X
            PULS B
            LSRB
            LSRB
            LSRB
            LSRB
            LDA  #8
            MUL
            ADDD #PALY
            TFR  D,Y
            RTS
; PALFRAME: in color A, the frame round COLOR's square, and its row's mark.
PALFRAME    PSHS A
            LDB  COLOR
            BSR  PALCELL
            LEAX -1,X
            LEAY -1,Y
            LDW  #11
            LDU  #9
            LDA  ,S
            JSR  ORECTR
            LDA  BPP
            CMPA #8
            BEQ  PALFRAME9
            LDX  #2
            LEAY 1,Y
            LDW  #4
            LDU  #7
            LDA  ,S
            JSR  FRECTR
PALFRAME9   PULS A,PC
; DRAWSLID: red, green and blue of COLOR as bars, and the color itself.
DRAWSLID    LDA  UI_BG
            LDX  #0
            LDY  #SLY-2
            LDW  #PANELW
            LDU  #16
            JSR  FRECTR
            LDB  COLOR
            JSR  RGBOF
            LDX  #SLMAX
            BSR  SLBAR
            LDX  #SLMAX+4
            BSR  SLBAR
            LDX  #SLMAX+8
            BSR  SLBAR
            LDX  #SWX
            LDY  #SLY-1
            LDW  #14
            LDU  #14
            LDA  COLOR
            LBEQ HOLLOW
            JMP  FRECTR
; SLBAR: the bar X points at in SLMAX: its track, and its value as far along.
SLBAR       STX  SLP
            LDB  1,X
            INCB
            CLRA
            TFR  D,W            ; (as long as its top value + 1)
            LDB  ,X
            TFR  D,X
            LDY  #SLY
            LDU  #12
            LDA  UI_MID
            JSR  FRECTR
            LDX  SLP
            LDB  [2,X]
            INCB
            CLRA
            TFR  D,W
            LDB  ,X
            TFR  D,X
            LDY  #SLY+3
            LDU  #6
            LDA  UI_FG
            JMP  FRECTR
;------------------------------------------------------------------------------
; The tile set: 6 rows of 10 from TSTOP, each tile 16x16 (8x8 ones doubled),
; the one being edited framed.
;------------------------------------------------------------------------------
DRAWTSET    LDA  UI_BG
            LDX  #0
            LDY  #TSY-2
            LDW  #PANELW
            LDU  #TSVIS/10*17+2
            JSR  FRECTR
            LDD  TSTOP
DRAWTSET1   CMPD NTILES
            BHS  DRAWTSET2
            PSHS D
            BSR  THUMB
            LDX  ,S             ; (each tile outlined)
            LDA  UI_MID
            BSR  TSBOX
            PULS D
            ADDD #1
            PSHS D
            SUBD TSTOP
            CMPD #TSVIS
            PULS D
            BLO  DRAWTSET1
DRAWTSET2   LDA  UI_HI
            BRA  TSFRAME
; TSPOS: tile D in sight? Carry clear and X, Y its place if so; carry set if not.
TSPOS       SUBD TSTOP
            BLO  TSPOS9
            CMPD #TSVIS
            BHS  TSPOS8
            DIVD #10            ; B = row, A = column
            PSHS A
            LDA  #17
            MUL
            ADDD #TSY
            TFR  D,Y
            PULS B
            LDA  #17
            MUL
            ADDD #TSX
            TFR  D,X
            ANDCC #$FE
            RTS
TSPOS8      ORCC #$01
TSPOS9      RTS
; TSFRAME: in color A, the frame round tile TILE (if it is in sight); TSBOX:
; round tile X.
TSFRAME     LDX  TILE
TSBOX       PSHS A
            TFR  X,D
            BSR  TSPOS
            BCS  TSFRAME9
            LEAX -1,X
            LEAY -1,Y
            LDW  #18
            LDU  #18
            LDA  ,S
            JSR  ORECTR
TSFRAME9    PULS A,PC
; THUMB: tile D's picture in the set (if it is in sight), from the card.
THUMB       PSHS D
            BSR  TSPOS
            PULS D
            BCS  THUMB9
            STX  THX
            STY  THY
            JSR  TILEADDR
            JSR  PORT1
            LDY  #THUMBBUF
            JSR  UNPACK
            JSR  WAITCMD        ; (the last BLIT may still be reading the scratch)
            LDA  #GK_SCRATCH/$10000
            LDX  #GK_SCRATCH&$FFFF
            JSR  PORT0
            LDX  #THUMBBUF
            LDA  TSIZE
            CMPA #8
            BEQ  THUMB8
            LDW  #256
THUMB1      LDA  ,X+
            JSR  DISPCOL
            STA  VC_DATA0
            DECW
            BNE  THUMB1
            BRA  THUMB2
THUMB8      LDE  #8             ; 8x8: each pixel 2x2
THUMB81     LDF  #8
THUMB82     LDA  ,X+
            JSR  DISPCOL
            STA  VC_DATA0
            STA  VC_DATA0
            DECF
            BNE  THUMB82
            LEAX -8,X           ; (the row again)
            LDF  #8
THUMB83     LDA  ,X+
            JSR  DISPCOL
            STA  VC_DATA0
            STA  VC_DATA0
            DECF
            BNE  THUMB83
            DECE
            BNE  THUMB81
THUMB2      LDX  THX
            LDY  THY
            CLRA
            JMP  BLIT16
THUMB9      RTS
;------------------------------------------------------------------------------
; Text.
;------------------------------------------------------------------------------
; PANELTEXT: text in UI_FG over the panel (see-through behind it); BARTEXT:
; on UI_BG, for the rows along the bottom.
PANELTEXT   LDA  UI_FG
            STA  TXFG
            CLR  TXBG
            RTS
BARTEXT     LDA  UI_FG
            STA  TXFG
            LDA  UI_BG
            STA  TXBG
            RTS
; DRAWTITLE: the panel's top row, the tile set's file, and its bottom row, the
; map's: each with * if changed since saved.
DRAWTITLE   BSR  PANELTEXT
            LDA  #58
            CLRB
            JSR  TXAT
            LDX  #T_TSNAME
            JSR  TXSTR
            LDX  #FILENAME
            LDA  MODIFIED
            BSR  DRAWNAME
            LDA  #58
            LDB  #MAPROW
            JSR  TXAT
            LDX  #T_MAPNAME
            JSR  TXSTR
            LDX  #MAPNAME
            LDA  MAPMOD
; DRAWNAME: the name at X ("(NEW)" if none), then * if A isn't 0, in 15 places.
DRAWNAME    STA  NAMEMOD
            TST  ,X
            BNE  DRAWNAME1
            LDX  #T_NONAME
DRAWNAME1   LDB  #12            ; at most 12 characters ...
DRAWNAME2   LDA  ,X+
            BEQ  DRAWNAME3
            JSR  TXCH
            DECB
            BNE  DRAWNAME2
DRAWNAME3   LDA  #$20           ; ... * if it has changed, and the rest blank
            TST  NAMEMOD
            BEQ  DRAWNAME4
            LDA  #'*
DRAWNAME4   JSR  TXCH
            INCB
            INCB
            JMP  TXSPC
; DRAWTSLABEL: above the set: how many tiles, and the NEW and DUP buttons.
DRAWTSLABEL BSR  PANELTEXT
            LDA  #58
            LDB  #TSROW
            JSR  TXAT
            LDA  #$20
            JSR  TXCH
            LDD  NTILES
            JSR  TXDEC4
            LDX  #T_TILES
            JSR  TXSTR
            LDA  UI_MID
            STA  TXBG
            LDX  #T_NEWBTN      ; (columns 69-72: HITTEST knows)
            JSR  TXSTR
            CLR  TXBG
            LDA  #$20
            JSR  TXCH
            LDA  UI_MID
            STA  TXBG
            LDX  #T_DUPBTN      ; (columns 74-77)
            JSR  TXSTR
            CLR  TXBG
            LDB  #2
            JMP  TXSPC
; DRAWSTATUS: the bottom row: the tile, how it is put down, the color, the map
; and the cell under the mouse, the kind of set.
DRAWSTATUS  JSR  BARTEXT
            CLRA
            LDB  #STATROW
            JSR  TXAT
            LDX  #T_TILE
            JSR  TXSTR
            LDD  TILE
            JSR  TXDEC4
            LDA  #'/
            JSR  TXCH
            LDD  NTILES
            JSR  TXDEC4
            LDX  #T_FLIP
            JSR  TXSTR
            LDA  #'-
            LDB  FLIPS
            BITB #$04
            BEQ  DRAWSTAT1
            LDA  #'H
DRAWSTAT1   JSR  TXCH
            LDA  #'-
            LDB  FLIPS
            BITB #$08
            BEQ  DRAWSTAT2
            LDA  #'V
DRAWSTAT2   JSR  TXCH
            LDX  #T_COLOR
            JSR  TXSTR
            CLRA
            LDB  COLOR
            JSR  TXDEC3
            LDB  COLOR
            JSR  RGBOF
            LDX  #T_R
            JSR  TXSTR
            LDB  GK_R
            JSR  TXDEC2
            LDX  #T_G
            JSR  TXSTR
            LDB  GK_G
            JSR  TXDEC2
            LDX  #T_B
            JSR  TXSTR
            LDB  GK_B
            JSR  TXDEC2
            LDX  #T_MAP
            JSR  TXSTR
            LDD  MAPW
            JSR  TXDEC3
            LDA  #'x
            JSR  TXCH
            LDD  MAPH
            JSR  TXDEC3
            LDX  #T_AT
            JSR  TXSTR
            LDA  HOVX
            CMPA #$FF
            BNE  DRAWSTAT3
            LDX  #T_NOWHERE
            JSR  TXSTR
            BRA  DRAWSTAT4
DRAWSTAT3   CLRA
            LDB  HOVX
            JSR  TXDEC3
            LDA  #',
            JSR  TXCH
            CLRA
            LDB  HOVY
            JSR  TXDEC3
DRAWSTAT4   LDX  #T_8X8
            LDA  TSIZE
            CMPA #8
            BEQ  DRAWSTAT5
            LDX  #T_16X16
DRAWSTAT5   JSR  TXSTR
            LDX  #T_16C
            LDA  BPP
            CMPA #8
            BNE  DRAWSTAT6
            LDX  #T_256C
DRAWSTAT6   JSR  TXSTR
            LDB  #2             ; (to the end of the row)
            JMP  TXSPC
; DRAWHELP: the row above it: the keys. MESSAGE: X instead, for a while.
DRAWHELP    CLR  MSGTIME
            LDX  #T_HELP
HELPLINE    PSHS X
            JSR  BARTEXT
            CLRA
            LDB  #HELPROW
            JSR  TXAT
            PULS X
            LDB  #58
            JMP  TXFIELD
MESSAGE     BSR  HELPLINE
            LDA  #180           ; (3 seconds)
            STA  MSGTIME
            RTS
;------------------------------------------------------------------------------
; The tools' icons: 16x16, a bit a pixel.
;------------------------------------------------------------------------------
ICONS       FDB  $000C,$001E,$003F,$007E,$00FC,$01F8,$03F0,$07E0 ; pen
            FDB  $0FC0,$1F80,$1F00,$3E00,$3C00,$7000,$6000,$0000
            FDB  $0003,$0006,$000C,$0018,$0030,$0060,$00C0,$0180 ; line
            FDB  $0300,$0600,$0C00,$1800,$3000,$6000,$C000,$0000
            FDB  $0000,$07E0,$0810,$1008,$3FFC,$3FFC,$1FF8,$1FF8 ; fill
            FDB  $0FF0,$0FF0,$07E0,$07E0,$0000,$0006,$0006,$0000
            FDB  $000E,$001F,$001F,$007E,$003C,$0058,$0088,$0110 ; pick
            FDB  $0220,$0440,$0880,$1100,$2200,$4400,$7800,$8000
            FDB  $0000,$0000,$0000,$3FFC,$20FC,$20FC,$20FC,$20FC ; eraser
            FDB  $20FC,$20FC,$3FFC,$0000,$0000,$0000,$0000,$0000
            FDB  $0000,$7FFE,$4002,$500A,$4812,$4422,$4242,$4182 ; clear
            FDB  $4182,$4242,$4422,$4812,$500A,$4002,$7FFE,$0000
            FDB  $0000,$0000,$0800,$1800,$3FF0,$7FF8,$3FFC,$180E ; undo
            FDB  $0806,$0006,$0006,$000E,$001C,$03F8,$03F0,$0000
;------------------------------------------------------------------------------
; Words.
;------------------------------------------------------------------------------
T_TSNAME    FCN  " TILES "
T_MAPNAME   FCN  " MAP   "
T_NONAME    FCN  "(NEW)"
T_TILES     FCN  " TILES"
T_NEWBTN    FCN  " NEW"
T_DUPBTN    FCN  " DUP"
T_TILE      FCN  " TILE "
T_FLIP      FCN  " FLIP "
T_MAP       FCN  " MAP "
T_AT        FCN  " AT "
T_NOWHERE   FCN  "---,---"
T_8X8       FCN  " 8x8"
T_16X16     FCN  " 16x16"
T_16C       FCN  " 16 "
T_256C      FCN  " 256"
T_LORES     FCN  "  320x240"
T_HIRES     FCN  "  640x480"
T_COLOR     FCN  " COLOR "
T_R         FCN  " R"
T_G         FCN  " G"
T_B         FCN  " B"
T_HELP      FCN  "P L F K E U  ,. TILE  H V FLIP  ^S SAVE  ^E EXPORT  ESC"
T_NOUNDO    FCN  "NOTHING TO UNDO"
T_FULL      FCN  "THE TILE SET IS FULL"
T_FILLFULL  FCN  "THE FILL STOPPED: TOO INTRICATE A SHAPE (U UNDOES IT)"
;------------------------------------------------------------------------------
DZCOL       FCB  0
DZX         FCB  0
SLP         FDB  0
THX         FDB  0
THY         FDB  0
NAMEMOD     FCB  0
