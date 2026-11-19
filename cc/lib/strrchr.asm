;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 C library
;    FILE: strrchr.asm -- char *strrchr(const char *s, int c): the last c, or NULL
;------------------------------------------------------------------------------
            EXPORT _strrchr
            SECTION code
_strrchr    PSHS Y
            LDX  4,S
            LDY  #0
            LDB  7,S
SR_LOOP     LDA  ,X+
            PSHS A
            CMPB ,S+
            BNE  SR_NOT
            LEAY -1,X
SR_NOT      TSTA
            BNE  SR_LOOP
            TFR  Y,D
            PULS Y,PC
            ENDSECT
