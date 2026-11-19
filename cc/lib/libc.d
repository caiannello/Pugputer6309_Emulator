;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 C library
;    FILE: libc.d -- what the library's modules share (INCLUDEd after defines.d)
;
; The calling convention (cc/DESIGN.md): C's names get a leading underscore.
; Arguments are pushed right to left, each a whole number of 16-bit words (char
; widened to 2 bytes, long 4, high word first); the caller pops them. So on
; entry to a function that hasn't pushed anything, its first argument is at 2,S.
; char comes back in B (D the widened value), int and pointers in D, long in Q
; (D the high word, W the low). A function keeps U, Y, S and DP; D, W, X and CC
; are scratch.
;------------------------------------------------------------------------------
; A FILE (__iob[n]: stdin, stdout, stderr, then the files fopen opens)
FL_FLAGS    equ  0
FL_HANDLE   equ  1                 ; a DOS handle, or a device (F_STDIN ...)
FL_UNGOT    equ  2                 ; ungetc's character (FF_UNGOT)
FL_SIZE     equ  4
NFILE       equ  3+DOS_NFILES
; FL_FLAGS
FF_USED     equ  $01
FF_READ     equ  $02
FF_WRITE    equ  $04
FF_CON      equ  $08               ; a console device, not a DOS file
FF_TEXT     equ  $10               ; '\n' is CR LF on the way out, CR or CR LF in
FF_EOF      equ  $20
FF_ERR      equ  $40
FF_UNGOT    equ  $80
; C's values
EOF         equ  -1
NULL        equ  0
; stdin is __iob, stdout __iob+FL_SIZE, stderr __iob+2*FL_SIZE
