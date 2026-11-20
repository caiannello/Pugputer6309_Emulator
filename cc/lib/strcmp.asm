;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 C library
;    FILE: strcmp.asm -- int strcmp(const char *a, const char *b): <0, 0, >0 (bytes unsigned)
;------------------------------------------------------------------------------
            EXPORT _strcmp
            SECTION code
_strcmp     PSHS Y
            LDX  4,S
            LDY  6,S
SM_LOOP     LDB  ,X+
            CMPB ,Y+
            BNE  SM_DIFF
            TSTB
            BNE  SM_LOOP
            CLRA
            PULS Y,PC
SM_DIFF     CLRA                       ; *a - *b
            SUBB -1,Y
            SBCA #0
            PULS Y,PC
            ENDSECT
