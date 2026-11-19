* libt.a: getb, some bss, and a second dupe (lc's comes first)
        EXPORT  getb,dupe
        SECTION code
getb    LDX     #bbuf
dupe    RTS
        ENDSECT
        SECTION bss
bbuf    RMB     4
        ENDSECT
