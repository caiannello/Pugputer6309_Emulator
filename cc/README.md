# CC: C for the Pugputer

A C compiler that runs on the Pugputer, with its library, is being built here in phases. The
plan is in [`DESIGN.md`](DESIGN.md). What exists so far:

| | |
|---|---|
| `CPP.COM` | the C preprocessor (`cpp.asm`) |
| `CC1.COM` | the compiler proper: preprocessed C to assembly language for `ASM.COM` (`cc1*.asm`) |
| `/LIB` | the start-up code, `CRT0.O`, the library, `LIBC.A`, and `CC.SCR`, LINK's script for a C program (`lib/`) |
| `/INCLUDE` | the headers (`include/`) |

All of it is written in 6309 assembly, and every disk image has it: the programs in `/CMD`,
the library in `/LIB` and the headers in `/INCLUDE`. The release disk also carries their
sources, in `/ASM/CC` and `/ASM/LIBC`, from which ASM rebuilds them on the Pugputer exactly as
they were built.

## Compiling a program

Until `CC.COM` (the driver, phase 4) runs the four steps itself, they're four commands:

```
CPP hello.c
CC1 hello.i
ASM -f obj hello.asm
LINK -f com -o HELLO.COM -s /lib/cc.scr -L /lib /lib/crt0.o hello.o -lc
HELLO
```

Each stage stops at its first error (CPP goes on to the end of the file and counts them), says
`FILE:LINE: error: what`, and leaves no output file.

## CPP

```
CPP [-o out] [-I dir] [-D name[=value]] [-U name] file
```

CPP does what C's preprocessor does: a backslash at the end of a line joins the next, comments
become a space, and `#include`, `#define` (object-like and function-like, with `#`, `##`, and
`...` with `__VA_ARGS__`), `#undef`, `#if`, `#ifdef`, `#ifndef`, `#elif`, `#else`, `#endif`,
`#line`, `#error` and `#warning` are carried out. `#pragma` lines are passed on to CC1.

- **Includes:** `#include "file"` looks next to the file doing the `#include`, then in each
  `-I` directory (up to 4), then in `/INCLUDE`. `#include <file>` skips the first.
- **Macros** expand as the standard says. An argument is expanded before it goes into its
  macro's body, unless `#` or `##` is next to it. A macro's name isn't expanded inside its own
  expansion. A call's arguments may go on to later lines. The C standard's own examples
  (6.10.3.5) come out as it says.
- **`#if`** works in 32 bits, with every C operator, `defined`, character constants, and
  names that aren't macros as 0.
- **Predefined:** `__LINE__`, `__FILE__`, `__PUGPUTER__` and `__6309__`.
- **The output** (`.I`) has no blank lines. `#line N`, and `#line N "file"` when the file
  changes, keep CC1's line numbers the source's.

## CC1

```
CC1 [-o out] file
```

CC1 reads a `.I` and writes its `.ASM`: lwasm's syntax, with `SECTION`, `EXPORT` and `IMPORT`,
so that ASM (or lwasm) makes an object file of it. Its C:

- **Types:** `char` (signed), `signed char`, `unsigned char`, `short` and `int` (16 bits,
  the same), `unsigned`, `long` and `unsigned long` (32 bits), `void`, pointers, arrays (of
  arrays too), functions, `struct`, `union`, `enum`, and `typedef`. `const` and `volatile`
  are accepted and do nothing.
- **Constants** have C's types: a decimal one too big for an `int` is a `long`, a hex or
  octal one an `unsigned int` first; `u` and `l` (in any order, any case) as usual.
- **Structs and unions:** members of any type but a function (no bit-fields), with no
  padding. `.` and `->`; assignment, arguments and return values copy them whole. Tags have
  their own names and scopes, so `struct node { struct node *next; }` and a tag declared before
  it's defined both work. An `enum`'s constants are `int`s; the type is `int`.
- **Declarations:** prototypes (with `...`) and old-style `()`, `extern` (in a block too, where
  it hides a local of that name), `static` (at file level and in functions), and `register` and
  `auto` (which do nothing). `interrupt` before a function makes it end with `RTI`.
