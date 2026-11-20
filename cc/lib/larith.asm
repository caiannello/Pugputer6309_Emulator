;------------------------------------------------------------------------------
; larith.asm -- the compiler's helpers for longs: * / % and shifts by a count.
;
; Q = the left operand (D its high word); the right is on the stack, at 2,S
; as the helper sees it: a long (high word first), or for a shift the count
; (an int). -> Q = the result. The caller takes the right side off again.
; They keep X, Y and U. Division by zero gives -1 ($FFFFFFFF), and the
; dividend as the remainder, rather than a trap.
;   __lmul  *  (signed or not: the low 32 bits are the same)
;   __uldiv unsigned /      __ulmod unsigned %
;   __ldiv  signed /        __lmod  signed % (the sign of the dividend)
;   __lshl  <<              __lshr  signed >>      __lushr unsigned >>
;   (a count of 32 or more shifts everything out)
;------------------------------------------------------------------------------
            SECTION code
            EXPORT __lmul
            EXPORT __uldiv
            EXPORT __ulmod
            EXPORT __ldiv
            EXPORT __lmod
            EXPORT __lshl
            EXPORT __lshr
            EXPORT __lushr
; a * b = aL*bL + ((aH*bL + aL*bH) << 16). MULD is signed: aL*bL unsigned is
; that, plus bL << 16 if aL is negative, plus aL << 16 if bL is.
__lmul      PSHS X
            PSHSW
            PSHS D                     ; ,S aH, 2,S aL, 4,S X, 6,S return,
            MULD 10,S                  ; 8,S bH, 10,S bL
            TFR  W,X                   ; aH*bL (its low word)
            LDD  2,S
            MULD 8,S
            ADDR W,X                   ; + aL*bH
            LDD  2,S
            MULD 10,S                  ; aL*bL
            TST  2,S
            BPL  LM_A
            ADDD 10,S
LM_A        TST  10,S
            BPL  LM_B
            ADDD 2,S
LM_B        ADDR X,D
            LEAS 4,S
            PULS X,PC
; Division: the four share LDIVIDE (X = 0 unsigned /, 1 unsigned %, 2 signed
; /, 3 signed %).
__uldiv     PSHS X
            LDX  #0
            BRA  LDIVIDE
__ulmod     PSHS X
            LDX  #1
            BRA  LDIVIDE
__ldiv      PSHS X
            LDX  #2
            BRA  LDIVIDE
__lmod      PSHS X
            LDX  #3
LDIVIDE     PSHS X                     ; the kind (8,S its signs: bit 7 the
            PSHSW                      ; quotient's, bit 6 the remainder's)
            PSHS D                     ; N: the dividend, then the quotient
            CLRD
            CLRW
            PSHSW
            PSHS D                     ; R: the remainder so far
            LDD  14,S                  ; (,S R, 4,S N, 8,S signs, 9,S the
            ORD  16,S                  ; kind, 10,S X, 12,S return, 14,S the
            BEQ  LD_ZERO               ; divisor)
            LDB  9,S
            BITB #2
            BEQ  LD_GO
            TST  4,S                   ; signed: on the magnitudes
            BPL  LD_NPOS
            LEAX 4,S
            BSR  NEG4
            LDA  #$C0
            STA  8,S
LD_NPOS     TST  14,S
            BPL  LD_GO
            LEAX 14,S
            BSR  NEG4
            LDA  8,S
            EORA #$80
            STA  8,S
LD_GO       LDX  #32
LD_LOOP     LDQ  4,S                   ; N <<= 1, its top bit into R
            ADDR W,W
            ROLD
            STQ  4,S
            LDQ  ,S
            ROLW
            ROLD
            STQ  ,S
            BCS  LD_SUB                ; (33 bits: more than the divisor)
            SUBW 16,S                  ; does the divisor go?
            SBCD 14,S
            BCS  LD_NEXT
            BRA  LD_GOES
LD_SUB      SUBW 16,S
            SBCD 14,S
LD_GOES     STQ  ,S
            INC  7,S                   ; the quotient's bit
LD_NEXT     LEAX -1,X
            BNE  LD_LOOP
            TST  8,S                   ; the signs
            BPL  LD_QPOS
            LEAX 4,S
            BSR  NEG4
LD_QPOS     LDA  8,S
            BITA #$40
            BEQ  LD_RESULT
            LEAX ,S
            BSR  NEG4
LD_RESULT   LDB  9,S                   ; the quotient, or the remainder
            BITB #1
            BNE  LD_REM
            LDQ  4,S
            BRA  LD_RET
LD_REM      LDQ  ,S
LD_RET      LEAS 10,S
            PULS X,PC
LD_ZERO     LDB  9,S                   ; by zero: -1, the remainder the
            BITB #1                    ; dividend
            BNE  LD_ZMOD
            LDD  #$FFFF
            TFR  D,W
            BRA  LD_RET
LD_ZMOD     LDQ  4,S
            BRA  LD_RET
; X = a 32-bit number: negated in place.
NEG4        CLRD
            CLRW
            SUBW 2,X
            SBCD ,X
            STQ  ,X
            RTS
; Shifts: ,S X, 2,S the return, 4,S the count.
__lshl      PSHS X
            LDX  4,S
            CMPX #32
            BHS  LS_ZERO
LS_LEFT     CMPX #0
            BEQ  LS_RET
            ADDR W,W
            ROLD
            LEAX -1,X
            BRA  LS_LEFT
LS_ZERO     CLRD
            CLRW
LS_RET      PULS X,PC
__lushr     PSHS X
            LDX  4,S
            CMPX #32
            BHS  LS_ZERO
LS_URIGHT   CMPX #0
            BEQ  LS_RET
            LSRD
            RORW
            LEAX -1,X
            BRA  LS_URIGHT
__lshr      PSHS X
            LDX  4,S
            CMPX #32
            BLO  LS_RIGHT
            LDX  #31                   ; (all of it: the sign)
LS_RIGHT    CMPX #0
            BEQ  LS_RET
            ASRD
            RORW
            LEAX -1,X
            BRA  LS_RIGHT
;------------------------------------------------------------------------------
; End of larith.asm
;------------------------------------------------------------------------------
