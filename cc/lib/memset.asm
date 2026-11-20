;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 C library
;    FILE: memset.asm -- void *memset(void *d, int c, size_t n)
;------------------------------------------------------------------------------
            EXPORT _memset
            SECTION code
_memset     PSHS Y
            LDY  4,S
            LEAX 7,S                   ; (c's low byte, on the stack: the source)
            LDW  8,S
            TFM  X,Y+
            LDD  4,S
            PULS Y,PC
            ENDSECT
