The sources of the programs in /CMD. ASM (and LINK) rebuild them here, on the
Pugputer, byte for byte as they were built.

  SHELL.ASM    the shell         ASM -o SHELL.COM shell.asm
  EDIT.ASM     the text editor   ASM -o EDIT.COM edit.asm
  HEXDUMP.ASM  HEXDUMP           ASM -o HEXDUMP.COM hexdump.asm
  MOVE.ASM     MOVE              ASM -o MOVE.COM move.asm
  BASIC.ASM    BASIC             ASM -o BASIC.COM basiccom.asm
                                 (BASICCOM.ASM includes BASIC.ASM; it takes
                                 a minute or two)
  DEFINES.D    the BIOS and DOS calls, included by the others

  ASMLINK/     the assembler and the linker:
                 CD ASMLINK
                 ASM -o ASM.COM asm.asm
                 ASM -o LINK.COM link.asm

These programs carry their own program header, so ASM's usual (raw) output,
named .COM, is the program. Add -l for a listing (-s adds the symbols).

To try a new one, run it from this directory: the current directory is
searched before /CMD. To keep it, copy it over the old one:

  COPY EDIT.COM /CMD

The shell is started from /CMD/SHELL.COM at boot and after every program, so
make sure a new shell works before you copy it there. If things go wrong,
reset-disk (see the README next to the emulator) puts the disk back as it came.
