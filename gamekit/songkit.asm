;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 game kit
;    FILE: songkit.asm
;
; SONGKIT.COM: music for the OPL3, on the video card's screen, worked with its
; keyboard and mouse (in the emulator, the video window's):
;
;   SONGKIT [file]      a song (.SNG, the default) to open
;
; Two pages, Tab from one to the other: the song's patterns (its settings, its
; orders, and the pattern an order plays, a grid of rows and tracks: sk_pat.asm),
; and its instruments (every setting of the chip's for one, heard as it is
; edited: sk_inst.asm). The keyboard's two rows of letters are a piano (Z-M,
; and Q-P an octave up). Space plays the song as it is -- a change is heard at
; once, while it plays -- by the player games use (sk_play.asm).
;
;   ASM -o SONGKIT.COM songkit.asm     makes SONGKIT.COM
;------------------------------------------------------------------------------
            INCLUDE "defines.d"
            INCLUDE "vidcard.d"

SK_EDITOR   equ  1          ; (the player's editor's parts too: sk_play.asm)
KIT_BASE     equ  $8000      ; (banks 2 and 3: bank 1 is the song's window)
KIT_STACK    equ  $EF00
WBANK       equ  1          ; the song's pages, seen through bank 1
WINDOW      equ  $4000
MAXPG       equ  32         ; 512KB of song at most
MAXINST     equ  255
NVOICE      equ  6          ; notes played at once from the keys
;------------------------------------------------------------------------------
            ORG  KIT_BASE-EXE_HDRSIZE
            FDB  EXE_MAGIC      ; the program header
            FDB  KIT_BASE        ; load address
            FDB  START          ; entry
            FDB  0              ; flags
;------------------------------------------------------------------------------
START       LDS  #KIT_STACK
            CLR  NPG
            CLR  NNPG
            CLR  MODE
            CLR  PAGE
            CLR  SETF
            CLR  RQN
            CLR  MSGUP
            CLR  SONGON
            CLR  PLAYON
            LDA  #4
            STA  OCT
            LDA  #9             ; (the first operator's attack)
            STA  CURF
            LDB  #WBANK         ; bank 1's own page, for after
            LDA  #B_BANK_GET
            SWI2
            STA  WHOME
            JSR  UISTART
            LDA  #B_PAGE_ALLOC  ; the pattern buffer's page, and the names'
            SWI2
            LBCS NOMEM
            STA  PBPG
            LDA  #B_PAGE_ALLOC
            SWI2
            LBCS NOMEM
            STA  NMPG
            LDA  #B_PAGE_ALLOC  ; and the instruments'
            SWI2
            LBCS NOMEM
            STA  INPG
            JSR  NEWSONG
            LBCS NOMEM
            LDA  #B_ARGS        ; a file named?
            SWI2
ST1         LDA  ,X+
            CMPA #$20
            BEQ  ST1
            LDY  #PR_BUF
            LDB  #PR_MAX
ST2         TSTA
            BEQ  ST3
            CMPA #$20
            BEQ  ST3
            CMPA #'a
            BLO  ST2A
            CMPA #'z
            BHI  ST2A
            SUBA #$20
ST2A        STA  ,Y+
            LDA  ,X+
            DECB
            BNE  ST2
ST3         CLR  ,Y
            JSR  JAMSET
            JSR  DRAWCUR
            TST  PR_BUF
            BEQ  MAIN
            JSR  OPENNAMED      ; (its name in PR_BUF)
;------------------------------------------------------------------------------
; The main loop: the song's ticks, the mouse, the keys.
;------------------------------------------------------------------------------
MAIN        TST  SONGON         ; (the window the player's: the editor's pages
            BEQ  MAIN0          ; come and go in it)
            LDB  SK_PG
            JSR  SKMAP
MAIN0       JSR  SK_POLL
            TST  SONGON         ; the song over by itself?
            BEQ  MAIN1
            TST  SK_PLAYING
            BNE  MAIN1
            CLR  SONGON
            JSR  JAMSET
            JSR  DRAWSTAT
MAIN1       LDA  MODE           ; (the help over the page: nothing drawn under it)
            CMPA #3
            BEQ  MAIN2
            JSR  PLAYPOS
            JSR  RQSTEP         ; (the grid's rows not drawn yet)
            TST  MODE           ; (a line being typed, a question: the mouse
            BNE  MAIN2          ; left until it's done, its clicks kept)
            JSR  POLLIN
            TST  PAGE
            BNE  MAIN1A
            JSR  PMOUSE
            BRA  MAIN2
MAIN1A      JSR  MOUSE
MAIN2       JSR  GETKEY
            BEQ  MAIN
            JSR  KEYDO
            BRA  MAIN

; MOUSE: a click picks a field (on the name: renames it); the wheel over one
; changes it.
MOUSE       LDA  PRESSED
            BITA #VC_MB_LEFT
            BEQ  MOUSE2
            JSR  FHIT
            BCS  MOUSE2
            JSR  PICKF
            LDA  CURF
            BNE  MOUSE2
            JMP  RENAME
MOUSE2      LDA  WHEEL
            BEQ  MOUSE9
            JSR  FHIT
            BCS  MOUSE9
            JSR  PICKF
            LDA  #1
            TST  WHEEL
            BPL  MOUSE3
            LDA  #-1
MOUSE3      JMP  FSTEP
MOUSE9      RTS
; PICKF: field A the one being edited.
PICKF       LDB  CURF
            STA  CURF
            TFR  B,A
            JSR  DRAWF
            LDA  CURF
            JMP  DRAWF

;------------------------------------------------------------------------------
; The keys.
;------------------------------------------------------------------------------
KEYDO       LDF  MODE
            BEQ  KD1
            CMPF #1
            BEQ  KDTYPE
            CMPF #3
            BEQ  KDHELP
            TSTB                ; a question: Y does it, anything else doesn't
            BMI  KD9
            CLR  MODE
            PSHS A
            JSR  CLRMSG
            PULS A
            CMPA #$1C           ; Y
            BNE  KD9
            JMP  [CF_DO]
KDTYPE      JSR  PRKEY          ; a line of typing
            TSTA
            BEQ  KD9
            CLR  MODE
            PSHS A
            JSR  CLRMSG
            PULS A
            CMPA #1
            BNE  KD9
            JMP  [PR_DO]
KDHELP      TSTB                ; the help: a key closes it (one let go: a note's end)
            BMI  KD1A
            CLR  MODE
            TST  PAGE
            LBEQ REDRAWUI
            JMP  DRAWPAGE
KD1         TSTB                ; a key let go: a note's end
            BPL  KD1B
KD1A        JMP  PIANOUP
KD1B        TST  MSGUP          ; (a message: the status back, from the next key)
            BEQ  KD1C
            PSHS D
            JSR  CLRMSG
            PULS D
KD1C        CMPA #K_F1
            LBEQ KHELP
KD2         TST  PAGE           ; (the pattern page's own)
            LBEQ PKEY
            LDB  KEYMODS
            BITB #VC_MOD_CTL
            BNE  KDCTL
            JSR  PIANODN        ; a note?
            BCC  KD9
            LDX  #KEYTAB        ; the others
KD3         LDB  ,X
            BEQ  KD9
            CMPA ,X
            BEQ  KD4
            LEAX 3,X
            BRA  KD3
KD4         JMP  [1,X]
KD9         RTS
KDCTL       LDX  #CTLTAB
            BRA  KD3
KEYTAB      FCB  K_UP
            FDB  KUP
            FCB  K_DOWN
            FDB  KDOWN
            FCB  K_LEFT
            FDB  KLEFT
            FCB  K_RIGHT
            FDB  KRIGHT
            FCB  $2E            ; = (and +)
            FDB  KPLUS
            FCB  $57            ; + on the keypad
            FDB  KPLUS
            FCB  $2D            ; -
            FDB  KMINUS
            FCB  $56            ; - on the keypad
            FDB  KMINUS
            FCB  $2F            ; [
            FDB  KOCTDN
            FCB  $30            ; ]
            FDB  KOCTUP
            FCB  K_PGUP
            FDB  KPREV
            FCB  K_PGDN
            FDB  KNEXT
            FCB  K_SPACE
            FDB  KSONG
            FCB  K_TAB
            FDB  KTAB
            FCB  K_ENTER
            FDB  KENTER
            FCB  K_ESC
            FDB  KQUIT
            FCB  K_BKSP
            FDB  KHUSH
            FCB  0
CTLTAB      FCB  K_LEFT         ; ^Left, ^Right: PgUp, PgDn (no Fn key needed)
            FDB  KPREV
            FCB  K_RIGHT
            FDB  KNEXT
            FCB  $11            ; ^N
            FDB  NEWINST
            FCB  $07            ; ^D
            FDB  DUPINST
            FCB  $12            ; ^O
            FDB  OPEN
            FCB  $16            ; ^S
            FDB  SAVE
            FCB  $04            ; ^A
            FDB  SAVEAS
            FCB  $1A            ; ^W
            FDB  SAVEINS
            FCB  0
KUP         CLRA
            JMP  FMOVE
KDOWN       LDA  #1
            JMP  FMOVE
KLEFT       LDA  #2
            JMP  FMOVE
KRIGHT      LDA  #3
            JMP  FMOVE
KPLUS       LDA  #1
            JMP  FSTEP
KMINUS      LDA  #-1
            JMP  FSTEP
KOCTDN      LDA  OCT
            BEQ  KOCT9
            DEC  OCT
            JMP  DRAWSTAT
KOCTUP      LDA  OCT
            CMPA #7
            BHS  KOCT9
            INC  OCT
            JMP  DRAWSTAT
KOCT9       RTS
KPREV       LDA  CURI
            CMPA #1
            BLS  KOCT9
            DEC  CURI
            BRA  KINST
KNEXT       LDA  CURI
            CMPA NINST
            BHS  KOCT9
            INC  CURI
KINST       JSR  SETIP
            TST  PAGE
            LBEQ DRAWSTAT
            JMP  DRAWVALS
KENTER      TST  CURF           ; on the name: rename it
            BNE  KOCT9
RENAME      LDX  #S_ASKNAME
            LDY  NP
            CLRA
            JSR  PRSTART
            LDX  #RENAMED
            STX  PR_DO
            LDA  #1
            STA  MODE
            RTS
RENAMED     LDX  #PR_BUF
            LDY  NP
            LDB  #16
RN1         LDA  ,X+
            STA  ,Y+
            BEQ  RN2
            DECB
            BNE  RN1
            BRA  RN3
RN2         DECB
            BEQ  RN3
            CLR  ,Y+
            BRA  RN2
RN3         JSR  PUTNAME
            LDA  #1
            STA  CHANGED
            JSR  CLRMSG
            JSR  DRAWTITLE
            JMP  DRAWVALS
; KSONG: the song played, or stopped.
KSONG       TST  SONGON
            BEQ  KSONG1
            JSR  SK_STOP
            CLR  SONGON
            JSR  JAMSET
            JMP  DRAWSTAT
KSONG1      JSR  CLRVOICES
            LDX  #PAGES
            LDA  NPG
            LDB  #WBANK
            JSR  SK_PSTART
            BCS  KSONG9
            JSR  USEINST
            LDA  CURORD         ; from the order being edited
            BEQ  KSONG2
            JSR  SKORDER
KSONG2      LDA  #1
            STA  SONGON
KSONG9      JMP  DRAWSTAT
; KHUSH: silence: the song stopped, every note cut off (even one that would
; never fade, with a release of 0), the chip set up again.
KHUSH       CLR  SONGON
            JSR  JAMSET
            JSR  DRAWSTAT
            LDX  #S_HUSH
            JMP  MSG
; KQUIT: back to the shell -- asked first, with changes not saved.
KQUIT       TST  CHANGED
            BEQ  QUITNOW
            LDX  #QUITNOW
            LDY  #S_ASKQUIT
            JMP  ASK
QUITNOW     JSR  SK_OFF
            JSR  FREEPG
            LDB  PBPG
            LDA  #B_PAGE_FREE
            SWI2
            LDB  NMPG
            LDA  #B_PAGE_FREE
            SWI2
            LDB  INPG
            LDA  #B_PAGE_FREE
            SWI2
            JSR  UIEND
            LDA  #B_EXIT
            SWI2
NOMEM       JSR  UIEND
            LDX  #S_NOMEM
            LDB  #F_STDOUT
            LDA  #B_PUTS
            SWI2
            LDA  #B_EXIT
            SWI2
; ASK: the question at Y (Y or N); X what Y does.
ASK         STX  CF_DO
            TFR  Y,X
            JSR  MSG
            LDA  #2
            STA  MODE
            RTS
; CLRMSG: the message or question gone from the bottom row: the status back.
CLRMSG      CLR  MSGUP
            JMP  DRAWSTAT
; KHELP (F1): the help, over the page, until a key.
KHELP       LDA  #3
            STA  MODE
            JSR  TXCLR
            JSR  DRAWTITLE
            LDX  #HELPTXT
            JMP  DRAWLAB

;------------------------------------------------------------------------------
; Instruments.
;------------------------------------------------------------------------------
; NEWINST: a new instrument (the first's sound to start from); DUPINST: a copy
; of this one; either after the last, and the one edited.
NEWINST     LDX  #DEFINST
            LDY  #DEFNAME
            BRA  ADDINST
DUPINST     LDX  IP
            LDY  NP
ADDINST     LDA  NINST
            CMPA #MAXINST
            BHS  ADD9
            PSHS Y              ; (it and its name kept: they may be CURINST and
            LDY  #IOBUF         ; CURNAME, about to change)
            LDW  #SK_ILEN
            TFM  X+,Y+
            PULS X
            LDW  #16
            TFM  X+,Y+
            INC  NINST
            LDA  NINST
            STA  CURI
            JSR  SETIP
            LDX  #IOBUF
            LDY  IP
            LDW  #SK_ILEN
            TFM  X+,Y+
            LDY  NP
            LDW  #16
            TFM  X+,Y+
            JSR  PUTINST
            JSR  PUTNAME
            JSR  USEINST
            LDA  #1
            STA  CHANGED
            JSR  DRAWTITLE
            JMP  DRAWVALS
ADD9        LDX  #S_FULL
            JMP  MSG
; USEINST: the player's instruments SONGKIT's (as they are edited).
USEINST     LDX  #WINDOW        ; (in their page: the player sees it while it
            STX  SK_IBASE       ; reads one)
            LDA  NINST
            STA  SK_INUM
            LDA  INPG
            STA  SK_IPG
            RTS

;------------------------------------------------------------------------------
; The keys as a piano.
;------------------------------------------------------------------------------
; JAMSET: the chip for notes from the keys: every 4-op pair (so 4-op
; instruments play as they are), and rhythm mode (for the drums).
JAMSET      LDA  #$3F
            LDB  #1
            TST  PAGE           ; (the pattern page: the song's own tracks)
            BNE  JS1
            LDA  SPAIRS
            LDB  SFLAGS
JS1         JSR  SK_JSETUP
            JSR  USEINST
CLRVOICES   LDX  #VKEY
            LDB  #NVOICE
CV1         CLR  ,X+
            DECB
            BNE  CV1
            RTS
; PIANODN: key A a note? (Carry set if not.) It starts, on a voice of its
; own -- or the drum Play on says.
PIANODN     JSR  PIANOKEY
            LBCS PD9
            STA  PDKEY
            STB  PDNOTE
            LDX  #VKEY          ; (a held key repeating: nothing)
            LDE  #NVOICE
PD2         CMPA ,X+
            BEQ  PD8
            DECE
            BNE  PD2
            CLRA                ; a voice: a free one, or the next in turn
            LDX  #VKEY
PD4         TST  A,X
            BEQ  PD6
            INCA
            CMPA #NVOICE
            BLO  PD4
            LDA  VNEXT
            INCA
            CMPA #NVOICE
            BLO  PD5
            CLRA
PD5         STA  VNEXT
PD6         TST  PLAYON         ; a drum: always voice 0
            BEQ  PD7
            CLRA
PD7         LDB  PDKEY
            STB  A,X
            LDX  #VTRK
            LDB  PLAYON
            BEQ  PD7A
            PSHS A
            LDX  #DRUMTRK
            LDB  B,X
            PULS A
            LDX  #VTRK
            STB  A,X
            BRA  PD7B
PD7A        PSHS A
            LDX  #JAMTRK
            LDB  A,X
            PULS A
            LDX  #VTRK
            STB  A,X
PD7B        LDA  PDNOTE
            LDE  CURI
            JSR  SK_JAM
PD8         ANDCC #$FE
            RTS
PD9         ORCC #1
            RTS
; PIANOKEY: key A one of the piano's? B its note (1-96, at the octave OCT),
; carry clear; carry set if not. (A kept.)
PIANOKEY    LDX  #PIANO
PKY0        LDB  ,X++
            BEQ  PKYNO
            CMPA -2,X
            BNE  PKY0
            PSHS A
            LDA  OCT
            LDB  #12
            MUL
            ADDB -1,X           ; (its place in the two octaves)
            INCB
            CMPB #96
            BLS  PKY1A
            LDB  #96
PKY1A       PULS A
            ANDCC #$FE
            RTS
PKYNO       ORCC #1
            RTS
; KTAB: Tab: the other page.
KTAB        LDA  PAGE
            EORA #1
            STA  PAGE
            TST  SONGON         ; (the chip for its keys, unless the song plays)
            BNE  KTAB1
            JSR  JAMSET
KTAB1       JMP  DRAWCUR
; DRAWCUR: the page being shown, drawn.
DRAWCUR     TST  PAGE
            LBEQ DRAWPAT
            JMP  DRAWPAGE
; PIANOUP: key A let go: its note too.
PIANOUP     CLRB
PU1         LDX  #VKEY
            CMPA B,X
            BEQ  PU2
            INCB
            CMPB #NVOICE
            BLO  PU1
            RTS
PU2         CLR  B,X
            LDX  #VTRK
            LDB  B,X
            LDA  #$7F
            CLRE
            JMP  SK_JAM
; JAMREF: every note of the instrument being edited -- the keys', the song's --
; sounding as it is now.
JAMREF      JSR  PUTINST        ; (into the instruments' page first)
            LDE  CURI
            JMP  SK_IREF
JAMTRK      FCB  0,1,2,9,10,11  ; the voices: the 4-op channels
DRUMTRK     FCB  0,6,7,8,18,19  ; and Play on's drums
; The keys a piano's: each key's USB usage, then its note from the lower C.
PIANO       FCB  $1D,0,$16,1,$1B,2,$07,3,$06,4,$19,5,$0A,6,$05,7,$0B,8 ; Z S X D C V G B H
            FCB  $11,9,$0D,10,$10,11,$36,12,$0F,13,$37,14,$33,15,$38,16 ; N J M , L . ; /
            FCB  $14,12,$1F,13,$1A,14,$20,15,$08,16,$15,17,$22,18 ; Q 2 W 3 E R 5
            FCB  $17,19,$23,20,$1C,21,$24,22,$18,23,$0C,24,$26,25 ; T 6 Y 7 U I 9
            FCB  $12,26,$27,27,$13,28 ; O 0 P
            FCB  0,0

;------------------------------------------------------------------------------
; The first instrument of a new song (and of each new one): a piano, of sorts.
;------------------------------------------------------------------------------
DEFINST     FCB  0,$06,$00
            FCB  $21,$1A,$F2,$45,$01
            FCB  $21,$00,$F3,$36,$00
            FCB  $21,$1A,$F2,$45,$01
            FCB  $21,$00,$F3,$36,$00
            FCB  0,0,0,0,0,0,0,0,0
DEFNAME     FCC  "Piano"
            FCB  0,0,0,0,0,0,0,0,0,0,0
S_ASKNAME   FCC  "The instrument's name: "
            FCB  0
S_ASKQUIT   FCC  "Changes not saved: quit anyway? (Y or N)"
            FCB  0
S_HUSH      FCC  "All notes off"
            FCB  0
S_FULL      FCC  "255 instruments: no room for more"
            FCB  0
S_NOMEM     FCC  "SONGKIT: not enough memory"
            FCB  CR,LF,0
; HELPTXT: the help screen (F1): its labels, as DRAWLAB draws them.
HELPTXT
            FCB  2,2,C_LABEL
            FCC  "A song plays its orders in turn, each one a pattern of up to 128 rows; a row"
            FCB  0
            FCB  2,3,C_LABEL
            FCC  "has a cell for each track: note, instrument, volume, effect. With the cursor"
            FCB  0
            FCB  2,4,C_LABEL
            FCC  "on a note, the keyboard's letters are a piano: the note goes in, heard as it"
            FCB  0
            FCB  2,5,C_LABEL
            FCC  "does, and the cursor moves down a row. As the song plays the cursor follows"
            FCB  0
            FCB  2,6,C_LABEL
            FCC  "it, and a note typed goes in the row playing. The instrument page has all of"
            FCB  0
            FCB  2,7,C_LABEL
            FCC  "an instrument's settings, heard as they change."
            FCB  0
            FCB  2,9,C_HEAD
            FCC  "Both pages"
            FCB  0
            FCB  2,10,C_VALUE
            FCC  "Z-M Q-P"
            FCB  0
            FCB  14,10,C_LABEL
            FCC  "the piano's keys"
            FCB  0
            FCB  2,11,C_VALUE
            FCC  "[ ]"
            FCB  0
            FCB  14,11,C_LABEL
            FCC  "octave down, up"
            FCB  0
            FCB  2,12,C_VALUE
            FCC  "Space"
            FCB  0
            FCB  14,12,C_LABEL
            FCC  "play from the order; stop"
            FCB  0
            FCB  2,13,C_VALUE
            FCC  "Bksp"
            FCB  0
            FCB  14,13,C_LABEL
            FCC  "all notes off"
            FCB  0
            FCB  2,14,C_VALUE
            FCC  "Tab"
            FCB  0
            FCB  14,14,C_LABEL
            FCC  "the other page"
            FCB  0
            FCB  2,15,C_VALUE
            FCC  "^O"
            FCB  0
            FCB  14,15,C_LABEL
            FCC  "open a song or instrument"
            FCB  0
            FCB  2,16,C_VALUE
            FCC  "^S ^A"
            FCB  0
            FCB  14,16,C_LABEL
            FCC  "save the song; save as"
            FCB  0
            FCB  2,17,C_VALUE
            FCC  "^W"
            FCB  0
            FCB  14,17,C_LABEL
            FCC  "save the instrument"
            FCB  0
            FCB  2,18,C_VALUE
            FCC  "F1"
            FCB  0
            FCB  14,18,C_LABEL
            FCC  "this help"
            FCB  0
            FCB  2,19,C_VALUE
            FCC  "Esc"
            FCB  0
            FCB  14,19,C_LABEL
            FCC  "back to the shell"
            FCB  0
            FCB  2,21,C_HEAD
            FCC  "The instrument page"
            FCB  0
            FCB  2,22,C_VALUE
            FCC  "arrows"
            FCB  0
            FCB  14,22,C_LABEL
            FCC  "the setting to change"
            FCB  0
            FCB  2,23,C_VALUE
            FCC  "+ -"
            FCB  0
            FCB  14,23,C_LABEL
            FCC  "change it"
            FCB  0
            FCB  2,24,C_VALUE
            FCC  "Enter"
            FCB  0
            FCB  14,24,C_LABEL
            FCC  "on the name: rename it"
            FCB  0
            FCB  2,25,C_VALUE
            FCC  "PgUp PgDn"
            FCB  0
            FCB  14,25,C_LABEL
            FCC  "instrument before, after"
            FCB  0
            FCB  2,26,C_VALUE
            FCC  "^N ^D"
            FCB  0
            FCB  14,26,C_LABEL
            FCC  "new instrument; a copy"
            FCB  0
            FCB  42,9,C_HEAD
            FCC  "The pattern page"
            FCB  0
            FCB  42,10,C_VALUE
            FCC  "arrows"
            FCB  0
            FCB  54,10,C_LABEL
            FCC  "move; row 0 up: settings"
            FCB  0
            FCB  42,11,C_VALUE
            FCC  "PgUp PgDn"
            FCB  0
            FCB  54,11,C_LABEL
            FCC  "16 rows up, down"
            FCB  0
            FCB  42,12,C_VALUE
            FCC  "Home End"
            FCB  0
            FCB  54,12,C_LABEL
            FCC  "the first row, the last"
            FCB  0
            FCB  42,13,C_VALUE
            FCC  "1"
            FCB  0
            FCB  54,13,C_LABEL
            FCC  "the key let go (note off)"
            FCB  0
            FCB  42,14,C_VALUE
            FCC  "0-9 A-F"
            FCB  0
            FCB  54,14,C_LABEL
            FCC  "a digit (effects: 0-9 A-Z)"
            FCB  0
            FCB  42,15,C_VALUE
            FCC  "Del"
            FCB  0
            FCB  54,15,C_LABEL
            FCC  "the field cleared"
            FCB  0
            FCB  42,16,C_VALUE
            FCC  "Ins ^Ins"
            FCB  0
            FCB  54,16,C_LABEL
            FCC  "a row in: this track, all"
            FCB  0
            FCB  42,17,C_VALUE
            FCC  "Sh+Del ^Del"
            FCB  0
            FCB  54,17,C_LABEL
            FCC  "a row out: this track, all"
            FCB  0
            FCB  42,18,C_VALUE
            FCC  "+ -"
            FCB  0
            FCB  54,18,C_LABEL
            FCC  "pattern played; a setting"
            FCB  0
            FCB  42,19,C_VALUE
            FCC  "^Up ^Dn"
            FCB  0
            FCB  54,19,C_LABEL
            FCC  "the order before, after"
            FCB  0
            FCB  42,20,C_VALUE
            FCC  "^N ^D"
            FCB  0
            FCB  54,20,C_LABEL
            FCC  "new pattern; a copy of it"
            FCB  0
            FCB  42,21,C_VALUE
            FCC  "^R ^X"
            FCB  0
            FCB  54,21,C_LABEL
            FCC  "order again; order out"
            FCB  0
            FCB  42,22,C_VALUE
            FCC  "^Lt ^Rt"
            FCB  0
            FCB  54,22,C_LABEL
            FCC  "the instrument put in"
            FCB  0
            FCB  42,23,C_VALUE
            FCC  "Enter"
            FCB  0
            FCB  54,23,C_LABEL
            FCC  "on title, author: retype"
            FCB  0
            FCB  2,28,C_LABEL
            FCC  "The mouse: a click picks a field; the wheel over one changes it."
            FCB  0
            FCB  2,29,C_MSG
            FCC  "Any key: back to the page"
            FCB  0
            FCB  $FF,$FF
;------------------------------------------------------------------------------
            INCLUDE "sk_ui.asm"
            INCLUDE "sk_inst.asm"
            INCLUDE "sk_file.asm"
            INCLUDE "sk_pat.asm"
            INCLUDE "sk_play.asm"
;------------------------------------------------------------------------------
; Variables.
;------------------------------------------------------------------------------
MODE        RMB  1          ; 0 editing; 1 a line being typed; 2 a question; 3 the help
MSGUP       RMB  1          ; a message on the bottom row (the status back at the next key)
PAGE        RMB  1          ; the page shown: 0 the patterns', 1 the instruments'
PBPG        RMB  1          ; the pattern buffer's page, the names', the
NMPG        RMB  1          ; instruments'
INPG        RMB  1
PR_DO       RMB  2          ; what Enter does, after typing
CF_DO       RMB  2          ; what Y does, to a question
CHANGED     RMB  1          ; changes not saved
SONGON      RMB  1          ; the song playing
NINST       RMB  1          ; the instruments: how many, the one edited
CURI        RMB  1
IP          RMB  2          ; it and its name (CURINST, CURNAME: copies of the
NP          RMB  2          ; instruments' and names' pages')
CURINST     RMB  SK_ILEN
CURNAME     RMB  17
NAMETMP     RMB  16
PNI         RMB  1
CURF        RMB  1          ; the field being edited
OCT         RMB  1          ; the keys' octave
PLAYON      RMB  1          ; 0 a channel, 1-5 a drum
VKEY        RMB  NVOICE     ; each voice's key (0: free), and track
VTRK        RMB  NVOICE
VNEXT       RMB  1
PDKEY       RMB  1
PDNOTE      RMB  1
FTMP        RMB  1          ; (sk_inst.asm's)
FTVAL       RMB  1
FTSTEP      RMB  1
FTMIN       RMB  1
FTMAX       RMB  1
FTROW       RMB  1
FTCOL       RMB  1
FTOPS       RMB  1
FTAT        RMB  1
FTNEW       RMB  1
TXFG        RMB  1          ; (sk_ui.asm's)
TXBG        RMB  1
TXCOL       RMB  1
TXTMP       RMB  2
TXN         RMB  1
MOUSEX      RMB  2
MOUSEY      RMB  2
BUTTONS     RMB  1
PRESSED     RMB  1
WHEEL       RMB  1
KEYMODS     RMB  1
UI_BITS     RMB  2
UI_EDGE     RMB  2
PR_ASK      RMB  2
PR_FILE     RMB  1
PR_MAXL     RMB  1
PR_LEN      RMB  1
PR_BUF      RMB  PR_MAX+1
SONGNAME    RMB  PR_MAX+1   ; (sk_file.asm's)
FNAME       RMB  PR_MAX+5
FH          RMB  1
WHOME       RMB  1
PAGES       RMB  MAXPG      ; the song: its pages, how many
NPG         RMB  1
NEWPG       RMB  MAXPG      ; (a song being opened)
NNPG        RMB  1
SSIZE       RMB  3          ; its bytes
SNEW        RMB  3          ; (a song being opened: its bytes)
LFLAST      RMB  2
SPREM       RMB  3
NORD        RMB  1          ; what its header says: orders, patterns, instruments
NPAT        RMB  1
OLDNI       RMB  1
ITAB        RMB  2          ; where its instruments are
DSTART      RMB  2          ;   and its patterns (to DEND)
DEND        RMB  3
NAMEOFS     RMB  3          ;   and its instruments' names (0: none)
RPG         RMB  1          ; reading the pages: the page, the next byte
RPTR        RMB  2
SPFROM      RMB  3
SPTO        RMB  3
SPLEN       RMB  2
DELTA       RMB  2
HBUF        RMB  80
SPAIRS      RMB  1          ; the song's 4-op pairs and flags (its header's)
SFLAGS      RMB  1
CURORD      RMB  1          ; (sk_pat.asm's) the order being edited, its pattern
CURPAT      RMB  1
PATOK       RMB  1          ;   (in the buffer, to edit), its rows,
PROWS       RMB  1
PATOFS      RMB  3          ;   where it is in the song, and how long
PATLEN      RMB  2
CROW        RMB  1          ; the cursor: row, track (of TLIST), field
CTRK        RMB  1
CCOL        RMB  1
TOPROW      RMB  1          ; the first row shown, the first track
LTRK        RMB  1
AREA        RMB  1          ; 0 the grid, 1 the settings (SETF the one picked)
SETF        RMB  1
OTOP        RMB  1          ; the first order shown
PLORD       RMB  1          ; where the song is playing, as shown ($FF: not)
PLROW       RMB  1
PPOLD       RMB  2
RQR         RMB  1          ; the grid's rows still to draw: the next, how many
RQN         RMB  1
TLIST       RMB  SK_NTRK    ; the song's tracks, how many
NTL         RMB  1
MROW        RMB  1          ; the mouse's cell
MCOL        RMB  1
DRR         RMB  1          ; (drawing)
DRS         RMB  1
DRN         RMB  1
DRF         RMB  1
DRBG        RMB  1
DRX         RMB  2
DGR         RMB  1
DGN         RMB  1
PNIB        RMB  1          ; (typing)
PKIND       RMB  1
PALL        RMB  1
PTMP        RMB  1
PKROW       RMB  1          ; (packing, unpacking)
PKN         RMB  1
PKLEN       RMB  2
RFLAG       RMB  1
RENT        RMB  1
RGUARD      RMB  1
RJUNK       RMB  5
WOFS        RMB  3
IPREM       RMB  2
IPN         RMB  2
IOPK        RMB  2
APSIZE      RMB  2
SLAT        RMB  3          ; (SPLICE)
SLOLD       RMB  2
SLNEW       RMB  2
SLD         RMB  2
SLTHR       RMB  3
SLSRC       RMB  3
SLDST       RMB  3
SLLEN       RMB  3
SLCF        RMB  3
SLCT        RMB  3
SLN         RMB  2
ROWLEN      RMB  MAXROWS    ; each row's cells' bytes, packed
RBUF        RMB  ROWB       ; a row read
WBUF        RMB  6*SK_NTRK+4 ; a row packed
; (The large ones are only addresses, after the program's last byte.)
IOBUF       equ  *          ; 1024
VAREND      equ  IOBUF+1024
            IFGT VAREND-(KIT_STACK-512)
            ERROR "SONGKIT's variables reach its stack"
            ENDC

            END  START
