;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 C library
;    FILE: strcat.asm -- char *strcat(char *d, const char *s)
;------------------------------------------------------------------------------
            EXPORT _strcat
            SECTION code
_strcat     PSHS Y
            LDY  4,S
SA_END      TST  ,Y+
            BNE  SA_END
            LEAY -1,Y
            LDX  6,S
SA_LOOP     LDA  ,X+
            STA  ,Y+
            BNE  SA_LOOP
            LDD  4,S
            PULS Y,PC
            ENDSECT
