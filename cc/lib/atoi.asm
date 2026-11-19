;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 C library
;    FILE: atoi.asm -- int atoi(const char *s): spaces, a sign, decimal digits (wrapping at 16 bits)
;------------------------------------------------------------------------------
            EXPORT _atoi
            SECTION code
_atoi       LDX  2,S
AI_SP       LDA  ,X+                   ; spaces (as isspace)
            CMPA #' '
            BEQ  AI_SP
            CMPA #9
            BLO  AI_SIGN
            CMPA #13
            BLS  AI_SP
AI_SIGN     CLRB                       ; B: negative
            CMPA #'+'
            BEQ  AI_NEXT
            CMPA #'-'
            BNE  AI_GO
            INCB
AI_NEXT     LDA  ,X+
AI_GO       PSHS B
            LDW  #0                    ; W: the value
AI_DIG      SUBA #'0'
            CMPA #9
            BHI  AI_END
            PSHS A
            TFR  W,D                   ; W*10 + the digit
            LSLD
            PSHS D
            LSLD
            LSLD
            ADDD ,S++
            ADDB ,S+
            ADCA #0
            TFR  D,W
            LDA  ,X+
            BRA  AI_DIG
AI_END      TFR  W,D
            TST  ,S+
            BEQ  AI_RET
            NEGD
AI_RET      RTS
            ENDSECT
