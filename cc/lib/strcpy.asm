;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 C library
;    FILE: strcpy.asm -- char *strcpy(char *d, const char *s)
;------------------------------------------------------------------------------
            EXPORT _strcpy
            SECTION code
_strcpy     PSHS Y
            LDY  4,S
            LDX  6,S
SC_LOOP     LDA  ,X+
            STA  ,Y+
            BNE  SC_LOOP
            LDD  4,S
            PULS Y,PC
            ENDSECT
