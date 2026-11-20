;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 C library
;    FILE: mexp.asm -- math.h: double exp(double x), log(x), log10(x),
;          pow(x, y), sinh(x), cosh(x), tanh(x)
;
; As Cephes's expf, logf, sinhf and tanhf (Stephen L. Moshier's). exp: x = n
; ln 2 + r (ln 2 in two parts), a polynomial of r, times 2^n. log: x = m 2^e
; (m from sqrt(1/2) to sqrt(2)), a polynomial of m - 1, and e ln 2. pow: a
; whole y below 32768 by squaring (exact where it can be); otherwise
; exp(y log x), a negative x only with a whole y. log(0) is -inf, a negative
; number's a NaN; exp overflows to inf above 88.7, and is 0 below -88.
;------------------------------------------------------------------------------
    INCLUDE defines.d
    INCLUDE libc.d
    INCLUDE fmath.d
            EXPORT _exp,_log,_log10,_pow,_sinh,_cosh,_tanh
            IMPORT __fadd,__fsub,__fmul,__fdiv,__fcmp,__ftol,__ltof,__fpoly
            IMPORT __ftrunc,_floor,_frexp,_ldexp
            SECTION code
; exp. The frame (U): 0 x, 4 z, 8 n, 10 a float.
_exp        LDQ  2,S
EXPQ        PSHS U
            LEAS -14,S
            TFR  S,U
            STQ  ,U
            ANDA #$7F                  ; (NaN: itself; inf goes on)
            CMPD #$7F80
            LBHI EX_SAME
            BLO  EX_NUM
            TSTW
            LBNE EX_SAME
EX_NUM      LDQ  ,U
            FK   __fcmp,MAXL
            LBGT EX_INF
            LDQ  ,U
            FK   __fcmp,MINL
            LBLT EX_ZERO
            LDQ  ,U                    ; n = floor(x log2(e) + 1/2)
            FK   __fmul,LOG2EF
            FK   __fadd,HALF
            FPUSH
            JSR  _floor
            LEAS 4,S
            STQ  4,U
            JSR  __ftol
            STW  8,U
            LDQ  4,U                   ; x -= n C1, x -= n C2
            FK   __fmul,C1
            STQ  10,U
            LDQ  ,U
            FV   __fsub,10
            STQ  ,U
            LDQ  4,U
            FK   __fmul,C2
            STQ  10,U
            LDQ  ,U
            FV   __fsub,10
            STQ  ,U
            FV   __fmul,0              ; z = x * x; P(x) z + x + 1
            STQ  4,U
            LDQ  ,U
            FPOLY EXPP
            FV   __fmul,4
            FV   __fadd,0
            FK   __fadd,ONE
            LDX  8,U                   ; times 2^n
            PSHS X
            FPUSH
            JSR  _ldexp
            LEAS 6,S
            BRA  EX_RET
EX_SAME     LDQ  ,U
            BRA  EX_RET
EX_INF      LDD  #$7F80
            CLRW
            BRA  EX_RET
EX_ZERO     CLRD
            CLRW
EX_RET      LEAS 14,U
            PULS U,PC
; log. The frame: 0 x, 4 z, 8 y, 12 e, 14 e as a float, 18 a float.
_log        LDQ  2,S
LOGQ        PSHS U
            LEAS -22,S
            TFR  S,U
            STQ  ,U
            ANDA #$7F
            ORR  W,D
            LBEQ LG_MINF               ; log(0): -inf
            TST  ,U
            LBMI LG_NAN
            LDD  ,U
            CMPD #$7F80
            LBHS LG_SAME               ; (inf, NaN)
            LEAX 12,U                  ; x = m 2^e
            PSHS X
            LDQ  ,U
            FPUSH
            JSR  _frexp
            LEAS 6,S
            STQ  ,U
            FK   __fcmp,SQRTHF
            BGE  LG_GE
            LDX  12,U                  ; m < sqrt(1/2): e - 1, 2m - 1
            LEAX -1,X
            STX  12,U
            LDQ  ,U
            FV   __fadd,0
            FK   __fsub,ONE
            BRA  LG_X
LG_GE       LDQ  ,U                    ; else m - 1
            FK   __fsub,ONE
