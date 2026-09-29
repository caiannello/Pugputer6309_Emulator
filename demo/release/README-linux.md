# Pugputer 6309 -- demo release (Linux x64)

This is a complete, self-contained demo of the **Pugputer 6309**, a homebrew computer built
around the Hitachi HD6309 CPU: an emulator running the real firmware -- BIOS, DOS, shell, a
nano-style text editor, an assembler and linker, and Microsoft-derived Extended BASIC -- from a virtual SD card. There is
nothing to install: `pugputer` is a statically linked x86-64 program that runs on any
reasonably recent Linux distribution, with no libraries to match.

## Quick start

1. Unpack this folder anywhere (a folder you can write to; the disk image lives here):

   ```
   tar xzf Pugputer6309-demo-*-linux-x64.tar.gz
   cd Pugputer6309-demo-*-linux-x64
   ```

2. Run **`./start-console.sh`** (or just `./pugputer`) in a terminal.
3. You get a prompt:

   ```
   Pugputer 6309 shell -- HELP lists the commands
   /> 
   ```

   Try `HELP`, `DIR`, `VER` and `MEM`.
4. Type **`BASIC`** and press Enter to start BASIC. You will see the `OK` prompt. BASIC starts
   in the disk's `/BASIC` directory, where the demo programs are.
5. Load and run a demo program:

   ```
   LOAD "HELLO"
   RUN
   LIST
   ```

6. Leave BASIC with **`SYSTEM`** (back to the shell). Press **Ctrl+\\** (Ctrl and backslash), or
   close the terminal, to stop the emulator. (Ctrl+C goes to the Pugputer, like any other key.)

Everything you `SAVE` is kept on `disk.img`. **`./reset-disk.sh`** puts the disk back the way it came.

## The demo programs

They are in the disk's `/BASIC` directory; `DIR /BASIC` at the shell prompt lists them.

| Program | Shows |
|---|---|
| `HELLO` | printing, `FOR`/`NEXT`, `MEM` |
| `PRIMES` | arrays: a sieve of Eratosthenes |
| `SINE` | `SIN` and `TAB` in a text plot |
| `MANDEL` | the Mandelbrot set in ASCII: nested loops, arithmetic, `MID$` (takes a while) |
| `SEQFILE` | sequential files: `OPEN`, `PRINT#`, `LINE INPUT#`, `EOF`, `KILL` |
| `RANDFILE` | random-access files: `FIELD`, `LSET`, `PUT`, `GET` |
| `ERRTRAP` | `ON ERROR GOTO`, `ERR`, `ERL`, `RESUME NEXT` |
| `COLORS` | the terminal's colors: `CLS`, `GOTOXY`, `LCOLOR` (256 colors), `HCOLOR` (24-bit), `RESET` |
| `VIDEO` | the video card: `SCREEN`, `PALETTE`, `LINE`, `CIRCLE`, `TRIANGLE`, `GPRINT`, `TPRINT`, sprites drawn with `IMAGE` and moved each `VSYNC` |

## Things to try

- **Shell:** `DIR`, `MD GAMES`, `CD GAMES`, `CD ..`, `CD /BASIC`, `COPY HELLO.BAS HI.BAS`,
  `TYPE HI.BAS`, `REN`, `DEL`, `RD`. A word that isn't a command runs a program: `BASIC` runs
  `BASIC.COM`, found in the current directory or else along the search path -- `PATH` shows it
  (`/CMD`, where all the programs are) and `PATH /CMD;/GAMES` changes it.
- **BASIC:** write your own: `10 PRINT "HI"`, `RUN`, `SAVE "MINE"`, then leave with `SYSTEM` and
  `DIR` to see `MINE.BAS`. `FILES`, `KILL`, `NAME`, `MKDIR` and `CHDIR` work from BASIC too.
  The differences from GW-BASIC are listed in the project's `basic309/README.md`.
- **BASIC has file I/O like GW-BASIC:** `OPEN "O",#1,"NOTES.TXT"` ... `PRINT #1,"..."` ... `CLOSE`.

## Using a serial port or another terminal program

The emulated serial port can be connected to something other than the terminal you started it
in:

