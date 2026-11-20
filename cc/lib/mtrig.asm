;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 C library
;    FILE: mtrig.asm -- math.h: double sin(double x), cos(x), tan(x)
;
; As Cephes's sinf, cosf and tanf (Stephen L. Moshier's): x is brought to
; within pi/4 of a multiple of pi/2 (j, its octant made even), less j * pi/4
; in three parts so that little is lost, then a polynomial of the sine's or the
; cosine's, as the octant says. Good to a unit or two in the last place for
; |x| up to some thousands; beyond that the octant itself is lost.
;------------------------------------------------------------------------------
    INCLUDE defines.d
    INCLUDE libc.d
    INCLUDE fmath.d
            EXPORT _sin,_cos,_tan
            IMPORT __fadd,__fsub,__fmul,__fdiv,__fcmp,__ftol,__ltof,__fpoly
; The frame (U): 0 x, 4 y, 8 z, 12 j, 14 the sign, 16 a float; x at 24.
FRSZ        equ  20
ARGX        equ  FRSZ+4
            SECTION code
_sin        PSHS U
            LEAS -FRSZ,S
            TFR  S,U
            JSR  TRIGARG               ; (|x|, its sign)
            JSR  REDUCE
            LDA  13,U                  ; octants 4-7: the other sign
            ANDA #7
            CMPA #3
            BLS  SN_J
            SUBA #4
            JSR  TURN
SN_J        CMPA #1                    ; 1, 2: the cosine's
            BEQ  SN_COS
            CMPA #2
            BEQ  SN_COS
            JSR  SINPOLY
            BRA  TR_SIGN
SN_COS      JSR  COSPOLY
TR_SIGN     TST  14,U
            BEQ  TR_RET
            EORA #$80
TR_RET      LEAS FRSZ,U
            PULS U,PC
_cos        PSHS U
            LEAS -FRSZ,S
            TFR  S,U
            JSR  TRIGARG
            CLR  14,U                  ; (cos is even)
            JSR  REDUCE
            LDA  13,U
            ANDA #7
            CMPA #3
            BLS  CS_J
            SUBA #4
            JSR  TURN
CS_J        CMPA #1
            BLS  CS_K
            JSR  TURN
CS_K        CMPA #1
            BEQ  CS_SIN
            CMPA #2
            BEQ  CS_SIN
            JSR  COSPOLY
            BRA  TR_SIGN
CS_SIN      JSR  SINPOLY
            BRA  TR_SIGN
_tan        PSHS U
            LEAS -FRSZ,S
            TFR  S,U
            JSR  TRIGARG
            JSR  REDUCE
            LDQ  8,U                   ; z * x * P(z) + x
            FPOLY TANP
            FV   __fmul,8
            FV   __fmul,0
            FV   __fadd,0
            STQ  16,U
            LDB  13,U                  ; (octants 2, 3: -1 / that)
            BITB #2
            BNE  TN_INV
            LDQ  16,U
            LBRA TR_SIGN
TN_INV      LDD  #$BF80
            CLRW
            FV   __fdiv,16
            LBRA TR_SIGN
; x -> 0,U as |x|, 14,U its sign (1: negative).
TRIGARG     CLR  14,U
            LDQ  ARGX,U
            TSTA
            BPL  TA_POS
            INC  14,U
            ANDA #$7F
TA_POS      STQ  ,U
            RTS
; A kept: the sign turned over.
TURN        PSHS A
            LDA  14,U
            EORA #1
            STA  14,U
            PULS A,PC
; x (0,U, not negative) -> j = (int)(x * 4/pi), made even (y = it as a float),
; x = ((x - y*DP1) - y*DP2) - y*DP3, z = x * x.
REDUCE      LDQ  ,U
            FK   __fmul,FOPI
            JSR  __ftol
            STW  12,U
            LDB  13,U
            BITB #1
            BEQ  RE_EVEN
            LDD  12,U
            ADDD #1
            STD  12,U
RE_EVEN     LDW  12,U
            TFR  W,D
            SEXW
            JSR  __ltof
            STQ  4,U
            FK   __fmul,DP1
            BSR  RE_LESS
            LDQ  4,U
            FK   __fmul,DP2
            BSR  RE_LESS
            LDQ  4,U
            FK   __fmul,DP3
            BSR  RE_LESS
            FV   __fmul,0
            STQ  8,U
            RTS
RE_LESS     STQ  16,U                  ; x = x - Q
            LDQ  ,U
            FV   __fsub,16
            STQ  ,U
            RTS
; z * x * P(z) + x, the sine's.
SINPOLY     LDQ  8,U
            FPOLY SINP
            FV   __fmul,8
            FV   __fmul,0
            FV   __fadd,0
            RTS
; z * z * P(z) - z/2 + 1, the cosine's.
COSPOLY     LDQ  8,U
            FPOLY COSP
            FV   __fmul,8
            FV   __fmul,8
            STQ  4,U
            LDQ  8,U
            FK   __fmul,HALF
            STQ  16,U
            LDQ  4,U
            FV   __fsub,16
            FK   __fadd,ONE
            RTS
;------------------------------------------------------------------------------
FOPI        FDB  $3FA2,$F983           ; 4/pi
DP1         FDB  $3F49,$0000           ; pi/4, in three parts
DP2         FDB  $397D,$A000
DP3         FDB  $3322,$2169
HALF        FDB  $3F00,$0000
ONE         FDB  $3F80,$0000
SINP        FCB  3
            FDB  $B94C,$A1F9           ; -1.9515295891e-4
            FDB  $3C08,$839E           ; 8.3321608736e-3
            FDB  $BE2A,$AAA3           ; -1.6666654611e-1
COSP        FCB  3
            FDB  $37CC,$F5CE           ; 2.443315711809948e-5
            FDB  $BAB6,$061A           ; -1.388731625493765e-3
            FDB  $3D2A,$AAA5           ; 4.166664568298827e-2
TANP        FCB  6
            FDB  $3C19,$C53B           ; 9.38540185543e-3
            FDB  $3B4C,$779C           ; 3.11992232697e-3
            FDB  $3CC8,$21B5           ; 2.44301354525e-2
            FDB  $3D5A,$C5C9           ; 5.34112807005e-2
            FDB  $3E08,$96DD           ; 1.33387994085e-1
            FDB  $3EAA,$AA6F           ; 3.33331568548e-1
            ENDSECT
;------------------------------------------------------------------------------
; End of mtrig.asm
;------------------------------------------------------------------------------
