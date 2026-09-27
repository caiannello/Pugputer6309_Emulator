* object-file features, compared with lwasm
ext1    IMPORT
ext2    EXTERN
        IMPORT  ext3,ext4
        EXTERNAL ext5
        EXPORT  start,data1
done    EXPORT
cnst    EQU     $1234
        SECTION code
start   LDX     #data1
        LDD     ext1
        LDD     ext1+2
        LDA     <ext2
        LDB     #ext3
        LDB     #ext3+1
        LEAX    ext4,PCR
        LEAX    start,PCR
        LEAX    later,PCR
        LBSR    ext5
        LBRA    later
        BSR     start
        JSR     ext1-2
        STX     data2+4,Y
        LDD     ext1,X
        FDB     ext1,ext2-1,data1,*,start-data1,2*data1,later-start
        FCB     ext3,later-start
        LDA     #cnst&$FF
loc@    BRA     loc@
        FDB     loc@
        RMB     3
        FILL    $AA,2
later   RTS
done    RTS
here    EQU     *
rel2    EQU     data1+10
rel3    EQU     ext1+5
        FDB     here,rel2,rel3
        ENDSECT
        SECTION bss
data1   RMB     10
        FILL    1,4
        ALIGN   8
data2   RMB     2
        ENDSECTION
        SECT    data,bss
dd      RMB     5
        ENDSECT
        SECTION code
more    NOP
        LDX     #dd
        ENDSECTION
        SECTION _constants
k1      RMB     4
k2      RMB     2
        ENDSECT
        SECTION tab,!bss
t1      FCB     1,2
cnt     SET     1
cnt     SET     cnt+1
        FCB     cnt
        ENDSECTION
