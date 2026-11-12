;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 game kit
;    FILE: sk_inst.asm
;
; SONGKIT's instrument page: every setting of the instrument being edited, as
; a field, its value from the instrument's 32 bytes (gamekit/README.md); the
; one being edited (CURF) lit up. The arrows move between them, + and - (and
; the mouse's wheel over one) change its value, a click picks one.
;
;   DRAWPAGE   the whole page: its labels, then DRAWVALS
;   DRAWVALS   every field's value, and what depends on them
;   FSTEP      A: +1 or -1: the field being edited changed by that
;   FMOVE      A: 0 up, 1 down, 2 left, 3 right: another field to edit
;   FHIT       the field under the mouse -> A (carry set: none)
;------------------------------------------------------------------------------
K_NUM       equ  0          ; the kinds of field: a number
K_YN        equ  1          ;   no or yes
K_WAVE      equ  2          ;   a waveform
K_OPS       equ  3          ;   2 or 4 operators
K_ALG       equ  4          ;   the connection (the 4-op algorithm)
K_NOTE      equ  5          ;   the fixed note, or the transpose
K_FINE      equ  6          ;   fine tune, signed
K_PAN       equ  7          ;   the outputs
K_PLAY      equ  8          ;   what the keys play it on (SONGKIT's, not the instrument's)
K_NAME      equ  9          ;   its name
FSIZE       equ  12         ; a field (FIELDS, below)
F_ROW       equ  0
F_COL       equ  1
F_W         equ  2
F_KIND      equ  3
F_BYTE      equ  4
F_SH        equ  5
F_MASK      equ  6
F_OP        equ  7
F_UP        equ  8          ; (then down, left and right)
F_FIX       equ  4          ; the fixed-note field (its number)

; SETIP: IP and NP, the instrument being edited and its name (copies, in
; CURINST and CURNAME, of the instruments' and names' pages': PUTINST and
; PUTNAME put them back).
SETIP       LDX  #CURINST
            STX  IP
            LDX  #CURNAME
            STX  NP
            BSR  INSTAT
            LDY  #CURINST
            LDW  #SK_ILEN
            TFM  X+,Y+
            BSR  NAMEAT
            LDY  #CURNAME
            LDW  #16
            TFM  X+,Y+
            CLR  ,Y
            RTS
PUTINST     BSR  INSTAT
            TFR  X,Y
            LDX  #CURINST
            LDW  #SK_ILEN
            TFM  X+,Y+
            RTS
; INSTAT: X, instrument CURI in the instruments' page (in the window).
INSTAT      JSR  IMAP
            LDA  CURI
            DECA
            LDB  #SK_ILEN
            MUL
            ADDD #WINDOW
            TFR  D,X
            RTS
PUTNAME     BSR  NAMEAT
            TFR  X,Y
            LDX  #CURNAME
            LDW  #16
            TFM  X+,Y+
            RTS
; NAMEAT: X, instrument CURI's name in the names' page (in the window).
NAMEAT      JSR  NMAP
            LDA  CURI
            DECA
            LDB  #16
            MUL
            ADDD #WINDOW
            TFR  D,X
            RTS
; FADDR: Y, field A. (A kept.)
FADDR       PSHS A
            LDB  #FSIZE
            MUL
            ADDD #FIELDS
            TFR  D,Y
            PULS A,PC
; FVIS: field Y shown? Carry set if not: operators 3 and 4 of a 2-op one.
FVIS        LDA  F_OP,Y
            CMPA #$FF
            BEQ  FVIS1
            CMPA #2
            BLO  FVIS1
            LDX  IP
            LDA  ,X
            BITA #1
            BNE  FVIS1
            ORCC #1
            RTS
FVIS1       ANDCC #$FE
            RTS

;------------------------------------------------------------------------------
; A field's value: FGET -> A, FSET A, FRANGE -> A the least, B the most.
;------------------------------------------------------------------------------
FGET        LDB  F_KIND,Y
            LDX  IP
            CMPB #K_ALG
            BEQ  FGALG
            CMPB #K_NOTE
            BEQ  FGNOTE
            CMPB #K_FINE
            BEQ  FGFINE
            CMPB #K_PAN
            BEQ  FGPAN
            CMPB #K_PLAY
            BEQ  FGPLAY
            CMPB #K_NAME
            BEQ  FGNONE
            LDB  F_BYTE,Y       ; (bits of a byte)
            LDA  B,X
            LDB  F_SH,Y
            BEQ  FG2
FG1         LSRA
            DECB
            BNE  FG1
FG2         ANDA F_MASK,Y
            RTS
FGALG       LDA  1,X            ; 2-op: the connection; 4-op: both of them
            ANDA #1
            LDB  ,X
            BITB #1
            BEQ  FG9
            LSLA
            LDB  2,X
            ANDB #1
            STB  FTMP
            ORA  FTMP
FG9         RTS
FGNOTE      LDA  23,X
            RTS
FGFINE      LDA  24,X
            RTS
FGPAN       LDA  25,X
            ANDA #$30
            CMPA #$10
            BEQ  FGPAN1
            CMPA #$20
            BEQ  FGPAN2
FGNONE      CLRA
            RTS
FGPAN1      LDA  #1
            RTS
FGPAN2      LDA  #2
            RTS
FGPLAY      LDA  PLAYON
            RTS

FSET        STA  FTVAL
            LDB  F_KIND,Y
            LDX  IP
            CMPB #K_ALG
            BEQ  FSALG
            CMPB #K_NOTE
            BEQ  FSNOTE
            CMPB #K_FINE
            BEQ  FSFINE
            CMPB #K_PAN
            BEQ  FSPAN
            CMPB #K_PLAY
            BEQ  FSPLAY
            CMPB #K_NAME
            BEQ  FS9
            LDA  F_MASK,Y       ; bits of a byte
            STA  FTMP
            LDA  FTVAL
            ANDA FTMP
            STA  FTVAL
            LDB  F_SH,Y
            BEQ  FS2
FS1         LSL  FTMP
            LSL  FTVAL
            DECB
            BNE  FS1
FS2         LDB  F_BYTE,Y
            ABX
            LDA  FTMP
            COMA
            ANDA ,X
            ORA  FTVAL
            STA  ,X
FS9         RTS
FSALG       LDB  ,X             ; 4-op: bit 1 the first connection, bit 0 the second
            BITB #1
            BEQ  FSALG2
            LDA  FTVAL
            ANDA #1
            STA  FTMP
            LDA  2,X
            ANDA #$FE
            ORA  FTMP
            STA  2,X
            LDA  FTVAL
            LSRA
            STA  FTVAL
FSALG2      LDA  FTVAL
            ANDA #1
            STA  FTMP
            LDA  1,X
            ANDA #$FE
            ORA  FTMP
            STA  1,X
            RTS
FSNOTE      LDA  FTVAL
            STA  23,X
            RTS
FSFINE      LDA  FTVAL
            STA  24,X
            RTS
FSPAN       LDB  FTVAL
            LDX  #PANV
            LDA  B,X
            LDX  IP
            STA  25,X
            RTS
FSPLAY      LDA  FTVAL
            STA  PLAYON
            RTS
PANV        FCB  $30,$10,$20

FRANGE      LDB  F_KIND,Y
            LDX  IP
            CMPB #K_ALG
            BEQ  FRALG
            CMPB #K_NOTE
            BEQ  FRNOTE
            CMPB #K_FINE
            BEQ  FRFINE
            CMPB #K_PAN
            BEQ  FRPAN
            CMPB #K_PLAY
            BEQ  FRPLAY
            CLRA
            LDB  F_MASK,Y
            RTS
FRALG       LDA  ,X             ; 2-op: 0-1; 4-op: 0-3
            BITA #1
            BEQ  FRALG1
            LDD  #$0003
            RTS
FRALG1      LDD  #$0001
            RTS
FRNOTE      LDA  ,X             ; a fixed note: C-0 to B-7; a transpose: 4 octaves
            BITA #2
            BEQ  FRNOTE1
            LDD  #$0160
            RTS
FRNOTE1     LDD  #$D030
            RTS
FRFINE      LDD  #$E020
            RTS
FRPAN       LDD  #$0002
            RTS
FRPLAY      LDD  #$0005
            RTS

;------------------------------------------------------------------------------
; Editing.
;------------------------------------------------------------------------------
; FSTEP: the field being edited, A (+1 or -1) further on: kept to its range;
; no or yes the other.
FSTEP       STA  FTSTEP
            LDA  CURF
            JSR  FADDR
            JSR  FVIS
            BCS  FST9
            LDB  F_KIND,Y
            CMPB #K_NAME
            BEQ  FST9
            CMPB #K_YN
            BNE  FST1
            JSR  FGET
            EORA #1
            BRA  FST4
FST1        JSR  FRANGE
            STD  FTMIN
            JSR  FGET
            ADDA FTSTEP
            CMPA FTMIN
            BGE  FST2
            LDA  FTMIN
FST2        CMPA FTMAX
            BLE  FST4
            LDA  FTMAX
FST4        JSR  FSET
            LDA  CURF           ; a fixed note made, or unmade: its note too
            CMPA #F_FIX
            BNE  FST5
            LDX  IP
            CLR  23,X           ; (no transpose)
            LDA  ,X
            BITA #2
            BEQ  FST5
            LDA  #49            ; (C-4)
            STA  23,X
FST5        LDA  CURF           ; (Play on is SONGKIT's, not the instrument's)
            JSR  FADDR
            LDA  F_KIND,Y
            CMPA #K_PLAY
            BEQ  FST6
            LDA  #1
            STA  CHANGED
            JSR  JAMREF
FST6        JSR  DRAWTITLE
            JMP  DRAWVALS
FST9        RTS

; FMOVE: to the field up (A 0), down (1), left (2) or right (3) of this one --
; passing over those not shown.
FMOVE       STA  FTMP
            LDA  CURF
FMOVE1      STA  FTAT
            JSR  FADDR
            LDB  FTMP
            ADDB #F_UP
            LDA  B,Y
            CMPA FTAT
            BEQ  FMOVE9         ; (nowhere to go)
            STA  FTNEW
            JSR  FADDR
            JSR  FVIS
            BCC  FMOVE2
            LDB  FTMP           ; not shown: left or right, stop; up or down,
            CMPB #2             ; on past it
            BHS  FMOVE9
            LDA  FTNEW
            BRA  FMOVE1
FMOVE2      LDB  CURF           ; the old one not lit, the new one lit
            LDA  FTNEW
            STA  CURF
            TFR  B,A
            JSR  DRAWF
            LDA  CURF
            JMP  DRAWF
FMOVE9      RTS

; FHIT: the field under the mouse, shown -> A; carry set if none.
FHIT        LDD  MOUSEY
            LSRD
            LSRD
            LSRD
            LSRD
            STB  FTROW
            LDD  MOUSEX
            LSRD
            LSRD
            LSRD
            STB  FTCOL
            CLRA
FHIT1       JSR  FADDR
            LDB  F_ROW,Y
            CMPB FTROW
            BNE  FHIT2
            LDB  FTCOL
            CMPB F_COL,Y
            BLO  FHIT2
            SUBB F_COL,Y
            CMPB F_W,Y
            BHS  FHIT2
            PSHS A
            JSR  FVIS
            PULS A
            BCC  FHIT9
FHIT2       INCA
            CMPA #NFIELDS
            BLO  FHIT1
            ORCC #1
            RTS
FHIT9       ANDCC #$FE
            RTS

;------------------------------------------------------------------------------
; Drawing it.
;------------------------------------------------------------------------------
DRAWPAGE    JSR  TXCLR
            LDX  #LABELS
            BSR  DRAWLAB
            JSR  DRAWTITLE
            JSR  DRAWSTAT
            BRA  DRAWVALS
; DRAWLAB: the labels at X: each its column, its row, its color, its text
; (the song's ticks let in as it goes: the window may be the player's after).
DRAWLAB     JSR  TICKPOLL
            LDD  ,X++
            CMPA #$FF
            BEQ  DL9
            JSR  TXAT
            PSHS A
            LDA  ,X+
            STA  TXFG
            PULS A
            JSR  TXSTR
            BRA  DRAWLAB
DL9         RTS
; DRAWVALS: every field, the instrument's number, the operators' headings
; (those heard lit), and the note's label.
DRAWVALS    CLRA
DV1         PSHS A
            JSR  DRAWF
            PULS A
            INCA
            CMPA #NFIELDS
            BLO  DV1
            CLR  TXBG
            LDD  #$0D02         ; "Instrument 1 of 5"
            JSR  TXAT
            LDA  #C_VALUE
            STA  TXFG
            LDA  CURI
            JSR  TXDEC
            PSHS B
            LDX  #S_OF
            JSR  TXSTR
            LDA  NINST
            JSR  TXDEC
            ADDB ,S+
            ADDB #4
            NEGB
            ADDB #11
            JSR  TXSPC
            LDD  #$1C05         ; the note's label
            JSR  TXAT
            LDA  #C_LABEL
            STA  TXFG
            LDX  IP
            LDA  ,X
            LDX  #S_XPOSE
            BITA #2
            BEQ  DV2
            LDX  #S_NOTE
DV2         JSR  TXSTR
            JSR  CARRIERS       ; the operators' headings
            STA  FTMP
            LDX  IP
            LDB  ,X
            ANDB #1
            LDA  #2
            TSTB
            BEQ  DV3
            LDA  #4
DV3         STA  FTOPS
            CLRB
DV4         PSHS B
            LDX  #OPCOLS
            LDA  B,X
            LDB  #8
            JSR  TXAT
            LDA  #C_LABEL       ; (each operator's bit, in turn)
            LSR  FTMP
            BCC  DV5
            LDA  #C_OUT
DV5         LDB  ,S
            CMPB FTOPS
            BLO  DV6
            LDA  #C_DIM
DV6         STA  TXFG
            LDX  #S_OP
            JSR  TXSTR
            LDA  ,S
            ADDA #'1
            JSR  TXCH
            PULS B
            INCB
            CMPB #4
            BLO  DV4
            RTS
OPCOLS      FCB  17,25,33,41

; CARRIERS: A, the operators heard (bit 0: the first).
CARRIERS    LDX  IP
            LDA  1,X
            ANDA #1
            LDB  ,X
            BITB #1
            BNE  CAR4
            LDX  #CAR2T
            LDA  A,X
            RTS
CAR4        LSLA
            LDB  2,X
            ANDB #1
            STB  FTMP
            ORA  FTMP
            LDX  #CAR4T
            LDA  A,X
            RTS
CAR2T       FCB  $02,$03
CAR4T       FCB  $08,$0A,$09,$0D

; DRAWF: field A, lit if it is the one being edited.
DRAWF       CLR  TXBG
            CMPA CURF
            BNE  DF1
            LDB  #C_CURBG
            STB  TXBG
DF1         JSR  FADDR
            LDA  F_COL,Y
            LDB  F_ROW,Y
            JSR  TXAT
            LDA  #C_VALUE
            STA  TXFG
            JSR  FVIS
            BCC  DF2
            LDB  F_W,Y          ; not shown
            CLR  TXBG
            JMP  TXSPC
DF2         JSR  FGET
            LDB  F_KIND,Y
            CMPB #K_NUM
            BEQ  DFNUM
            CMPB #K_YN
            BEQ  DFYN
            CMPB #K_WAVE
            BEQ  DFWAVE
            CMPB #K_OPS
            BEQ  DFOPS
            CMPB #K_ALG
            BEQ  DFALG
            CMPB #K_NOTE
            LBEQ DFNOTE
            CMPB #K_FINE
            BEQ  DFFINE
            CMPB #K_PAN
            BEQ  DFPAN
            CMPB #K_PLAY
            BEQ  DFPLAY
            LDX  NP             ; the name: up to 16 characters
            CLRB
DFNAME1     LDA  ,X+
            BEQ  DFPAD
            JSR  TXCH
            INCB
            CMPB #16
            BLO  DFNAME1
            BRA  DFPAD
DFNUM       JSR  TXDEC
            BRA  DFPAD
DFFINE      JSR  TXSGN
            BRA  DFPAD
DFYN        LDX  #S_NO
            TSTA
            BEQ  DFSTR
            LDX  #S_YES
            BRA  DFSTR
DFWAVE      LDX  #S_WAVES
DFTAB       LDB  #8             ; the A'th of strings 8 apart
            MUL
            ABX
DFSTR       JSR  PSTR
            BRA  DFPAD
DFPAN       LDX  #S_PANS
            BRA  DFTAB
DFPLAY      LDX  #S_PLAYS
            LDB  #10
            MUL
            ABX
            BRA  DFSTR
DFOPS       LDB  #'2
            TSTA
            BEQ  DFOPS1
            LDB  #'4
DFOPS1      TFR  B,A
            JSR  TXCH
            LDB  #1
            BRA  DFPAD
DFALG       PSHS A              ; its number, and what it is
            ADDA #'0
            JSR  TXCH
            LDA  #$20
            JSR  TXCH
            LDX  IP
            LDA  ,X
            LDX  #S_ALG2
            BITA #1
            BEQ  DFALG1
            LDX  #S_ALG4
DFALG1      PULS A
            LDB  #16
            MUL
            ABX
            JSR  PSTR
            ADDB #2
            BRA  DFPAD
DFNOTE      LDX  IP
            LDB  ,X
            BITB #2
            BEQ  DFFINE         ; a transpose
            JSR  NOTENAME
            LDB  #3
DFPAD       NEGB                ; spaces to its width
            ADDB F_W,Y
            BLE  DF9
            JMP  TXSPC
DF9         RTS
; PSTR: the string at X; B how many characters.
PSTR        CLRB
PSTR1       LDA  ,X+
            BEQ  PSTR9
            JSR  TXCH
            INCB
            BRA  PSTR1
PSTR9       RTS
; NOTENAME: note A (1-96) as C-4, F#2 ... (X kept.)
NOTENAME    PSHS X
            DECA
            CLRB
NN1         CMPA #12
            BLO  NN2
            SUBA #12
            INCB
            BRA  NN1
NN2         PSHS B
            LDX  #S_NOTES
            LSLA
            LEAX A,X
            LDA  ,X+
            JSR  TXCH
            LDA  ,X
            JSR  TXCH
            PULS A
            ADDA #'0
            JSR  TXCH
            PULS X,PC

; DRAWTITLE: the title bar: SONGKIT, the song's file, * if it has changed.
DRAWTITLE   CLRA
            CLRB
            JSR  TXAT
            LDA  #C_BARBG
            STA  TXBG
            LDA  #C_VALUE
            STA  TXFG
            LDX  #S_TITLE
            JSR  PSTR
            STB  FTMP
            LDX  #SONGNAME
            TST  ,X
            BNE  DT1
            LDX  #S_NEWSONG
DT1         JSR  PSTR
            ADDB FTMP
            STB  FTMP
            LDA  #$20
            TST  CHANGED
            BEQ  DT2
            LDA  #'*
DT2         JSR  TXCH
            LDB  FTMP
            INCB
            NEGB
            ADDB #80
            JSR  TXSPC
            CLR  TXBG
            RTS

; DRAWSTAT: the bottom row, the status: the octave the keys play, and whether
; the song is playing (on the pattern page, more: PSTAT); F1 for the help.
; (Nothing while a message, a question or the help is up.)
DRAWSTAT    TST  MODE
            BNE  DS9
            TST  MSGUP
            BNE  DS9
            LDB  #29
            JSR  TXROWCLR
            LDD  #$481D
            JSR  TXAT
            CLR  TXBG
            LDA  #C_HELP
            STA  TXFG
            LDX  #S_F1
            JSR  TXSTR
            TST  PAGE
            LBEQ PSTAT
            LDD  #$021D
            JSR  TXAT
            CLR  TXBG
            LDA  #C_LABEL
            STA  TXFG
            LDX  #S_OCT
            JSR  TXSTR
            LDA  #C_VALUE
            STA  TXFG
            LDA  OCT
            ADDA #'0
            JSR  TXCH
            LDA  #C_MSG
            STA  TXFG
            LDX  #S_PLAYING
            TST  SONGON
            BNE  DS1
            LDX  #S_STOPPED
DS1         JMP  TXSTR
DS9         RTS

; MSG: the message at X on the bottom row (over the status, until the next
; key).
MSG         PSHS X
            LDA  #1
            STA  MSGUP
            LDB  #29
            JSR  TXROWCLR
            CLRA
            JSR  TXAT
            LDA  #C_MSG
            STA  TXFG
            PULS X
            JMP  TXSTR

;------------------------------------------------------------------------------
; The page's words.
;------------------------------------------------------------------------------
LABELS      FCB  2,2,C_LABEL
            FCC  "Instrument"
            FCB  0
            FCB  24,2,C_LABEL
            FCC  "Name"
            FCB  0
            FCB  2,4,C_LABEL
            FCC  "Operators"
            FCB  0
            FCB  28,4,C_LABEL
            FCC  "Connection"
            FCB  0
            FCB  60,4,C_LABEL
            FCC  "Feedback"
            FCB  0
            FCB  2,5,C_LABEL
            FCC  "Fixed note"
            FCB  0
            FCB  60,5,C_LABEL
            FCC  "Fine tune"
            FCB  0
            FCB  2,6,C_LABEL
            FCC  "Output"
            FCB  0
            FCB  28,6,C_LABEL
            FCC  "Play on"
            FCB  0
            FCB  2,9,C_LABEL
            FCC  "Attack"
            FCB  0
            FCB  2,10,C_LABEL
            FCC  "Decay"
            FCB  0
            FCB  2,11,C_LABEL
            FCC  "Sustain level"
            FCB  0
            FCB  2,12,C_LABEL
            FCC  "Release"
            FCB  0
            FCB  2,13,C_LABEL
            FCC  "Level"
            FCB  0
            FCB  2,14,C_LABEL
            FCC  "Multiple"
            FCB  0
            FCB  2,15,C_LABEL
            FCC  "Waveform"
            FCB  0
            FCB  2,16,C_LABEL
            FCC  "Key scale lvl"
            FCB  0
            FCB  2,17,C_LABEL
            FCC  "Key scale rate"
            FCB  0
            FCB  2,18,C_LABEL
            FCC  "Sustained"
            FCB  0
            FCB  2,19,C_LABEL
            FCC  "Vibrato"
            FCB  0
            FCB  2,20,C_LABEL
            FCC  "Tremolo"
            FCB  0
            FCB  2,22,C_HELP
            FCC  "Operators in orange are heard; the others shape their sound."
            FCB  0
            FCB  2,23,C_HELP
            FCC  "Attack, decay, release: 15 is fastest. Level, sustain level: 0 is loudest."
            FCB  0
            FCB  $FF,$FF
S_F1        FCC  "F1: help"
            FCB  0
S_OF        FCC  " of "
            FCB  0
S_XPOSE     FCC  "Transpose"
            FCB  0
S_NOTE      FCC  "Note     "
            FCB  0
S_OP        FCC  "Op "
            FCB  0
S_NO        FCC  "no"
            FCB  0
S_YES       FCC  "yes"
            FCB  0
S_WAVES     FCC  "sine"             ; (8 apart)
            FCB  0,0,0,0
            FCC  "half"
            FCB  0,0,0,0
            FCC  "abs"
            FCB  0,0,0,0,0
            FCC  "pulse"
            FCB  0,0,0
            FCC  "alt"
            FCB  0,0,0,0,0
            FCC  "camel"
            FCB  0,0,0
            FCC  "square"
            FCB  0,0
            FCC  "saw"
            FCB  0,0,0,0,0
S_PANS      FCC  "L+R"
            FCB  0,0,0,0,0
            FCC  "L"
            FCB  0,0,0,0,0,0,0
            FCC  "R"
            FCB  0,0,0,0,0,0,0
S_PLAYS     FCC  "a channel"        ; (10 apart)
            FCB  0
            FCC  "bass drum"
            FCB  0
            FCC  "snare"
            FCB  0,0,0,0,0
            FCC  "tom-tom"
            FCB  0,0,0
            FCC  "cymbal"
            FCB  0,0,0,0
            FCC  "hi-hat"
            FCB  0,0,0,0
S_ALG2      FCC  "FM: 1>2"          ; (16 apart)
            FCB  0,0,0,0,0,0,0,0,0
            FCC  "additive: 1+2"
            FCB  0,0,0
S_ALG4      FCC  "1>2>3>4"
            FCB  0,0,0,0,0,0,0,0,0
            FCC  "1>2 + 3>4"
            FCB  0,0,0,0,0,0,0
            FCC  "1 + 2>3>4"
            FCB  0,0,0,0,0,0,0
            FCC  "1 + 2>3 + 4"
            FCB  0,0,0,0,0
S_NOTES     FCC  "C-C#D-D#E-F-F#G-G#A-A#B-"
S_TITLE     FCC  " SONGKIT   "
            FCB  0
S_NEWSONG   FCC  "(a new song)"
            FCB  0
S_OCT       FCC  "Octave "
            FCB  0
S_PLAYING   FCC  "   playing"
            FCB  0
S_STOPPED   FCC  "          "
            FCB  0

;------------------------------------------------------------------------------
; BEGIN FIELDS
; Each field (FSIZE bytes): its row, column, width, kind (K_), the instrument's
; byte, shift and mask, its operator ($FF: none), then the fields up, down,
; left and right of it. Made by tools/sk_fields.py.
NFIELDS     equ  57
FIELDS
            FCB  2,30,16,9,0,0,0,255,0,2,0,0
            FCB  4,17,1,3,0,0,1,255,0,4,1,2
            FCB  4,41,18,4,0,0,0,255,0,5,1,3
            FCB  4,70,1,0,1,1,7,255,0,6,2,3
            FCB  5,17,3,1,0,1,1,255,1,7,4,5
            FCB  5,41,4,5,0,0,0,255,2,8,4,6
            FCB  5,70,3,6,0,0,0,255,3,8,5,6
            FCB  6,17,3,7,0,0,0,255,4,9,7,8
            FCB  6,41,9,8,0,0,0,255,5,12,7,8
            FCB  9,17,6,0,5,4,15,0,7,13,9,10
            FCB  9,25,6,0,10,4,15,1,7,14,9,11
            FCB  9,33,6,0,15,4,15,2,8,15,10,12
            FCB  9,41,6,0,20,4,15,3,8,16,11,12
            FCB  10,17,6,0,5,0,15,0,9,17,13,14
            FCB  10,25,6,0,10,0,15,1,10,18,13,15
            FCB  10,33,6,0,15,0,15,2,11,19,14,16
            FCB  10,41,6,0,20,0,15,3,12,20,15,16
            FCB  11,17,6,0,6,4,15,0,13,21,17,18
            FCB  11,25,6,0,11,4,15,1,14,22,17,19
            FCB  11,33,6,0,16,4,15,2,15,23,18,20
            FCB  11,41,6,0,21,4,15,3,16,24,19,20
            FCB  12,17,6,0,6,0,15,0,17,25,21,22
            FCB  12,25,6,0,11,0,15,1,18,26,21,23
            FCB  12,33,6,0,16,0,15,2,19,27,22,24
            FCB  12,41,6,0,21,0,15,3,20,28,23,24
            FCB  13,17,6,0,4,0,63,0,21,29,25,26
            FCB  13,25,6,0,9,0,63,1,22,30,25,27
            FCB  13,33,6,0,14,0,63,2,23,31,26,28
            FCB  13,41,6,0,19,0,63,3,24,32,27,28
            FCB  14,17,6,0,3,0,15,0,25,33,29,30
            FCB  14,25,6,0,8,0,15,1,26,34,29,31
            FCB  14,33,6,0,13,0,15,2,27,35,30,32
            FCB  14,41,6,0,18,0,15,3,28,36,31,32
            FCB  15,17,6,2,7,0,7,0,29,37,33,34
            FCB  15,25,6,2,12,0,7,1,30,38,33,35
            FCB  15,33,6,2,17,0,7,2,31,39,34,36
            FCB  15,41,6,2,22,0,7,3,32,40,35,36
            FCB  16,17,6,0,4,6,3,0,33,41,37,38
            FCB  16,25,6,0,9,6,3,1,34,42,37,39
            FCB  16,33,6,0,14,6,3,2,35,43,38,40
            FCB  16,41,6,0,19,6,3,3,36,44,39,40
            FCB  17,17,6,1,3,4,1,0,37,45,41,42
            FCB  17,25,6,1,8,4,1,1,38,46,41,43
            FCB  17,33,6,1,13,4,1,2,39,47,42,44
            FCB  17,41,6,1,18,4,1,3,40,48,43,44
            FCB  18,17,6,1,3,5,1,0,41,49,45,46
            FCB  18,25,6,1,8,5,1,1,42,50,45,47
            FCB  18,33,6,1,13,5,1,2,43,51,46,48
            FCB  18,41,6,1,18,5,1,3,44,52,47,48
            FCB  19,17,6,1,3,6,1,0,45,53,49,50
            FCB  19,25,6,1,8,6,1,1,46,54,49,51
            FCB  19,33,6,1,13,6,1,2,47,55,50,52
            FCB  19,41,6,1,18,6,1,3,48,56,51,52
            FCB  20,17,6,1,3,7,1,0,49,53,53,54
            FCB  20,25,6,1,8,7,1,1,50,54,53,55
            FCB  20,33,6,1,13,7,1,2,51,55,54,56
            FCB  20,41,6,1,18,7,1,3,52,56,55,56
; END FIELDS
;------------------------------------------------------------------------------
; End of sk_inst.asm
;------------------------------------------------------------------------------
