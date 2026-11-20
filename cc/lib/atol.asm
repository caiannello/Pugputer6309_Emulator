;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 C library
;    FILE: atol.asm -- long atol(const char *s): spaces, a sign, decimal digits
;          (wrapping at 32 bits)
;------------------------------------------------------------------------------
            EXPORT _atol
            SECTION code
_atol       LDX  2,S
AL_SP       LDA  ,X+                   ; spaces (as isspace)
            CMPA #' '
            BEQ  AL_SP
            CMPA #9
            BLO  AL_SIGN
            CMPA #13
            BLS  AL_SP
AL_SIGN     CLRB                       ; B: negative
            CMPA #'+'
            BEQ  AL_GO
            CMPA #'-'
            BNE  AL_BACK
            INCB
            BRA  AL_GO
AL_BACK     LEAX -1,X                  ; (no sign: X at the first digit)
AL_GO       PSHS B
            CLRD
            CLRW
            PSHSW
            PSHS D                     ; ,S the value, 4,S negative
AL_DIG      LDB  ,X+
            SUBB #'0'
            CMPB #9
            BHI  AL_END
            CLRA
            PSHS D                     ; value * 10 + the digit
            LDQ  2,S
            ADDR W,W                   ; * 2
            ROLD
            STQ  2,S
            ADDR W,W                   ; * 8
            ROLD
            ADDR W,W
            ROLD
            ADDW 4,S
            ADCD 2,S
            ADDW ,S
            ADCD #0
            STQ  2,S
            LEAS 2,S
            BRA  AL_DIG
AL_END      LDQ  ,S
            TST  4,S
            BEQ  AL_RET
            COMD
            COMW
            ADDW #1
            ADCD #0
AL_RET      LEAS 5,S
            RTS
            ENDSECT
