;------------------------------------------------------------------------------
; PROJECT: VGM PLAYER
;    FILE: vgmplay.asm
;
; VGMPLAY.COM: plays a VGM file on the OPL3 music chip (YMF262):
;
;   VGMPLAY file             (".VGM" is added to a name without an extension)
;
; A VGM file is a log of a sound chip's register writes and the waits between
; them, in samples at 44100 Hz. This plays the OPL3's (and the OPL2's: a YM3812
; song plays on the OPL3's first register array), as WAV2VGM and VGM loggers
; write them; other chips' commands are skipped. Ctrl-C stops it.
;
; The file is read as it plays, a sector (512 bytes) at a time, so a song can be
; as long as the disk has room for. The OPL3's Timer 1 keeps the time: it ticks
; every 4 ms (176.4 samples), and the player waits for as many ticks as the
; song's waits add up to. So the song keeps the chip's time, however long the
; register writes take along the way (when the player falls behind, it catches
; up). The timer only says that it has ticked, not how often, so a tick must
; not go by unseen: a read, which takes a few ms, starts just after one. The
; song's own writes to the timer registers (2, 3 and 4) are left out: Timer 1
; is the player's.
;
;   ASM -f com vgmplay.asm   makes VGMPLAY.COM
;------------------------------------------------------------------------------
OPL3_BASE   equ  $FFE0      ; ffe0 - ffe3: Music Chip YMF262 (OPL3)
F_STDOUT    equ  $01        ; the BIOS and DOS calls used (see /ASM/DEFINES.D)
F_STDIN     equ  $02
B_PUTS      equ  $0A
B_GETC      equ  $0C
B_FOPEN_NAME equ $13
B_FREAD     equ  $1D
B_FSEEK_NAME equ $1F
B_ARGS      equ  $2A
B_EXIT      equ  $2B
FOPEN_READ  equ  $00
SEEK_SET    equ  $00
ERR_NOTFOUND equ $05
ERR_EOF     equ  $09
ERR_NOTDIR  equ  $0C
ERR_ISDIR   equ  $0D
ERR_BADPATH equ  $0F
CR          equ  $0D
LF          equ  $0A
;------------------------------------------------------------------------------
NAMEMAX     equ  79
BUFSIZE     equ  512        ; read at a time: a sector
HDRSIZE     equ  $80        ; the header: what's used of it is below $60
T1_STEPS    equ  50         ; Timer 1 counts 80 us steps: a tick is 50 of them, 4 ms,
TICK_FIFTHS equ  882        ; which is 176.4 samples: 882 fifths of a sample
BEHIND_MAX  equ  20000      ; the most (in fifths of a sample) the song is let fall
                            ; behind the clock: any more is forgotten, not caught up
