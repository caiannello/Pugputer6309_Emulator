;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 text editor
;    FILE: edit.asm
;
; EDIT.COM: a full-screen text editor for an ANSI (VT100 / xterm) terminal on
; the console, modelled on GNU nano 2.2 with only its elementary functions:
; a title bar, the text, a status line and two lines of shortcuts, and nano's
; keys (^ = Ctrl, M- = Alt, or Esc then the key):
;
;   ^G F1   help                     ^X F2   exit (asks to save a changed text)
;   ^O F3   write the file out       ^R F5   open a file ("Read File" into a
;                                            new buffer; Enter alone: empty)
;   ^W F6   search                   M-W     search again
;   ^K F9   cut the line / the marked text     ^U F10  paste ("uncut")
;   M-A ^^  set / unset the mark     M-6 M-^ copy the line / the marked text
;   M-\ M-| first line               M-/ M-? last line
;   ^Y F7 PgUp, ^V F8 PgDn   pages   ^C F11  where the cursor is
;   ^A Home, ^E End, ^P ^N ^B ^F and the arrows, ^D Del, ^H Backspace, ^L redraw
;
;   EDIT [file]     opens file (a name that doesn't exist yet is a new file)
;
; The text is a gap buffer in the RAM above the program (up to $EFFF). The cut
; buffer lives at the very top of that space and grows down, so the two share
; it: [ARENA_LO, GAPS) text before the cursor, [GAPS, GAPE) the gap, [GAPE,
; CUTLO) text after the cursor, [CUTLO, ARENA_HI) the cut buffer. Lines end in
; LF inside the buffer. A file's line endings are kept: one with bare LF stays
; that way, anything else (and a new file) is written with CR LF, like the rest
; of the system.
;
; A text too big for that space is only partly in it: the arena holds a window
; of the text around the cursor, and the rest is in the store, RAM pages above
; the program's 64KB (see "The window and the store"). So a text can be as big as
; the free RAM (up to 4MB), with at most 65535 lines.
;
; At 19200 baud a full repaint takes about a second, so the screen is kept up to
; date a row at a time (DIRTY), scrolling with insert / delete line inside a
; scroll region around the text. The terminal's size is asked for with the
; cursor-position report (ESC [ 6 n after moving to 999;999): at the start, on
; ^L, and whenever the keyboard goes quiet after some typing. A reply is handled
; whenever it arrives, as a K_RESIZE "key".
;------------------------------------------------------------------------------
    INCLUDE defines.d
;------------------------------------------------------------------------------
EDIT_BASE   equ  $3400             ; above DOS's RAM (DOS_END), where BASIC's range starts
ARENA_HI    equ  EXE_MAXTOP        ; the text arena ends below the ROM
MINROWS     equ  6
MINCOLS     equ  20
MAXROWS     equ  100
MAXCOLS     equ  250
TEXTTOP     equ  3                 ; screen row of the first text row (1 = title bar)
NAMEMAX     equ  64                ; longest file name / search string
OUTMAX      equ  200               ; output is sent with one B_PUT when this is full
MSGMAX      equ  100
STATMAX     equ  120
PTEXTMAX    equ  100
IDLEPOLLS   equ  5400              ; empty keyboard polls (about half a second at
                                   ; 3.58 MHz: a poll is about 330 cycles) after
                                   ; some typing before the size is asked for again
SIZEWAIT    equ  3200              ; polls to wait for the size reply at the start
                                   ; (about 0.3 s: a terminal answers in a few ms)
STACKSIZE   equ  384
GAPMIN      equ  4096              ; the window keeps this much gap (room to type) ...
GAPLOW      equ  2048              ; ... and is rearranged when the gap gets below this
STRESERVE   equ  4096              ; store space kept free, so the window can always move
MAXSP       equ  252               ; store pages at most (4MB, less banks 0..3)
RDMAX       equ  255               ; RDBYTE reads the text this many characters at a time
SCHUNK      equ  256               ; the search tries this many places per DOCCOPY
; Key codes from GETKEY, in A, with B = 1 for a Meta key (Alt, or Esc then the
; key; letters in upper case). Below $80 they are the characters themselves.
K_UP        equ  $80
K_DOWN      equ  $81
K_RIGHT     equ  $82
K_LEFT      equ  $83
K_HOME      equ  $84
K_END       equ  $85
K_PGUP      equ  $86
K_PGDN      equ  $87
K_DEL       equ  $88
K_INS       equ  $89
K_RESIZE    equ  $8A               ; the terminal reported its size (NEWROWS, NEWCOLS)
K_NONE      equ  $8B               ; nothing: an unknown sequence
K_F1        equ  $90               ; ... K_F12 = $9B
; PMODE: what the status line and the shortcut lines are for
PM_EDIT     equ  0
PM_TEXT     equ  1                 ; a question with an answer being typed (PBUF)
PM_YESNO    equ  2
PM_HELP     equ  3
;------------------------------------------------------------------------------
; VAR name,size: the next size bytes of RAM after the program (nothing of it is in
; edit.bin).
VAR         MACRO
\1          equ  VP
VP          SET  VP+\2
            ENDM
;------------------------------------------------------------------------------
    ORG  EDIT_BASE-EXE_HDRSIZE
    FDB  EXE_MAGIC                 ; the program header
    FDB  EDIT_BASE                 ; load address
    FDB  START                     ; entry
    FDB  0                         ; flags
;------------------------------------------------------------------------------
START       LDS  #STACKTOP
            LDX  #ZERO                 ; clear the variables
            LDY  #VARS
            LDW  #STACKB-VARS
            TFM  X,Y+
            LDA  #24                   ; until the terminal says otherwise
            STA  ROWS
            LDA  #80
            STA  COLS
            JSR  SIZEVARS
            JSR  STINIT
            LDD  #ARENA_HI             ; the cut buffer starts empty
            STD  CUTLO
            JSR  NEWBUF
            LDA  #B_ARGS               ; EDIT [file]
            SWI2
            LDY  #FILENAME
            JSR  GETWORD
            LDX  #S_ALTON              ; the terminal's alternate screen, if it has one
            JSR  OUTS
            JSR  SIZEQ
            JSR  WAITSIZE
            JSR  FULLREDRAW
            TST  FILENAME
            BEQ  MAINLOOP
            JSR  READFILE
;------------------------------------------------------------------------------
; The main loop: bring the screen up to date, then do one key.
;------------------------------------------------------------------------------
MAINLOOP    JSR  ENSUREWIN
            JSR  ENSUREVIS
            JSR  RENDER
            JSR  GETKEY
            CMPA #K_RESIZE
            BNE  ML_KEY
            JSR  ONRESIZE
            BRA  MAINLOOP
ML_KEY      CLR  MSGON                 ; a message lasts until the next key
            LDX  CURLINE
            STX  OLDLINE
            CLR  THISCUT
            CLR  UPDPREF
            JSR  DISPATCH
            LDA  THISCUT               ; cuts in a row collect in the cut buffer
            STA  LASTCUT
            TST  UPDPREF               ; a sideways move: up/down aim for this column
            BEQ  ML_MARK
            JSR  CALCX
            LDD  XCOL
            STD  PREFCOL
ML_MARK     TST  MARKON                ; the marked region changed on every line the
            BEQ  MAINLOOP              ; cursor passed
            LDD  OLDLINE
            LDX  CURLINE
            JSR  MARKRANGE
            BRA  MAINLOOP
;------------------------------------------------------------------------------
; A = a key, B = 1 if Meta: runs its command.
DISPATCH    TSTB
            BNE  DP_META
            CMPA #' '
            BLO  DP_TABLE
            CMPA #$7F
            BHS  DP_TABLE
            JMP  INSCHAR               ; a printable character
DP_META     LDX  #METATAB
            BRA  DP_LOOK
DP_TABLE    LDX  #KEYTAB
DP_LOOK     LDB  ,X
            CMPB #$FF
            BEQ  DP_NONE
            CMPA ,X
            BEQ  DP_GO
            LEAX 3,X
            BRA  DP_LOOK
DP_GO       JMP  [1,X]
DP_NONE     RTS
; The key, then its command.
KEYTAB      FCB  $01
            FDB  C_HOME                ; ^A
            FCB  $02
            FDB  C_LEFT                ; ^B
            FCB  $03
            FDB  C_CURPOS              ; ^C
            FCB  $04
            FDB  C_DEL                 ; ^D
            FCB  $05
            FDB  C_END                 ; ^E
            FCB  $06
            FDB  C_RIGHT               ; ^F
            FCB  $07
            FDB  C_HELP                ; ^G
            FCB  $08
            FDB  C_BKSP                ; ^H
            FCB  $09
            FDB  C_TAB                 ; ^I
            FCB  $0B
            FDB  C_CUT                 ; ^K
            FCB  $0C
            FDB  C_REFRESH             ; ^L
            FCB  CR
            FDB  C_ENTER               ; ^M
            FCB  $0E
            FDB  C_DOWN                ; ^N
            FCB  $0F
            FDB  C_WRITEOUT            ; ^O
            FCB  $10
            FDB  C_UP                  ; ^P
            FCB  $12
            FDB  C_OPEN                ; ^R
            FCB  $15
            FDB  C_PASTE               ; ^U
            FCB  $16
            FDB  C_PGDN                ; ^V
            FCB  $17
            FDB  C_WHEREIS             ; ^W
            FCB  $18
            FDB  C_EXIT                ; ^X
            FCB  $19
            FDB  C_PGUP                ; ^Y
            FCB  $1E
            FDB  C_MARK                ; ^^
            FCB  $7F
            FDB  C_BKSP                ; Backspace (DEL)
            FCB  K_UP
            FDB  C_UP
            FCB  K_DOWN
            FDB  C_DOWN
            FCB  K_LEFT
            FDB  C_LEFT
            FCB  K_RIGHT
            FDB  C_RIGHT
            FCB  K_HOME
            FDB  C_HOME
            FCB  K_END
            FDB  C_END
            FCB  K_PGUP
            FDB  C_PGUP
            FCB  K_PGDN
            FDB  C_PGDN
            FCB  K_DEL
            FDB  C_DEL
            FCB  K_F1
            FDB  C_HELP
            FCB  K_F1+1
            FDB  C_EXIT
            FCB  K_F1+2
            FDB  C_WRITEOUT
            FCB  K_F1+4
            FDB  C_OPEN
            FCB  K_F1+5
            FDB  C_WHEREIS
            FCB  K_F1+6
            FDB  C_PGUP
            FCB  K_F1+7
            FDB  C_PGDN
            FCB  K_F1+8
            FDB  C_CUT
            FCB  K_F1+9
            FDB  C_PASTE
            FCB  K_F1+10
            FDB  C_CURPOS
            FCB  $FF
METATAB     FCB  'A'
            FDB  C_MARK                ; M-A
            FCB  '6'
            FDB  C_COPY                ; M-6
            FCB  '^'
            FDB  C_COPY                ; M-^
            FCB  $5C
            FDB  C_TOP                 ; M-\ (backslash)
            FCB  '|'
            FDB  C_TOP                 ; M-|
            FCB  '/'
            FDB  C_BOTTOM              ; M-/
            FCB  '?'
            FDB  C_BOTTOM              ; M-?
            FCB  'W'
            FDB  C_SEARCHNEXT          ; M-W
            FCB  $FF
;------------------------------------------------------------------------------
; Moving around. The cursor is always at the gap; MOVEGAP moves it.
;------------------------------------------------------------------------------
C_LEFT      LDD  GAPS
            CMPD #ARENA_LO
            BEQ  CL_RET
            JSR  CURPOS
            SUBD #1
            JSR  MOVEGAP
            INC  UPDPREF
CL_RET      RTS
C_RIGHT     LDD  GAPE
            CMPD CUTLO
            BEQ  CR_RET
            JSR  CURPOS
            ADDD #1
            JSR  MOVEGAP
            INC  UPDPREF
CR_RET      RTS
C_HOME      JSR  LINESTART
            TFR  X,D
            SUBD #ARENA_LO
            JSR  MOVEGAP
            INC  UPDPREF
            RTS
C_END       JSR  AFTERLEN
            STD  TMPW
            JSR  CURPOS
            ADDD TMPW
            JSR  MOVEGAP
            INC  UPDPREF
            RTS
C_UP        JSR  PREVLINE
            BCS  CU_RET
            JMP  GOCOL
CU_RET      RTS
C_DOWN      JSR  NEXTLINE
            BCS  CU_RET
            JMP  GOCOL
C_TOP       CLRD
            CLRW
            BRA  TB_GO
C_BOTTOM    JSR  DOCLEN
TB_GO       STQ  GOTP
            JSR  GOTOABS
            INC  UPDPREF
            RTS
; A page is the text rows less two; the screen moves with the cursor.
C_PGUP      JSR  PAGEN
            STB  PGNS
            STB  PGN
PU_LOOP     JSR  ENSUREWIN             ; (a page may take the window along)
            JSR  PREVLINE
            BCS  PU_DONE
            DEC  PGN
            BNE  PU_LOOP
PU_DONE     JSR  GOCOL
            JSR  PAGEMOVED             ; D = lines moved
            BEQ  PU_RET
            STD  TMPW
            LDD  TOPLINE
            SUBD TMPW
            BHI  PU_TOP
            LDD  #1
PU_TOP      STD  TOPLINE
            JMP  MARKALL
PU_RET      RTS
C_PGDN      JSR  PAGEN
            STB  PGNS
            STB  PGN
PD_LOOP     JSR  ENSUREWIN
            JSR  NEXTLINE
            BCS  PD_DONE
            DEC  PGN
            BNE  PD_LOOP
PD_DONE     JSR  GOCOL
            JSR  PAGEMOVED
            BEQ  PU_RET
            ADDD TOPLINE
            STD  TOPLINE
            JMP  MARKALL
PAGEN       LDB  TROWS
            SUBB #2
            BLS  PN_ONE
            RTS
PN_ONE      LDB  #1
            RTS
PAGEMOVED   LDB  PGNS
            SUBB PGN
            CLRA
            TSTB
            RTS
;------------------------------------------------------------------------------
; Cursor to the start of the previous / next line; carry set if there is none.
PREVLINE    JSR  LINESTART
            CMPX #ARENA_LO
            BEQ  PL_NONE
            LEAX -1,X                  ; the LF that ends the line above
            JSR  LINEBACK
            TFR  X,D
            SUBD #ARENA_LO
            JSR  MOVEGAP
            ANDCC #$FE
            RTS
PL_NONE     ORCC #1
            RTS
NEXTLINE    JSR  AFTERLEN
            BCS  NL_NONE
            ADDD #1
            STD  TMPW
            JSR  CURPOS
            ADDD TMPW
            JSR  MOVEGAP
            ANDCC #$FE
NL_NONE     RTS
; From the start of a line, along it to the column PREFCOL (onto the character
; covering it, or the end of the line).
GOCOL       LDX  GAPE
            LDY  #0
GC_LOOP     CMPX CUTLO
            BHS  GC_DONE
            LDA  ,X
            CMPA #LF
            BEQ  GC_DONE
            JSR  ADVCOL
            CMPY PREFCOL
            BHI  GC_DONE
            LEAX 1,X
            BRA  GC_LOOP
GC_DONE     TFR  X,D
            SUBD GAPE
            BEQ  GC_RET
            ADDD GAPS
            SUBD #ARENA_LO
            JMP  MOVEGAP
GC_RET      RTS
;------------------------------------------------------------------------------
; The gap buffer.
;------------------------------------------------------------------------------
; -> D = the cursor's position in the text (characters before it).
CURPOS      LDD  GAPS
            SUBD #ARENA_LO
            RTS
; -> D = the length of the text.
TEXTLEN     LDD  CUTLO
            SUBD GAPE
            ADDD GAPS
            SUBD #ARENA_LO
            RTS
; D = a position in the text: moves the cursor (the gap) there. CURLINE follows.
MOVEGAP     PSHS D,X,Y
            PSHSW
            ADDD #ARENA_LO             ; where it is when it's before the gap
            STD  MGT
            CMPD GAPS
            BEQ  MG_RET
            BLO  MG_BACK
            SUBD GAPS                  ; forward: n characters from after the gap
            TFR  D,W                   ; go before it
            LDX  GAPE
            JSR  COUNTLF
            ADDD CURLINE
            STD  CURLINE
            LDX  GAPE
            LDY  GAPS
            TFM  X+,Y+
            STX  GAPE
            STY  GAPS
            BRA  MG_RET
MG_BACK     LDD  GAPS                  ; back: the n characters before the gap go
            SUBD MGT                   ; after it
            TFR  D,W
            LDX  MGT
            JSR  COUNTLF
            STD  TMP2
            LDD  CURLINE
            SUBD TMP2
            STD  CURLINE
            LDX  GAPS
            LEAX -1,X
            LDY  GAPE
            LEAY -1,Y
            TFM  X-,Y-
            LEAX 1,X
            LEAY 1,Y
            STX  GAPS
            STY  GAPE
MG_RET      PULSW
            PULS D,X,Y,PC
; X = an address, D = a count: -> D = the LFs among those bytes. Keeps X, Y, W.
COUNTLF     PSHS X,Y
            PSHSW
            TFR  D,Y
            CLRD
            CMPY #0
            BEQ  CF_DONE
CF_LOOP     LDE  ,X+
            CMPE #LF
            BNE  CF_NEXT
            ADDD #1
CF_NEXT     LEAY -1,Y
            BNE  CF_LOOP
CF_DONE     PULSW
            PULS X,Y,PC
; -> X = the start of the cursor's line (it is before the gap).
LINESTART   LDX  GAPS
; X = an address before the gap: back to the start of its line.
LINEBACK    CMPX #ARENA_LO
            BEQ  LB_RET
            LDA  -1,X
            CMPA #LF
            BEQ  LB_RET
            LEAX -1,X
            BRA  LINEBACK
LB_RET      RTS
; -> D = the characters from the cursor to the end of its line; carry set if the
; line has no LF (it's the last).
AFTERLEN    LDX  GAPE
AF_LOOP     CMPX CUTLO
            BHS  AF_END
            LDA  ,X
            CMPA #LF
            BEQ  AF_LF
            LEAX 1,X
            BRA  AF_LOOP
AF_LF       TFR  X,D
            SUBD GAPE
            ANDCC #$FE
            RTS
AF_END      TFR  X,D
            SUBD GAPE
            ORCC #1
            RTS
; Walking the text from X, skipping the gap: -> A = the next character, carry
; set at the end of the text.
NEXTCH      CMPX GAPS
            BNE  NC_1
            LDX  GAPE
NC_1        CMPX CUTLO
            BHS  NC_END
            LDA  ,X+
            ANDCC #$FE
            RTS
NC_END      ORCC #1
            RTS
; X = where NEXTCH is: -> D = the position of that character in the text.
LPOS        CMPX GAPS
            BHI  LP_AFTER
            TFR  X,D
            SUBD #ARENA_LO
            RTS
LP_AFTER    TFR  X,D
            SUBD GAPE
            ADDD GAPS
            SUBD #ARENA_LO
            RTS
; A = a character at display column Y: -> Y = the column after it (tabs every 8).
ADVCOL      CMPA #9
            BNE  AC_ONE
            TFR  Y,D
            ORB  #7
            ADDD #1
            TFR  D,Y
            RTS
AC_ONE      LEAY 1,Y
            RTS
; -> XCOL = the cursor's display column, PSTART = the first column shown of its
; line. A line too long for the screen is shown a page at a time: the page
; changes when the cursor reaches the last text column, and then keeps the
; cursor 7 columns in (as nano does).
CALCX       JSR  LINESTART
            LDY  #0
CX_LOOP     CMPX GAPS
            BEQ  CX_DONE
            LDA  ,X+
            JSR  ADVCOL
            BRA  CX_LOOP
CX_DONE     STY  XCOL
            LDB  COLS
            DECB
            CLRA
            CMPD XCOL
            BLS  CX_PAGE
            CLRD
            STD  PSTART
            RTS
CX_PAGE     LDB  COLS                  ; page width COLS-8
            SUBB #8
            CLRA
            STD  PW
            LDD  XCOL
            SUBD #7
            STD  TMPW
CX_MOD      CMPD PW
            BLO  CX_MODDED
            SUBD PW
            BRA  CX_MOD
CX_MODDED   STD  TMP2
            LDD  TMPW
            SUBD TMP2
            STD  PSTART
            RTS
; A new, empty text (the cut buffer is kept).
NEWBUF      LDD  #ARENA_LO
            STD  GAPS
            LDD  CUTLO
            STD  GAPE
            LDD  #1
            STD  CURLINE
            STD  NLINES
            STD  TOPLINE
            STD  DRAWNLINE
            CLRD
            STD  PREFCOL
            STD  DRAWNPS
            STD  MARKPOS
            STD  BLINES                ; nothing in the store
            STD  ALINES
            STD  BLEN
            STD  BLEN+2
            STD  ALEN
            STD  ALEN+2
            CLR  LFOVER
            CLR  MARKON
            CLR  MODIFIED
            CLR  LASTCUT
            LDA  #1
            STA  DOSFMT
            STA  TITLEDIRTY
            JMP  MARKALL
SETMOD      TST  MODIFIED
            BNE  SM_RET
            INC  MODIFIED
            INC  TITLEDIRTY
SM_RET      RTS
;------------------------------------------------------------------------------
; The window and the store. The arena holds a window of the text; the rest is in
; the store: RAM pages above the program's 64KB, up to NSP of them (B_PAGE_ALLOC'd
; the first time they are written, given back at the end). In the store's byte
; space [0, VTOP), [0, BLEN) is the text before the window, in order, and
; [VTOP-ALEN, VTOP) the text after it; BLINES and ALINES count their LFs.
; CURLINE, NLINES and TOPLINE count lines in the whole text, but positions
; (CURPOS, MOVEGAP, MARKPOS) are in the window. B_PAGE_COPY moves bytes between
; the store and the arena without touching the bank mapping. ENSUREWIN keeps the
; window around the cursor, before every key; GOTOABS moves it anywhere.
;------------------------------------------------------------------------------
; Finds the arena's pages and how big the store can be (the free pages).
STINIT      LDB  #1
SI_BANK     PSHS B
            LDA  #B_BANK_GET
            SWI2
            PULS B
            LDX  #ARPAGE
            STA  B,X
            INCB
            CMPB #4
            BLO  SI_BANK
            LDA  #B_PAGE_INFO          ; Y = the pages still free
            SWI2
            CMPY #MAXSP
            BLS  SI_NSP
            LDY  #MAXSP
SI_NSP      TFR  Y,D
            STB  NSP
            LSRB                       ; VTOP = NSP * 16KB
            LSRB
            CLRA
            STD  VTOP
            LDB  NSP
            ANDB #3
            LDA  #$40
            MUL
            TFR  B,A
            CLRB
            STD  VTOP+2
            RTS
; Gives the store's pages back.
STFREE      LDX  #STPAGES
            CLRA
SQ_LOOP     LDB  ,X+
            BEQ  SQ_NEXT
            PSHS A,X
            LDA  #B_PAGE_FREE
            SWI2
            PULS A,X
SQ_NEXT     INCA
            BNE  SQ_LOOP
            RTS
; A = a store page's index: -> A = the RAM page (taken now if it wasn't yet);
; carry set if there is none to take.
STPAGE      PSHS B,X
            LDX  #STPAGES
            TFR  A,B
            ABX
            LDA  ,X
            BNE  SP_OK
            LDA  #B_PAGE_ALLOC
            SWI2
            BCS  SP_RET
            STA  ,X
SP_OK       ANDCC #$FE
SP_RET      PULS B,X,PC
; Copies XLEN bytes between XRAM (an address in banks 1..3) and XVA (a place in
; the store): XDIR 0 from RAM to the store, 1 from the store to RAM. A piece at a
; time, so that neither side crosses a page. Carry set if a page couldn't be had.
XFER        LDD  XLEN
            LBEQ XF_OK
            LDA  XRAM                  ; the RAM side: its bank's page, the offset
            LSRA
            LSRA
            LSRA
            LSRA
            LSRA
            LSRA
            LDX  #ARPAGE
            LDA  A,X
            STA  XRP
            LDD  XRAM
            ANDA #$3F
            STD  XRO
            LDD  #$4000
            SUBD XRO
            STD  XC                    ; (the room left in that page)
            LDB  XVA+2                 ; the store side: page index = bits 14..21
            LSRB
            LSRB
            LSRB
            LSRB
            LSRB
            LSRB
            STB  TMPB
            LDA  XVA+1
            LSLA
            LSLA
            ORA  TMPB
            JSR  STPAGE
            BCS  XF_RET
            STA  XSP
            LDD  XVA+2
            ANDA #$3F
            STD  XSO
            LDD  #$4000
            SUBD XSO
            CMPD XC
            BHS  XF_C1
            STD  XC
XF_C1       LDD  XLEN
            CMPD XC
            BHS  XF_C2
            STD  XC
XF_C2       TST  XDIR
            BNE  XF_IN
            LDB  XRP                   ; RAM -> store
            LDE  XSP
            LDX  XRO
            LDY  XSO
            BRA  XF_GO
XF_IN       LDB  XSP                   ; store -> RAM
            LDE  XRP
            LDX  XSO
            LDY  XRO
XF_GO       LDU  XC
            LDA  #B_PAGE_COPY
            SWI2
            BCS  XF_RET
            LDD  XRAM
            ADDD XC
            STD  XRAM
            LDQ  XVA
            ADDW XC
            ADCD #0
            STQ  XVA
            LDD  XLEN
            SUBD XC
            STD  XLEN
            LBRA XFER
XF_OK       ANDCC #$FE
XF_RET      RTS
; D = n: the window's first n characters (all before the gap) go on the end of the
; store's front part. Carry set if the store can't take them (then nothing moves).
SPILLF      STD  SPN
            BEQ  SPF_OK
            LDX  #ARENA_LO
            JSR  COUNTLF
            STD  SPLF
            LDD  #ARENA_LO
            STD  XRAM
            LDQ  BLEN
            STQ  XVA
            LDD  SPN
            STD  XLEN
            CLR  XDIR
            JSR  XFER
            BCS  SPF_RET
            LDQ  BLEN
            ADDW SPN
            ADCD #0
            STQ  BLEN
            LDD  BLINES
            ADDD SPLF
            BCC  SPF_LINES
            INC  LFOVER                ; (over 65535 lines: can only happen reading)
SPF_LINES   STD  BLINES
            LDD  GAPS                  ; the rest before the gap moves down n
            SUBD #ARENA_LO
            SUBD SPN
            BEQ  SPF_MOVED
            TFR  D,W
            LDD  #ARENA_LO
            ADDD SPN
            TFR  D,X
            LDY  #ARENA_LO
            TFM  X+,Y+
SPF_MOVED   LDD  GAPS
            SUBD SPN
            STD  GAPS
            LDD  MARKPOS               ; and so do the positions kept in the window
            SUBD SPN
            STD  MARKPOS
            LDD  CPSAVE
            SUBD SPN
            STD  CPSAVE
SPF_OK      ANDCC #$FE
SPF_RET     RTS
; D = n (at most BLEN, and at most the gap): the last n characters of the store's
; front part come back to the start of the window.
FILLF       STD  SPN
            BEQ  FF_RET
            LDD  GAPS                  ; the text before the gap moves up n
            SUBD #ARENA_LO
            BEQ  FF_MOVED
            TFR  D,W
            LDX  GAPS
            LEAX -1,X
            TFR  X,D
            ADDD SPN
            TFR  D,Y
            TFM  X-,Y-
FF_MOVED    LDD  GAPS
            ADDD SPN
            STD  GAPS
            LDQ  BLEN
            SUBW SPN
            SBCD #0
            STQ  BLEN
            STQ  XVA
            LDD  #ARENA_LO
            STD  XRAM
            LDD  SPN
            STD  XLEN
            LDA  #1
            STA  XDIR
            JSR  XFER
            LDX  #ARENA_LO
            LDD  SPN
            JSR  COUNTLF
            STD  SPLF
            LDD  BLINES
            SUBD SPLF
            STD  BLINES
            LDD  MARKPOS
            ADDD SPN
            STD  MARKPOS
            LDD  CPSAVE
            ADDD SPN
            STD  CPSAVE
FF_RET      RTS
; D = n: the window's last n characters (all after the gap) go on the front of the
; store's back part. Carry set if the store can't take them (then nothing moves).
SPILLB      STD  SPN
            BEQ  SB_OK
            LDD  CUTLO
            SUBD SPN
            STD  XRAM
            TFR  D,X
            LDD  SPN
            JSR  COUNTLF
            STD  SPLF
            LDQ  VTOP
            SUBW ALEN+2
            SBCD ALEN
            SUBW SPN
            SBCD #0
            STQ  XVA
            LDD  SPN
            STD  XLEN
            CLR  XDIR
            JSR  XFER
            BCS  SB_RET
            LDQ  ALEN
            ADDW SPN
            ADCD #0
            STQ  ALEN
            LDD  ALINES
            ADDD SPLF
            STD  ALINES
            LDD  CUTLO                 ; the rest after the gap moves up n
            SUBD SPN
            SUBD GAPE
            BEQ  SB_MOVED
            TFR  D,W
            LDD  CUTLO
            SUBD SPN
            SUBD #1
            TFR  D,X
            LDY  CUTLO
            LEAY -1,Y
            TFM  X-,Y-
SB_MOVED    LDD  GAPE
            ADDD SPN
            STD  GAPE
SB_OK       ANDCC #$FE
SB_RET      RTS
; D = n (at most ALEN, and at most the gap): the first n characters of the store's
; back part come back to the end of the window.
FILLB       STD  SPN
            BEQ  FB_RET
            LDD  CUTLO                 ; the text after the gap moves down n
            SUBD GAPE
            BEQ  FB_MOVED
            TFR  D,W
            LDX  GAPE
            TFR  X,D
            SUBD SPN
            TFR  D,Y
            TFM  X+,Y+
FB_MOVED    LDD  GAPE
            SUBD SPN
            STD  GAPE
            LDQ  VTOP
            SUBW ALEN+2
            SBCD ALEN
            STQ  XVA
            LDD  CUTLO
            SUBD SPN
            STD  XRAM
            LDD  SPN
            STD  XLEN
            LDA  #1
            STA  XDIR
            JSR  XFER
            LDD  CUTLO
            SUBD SPN
            TFR  D,X
            LDD  SPN
            JSR  COUNTLF
            STD  SPLF
            LDD  ALINES
            SUBD SPLF
            STD  ALINES
            LDQ  ALEN
            SUBW SPN
            SBCD #0
            STQ  ALEN
FB_RET      RTS
; -> D = what the window may spill into the store: the free space less STRESERVE
; (kept for GOTOABS), at most $FFFF. SHIFTROOM: all the free space.
SPILLROOM   JSR  STOREFREE
            SUBW #STRESERVE
            SBCD #0
            BCC  CLAMPQ
            CLRD
            RTS
SHIFTROOM   JSR  STOREFREE
; Q = a 32-bit number: -> D = it, or $FFFF if it's bigger.
CLAMPQ      CMPD #0
            BNE  CQ_MAX
            TFR  W,D
            RTS
CQ_MAX      LDD  #$FFFF
            RTS
; -> Q = the store's free space.
STOREFREE   LDQ  VTOP
            SUBW BLEN+2
            SBCD BLEN
            SUBW ALEN+2
            SBCD ALEN
            RTS
; Q = a 32-bit number: Z set if it is 0.
ISZERO      CMPD #0
            BNE  IZ_RET
            CMPW #0
IZ_RET      RTS
; D = n: WANT = the smaller of WANT and n.
MINWANT     CMPD WANT
            BHS  MW_RET
            STD  WANT
MW_RET      RTS
; -> D = the gap a fill may take: all of it but GAPLOW.
GAPROOM     LDD  GAPE
            SUBD GAPS
            SUBD #GAPLOW
            BHI  GR_RET
            CLRD
GR_RET      RTS
; -> Q = the length of the whole text. CURABS: -> Q = the cursor's position in it.
DOCLEN      JSR  TEXTLEN
            STD  TMPW
            LDQ  BLEN
            ADDW ALEN+2
            ADCD ALEN
            BRA  DA_ADD
CURABS      JSR  CURPOS
            STD  TMPW
            LDQ  BLEN
DA_ADD      ADDW TMPW
            ADCD #0
            RTS
; Keeps the window around the cursor. When the gap runs low, or the text on one
; side of the cursor runs short while the store has more of it, each side is
; brought to HALF (what the arena holds with GAPMIN of gap), as far as the store
; allows. While the mark is set, the marked text stays in the window.
ENSUREWIN   LDD  CUTLO
            SUBD #ARENA_LO+GAPMIN
            BHI  EW_HALF
            CLRD
EW_HALF     LSRA
            RORB
            STD  HALF
            LSRA
            RORB
            STD  LOWM
            LDD  GAPE                  ; the gap running low?
            SUBD GAPS
            CMPD #GAPLOW
            BLO  EW_GO
            LDQ  BLEN                  ; the text before the cursor running short?
            JSR  ISZERO
            BEQ  EW_AFTER
            LDD  GAPS
            SUBD #ARENA_LO
            CMPD LOWM
            BLO  EW_GO
EW_AFTER    LDQ  ALEN                  ; or after it?
            JSR  ISZERO
            BEQ  EW_RET
            LDD  CUTLO
            SUBD GAPE
            CMPD LOWM
            BLO  EW_GO
EW_RET      RTS
EW_GO       LDD  GAPS                  ; more than HALF before the cursor: spill
            SUBD #ARENA_LO
            SUBD HALF
            BLS  EW_BACK
            STD  WANT
            JSR  SPILLROOM
            JSR  MINWANT
            TST  MARKON
            BEQ  EW_F1
            LDD  MARKPOS               ; (not past the mark)
            JSR  MINWANT
EW_F1       LDD  WANT
            JSR  SPILLF
EW_BACK     LDD  CUTLO                 ; more than HALF after it
            SUBD GAPE
            SUBD HALF
            BLS  EW_FILL
            STD  WANT
            JSR  SPILLROOM
            JSR  MINWANT
            TST  MARKON
            BEQ  EW_B1
            JSR  TEXTLEN               ; (not before the mark)
            SUBD MARKPOS
            JSR  MINWANT
EW_B1       LDD  WANT
            JSR  SPILLB
EW_FILL     LDD  GAPS                  ; less than HALF before it: fill from the store
            SUBD #ARENA_LO
            STD  TMPW
            LDD  HALF
            SUBD TMPW
            BLS  EW_FILLB
            STD  WANT
            LDQ  BLEN
            JSR  CLAMPQ
            JSR  MINWANT
            JSR  GAPROOM
            JSR  MINWANT
            LDD  WANT
            JSR  FILLF
EW_FILLB    LDD  CUTLO                 ; and after it
            SUBD GAPE
            STD  TMPW
            LDD  HALF
            SUBD TMPW
            BLS  EW_DONE
            STD  WANT
            LDQ  ALEN
            JSR  CLAMPQ
            JSR  MINWANT
            JSR  GAPROOM
            JSR  MINWANT
            LDD  WANT
            JMP  FILLB
EW_DONE     RTS
; D = n: makes the gap at least n, spilling text around it to the store if it has
; to (never past the mark). Carry set if it can't.
MAKEROOM    STD  MKN
            LDD  GAPS                  ; the text before the cursor first
            SUBD #ARENA_LO
            STD  WANT
            TST  MARKON
            BEQ  MM_1
            LDD  MARKPOS
            JSR  MINWANT
MM_1        JSR  SPILLROOM
            JSR  MINWANT
            JSR  NEEDGAP
            BEQ  MM_OK
            JSR  MINWANT
            LDD  WANT
            JSR  SPILLF
            LDD  CUTLO                 ; then the text after it
            SUBD GAPE
            STD  WANT
            TST  MARKON
            BEQ  MM_2
            JSR  TEXTLEN
            SUBD MARKPOS
            JSR  MINWANT
MM_2        JSR  SPILLROOM
            JSR  MINWANT
            JSR  NEEDGAP
            BEQ  MM_OK
            JSR  MINWANT
            LDD  WANT
            JSR  SPILLB
            JSR  NEEDGAP
            BEQ  MM_OK
            ORCC #1
            RTS
MM_OK       ANDCC #$FE
            RTS
; -> D = how much more gap MAKEROOM needs (Z set if none).
NEEDGAP     LDD  GAPE
            SUBD GAPS
            STD  MMT
            LDD  MKN
            SUBD MMT
            BHI  NG_RET
            CLRD
NG_RET      RTS
; GOTP = a position in the whole text: the cursor goes there. If it is outside
; the window, the window moves through the store to it, a step at a time: text
; from one end goes to the store and as much comes in at the other (the mark is
; dropped). CURLINE follows.
GOTOABS     LDQ  GOTP                  ; before the window?
            CMPD BLEN
            BLO  GA_BACK
            BHI  GA_REL
            CMPW BLEN+2
            BLO  GA_BACK
GA_REL      SUBW BLEN+2                ; Q = the place in the window
            SBCD BLEN
            CMPD #0
            BNE  GA_FWD
            STW  TMPW
            JSR  TEXTLEN
            CMPD TMPW
            BLO  GA_FWD                ; past its end
            LDD  TMPW
            JMP  MOVEGAP
GA_BACK     JSR  GA_NOMARK
            CLRD                       ; the window's text all after the gap
            JSR  MOVEGAP
            LDQ  BLEN                  ; GDIST = how far back to go
            SUBW GOTP+2
            SBCD GOTP
            JSR  CLAMPQ
            STD  GDIST
            STD  WANT
            JSR  SHIFTROOM             ; the window's end goes to the store ...
            JSR  MINWANT
            LDD  CUTLO
            SUBD GAPE
            JSR  MINWANT
            LDD  WANT
            JSR  SPILLB
            LDD  GDIST                 ; ... and the store's front part comes in
            STD  WANT
            LDQ  BLEN
            JSR  CLAMPQ
            JSR  MINWANT
            LDD  GAPE
            SUBD GAPS
            JSR  MINWANT
            LDD  WANT
            BEQ  GA_STUCK
            JSR  FILLF
            LBRA GOTOABS
GA_FWD      JSR  GA_NOMARK
            JSR  TEXTLEN               ; the window's text all before the gap
            JSR  MOVEGAP
            JSR  TEXTLEN               ; GDIST = how far past the window's end
            STD  TMPW
            LDQ  GOTP
            SUBW BLEN+2
            SBCD BLEN
            SUBW TMPW
            SBCD #0
            JSR  CLAMPQ
            STD  GDIST
            STD  WANT
            JSR  SHIFTROOM             ; the window's start goes to the store ...
            JSR  MINWANT
            LDD  GAPS
            SUBD #ARENA_LO
            JSR  MINWANT
            LDD  WANT
            JSR  SPILLF
            LDD  GDIST                 ; ... and the store's back part comes in
            STD  WANT
            LDQ  ALEN
            JSR  CLAMPQ
            JSR  MINWANT
            LDD  GAPE
            SUBD GAPS
            JSR  MINWANT
            LDD  WANT
            BEQ  GA_STUCK
            JSR  FILLB
            LBRA GOTOABS
GA_STUCK    RTS                        ; (no room at all to move in: it stays)
GA_NOMARK   TST  MARKON
            BEQ  GN_RET
            CLR  MARKON
            JMP  MARKALL
GN_RET      RTS
; Copies DCN characters of the whole text, from position DCP, to DCD (they must
; all be in the text). DCP and DCD move along; DCN ends at 0.
DOCCOPY     LDD  DCN
            LBEQ DY_RET
            LDQ  DCP
            CMPD BLEN                  ; in the store's front part?
            BLO  DY_FRONT
            BHI  DY_WIN
            CMPW BLEN+2
            BHS  DY_WIN
DY_FRONT    STQ  XVA
            LDQ  BLEN                  ; (up to its end)
            SUBW DCP+2
            SBCD DCP
            JSR  CLAMPQ
            LBRA DY_STORE
DY_WIN      SUBW BLEN+2                ; the place in the window
            SBCD BLEN
            CMPD #0
            BNE  DY_BACK
            STW  DYREL
            LDD  GAPS                  ; before the gap?
            SUBD #ARENA_LO
            CMPD DYREL
            BLS  DY_NOTB
            SUBD DYREL
            STD  DYLEN
            LDD  #ARENA_LO
            ADDD DYREL
            BRA  DY_RAM
DY_NOTB     STD  TMPW                  ; after it?
            LDD  DYREL
            SUBD TMPW
            STD  DYREL
            LDD  CUTLO
            SUBD GAPE
            CMPD DYREL
            BLS  DY_BACK
            SUBD DYREL
            STD  DYLEN
            LDD  GAPE
            ADDD DYREL
DY_RAM      TFR  D,X                   ; in the arena: copied from X
            LDD  DYLEN
            CMPD DCN
            BLS  DY_R1
            LDD  DCN
DY_R1       STD  DYLEN
            TFR  D,W
            LDY  DCD
            TFM  X+,Y+
            BRA  DY_NEXT
DY_BACK     JSR  TEXTLEN               ; in the store's back part: VTOP - ALEN +
            STD  TMPW                  ; (DCP - BLEN - the window's text)
            LDQ  DCP
            SUBW BLEN+2
            SBCD BLEN
            SUBW TMPW
            SBCD #0
            ADDW VTOP+2
            ADCD VTOP
            SUBW ALEN+2
            SBCD ALEN
            STQ  XVA
            LDD  DCN
DY_STORE    CMPD DCN                   ; D = what there is: at most DCN
            BLS  DY_S1
            LDD  DCN
DY_S1       STD  DYLEN
            STD  XLEN
            LDD  DCD
            STD  XRAM
            LDA  #1
            STA  XDIR
            JSR  XFER
DY_NEXT     LDQ  DCP
            ADDW DYLEN
            ADCD #0
            STQ  DCP
            LDD  DCD
            ADDD DYLEN
            STD  DCD
            LDD  DCN
            SUBD DYLEN
            STD  DCN
            LBRA DOCCOPY
DY_RET      RTS
; The whole text a character at a time (for SAVEFILE): RDSTART, then RDBYTE ->
; A = the next character; carry set at the end. RDBYTE keeps B, X, Y, U and W.
RDSTART     CLRD
            STD  RDPOS
            STD  RDPOS+2
            CLR  RDI
            CLR  RDN
            RTS
RDBYTE      PSHS B,X,Y,U
            PSHSW
            LDB  RDI
            CMPB RDN
            BLO  RB_HAVE
            JSR  DOCLEN                ; RDBUF is used up: the next RDMAX (or what's left)
            SUBW RDPOS+2
            SBCD RDPOS
            JSR  CLAMPQ
            CMPD #RDMAX
            BLS  RB_N
            LDD  #RDMAX
RB_N        TSTB
            BEQ  RB_END
            STB  RDN
            STD  DCN
            LDQ  RDPOS
            STQ  DCP
            LDD  #RDBUF
            STD  DCD
            JSR  DOCCOPY
            LDQ  DCP
            STQ  RDPOS
            CLRB
            STB  RDI
RB_HAVE     LDX  #RDBUF
            ABX
            LDA  ,X
            INC  RDI
            PULSW
            ANDCC #$FE
            PULS B,X,Y,U,PC
RB_END      PULSW
            ORCC #1
            PULS B,X,Y,U,PC
;------------------------------------------------------------------------------
; Editing.
;------------------------------------------------------------------------------
C_ENTER     LDA  #LF
            BRA  INSCHAR
C_TAB       LDA  #9
; A = a character: typed in at the cursor.
INSCHAR     STA  ICH
            CMPA #LF                   ; (65535 lines at most)
            BNE  IC_GAP
            LDD  NLINES
            CMPD #$FFFF
            BEQ  IC_NOMEM
IC_GAP      LDD  GAPE
            CMPD GAPS
            BNE  IC_ROOM
            LDD  #1                    ; the gap is full: some text to the store
            JSR  MAKEROOM
            BCC  IC_ROOM
IC_NOMEM    LDX  #M_NOMEM
            JMP  SETMSG
IC_ROOM     TST  MARKON                ; a mark after the cursor moves along
            BEQ  IC_PUT
            JSR  CURPOS
            CMPD MARKPOS
            BHS  IC_PUT
            LDD  MARKPOS
            ADDD #1
            STD  MARKPOS
IC_PUT      LDX  GAPS
            LDA  ICH
            STA  ,X+
            STX  GAPS
            JSR  SETMOD
            INC  UPDPREF
            CMPA #LF
            BEQ  IC_NL
            LDD  CURLINE
            JMP  MARKLINE
IC_NL       LDD  NLINES
            ADDD #1
            STD  NLINES
            LDD  CURLINE
            STD  TMPW                  ; the line that was split
            ADDD #1
            STD  CURLINE
            LDD  TMPW
            SUBD TOPLINE
            INCB                       ; the new line's row
            CMPB TROWS
            BHS  IC_NLBOT
            TFR  B,A                   ; open a row for it
            JSR  SCR_IL
            LDD  TMPW
            JMP  MARKLINE
IC_NLBOT    LDD  TMPW                  ; it's below the screen: it will scroll
            JMP  MARKFROM
C_BKSP      LDD  GAPS
            CMPD #ARENA_LO
            BEQ  BK_RET
            TST  MARKON
            BEQ  BK_DEL
            JSR  CURPOS
            CMPD MARKPOS
            BHI  BK_DEL                ; the mark is before the character going
            LDD  MARKPOS
            SUBD #1
            STD  MARKPOS
BK_DEL      LDX  GAPS
            LDA  ,-X
            STX  GAPS
            STA  ICH
            JSR  SETMOD
            INC  UPDPREF
            CMPA #LF
            BEQ  BK_NL
            LDD  CURLINE
            JMP  MARKLINE
BK_NL       LDD  NLINES                ; two lines joined
            SUBD #1
            STD  NLINES
            LDD  CURLINE
            SUBD TOPLINE
            STD  TMPW                  ; the row of the line that went
            LDD  CURLINE
            SUBD #1
            STD  CURLINE
            LDD  TMPW
            BEQ  BK_TOP
            TFR  B,A
            JSR  SCR_DL
            LDD  CURLINE
            JMP  MARKLINE
BK_TOP      JMP  MARKALL               ; joined onto the line above the screen
BK_RET      RTS
C_DEL       LDD  GAPE
            CMPD CUTLO
            BEQ  DE_RET
            TST  MARKON
            BEQ  DE_DEL
            JSR  CURPOS
            CMPD MARKPOS
            BHS  DE_DEL
            LDD  MARKPOS
            SUBD #1
            STD  MARKPOS
DE_DEL      LDX  GAPE
            LDA  ,X+
            STX  GAPE
            STA  ICH
            JSR  SETMOD
            CMPA #LF
            BNE  DE_LINE
            LDD  NLINES                ; the next line joins this one
            SUBD #1
            STD  NLINES
            LDD  CURLINE
            SUBD TOPLINE
            INCB
            CMPB TROWS
            BHS  DE_LINE
            TFR  B,A
            JSR  SCR_DL
DE_LINE     LDD  CURLINE
            JMP  MARKLINE
DE_RET      RTS
;------------------------------------------------------------------------------
; The mark, cut, copy and paste. Without the mark, ^K and M-6 take the whole line;
; with it, the text between the mark and the cursor. Cuts in a row add to the cut
; buffer; anything else in between starts it afresh.
;------------------------------------------------------------------------------
C_MARK      TST  MARKON
            BNE  MK_OFF
            INC  MARKON
            JSR  CURPOS
            STD  MARKPOS
            LDX  #M_MARKSET
            JMP  SETMSG
MK_OFF      JSR  MARKREGION
            CLR  MARKON
            LDX  #M_MARKUNSET
            JMP  SETMSG
; -> MLO, MHI = the marked region.
MARKBOUNDS  JSR  CURPOS
            CMPD MARKPOS
            BLS  MB_CURLO
            STD  MHI
            LDD  MARKPOS
            STD  MLO
            RTS
MB_CURLO    STD  MLO
            LDD  MARKPOS
            STD  MHI
            RTS
; Marks for redrawing the rows from the mark's line to the cursor's.
MARKREGION  JSR  CURPOS
            CMPD MARKPOS
            BHS  MR_BEFORE
            STD  TMPW                  ; the mark is after the cursor
            LDD  MARKPOS
            SUBD TMPW
            LDX  GAPE
            JSR  COUNTLF
            ADDD CURLINE
            BRA  MR_GO
MR_BEFORE   SUBD MARKPOS               ; the mark is before it
            LDX  MARKPOS
            LEAX ARENA_LO,X
            JSR  COUNTLF
            STD  TMPW
            LDD  CURLINE
            SUBD TMPW
MR_GO       LDX  CURLINE
            JMP  MARKRANGE
C_CUT       INC  THISCUT
            TST  MARKON
            BNE  CT_MARK
            JSR  LINESTART
            TFR  X,D
            SUBD #ARENA_LO
            JSR  MOVEGAP
            INC  UPDPREF
            JSR  AFTERLEN
            BCS  CT_LAST
            ADDD #1                    ; the line and its LF
            STD  CTN
            JSR  CT_TAKE
            LDD  CURLINE               ; the lines below move up
            SUBD TOPLINE
            TFR  B,A
            JSR  SCR_DL
            LDD  CURLINE
            JMP  MARKLINE
CT_LAST     STD  CTN                   ; the last line: what there is of it
            BEQ  CT_RET
            JSR  CT_TAKE
            LDD  CURLINE
            JMP  MARKLINE
CT_RET      RTS
CT_TAKE     JSR  PREPCUT
            CLR  COPYONLY
            LDD  CTN
            JSR  TAKE
            JMP  SETMOD
CT_MARK     JSR  MARKBOUNDS
            CLR  MARKON
            LDD  MHI
            SUBD MLO
            STD  CTN
            LDD  MLO
            JSR  MOVEGAP
            INC  UPDPREF
            LDD  CTN
            BEQ  CT_MDONE
            JSR  CT_TAKE
CT_MDONE    LDD  CURLINE
            JMP  MARKFROM
C_COPY      INC  THISCUT
            TST  MARKON
            BNE  CO_MARK
            JSR  LINESTART
            TFR  X,D
            SUBD #ARENA_LO
            JSR  MOVEGAP
            INC  UPDPREF
            JSR  AFTERLEN
            BCS  CO_LAST
            ADDD #1
CO_LAST     STD  CTN
            BEQ  CO_RET
            JSR  CO_TAKE
            BCS  CO_RET
            JMP  NEXTLINE              ; on to the next line, for another M-6
CO_RET      RTS
CO_MARK     JSR  MARKREGION            ; the highlight goes
            JSR  MARKBOUNDS
            CLR  MARKON
            LDD  MHI
            SUBD MLO
            STD  CTN
            BEQ  CO_RET
            JSR  CURPOS
            STD  CPSAVE
            LDD  MLO
            JSR  MOVEGAP
            JSR  CO_TAKE
            LDD  CPSAVE
            JMP  MOVEGAP
CO_TAKE     JSR  PREPCUT
            LDD  CTN                   ; the gap must hold the copy
            JSR  MAKEROOM
            BCS  CO_NOMEM
            INC  COPYONLY
            LDD  CTN
            JSR  TAKE
            CLR  COPYONLY
            ANDCC #$FE
            RTS
CO_NOMEM    LDX  #M_NOMEM
            JSR  SETMSG
            ORCC #1
            RTS
C_PASTE     LDD  #ARENA_HI
            SUBD CUTLO
            BEQ  PA_RET
            STD  CTN
            LDX  CUTLO
            JSR  COUNTLF
            STD  TKLF
            ADDD NLINES                ; (65535 lines at most)
            BCS  PA_NOMEM
            LDD  CTN
            JSR  MAKEROOM
            BCS  PA_NOMEM
            TST  MARKON
            BEQ  PA_COPY
            JSR  CURPOS
            CMPD MARKPOS
            BHS  PA_COPY
            LDD  MARKPOS
            ADDD CTN
            STD  MARKPOS
PA_COPY     LDX  CUTLO
            LDY  GAPS
            LDW  CTN
            TFM  X+,Y+
            STY  GAPS
            LDD  NLINES
            ADDD TKLF
            STD  NLINES
            LDD  CURLINE
            STD  TMPW
            ADDD TKLF
            STD  CURLINE
            JSR  SETMOD
            INC  UPDPREF
            LDD  TKLF
            BNE  PA_LINES
            LDD  CURLINE
            JMP  MARKLINE
PA_LINES    LDD  TMPW
            JMP  MARKFROM
PA_NOMEM    LDX  #M_NOMEM
            JMP  SETMSG
PA_RET      RTS
PREPCUT     TST  LASTCUT
            BEQ  CLEARCUT
            RTS
; Empties the cut buffer: the text after the gap moves up over it.
CLEARCUT    LDD  #ARENA_HI
            SUBD CUTLO
            BEQ  CC_RET
            STD  TMPW
            LDD  CUTLO
            SUBD GAPE
            BEQ  CC_MOVED
            TFR  D,W
            LDX  CUTLO
            LEAX -1,X
            LDY  #ARENA_HI-1
            TFM  X-,Y-
CC_MOVED    LDD  GAPE
            ADDD TMPW
            STD  GAPE
            LDD  #ARENA_HI
            STD  CUTLO
CC_RET      RTS
; D = n: the n characters just after the cursor go on the end of the cut buffer
; -- and out of the text, unless COPYONLY (then the caller has checked that the
; gap has room for them: gap >= n).
TAKE        STD  TKN
            LDX  GAPE
            JSR  COUNTLF
            STD  TKLF
            LDD  GAPE
            SUBD GAPS
            CMPD TKN
            BLO  TK_ROTATE
            LDX  GAPE                  ; the gap has room: everything after it (the
            TFR  X,D                   ; text, then the cut buffer) slides down n
            SUBD TKN
            TFR  D,Y
            LDD  #ARENA_HI
            SUBD GAPE
            TFR  D,W
            TFM  X+,Y+
            LDD  GAPE
            SUBD TKN
            STD  GAPE
            LDD  CUTLO
            SUBD TKN
            STD  CUTLO
            LDX  GAPE                  ; and a copy of the n characters (now at the
            LDD  #ARENA_HI             ; gap's end) goes in the space freed at the top
            SUBD TKN
            TFR  D,Y
            LDW  TKN
            TFM  X+,Y+
            TST  COPYONLY
            BNE  TK_RET
            LDD  GAPE                  ; cutting: out of the text
            ADDD TKN
            STD  GAPE
            BRA  TK_LINES
TK_ROTATE   LDX  GAPE                  ; (only when cutting) no room: rotate them to
            LDD  GAPE                  ; the top in place -- [GAPE, ARENA_HI) =
            ADDD TKN                   ; taken, rest of text, cut buffer becomes
            TFR  D,Y                   ; rest of text, cut buffer, taken
            JSR  REVERSE
            TFR  Y,X
            LDY  #ARENA_HI
            JSR  REVERSE
            LDX  GAPE
            JSR  REVERSE
            LDD  CUTLO
            SUBD TKN
            STD  CUTLO
TK_LINES    LDD  NLINES
            SUBD TKLF
            STD  NLINES
TK_RET      RTS
; Reverses the bytes [X, Y). Keeps X and Y.
REVERSE     PSHS D,X,Y
RV_LOOP     LEAY -1,Y
            PSHS Y
            CMPX ,S++
            BHS  RV_DONE
            LDA  ,X
            LDB  ,Y
            STB  ,X+
            STA  ,Y
            BRA  RV_LOOP
RV_DONE     PULS D,X,Y,PC
;------------------------------------------------------------------------------
; Searching: nano's ^W (case doesn't matter) and M-W.
;------------------------------------------------------------------------------
C_WHEREIS   LDY  #PTEXT                ; "Search [last]: "
            LDX  #P_SEARCH
            JSR  STRCPY
            TST  SEARCHSTR
            BEQ  WI_COLON
            LDX  #P_LBR
            JSR  STRCPY
            LDX  #SEARCHSTR
            JSR  STRCPY
            LDX  #P_RBR
            JSR  STRCPY
WI_COLON    LDX  #P_COLON
            JSR  STRCPY
            CLR  PBUF
            JSR  PROMPT
            LBCS WI_CANCEL
            TST  PBUF
            BNE  WI_NEW
            TST  SEARCHSTR             ; Enter alone: the last one again
            BEQ  WI_CANCEL
            BRA  DOSEARCH
WI_NEW      LDX  #PBUF
            LDY  #SEARCHSTR
            JSR  STRCPY
            BRA  DOSEARCH
WI_CANCEL   LDX  #M_CANCELLED
            JMP  SETMSG
C_SEARCHNEXT TST SEARCHSTR
            BNE  DOSEARCH
            LDX  #M_NOPATTERN
            JMP  SETMSG
; From just after the cursor to the end, then from the start round to the cursor.
; Positions here are in the whole text (32 bits), and the window moves to a find.
DOSEARCH    LDX  #SEARCHSTR
            JSR  STRLEN
            STD  SPLEN
            JSR  CURABS
            STQ  SSAVE
            JSR  DOCLEN
            SUBW SPLEN
            SBCD #0
            LBCS SE_NOTFOUND           ; longer than the text
            STQ  SLAST                 ; the last place it could start
            LDQ  SSAVE
            ADDW #1
            ADCD #0
            STQ  SFROM
            LDQ  SLAST
            STQ  STO
            JSR  SCANRANGE
            BCC  SE_GO
            CLRD                       ; round from the start
            CLRW
            STQ  SFROM
            LDQ  SSAVE                 ; to the cursor (or SLAST, if that's sooner)
            CMPD SLAST
            BLO  SE_WTO
            BHI  SE_LAST
            CMPW SLAST+2
            BLS  SE_WTO
SE_LAST     LDQ  SLAST
SE_WTO      STQ  STO
            JSR  SCANRANGE
            BCS  SE_NOTFOUND
            LDX  #M_WRAPPED
            LDQ  SFOUND
            CMPD SSAVE
            BNE  SE_MSG
            CMPW SSAVE+2
            BNE  SE_MSG
            LDX  #M_ONLYONE
SE_MSG      JSR  SETMSG
SE_GO       LDQ  SFOUND
            STQ  GOTP
            JSR  GOTOABS
            INC  UPDPREF
            RTS
SE_NOTFOUND JSR  MB_START
            LDX  #M_QUOTE
            JSR  MB_STR
            LDX  #SEARCHSTR
            JSR  MB_STR
            LDX  #M_NOTFOUND
            JSR  MB_STR
            JMP  MB_END
; The first position from SFROM to STO (both included) where SEARCHSTR starts:
; -> SFOUND, carry clear; carry set if none. The text is copied into SBUF for
; SCHUNK places at a time (and the SPLEN-1 characters the last one needs).
SCANRANGE   LDQ  STO                   ; places left: STO - SFROM + 1
            SUBW SFROM+2
            SBCD SFROM
            BCS  SR_NONE
            ADDW #1
            ADCD #0
            JSR  CLAMPQ
            CMPD #SCHUNK
            BLS  SR_N
            LDD  #SCHUNK
SR_N        STD  SRN
            ADDD SPLEN
            SUBD #1
            STD  DCN
            LDQ  SFROM
            STQ  DCP
            LDD  #SBUF
            STD  DCD
            JSR  DOCCOPY
            LDX  #SBUF
            LDY  SRN
SR_LOOP     JSR  MATCHAT
            BEQ  SR_HIT
            LEAX 1,X
            LEAY -1,Y
            BNE  SR_LOOP
            LDQ  SFROM
            ADDW SRN
            ADCD #0
            STQ  SFROM
            BRA  SCANRANGE
SR_HIT      TFR  X,D
            SUBD #SBUF
            STD  TMPW
            LDQ  SFROM
            ADDW TMPW
            ADCD #0
            STQ  SFOUND
            ANDCC #$FE
            RTS
SR_NONE     ORCC #1
            RTS
; Z set if SEARCHSTR is at X. Keeps D and X.
MATCHAT     PSHS D,X,Y
            LDY  #SEARCHSTR
MA_LOOP     LDA  ,Y+
            BEQ  MA_RET                ; (Z set)
            JSR  UPCASE
            STA  TMPB
            LDA  ,X+
            JSR  UPCASE
            CMPA TMPB
            BEQ  MA_LOOP
MA_RET      PULS D,X,Y,PC
;------------------------------------------------------------------------------
; Files.
;------------------------------------------------------------------------------
C_WRITEOUT  JMP  WRITEOUT
; Asks for the name to write to (the file's own, to start with) and writes the
; text there. Carry set if it wasn't written.
WRITEOUT    LDX  #FILENAME
            LDY  #PBUF
            JSR  STRCPY
            LDX  #P_WRITE
            LDY  #PTEXT
            JSR  STRCPY
            JSR  PROMPT
            BCS  WO_CANCEL
            TST  PBUF
            BEQ  WO_CANCEL
            LDX  #PBUF                 ; another file that is already there: ask
            LDY  #FILENAME
            JSR  STRCMPI
            BEQ  WO_WRITE
            LDX  #PBUF
            LDY  #STATBUF
            LDA  #B_STAT
            SWI2
            BCS  WO_WRITE
            LDX  #P_OVERWRITE
            JSR  ASKYN
            CMPA #'Y'
            BNE  WO_CANCEL
WO_WRITE    JSR  SAVEFILE
            BCS  WO_ERR
            LDX  #PBUF
            LDY  #FILENAME
            JSR  STRCPY
            CLR  MODIFIED
            INC  TITLEDIRTY
            JSR  MB_START
            LDX  #M_WROTE
            JSR  MB_STR
            LDD  NLW
            JSR  MB_LINES
            JSR  MB_END
            ANDCC #$FE
            RTS
WO_ERR      PSHS A
            JSR  MB_START
            LDX  #M_ERRWRITE
            JSR  MB_STR
            LDX  #PBUF
            JSR  MB_STR
            LDX  #M_COLON
            JSR  MB_STR
            PULS A
            JSR  MB_ERR
            JSR  MB_END
            ORCC #1
            RTS
WO_CANCEL   LDX  #M_CANCELLED
            JSR  SETMSG
            ORCC #1
            RTS
C_EXIT      TST  MODIFIED
            BEQ  QUIT
            JSR  ASKSAVE
            BCS  EX_RET
QUIT        JSR  STFREE                ; the store's pages go back
            LDX  #S_QUIT
            JSR  OUTS
            JSR  FLUSH
            LDA  #B_EXIT
            SWI2
EX_RET      RTS
; "Save modified buffer?" -- Yes writes it out. Carry set if the text should stay
; (cancelled, or not written).
ASKSAVE     LDX  #P_SAVEMOD
            JSR  ASKYN
            TSTA
            BEQ  WO_CANCEL
            CMPA #'N'
            BEQ  AS_OK
            JMP  WRITEOUT
AS_OK       ANDCC #$FE
            RTS
; ^R: nano's "Read File" into a new buffer -- here, the file replaces the text.
C_OPEN      TST  MODIFIED
            BEQ  OP_ASK
            JSR  ASKSAVE
            BCS  OP_RET
OP_ASK      CLR  PBUF
            LDX  #P_OPEN
            LDY  #PTEXT
            JSR  STRCPY
            JSR  PROMPT
            LBCS WI_CANCEL
            TST  PBUF
            BNE  OP_FILE
            JSR  NEWBUF                ; Enter alone: an empty new buffer
            CLR  FILENAME
            RTS
OP_FILE     LDX  #PBUF
            LDY  #FILENAME
            JSR  STRCPY
            JMP  READFILE
OP_RET      RTS
; LOADFILE with "Reading File" showing meanwhile (a big file takes a second or so).
READFILE    LDX  #M_READING
            JSR  SETMSG
            JSR  RENDER
            JSR  FLUSH
; Reads FILENAME into a new text. A file that isn't there is a new file.
LOADFILE    JSR  NEWBUF
            LDX  #FILENAME
            LDE  #FOPEN_READ
            LDA  #B_FOPEN_NAME
            SWI2
            BCC  LD_OPEN
            CMPA #ERR_NOTFOUND
            BNE  LD_ERR
            LDX  #M_NEWFILE
            JMP  SETMSG
LD_ERR      PSHS A                     ; "Error reading NAME: why"
            JSR  MB_START
            LDX  #M_ERRREAD
            JSR  MB_STR
            LDX  #FILENAME
            JSR  MB_STR
            LDX  #M_COLON
            JSR  MB_STR
            PULS A
            JSR  MB_ERR
            JSR  MB_END
            CLR  FILENAME              ; so ^O can't write over it by accident
            RTS
LD_OPEN     STA  FH
            CLR  LASTCR
            CLR  SAWLF
            CLR  SAWCRLF
            LDA  #LF                   ; (an empty file has no last line to end)
            STA  LASTLD
LD_READ     LDB  FH
            LDX  #IOBUF
            LDY  #512
            LDA  #B_FREAD
            SWI2
            BCS  LD_RDERR
            CMPX #0
            BEQ  LD_EOF
            TFR  X,W
            LDX  #IOBUF
            LDY  GAPS
LD_BYTE     LDA  ,X+                   ; CR LF, CR and LF all become LF
            CMPA #CR
            BEQ  LD_CR
            CMPA #LF
            BEQ  LD_LF
            CLR  LASTCR
            BRA  LD_PUT
LD_CR       LDB  #1
            STB  LASTCR
            LDA  #LF
            BRA  LD_PUT
LD_LF       TST  LASTCR
            BEQ  LD_BARE
            CLR  LASTCR                ; the LF of a CR LF: already there
            LDB  #1
            STB  SAWCRLF
            BRA  LD_NEXT
LD_BARE     LDB  #1
            STB  SAWLF
LD_PUT      CMPY GAPE
            BLO  LD_STORE
            STY  GAPS                  ; the window is full: its text goes to the store
            JSR  LD_SPILL
            BCS  LD_FULL
            LDY  GAPS
LD_STORE    STA  ,Y+
            STA  LASTLD
LD_NEXT     DECW
            BNE  LD_BYTE
            STY  GAPS
            BRA  LD_READ
LD_FULL     JSR  LD_CLOSE
            JSR  NEWBUF
            CLR  FILENAME
            LDX  #M_TOOBIG
            JMP  SETMSG
LD_RDERR    PSHS A
            JSR  LD_CLOSE
            JSR  NEWBUF
            PULS A
            LBRA LD_ERR
LD_EOF      JSR  LD_CLOSE
            JSR  CURPOS
            LDX  #ARENA_LO
            JSR  COUNTLF
            ADDD BLINES                ; lines read: the LFs ...
            BCS  LD_TOOMANY
            STD  NLW
            ADDD #1
            BCS  LD_TOOMANY
            TST  LFOVER
            BNE  LD_TOOMANY
            STD  NLINES
            STD  CURLINE               ; (the cursor is at the end)
            LDA  LASTLD
            CMPA #LF
            BEQ  LD_FORMAT
            LDD  NLW                   ; ... and a last one with no LF
            ADDD #1
            STD  NLW
LD_FORMAT   TST  SAWLF                 ; a file with bare LFs only keeps them
            BEQ  LD_TOP
            TST  SAWCRLF
            BNE  LD_TOP
            CLR  DOSFMT
LD_TOP      CLRD
            CLRW
            STQ  GOTP
            JSR  GOTOABS
            JSR  MB_START
            LDX  #M_READ
            JSR  MB_STR
            LDD  NLW
            JSR  MB_LINES
            JMP  MB_END
LD_TOOMANY  JSR  NEWBUF                ; more than 65535 lines
            CLR  FILENAME
            LDX  #M_TOOBIG
            JMP  SETMSG
LD_CLOSE    LDB  FH
            LDA  #B_FCLOSE_NAME
            SWI2
            RTS
; The window filled up while reading: its text goes to the store (the cursor is at
; its end). Carry set if the store is full. Keeps A, X and W.
LD_SPILL    PSHS A,X
            PSHSW
            LDD  GAPS
            SUBD #ARENA_LO
            STD  WANT
            JSR  SPILLROOM
            JSR  MINWANT
            LDD  WANT
            BEQ  LS_FULL
            JSR  SPILLF
            BRA  LS_RET
LS_FULL     ORCC #1
LS_RET      PULSW
            PULS A,X,PC
; Writes the text to the file named in PBUF, ending every line with CR LF (or LF,
; see DOSFMT) -- the last one too. -> NLW = the lines written; carry + A = the
; error if it failed.
SAVEFILE    LDX  #PBUF
            LDE  #FOPEN_WRITE
            LDA  #B_FOPEN_NAME
            SWI2
            BCS  SF_RET
            STA  FH
            CLRD
            STD  NLW
            LDA  #LF
            STA  LASTCH
            LDY  #IOBUF
            JSR  RDSTART
SF_LOOP     JSR  RDBYTE
            BCS  SF_END
            STA  LASTCH
            CMPA #LF
            BNE  SF_PUT
            JSR  SF_NL
            BRA  SF_CHK
SF_PUT      STA  ,Y+
SF_CHK      CMPY #IOBUF+510
            BLO  SF_LOOP
            JSR  SF_FLUSH
            BCC  SF_LOOP
            BRA  SF_FAIL
SF_END      LDA  LASTCH
            CMPA #LF
            BEQ  SF_LAST
            JSR  SF_NL
SF_LAST     JSR  SF_FLUSH
            BCS  SF_FAIL
            LDB  FH
            LDA  #B_FCLOSE_NAME
            SWI2
SF_RET      RTS
SF_FAIL     PSHS A
            LDB  FH
            LDA  #B_FCLOSE_NAME
            SWI2
            PULS A
            ORCC #1
            RTS
SF_NL       TST  DOSFMT
            BEQ  SF_LF
            LDA  #CR
            STA  ,Y+
SF_LF       LDA  #LF
            STA  ,Y+
            LDD  NLW
            ADDD #1
            STD  NLW
            RTS
SF_FLUSH    TFR  Y,D
            SUBD #IOBUF
            BEQ  SF_FOK
            PSHS X
            TFR  D,Y
            LDX  #IOBUF
            LDB  FH
            LDA  #B_FWRITE
            SWI2
            PULS X
            LDY  #IOBUF
            RTS
SF_FOK      ANDCC #$FE
            RTS
;------------------------------------------------------------------------------
; The other commands.
;------------------------------------------------------------------------------
C_REFRESH   JSR  SIZEQ
            JMP  FULLREDRAW
; "line 3/10 (30%), col 5/21 (23%), char 40/200 (20%)"
C_CURPOS    JSR  CALCX
            LDY  XCOL                  ; the width of the whole line
            LDX  GAPE
CP_WIDTH    CMPX CUTLO
            BHS  CP_WIDE
            LDA  ,X+
            CMPA #LF
            BEQ  CP_WIDE
            JSR  ADVCOL
            BRA  CP_WIDTH
CP_WIDE     STY  LINEW
            JSR  MB_START
            LDX  #M_CPLINE
            JSR  MB_STR
            LDD  CURLINE
            LDX  NLINES
            JSR  MB_FRAC
            LDX  #M_CPCOL
            JSR  MB_STR
            LDD  XCOL
            ADDD #1
            LDX  LINEW
            LEAX 1,X
            JSR  MB_FRAC
            LDX  #M_CPCHAR
            JSR  MB_STR
            JSR  CURABS
            ADDW #1
            ADCD #0
            STQ  FA
            JSR  DOCLEN
            ADDW #1
            ADCD #0
            STQ  FB
            JSR  MB_FRAC32
            JMP  MB_END
; FA = a, FB = b (32 bits, a <= b, b > 0): "a/b (p%)".
MB_FRAC32   LDQ  FA
            JSR  MB_DEC32
            LDX  #S_SLASH
            JSR  MB_STR
            LDQ  FB
            JSR  MB_DEC32
            LDX  #M_PCTOPEN
            JSR  MB_STR
F32_SHIFT   LDD  FB                    ; both halved until b fits in 16 bits
            BEQ  F32_PCT
            LSR  FB
            ROR  FB+1
            ROR  FB+2
            ROR  FB+3
            LSR  FA
            ROR  FA+1
            ROR  FA+2
            ROR  FA+3
            BRA  F32_SHIFT
F32_PCT     LDD  FA+2
            LDX  FB+2
            JSR  PCT
            JSR  MB_DEC
            LDX  #M_PCTCLOSE
            JMP  MB_STR
; D = a, X = b: "a/b (p%)".
MB_FRAC     PSHS D,X
            JSR  MB_DEC
            LDX  #S_SLASH
            JSR  MB_STR
            LDD  2,S
            JSR  MB_DEC
            LDX  #M_PCTOPEN
            JSR  MB_STR
            PULS D,X
            JSR  PCT
            JSR  MB_DEC
            LDX  #M_PCTCLOSE
            JMP  MB_STR
; D = a, X = b (not 0): -> D = 100 * a / b, rounded down.
PCT         STD  PA
            STX  PB
            CLR  PACC
            CLRD
            STD  PACC+1
            LDE  #100
PC_MUL      LDD  PACC+1
            ADDD PA
            STD  PACC+1
            BCC  PC_MUL1
            INC  PACC
PC_MUL1     DECE
            BNE  PC_MUL
            CLRD
            STD  PQ
PC_DIV      TST  PACC
            BNE  PC_SUB
            LDD  PACC+1
            CMPD PB
            BLO  PC_DONE
PC_SUB      LDD  PACC+1
            SUBD PB
            STD  PACC+1
            BCC  PC_SUB1
            DEC  PACC
PC_SUB1     LDD  PQ
            ADDD #1
            STD  PQ
            BRA  PC_DIV
PC_DONE     LDD  PQ
            RTS
; ^G: the help text, until a key.
C_HELP      LDA  #PM_HELP
            STA  PMODE
HP_DRAW     JSR  FULLREDRAW
            JSR  DRAWTITLE
            LDX  #HELPTEXT
            LDA  #2
HP_LINE     LDB  ,X
            CMPB #$FF
            BEQ  HP_BOTTOM
            LDB  ROWS
            SUBB #2
            STB  TMPB
            CMPA TMPB
            BHS  HP_BOTTOM
            LDB  #1
            JSR  CUP
            JSR  OUTSCLIP
            INCA
            BRA  HP_LINE
HP_BOTTOM   JSR  DRAWBOTTOM
            LDA  ROWS
            SUBA #2
            LDB  #1
            JSR  CUP
            JSR  GETKEY
            CMPA #K_RESIZE
            BNE  HP_DONE
            JSR  APPLYSIZE
            BRA  HP_DRAW
HP_DONE     CLR  PMODE
            JMP  FULLREDRAW
;------------------------------------------------------------------------------
; Questions on the status line.
;------------------------------------------------------------------------------
; PTEXT = the question, PBUF = the answer so far: lets it be edited. Carry set if
; cancelled (^C).
PROMPT      LDA  #PM_TEXT
            STA  PMODE
            STA  BOTDIRTY
PM_LOOP     JSR  RENDER
            JSR  GETKEY
            CMPA #K_RESIZE
            BNE  PM_KEY
            JSR  ONRESIZE
            BRA  PM_LOOP
PM_KEY      TSTB
            BNE  PM_LOOP               ; Meta keys do nothing here
            CMPA #CR
            BEQ  PM_OK
            CMPA #3
            BEQ  PM_CANCEL
            CMPA #8
            BEQ  PM_BS
            CMPA #$7F
            BEQ  PM_BS
            CMPA #' '
            BLO  PM_LOOP
            CMPA #$7F
            BHS  PM_LOOP
            STA  ICH
            LDX  #PBUF
            JSR  STRLEN
            CMPD #NAMEMAX
            BHS  PM_LOOP
            LEAX D,X
            LDA  ICH
            STA  ,X+
            CLR  ,X
            BRA  PM_LOOP
PM_BS       LDX  #PBUF
            JSR  STRLEN
            CMPD #0
            BEQ  PM_LOOP
            LEAX D,X
            CLR  -1,X
            BRA  PM_LOOP
PM_OK       JSR  PM_END
            ANDCC #$FE
            RTS
PM_CANCEL   JSR  PM_END
            ORCC #1
            RTS
PM_END      CLR  PMODE
            LDA  #1
            STA  BOTDIRTY
            RTS
; X = a yes/no question: -> A = 'Y', 'N', or 0 if cancelled.
ASKYN       LDY  #PTEXT
            JSR  STRCPY
            LDA  #PM_YESNO
            STA  PMODE
            STA  BOTDIRTY
AY_LOOP     JSR  RENDER
            JSR  GETKEY
            CMPA #K_RESIZE
            BNE  AY_KEY
            JSR  ONRESIZE
            BRA  AY_LOOP
AY_KEY      TSTB
            BNE  AY_LOOP
            JSR  UPCASE
            CMPA #'Y'
            BEQ  AY_DONE
            CMPA #'N'
            BEQ  AY_DONE
            CMPA #3
            BNE  AY_LOOP
            CLRA
AY_DONE     PSHS A
            JSR  PM_END
            PULS A,PC
;------------------------------------------------------------------------------
; The screen: row 1 the title bar, row 2 blank, rows 3 .. ROWS-3 the text (a
; scroll region), row ROWS-2 the status line, the last two rows the shortcuts.
;------------------------------------------------------------------------------
; Keeps the cursor's line on the screen: one line off scrolls by one, further
; recentres (as nano does).
ENSUREVIS   LDD  CURLINE
            CMPD TOPLINE
            BHS  EV_BELOW
            LDD  TOPLINE
            SUBD CURLINE
            CMPD #1
            BNE  EV_CENTRE
            CLRA
            JSR  SCR_IL
            LDD  TOPLINE
            SUBD #1
            STD  TOPLINE
            RTS
EV_BELOW    LDB  TROWS
            CLRA
            ADDD TOPLINE
            STD  TMPW                  ; the first line below the screen
            LDD  CURLINE
            CMPD TMPW
            BLO  EV_RET
            BNE  EV_CENTRE
            CLRA
            JSR  SCR_DL
            LDD  TOPLINE
            ADDD #1
            STD  TOPLINE
EV_RET      RTS
EV_CENTRE   LDB  TROWS
            LSRB
            CLRA
            STD  TMPW
            LDD  CURLINE
            SUBD TMPW
            BLS  EV_FIRST
            STD  TOPLINE
            JMP  MARKALL
EV_FIRST    LDD  #1
            STD  TOPLINE
            JMP  MARKALL
; Brings the screen up to date and puts the cursor where it belongs.
RENDER      TST  MARKON
            BEQ  RN_X
            JSR  MARKBOUNDS
RN_X        JSR  CALCX
            LDD  CURLINE               ; a line shown scrolled sideways needs redrawing
            CMPD DRAWNLINE             ; when the cursor leaves it or its page changes
            BEQ  RN_SAME
            LDD  DRAWNPS
            BEQ  RN_OLDOK
            LDD  DRAWNLINE
            JSR  MARKLINE
RN_OLDOK    LDD  PSTART
            BEQ  RN_PSOK
            BRA  RN_MARKCUR
RN_SAME     LDD  PSTART
            CMPD DRAWNPS
            BEQ  RN_PSOK
RN_MARKCUR  LDD  CURLINE
            JSR  MARKLINE
RN_PSOK     LDD  CURLINE
            STD  DRAWNLINE
            LDD  PSTART
            STD  DRAWNPS
            TST  TITLEDIRTY
            BEQ  RN_ROWS
            JSR  DRAWTITLE
RN_ROWS     JSR  DRAWROWS
            JSR  DRAWSTATUS
            TST  BOTDIRTY
            BEQ  RN_CURSOR
            JSR  DRAWBOTTOM
RN_CURSOR   TST  PMODE
            BNE  RN_PCURSOR
            LDD  CURLINE
            SUBD TOPLINE
            ADDB #TEXTTOP
            PSHS B
            LDD  XCOL
            SUBD PSTART
            INCB
            PULS A
            JMP  CUP
RN_PCURSOR  LDA  ROWS
            SUBA #2
            LDB  PCURCOL
            JMP  CUP
; Draws the text rows marked in DIRTY.
DRAWROWS    LDB  TROWS                 ; the last one: nothing below it needs walking
            LDU  #DIRTY
DW_FIND     DECB
            BMI  DW_RET
            TST  B,U
            BEQ  DW_FIND
            STB  LASTD
            JSR  LINESTART             ; X = the start of the top line
            LDD  CURLINE
            SUBD TOPLINE
            TFR  D,Y
DW_BACK     CMPY #0
            BEQ  DW_TOP
            LEAX -1,X
            JSR  LINEBACK
            LEAY -1,Y
            BRA  DW_BACK
DW_TOP      LDD  TOPLINE
            STD  RLINE
            CLR  RROW
DW_ROW      LDB  RROW
            CMPB LASTD
            BHI  DW_RET
            LDU  #DIRTY
            TST  B,U
            BEQ  DW_SKIP
            CLR  B,U
            JSR  DRAWLINE
DW_SKIP     JSR  SKIPLINE
            INC  RROW
            LDD  RLINE
            ADDD #1
            STD  RLINE
            BRA  DW_ROW
DW_RET      RTS
; X = the start of a line ($FFFF: past the end of the text): X = the next line's.
SKIPLINE    CMPX #$FFFF
            BEQ  SK_RET
SK_LOOP     JSR  NEXTCH
            BCS  SK_END
            CMPA #LF
            BNE  SK_LOOP
SK_RET      RTS
SK_END      LDX  #$FFFF
            RTS
; Draws one text row: RROW, RLINE, X = the line's start ($FFFF: no line). Keeps X.
DRAWLINE    PSHS X
            LDA  RROW
            ADDA #TEXTTOP
            LDB  #1
            JSR  CUP
            CMPX #$FFFF
            LBEQ DL_EOL
            CLRD
            STD  LCOL                  ; display column of the next cell
            STD  LPS                   ; the first column shown
            LDD  RLINE
            CMPD CURLINE
            BNE  DL_CHAR
            LDD  PSTART
            STD  LPS
DL_CHAR     CLR  WANTINV               ; inside the marked region: inverse
            TST  MARKON
            BEQ  DL_GET
            JSR  LPOS
            CMPD MLO
            BLO  DL_GET
            CMPD MHI
            BHS  DL_GET
            INC  WANTINV
DL_GET      JSR  NEXTCH
            BCS  DL_EOL
            CMPA #LF
            BEQ  DL_EOL
            STA  LCH
            LDY  LCOL
            JSR  ADVCOL
            STY  LNEXT
DL_CELL     LDD  LCOL                  ; each column the character covers
            CMPD LNEXT
            BHS  DL_CHAR
            SUBD LPS
            BCS  DL_SKIP               ; left of what is shown
            TSTA
            BNE  DL_OVER
            INCB
            CMPB COLS
            BHS  DL_OVER               ; the last column is kept for "$"
            DECB
            BNE  DL_GLYPH
            LDD  LPS
            BEQ  DL_GLYPH
            CLRA                       ; scrolled sideways: "$" in the first column
            JSR  SETINV
            LDA  #'$'
            BRA  DL_PUT
DL_GLYPH    LDA  WANTINV
            JSR  SETINV
            LDA  LCH
            CMPA #9
            BNE  DL_NOTTAB
            LDA  #' '
DL_NOTTAB   CMPA #' '
            BLO  DL_ODD
            CMPA #$7F
            BLO  DL_PUT
DL_ODD      LDA  #'?'                  ; control characters and the like
DL_PUT      JSR  OUTC
DL_SKIP     LDD  LCOL
            ADDD #1
            STD  LCOL
            BRA  DL_CELL
DL_OVER     CLRA                       ; more than fits: "$" in the last column
            JSR  SETINV
            LDA  #'$'
            JSR  OUTC
            PULS X,PC
DL_EOL      CLRA
            JSR  SETINV
            LDX  #S_EL
            JSR  OUTS
            PULS X,PC
; The title bar: "  EDIT 1.0", the file's name in the middle, "Modified".
DRAWTITLE   CLR  TITLEDIRTY
            LDX  #SPACECH
            LDY  #LINEBUF
            CLRA
            LDB  COLS
            TFR  D,W
            TFM  X,Y+
            LDX  #LINEBUF
            LDB  COLS
            ABX
            STX  LINEEND
            LDX  #T_PROGRAM
            LDY  #LINEBUF
            JSR  PUTAT
            LDY  #TNAME
            LDX  #T_NEWBUF
            TST  FILENAME
            BEQ  DT_NAME
            LDX  #T_FILE
            JSR  STRCPY
            LDX  #FILENAME
DT_NAME     JSR  STRCPY
            LDX  #TNAME
            JSR  STRLEN
            TSTA
            BNE  DT_LEFT
            CMPB COLS
            BHS  DT_LEFT
            NEGB
            ADDB COLS
            LSRB
            BRA  DT_AT
DT_LEFT     CLRB
DT_AT       LDX  #LINEBUF
            ABX
            TFR  X,Y
            LDX  #TNAME
            JSR  PUTAT
            TST  MODIFIED
            BEQ  DT_OUT
            LDB  COLS
            CMPB #30
            BLO  DT_OUT
            SUBB #10
            LDX  #LINEBUF
            ABX
            TFR  X,Y
            LDX  #T_MODIFIED
            JSR  PUTAT
DT_OUT      LDD  #$0101
            JSR  CUP
            LDA  #1
            JSR  SETINV
            LDX  #LINEBUF
            LDB  COLS
DT_CHAR     LDA  ,X+
            JSR  OUTC
            DECB
            BNE  DT_CHAR
            CLRA
            JMP  SETINV
; X = a string, Y = in LINEBUF: copies it there, as far as LINEEND.
PUTAT       LDA  ,X+
            BEQ  PT_RET
            CMPY LINEEND
            BHS  PT_RET
            STA  ,Y+
            BRA  PUTAT
PT_RET      RTS
; The status line: a question, a message ("[ Wrote 3 lines ]") in inverse, or
; where the cursor is -- redrawn only when it changes.
DRAWSTATUS  LDA  PMODE
            LBNE DZ_PROMPT
            LDX  #STATTXT
            STX  MBP
            LDX  #STATTXT+STATMAX
            STX  MBLIM
            TST  MSGON
            BEQ  DZ_POS
            LDX  #S_LBR
            JSR  MB_STR
            LDX  #MSGBUF
            JSR  MB_STR
            LDX  #S_RBR
            JSR  MB_STR
            LDA  #1
            BRA  DZ_TERM
DZ_POS      LDX  #S_LINE
            JSR  MB_STR
            LDD  CURLINE
            JSR  MB_DEC
            LDX  #S_SLASH
            JSR  MB_STR
            LDD  NLINES
            JSR  MB_DEC
            LDX  #S_COL
            JSR  MB_STR
            LDD  XCOL
            ADDD #1
            JSR  MB_DEC
            LDX  #S_RBR
            JSR  MB_STR
            CLRA
DZ_TERM     STA  STATINVF
            JSR  MB_TERM
            TST  STATDIRTY
            BNE  DZ_DRAW
            LDA  STATINVF
            CMPA SHOWNINV
            BNE  DZ_DRAW
            LDX  #STATTXT
            LDY  #SHOWNTXT
            JSR  STRCMP
            BEQ  DZ_RET
DZ_DRAW     CLR  STATDIRTY
            LDA  STATINVF
            STA  SHOWNINV
            LDX  #STATTXT
            LDY  #SHOWNTXT
            JSR  STRCPY
            LDA  ROWS
            SUBA #2
            LDB  #1
            JSR  CUP
            LDX  #S_EL
            JSR  OUTS
            LDX  #STATTXT
            JSR  STRLEN
            TSTA
            BNE  DZ_LEFT
            CMPB COLS
            BHS  DZ_LEFT
            NEGB
            ADDB COLS
            LSRB
            INCB
            BRA  DZ_AT
DZ_LEFT     LDB  #1
DZ_AT       LDA  ROWS
            SUBA #2
            JSR  CUP
            LDA  STATINVF
            JSR  SETINV
            LDX  #STATTXT
            JSR  OUTSCLIP
            CLRA
            JMP  SETINV
DZ_RET      RTS
DZ_PROMPT   LDA  #1                    ; (drawn every time; and the normal status
            STA  STATDIRTY             ; line comes back afterwards)
            LDA  ROWS
            SUBA #2
            LDB  #1
            JSR  CUP
            LDA  #1
            JSR  SETINV
            CLR  PCNT
            LDX  #PTEXT
            JSR  OUTCNT
            LDA  PMODE
            CMPA #PM_TEXT
            BNE  DZ_PCUR
            LDX  #PBUF
            JSR  OUTCNT
DZ_PCUR     LDB  PCNT
            INCB
            CMPB COLS
            BLS  DZ_PCOL
            LDB  COLS
DZ_PCOL     STB  PCURCOL
DZ_PAD      LDB  PCNT
            CMPB COLS
            BHS  DZ_PEND
            LDA  #' '
            JSR  OUTC
            INC  PCNT
            BRA  DZ_PAD
DZ_PEND     CLRA
            JMP  SETINV
; X = a string: outputs it, counting PCNT, no further than the last column.
OUTCNT      LDA  ,X+
            BEQ  OT_RET
            LDB  PCNT
            CMPB COLS
            BHS  OT_RET
            JSR  OUTC
            INC  PCNT
            BRA  OUTCNT
OT_RET      RTS
; The two shortcut lines, as nano shows them for what is going on (PMODE).
DRAWBOTTOM  CLR  BOTDIRTY
            LDB  PMODE
            LDX  #SCTAB
            ASLB
            ASLB
            ABX
            PSHS X
            LDA  ROWS
            DECA
            LDX  [,S]
            JSR  DRAWSC
            PULS X
            LDX  2,X
            LDA  ROWS
; A = a screen row, X = its shortcuts (key, label, ..., 0): NSLOT slots of SLOTW
; columns, the key in inverse.
DRAWSC      LDB  #1
            JSR  CUP
            PSHS X
            LDX  #S_EL
            JSR  OUTS
            PULS X
            CLR  SCI
DC_SLOT     TST  ,X
            BEQ  DC_RET
            LDA  SCI
            CMPA NSLOT
            BHS  DC_RET
            LDA  #1
            JSR  SETINV
            JSR  STRLEN
            STB  SCUSED
            JSR  OUTS
            CLRA
            JSR  SETINV
            JSR  SKIPSTR
            LDA  #' '
            JSR  OUTC
            INC  SCUSED
DC_LABEL    LDA  ,X+
            BEQ  DC_PAD
            LDB  SCUSED
            CMPB SLOTW
            BHS  DC_LABEL              ; too long: cut short
            INC  SCUSED
            JSR  OUTC
            BRA  DC_LABEL
DC_PAD      INC  SCI
            LDA  SCI
            CMPA NSLOT
            BHS  DC_RET
            TST  ,X
            BEQ  DC_RET
            LDA  #' '
DC_PADL     LDB  SCUSED
            CMPB SLOTW
            BHS  DC_SLOT
            JSR  OUTC
            INC  SCUSED
            BRA  DC_PADL
DC_RET      RTS
SCTAB       FDB  SC_MAIN1,SC_MAIN2     ; PM_EDIT
            FDB  SC_TEXT1,SC_TEXT2     ; PM_TEXT
            FDB  SC_YN1,SC_YN2         ; PM_YESNO
            FDB  SC_HELP1,SC_HELP2     ; PM_HELP
; Clears the screen and marks everything for drawing.
FULLREDRAW  LDX  #S_CLEAR
            JSR  OUTS
            CLR  LINV
            JSR  SETREGION
            LDA  #1
            STA  TITLEDIRTY
            STA  STATDIRTY
            STA  BOTDIRTY
            JMP  MARKALL
; The scroll region: the text rows.
SETREGION   JSR  OUTCSI
            LDD  #TEXTTOP
            JSR  OUTDEC
            LDA  #';'
            JSR  OUTC
            LDB  ROWS
            SUBB #3
            CLRA
            JSR  OUTDEC
            LDA  #'r'
            JMP  OUTC
; Row flags (DIRTY): a text row to draw. Rows move with the insert / delete line
; that scrolls them.
MARKALL     PSHS D,X,Y
            PSHSW
            LDX  #ONE
            LDY  #DIRTY
            LDW  #MAXROWS
            TFM  X,Y+
            PULSW
            PULS D,X,Y,PC
; D = a line: marks its row, if it's on the screen. Keeps D.
MARKLINE    PSHS D,X
            SUBD TOPLINE
            BCS  MK_RET
            TSTA
            BNE  MK_RET
            CMPB TROWS
            BHS  MK_RET
            LDX  #DIRTY
            LDA  #1
            STA  B,X
MK_RET      PULS D,X,PC
; D = a line: marks its row and every one below it.
MARKFROM    PSHS D,X
            SUBD TOPLINE
            BCC  MF_ON
            CLRD
MF_ON       TSTA
            BNE  MF_RET
            LDX  #DIRTY
            LDA  #1
MF_LOOP     CMPB TROWS
            BHS  MF_RET
            STA  B,X
            INCB
            BRA  MF_LOOP
MF_RET      PULS D,X,PC
; D = one line, X = another: marks the rows of the lines from one to the other.
MARKRANGE   PSHS D,X,Y
            STX  MRB
            CMPD MRB
            BLS  MR_ORDER
            LDX  MRB                   ; D = the lower, MRB = the higher
            STD  MRB
            TFR  X,D
MR_ORDER    CMPD TOPLINE
            BHS  MR_FROM
            LDD  TOPLINE
MR_FROM     TFR  D,Y
            CLRA
            LDB  TROWS
            ADDD TOPLINE
            SUBD #1                    ; the last line on the screen
            CMPD MRB
            BHS  MR_START
            STD  MRB
MR_START    TFR  Y,D
MR_LOOP     CMPD MRB
            BHI  MR_RET
            JSR  MARKLINE
            ADDD #1
            BRA  MR_LOOP
MR_RET      PULS D,X,Y,PC
; A = a text row: a blank row opens there (the rows below move down).
SCR_IL      PSHS D,X,Y
            PSHSW
            STA  TMPB
            ADDA #TEXTTOP
            LDB  #1
            JSR  CUP
            LDX  #S_IL
            JSR  OUTS
            LDB  TROWS
            SUBB TMPB
            DECB
            BEQ  IL_SET
            CLRA
            TFR  D,W
            LDX  #DIRTY
            LDB  TROWS
            SUBB #2
            ABX
            LEAY 1,X
            TFM  X-,Y-
IL_SET      LDX  #DIRTY
            LDB  TMPB
            LDA  #1
            STA  B,X
            PULSW
            PULS D,X,Y,PC
; A = a text row: it goes (the rows below move up; a blank one comes in at the bottom).
SCR_DL      PSHS D,X,Y
            PSHSW
            STA  TMPB
            ADDA #TEXTTOP
            LDB  #1
            JSR  CUP
            LDX  #S_DL
            JSR  OUTS
            LDB  TROWS
            SUBB TMPB
            DECB
            BEQ  DL2_SET
            CLRA
            TFR  D,W
            LDX  #DIRTY
            LDB  TMPB
            ABX
            TFR  X,Y
            LEAX 1,X
            TFM  X+,Y+
DL2_SET     LDX  #DIRTY
            LDB  TROWS
            DECB
            LDA  #1
            STA  B,X
            PULSW
            PULS D,X,Y,PC
; A = 1 for inverse video, 0 for normal: switches if it isn't already.
SETINV      CMPA LINV
            BEQ  SI_RET
            STA  LINV
            PSHS X
            LDX  #S_INV
            TSTA
            BNE  SI_OUT
            LDX  #S_NORM
SI_OUT      JSR  OUTS
            PULS X
SI_RET      RTS
;------------------------------------------------------------------------------
; The terminal's size.
;------------------------------------------------------------------------------
; Asks: save the cursor, go as far right and down as it will, report where that
; is, restore the cursor. The reply (ESC [ rows ; cols R) comes as K_RESIZE.
SIZEQ       LDX  #S_SIZEQ
            JSR  OUTS
            JMP  FLUSH
; At the start: waits a while for the reply. A key typed meanwhile is kept.
WAITSIZE    LDD  #SIZEWAIT
            STD  WCNT
WS_LOOP     JSR  RAWGET
            BCS  WS_IDLE
            JSR  PARSEKEY
            CMPA #K_RESIZE
            BEQ  APPLYSIZE
            CMPA #K_NONE
            BEQ  WS_LOOP
            STA  PENDKEY
            STB  PENDMETA
            LDA  #1
            STA  HAVEPEND
            BRA  WS_LOOP
WS_IDLE     LDD  WCNT
            SUBD #1
            STD  WCNT
            BNE  WS_LOOP
            RTS
; A reported size: redraws for it if it's new.
ONRESIZE    JSR  APPLYSIZE
            BEQ  OR_RET
            JSR  FULLREDRAW
            JMP  ENSUREVIS
OR_RET      RTS
; NEWROWS, NEWCOLS -> ROWS, COLS (within the limits). Z set if unchanged.
APPLYSIZE   LDD  NEWROWS
            CMPD #MAXROWS
            BLS  AZ_ROWS
            LDD  #MAXROWS
AZ_ROWS     STB  TMPB
            LDD  NEWCOLS
            CMPD #MAXCOLS
            BLS  AZ_COLS
            LDD  #MAXCOLS
AZ_COLS     CMPB COLS
            BNE  AZ_SET
            LDA  TMPB
            CMPA ROWS
            BEQ  AZ_RET
AZ_SET      STB  COLS
            LDA  TMPB
            STA  ROWS
            JSR  SIZEVARS
            ANDCC #$FB
AZ_RET      RTS
; From ROWS and COLS: the text rows, and the shortcut slots (at least 13 columns
; each, at most 6 a line, none reaching the last column).
SIZEVARS    LDA  ROWS
            SUBA #5
            STA  TROWS
            LDA  COLS
            CLRB
SZ_DIV      CMPA #13
            BLO  SZ_SLOTS
            SUBA #13
            INCB
            BRA  SZ_DIV
SZ_SLOTS    CMPB #6
            BLS  SZ_MAX
            LDB  #6
SZ_MAX      TSTB
            BNE  SZ_MIN
            INCB
SZ_MIN      STB  NSLOT
            LDA  COLS
            DECA
            CLRB
SZ_DIV2     CMPA NSLOT
            BLO  SZ_WIDTH
            SUBA NSLOT
            INCB
            BRA  SZ_DIV2
SZ_WIDTH    STB  SLOTW
            RTS
;------------------------------------------------------------------------------
; The keyboard.
;------------------------------------------------------------------------------
; -> A = the next key, B = 1 if it's a Meta key. Output is sent first. When the
; keyboard has been quiet for a while after a key, asks the terminal its size.
GETKEY      JSR  FLUSH
            TST  HAVEPEND
            BEQ  GK_START
            CLR  HAVEPEND
            LDA  PENDKEY
            LDB  PENDMETA
            RTS
GK_START    CLRD
            STD  IDLECNT
GK_WAIT     JSR  RAWGET
            BCC  GK_GOT
            LDD  IDLECNT
            ADDD #1
            STD  IDLECNT
            CMPD #IDLEPOLLS
            BNE  GK_WAIT
            TST  KEYSEEN
            BEQ  GK_WAIT
            CLR  KEYSEEN
            JSR  SIZEQ
            BRA  GK_WAIT
GK_GOT      JSR  PARSEKEY
            CMPA #K_NONE
            BEQ  GK_START
            CMPA #K_RESIZE
            BEQ  GK_RET
            PSHS A
            LDA  #1
            STA  KEYSEEN
            PULS A
GK_RET      RTS
; -> A = a byte from the terminal, or carry set if there is none.
RAWGET      PSHS B
            LDB  #F_STDIN
            LDA  #B_GETC
            SWI2
            PULS B,PC
; -> A = the next byte (waits for it).
WAITBYTE    JSR  RAWGET
            BCS  WAITBYTE
            RTS
; A = a byte from the terminal: reads the rest of its sequence, if it starts one.
; -> A = the key, B = 1 if Meta.
PARSEKEY    CLRB
            CMPA #ESCAPE
            BEQ  PK_ESC
            CMPA #$80
            BLO  PK_RET
            LDA  #K_NONE
PK_RET      RTS
PK_ESC      JSR  WAITBYTE
            CMPA #ESCAPE
            BEQ  PK_ESC                ; Esc Esc: start again
            CMPA #'['
            BEQ  PK_CSI
            CMPA #'O'
            BEQ  PK_SS3
            JSR  UPCASE                ; Esc and a key: Meta
            LDB  #1
            RTS
PK_SS3      JSR  WAITBYTE              ; ESC O x
            LDX  #SS3TAB
            BRA  PK_LOOKUP
PK_CSI      CLRD                       ; ESC [ params final
            STD  P1
            STD  P2
            CLR  PIDX
            JSR  WAITBYTE
            CMPA #'['
            BNE  PK_CSIC
            JSR  WAITBYTE              ; ESC [ [ A..E: F1-F5 on the Linux console
            CMPA #'A'
            BLO  PK_NONE
            CMPA #'E'
            BHI  PK_NONE
            ADDA #K_F1-'A'
            CLRB
            RTS
PK_CSIN     JSR  WAITBYTE
PK_CSIC     CMPA #'0'
            BLO  PK_NOTDIG
            CMPA #'9'
            BHI  PK_NOTDIG
            SUBA #'0'
            STA  PDIG
            LDX  #P1
            TST  PIDX
            BEQ  PK_ACC
            LDX  #P2
PK_ACC      LDD  ,X
            CMPD #1000
            BHS  PK_CSIN               ; too big to mean anything: stop adding
            ASLB                       ; * 10
            ROLA
            STD  TMPW
            ASLB
            ROLA
            ASLB
            ROLA
            ADDD TMPW
            ADDB PDIG
            ADCA #0
            STD  ,X
            BRA  PK_CSIN
PK_NOTDIG   CMPA #';'
            BNE  PK_NOTSEMI
            LDA  #1
            STA  PIDX
            BRA  PK_CSIN
PK_NOTSEMI  CMPA #$40
            BLO  PK_CSIN               ; other parameter and intermediate bytes
            CMPA #'~'
            BEQ  PK_TILDE
            CMPA #'R'
            BEQ  PK_CPR
            LDX  #CSITAB
PK_LOOKUP   TST  ,X                    ; X = pairs: a final byte, its key; 0
            BEQ  PK_NONE
            CMPA ,X++
            BNE  PK_LOOKUP
            LDA  -1,X
            CLRB
            RTS
PK_NONE     LDA  #K_NONE
            CLRB
            RTS
PK_TILDE    LDD  P1                    ; ESC [ n ~
            CMPD #24
            BHI  PK_NONE
            LDX  #TILDETAB
            LDA  B,X
            CLRB
            RTS
PK_CPR      LDD  P1                    ; ESC [ rows ; cols R: the size
            CMPD #MINROWS
            BLO  PK_NONE
            LDD  P2
            CMPD #MINCOLS
            BLO  PK_NONE
            STD  NEWCOLS
            LDD  P1
            STD  NEWROWS
            LDA  #K_RESIZE
            CLRB
            RTS
SS3TAB      FCB  'A',K_UP,'B',K_DOWN,'C',K_RIGHT,'D',K_LEFT
            FCB  'H',K_HOME,'F',K_END
            FCB  'P',K_F1,'Q',K_F1+1,'R',K_F1+2,'S',K_F1+3
            FCB  0
CSITAB      FCB  'A',K_UP,'B',K_DOWN,'C',K_RIGHT,'D',K_LEFT
            FCB  'H',K_HOME,'F',K_END
            FCB  0
TILDETAB    FCB  K_NONE,K_HOME,K_INS,K_DEL,K_END,K_PGUP,K_PGDN,K_HOME ; 0-7
            FCB  K_END,K_NONE,K_NONE,K_F1,K_F1+1,K_F1+2,K_F1+3,K_F1+4 ; 8-15
            FCB  K_NONE,K_F1+5,K_F1+6,K_F1+7,K_F1+8,K_F1+9,K_NONE      ; 16-22
            FCB  K_F1+10,K_F1+11                                       ; 23-24
;------------------------------------------------------------------------------
; Output, buffered: sent with B_PUT when the buffer fills and before waiting for
; a key.
;------------------------------------------------------------------------------
OUTC        PSHS B,X
            LDB  OUTLEN
            LDX  #OUTBUF
            ABX
            STA  ,X
            INCB
            STB  OUTLEN
            CMPB #OUTMAX
            BLO  OC_RET
            JSR  FLUSH
OC_RET      PULS B,X,PC
FLUSH       PSHS D,X,Y
            LDB  OUTLEN
            BEQ  FL_RET
            CLRA
            TFR  D,Y
            LDX  #OUTBUF
            LDB  #F_STDOUT
            LDA  #B_PUT
            SWI2
            CLR  OUTLEN
FL_RET      PULS D,X,Y,PC
; X = a NUL-terminated string. Keeps A and X.
OUTS        PSHS A,X
OS_LOOP     LDA  ,X+
            BEQ  OS_RET
            JSR  OUTC
            BRA  OS_LOOP
OS_RET      PULS A,X,PC
; X = a string: no further than the second-last column. X ends after its NUL.
; Keeps D.
OUTSCLIP    PSHS D
            LDB  COLS
            DECB
OX_LOOP     LDA  ,X+
            BEQ  OX_RET
            TSTB
            BEQ  OX_LOOP
            JSR  OUTC
            DECB
            BRA  OX_LOOP
OX_RET      PULS D,PC
OUTCSI      LDA  #ESCAPE
            JSR  OUTC
            LDA  #'['
            JMP  OUTC
; D = a number, in decimal. Keeps D and X.
OUTDEC      PSHS D,X
            LDX  #DECBUF
            JSR  DECSTR
            LDX  #DECBUF
            JSR  OUTS
            PULS D,X,PC
; A = row, B = column (from 1): moves the cursor there. Keeps D.
CUP         PSHS D
            JSR  OUTCSI
            LDD  ,S
            PSHS B
            TFR  A,B
            CLRA
            JSR  OUTDEC
            LDA  #';'
            JSR  OUTC
            PULS B
            CLRA
            JSR  OUTDEC
            LDA  #'H'
            JSR  OUTC
            PULS D,PC
; D = a number, X = where: its decimal digits, NUL-terminated. X ends at the NUL.
DECSTR      PSHS D,Y,U
            LDU  #DECPOW
            CLR  DSTART
DS_POW      CLR  DDIG
DS_SUB      CMPD ,U
            BLO  DS_EMIT
            SUBD ,U
            INC  DDIG
            BRA  DS_SUB
DS_EMIT     PSHS D
            LDA  DDIG
            BNE  DS_PUT
            TST  DSTART
            BNE  DS_PUT
            CMPU #DECPOW_LAST
            BNE  DS_SKIP               ; a leading zero
DS_PUT      ADDA #'0'
            STA  ,X+
            INC  DSTART
DS_SKIP     PULS D
            LEAU 2,U
            CMPU #DECPOW_END
            BNE  DS_POW
            CLR  ,X
            PULS D,Y,U,PC
; Q = a number (32 bits): -> its decimal digits at X, NUL-terminated.
DEC32       STQ  D32
            LDY  #POW32
            CLR  DSTART
D3_POW      CLR  DDIG
D3_SUB      LDQ  D32
            SUBW 2,Y
            SBCD ,Y
            BCS  D3_EMIT
            STQ  D32
            INC  DDIG
            BRA  D3_SUB
D3_EMIT     LDA  DDIG
            BNE  D3_PUT
            TST  DSTART
            BNE  D3_PUT
            CMPY #POW32_LAST
            BNE  D3_SKIP
D3_PUT      ADDA #'0'
            STA  ,X+
            INC  DSTART
D3_SKIP     LEAY 4,Y
            CMPY #POW32_END
            BLO  D3_POW
            CLR  ,X
            RTS
POW32       FQB  1000000000,100000000,10000000,1000000,100000,10000,1000,100,10
POW32_LAST  FQB  1
POW32_END
DECPOW      FDB  10000,1000,100,10
DECPOW_LAST FDB  1
DECPOW_END
;------------------------------------------------------------------------------
; Messages (the status line). MB_START begins one in MSGBUF, MB_STR / MB_DEC /
; MB_LINES / MB_ERR add to it, MB_END shows it.
;------------------------------------------------------------------------------
SETMSG      PSHS X
            JSR  MB_START
            PULS X
            JSR  MB_STR
            JMP  MB_END
MB_START    PSHS X
            LDX  #MSGBUF
            STX  MBP
            LDX  #MSGBUF+MSGMAX
            STX  MBLIM
            PULS X,PC
MB_STR      PSHS A,X,Y
            LDY  MBP
MS_LOOP     LDA  ,X+
            BEQ  MS_DONE
            CMPY MBLIM
            BHS  MS_DONE
            STA  ,Y+
            BRA  MS_LOOP
MS_DONE     STY  MBP
            PULS A,X,Y,PC
MB_DEC      PSHS D,X
            LDX  #DECBUF
            JSR  DECSTR
            LDX  #DECBUF
            JSR  MB_STR
            PULS D,X,PC
; Q = a number (32 bits): added to the message.
MB_DEC32    PSHS X,Y
            LDX  #DECBUF
            JSR  DEC32
            LDX  #DECBUF
            JSR  MB_STR
            PULS X,Y,PC
; D = a number of lines: "3 lines", "1 line".
MB_LINES    JSR  MB_DEC
            PSHS D
            LDX  #M_LINE
            JSR  MB_STR
            PULS D
            CMPD #1
            BEQ  ML2_RET
            LDX  #M_S
            JMP  MB_STR
ML2_RET     RTS
; A = a DOS error: what it means.
MB_ERR      LDX  #ERRTAB
ME_LOOP     LDB  ,X
            BEQ  ME_OTHER
            CMPA ,X
            BEQ  ME_FOUND
            LEAX 3,X
            BRA  ME_LOOP
ME_FOUND    LDX  1,X
            JMP  MB_STR
ME_OTHER    PSHS A
            LDX  #M_ERRNUM
            JSR  MB_STR
            PULS B
            CLRA
            JMP  MB_DEC
MB_TERM     PSHS X
            LDX  MBP
            CLR  ,X
            PULS X,PC
MB_END      JSR  MB_TERM
            LDA  #1
            STA  MSGON
            RTS
ERRTAB      FCB  ERR_NOTFOUND
            FDB  M_E_NOTFOUND
            FCB  ERR_NOSPACE
            FDB  M_E_NOSPACE
            FCB  ERR_ISOPEN
            FDB  M_E_ISOPEN
            FCB  ERR_NOTDIR
            FDB  M_E_NOTDIR
            FCB  ERR_ISDIR
            FDB  M_E_ISDIR
            FCB  ERR_BADPATH
            FDB  M_E_BADPATH
            FCB  ERR_NOSLOT
            FDB  M_E_NOSLOT
            FCB  ERR_TOOBIG
            FDB  M_E_TOOBIG
            FCB  ERR_IOERR
            FDB  M_E_IOERR
            FCB  0
;------------------------------------------------------------------------------
; Strings.
;------------------------------------------------------------------------------
; X = the command tail: its first word -> Y (at most NAMEMAX characters).
GETWORD     LDA  ,X
            CMPA #' '
            BNE  GW_COPY
            LEAX 1,X
            BRA  GETWORD
GW_COPY     LDB  #NAMEMAX
GW_LOOP     LDA  ,X+
            BEQ  GW_END
            CMPA #' '
            BEQ  GW_END
            TSTB
            BEQ  GW_LOOP
            STA  ,Y+
            DECB
            BRA  GW_LOOP
GW_END      CLR  ,Y
            RTS
; X -> Y, with its NUL; Y ends at the NUL (so another can be added).
STRCPY      LDA  ,X+
            STA  ,Y+
            BNE  STRCPY
            LEAY -1,Y
            RTS
; X = a string: -> D = its length. Keeps X.
STRLEN      PSHS X
            CLRD
SL_LOOP     TST  ,X+
            BEQ  SL_RET
            ADDD #1
            BRA  SL_LOOP
SL_RET      PULS X,PC
; Z set if the strings at X and Y are the same.
STRCMP      PSHS A,X,Y
SC_LOOP     LDA  ,X+
            CMPA ,Y+
            BNE  SC_RET
            TSTA
            BNE  SC_LOOP
SC_RET      PULS A,X,Y,PC
; The same, but upper and lower case are alike.
STRCMPI     PSHS D,X,Y
CI_LOOP     LDA  ,Y+
            JSR  UPCASE
            TFR  A,B
            LDA  ,X+
            JSR  UPCASE
            PSHS B
            CMPA ,S+
            BNE  CI_RET
            TSTA
            BNE  CI_LOOP
CI_RET      PULS D,X,Y,PC
UPCASE      CMPA #'a'
            BLO  UC_RET
            CMPA #'z'
            BHI  UC_RET
            SUBA #$20
UC_RET      RTS
; X = a string: X = just after its NUL.
SKIPSTR     TST  ,X+
            BNE  SKIPSTR
            RTS
ZERO        FCB  0
ONE         FCB  1
SPACECH     FCB  ' '
S_ALTON     FCB  ESCAPE
            FCN  "[?1049h"
S_CLEAR     FCB  ESCAPE
            FCC  "[0m"
            FCB  ESCAPE
            FCN  "[2J"
S_QUIT      FCB  ESCAPE
            FCC  "[r"
            FCB  ESCAPE
            FCC  "[0m"
            FCB  ESCAPE
            FCC  "[2J"
            FCB  ESCAPE
            FCC  "[H"
            FCB  ESCAPE
            FCN  "[?1049l"
S_SIZEQ     FCB  ESCAPE
            FCC  "7"
            FCB  ESCAPE
            FCC  "[999;999H"
            FCB  ESCAPE
            FCC  "[6n"
            FCB  ESCAPE
            FCN  "8"
S_EL        FCB  ESCAPE
            FCN  "[K"
S_IL        FCB  ESCAPE
            FCN  "[L"
S_DL        FCB  ESCAPE
            FCN  "[M"
S_INV       FCB  ESCAPE
            FCN  "[7m"
S_NORM      FCB  ESCAPE
            FCN  "[0m"
S_LBR       FCN  "[ "
S_RBR       FCN  " ]"
S_LINE      FCN  "[ line "
S_SLASH     FCN  "/"
S_COL       FCN  ", col "
T_PROGRAM   FCN  "  NANO6309 1.0"
T_FILE      FCN  "File: "
T_NEWBUF    FCN  "New Buffer"
T_MODIFIED  FCN  "Modified"
P_WRITE     FCN  "File Name to Write: "
P_OPEN      FCN  "File to Read (Enter alone: New Buffer): "
P_SAVEMOD   FCN  /Save modified buffer (ANSWERING "No" WILL DESTROY CHANGES) ? /
P_OVERWRITE FCN  "File exists, OVERWRITE ? "
P_SEARCH    FCN  "Search"
P_LBR       FCN  " ["
P_RBR       FCN  "]"
P_COLON     FCN  ": "
M_NEWFILE   FCN  "New File"
M_READING   FCN  "Reading File"
M_READ      FCN  "Read "
M_WROTE     FCN  "Wrote "
M_LINE      FCN  " line"
M_S         FCN  "s"
M_TOOBIG    FCN  "File too large to edit"
M_NOMEM     FCN  "Out of memory"
M_CANCELLED FCN  "Cancelled"
M_MARKSET   FCN  "Mark Set"
M_MARKUNSET FCN  "Mark UNset"
M_WRAPPED   FCN  "Search Wrapped"
M_ONLYONE   FCN  "This is the only occurrence"
M_NOPATTERN FCN  "No current search pattern"
M_QUOTE     FCN  /"/
M_NOTFOUND  FCN  /" not found/
M_ERRREAD   FCN  "Error reading "
M_ERRWRITE  FCN  "Error writing "
M_COLON     FCN  ": "
M_ERRNUM    FCN  "error "
M_CPLINE    FCN  "line "
M_CPCOL     FCN  ", col "
M_CPCHAR    FCN  ", char "
M_PCTOPEN   FCN  " ("
M_PCTCLOSE  FCN  "%)"
M_E_NOTFOUND FCN "File not found"
M_E_NOSPACE FCN  "Disk full"
M_E_ISOPEN  FCN  "File is in use"
M_E_NOTDIR  FCN  "Not a directory"
M_E_ISDIR   FCN  "Is a directory"
M_E_BADPATH FCN  "Bad name or path"
M_E_NOSLOT  FCN  "Too many open files"
M_E_TOOBIG  FCN  "Too big"
M_E_IOERR   FCN  "Disk error"
; The shortcut lines: key, label, ..., 0.
SC_MAIN1    FCN  "^G"
            FCN  "Get Help"
            FCN  "^O"
            FCN  "WriteOut"
            FCN  "^R"
            FCN  "Read File"
            FCN  "^Y"
            FCN  "Prev Page"
            FCN  "^K"
            FCN  "Cut Text"
            FCN  "^C"
            FCN  "Cur Pos"
            FCB  0
SC_MAIN2    FCN  "^X"
            FCN  "Exit"
            FCN  "M-A"
            FCN  "Mark Text"
            FCN  "^W"
            FCN  "Where Is"
            FCN  "^V"
            FCN  "Next Page"
            FCN  "^U"
            FCN  "UnCut Text"
            FCN  "M-6"
            FCN  "Copy Text"
            FCB  0
SC_TEXT1    FCN  "^C"
            FCN  "Cancel"
            FCB  0
SC_TEXT2    FCB  0
SC_YN1      FCN  " Y"
            FCN  "Yes"
            FCB  0
SC_YN2      FCN  " N"
            FCN  "No"
            FCN  "^C"
            FCN  "Cancel"
            FCB  0
SC_HELP1    FCN  "^X"
            FCN  "Exit Help"
            FCB  0
SC_HELP2    FCB  0
HELPTEXT    FCN  "EDIT: a small text editor in the style of GNU nano"
            FCN  ""
            FCN  "^ is the Ctrl key. M- is Alt, or press Esc and then the key."
            FCN  ""
            FCN  "^G F1       this help           ^X F2       exit (asks to save changes)"
            FCN  "^O F3       write the file out  ^R F5       open a file (Enter: new one)"
            FCN  "^W F6       search              M-W         search again"
            FCN  "^K F9       cut line / marked   ^U F10      paste (uncut)"
            FCN  "M-A ^^      set / unset mark    M-6 M-^     copy line / marked"
            FCN  "^Y F7 PgUp  previous page       ^V F8 PgDn  next page"
            FCB  'M','-',$5C
            FCN  " M-|     first line          M-/ M-?     last line"
            FCN  "^A Home     start of the line   ^E End      end of the line"
            FCN  "^P ^N ^B ^F and the arrows: up, down, left, right"
            FCN  "^D Del      delete this char    ^H Bksp     delete the one before"
            FCN  "^C F11      cursor position     ^L          redraw the screen"
            FCN  ""
            FCN  "Without the mark, ^K cuts the whole line. Lines cut one after"
            FCN  "another are collected, and ^U pastes them all back."
            FCB  $FF
EDIT_END    equ  *
;------------------------------------------------------------------------------
; Variables and buffers: RAM after the program (none of it is in edit.bin).
;------------------------------------------------------------------------------
VARS        equ  *
VP          SET  VARS
            VAR  ROWS,1
            VAR  COLS,1
            VAR  TROWS,1               ; text rows: ROWS-5
            VAR  NSLOT,1               ; shortcut slots a line
            VAR  SLOTW,1               ; and their width
            VAR  GAPS,2                ; the gap buffer (see the top of the file)
            VAR  GAPE,2
            VAR  CUTLO,2
            VAR  CURLINE,2             ; the cursor's line (from 1)
            VAR  NLINES,2
            VAR  TOPLINE,2             ; the line in the top text row
            VAR  OLDLINE,2
            VAR  PREFCOL,2             ; the column up / down aim for
            VAR  XCOL,2                ; the cursor's display column (from 0)
            VAR  PSTART,2              ; the first column shown of the cursor's line
            VAR  PW,2
            VAR  LINEW,2
            VAR  DRAWNLINE,2           ; the line last drawn as the cursor's
            VAR  DRAWNPS,2             ; and its PSTART then
            VAR  MARKON,1
            VAR  MARKPOS,2
            VAR  MLO,2
            VAR  MHI,2
            VAR  MODIFIED,1
            VAR  DOSFMT,1              ; write lines with CR LF (else LF)
            VAR  LASTCUT,1             ; the last command cut or copied
            VAR  THISCUT,1
            VAR  UPDPREF,1
            VAR  COPYONLY,1
            VAR  TITLEDIRTY,1
            VAR  STATDIRTY,1
            VAR  BOTDIRTY,1
            VAR  MSGON,1
            VAR  PMODE,1
            VAR  PCNT,1
            VAR  PCURCOL,1
            VAR  STATINVF,1
            VAR  SHOWNINV,1
            VAR  LINV,1                ; the terminal is in inverse video
            VAR  WANTINV,1
            VAR  KEYSEEN,1
            VAR  HAVEPEND,1
            VAR  PENDKEY,1
            VAR  PENDMETA,1
            VAR  IDLECNT,2
            VAR  WCNT,2
            VAR  P1,2
            VAR  P2,2
            VAR  PIDX,1
            VAR  PDIG,1
            VAR  NEWROWS,2
            VAR  NEWCOLS,2
            VAR  OUTLEN,1
            VAR  MGT,2
            VAR  TMPW,2
            VAR  TMP2,2
            VAR  TMPB,1
            VAR  ICH,1
            VAR  TKN,2
            VAR  TKLF,2
            VAR  CTN,2
            VAR  CPSAVE,2
            VAR  RROW,1
            VAR  RLINE,2
            VAR  LASTD,1
            VAR  LPS,2
            VAR  LCOL,2
            VAR  LNEXT,2
            VAR  LCH,1
            VAR  FH,1
            VAR  LASTCR,1
            VAR  SAWLF,1
            VAR  SAWCRLF,1
            VAR  NLW,2
            VAR  LASTCH,1
            VAR  SSAVE,4               ; the search (positions in the whole text)
            VAR  SFROM,4
            VAR  STO,4
            VAR  SFOUND,4
            VAR  SPLEN,2
            VAR  SLAST,4
            VAR  SRN,2
            VAR  BLEN,4                ; the store (see "The window and the store")
            VAR  ALEN,4
            VAR  VTOP,4
            VAR  BLINES,2
            VAR  ALINES,2
            VAR  LFOVER,1
            VAR  NSP,1
            VAR  ARPAGE,4              ; the pages banks 1..3 show (index = bank)
            VAR  XRAM,2                ; XFER
            VAR  XVA,4
            VAR  XLEN,2
            VAR  XDIR,1
            VAR  XRP,1
            VAR  XSP,1
            VAR  XRO,2
            VAR  XSO,2
            VAR  XC,2
            VAR  SPN,2                 ; SPILLF / FILLF / SPILLB / FILLB
            VAR  SPLF,2
            VAR  HALF,2                ; ENSUREWIN
            VAR  LOWM,2
            VAR  WANT,2
            VAR  MKN,2                 ; MAKEROOM
            VAR  MMT,2
            VAR  GOTP,4                ; GOTOABS
            VAR  GDIST,2
            VAR  DCP,4                 ; DOCCOPY
            VAR  DCN,2
            VAR  DCD,2
            VAR  DYREL,2
            VAR  DYLEN,2
            VAR  RDPOS,4               ; RDBYTE
            VAR  RDI,1
            VAR  RDN,1
            VAR  LASTLD,1              ; the last character read in
            VAR  FA,4                  ; MB_FRAC32
            VAR  FB,4
            VAR  D32,4                 ; DEC32
            VAR  PA,2
            VAR  PB,2
            VAR  PACC,3
            VAR  PQ,2
            VAR  MBP,2
            VAR  MBLIM,2
            VAR  DSTART,1
            VAR  DDIG,1
            VAR  PGN,1
            VAR  PGNS,1
            VAR  MRB,2
            VAR  SCI,1
            VAR  SCUSED,1
            VAR  LINEEND,2
            VAR  OUTBUF,OUTMAX+8
            VAR  DECBUF,12
            VAR  MSGBUF,MSGMAX+4
            VAR  STATTXT,STATMAX+4
            VAR  SHOWNTXT,STATMAX+4
            VAR  PTEXT,PTEXTMAX
            VAR  PBUF,NAMEMAX+2
            VAR  FILENAME,NAMEMAX+2
            VAR  SEARCHSTR,NAMEMAX+2
            VAR  TNAME,NAMEMAX+8
            VAR  LINEBUF,MAXCOLS+2
            VAR  DIRTY,MAXROWS
            VAR  STATBUF,16
            VAR  IOBUF,512
            VAR  STPAGES,256           ; the RAM page of each store page (0: not yet)
            VAR  RDBUF,RDMAX
            VAR  SBUF,SCHUNK+NAMEMAX
            VAR  STACKB,STACKSIZE
STACKTOP    equ  VP
ARENA_LO    equ  VP                    ; the text and the cut buffer: to ARENA_HI
;------------------------------------------------------------------------------
; End of edit.asm
;------------------------------------------------------------------------------
