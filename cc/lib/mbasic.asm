;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 C library
;    FILE: mbasic.asm -- math.h: fabs floor ceil trunc round fmod modf frexp
;          ldexp, and __fpoly (the polynomials of the other math modules)
;
; double fabs(double x), floor(x), ceil(x), trunc(x), round(x) (halves away
; from 0), fmod(x, y) (x - trunc(x/y) * y: a NaN if y is 0), modf(x, double
; *ip) (the fraction, and *ip the whole part), frexp(x, int *e) (x = m * 2^*e,
; m from 0.5 to 1), ldexp(x, n) (x * 2^n).
; __fpoly: Q = z, X = a table (FCB n, then n floats, the highest power's
; first) -> Q = the polynomial's value (Horner's way). Keeps Y and U.
;------------------------------------------------------------------------------
    INCLUDE defines.d
    INCLUDE libc.d
    INCLUDE fmath.d
            EXPORT _fabs,_floor,_ceil,_trunc,_round,_fmod,_modf,_frexp,_ldexp
            EXPORT __fpoly,__ftrunc
            IMPORT __fadd,__fsub,__fmul,__fdiv,__fcmp
            SECTION code
_fabs       LDQ  2,S
            ANDA #$7F
            RTS
_trunc      LDQ  2,S
; Q = trunc(Q): the bits of the fraction below the point cleared. Keeps X, Y, U.
__ftrunc    PSHSW
            PSHS D
            LSLB
            ROLA                       ; A = the exponent
            CMPA #127
            BLO  TR_ZERO               ; below 1: a zero (of x's sign)
            CMPA #127+23
            BHS  TR_SAME               ; whole already (inf, NaN too)
            NEGA                       ; 150 - E bits go
            ADDA #127+23
            PSHS A
            PSHS A
            LDQ  2,S
TR_RIGHT    LSRD
            RORW
            DEC  ,S
            BNE  TR_RIGHT
            LEAS 1,S
TR_LEFT     ADDR W,W
            ROLD
            DEC  ,S
            BNE  TR_LEFT
            LEAS 5,S
            RTS
TR_ZERO     PULS D
            PULSW
            ANDA #$80
            CLRB
            CLRW
            RTS
TR_SAME     PULS D
            PULSW
            RTS
; floor: t = trunc(x), less 1 if that's above x. ceil: plus 1 if it's below.
_floor      PSHS U
            LEAS -4,S
            TFR  S,U                   ; (0 t, 8 x)
            LDQ  8,U
            BSR  __ftrunc
            STQ  ,U
            FV   __fcmp,8
            BLE  FC_T
            LDQ  ,U
            FK   __fsub,ONE
            BRA  FC_RET
_ceil       PSHS U
            LEAS -4,S
            TFR  S,U
            LDQ  8,U
            BSR  __ftrunc
            STQ  ,U
            FV   __fcmp,8
            BGE  FC_T
            LDQ  ,U
            FK   __fadd,ONE
            BRA  FC_RET
FC_T        LDQ  ,U
FC_RET      LEAS 4,U
            PULS U,PC
; round: t = trunc(x), and 1 more (away from 0) if x - t is a half or more.
_round      PSHS U
            LEAS -4,S
            TFR  S,U                   ; (0 t, 8 x)
            LDQ  8,U
            JSR  __ftrunc
            STQ  ,U
            LDQ  8,U
            FV   __fsub,0
            ANDA #$7F
            FK   __fcmp,HALF
            BLT  FC_T
            LDQ  ,U
            TST  8,U
            BMI  RD_NEG
            FK   __fadd,ONE
            BRA  FC_RET
RD_NEG      FK   __fsub,ONE
            BRA  FC_RET
; fmod(x, y) = x - trunc(x / y) * y.
_fmod       PSHS U
            LEAS -4,S
            TFR  S,U                   ; (0 t, 8 x, 12 y)
            LDD  12,U
            ANDA #$7F
            ORD  14,U
            BEQ  FM_NAN
            LDQ  8,U
            FV   __fdiv,12
            JSR  __ftrunc
            FV   __fmul,12
            STQ  ,U
            LDQ  8,U
            FV   __fsub,0
            LBRA FC_RET
FM_NAN      LDD  #$7FC0
            CLRW
            LBRA FC_RET
; modf(x, ip): *ip = trunc(x), x - that.
_modf       PSHS U
            LEAS -4,S
            TFR  S,U                   ; (0 t, 8 x, 12 ip)
            LDQ  8,U
            JSR  __ftrunc
            LDX  12,U
            STQ  ,X
            STQ  ,U
            LDQ  8,U
            FV   __fsub,0
            LBRA FC_RET
; frexp(x, e): *e = the exponent - 126, x's exponent made 126 (0.5 to 1). 0,
; inf and NaN: x, *e = 0.
_frexp      LDX  6,S
            CLR  ,X
            CLR  1,X
            LDD  2,S
            LSLB
            ROLA
            TSTA
            BEQ  FX_SAME
            CMPA #255
            BEQ  FX_SAME
            TFR  A,B
            CLRA
            SUBD #126
            STD  ,X
            LDQ  2,S
            ANDA #$80
            ORA  #$3F
            ANDB #$7F
            RTS
FX_SAME     LDQ  2,S
            RTS
; ldexp(x, n): the exponent plus n (0 if it's too small, inf if it's too big).
_ldexp      LDD  2,S
            LSLB
            ROLA
            TSTA
            BEQ  FX_SAME
            CMPA #255
            BEQ  FX_SAME
            TFR  A,B
            CLRA
            ADDD 6,S
            BLE  LX_ZERO
            CMPD #255
            BGE  LX_INF
            PSHS B                     ; (,S the exponent, 3,S x)
            LDQ  3,S
            ANDA #$80
            PSHS A
            LDA  1,S
            LSRA                       ; (C = its low bit)
            ORA  ,S+
            ANDB #$7F
            BCC  LX_LOW
            ORB  #$80
LX_LOW      LEAS 1,S
            RTS
LX_ZERO     LDQ  2,S
            ANDA #$80
            CLRB
            CLRW
            RTS
LX_INF      LDQ  2,S
            ANDA #$80
            ORA  #$7F
            LDB  #$80
            CLRW
            RTS
;------------------------------------------------------------------------------
__fpoly     PSHS X,Y,U
            LEAS -5,S                  ; (,S z, 4,S how many to go)
            STQ  ,S
            LDB  ,X+
            DECB
            STB  4,S
            TFR  X,Y
            LDQ  ,Y
            LEAY 4,Y
PL_LOOP     TST  4,S
            BEQ  PL_END
            LDX  2,S                   ; * z
            PSHS X
            LDX  2,S
            PSHS X
            JSR  __fmul
            LEAS 4,S
            LDX  2,Y                   ; + the next
            PSHS X
            LDX  ,Y
            PSHS X
            JSR  __fadd
            LEAS 4,S
            LEAY 4,Y
            DEC  4,S
            BRA  PL_LOOP
PL_END      LEAS 5,S
            PULS X,Y,U,PC
ONE         FDB  $3F80,$0000
HALF        FDB  $3F00,$0000
            ENDSECT
;------------------------------------------------------------------------------
; End of mbasic.asm
;------------------------------------------------------------------------------
