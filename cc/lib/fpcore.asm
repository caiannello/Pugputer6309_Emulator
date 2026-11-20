;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 C library
;    FILE: fpcore.asm -- floating point: the arithmetic, the conversions, and
;          decimal scaling. INCLUDEd, in its section, by float.asm (the
;          library's member) and by CC1 (cc1.asm), which folds constants and
;          reads numbers with it, so that both get the same bits.
;
; A float (and a double: the same type) is IEEE 754's single: 1 bit of sign,
; 8 of exponent (biased by 127), 23 of fraction. In Q it is as in memory: D the
; high word (A the sign and most of the exponent), W the low one. Rounding is
; to the nearest, ties to even. Infinities and NaNs come and go as IEEE has
; them, but there are no denormals: a result too small for a normal number is
; a zero, and a denormal operand is taken as one.
;
; The compiler's helpers (as the long ones: the left operand in Q, the right on
; the stack at 2,S as the helper sees it, the result in Q; the caller takes the
; right off again). They keep X, Y and U.
;   __fadd __fsub __fmul __fdiv   Q = Q op 2,S
;   __fcmp      Q against 2,S -> D = -1, 0 or 1, and the flags as TSTD sets
;               them (so a signed branch follows). -0 equals +0. A NaN is
;               taken as greater than everything.
;   __ltof __ultof   Q = a long (unsigned long) as a float
;   __ftol __ftoul   Q = a float as a long (unsigned long), truncated toward
;               zero; too big gives the limit. (A negative one to unsigned:
;               as a long.)
;   __finc __fdec    Q = Q + 1.0, Q - 1.0
; For the library's conversions to and from decimal (they keep Y and U):
;   __fdec2f    Q = M (unsigned) * 10^X (signed), rounded, as a float
;   __fxint     Q = round(x * 10^X) for a float x >= 0 in Q, as an unsigned
;               long ($FFFFFFFF if it doesn't fit); a tie (only when it's
;               exact) to even, as printf's are
;
; Inside, a number is unpacked to a record of 7 bytes: its sign ($80 or 0), its
; exponent (16 bits, signed, biased by 127) and a mantissa of 32 bits with the
; leading 1 at the top (bit 31), so its low byte holds the bits rounding needs.
; Each routine has a frame of FPFRM bytes, at U (the caller's U and X saved
; above it): two records (A and B), 8 bytes for a product, and some scratch.
;------------------------------------------------------------------------------
FR_A        equ  0                 ; record A (the left operand, the result)
FR_B        equ  7                 ; record B (the right)
FR_P        equ  14                ; 8 bytes: a product, a divisor, a quotient
FR_K        equ  22                ; 2 bytes: kinds, flags, counts
FR_T        equ  24                ; 2 bytes: a table pointer
FPFRM       equ  26
FPARG       equ  FPFRM+6           ; the right operand, as the caller pushed it
R_S         equ  0                 ; a record: the sign
R_E         equ  1                 ; the exponent
R_M         equ  3                 ; the mantissa
;------------------------------------------------------------------------------
; The frame, and the way out (Q is the result).
FPEXIT      LEAS FPFRM,U
            PULS X,U,PC
FP_NAN      LDD  #$7FC0                ; a NaN
            CLRW
            BRA  FPEXIT
FP_ZERO     CLRD
            CLRW
            BRA  FPEXIT
;------------------------------------------------------------------------------
; + and -.
;------------------------------------------------------------------------------
__fsub      PSHS U,X
            LEAS -FPFRM,S
            TFR  S,U
            LDX  #$80                  ; (FR_K+1 = $80: b's sign turned over)
            STX  FR_K,U
            BRA  FA_GO
__fadd      PSHS U,X
            LEAS -FPFRM,S
            TFR  S,U
            CLR  FR_K+1,U
