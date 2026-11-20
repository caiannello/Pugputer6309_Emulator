;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 C library
;    FILE: msqrt.asm -- math.h: double sqrt(double x)
;
; Worked out a bit at a time, as an integer square root of the mantissa
; (made even-exponented, and shifted so that the root has 27 bits: 24, a
; rounding bit and two more, and what's left over says if there's anything
; after them), so the result is the correctly rounded one. sqrt(-0) is -0, a
; negative number's is a NaN, inf's inf.
;------------------------------------------------------------------------------
    INCLUDE defines.d
    INCLUDE libc.d
            EXPORT _sqrt
            SECTION code
; The frame (U): 0 the remainder, 4 the root, 8 a trial, 12 the radicand's
; bits still to come, 16 the count, 17 round up, 18 the exponent; x at 24.
_sqrt       PSHS U
            LEAS -20,S
            TFR  S,U
            LDD  24,U
            LSLB
            ROLA                       ; A = the exponent
            LBEQ SQ_SAME               ; (+-0)
            TST  24,U
            LBMI SQ_NAN
            CMPA #255
            LBEQ SQ_SAME               ; (inf, NaN)
            TFR  A,B
            CLRA
            SUBD #127                  ; e, and an odd one made even (the
            BITB #1                    ; mantissa twice as big)
            BEQ  SQ_EVEN
            SUBD #1
            LDX  #1
            BRA  SQ_E
SQ_EVEN     LDX  #0
SQ_E        ASRA                       ; the root's exponent: 127 + e / 2
            RORB
            ADDD #127
            STD  18,U
            STX  16,U                  ; (for a moment)
            LDB  25,U                  ; Q = the mantissa (24 bits) << 8
            ORB  #$80
            TFR  B,A
            LDB  26,U
            LDE  27,U
            CLRF
            TST  17,U
            BNE  SQ_RA                 ; (odd: << 8, even: << 7)
            LSRD
            RORW
SQ_RA       STQ  12,U
            CLRD
            CLRW
            STQ  ,U
            STQ  4,U
            LDA  #27
            STA  16,U
            CLR  17,U
SQ_LOOP     LDB  #2                    ; two bits into the remainder
SQ_TWO      LSL  15,U
            ROL  14,U
            ROL  13,U
            ROL  12,U
            ROL  3,U
            ROL  2,U
            ROL  1,U
            ROL  ,U
            DECB
            BNE  SQ_TWO
            LDQ  4,U                   ; the trial: root * 4 + 1
            ADDR W,W
            ROLD
            ADDR W,W
            ROLD
            ADDW #1
            STQ  8,U
            LDQ  ,U                    ; it goes: the remainder less it, and a
            SUBW 10,U                  ; 1 in the root
            SBCD 8,U
            BCS  SQ_NO
            STQ  ,U
            LDQ  4,U
            ADDR W,W
            ROLD
            ADDW #1
            BRA  SQ_ROOT
SQ_NO       LDQ  4,U
            ADDR W,W
            ROLD
SQ_ROOT     STQ  4,U
            DEC  16,U
            BNE  SQ_LOOP
            LDA  7,U                   ; round: the three bits below the 24
            ANDA #7
            CMPA #4
            BLO  SQ_PACK
            BHI  SQ_UP
            LDQ  ,U                    ; (just a half: up if there's more,
            TSTD                       ; or the last kept is odd)
            BNE  SQ_UP
            TSTW
            BNE  SQ_UP
            LDA  7,U
            BITA #8
            BEQ  SQ_PACK
SQ_UP       INC  17,U
SQ_PACK     LDB  #3                    ; the 24 bits
            STB  16,U
            LDQ  4,U
SQ_SHIFT    LSRD
            RORW
            DEC  16,U
            BNE  SQ_SHIFT
            TST  17,U
            BEQ  SQ_SIG
            ADDW #1
            ADCD #0
SQ_SIG      CMPD #$0100                ; (rounded up to 2^24: 2^23, twice)
            BLO  SQ_BITS
            LSRD
            RORW
            INC  19,U
SQ_BITS     ANDB #$7F                  ; the exponent in
            LDA  19,U
            LSRA
            BCC  SQ_RET
            ORB  #$80
            BRA  SQ_RET
SQ_SAME     LDQ  24,U
            BRA  SQ_RET
SQ_NAN      LDD  #$7FC0
            CLRW
SQ_RET      LEAS 20,U
            PULS U,PC
            ENDSECT
;------------------------------------------------------------------------------
; End of msqrt.asm
;------------------------------------------------------------------------------
