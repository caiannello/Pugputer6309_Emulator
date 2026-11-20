;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 C library
;    FILE: fmath.d -- what math.h's modules share (INCLUDEd after libc.d)
;
; They work in Q with fpcore's helpers (__fadd __fsub __fmul __fdiv __fcmp:
; Q = Q op the float pushed), and a frame at U: a function's locals are at
; 0,U and up, its arguments after them (and the saved U and the return).
; These keep Y and U; X is used for the operand.
;------------------------------------------------------------------------------
; FK op,label: Q = Q op the float at label.
FK          MACRO
            LDX  \2+2
            PSHS X
            LDX  \2
            PSHS X
            JSR  \1
            LEAS 4,S
            ENDM
; FV op,n: Q = Q op the float at n,U.
FV          MACRO
            LDX  \2+2,U
            PSHS X
            LDX  \2,U
            PSHS X
            JSR  \1
            LEAS 4,S
            ENDM
; FLD label: Q = the float at label.
FLD         MACRO
            LDD  \1
            LDW  \1+2
            ENDM
; FPUSH: Q pushed (an argument, high word first).
FPUSH       MACRO
            PSHSW
            PSHS D
            ENDM
; FPOLY table: Q = the polynomial at table (__fpoly's) of Q.
FPOLY       MACRO
            LDX  #\1
            JSR  __fpoly
            ENDM
;------------------------------------------------------------------------------
; End of fmath.d
;------------------------------------------------------------------------------
