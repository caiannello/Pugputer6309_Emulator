;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 C library
;    FILE: strchr.asm -- char *strchr(const char *s, int c): the first c (the NUL counts), or NULL
;------------------------------------------------------------------------------
            EXPORT _strchr
            SECTION code
_strchr     LDX  2,S
            LDB  5,S
SH_LOOP     LDA  ,X+
            PSHS A
            CMPB ,S+
            BEQ  SH_HIT
            TSTA
            BNE  SH_LOOP
            CLRD
            RTS
SH_HIT      LEAX -1,X
            TFR  X,D
            RTS
            ENDSECT
