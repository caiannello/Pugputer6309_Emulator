;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 C library
;    FILE: strncmp.asm -- int strncmp(const char *a, const char *b, size_t n)
;------------------------------------------------------------------------------
            EXPORT _strncmp
            SECTION code
_strncmp    PSHS Y
            LDX  4,S
            LDY  6,S
            LDW  8,S
            BEQ  SN_SAME
SN_LOOP     LDB  ,X+
            CMPB ,Y+
            BNE  SN_DIFF
            TSTB
            BEQ  SN_SAME
            DECW
            BNE  SN_LOOP
SN_SAME     CLRD
            PULS Y,PC
SN_DIFF     CLRA
            SUBB -1,Y
            SBCA #0
            PULS Y,PC
            ENDSECT
