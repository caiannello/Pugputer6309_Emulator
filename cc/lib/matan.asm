;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 C library
;    FILE: matan.asm -- math.h: double atan(double x), atan2(y, x), asin(x),
;          acos(x)
;
; As Cephes's atanf and asinf (Stephen L. Moshier's). atan: above tan(3pi/8),
; pi/2 + atan(-1/x); above tan(pi/8), pi/4 + atan((x-1)/(x+1)); then a
; polynomial. asin: above 1/2, pi/2 - 2 asin(sqrt((1-x)/2)); then a
; polynomial. acos from asin. atan2(y, x) is atan(y/x) put in its quadrant
; (x = 0: +-pi/2, or 0). asin and acos of more than 1 are NaNs.
;------------------------------------------------------------------------------
    INCLUDE defines.d
    INCLUDE libc.d
    INCLUDE fmath.d
            EXPORT _atan,_atan2,_asin,_acos
            IMPORT __fadd,__fsub,__fmul,__fdiv,__fcmp,__fpoly,_sqrt
            SECTION code
; atan. The frame (U): 0 x, 4 y, 8 z, 12 the sign.
_atan       LDQ  2,S
ATANQ       PSHS U
            LEAS -13,S
            TFR  S,U
            CLR  12,U
            TSTA
            BPL  AT_POS
            INC  12,U
            ANDA #$7F
AT_POS      STQ  ,U
            CLRD
            CLRW
            STQ  4,U
            LDQ  ,U
            FK   __fcmp,T3P8
            BLE  AT_MID
            FLD  PIO2                  ; pi/2 + atan(-1/x)
            STQ  4,U
            LDD  #$BF80
            CLRW
            FV   __fdiv,0
            STQ  ,U
            BRA  AT_POLY
AT_MID      LDQ  ,U
            FK   __fcmp,TP8
            BLE  AT_POLY
            FLD  PIO4                  ; pi/4 + atan((x-1)/(x+1))
            STQ  4,U
            LDQ  ,U
            FK   __fadd,ONE
            STQ  8,U
            LDQ  ,U
            FK   __fsub,ONE
            FV   __fdiv,8
            STQ  ,U
AT_POLY     LDQ  ,U                    ; z = x * x; y + z * x * P(z) + x
            FV   __fmul,0
            STQ  8,U
            FPOLY ATANP
            FV   __fmul,8
            FV   __fmul,0
            FV   __fadd,0
            FV   __fadd,4
            TST  12,U
            BEQ  AT_RET
            EORA #$80
AT_RET      LEAS 13,U
            PULS U,PC
; atan2(y, x). The frame: 0 a float; y at 8, x at 12.
_atan2      PSHS U
            LEAS -4,S
            TFR  S,U
            LDD  12,U                  ; x = 0: pi/2 as y's sign, or y (0)
            ANDA #$7F
            ORD  14,U
            BNE  A2_DIV
            LDD  8,U
            ANDA #$7F
            ORD  10,U
            BEQ  A2_Y
            FLD  PIO2
            TST  8,U
            BPL  A2_RET
            EORA #$80
            BRA  A2_RET
A2_Y        LDQ  8,U
            BRA  A2_RET
A2_DIV      LDQ  8,U
            FV   __fdiv,12
            JSR  ATANQ
            TST  12,U                  ; x < 0: pi more (y >= 0), or less
            BPL  A2_RET
            TST  8,U
            BMI  A2_SUB
            FK   __fadd,PI
            BRA  A2_RET
A2_SUB      FK   __fsub,PI
A2_RET      LEAS 4,U
            PULS U,PC
; asin. The frame: 0 x, 4 z, 8 a float, 12 the sign, 13 above 1/2.
_asin       LDQ  2,S
ASINQ       PSHS U
            LEAS -14,S
            TFR  S,U
            CLR  12,U
            CLR  13,U
            TSTA
            BPL  AS_POS
            INC  12,U
            ANDA #$7F
