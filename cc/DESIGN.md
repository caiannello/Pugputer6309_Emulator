# CC: a C compiler for the Pugputer (design)

Status: phases 1 to 5 done (2026-11-19/20). Phase 1: LINK's libraries, AR, CRT0
and the first libc. Phase 2: CPP, and CC1 with `char`, `int`, pointers, arrays, functions,
`typedef` and every statement and operator. Phase 3: `long`, `struct`, `union`, `enum`,
`asm { }`, `interrupt` and the rest of the declarations and initializers. Phase 4: children
(DOS's `B_EXEC` with `EXEC_CHILD`, libc's `spawn()`), `CC.COM`, banked code and
`<pug/bank.h>`. Phase 5: `LIBPUG.A` (`<pug/video.h>`, `<pug/input.h>`,
`<pug/sound.h>`) and SWAMPFLY, a demo in C. Phase 6 (2026-11-20), the first part: `float`
and `double` (IEEE single), `_Bool`, `<stdint.h>`, `<stdbool.h>`, `<float.h>`, `<math.h>`,
scanf, `atof`/`strtod`, printf's floats, and CC's signs of life as it works. See
[`README.md`](README.md) for what is there now, and the "Found in phase" sections at the end
for what each settled. Decisions taken so far (2026-11-19):

- The compiler is written in **6309 assembly**, like ASM and LINK. It is built with lwtools
  on the PC to bootstrap, and can be rebuilt on the Pugputer with ASM and LINK.
- It accepts **CMOC's C dialect** (including `asm { }` blocks and the pragmas that make sense
  here), but uses **its own calling convention**, made for the 6309. Its output is not meant
  to match CMOC's.
- One command, `CC`, compiles, assembles and links. That needed DOS to run a program as a
  child: **`B_SPAWN`**, which became `B_EXEC` with `E = EXEC_CHILD` (see "Found in phase 4").
- **Banked code works automatically:** a file or function is given a bank, LINK puts it in an
  overlay page, and calls to it go through generated trampolines.

## The pipeline

```
FOO.C --CPP--> FOO.I --CC1--> FOO.ASM --ASM -f obj--> FOO.O --LINK--> FOO.COM
                                                      CRT0.O, LIBC.A, LIBPUG.A
```

| Program | What it does |
|---|---|
| `CC.COM` | The driver. It runs each stage with `B_SPAWN`, deletes the temporary files and stops at the first error. Options: `-c` (stop at `.O`), `-S` (stop at `.ASM`), `-E` (stop at `.I`), `-o`, `-I`, `-L`, `-l`, `-D`, `-9` (6809 code only, later), `-O` (peephole pass, later). |
| `CPP.COM` | The C preprocessor: `#include`, `#define` (object-like and function-like, with `#` and `##`), `#if`/`#elif` with `defined`, `#ifdef`, `#line`, `#error`, `#pragma` passed through. Writes `#line` markers so CC1 can report errors against the original file. |
| `CC1.COM` | Parses one preprocessed file and writes lwasm-syntax assembly with `SECTION`/`EXPORT`/`IMPORT`. |
| `ASM.COM`, `LINK.COM` | The existing ones, with the LINK changes listed below. |
| `AR.COM` | New: a librarian for lwar-compatible `.a` archives, so that lwlink on the PC can read them too. |

CPP and CC1 are separate programs because each must fit in the space a program gets
($3400-$EFFF, about 47KB) together with its buffers. CPP's macros live in banked RAM through
`pa_heap.asm`, as ASM's symbols do. CC1 (25KB of code since phase 6) keeps its names, types
and symbols in a 12KB heap of its own for now; they can move to banked RAM if programs
outgrow it. `CC1 -M` says how close a file came (see "Found in phase 6").

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
  initializers and struct copies (`__scopy`); `NEGD`, `COMD`, `LSLD`, `ASRD`, `TSTD`; Q for
  `long` (`LDQ`, `STQ`, `ADDW`/`ADCD`, `SUBW`/`SBCD`, `ORR W,D`, `SEXW`). W as a second
  accumulator, and `AIM`/`OIM`/`EIM`, are for the peephole pass. `/`, `%` and shifts by a
  variable call the library's helpers (`lib/arith.asm`, `lib/larith.asm`), not `DIVD`/`DIVQ`
  (see "Found in phase 2").
