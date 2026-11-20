# CC: C for the Pugputer

A C compiler that runs on the Pugputer, with its library, is being built here in phases. The
plan is in [`DESIGN.md`](DESIGN.md). What exists so far:

| | |
|---|---|
| `CC.COM` | the driver: compiles, assembles and links, running the others (`cc.asm`) |
| `CPP.COM` | the C preprocessor (`cpp.asm`) |
| `CC1.COM` | the compiler proper: preprocessed C to assembly language for `ASM.COM` (`cc1*.asm`) |
| `/LIB` | the start-up code, `CRT0.O`, the libraries, `LIBC.A` (C's) and `LIBPUG.A` (the Pugputer's: video, input, sound), and `CC.SCR`, LINK's script for a C program (`lib/`) |
| `/INCLUDE` | the headers (`include/`) |

All of it is written in 6309 assembly, and every disk image has it: the programs in `/CMD`,
the library in `/LIB` and the headers in `/INCLUDE`. The release disk also carries their
sources, in `/ASM/CC` and `/ASM/LIBC`, from which ASM rebuilds them on the Pugputer exactly as
they were built.

## Compiling a program

```
CC hello.c
HELLO
```

```
CC [-c|-S|-E] [-o out] [-v] [-q] [-I dir] [-D name[=val]] [-U name] [-b bank]
   [-L dir] [-l lib] file...
```

CC runs CPP, CC1, ASM and LINK in turn, each as a child (it waits, and goes on from where it
was), and stops at the first that fails. A `.c` file is preprocessed, compiled and assembled;
a `.asm` (or `.s`) file is assembled; anything else (a `.o`, a library) goes to LINK as it
is. The program is the first file's name with `.COM`, or `-o`'s.

- `-c` stops at the `.O` files, `-S` at the `.ASM`, `-E` at the `.I` (with `-o`, for one
  file). Otherwise the files made on the way (in the current directory: the source's name
  with `.I`, `.ASM`, `.O`) are deleted once used.
- `-I`, `-D` and `-U` are CPP's; `-b N` is CC1's (see "Banked code"); `-L` and `-l` are LINK's.
  `/LIB`, `CRT0.O`, `-lpug` and `-lc` are always there (with LINK's `--quiet-libs`, so a
  program that uses neither library hears nothing of it).
- CC says what it is when it starts (`CC: the Pugputer 6309's C compiler`), then a line as each
  stage starts, so that a long one is seen to be going: `hello.c: cpp`, `hello.c: cc1`,
  `hello.c: asm`, `link: HELLO.COM`. An error comes on the line after the stage it's from.
  `-q` (quiet) leaves all that out, so that only what's wrong is said.
- `-v` shows each command as it's run.
- The tools are looked for in the current directory, then along the search path (`PATH`).

Each stage stops at its first error (CPP goes on to the end of the file and counts them), says
`FILE:LINE: error: what`, and leaves no output file. CC's exit code is 0, or 1 if something
failed. The four steps by hand:

