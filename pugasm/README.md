# PUGASM and PUGLINK, the Pugputer's assembler and linker

This folder holds two programs that run on the Pugputer itself. Each is a counterpart of a tool
from William Astle's lwtools 4.20, and each produces the same files for the same input.

- **`PUGASM.COM`** (`pugasm.asm` and the `pa_*.asm` files it includes) is a 6309/6809
  assembler modelled on **lwasm**. It produces the same bytes, listings and symbol tables, and
  the same LWOBJ object files.
- **`PUGLINK.COM`** (`puglink.asm`) is a linker modelled on **lwlink**. It produces the same
  S-records, raw binaries and maps from the same object files and link script.

Together they build everything in this project on the Pugputer, identical to the lwtools
build: the shell, the editor, DOS and BASIC, the BIOS from its eight object files and link
script, and both tools themselves.

## PUGASM

```
PUGASM [options] file
  -f FMT, --format=FMT        raw (the default), srec, com, or obj
  -o FILE, --output=FILE      the output (default: the source's name with .BIN, .S19, .COM or .O)
  -l[FILE], --list[=FILE]     a listing (default: the source's name with .LST)
  -s, --symbols               the symbol table at the end of the listing
  -I DIR, --includedir=DIR    another place INCLUDE looks (up to 4)
  -3, --6309 (the default)    -9, --6809
```

For example, on a disk that holds the shell's source and `defines.d`:

```
/> PUGASM -o SHELL.COM -l -s shell.asm
```

### Output formats

- **raw**: the bytes from the first one emitted to the last. Space reserved in between (`RMB`)
  is written as zeros, as lwasm does.
- **srec**: Motorola S-records (S1 data, and an S9 with `END`'s address). The S0 header
  names the tool (`[pugasm 1.0] file`), so it is the one record that differs from lwasm's.
- **com**: a Pugputer program. This is raw output with the 8-byte program header in front:
  "PX", the load address (the first byte's), the entry address (`END`'s operand, or else the
  load address), and flags 0. Type its name at the shell to run it. The project's programs
  (like `pugasm.asm` itself) write their own header in the source, so for them use raw
  output named `.COM`.
- **obj**: an LWOBJ16 object file for PUGLINK (or lwlink), byte for byte what lwasm writes.
  See below.

A source with errors produces no output file and no listing, as with lwasm. Each error
appears on the console as `file(line) : ERROR : message` followed by the line, and a count
comes at the end.

### Object files

With `-f obj` the code goes into sections, and the linker decides where each one goes:

```
        SECTION code            (or SECT; a section can be left and taken up again)
        ...
        ENDSECTION              (or ENDSECT)
start   EXPORT                  (or EXPORT start,other,...)
greet   IMPORT                  (or IMPORT a,b / EXTERN / EXTERNAL)
```

A section named `bss` (or given the `bss` flag, `SECTION name,bss`) only reserves space. A
section named `_constants` (or given `constant`) holds constants that other files can import.

An address in a section is relative to the section, and an imported symbol has no value until
the link. Values made from them work as in lwasm:
- They are sized as unknown, so an instruction gets its extended or 16-bit form unless you
  force it with `<`.
- Their bytes go out as zeros, with a relocation record that the linker completes.
- A difference of two addresses in one section, such as a branch or `,PCR` within a section,
  is an ordinary constant.

Relocatable values can be sums, differences and constant multiples of section addresses and
imports: `ext+2`, `label-*`, `2*table`, `data2-code1`, and so on. That covers everything lwasm
itself turns into a simple relocation. Anything else is refused with "Incomplete expression too
complex": for example `ext/256` or `label&$FF`, or a 32-bit `FQB` of a relocatable value. lwasm
would write a formula for lwlink to work out in those cases.

### What it understands

It supports everything this project uses, and most of lwasm besides:

- **Instructions:** all of lwasm's 6809 and 6309 mnemonics (the table is generated from
  lwasm's `instab.c` by `gen_itab.py`) in every addressing mode, including the 6309
  `W`/`E`/`F` registers, `TFM`, the bit operations (`BAND`, `LDBT`, ...) and `AIM`/`OIM`/...
  With `-9`, the 6309 operations and registers are errors, and the 6809-only `HCF`/`RESET`
  are allowed.
- **Sizing:** it follows lwasm's default rule (`forwardrefmax`). A symbol not yet defined
  when a line is reached gets the largest form (extended, or a 16-bit offset). Known values
  pick the direct page (`SETDP`), 5- and 8-bit offsets, and short branches, all exactly as
  lwasm picks them. Forcing with `<`, `>` and `<<` works as in lwasm.
- **Expressions:** lwasm's operators and precedence (`+ - * / % \`, `& | ^ !`, `&& ||`,
  unary `- ~ ^`), and all its number forms (`$1F`, `0x1F`, `1Fh`, `%101`, `101b`, `@17`, `17o`,
  `17q`, `&10`, `'A`, `"AB`). `*` and `.` mean the current address.