- **A pseudo-terminal** (nothing to install): run **`./start-serial.sh`** and press Enter, or
  `./pugputer --com pty`. It prints the name of a new pseudo-terminal, such as `/dev/pts/3`;
  open that in a terminal program at **19200 baud, 8 data bits, no parity, 1 stop bit**:

  ```
  screen /dev/pts/3 19200
  picocom -b 19200 /dev/pts/3
  ```

  Output the Pugputer sends before you connect waits for you (up to a few kilobytes), so you
  see the boot messages and the prompt. Press Ctrl+C in the emulator's own terminal to stop it.
- **A real serial port** (a USB serial adapter, say): `./pugputer --com /dev/ttyUSB0`. You may
  need to be in the `dialout` group to open it.

The terminal program should send CR for Enter, and ^H (Ctrl+H) for Backspace if you want
Backspace in BASIC's line editor (the shell and the editor accept either). `./pugputer --help`
lists the options (`--bios` and `--disk` select other images).

## What is in this folder

| File | |
|---|---|
| `pugputer` | The emulator: HD6309 CPU, UART, SD card and banked RAM |
| `pugputer-video` | The video card's window (it needs the SDL2 library, `libsdl2-2.0-0`) |
| `pugbios.s19` | The BIOS ROM image (Motorola S-record) |
| `disk.img` | The virtual SD card (FAT16): `/CMD` (`SHELL.COM`, `EDIT.COM`, `ASM.COM`, `LINK.COM`, `HEXDUMP.COM`, `MOVE.COM`, `BASIC.COM`), `/BASIC` (the BASIC demos) and `/ASM` (`GREET.ASM`, the demos' sources in `/ASM/VGM` and `/ASM/VIDEO`, and the sources of every program in `/CMD`) and `/DEMO` (the music and video card demos, ready to run) |
| `disk-original.img` | A pristine copy of the disk, used by `reset-disk.sh` |
| `start-console.sh`, `start-serial.sh`, `reset-disk.sh` | Launchers |
| `LICENSE.txt`, `NOTICE.md` | MIT License, and credits (Microsoft, William Astle's lwtools, ...) |

You can also read `disk.img` with ordinary tools (it is a plain FAT16 image with no partition
table), for instance `mdir -i disk.img ::` and `mcopy -i disk.img ::BASIC/HELLO.BAS .` from mtools,
or `sudo mount -o loop disk.img /mnt`, to copy your BASIC programs out or in.

## The text editor

**`EDIT NAME.TXT`** at the shell prompt opens a file (or starts a new one) in a full-screen editor
that works like GNU nano: the keys are listed at the bottom of the screen (`^` is Ctrl, `M-` is
Alt, or Esc then the key). `^O` writes the file, `^X` exits, `^G` shows all the keys. Try
`EDIT /BASIC/HELLO.BAS`, change it, write it out, then `LOAD` and `RUN` it in BASIC.

## The assembler

**`ASM`** assembles 6309/6809 source on the Pugputer itself (it speaks the same language as
lwasm, the assembler the whole system is built with). Try the demo:

```
CD /ASM
ASM -f com greet.asm
GREET Ada
```

`EDIT GREET.ASM` shows how it works; `ASM` alone lists the options (`-l` makes a listing).
**`LINK`** links object files (`ASM -f obj`) into a program, as lwlink does.

`/ASM` also holds the sources of every program in `/CMD` -- the shell, the editor, BASIC,
`HEXDUMP`, `MOVE`, and ASM and LINK themselves (in `/ASM/ASMLINK`) -- so you can change them and
rebuild them on the Pugputer. `TYPE /ASM/README.TXT` lists the commands. For instance:

```
CD /ASM
ASM -o HEXDUMP.COM hexdump.asm
```

makes `HEXDUMP.COM` there, which runs in place of `/CMD/HEXDUMP.COM` while `/ASM` is the
current directory; `COPY HEXDUMP.COM /CMD` makes it the one everywhere.

## Music

The emulator plays the Pugputer's music card, a Yamaha **YMF262 (OPL3)**, through your PC's
sound. `/ASM/VGM` holds two songs from classic PC games, as programs that drive the chip:

```
CD /ASM/VGM
ASM -f com vgmonkey.asm
VGMONKEY
```

plays LeChuck's theme from *The Secret of Monkey Island*; `VGXWINGF.ASM` is from *Star Wars:
X-Wing*. Both are also ready to run in `/DEMO`: `/DEMO/VGMONKEY`, `/DEMO/VGXWINGF`. Ctrl-C
stops a song. While music plays, the emulator runs at the real machine's speed
(3.58 MHz), so songs keep their tempo; the rest of the time it runs flat out.
The sound goes out through `aplay` (ALSA), or `pacat` (PulseAudio) or `pw-cat` (PipeWire),
whichever is installed -- Ubuntu has `aplay` already (package `alsa-utils`). With none of them,
the emulator says so at start-up and runs without sound. `./pugputer --no-sound` keeps the chip
quiet.

## The video card

The emulator has the Pugputer's video card too: 640x480 in 256 colors (from 65536), with three
layers of text, tiles or bitmaps, 128 sprites and drawing commands the card carries out itself.
Its picture opens in a window the first time a program uses the card; the console stays
where it is, in the terminal. Keys typed into the window go to the Pugputer as well.

| Program | Shows |
|---|---|
| `/DEMO/VIDDEMO` | all at once: a bitmap drawn with commands, a scrolling row of tiles, text, bouncing sprites |
| `/DEMO/VIDTEXT` | text: the 256 characters and 256 colors, a 320x240 marquee over them; then an 8x8 font made from the card's own, 80x60 cells scrolling under a heading that stays put |
| `/DEMO/VIDTILES` | tiles and sprites: three layers scrolling at their own speeds (8x8 and 16x16 tiles, 2 and 8 bits a pixel, flipped, in palettes of their own), sprites of every size between and in front of them; then 128 sprites at 640x480, and the 32-a-line limit |
| `/DEMO/VIDGFX` | bitmaps and drawing: every drawing command at 640x480 in 16 colors, palette cycling; then bitmaps of 8, 2 and 1 bits a pixel, bars of color set by a line interrupt, an animation drawn in the PSRAM |
| `/BASIC/VIDEO.BAS` | the same from BASIC: `SCREEN`, `LINE`, `CIRCLE`, `SPRITE` and the rest |

A key moves a demo on to its next page, and after its last page back to the shell. Their sources
are in `/ASM/VIDEO`, with the card's registers in `/ASM/VIDEO/VIDCARD.D` and the card described
in `/ASM/VIDEO/VIDCARD.TXT`.

While the window is open, the emulator runs at the real machine's speed (60 frames a second);
`./pugputer --turbo` lets it run flat out, `--scale 2` doubles the window, and `--no-video` does
without it. The window is `pugputer-video`, beside `pugputer`; it needs the SDL2 library
(`sudo apt install libsdl2-2.0-0` if it isn't there already). Without it, or without a display,
the emulator says so and goes on without the window.

## Other commands

**`HEXDUMP file`** shows a file as hex and ASCII, 16 bytes a line (Ctrl-C stops it).
**`MOVE from [to]`** moves a file to another directory or renames it; `COPY from [to]` copies
one. For both, a `to` that is a directory keeps the file's name, and no `to` at all means the
current directory.

## Good to know

- The emulator has no graphics yet -- the Pugputer's console is a serial terminal.
- It runs as fast as your PC allows (much faster than the real machine), except while music
  plays; it uses a full CPU core while it is running.
- The keyboard: your terminal is used as the Pugputer's ANSI terminal, so arrows, Home/End,
  PgUp/PgDn, Delete, F-keys and Alt+key reach the Pugputer as the terminal sends them.
  Backspace is sent as ^H, which is what BASIC expects. BASIC's own line editor cannot type
  `|`, `{`, `}` or `~`.

## About the project

The Pugputer 6309 is open source: firmware, emulator and test suite are all in one repository,
with a much longer README describing the design, how to build everything from source, and where
the project is going (a graphics peripheral, and testing
on the real hardware). It's at
<https://github.com/YOUR-GITHUB-NAME/Pugputer6309_Experiments>.

Licensed under the MIT License. BASIC descends from Microsoft's Extended Color BASIC; see
`NOTICE.md`.