```
CPP hello.c
CC1 hello.i
ASM -f obj hello.asm
LINK -f com -o HELLO.COM -s /lib/cc.scr -L /lib /lib/crt0.o hello.o -lc
```

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
CC1 [-o out] [-b bank] [-M] file
```

`-M` says, at the end, the least room CC1's heap had and the most of its stack it used
(`CC1: heap: 3211 of 12091 bytes free at least; stack: 166 of 1536 used at most`, for SWAMPFLY):
how close a program comes to "out of memory".

CC1 reads a `.I` and writes its `.ASM`: lwasm's syntax, with `SECTION`, `EXPORT` and `IMPORT`,
so that ASM (or lwasm) makes an object file of it. Its C:

- **Types:** `char` (signed), `signed char`, `unsigned char`, `short` and `int` (16 bits,
  the same), `unsigned`, `long` and `unsigned long` (32 bits), `float`, `double` and
  `long double` (all IEEE 754 single precision, 32 bits: see "Floating point"), `_Bool` (a
  byte, whatever is stored in it made 0 or 1; `<stdbool.h>`'s `bool`), `void`, pointers,
  arrays (of arrays too), functions, `struct`, `union`, `enum`, and `typedef`. `const` and
  `volatile` are accepted and do nothing.
- **Constants** have C's types: a decimal one too big for an `int` is a `long`, a hex or
  octal one an `unsigned int` first; `u` and `l` (in any order, any case) as usual. One with
  a point or an exponent (`1.5`, `.5`, `1e-3`, `2.5f`) is a `double`.
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
  to `int`, a `double` on either side makes an operation `double`, a `long` makes it `long`,
  either side `unsigned` makes it unsigned (`/`, `%`, `>>` and the comparisons), pointer
  arithmetic is scaled, and arrays and functions decay to pointers. Calls go directly or
  through pointers. Constants are folded, `long`s in 32 bits and `double`s as the program
  would have worked them out.
- **Not yet:** bit-fields, and `-9` (code for a plain 6809).

The code is plain: D holds a value (a `long` is in Q), an operand already in memory or a
constant is used where it is (`ADDD 4,U`, `LDD [p,U]`, `CMPD #3`, `ADDW _l+2` / `ADCD _l`),
and anything else is pushed. A struct's value is its address. Division, `%` and shifts by a
variable call the library's helpers (`lib/arith.asm`, and `lib/larith.asm` for longs, which
`*` uses too); an `int`'s `*` is `MULD`. Copying a struct is `__scopy` (`lib/scopy.asm`).

### Floating point

`float`, `double` and `long double` are one type: IEEE 754's single precision (as CMOC's
`double` is its `float`), 4 bytes, about 7 significant digits, from 1.2e-38 to 3.4e38. Results
are rounded to the nearest (ties to even), with IEEE's infinities and NaNs, but no denormals: a
result smaller than 1.2e-38 is 0. `<float.h>` has the limits.

- A float is held as a long is: in Q (D the high word, with the sign and the exponent), 4 bytes
  as an argument, returned in Q. So loading, storing and passing one costs what a long's does.
- Arithmetic and comparing are the library's helpers (`lib/fpcore.asm`, in `LIBC.A` as
  `float.o`): `__fadd`, `__fsub`, `__fmul`, `__fdiv` (the left in Q, the right pushed, as the
  long helpers), `__fcmp` (which leaves the flags a signed branch wants), and the conversions
  `__ltof`, `__ultof`, `__ftol`, `__ftoul` (an `int` or a `char` goes through a long). About
  730 cycles for `+`, 1300 for `*`, 2700 for `/` (0.2 to 0.75 ms at 3.58 MHz). They are
  checked against the PC's IEEE arithmetic bit for bit (`test_float.cpp`). `-x` turns the sign
  bit over.
- CC1 includes the same `fpcore.asm`: a constant (`1.0 / 3`, `(float)7`, `-2.5e-3`) is folded
  to the bits the program would have made, and decimal constants are read the way `strtod`
  reads them.
- An `int` `op=` a `double` (`i *= 1.5`) is done in floats, as C says: it becomes
  `i = i * 1.5`, so `i` is worked out twice (side effects in it happen twice).
- printf's and scanf's float conversions are only linked when the program passes a float, or
  a pointer to one, to `...` (or to a function with no prototype): CC1 then refers to
  `__fltused`, which brings in `fltio.asm` (and `strtod.asm`). A program that never does
  keeps printf's size; one that prints a float without it gets a `?`.

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

### Banked code

