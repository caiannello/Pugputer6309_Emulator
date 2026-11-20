* malloc, free (a block used again, free blocks joined), calloc, realloc
        INCLUDE calls.d
        IMPORT  _malloc,_free,_calloc,_realloc,_memset,_strcpy,_strcmp
        EXPORT  _main
        SECTION code
_main   ARG     10
        CALL    _malloc,2
        STD     p1
        ARG     20
        CALL    _malloc,2
        STD     p2
        ARG     30
        CALL    _malloc,2
        STD     p3
        LDD     p2                      p2 - p1: 12 (10, the header, even)
        SUBD    p1
        PRINTD  f_d
        LDD     p3                      p3 - p2: 22
        SUBD    p2
        PRINTD  f_d
        LDD     p2                      p2's block used again (split)
        PSHS    D
        CALL    _free,2
        ARG     16
        CALL    _malloc,2
        STD     p4
        CMPD    p2
        LBSR    SAME
        LDD     p1                      p1 and p4 (and the rest) joined
        PSHS    D
        CALL    _free,2
        LDD     p4
        PSHS    D
        CALL    _free,2
        ARG     30
        CALL    _malloc,2
        STD     p5
        CMPD    p1
        LBSR    SAME
        ARG     30                      dirtied, freed: calloc's is clean
        ARG     $AA
        LDD     p5
        PSHS    D
        CALL    _memset,6
        LDD     p5
        PSHS    D
        CALL    _free,2
        ARG     4
        ARG     5
        CALL    _calloc,4
        STD     p5
        CMPD    p1
        LBSR    SAME
        LDX     p5
        LDB     #20
        CLRA
SUM     ORA     ,X+
        DECB
        BNE     SUM
        TFR     A,B
        CLRA
        PRINTD  f_d                     0
        ARG     s_text                  realloc: moved, the text kept
        LDD     p3
        PSHS    D
        CALL    _strcpy,4
        ARG     100
        LDD     p3
        PSHS    D
        CALL    _realloc,4
        STD     p6
        CMPD    p3
        LBSR    SAME                    0 (it moved)
        ARG     s_text
        LDD     p6
        PSHS    D
        CALL    _strcmp,4
        PRINTD  f_d                     0
        ARG     60000                   too big: NULL
        CALL    _malloc,2
        PRINTD  f_d
        CLRD
        RTS
* "1" if Z is set, else "0"
SAME    BEQ     SA_YES
        CLRD
        BRA     SA_OUT
SA_YES  LDD     #1
SA_OUT  PRINTD  f_d
        RTS
        ENDSECT
        SECTION rodata
f_d     FCC     "%d"
        FCB     10,0
s_text  FCN     "kept through realloc"
        ENDSECT
        SECTION bss
p1      RMB     2
p2      RMB     2
p3      RMB     2
p4      RMB     2
p5      RMB     2
p6      RMB     2
        ENDSECT
