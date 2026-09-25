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
MAINLOOP    JSR  ENSUREVIS
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
            JSR  MOVEGAP
            INC  UPDPREF
            RTS
C_BOTTOM    JSR  TEXTLEN
            JSR  MOVEGAP
            INC  UPDPREF
            RTS
; A page is the text rows less two; the screen moves with the cursor.
C_PGUP      JSR  PAGEN
            STB  PGNS
            STB  PGN
PU_LOOP     JSR  PREVLINE
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
PD_LOOP     JSR  NEXTLINE
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
; Editing.
;------------------------------------------------------------------------------
C_ENTER     LDA  #LF
            BRA  INSCHAR
C_TAB       LDA  #9
; A = a character: typed in at the cursor.
INSCHAR     STA  ICH
            LDD  GAPE
            CMPD GAPS
            BNE  IC_ROOM
            LDX  #M_NOMEM
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
            LDD  GAPE
            SUBD GAPS
            CMPD CTN
            BLO  CO_NOMEM
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
            LDD  GAPE
            SUBD GAPS
            CMPD CTN
            BLO  PA_NOMEM
            LDX  CUTLO
            LDD  CTN
            JSR  COUNTLF
            STD  TKLF
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
DOSEARCH    JSR  CURPOS
            STD  SSAVE
            JSR  TEXTLEN               ; all of the text before the gap, in one piece
            STD  TMPW
            JSR  MOVEGAP
            LDX  #SEARCHSTR
            JSR  STRLEN
            STD  SPLEN
            LDD  TMPW
            SUBD SPLEN
            BCS  SE_NOTFOUND           ; longer than the text
            STD  SLAST                 ; the last place it could start
            LDD  SSAVE
            ADDD #1
            STD  SFROM
            LDD  SLAST
            STD  STO
            JSR  SCANRANGE
            BCC  SE_GO
            CLRD                       ; round from the start
            STD  SFROM
            LDD  SSAVE
            CMPD SLAST
            BLS  SE_WTO
            LDD  SLAST
SE_WTO      STD  STO
            JSR  SCANRANGE
            BCS  SE_NOTFOUND
            STD  SFOUND
            LDX  #M_WRAPPED
            CMPD SSAVE
            BNE  SE_MSG
            LDX  #M_ONLYONE
SE_MSG      JSR  SETMSG
            LDD  SFOUND
SE_GO       JSR  MOVEGAP
            INC  UPDPREF
            RTS
SE_NOTFOUND LDD  SSAVE
            JSR  MOVEGAP
            JSR  MB_START
            LDX  #M_QUOTE
            JSR  MB_STR
            LDX  #SEARCHSTR
            JSR  MB_STR
            LDX  #M_NOTFOUND
            JSR  MB_STR
            JMP  MB_END
; The first position from SFROM to STO where SEARCHSTR starts: -> D, carry clear;
; carry set if none. (The text is all before the gap.)
SCANRANGE   LDD  SFROM
SR_LOOP     CMPD STO
            BHI  SR_NONE
            TFR  D,X
            LEAX ARENA_LO,X
            JSR  MATCHAT
            BEQ  SR_HIT
            ADDD #1
            BRA  SR_LOOP
SR_HIT      ANDCC #$FE
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
QUIT        LDX  #S_QUIT
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
            BHS  LD_FULL
            STA  ,Y+
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
            STD  NLW                   ; lines read: the LFs ...
            ADDD #1
            STD  NLINES
            STD  CURLINE               ; (the cursor is at the end)
            LDX  GAPS
            CMPX #ARENA_LO
            BEQ  LD_FORMAT
            LDA  -1,X
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
            JSR  MOVEGAP
            JSR  MB_START
            LDX  #M_READ
            JSR  MB_STR
            LDD  NLW
            JSR  MB_LINES
            JMP  MB_END
LD_CLOSE    LDB  FH
            LDA  #B_FCLOSE_NAME
            SWI2
            RTS
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
            LDX  #ARENA_LO
SF_LOOP     JSR  NEXTCH
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
            JSR  TEXTLEN
            ADDD #1
            TFR  D,X
            JSR  CURPOS
            ADDD #1
            JSR  MB_FRAC
            JMP  MB_END
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
T_PROGRAM   FCN  "  EDIT 1.0"
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
            VAR  SSAVE,2
            VAR  SFROM,2
            VAR  STO,2
            VAR  SFOUND,2
            VAR  SPLEN,2
            VAR  SLAST,2
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
            VAR  DECBUF,8
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
            VAR  STACKB,STACKSIZE
STACKTOP    equ  VP
ARENA_LO    equ  VP                    ; the text and the cut buffer: to ARENA_HI
;------------------------------------------------------------------------------
; End of edit.asm
;------------------------------------------------------------------------------