A program can have more code than its 47KB: `#pragma bank N` (N from 1 to 15) puts the
functions after it in overlay N, until another `#pragma bank` (`#pragma bank 0` is fixed code
again). `CC -b N` (CC1's `-b N`) does it for a whole file.

```c
#pragma bank 1
int level_one(int x) { return x * 2; }   /* in overlay 1 */
#pragma bank 0
int main(void) { return level_one(21); }  /* fixed code */
```

- Each overlay is up to 12KB of code, linked to run at `$C000` (bank 3, the window). Its data,
  strings and statics stay in fixed memory, so anything can use them.
- A banked function `f` has a stub in fixed memory under its own name: `LDB #N` / `LDX
  #__b_f` / `JMP __farcall`. Calls, and pointers to `f`, go through it; a call from code in the
  same overlay goes straight to the body. `__farcall` (`lib/farcall.asm`) keeps the return
  address and the window's page on a side stack of its own, maps the overlay's page, calls the
  body, and maps the caller's back: every argument and result (a `long` too) passes through.
  Each far call costs two `B_BANK_SET`s.
- LINK writes the overlays after the program's body (`EXE_MORE`). When the program starts,
  `farcall.asm`'s part of CRT0 moves the stack below `$C000` (bank 3 can't be remapped while
  the stack is in it), reads each overlay into a page of its own, and frees them at `exit()`.
  So with overlays, the fixed part (code, data, bss and the heap's start) must end below
  `$C000`.
- An `interrupt` function can't be banked. Code that maps bank 3 itself shouldn't call banked
  code while it does.

## The library

| Header | Functions |
|---|---|
| `<stdio.h>` | `printf` `fprintf` `sprintf` `vprintf` `vfprintf` `vsprintf`; `scanf` `fscanf` `sscanf` `vscanf` `vfscanf` `vsscanf`; `putchar` `getchar` `puts` `fputs` `fgets` `fputc` `fgetc` `putc` `getc` `ungetc`; `fopen` `fclose` `fread` `fwrite` `fseek` `ftell` `rewind` `fflush` `feof` `ferror` `clearerr` `remove` `rename`; `stdin` `stdout` `stderr` |
| `<string.h>` | `strlen` `strcpy` `strncpy` `strcat` `strcmp` `strncmp` `strchr` `strrchr` `strstr` `memcpy` `memmove` `memset` `memcmp` |
| `<ctype.h>` | `isalpha` `isdigit` `isalnum` `isxdigit` `isspace` `isupper` `islower` `ispunct` `iscntrl` `isgraph` `isprint` `isblank` `toupper` `tolower` |
| `<stdlib.h>` | `malloc` `free` `calloc` `realloc` `sbrk` `atoi` `atol` `atof` `strtod` `abs` `labs` `rand` `srand` `exit` |
| `<math.h>` | `sin` `cos` `tan` `asin` `acos` `atan` `atan2` `sinh` `cosh` `tanh` `exp` `log` `log10` `pow` `sqrt` `fabs` `floor` `ceil` `trunc` `round` `fmod` `modf` `frexp` `ldexp`, the C99 `f` names for them (`sinf` ...), `M_PI` and the other constants, `HUGE_VAL` `INFINITY` `NAN`. In `LIBC.A` (no `-lm`) |
| `<stdint.h>` | `int8_t` to `uint32_t`, the `least` and `fast` ones, `intptr_t` `intmax_t`, their limits, `INT32_C()` and the rest (no 64-bit types) |
| `<stdbool.h>`, `<float.h>` | `bool` `true` `false`; the floating types' limits (`FLT_EPSILON`, `DBL_MAX` ...) |
| `<stdarg.h>` | `va_list`, `va_start`, `va_arg` and `va_end`, for writing variadic functions |
| `<stddef.h>`, `<limits.h>` | `size_t`, `ptrdiff_t`, `NULL`; the integer types' limits |
| `<pug/sys.h>` | `spawn(path, tail)`: runs a program as a child (DOS's `B_EXEC` with `EXEC_CHILD`) and goes on when it ends -> its exit code, or -1 |
| `<pug/bank.h>` | data in banked RAM: `page_alloc` `page_free` `bank_get` `bank_map`; `far_read` `far_write` `far_peek` `far_poke` (a page and an offset in it, copied through `B_PAGE_COPY` whatever the banks show) |

`LIBPUG.A`, the Pugputer's own (`lib/pugvid.asm`, `pugin.asm`, `pugsnd.asm`; the card itself
is `vidcard/README.md`):

| Header | Functions |
|---|---|
| `<pug/video.h>` | the video card. Its address space (24 bits: a `long`): `vc_poke` `vc_peek` `vc_poke16` `vc_write` `vc_read`, and the card's own `vc_fill` `vc_copy`, `vc_wait` for them to be done. The display: `vc_reset` `vc_layer` (mode, map size, map and tiles) `vc_scroll` `vc_stride` `vc_show` `vc_backdrop` `vc_color` (`VC_RGB(r, g, b)`), `vc_text` (the text screen). Time: `vc_vsync` (waits for vertical blank, calling `vc_idle` meanwhile), `vc_frame`. Drawing commands: `gfx_target` `gfx_color` `gfx_plot` `gfx_line` `gfx_rect` `gfx_fillrect` `gfx_circle` `gfx_disc` `gfx_triangle` `gfx_clear` `gfx_font` `gfx_char` `gfx_text` `gfx_blit`. Sprites: `spr_set` `spr_move` `spr_count` `spr_hires`. With the card's constants (`LM_...`, `LW_...`, `SS_...`, `TILE(n, pal)`) |
| `<pug/input.h>` | `key_grab` (the keys from the console), `key_get` (each press and release: its USB code, `KEY_...`, and its character), `key_waiting` `key_mods`; `mouse_get` `mouse_wheel` `mouse_pointer`; `pad_get` (a `struct pad`: d-pad, buttons by place, sticks) |
| `<pug/sound.h>` | SONGKIT's player (`gamekit/sk_play.asm`, as games include it): `song_start` (a `.SNG` in memory) `song_pstart` (in pages) `song_poll` `song_tick` `song_stop` `song_off`; and `opl_write`. `song_start` sets `vc_idle`, so a program that waits for each frame with `vc_vsync` keeps the song going |

The demo `/DEMO/SWAMPFLY.C` (`demo/programs/C/`) uses all three: SWAMP's tile layers and
music, and a firefly to fly with the keys, a gamepad or the mouse.

- **printf** does `%d %i %u %x %X %o %c %s %p %%` and `%e %E %f %F %g %G`, with `-`, `0`, `+`
  and space (a sign or a space before a signed number), `#` (`%g` keeps its zeros, `%.0f` its
  point), a width (digits or `*`), a precision (`.n` or `.*`: the most characters of a `%s`, the
  fewest digits of a number, the digits after a float's point: at most 20), and `l` for a long.
  A float's first 9 significant digits are worked out exactly from its value (more are zeros);
  `inf` and `nan` as C has them.
- **scanf** (and `fscanf`, `sscanf`, the `v` ones) does `%d %i %u %o %x %X %p` (with `hh`, `h`
  and `l`), `%c`, `%s`, `%[set]` and `%[^set]` (ranges like `a-z`), `%e %f %g` (and `%lf`),
  `%n` and `%%`, with a width and `*`. White space in the format matches any amount, and every
  conversion but `%c`, `%[` and `%n` skips it first. It returns how many it stored, or `EOF` if
  the input ended before the first. The character a conversion stops at is put back: it's the
  next one read.
- **math.h** is Cephes's single-precision functions (Stephen L. Moshier's), in assembly: good
  to a few units in the last place (`sqrt` correctly rounded); `sin`, `cos` and `tan` lose
  accuracy beyond some thousands. `log(0)` is `-inf`, a negative's `log` or `sqrt` a NaN.
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
- **exit** ends the program. DOS closes its files, which writes out what they hold. The
  status's low byte is the exit code: the program that ran this one with `spawn()` gets it.
- **spawn** runs the child in pages of its own: when it ends, the caller's memory (banks 1 to 3,
  and its part of bank 0, `$3400-$3FFF`) is as it was, and the child's open files are closed.
  Pages the child allocated itself are not freed. Children can be four deep.

