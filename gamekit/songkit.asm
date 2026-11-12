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
KIT_BASE    equ  $C000      ; the core: bank 3, with the variables and the stack
KIT_STACK   equ  $EF00
WBANK       equ  1          ; the song's pages (and the others), seen through bank 1
WINDOW      equ  $4000
OBANK       equ  2          ; the overlays, seen through bank 2 one at a time
OWIN        equ  $8000
OV_EDIT     equ  0          ; the overlays: the two pages' editing,
OV_FILE     equ  1          ;   the files,
OV_HELP     equ  2          ;   the help,
OV_BLOCK    equ  3          ;   blocks of a pattern copied, pasted (the clipboard too)
NOVL        equ  4
MAXPG       equ  32         ; 512KB of song at most
MAXINST     equ  255
NVOICE      equ  6          ; notes played at once from the keys
;------------------------------------------------------------------------------
; SONGKIT.COM is bigger than 64KB could hold, in time: its core (this file, to
; the variables' end) is the program's body, loaded at $C000 (bank 3); after it
; in the file come the overlays, each the code for $8000 (bank 2) -- loaded
; into pages of their own as it starts (EXE_MORE: the file is left open for
; it), one of them in bank 2 at a time. The core calls into an overlay through
; a stub (O_name, below: OVCALL), which puts that overlay in bank 2 and the
; caller's back after; an overlay calls the core as it likes, and another
; overlay through a stub too. Bank 1 is the window, for the song's pages and
; the editor's others.
;------------------------------------------------------------------------------
            ORG  KIT_BASE-EXE_HDRSIZE-2
            FDB  EXE_MAGIC      ; the program header
            FDB  KIT_BASE       ; load address
            FDB  START          ; entry
            FDB  EXE_MORE       ; flags: the overlays after the body
            FDB  COREEND-KIT_BASE ; the body: the core
;------------------------------------------------------------------------------
START       LDS  #KIT_STACK
            STB  OVFH           ; (the file, open at the first overlay)
            JSR  OVLOAD
            LBCS NOOVL
            CLR  NPG
            CLR  NNPG
            CLR  MODE
            CLR  PAGE
            CLR  SETF
            CLR  RQN
            CLR  MSGUP
            CLR  RECORD         ; Record off; the song's end back to its start in
            LDA  #1             ; the editor; no pattern looped, no track muted
            STA  SK_WRAP
            CLR  LOOPPAT
            CLR  SK_PLOOP
            CLR  RKEY
            CLR  MUTES
            CLR  MUTES+1
            CLR  MUTES+2
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
            JSR  O_NEWSONG
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
            JSR  O_OPENNAMED      ; (its name in PR_BUF)
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
            JSR  O_DRAWSTAT
MAIN1       LDA  MODE           ; (the help over the page: nothing drawn under it)
            CMPA #3
            BEQ  MAIN2
            JSR  O_PLAYPOS
            JSR  O_RQSTEP         ; (the grid's rows not drawn yet)
            TST  MODE           ; (a line being typed, a question: the mouse
            BNE  MAIN2          ; left until it's done, its clicks kept)
            JSR  POLLIN
            TST  PAGE
            BNE  MAIN1A
            JSR  O_PMOUSE
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
            JSR  O_FHIT
            BCS  MOUSE2
            JSR  PICKF
            LDA  CURF
            BNE  MOUSE2
            JMP  RENAME
MOUSE2      LDA  WHEEL
            BEQ  MOUSE9
            JSR  O_FHIT
            BCS  MOUSE9
            JSR  PICKF
            LDA  #1
            TST  WHEEL
            BPL  MOUSE3
            LDA  #-1
MOUSE3      JMP  O_FSTEP
MOUSE9      RTS
; PICKF: field A the one being edited.
PICKF       LDB  CURF
            STA  CURF
            TFR  B,A
            JSR  O_DRAWF
            LDA  CURF
            JMP  O_DRAWF

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
            LBMI KD9
            CLR  MODE
            PSHS A
            JSR  CLRMSG
            PULS A
            CMPA #$1C           ; Y
            BNE  KD9
            LDX  CF_DO          ; (in the overlay that asked)
            LDA  CF_OV
            JMP  OVGO
KDTYPE      JSR  PRKEY          ; a line of typing
            TSTA
            BEQ  KD9
            CLR  MODE
            PSHS A
            JSR  CLRMSG
            PULS A
            CMPA #1
            BNE  KD9
            LDX  PR_DO
            LDA  PR_OV
            JMP  OVGO
KDHELP      TSTB                ; the help: a key closes it (one let go: a note's end)
            BMI  KD1A
            CLR  MODE
            TST  PAGE
            LBEQ O_REDRAWUI
            JMP  O_DRAWPAGE
KD1         TSTB                ; a key let go: a note's end
            BPL  KD1B
KD1A        JSR  O_PRECUP         ; (recording: the note's end put in)
            JMP  PIANOUP
KD1B        TST  MSGUP          ; (a message: the status back, from the next key)
            BEQ  KD1C
            PSHS D
            JSR  CLRMSG
            PULS D
KD1C        CMPA #K_F1
            LBEQ O_KHELP
KD2         TST  PAGE           ; (the pattern page's own)
            LBEQ O_PKEY
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
            FDB  O_OPEN
            FCB  $16            ; ^S
            FDB  O_SAVE
            FCB  $04            ; ^A
            FDB  O_SAVEAS
            FCB  $1A            ; ^W
            FDB  O_SAVEINS
            FCB  0
KUP         CLRA
            JMP  O_FMOVE
KDOWN       LDA  #1
            JMP  O_FMOVE
KLEFT       LDA  #2
            JMP  O_FMOVE
KRIGHT      LDA  #3
            JMP  O_FMOVE
KPLUS       LDA  #1
            JMP  O_FSTEP
KMINUS      LDA  #-1
            JMP  O_FSTEP
KOCTDN      LDA  OCT
            BEQ  KOCT9
            DEC  OCT
            JMP  O_DRAWSTAT
KOCTUP      LDA  OCT
            CMPA #7
            BHS  KOCT9
            INC  OCT
            JMP  O_DRAWSTAT
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
            LBEQ O_DRAWSTAT
            JMP  O_DRAWVALS
KENTER      TST  CURF           ; on the name: rename it
            BNE  KOCT9
RENAME      LDX  #S_ASKNAME
            LDY  NP
            CLRA
            JSR  PRSTART
            LDX  #RENAMED
            JSR  SETPRDO
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
            JSR  O_DRAWTITLE
            JMP  O_DRAWVALS
; KSONG: the song played, or stopped.
KSONG       TST  SONGON
            BEQ  KSONG1
            JSR  SK_STOP
            CLR  SONGON
            JSR  JAMSET
            JMP  O_DRAWSTAT
KSONG1      JSR  CLRVOICES
            LDX  #PAGES
            LDA  NPG
            LDB  #WBANK
            JSR  SK_PSTART
            BCS  KSONG9
            LDD  MUTES          ; (the tracks muted, the player's to know)
            STD  SK_MUTE
            LDA  MUTES+2
            STA  SK_MUTE+2
            JSR  USEINST
            LDA  CURORD         ; from the order being edited
            BEQ  KSONG2
            JSR  SKORDER
KSONG2      LDA  #1
            STA  SONGON
KSONG9      JMP  O_DRAWSTAT
; KHUSH: silence: the song stopped, every note cut off (even one that would
; never fade, with a release of 0), the chip set up again.
KHUSH       CLR  SONGON
            JSR  JAMSET
            JSR  O_DRAWSTAT
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
            JSR  OVFREE
            LDA  #B_EXIT
            SWI2
NOMEM       JSR  UIEND
            JSR  OVFREE
            LDX  #S_NOMEM
NOMEM1      LDB  #F_STDOUT
            LDA  #B_PUTS
            SWI2
            LDA  #B_EXIT
            SWI2
NOOVL       LDX  #S_NOMEM       ; (no page for an overlay, or the file short)
            CMPA #ERR_NOSPACE
            BEQ  NOMEM1
            LDX  #S_BADOVL
            BRA  NOMEM1
; ASK: the question at Y (Y or N); X what Y does (in the caller's overlay).
ASK         STX  CF_DO
            LDA  CUROV
            STA  CF_OV
            TFR  Y,X
            JSR  MSG
            LDA  #2
            STA  MODE
            RTS
; CLRMSG: the message or question gone from the bottom row: the status back.
CLRMSG      CLR  MSGUP
            JMP  O_DRAWSTAT
;------------------------------------------------------------------------------
; The overlays.
;------------------------------------------------------------------------------
; OVLOAD: each overlay, from the file (OVFH: open at the first), into a page of
; its own; the file closed, OV_EDIT in bank 2. Carry set (A: ERR_NOSPACE, no
; page for one; or ERR_EOF, the file ends too soon) if not -- the pages given
; back.
OVLOAD      LDB  #OBANK         ; (bank 2's own page, for after)
            LDA  #B_BANK_GET
            SWI2
            STA  OHOME
            LDA  #$FF
            STA  CUROV
            CLR  NOVPG
OL1         LDA  #B_PAGE_ALLOC
            SWI2
            BCS  OLERR
            LDX  #OVPG
            LDB  NOVPG
            STA  B,X
            INC  NOVPG
            TFR  A,E
            LDB  #OBANK
            LDA  #B_BANK_SET
            SWI2
            LDB  NOVPG          ; its length
            DECB
            LSLB
            LDX  #OVLEN
            LDY  B,X
            PSHS Y
            LDX  #OWIN
            LDB  OVFH
            LDA  #B_FREAD
            SWI2
            BCS  OLSHORT
            CMPX ,S++
            BNE  OLSHORT1
            LDA  NOVPG
            CMPA #NOVL
            BLO  OL1
            BSR  OLCLOSE
            LDA  #OV_EDIT
            JSR  OVMAP
            ANDCC #$FE
            RTS
OLSHORT     LEAS 2,S
OLSHORT1    LDA  #ERR_EOF
OLERR       PSHS A
            BSR  OLCLOSE
            BSR  OVFREE
            PULS A
            ORCC #1
            RTS
OLCLOSE     LDB  OVFH
            LDA  #B_FCLOSE_NAME
            SWI2
            RTS
; OVLEN: each overlay's length, in the file's order.
OVLEN       FDB  EDITEND-OWIN,FILEEND-OWIN,HELPEND-OWIN,BLOCKEND-OWIN
; OVFREE: bank 2 its own page again, the overlays' pages given back.
OVFREE      LDB  #OBANK
            LDE  OHOME
            LDA  #B_BANK_SET
            SWI2
            LDA  #$FF
            STA  CUROV
OF1         TST  NOVPG
            BEQ  OF9
            DEC  NOVPG
            LDX  #OVPG
            LDB  NOVPG
            LDB  B,X
            LDA  #B_PAGE_FREE
            SWI2
            BRA  OF1
OF9         RTS
; OVMAP: overlay A in bank 2 (if it isn't already). (All kept but CC.)
OVMAP       CMPA CUROV
            BEQ  OM9
            PSHS D,X
            PSHSW
            STA  CUROV
            LDX  #OVPG
            LDE  A,X
            LDB  #OBANK
            LDA  #B_BANK_SET
            SWI2
            PULSW
            PULS D,X
OM9         RTS
; OVCALL: from a stub (JSR OVCALL, then the overlay, FCB, and the address in
; it, FDB): that called with its overlay in bank 2, the caller's put back
; after -- every register passed to it, and back from it, as it left them.
OVCALL      PSHS CC,D,X         ; (5,S: the stub's own: what follows its JSR)
            LDX  5,S
            LDA  CUROV          ; the caller's overlay kept there instead
            STA  5,S
            LDA  ,X
            LDX  1,X
            STX  OVADR
            JSR  OVMAP
            PULS CC,D,X
            JSR  [OVADR]
OVBACK      PSHS CC,A           ; (2,S: the caller's overlay)
            LDA  2,S
            JSR  OVMAP
            PULS CC,A
            LEAS 2,S
            RTS                 ; (to the stub's caller)
; OVGO: X in overlay A, called (the caller's overlay put back after) -- for
; what was kept to do later, its overlay kept with it (PR_DO, CF_DO).
OVGO        STX  OVADR
            LDB  CUROV
            EXG  A,B
            PSHS D              ; (as OVCALL leaves it: the caller's, then junk)
            TFR  B,A
            JSR  OVMAP
            JSR  [OVADR]
            BRA  OVBACK
; SETPRDO: PR_DO X, in the caller's overlay. (All kept.)
SETPRDO     STX  PR_DO
            PSHS A
            LDA  CUROV
            STA  PR_OV
            PULS A,PC
; The overlays' entries, for the core and for each other: O_name calls name.
O_DRAWF     JSR  OVCALL
            FCB  OV_EDIT
            FDB  DRAWF
O_DRAWPAGE  JSR  OVCALL
            FCB  OV_EDIT
            FDB  DRAWPAGE
O_DRAWSTAT  JSR  OVCALL
            FCB  OV_EDIT
            FDB  DRAWSTAT
O_DRAWTITLE JSR  OVCALL
            FCB  OV_EDIT
            FDB  DRAWTITLE
O_DRAWVALS  JSR  OVCALL
            FCB  OV_EDIT
            FDB  DRAWVALS
O_FHIT      JSR  OVCALL
            FCB  OV_EDIT
            FDB  FHIT
O_FMOVE     JSR  OVCALL
            FCB  OV_EDIT
            FDB  FMOVE
O_FSTEP     JSR  OVCALL
            FCB  OV_EDIT
            FDB  FSTEP
O_DRAWPAT   JSR  OVCALL
            FCB  OV_EDIT
            FDB  DRAWPAT
O_PKEY      JSR  OVCALL
            FCB  OV_EDIT
            FDB  PKEY
O_PLAYPOS   JSR  OVCALL
            FCB  OV_EDIT
            FDB  PLAYPOS
O_PMOUSE    JSR  OVCALL
            FCB  OV_EDIT
            FDB  PMOUSE
O_PRECUP    JSR  OVCALL
            FCB  OV_EDIT
            FDB  PRECUP
O_REDRAWUI  JSR  OVCALL
            FCB  OV_EDIT
            FDB  REDRAWUI
O_RQSTEP    JSR  OVCALL
            FCB  OV_EDIT
            FDB  RQSTEP
O_MKTLIST   JSR  OVCALL
            FCB  OV_EDIT
            FDB  MKTLIST
O_PATLOAD   JSR  OVCALL
            FCB  OV_EDIT
            FDB  PATLOAD
O_NEWSONG   JSR  OVCALL
            FCB  OV_FILE
            FDB  NEWSONG
O_OPEN      JSR  OVCALL
            FCB  OV_FILE
            FDB  OPEN
O_OPENNAMED JSR  OVCALL
            FCB  OV_FILE
            FDB  OPENNAMED
O_SAVE      JSR  OVCALL
            FCB  OV_FILE
            FDB  SAVE
O_SAVEAS    JSR  OVCALL
            FCB  OV_FILE
            FDB  SAVEAS
O_SAVEINS   JSR  OVCALL
            FCB  OV_FILE
            FDB  SAVEINS
O_KHELP     JSR  OVCALL
            FCB  OV_HELP
            FDB  KHELP
O_BCOPY     JSR  OVCALL
            FCB  OV_BLOCK
            FDB  BCOPY
O_BCLEAR    JSR  OVCALL
            FCB  OV_BLOCK
            FDB  BCLEAR
O_BPASTE    JSR  OVCALL
            FCB  OV_BLOCK
            FDB  BPASTE

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
            JSR  O_DRAWTITLE
            JMP  O_DRAWVALS
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
            LBEQ O_DRAWPAT
            JMP  O_DRAWPAGE
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
S_BADOVL    FCC  "SONGKIT: SONGKIT.COM is damaged (its overlays can't be read)"
            FCB  CR,LF,0
;------------------------------------------------------------------------------
            INCLUDE "sk_core.asm"
            INCLUDE "sk_ui.asm"
            INCLUDE "sk_play.asm"
;------------------------------------------------------------------------------
; Variables.
;------------------------------------------------------------------------------
MODE        RMB  1          ; 0 editing; 1 a line being typed; 2 a question; 3 the help
MSGUP       RMB  1          ; a message on the bottom row (the status back at the next key)
RECORD      RMB  1          ; Record: notes (and the rest) go in; 0, the keys only play
LOOPPAT     RMB  1          ; Loop pattern: the order playing played again
MUTES       RMB  3          ; the tracks muted, a bit each (as SK_MUTE)
MTRK        RMB  1          ; (TOGMUTE's track)
RKEY        RMB  1          ; recording as the song plays: the key of the note put
RTRK        RMB  1          ;   in last (0: none), its track (shown), row and order
RROW        RMB  1
RORD        RMB  1
PNEXT       RMB  1          ; (PRECUP's: the note's end in the row after)
PTGT        RMB  1
PSVROW      RMB  1
PSVTRK      RMB  1
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
PR_ASK      RMB  PR_ASKN    ; (PRSTART's question, copied)
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
OVFH        RMB  1          ; the overlays: the file (as it starts), bank 2's own page,
OHOME       RMB  1
CUROV       RMB  1          ;   the one in bank 2 ($FF: none), their pages,
NOVPG       RMB  1
OVPG        RMB  NOVL
OVADR       RMB  2          ;   (OVCALL's)
PR_OV       RMB  1          ; PR_DO's overlay, CF_DO's
CF_OV       RMB  1
SELON       RMB  1          ; a block selected (sk_pat.asm's): its corners,
SELR        RMB  1          ;   where it began and where it's taken to (the
SELT        RMB  1          ;   cursor, as it was then)
SELR2       RMB  1
SELT2       RMB  1
SBR0        RMB  1          ; the block from them (SELBOX): its rows, tracks
SBR1        RMB  1
SBT0        RMB  1
SBT1        RMB  1
OBON        RMB  1          ; (as it was drawn before: SELSAVE)
OBR0        RMB  1
OBR1        RMB  1
OBT0        RMB  1
OBT1        RMB  1
SDR         RMB  1          ; (SELDIFF's)
SDQ         RMB  1
DRAG        RMB  1          ; a block being dragged with the mouse
DRBGR       RMB  1          ; (DRAWROW's: the row's own background)
CBROWS      RMB  1          ; the clipboard's rows (0: empty) and tracks
CBTRKS      RMB  1
BKCUT       RMB  1          ; (sk_block.asm's)
BKR         RMB  1
BKNR        RMB  1
BKNT        RMB  1
BKRB        RMB  1
BKI         RMB  1
BKJ         RMB  1
COREEND     equ  *          ; (the core's last byte: the program's body is to here)
; (The large ones are only addresses, after the program's last byte.)
IOBUF       equ  *          ; 1024
VAREND      equ  IOBUF+1024
            IFGT VAREND-(KIT_STACK-512)
            ERROR "SONGKIT's variables reach its stack"
            ENDC

;------------------------------------------------------------------------------
; The overlays: each one's code at $8000 (bank 2), after the core in the file.
;------------------------------------------------------------------------------
            ORG  OWIN           ; OV_EDIT: the two pages
            INCLUDE "sk_inst.asm"
            INCLUDE "sk_pat.asm"
EDITEND     equ  *
            IFGT EDITEND-(OWIN+$4000)
            ERROR "OV_EDIT is more than 16KB"
            ENDC
            ORG  OWIN           ; OV_FILE: the files
            INCLUDE "sk_file.asm"
FILEEND     equ  *
            IFGT FILEEND-(OWIN+$4000)
            ERROR "OV_FILE is more than 16KB"
            ENDC
            ORG  OWIN           ; OV_HELP: the help
            INCLUDE "sk_help.asm"
HELPEND     equ  *
            IFGT HELPEND-(OWIN+$4000)
            ERROR "OV_HELP is more than 16KB"
            ENDC
            ORG  OWIN           ; OV_BLOCK: blocks, and the clipboard after them
            INCLUDE "sk_block.asm"
BLOCKEND    equ  *
CLIP        equ  BLOCKEND       ; (only addresses: not in the file)
CLIPEND     equ  CLIP+MAXROWS*SK_NTRK*5
            IFGT CLIPEND-(OWIN+$4000)
            ERROR "OV_BLOCK and its clipboard are more than 16KB"
            ENDC

            END  START
