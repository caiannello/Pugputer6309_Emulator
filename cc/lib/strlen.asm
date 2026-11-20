;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 C library
;    FILE: strlen.asm -- size_t strlen(const char *s)
;------------------------------------------------------------------------------
            EXPORT _strlen
            SECTION code
_strlen     LDX  2,S
SL_LOOP     TST  ,X+
            BNE  SL_LOOP
            TFR  X,D
            SUBD 2,S
            DECD
            RTS
            ENDSECT
