;------------------------------------------------------------------------------
; PROJECT: VIDEO CARD DEMOS
;    FILE: swamp.asm
;
; A swamp at night in three tile layers, scrolled at their own speeds until a
; key is pressed: the sky stands still, the bayou drifts by, the mossy ground
; in front runs past. 320x240, 16x16 tiles of 8 bits a pixel.
;
; The pictures aren't in the program (their 77KB of tiles is more than it has
; room for): they are a TILEKIT project, read from the disk as it starts --
; SWAMP1.TLS and SWAMP1.MAP for layer 0 (at the back) to SWAMP3.TLS and
; SWAMP3.MAP for layer 2 (in front), and the palette from SWAMP1.TLS -- looked
; for in /DEMO, then in the current directory. So TILEKIT can change them
; (TILEKIT SWAMP.TKT), and this shows what it saves: tiles of any size and
; depth, maps of any size. Each layer has 48KB of video memory, as in TILEKIT:
; its tiles at the start, its map at the end.
;
; And music, if there is a SWAMP.VGM beside them: a VGM file for the OPL3 (or
; OPL2), as VGMPLAY plays. It goes into the card's PSRAM as it loads, the whole
; of it, and plays from there through data port 1 -- so the disk isn't read
; while the swamp scrolls -- over and over (from the song's loop point, if it
; has one). The OPL3's Timer 1 keeps its time, as in VGMPLAY: the loop below
; looks for its ticks (every 4 ms) and for the card's vertical blank (every
; 1/60 s), and plays the song between them, giving way to the vertical blank,
; so the scrolling is never late. Without the file, the swamp is silent. (The
; demo disk's is Red River Valley, a traditional song, made from a MIDI file
; by midi2vgm_opl3.)
;
;   ASM -f com swamp.asm        makes SWAMP.COM
;------------------------------------------------------------------------------
            INCLUDE "vidcard.d"

F_STDOUT    equ  $01        ; the DOS calls used (see /ASM/DEFINES.D)
B_PUTS      equ  $0A
B_FOPEN_NAME equ $13
B_FCLOSE_NAME equ $16
B_FREAD     equ  $1D
FOPEN_READ  equ  $00
ERR_EOF     equ  $09
CR          equ  $0D
LF          equ  $0A
ROOM        equ  $C000      ; each layer's video memory: 48KB
BUFSIZE     equ  512        ; read at a time: a sector
SONG        equ  $80        ; the song in the PSRAM: from $800000 (the file's offsets
                            ; are its addresses there, with this as the high byte)
OPL3_BASE   equ  $FFE0      ; $FFE0-$FFE3: the OPL3 (YMF262)
T1_STEPS    equ  50         ; Timer 1 counts 80 us steps: a tick is 50 of them, 4 ms,
TICK_FIFTHS equ  882        ; which is 176.4 samples: 882 fifths of a sample
BEHIND_MAX  equ  20000      ; the most (in fifths of a sample) the song may fall behind
;------------------------------------------------------------------------------
            ORG  $4000
START       LDA  #$80
            STA  VC_CTRL        ; the card as it starts: a blank text screen
            LDX  #T_LOADING
            JSR  PUTS
            LDX  #LAYERS        ; the three layers' settings: 0 but for what the
            LDB  #48            ; files say (so not scrolled)
CLEAR       CLR  ,X+
            DECB
            BNE  CLEAR
            CLR  LAYERN
