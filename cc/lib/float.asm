;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 C library
;    FILE: float.asm -- floating point: the compiler's helpers and the
;          conversions to and from decimal, which are fpcore.asm's (CC1
;          includes the same file, to fold constants and read numbers).
;------------------------------------------------------------------------------
            SECTION code
            EXPORT __fadd,__fsub,__fmul,__fdiv,__fcmp
            EXPORT __ltof,__ultof,__ftol,__ftoul,__finc,__fdec
            EXPORT __fdec2f,__fxint
    INCLUDE fpcore.asm
            ENDSECT
;------------------------------------------------------------------------------
; End of float.asm
;------------------------------------------------------------------------------
