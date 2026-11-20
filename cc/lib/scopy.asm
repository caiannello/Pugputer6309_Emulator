;------------------------------------------------------------------------------
; scopy.asm -- the compiler's helper for copying a struct.
;
;   JSR __scopy / FDB size: X = where to, D = where from -> D = where to.
;   It keeps X, Y and U.
;------------------------------------------------------------------------------
            SECTION code
            EXPORT __scopy
__scopy     PSHS X,Y                   ; (4,S: the return, at the size)
            LDY  4,S
            LDW  ,Y++
            STY  4,S
            TFR  X,Y
            TFR  D,X
            TFM  X+,Y+
            PULS X,Y
            TFR  X,D
            RTS
;------------------------------------------------------------------------------
; End of scopy.asm
;------------------------------------------------------------------------------