- **Longs and structs** have their own generator (`cc1_long.asm`): a `long` is made in Q, a
  struct's value is its address in D.
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

- **Marking code:** `#pragma bank N` (1 to 15) puts the functions after it in overlay N, up
  to the next `#pragma bank` (`0`: fixed code), and `cc -b N` (CC1's `-b N`) starts a file
  that way. Their code goes in section `ovlN`; their data, strings and statics stay fixed.
- **The window:** overlays are linked to run in **bank 3, `$C000-$EFFF`**, 12KB each. With
  overlays in the program, the fixed part runs from `$3400` to `$BFFF` (about 35KB), and the
  stack moves to `$BFFF` (`B_BANK_SET` refuses to remap the bank the stack is in).
- **Calling:** for each banked function, CC1 writes the body as `__b_name`, and a small stub
  in fixed memory under the real name: `LDB #N` / `LDX #__b_name` / `JMP __farcall`. Every
  call or function pointer simply uses the stub. `__farcall` moves the return address and the
  current bank-3 page to a small side stack, maps the overlay's page, and calls the body.
  Because the arguments sit where the callee expects them, it doesn't need to know it was
  called through a stub. When the body returns, `__farcall` puts the page back and returns. D
  and W pass through untouched, so return values survive. A call from the same overlay to a
  body this file has defined is direct.
- **On disk:** LINK writes the overlays after the `.COM`'s body (EXE_MORE): for each `ovlN`
  section, `FCB N`, `FDB` its address and size, its bytes; then `FCB 0`. CRT0's start falls
  through `init_ovl`, which `farcall.asm` fills (and is empty without it): the stack moves
  below `$C000`, and each overlay is read into a page from `B_PAGE_ALLOC`, the table from
  overlay number to page filled in. `exit()` falls through `fini_ovl` the same way, which
  frees the pages.
- **Cost:** each far call goes through `B_BANK_SET` twice (about 100 cycles or more). If
  that turns out to matter, a fast bank-switch entry in the BIOS would help, one that keeps
  its shadow copies correct.

### Banked data

At first, this works through library calls in `<pug/bank.h>`, not a new pointer type:
`page_alloc()`, `page_free()`, `far_peek()`/`far_poke()`, `far_read()`/`far_write()`
(copying between a near buffer and a page and offset, through `B_PAGE_COPY`), and
`bank_get()`/`bank_map()` for a program that wants a page in bank 1 or 2 itself (done so in
phase 4). A real `__far` pointer type can come later.

## The library

The library starts small and is written in assembly. More can be written in C once CC1
works.

| Header | First pass |
|---|---|
| `stdio.h` | `FILE` over the DOS file calls; `stdin`/`stdout`/`stderr`; `fopen`, `fclose`, `fread`, `fwrite`, `fgetc`, `fputc`, `fgets`, `fputs`, `fseek`, `ftell`, `fflush`, `putchar`, `getchar`, `puts`, `remove`, `rename`; `printf`/`fprintf`/`sprintf` with `%d %u %x %X %o %c %s %p %%`, `l`, width, `-`, `0` (floats and scanf: phase 6) |
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
| LINK | Libraries: `-l`/`-L` and lwar `.a` archives, pulling in a member only when it resolves an undefined symbol, as lwlink does. More than 32 input files (phase 1). Overlay sections (`ovlN`), and the EXE_MORE output that carries them (phase 4). An exit code. |
| DOS | (Phase 4.) `B_EXEC` with `E = EXEC_CHILD` runs a child: X is the path and Y the command tail. DOS keeps the caller's memory (its pages in banks 1 to 3 stay as they are, the child gets three new ones; `$3400-$3FFF` and a record go in another page), runs the child, and on its `B_EXIT` puts the caller back, B = the child's exit code. `B_EXIT` takes an exit code in B. Open files and directory scans belong to the program that opened them: a child's are closed when it exits, and the parent's stay open. (Pages a child allocates itself are not freed for it: no room in DOS for that.) |
| Shell | Clears E for `B_EXEC`. (Showing a program's exit code, and `system()`, are left: the shell isn't told the code when a program ends at the top level.) |
| CPP, CC1, ASM, LINK, AR | Exit codes: 0, or 1 when something failed (CC.COM goes by them). |
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
3. **The rest of the language** (done): `struct`/`union`, `enum`, `long` (and
   `fseek`/`ftell`, `atol`, `labs`), `asm { }`, `interrupt`, brace elision in initializers,
   `extern` in a block, a local array sized by a `{ list }`. (`-9` moved to "Later".)
4. **Children, `CC.COM`, overlays** (done): DOS's `B_EXEC` with `EXEC_CHILD` and `B_EXIT`'s
   exit code, libc's `spawn()` (`<pug/sys.h>`), the tools' exit codes, `CC.COM`; `#pragma bank`
   and `-b` (CC1's stubs), LINK's overlay output, `__farcall` and its loader, and
   `<pug/bank.h>`.
5. **`LIBPUG.A`** (video, sound, input), and a demo written in C (done: `SWAMPFLY.C`).
6. **Floating point and the rest of the library** (the first part done, 2026-11-20): `float`
   and `double` (the same type, as in CMOC: IEEE single), `_Bool`, `<stdint.h>`,
   `<stdbool.h>`, `<float.h>`, `<math.h>`, scanf and its family, `atof` and `strtod`, printf's
   `%e %f %g` (and its `+`, space and `#`), CC's banner and a line for each stage (`-q` for
   none). Chosen before a better malloc and `-9` (2026-11-20), so that the system can be used
   for a while first.
7. **Later:** a better `malloc`, bitfields, `-O`, `__far` pointers, memory for CC1 beyond its
   12KB heap (banked RAM), more overlays at `$C000` than 15 (agreed; see the end), and `-9`: plain 6809 code. That
   needs a second way of holding a `long` (there's no Q) and a 6809 build of the library, for
   its code to run on a 6809 at all; the Pugputer always has a 6309, so it waits (decided
   2026-11-19).

Not planned: K&R-style function definitions, `goto` into a block from outside it with
initialized locals, wide characters, and the parts of C99 CMOC doesn't have.

## Testing

`simulator/tests/test_cc.cpp`, in the pattern of `test_asmlink.cpp`:

- C programs under `simulator/tests/test_cc/` (expressions, control flow, structs, the
  library, overlays), each with its expected output.
- Each is compiled on the emulated machine, run there, and what it prints is compared with
  the expected output. (With `-9`, later, for 6809 code too.)
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
- **`FILE` was a `char` until structs,** and libc's console `FILE`s are C's `_iob` (`__iob` in
  assembly). Programs never look inside a `FILE`, so nothing changed for them when it became a
  struct (phase 3: an undefined one).

## Found in phase 3

- **A long's comparisons are a subtraction.** `SUBW` then `SBCD` leaves the flags that `<`
  and `>=` need (signed: N and V; unsigned: C), but Z is the high word's alone (as with `LDQ`),
  so `==` and `!=` add `ORR W,D`. `a > b` is made as `b < a`, and `a <= b` as `b >= a`.
- **The long helpers keep X,** so that `x op= y` can keep x's address in X across the call.
  They take the right side on the stack, and the caller pops it.
- **A struct is passed by its bytes,** rounded up to words; one returned goes through a hidden
  pointer to a temporary in the caller's frame (a block's, made when the call is parsed).
  `f().m` works on that temporary's address.
- **Member access is `*(T *)(&s + offset)`,** which OPND and GENADDR already knew as `n,U`,
  `_s+n` and `n,X`, so `s.m` and `p->m` cost nothing new. `(&x + n) + m` is folded to one
  offset, so nested members do too.
- **An initializer is one walk for data and for code:** the object's bytes are done in order,
  so a gap is zeros (`ZMB`, or `CLR`/`TFM` in code). Brace elision is a list that stops when its
  aggregate is full and leaves the comma to the list around it.
- **A local array sized by `{ list }`** is made in `rodata` and copied: its size is only known
  at the list's end, and the frame offsets are needed before.
- **DOS's `fseek` offsets are signed** for `SEEK_CUR` and `SEEK_END`. DOS took a carry out of
  the addition as "too big", which every negative offset gives; it tests the sign now.
- **`asm { }` names:** a register's name only means the register next to a comma or `-`, or
  after PSHS, TFR and the like; on its own (`ldd x`) it's a C name if there is one.
- **Line endings:** `.gitattributes` has `* -text`, so a tool that writes CR LF changes every
  line of an LF file. Edit sources byte for byte.

## Found in phase 4

- **No new call numbers.** The BIOS numbers its own calls straight after the DOS's, and BASIC
  hard-codes some, so a new DOS call would have moved `B_BANK_SET` and the rest. `B_SPAWN` is
  `B_EXEC` with `E = EXEC_CHILD` instead (E was ignored before; the shell now clears it), and
  the exit code comes back in B, written into the caller's SWI2 frame (`B_EXEC`'s outputs
  are fixed in the ROM).
