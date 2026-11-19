* test_libc.cpp's programs: C's calling convention by hand (until there's a
* compiler). ARG pushes a word; CALL calls and pops the arguments; PRINT1
* prints D (or a word) with a format.
ARG     MACRO
        LDD     #\1
        PSHS    D
        ENDM
ARGL    MACRO                   ; a long (\1 high word, \2 low): the high first
        LDD     #\2
        PSHS    D
        LDD     #\1
        PSHS    D
        ENDM
CALL    MACRO
        JSR     \1
        IFNE    \2
        LEAS    \2,S
        ENDC
        ENDM
* printf(\1, D)
PRINTD  MACRO
        PSHS    D
        ARG     \1
        CALL    _printf,4
        ENDM
        IMPORT  _printf,_puts,_putchar,_sprintf,_fprintf
