;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 game kit
;    FILE: tk_map.asm
;
; TILEKIT's map: the left of the screen, the card's tile layer 0 showing the
; map in video memory (MAPV) -- scrolled, with the cell under the mouse framed
; by sprite 1, and what is past the end of a map smaller than the screen
; covered by the text layer (the card would show the map again there: it
; wraps around). The tools, on its cells; its undo steps, in the card's PSRAM.
; INCLUDEd by tilekit.asm.
;
; A cell is the card's map entry: bits 0-9 the tile, 10 flipped across, 11
; flipped down, 12-15 the palette row (in a 16-color set).
;------------------------------------------------------------------------------
MFMAX       equ  1024       ; the fill's stack: places to look from, at most
;------------------------------------------------------------------------------
; The map's size, and the card for it.
;------------------------------------------------------------------------------
; MAPSETUP: MAPW, MAPH and the rest from MAPWC, MAPHC; the scroll kept in the
; map; layer 0, the cursor and the cover set up for it.
MAPSETUP    LDD  #32            ; MAPW = 32 << MAPWC
            LDF  MAPWC
            BEQ  MAPSETUP2
MAPSETUP1   LSLD
            DECF
            BNE  MAPSETUP1
MAPSETUP2   STD  MAPW
            LDD  #32
            LDF  MAPHC
            BEQ  MAPSETUP4
MAPSETUP3   LSLD
            DECF
            BNE  MAPSETUP3
MAPSETUP4   STD  MAPH
            LDA  MAPWC
            ADDA #5
            STA  MAPWSH
            LDD  #2048          ; MAPBYTES = 32 x 32 x 2 << (MAPWC + MAPHC)
            LDF  MAPWC
            ADDF MAPHC
            BEQ  MAPSETUP6
MAPSETUP5   LSLD
            DECF
            BNE  MAPSETUP5
MAPSETUP6   STD  MAPBYTES
            CLR  SCLSH          ; 320x240: the layer's pixels are 2 of the screen's
            TST  HIRES
            BNE  MAPSETUP7
            INC  SCLSH
MAPSETUP7   LDA  #$FF           ; (nothing under the mouse yet)
            STA  HOVX
            LDA  #VC_CFG/$10000 ; layer 0: its size, where it is
            LDX  #LAYER0+L_MAP
            JSR  PORT0
            LDA  MAPHC
            LSLA
            LSLA
            ORA  MAPWC
            STA  VC_DATA0
            LDA  #MAPV/$10000
            STA  VC_DATA0
            LDD  #MAPV&$FFFF
            STA  VC_DATA0
            STB  VC_DATA0
            JSR  MKCURSOR
; MAPSCROLL: SCRX, SCRY kept in the map, and the layer scrolled there.
MAPSCROLL   LDD  MAPW           ; the most across: the map's width less the view's
            BSR  MPIX
            STD  GK_T
            LDD  #VIEWW
            BSR  LPIX
            PSHS D
            LDD  GK_T
            SUBD ,S++
            BPL  MAPSCROLL1
            CLRD
MAPSCROLL1  CMPD SCRX
            BHS  MAPSCROLL2
            STD  SCRX
MAPSCROLL2  LDD  MAPH           ; and down
            BSR  MPIX
            STD  GK_T
            LDD  #VIEWH
            BSR  LPIX
            PSHS D
            LDD  GK_T
            SUBD ,S++
            BPL  MAPSCROLL3
            CLRD
MAPSCROLL3  CMPD SCRY
            BHS  MAPSCROLL4
            STD  SCRY
MAPSCROLL4  LDA  #VC_CFG/$10000
            LDX  #LAYER0+L_HSCROLL
            JSR  PORT0
            LDD  SCRX
            STA  VC_DATA0
            STB  VC_DATA0
            LDD  SCRY
            STA  VC_DATA0
            STB  VC_DATA0
            LDA  #$FF
            STA  HOVX
            JMP  MASKMAP
