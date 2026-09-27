* provides objf.asm's imports, in several kinds of section
        EXPORT  ext1,ext2,ext3,ext4,ext5,__start
        SECTION init
__start LDS     #$8000
        JMP     start
        ENDSECT
        SECTION code
ext1    RTS
ext4    FCB     1,2,3
        ENDSECT
        SECTION _constants
ext3    RMB     $12
ext2    RMB     1
        ENDSECT
        SECTION bss
ext5    RMB     20
        ENDSECT
        SECTION .data
dat     FDB     ext1,dat,done
        ENDSECT
start   IMPORT
done    IMPORT
