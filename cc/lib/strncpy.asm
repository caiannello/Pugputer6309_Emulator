;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 C library
;    FILE: strncpy.asm -- char *strncpy(char *d, const char *s, size_t n): n bytes, NUL-padded
;------------------------------------------------------------------------------
            EXPORT _strncpy
            SECTION code
_strncpy    PSHS Y
            LDY  4,S
            LDX  6,S
            LDW  8,S
            BEQ  SN_RET
SN_COPY     LDA  ,X+
            STA  ,Y+
            BEQ  SN_PAD
            DECW
            BNE  SN_COPY
            BRA  SN_RET
SN_PAD      DECW                       ; (the NUL was one of them)
            BEQ  SN_RET
SN_ZERO     CLR  ,Y+
            DECW
            BNE  SN_ZERO
SN_RET      LDD  4,S
            PULS Y,PC
            ENDSECT
