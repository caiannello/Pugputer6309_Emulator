;------------------------------------------------------------------------------
; arith.asm -- the compiler's helpers: int division and shifts by a count.
;
; D = the left operand, X = the right one -> D = the result. They keep Y and
; U (X, W and CC are scratch). Division by zero gives -1 (or $FFFF), and the
; dividend as the remainder, rather than a trap.
;   __udiv  unsigned /      __umod  unsigned %
;   __div   signed /        __mod   signed % (the sign of the dividend; C
;                                   division truncates toward zero)
;   __shl   <<              __shr   signed >>      __ushr  unsigned >>
;   (a count of 16 or more shifts everything out)
;------------------------------------------------------------------------------
            SECTION code
            EXPORT __udiv
            EXPORT __umod
            EXPORT __div
            EXPORT __mod
            EXPORT __shl
            EXPORT __shr
            EXPORT __ushr
__udiv      BSR  UDM16
            RTS
__umod      BSR  UDM16
            TFR  X,D
            RTS
__div       BSR  SDM16
            RTS
__mod       BSR  SDM16
            TFR  X,D
            RTS
; D / X, unsigned -> D = the quotient, X = the remainder.
UDM16       CMPX #0
            BEQ  UD_ZERO
            PSHS X                     ; ,S the divisor
            CLRW                       ; the remainder
            LDX  #16
UD_LOOP     LSLB                       ; the dividend's top bit into the
            ROLA                       ; remainder; the quotient's bits come in
            ROLW                       ; at the bottom of D
            BCS  UD_SUB                ; (17 bits: more than the divisor)
            CMPW ,S
            BLO  UD_NEXT
UD_SUB      SUBW ,S
            INCB
UD_NEXT     LEAX -1,X
            BNE  UD_LOOP
            LEAS 2,S
            TFR  W,X
            RTS
UD_ZERO     TFR  D,X
            LDD  #$FFFF
            RTS
; D / X, signed -> D = the quotient, X = the remainder.
SDM16       PSHS D,X                   ; ,S the dividend, 2,S the divisor
            TSTA
            BPL  SD_APOS
            NEGD
SD_APOS     TFR  D,W
            LDD  2,S
            BPL  SD_BPOS
            NEGD
SD_BPOS     TFR  D,X
            TFR  W,D
            BSR  UDM16
            TST  ,S                    ; the remainder: the dividend's sign
            BPL  SD_RPOS
            EXG  D,X
            NEGD
            EXG  D,X
SD_RPOS     PSHS D                     ; the quotient: negative if the signs
            LDA  2,S                   ; differ
            EORA 4,S
            PULS D
            BPL  SD_QPOS
            NEGD
SD_QPOS     LEAS 4,S
            RTS
__shl       CMPX #16
            BHS  SH_ZERO
SL_LOOP     CMPX #0
            BEQ  SH_RET
            LSLD
            LEAX -1,X
            BRA  SL_LOOP
__ushr      CMPX #16
            BHS  SH_ZERO
UR_LOOP     CMPX #0
            BEQ  SH_RET
            LSRD
            LEAX -1,X
            BRA  UR_LOOP
__shr       CMPX #16
            BHS  SR_SIGN
SR_LOOP     CMPX #0
            BEQ  SH_RET
            ASRD
            LEAX -1,X
            BRA  SR_LOOP
SR_SIGN     TFR  A,B
            SEX
            TFR  A,B
SH_RET      RTS
SH_ZERO     CLRD
            RTS
;------------------------------------------------------------------------------
; End of arith.asm
;------------------------------------------------------------------------------
