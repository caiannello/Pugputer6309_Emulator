# Pugputer 6309 Simulator

A homebrew computer built around the Hitachi **HD6309** CPU, with its complete software stack --
BIOS, DOS, shell and BASIC -- and a cycle-counted emulator that runs all of it on a PC.

```
/> ver
Pugputer 6309 DOS 2.1
/> basic
6809 EXTENDED BASIC ...
OK
LOAD "PRIMES"
RUN
 2  3  5  7  11  13  17  19  23  29 ...
```

**Just want to try it?** Download the Windows demo from the *Releases* page, unzip it and
double-click `start-console.bat`. Nothing to install or compile; see the release's `README.md`.

## Future plans
- Self-hosted assembler/linker
- Text editor
- Simulated graphic display

## Actual Hardware
[Pugputer6309 on GitHub](https://github.com/caiannello/Pugputer6309)

## What is in here

| Folder | What it is |
|---|---|
| `bios/` | The 4KB boot ROM: reset, an interrupt-driven UART driver, an SD block driver, RAM-bank management, and the `SWI2` system-call interface everything else uses. |
| `dos/` | The resident DOS: a FAT16 file system (8.3 names, subdirectories, 32-bit file sizes and block numbers, a FAT cache, crash-safe write ordering) and the program loader. |
| `shell/` | `SHELL.COM`, the command interpreter: `DIR`, `CD`, `COPY`, `TYPE`, ... and running programs. |
| `basic309/` | **basic309**, Microsoft's Extended Color BASIC ported to run on this system, with GW-BASIC-style sequential and random-access files, directories, and `ON ERROR`/`RESUME`. |
| `simulator/` | The HD6309 CPU core, the system bus and device models (UART, SD card, RAM banking), the emulator programs, and the test suite. |
| `demo/` | The sample BASIC programs and launcher scripts that go into the binary release. |

Every folder has its own `README.md` with the details.

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
  `B_EXEC` loads and starts it and `B_EXIT` returns to the shell.
- **BASIC.** Extended Color BASIC plus `OPEN`/`PRINT#`/`INPUT#`/`FIELD`/`GET`/`PUT`,
  `MKDIR`/`CHDIR`/`FILES`/`KILL`/`NAME`, `ON ERROR GOTO`/`RESUME`/`ERR`/`ERL`, `SYSTEM`. See
  `basic309/README.md` for the differences from GW-BASIC.
- **Emulator.** A cycle-counted HD6309 (native and 6809-emulation modes), with the UART, SD
  card and banked RAM modeled to the register. `basic309_sdboot_demo.exe` boots the real chain --
  BIOS, SD boot, DOS, shell -- from a disk image, with the console on your terminal or on a COM
  port.

## Building from source

You need Windows and:

1. **Visual Studio 2022** (the Build Tools are enough) with the *Desktop development with C++*
   workload, and **CMake** 3.15 or newer.
2. **lwtools**, the 6809/6309 assembler and linker by **William Astle** -- <https://www.lwtools.ca>.
   It is not part of this repository. Either:
   - download the prebuilt Windows package,
     <https://www.lwtools.ca/releases/lwtools/lwtools-4.25-win64.zip> (4.25; it produces exactly the
     same code for this project as 4.20 does), and unzip it into a folder named `lwtools` at the
     top of this repository, so that `lwtools\lwasm.exe` exists; or
   - build the source release, <https://www.lwtools.ca/releases/lwtools/lwtools-4.20.tar.gz>
     (it includes Visual Studio project files and build instructions), and put the resulting
     `bin` folder's contents in `lwtools\bin`.

   Any other place works if you set the `LWTOOLS` environment variable to the folder that
   holds `lwasm.exe` and `lwlink.exe`. (`lwtools_env.bat` documents the search order.)
3. Optional: **SRecord** (`srec_cat`), only for the Intel-hex copy of the BIOS ROM.
   Optional: **com0com**, for the emulator's COM-port mode (below).

Then, from a Developer Command Prompt (or any prompt with `cmake` on the PATH):

```
build_all.bat
```

That assembles the BIOS, DOS, shell and BASIC, builds the emulator and the tools, makes the disk
image `basic309\disk.img`, and runs the test suite (about 150 tests, under a minute in the
default Release configuration; add `notests` to skip it, or `Debug` for a debug build, in which
the tests take several minutes). To run the result:

```
simulator\build\tools\Release\basic309_sdboot_demo.exe
```

`make_release.bat` builds the binary release (`dist\Pugputer6309-demo-<version>-win64.zip`).

### Using a COM port instead of the console

`basic309_sdboot_demo.exe --com COM4` connects the emulated UART to a Windows COM port, so you
can use a real terminal program (PuTTY, Tera Term, a retro-terminal emulator...) as the
console, or wire the emulator to other software. You need a *virtual serial-port pair*, such as
[com0com](https://com0com.sourceforge.net): the emulator opens one end (say `COM4`) and the
terminal program the other (`COM5`), at 19200 baud, 8 data bits, no parity, 1 stop bit.

## Tests

`simulator\build` after `build_all.bat`: `ctest -C Release`, or run
`tests\Release\pugputer_tests.exe` directly -- optionally with words to select tests by name
(`pugputer_tests shell bios_`). About 150 tests and 3,500 checks cover the CPU core, the devices,
the BIOS (including hostile input: malformed S-records, a card that dies, a crashing program),
the DOS (a randomized model-based test compared against an independent FAT16 reader, crash
injection at every disk write, 100MB volumes), the shell, and BASIC (exact-output regression
tests, a keyword-table audit, file and error-trapping tests driven with real keystrokes).

## Where it is going

- **A self-hosted assembler and linker** that runs on the Pugputer itself, `lwasm`-syntax
  compatible, using the banked RAM for code and symbols -- the system should be able to
  build its own software.
- **A text editor** application, also using banked RAM for the text buffer.
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