- **Initializers:** globals and statics take constants: numbers, addresses (`&x`, `a + 2`,
  `&s.m`, `"strings"`), and `{ lists }` for arrays, structs and unions (a union's first member),
  nested or with braces left out as C allows. What a list leaves out is zeros. An array's size
  can come from its initializer. Locals may be declared at the start of any block, or at the
  start of a `for`, and take any expression; a struct can be initialized from another, and an
  array with no size from a `{ list }` (of constants, then copied from `rodata`) or a string.
- **Statements:** all of them: `if`, `while`, `do`, `for`, `switch` (on a `long` too) with
  `case` and `default`, `break`, `continue`, `return`, `goto` and labels; and `asm { }`.
- **Expressions:** every operator, with C's conversions: arithmetic on `char`s promotes them
  to `int`, a `long` on either side makes an operation `long`, either side `unsigned` makes it
  unsigned (`/`, `%`, `>>` and the comparisons), pointer arithmetic is scaled, and arrays and
  functions decay to pointers. Calls go directly or through pointers. Constants are folded,
  `long`s in 32 bits.
- **Not yet:** bit-fields, floating point, and `-9` (code for a plain 6809).

The code is plain: D holds a value (a `long` is in Q), an operand already in memory or a
constant is used where it is (`ADDD 4,U`, `LDD [p,U]`, `CMPD #3`, `ADDW _l+2` / `ADCD _l`),
and anything else is pushed. A struct's value is its address. Division, `%` and shifts by a
variable call the library's helpers (`lib/arith.asm`, and `lib/larith.asm` for longs, which
`*` uses too); an `int`'s `*` is `MULD`. Copying a struct is `__scopy` (`lib/scopy.asm`).

### asm { }

```c
int twice(int x)
{
    asm {
        ldd   x
        lslb
        rola
        std   x
    }
    return x;
}
```