- **DOS had 19 bytes to spare** below `$3400`. Its start-up code (and the table it copies into
  the BIOS) now sits in the first file buffer, which nothing uses until it's done: 400 bytes
  back. A child's record lives in DOSBUF while it's made, then in a page of its own, so DOS's
  RAM grew by 8 bytes. An `IFGT` stops a DOS that would pass `$3400`.
- **Owners are levels:** a file slot's or directory scan's `inuse` byte is its program's level
  + 1, and `B_EXIT` closes those at its level or deeper.
- **Pages aren't owned:** the BIOS hands them out, and DOS has no room to track them, so a
  child's own pages stay allocated (as a top-level program's always have). libc frees the
  overlays' pages itself, at `exit()`.
- **The tools' exit codes:** each `B_EXIT` sets B (it was whatever B held).
- **Fall-through sections** let a library module add start-up and exit code only when it's
  linked: CRT0 is `init` / `init_ovl` / `init_end` and `fini` / `fini_ovl` / `fini_end`.
  `init_ovl` runs before bss is cleared, so its state is in `data`.
- **`@` makes a local label** in ASM and lwasm, so a body can't be `_name@b`; it is `__b_name`.
- **The overlay records end with one 0 byte,** so the loader takes a short read there.

## Found in phase 5

- **LIBPUG is thin:** the card is registers, data ports and commands, so most calls are a
  port's address and a few bytes. Everything uses data port 0 (and the command port), leaving
  port 1 to an interrupt handler.