- **Symbols:** case-sensitive names up to 63 characters; local labels (names containing `@`,
  `?` or `$`), scoped between blank lines; `SET` symbols redefined as often as
  wanted; `EQU` of things defined later.
- **Directives:** `ORG EQU = SET SETDP FCB FDB FQB FCC FCN FCS RMB RMD RMQ ZMB ZMD ZMQ FILL
  ALIGN END INCLUDE INCLUDEBIN`, the conditionals (`IFEQ IFNE IFGT IFGE IFLT IFLE IF IFDEF
  IFNDEF ELSE ENDC`, nested), `MACRO`/`ENDM` (arguments `\1`..`\9`, `{n}`, `\0` the name,
  `\*` all, `\#` how many; the `noexpand` option), `STRUCT`/`ENDSTRUCT` (nested, with
  `sizeof{...}`), `ERROR`, `WARNING`, and the object-file ones above (`EXTDEP` too). `PRAGMA`
  is accepted and ignored.
- **Not supported:** lwasm's OS-9 module directives (`MOD`, `EMOD`, `OS9`) and a few rarely
  used ones (`IFP1`, `IFP2`, `IFPRAGMA`, `IFSTR`, `SETSTR`, `INCLUDESTR`, `REORG`, `DTB`, `DTS`,
  `FDBS`).

### Limits

- Source lines up to 255 characters (the rest is dropped), and 8 levels of nested `INCLUDE`
  files and macro calls.
- Symbols, macros, saved expressions and an object file's sections live in banked RAM pages
  (from `B_PAGE_ALLOC`, 12KB of each used). It takes as many pages as the source needs, up to
  48 (about 580KB).
- An object file can have up to 16 sections, and a relocatable value up to 4 terms.
- Names on the disk are 8.3. An `INCLUDE` is looked for next to the file that includes it,
  then in each `-I` directory.

### How it works

It uses two passes, reading the source from the disk each time, with a small buffer per open
file:

1. Pass 1 decides every line's size and defines the symbols, as lwasm's first pass does. An
   instruction whose operand isn't known yet gets the largest form.
2. Pass 2 does it all again and writes the output and the listing. So that each line gets the
   size pass 1 gave it, operands are evaluated twice. For sizing, any symbol defined at or
   after the current line counts as unknown. For the bytes, everything is known.

`EQU`s that can't be evaluated yet keep their expression and evaluate it when used. Lines
after an `RMB` of a not-yet-known size have addresses that pass 1 doesn't know exactly either.
Those are tracked the way lwasm tracks them, so the choices come out the same.

For object output, a value carries its relocatable part along with its constant part: a list
of "terms", each a coefficient times a section's base or an import. `+`, `-` and `*` by a
constant combine the terms, and like terms merge. A value with terms left at the end is
relocatable. Each section's bytes and relocation records are kept in banked RAM, and the
object file is written at the end in lwasm's layout and order.

The memory map while it runs: the direct page is at `$3400`, the code at `$3500` (about 22KB),
then its buffers, and the stack below `$C000`. Heap pages are mapped one at a time into bank 3
(`$C000`-`$EFFF`).

## PUGLINK

```
PUGLINK [options] file.o ...
  -f FMT, --format=FMT        raw (the default), srec, or com
  -o FILE, --output=FILE      the output (default A.OUT)
  -m FILE, --map=FILE         a map: the sections, then every symbol with its address
  -s FILE, --script=FILE      the link script (default: lwlink's own, for the format)
  -e SYM, --entry=SYM         the entry point: a symbol, or a hex address
  --section-base=SECT=ADDR    a section's load address (with the default script)
  -r                          the same as -f raw
  @FILE                       more arguments, from a file
```

The shell's command line holds 79 characters, which a link of several files soon outgrows.
`@FILE` reads arguments from a file, in which spaces and line ends both separate them. The
BIOS, for instance:

```
BIOS.RSP:  -f srec -o PUGBIOS.S19 -m PUGBIOS.MAP -s LINK.SCR
           helpers.o devio.o serio.o sdcard.o time.o loader.o banks.o main.o

/> PUGLINK @bios.rsp
```

### Output formats

- **raw**: each placed section's bytes, one after another (bss sections are left out), as
  lwlink writes them.
- **srec**: S1 records of up to 16 bytes from each section's load address, then an S9 with
  the entry point, as lwlink writes them (no S0).
- **com**: a Pugputer program. This is the raw output with the 8-byte program header in front:
  the load address is the first section's, and the entry is the script's or `-e`'s, if any
  (otherwise the load address). The sections should follow one another in memory, as a
  script with one `load` places them. This format is PUGLINK's own; lwlink has no equivalent.

### Link scripts

