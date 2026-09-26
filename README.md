# Pugputer 6309 Simulator

A homebrew computer built around the Hitachi **HD6309** CPU, with its complete software stack --
BIOS, DOS, shell, a text editor, an assembler and linker, and BASIC -- and a cycle-counted emulator that runs all of
it on a PC.

![Demo Running in Tera Term](https://github.com/caiannello/Pugputer6309_Emulator/blob/main/demo.png?raw=true)

**Just want to try it?** Download the demo for Windows or Linux from the *Releases* page.
On Windows, unzip it and double-click `start-console.bat`; on Linux, unpack the `.tar.gz` and
run `./start-console.sh` in a terminal. Nothing to install or compile; see the release's `README.md`.

## Future plans
- Emulated Graphical display and OPL3 Sound

## Real Hardware Here!
[Pugputer6309 on GitHub](https://github.com/caiannello/Pugputer6309)

## What is in here

| Folder | What it is |
|---|---|
| `bios/` | The 4KB boot ROM: reset, an interrupt-driven UART driver, an SD block driver, RAM-bank management, and the `SWI2` system-call interface everything else uses. |
| `dos/` | The resident DOS: a FAT16 file system (8.3 names, subdirectories, 32-bit file sizes and block numbers, a FAT cache, crash-safe write ordering) and the program loader. |
| `shell/` | `SHELL.COM`, the command interpreter: `DIR`, `CD`, `COPY`, `TYPE`, ... and running programs. |
| `edit/` | `EDIT.COM`, a full-screen text editor for an ANSI terminal, modelled on GNU nano. |
| `pugasm/` | `PUGASM.COM` and `PUGLINK.COM`, an assembler and a linker that run on the Pugputer and produce the same code, listings, object files, S-records and maps as lwasm and lwlink -- together they build this whole project, the BIOS and themselves included. |
| `basic309/` | **basic309**, Microsoft's Extended Color BASIC ported to run on this system, with GW-BASIC-style sequential and random-access files, directories, and `ON ERROR`/`RESUME`. |
| `simulator/` | The HD6309 CPU core, the system bus and device models (UART, SD card, RAM banking), the emulator programs, and the test suite. |
| `demo/` | The sample BASIC programs and launcher scripts that go into the binary release. |

Every folder has its own `README.md` with the details.

![Nano-like text editor](https://github.com/caiannello/Pugputer6309_Emulator/blob/main/nano.png?raw=true)

## The machine

| Address | |
|---|---|
| `$0000-$3FFF` | RAM bank 0 -- always physical page 0: BIOS variables and stack (to `$052F`), then the resident DOS (`$0600` up) |
| `$4000-$7FFF` | RAM bank 1 (the shell loads at `$4000`) |
| `$8000-$BFFF` | RAM bank 2 |
| `$C000-$EFFF` | RAM bank 3 (BASIC.COM loads at `$C000`) |
| `$F000-$FEFF` | BIOS ROM (about 3.1KB of the 3.8KB used) |
| `$FF00-$FFEF` | I/O: SD storage `$FFD8`, UART `$FFE8`, bank registers `$FFEC-$FFEF`; addresses are reserved for a VDP (`$FFE4`), an OPL3 (`$FFE0`) and a VIA (`$FFB0`) |
| `$FFF0-$FFFF` | Interrupt vectors |

- **Memory banking.** The 64KB address space is four 16KB banks; each bank register (write-only)
  selects which of up to 256 physical 16KB RAM pages appears there, for up to **1MB of RAM**.
  The BIOS probes how much RAM is installed and hands pages out through `B_PAGE_ALLOC`; bank 0
  stays fixed and applications may remap banks 1-3.
- **Console.** A serial console: an R65C51 UART at 19200 baud, 8N1.
- **Storage.** An SD card holding a FAT16 volume. Today the card is an idealized block device
  (write a block number, stream 512 bytes); the real SPI/transport hardware isn't settled yet.
- **Clock.** A 16 Hz NMI tick keeps the time.

## Software

- **BIOS.** All services are one `SWI2` instruction with a function code in `A`; the calls
  (console, block I/O, banking, DOS, programs) are documented in `bios/defines.d` and
  `bios/README.md`. It also survives a crashing program: an illegal opcode prints where it happened, puts
  the stack, direct page and banks right, and restarts the shell.
- **DOS.** Files up to 4GB, volumes up to FAT16's 2GB, paths with `/`, `.` and `..`, eight open
  files. Metadata writes are ordered so that a power cut can lose clusters but never corrupt the
  volume -- and the test suite proves it by cutting the power at every single disk write of a
  scripted session.
- **Programs.** A program is a file with an 8-byte header (load address, entry address);
  `B_EXEC` loads and starts it and `B_EXIT` returns to the shell. The disk keeps them in `/CMD`,
  and the shell finds them through its `PATH`.
- **Editor.** `EDIT [file]`: nano's keys (`^O` write out, `^X` exit, `^W` search, `^K`/`^U` cut
  and paste, `M-A` mark, ...), a title bar, a status line, and it fits itself to the terminal's
  size. See `edit/README.md`.
- **Assembler and linker.** `PUGASM [-f raw|srec|com|obj] [-o out] [-l[list]] [-s] file`:
  lwasm's syntax, directives, macros, structs and code-size choices, with raw, S-record, `.COM`
  and LWOBJ object output. `PUGLINK [-f raw|srec|com] [-o out] [-m map] [-s script] file.o ...`:
  lwlink's link scripts, relocations and maps. On the Pugputer they rebuild the shell, the
  editor, DOS, BASIC, the BIOS and themselves byte for byte. See `pugasm/README.md`.
- **BASIC.** Extended Color BASIC plus `OPEN`/`PRINT#`/`INPUT#`/`FIELD`/`GET`/`PUT`,
  `MKDIR`/`CHDIR`/`FILES`/`KILL`/`NAME`, `ON ERROR GOTO`/`RESUME`/`ERR`/`ERL`, `SYSTEM`. See
  `basic309/README.md` for the differences from GW-BASIC.
- **Emulator.** A cycle-counted HD6309 (native and 6809-emulation modes), with the UART, SD
  card and banked RAM modeled to the register. `basic309_sdboot_demo` boots the real chain --
  BIOS, SD boot, DOS, shell -- from a disk image, with the console on your terminal or on a
  serial port (a COM port on Windows; a tty or a pseudo-terminal on Linux).

## Building from source

Windows and Linux are both supported; the Linux instructions follow the Windows ones.

### Windows

You need:

1. **Visual Studio 2022** (the Build Tools are enough) with the *Desktop development with C++*
   workload, and **CMake** 3.15 or newer.
2. **lwtools**, the 6809/6309 assembler and linker by **William Astle** -- <https://www.lwtools.ca>.
   It is not part of this repository. Put its Windows binaries in **`lwtools\win_bin`** at the
   top of this repository, so that `lwtools\win_bin\lwasm.exe` exists. Either:
   - download the prebuilt Windows package,
     <https://www.lwtools.ca/releases/lwtools/lwtools-4.25-win64.zip> (4.25; it produces exactly the
     same code for this project as 4.20 does), and copy `lwasm.exe`, `lwlink.exe` and the DLLs
     beside them into `lwtools\win_bin`; or
   - build the source release, <https://www.lwtools.ca/releases/lwtools/lwtools-4.20.tar.gz>
     (it includes Visual Studio project files and build instructions), and copy the resulting
     `bin` folder's contents into `lwtools\win_bin`.

   Any other place works if you set the `LWTOOLS` environment variable to the folder that
   holds `lwasm.exe` and `lwlink.exe`. (`lwtools_env.bat` documents the search order. The Linux
   binaries have their own folder, `lwtools\linux_bin`, so one copy of the repository can
   hold both.)
3. Optional: **SRecord** (`srec_cat`), only for the Intel-hex copy of the BIOS ROM.
   Optional: **com0com**, for the emulator's COM-port mode (below).

Then, from a Developer Command Prompt (or any prompt with `cmake` on the PATH):

```
build_all.bat
```

That assembles the BIOS, DOS, shell, editor, assembler, linker and BASIC, builds the emulator and the tools, makes the disk
image `basic309\disk.img`, and runs the test suite (about 170 tests, under a minute in the
default Release configuration; add `notests` to skip it, or `Debug` for a debug build, in which
the tests take several minutes). To run the result:

```
simulator\build\tools\Release\basic309_sdboot_demo.exe
```

`make_release.bat` builds the binary release (`dist\Pugputer6309-demo-<version>-win64.zip`).

### Linux

You need:

1. A C++17 compiler (g++ or clang++), **CMake** 3.15 or newer, and bash. On Ubuntu/Debian:
   `sudo apt install build-essential cmake`.
2. **lwtools** by **William Astle** -- <https://www.lwtools.ca>, built from the source release,
   <https://www.lwtools.ca/releases/lwtools/lwtools-4.20.tar.gz>:

   ```
   tar xzf lwtools-4.20.tar.gz
   cd lwtools-4.20
   make
   ```

   Then copy the two programs into **`lwtools/linux_bin`** at the top of this repository:

   ```
   cp lwasm/lwasm lwlink/lwlink /path/to/Pugputer6309_Emulator/lwtools/linux_bin/
   ```

   (If they reach that folder through Windows, `chmod +x` them.) Alternatively, `sudo make
   install` puts them on the PATH, or you can leave the built tree where it is and set the
   `LWTOOLS` environment variable to it (`export LWTOOLS=$HOME/lwtools-4.20`).
   (`lwtools_env.sh` documents the search order. The Windows binaries have their own folder,
   `lwtools/win_bin`, so one copy of the repository can hold both.)
3. Optional: **SRecord** (`sudo apt install srecord`), only for the Intel-hex copy of the BIOS
   ROM.

Then:

```
./build_all.sh
```

It does what `build_all.bat` does (and takes `notests` and `Debug` the same way). To run the
result:

```
simulator/build/tools/basic309_sdboot_demo
```

In the terminal, **Ctrl+\** quits the emulator (Ctrl+C goes to the Pugputer). `reinit_disk.sh`
rebuilds the firmware and makes a fresh `basic309/disk.img`, like `reinit_disk.bat`.

`make_release.sh` builds the Linux binary release
(`dist/Pugputer6309-demo-<version>-linux-x64.tar.gz`, the version taken from `make_release.bat`),
with the emulator linked fully statically so it runs on any x86-64 Linux.

### Using a COM port instead of the console

`basic309_sdboot_demo.exe --com COM4` connects the emulated UART to a Windows COM port, so you
can use a real terminal program (PuTTY, Tera Term, a retro-terminal emulator...) as the
console, or wire the emulator to other software. You need a *virtual serial-port pair*, such as
[com0com](https://com0com.sourceforge.net): the emulator opens one end (say `COM4`) and the
terminal program the other (`COM5`), at 19200 baud, 8 data bits, no parity, 1 stop bit.

On Linux, `basic309_sdboot_demo --com pty` needs no extra software: it creates a
pseudo-terminal and prints its name (say `/dev/pts/3`) for a terminal program to open --
`screen /dev/pts/3 19200`, or `picocom -b 19200 /dev/pts/3`. `--com /dev/ttyUSB0` uses a real
serial port.

## Tests

`simulator\build` after `build_all.bat`: `ctest -C Release`, or run
`tests\Release\pugputer_tests.exe` directly (on Linux, after `build_all.sh`: `ctest`, or
`tests/pugputer_tests`) -- optionally with words to select tests by name
(`pugputer_tests shell bios_`). About 150 tests and 3,500 checks cover the CPU core, the devices,
the BIOS (including hostile input: malformed S-records, a card that dies, a crashing program),
the DOS (a randomized model-based test compared against an independent FAT16 reader, crash
injection at every disk write, 100MB volumes), the shell, and BASIC (exact-output regression
tests, a keyword-table audit, file and error-trapping tests driven with real keystrokes).

## Where it is going

- **A graphics display peripheral** for the emulator (the memory map already reserves the
  address range of a V9958 video card), and later the same on the real machine.
- **Testing on the real Pugputer 6309:** the SD transport (SPI or VIA-driven), an SD card
  prepared off-line to bootstrap the hardware, and timing checks against the emulator.
- **Programs that use banking:** an extension of the program-file header describing segments
  in banked RAM, so applications bigger than 64KB can be loaded and run.
- **More BASIC:** the remaining Color BASIC space is tight (about 160 bytes), so growing it
  means relocating BASIC lower in RAM, which the program header already allows.
- **Emulator conveniences:** running at the real machine's clock speed, a debugger view,
  state save/restore.

Ideas and patches are welcome; open an issue to discuss before a big change.

## License and credits

MIT License -- see `LICENSE`. BASIC descends from Microsoft's Extended Color BASIC, and the
firmware is assembled with William Astle's lwtools; see `NOTICE.md` for these and other credits.
