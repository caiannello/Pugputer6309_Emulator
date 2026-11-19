# CC: a C compiler for the Pugputer (design)

Status: phases 1 and 2 done (2026-11-19). Phase 1: LINK's libraries, AR, CRT0 and the first
libc. Phase 2: CPP, and CC1 with `char`, `int`, pointers, arrays, functions, `typedef` and every
statement and operator. See [`README.md`](README.md) for what is there now, and "Found in
phase 1" and "Found in phase 2" at the end for what they settled. Decisions taken so far
(2026-11-19):

- The compiler is written in **6309 assembly**, like ASM and LINK. It is built with lwtools
  on the PC to bootstrap, and can be rebuilt on the Pugputer with ASM and LINK.
- It accepts **CMOC's C dialect** (including `asm { }` blocks and the pragmas that make sense
  here), but uses **its own calling convention**, made for the 6309. Its output is not meant
  to match CMOC's.
- One command, `CC`, compiles, assembles and links. That needs a new DOS call, **`B_SPAWN`**.
- **Banked code works automatically:** a file or function is given a bank, LINK puts it in an
  overlay page, and calls to it go through generated trampolines.

## The pipeline

```
FOO.C --CPP--> FOO.I --CC1--> FOO.ASM --ASM -f obj--> FOO.O --LINK--> FOO.COM
                                                      CRT0.O, LIBC.A, LIBPUG.A
```

| Program | What it does |
|---|---|
| `CC.COM` | The driver. It runs each stage with `B_SPAWN`, deletes the temporary files and stops at the first error. Options: `-c` (stop at `.O`), `-S` (stop at `.ASM`), `-E` (stop at `.I`), `-o`, `-I`, `-L`, `-l`, `-D`, `-9` (6809 code only), `-O` (peephole pass, later). |
| `CPP.COM` | The C preprocessor: `#include`, `#define` (object-like and function-like, with `#` and `##`), `#if`/`#elif` with `defined`, `#ifdef`, `#line`, `#error`, `#pragma` passed through. Writes `#line` markers so CC1 can report errors against the original file. |
| `CC1.COM` | Parses one preprocessed file and writes lwasm-syntax assembly with `SECTION`/`EXPORT`/`IMPORT`. |
| `ASM.COM`, `LINK.COM` | The existing ones, with the LINK changes listed below. |
| `AR.COM` | New: a librarian for lwar-compatible `.a` archives, so that lwlink on the PC can read them too. |

CPP and CC1 are separate programs because each must fit in the space a program gets
($3400-$EFFF, about 47KB) together with its buffers. CPP's macros live in banked RAM through
`pa_heap.asm`, as ASM's symbols do. CC1 (16KB of code) keeps its names, types and symbols in
a 16KB heap of its own for now; they can move to banked RAM if programs outgrow it.

### Inside CC1

