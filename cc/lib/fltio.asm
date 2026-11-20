;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 C library
;    FILE: fltio.asm -- printf's and scanf's floats: %e %f %g (and E F G)
;
; Linked only when the program needs it: CC1 IMPORTs __fltused (this module's)
; when a float, or a pointer to one, is passed to "..." (or to a function with
; no prototype). Its part of CRT0's start (init_flt) points __pfhook at PFLOAT
; and __sfhook at strtod.asm's __sfloat; printf and scanf call through them.
;
; PFLOAT: Y -> the double, B = the conversion, X = the precision (-1: none,
; so 6; at most 20), A = 1 for the # flag, U = a buffer (64 bytes) -> U = the
; characters (with room for a sign before them), D = how many, carry set if the
; number is negative (printf puts the sign, and the padding). Keeps Y.
;   %f  [d...]d.ddd (precision: the digits after the point)
;   %e  d.ddde+XX
;   %g  %e if the exponent is below -4 or not below the precision (the
;       significant digits: 0 is 1), %f otherwise; trailing zeros (and the
;       point) go, unless #.
;   inf and nan (INF, NAN for E F G).
; A float has about 7 significant digits; up to 9 are worked out exactly from
; its value (__fxint), and any after those are zeros.
;------------------------------------------------------------------------------
    INCLUDE defines.d
    INCLUDE libc.d
MAXPREC     equ  20
NSIG        equ  9                 ; significant digits worked out
            EXPORT __fltused
            IMPORT __pfhook,__sfhook,__sfloat,__fxint
;------------------------------------------------------------------------------
            SECTION init_flt
            LDX  #PFLOAT
            STX  __pfhook
            LDX  #__sfloat
            STX  __sfhook
            ENDSECT
;------------------------------------------------------------------------------
            SECTION code
__fltused
PFLOAT      PSHS Y
            STA  falt
            STX  fprec
            CLR  fstrip
            CLR  fupper
            BITB #$20
            BNE  PF_LOWER
            INC  fupper
PF_LOWER    ORB  #$20
            STB  fconv
            LEAU 1,U                   ; (room for the sign)
            STU  fstart
            CLR  fpoint
            CLR  fpoint+1
            LDQ  ,Y
            CLR  fneg
            TSTA
            BPL  PF_POS
            INC  fneg
            ANDA #$7F
PF_POS      STQ  fq
            CMPD #$7F80                ; infinite, or not a number
            BLO  PF_NUM
            BHI  PF_NAN
            TSTW
            BNE  PF_NAN
            LDX  #s_inf
            BRA  PF_TEXT
PF_NAN      LDX  #s_nan
PF_TEXT     LDB  #3
PF_TL       LDA  ,X+
            JSR  PUTC
            DECB
            BNE  PF_TL
            BRA  PF_DONE
PF_NUM      LDD  fprec                 ; the precision: 6, at most MAXPREC
            BPL  PF_PMAX
            LDD  #6
PF_PMAX     CMPD #MAXPREC
            BLS  PF_PSET
            LDD  #MAXPREC
PF_PSET     STD  fprec
            LDA  fconv
            CMPA #'f'
            BEQ  PF_F
            CMPA #'e'
            BEQ  PF_E
            LDD  fprec                 ; %g: P significant digits (0 is 1)
            BNE  PG_P
            INCB
PG_P        STD  fprec
            TST  falt
            BNE  PG_KEEP
            INC  fstrip
PG_KEEP     CLRD                       ; the exponent it has, rounded to P
            STD  fexp
            LDQ  fq
            TSTD
            BNE  PG_DIG
            TSTW
            BEQ  PG_STYLE
PG_DIG      LDB  fprec+1
            CMPB #NSIG
            BLS  PG_N
            LDB  #NSIG
PG_N        JSR  DIGITS
PG_STYLE    LDD  fexp
            CMPD #-4
            BLT  PG_E
            CMPD fprec
            BGE  PG_E
            LDD  fprec                 ; %f, P - 1 - exponent after the point
            SUBD #1
            SUBD fexp
            STD  fprec
PF_F        JSR  STYLEF
            BRA  PF_DONE
PG_E        LDD  fprec                 ; %e, P - 1 after the point
            SUBD #1
            STD  fprec
PF_E        JSR  STYLEE
PF_DONE     TFR  U,D                   ; -> U the characters, D how many
            SUBD fstart
            LDU  fstart
            PULS Y
            TST  fneg
            BEQ  PF_RET
            ORCC #1
            RTS
PF_RET      ANDCC #$FE
            RTS
; A = a character: written (upper case for E F G).
PUTC        TST  fupper
            BEQ  PU_PUT
            CMPA #'a'
            BLO  PU_PUT
            CMPA #'z'
            BHI  PU_PUT
            SUBA #'a'-'A'
PU_PUT      STA  ,U+
            RTS
;------------------------------------------------------------------------------
; %f: N = round(x * 10^prec) if that's below 10^9 (its digits, the point put in);
; otherwise the first NSIG digits, and zeros.
STYLEF      LDX  fprec
            LDQ  fq
            JSR  __fxint
            CMPD #$3B9A                ; (10^9 = $3B9ACA00)
            BHI  SF_BIG
            BLO  SF_INT
            CMPW #$CA00
            BHS  SF_BIG
SF_INT      STQ  fnum                  ; its digits; the first is at 10^(n-1-p)
            JSR  UTOA
            CLRA
            LDB  fnd
            SUBD #1
            SUBD fprec
            STD  fexp
            BRA  SF_WRITE
SF_BIG      LDB  #NSIG
            JSR  DIGITS
SF_WRITE    LDD  fexp                  ; the integer part (0 if there's none)
            BPL  SF_INTP
            LDA  #'0'
            JSR  PUTC
            BRA  SF_POINT
SF_INTP     CLRD
SF_IL       PSHS D
            JSR  DIGAT
            JSR  PUTC
            PULS D
            ADDD #1
            CMPD fexp
            BLE  SF_IL
SF_POINT    LDD  fprec                 ; the point (if digits follow, or #)
            BNE  SF_PT
            TST  falt
            BEQ  SF_RET
SF_PT       STU  fpoint
            LDA  #'.'
            JSR  PUTC
            LDD  fexp                  ; prec digits after it
            ADDD #1
            LDX  fprec
SF_FL       CMPX #0
            BEQ  SF_STRIP
            PSHS D,X
            JSR  DIGAT
            JSR  PUTC
            PULS D,X
            ADDD #1
            LEAX -1,X
            BRA  SF_FL
SF_STRIP    JMP  STRIP
SF_RET      RTS
;------------------------------------------------------------------------------
; %e: prec + 1 significant digits (at most NSIG worked out), d.ddd, e, the
; exponent's sign and at least two digits.
STYLEE      CLRD
            STD  fexp
            CLR  fnd                   ; (0: digits of 0)
            LDQ  fq
            TSTD
            BNE  SE_DIG
            TSTW
            BEQ  SE_WRITE
SE_DIG      LDB  fprec+1
            INCB
            CMPB #NSIG
            BLS  SE_N
            LDB  #NSIG
SE_N        JSR  DIGITS
SE_WRITE    CLRD
            JSR  DIGAT
            JSR  PUTC
            LDD  fprec
            BNE  SE_PT
            TST  falt
            BEQ  SE_EXP
SE_PT       STU  fpoint
            LDA  #'.'
            JSR  PUTC
            LDD  #1
SE_FL       CMPD fprec
            BGT  SE_STRIP
            PSHS D
            JSR  DIGAT
            JSR  PUTC
            PULS D
            ADDD #1
            BRA  SE_FL
SE_STRIP    JSR  STRIP
SE_EXP      LDA  #'e'
            JSR  PUTC
            LDD  fexp
            BPL  SE_EPOS
            NEGD
            PSHS B
            LDA  #'-'
            BRA  SE_ESGN
SE_EPOS     PSHS B
            LDA  #'+'
SE_ESGN     JSR  PUTC
            PULS B                     ; (below 100)
            LDA  #'0'-1
SE_TENS     INCA
            SUBB #10
            BCC  SE_TENS
            ADDB #10+'0'
            PSHS B
            JSR  PUTC
            PULS A
            JMP  PUTC
;------------------------------------------------------------------------------
; %g without #: the zeros at the end of the digits after the point go, and
; the point if nothing's left after it.
STRIP       TST  fstrip
            BEQ  SP_RET
            LDX  fpoint
            BEQ  SP_RET
SP_LOOP     LDA  ,-U
            CMPA #'0'
            BEQ  SP_LOOP
            CMPU fpoint
            BEQ  SP_RET                ; (the point: gone too)
            LEAU 1,U
SP_RET      RTS
;------------------------------------------------------------------------------
; B = n (1 to NSIG): N = x's first n significant digits, rounded (fnum, and
; their characters in fdig), and fexp = the power of ten of the first. Its
; exponent is estimated (log10(2) is about 77/256), then put right.
DIGITS      STB  fn
            LDD  fq                    ; the binary exponent
            LSLB
            ROLA
            TFR  A,B
            CLRA
            SUBD #127
            MULD #77
            TFR  W,D
            TFR  A,B
            SEX
            STD  fexp
            LDA  #4                    ; (a few tries at most)
            STA  ftries
DG_TRY      LDB  fn                    ; N = round(x * 10^(n - 1 - E))
            CLRA
            SUBD #1
            SUBD fexp
            TFR  D,X
            LDQ  fq
            JSR  __fxint
            STQ  fnum
            DEC  ftries
            BEQ  DG_DONE
            LDB  fn                    ; N >= 10^n: E one more
            LDX  #pow10
            LSLB
            LSLB
            ABX
            LDQ  fnum
            CMPD ,X
            BHI  DG_UP
            BLO  DG_LOW
            CMPW 2,X
            BLO  DG_LOW
DG_UP       LDX  fexp
            LEAX 1,X
            STX  fexp
            BRA  DG_TRY
DG_LOW      LDQ  fnum                  ; N < 10^(n-1): E one less
            CMPD -4,X
            BHI  DG_DONE
            BLO  DG_DOWN
            CMPW -2,X
            BHS  DG_DONE
DG_DOWN     LDX  fexp
            LEAX -1,X
            STX  fexp
            BRA  DG_TRY
DG_DONE     JMP  UTOA
; fnum -> its decimal digits in fdig (no zeros before them; "0" for 0), fnd
; how many. fnum is used up.
UTOA        PSHS Y
            LDY  #fdig
            CLR  fnd
            LDX  #pow10+36             ; 10^9 down to 10^0
UT_POW      CLR  fdc                   ; (the digit: how many times it goes)
UT_SUB      LDQ  fnum
            SUBW 2,X
            SBCD ,X
            BCS  UT_DIG
            STQ  fnum
            INC  fdc
            BRA  UT_SUB
UT_DIG      LDA  fdc
            ADDA #'0'
            CMPA #'0'
            BNE  UT_PUT
            TST  fnd
            BNE  UT_PUT
            CMPX #pow10                ; (the last: 0 itself)
            BNE  UT_NEXT
UT_PUT      STA  ,Y+
            INC  fnd
UT_NEXT     LEAX -4,X
            CMPX #pow10
            BHS  UT_POW
            PULS Y,PC
; D = a place (0: the first significant digit) -> A = its digit: fdig's, or
; '0' before them or after them.
DIGAT       TSTA
            BMI  DA_ZERO
            BNE  DA_ZERO
            CMPB fnd
            BHS  DA_ZERO
            LDX  #fdig
            LDA  B,X
            RTS
DA_ZERO     LDA  #'0'
            RTS
;------------------------------------------------------------------------------
pow10       FDB  0,1,0,10,0,100,0,1000,0,10000
            FDB  $0001,$86A0,$000F,$4240,$0098,$9680,$05F5,$E100,$3B9A,$CA00
s_inf       FCC  "inf"
s_nan       FCC  "nan"
            ENDSECT
;------------------------------------------------------------------------------
            SECTION bss
fq          RMB  4                     ; the number (its magnitude)
fnum        RMB  4                     ; its digits as a number
fexp        RMB  2                     ; the power of ten of the first digit
fprec       RMB  2
fstart      RMB  2                     ; the characters
fpoint      RMB  2                     ; where the point went (0: none)
fdig        RMB  10                    ; the digits
fnd         RMB  1                     ; how many
fn          RMB  1
fdc         RMB  1
ftries      RMB  1
fconv       RMB  1                     ; 'e' 'f' 'g'
fupper      RMB  1
falt        RMB  1
fstrip      RMB  1
fneg        RMB  1
            ENDSECT
;------------------------------------------------------------------------------
; End of fltio.asm
;------------------------------------------------------------------------------