A program that only prints links in only what it uses: "hello" with `printf` is about 1.5KB.

## The calling convention

From `cc/lib/libc.d`, and what CC1's code follows:

- C's names get a leading underscore in assembly (`printf` is `_printf`).
- Arguments are pushed right to left, each a whole number of 16-bit words. A `char` is
  widened to 2 bytes, and a `long` takes 4, high word first. The caller pops them. So on entry,
  a function's first argument is at `2,S`.
- A struct argument is its bytes, rounded up to a whole number of words.
- A `char` comes back in B (with D holding the widened value), an `int` or pointer in D, and a
  `long` or a `double` in Q (D is the high word, W the low one). A function returning a struct gets a
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

`CC.SCR` places these, in this order, from `$3400`: `init`, `init_ovl`, `init_flt` and
`init_end` (CRT0's start, so it comes first; `init_ovl` is `farcall.asm`'s, for overlays,
`init_flt` `fltio.asm`'s, setting printf's and scanf's float hooks, and they fall through), `code`, `fini`, `fini_ovl` and `fini_end` (`exit()`, the same way), `rodata` (CC1's
strings), `data` (initialized globals), `bss` (the rest) and `heap` (CRT0's, empty, so the
heap starts after everything). Then `ovl1` to `ovl15`, each at `$C000`: banked code. Code that the program, the library or an
assembly module adds must be in one of these sections, because the script places no others. As
lwlink does, LINK reads `-l` libraries before the files, so the library's `code` comes before
the program's. Only `init`'s place is fixed.