A script has one statement per line, and `#` or `;` starts a comment line. A line must not
begin with a space, as in lwlink.

```
section NAME[,bss|,!bss] [load ADDR | high ADDR]
entry ADDR  |  entry SYMBOL
define basesympat PATTERN     (e.g. s_%s: a symbol for each section's start)
define lensympat PATTERN      (e.g. l_%s: and one for its length)
pad N / stacksize N           (accepted and ignored)
```

Sections are placed in the order the script lists them, each from the last `load` address
onwards (or downwards from a `high` address). A named line places every file's section of that
name. `section *` places each section not placed yet, with the flags asked for, together with
all others of its name. Without `-s`, PUGLINK uses lwlink's built-in script for the format:
`raw` places `init` at 0, then `code`, then everything else; `srec` does the same from `$0400`
with `entry __start`. `--section-base` lines come before it. A constant section is placed at
0 as soon as something imports from it, the way lwlink handles it.

### Differences from lwlink

- No libraries (`-l`, `-L`, `.a` archives), no `sectopt`, and no DECB, OS-9 or LWEX formats.
  The `com` format and `@FILE` are PUGLINK's own.
- A section is placed once. lwlink places a section again when the script names it twice.
  For example, `--section-base=code=ADDR` with the default script (which also names `code`)
  makes lwlink write the code twice.
- Up to 32 input files and 32 script lines. Symbol and section names are kept to 127
  characters, and a map lists up to 4,000 symbols.

### How it works

- **Reading:** each object file is read as a stream into banked RAM. That covers its
  sections, their symbols and exports, their relocation expressions, and their bytes (in 1KB
  chunks).
- **Placing:** the script places the sections. Then each relocation's expression is worked out
  with the final addresses: lwlink's postfix terms and operators, in C `int` arithmetic.
- **Resolving:** names resolve as in lwlink. A local reference looks in its own section first,
  then in its file's other sections. An external one looks among the synthetic symbols first,
  then in its own file's exports, then in every file's in order.
- **Writing:** the value is patched into the bytes. Then the output is written, and the map
  (sorted with a heap sort in banked RAM, by name and then by file, as lwlink sorts it).
- **Size:** PUGLINK is about 7KB.

## The files

| File | What it holds |
|---|---|
| `pugasm.asm` | PUGASM: the header, the variables, the main flow (the command line, two passes, the end). |
| `puglink.asm` | PUGLINK, all of it (with `pa_util`, `pa_heap` and `pa_strm`). |
| `pa_util.asm` | Console output, strings, character classes, 32-bit multiply and divide. (Both.) |
| `pa_heap.asm` | The banked-RAM heap (far pointers: a page number and an address). (Both.) |
| `pa_strm.asm` | Buffered output files. (Both.) |
| `pa_io.asm` | The command line, the input stack (files and macros), finding `INCLUDE` files. |
| `pa_sym.asm` | The symbol table (hashed, in the heap), local-label contexts, `SET` versions, saved expressions. |
| `pa_expr.asm` | Expressions and numbers. |
| `pa_line.asm` | One source line: label, operation and operand; emitting bytes; errors; the listing line. |
| `pa_insn.asm` | The instruction classes and addressing modes. |
| `pa_dir.asm` | The directives: data, space, conditionals, macros, structs. |
| `pa_obj.asm` | Object output: relocatable terms, sections, IMPORT/EXPORT, the LWOBJ16 file. |
| `pa_out.asm` | The output files, S-records, the symbol-table listing, error messages. |
| `pa_itab.asm` | The operation table (generated by `gen_itab.py` from lwasm's `instab.c`; don't edit). |

## Building and testing

`compile.bat` assembles both with lwasm (`pugasm.bin`, `puglink.bin` and their listings).
`build_all.bat` and `reinit_disk.bat` do this too, and put them on the disk image as
`PUGASM.COM` and `PUGLINK.COM`.

`simulator/tests/test_pugasm.cpp` runs them on the emulated machine and checks the following,
comparing byte for byte (and listing line for listing line) with the lwtools build:

- PUGASM assembles the shell, the editor, DOS (raw), BASIC (S-records) and the BIOS's eight
  modules (object files).
- PUGLINK links the BIOS's objects to `pugbios.s19` and `pugbios.map`.
- The whole BIOS builds on the Pugputer, from source.
- PUGASM makes a copy of itself (and that copy makes another), and a copy of PUGLINK that
  links the BIOS.
- What they make runs, and errors are reported and leave no files.
- With lwtools available, the sources in `simulator/tests/test_asm/pugasm` must match lwasm
  and lwlink too:
  - every operation in every operand form, for each CPU (generated by `gen_allops.py`);
  - a file of directives, macros and expressions;
  - object files (`objf.asm`, `objexpr.asm`);
  - links of `objf.o` and `prov.o` with the default scripts, a script of its own
    (`link1.scr`), `--section-base` and `-e`.
