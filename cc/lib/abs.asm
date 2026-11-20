;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 C library
;    FILE: abs.asm -- int abs(int n), long labs(long n)
;------------------------------------------------------------------------------
            EXPORT _abs,_labs
            SECTION code
_abs        LDD  2,S
            BPL  AB_RET
            NEGD
AB_RET      RTS
_labs       LDQ  2,S
            TSTA
            BPL  LA_RET
            COMD
            COMW
            ADDW #1
            ADCD #0
LA_RET      RTS
            ENDSECT
