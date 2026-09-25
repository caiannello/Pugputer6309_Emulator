* GREET.ASM -- a first program for PUGASM, the Pugputer's own assembler.
*
*   PUGASM -f com greet.asm        makes GREET.COM
*   GREET Ada                      prints "Hello, Ada!"
*
* A program is a file with an 8-byte header (PUGASM's "com" format writes it);
* the shell loads it and jumps to its entry point (END's operand). Everything
* else goes through the BIOS: SWI2 with a function number in A.

F_STDOUT        EQU     $01             ; the console (bios/defines.d)
B_PUTS          EQU     $0A             ; print the string at X to file B
B_ARGS          EQU     $2A             ; -> X: what was typed after the name
B_EXIT          EQU     $2B             ; back to the shell

* A macro: print the string at X.
print           MACRO
                LDB     #F_STDOUT
                LDA     #B_PUTS
                SWI2
                ENDM

                ORG     $4000
start           LDX     #hello
                print
                LDA     #B_ARGS         ; a name after the command?
                SWI2
                TST     ,X
                BNE     named
                LDX     #world          ; no: the world, then
named           print
                LDX     #bang
                print
                LDA     #B_EXIT
                SWI2

hello           FCN     "Hello, "
world           FCN     "world"
bang            FCB     '!',13,10,0

                END     start
