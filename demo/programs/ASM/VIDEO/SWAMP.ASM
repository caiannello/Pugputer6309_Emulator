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
;------------------------------------------------------------------------------
; All loaded: the layers on, together, at a vertical blank.
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
;------------------------------------------------------------------------------
; Each frame: the sky stays, the bayou moves a pixel every 2 frames, the
; ground 2 pixels a frame. (The maps wrap, and the frame count wraps at a
; multiple of their width, so the scrolling never jumps.)
;------------------------------------------------------------------------------
FRAME       JSR  VBLANK
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
            BCS  FRAME
            JMP  QUIT
;------------------------------------------------------------------------------
; OPEN: the file named at X ("/DEMO/name"), or else "name" here; FH its handle.
;------------------------------------------------------------------------------
OPEN        STX  NAMEP
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
            BCS  NOTFOUND
OPENED      STA  FH
            RTS
; READ: up to Y bytes of the file into BUF; X how many there were (0: its end).
READ        LDB  FH
            LDX  #BUF
            LDA  #B_FREAD
            SWI2
            BCC  READ1
            CMPA #ERR_EOF
            BNE  DISKERR
            LDX  #0
READ1       RTS
; HEADER: D bytes of the file into BUF -- all of them, or it isn't the file
; expected.
HEADER      STD  WANT
            TFR  D,Y
            BSR  READ
            CMPX WANT
            BNE  BADFILE
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
            BRA  BADFILE
SIZE2       TFR  E,B
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
BUF         equ  LAYERS+48  ; BUFSIZE: the file, as it is read

            END  START