LG_X        STQ  ,U
            FV   __fmul,0              ; z = x * x, y = P(x) x z
            STQ  4,U
            LDQ  ,U
            FPOLY LOGP
            FV   __fmul,0
            FV   __fmul,4
            STQ  8,U
            LDW  12,U                  ; y += e C2
            SEXW
            JSR  __ltof
            STQ  14,U
            FK   __fmul,C2
            FV   __fadd,8
            STQ  8,U
            LDQ  4,U                   ; y -= z / 2
            FK   __fmul,HALF
            STQ  18,U
            LDQ  8,U
            FV   __fsub,18
            FV   __fadd,0              ; x + y + e C1
            STQ  8,U
            LDQ  14,U
            FK   __fmul,C1
            FV   __fadd,8
            BRA  LG_RET
LG_MINF     LDD  #$FF80
            CLRW
            BRA  LG_RET
LG_NAN      LDD  #$7FC0
            CLRW
            BRA  LG_RET
LG_SAME     LDQ  ,U
LG_RET      LEAS 22,U
            PULS U,PC
_log10      LDQ  2,S
            JSR  LOGQ
            FK   __fmul,LOG10E
            RTS
; pow(x, y). The frame: 0 r, 4 b, 8 m, 10 1/r wanted, 11 odd, 12 a float;
; x at 20, y at 24.
_pow        PSHS U
            LEAS -16,S
            TFR  S,U
            LDD  24,U                  ; y = 0: 1
            ANDA #$7F
            ORD  26,U
            LBEQ PW_ONE
            LDD  20,U                  ; x = 0: 0 (y > 0), or inf
            ANDA #$7F
            ORD  22,U
            BNE  PW_NZ
            TST  24,U
            LBMI PW_INF
            CLRD
            CLRW
            LBRA PW_RET
PW_NZ       CLR  11,U
            LDQ  24,U                  ; y whole?
            JSR  __ftrunc
            FV   __fcmp,24
            LBNE PW_FRAC
            LDQ  24,U                  ; and below 32768: squaring
            ANDA #$7F
            FK   __fcmp,BIGINT
            BGE  PW_BIG
            LDQ  24,U
            JSR  __ftol
            CLR  10,U
            TFR  W,D
            TSTA
            BPL  PW_M
            INC  10,U
            NEGD
PW_M        STD  8,U
            FLD  ONE
            STQ  ,U
            LDQ  20,U
            STQ  4,U
PW_SQ       LDD  8,U                   ; each bit of m: r *= b; b *= b
            LSRD
            STD  8,U
            BCC  PW_SKIP
            LDQ  ,U
            FV   __fmul,4
            STQ  ,U
PW_SKIP     LDD  8,U
            BEQ  PW_DONE
            LDQ  4,U
            FV   __fmul,4
            STQ  4,U
            BRA  PW_SQ
PW_DONE     LDQ  ,U
            TST  10,U                  ; (y < 0: 1/r)
            LBEQ PW_RET
            STQ  12,U
            FLD  ONE
            FV   __fdiv,12
            LBRA PW_RET
PW_BIG      LDQ  24,U                  ; whole and big: odd only below 2^24
            ANDA #$7F
            FK   __fcmp,TWO24
            BGE  PW_LOG
            LDQ  24,U
            JSR  __ftol
            STW  12,U
            LDB  13,U
            ANDB #1
            STB  11,U
            BRA  PW_LOG
PW_FRAC     TST  20,U                  ; a fraction of a negative: NaN
            BMI  PW_NAN
PW_LOG      LDQ  20,U                  ; exp(y log |x|), - if x < 0 and y odd
            ANDA #$7F
            JSR  LOGQ
            FV   __fmul,24
            JSR  EXPQ
            TST  20,U
            BPL  PW_RET
            TST  11,U
            BEQ  PW_RET
            EORA #$80
            BRA  PW_RET
PW_ONE      FLD  ONE
            BRA  PW_RET
PW_INF      LDD  #$7F80
            CLRW
            BRA  PW_RET
PW_NAN      LDD  #$7FC0
            CLRW
PW_RET      LEAS 16,U
            PULS U,PC
; cosh = (e + 1/e) / 2, e = exp(|x|). The frame: 0 e; x at 8.
_cosh       PSHS U
            LEAS -4,S
            TFR  S,U
            LDQ  8,U
            ANDA #$7F
            JSR  EXPQ
            STQ  ,U
            FLD  ONE
            FV   __fdiv,0
            FV   __fadd,0
            FK   __fmul,HALF
            LEAS 4,U
            PULS U,PC
