;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 game kit
;    FILE: songplay.asm
;
; SONGPLAY.COM: plays a SONGKIT song on the OPL3 music chip:
;
;   SONGPLAY file           (".SNG" is added to a name without an extension)
;
; The song is read into RAM pages of its own (up to 512KB), seen through bank
; 2, and played there by the player games use (sk_play.asm), timed by the
; OPL3's Timer 2. A key stops it; at its end (unless it loops) the last notes
; are given a second to fade.
;
;   ASM -o SONGPLAY.COM songplay.asm   makes SONGPLAY.COM
;------------------------------------------------------------------------------
            INCLUDE "defines.d"

SP_BASE     equ  $4000
SP_STACK    equ  $7F00      ; (in bank 1, with the program: bank 2 is the song's)
WBANK       equ  2          ; the song's window: $8000-$BFFF
WINDOW      equ  $8000
MAXPG       equ  32         ; its pages at most: 512KB
NAMEMAX     equ  79
;------------------------------------------------------------------------------
            ORG  SP_BASE-EXE_HDRSIZE
            FDB  EXE_MAGIC      ; the program header
            FDB  SP_BASE        ; load address
            FDB  START          ; entry
            FDB  0              ; flags
;------------------------------------------------------------------------------
START       LDS  #SP_STACK
            CLR  NPG
            JSR  SK_OFF
            LDB  #WBANK         ; bank 2's own page, for after
            LDA  #B_BANK_GET
            SWI2
            STA  WHOME
            LDA  #B_ARGS        ; the file name: the tail's first word
            SWI2
SP_SKIP     LDA  ,X
            CMPA #' '
            BNE  SP_NAME
            LEAX 1,X
            BRA  SP_SKIP
SP_NAME     TSTA
            LBEQ USAGE
            LDY  #NAMEBUF
            LDB  #NAMEMAX-4     ; (room for ".SNG")
            CLR  DOT
SP_NCOPY    LDA  ,X+
            BEQ  SP_NEND
            CMPA #' '
            BEQ  SP_NEND
            CMPA #'a'           ; (in upper case, as DOS has it)
            BLO  SP_NCHAR
            CMPA #'z'
            BHI  SP_NCHAR
            SUBA #'a'-'A'
SP_NCHAR    STA  ,Y+
            CMPA #'.'           ; an extension (a dot after the path's last "/")
            BNE  SP_NSLASH
            STA  DOT
SP_NSLASH   CMPA #'/'
            BNE  SP_NNEXT
            CLR  DOT
SP_NNEXT    DECB
            BNE  SP_NCOPY
SP_NEND     CLR  ,Y
            TST  DOT
            BNE  SP_OPEN
            LDX  #EXT_SNG       ; none: ".SNG"
SP_EXT      LDA  ,X+
            STA  ,Y+
            BNE  SP_EXT
SP_OPEN     LDX  #NAMEBUF
            LDE  #FOPEN_READ
            LDA  #B_FOPEN_NAME
            SWI2
            LBCS FAIL
            STA  FH
;------------------------------------------------------------------------------
; The file into pages, 16KB at a time, straight into the window.
;------------------------------------------------------------------------------
LOAD        LDA  NPG
            CMPA #MAXPG
            LBHS TOOBIG
            LDA  #B_PAGE_ALLOC
            SWI2
            LBCS NOROOM
            LDX  #PAGES
            LDB  NPG
            STA  B,X
            INC  NPG
            TFR  A,E
            LDB  #WBANK
            LDA  #B_BANK_SET
            SWI2
            LDB  FH
            LDX  #WINDOW
            LDY  #$4000
            LDA  #B_FREAD
            SWI2
            BCC  LD_GOT
            CMPA #ERR_EOF
            LBNE FAIL
            LDX  #0
LD_GOT      CMPX #$4000         ; a whole page: there may be more
            BEQ  LOAD
            STX  LAST           ; (how much of the last page there is)
            LDB  FH
            LDA  #B_FCLOSE_NAME
            SWI2
;------------------------------------------------------------------------------
; Its first page: is it a song? Its title, and play it.
;------------------------------------------------------------------------------
            LDB  #WBANK
            LDE  PAGES
            LDA  #B_BANK_SET
            SWI2
            LDA  NPG
            CMPA #1
            BNE  SP_BIG
            LDD  LAST
            CMPD #96            ; (a header and one order, pattern and row)
            LBLO NOTSONG
SP_BIG      LDD  WINDOW
            CMPD #$5053         ; "PSG1"
            LBNE NOTSONG
            LDD  WINDOW+2
            CMPD #$4731
            LBNE NOTSONG
            LDX  #MSG_PLAY      ; "Playing NAME: title (any key stops it)"
            JSR  PUTS
            LDX  #NAMEBUF
            JSR  PUTS
            LDX  #WINDOW+16     ; the title: 32 bytes, 0s after it
            LDY  #TITLE
            LDB  #32
SP_T1       LDA  ,X+
            BEQ  SP_T2
            STA  ,Y+
            DECB
            BNE  SP_T1
SP_T2       CLR  ,Y
            TST  TITLE
            BEQ  SP_T3
            LDX  #MSG_COLON
            JSR  PUTS
            LDX  #TITLE
            JSR  PUTS
SP_T3       LDX  #MSG_PLAY2
            JSR  PUTS
            LDX  #PAGES
            LDA  NPG
            LDB  #WBANK
            JSR  SK_PSTART
            LBCS NOTSONG
            LDD  SK_TICKS
            STD  LASTT
;------------------------------------------------------------------------------
; Playing: a tick whenever Timer 2 says, and once a tick, a look for a key.
;------------------------------------------------------------------------------
PLAY        JSR  SK_POLL
            LDD  SK_TICKS
            CMPD LASTT
            BEQ  PLAY
            STD  LASTT
            JSR  KEY
            BCC  DONE
            TST  SK_PLAYING
            BNE  PLAY
            LDB  SK_RATE        ; over: a second more, for the last notes
            CLRA
            ADDD SK_TICKS
            STD  ENDT
FADE        JSR  SK_POLL
            LDD  SK_TICKS
            CMPD LASTT
            BEQ  FADE
            STD  LASTT
            JSR  KEY
            BCC  DONE
            LDD  SK_TICKS
            CMPD ENDT
            BNE  FADE
DONE        JSR  SK_OFF
            JSR  FREE
EXIT        LDA  #B_EXIT        ; (DOS closes the file)
            SWI2
; KEY: carry clear if a key was typed.
KEY         LDB  #F_STDIN
            LDA  #B_GETC
            SWI2
            RTS
; FREE: bank 2 back to its own page, and the song's pages given back.
FREE        LDA  NPG
            BEQ  FR_RET
            LDB  #WBANK
            LDE  WHOME
            LDA  #B_BANK_SET
            SWI2
FR_NEXT     DEC  NPG
            LDX  #PAGES
            LDB  NPG
            LDB  B,X
            LDA  #B_PAGE_FREE
            SWI2
            TST  NPG
            BNE  FR_NEXT
FR_RET      RTS
;------------------------------------------------------------------------------
USAGE       LDX  #MSG_USAGE
            BRA  SAY
TOOBIG      LDX  #MSG_TOOBIG
            BRA  SAYNAME
NOROOM      LDX  #MSG_NOROOM
            BRA  SAYNAME
NOTSONG     LDX  #MSG_NOTSONG
            BRA  SAYNAME
FAIL        LDX  #ERRMSGS       ; A = the error: its message, if it has one
FL_FIND     LDB  ,X+
            BEQ  FL_NUM
            CMPA -1,X
            BEQ  SAYNAME
FL_SKIP     TST  ,X+
            BNE  FL_SKIP
            BRA  FL_FIND
FL_NUM      LDX  #MSG_ERR       ; "Disk error" will do for the rest
SAYNAME     PSHS X              ; "name: message"
            LDX  #NAMEBUF
            BSR  PUTS
            LDX  #MSG_COLON
            BSR  PUTS
            PULS X
SAY         BSR  PUTS
            JSR  SK_OFF
            JSR  FREE
            BRA  EXIT
PUTS        LDB  #F_STDOUT      ; X = a NUL-terminated string
            LDA  #B_PUTS
            SWI2
            RTS
;------------------------------------------------------------------------------
EXT_SNG     FCC  ".SNG"
            FCB  0
MSG_PLAY    FCC  "Playing "
            FCB  0
MSG_PLAY2   FCC  " (any key stops it)"
            FCB  CR,LF,0
MSG_USAGE   FCC  "Usage: SONGPLAY file[.SNG]"
            FCB  CR,LF,0
MSG_COLON   FCC  ": "
            FCB  0
MSG_NOTSONG FCC  "Not a SONGKIT song"
            FCB  CR,LF,0
MSG_TOOBIG  FCC  "Too big (512KB at most)"
            FCB  CR,LF,0
MSG_NOROOM  FCC  "Not enough memory"
            FCB  CR,LF,0
ERRMSGS     FCB  ERR_NOTFOUND   ; (code, message; 0 ends the list)
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
            INCLUDE "sk_play.asm"
;------------------------------------------------------------------------------
NAMEBUF     RMB  NAMEMAX+1
TITLE       RMB  33
PAGES       RMB  MAXPG
NPG         RMB  1
WHOME       RMB  1
FH          RMB  1
DOT         RMB  1
LAST        RMB  2
LASTT       RMB  2
ENDT        RMB  2

            END  START
