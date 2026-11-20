;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 C library
;    FILE: memmove.asm -- void *memmove(void *d, const void *s, size_t n): the areas may overlap
;------------------------------------------------------------------------------
            EXPORT _memmove
            SECTION code
_memmove    PSHS Y
            LDY  4,S
            LDX  6,S
            LDW  8,S
            BEQ  MV_RET
            CMPY 6,S                   ; d below s: forwards
            BLS  MV_FWD
            LDD  8,S                   ; else from the ends, backwards
            DECD
            LEAX D,X
            LEAY D,Y
            TFM  X-,Y-
            BRA  MV_RET
MV_FWD      TFM  X+,Y+
MV_RET      LDD  4,S
            PULS Y,PC
            ENDSECT
