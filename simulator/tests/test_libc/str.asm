* <string.h>, <ctype.h>, atoi, abs, rand: each result printed
        INCLUDE calls.d
        IMPORT  _strlen,_strcpy,_strcat,_strcmp,_strncmp,_strncpy
        IMPORT  _strchr,_strrchr,_strstr,_memmove,_memset,_memcmp,_memcpy
        IMPORT  _atoi,_abs,_srand,_rand
        IMPORT  _isalpha,_isdigit,_isspace,_isupper,_isxdigit,_isprint
        IMPORT  _ispunct,_toupper,_tolower
        EXPORT  _main
* \1(\2) or \1(\2, \3) ...: printed with f_d
P1      MACRO
        ARG     \2
        CALL    \1,2
        PRINTD  f_d
        ENDM
P2      MACRO
        ARG     \3
        ARG     \2
        CALL    \1,4
        PRINTD  f_d
        ENDM
P3      MACRO
        ARG     \4
        ARG     \3
        ARG     \2
        CALL    \1,6
        PRINTD  f_d
        ENDM
        SECTION code
_main   P1      _strlen,s_hello                 5
        ARG     s_abc
        ARG     buf
        CALL    _strcpy,4
        ARG     s_def
        ARG     buf
        CALL    _strcat,4
        PSHS    D
        CALL    _puts,2                         abcdef
        P2      _strcmp,s_abc,s_abd             -1
        P2      _strcmp,s_b,s_a                 1
        P2      _strcmp,s_abc,s_abc             0
        P2      _strcmp,s_ab,s_abc              -99
        P3      _strncmp,s_abcx,s_abcy,3        0
        ARG     8                               strncpy's padding
        ARG     $FF
        ARG     buf2
        CALL    _memset,6
        ARG     5
        ARG     s_hi
        ARG     buf2
        CALL    _strncpy,6
        P3      _memcmp,buf2,s_hipad,5          0
        LDB     buf2+5
        CLRA
        PRINTD  f_d                             255 (not touched)
        ARG     'l'
        ARG     s_hello
        CALL    _strchr,4
        SUBD    #s_hello
        PRINTD  f_d                             2
        ARG     'l'
        ARG     s_hello
        CALL    _strrchr,4
        SUBD    #s_hello
        PRINTD  f_d                             3
        P2      _strchr,s_hello,'z'             0
        ARG     s_wor
        ARG     s_hw
        CALL    _strstr,4
        SUBD    #s_hw
        PRINTD  f_d                             6
        P2      _strstr,s_hw,s_xyz              0
        ARG     10                              memmove, both ways
        ARG     s_digits
        ARG     buf
        CALL    _memcpy,6
        ARG     5
        ARG     buf
        ARG     buf+2
        CALL    _memmove,6
        ARG     buf
        CALL    _puts,2                         121234589
        ARG     5
        ARG     buf+3
        ARG     buf
        CALL    _memmove,6
        ARG     buf
        CALL    _puts,2                         23458234589
        ARG     3
        ARG     'z'
        ARG     buf
        CALL    _memset,6
        ARG     buf
        CALL    _puts,2                         zzz58234589
        P1      _atoi,s_num1                    -1234
        P1      _atoi,s_num2                    77
        P1      _abs,-5                         5
        P1      _isalpha,'a'                    2
        P1      _isdigit,'5'                    4
        P1      _isspace,9                      8
        P1      _isupper,'a'                    0
        P1      _isxdigit,'F'                   64
        P1      _isprint,32                     128 (the space)
        P1      _isprint,9                      0
        P1      _ispunct,'!'                    16
        P1      _isalpha,-1                     0
        P1      _toupper,'q'                    81
        P1      _tolower,'Q'                    113
        P1      _toupper,'1'                    49
        ARG     1
        CALL    _srand,2
        CALL    _rand,0
        PRINTD  f_d                             385
        CALL    _rand,0
        PRINTD  f_d                             24609
        CALL    _rand,0
        PRINTD  f_d                             27033
        CLRD
        RTS
        ENDSECT
        SECTION rodata
f_d     FCC     "%d"
        FCB     10,0
s_hello FCN     "hello"
s_abc   FCN     "abc"
s_abd   FCN     "abd"
s_def   FCN     "def"
s_a     FCN     "a"
s_b     FCN     "b"
s_ab    FCN     "ab"
s_abcx  FCN     "abcx"
s_abcy  FCN     "abcy"
s_hi    FCN     "hi"
s_hipad FCB     'h','i',0,0,0
s_hw    FCN     "hello world"
s_wor   FCN     "wor"
s_xyz   FCN     "xyz"
s_digits FCN    "123456789"
s_num1  FCN     "  -1234x"
s_num2  FCN     "+77"
        ENDSECT
        SECTION bss
buf     RMB     40
buf2    RMB     8
        ENDSECT
