;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 utilities
;    FILE: hexdump.asm
;
; HEXDUMP.COM: shows a file as hex and ASCII, 16 bytes a line:
;
;   HEXDUMP file
;
;   000000  48 65 6C 6C 6F 0D 0A 00  00 00 00 00 00 00 00 00  |Hello...........|
;
; The offset is 24 bits (6 hex digits); bytes outside $20-$7E show as dots in the
; ASCII column. A short last line leaves its missing bytes blank. Ctrl-C stops it.
;------------------------------------------------------------------------------
    INCLUDE defines.d
;------------------------------------------------------------------------------
HD_BASE     equ  $4000
NAMEMAX     equ  79
;------------------------------------------------------------------------------
    ORG  HD_BASE-EXE_HDRSIZE
    FDB  EXE_MAGIC             ; the program header
    FDB  HD_BASE               ; load address
    FDB  START                 ; entry
    FDB  0                     ; flags
;------------------------------------------------------------------------------
START       LDS  #$7F00
            LDA  #B_ARGS               ; the file name: the tail's first word
            SWI2
HD_SKIP     LDA  ,X
            CMPA #' '
            BNE  HD_NAME
            LEAX 1,X
            BRA  HD_SKIP
HD_NAME     TSTA
            LBEQ USAGE
            LDY  #NAMEBUF
            LDB  #NAMEMAX
HD_NCOPY    LDA  ,X+
            BEQ  HD_NEND
            CMPA #' '
            BEQ  HD_NEND
            STA  ,Y+
            DECB
            BNE  HD_NCOPY
HD_NEND     CLR  ,Y
            LDX  #NAMEBUF
            LDE  #FOPEN_READ
            LDA  #B_FOPEN_NAME
            SWI2
            BCS  FAIL
            STA  FH
            CLR  OFS
            CLR  OFS+1
            CLR  OFS+2
;------------------------------------------------------------------------------
LINE_LOOP   LDB  #F_STDIN              ; Ctrl-C stops it
            LDA  #B_GETC
            SWI2
            BCS  HD_READ
            CMPA #3
            BEQ  CANCEL
HD_READ     LDB  FH
            LDX  #BUF
            LDY  #16
            LDA  #B_FREAD
            SWI2
            BCC  HD_GOT
            CMPA #ERR_EOF
            BEQ  DONE
            BRA  FAIL
HD_GOT      CMPX #0
            BEQ  DONE
            TFR  X,D
            STB  COUNT
            JSR  FORMAT
            LDX  #LINE
            LDB  #F_STDOUT
            LDA  #B_PUTS
            SWI2
            LDD  OFS+1                 ; the offset moves on 16
            ADDD #16
            STD  OFS+1
            BCC  LINE_LOOP
            INC  OFS
            BRA  LINE_LOOP
;------------------------------------------------------------------------------
DONE        LDB  FH
            LDA  #B_FCLOSE_NAME
            SWI2
EXIT        LDA  #B_EXIT
            SWI2
CANCEL      LDX  #MSG_CANCEL
            BRA  SAY
USAGE       LDX  #MSG_USAGE
SAY         LDB  #F_STDOUT
            LDA  #B_PUTS
            SWI2
            BRA  EXIT
FAIL        LDX  #ERRMSGS              ; A = the error: its message, if it has one
FL_FIND     LDB  ,X+
            BEQ  FL_NUM
            CMPA -1,X
            BEQ  FL_SAY
FL_SKIP     TST  ,X+
            BNE  FL_SKIP
            BRA  FL_FIND
FL_SAY      PSHS X                     ; "name: message"
            LDX  #NAMEBUF
            BSR  PUTS
            LDX  #MSG_COLON
            BSR  PUTS
            PULS X
            BRA  SAY
FL_NUM      LDY  #LINE                 ; "Error $nn"
            JSR  HEXBYTE
            CLR  ,Y
            LDX  #MSG_ERR
            BSR  PUTS
            LDX  #LINE
            BSR  PUTS
            LDX  #MSG_CRLF
            BRA  SAY
PUTS        LDB  #F_STDOUT             ; X = a NUL-terminated string
            LDA  #B_PUTS
            SWI2
            RTS
;------------------------------------------------------------------------------
; Builds the line for BUF's COUNT bytes at offset OFS in LINE (NUL-terminated).
FORMAT      LDY  #LINE
            LDA  OFS
            BSR  HEXBYTE
            LDA  OFS+1
            BSR  HEXBYTE
            LDA  OFS+2
            BSR  HEXBYTE
            LDA  #' '
            STA  ,Y+
            LDX  #BUF
            CLRB
FM_HEX      LDA  #' '
            STA  ,Y+
            CMPB #8                    ; a second space between the two halves
            BNE  FM_BYTE
            STA  ,Y+
FM_BYTE     CMPB COUNT
            BHS  FM_BLANK
            LDA  ,X+
            BSR  HEXBYTE
            BRA  FM_NEXT
FM_BLANK    LDA  #' '                  ; past the end: blank
            STA  ,Y+
            STA  ,Y+
FM_NEXT     INCB
            CMPB #16
            BLO  FM_HEX
            LDD  #$2020                ; "  |"
            STD  ,Y++
            LDA  #'|'
            STA  ,Y+
            LDX  #BUF
            LDB  COUNT
FM_ASCII    LDA  ,X+
            CMPA #' '
            BLO  FM_DOT
            CMPA #'~'
            BLS  FM_CHAR
FM_DOT      LDA  #'.'
FM_CHAR     STA  ,Y+
            DECB
            BNE  FM_ASCII
            LDA  #'|'
            STA  ,Y+
            LDD  #CR*256+LF
            STD  ,Y++
            CLR  ,Y
            RTS
;------------------------------------------------------------------------------
; A as two hex digits at Y (Y moves on); keeps B and X.
HEXBYTE     PSHS A
            LSRA
            LSRA
            LSRA
            LSRA
            BSR  HEXDIG
            PULS A
            ANDA #$0F
HEXDIG      CMPA #10
            BLO  HX_NUM
            ADDA #7
HX_NUM      ADDA #'0'
            STA  ,Y+
            RTS
;------------------------------------------------------------------------------
MSG_USAGE   FCC  "Usage: HEXDUMP file"
MSG_CRLF    FCB  CR,LF,0
MSG_CANCEL  FCC  "^C"
            FCB  CR,LF,0
MSG_COLON   FCC  ": "
            FCB  0
MSG_ERR     FCC  "Error $"
            FCB  0
ERRMSGS     FCB  ERR_NOTFOUND          ; (code, message; 0 ends the list)
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
            FCB  ERR_ISOPEN
            FCC  "File is in use"
            FCB  CR,LF,0
            FCB  ERR_IOERR
            FCC  "Disk error"
            FCB  CR,LF,0
            FCB  0
;------------------------------------------------------------------------------
; Variables and buffers are just addresses after the last byte of code.
;------------------------------------------------------------------------------
NAMEBUF     equ  *                     ; 80
BUF         equ  NAMEBUF+NAMEMAX+1     ; 16
LINE        equ  BUF+16                ; 80: the line being built
FH          equ  LINE+80
COUNT       equ  FH+1                  ; bytes in BUF
OFS         equ  COUNT+1               ; 3: the offset of BUF's first byte
HD_END      equ  OFS+3
;------------------------------------------------------------------------------
; End of hexdump.asm
;------------------------------------------------------------------------------
