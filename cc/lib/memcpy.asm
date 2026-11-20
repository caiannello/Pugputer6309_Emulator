;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 C library
;    FILE: memcpy.asm -- void *memcpy(void *d, const void *s, size_t n)
;------------------------------------------------------------------------------
            EXPORT _memcpy
            SECTION code
_memcpy     PSHS Y
            LDY  4,S
            LDX  6,S
            LDW  8,S
            TFM  X+,Y+
            LDD  4,S
            PULS Y,PC
            ENDSECT
