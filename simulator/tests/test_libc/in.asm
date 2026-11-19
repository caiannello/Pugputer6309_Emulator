* stdin: lines typed (echoed, Backspace taking one back), then Ctrl-D
        INCLUDE calls.d
        IMPORT  _fgets,_getchar,__iob
        EXPORT  _main
        SECTION code
_main   ARG     __iob                   fgets(buf, 40, stdin)
        ARG     40
        ARG     buf
        CALL    _fgets,6
        ARG     buf
        ARG     f_s
        CALL    _printf,4
        CALL    _getchar,0              a character at a time, to the end
EACH    CMPD    #-1
        BEQ     DONE
        PRINTD  f_c
        CALL    _getchar,0
        BRA     EACH
DONE    ARG     f_end
        CALL    _printf,2
        CLRD
        RTS
        ENDSECT
        SECTION rodata
f_s     FCN     "<%s>"
f_c     FCN     "(%d)"
f_end   FCN     "EOF"
        ENDSECT
        SECTION bss
buf     RMB     40
        ENDSECT