AS_POS      STQ  ,U
            FK   __fcmp,ONE
            LBGT AS_NAN
            LDQ  ,U
            FK   __fcmp,HALF
            BLE  AS_SMALL
            INC  13,U                  ; z = (1 - x) / 2, x = sqrt(z)
            FLD  ONE
            FV   __fsub,0
            FK   __fmul,HALF
            STQ  4,U
            FPUSH
            JSR  _sqrt
            LEAS 4,S
            STQ  ,U
            BRA  AS_POLY
AS_SMALL    LDQ  ,U                    ; z = x * x
            FV   __fmul,0
            STQ  4,U
AS_POLY     LDQ  4,U                   ; z * x * P(z) + x
            FPOLY ASINP
            FV   __fmul,4
            FV   __fmul,0
            FV   __fadd,0
            TST  13,U
            BEQ  AS_SIGN
            STQ  8,U                   ; (pi/2 - 2 that)
            FV   __fadd,8
            STQ  8,U
            FLD  PIO2
            FV   __fsub,8
AS_SIGN     TST  12,U
            BEQ  AS_RET
            EORA #$80
            BRA  AS_RET
AS_NAN      LDD  #$7FC0
            CLRW
AS_RET      LEAS 14,U
            PULS U,PC
; acos: x < -1/2: pi - 2 asin(sqrt((1+x)/2)); x > 1/2: 2 asin(sqrt((1-x)/2));
; otherwise pi/2 - asin(x). The frame: 0 a float; x at 8.
_acos       PSHS U
            LEAS -4,S
            TFR  S,U
            LDQ  8,U
            FK   __fcmp,MHALF
            BLT  AC_NEG
            LDQ  8,U
            FK   __fcmp,HALF
            BGT  AC_POS
            LDQ  8,U
            JSR  ASINQ
            STQ  ,U
            FLD  PIO2
            FV   __fsub,0
            BRA  AC_RET
AC_NEG      LDQ  8,U
            FK   __fadd,ONE
            BSR  AC_HALF
            STQ  ,U
            FLD  PI
            FV   __fsub,0
            BRA  AC_RET
AC_POS      FLD  ONE
            FV   __fsub,8
            BSR  AC_HALF
AC_RET      LEAS 4,U
            PULS U,PC
; Q -> 2 asin(sqrt(Q / 2)).
AC_HALF     FK   __fmul,HALF
            FPUSH
            JSR  _sqrt
            LEAS 4,S
            JSR  ASINQ
            STQ  ,U
            FV   __fadd,0
            RTS
;------------------------------------------------------------------------------
PI          FDB  $4049,$0FDB
PIO2        FDB  $3FC9,$0FDB
PIO4        FDB  $3F49,$0FDB
T3P8        FDB  $401A,$827A           ; tan(3pi/8)
TP8         FDB  $3ED4,$13CD           ; tan(pi/8)
ONE         FDB  $3F80,$0000
HALF        FDB  $3F00,$0000
MHALF       FDB  $BF00,$0000
ATANP       FCB  4
            FDB  $3DA4,$F0D1           ; 8.05374449538e-2
            FDB  $BE0E,$1B85           ; -1.38776856032e-1
            FDB  $3E4C,$925F           ; 1.99777106478e-1
            FDB  $BEAA,$AA2A           ; -3.33329491539e-1
ASINP       FCB  5
            FDB  $3D2C,$B352           ; 4.2163199048e-2
            FDB  $3CC6,$17E3           ; 2.4181311049e-2
            FDB  $3D3A,$3EC7           ; 4.5470025998e-2
            FDB  $3D99,$80F6           ; 7.4953002686e-2
            FDB  $3E2A,$AAE4           ; 1.6666752422e-1
            ENDSECT
;------------------------------------------------------------------------------
; End of matan.asm
;------------------------------------------------------------------------------