- **SONGKIT's player goes in as it is.** `pugsnd.asm` includes `gamekit/sk_play.asm`, which
  now has an `IFDEF SK_LIBRARY` that ends the code section and starts bss before its
  variables (1.1KB that would otherwise be zeros in the program). SONGKIT, SONGPLAY and SWAMP
  assemble as before.
- **Keeping the song going:** its ticks need polling every few ms. `song_start` points
  `vc_idle` at `song_poll`, and `vc_vsync` calls it while it waits, so a frame loop needs
  nothing more. The video module doesn't refer to the sound module, so a program without
  music doesn't link the player.
- **`-lpug` always:** CC gives LINK both libraries, and LINK (like lwlink) warns about a
  library that resolves nothing, so it has `--quiet-libs`, which CC passes.
- **The C demo is compiled on the Pugputer.** There is no CC on the PC, so `SWAMPFLY.C` goes
  on the disk as source (`CC swampfly.c`, about 25 s on the machine), and the test compiles
  and runs it on the emulated one.
- **pugrun has `--video`:** the video card (with no window) and the OPL3 on the bus.
- **The emulator's card takes key events from the test** (`VideoDevice::key`), not from the
  UART, while a program has grabbed the keys.

## Found in phase 6

- **A float lives in Q, as a long does.** So every move of one (loads, stores, arguments,
  results, `?:`, assignment) is the long code's, and `TISQ` (a long or a float) replaced
  `TISLONG` wherever only the size mattered. The type kinds were renumbered, `TK_FLOAT` between
  `TK_ULONG` and `TK_PTR`, so that `TISSCALAR` (char to pointer) takes it and `USUALTYPE`'s
  "the greater kind" still works. A `long` and a `float` are held alike but aren't the same
  class: `MKCONVERT` casts whenever the class (`TCLASS`: in D, a long, a float) differs.
