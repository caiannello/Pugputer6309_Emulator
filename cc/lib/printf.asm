;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 C library
;    FILE: printf.asm -- printf(), fprintf(), sprintf(), vprintf(), vfprintf(),
;          vsprintf()
;
; Conversions: %d %i %u %x %X %o %c %s %p %%, with the flags - (left-justify)
; and 0 (pad with zeros), a width (digits or *), a precision (.digits or .*:
; at most that many characters of a %s, at least that many digits of a
; number), and l for a long (h is accepted). + # and space are accepted and
; ignored. No floating point. %p is a pointer as 4 hex digits.
; Each returns how many characters it wrote (sprintf's NUL not counted).
; A va_list is a pointer to the next argument (each a whole number of words).
;------------------------------------------------------------------------------
    INCLUDE defines.d
    INCLUDE libc.d
NBUFSZ      equ  40
            EXPORT _printf,_fprintf,_sprintf,_vprintf,_vfprintf,_vsprintf
            IMPORT __iob,__putc
            SECTION code
;------------------------------------------------------------------------------
; int printf(const char *fmt, ...), int vprintf(const char *fmt, va_list ap)
_printf     PSHS Y,U                   ; (6 fmt, 8 the arguments)
            LEAY 8,S
            BRA  PR_OUT
_vprintf    PSHS Y,U                   ; (6 fmt, 8 ap)
            LDY  8,S
PR_OUT      LDD  #__iob+FL_SIZE
            STD  outf
            CLRD
            STD  outb
            LDX  6,S
            JSR  DOPRNT
            PULS Y,U,PC
; int fprintf(FILE *f, const char *fmt, ...), int vfprintf(FILE *f, const char
; *fmt, va_list ap)
_fprintf    PSHS Y,U                   ; (6 f, 8 fmt, 10 the arguments)
            LEAY 10,S
            BRA  FP_OUT
_vfprintf   PSHS Y,U                   ; (6 f, 8 fmt, 10 ap)
            LDY  10,S
FP_OUT      LDD  6,S
            STD  outf
            CLRD
            STD  outb
            LDX  8,S
            JSR  DOPRNT
            PULS Y,U,PC
; int sprintf(char *buf, const char *fmt, ...), int vsprintf(char *buf, const
; char *fmt, va_list ap)
_sprintf    PSHS Y,U                   ; (6 buf, 8 fmt, 10 the arguments)
            LEAY 10,S
            BRA  SP_OUT
_vsprintf   PSHS Y,U                   ; (6 buf, 8 fmt, 10 ap)
            LDY  10,S
SP_OUT      LDD  6,S
            STD  outb
            LDX  8,S
            JSR  DOPRNT
            LDX  outb                  ; (the NUL, not counted)
            CLR  ,X
            PULS Y,U,PC
;------------------------------------------------------------------------------
; X = the format, Y = the arguments: written (to outb if it isn't NULL, else
; to the FILE outf) -> D = how many characters.
DOPRNT      CLRD
            STD  count
DP_LOOP     LDB  ,X+
            BEQ  DP_END
            CMPB #'%'
            BEQ  DP_CONV
DP_LIT      JSR  EMIT
            BRA  DP_LOOP
DP_END      LDD  count
            RTS
DP_CONV     CLR  fleft                 ; %[flags][width][.prec][l]type
            CLR  fzero
            CLR  flong
            CLRD
            STD  width
            LDD  #-1
            STD  prec
DP_FLAGS    LDB  ,X+
            CMPB #'-'
            BNE  DP_FZ
            INC  fleft
            BRA  DP_FLAGS
DP_FZ       CMPB #'0'
            BNE  DP_FOTHER
            INC  fzero
            BRA  DP_FLAGS
DP_FOTHER   CMPB #'+'
            BEQ  DP_FLAGS
            CMPB #' '
            BEQ  DP_FLAGS
            CMPB #'#'
            BEQ  DP_FLAGS
            CMPB #'*'                  ; the width
            BNE  DP_WDIG
            LDD  ,Y++
            BPL  DP_WSET
            INC  fleft                 ; (a negative one: left-justified)
            NEGD
DP_WSET     STD  width
            LDB  ,X+
            BRA  DP_PREC
DP_WDIG     LDU  #width
            JSR  DIGITS
DP_PREC     CMPB #'.'                  ; the precision
            BNE  DP_LEN
            CLRD
            STD  prec
            LDB  ,X+
            CMPB #'*'
            BNE  DP_PDIG
            LDD  ,Y++
            STD  prec
            LDB  ,X+
            BRA  DP_LEN
DP_PDIG     LDU  #prec
            JSR  DIGITS
DP_LEN      CMPB #'h'
            BNE  DP_LONG
            LDB  ,X+
DP_LONG     CMPB #'l'
            BNE  DP_TYPE
            INC  flong
            LDB  ,X+
DP_TYPE     CMPB #'d'
            LBEQ DP_SIGNED
            CMPB #'i'
            LBEQ DP_SIGNED
            CMPB #'u'
            BNE  DP_X
            LDA  #10
            BRA  DP_UNSIGNED
DP_X        CMPB #'x'
            BNE  DP_BIGX
            LDA  #16
            BRA  DP_UNSIGNED
DP_BIGX     CMPB #'X'
            BNE  DP_O
            LDA  #16+$80               ; (upper-case digits)
            BRA  DP_UNSIGNED
DP_O        CMPB #'o'
            BNE  DP_P
            LDA  #8
            BRA  DP_UNSIGNED
DP_P        CMPB #'p'
            BNE  DP_C
            CLR  flong
            LDD  #4
            STD  width
            STA  fzero                 ; (A is 0: no; set it to 1)
            INC  fzero
            LDA  #16+$80
            BRA  DP_UNSIGNED
DP_C        CMPB #'c'
            BNE  DP_S
            LDD  ,Y++                  ; a character: a string of 1
            STB  nbuf
            LDU  #nbuf
            LDD  #1
            LBRA DP_FIELD
DP_S        CMPB #'s'
            BNE  DP_PCT
            LDU  ,Y++
            BNE  DP_SLEN
            LDU  #m_null
DP_SLEN     PSHS X                     ; its length, at most the precision
            TFR  U,X
            LDD  #0
DP_SL       TST  ,X+
            BEQ  DP_SLD
            ADDD #1
            BRA  DP_SL
DP_SLD      PULS X
            TST  prec
            LBMI DP_FIELD
            CMPD prec
            LBLS DP_FIELD
            LDD  prec
            LBRA DP_FIELD
DP_PCT      TSTB                       ; %% (or anything else: itself)
            BNE  DP_LIT2
            LEAX -1,X                  ; (% at the end: stop there)
            LBRA DP_LOOP
DP_LIT2     LBRA DP_LIT
; A number: its value (32 bits) in num, its sign in fneg.
DP_UNSIGNED STA  base
            CLR  fneg
            TST  flong
            BNE  DP_U32
            LDD  ,Y++
            STD  num+2
            CLRD
            STD  num
            BRA  DP_NUM
DP_U32      LDD  ,Y++
            STD  num
            LDD  ,Y++
            STD  num+2
            BRA  DP_NUM
DP_SIGNED   LDA  #10
            STA  base
            CLR  fneg
            TST  flong
            BNE  DP_S32
            LDD  ,Y++                  ; (an int, sign-extended)
            STD  num+2
            CLRD
            TST  num+2
            BPL  DP_SHI
            DECD
DP_SHI      STD  num
            BRA  DP_SNEG
DP_S32      LDD  ,Y++
            STD  num
            LDD  ,Y++
            STD  num+2
DP_SNEG     TST  num                   ; negative: its magnitude, and a -
            BPL  DP_NUM
            INC  fneg
            CLRD
            SUBD num+2
            STD  num+2
            LDD  #0
            SBCD num
            STD  num
DP_NUM      LDU  #nbuf+NBUFSZ          ; its digits, last first, backwards
DP_DIG      JSR  UDIV8
            CMPA #10
            BLO  DP_DEC
            ADDA #'a'-'0'-10
            TST  base
            BPL  DP_DEC
            SUBA #'a'-'A'
DP_DEC      ADDA #'0'
            STA  ,-U
            LDD  num
            BNE  DP_DIG
            LDD  num+2
            BNE  DP_DIG
DP_PDIGS    TFR  U,D                   ; at least the precision's digits
            PSHS D
            LDD  #nbuf+NBUFSZ
            SUBD ,S++
            TST  prec
            BMI  DP_SIGN
            CMPD prec
            BHS  DP_SIGN
            CMPU #nbuf+1
            BLS  DP_SIGN
            LDA  #'0'
            STA  ,-U
            BRA  DP_PDIGS
DP_SIGN     TST  fneg
            BEQ  DP_FIELD
            TST  fzero                 ; zeros go between the - and the digits
            BEQ  DP_MINUS
            PSHS D
            LDB  #'-'
            JSR  EMIT
            LDD  width
            BEQ  DP_W0
            SUBD #1
DP_W0       STD  width
            PULS D
            BRA  DP_FIELD
DP_MINUS    PSHS B
            LDB  #'-'
            STB  ,-U
            PULS B
            ADDD #1
; U = the characters, D = how many: written, padded to the width.
DP_FIELD    STD  flen
            LDD  width
            SUBD flen
            BGT  DP_PAD
            CLRD
DP_PAD      STD  fpad
            TST  fleft
            BNE  DP_CHARS
            LDB  #' '
            TST  fzero
            BEQ  DP_LPAD
            LDB  #'0'
DP_LPAD     BSR  PADS
DP_CHARS    LDD  flen
            BEQ  DP_RPAD
DP_CH       PSHS D
            LDB  ,U+
            BSR  EMIT
            PULS D
            SUBD #1
            BNE  DP_CH
DP_RPAD     TST  fleft
            LBEQ DP_LOOP
            LDB  #' '
            BSR  PADS
            LBRA DP_LOOP
; B = a character: fpad of them.
PADS        PSHS B
PD_LOOP     LDD  fpad
            BEQ  PD_RET
            SUBD #1
            STD  fpad
            LDB  ,S
            BSR  EMIT
            BRA  PD_LOOP
PD_RET      PULS B,PC
; B = a character: written. Keeps X, Y, U.
EMIT        PSHS D,X
            LDX  outb
            BEQ  EM_FILE
            STB  ,X+
            STX  outb
            BRA  EM_COUNT
EM_FILE     LDX  outf
            JSR  __putc
EM_COUNT    LDX  count
            LEAX 1,X
            STX  count
            PULS D,X,PC
; B = the first character, X past it, U = a word: decimal digits -> U's value;
; B = the character after them, X past that.
DIGITS      SUBB #'0'
            CMPB #9
            BHI  DG_END
            PSHS B
            LDD  ,U                    ; *10, + the digit
            LSLD
            PSHS D
            LSLD
            LSLD
            ADDD ,S++
            ADDB ,S+
            ADCA #0
            STD  ,U
            LDB  ,X+
            BRA  DIGITS
DG_END      ADDB #'0'
            RTS
; num (32 bits) / base (its low 7 bits) -> num, and A = the remainder.
UDIV8       LDB  base
            ANDB #$7F
            STB  divisor
            CLRA
            LDB  #32
            STB  bits
UD_LOOP     ASL  num+3
            ROL  num+2
            ROL  num+1
            ROL  num
            ROLA
            CMPA divisor
            BLO  UD_NEXT
            SUBA divisor
            INC  num+3
UD_NEXT     DEC  bits
            BNE  UD_LOOP
            RTS
m_null      FCN  "(null)"
            ENDSECT
;------------------------------------------------------------------------------
            SECTION bss
outf        RMB  2                     ; where it goes: a FILE,
outb        RMB  2                     ; ... or (if not NULL) a buffer
count       RMB  2
fleft       RMB  1
fzero       RMB  1
flong       RMB  1
fneg        RMB  1
base        RMB  1                     ; (bit 7: upper-case hex)
divisor     RMB  1
bits        RMB  1
width       RMB  2
prec        RMB  2                     ; (-1: none)
flen        RMB  2
fpad        RMB  2
num         RMB  4
nbuf        RMB  NBUFSZ
            ENDSECT
;------------------------------------------------------------------------------
; End of printf.asm
;------------------------------------------------------------------------------
