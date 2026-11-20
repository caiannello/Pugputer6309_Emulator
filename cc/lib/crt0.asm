;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 C library
;    FILE: crt0.asm -- CRT0.O, the start of every C program
;
; In section init, which CC.SCR places first (at $3400, where the program
; loads): the stack at the top of the program's memory, bss cleared, the heap
; (sbrk's) after everything else, the command line split into argc/argv, then
; exit(main(argc, argv)).
;
; The start is two sections, init and init_end, and exit() two, fini and
; fini_end: CC.SCR places init_ovl and init_flt, and fini_ovl, between them,
; which are empty unless libc's farcall.asm (banked code) or fltio.asm (printf's
; and scanf's floats) is linked. Each falls through to the next. init_ovl gets
; B as DOS left it (a program with overlays: its file).
;
; __pfhook and __sfhook (data) are where printf and scanf find their float
; conversions: 0, unless fltio.asm's init_flt sets them.
;
; Arguments are separated by spaces; "double quotes" keep spaces in one.
; argv[0] is "" (DOS doesn't say what the program was called), and there are
; at most MAXARGS.
;------------------------------------------------------------------------------
    INCLUDE defines.d
    INCLUDE libc.d
MAXARGS     equ  16
ARGBUFSZ    equ  168               ; the tail (<= 80) with a NUL for each word
STACKTOP    equ  $F000             ; (the first push goes to $EFFF)
            EXPORT __start,_exit,__brk,__argc,__argv,__pfhook,__sfhook
            IMPORT _main
            IMPORT s_bss,l_bss,s_heap  ; (CC.SCR's synthetic symbols)
;------------------------------------------------------------------------------
            SECTION init
__start     LDS  #STACKTOP             ; (B: the file, for init_ovl)
            ENDSECT
            SECTION init_end
            LDX  #zero                 ; bss cleared
            LDY  #s_bss
            LDW  #l_bss
            TFM  X,Y+
            LDD  #s_heap               ; the heap starts after everything
            STD  __brk
            LDA  #B_ARGS               ; the command line -> argv
            SWI2
            LDY  #argbuf
            LDU  #__argv
            LDD  #zero                 ; argv[0] = ""
            STD  ,U++
AR_SKIP     LDA  ,X+
            BEQ  AR_END
            CMPA #' '
            BEQ  AR_SKIP
            CMPU #__argv+2*MAXARGS     ; (room for the NULL after)
            BHS  AR_END
            STY  ,U++                  ; a word
            CMPA #'"'
            BEQ  AR_QUOTE
AR_WORD     STA  ,Y+
            LDA  ,X+
            BEQ  AR_LAST
            CMPA #' '
            BNE  AR_WORD
            CLR  ,Y+
            BRA  AR_SKIP
AR_QUOTE    LDA  ,X+                   ; "...": to the next "
            BEQ  AR_LAST
            CMPA #'"'
            BEQ  AR_QEND
            STA  ,Y+
            BRA  AR_QUOTE
AR_QEND     CLR  ,Y+
            BRA  AR_SKIP
AR_LAST     CLR  ,Y+
AR_END      CLR  ,U                    ; argv[argc] = NULL
            CLR  1,U
            TFR  U,D
            SUBD #__argv
            LSRD
            STD  __argc
            LDX  #__argv               ; exit(main(argc, argv))
            PSHS X
            PSHS D
            JSR  _main
            LEAS 4,S
            PSHS D
            JSR  _exit
zero        FDB  0
            ENDSECT
; void exit(int status): the end of the program (DOS closes its files, which
; writes out what they hold). The status's low byte is the exit code, which a
; program that started this one with spawn() gets back. (fini_ovl comes
; between, and keeps S.)
            SECTION fini
_exit
            ENDSECT
            SECTION fini_end
            LDB  3,S
            LDA  #B_EXIT
            SWI2
            ENDSECT
;------------------------------------------------------------------------------
            SECTION data
__pfhook    FDB  0                     ; printf's %e %f %g (fltio.asm)
__sfhook    FDB  0                     ; scanf's %e %f %g
            ENDSECT
            SECTION bss
__brk       RMB  2                     ; the heap's end (sbrk)
__argc      RMB  2
__argv      RMB  2*(MAXARGS+1)
argbuf      RMB  ARGBUFSZ
            ENDSECT
;------------------------------------------------------------------------------
            SECTION heap               ; (empty: CC.SCR places it last)
            ENDSECT
;------------------------------------------------------------------------------
; End of crt0.asm
;------------------------------------------------------------------------------
