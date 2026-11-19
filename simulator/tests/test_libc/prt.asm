* printf's conversions, sprintf, and what they return
        INCLUDE calls.d
        EXPORT  _main
        SECTION code
_main   ARG     8
        ARG     $BEEF
        ARG     $BEEF
        ARG     65535
        ARG     456
        ARG     -123
        ARG     f1
        CALL    _printf,14
        ARG     'Q'
        ARG     s_xyz
        ARG     s_ab
        ARG     s_ab
        ARG     7
        ARG     -42
        ARG     42
        ARG     42
        ARG     f2
        CALL    _printf,18
        ARG     5
        ARGL    $1234,$5678
        ARGL    $EE6B,$2800
        ARGL    $FFFE,$7960
        ARG     f3
        CALL    _printf,16
        ARG     0
        ARG     $ABCD
        ARG     7
        ARG     99
        ARG     4
        ARG     99
        ARG     6
        ARG     f4
        CALL    _printf,16
        ARG     12
        ARG     s_x
        ARG     f5
        ARG     buf
        CALL    _sprintf,8
        PSHS    D
        ARG     buf
        CALL    _puts,2
        PULS    D
        PRINTD  f_d
        ARG     s_abc
        CALL    _printf,2
        PRINTD  f_d
        ARG     '!'
        CALL    _putchar,2
        PRINTD  f_d
        CLRD
        RTS
        ENDSECT
        SECTION rodata
f1      FCC     "%d|%i|%u|%x|%X|%o"
        FCB     10,0
f2      FCC     "[%5d][%-5d][%05d][%-05d][%5s][%-5s][%.2s][%c]"
        FCB     10,0
f3      FCC     "%ld %lu %lx %d%%"
        FCB     10,0
f4      FCC     "%*d|%-*d|%.3d|%p|%s"
        FCB     10,0
f5      FCN     "%s-%d"
f_d     FCC     "%d"
        FCB     10,0
s_ab    FCN     "ab"
s_xyz   FCN     "xyz"
s_x     FCN     "x"
s_abc   FCC     "abc"
        FCB     10,0
        ENDSECT
        SECTION bss
buf     RMB     40
        ENDSECT
