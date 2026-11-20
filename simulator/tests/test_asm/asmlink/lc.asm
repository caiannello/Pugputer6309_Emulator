* libt.a: getc, and the dupe the program gets
        EXPORT  getc,dupe
        SECTION code
getc    LDA     #1
        RTS
dupe    FCB     $DD
        ENDSECT
