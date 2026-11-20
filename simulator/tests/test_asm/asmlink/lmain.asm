* LINK's libraries (test_asmlink.cpp): the program, linked with -lt (libt.a:
* ld, lc, la, lk, lb, in that order) and -lx (libx.a, which it doesn't need)
        EXPORT  __start,back
        IMPORT  geta,getc,kval,dupe
        SECTION init
__start LDS     #$8000
        JSR     geta
        JSR     getc
        LDD     #kval
        LDX     #dupe
back    RTS
        ENDSECT
        SECTION code
mainc   FDB     geta,getc
        ENDSECT
