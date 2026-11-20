* Files: text and binary, fprintf/fputs/fputc, fgets, fread/fwrite,
* fseek/ftell, feof, append, a file that isn't there, rename, remove
        INCLUDE calls.d
        IMPORT  _fopen,_fclose,_fputs,_fputc,_fgets,_fgetc,_fread,_fwrite
        IMPORT  _fseek,_ftell,_feof,_rename,_remove
        EXPORT  _main
OPEN    MACRO                           ; fopen(\1, \2) -> f
        ARG     \2
        ARG     \1
        CALL    _fopen,4
        STD     f
        ENDM
CLOSE   MACRO
        LDD     f
        PSHS    D
        CALL    _fclose,2
        ENDM
        SECTION code
_main   OPEN    n_t,m_w                 a text file
        ARG     1
        ARG     f_line
        LDD     f
        PSHS    D
        CALL    _fprintf,6
        LDD     f
        PSHS    D
        ARG     s_two
        CALL    _fputs,4
        LDD     f
        PSHS    D
        ARG     '3'
        CALL    _fputc,4
        LDD     f
        PSHS    D
        ARG     10
        CALL    _fputc,4
        CLOSE
        OPEN    n_t,m_r                 read back a line at a time
LINES   LDD     f
        PSHS    D
        ARG     40
        ARG     buf
        CALL    _fgets,6
        CMPD    #0
        BEQ     LINES_END
        ARG     buf
        ARG     f_br
        CALL    _printf,4
        BRA     LINES
LINES_END LDD   f
        PSHS    D
        CALL    _feof,2
        PRINTD  f_d                     32 (FF_EOF)
        CLOSE
        OPEN    n_t,m_rb                binary: the CR LFs are there
        LDD     f
        PSHS    D
        ARG     40
        ARG     1
        ARG     buf
        CALL    _fread,8
        PRINTD  f_d                     16
        ARG     0                       fseek(f, 5, SEEK_SET), fgetc, ftell
        ARGL    0,5
        LDD     f
        PSHS    D
        CALL    _fseek,8
        PRINTD  f_d                     0
        LDD     f
        PSHS    D
        CALL    _fgetc,2
        PRINTD  f_d                     49 ('1')
        LDD     f
        PSHS    D
        CALL    _ftell,2
        PSHSW
        PSHS    D
        ARG     f_ld
        CALL    _printf,6               6
        CLOSE
        OPEN    n_b,m_wb                fwrite: 3 items of 2
        LDD     f
        PSHS    D
        ARG     3
        ARG     2
        ARG     bin
        CALL    _fwrite,8
        PRINTD  f_d                     3
        CLOSE
        OPEN    n_none,m_r              no such file: NULL
        LDD     f
        PRINTD  f_d                     0
        OPEN    n_a,m_a                 appended to, twice
        LDD     f
        PSHS    D
        ARG     s_x
        CALL    _fputs,4
        CLOSE
        OPEN    n_a,m_a
        LDD     f
        PSHS    D
        ARG     s_y
        CALL    _fputs,4
        CLOSE
        ARG     n_u                     T.TXT renamed U.TXT, A.TXT removed
        ARG     n_t
        CALL    _rename,4
        PRINTD  f_d                     0
        ARG     n_a
        CALL    _remove,2
        PRINTD  f_d                     0
        ARG     n_a
        CALL    _remove,2
        PRINTD  f_d                     -1
        CLRD
        RTS
        ENDSECT
        SECTION rodata
f_d     FCC     "%d"
        FCB     10,0
f_ld    FCC     "%ld"
        FCB     10,0
f_line  FCC     "line %d"
        FCB     10,0
f_br    FCN     "[%s]"
s_two   FCC     "two"
        FCB     10,0
s_x     FCN     "x"
s_y     FCN     "y"
n_t     FCN     "T.TXT"
n_u     FCN     "U.TXT"
n_b     FCN     "B.BIN"
n_a     FCN     "A.TXT"
n_none  FCN     "NONE.TXT"
m_w     FCN     "w"
m_r     FCN     "r"
m_rb    FCN     "rb"
m_wb    FCN     "wb"
m_a     FCN     "a"
bin     FCB     1,2,10,13,0,255
        ENDSECT
        SECTION bss
f       RMB     2
buf     RMB     40
        ENDSECT
