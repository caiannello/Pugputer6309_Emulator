;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 C library
;    FILE: strstr.asm -- char *strstr(const char *s, const char *t): where t first is in s, or NULL
;------------------------------------------------------------------------------
            EXPORT _strstr
            SECTION code
_strstr     PSHS Y,U
            LDU  6,S                   ; s, each place in turn
SS_START    LDX  8,S
            TFR  U,Y
SS_CMP      LDA  ,X+
            BEQ  SS_HIT                ; all of t matched
            CMPA ,Y+
            BEQ  SS_CMP
            TST  ,U+                   ; no: the next place (or the end)
            BNE  SS_START
            CLRD
            PULS Y,U,PC
SS_HIT      TFR  U,D
            PULS Y,U,PC
            ENDSECT
