* libt.a: getd, which nothing needs (so it isn't linked)
        EXPORT  getd
        SECTION code
getd    LDB     #2
        RTS
        ENDSECT
