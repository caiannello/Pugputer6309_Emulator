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
; And music, if there is a SWAMP.SNG beside them: a SONGKIT song (SONGKIT
; SWAMP.SNG edits it). It goes into the CPU card's RAM as it loads, the whole of
; it, in 16KB pages of its own (B_PAGE_ALLOC'd, above the program's 64KB), and
; SONGKIT's player -- sk_play.asm, the one a game INCLUDEs (from /ASM/GAMEKIT; a
; copy is beside this file) -- plays it from there, seen through bank 2
; ($8000-$BFFF), over and over (it loops), so the disk isn't read while the
; swamp scrolls. Its ticks come from the OPL3's Timer 2: the loop below looks for
; them (SK_POLL) and for the card's vertical blank. Without the file, the swamp
; is silent. (The demo disk's is Old Joe Clark, a traditional tune, as R. G.
; Allen sequenced it, with The Fat Man's OPL3 instruments.)
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
B_BANK_GET  equ  $2D        ; the RAM banking calls (see /ASM/DEFINES.D)
B_BANK_SET  equ  $2E
B_PAGE_ALLOC equ $2F
B_PAGE_FREE equ  $30
ERR_EOF     equ  $09
CR          equ  $0D
LF          equ  $0A
ROOM        equ  $C000      ; each layer's video memory: 48KB
BUFSIZE     equ  512        ; read at a time: a sector
WBANK       equ  2          ; the song is seen through bank 2: $8000-$BFFF (the
WINDOW      equ  $8000      ; program, its variables and BUF are all below it)
MAXPG       equ  32         ; its pages at most (512KB, as SONGKIT's)
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
            CLR  NPG            ; no song pages yet
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
            LDX  #SPAGES        ; the song from its start (not a song the player
            LDA  NPG            ; takes: the swamp silent)
            LDB  #WBANK
            JSR  SK_PSTART
            BCC  FRAME
            JSR  SONGFREE
;------------------------------------------------------------------------------
; Round and round: the music, a tick whenever Timer 2 says, until the
; vertical blank; then the frame. The sky stays, the bayou moves a pixel every 2 frames, the ground
; 2 pixels a frame. (The maps wrap, and the frame count wraps at a multiple of
; their width, so the scrolling never jumps.)
;------------------------------------------------------------------------------
FRAME       TST  MUSICON
            BEQ  FRAME1
            JSR  SK_POLL
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
            TST  MUSICON        ; a key: the chip quiet, the song's pages given
            BEQ  FRAME2         ; back, and back to the shell
            JSR  SK_OFF
FRAME2      JSR  SONGFREE
            JMP  QUIT
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
STREAM1
CLOSE       LDB  FH             ; CLOSE: the file closed
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
; LOADSONG: SWAMP.SNG, if there is one, into RAM pages of its own (SPAGES, NPG
; of them; as many as it takes, up to MAXPG), MUSICON set if so. SK_PSTART says
; whether it is a song.
;------------------------------------------------------------------------------
LOADSONG    CLR  MUSICON
            LDX  #N_SONG
            JSR  TRYOPEN
            BCS  LS_RET
            LDB  #WBANK         ; the window's own page, for after
            LDA  #B_BANK_GET
            SWI2
            STA  WHOME
LS_PAGE     LDA  NPG
            CMPA #MAXPG
            BHS  LS_DONE        ; (more than the pages hold: the rest left)
            LDA  #B_PAGE_ALLOC  ; a page, in the window
            SWI2
            BCS  LS_DONE        ; (no more of them: what there is)
            LDB  NPG
            LDX  #SPAGES
            STA  B,X
            INC  NPG
            TFR  A,E
            LDB  #WBANK
            LDA  #B_BANK_SET
            SWI2
            LDB  FH             ; the next 16KB of the file into it
            LDX  #WINDOW
            LDY  #$4000
            LDA  #B_FREAD
            SWI2
            BCC  LS_GOT
            CMPA #ERR_EOF
            LBNE DISKERR
            LDX  #0
LS_GOT      CMPX #$4000         ; (the page filled: more, perhaps)
            BEQ  LS_PAGE
LS_DONE     JSR  CLOSE
            TST  NPG
            BEQ  LS_RET
            LDA  #1
            STA  MUSICON
LS_RET      RTS
; SONGFREE: the window back at its own page, and the song's pages given back
; (DOS's B_EXIT does neither). Nothing if it had none.
SONGFREE    TST  NPG
            BEQ  SF_RET
            LDB  #WBANK
            LDE  WHOME
            LDA  #B_BANK_SET
            SWI2
SF_FREE     DEC  NPG
            LDB  NPG
            LDX  #SPAGES
            LDB  B,X
            LDA  #B_PAGE_FREE
            SWI2
            TST  NPG
            BNE  SF_FREE
SF_RET      CLR  MUSICON
            RTS
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
            JSR  SONGFREE       ; (a disk error may come with the song half loaded)
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
N_SONG      FCN  "/DEMO/SWAMP.SNG"
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
; SONGKIT's player (its own variables, RMBs, at its end).
;------------------------------------------------------------------------------
            INCLUDE "sk_play.asm"
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
NPG         equ  MUSICON+1  ; the song's pages taken
SPAGES      equ  NPG+1      ; MAXPG: which they are, in order
WHOME       equ  SPAGES+MAXPG ; the window's own page
BUF         equ  WHOME+1    ; BUFSIZE: the file, as it is read

            END  START