## Building it

`cc/compile.bat` (or `compile.sh`) assembles CPP and CC1 with lwasm; `cc/lib/compile.bat`
assembles `crt0.asm` and each part of the libraries that `libc.rsp` and `libpug.rsp` name. `build_all` and
`reinit_disk` do both, and `mkdiskimg` puts the results on the disk (see
`simulator/include/pugputer/c_library.hpp`). On the Pugputer, the release disk's `/ASM/CC`
rebuilds CPP and CC1 (`ASM -o CPP.COM cpp.asm`, `ASM -o CC1.COM cc1.asm`), and `/ASM/LIBC`
the libraries (`AR @libc.rsp` makes `LIBC.A`, `AR @libpug.rsp` `LIBPUG.A`), byte for byte as they
were built.

Memory: CPP keeps its macros in RAM pages from `B_PAGE_ALLOC`, mapped into bank 3 as ASM's
symbols are. CC1 keeps its names, types and symbols in its own heap (12KB, after its 25KB of
code and 11KB of buffers, with 1.5KB of stack above it); a function's locals go when it ends.
Each function a header declares takes about 50 bytes of it, so a program that includes
`<math.h>` has 1.2KB less: `CC1 -M` says how much is left.

## Tests

- `simulator/tests/test_float.cpp` runs `lib/fpcore.asm` on the CPU alone and compares it with
  the PC's IEEE single precision, bit for bit: 40,000 random `+ - * /`, the special values,
  comparisons, the conversions, and decimal scaling.
- `simulator/tests/test_cc.cpp` compiles the C programs in `test_cc/` on the emulated machine
  as above, runs them and compares what they print with their `.out` files. It also compares
  CPP's output with the `.i` files (the standard's macro examples; includes and line numbers),
  checks that lwasm makes the same object file from CC1's assembly as ASM does, and checks the
  error messages for programs that must fail, and that they leave no output. CC.COM builds a
  program from C and assembly files (and `-c`, `-S`, `-E`, and a failure, tidied up);
  `spawn` runs children four deep, the caller's memory and their exit codes checked; a program
  with code in three overlays runs, and gives its pages back; `<pug/bank.h>`'s calls;
  `LIBPUG.A` with the video card and the OPL3 on the bus (`pugtest.c`); floats (`float.c`),
  scanf (`scanf.c`, typed at the console too), math.h (`math.c`, each function against its
  exact value); deep nesting, and an error for too deep (`deep.c`); CC1's heap with SWAMPFLY
  (at least 2KB left); and SWAMPFLY, compiled on the machine, run, and stopped with a key.
- `simulator/tests/test_libc.cpp` runs programs written in assembly by the calling convention
  (`test_libc/*.asm`), which ASM and LINK build on the emulated machine. It checks their output
  and the files they leave: printf's conversions, the string, ctype and stdlib functions,
  malloc's reuse and joining of blocks, text and binary files, `argv`, and typed input.
- `test_asmlink.cpp`'s `asm_rebuilds_every_program_from_the_demo_disk_sources` rebuilds CC,
  CPP, CC1 and the library from `/ASM/CC` and `/ASM/LIBC` on the Pugputer. Every file must match
  the one built on the PC.
