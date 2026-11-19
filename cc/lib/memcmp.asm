;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 C library
;    FILE: memcmp.asm -- int memcmp(const void *a, const void *b, size_t n)
;------------------------------------------------------------------------------
            EXPORT _memcmp
            SECTION code
_memcmp     PSHS Y
            LDX  4,S
            LDY  6,S
            LDW  8,S
            BEQ  MC_SAME
MC_LOOP     LDB  ,X+
            CMPB ,Y+
            BNE  MC_DIFF
            DECW
            BNE  MC_LOOP
MC_SAME     CLRD
            PULS Y,PC
MC_DIFF     CLRA
            SUBB -1,Y
            SBCA #0
            PULS Y,PC
            ENDSECT