; sinh: |x| > 1: (e - 1/e) / 2; otherwise a polynomial. The frame: 0 e, 4 z,
; 8 the sign; x at 13.
_sinh       PSHS U
            LEAS -9,S
            TFR  S,U
            LDQ  13,U
            JSR  HY_SIGN
            FK   __fcmp,ONE
            BLE  SH_POLY
            LDQ  ,U
            JSR  EXPQ
            STQ  ,U
            FLD  ONE
            FV   __fdiv,0
            STQ  4,U
            LDQ  ,U
            FV   __fsub,4
            FK   __fmul,HALF
            BRA  HY_SIGNED
SH_POLY     LDX  #SINHP
HY_POLY     PSHS X                     ; z x P(z) + x
            LDQ  ,U
            FV   __fmul,0
            STQ  4,U
            PULS X
            JSR  __fpoly
            FV   __fmul,4
            FV   __fmul,0
            FV   __fadd,0
HY_SIGNED   TST  8,U
            BEQ  HY_RET
            EORA #$80
HY_RET      LEAS 9,U
            PULS U,PC
; Q -> 0,U = |Q|, 8,U = its sign, and Q = |Q|.
HY_SIGN     CLR  8,U
            TSTA
            BPL  HS_POS
            INC  8,U
            ANDA #$7F
HS_POS      STQ  ,U
            RTS
; tanh: |x| > 0.625: 1 - 2 / (exp(2|x|) + 1); otherwise a polynomial.
_tanh       PSHS U
            LEAS -9,S
            TFR  S,U
            LDQ  13,U
            BSR  HY_SIGN
            FK   __fcmp,PT625
            BLE  TH_POLY
            LDQ  ,U
            FV   __fadd,0
            JSR  EXPQ
            FK   __fadd,ONE
            STQ  4,U
            FLD  TWO
            FV   __fdiv,4
            STQ  4,U
            FLD  ONE
            FV   __fsub,4
            LBRA HY_SIGNED
TH_POLY     LDX  #TANHP
            LBRA HY_POLY
;------------------------------------------------------------------------------
ONE         FDB  $3F80,$0000
TWO         FDB  $4000,$0000
HALF        FDB  $3F00,$0000
PT625       FDB  $3F20,$0000
MAXL        FDB  $42B1,$7218           ; 88.7228...: the most exp takes
MINL        FDB  $C2B0,$0000           ; -88
LOG2EF      FDB  $3FB8,$AA3B           ; log2(e)
C1          FDB  $3F31,$8000           ; ln 2 = C1 - C2
C2          FDB  $B95E,$8083
SQRTHF      FDB  $3F35,$04F3           ; sqrt(1/2)
LOG10E      FDB  $3EDE,$5BD9           ; log10(e)
BIGINT      FDB  $4700,$0000           ; 32768
TWO24       FDB  $4B80,$0000           ; 2^24
EXPP        FCB  6
            FDB  $3950,$6967           ; 1.9875691500e-4
            FDB  $3AB7,$43CE           ; 1.3981999507e-3
            FDB  $3C08,$8908           ; 8.3334519073e-3
            FDB  $3D2A,$A9C1           ; 4.1665795894e-2
            FDB  $3E2A,$AAAA           ; 1.6666665459e-1
            FDB  $3F00,$0000           ; 5.0000001201e-1
LOGP        FCB  9
            FDB  $3D90,$21BB           ; 7.0376836292e-2
            FDB  $BDEB,$D1B8           ; -1.1514610310e-1
            FDB  $3DEF,$251A           ; 1.1676998740e-1
            FDB  $BDFE,$5D4F           ; -1.2420140846e-1
            FDB  $3E11,$E9BF           ; 1.4249322787e-1
            FDB  $BE2A,$AE50           ; -1.6668057665e-1
            FDB  $3E4C,$CEAC           ; 2.0000714765e-1
            FDB  $BE7F,$FFFC           ; -2.4999993993e-1
            FDB  $3EAA,$AAAA           ; 3.3333331174e-1
SINHP       FCB  3
            FDB  $3955,$9E2F           ; 2.03721912945e-4
            FDB  $3C08,$7BBE           ; 8.33028376239e-3
            FDB  $3E2A,$AACC           ; 1.66667160211e-1
TANHP       FCB  5
            FDB  $BBBA,$F0EA           ; -5.70498872745e-3
            FDB  $3CA9,$134E           ; 2.06390887954e-2
            FDB  $BD5C,$1E2D           ; -5.37397155531e-2
            FDB  $3E08,$8393           ; 1.33314422036e-1
            FDB  $BEAA,$AA99           ; -3.33332819422e-1
            ENDSECT
;------------------------------------------------------------------------------
; End of mexp.asm
;------------------------------------------------------------------------------
