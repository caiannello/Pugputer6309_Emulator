# PUGASM, the Pugputer's assembler

`PUGASM.COM` (`pugasm.asm` and the `pa_*.asm` files it includes) is a 6309/6809 assembler that
runs on the Pugputer itself. It is modelled on **lwasm** from William Astle's lwtools 4.20, and
for the same source it produces the same bytes, the same listing and the same symbol table. It
assembles everything in this project (the shell, the editor, DOS, BASIC, and itself) to files
identical to lwasm's.

```
PUGASM [options] file
  -f FMT, --format=FMT        raw (the default), srec, or com
  -o FILE, --output=FILE      the output (default: the source's name with .BIN, .S19 or .COM)
  -l[FILE], --list[=FILE]     a listing (default: the source's name with .LST)
  -s, --symbols               the symbol table at the end of the listing
  -I DIR, --includedir=DIR    another place INCLUDE looks (up to 4)
  -3, --6309 (the default)    -9, --6809
```

For example, on a disk that holds the shell's source and `defines.d`:

```
/> PUGASM -o SHELL.COM -l -s shell.asm
```

## Output formats

- **raw**: the bytes from the first one emitted to the last. Space reserved in between (`RMB`)
  is written as zeros, as lwasm does.
- **srec**: Motorola S-records (S1 data, and an S9 with `END`'s address). The S0 header
  names the tool (`[pugasm 1.0] file`), so it is the one record that differs from lwasm's.
- **com**: a Pugputer program. This is raw output with the 8-byte program header in front:
  "PX", the load address (the first byte's), the entry address (`END`'s operand, or else the
  load address), and flags 0. Type its name at the shell to run it. The project's programs
  (like `pugasm.asm` itself) write their own header in the source, so for them use raw
  output named `.COM`.

A source with errors produces no output file and no listing, as with lwasm. Each error
appears on the console as `file(line) : ERROR : message` followed by the line, and a count
comes at the end.

## What it understands

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
  `sizeof{...}`), `ERROR`, `WARNING`. `PRAGMA` is accepted and ignored.
- **Not (yet):** object files, and the directives that only make sense with them (`SECTION`,
  `EXPORT`, `IMPORT`, `EXTERN`, `EXTDEP`; these give "Only supported for object target").
  Also missing are lwasm's OS-9 module directives (`MOD`, `EMOD`, `OS9`) and a few rarities
  (`IFP1`, `IFP2`, `IFPRAGMA`, `IFSTR`, `SETSTR`, `INCLUDESTR`, `REORG`, `DTB`, `DTS`, `FDBS`).

## Limits

- Source lines up to 255 characters (the rest is dropped), and 8 levels of nested `INCLUDE`
  files and macro calls.
- Symbols, macros and saved expressions live in banked RAM pages (from `B_PAGE_ALLOC`, 12KB
  of each used). It takes as many pages as the source needs, up to 48 (about 580KB).
- Names on the disk are 8.3. An `INCLUDE` is looked for next to the file that includes it,
  then in each `-I` directory.

## How it works

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

The memory map while it runs: the direct page is at `$3400`, the code at `$3500` (about 19KB),
then its buffers, and the stack below `$C000`. Heap pages are mapped one at a time into bank 3
(`$C000`-`$EFFF`).

| File | What it holds |
|---|---|
| `pugasm.asm` | The header, the variables, the main flow (the command line, two passes, the end). |
| `pa_util.asm` | Console output, strings, character classes, 32-bit multiply and divide. |
| `pa_heap.asm` | The banked-RAM heap (far pointers: a page number and an address). |
| `pa_io.asm` | The command line, buffered output streams, the input stack (files and macros), finding `INCLUDE` files. |
| `pa_sym.asm` | The symbol table (hashed, in the heap), local-label contexts, `SET` versions, saved expressions. |
| `pa_expr.asm` | Expressions and numbers. |
| `pa_line.asm` | One source line: label, operation and operand; emitting bytes; errors; the listing line. |
| `pa_insn.asm` | The instruction classes and addressing modes. |
| `pa_dir.asm` | The directives: data, space, conditionals, macros, structs. |
| `pa_out.asm` | The output files, S-records, the symbol-table listing, error messages. |
| `pa_itab.asm` | The operation table (generated by `gen_itab.py` from lwasm's `instab.c`; don't edit). |

## Building and testing

`compile.bat` assembles it with lwasm (`pugasm.bin`, `pugasm.lst`). `build_all.bat` and
`reinit_disk.bat` do this too and put it on the disk image as `PUGASM.COM`.

`simulator/tests/test_pugasm.cpp` runs it on the emulated machine and checks the following:

- The shell, the editor, DOS (raw) and BASIC (S-records) must come out byte for byte, and
  listing line for listing line, the same as the lwasm build.
- pugasm must assemble itself into a copy of `pugasm.bin`, and that copy must do the same
  again.
- A program it makes as `.com` must run.
- Errors must be reported, and must leave no files.
- With lwasm available, the sources in `simulator/tests/test_asm/pugasm` must match lwasm
  too. These are every operation in every operand form for each CPU (generated by
  `gen_allops.py`) and a file of directives, macros and expressions.
