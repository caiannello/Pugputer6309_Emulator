;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 game kit
;    FILE: sk_play.asm
;
; SONGKIT's player: plays a song (a .SNG file's contents, as gamekit/README.md
; describes them) on the OPL3 music chip -- the same code in a game as in the
; tools. INCLUDE it after DEFINES.D, after the program's code: its variables
; (about 1.1KB, RMBs) are at its end.
;
;   SK_START   X: the song, in memory -> plays it from its start (carry set:
;              it isn't a song)
;   SK_PSTART  X: the song's RAM pages (a byte each, in order), A: how many,
;              B: the bank (1-3) to see them through -> the same, for a song
;              in pages of its own (that bank is the player's while it plays)
;   SK_POLL    call it often -- at least every few ms: when the OPL3's Timer 2
;              says a tick is due, it plays one (SK_TICK)
;   SK_TICK    one tick of the song, for a program that keeps its own time
;   SK_STOP    the song stopped: its notes let go, and fade as they would
;   SK_OFF     the chip silent and as it starts (OPL2 mode, timers stopped);
;              before a program ends, and before SK_POLL with no song
;
; For an editor, notes played by hand (with a song, or without one):
;
;   SK_JSETUP  A: the 4-op pairs ($104's bits), B: flags (bit 0 rhythm mode)
;              -> the chip and the tracks set up so, with no song
;   SK_JAM     B: a track, A: a note (1-96; $7F the key let go), E: an
;              instrument (0: the track's own) -> played now
;   SK_JREF    B: a track, E: an instrument -> its registers written again,
;              the key as it is (a held note changes as it is edited)
;   SK_IREF    E: an instrument -> the same, on every track playing it
;   SK_IBASE   (2 bytes; SK_START and SK_PSTART make it 0) not 0: the
;   SK_INUM    instruments are SK_INUM of 32 bytes there, not the song's own
;   SK_PLAYING (a byte) not 0 while the song plays
;   SK_TICKS   (2 bytes) Timer 2's ticks since SK_START, playing or not
;   SK_RATE    (a byte) ticks a second, as the song has them now
;
; The song's ticks come from Timer 2, at the song's rate (Fxx changes it). Each
; tick clears the timers' flags, so Timer 1's flag is no use to a program while
; a song plays. Routines change any register but S.
;------------------------------------------------------------------------------
SK_OPL      equ  $FFE0      ; the OPL3: $FFE0-$FFE3
SK_NTRK     equ  20         ; tracks: 18 channels, and 2 more drums
SK_TSIZE    equ  48         ; a track's state (T_ below)
SK_HLEN     equ  80         ; a song's header: its orders follow it
SK_ILEN     equ  32         ; an instrument
SK_PMAX     equ  3071       ; the highest pitch: B-7, in 32nds of a semitone

; A track's state (SK_TRK has 20).
T_FL        equ  0          ; bit 0: the track plays; 1: a 4-op channel; 2: a
                            ; drum; 6: a new note to start; 7: the key is down
T_ARR       equ  1          ; the OPL3's register array (0 or 1)
T_CH        equ  2          ; its channel, 0-8 (a drum: the one its pitch is in)
T_OP        equ  3          ; its operators' register offsets (4)
T_NOP       equ  7          ; how many operators: 1 (a drum), 2 or 4
T_DRUM      equ  8          ; a drum's bit in $BD (0: not a drum)
T_DSRC      equ  9          ; a one-operator drum: which of an instrument's it plays
T_INS       equ  10         ; the instrument (0: none yet)
T_CAR       equ  11         ; the operators that are carriers (bit 0: the first)
T_TL        equ  12         ; each operator's $40 (KSL, total level) as given (4)
T_C0A       equ  16         ; the instrument's $C0s (feedback, connection)
T_C0B       equ  17
T_PAN       equ  18         ; $10 left, $20 right
T_XP        equ  19         ; the instrument's transpose, or its fixed note
T_FINE      equ  20         ; its fine tune
T_IFL       equ  21         ; its flags
T_VOL       equ  22         ; the volume, 0-63
T_LVOL      equ  23         ; the volume last written ($FF: none)
T_PITCH     equ  24         ; the pitch (2), in 32nds of a semitone from C-0
T_TARG      equ  26         ; where 3xx slides to (2)
T_LPIT      equ  28         ; the pitch last written (2)
T_FX        equ  30         ; the row's effect (0: none), and its parameter
T_PAR       equ  31
T_MSL       equ  32         ; the last parameters of 1xx 2xx, 3xx, 4xy, Axy
T_MPO       equ  33
T_MVIB      equ  34
T_MVS       equ  35
T_VPOS      equ  36         ; where vibrato is in its wave (0-63)
T_CUT       equ  37         ; ECx: the tick the note is cut at
T_DLY       equ  38         ; EDx: the tick the cell is played at
T_DCELL     equ  39         ; and that cell (5)
T_B0        equ  44         ; $B0 as last written, the key bit clear

;------------------------------------------------------------------------------
; SK_START, SK_PSTART: a song from its start.
;------------------------------------------------------------------------------
SK_START    CLR  SK_PAGED
            STX  SK_BASE
            LDD  #0         ; (in memory: no end of a window to come to)
            STD  SK_WEND
            BRA  SKBEGIN
SK_PSTART   STX  SK_PGT
            STA  SK_NPG
            STB  SK_BANK
            LDA  #1
            STA  SK_PAGED
            TFR  B,A        ; the window: bank x $4000
            LSLA
            LSLA
            LSLA
            LSLA
            LSLA
            LSLA
            CLRB
            STD  SK_WIN
            ADDD #$4000
            STD  SK_WEND
SKBEGIN     JSR  SK_OFF
            LDD  #0
            STD  SK_TICKS
            STD  SK_IBASE
            LDX  #0         ; the header
            CLRA
            JSR  SKSEEK
            LDX  #SK_HDR
            LDB  #16
SKB1        JSR  SKGETB
            STA  ,X+
            DECB
            BNE  SKB1
            LDD  SK_HDR     ; "PSG1"
            CMPD #$5053
            LBNE SKBAD
            LDD  SK_HDR+2
            CMPD #$4731
            LBNE SKBAD
            LDB  SK_HDR+11  ; orders: one at least
            LBEQ SKBAD
            CLRA            ; where the pattern table and the instruments are
            ADDD #SK_HLEN
            STD  SK_PTAB
            LDB  SK_HDR+10
            CLRA
            LSLD
            LSLD
            ADDD SK_PTAB
            STD  SK_ITAB
            JSR  SKCHIP
            LDA  SK_HDR+8   ; ticks a row: 1-31 (6 if it says otherwise)
            BEQ  SKB3
            CMPA #32
            BLO  SKB4
SKB3        LDA  #6
SKB4        STA  SK_SPEED
            LDA  SK_HDR+7   ; ticks a second: 32-255 (60 if it says otherwise)
            CMPA #32
            BHS  SKB5
            LDA  #60
SKB5        JSR  SKRATE
            CLR  SK_JFL
            CLR  SK_TICKN
            LDA  #1
            STA  SK_PLAYING
            CLRA            ; the first order's pattern, from its start
            JSR  SKORDER
            ANDCC #$FE
            RTS
SKBAD       ORCC #1
            RTS

; SK_JSETUP: the chip and the tracks for notes played by hand, with no song.
SK_JSETUP   PSHS D
            JSR  SK_OFF
            PULS D
            STA  SK_HDR+5
            STB  SK_HDR+4
            CLR  SK_HDR+6
; SKCHIP: the chip as SK_HDR says (OPL3 mode, the 4-op pairs, rhythm mode,
; deep tremolo and vibrato), and the tracks for it.
SKCHIP      LDE  #1         ; the chip: OPL3 mode, the song's 4-op channels
            LDD  #$0501
            JSR  SKW
            LDA  #$04
            LDB  SK_HDR+5
            ANDB #$3F
            JSR  SKW
            CLRE            ; deep tremolo and vibrato, and rhythm mode
            LDB  SK_HDR+6
            ANDB #$C0
            LDA  SK_HDR+4
            BITA #1
            BEQ  SKB2
            ORB  #$20
SKB2        STB  SK_BD
            LDA  #$BD
            JSR  SKW
            JMP  SKTRACKS

; SK_JAM: note A on track B, now (instrument E, or the track's own).
SK_JAM      PSHS A
            LDA  #SK_TSIZE
            MUL
            ADDD #SK_TRK
            TFR  D,U
            PULS A
            LDX  #SK_CELL
            STA  ,X
            STE  1,X
            CLR  2,X
            CLR  3,X
            CLR  4,X
            LDA  T_FL,U
            BITA #1
            BEQ  SKJ9
            TSTE
            BEQ  SKJ1
            CLR  T_INS,U    ; (always read again: it may have been edited)
SKJ1        JSR  SKTRIG
            JMP  SKOUT
SKJ9        RTS
; SK_IREF: instrument E's registers again to every track playing it (a song's
; too), their keys as they are: an instrument changed is heard at once.
SK_IREF     LDU  #SK_TRK
            LDB  #SK_NTRK
SKIR1       PSHS B
            LDA  T_FL,U
            BITA #1
            BEQ  SKIR2
            CMPE T_INS,U
            BNE  SKIR2
            PSHSW
            TFR  E,A
            JSR  SKLOADR
            JSR  SKOUT
            PULSW
SKIR2       LEAU SK_TSIZE,U
            PULS B
            DECB
            BNE  SKIR1
            RTS
; SK_JREF: instrument E's registers to track B again, its key as it is.
SK_JREF     LDA  #SK_TSIZE
            MUL
            ADDD #SK_TRK
            TFR  D,U
            LDA  T_FL,U
            BITA #1
            BEQ  SKJ9
            TFR  E,A
            STA  T_INS,U
            JSR  SKLOADR
            JMP  SKOUT

; SKTRACKS: the tracks set up for the song: which channel and operators each
; has, as its 4-op pairs and rhythm mode make them.
SKTRACKS    LDU  #SK_TRK
            CLRB
SKT1        PSHS B
            TFR  U,X        ; all 0 to start with
            LDA  #SK_TSIZE
SKT2        CLR  ,X+
            DECA
            BNE  SKT2
            LDA  #63
            STA  T_VOL,U
            LDA  #$FF
            STA  T_LVOL,U
            STA  T_LPIT,U
            STA  T_LPIT+1,U
            LDA  #$30
            STA  T_PAN,U
            CMPB #18        ; 18 and 19: only drums (below)
            BHS  SKT9
            CLRA            ; tracks 0-8: array 0's channels; 9-17: array 1's
            CMPB #9
            BLO  SKT3
            SUBB #9
            INCA
SKT3        STA  T_ARR,U
            STB  T_CH,U
            LDX  #SKOPOFF
            LDA  B,X
            STA  T_OP,U
            ADDA #3
            STA  T_OP+1,U
            LDA  #2
            STA  T_NOP,U
            LDA  #1
            STA  T_FL,U
            CMPB #6         ; channels 0-5: a 4-op pair? (0 and 3, 1 and 4, 2
            BHS  SKT9       ; and 5: $104's bits 0-2, and 3-5 for array 1)
            TFR  B,A
            CMPA #3
            BLO  SKT4
            SUBA #3
SKT4        TST  T_ARR,U
            BEQ  SKT5
            ADDA #3
SKT5        LDX  #SKBITS
            LDA  A,X
            ANDA SK_HDR+5
            BEQ  SKT9
            CMPB #3
            BHS  SKTOFF     ; the pair's second channel: not a track of its own
            LDX  #SKOPOFF
            ADDB #3
            LDA  B,X
            STA  T_OP+2,U
            ADDA #3
            STA  T_OP+3,U
            LDA  #4
            STA  T_NOP,U
            LDA  #3
            STA  T_FL,U
            BRA  SKT9
SKTOFF      CLR  T_FL,U
SKT9        LEAU SK_TSIZE,U
            PULS B
            INCB
            CMPB #SK_NTRK
            LBLO SKT1
            LDA  SK_HDR+4   ; rhythm mode: tracks 6, 7, 8, 18 and 19 the drums
            BITA #1
            BEQ  SKT12
            LDX  #SKDRUMS
SKT10       LDB  ,X+
            BMI  SKT12
            LDA  #SK_TSIZE
            MUL
            ADDD #SK_TRK
            TFR  D,U
            LDD  ,X++
            STA  T_CH,U
            STB  T_OP,U
            LDD  ,X++
            STA  T_OP+1,U
            STB  T_NOP,U
            LDD  ,X++
            STA  T_DRUM,U
            STB  T_DSRC,U
            CLR  T_ARR,U
            LDA  #5
            STA  T_FL,U
            BRA  SKT10
SKT12       RTS

; SKRATE: A ticks a second (32-255), Timer 2 (steps of 320 us) set to that.
SKRATE      STA  SK_RATE
            LDD  #3125      ; 3125 steps a second
            DIVD SK_RATE    ; B steps a tick, A over
            PSHS B
            LSLA            ; rounded
            BCS  SKR1
            CMPA SK_RATE
            BLO  SKR2
SKR1        INC  ,S
SKR2        PULS B
            NEGB            ; (256 - steps)
            CLRE
            LDA  #$03
            JSR  SKW
            LDD  #$0480     ; the flags cleared
            JSR  SKW
            LDD  #$0442     ; Timer 2 started; Timer 1 masked
            JMP  SKW

;------------------------------------------------------------------------------
; SK_POLL, SK_TICK: the song's time.
;------------------------------------------------------------------------------
SK_POLL     LDA  SK_OPL     ; Timer 2's flag
            BITA #$20
            BEQ  SKP9
            CLRE
            LDD  #$0480
            JSR  SKW
            LDD  SK_TICKS
            ADDD #1
            STD  SK_TICKS
            BRA  SK_TICK
SKP9        RTS

SK_TICK     TST  SK_PLAYING
            BEQ  SKTK9
            TST  SK_TICKN   ; a row's first tick: the row read
            BNE  SKTK1
            JSR  SKROWST
            BRA  SKTK2
SKTK1       JSR  SKFXALL    ; the rest: its effects
SKTK2       TST  SK_PLAYING ; (F00: the end)
            BEQ  SKTK9
            JSR  SKOUTALL
            INC  SK_TICKN
            LDA  SK_TICKN
            CMPA SK_SPEED
            BLO  SKTK9
            CLR  SK_TICKN
            JMP  SKNEXT
SKTK9       RTS

; SKROWST: a new row: the last one's effects over, then this one's cells.
SKROWST     LDU  #SK_TRK
            LDB  #SK_NTRK
SKRS1       CLR  T_FX,U
            CLR  T_CUT,U
            CLR  T_DLY,U
            LEAU SK_TSIZE,U
            DECB
            BNE  SKRS1
            TST  SK_SKIP    ; one of a run of empty rows
            BEQ  SKRS2
            DEC  SK_SKIP
            RTS
SKRS2       CLR  SK_DISC
; SKROW: a row read (SK_DISC not 0: just passed over). An entry: a byte, bits
; 0-4 its track, bit 5 a note and an instrument follow, 6 a volume, 7 an
; effect and its parameter; $1F ends the row, $1E n ends it and n empty rows.
SKROW       LDA  #32        ; (a song gone wrong can't hold the player here)
            STA  SK_GUARD
SKRW1       JSR  SKGETB
            CMPA #$1F
            BEQ  SKRW9
            CMPA #$1E
            BNE  SKRW2
            JSR  SKGETB
            STA  SK_SKIP
SKRW9       RTS
SKRW2       STA  SK_ENT
            LDX  #SK_CELL
            CLR  ,X
            CLR  1,X
            CLR  2,X
            CLR  3,X
            CLR  4,X
            BITA #$20
            BEQ  SKRW3
            JSR  SKGETB
            STA  ,X
            JSR  SKGETB
            STA  1,X
SKRW3       LDA  SK_ENT
            BITA #$40
            BEQ  SKRW4
            JSR  SKGETB
            STA  2,X
SKRW4       LDA  SK_ENT
            BITA #$80
            BEQ  SKRW5
            JSR  SKGETB
            STA  3,X
            JSR  SKGETB
            STA  4,X
SKRW5       TST  SK_DISC
            BNE  SKRW6
            LDB  SK_ENT
            ANDB #$1F
            CMPB #SK_NTRK
            BHS  SKRW6
            LDA  #SK_TSIZE
            MUL
            ADDD #SK_TRK
            TFR  D,U
            LDA  T_FL,U
            BITA #1
            BEQ  SKRW6
            JSR  SKCELL
SKRW6       DEC  SK_GUARD
            BNE  SKRW1
            RTS

; SKNEXT: on to the next row -- or where Bxx and Dxx said.
SKNEXT      LDA  SK_JFL
            BEQ  SKNX6
            CLR  SK_JFL
            LDB  SK_ORD     ; the next order, or Bxx's
            INCB
            BITA #1
            BEQ  SKNX1
            LDB  SK_JORD
SKNX1       CLR  SK_BROW    ; its first row, or Dxx's
            BITA #2
            BEQ  SKNX2
            LDA  SK_JROW
            STA  SK_BROW
SKNX2       TFR  B,A
            JSR  SKORDER
            TST  SK_PLAYING
            BEQ  SKNX9
            LDA  SK_BROW
            CMPA SK_ROWS
            BHS  SKNX9      ; (past the pattern's end: its start)
            LDA  #1
            STA  SK_DISC
SKNX3       LDA  SK_ROW     ; the rows before it passed over
            CMPA SK_BROW
            BHS  SKNX9
            TST  SK_SKIP
            BEQ  SKNX4
            DEC  SK_SKIP
            BRA  SKNX5
SKNX4       JSR  SKROW
SKNX5       INC  SK_ROW
            BRA  SKNX3
SKNX6       INC  SK_ROW
            LDA  SK_ROW
            CMPA SK_ROWS
            BLO  SKNX9
            LDA  SK_ORD
            INCA
            JMP  SKORDER
SKNX9       RTS

; SKORDER: A, an order: its pattern, from its first row. Past the last order,
; the song goes back to its loop -- or, with none, it is over.
SKORDER     CMPA SK_HDR+11
            BLO  SKO1
            LDA  SK_HDR+12
            CMPA SK_HDR+11
            LBHS SK_STOP
SKO1        STA  SK_ORD
            CLR  SK_ROW
            CLR  SK_SKIP
            TFR  A,B
            CLRA
            ADDD #SK_HLEN
            TFR  D,X
            CLRA
            JSR  SKSEEK
            JSR  SKGETB     ; its pattern
            CMPA SK_HDR+10
            BLO  SKO2
            LDA  #64        ; there's no such pattern: 64 empty rows
            STA  SK_ROWS
            STA  SK_SKIP
            RTS
SKO2        TFR  A,B
            CLRA
            LSLD
            LSLD
            ADDD SK_PTAB
            TFR  D,X
            CLRA
            JSR  SKSEEK
            JSR  SKGETB     ; its rows (0: 64)
            TSTA
            BNE  SKO3
            LDA  #64
SKO3        STA  SK_ROWS
            JSR  SKGETB     ; and where it is
            STA  SK_TMP3
            JSR  SKGETB
            STA  SK_TMP3+1
            JSR  SKGETB
            STA  SK_TMP3+2
            LDA  SK_TMP3
            LDX  SK_TMP3+1
            JMP  SKSEEK

;------------------------------------------------------------------------------
; A cell: the note, instrument, volume and effect for track U.
;------------------------------------------------------------------------------
SKCELL      LDX  #SK_CELL
            LDA  3,X        ; EDx: all of it x ticks on
            CMPA #'E
            BNE  SKTRIG
            LDA  4,X
            ANDA #$F0
            CMPA #$D0
            BNE  SKTRIG
            LDA  4,X
            ANDA #$0F
            BEQ  SKTRIG
            STA  T_DLY,U
            LDD  ,X
            STD  T_DCELL,U
            LDD  2,X
            STD  T_DCELL+2,U
            LDA  4,X
            STA  T_DCELL+4,U
            RTS
; SKTRIG: the cell at X played on track U.
SKTRIG      STX  SK_CP
            LDA  1,X        ; an instrument: its sound, at full volume
            BEQ  SKTG2
            CMPA T_INS,U
            BEQ  SKTG1
            JSR  SKLOADI
SKTG1       LDA  #63
            STA  T_VOL,U
SKTG2       LDX  SK_CP
            LDA  ,X         ; the note
            BEQ  SKTG5
            CMPA #$7F       ; key off
            BNE  SKTG3
            JSR  SKKOFF
            BRA  SKTG5
SKTG3       CMPA #96
            BHI  SKTG5
            TST  T_INS,U
            BEQ  SKTG5
            JSR  SKNPIT
            LDX  SK_CP
            LDF  3,X
            CMPF #'3        ; 3xx with a note playing: where it slides to
            BNE  SKTG4
            TST  T_FL,U
            BPL  SKTG4
            STD  T_TARG,U
            BRA  SKTG5
SKTG4       STD  T_PITCH,U
            STD  T_TARG,U
            CLR  T_VPOS,U
            LDA  T_FL,U
            ORA  #$C0       ; to start, and down
            STA  T_FL,U
SKTG5       LDX  SK_CP      ; the volume
            LDA  2,X
            BEQ  SKTG7
            DECA
            CMPA #63
            BLS  SKTG6
            LDA  #63
SKTG6       STA  T_VOL,U
SKTG7       LDX  SK_CP      ; the effect: what it does at once
            LDD  3,X
            STA  T_FX,U
            STB  T_PAR,U
            TSTA
            BEQ  SKTG9
            CMPA #'1
            BEQ  SKE12
            CMPA #'2
            BEQ  SKE12
            CMPA #'3
            BEQ  SKE3
            CMPA #'4
            BEQ  SKE4
            CMPA #'A
            BEQ  SKEA
            CMPA #'C
            BEQ  SKEC
            CMPA #'8
            BEQ  SKE8
            CMPA #'B
            BEQ  SKEB
            CMPA #'D
            BEQ  SKED
            CMPA #'E
            BEQ  SKEE
            CMPA #'F
            LBEQ SKEF
SKTG9       RTS
SKE12       TSTB            ; (a parameter of 0: the last one again)
            BNE  SKE12A
            LDB  T_MSL,U
SKE12A      STB  T_MSL,U
            STB  T_PAR,U
            RTS
SKE3        TSTB
            BNE  SKE3A
            LDB  T_MPO,U
SKE3A       STB  T_MPO,U
            STB  T_PAR,U
            RTS
SKE4        TSTB
            BNE  SKE4A
            LDB  T_MVIB,U
SKE4A       STB  T_MVIB,U
            STB  T_PAR,U
            RTS
SKEA        TSTB
            BNE  SKEAA
            LDB  T_MVS,U
SKEAA       STB  T_MVS,U
            STB  T_PAR,U
            RTS
SKEC        CMPB #63
            BLS  SKEC1
            LDB  #63
SKEC1       STB  T_VOL,U
            RTS
SKE8        CLRA            ; 8xy: x left, y right (both 0: both)
            BITB #$F0
            BEQ  SKE8A
            ORA  #$10
SKE8A       BITB #$0F
            BEQ  SKE8B
            ORA  #$20
SKE8B       TSTA
            BNE  SKE8C
            LDA  #$30
SKE8C       STA  T_PAN,U
            JMP  SKWC0
SKEB        STB  SK_JORD
            LDA  SK_JFL
            ORA  #1
            STA  SK_JFL
            RTS
SKED        STB  SK_JROW
            LDA  SK_JFL
            ORA  #2
            STA  SK_JFL
            RTS
SKEE        TFR  B,A
            ANDB #$0F
            ANDA #$F0
            CMPA #$10       ; E1x, E2x: up, down x 32nds of a semitone
            BEQ  SKEE1
            CMPA #$20
            BEQ  SKEE2
            CMPA #$C0       ; ECx: cut at tick x
            BNE  SKEE9
            STB  T_CUT,U
            BNE  SKEE9
            CLR  T_VOL,U
SKEE9       RTS
SKEE1       CLRA
            ADDD T_PITCH,U
            BRA  SKEE3
SKEE2       CLRA
            STD  SK_TMPW
            LDD  T_PITCH,U
            SUBD SK_TMPW
SKEE3       JSR  SKCLAMP
            STD  T_PITCH,U
            RTS
SKEF        TSTB            ; F00: the end; F01-F1F ticks a row; F20-FFF a second
            LBEQ SK_STOP
            CMPB #$20
            BHS  SKEF1
            STB  SK_SPEED
            RTS
SKEF1       TFR  B,A
            JMP  SKRATE

; SKCLAMP: D (signed) kept to 0 .. SK_PMAX.
SKCLAMP     TSTA
            BPL  SKCL1
            LDD  #0
            RTS
SKCL1       CMPD #SK_PMAX
            BLS  SKCL2
            LDD  #SK_PMAX
SKCL2       RTS

; SKNPIT: A, a note (1-96: C-0 to B-7), as track U's instrument plays it -> D,
; its pitch.
SKNPIT      LDB  T_IFL,U
            BITB #2
            BEQ  SKNP1
            LDB  T_XP,U     ; a fixed note, whatever the note
            CLRA
            BRA  SKNP2
SKNP1       TFR  A,B
            CLRA
            STD  SK_TMPW
            LDB  T_XP,U
            SEX
            ADDD SK_TMPW
SKNP2       CMPD #1
            BGE  SKNP3
            LDD  #1
SKNP3       CMPD #96
            BLE  SKNP4
            LDD  #96
SKNP4       SUBD #1
            LSLD
            LSLD
            LSLD
            LSLD
            LSLD
            STD  SK_TMPW
            LDB  T_FINE,U
            SEX
            ADDD SK_TMPW
            BRA  SKCLAMP

;------------------------------------------------------------------------------
; A row's other ticks: the effects that go on.
;------------------------------------------------------------------------------
SKFXALL     LDU  #SK_TRK
            LDB  #SK_NTRK
SKFA1       PSHS B
            LDA  T_FL,U
            BITA #1
            BEQ  SKFA2
            JSR  SKFX
SKFA2       LEAU SK_TSIZE,U
            PULS B
            DECB
            BNE  SKFA1
            RTS
SKFX        LDA  T_DLY,U    ; EDx's cell, when its tick comes
            BEQ  SKFX1
            CMPA SK_TICKN
            BNE  SKFX1
            CLR  T_DLY,U
            LEAX T_DCELL,U
            JSR  SKTRIG
SKFX1       LDA  T_CUT,U    ; ECx
            BEQ  SKFX2
            CMPA SK_TICKN
            BNE  SKFX2
            CLR  T_CUT,U
            CLR  T_VOL,U
SKFX2       LDA  T_FX,U
            LDB  T_PAR,U
            CMPA #'1
            BEQ  SKF1
            CMPA #'2
            BEQ  SKF2
            CMPA #'3
            BEQ  SKF3
            CMPA #'4
            BEQ  SKF4
            CMPA #'A
            BEQ  SKFA
            RTS
SKF1        CLRA            ; up
            ADDD T_PITCH,U
            BRA  SKF2A
SKF2        CLRA            ; down
            STD  SK_TMPW
            LDD  T_PITCH,U
            SUBD SK_TMPW
SKF2A       JSR  SKCLAMP
            STD  T_PITCH,U
            RTS
SKF3        CLRA            ; toward the note
            STD  SK_TMPW
            LDD  T_PITCH,U
            CMPD T_TARG,U
            BEQ  SKF3Z
            BLT  SKF3U
            SUBD SK_TMPW
            CMPD T_TARG,U
            BGE  SKF3S
            LDD  T_TARG,U
            BRA  SKF3S
SKF3U       ADDD SK_TMPW
            CMPD T_TARG,U
            BLE  SKF3S
            LDD  T_TARG,U
SKF3S       STD  T_PITCH,U
SKF3Z       RTS
SKF4        LSRB            ; vibrato: x along its wave
            LSRB
            LSRB
            LSRB
            ADDB T_VPOS,U
            ANDB #63
            STB  T_VPOS,U
            RTS
SKFA        TFR  B,A        ; volume: x up, or y down
            LSRA
            LSRA
            LSRA
            LSRA
            BEQ  SKFA4
            ADDA T_VOL,U
            CMPA #63
            BLS  SKFA3
            LDA  #63
SKFA3       STA  T_VOL,U
            RTS
SKFA4       ANDB #$0F
            STB  SK_TMP
            LDA  T_VOL,U
            SUBA SK_TMP
            BCC  SKFA3
            CLRA
            BRA  SKFA3

;------------------------------------------------------------------------------
; Each tick's end: what has changed, to the chip.
;------------------------------------------------------------------------------
SKOUTALL    LDU  #SK_TRK
            LDB  #SK_NTRK
SKOA1       PSHS B
            LDA  T_FL,U
            BITA #1
            BEQ  SKOA2
            JSR  SKOUT
SKOA2       LEAU SK_TSIZE,U
            PULS B
            DECB
            BNE  SKOA1
            RTS
SKOUT       TST  T_INS,U    ; (nothing played on it yet: nothing to write)
            BEQ  SKOU9
            LDA  T_VOL,U
            CMPA T_LVOL,U
            BEQ  SKOU1
            STA  T_LVOL,U
            JSR  SKWVOL
SKOU1       LDD  T_PITCH,U  ; the pitch, with 0xy's or 4xy's part
            STD  SK_OUTP
            LDA  T_FX,U
            CMPA #'0
            BEQ  SKOARP
            CMPA #'4
            BEQ  SKOVIB
SKOU2       LDD  SK_OUTP
            JSR  SKCLAMP
            STD  SK_OUTP
            LDA  T_FL,U
            BITA #$40
            BNE  SKOU3
            LDD  SK_OUTP
            CMPD T_LPIT,U
            BEQ  SKOU9
            STD  T_LPIT,U
            JMP  SKWFREQ
SKOU3       ANDA #$BF       ; a note to start
            STA  T_FL,U
            LDD  SK_OUTP
            STD  T_LPIT,U
            JMP  SKRETRIG
SKOU9       RTS
SKOARP      LDB  T_PAR,U    ; 0xy: the note, +x, +y, a tick each
            BEQ  SKOU2
            LDA  SK_TICKN
SKOAR1      CMPA #3
            BLO  SKOAR2
            SUBA #3
            BRA  SKOAR1
SKOAR2      TSTA
            BEQ  SKOU2
            DECA
            BNE  SKOAR3
            LSRB
            LSRB
            LSRB
            LSRB
            BRA  SKOAR4
SKOAR3      ANDB #$0F
SKOAR4      LDA  #32
            MUL
            ADDD SK_OUTP
            STD  SK_OUTP
            LBRA SKOU2
SKOVIB      LDB  T_VPOS,U   ; 4xy: y/32 of the wave, in 32nds of a semitone
            ANDB #31
            LDX  #SKSINE
            LDA  B,X
            LDB  T_PAR,U
            ANDB #$0F
            MUL
            LSRD
            LSRD
            LSRD
            LSRD
            LSRD
            STD  SK_TMPW
            LDA  T_VPOS,U
            BITA #32        ; (the wave's second half: down)
            BEQ  SKOV0
            LDD  SK_TMPW
            NEGD
            BRA  SKOV1
SKOV0       LDD  SK_TMPW
SKOV1       ADDD SK_OUTP
            STD  SK_OUTP
            LBRA SKOU2

; SKWVOL: the carriers' levels, from the instrument's and the volume.
SKWVOL      LDE  T_ARR,U
            LDA  #63
            SUBA T_VOL,U
            STA  SK_ATT
            CLRB
SKWV1       CMPB T_NOP,U
            BHS  SKWV9
            LDX  #SKBITS
            LDA  B,X
            ANDA T_CAR,U
            BEQ  SKWV3
            LEAX T_TL,U
            LDA  B,X
            ANDA #$3F
            ADDA SK_ATT
            CMPA #63
            BLS  SKWV2
            LDA  #63
SKWV2       STA  SK_TMP
            LDA  B,X
            ANDA #$C0
            ORA  SK_TMP
            STA  SK_TMP
            LEAX T_OP,U
            LDA  B,X
            ADDA #$40
            PSHS B
            LDB  SK_TMP
            JSR  SKW
            PULS B
SKWV3       INCB
            BRA  SKWV1
SKWV9       RTS

; SKWFREQ: D, a pitch, to track U's channel (the key as T_FL has it).
SKWFREQ     JSR  SKFNUM
            LDB  SK_FB0
            STB  T_B0,U
            LDE  T_ARR,U
            LDA  #$A0
            ADDA T_CH,U
            LDB  SK_FA0
            JSR  SKW
            ADDA #$10
            LDB  T_B0,U
            TST  T_DRUM,U   ; (a drum's key is in $BD)
            BNE  SKWF1
            TST  T_FL,U
            BPL  SKWF1
            ORB  #$20
SKWF1       JMP  SKW

; SKFNUM: D, a pitch -> SK_FA0, SK_FB0: $A0 and $B0 (no key) for it.
SKFNUM      PSHS B
            LSRD            ; the semitone: its octave (the block), and which
            LSRD
            LSRD
            LSRD
            LSRD
            CLRA
SKFN1       CMPB #12
            BLO  SKFN2
            SUBB #12
            INCA
            BRA  SKFN1
SKFN2       STA  SK_OCT
            LSLB
            LDX  #SKFTAB
            ABX
            LDD  2,X        ; then between its F-number and the next one's
            SUBD ,X
            PULS A
            ANDA #31
            MUL
            LSRD
            LSRD
            LSRD
            LSRD
            LSRD
            ADDD ,X
            STB  SK_FA0
            STA  SK_TMP
            LDA  SK_OCT
            LSLA
            LSLA
            ORA  SK_TMP
            STA  SK_FB0
            RTS

; SKRETRIG: D, a pitch: track U's note started again there.
SKRETRIG    PSHS D
            TST  T_DRUM,U
            BNE  SKRT1
            LDE  T_ARR,U    ; the key up (where it was), then down
            LDA  #$B0
            ADDA T_CH,U
            LDB  T_B0,U
            JSR  SKW
            PULS D
            JMP  SKWFREQ
SKRT1       CLRE            ; a drum: its bit in $BD off, the pitch, then on
            LDA  T_DRUM,U
            COMA
            ANDA SK_BD
            STA  SK_BD
            TFR  A,B
            LDA  #$BD
            JSR  SKW
            PULS D
            JSR  SKWFREQ
            CLRE
            LDB  SK_BD
            ORB  T_DRUM,U
            STB  SK_BD
            LDA  #$BD
            JMP  SKW

; SKKOFF: track U's key let go.
SKKOFF      LDA  T_FL,U
            ANDA #$3F
            STA  T_FL,U
            TST  T_DRUM,U
            BNE  SKKO1
            LDE  T_ARR,U
            LDA  #$B0
            ADDA T_CH,U
            LDB  T_B0,U
            JMP  SKW
SKKO1       CLRE
            LDA  T_DRUM,U
            COMA
            ANDA SK_BD
            STA  SK_BD
            TFR  A,B
            LDA  #$BD
            JMP  SKW

;------------------------------------------------------------------------------
; Instruments.
;------------------------------------------------------------------------------
; SKLOADI: instrument A to track U.
SKLOADI     STA  T_INS,U
            JSR  SKKOFF
            LDA  T_INS,U
SKLOADR     JSR  SKFETCH    ; (SK_JREF comes in here: the key as it is)
            LDA  SK_IB
            STA  T_IFL,U
            LDD  SK_IB+1
            STA  T_C0A,U
            STB  T_C0B,U
            LDD  SK_IB+23
            STA  T_XP,U
            STB  T_FINE,U
            LDA  SK_IB+25
            ANDA #$30
            BNE  SKLI1
            LDA  #$30
SKLI1       STA  T_PAN,U
            LDX  #SK_SRC    ; which of its operators each of the track's plays
            LDD  #$0001
            STD  ,X
            LDD  #$0203
            STD  2,X
            LDA  T_FL,U
            BITA #4
            BNE  SKLDRUM
            BITA #2
            BEQ  SKL2OP
            LDA  T_IFL,U    ; a 4-op channel
            BITA #1
            BEQ  SKL4X2
            LDA  T_C0A,U    ; and instrument: which 4-op algorithm
            ANDA #1
            LSLA
            LDB  T_C0B,U
            ANDB #1
            STB  SK_TMP
            ORA  SK_TMP
            LDX  #SKCAR4
            LDA  A,X
            BRA  SKLCAR
SKL4X2      LDA  T_C0B,U    ; a 2-op instrument on a 4-op channel: the pair's
            ORA  #1         ; second connection 1, so that its 2 operators
            STA  T_C0B,U    ; sound as they would alone
            LDA  T_C0A,U
            BITA #1
            BNE  SKL4X2A
            LDD  #$FFFF     ; FM: 1 -> 2 out, 3 and 4 silent
            STD  2,X
            LDA  #$02
            BRA  SKLCAR
SKL4X2A     LDA  #$FF       ; additive: 1 out, 4 out (its operator 2), 2 and
            STA  1,X        ; 3 silent
            STA  2,X
            LDA  #1
            STA  3,X
            LDA  #$09
            BRA  SKLCAR
SKLDRUM     LDA  T_NOP,U
            CMPA #1
            BNE  SKL2OP     ; (the bass drum: both)
            LDA  T_DSRC,U
            STA  ,X
            LDA  #1
            BRA  SKLCAR
SKL2OP      LDA  T_C0A,U
            BITA #1
            BEQ  SKL2A
            LDA  #3
            BRA  SKLCAR
SKL2A       LDA  #2
SKLCAR      STA  T_CAR,U
            CLRB
SKLOP       CMPB T_NOP,U
            BHS  SKLOP1
            PSHS B
            JSR  SKWOP
            PULS B
            INCB
            BRA  SKLOP
SKLOP1      LDA  #$FF       ; the level and the pitch, written again
            STA  T_LVOL,U
            STA  T_LPIT,U
            STA  T_LPIT+1,U
            JMP  SKWC0

; SKWOP: track U's operator B, its registers from the instrument's operator
; SK_SRC has for it.
SKWOP       LDE  T_ARR,U
            LEAX T_OP,U
            LDA  B,X
            STA  SK_OPO
            LDX  #SK_SRC
            LDA  B,X
            LDY  #SKSILENT
            CMPA #$FF
            BEQ  SKWO1
            PSHS B
            LDB  #5
            MUL
            ADDD #SK_IB+3
            TFR  D,Y
            PULS B
SKWO1       LEAX T_TL,U
            LDA  1,Y
            STA  B,X
            LDA  #$20
            ADDA SK_OPO
            LDB  ,Y         ; $20: tremolo, vibrato, sustain, KSR, multiple
            JSR  SKW
            ADDA #$20
            LDB  1,Y        ; $40: KSL, total level
            JSR  SKW
            ADDA #$20
            LDB  2,Y        ; $60: attack, decay
            JSR  SKW
            ADDA #$20
            LDB  3,Y        ; $80: sustain level, release
            JSR  SKW
            ADDA #$60
            LDB  4,Y        ; $E0: waveform
            ANDB #7
            JMP  SKW

; SKWC0: track U's $C0 (feedback, connection and outputs), and its pair's.
SKWC0       LDE  T_ARR,U
            LDB  T_C0A,U
            ANDB #$0F
            ORB  T_PAN,U
            LDA  #$C0
            ADDA T_CH,U
            JSR  SKW
            LDB  T_FL,U
            BITB #2
            BEQ  SKWC9
            ADDA #3
            LDB  T_C0B,U
            ANDB #$0F
            ORB  T_PAN,U
            JMP  SKW
SKWC9       RTS

; SKFETCH: instrument A's 32 bytes into SK_IB (a silent one if there's none).
SKFETCH     LDX  #SK_IB
            LDB  #SK_ILEN
SKFE1       CLR  ,X+
            DECB
            BNE  SKFE1
            LDB  #$3F
            STB  SK_IB+4
            STB  SK_IB+9
            STB  SK_IB+14
            STB  SK_IB+19
            TSTA
            BEQ  SKFE9
            LDX  SK_IBASE   ; the editor's instruments
            BEQ  SKFE3
            CMPA SK_INUM
            BHI  SKFE9
            DECA
            LDB  #SK_ILEN
            MUL
            LEAX D,X
            LDY  #SK_IB
            LDW  #SK_ILEN
            TFM  X+,Y+
            RTS
SKFE3       CMPA SK_HDR+9
            BHI  SKFE9
            DECA
            LDB  #SK_ILEN
            MUL
            ADDD SK_ITAB
            PSHS D
            LDD  SK_PTR     ; (where the song was being read: back to it after)
            STD  SK_SPTR
            LDA  SK_PG
            STA  SK_SPG
            PULS X
            CLRA
            JSR  SKSEEK
            LDX  #SK_IB
            LDB  #SK_ILEN
SKFE2       JSR  SKGETB
            STA  ,X+
            DECB
            BNE  SKFE2
            LDD  SK_SPTR
            STD  SK_PTR
            TST  SK_PAGED
            BEQ  SKFE9
            LDB  SK_SPG
            JMP  SKMAP
SKFE9       RTS

;------------------------------------------------------------------------------
; Reading the song.
;------------------------------------------------------------------------------
; SKSEEK: to A:X (24 bits), from the song's start. (D and X kept.)
SKSEEK      PSHS A,B,X
            TST  SK_PAGED
            BNE  SKSK1
            TFR  X,D
            ADDD SK_BASE
            STD  SK_PTR
            PULS A,B,X,PC
SKSK1       TFR  X,D        ; in its page
            ANDA #$3F
            ADDD SK_WIN
            STD  SK_PTR
            LDA  2,S        ; and which page
            LSRA
            LSRA
            LSRA
            LSRA
            LSRA
            LSRA
            STA  SK_TMP
            LDB  ,S
            LSLB
            LSLB
            ORB  SK_TMP
            JSR  SKMAP
            PULS A,B,X,PC
; SKMAP: the song's page B into its window. (All kept.)
SKMAP       PSHS A,B,X
            PSHSW
            CMPB SK_NPG
            BLO  SKMP1
            LDB  SK_NPG     ; (past its end: the last, and nonsense read)
            DECB
SKMP1       STB  SK_PG
            LDX  SK_PGT
            LDE  B,X
            LDB  SK_BANK
            LDA  #B_BANK_SET
            SWI2
            PULSW
            PULS A,B,X,PC
; SKGETB: A, the song's next byte. (The rest kept.)
SKGETB      PSHS X
            LDX  SK_PTR
            LDA  ,X+
            CMPX SK_WEND
            BEQ  SKGB1
            STX  SK_PTR
            PULS X,PC
SKGB1       PSHS B          ; its window's end: the next page
            LDX  SK_WIN
            STX  SK_PTR
            LDB  SK_PG
            INCB
            JSR  SKMAP
            PULS B,X,PC

;------------------------------------------------------------------------------
; The chip.
;------------------------------------------------------------------------------
; SKW: B to the OPL3's register A of array E (0 or 1). (All kept.)
SKW         TSTE
            BNE  SKW1
            STA  SK_OPL
            NOP
            NOP
            NOP
            NOP
            NOP
            STB  SK_OPL+1
            NOP
            NOP
            NOP
            NOP
            NOP
            RTS
SKW1        STA  SK_OPL+2
            NOP
            NOP
            NOP
            NOP
            NOP
            STB  SK_OPL+3
            NOP
            NOP
            NOP
            NOP
            NOP
            RTS

; SK_STOP: the song stopped, every key let go.
SK_STOP     CLR  SK_PLAYING
            LDU  #SK_TRK
            LDB  #SK_NTRK
SKS1        PSHS B
            LDA  T_FL,U
            BITA #1
            BEQ  SKS2
            JSR  SKKOFF
SKS2        LEAU SK_TSIZE,U
            PULS B
            DECB
            BNE  SKS1
            RTS

; SK_OFF: silence -- every channel's key off, every operator all the way down,
; every channel's outputs off, in both arrays; the timers stopped; then the
; chip back in OPL2 mode with no 4-op channels, as it starts. (An operator at
; full attenuation still puts out a little, which 18 channels of add up to:
; with the outputs off, in OPL3 mode, there is nothing.)
SK_OFF      CLR  SK_PLAYING
            LDE  #1
            LDD  #$0501
            JSR  SKW
            CLRE
SKOF1       LDA  #$C0
            CLRB
SKOF2       JSR  SKW
            INCA
            CMPA #$C9
            BNE  SKOF2
            LDA  #$B0
SKOF3       JSR  SKW
            INCA
            CMPA #$B9
            BNE  SKOF3
            LDA  #$40
            LDB  #$3F
SKOF4       JSR  SKW
            INCA
            CMPA #$56
            BNE  SKOF4
            LDA  #$BD
            CLRB
            JSR  SKW
            INCE
            CMPE #2
            BNE  SKOF1
            CLRE
            LDD  #$0460
            JSR  SKW
            LDD  #$0480
            JSR  SKW
            INCE
            LDD  #$0400
            JSR  SKW
            LDD  #$0500
            JMP  SKW

;------------------------------------------------------------------------------
; Tables.
;------------------------------------------------------------------------------
SKFTAB      FDB  345,365,387,410,435,460,488,517,547,580,615,651,690
                            ; C to B, and the next C: F-numbers in a block (A is
                            ; 440 Hz in block 4)
SKSINE      FCB  0,12,25,37,49,60,71,81,90,98,106,112,117,122,125,126
            FCB  127,126,125,122,117,112,106,98,90,81,71,60,49,37,25,12
SKOPOFF     FCB  $00,$01,$02,$08,$09,$0A,$10,$11,$12 ; a channel's first operator
SKBITS      FCB  1,2,4,8,16,32
SKCAR4      FCB  $08,$0A,$09,$0D ; the 4-op algorithms' carriers
SKSILENT    FCB  0,$3F,$FF,$0F,0 ; an operator not playing
SKDRUMS     FCB  6,6,$10,$13,2,$10,0 ; track, channel, operators, how many,
            FCB  7,7,$14,0,1,$08,1   ; $BD bit, the instrument's operator:
            FCB  8,8,$12,0,1,$04,0   ; the bass drum, the snare, the tom, the
            FCB  18,8,$15,0,1,$02,1  ; cymbal and the hi-hat
            FCB  19,7,$11,0,1,$01,0
            FCB  $FF

;------------------------------------------------------------------------------
; The player's variables.
;------------------------------------------------------------------------------
SK_PLAYING  RMB  1
SK_TICKS    RMB  2
SK_RATE     RMB  1
SK_IBASE    RMB  2          ; the editor's instruments (0: the song's)
SK_INUM     RMB  1
SK_PAGED    RMB  1          ; the song: in pages (1) or in memory (0)
SK_BASE     RMB  2          ;   in memory: where
SK_PGT      RMB  2          ;   in pages: their list, how many, the bank, and its
SK_NPG      RMB  1          ;   window's start and end
SK_BANK     RMB  1
SK_WIN      RMB  2
SK_WEND     RMB  2
SK_PTR      RMB  2          ; the next byte to read, and its page
SK_PG       RMB  1
SK_SPTR     RMB  2          ; (kept while an instrument is read)
SK_SPG      RMB  1
SK_HDR      RMB  16         ; the song's header
SK_PTAB     RMB  2          ; where its pattern table is
SK_ITAB     RMB  2          ;   and its instruments
SK_BD       RMB  1          ; $BD as last written
SK_SPEED    RMB  1          ; ticks a row
SK_TICKN    RMB  1          ; this one, of the row's
SK_ORD      RMB  1          ; the order playing
SK_ROW      RMB  1          ;   its row, of how many
SK_ROWS     RMB  1
SK_SKIP     RMB  1          ; empty rows to come
SK_JFL      RMB  1          ; Bxx (bit 0) and Dxx (bit 1) in this row: where to
SK_JORD     RMB  1
SK_JROW     RMB  1
SK_BROW     RMB  1
SK_DISC     RMB  1
SK_GUARD    RMB  1
SK_ENT      RMB  1
SK_CELL     RMB  5          ; a cell read: note, instrument, volume, effect, its
SK_CP       RMB  2          ;   parameter
SK_TMP      RMB  1
SK_TMP3     RMB  3
SK_TMPW     RMB  2
SK_ATT      RMB  1
SK_OPO      RMB  1
SK_OUTP     RMB  2
SK_OCT      RMB  1
SK_FA0      RMB  1
SK_FB0      RMB  1
SK_SRC      RMB  4
SK_IB       RMB  SK_ILEN    ; an instrument read
SK_TRK      RMB  SK_NTRK*SK_TSIZE
;------------------------------------------------------------------------------
; End of sk_play.asm
;------------------------------------------------------------------------------