;------------------------------------------------------------------------------
            ORG     $4000   ; CODE & VARS (a program loads above DOS's RAM)
;------------------------------------------------------------------------------
START       LDS  #$7F00
            LDA  #B_ARGS    ; the file name: the tail's first word
            SWI2
VP_SKIP     LDA  ,X
            CMPA #' '
            BNE  VP_NAME
            LEAX 1,X
            BRA  VP_SKIP
VP_NAME     TSTA
            LBEQ USAGE
            LDY  #NAMEBUF
            LDB  #NAMEMAX-4 ; (room for ".VGM")
            CLR  DOT
VP_NCOPY    LDA  ,X+
            BEQ  VP_NEND
            CMPA #' '
            BEQ  VP_NEND
            CMPA #'a'       ; (in upper case, as DOS has it)
            BLO  VP_NCHAR
            CMPA #'z'
            BHI  VP_NCHAR
            SUBA #'a'-'A'
VP_NCHAR    STA  ,Y+
            CMPA #'.'       ; an extension (a dot after the path's last "/")
            BNE  VP_NSLASH
            STA  DOT
VP_NSLASH   CMPA #'/'
            BNE  VP_NNEXT
            CLR  DOT
VP_NNEXT    DECB
            BNE  VP_NCOPY
VP_NEND     CLR  ,Y
            TST  DOT
            BNE  VP_OPEN
            LDX  #EXT_VGM   ; none: ".VGM"
VP_EXT      LDA  ,X+
            STA  ,Y+
            BNE  VP_EXT
VP_OPEN     LDX  #NAMEBUF
            LDE  #FOPEN_READ
            LDA  #B_FOPEN_NAME
            SWI2
            LBCS FAIL
            STA  FH
;------------------------------------------------------------------------------
; The header: "Vgm ", version 1.51 or later (the first with the OPL chips),
; and a clock for the YMF262 (OPL3) or the YM3812 (OPL2). Its numbers are
; little-endian.
;------------------------------------------------------------------------------
            LDB  FH
            LDX  #BUF
            LDY  #HDRSIZE
            LDA  #B_FREAD
            SWI2
            BCC  VP_HDR
            CMPA #ERR_EOF   ; (an empty file)
            LBNE FAIL
            LDX  #0
VP_HDR      CMPX #$60
            LBLO NOTVGM
            LDD  BUF
            CMPD #$1F8B     ; gzip's mark: a .VGZ, a VGM file compressed
            LBEQ PACKED
            CMPD #$5667     ; "Vg"
            LBNE NOTVGM
            LDD  BUF+2
            CMPD #$6D20     ; "m "
            LBNE NOTVGM
            LDD  BUF+8      ; the version
            EXG  A,B
            CMPD #$0151
            LBLO NOTOPL
            LDQ  BUF+$5C    ; the YMF262's clock
            BNE  VP_DATA
            LDQ  BUF+$50    ; or the YM3812's
            LBEQ NOTOPL
VP_DATA     LDD  BUF+$36    ; where the commands start: $34 + the offset at $34
            LBNE NOTVGM     ; (the offset is 32 bits; any real one is small)
            LDD  BUF+$34
            EXG  A,B
            ADDD #$34
            CMPD #$34       ; (0: the old place, $40)
            BNE  VP_SEEK
            LDD  #$40
VP_SEEK     TFR  D,Y
            ANDD #BUFSIZE-1 ; the first read only to the end of its sector
            STD  TMP
            LDD  #BUFSIZE
            SUBD TMP
            STD  READLEN
            LDX  #0
            LDE  #SEEK_SET
            LDB  FH
            LDA  #B_FSEEK_NAME
            SWI2
            LBCS FAIL
            LDU  #BUF       ; U: the next byte; the buffer is empty
            STU  BUFEND
            LDX  #MSG_PLAY  ; "Playing name (Ctrl-C stops it)"
            JSR  PUTS
            LDX  #NAMEBUF
            JSR  PUTS
            LDX  #MSG_PLAY2
            JSR  PUTS
;------------------------------------------------------------------------------
; The chip quiet, then Timer 1 started: a tick every 4 ms, its flag in the
; status register (Timer 2 masked, so its flag never shows).
;------------------------------------------------------------------------------
            JSR  OPL_QUIET
            CLRE
            LDD  #$0200+(256-T1_STEPS)
            JSR  OPL_WRITE
            LDD  #$0480     ; the flags cleared
            JSR  OPL_WRITE
            LDD  #$0421     ; Timer 1 on, Timer 2 masked
            JSR  OPL_WRITE
            LDD  #0
            STD  CREDIT
;------------------------------------------------------------------------------
; The song: a command at a time, and Timer 1's ticks counted as they come.
;------------------------------------------------------------------------------
PLAY        LDA  OPL3_BASE  ; a tick? (Timer 1's flag, bit 6 of the status)
            BITA #$40
            BEQ  PL_CMD
            JSR  TICK
PL_CMD      JSR  GETB
            CMPA #$5E       ; $5E rr dd: register rr of array 0 = dd
            BEQ  PL_W0
            CMPA #$5F       ; $5F rr dd: array 1
            BEQ  PL_W1
            CMPA #$61       ; $61 nnnn: wait nnnn samples
            BEQ  PL_WAIT
            CMPA #$70
            LBLO PL_LOW
            CMPA #$7F       ; $7n: wait n+1 samples
            BLS  PL_SHORT
            CMPA #$8F       ; $8n: a YM2612 sample, then wait n
            BLS  PL_DAC
            LBRA PL_HIGH
PL_W0       JSR  GETB       ; the register
            TFR  A,F
            JSR  GETB       ; its value
            CMPF #4
            BHI  PL_W0OK
            CMPF #2
            BHS  PLAY       ; (2-4: the timers, the player's)
PL_W0OK     STF  OPL3_BASE
            NOP
            NOP
            NOP
            NOP
            NOP
            STA  OPL3_BASE+1
            NOP
            NOP
            NOP
            NOP
            NOP
            BRA  PLAY
PL_W1       JSR  GETB
            TFR  A,F
            JSR  GETB
            STF  OPL3_BASE+2
            NOP
            NOP
            NOP
            NOP
            NOP
            STA  OPL3_BASE+3
            NOP
            NOP
            NOP
            NOP
            NOP
            BRA  PLAY
PL_WAIT     JSR  GETB       ; (little-endian)
            TFR  A,F
            JSR  GETB
            TFR  A,E
            TFR  W,D
            BRA  PL_WAITD
PL_SHORT    ANDA #$0F
            INCA
            TFR  A,B
            CLRA
            BRA  PL_WAITD
PL_DAC      ANDA #$0F
            TFR  A,B
            CLRA
PL_WAITD    JSR  WAIT
            LBRA PLAY
;------------------------------------------------------------------------------
; The other commands: the waits for 1/60 and 1/50 s, the end, data blocks
; (skipped), and other chips' writes (skipped: each has its operands' length).
;------------------------------------------------------------------------------
PL_LOW      CMPA #$5A       ; $5A rr dd: the YM3812 (OPL2): array 0
            BEQ  PL_W0
            CMPA #$62       ; a 60th of a second
            BNE  PL_NOT62
            LDD  #735
            BRA  PL_WAITD
PL_NOT62    CMPA #$63       ; a 50th
            BNE  PL_NOT63
            LDD  #882
            BRA  PL_WAITD
PL_NOT63    CMPA #$66       ; the end
            LBEQ DONE
            CMPA #$67       ; $67 $66 tt ssssssss: a data block, ss bytes
            BEQ  PL_BLOCK
            LDB  #11        ; $68: a PCM RAM write, 11 bytes
            CMPA #$68
            BEQ  SKIPN
            CMPA #$30       ; ($00-$2F: none)
            LBLO PLAY
            LDB  #1         ; $30-$3F: 1 byte
            CMPA #$3F
            BLS  SKIPN
            LDB  #2         ; $40-$4E: 2
            CMPA #$4E
            BLS  SKIPN
            LDB  #1         ; $4F, $50: 1
            CMPA #$50
            BLS  SKIPN
            LDB  #2         ; $51-$5F: 2
            CMPA #$5F
            BLS  SKIPN
            LBRA PLAY       ; ($60, $64, $65, $69-$6F: none)
PL_HIGH     CMPA #$95       ; $90-$95: DAC stream control
            BHI  PL_ABOVE
            SUBA #$90
            LDX  #STREAMLEN
            LDB  A,X
            BRA  SKIPN
PL_ABOVE    CMPA #$A0       ; ($96-$9F: none)
            LBLO PLAY
            LDB  #2         ; $A0-$BF: 2
            CMPA #$BF
            BLS  SKIPN
            LDB  #3         ; $C0-$DF: 3
            CMPA #$DF
            BLS  SKIPN
            LDB  #4         ; $E0-$FF: 4
SKIPN       JSR  GETB       ; B bytes skipped
            DECB
            BNE  SKIPN
            LBRA PLAY
PL_BLOCK    JSR  GETB       ; ($66)
            JSR  GETB       ; (the type)
            JSR  GETB       ; the size, little-endian
            STA  SKIP+3
            JSR  GETB
            STA  SKIP+2
            JSR  GETB
            STA  SKIP+1
            JSR  GETB
            STA  SKIP
PB_LOOP     LDQ  SKIP
            LBEQ PLAY
            LDD  SKIP+2
            SUBD #1
            STD  SKIP+2
            LDD  SKIP
            SBCD #0
            STD  SKIP
            JSR  GETB
            BRA  PB_LOOP
;------------------------------------------------------------------------------
; Wait D samples: the song moves on, and while it is ahead of Timer 1's ticks
; the player waits for them. CREDIT counts fifths of a sample: + a tick's 882,
; - a wait's 5 a sample.
;------------------------------------------------------------------------------
WAIT        CMPD #6000      ; in parts of up to 6000 samples (30000 fifths: they fit)
            BLS  WT_PART
            SUBD #6000
            PSHS D
            LDD  #6000
            BSR  WT_PART
            PULS D
            BRA  WAIT
WT_PART     STD  TMP
            ASLD
            ASLD
            ADDD TMP
            STD  TMP
            LDD  CREDIT
            SUBD TMP
            STD  CREDIT
WT_LOOP     LDD  CREDIT     ; not ahead of the clock: done
            BPL  WT_DONE
            LDA  OPL3_BASE
            BITA #$40
            BEQ  WT_LOOP
            BSR  TICK
            BRA  WT_LOOP
WT_DONE     RTS
;------------------------------------------------------------------------------
; A tick of Timer 1: its flag cleared (the timer runs on), 4 ms more on the
; clock -- and a Ctrl-C typed meanwhile ends the song.
;------------------------------------------------------------------------------
TICK        LDD  #$0480     ; register 4 = $80: the flags cleared
            STA  OPL3_BASE
            NOP
            NOP
            NOP
            NOP
            NOP
            STB  OPL3_BASE+1
            LDD  CREDIT
            ADDD #TICK_FIFTHS
            CMPD #BEHIND_MAX
            BLE  TK_KEEP
            LDD  #BEHIND_MAX
TK_KEEP     STD  CREDIT
            LDB  #F_STDIN
            LDA  #B_GETC
            SWI2
            BCS  TK_DONE
            CMPA #3
            LBEQ CANCEL
TK_DONE     RTS
;------------------------------------------------------------------------------
; A: the song's next byte (U moves on), the buffer filled again when it runs
; out. Keeps B, E, F, X and Y. The file's end, or a disk error, ends the song.
;------------------------------------------------------------------------------
GETB        CMPU BUFEND
            BHS  REFILL
            LDA  ,U+
            RTS
REFILL      PSHS B,X,Y
RF_SYNC     LDA  OPL3_BASE  ; just after a tick: the next one can't come and go
            BITA #$40       ; unseen while the sector is read
            BEQ  RF_SYNC
            JSR  TICK
            LDB  FH
            LDX  #BUF
            LDY  READLEN
            LDA  #B_FREAD
            SWI2
            BCS  RF_END
            CMPX #0
            BEQ  DONE
            LDU  #BUF
            TFR  X,D
            ADDD #BUF
            STD  BUFEND
            LDD  #BUFSIZE   ; (from here on, whole sectors)
            STD  READLEN
            PULS B,X,Y
            LDA  ,U+
            RTS
RF_END      CMPA #ERR_EOF
            BEQ  DONE
            PSHS A          ; a disk error: the chip quiet, then the message
            JSR  OPL_QUIET
            PULS A
            BRA  FAIL
;------------------------------------------------------------------------------
DONE        JSR  OPL_QUIET  ; the end (or Ctrl-C): silence, then back to the shell
EXIT        LDA  #B_EXIT    ; (DOS closes the file)
            SWI2
CANCEL      JSR  OPL_QUIET
            LDX  #MSG_CANCEL
            BRA  SAY
USAGE       LDX  #MSG_USAGE
SAY         BSR  PUTS
            BRA  EXIT
NOTVGM      LDX  #MSG_NOTVGM
            BRA  SAYNAME
NOTOPL      LDX  #MSG_NOTOPL
            BRA  SAYNAME
PACKED      LDX  #MSG_PACKED
            BRA  SAYNAME
FAIL        LDX  #ERRMSGS   ; A = the error: its message, if it has one
FL_FIND     LDB  ,X+
            BEQ  FL_NUM
            CMPA -1,X
            BEQ  SAYNAME
FL_SKIP     TST  ,X+
            BNE  FL_SKIP
            BRA  FL_FIND
FL_NUM      LDX  #MSG_ERR   ; "Disk error" will do for the rest
SAYNAME     PSHS X          ; "name: message"
            LDX  #NAMEBUF
            BSR  PUTS
            LDX  #MSG_COLON
            BSR  PUTS
            PULS X
            BRA  SAY
PUTS        LDB  #F_STDOUT  ; X = a NUL-terminated string
            LDA  #B_PUTS
            SWI2
            RTS
; -----------------------------------------------------------------------------
; Write B to the OPL3 register A of array E (0 or 1). Keeps A, B and E.
; -----------------------------------------------------------------------------
OPL_WRITE   CMPE #00
            BEQ  BANK0
BANK1       STA  OPL3_BASE+2
            NOP
            NOP
            NOP
            NOP
            NOP
            STB  OPL3_BASE+3
            NOP
            NOP
            NOP
            NOP
            NOP
            RTS
BANK0       STA  OPL3_BASE+0
            NOP
            NOP
            NOP
            NOP
            NOP
            STB  OPL3_BASE+1
            NOP
            NOP
            NOP
            NOP
            NOP
            RTS
; -----------------------------------------------------------------------------
; Silence: every channel's key off, every operator at full attenuation and
; every channel's outputs off, in both arrays; the timers stopped; then the
; chip back in OPL2 mode, as it starts (register $105), with no 4-operator
; channels ($104). (Even at full attenuation, an operator halfway through its
; wave puts out -1, not 0: 18 channels of that are a faint DC that the chip
; would keep up. With the outputs off, in OPL3 mode, there is nothing; they
; stay off in OPL2 mode, until a song writes the channel's $C0 again.)
; -----------------------------------------------------------------------------
OPL_QUIET   LDE  #1
            LDD  #$0501     ; $105: OPL3 mode, for the outputs' bits in $C0-$C8
            JSR  OPL_WRITE
            CLRE
QT_BANK     LDA  #$C0
            CLRB
QT_OUT      JSR  OPL_WRITE  ; $C0-$C8: no outputs
            INCA
            CMPA #$C9
            BNE  QT_OUT
            LDA  #$B0
            CLRB
QT_KEY      JSR  OPL_WRITE  ; $B0-$B8: key off
            INCA
            CMPA #$B9
            BNE  QT_KEY
            LDA  #$40
            LDB  #$3F
QT_TL       JSR  OPL_WRITE  ; $40-$55: total level, all the way down
            INCA
            CMPA #$56
            BNE  QT_TL
            LDA  #$BD
            CLRB
            JSR  OPL_WRITE
            INCE
            CMPE #2
            BNE  QT_BANK
            CLRE
            LDD  #$0460     ; the timers stopped (and masked), their flags cleared
            JSR  OPL_WRITE
            LDD  #$0480
            JSR  OPL_WRITE
            INCE
            LDD  #$0400     ; $104
            JSR  OPL_WRITE
            LDD  #$0500     ; $105
            JMP  OPL_WRITE
;------------------------------------------------------------------------------
STREAMLEN   FCB  4,4,5,10,1,4 ; $90-$95's operands
EXT_VGM     FCC  ".VGM"
            FCB  0
MSG_PLAY    FCC  "Playing "
            FCB  0
MSG_PLAY2   FCC  " (Ctrl-C stops it)"
MSG_CRLF    FCB  CR,LF,0
MSG_USAGE   FCC  "Usage: VGMPLAY file[.VGM]"
            FCB  CR,LF,0
MSG_CANCEL  FCC  "^C"
            FCB  CR,LF,0
MSG_COLON   FCC  ": "
            FCB  0
MSG_NOTVGM  FCC  "Not a VGM file"
            FCB  CR,LF,0
MSG_NOTOPL  FCC  "Not an OPL3 (or OPL2) song"
            FCB  CR,LF,0
MSG_PACKED  FCC  "Compressed (.VGZ): unzip it to a .VGM first"
            FCB  CR,LF,0
ERRMSGS     FCB  ERR_NOTFOUND ; (code, message; 0 ends the list)
            FCC  "File not found"
            FCB  CR,LF,0
            FCB  ERR_ISDIR
            FCC  "Is a directory"
            FCB  CR,LF,0
            FCB  ERR_NOTDIR
            FCC  "Not a directory"
            FCB  CR,LF,0
            FCB  ERR_BADPATH
            FCC  "Bad name or path"
            FCB  CR,LF,0
            FCB  0
MSG_ERR     FCC  "Disk error"
            FCB  CR,LF,0
;------------------------------------------------------------------------------
; Variables and buffers are just addresses after the last byte of code.
;------------------------------------------------------------------------------
NAMEBUF     equ  *          ; 80
BUF         equ  NAMEBUF+NAMEMAX+1 ; BUFSIZE: the song, as it is read
BUFEND      equ  BUF+BUFSIZE ; 2: the end of what's in BUF
READLEN     equ  BUFEND+2   ; 2: how much the next read asks for
CREDIT      equ  READLEN+2  ; 2: the clock's lead on the song (fifths of a sample)
TMP         equ  CREDIT+2   ; 2
SKIP        equ  TMP+2      ; 4: a data block's bytes still to skip
FH          equ  SKIP+4     ; the file's handle
DOT         equ  FH+1       ; the name has an extension
VP_END      equ  DOT+1
;------------------------------------------------------------------------------
; End of vgmplay.asm
;------------------------------------------------------------------------------
