;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 C library
;    FILE: ctype.asm -- <ctype.h>: isalpha() ... toupper(), tolower()
;
; Each is* takes an int (EOF, or a character 0..255) and gives nonzero (the
; class's bit) if it is of that class, else 0. Only ASCII (0..127) is in any
; class. isprint's class includes the space, but not the other blank (tab).
;------------------------------------------------------------------------------
CT_U        equ  $01               ; upper case
CT_L        equ  $02               ; lower case
CT_D        equ  $04               ; digit
CT_S        equ  $08               ; space (space, tab, LF, VT, FF, CR)
CT_P        equ  $10               ; punctuation
CT_C        equ  $20               ; control
CT_X        equ  $40               ; a hex letter
CT_B        equ  $80               ; blank (space, tab)
            EXPORT _isupper,_islower,_isalpha,_isdigit,_isalnum,_isxdigit,_isspace,_ispunct,_iscntrl,_isgraph,_isprint,_isblank
            EXPORT _toupper,_tolower,__ctype
            SECTION code
_isupper    LDB  #CT_U
            BRA  CT_TEST
_islower    LDB  #CT_L
            BRA  CT_TEST
_isalpha    LDB  #CT_U|CT_L
            BRA  CT_TEST
_isdigit    LDB  #CT_D
            BRA  CT_TEST
_isalnum    LDB  #CT_U|CT_L|CT_D
            BRA  CT_TEST
_isxdigit   LDB  #CT_D|CT_X
            BRA  CT_TEST
_isspace    LDB  #CT_S
            BRA  CT_TEST
_ispunct    LDB  #CT_P
            BRA  CT_TEST
_iscntrl    LDB  #CT_C
            BRA  CT_TEST
_isgraph    LDB  #CT_U|CT_L|CT_D|CT_P
            BRA  CT_TEST
_isprint    LDD  2,S                   ; (the space, not the tab)
            CMPD #9
            BEQ  CT_NO
            LDB  #CT_U|CT_L|CT_D|CT_P|CT_B
            BRA  CT_TEST
_isblank    LDB  #CT_B
            BRA  CT_TEST
; B = the classes; the int at 3,S (B pushed): -> D = its bit(s), or 0.
CT_TEST     PSHS B
            LDD  3,S
            CMPD #127
            BHI  CT_NO1                ; (EOF and 128..255: none)
            LDX  #__ctype
            LDB  B,X
            ANDB ,S+
            CLRA
            RTS
CT_NO1      LEAS 1,S
CT_NO       CLRD
            RTS
; int toupper(int c), int tolower(int c)
_toupper    LDD  2,S
            CMPD #'a'
            BLT  TU_RET
            CMPD #'z'
            BGT  TU_RET
            SUBB #$20
TU_RET      RTS
_tolower    LDD  2,S
            CMPD #'A'
            BLT  TU_RET
            CMPD #'Z'
            BGT  TU_RET
            ADDB #$20
            RTS
            ENDSECT
            SECTION rodata
__ctype
            FCB  $20,$20,$20,$20,$20,$20,$20,$20,$20,$A8,$28,$28,$28,$28,$20,$20
            FCB  $20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20
            FCB  $88,$10,$10,$10,$10,$10,$10,$10,$10,$10,$10,$10,$10,$10,$10,$10
            FCB  $04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$10,$10,$10,$10,$10,$10
            FCB  $10,$41,$41,$41,$41,$41,$41,$01,$01,$01,$01,$01,$01,$01,$01,$01
            FCB  $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$10,$10,$10,$10,$10
            FCB  $10,$42,$42,$42,$42,$42,$42,$02,$02,$02,$02,$02,$02,$02,$02,$02
            FCB  $02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$10,$10,$10,$10,$20
            ENDSECT
;------------------------------------------------------------------------------
; End of ctype.asm
;------------------------------------------------------------------------------
