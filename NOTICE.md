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

## Nuke.YKT -- Nuked OPL3

The emulator's YMF262 (OPL3) music chip sounds through **Nuked OPL3** by **Nuke.YKT**
(<https://github.com/nukeykt/Nuked-OPL3>), a cycle-accurate emulation of the chip built from
its decapped die. It is included, unmodified, in `simulator/third_party/nuked-opl3`, under the
**GNU Lesser General Public License, version 2.1 or later** (the `LICENSE` file there); it is
compiled into the emulator programs, whose complete source -- this repository -- is available,
so you can change or replace it and rebuild them. Nuked OPL3 credits in turn the MAME team (the
rhythm section), carbon14 and opl3 of forums.submarine.org.uk (tremolo and phase), Matthew
Gambrell and Olli Niemitalo (the OPL2 ROMs) and John McMaster and digshadow of siliconpr0n.org
(the die photographs).

## Frederic Cambus -- Spleen

The video card's font (`vidcard/core/vc_font.c`) is made from **Spleen** 8x16, its code page 437
version, by **Frederic Cambus** (<https://github.com/fcambus/spleen>), under the BSD 2-Clause
license:

> Copyright (c) 2018-2024, Frederic Cambus
> All rights reserved.
>
> Redistribution and use in source and binary forms, with or without modification, are permitted
> provided that the following conditions are met:
>
> * Redistributions of source code must retain the above copyright notice, this list of
>   conditions and the following disclaimer.
> * Redistributions in binary form must reproduce the above copyright notice, this list of
>   conditions and the following disclaimer in the documentation and/or other materials provided
>   with the distribution.
>
> THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR
> IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND
> FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR
> CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
> CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
> SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
> THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
> OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
> POSSIBILITY OF SUCH DAMAGE.

## The music in the demos

`demo/programs/ASM/VGM` holds two VGM players by Craig Iannello, from the Pugputer 6309
hardware project, each with a song logged from a classic PC game's OPL music: LeChuck's theme,
by Michael Z. Land, from *The Secret of Monkey Island* (Lucasfilm Games, 1990), and "Death and
Funeral" from *Star Wars: X-Wing* (LucasArts, 1993). The music remains the property of its
composers and publishers; it is included, as a short demonstration of the hardware, in the same
spirit as the VGM archives it came from.

`demo/vgm` holds three short recordings that Craig Iannello's WAV2VGM turned into OPL3 register
writes, for `VGMPLAY` to play: John F. Kennedy speaking (`JFK.VGM`); HAL 9000, the computer of
*2001: A Space Odyssey* (MGM, 1968), voiced by Douglas Rain (`HAL9000.VGM`); and the "Wilhelm
scream", the stock sound effect first heard in *Distant Drums* (Warner Bros., 1951)
(`WILHELM.VGM`). The recordings remain the property of their owners; these few seconds of each,
remade by an FM synthesizer, are included as a demonstration of the hardware.

## Hardware and standards

- The **Hitachi HD6309** CPU (and Motorola MC6809 behind it), the **Rockwell R65C51** UART, the
  **Yamaha V9958** and **YMF262**, and the **WDC W65C22** VIA are the parts the Pugputer 6309 is
  built around; the emulator models the CPU, the UART and the YMF262 (the last through Nuked
  OPL3, above), and the memory map reserves addresses for the others.
- The video card is designed around the **Raspberry Pi RP2350** (on an **Olimex
  RP2350-PICO2-XXL** board) and its DVI output; its palette starts as **xterm**'s 256 colors.
- The disk format is **FAT16** (Microsoft's published file-system layout), 8.3 names, 512-byte
  sectors; images are raw and can be read with ordinary tools.
- The BASIC file statements follow the **GW-BASIC User's Guide** (sections 5.2 and 5.3) in spirit.

## The binary release

The Windows demo is built with Microsoft Visual C++ and links its C++ runtime **statically**,
so there are no runtime DLLs to ship. The Microsoft runtime libraries are redistributable under
the Visual Studio license terms. The program uses only Windows system libraries at run time
(winmm for sound, gdi32 and user32 for the video card's window). Both demos contain Nuked OPL3 (LGPL-2.1+, above); the Linux one plays its
sound through a separate player program (`aplay`, `pacat` or `pw-cat`) it doesn't include, and
shows the video card through `pugputer-video`, which uses the system's **SDL2** library (zlib
license; not included).

## Optional tools you may want

- **com0com** (virtual serial-port pairs) -- for the COM-port mode; not included.
- **SRecord** (`srec_cat`) -- optional, used only to make an Intel-hex copy of the BIOS for an
  EPROM programmer; not included.
