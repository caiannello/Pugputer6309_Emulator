# CC: C for the Pugputer

A C compiler that runs on the Pugputer, with its library, is being built here in phases. The
plan is in [`DESIGN.md`](DESIGN.md). What exists so far is the C library: the start-up code
and a first `libc`, in 6309 assembly. Programs written in assembly can use it today, by C's
calling convention.

## The library

Every disk image has it in `/LIB`:

| File | |
|---|---|
| `CRT0.O` | the start of every C program: the stack, `bss` cleared, the heap, `argc`/`argv`, then `exit(main(argc, argv))` |
| `LIBC.A` | the library: an archive (`asmlink/README.md`, "AR") of one object file per part, so a program links only the parts it uses |
| `CC.SCR` | LINK's script for a C program: a `.COM` loading at `$3400` |

A program is linked with

```
LINK -f com -o PROG.COM -s /lib/cc.scr -L /lib /lib/crt0.o prog.o -lc
```

### What is in it

| Header (to come) | Functions |
|---|---|
| `<stdio.h>` | `printf` `fprintf` `sprintf` `vprintf` `vfprintf` `vsprintf`; `putchar` `getchar` `puts` `fputs` `fgets` `fputc` `fgetc` `putc` `getc` `ungetc`; `fopen` `fclose` `fread` `fwrite` `fseek` `ftell` `rewind` `fflush` `feof` `ferror` `clearerr` `remove` `rename`; `stdin` `stdout` `stderr` |
| `<string.h>` | `strlen` `strcpy` `strncpy` `strcat` `strcmp` `strncmp` `strchr` `strrchr` `strstr` `memcpy` `memmove` `memset` `memcmp` |
| `<ctype.h>` | `isalpha` `isdigit` `isalnum` `isxdigit` `isspace` `isupper` `islower` `ispunct` `iscntrl` `isgraph` `isprint` `isblank` `toupper` `tolower` |
| `<stdlib.h>` | `malloc` `free` `calloc` `realloc` `sbrk` `atoi` `abs` `rand` `srand` `exit` |

- **printf** does `%d %i %u %x %X %o %c %s %p %%`, with `-` and `0`, a width (digits or `*`),
  a precision (`.n` or `.*`: the most characters of a `%s`, the fewest digits of a number), and
  `l` for a long. `+`, `#` and space are accepted and ignored. It has no floating point yet.
- **Files**: fopen's modes are `r`, `w`, `a`, and each of those with `+`. A `b` makes a file
  binary. In text mode, the default, `'\n'` is written as CR LF, and CR, CR LF or LF reads as
  `'\n'`. DOS allows 8 files open at once. `rename` keeps a file in its directory, taking only
  the last part of the new name.
- **The console**: `stdin` reads a line at a time, echoing as you type. Backspace takes a
  character back, Enter ends the line, and Ctrl-D at the start of a line is the end of the
  file. `stdout` and `stderr` go straight to the console.
- **malloc** uses a first-fit free list in address order. `free` joins a block to the free
  blocks next to it. The heap runs from the end of the program up to 512 bytes below the stack,
  which starts at `$EFFF`.
- **rand** is a 16-bit xorshift (period 65535), from 0 to 32767.
- **exit** ends the program. DOS closes its files, which writes out what they hold. The status
  isn't passed on yet (that comes with `B_SPAWN`).

## The calling convention

From `cc/lib/libc.d`:

- C's names get a leading underscore in assembly (`printf` is `_printf`).
- Arguments are pushed right to left, each a whole number of 16-bit words. A `char` is
  widened to 2 bytes, and a `long` takes 4, high word first. The caller pops them. So on entry,
  a function's first argument is at `2,S`.
- A `char` comes back in B (with D holding the widened value), an `int` or pointer in D, and a
  `long` in Q (D is the high word, W the low one).
- A function keeps U, Y, S and DP as it found them. D, W, X and CC are scratch.

`printf("%d items\n", n)` in assembly:

```
        LDD     n
        PSHS    D
        LDX     #fmt
        PSHS    X
        JSR     _printf
        LEAS    4,S
        ...
fmt     FCC     "%d items"
        FCB     10,0
```

(lwasm's strings take no C escapes, so the `'\n'` is written as `FCB 10`.)

## Sections

`CC.SCR` places these, in this order, from `$3400`: `init` (CRT0, so it comes first),
`code`, `rodata`, `data`, `bss` and `heap` (CRT0's, empty, so the heap starts after
everything). Code that the program, the library or an assembly module adds must be in one of
these sections, because the script places no others. As lwlink does, LINK reads `-l`
libraries before the files, so the library's `code` comes before the program's. Only `init`'s
place is fixed.

## Building it

`cc/lib/compile.bat` (or `compile.sh`) assembles `crt0.asm` and each part that `libc.rsp`
names, with lwasm. `build_all` and `reinit_disk` do this, and `mkdiskimg` puts the results in
`/LIB` (see `simulator/include/pugputer/c_library.hpp`). `libc.rsp` is AR's response file. On
the Pugputer, the release disk has the sources in `/ASM/LIBC`, and `AR @libc.rsp` there
makes the same `LIBC.A`, byte for byte.

## Tests

- `simulator/tests/test_libc.cpp` runs programs written in assembly by the calling convention
  (`test_libc/*.asm`), which ASM and LINK build on the emulated machine. It checks their output
  and the files they leave: printf's conversions, the string, ctype and stdlib functions,
  malloc's reuse and joining of blocks, text and binary files, `argv`, and typed input.
- `test_asmlink.cpp`'s `asm_rebuilds_every_program_from_the_demo_disk_sources` rebuilds the
  library from `/ASM/LIBC` on the Pugputer. Every object must match lwasm's, and `LIBC.A`
  must match `mkdiskimg`'s.