- **One floating-point core, two users.** `lib/fpcore.asm` has no sections and keeps to the
  stack, so `float.asm` (the library's member) and CC1 include the same file: a constant CC1
  folds has the bits the program would have made. It's checked against the PC's IEEE single
  precision bit for bit, on the CPU alone (`test_float.cpp`). There are no denormals (it
  flushes to 0); near FLT_MIN that differs from IEEE, which rounds a denormal back up.
- **Decimal is scaled by powers of ten in 32-bit mantissas** (10^1, 10^2 ... 10^64 and their
  inverses, each correctly rounded), so a constant, `strtod` and printf's digits take at most
  seven multiplications: correctly rounded in all but about 1 in 700 cases (a unit in the last
  place off then). `__fxint` (round(x * 10^k), ties to even when they're exact) gives printf
  its digits; 9 significant ones are exact, more are zeros.
- **printf mustn't grow for everyone.** Its float conversion is a hook in CRT0's data
  (`__pfhook`, and scanf's `__sfhook`), set by `fltio.asm`'s part of the start (`init_flt`, a
  third fall-through section). `fltio.asm` is linked only when CC1 refers to `__fltused`: when
  a float or a pointer to one is passed to `...` or to a function with no prototype. An
  `IMPORT` nothing uses doesn't reach the object file, so CC1 writes `FDB __fltused` in
  `rodata` (2 bytes) to make it real.
- **The helpers' bitmap grew to 32 bits** (`HELPERS`): 11 float helpers and `__fltused`.
- **`i op= 1.5`** with an integer `i` is rewritten `i = i op 1.5` (C does it in floats, then
  converts back); `i` is worked out twice.
- **CC1's memory:** each function a header declares costs about 50 bytes of heap (its name,
  symbol, type and parameter list), so scanf's and stdlib's new prototypes took 460 bytes from
  SWAMPFLY's room, and `<math.h>` takes 1.2KB. `CC1 -M` measured the stack: SWAMPFLY uses 166
  bytes of the 3KB that was kept for it, and very deep nesting (60 parentheses, 25 blocks) 823.
  So the stack's room is 1.5KB now, with a check (`STKCHK`, in the parser's recursions) that
  makes too deep an error ("expression too complex") instead of a crash, and the heap is 12KB.
  Smaller buffers (a 512-byte string literal at most, 400 nodes, 128 cases a switch) paid for
  fpcore. `test_cc.cpp` checks that SWAMPFLY leaves at least 2KB.
- **CC's progress:** a banner and one short line as each stage starts, so a long one (ASM is
  the slowest, about 7 s for a few hundred lines) is seen to be working, and an error comes on
  its own line after the stage it's from. `-q` is quiet.
- **Names are 8.3 on the disk:** `cc1_float.asm` couldn't be included by ASM on the Pugputer
  (the rebuild test caught it); it's `cc1_flt.asm`.

### Banked code: what limits it now

Overlays are linked to run in bank 3 at `$C000-$EFFF` (12KB: `$F000` up is the BIOS's and the
I/O's), each in a page of its own, numbered 1 to 15. Neither number is fundamental:

- **15 overlays** is only where the names stop: CC.SCR lists `ovl1` to `ovl15`, CC1's `-b` and
  `#pragma bank` accept 15 at most, and `farcall.asm`'s table has 16 entries. With 64 pages of
  RAM (and DOS's, the program's three and the data pages), 40 or more would fit; raising it is
  those three places. **Agreed (2026-11-20): more overlay pages at `$C000` is the way to grow
  banked code** (the window and its 12KB stay as they are), when it's wanted.
- **12KB each** wastes a quarter of each 16KB page. Running overlays in bank 2 (`$8000-$BFFF`)
  would give them whole pages, but the fixed part (code, data, bss and the heap) would have
  only `$3400-$7FFF` (19KB) instead of 35KB, and the stack would have to live there too; bank 3
  for overlays keeps more for data. A program could also pick the window (a link-script and
  `farcall.asm` choice), or overlays could be packed two to a page at different addresses.
- So 15 x 12KB = 180KB of banked code, plus about 35KB fixed, today: chosen to leave the fixed
  part room for working data, and it can grow without changing the scheme.
