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
  VIDCARD.D    the video card's registers and commands (for your own programs)

  VGM/         two songs for the OPL3 music chip (ready to run in /DEMO):
                 ASM -f com vgmonkey.asm   then VGMONKEY
               and VGMPLAY, a player for VGM files (ready to run, with three
               to play, in /DEMO/VGMPLAY):
                 ASM -f com vgmplay.asm    then VGMPLAY file

  VIDEO/       the video card's demos (ready to run in /DEMO), VIDCARD.D again,
               VIDLIB.ASM (helpers they share) and the card described (VIDCARD.TXT):
                 ASM -f com viddemo.asm    then VIDDEMO   (everything at once)
                 ASM -f com vidtext.asm    then VIDTEXT   (text layers)
                 ASM -f com vidtiles.asm   then VIDTILES  (tiles and sprites)
                 ASM -f com vidgfx.asm     then VIDGFX    (bitmaps, commands, interrupts)
                 ASM -f com vidmouse.asm   then VIDMOUSE  (the mouse and keyboard)
                 ASM -f com vidpad.asm     then VIDPAD    (the gamepads)
                 ASM -f com padmap.asm     then PADMAP    (set up a gamepad's buttons;
                                                           also in /CMD, ready to run)
                 ASM -f com mandel.asm     then MANDEL    (the Mandelbrot set, with
                                                          the MC6839 floating-point ROM)
                 ASM -f com swamp.asm      then SWAMP     (parallax scrolling; its
                                                          pictures, SWAMP*.TLS and .MAP,
                                                          are in /DEMO, with its song,
                                                          SWAMP.SNG, which SONGKIT
                                                          opens; SK_PLAY.ASM, beside
                                                          it, plays it)

  GAMEKIT/     TILEKIT, the tile set editor (README.TXT there), SONGKIT, the
               music editor, and SONGPLAY, which plays a SONGKIT song with the
               player a game includes (SK_PLAY.ASM), and the files they include:
                 CD GAMEKIT
                 ASM -o TILEKIT.COM tilekit.asm
                 ASM -o SONGKIT.COM songkit.asm
                 ASM -o SONGPLAY.COM songplay.asm

  ASMLINK/     the assembler, the linker and the librarian:
                 CD ASMLINK
                 ASM -o ASM.COM asm.asm
                 ASM -o LINK.COM link.asm
                 ASM -o AR.COM ar.asm

  LIBC/        the C library (in /LIB: CRT0.O, LIBC.A, and CC.SCR, LINK's
               script for a C program). Each part is an object file of its
               own, so a program links only the ones it uses:
                 CD LIBC
                 ASM -f obj crt0.asm
                 ASM -f obj strlen.asm   (and so on: each file LIBC.RSP names)
                 AR @libc.rsp            (LIBC.A, from them)
               A program written in assembly can use it: its main is _main,
               called as C calls a function (see LIBC.D), and it is linked
               with
                 LINK -f com -o PROG.COM -s /lib/cc.scr -L /lib
                      /lib/crt0.o prog.o -lc

  CC/          the C compiler (in /CMD): CPP, the preprocessor, and CC1, the
               compiler proper (the headers are in /INCLUDE):
                 CD CC
                 ASM -o CPP.COM cpp.asm
                 ASM -o CC1.COM cc1.asm    (it takes a minute or so)
               A C program is compiled and linked with
                 CPP prog.c
                 CC1 prog.i
                 ASM -f obj prog.asm
                 LINK -f com -o PROG.COM -s /lib/cc.scr -L /lib
                      /lib/crt0.o prog.o -lc

These programs carry their own program header, so ASM's usual (raw) output,
named .COM, is the program. Add -l for a listing (-s adds the symbols).

To try a new one, run it from this directory: the current directory is
searched before /CMD. To keep it, copy it over the old one:

  COPY EDIT.COM /CMD

The shell is started from /CMD/SHELL.COM at boot and after every program, so
make sure a new shell works before you copy it there. If things go wrong,
reset-disk (see the README next to the emulator) puts the disk back as it came.
