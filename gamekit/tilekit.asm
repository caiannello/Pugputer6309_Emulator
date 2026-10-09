;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 game kit
;    FILE: tilekit.asm
;
; TILEKIT.COM: a tile set and tile map editor for the video card, worked with
; the mouse and the keyboard of the card (in the emulator, the video window's):
;
;   TILEKIT [file]      a tile set (.TLS, the default) or a map (.MAP) to open
;
; The screen, 640x480:
;
;   left     the map, as the card's tile layer shows it in a game (at 320x240
;            or 640x480, as the set is made for), the cell under the mouse
;            framed; a tile being drawn shows wherever it is in the map
;   right    the tools: pen, line, fill, pick, eraser, clear and undo -- on
;            the map's cells or the tile's pixels, whichever the mouse is on;
;            the tile, magnified, to draw in; the palette, and red, green and
;            blue for the color picked in it; the tile set
;   bottom   the keys, and what is being edited
;
; A tile set is 8x8 or 16x16 tiles of 16 colors (4 bits a pixel, in any one of
; the palette's 16 rows -- the row is chosen where a tile is placed) or of 256
; (8 bits), for 320x240 or 640x480, as chosen when it is made. Its file (.TLS)
; holds that, the palette and the tiles, as the card holds them:
;
;   0  "PTS1"
;   4  the tile size (8 or 16), bits a pixel (4 or 8), flags (bit 0: 640x480), 0
;   8  how many tiles (2 bytes, high first), then 6 bytes of 0
;  16  the palette: 256 colors, RGB565, 2 bytes each, high byte first
; 528  the tiles, one after another: rows of pixels, packed from the high bits
;
; A map is 32 to 256 cells across and down (16384 at most), each the card's
; map entry: the tile (bits 0-9), flipped across (10), down (11), the palette
; row (12-15). Its file (.MAP) names its tile set, so maps can share one:
;
;   0  "PTM1"
;   4  its width, then height, in cells (2 bytes each, high first)
;   8  the tile set's file name (40 bytes, 0 after it)
;  48  the cells, a row at a time, as the card holds them (2 bytes, high first)
;
; The keys: P L F K E the tools, ^Z (or U) undo, C clear, N a new tile, D a
; copy of this one, , and . another tile, H and V flip what is put on the map,
; + and - (PgUp, PgDn) another color (row), the arrows (Home) scroll the map,
; ^S save, ^A save as, ^E export as assembly source, ^O open, ^N new, Esc quit.
;------------------------------------------------------------------------------
            INCLUDE "defines.d"
            INCLUDE "vidcard.d"

TK_BASE     equ  $4000
TK_STACK    equ  $EF00

; Video memory.
                            ; $000000-$023FFF: the three layers' rooms (tk_layer.asm)
PCOL0       equ  $024000    ; the panel (a surface: gk_ui.asm): 4 columns, 64, 64,
PCOL1       equ  $02B800    ;   32 and 16 wide, 480 high
PCOL2       equ  $033000
PCOL3       equ  $036C00
SCOL        equ  $038A00    ; the status rows: 7 columns of 64x32, one of 16x32
CURIMG      equ  $03C400    ; sprite 1's image: the frame round a cell, up to 32x32
                            ; ($03C800-$03C9FF the pointer and scratch: gk_ui.asm;
                            ; $03CC00 the sprite table; $03F000 the card's font)
PSUNDO      equ  $800000    ; (the PSRAM) the map's undo steps, 32KB each

VIEWW       equ  464        ; the map's part of the screen
VIEWH       equ  448

; The panel, in its own pixels (it starts 464 pixels across the screen): a
; surface, shown by sprites -- the card's three layers are all the map's.
PANELX      equ  464
PANELW      equ  176
TOOLY       equ  34         ; the tool buttons: 7 of 22x22, 25 apart, from x 1
ZOOMX       equ  24         ; the magnified tile: 128x128
ZOOMY       equ  60
PALX        equ  8          ; the palette: 16x16 colors of 10x8
PALY        equ  192
SLY         equ  322        ; red, green and blue: bars 12 high
SLRX        equ  8          ;   red 0-31
SLGX        equ  48         ;   green 0-63
SLBX        equ  120        ;   blue 0-31
SWX         equ  158        ; the color itself
TSX         equ  3          ; the tile set: 10 across, 5 down, 17 apart
TSY         equ  352
TSVIS       equ  50         ;   (so many in sight)
TSROW       equ  21         ; the text row above it (NEW, DUP)
LAYROW      equ  0          ; the panel's text rows: the layers,
SETROW      equ  1          ;   the tile set's file
MAPROW      equ  28         ; the panel's text row under it: the map's name
HELPROW     equ  28         ; the text row of the keys, or a message
STATROW     equ  29         ; the text row of what is being edited

; Tools.
TL_PEN      equ  0
TL_LINE     equ  1
TL_FILL     equ  2
TL_PICK     equ  3
TL_ERASE    equ  4
TL_CLEAR    equ  5          ; (buttons, not tools)
TL_UNDO     equ  6

; What the mouse is over, or dragging.
R_NONE      equ  0
R_TOOL      equ  1
R_ZOOM      equ  2
R_PAL       equ  3
R_SLIDR     equ  4
R_SLIDG     equ  5
R_SLIDB     equ  6
R_NEW       equ  7
R_DUP       equ  8
R_TSET      equ  9
R_MAP       equ  10
R_PAN       equ  11         ; (the map being moved with the middle button)
R_LAYER     equ  12         ; the layer bar

; What the keys do.
M_EDIT      equ  0
M_DIALOG    equ  1          ; the new tile set questions
M_PROMPT    equ  2          ; a file name being typed
M_CONFIRM   equ  3          ; Y or N

UNDOS       equ  16         ; steps of undo kept
UNDOSIZE    equ  258        ; each: the tile's number and its 256 pixels (a map's
                            ; steps are in the PSRAM)
;------------------------------------------------------------------------------
            ORG  TK_BASE-EXE_HDRSIZE
            FDB  EXE_MAGIC      ; the program header
            FDB  TK_BASE        ; load address
            FDB  START          ; entry
            FDB  0              ; flags
;------------------------------------------------------------------------------
START       LDS  #TK_STACK
            JSR  INILOAD        ; the default palettes, if TILEKIT.INI has them
            LDA  #B_ARGS        ; a file named? (the tail lives in DOS's RAM)
            SWI2
            LDY  #FILENAME
ARGS1       LDA  ,X+
            CMPA #$20
            BEQ  ARGS1
ARGS2       TSTA
            BEQ  ARGS3
            CMPA #$20
            BEQ  ARGS3
            STA  ,Y+
            CMPY #FILENAME+PR_MAX
            BHS  ARGS3
            LDA  ,X+
            BRA  ARGS2
ARGS3       CLR  ,Y
            JSR  NEWPROJ        ; an 8x8, 16-color set for 320x240 to start with
            TST  FILENAME
            BEQ  ASKNEW
            LDX  #FILENAME
            LDY  #T_EXT
            JSR  DEFEXT
            LDX  #FILENAME
            JSR  OPENANY
            BCC  MAIN
            CMPA #ERR_NOTFOUND  ; not there: a new set (or map) by that name
            BNE  MAIN
            LDA  #1
            STA  KEEPNAME
            LDX  #FILENAME      ; (a .MAP: the map's name; the set has none yet)
            JSR  ISMAP
            BNE  START2
            LDX  #FILENAME
            LDY  #MAPNAME
            JSR  STRCPY
            CLR  FILENAME
            LDA  #2
            STA  KEEPNAME
START2
            JSR  NEWDIALOG
            LDX  #T_NEWFILE
            JSR  MESSAGE
            BRA  MAIN
ASKNEW      JSR  NEWDIALOG      ; (or what to make)
;------------------------------------------------------------------------------
; Each frame: the keys, the mouse, and what they changed.
;------------------------------------------------------------------------------
MAIN        JSR  WAITVB
            JSR  POLLIN
            JSR  DOKEYS
            JSR  DOMOUSE
            JSR  PERFRAME
            BRA  MAIN
;------------------------------------------------------------------------------
; The keys.
;------------------------------------------------------------------------------
DOKEYS      JSR  GETKEY
            BEQ  DOKEYS9
            STA  KCODE
            STB  KCHAR
            TSTB
            BMI  DOKEYS         ; (a release)
            LDA  MODE
            BNE  DOKEYS1
            JSR  EDITKEY
            BRA  DOKEYS
DOKEYS1     CMPA #M_DIALOG
            BNE  DOKEYS2
            JSR  DLGKEY
            BRA  DOKEYS
DOKEYS2     CMPA #M_PROMPT
            BNE  DOKEYS3
            JSR  PROMPTKEY
            BRA  DOKEYS
DOKEYS3     JSR  CONFKEY
            BRA  DOKEYS
DOKEYS9     RTS
; UPCHAR: KCHAR in B, letters in upper case.
UPCHAR      LDB  KCHAR
            CMPB #'a
            BLO  UPCHAR9
            CMPB #'z
            BHI  UPCHAR9
            SUBB #$20
UPCHAR9     RTS
; EDITKEY: a key while editing.
EDITKEY     LDA  KCODE
            CMPA #K_ESC
            LBEQ QUITCMD
            JSR  LAYERKEY       ; (1 2 3: the layers)
            BCC  EDITKEY9
            LDA  KCODE
            JSR  MAPKEYS        ; (the arrows, Home: the map scrolls)
            BCC  EDITKEY9
            LDA  KCODE
            CMPA #K_PGUP
            LBEQ PREVROW
            CMPA #K_PGDN
            LBEQ NEXTROW
            BSR  UPCHAR
            LDX  #KEYTAB
EDITKEY1    LDA  ,X
            BEQ  EDITKEY9
            CMPB ,X
            BEQ  EDITKEY2
            LEAX 3,X
            BRA  EDITKEY1
EDITKEY2    JMP  [1,X]
EDITKEY9    RTS
; The keys that type a character: the character, what it does.
KEYTAB      FCB  'P
            FDB  TOOLPEN
            FCB  'L
            FDB  TOOLLINE
            FCB  'F
            FDB  TOOLFILL
            FCB  'K
            FDB  TOOLPICK
            FCB  'I
            FDB  TOOLPICK
            FCB  'E
            FDB  TOOLERASE
            FCB  'C
            FDB  CLEARCMD
            FCB  'U
            FDB  UNDO
            FCB  $1A            ; ^Z
            FDB  UNDO
            FCB  'N
            FDB  NEWTILE
            FCB  'D
            FDB  DUPTILE
            FCB  ',
            FDB  PREVTILE
            FCB  '<
            FDB  PREVTILE
            FCB  '.
            FDB  NEXTTILE
            FCB  '>
            FDB  NEXTTILE
            FCB  '[
            FDB  LAYERBACK
            FCB  ']
            FDB  LAYERFWD
            FCB  'H
            FDB  FLIPH
            FCB  'V
            FDB  FLIPV
            FCB  '+
            FDB  NEXTCOLOR
            FCB  '=
            FDB  NEXTCOLOR
            FCB  '-
            FDB  PREVCOLOR
            FCB  $13            ; ^S
            FDB  SAVECMD
            FCB  $01            ; ^A
            FDB  SAVEASCMD
            FCB  $05            ; ^E
            FDB  EXPORTCMD
            FCB  $0C            ; ^L
            FDB  LAYERDLG
            FCB  $0F            ; ^O
            FDB  OPENCMD
            FCB  $0E            ; ^N
            FDB  NEWCMD
            FCB  0
TOOLPEN     LDB  #TL_PEN
            JMP  SETTOOL
TOOLLINE    LDB  #TL_LINE
            JMP  SETTOOL
TOOLFILL    LDB  #TL_FILL
            JMP  SETTOOL
TOOLPICK    LDB  #TL_PICK
            JMP  SETTOOL
TOOLERASE   LDB  #TL_ERASE
            JMP  SETTOOL
NEXTCOLOR   LDB  COLOR
            INCB
            JMP  SELCOLOR
PREVCOLOR   LDB  COLOR
            DECB
            JMP  SELCOLOR
NEXTROW     LDB  COLOR
            ADDB #16
            JMP  SELCOLOR
PREVROW     LDB  COLOR
            SUBB #16
            JMP  SELCOLOR
PREVTILE    LDD  TILE
            BEQ  NOTILE
            SUBD #1
            JMP  SELTILE
NEXTTILE    LDD  TILE
            ADDD #1
            CMPD NTILES
            BHS  NOTILE
            JMP  SELTILE
NOTILE      RTS
FLIPH       LDA  #$04           ; (bit 10 of a cell)
            BRA  FLIP
FLIPV       LDA  #$08           ; (bit 11)
FLIP        EORA FLIPS
            STA  FLIPS
            LDA  #1
            STA  STATDIRTY
            RTS
; CLEARCMD: clear the tile, or the map: whichever was drawn on last.
CLEARCMD    TST  FOCUS
            LBEQ CLEARTILE
            JMP  MAPCLEAR
;------------------------------------------------------------------------------
; The mouse.
;------------------------------------------------------------------------------
DOMOUSE     LDA  MODE
            BEQ  DOMOUSE1
            CMPA #M_DIALOG
            LBEQ DLGMOUSE
            RTS
DOMOUSE1    LDA  PRESSED        ; a button down: what it is over
            BEQ  DOMOUSE2
            LDA  DRAG
            BNE  DOMOUSE2       ; (one drag at a time)
            JSR  HITTEST
            STA  DRAG
            STB  DRAGSUB
            LDX  #PRESSTAB
            BSR  REGION
DOMOUSE2    LDA  BUTTONS        ; held: drawing, or a bar being dragged
            BEQ  DOMOUSE3
            LDA  DRAG
            BEQ  DOMOUSE3
            LDB  DRAGSUB
            LDX  #DRAGTAB
            BSR  REGION
DOMOUSE3    LDA  BUTTONS        ; all up: the end of a drag
            BNE  DOMOUSE4
            LDA  DRAG
            BEQ  DOMOUSE4
            CLR  DRAG
            LDX  #UPTAB
            BSR  REGION
DOMOUSE4    LDA  WHEEL          ; the wheel scrolls the tile set, or the map
            BEQ  DOMOUSE9
            JSR  HITTEST
            CMPA #R_TSET
            LBEQ SCROLLSET
            CMPA #R_MAP
            LBEQ MAPWHEEL
DOMOUSE9    RTS
; REGION: call the routine for region A in table X (a word each), B passed on.
REGION      LSLA
            LDX  A,X
            BEQ  REGION9
            JMP  ,X
REGION9     RTS
PRESSTAB    FDB  0,TOOLCLICK,ZPRESS,PALCLICK,0,0,0,NEWTILE,DUPTILE,TSETCLICK,MPRESS,0
            FDB  LAYERCLICK
DRAGTAB     FDB  0,0,ZDRAG,0,SLDRAG,SLDRAG,SLDRAG,0,0,0,MDRAG,MPAN,0
UPTAB       FDB  0,0,0,0,PALDONE,PALDONE,PALDONE,0,0,0,0,0,0
; HITTEST: what the mouse is over: A the region (R_...), B which part of it.
HITTEST     LDD  MOUSEX
            CMPD #PANELX
            BHS  HTPANEL
            LDD  MOUSEY         ; the map
            CMPD #VIEWH
            LBHS HTNONE
            LDA  #R_MAP
            RTS
HTPANEL     SUBD #PANELX
            STD  HX
            LDD  MOUSEY
            STD  HY
            CMPD #16            ; the layer bar
            BHS  HT1
            LDD  MOUSEX
            LSRD
            LSRD
            LSRD
            SUBB #LAYBARCOL
            LBLO HTNONE
            CLRA
            DIVD #3             ; (0-2 the layers, 3 the ...)
            CMPB #4
            LBHS HTNONE
            LDA  #R_LAYER
            RTS
HT1         LDD  HY
            CMPD #TOOLY         ; the tools
            BLO  HT2
            CMPD #TOOLY+22
            BHS  HT2
            LDD  HX
            SUBD #1
            LBLO HTNONE
            DIVD #25            ; B = which, A = how far in
            CMPA #22
            LBHS HTNONE
            CMPB #7
            LBHS HTNONE
            LDA  #R_TOOL
            RTS
HT2         CMPD #ZOOMY         ; the magnified tile
            BLO  HT3
            CMPD #ZOOMY+128
            BHS  HT3
            LDD  HX
            SUBD #ZOOMX
            BLO  HT3
            CMPD #128
            BHS  HT3
            LDA  #R_ZOOM
            RTS
HT3         LDD  HY             ; the palette
            CMPD #PALY
            BLO  HT4
            CMPD #PALY+128
            BHS  HT4
            LDD  HX
            SUBD #PALX
            BLO  HT4
            CMPD #160
            BHS  HT4
            DIVD #10
            STB  HCOL
            LDD  HY
            SUBD #PALY
            LSRB
            LSRB
            LSRB                ; the row
            LDA  #16
            MUL
            ADDB HCOL
            LDA  #R_PAL
            RTS
HT4         LDD  HY             ; red, green, blue
            CMPD #SLY
            BLO  HT5
            CMPD #SLY+12
            BHS  HT5
            LDD  HX
            CMPD #SLRX
            LBLO HTNONE
            CMPD #SLRX+32
            BHS  HT41
            LDA  #R_SLIDR
            RTS
HT41        CMPD #SLGX
            BLO  HTNONE
            CMPD #SLGX+64
            BHS  HT42
            LDA  #R_SLIDG
            RTS
HT42        CMPD #SLBX
            BLO  HTNONE
            CMPD #SLBX+32
            BHS  HTNONE
            LDA  #R_SLIDB
            RTS
HT5         CMPD #TSROW*16      ; NEW and DUP
            BLO  HT6
            CMPD #TSROW*16+16
            BHS  HT6
            LDD  MOUSEX
            LSRD
            LSRD
            LSRD                ; the column
            CMPB #69
            BLO  HTNONE
            CMPB #73
            BHS  HT51
            LDA  #R_NEW
            RTS
HT51        CMPB #74
            BLO  HTNONE
            CMPB #78
            BHS  HTNONE
            LDA  #R_DUP
            RTS
HT6         CMPD #TSY           ; the tile set
            BLO  HTNONE
            CMPD #TSY+TSVIS/10*17
            BHS  HTNONE
            LDD  HX
            SUBD #TSX
            BLO  HTNONE
            CMPD #10*17
            BHS  HTNONE
            DIVD #17
            STB  HCOL
            LDD  HY
            SUBD #TSY
            DIVD #17
            LDA  #10
            MUL
            ADDB HCOL
            LDA  #R_TSET
            RTS
HTNONE      CLRA
            RTS
;------------------------------------------------------------------------------
; What a click does.
;------------------------------------------------------------------------------
TOOLCLICK   CMPB #TL_CLEAR
            LBEQ CLEARCMD
            CMPB #TL_UNDO
            LBEQ UNDO
            JMP  SETTOOL
PALCLICK    JMP  SELCOLOR
TSETCLICK   CLRA
            ADDD TSTOP
            CMPD NTILES
            BHS  TSETCLICK9
            JMP  SELTILE
TSETCLICK9  RTS
; SCROLLSET: the tile set up or down a row a wheel click.
SCROLLSET   LDD  NTILES         ; the most it can scroll: the last row at the bottom
            ADDD #9
            DIVD #10            ; B = rows
            LDA  #10
            MUL
            SUBD #TSVIS
            BPL  SCROLL1
            CLRD
SCROLL1     STD  MAXTOP
            LDB  WHEEL          ; away from you: towards the first tile
            BPL  SCRUP
SCRDN       LDD  TSTOP          ; towards the end
            ADDD #10
            CMPD MAXTOP
            BHI  SCRSET
            STD  TSTOP
            INC  WHEEL
            BNE  SCRDN
            BRA  SCRSET
SCRUP       LDD  TSTOP          ; towards the start
            BEQ  SCRSET
            SUBD #10
            STD  TSTOP
            DEC  WHEEL
            BNE  SCRUP
SCRSET      JMP  DRAWTSET
;------------------------------------------------------------------------------
; Editing the tile in the magnified view.
;------------------------------------------------------------------------------
; ZPIXEL: the tile's pixel under the mouse: carry clear and A = x, B = y if it
; is over the magnified tile; carry set if not.
ZPIXEL      LDD  MOUSEY
            SUBD #ZOOMY
            BLO  ZPIXEL9
            CMPD #128
            BHS  ZPIXEL9
            LDA  ZSHIFT
ZPIXEL1     LSRB
            DECA
            BNE  ZPIXEL1
            STB  ZPY
            LDD  MOUSEX
            SUBD #PANELX+ZOOMX
            BLO  ZPIXEL9
            CMPD #128
            BHS  ZPIXEL9
            LDA  ZSHIFT
ZPIXEL2     LSRB
            DECA
            BNE  ZPIXEL2
            TFR  B,A
            LDB  ZPY
            ANDCC #$FE
            RTS
ZPIXEL9     ORCC #$01
            RTS
; PENVAL: the value the tool draws with: 0 with the right button or the eraser,
; else the color picked (in a 16-color set, its place in its row).
PENVAL      CLR  PENC
            LDA  BUTTONS
            BITA #VC_MB_LEFT
            BEQ  PENVAL9
            LDA  TOOL
            CMPA #TL_ERASE
            BEQ  PENVAL9
            LDA  COLOR
            LDB  BPP
            CMPB #8
            BEQ  PENVAL1
            ANDA #$0F
PENVAL1     STA  PENC
PENVAL9     RTS
; ZPRESS: a button down over the magnified tile.
ZPRESS      BSR  ZPIXEL
            BCS  ZPRESS9
            CLR  FOCUS          ; (clear is for the tile now)
            STD  LASTX          ; (LASTX, LASTY)
            STD  ANCX           ; (ANCX, ANCY: where a line starts)
            LDA  #1
            STA  INZOOM
            BSR  PENVAL
            LDA  TOOL
            CMPA #TL_PICK
            BEQ  ZPICK
            JSR  PUSHUNDO
            LDA  TOOL
            CMPA #TL_FILL
            BEQ  ZFILL
            LDA  #1             ; pen, eraser, line: the first pixel
            STA  DRAWNOW
            LDD  LASTX
            JMP  SETPIX
ZFILL       LDD  LASTX
            JSR  FLOOD
            JSR  DRAWZOOM
            LDA  #1
            STA  TDIRTY
ZPRESS9     RTS
ZPICK       LDD  LASTX
            JSR  PIXIDX
            LDA  TILEBUF,X
            LDB  BPP
            CMPB #8
            BEQ  ZPICK1
            LDB  COLOR          ; (the same row)
            ANDB #$F0
            PSHS B
            ORA  ,S+
ZPICK1      TFR  A,B
            JMP  SELCOLOR
; ZDRAG: a button held over (or off) the magnified tile.
ZDRAG       LDA  TOOL
            CMPA #TL_PICK
            BEQ  ZPICK2
            CMPA #TL_FILL
            BEQ  ZDRAG9
            JSR  ZPIXEL
            BCS  ZDRAGOFF
            CMPD LASTX
            BEQ  ZDRAG9         ; (not moved off the pixel)
            STD  ZNEW
            LDA  TOOL
            CMPA #TL_LINE
            BEQ  ZLINE
            LDA  INZOOM         ; pen, eraser: a line from the last pixel
            BEQ  ZDRAG1         ; (or a new start, back from off the tile)
            LDD  LASTX
            STD  LX0
            LDD  ZNEW
            STD  LX1
            LDA  #1
            STA  DRAWNOW
            LDX  #SETPIX
            STX  PLOTV
            JSR  LINE
            BRA  ZDRAG2
ZDRAG1      LDA  #1
            STA  DRAWNOW
            LDD  ZNEW
            JSR  SETPIX
ZDRAG2      LDD  ZNEW
            STD  LASTX
            LDA  #1
            STA  INZOOM
ZDRAG9      RTS
ZDRAGOFF    CLR  INZOOM
            RTS
ZPICK2      JSR  ZPIXEL         ; (picking follows the mouse)
            BCS  ZDRAG9
            STD  LASTX
            LBRA ZPICK
ZLINE       JSR  PEEKUNDO       ; the tile as it was, then the line to here
            LDD  ANCX
            STD  LX0
            LDD  ZNEW
            STD  LX1
            STD  LASTX
            CLR  DRAWNOW
            LDX  #SETPIX
            STX  PLOTV
            JSR  LINE
            JSR  DRAWZOOM
            LDA  #1
            STA  TDIRTY
            RTS
; PIXIDX: X = the index in TILEBUF of pixel A = x, B = y. (D kept.)
PIXIDX      PSHS D
            LDA  TSHIFT
            CLR  ,-S
            LDB  2,S            ; y
PIXIDX1     LSLB
            ROL  ,S
            DECA
            BNE  PIXIDX1
            ADDB 1,S            ; + x
            LDA  ,S+
            ADCA #0
            TFR  D,X
            PULS D,PC
; SETPIX: pixel A = x, B = y of TILEBUF to PENC; drawn magnified too if DRAWNOW.
SETPIX      BSR  PIXIDX
            LDA  PENC
            STA  TILEBUF,X
            LDA  #1
            STA  TDIRTY
            TST  DRAWNOW
            BEQ  SETPIX9
            TFR  X,D
            JMP  DRAWZPIX
SETPIX9     RTS
; LINE: from LX0, LY0 to LX1, LY1 (each end too), each point (A = x, B = y)
; given to the routine at PLOTV: SETPIX for the tile, PUTCELL for the map.
LINE        CLRA                ; dx = |x1 - x0|, sx
            LDB  LX1
            SUBB LX0
            SBCA #0
            LDX  #1
            TSTA
            BPL  LINE1
            NEGD
            LDX  #-1
LINE1       STD  LNDX
            STX  LNSX
            CLRA                ; dy = -|y1 - y0|, sy
            LDB  LY1
            SUBB LY0
            SBCA #0
            LDX  #1
            TSTA
            BPL  LINE2
            NEGD
            LDX  #-1
LINE2       STX  LNSY
            NEGD
            STD  LNDY
            ADDD LNDX
            STD  LNERR          ; err = dx + dy
LINE3       LDD  LX0
            JSR  [PLOTV]
            LDD  LX0
            CMPD LX1
            BEQ  LINE9
            LDD  LNERR
            LSLD                ; e2 = 2 * err
            STD  LNE2
            CMPD LNDY
            BLT  LINE4
            LDD  LNERR          ; e2 >= dy: a step across
            ADDD LNDY
            STD  LNERR
            LDA  LX0
            ADDA LNSX+1
            STA  LX0
LINE4       LDD  LNE2
            CMPD LNDX
            BGT  LINE3
            LDD  LNERR          ; e2 <= dx: a step down
            ADDD LNDX
            STD  LNERR
            LDA  LY0
            ADDA LNSY+1
            STA  LY0
            BRA  LINE3
LINE9       RTS
; FLOOD: fill from pixel A = x, B = y in PENC, over the pixels of its value
; that touch it (not diagonally).
FLOOD       JSR  PIXIDX
            LDA  TILEBUF,X
            CMPA PENC
            BEQ  FLOOD9         ; (already that)
            STA  FOLD
            LDA  PENC
            STA  TILEBUF,X
            LDU  #FSTACK        ; a stack of pixel numbers to look around
            TFR  X,D
            STB  ,U+
FLOOD1      CMPU #FSTACK
            BEQ  FLOOD9
            LDB  ,-U
            STB  FIDX
            ANDB TSMASK
            BEQ  FLOOD2         ; (the left edge)
            LDB  FIDX
            DECB
            BSR  FTRY
FLOOD2      LDB  FIDX
            ANDB TSMASK
            CMPB TSMASK
            BEQ  FLOOD3         ; (the right edge)
            LDB  FIDX
            INCB
            BSR  FTRY
FLOOD3      LDB  FIDX
            SUBB TSIZE
            BLO  FLOOD4         ; (the top)
            BSR  FTRY
FLOOD4      LDB  FIDX
            ADDB TSIZE
            BCS  FLOOD1         ; (the bottom, of a 16x16 tile)
            LDA  TSIZE
            CMPA #8
            BNE  FLOOD5
            CMPB #64
            BHS  FLOOD1         ; (the bottom, of an 8x8 one)
FLOOD5      BSR  FTRY
            BRA  FLOOD1
FLOOD9      RTS
; FTRY: pixel B is filled and stacked if it has the value being filled over.
FTRY        LDX  #TILEBUF
            ABX
            LDA  ,X
            CMPA FOLD
            BNE  FTRY9
            LDA  PENC
            STA  ,X
            STB  ,U+
FTRY9       RTS
;------------------------------------------------------------------------------
; Undo: before each change to a tile, the tile as it was.
;------------------------------------------------------------------------------
; UNDOSLOT: X = slot B (0-15) of UNDOMEM.
UNDOSLOT    LDA  #UNDOSIZE/2
            MUL
            LSLD
            ADDD #UNDOMEM
            TFR  D,X
            RTS
PUSHUNDO    LDB  UHEAD
            LDX  #UTYPE         ; (a tile's step, and its layer's)
            LDA  CURL
            LSLA
            LSLA
            LSLA
            LSLA
            STA  B,X
            BSR  UNDOSLOT
            LDD  TILE
            STD  ,X++
            LDY  #TILEBUF
            LDW  #256
            TFM  Y+,X+
; NEXTUNDO: the newest step taken: the next slot, one more to undo.
NEXTUNDO    LDA  UHEAD
            INCA
            ANDA #UNDOS-1
            STA  UHEAD
            LDA  UCOUNT
            CMPA #UNDOS
            BHS  PUSHUNDO9
            INC  UCOUNT
PUSHUNDO9   RTS
; PEEKUNDO: TILEBUF as the newest step has it (a line being drawn starts again).
PEEKUNDO    LDB  UHEAD
            DECB
            ANDB #UNDOS-1
            BSR  UNDOSLOT
            LEAX 2,X
            LDY  #TILEBUF
            LDW  #256
            TFM  X+,Y+
            RTS
UNDO        LDA  UCOUNT
            BNE  UNDO1
            LDX  #T_NOUNDO
            JMP  MESSAGE
UNDO1       DEC  UCOUNT
            LDB  UHEAD
            DECB
            ANDB #UNDOS-1
            STB  UHEAD
            LDX  #UTYPE
            LDA  B,X
            STA  UTHIS
            LSRA                ; (another layer's step: that layer first)
            LSRA
            LSRA
            LSRA
            CMPA CURL
            BEQ  UNDO0
            TFR  A,B
            JSR  SELLAYER
UNDO0       LDB  UHEAD
            LDA  UTHIS
            BITA #1
            BEQ  UNDO3
            JSR  MAPBACKU       ; a map's step: the map as it was
            LDA  #1
            STA  MAPMOD
            STA  STATDIRTY
            RTS
UNDO3       JSR  UNDOSLOT
            LDD  ,X++
            PSHS X
            CMPD TILE           ; another tile: go to it first
            BEQ  UNDO2
            JSR  SELTILE
UNDO2       PULS X
            LDY  #TILEBUF
            LDW  #256
            TFM  X+,Y+
            JSR  STORETILE
            JSR  DRAWZOOM
            LDD  TILE
            JSR  THUMB
            LDA  #1
            STA  MODIFIED
            STA  STATDIRTY
            RTS
;------------------------------------------------------------------------------
; Tiles.
;------------------------------------------------------------------------------
; CLEARTILE: every pixel of the tile 0.
CLEARTILE   JSR  PUSHUNDO
            LDX  #TILEBUF
            LDW  #256
CLEARTILE1  CLR  ,X+
            DECW
            BNE  CLEARTILE1
            JSR  DRAWZOOM
            LDA  #1
            STA  TDIRTY
            RTS
; NEWTILE: a blank tile at the end of the set; DUPTILE: a copy of this one.
NEWTILE     LDD  NTILES
            CMPD MAXT
            BHS  SETFULL
            LDX  #TILEBUF
            LDW  #256
NEWTILE1    CLR  ,X+
            DECW
            BNE  NEWTILE1
            BRA  ADDTILE
DUPTILE     LDD  NTILES
            CMPD MAXT
            BHS  SETFULL
ADDTILE     JSR  FLUSHTILE
            LDA  UI_MID         ; (the frame back to an outline on this one)
            JSR  TSFRAME
            LDX  TILE
            STX  OLDTILE
            LDD  NTILES         ; TILEBUF becomes the new last tile
            STD  TILE
            ADDD #1
            STD  NTILES
            JSR  STORETILE
            JSR  CURROW         ; (in this row)
            JSR  SETTROW
            LDD  OLDTILE        ; (the one before: in its own row)
            JSR  THUMB
            LDA  #1
            STA  MODIFIED
            JSR  DRAWTSLABEL
            LDD  TILE
            JSR  THUMB
            BRA  SHOWTILE
SETFULL     LDX  #T_FULL
            JMP  MESSAGE
; SELTILE: tile D to edit.
SELTILE     CMPD TILE
            BEQ  SELTILE9
            PSHS D
            JSR  FLUSHTILE
            LDA  UI_MID         ; (its frame in the set back to an outline)
            JSR  TSFRAME
            LDX  TILE
            STX  OLDTILE
            PULS D
            STD  TILE
            JSR  LOADTILE
            LDD  OLDTILE        ; the one before: in its own row
            JSR  THUMB
            LDA  BPP            ; (16 colors: the row this one was last in, the
            CMPA #8             ; same place in it)
            BEQ  SHOWTILE
            LDX  #TROW
            LDD  TILE
            LDA  D,X
            LSLA
            LSLA
            LSLA
            LSLA
            STA  OLDROW
            LDB  COLOR
            ANDB #$0F
            ORB  OLDROW
            JSR  SELCOLOR
SHOWTILE    LDD  TILE           ; in sight in the set?
            CMPD TSTOP
            BLO  SHOWTILE1
            SUBD TSTOP
            CMPD #TSVIS
            BLO  SHOWTILE2
SHOWTILE1   LDD  TILE           ; no: its row, at the top or the bottom
            DIVD #10
            LDA  #10
            MUL
            CMPD TSTOP
            BLO  SHOWTILE3
            SUBD #TSVIS-10
SHOWTILE3   STD  TSTOP
            JSR  DRAWTSET
            BRA  SHOWTILE4
SHOWTILE2   LDA  UI_HI
            JSR  TSFRAME
SHOWTILE4   JSR  DRAWZOOM
            LDA  #1
            STA  STATDIRTY
SELTILE9    RTS
; TILEADDR: A:X = where tile D is in video memory.
TILEADDR    LDF  TBSHIFT
TILEADDR1   LSLD
            DECF
            BNE  TILEADDR1
            ADDD TBASE+1        ; + where the tile set is
            TFR  D,X
            LDA  TBASE
            ADCA #0
            RTS
; LOADTILE: TILEBUF from the card.
LOADTILE    LDD  TILE
            BSR  TILEADDR
            JSR  PORT1
            LDY  #TILEBUF
            BRA  UNPACK
; UNPACK: a tile from data port 1 into Y, a byte a pixel.
UNPACK      LDA  BPP
            CMPA #8
            BNE  UNPACK4
            LDW  TB
            LDX  #VC_DATA1
            TFM  X,Y+
            RTS
UNPACK4     LDW  TB
UNPACK41    LDA  VC_DATA1
            TFR  A,B
            LSRA
            LSRA
            LSRA
            LSRA
            ANDB #$0F
            STD  ,Y++
            DECW
            BNE  UNPACK41
            RTS
; STORETILE: TILEBUF to the card.
STORETILE   LDD  TILE
            BSR  TILEADDR
            JSR  PORT0
            LDX  #TILEBUF
            LDA  BPP
            CMPA #8
            BNE  STORE4
            LDW  TB
            LDY  #VC_DATA0
            TFM  X+,Y
            RTS
STORE4      LDW  TB
STORE41     LDD  ,X++
            LSLA
            LSLA
            LSLA
            LSLA
            PSHS B
            ORA  ,S+
            STA  VC_DATA0
            DECW
            BNE  STORE41
            RTS
;------------------------------------------------------------------------------
; Colors and tools.
;------------------------------------------------------------------------------
; SELCOLOR: color B to draw with (in a 16-color set, its row is the tiles' palette).
SELCOLOR    CMPB COLOR
            BEQ  SELCOLOR9
            PSHS B
            LDA  UI_BG          ; (its frame off)
            JSR  PALFRAME
            LDA  COLOR
            ANDA #$F0
            STA  OLDROW
            PULS B
            STB  COLOR
            LDA  UI_HI
            JSR  PALFRAME
            JSR  DRAWSLID
            LDA  #1
            STA  STATDIRTY
            LDA  BPP            ; a new row: the tiles are shown in it
            CMPA #8
            BEQ  SELCOLOR9
            LDA  COLOR
            ANDA #$F0
            CMPA OLDROW
            BEQ  SELCOLOR9
            JSR  DRAWZOOM
            LDD  TILE           ; (the other tiles: in their own rows)
            JMP  THUMB
SELCOLOR9   RTS
; SLDRAG: red, green or blue (DRAG) set from where the mouse is along its bar.
SLDRAG      LDB  COLOR
            JSR  RGBOF          ; GK_R, GK_G, GK_B as they are
            LDA  DRAG
            SUBA #R_SLIDR
            LDB  #4
            MUL
            LDX  #SLMAX
            ABX                 ; X: the bar's x, its top value, where its value goes
            LDD  MOUSEX
            SUBD #PANELX
            SUBB ,X
            SBCA #0             ; how far along it (maybe before it, or past it)
            BPL  SLDRAG1
            CLRB
            BRA  SLDRAG3
SLDRAG1     TSTA
            BNE  SLDRAG2
            CMPB 1,X
            BLS  SLDRAG3
SLDRAG2     LDB  1,X
SLDRAG3     LDY  2,X
            CMPB ,Y
            BEQ  SLDRAG9
            STB  ,Y
            LDB  COLOR
            JSR  RGBTO
            JSR  DRAWSLID
            LDA  #1
            STA  PALCHG
            STA  MODIFIED
            STA  STATDIRTY
SLDRAG9     RTS
SLMAX       FCB  SLRX,31
            FDB  GK_R
            FCB  SLGX,63
            FDB  GK_G
            FCB  SLBX,31
            FDB  GK_B
; PALDONE: a color has been changed: the editor's own colors may be others now.
PALDONE     TST  PALCHG
            BEQ  PALDONE9
            CLR  PALCHG
            JSR  UICOLORS
            TSTA
            BEQ  PALDONE9
            JMP  REDRAWALL
PALDONE9    RTS
; SETTOOL: tool B.
SETTOOL     LDA  TOOL
            STB  TOOL
            PSHS A
            JSR  DRAWTOOL
            PULS B
            JSR  DRAWTOOL
            LDA  #1
            STA  STATDIRTY
            RTS
;------------------------------------------------------------------------------
; Each frame, after the keys and the mouse.
;------------------------------------------------------------------------------
PERFRAME    BSR  FLUSHTILE
            JSR  HOVER
            LDA  MSGTIME        ; a message: back to the keys after a while
            BEQ  PERFRAME2
            DECA
            STA  MSGTIME
            BNE  PERFRAME2
            JSR  DRAWHELP
PERFRAME2   TST  STATDIRTY
            BEQ  PERFRAME9
            CLR  STATDIRTY
            JSR  DRAWSTATUS
            JSR  DRAWTITLE
PERFRAME9   RTS
; FLUSHTILE: if TILEBUF has changed, to the card (so the left shows it) and its
; picture in the set.
FLUSHTILE   TST  TDIRTY
            BEQ  FLUSHTILE9
            CLR  TDIRTY
            JSR  STORETILE
            JSR  CURROW         ; (drawn in this row: its row now)
            JSR  SETTROW
            LDD  TILE
            JSR  THUMB
            LDA  MODIFIED
            BNE  FLUSHTILE9
            LDA  #1
            STA  MODIFIED
            STA  STATDIRTY
FLUSHTILE9  RTS
; CURROW: A = the row of the color picked (0-15). SETTROW: tile TILE's own row
; (its picture in the set is in it) is A.
CURROW      LDA  COLOR
            LSRA
            LSRA
            LSRA
            LSRA
            RTS
SETTROW     PSHS A
            LDD  TILE
            LDX  #TROW
            LEAX D,X
            PULS A
            STA  ,X
            RTS
;------------------------------------------------------------------------------
            INCLUDE "tk_map.asm"
            INCLUDE "tk_draw.asm"
            INCLUDE "tk_file.asm"
            INCLUDE "tk_src.asm"
            INCLUDE "tk_ini.asm"
            INCLUDE "tk_layer.asm"
            INCLUDE "tk_ldlg.asm"
;------------------------------------------------------------------------------
; Variables.
;------------------------------------------------------------------------------
TSIZE       FCB  8          ; the tile set: tiles 8 or 16 pixels square
BPP         FCB  4          ;   bits a pixel, 4 or 8
HIRES       FCB  0          ;   for 640x480 (1) or 320x240 (0)
NTILES      FDB  1          ;   how many tiles
TSHIFT      FCB  3          ; and from those: log2 of the tile size
TSMASK      FCB  7          ;   the tile size - 1
TPIX        FDB  64         ;   pixels in a tile
TBSHIFT     FCB  5          ;   log2 of the bytes in a tile
TB          FDB  32         ;   bytes in a tile
MAXT        FDB  1024       ;   the most tiles there is room for
CHUNKT      FCB  16         ;   tiles in 512 bytes
ZSHIFT      FCB  4          ;   log2 of the magnification
ZOOM        FCB  16         ;   the magnification (8 or 16)
TILE        FDB  0          ; the tile being edited
TSTOP       FDB  0          ; the first tile in sight in the set
MAXTOP      FDB  0          ; the most TSTOP can be
COLOR       FCB  15         ; the color drawn with
OLDROW      FCB  0
OLDTILE     FDB  0
TOOL        FCB  TL_PEN
MODE        FCB  M_EDIT
MODIFIED    FCB  0          ; changed since saved
STATDIRTY   FCB  0          ; the status line is to be drawn again
TDIRTY      FCB  0          ; TILEBUF is to go to the card
PALCHG      FCB  0          ; a color was changed (in this drag)
MSGTIME     FCB  0          ; frames left of a message
DRAG        FCB  R_NONE     ; what the mouse is dragging
DRAGSUB     FCB  0
KCODE       FCB  0
KCHAR       FCB  0
HX          FDB  0
HY          FDB  0
HCOL        FCB  0
INZOOM      FCB  0          ; the last drag step was over the tile
DRAWNOW     FCB  0
PENC        FCB  0
ZPY         FCB  0
LASTX       FCB  0          ; (LASTX, LASTY: one word)
LASTY       FCB  0
ANCX        FCB  0
ANCY        FCB  0
ZNEW        FDB  0
LX0         FCB  0          ; LINE's ends (LX0, LY0 and LX1, LY1: words)
LY0         FCB  0
LX1         FCB  0
LY1         FCB  0
PLOTV       FDB  SETPIX     ; what LINE does with each point
LNDX        FDB  0
LNDY        FDB  0
LNSX        FDB  0
LNSY        FDB  0
LNERR       FDB  0
LNE2        FDB  0
FOLD        FCB  0
FIDX        FCB  0
UHEAD       FCB  0          ; the next undo slot
UCOUNT      FCB  0          ; steps that can be undone
UTYPE       FCB  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0 ; each slot: bit 0 the map's (else a
                            ; tile's); bits 4-5 its layer
UTHIS       FCB  0
USLOT       FCB  0,0,0      ; a map step's place in the PSRAM
MAPWC       FCB  1          ; the map: its width, 32 << this (64)
MAPHC       FCB  1          ;   and height (64)
MAPW        FDB  64         ;   in cells
MAPH        FDB  64
MAPWSH      FCB  6          ;   log2 of the width
MAPBYTES    FDB  8192
SCLSH       FCB  1          ;   1 at 320x240: a layer pixel is 2 screen ones
SCRX        FDB  0          ; the view, scrolled to here (the screen's pixels)
SCRY        FDB  0
MAPMOD      FCB  0          ;   changed since saved
MPEN        FDB  0          ;   the cell the tool puts down
FLIPS       FCB  0          ;   $04 across, $08 down: the cells' flips (bits 10, 11)
FOCUS       FCB  0          ; clear is for: 0 the tile, 1 the map
HOVX        FCB  $FF        ; the cell under the mouse ($FF: none)
HOVY        FCB  $FF
CURSZ       FCB  16         ; the frame round it, its size on the screen
CURATTR     FCB  0          ;   (its sprite size bits)
PANMX       FDB  0          ; a move with the middle button: where it started
PANMY       FDB  0
PANSX       FDB  0
PANSY       FDB  0
FX          FCB  0          ; the map's fill (FX, FY: a word)
FY          FCB  0
FOLDC       FDB  0
FUP         FCB  0
EXTW        FDB  0          ; how far the layers reach (the screen's pixels)
EXTH        FDB  0
PICKED      FDB  0          ; the cell picked up
FDOWN       FCB  0
            INCLUDE "gk_ui.asm" ; (it ends with space reserved, as this does)
FILENAME    RMB  PR_MAX+1   ; the tile set's file
MAPNAME     RMB  PR_MAX+1   ; the map's
MPATHBUF    RMB  PR_MAX+1
EXPNAME     RMB  PR_MAX+1   ; an export's name, to start with
MFSTACK     RMB  MFMAX*2
TROW        RMB  1024       ; each tile's own row (16-color sets): its picture in it
PAL8BUF     RMB  512        ; TILEKIT.INI's palettes: for 256-color sets
PAL4BUF     RMB  512        ;   and for 16-color ones
LRECS       RMB  3*LRSIZE   ; the layers' records (tk_layer.asm)
TSRECS      RMB  3*TSRSIZE  ;   and the tile sets' (these two together)
TROWS       RMB  3*1024     ;   and the tile sets' own TROWs
TILEBUF     RMB  256        ; the tile being edited, a byte a pixel
THUMBBUF    RMB  256
FSTACK      RMB  256
IOBUF       RMB  512
UNDOMEM     RMB  UNDOS*UNDOSIZE

            END  START