CC1 works one top-level declaration at a time. A function body is parsed one statement at a
time. Each full expression becomes a tree (in a pool of nodes, used again for the next one),
is type-checked, has constants folded, and is turned into code straight away. Then the tree is
dropped. (A `for`'s condition and step are kept together until both are code.) Only declarations
(the symbols, types, struct layouts and string literals) last for the whole file. That keeps
CC1's memory needs proportional to its declarations, not to the size of the source.

Code generation is plain and template-based:

- **Registers:** D is the accumulator, X holds addresses, and intermediate values are pushed
  on the stack.
- **Operands in place:** a number, a variable, `*p` for a pointer variable, or an array's
  element at a constant index is used where it is (`ADDD 4,U`, `LDD [-2,U]`, `STB _a+3`);
  anything else on the right is made first and pushed (`ADDD ,S++`).
- **6309 instructions** (which `-9` will turn off): `MULD` for `*`; `TFM` for locals' array
  initializers (and struct copy, later); `NEGD`, `COMD`, `LSLD`, `ASRD`, `TSTD`; Q for `long`
  (`LDQ`, `STQ`, `ADDW`/`ADCD`) in phase 3. W as a second accumulator, and `AIM`/`OIM`/`EIM`,
  are for the peephole pass. `/`, `%` and shifts by a variable call the library's helpers
  (`lib/arith.asm`), not `DIVD`/`DIVQ` (see "Found in phase 2").
- **Optimization:** so far only constant folding. Every branch is long (`LBxx`). A peephole
  pass (`-O`) comes later.

## The calling convention

C names get a leading underscore in assembly (`main` is `_main`), as in CMOC. An assembly
routine is callable from C if it follows these rules.

- **Arguments** are pushed right to left. Each is a whole number of 16-bit words: `char` is
  widened to 2 bytes, and `long` takes 4. The caller pops them.
- **Return values:** `char` comes back in B (with D holding the widened value), `int` and
  pointers in D, `long` in Q (D is the high word, W the low one). A struct is returned
  through a hidden pointer pushed after the other arguments, so it comes first.
- **Registers:** a function must keep U, Y, S and DP as it found them. D, W, X and CC are
  scratch. (In native mode an interrupt saves W by itself.)
- **Frame:** `PSHS U` / `TFR S,U` / `LEAS -locals,S`. The arguments are at `4,U` and up and
  the locals below U. Leaving is `LEAS ,U` / `PULS U,PC`. A function that has no locals and
  touches no arguments skips the frame.
- **Variadic functions** (`printf`) use the same layout. `va_start` points just past the
  last named argument.
- **Interrupt functions** (CMOC's `interrupt` keyword) end with `RTI`. They save nothing
  extra, because the CPU's own frame already holds every register.

The full reference, with examples, will go in `cc/README.md` once it's built.

## Program memory layout

The link script (`/LIB/CC.SCR`) makes a `.COM` that loads at `$3400`, just above DOS's RAM
(`DOS_END` is `$33ED` today). Sections go in this order: `init` (CRT0's), `code`, `rodata`,
`data`, `bss`, and `heap` (empty). The heap starts after them, and the stack grows down from
`$EFFF`.

`CRT0.O` sets up the stack, clears `bss`, splits the command line into `argc`/`argv`, calls
`main` and passes its result to `exit()`. The console's `FILE`s need no setting up: they are
initialized data.

### Banked code (overlays)

- **Marking code:** `#pragma bank N` marks a whole file (or `__bank(N)` one function, later),
  and `cc -b N` does the same from the command line. That file's code goes in section
  `ovlN`.
- **The window:** overlays are linked to run in **bank 3, `$C000-$EFFF`**, 12KB each. With
  overlays in the program, the fixed part runs from `$3400` to `$BFFF` (about 35KB), and the
  stack moves to `$BFFF` (`B_BANK_SET` refuses to remap the bank the stack is in).
- **Calling:** for each function a banked file exports, CC1 writes the body under an
  internal name, plus a small stub in fixed memory under the real name:
  `LDB #N` / `LDX #body` / `JMP __farcall`. Every call or function pointer simply uses the
  stub. `__farcall` moves the return address and the current bank-3 page to a small side
  stack, maps the overlay's page, and calls the body. Because the arguments sit where the
  callee expects them, it doesn't need to know it was called through a stub. When the body
  returns, `__farcall` puts the page back and returns. D and W pass through untouched, so
  return values survive. Calls inside the same overlay are direct.
- **On disk:** LINK writes the overlays into the EXE_MORE tail of the `.COM`. CRT0 reads
  them into pages from `B_PAGE_ALLOC` and fills in the table from overlay number to
  physical page.
- **Cost:** each far call goes through `B_BANK_SET` twice (about 100 cycles or more). If
  that turns out to matter, a fast bank-switch entry in the BIOS would help, one that keeps
  its shadow copies correct.

### Banked data

At first, this works through library calls in `<pug/bank.h>`, not a new pointer type:
`page_alloc()`, `page_free()`, `far_peek()`/`far_poke()`, `far_read()`/`far_write()`
(copying between a near buffer and a page and offset, through `B_PAGE_COPY`), and
`bank_map()`/`bank_unmap()` for a program that wants a page in bank 1 or 2 itself. A real
`__far` pointer type can come later.

## The library

The library starts small and is written in assembly. More can be written in C once CC1
works.

| Header | First pass |
|---|---|
| `stdio.h` | `FILE` over the DOS file calls; `stdin`/`stdout`/`stderr`; `fopen`, `fclose`, `fread`, `fwrite`, `fgetc`, `fputc`, `fgets`, `fputs`, `fseek`, `ftell`, `fflush`, `putchar`, `getchar`, `puts`, `remove`, `rename`; `printf`/`fprintf`/`sprintf` with `%d %u %x %X %o %c %s %p %%`, `l`, width, `-`, `0` (no float) |
| `string.h` | `mem*`, `str*`, the common ones |
| `stdlib.h` | `exit`, `atoi`, `atol`, `strtol`, `abs`, `rand`/`srand`, `qsort`. `malloc`/`free` start as a simple first-fit free list over the heap (or a bump allocator, if that comes first), with `sbrk` underneath |
| `ctype.h`, `stdarg.h`, `stddef.h`, `limits.h`, `setjmp.h` | as usual (`setjmp` is short in assembly) |
| `pug/sys.h` | the BIOS and DOS calls directly, including `spawn` (`B_SPAWN`) |
| `pug/bank.h` | banked data (above) |
| `pug/video.h`, `pug/sound.h`, `pug/input.h` | the video card (modes, layers, tiles, sprites, drawing commands), the OPL3 and SONGKIT songs (wrapping `sk_play.asm`), keyboard, mouse and gamepads. This is `LIBPUG.A` |

The headers go in `/INCLUDE` and the libraries in `/LIB` on the disk image.

## Changes to existing software

| Where | Change |
|---|---|
| LINK | Libraries: `-l`/`-L` and lwar `.a` archives, pulling in a member only when it resolves an undefined symbol, as lwlink does. More than 32 input files. Overlay sections, and the EXE_MORE output that carries them. |
| DOS | `B_SPAWN`: X is the path and Y the command tail. DOS swaps the caller's memory (`DOS_END`-`$EFFF`, and the caller's bank mapping) out to free pages, runs the child, and on its `B_EXIT` puts the caller back and returns the child's exit code. `B_EXIT` takes an exit code. Open files and allocated pages belong to the program that opened or allocated them: a child's are closed and freed when it exits, and the parent's stay open. |
| Shell | Shows a program's nonzero exit code. Gets `system()` for free. |
| ASM | Nothing needed, as far as I know. CC1 avoids the expressions ASM refuses (`sym/256` and the like). How fast it runs on the device decides how long a build takes, so it may want looking at. |
| BIOS | Nothing, unless a fast bank-switch entry is wanted (above). |

## Phases

Each phase leaves something that works and is tested.

1. **Runtime and libraries, in assembly** (done): CRT0, the first `LIBC.A`, and LINK's
   library support and `AR.COM`. Assembly programs can use libc right away. The compiler's
   helper routines (16- and 32-bit multiply, divide and shift) moved to phase 2: their
   register interface is the code generator's to decide.
2. **CPP and the core of CC1** (done): `char`, `int`, `unsigned`, pointers, arrays,
   functions, every statement, globals and string literals; `typedef`, `static`, initializers
   for arrays and calls through function pointers came early. The headers, and the library's
   helpers (`lib/arith.asm`). Tests compile C programs on the emulated machine, run them and
   compare what they print.
3. **The rest of the language:** `struct`/`union`, `enum`, `long` (and `fseek`/`ftell`),
   `asm { }`, `interrupt`, brace elision in initializers, `extern` in a block, a local array
   sized by a `{ list }`, and `-9`. (Variadic functions already work, with `<stdarg.h>`.)
4. **`B_SPAWN` and `CC.COM`; overlays** (LINK, CC1's stubs, `__farcall`, CRT0) and
   `<pug/bank.h>`.
5. **`LIBPUG.A`** (video, sound, input), and a demo written in C.
6. **Later:** a better `malloc`, `float` (and `double` as the same type, as in CMOC),
   bitfields, `-O`, and `__far` pointers.

Not planned: K&R-style function definitions, `goto` into a block from outside it with
initialized locals, wide characters, and the parts of C99 CMOC doesn't have.

## Testing

`simulator/tests/test_cc.cpp`, in the pattern of `test_asmlink.cpp`:

- C programs under `simulator/tests/test_cc/` (expressions, control flow, structs, the
  library, overlays), each with its expected output.
- Each is compiled on the emulated machine, run there, and what it prints is compared with
  the expected output. This is done for 6309 and `-9` code alike.
- The `.ASM` that CC1 writes is also assembled by lwasm and must give the same object file
  as ASM gives, so the two assemblers keep checking each other.
- A program that should fail to compile must fail, with the right message, and leave no
  output.

## Found in phase 1

Things that phase 2 onwards has to follow:

- **LINK reads libraries first.** As in lwlink, every `-l` library is read before the plain
  files, wherever it is on the command line, because lwlink's option parser takes the options
  first. So the library's `code` lands before the program's. CRT0 is in `init`, which the
  script places first, so that the program's first byte is its start.
- **lwasm takes no C escapes in strings.** `FCC "a\n"` is four bytes, and ASM ignores
  `PRAGMA`, so `cescapes` can't be turned on. CC1 must write string literals as `FCB`
  bytes.
- **LDQ (and MULD) set Z from bits 31-16 only.** That is the real HD6309's behaviour, and the
  emulator's. A 32-bit test for zero must look at both halves. This matters for `long`
  comparisons and `if (l)`.
- **No `ORE`/`ANDE`.** The 6309's E and F registers have loads, stores, adds, subtracts,
  compares, increments, clears and tests, but no logic operations.
- **Macro arguments end at a space.** In ASM and lwasm, `' '` as a macro argument splits.
  CC1 writes characters as numbers.
- **`B_GETC` doesn't echo,** so libc's console input does its own line editing.
- **DOS's text files end lines with CR** (`B_WRITELINE`) **or CR LF.** libc writes CR LF and
  reads either as `'\n'`.

## Found in phase 2

- **Arguments are expanded before they go into a macro.** CPP first expanded them where they
  landed, marked off in the text. That got `XSTR(N)` (`#define XSTR(x) STR(x)`) wrong, since
  `STR`'s `#` takes the argument before it's scanned. Now each argument a body uses (not next
  to `#` or `##`) is copied above the end of the line and expanded there first, with the call's
  state saved on the stack. The standard's examples all come out as it says.
- **`char` is signed**, so `'\xff'` is -1 and `char c = 200` reads back as -56. CMOC's
  default wasn't checked; `unsigned char` is there for bytes.
- **`DIVD` and `DIVQ` aren't used.** They trap on a zero divisor, and their quotient must fit
  in 15 bits (or 7), so `60000 / 1` overflows. The helpers divide by shifting and subtracting,
  and give -1 for a zero divisor.
- **`TST` leaves the carry alone** (the 6809's way), so a test against 0 is `TSTD` for `==`,
  `!=` and signed comparisons, and `CMPD #0` for unsigned ones.
- **A function's frame size is an `EQU` after it** (`LEAS -L3,S` / `L3 EQU 6`): it's only
  known at the end. The forward reference makes the `LEAS` 16 bits wide, in ASM and lwasm alike.
- **Strings go into `rodata` as they're read,** in the middle of a function's code: `SECTION
  rodata`, a label and `FCB`s, and back to `SECTION code`.
- **`FILE` is a `char` until structs,** and libc's console `FILE`s are C's `_iob` (`__iob` in
  assembly). Programs never look inside a `FILE`, so nothing changes for them when it becomes a
  struct.
