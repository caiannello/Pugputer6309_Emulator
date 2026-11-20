; CC's test: int twice(int x), in assembly, called from C.
            SECTION code
            EXPORT _twice
_twice      LDD  2,S
            LSLD
            RTS
            ENDSECT