; MPIX: D cells in the layer's pixels. LPIX: D screen pixels in the layer's.
MPIX        LDF  TSHIFT
MPIX1       LSLD
            DECF
            BNE  MPIX1
            RTS
LPIX        TST  SCLSH
            BEQ  LPIX9
            LSRD
LPIX9       RTS
; MASKMAP: the text layer over the view: see-through over the map, shaded
; (the font's light shade, in UI_MID on UI_BG) past its end -- a map smaller
; than the view.
MASKMAP     LDD  MAPW           ; how far the map reaches across the screen, in
            BSR  MPIX           ; text columns ...
            SUBD SCRX
            TST  SCLSH
            BEQ  MASKMAP1
            LSLD
MASKMAP1    LSRD
            LSRD
            LSRD
            CMPD #VIEWW/8
            BLS  MASKMAP2
            LDD  #VIEWW/8
MASKMAP2    STB  MASKC
            LDD  MAPH           ; ... and down, in rows
            BSR  MPIX
            SUBD SCRY
            TST  SCLSH
            BEQ  MASKMAP3
            LSLD
MASKMAP3    LSRD
            LSRD
            LSRD
            LSRD
            CMPD #VIEWH/16
            BLS  MASKMAP4
            LDD  #VIEWH/16
MASKMAP4    STB  MASKR
            LDA  UI_MID         ; (past the end: shaded)
            STA  TXFG
            CLRB                ; the row
MASKMAP5    PSHS B
            CLRA
            JSR  TXAT
            LDE  #VIEWW/8
            LDF  MASKC          ; the columns over the map
            CMPB MASKR
            BLO  MASKMAP6
            CLRF                ; (a row past its end: none)
MASKMAP6    CLR  TXBG
            LDA  #$20
MASKMAP7    TSTF
            BEQ  MASKMAP8
            JSR  TXCH
            DECF
            DECE
            BNE  MASKMAP7
            BRA  MASKMAP9
MASKMAP8    LDB  UI_BG          ; the rest covered, shaded
            STB  TXBG
            LDA  #$B0
            JSR  TXCH
            DECE
            BNE  MASKMAP8
MASKMAP9    PULS B
            INCB
            CMPB #VIEWH/16
            BNE  MASKMAP5
            RTS
; MKCURSOR: sprite 1, the frame round the cell under the mouse: a square the
; size a cell is on the screen (8, 16 or 32 pixels), in UI_HI.
MKCURSOR    LDA  TSIZE          ; its size: the tile's, doubled at 320x240
            LDB  SCLSH
            BEQ  MKCURSOR1
            LSLA
MKCURSOR1   STA  CURSZ
            LDA  #CURIMG/$10000
            LDX  #CURIMG&$FFFF
            JSR  PORT0
            LDE  CURSZ          ; the rows
MKCURSOR2   LDF  CURSZ          ; the pixels
MKCURSOR3   LDA  UI_HI
            CMPE CURSZ          ; the top and bottom rows, the first and last
            BEQ  MKCURSOR4      ; pixels: the frame
            CMPE #1
            BEQ  MKCURSOR4
            CMPF CURSZ
            BEQ  MKCURSOR4
            CMPF #1
            BEQ  MKCURSOR4
            CLRA
MKCURSOR4   STA  VC_DATA0
            DECF
            BNE  MKCURSOR3
            DECE
            BNE  MKCURSOR2
            LDA  #VC_SPRITES/$10000 ; sprite 1's image, size and colors (hidden)
            LDX  #(VC_SPRITES+8)&$FFFF
            JSR  PORT0
            LDD  #CURIMG/32
            STA  VC_DATA0
            STB  VC_DATA0
            LDX  #(VC_SPRITES+14)&$FFFF
            LDA  #VC_SPRITES/$10000
            JSR  PORT0
            CLRA                ; 8x8
            LDB  CURSZ
            CMPB #8
            BEQ  MKCURSOR5
            LDA  #SS_W16+SS_H16
            CMPB #16
            BEQ  MKCURSOR5
            LDA  #SS_W32+SS_H32
MKCURSOR5   STA  CURATTR
            STA  VC_DATA0       ; (priority 0: not shown)
            LDA  #SC_8BPP
            STA  VC_DATA0
            RTS
; HOVER: the cell under the mouse framed (or no frame, off the map), and its
; place in the status line.
HOVER       LDA  MODE
            BNE  HOVER0
            LDA  DRAG
            CMPA #R_PAN
            BEQ  HOVER0
            JSR  MAPCELL
            BCC  HOVER1
HOVER0      LDA  #$FF           ; not on the map
            TFR  A,B
HOVER1      CMPD HOVX
            BEQ  HOVER9
            STD  HOVX
            LDA  #1
            STA  STATDIRTY
            LDA  #VC_SPRITES/$10000
            LDX  #(VC_SPRITES+10)&$FFFF
            JSR  PORT0
            LDA  HOVX
            CMPA #$FF
            BEQ  HOVER2
            CLRA                ; X: the cell's left edge on the screen
            LDB  HOVX
            JSR  MPIX
            SUBD SCRX
            TST  SCLSH
            BEQ  HOVER3
            LSLD
HOVER3      STA  VC_DATA0
            STB  VC_DATA0
            CLRA                ; Y: its top
            LDB  HOVY
            JSR  MPIX
            SUBD SCRY
            TST  SCLSH
            BEQ  HOVER4
            LSLD
HOVER4      STA  VC_DATA0
            STB  VC_DATA0
            LDA  CURATTR
            ORA  #SS_FRONT
            STA  VC_DATA0
HOVER9      RTS
HOVER2      LDB  #4             ; off the map: hidden
            CLRA
HOVER5      STA  VC_DATA0
            DECB
            BNE  HOVER5
            LDA  CURATTR
            STA  VC_DATA0
            RTS
;------------------------------------------------------------------------------
; Cells.
;------------------------------------------------------------------------------
; MAPCELL: the cell under the mouse: carry clear and A = x, B = y if it is over
; the map; carry set if not.
MAPCELL     LDD  MOUSEX
            CMPD #VIEWW
            BHS  MAPCELL9
            JSR  LPIX
            ADDD SCRX
            BSR  CELLOF
            CMPD MAPW
            BHS  MAPCELL9
            STB  HCOL
            LDD  MOUSEY
            CMPD #VIEWH
            BHS  MAPCELL9
            JSR  LPIX
            ADDD SCRY
            BSR  CELLOF
            CMPD MAPH
            BHS  MAPCELL9
            LDA  HCOL
            ANDCC #$FE
            RTS
MAPCELL9    ORCC #$01
            RTS
; CELLOF: the layer's pixel D as a cell.
CELLOF      LDF  TSHIFT
CELLOF1     LSRD
            DECF
            BNE  CELLOF1
            RTS
; CELLADDR: A:X = where cell A = x, B = y is in video memory.
CELLADDR    PSHS D
            LDB  1,S            ; (y << MAPWSH) + x
            CLRA
            LDF  MAPWSH
CELLADDR1   LSLD
            DECF
            BNE  CELLADDR1
            ADDB ,S
            ADCA #0
            LSLD                ; 2 bytes a cell
            ADDD #MAPV&$FFFF
            TFR  D,X
            LDA  #MAPV/$10000
            LEAS 2,S
            RTS
; GETCELL: D = cell A = x, B = y.
GETCELL     BSR  CELLADDR
            JSR  PORT1
            LDA  VC_DATA1
            LDB  VC_DATA1
            RTS
; PUTCELL: cell A = x, B = y becomes MPEN.
PUTCELL     BSR  CELLADDR
            JSR  PORT0
            LDD  MPEN
            STA  VC_DATA0
            STB  VC_DATA0
            TST  MAPMOD
            BNE  PUTCELL9
            LDA  #1
            STA  MAPMOD
            STA  STATDIRTY
PUTCELL9    RTS
; MAPPEN: MPEN, the cell the tool puts down: 0 (tile 0, as a blank map is) with
; the right button or the eraser, else the tile picked, its flips, and (in a
; 16-color set) the color's row.
MAPPEN      CLRD
            STD  MPEN
            LDA  BUTTONS
            BITA #VC_MB_LEFT
            BEQ  MAPPEN9
            LDA  TOOL
            CMPA #TL_ERASE
            BEQ  MAPPEN9
            LDD  TILE
            ORA  FLIPS
            LDB  BPP
            CMPB #8
            BEQ  MAPPEN1
            LDB  COLOR
            ANDB #$F0
            PSHS B
            ORA  ,S+
MAPPEN1     LDB  TILE+1
            STD  MPEN
MAPPEN9     RTS
;------------------------------------------------------------------------------
; The tools on the map.
;------------------------------------------------------------------------------
; MPRESS: a button down over the map. The middle button grabs it to move it.
MPRESS      LDA  PRESSED
            BITA #VC_MB_MID
            BEQ  MPRESS1
            LDA  #R_PAN
            STA  DRAG
            LDD  MOUSEX
            STD  PANMX
            LDD  MOUSEY
            STD  PANMY
            LDD  SCRX
            STD  PANSX
            LDD  SCRY
            STD  PANSY
            RTS
MPRESS1     JSR  MAPCELL
            BCS  MPRESS9
            STD  LASTX
            STD  ANCX
            LDA  #1
            STA  INZOOM
            STA  FOCUS          ; (clear is for the map now)
            BSR  MAPPEN
            LDA  TOOL
            CMPA #TL_PICK
            BEQ  MPICK
            JSR  PUSHMAPU
            LDA  TOOL
            CMPA #TL_FILL
            BEQ  MFILLAT
            LDD  LASTX          ; pen, eraser, line: the first cell
            LBRA PUTCELL
MFILLAT     LDD  LASTX
            JMP  MFILL
MPRESS9     RTS
; MPICK: the cell under the mouse is what the pen puts down: its tile, flips
; and row.
MPICK       LDD  LASTX
            JSR  GETCELL
            PSHS D
            ANDA #$0C
            STA  FLIPS
            LDA  BPP            ; (the row: the color's, in the same place in it)
            CMPA #8
            BEQ  MPICK1
            LDA  ,S
            ANDA #$F0
            LDB  COLOR
            ANDB #$0F
            PSHS B
            ORA  ,S+
            TFR  A,B
            JSR  SELCOLOR
MPICK1      PULS D
            ANDA #$03
            CMPD NTILES
            BHS  MPICK2
            JSR  SELTILE
MPICK2      LDA  #1
            STA  STATDIRTY
            RTS
; MDRAG: a button held over (or off) the map.
MDRAG       LDA  TOOL
            CMPA #TL_FILL
            BEQ  MDRAG9
            JSR  MAPCELL
            BCS  MDRAGOFF
            CMPD LASTX
            BEQ  MDRAG9         ; (still the same cell)
            STD  ZNEW
            LDA  TOOL
            CMPA #TL_PICK
            BEQ  MDRAGPICK
            CMPA #TL_LINE
            BEQ  MLINE
            LDX  #PUTCELL       ; pen, eraser: a line from the last cell
            STX  PLOTV
            LDA  INZOOM
            BEQ  MDRAG1         ; (or a new start, back from off the map)
            LDD  LASTX
            STD  LX0
            LDD  ZNEW
            STD  LX1
            JSR  LINE
            BRA  MDRAG2
MDRAG1      LDD  ZNEW
            JSR  PUTCELL
MDRAG2      LDD  ZNEW
            STD  LASTX
            LDA  #1
            STA  INZOOM
MDRAG9      RTS
MDRAGOFF    CLR  INZOOM
            RTS
MDRAGPICK   STD  LASTX
            LBRA MPICK
MLINE       JSR  PEEKMAPU       ; the map as it was, then the line to here
            LDX  #PUTCELL
            STX  PLOTV
            LDD  ANCX
            STD  LX0
            LDD  ZNEW
            STD  LX1
            STD  LASTX
            JMP  LINE
; MPAN: the middle button held: the map moves with the mouse.
MPAN        LDD  PANMX          ; across: where it started less how far the mouse went
            SUBD MOUSEX
            JSR  LPIX2
            ADDD PANSX
            BPL  MPAN1
            CLRD
MPAN1       STD  SCRX
            LDD  PANMY
            SUBD MOUSEY
            JSR  LPIX2
            ADDD PANSY
            BPL  MPAN2
            CLRD
MPAN2       STD  SCRY
            JMP  MAPSCROLL
; LPIX2: D (signed) screen pixels in the layer's.
LPIX2       TST  SCLSH
            BEQ  LPIX29
            ASRD
LPIX29      RTS
; MFILL: from cell A = x, B = y, every cell like it that touches it (not
; diagonally) becomes MPEN: a row at a time, left to right, with a stack of the
; places above and below to go on from.
MFILL       STD  FX
            JSR  GETCELL
            CMPD MPEN
            LBEQ MFILL99        ; (it is that already)
            STD  FOLDC
            LDU  #MFSTACK
            LDD  FX
            STD  ,U++
MFILL1      CMPU #MFSTACK       ; the next place
            LBEQ MFILL99
            LDD  ,--U
            STD  FX
            JSR  GETCELL
            CMPD FOLDC
            BNE  MFILL1         ; (filled since)
MFILL2      LDA  FX             ; to the start of its row's stretch
            BEQ  MFILL3
            DECA
            LDB  FY
            JSR  GETCELL
            CMPD FOLDC
            BNE  MFILL3
            DEC  FX
            BRA  MFILL2
MFILL3      CLR  FUP            ; the stretch: each cell filled, and the rows
            CLR  FDOWN          ; above and below it looked at
MFILL4      LDD  FX
            JSR  GETCELL
            CMPD FOLDC
            BNE  MFILL1
            LDD  FX
            JSR  PUTCELL
            LDB  FY             ; above
            BEQ  MFILL6
            LDA  FX
            DECB
            LDX  #FUP
            BSR  MFLOOK
            LBCS MFILLFULL
MFILL6      LDB  FY             ; below
            CLRA
            ADDD #1
            CMPD MAPH
            BHS  MFILL7
            LDA  FX
            LDX  #FDOWN
            BSR  MFLOOK
            LBCS MFILLFULL
MFILL7      INC  FX             ; on along the row
            BEQ  MFILL1         ; (past 255)
            CLRA
            LDB  FX
            CMPD MAPW
            BLO  MFILL4
            LBRA MFILL1
; MFLOOK: cell A, B (above or below): the start of a stretch to fill? Then it
; is stacked (once a stretch: the flag at X). Carry set if the stack is full.
MFLOOK      PSHS D,X
            JSR  GETCELL
            CMPD FOLDC
            PULS D,X
            BEQ  MFLOOK1
            CLR  ,X             ; (not one: the next one like it starts a stretch)
            ANDCC #$FE
            RTS
MFLOOK1     TST  ,X
            BNE  MFLOOK9        ; (this stretch is stacked already)
            CMPU #MFSTACK+MFMAX*2
            BHS  MFLOOK8
            STD  ,U++
            LDA  #1
            STA  ,X
MFLOOK9     ANDCC #$FE
            RTS
MFLOOK8     ORCC #$01
            RTS
MFILLFULL   LDX  #T_FILLFULL
            JMP  MESSAGE
MFILL99     RTS
; MAPCLEAR: every cell 0.
MAPCLEAR    JSR  PUSHMAPU
            LDA  #C_FILL
            STA  VC_CMD
            LDA  #MAPV/$10000
            STA  VC_CMD
            LDD  #MAPV&$FFFF
            JSR  CMDD
            CLRA
            STA  VC_CMD
            LDD  MAPBYTES
            JSR  CMDD
            CLRA
            STA  VC_CMD
            JSR  WAITCMD
            LDA  #1
            STA  MAPMOD
            STA  STATDIRTY
            RTS
; MAPKEYS: the arrows (and Home) scroll the map a cell (with Shift, 8); A the
; key's usage code. Carry set if it wasn't one of them.
MAPKEYS     CMPA #K_HOME
            BNE  MAPKEYS1
            CLRD
            STD  SCRX
            STD  SCRY
            BRA  MAPKEYS8
MAPKEYS1    LDX  #SCRX          ; which way
            LDY  #-1
            CMPA #K_LEFT
            BEQ  MAPKEYS2
            LDY  #1
            CMPA #K_RIGHT
            BEQ  MAPKEYS2
            LDX  #SCRY
            LDY  #-1
            CMPA #K_UP
            BEQ  MAPKEYS2
            LDY  #1
            CMPA #K_DOWN
            BEQ  MAPKEYS2
            ORCC #$01
            RTS
MAPKEYS2    LDB  KEYMODS        ; how far: a cell, or 8 with Shift
            ANDB #VC_MOD_SHF
            STB  GK_T
            TFR  Y,D
            TST  GK_T
            BEQ  MAPKEYS3
            LSLD
            LSLD
            LSLD
MAPKEYS3    JSR  MPIX           ; (in the layer's pixels; signed)
            ADDD ,X
            BPL  MAPKEYS4
            CLRD
MAPKEYS4    STD  ,X             ; (MAPSCROLL keeps it in the map)
MAPKEYS8    JSR  MAPSCROLL
            ANDCC #$FE
            RTS
; MAPWHEEL: the wheel over the map scrolls it a cell a click (with Shift, across).
MAPWHEEL    LDB  WHEEL
            SEX
            PSHS D
            LDX  #SCRY
            LDA  KEYMODS
            BITA #VC_MOD_SHF
            BEQ  MAPWHEEL1
            LDX  #SCRX
MAPWHEEL1   PULS D
            JSR  MPIX           ; (signed: a whole number of cells)
            PSHS D
            LDD  ,X
            SUBD ,S++           ; away from you: towards the top
            BPL  MAPWHEEL2
            CLRD
MAPWHEEL2   STD  ,X
            JMP  MAPSCROLL
;------------------------------------------------------------------------------
; The map's undo steps: the whole map, copied by the card into its PSRAM.
;------------------------------------------------------------------------------
; PUSHMAPU: the map as it is, as the newest step.
PUSHMAPU    LDB  UHEAD
            LDX  #UTYPE
            LDA  #1
            STA  B,X
            BSR  MAPSLOT
            LDA  #C_COPY        ; video memory -> its slot
            STA  VC_CMD
            LDA  #MAPV/$10000
            STA  VC_CMD
            LDD  #MAPV&$FFFF
            JSR  CMDD
            BSR  SLOTOUT
            CLRA
            STA  VC_CMD
            LDD  MAPBYTES
            JSR  CMDD
            JSR  NEXTUNDO
            JMP  WAITCMD
; PEEKMAPU: the map as the newest step has it (a line being drawn starts again).
PEEKMAPU    LDB  UHEAD
            DECB
            ANDB #UNDOS-1
; MAPBACKU: the map as slot B has it.
MAPBACKU    BSR  MAPSLOT
            LDA  #C_COPY        ; its slot -> video memory
            STA  VC_CMD
            BSR  SLOTOUT
            LDA  #MAPV/$10000
            STA  VC_CMD
            LDD  #MAPV&$FFFF
            JSR  CMDD
            CLRA
            STA  VC_CMD
            LDD  MAPBYTES
            JSR  CMDD
            JMP  WAITCMD
; MAPSLOT: USLOT (3 bytes) = slot B's address in the PSRAM: PSUNDO + B * $8000.
MAPSLOT     CLR  USLOT+1
            CLR  USLOT+2
            TFR  B,A
            LSRA                ; (B / 2; carry: B odd)
            BCC  MAPSLOT1
            LDB  #$80
            STB  USLOT+1
MAPSLOT1    ADDA #PSUNDO/$10000
            STA  USLOT
            RTS
; SLOTOUT: USLOT to the command port.
SLOTOUT     LDA  USLOT
            STA  VC_CMD
            LDD  USLOT+1
            JMP  CMDD