FA_GO       LEAX FR_A,U
            JSR  FPUNPK
            STB  FR_K,U
            LDQ  FPARG,U
            LEAX FR_B,U
            JSR  FPUNPK                ; (B = b's kind)
            LDA  FR_B+R_S,U
            EORA FR_K+1,U
            STA  FR_B+R_S,U
            LDA  FR_K,U                ; A = a's kind
            CMPA #3
            BEQ  FP_NAN
            CMPB #3
            BEQ  FP_NAN
            CMPA #2
            BNE  FA_ANINF
            CMPB #2                    ; inf + x: inf (inf - inf: NaN)
            BNE  FA_RETA
            LDA  FR_A+R_S,U
            CMPA FR_B+R_S,U
            BNE  FP_NAN
            BRA  FA_RETA
FA_ANINF    CMPB #2                    ; x + inf
            BEQ  FA_RETB
            TSTB
            BNE  FA_BNZ
            TSTA                       ; x + 0: x
            BNE  FA_RETA
            LDA  FR_A+R_S,U            ; 0 + 0: -0 only if both are
            ANDA FR_B+R_S,U
            STA  FR_A+R_S,U
            BRA  FA_RETA
FA_BNZ      TSTA                       ; 0 + y: y
            BNE  FA_BOTH
FA_RETB     LEAX FR_B,U
            BRA  FA_PACKX
FA_RETA     LEAX FR_A,U
FA_PACKX    JSR  FPPACK
            BRA  FPEXIT
FA_BOTH     LDD  FR_A+R_E,U            ; |a| >= |b| (or they change places)
            CMPD FR_B+R_E,U
            BGT  FA_ORDER
            BLT  FA_SWAP
            LDD  FR_A+R_M,U
            CMPD FR_B+R_M,U
            BHI  FA_ORDER
            BLO  FA_SWAP
            LDD  FR_A+R_M+2,U
            CMPD FR_B+R_M+2,U
            BHS  FA_ORDER
FA_SWAP     LEAX FR_A,U
            LDB  #7
FA_SWL      LDA  ,X
            LDE  FR_B-FR_A,X
            STA  FR_B-FR_A,X
            STE  ,X+
            DECB
            BNE  FA_SWL
FA_ORDER    LDD  FR_A+R_E,U            ; b shifted to a's exponent
            SUBD FR_B+R_E,U
            TSTA
            BEQ  FA_SH
            LDB  #255
FA_SH       LEAX FR_B+R_M,U
            JSR  FPSHR
            TSTF                       ; (what fell off: a 1 at the bottom)
            BEQ  FA_SIGNS
            LDA  FR_B+R_M+3,U
            ORA  #1
            STA  FR_B+R_M+3,U
FA_SIGNS    LDA  FR_A+R_S,U
            EORA FR_B+R_S,U
            STA  FR_K,U                ; (bit 7: the magnitudes subtracted)
            LDQ  FR_A+R_M,U
            TST  FR_K,U
            BMI  FA_SUB
            ADDW FR_B+R_M+2,U
            ADCD FR_B+R_M,U
            BCC  FA_STORE
            RORD                       ; a carry: one place right, the bit
            RORW                       ; that falls off kept
            STQ  FR_A+R_M,U
            BCC  FA_UP
            LDA  FR_A+R_M+3,U
            ORA  #1
            STA  FR_A+R_M+3,U
FA_UP       LDX  FR_A+R_E,U
            LEAX 1,X
            STX  FR_A+R_E,U
            BRA  FA_PACK
FA_SUB      SUBW FR_B+R_M+2,U
            SBCD FR_B+R_M,U
            BNE  FA_STORE
            TSTW
            BNE  FA_STORE
            CLR  FR_A+R_S,U            ; x - x: +0
FA_STORE    STQ  FR_A+R_M,U
FA_PACK     LEAX FR_A,U
            JSR  FPNORM
            JSR  FPPACK
            JMP  FPEXIT
;------------------------------------------------------------------------------
; *
;------------------------------------------------------------------------------
__fmul      PSHS U,X
            LEAS -FPFRM,S
            TFR  S,U
            JSR  FPBOTH                ; A = a's kind, B = b's, the sign set
            CMPA #3
            LBEQ FP_NAN
            CMPB #3
            LBEQ FP_NAN
            CMPA #2
            BEQ  FM_AINF
            CMPB #2
            BEQ  FM_BINF
            TSTA
            BEQ  FM_SZERO
            TSTB
            BEQ  FM_SZERO
            JSR  FPMUL32
            LDD  FR_A+R_E,U            ; the exponent: ea + eb - 126
            ADDD FR_B+R_E,U
            SUBD #126
            STD  FR_A+R_E,U
            TST  FR_P,U                ; the product below 2^63: one place
            BMI  FM_TOP                ; left
            LSL  FR_P+5,U
            ROL  FR_P+4,U
            ROL  FR_P+3,U
            ROL  FR_P+2,U
            ROL  FR_P+1,U
            ROL  FR_P,U
            LDX  FR_A+R_E,U
            LEAX -1,X
            STX  FR_A+R_E,U
FM_TOP      LDQ  FR_P,U                ; its top 32 bits, the rest a 1 at the
            STQ  FR_A+R_M,U            ; bottom if it isn't 0
            LDD  FR_P+4,U
            BEQ  FM_PACK
FM_STICKY   LDA  FR_A+R_M+3,U
            ORA  #1
            STA  FR_A+R_M+3,U
FM_PACK     LEAX FR_A,U
            JSR  FPPACK
            JMP  FPEXIT
FM_AINF     TSTB                       ; inf * 0: NaN
            LBEQ FP_NAN
FM_SINF     LDD  #255                  ; inf, signed (A's mantissa isn't 0)
            STD  FR_A+R_E,U
            BRA  FM_PACK
FM_BINF     TSTA
            LBEQ FP_NAN
            BRA  FM_SINF
FM_SZERO    CLR  FR_A+R_M,U            ; 0, signed
            BRA  FM_PACK
;------------------------------------------------------------------------------
; /
;------------------------------------------------------------------------------
__fdiv      PSHS U,X
            LEAS -FPFRM,S
            TFR  S,U
            JSR  FPBOTH
            CMPA #3
            LBEQ FP_NAN
            CMPB #3
            LBEQ FP_NAN
            CMPA #2
            BNE  FD_ANINF
            CMPB #2                    ; inf / inf: NaN; inf / x: inf
            LBEQ FP_NAN
            BRA  FM_SINF
FD_ANINF    CMPB #2                    ; x / inf: 0
            BEQ  FM_SZERO
            TSTB
            BNE  FD_BNZ
            TSTA                       ; 0 / 0: NaN; x / 0: inf
            LBEQ FP_NAN
            BRA  FM_SINF
FD_BNZ      TSTA                       ; 0 / y: 0
            BEQ  FM_SZERO
            CLR  FR_P,U                ; the divisor: b's 24 bits
            LDA  FR_B+R_M,U
            STA  FR_P+1,U
            LDD  FR_B+R_M+1,U
            STD  FR_P+2,U
            CLRD                       ; the quotient (32 bits)
            STD  FR_P+4,U
            STD  FR_P+6,U
            LDB  #32
            STB  FR_K,U
            LDD  FR_A+R_E,U            ; the exponent: ea - eb + 127
            SUBD FR_B+R_E,U
            ADDD #127
            STD  FR_A+R_E,U
            CLRA                       ; Q = the remainder: a's 24 bits
            LDB  FR_A+R_M,U
            LDW  FR_A+R_M+1,U
            CMPD FR_P,U                ; (below the divisor: twice it, and the
            BHI  FD_LOOP               ; exponent one less, so that the
            BLO  FD_SHIFT              ; quotient's first bit is a 1)
            CMPW FR_P+2,U
            BHS  FD_LOOP
FD_SHIFT    ADDR W,W
            ROLD
            LDX  FR_A+R_E,U
            LEAX -1,X
            STX  FR_A+R_E,U
FD_LOOP     LSL  FR_P+7,U              ; a bit of the quotient each time
            ROL  FR_P+6,U
            ROL  FR_P+5,U
            ROL  FR_P+4,U
            CMPD FR_P,U
            BHI  FD_SUB
            BLO  FD_NEXT
            CMPW FR_P+2,U
            BLO  FD_NEXT
FD_SUB      SUBW FR_P+2,U
            SBCD FR_P,U
            INC  FR_P+7,U
FD_NEXT     ADDR W,W
            ROLD
            DEC  FR_K,U
            BNE  FD_LOOP
            TSTD                       ; a remainder: a 1 at the bottom
            BNE  FD_REM
            TSTW
            BEQ  FD_DONE
FD_REM      LDA  FR_P+7,U
            ORA  #1
            STA  FR_P+7,U
FD_DONE     LDQ  FR_P+4,U
            STQ  FR_A+R_M,U
            LEAX FR_A,U
            JSR  FPPACK
            JMP  FPEXIT
; Both operands unpacked (a from Q, b from FPARG) -> A = a's kind, B = b's;
; the result's sign (a's xor b's) in record A.
FPBOTH      LEAX FR_A,U
            JSR  FPUNPK
            STB  FR_K,U
            LDQ  FPARG,U
            LEAX FR_B,U
            JSR  FPUNPK
            LDA  FR_A+R_S,U
            EORA FR_B+R_S,U
            STA  FR_A+R_S,U
            LDA  FR_K,U
            RTS
;------------------------------------------------------------------------------
; Comparing: each made a 32-bit signed number that sorts as the floats do
; (a negative one is minus its magnitude), then subtracted.
;------------------------------------------------------------------------------
__fcmp      TSTA
            BPL  FC_APOS
            ANDA #$7F
            COMD
            COMW
            ADDW #1
            ADCD #0
FC_APOS     PSHSW
            PSHS D                     ; (,S a's, 6,S b)
            LDQ  6,S
            TSTA
            BPL  FC_BPOS
            ANDA #$7F
            COMD
            COMW
            ADDW #1
            ADCD #0
FC_BPOS     STQ  6,S
            PULS D
            PULSW
            SUBW 4,S
            SBCD 2,S
            BLT  FC_LT
            BNE  FC_GT
            TSTW
            BNE  FC_GT
            CLRD
            RTS
FC_LT       LDD  #-1
            RTS
FC_GT       LDD  #1
            RTS
;------------------------------------------------------------------------------
; Conversions.
;------------------------------------------------------------------------------
__ultof     PSHS U,X
            LEAS -FPFRM,S
            TFR  S,U
            CLR  FR_A+R_S,U
            BRA  LF_GO
__ltof      PSHS U,X
            LEAS -FPFRM,S
            TFR  S,U
            CLR  FR_A+R_S,U
            TSTA
            BPL  LF_GO
            COMD                       ; negative: its magnitude
            COMW
            ADDW #1
            ADCD #0
            LDX  #$8000                ; (R_S = $80)
            STX  FR_A+R_S,U
LF_GO       STQ  FR_A+R_M,U
            LDX  #127+31
            STX  FR_A+R_E,U
            LEAX FR_A,U
            JSR  FPNORM
            JSR  FPPACK
            JMP  FPEXIT
__ftoul     PSHS U,X
            LEAS -FPFRM,S
            TFR  S,U
            LDX  #1                    ; (FR_K+1 = 1: unsigned)
            STX  FR_K,U
            BRA  FI_GO
__ftol      PSHS U,X
            LEAS -FPFRM,S
            TFR  S,U
            CLR  FR_K+1,U
FI_GO       LEAX FR_A,U
            JSR  FPUNPK
            TSTB
            LBEQ FP_ZERO
            CMPB #3
            LBEQ FP_ZERO
            LDD  FR_A+R_E,U            ; the value is m * 2^(e - 31)
            SUBD #127
            LBLT FP_ZERO
            CMPD #31
            BGE  FI_BIG
            NEGB                       ; m >> (31 - e)
            ADDB #31
            LEAX FR_A+R_M,U
            JSR  FPSHR
            LDQ  FR_A+R_M,U
            TST  FR_A+R_S,U
            BPL  FI_RET
            COMD
            COMW
            ADDW #1
            ADCD #0
FI_RET      JMP  FPEXIT
FI_BIG      TST  FR_K+1,U              ; 2^31 and up: unsigned, and 2^31 to
            BEQ  FI_SLIM               ; 2^32 - 1, is m itself
            TST  FR_A+R_S,U
            BMI  FI_SLIM
            CMPD #31
            BNE  FI_UMAX
            LDQ  FR_A+R_M,U
            JMP  FPEXIT
FI_UMAX     LDD  #$FFFF
            LDW  #$FFFF
            JMP  FPEXIT
FI_SLIM     LDD  #$7FFF                ; the limits
            LDW  #$FFFF
            TST  FR_A+R_S,U
            BPL  FI_RET
            LDD  #$8000
            CLRW
            JMP  FPEXIT
    IFNDEF FP_NOLIB
__finc      PSHS X
            LDX  #0
            PSHS X
            LDX  #$3F80
            PSHS X
            JSR  __fadd
            LEAS 4,S
            PULS X,PC
__fdec      PSHS X
            LDX  #0
            PSHS X
            LDX  #$3F80
            PSHS X
            JSR  __fsub
            LEAS 4,S
            PULS X,PC
    ENDC
;------------------------------------------------------------------------------
; Decimal.
;------------------------------------------------------------------------------
__fdec2f    PSHS U,X
            LEAS -FPFRM,S
            TFR  S,U
            CLR  FR_A+R_S,U
            STQ  FR_A+R_M,U
            LDX  #127+31
            STX  FR_A+R_E,U
            LEAX FR_A,U
            JSR  FPNORM
            TST  FR_A+R_M,U
            BPL  DF_PACK               ; (0)
            LDX  FPFRM,U               ; (the X it came with)
            JSR  FPXSCALE
DF_PACK     LEAX FR_A,U
            JSR  FPPACK
            JMP  FPEXIT
    IFNDEF FP_NOLIB
__fxint     PSHS U,X
            LEAS -FPFRM,S
            TFR  S,U
            LEAX FR_A,U
            JSR  FPUNPK
            TSTB
            LBEQ FP_ZERO
            CMPB #1
            BNE  XI_MAX
            CLR  FR_K+1,U              ; (not 0: inexact, so it's no tie)
            LDX  FPFRM,U
            JSR  FPXSCALE
            LDD  FR_A+R_E,U            ; m * 2^(e - 31): shifted right 31 - e,
            SUBD #127                  ; rounded (half up)
            CMPD #32
            BGE  XI_MAX
            CMPD #-1
            LBLT FP_ZERO
            NEGB
            ADDB #31
            BEQ  XI_TOP
            DECB
            LEAX FR_A+R_M,U
            JSR  FPSHR
            TSTF
            BEQ  XI_BITS
            INC  FR_K+1,U
XI_BITS     CLR  FR_T,U                ; FR_T: up (the bit below is a 1, and
            LDA  FR_A+R_M+3,U          ; more after it, or the last kept is)
            LSRA
            BCC  XI_SHIFT
            TST  FR_K+1,U
            BNE  XI_UP
            BITA #1
            BEQ  XI_SHIFT
XI_UP       INC  FR_T,U
XI_SHIFT    LDQ  FR_A+R_M,U
            LSRD
            RORW
            TST  FR_T,U
            BEQ  XI_RET
            ADDW #1
            ADCD #0
            BCS  XI_MAX
XI_RET      JMP  FPEXIT
XI_TOP      LDQ  FR_A+R_M,U
            JMP  FPEXIT
XI_MAX      LDD  #$FFFF
            LDW  #$FFFF
            JMP  FPEXIT
    ENDC
; Record A (normalized, not 0) times 10^X (to +-127, which is more than enough).
FPXSCALE    TFR  X,D
            LEAX FPTENP,PCR
            TSTA
            BPL  XS_MAG
            NEGD
            LEAX FPTENM,PCR
XS_MAG      CMPD #127
            BLS  XS_SET
            LDB  #127
XS_SET      STB  FR_K,U
XS_LOOP     STX  FR_T,U
            LSR  FR_K,U                ; each bit of the exponent: its power
            BCC  XS_NEXT
            LDQ  2,X
            STQ  FR_B+R_M,U
            LDD  ,X
            STD  FR_B+R_E,U
            JSR  FPXMUL
XS_NEXT     LDX  FR_T,U
            LEAX 6,X
            TST  FR_K,U
            BNE  XS_LOOP
            RTS
; Record A = A * B (32-bit mantissas, the product rounded to 32 bits).
FPXMUL      JSR  FPMUL32
            LDD  FR_A+R_E,U
            ADDD FR_B+R_E,U
            SUBD #126
            STD  FR_A+R_E,U
            TST  FR_P,U
            BMI  XM_TOP
            LSL  FR_P+4,U
            ROL  FR_P+3,U
            ROL  FR_P+2,U
            ROL  FR_P+1,U
            ROL  FR_P,U
            LDX  FR_A+R_E,U
            LEAX -1,X
            STX  FR_A+R_E,U
XM_TOP      LDD  FR_P+4,U              ; (bits that go: FR_K+1 not 0)
            ORD  FR_P+6,U
            BEQ  XM_EXACT
            INC  FR_K+1,U
XM_EXACT    LDQ  FR_P,U
            TST  FR_P+4,U
            BPL  XM_SET
            ADDW #1
            ADCD #0
            BCC  XM_SET
            LDD  #$8000                ; (all ones, rounded up)
            LDX  FR_A+R_E,U
            LEAX 1,X
            STX  FR_A+R_E,U
XM_SET      STQ  FR_A+R_M,U
            RTS
; 10^1, 10^2, 10^4 ... 10^64, and 10^-1 ... 10^-64, as records' exponents and
; mantissas (rounded).
FPTENP      FDB  130,$A000,$0000
            FDB  133,$C800,$0000
            FDB  140,$9C40,$0000
            FDB  153,$BEBC,$2000
            FDB  180,$8E1B,$C9BF
            FDB  233,$9DC5,$ADA8
            FDB  339,$C278,$1F4A
FPTENM      FDB  123,$CCCC,$CCCD
            FDB  120,$A3D7,$0A3D
            FDB  113,$D1B7,$1759
            FDB  100,$ABCC,$7712
            FDB  73,$E695,$94BF
            FDB  20,$CFB1,$1EAD
            FDB  -86,$A87F,$EA28
;------------------------------------------------------------------------------
; Records.
;------------------------------------------------------------------------------
; Q (a float) -> the record at X; B = its kind: 0 zero (a denormal too), 1 a
; number, 2 infinite, 3 NaN. Keeps X and U.
FPUNPK      STW  R_M+1,X
            CLR  R_M+3,X
            TFR  A,E
            TFR  B,F
            ORB  #$80                  ; the leading 1
            STB  R_M,X
            CLR  R_E,X
            ANDA #$80
            STA  R_S,X
            TFR  F,B
            LSLB                       ; (C = the exponent's low bit)
            TFR  E,A
            ROLA
            STA  R_E+1,X
            BEQ  FU_ZERO
            INCA
            BEQ  FU_SPEC
            LDB  #1
            RTS
FU_ZERO     CLR  R_M,X
            CLR  R_M+1,X
            CLR  R_M+2,X
            CLRB
            RTS
FU_SPEC     LDA  R_M,X
            ANDA #$7F
            ORA  R_M+1,X
            ORA  R_M+2,X
            BNE  FU_NAN
            LDB  #2
            RTS
FU_NAN      LDB  #3
            RTS
; The record at X (normalized, or a mantissa of 0) -> Q, rounded: infinite if
; it's too big, 0 if it's too small. Keeps X and U.
FPPACK      TST  R_M,X
            BPL  FK_ZERO
            LDA  R_M+3,X               ; to the nearest (ties to even)
            CMPA #$80
            BLO  FK_EXP
            BHI  FK_UP
            LDA  R_M+2,X
            BITA #1
            BEQ  FK_EXP
FK_UP       INC  R_M+2,X
            BNE  FK_EXP
            INC  R_M+1,X
            BNE  FK_EXP
            INC  R_M,X
            BNE  FK_EXP
            LDA  #$80
            STA  R_M,X
            LDD  R_E,X
            ADDD #1
            STD  R_E,X
FK_EXP      LDD  R_E,X
            BLE  FK_ZERO
            CMPD #255
            BGE  FK_INF
            LSRB                       ; (C = the exponent's low bit)
            ORB  R_S,X
            TFR  B,A
            LDB  R_M,X
            ANDB #$7F
            BCC  FK_LOW
            ORB  #$80
FK_LOW      LDW  R_M+1,X
            RTS
FK_ZERO     LDA  R_S,X
            CLRB
            CLRW
            RTS
FK_INF      LDA  R_S,X
            ORA  #$7F
            LDB  #$80
            CLRW
            RTS
; The record at X normalized (its mantissa shifted left until the top bit is
; a 1). Keeps X and U.
FPNORM      LDA  R_M,X
            BMI  FN_RET
            ORA  R_M+1,X
            ORA  R_M+2,X
            ORA  R_M+3,X
            BEQ  FN_RET
FN_BYTE     TST  R_M,X
            BNE  FN_BIT
            LDD  R_M+1,X
            STD  R_M,X
            LDA  R_M+3,X
            STA  R_M+2,X
            CLR  R_M+3,X
            LDD  R_E,X
            SUBD #8
            STD  R_E,X
            BRA  FN_BYTE
FN_BIT      TST  R_M,X
            BMI  FN_RET
            LSL  R_M+3,X
            ROL  R_M+2,X
            ROL  R_M+1,X
            ROL  R_M,X
            LDD  R_E,X
            SUBD #1
            STD  R_E,X
            BRA  FN_BIT
FN_RET      RTS
; The 32 bits at X shifted right B places; F is not 0 if a 1 fell off. Keeps
; X and U.
FPSHR       CLRF
            CMPB #32
            BLO  FS_BYTE
            LDA  ,X                    ; 32 or more: all of them
            ORA  1,X
            ORA  2,X
            ORA  3,X
            BEQ  FS_RET
            LDF  #1
            CLR  ,X
            CLR  1,X
            CLR  2,X
            CLR  3,X
            RTS
FS_BYTE     CMPB #8
            BLO  FS_BITS
            TST  3,X
            BEQ  FS_MOVE
            LDF  #1
FS_MOVE     LDA  2,X
            STA  3,X
            LDA  1,X
            STA  2,X
            LDA  ,X
            STA  1,X
            CLR  ,X
            SUBB #8
            BRA  FS_BYTE
FS_BITS     TSTB
            BEQ  FS_RET
FS_BIT      LSR  ,X
            ROR  1,X
            ROR  2,X
            ROR  3,X
            BCC  FS_NEXT
            LDF  #1
FS_NEXT     DECB
            BNE  FS_BIT
FS_RET      RTS
; The product (64 bits, at FR_P) of the mantissas of records A and B.
FPMUL32     CLRD
            STD  FR_P,U
            STD  FR_P+2,U
            STD  FR_P+4,U
            STD  FR_P+6,U
            LDE  #3                    ; E: a's byte, F: b's (3 the lowest);
FP_MI       LEAX FR_A+R_M,U            ; their product goes in at E+F
            TST  E,X
            BEQ  FP_MINEXT
            LDF  #3
FP_MJ       LEAX FR_A+R_M,U
            LDA  E,X
            LEAX FR_B+R_M,U
            LDB  F,X
            MUL
            BEQ  FP_MJNEXT
            LEAX FR_P,U
            LEAX E,X
            ADDD F,X
            STD  F,X
            BCC  FP_MJNEXT
            LEAX F,X                   ; the carry, on up
FP_MC       LEAX -1,X
            INC  ,X
            BEQ  FP_MC
FP_MJNEXT   DECF
            BPL  FP_MJ
FP_MINEXT   DECE
            BPL  FP_MI
            RTS
;------------------------------------------------------------------------------
; End of fpcore.asm
;------------------------------------------------------------------------------
