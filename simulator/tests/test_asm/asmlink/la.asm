* libt.a: geta, which needs getb (a later member) and back (the program's)
        EXPORT  geta
        IMPORT  getb,back
        SECTION code
geta    JSR     getb
        JMP     back
        ENDSECT
        SECTION .data
adat    FDB     geta
        ENDSECT