;------------------------------------------------------------------------------
; Each layer: its tile set (and the first one's palette), then its map.
;------------------------------------------------------------------------------
LAYER       LDA  LAYERN
            ADDA #'1
            STA  N_TLS+11       ; "/DEMO/SWAMPn.TLS"
            STA  N_MAP+11
            LDA  LAYERN         ; its settings
            LDB  #16
            MUL
            ADDD #LAYERS
            STD  SETP
            LDA  LAYERN         ; its room's start
            LDB  #3
            MUL
            ADDD #ROOMS
            STD  ROOMP
            LDX  #N_TLS
            JSR  OPEN
            LDD  #16            ; "PTS1", tile size, bits a pixel, flags, 0,
            JSR  HEADER         ; how many tiles, 6 bytes of 0
            LDD  BUF
            CMPD #$5054         ; "PT"
            LBNE BADFILE
            LDD  BUF+2
            CMPD #$5331         ; "S1"
            LBNE BADFILE
            LDB  #LM_TILE       ; L_MODE from them
            LDA  BUF+4
            CMPA #16
            BNE  MODE1
            ORB  #LM_BIG        ; 16x16
MODE1       LDA  BUF+5          ; 1, 2, 4 or 8 bits a pixel
            CMPA #2
            BLO  MODE2
            ADDB #LM_2BPP
            CMPA #4
            BLO  MODE2
            ADDB #LM_2BPP
            CMPA #8
            BLO  MODE2
            ADDB #LM_2BPP
MODE2       LDA  BUF+6
            BITA #1
            BEQ  MODE3
            ORB  #LM_HIRES      ; 640x480
MODE3       LDX  SETP
            STB  L_MODE,X
            LDY  ROOMP          ; the tiles at the room's start
            LDA  ,Y
            STA  L_TILEBASE,X
            LDD  1,Y
            STD  L_TILEBASE+1,X
            LDD  #512           ; the palette: the first set's is the card's
            JSR  HEADER
            TST  LAYERN
            BNE  TILES
            LDA  #VC_PAL/$10000
            LDX  #VC_PAL&$FFFF
            JSR  PORT0
            LDX  #BUF
            LDW  #512
            JSR  SENDDAT
TILES       LDY  ROOMP          ; and the tiles: the rest of the file
            LDA  ,Y
            LDX  1,Y
            JSR  PORT0
            JSR  STREAM
;------------------------------------------------------------------------------
            LDX  #N_MAP
            JSR  OPEN
            LDD  #48            ; "PTM1", width, height (in cells), the set's name
            JSR  HEADER
            LDD  BUF
            CMPD #$5054         ; "PT"
            LBNE BADFILE
            LDD  BUF+2
            CMPD #$4D31         ; "M1"
            LBNE BADFILE
            LDD  BUF+4
            JSR  SIZECODE
            STB  WCODE
            LDD  BUF+6
            JSR  SIZECODE
            STB  HCODE
            LSLB
            LSLB
            ORB  WCODE
            LDX  SETP
            STB  L_MAP,X
            LDA  WCODE          ; its bytes: 2048 (32x32 cells) times 2 for each
            ADDA HCODE          ; step up in width or height -- 32KB at most
            CMPA #4
            LBHI BADFILE
            TFR  A,E
            LDD  #2048
BYTES1      TSTE
            BEQ  BYTES2
            LSLD
            DECE
            BRA  BYTES1
BYTES2      STD  BYTES
            LDY  ROOMP          ; at the room's end: its start + 48KB - them
            LDD  1,Y
            ADDD #ROOM
            STD  MAPADR+1
            LDA  ,Y
            ADCA #0
            STA  MAPADR
            LDD  MAPADR+1
            SUBD BYTES
            STD  MAPADR+1
            LDA  MAPADR
            SBCA #0
            STA  MAPADR
            LDX  SETP
            STA  L_MAPBASE,X
            LDD  MAPADR+1
            STD  L_MAPBASE+1,X
            LDA  MAPADR
            LDX  MAPADR+1
            JSR  PORT0
            JSR  STREAM
            INC  LAYERN
            LDA  LAYERN
            CMPA #3
            LBLO LAYER
            JSR  LOADSONG       ; and the music, if there is any
;------------------------------------------------------------------------------
; All loaded: the layers on, together, at a vertical blank; the music started.
;------------------------------------------------------------------------------
            JSR  VBLANK
            LDA  #VC_CFG/$10000
            LDX  #LAYER0
            JSR  PORT0
            LDX  #LAYERS
            LDW  #48
            JSR  SENDDAT
            LDA  #VC_CFG/$10000
            LDX  #DC_CTRL
            JSR  PORT0
            LDA  #$07           ; layers 0-2, no sprites
            STA  VC_DATA0
            CLRA                ; the backdrop: color 0
            STA  VC_DATA0
            TST  MUSICON
            BEQ  FRAME
            JSR  OPL_QUIET      ; the chip quiet, then Timer 1 started: a tick
            CLRE                ; every 4 ms, its flag in the status register
            LDD  #$0200+(256-T1_STEPS)
            JSR  OPL_WRITE
            LDD  #$0480         ; (the flags cleared)
            JSR  OPL_WRITE
            LDD  #$0421         ; (Timer 1 on, Timer 2 masked)
            JSR  OPL_WRITE
            LDD  #0             ; the song from its start, the clock with it
            STD  CREDIT
            STD  WAITLEFT
            CLR  WAITED
            LDX  #SONGTOP
            JSR  PORT1AT
;------------------------------------------------------------------------------
; Round and round: the music, as Timer 1 ticks, until the vertical blank; then
; the frame. The sky stays, the bayou moves a pixel every 2 frames, the ground
; 2 pixels a frame. (The maps wrap, and the frame count wraps at a multiple of
; their width, so the scrolling never jumps.)
;------------------------------------------------------------------------------
FRAME       TST  MUSICON
            BEQ  FRAME1
            LDA  OPL3_BASE      ; a tick? (Timer 1's flag, bit 6 of the status)
            BITA #$40
            BEQ  FRAME0
            JSR  TICK
FRAME0      JSR  MUSIC
FRAME1      LDA  VC_ISR         ; the vertical blank?
            BITA #VC_I_VSYNC
            BEQ  FRAME
            LDA  #VC_I_VSYNC    ; (its flag cleared)
            STA  VC_ISR
            LDD  VL_FRAMES
            ADDD #1
            STD  VL_FRAMES
            LDA  #VC_CFG/$10000
            LDX  #LAYER1+L_HSCROLL
            JSR  PORT0
            LDD  VL_FRAMES
            LSRD
            STA  VC_DATA0
            STB  VC_DATA0
            LDA  #VC_CFG/$10000
            LDX  #LAYER2+L_HSCROLL
            JSR  PORT0
            LDD  VL_FRAMES
            LSLD
            STA  VC_DATA0
            STB  VC_DATA0
            JSR  GETKEY
            LBCS FRAME
            TST  MUSICON        ; a key: the chip quiet, and back to the shell
            BEQ  FRAME2
            JSR  OPL_QUIET
FRAME2      JMP  QUIT
;------------------------------------------------------------------------------
; OPEN: the file named at X ("/DEMO/name"), or else "name" here; FH its handle.
; TRYOPEN: the same, but carry set if there's neither.
;------------------------------------------------------------------------------
OPEN        BSR  TRYOPEN
            LBCS NOTFOUND
            RTS
TRYOPEN     STX  NAMEP
            LDE  #FOPEN_READ
            LDA  #B_FOPEN_NAME
            SWI2
            BCC  OPENED
            LDX  NAMEP
            LEAX 6,X            ; (past "/DEMO/")
            STX  NAMEP
            LDE  #FOPEN_READ
            LDA  #B_FOPEN_NAME
            SWI2
            BCS  OPENED1
OPENED      STA  FH
OPENED1     RTS
; READ: up to Y bytes of the file into BUF; X how many there were (0: its end).
READ        LDB  FH
            LDX  #BUF
            LDA  #B_FREAD
            SWI2
            BCC  READ1
            CMPA #ERR_EOF
            LBNE DISKERR
            LDX  #0
READ1       RTS
; HEADER: D bytes of the file into BUF -- all of them, or it isn't the file
; expected.
HEADER      STD  WANT
            TFR  D,Y
            BSR  READ
            CMPX WANT
            LBNE BADFILE
            RTS
; STREAM: the rest of the file to data port 0, then closes it.
STREAM      LDY  #BUFSIZE
            BSR  READ
            CMPX #0
            BEQ  STREAM1
            TFR  X,W
            LDX  #BUF
            JSR  SENDDAT
            BRA  STREAM
STREAM1     LDB  FH
            LDA  #B_FCLOSE_NAME
            SWI2
            RTS
; SIZECODE: a map's width or height in D (32, 64, 128 or 256 cells) as L_MAP has
; it, 0-3, in B.
SIZECODE    CLRE
SIZE1       CMPD #32
            BEQ  SIZE2
            LSRD
            INCE
            CMPE #4
            BLO  SIZE1
            LBRA BADFILE
SIZE2       TFR  E,B
            RTS
;------------------------------------------------------------------------------
; LOADSONG: SWAMP.VGM, if there is one and it's a song for the OPL3 or OPL2,
; the whole file into the PSRAM from $800000; MUSICON set if so. Where its
; commands start, end and loop from are noted as addresses there, and a $66
; (the end) put at its end -- some files have none, going straight on to their
; tags.
;------------------------------------------------------------------------------
LOADSONG    CLR  MUSICON
            LDX  #N_VGM
            JSR  TRYOPEN
            LBCS LS_NONE
            LDY  #128           ; the header: "Vgm ", the version (1.51 or later,
            JSR  READ           ; the first with the OPL chips) and a clock for
            STX  TMPW           ; the YMF262 (OPL3) or the YM3812 (OPL2)
            CMPX #$60
            LBLO LS_NOT
            LDD  BUF
            CMPD #$5667         ; "Vg"
            LBNE LS_NOT
            LDD  BUF+2
            CMPD #$6D20         ; "m "
            LBNE LS_NOT
            LDD  BUF+8          ; (its numbers are little-endian)
            EXG  A,B
            CMPD #$0151
            LBLO LS_NOT
            LDD  BUF+$5C
            ORD  BUF+$5E
            BNE  LS_OK
            LDD  BUF+$50
            ORD  BUF+$52
            BEQ  LS_NOT
LS_OK       LDX  #BUF+$34       ; the commands: $34 + the offset at $34 (0: $40)
            LDB  #$34
            LDY  #SONGTOP
            BSR  LEOFS
            BNE  LS_END
            CLR  SONGTOP
            LDD  #$40
            STD  SONGTOP+1
LS_END      LDX  #BUF+$14       ; their end: the tags ($14 + the offset at $14)
            LDB  #$14
            LDY  #SONGEND
            BSR  LEOFS
            BNE  LS_LOOP
            LDX  #BUF+4         ; or, with none, the file's ($4 + the offset at $4)
            LDB  #4
            BSR  LEOFS
LS_LOOP     LDX  #BUF+$1C       ; the loop: $1C + the offset at $1C (0: the start)
            LDB  #$1C
            LDY  #SONGLOOP
            BSR  LEOFS
            BNE  LS_COPY
            LDD  SONGTOP
            STD  SONGLOOP
            LDA  SONGTOP+2
            STA  SONGLOOP+2
LS_COPY     LDA  #SONG          ; the file into the PSRAM: the header read, then the rest
            LDX  #0
            JSR  PORT0
            LDX  #BUF
            LDW  TMPW
            JSR  SENDDAT
            JSR  STREAM         ; (which closes it)
            LDA  SONGEND        ; and the end marked
            ORA  #SONG
            LDX  SONGEND+1
            JSR  PORT0
            LDA  #$66
            STA  VC_DATA0
            LDA  #1
            STA  MUSICON
            RTS
LS_NOT      LDB  FH             ; not a song for this: none
            LDA  #B_FCLOSE_NAME
            SWI2
LS_NONE     RTS
; LEOFS: the 32-bit little-endian offset at X, plus B (where it counts from), to
; the 3 bytes at Y (high first); Z set, and nothing stored, if the offset is 0.
LEOFS       LDA  ,X
            ORA  1,X
            ORA  2,X
            ORA  3,X
            BEQ  LEOFS1
            LDA  ,X
            PSHS B
            ADDA ,S+
            STA  2,Y
            LDA  1,X
            ADCA #0
            STA  1,Y
            LDA  2,X
            ADCA #0
            STA  ,Y
            LDA  #1             ; (Z clear)
LEOFS1      RTS
; PORT1AT: data port 1 at the song's address at X (3 bytes, from SONG), step 1.
PORT1AT     LDA  ,X
            ORA  #SONG
            LDX  1,X
            STA  VC_ADDR1
            STX  VC_ADDR1M
            LDD  #1
            STD  VC_INC1
            RTS
;------------------------------------------------------------------------------
; A tick of Timer 1: its flag cleared (the timer runs on), and 4 ms more on the
; clock. CREDIT is how far the clock is ahead of the song, in fifths of a
; sample (a tick's 176.4 samples are 882): the song plays while it isn't
; negative.
;------------------------------------------------------------------------------
TICK        LDD  #$0480         ; register 4 = $80: the flags cleared
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
            BLE  TICK1
            LDD  #BEHIND_MAX
TICK1       STD  CREDIT
            RTS
;------------------------------------------------------------------------------
; MUSIC: the song's commands, from data port 1, until it is ahead of the clock
; -- or the vertical blank comes, which goes first. A wait takes 5 fifths a
; sample off CREDIT, in parts of up to 6000 samples (30000 fifths: they fit).
;------------------------------------------------------------------------------
MUSIC       LDA  VC_ISR         ; the vertical blank: that first
            BITA #VC_I_VSYNC
            BNE  MU_DONE
            LDD  CREDIT         ; ahead of the clock: wait for its ticks
            BMI  MU_DONE
            LDD  WAITLEFT       ; a wait still going on: the next part of it
            BEQ  MU_CMD
            CMPD #6000
            BLS  MU_PART
            LDD  #6000
MU_PART     STD  TMPW
            LDD  WAITLEFT
            SUBD TMPW
            STD  WAITLEFT
            LDD  TMPW
            ASLD
            ASLD
            ADDD TMPW
            STD  TMPW
            LDD  CREDIT
            SUBD TMPW
            STD  CREDIT
            BRA  MUSIC
MU_DONE     RTS
MU_CMD      LDA  VC_DATA1
            CMPA #$5E           ; $5E rr dd: register rr of array 0 = dd
            BEQ  MU_W0
            CMPA #$5F           ; $5F rr dd: array 1
            BEQ  MU_W1
            CMPA #$61           ; $61 nnnn: wait nnnn samples
            BEQ  MU_WAIT
            CMPA #$70
            LBLO MU_LOW
            CMPA #$7F           ; $7n: wait n+1 samples
            BLS  MU_SHORT
            CMPA #$8F           ; $8n: a YM2612 sample, then wait n
            BLS  MU_DAC
            LBRA MU_HIGH
MU_W0       LDF  VC_DATA1       ; the register
            LDA  VC_DATA1       ; its value
            CMPF #4
            BHI  MU_W0OK
            CMPF #2
            BHS  MUSIC          ; (2-4: the timers, ours)
MU_W0OK     STF  OPL3_BASE
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
            LBRA MUSIC
MU_W1       LDF  VC_DATA1
            LDA  VC_DATA1
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
            LBRA MUSIC
MU_WAIT     LDB  VC_DATA1       ; (little-endian)
            LDA  VC_DATA1
            BRA  MU_WAITD
MU_SHORT    ANDA #$0F
            INCA
            TFR  A,B
            CLRA
            BRA  MU_WAITD
MU_DAC      ANDA #$0F
            TFR  A,B
            CLRA
MU_WAITD    STD  WAITLEFT
            LDA  #1
            STA  WAITED
            LBRA MUSIC
;------------------------------------------------------------------------------
; The other commands: the waits for 1/60 and 1/50 s; the end, which goes back
; to the loop point (or, for a song that never waits, stops the music: it would
; never let the swamp move); data blocks (skipped), and other chips' writes
; (skipped: each has its operands' length).
;------------------------------------------------------------------------------
MU_LOW      CMPA #$5A           ; $5A rr dd: the YM3812 (OPL2): array 0
            BEQ  MU_W0
            CMPA #$62           ; a 60th of a second
            BNE  MU_NOT62
            LDD  #735
            BRA  MU_WAITD
MU_NOT62    CMPA #$63           ; a 50th
            BNE  MU_NOT63
            LDD  #882
            BRA  MU_WAITD
MU_NOT63    CMPA #$66           ; the end
            BEQ  MU_END
            CMPA #$67           ; $67 $66 tt ssssssss: a data block, ss bytes
            BEQ  MU_BLOCK
            LDB  #11            ; $68: a PCM RAM write, 11 bytes
            CMPA #$68
            BEQ  MU_SKIPN
            CMPA #$30           ; ($00-$2F: none)
            LBLO MUSIC
            LDB  #1             ; $30-$3F: 1 byte
            CMPA #$3F
            BLS  MU_SKIPN
            LDB  #2             ; $40-$4E: 2
            CMPA #$4E
            BLS  MU_SKIPN
            LDB  #1             ; $4F, $50: 1
            CMPA #$50
            BLS  MU_SKIPN
            LDB  #2             ; $51-$5F: 2
            CMPA #$5F
            BLS  MU_SKIPN
            LBRA MUSIC          ; ($60, $64, $65, $69-$6F: none)
MU_HIGH     CMPA #$95           ; $90-$95: DAC stream control
            BHI  MU_ABOVE
            SUBA #$90
            LDX  #STREAMLEN
            LDB  A,X
            BRA  MU_SKIPN
MU_ABOVE    CMPA #$A0           ; ($96-$9F: none)
            LBLO MUSIC
            LDB  #2             ; $A0-$BF: 2
            CMPA #$BF
            BLS  MU_SKIPN
            LDB  #3             ; $C0-$DF: 3
            CMPA #$DF
            BLS  MU_SKIPN
            LDB  #4             ; $E0-$FF: 4
MU_SKIPN    LDA  VC_DATA1       ; B bytes skipped
            DECB
            BNE  MU_SKIPN
            LBRA MUSIC
MU_END      TST  WAITED
            BEQ  MU_STOP
            CLR  WAITED
            LDX  #SONGLOOP
            JSR  PORT1AT
            LBRA MUSIC
MU_STOP     CLR  MUSICON
            JMP  OPL_QUIET
MU_BLOCK    LDA  VC_DATA1       ; ($66)
            LDA  VC_DATA1       ; (the type)
            LDA  VC_DATA1       ; the size, little-endian
            STA  SKIP+3
            LDA  VC_DATA1
            STA  SKIP+2
            LDA  VC_DATA1
            STA  SKIP+1
            LDA  VC_DATA1
            STA  SKIP
MU_BLOCK1   LDD  SKIP
            ORD  SKIP+2
            LBEQ MUSIC
            LDD  SKIP+2
            SUBD #1
            STD  SKIP+2
            LDD  SKIP
            SBCD #0
            STD  SKIP
            LDA  VC_DATA1
            BRA  MU_BLOCK1
;------------------------------------------------------------------------------
; OPL_WRITE: B to the OPL3's register A of array E (0 or 1). Keeps A, B and E.
;------------------------------------------------------------------------------
OPL_WRITE   CMPE #0
            BEQ  OPL_W0
            STA  OPL3_BASE+2
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
OPL_W0      STA  OPL3_BASE
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
;------------------------------------------------------------------------------
; OPL_QUIET: silence, as VGMPLAY leaves it: every channel's key off, every
; operator at full attenuation and every channel's outputs off, in both arrays;
; the timers stopped; then the chip back in OPL2 mode ($105), as it starts,
; with no 4-operator channels ($104).
;------------------------------------------------------------------------------
OPL_QUIET   LDE  #1
            LDD  #$0501         ; $105: OPL3 mode, for the outputs' bits in $C0-$C8
            BSR  OPL_WRITE
            CLRE
QT_BANK     LDA  #$C0
            CLRB
QT_OUT      BSR  OPL_WRITE      ; $C0-$C8: no outputs
            INCA
            CMPA #$C9
            BNE  QT_OUT
            LDA  #$B0
            CLRB
QT_KEY      BSR  OPL_WRITE      ; $B0-$B8: key off
            INCA
            CMPA #$B9
            BNE  QT_KEY
            LDA  #$40
            LDB  #$3F
QT_TL       BSR  OPL_WRITE      ; $40-$55: total level, all the way down
            INCA
            CMPA #$56
            BNE  QT_TL
            LDA  #$BD
            CLRB
            BSR  OPL_WRITE
            INCE
            CMPE #2
            BNE  QT_BANK
            CLRE
            LDD  #$0460         ; the timers stopped (and masked), their flags cleared
            BSR  OPL_WRITE
            LDD  #$0480
            BSR  OPL_WRITE
            INCE
            LDD  #$0400         ; $104
            BSR  OPL_WRITE
            LDD  #$0500         ; $105
            BRA  OPL_WRITE
;------------------------------------------------------------------------------
; Something wrong with a file: "SWAMP: name: what", and back to the shell (the
; card still showing its text screen, so the message stays).
;------------------------------------------------------------------------------
NOTFOUND    LDX  #M_NOTFOUND
            BRA  FAIL
BADFILE     LDX  #M_BADFILE
            BRA  FAIL
DISKERR     LDX  #M_DISKERR
FAIL        PSHS X
            LDX  #M_SWAMP
            BSR  PUTS
            LDX  NAMEP
            LDA  ,X
            CMPA #'/
            BNE  FAIL1
            LEAX 6,X            ; just the name
FAIL1       BSR  PUTS
            PULS X
            BSR  PUTS
            LDA  #B_EXIT
            SWI2
PUTS        LDB  #F_STDOUT      ; X: a string, 0 at its end
            LDA  #B_PUTS
            SWI2
            RTS
;------------------------------------------------------------------------------
            INCLUDE "VIDLIB.ASM"
;------------------------------------------------------------------------------
ROOMS       FCB  $00,$00,$00    ; where each layer's 48KB starts
            FCB  $00,$C0,$00
            FCB  $01,$80,$00
N_TLS       FCN  "/DEMO/SWAMP1.TLS"
N_MAP       FCN  "/DEMO/SWAMP1.MAP"
N_VGM       FCN  "/DEMO/SWAMP.VGM"
STREAMLEN   FCB  4,4,5,10,1,4   ; VGM commands $90-$95's operands
T_LOADING   FCC  "Loading the swamp..."
            FCB  CR,LF,0
M_SWAMP     FCN  "SWAMP: "
M_NOTFOUND  FCC  ": not found (in /DEMO or here)"
            FCB  CR,LF,0
M_BADFILE   FCC  ": not a TILEKIT file of the kind expected"
            FCB  CR,LF,0
M_DISKERR   FCC  ": disk error"
            FCB  CR,LF,0
;------------------------------------------------------------------------------
; Variables and buffers are just addresses after the last byte of code.
;------------------------------------------------------------------------------
LAYERN      equ  *          ; the layer being loaded, 0-2
FH          equ  LAYERN+1   ; its file's handle
NAMEP       equ  FH+1       ; 2: the file's name
SETP        equ  NAMEP+2    ; 2: the layer's settings, in LAYERS
ROOMP       equ  SETP+2     ; 2: where its room starts, in ROOMS
WANT        equ  ROOMP+2    ; 2: HEADER's byte count
WCODE       equ  WANT+2     ; the map's width and height as L_MAP has them
HCODE       equ  WCODE+1
BYTES       equ  HCODE+1    ; 2: the map's bytes
MAPADR      equ  BYTES+2    ; 3: where the map goes
LAYERS      equ  MAPADR+3   ; 48: the three layers' settings, as the card has them
MUSICON     equ  LAYERS+48  ; the song is playing
SONGTOP     equ  MUSICON+1  ; 3: where its commands start (from SONG, high first)
SONGEND     equ  SONGTOP+3  ; 3: and end
SONGLOOP    equ  SONGEND+3  ; 3: and where the end goes back to
CREDIT      equ  SONGLOOP+3 ; 2: the clock's lead on the song (fifths of a sample)
WAITLEFT    equ  CREDIT+2   ; 2: samples of a wait still to go
WAITED      equ  WAITLEFT+2 ; a wait since the song (re)started
SKIP        equ  WAITED+1   ; 4: a data block's bytes still to skip
TMPW        equ  SKIP+4     ; 2
BUF         equ  TMPW+2     ; BUFSIZE: the file, as it is read

            END  START
