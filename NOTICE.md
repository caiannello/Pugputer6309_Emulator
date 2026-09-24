# Credits and third-party notices

This project is released under the MIT License (see `LICENSE`). It stands on other people's
work, gratefully acknowledged here.

## Microsoft -- Extended Color BASIC

`basic309/exbasrom309.asm` is a port of **Microsoft's Extended Color BASIC** for the 6809
(as found in the Tandy Color Computer; the original's copyright message reads "(C) 1982 BY
MICROSOFT"). Credit for the interpreter itself -- its parser, floating-point package, string
handling and most of what makes it BASIC -- belongs to Microsoft. The port changes its I/O
to go through this project's BIOS, moves its workspace, and adds file and directory
statements, error trapping and other extensions; those changes are covered by this project's
license. The original is understood to have been released into the public domain.

## William Astle -- lwtools

The BIOS, DOS, shell and BASIC are assembled with **lwtools** (`lwasm`, `lwlink`), the 6809/6309
cross-assembler and linker by **William Astle** (<https://www.lwtools.ca>), a much-loved tool
of the Color Computer community. lwtools is licensed under the GNU GPL v3 and is **not included
in this repository or in the binary release**; see "Building from source" in `README.md` for
where to get it. (Assembling with it does not make the assembled output GPL: the programs in
the release are this project's own code.)

The emulator's CPU core takes its opcode assignments and per-addressing-mode cycle counts
from lwtools' instruction and cycle tables (`lwasm/instab.c`, `lwasm/cycle.c`), which proved
more reliable than the OCR'd programming manual; those numbers are facts of the HD6309
instruction set, also documented in Hitachi's and Motorola's publications. The emulator's
golden tests assemble small programs with `lwasm` (skipped when it isn't installed).

## Hardware and standards

- The **Hitachi HD6309** CPU (and Motorola MC6809 behind it), the **Rockwell R65C51** UART, the
  **Yamaha V9958** and **YMF262**, and the **WDC W65C22** VIA are the parts the Pugputer 6309 is
  built around; the emulator models the CPU and UART, and the memory map reserves addresses for
  the others.
- The disk format is **FAT16** (Microsoft's published file-system layout), 8.3 names, 512-byte
  sectors; images are raw and can be read with ordinary tools.
- The BASIC file statements follow the **GW-BASIC User's Guide** (sections 5.2 and 5.3) in spirit.

## The binary release

The Windows demo is built with Microsoft Visual C++ and links its C++ runtime **statically**,
so there are no runtime DLLs to ship. The Microsoft runtime libraries are redistributable under
the Visual Studio license terms. The program uses only Windows system libraries at run time.

## Optional tools you may want

- **com0com** (virtual serial-port pairs) -- for the COM-port mode; not included.
- **SRecord** (`srec_cat`) -- optional, used only to make an Intel-hex copy of the BIOS for an
  EPROM programmer; not included.
