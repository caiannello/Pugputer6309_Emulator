* BASICCOM.ASM -- BASIC.ASM as a program file:
*
*   ASM -o BASIC.COM basiccom.asm
*
* With COMFILE defined, BASIC.ASM puts BASIC.COM's program header in front and
* leaves out what isn't in BASIC.COM (the vectors at the top of memory). On its
* own, BASIC.ASM makes S-records: ASM -f srec basic.asm
COMFILE     EQU  1
            INCLUDE basic.asm
