;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 C library
;    FILE: abs.asm -- int abs(int n)
;------------------------------------------------------------------------------
            EXPORT _abs
            SECTION code
_abs        LDD  2,S
            BPL  AB_RET
            NEGD
AB_RET      RTS
            ENDSECT