An `asm { }` block (in a function, or at file level, where it goes in `code`) is copied into
the output line by line. An indented line is an instruction; a line that starts in its first
column starts with a label. In an operand, a C name in scope becomes what it is in assembly: a
local or parameter `n,U`, a global `_name` (IMPORTed if it isn't defined here), a static in a
function `Ln`, an `enum` constant its value. A register's name (`a`, `x`, `pc`, ...) is the
register next to a comma or after `-` (`,x`, `d,y`, `,-s`), and in the operands of `PSHS`,
`PULS`, `TFR`, `EXG` and the other register-only instructions; on its own, `x` is a C name if
there is one. The block must keep U, Y, S and DP. CPP has been through it already, so its
macros expand there, and its comments should be C's (`;` comments may hold a `'`, which CPP
reads as a character constant).

## The library

| Header | Functions |
|---|---|
| `<stdio.h>` | `printf` `fprintf` `sprintf` `vprintf` `vfprintf` `vsprintf`; `putchar` `getchar` `puts` `fputs` `fgets` `fputc` `fgetc` `putc` `getc` `ungetc`; `fopen` `fclose` `fread` `fwrite` `fseek` `ftell` `rewind` `fflush` `feof` `ferror` `clearerr` `remove` `rename`; `stdin` `stdout` `stderr` |
| `<string.h>` | `strlen` `strcpy` `strncpy` `strcat` `strcmp` `strncmp` `strchr` `strrchr` `strstr` `memcpy` `memmove` `memset` `memcmp` |
| `<ctype.h>` | `isalpha` `isdigit` `isalnum` `isxdigit` `isspace` `isupper` `islower` `ispunct` `iscntrl` `isgraph` `isprint` `isblank` `toupper` `tolower` |
| `<stdlib.h>` | `malloc` `free` `calloc` `realloc` `sbrk` `atoi` `atol` `abs` `labs` `rand` `srand` `exit` |
| `<stdarg.h>` | `va_list`, `va_start`, `va_arg` and `va_end`, for writing variadic functions |
| `<stddef.h>`, `<limits.h>` | `size_t`, `ptrdiff_t`, `NULL`; the integer types' limits |

- **printf** does `%d %i %u %x %X %o %c %s %p %%`, with `-` and `0`, a width (digits or `*`),
  a precision (`.n` or `.*`: the most characters of a `%s`, the fewest digits of a number), and
  `l` for a long. `+`, `#` and space are accepted and ignored. It has no floating point yet.
- **Files**: fopen's modes are `r`, `w`, `a`, and each of those with `+`. A `b` makes a file
  binary. In text mode, the default, `'\n'` is written as CR LF, and CR, CR LF or LF reads as
  `'\n'`. DOS allows 8 files open at once. `rename` keeps a file in its directory, taking only
  the last part of the new name. `FILE` is a struct that isn't defined: a program only uses
  pointers to one.
- **The console**: `stdin` reads a line at a time, echoing as you type. Backspace takes a
  character back, Enter ends the line, and Ctrl-D at the start of a line is the end of the
  file. `stdout` and `stderr` go straight to the console.
- **malloc** uses a first-fit free list in address order. `free` joins a block to the free
  blocks next to it. The heap runs from the end of the program up to 512 bytes below the stack,
  which starts at `$EFFF`.
- **rand** is a 16-bit xorshift (period 65535), from 0 to 32767.
- **exit** ends the program. DOS closes its files, which writes out what they hold. The status
  isn't passed on yet (that comes with `B_SPAWN`).

A program that only prints links in only what it uses: "hello" with `printf` is about 1.5KB.

## The calling convention

From `cc/lib/libc.d`, and what CC1's code follows:

- C's names get a leading underscore in assembly (`printf` is `_printf`).
- Arguments are pushed right to left, each a whole number of 16-bit words. A `char` is
  widened to 2 bytes, and a `long` takes 4, high word first. The caller pops them. So on entry,
  a function's first argument is at `2,S`.
- A struct argument is its bytes, rounded up to a whole number of words.
- A `char` comes back in B (with D holding the widened value), an `int` or pointer in D, and a
  `long` in Q (D is the high word, W the low one). A function returning a struct gets a
  pointer to where it goes as a hidden first argument (pushed last), copies its value there,
  and returns the pointer in D.
- A function keeps U, Y, S and DP as it found them. D, W, X and CC are scratch.
- CC1's functions make a frame: `PSHS U` / `TFR S,U` / `LEAS -n,S`. Their arguments are at
  `4,U` and up (`6,U` returning a struct), a `char`'s value in the second byte of its word,
  and their locals below U.

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

(lwasm's strings take no C escapes, so the `'\n'` is written as `FCB 10`. CC1 writes every
string as `FCB` bytes.)

## Sections

`CC.SCR` places these, in this order, from `$3400`: `init` (CRT0, so it comes first),
`code`, `rodata` (CC1's strings), `data` (initialized globals), `bss` (the rest) and `heap`
(CRT0's, empty, so the heap starts after everything). Code that the program, the library or an
assembly module adds must be in one of these sections, because the script places no others. As
lwlink does, LINK reads `-l` libraries before the files, so the library's `code` comes before
the program's. Only `init`'s place is fixed.

## Building it

`cc/compile.bat` (or `compile.sh`) assembles CPP and CC1 with lwasm; `cc/lib/compile.bat`
assembles `crt0.asm` and each part of the library that `libc.rsp` names. `build_all` and
`reinit_disk` do both, and `mkdiskimg` puts the results on the disk (see
`simulator/include/pugputer/c_library.hpp`). On the Pugputer, the release disk's `/ASM/CC`
rebuilds CPP and CC1 (`ASM -o CPP.COM cpp.asm`, `ASM -o CC1.COM cc1.asm`), and `/ASM/LIBC`
the library (`AR @libc.rsp` makes `LIBC.A`), byte for byte as they were built.

Memory: CPP keeps its macros in RAM pages from `B_PAGE_ALLOC`, mapped into bank 3 as ASM's
symbols are. CC1 keeps its names, types and symbols in its own heap (11KB, after its 21KB of
code and 13KB of buffers); a function's locals go when it ends.

## Tests

- `simulator/tests/test_cc.cpp` compiles the C programs in `test_cc/` on the emulated machine
  as above, runs them and compares what they print with their `.out` files. It also compares
  CPP's output with the `.i` files (the standard's macro examples; includes and line numbers),
  checks that lwasm makes the same object file from CC1's assembly as ASM does, and checks the
  error messages for programs that must fail, and that they leave no output.
- `simulator/tests/test_libc.cpp` runs programs written in assembly by the calling convention
  (`test_libc/*.asm`), which ASM and LINK build on the emulated machine. It checks their output
  and the files they leave: printf's conversions, the string, ctype and stdlib functions,
  malloc's reuse and joining of blocks, text and binary files, `argv`, and typed input.
- `test_asmlink.cpp`'s `asm_rebuilds_every_program_from_the_demo_disk_sources` rebuilds CPP,
  CC1 and the library from `/ASM/CC` and `/ASM/LIBC` on the Pugputer. Every file must match
  the one built on the PC.
