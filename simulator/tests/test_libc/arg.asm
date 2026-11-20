* argc and argv, from the command line
        INCLUDE calls.d
        EXPORT  _main
        SECTION code
_main   PSHS    Y
        LDD     4,S                     argc
        PRINTD  f_d
        LDY     6,S                     each argv[i], to the NULL
EACH    LDD     ,Y++
        BEQ     DONE
        PSHS    D
        ARG     f_s
        CALL    _printf,4
        BRA     EACH
DONE    ARG     10
        CALL    _putchar,2
        LDD     #0
        PULS    Y,PC
        ENDSECT
        SECTION rodata
f_d     FCN     "%d"
f_s     FCN     " [%s]"
        ENDSECT
