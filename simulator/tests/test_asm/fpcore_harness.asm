; test_float.cpp's harness: cc/lib/fpcore.asm (the library's floating point,
; which CC1 includes too) at $1000, behind a table of jumps the test calls,
; each returning to DONE (a breakpoint).
            ORG  $1000
            JMP  __fadd                ; $1000
            JMP  __fsub                ; $1003
            JMP  __fmul                ; $1006
            JMP  __fdiv                ; $1009
            JMP  __fcmp                ; $100C
            JMP  __ltof                ; $100F
            JMP  __ultof               ; $1012
            JMP  __ftol                ; $1015
            JMP  __ftoul               ; $1018
            JMP  __fdec2f              ; $101B
            JMP  __fxint               ; $101E
            JMP  __finc                ; $1021
            JMP  __fdec                ; $1024
DONE        NOP                        ; $1027
            INCLUDE fpcore.asm
