# basic309

The Pugputer6309's BASIC: Microsoft 6809 Extended Color BASIC, adapted to run as a
*guest of the BIOS* (no direct UART access -- console I/O goes through the BIOS's `SWI2`
calls) and extended with disk file I/O in the style of GW-BASIC. This is the project's
only BASIC.

- `exbasrom309.asm` -- the interpreter (assembled with `lwasm --6309`).
- `build_basic.bat` -- builds `exbasrom309.s19` **and** `exbasrom309.lst` with a symbol
  table (`--symbols`). Always build through it: the token-audit test reads the symbols.
- `../reinit_disk.bat` -- rebuilds the BIOS, `dos/dos.asm`, the shell and BASIC, then
  regenerates `disk.img` (DOS + `SHELL.COM` + `BASIC.COM` only -- a clean slate). Run it after editing `bios/`,
  `dos/` or `basic309/`, and after test runs if you want the disk emptied.
- `disk.img` -- the FAT16 SD-card image the emulator boots from (see
  `../simulator/README.md`, "boot chain").

## How it is loaded and where it lives

`BASIC.COM` is an ordinary program file (see `../shell/README.md`): an 8-byte header
("PX", load `$C000`, entry `$C000`, flags 0) followed by `$C000-$EFFF` (12288 bytes). At boot
DOS starts the shell (BIOS -> `SD_BOOT_TRY` -> DOS -> `SHELL.COM`); typing `BASIC` at its
prompt has DOS load BASIC.COM and jump to `BASIC_ENTRY`. `SYSTEM` leaves BASIC: DOS closes
every open file and starts the shell again. (On a disk with no `SHELL.COM`, DOS starts
`BASIC.COM` directly.)

| Range          | What |
|----------------|------|
| `$0600-$3331`  | resident DOS (code, variables, a FAT-sector cache, eight 512-byte file buffers) -- loaded at `DOS_LOAD` (`bios/defines.d`), below `WORKBASE`; only its first ~6KB is on disk, the buffers are just RAM |
| `$3400`        | `WORKBASE`: BASIC's fixed workspace (direct page = `$34`); its top, `PROGST`, moves as variables are added. Must stay above `DOS_END` (`dos/dos.lst`); `test_bios_layout` checks it. |
| `PROGST+1`     | start of the BASIC program, then variables, arrays, free memory |
| `$BFFF`        | fixed top of string space (`TOPRAM_FIXED`) |
| `$C000`        | `BASIC_ENTRY`: a `JMP RESVEC`. **The entry point everyone jumps to** (DOS, the test harnesses, the demos). It never moves; `RESVEC` does whenever code is added above it. |
| `$F000-$FFFF`  | BIOS ROM |

The ROM window is nearly full (about 160 bytes left after error trapping). Growing BASIC
further means trimming unused Color BASIC code or moving `BASIC.COM` lower: its program
header (`shell/README.md`) already says where it loads, so the load address is just
`ORG`, `BASIC_ENTRY` and `TOPRAM_FIXED` in `exbasrom309.asm` plus the constants in
`mkdiskimg.cpp` and the test sessions.

## Disk commands and directories

`LOAD "path"`, `SAVE "path"` (programs are stored as plain text listings, one line per
program line), `FILES ["path"]`, `KILL "path"`, `NAME "old path" AS "new name"`,
`MKDIR "path"`, `RMDIR "path"`, `CHDIR "path"` (`CHDIR` alone prints the current directory),
`SYSTEM` (leave BASIC, back to the shell).

- **Paths** use `/` as the separator: `SAVE "GAMES/CHESS"`. A leading `/` means the root,
  anything else is relative to the current directory (one, system-wide; it starts at the root
  on every boot). `.` and `..` work: `CHDIR ".."`, `LOAD "../UTIL/TOOLS"`.
- **Names** are 8.3: at most 8 characters, a dot, at most 3 more; letters are upper-cased for
  you. A longer name is `?BP` (older versions silently cut it to 8 characters).
- **Default extension:** `LOAD`/`SAVE`/`KILL`/`NAME` give a name with no dot in its last
  component the extension `.BAS`; `"NAME."` (trailing dot) means "no extension". (`OPEN` adds
  nothing -- see below.) `KILL` and `NAME`'s old name have a second chance: if `NAME.BAS`
  isn't there, `NAME` is tried exactly as typed, so `KILL "DATA"` works on a data file made
  with `OPEN "O",#1,"DATA"`. A name you typed with its extension is never altered.
- `FILES` lists a directory (the current one, or the path's): name, byte size, or `<DIR>`.
  `NAME "old" AS "new"` renames a file or directory in place (the new name is a single name).
- `RMDIR` needs an empty directory that isn't the current one (`?DE`, `?AO`). `KILL` a
  directory is `?IS`; `CHDIR` to a file is `?ND`.
- `KILL`, `NAME`, `FILES`, `MKDIR`, `RMDIR` and `CHDIR` are ordinary statements you can use
  in a program. (`LOAD` and `SAVE` still end the running line, as they always did.)
- `KILL`/`NAME` refuse a file that is open (`?AO`).

## File I/O statements (GW-BASIC guide, sections 5.2 and 5.3)

Up to **4** files open at once, numbered 1 to 4 (a fifth `OPEN` number gives `?DN`).
Unlike `LOAD`/`SAVE`, `OPEN` gives a name with no dot **no** extension -- so
`OPEN "O",#1,"DATA"` creates `DATA`, and to delete it you must `KILL "DATA."`.

### Sequential files

```
OPEN "O",#1,"name"            or   OPEN "name" FOR OUTPUT AS #1   (create / empty)
OPEN "I",#1,"name"            or   OPEN "name" FOR INPUT  AS #1   (must exist)
OPEN "A",#1,"name"            or   OPEN "name" FOR APPEND AS #1   (create / add to the end)
PRINT #1, ...                       PRINT with its output in the file (also PRINT #1, USING ...)
WRITE #1, a, b$, ...                numbers plain, strings in quotes, comma separated
INPUT #1, a, b$, ...                reads fields written by PRINT #/WRITE #
LINE INPUT #1, a$                   the rest of the line (up to 249 characters)
EOF(1)  LOF(1)  LOC(1)              at end / length in bytes / 128-byte records so far
CLOSE [#1[,#2...]]                  no argument = all files
```

Lines are written with CR LF; CR, LF and CR LF are all accepted when reading. `INPUT #`
skips leading spaces and line breaks; a field is either `"quoted"` (may hold commas and
colons) or runs to a comma or line break. A field can't span lines. Bad number data is
`?FD`; reading at the end of the file is `?IE` (test with `EOF()` first). `WRITE` with
no `#` writes to the screen.

### Random-access files

```
OPEN "R",#1,"name",32         or   OPEN "name" AS #1 LEN=32      (record length 1-256, default 128)
FIELD #1, 20 AS N$, 4 AS A$, 8 AS P$      variables become windows onto the record buffer
LSET N$=X$    RSET N$=X$                  left / right justified, space padded, cut to width
PUT #1[,rec]  GET #1[,rec]                write / read a whole record (no rec = the next one)
MKI$(n)  CVI(s$)                          integer <-> 2-byte string (big-endian)
MKS$(x)  CVS(s$)                          number  <-> 4-byte string
LOC(1)                                    the last record number used
EOF(1)                                    true if the last GET ran past the end
LOF(1)                                    file length in bytes
```

- Each random file has a 256-byte record buffer; the total width of a `FIELD` must fit the
  record length (`?FC` otherwise). `LSET`/`RSET` work only on fielded variables (`?FC` on
  any other string). Assigning normally (`N$="X"`) detaches the variable from the buffer.
- Record numbers are 1-32767, and a file stays under 64 KB (`?FC` beyond that).
- `GET` past the end of the file is not an error: the record reads as zeros and `EOF(n)` is
  true. `PUT` past the end extends the file; the gap reads as zeros.
- `MKS$` keeps 24 bits of mantissa (4 bytes), so `PRINT CVS(x)` can show noise in the 8th-9th
  digit (19.99 prints as 19.9899998); `PRINT USING` hides it.

### When files are closed

`END`, running off the end of a program, `NEW`, `CLEAR`, `RUN` and `LOAD` close all files.
`STOP`, Ctrl-C, errors and direct-mode lines leave them open (so `CONT` works); use `CLOSE`.

### Errors added for files

`?NO` file not open, `?FM` bad file mode, `?AO` file already open, `?DN` bad file number,
`?IE` input past end, `?FD` bad file data, `?NE` file not found, `?FE` file already exists,
`?IO` I/O error, `?DF` disk full, `?ND` not a directory, `?IS` is a directory, `?DE` directory
not empty, `?BP` bad name or path (invalid 8.3 name, or a path over 79 characters).

## Error trapping

`ON ERROR GOTO line` names a handler. From then on an error in a *running program* (not in a
direct-mode line, and not while another error is being handled) jumps to that line instead of
printing the message and stopping. `ON ERROR GOTO 0` turns trapping off; `RUN`, `NEW` and `CLEAR`
do too. In the handler:

- `ERR` is the error's number -- its position in BASIC's message table, **not** GW-BASIC's
  numbering -- and `ERL` the line it happened in (line numbers up to 63999 work);
- `RESUME` runs the statement that failed again, `RESUME NEXT` continues with the statement
  after it (the rest of the line still runs), `RESUME n` continues at line `n`;
- the `FOR`/`GOSUB` state is exactly as it was when the statement failed, so a handler can
  `RESUME NEXT` out of the middle of a subroutine and the `RETURN` still finds its `GOSUB`;
- an error inside the handler itself, or `RESUME` when nothing is being handled (`?RW`), is an
  ordinary error.

`ERROR n` raises error `n` (so a program can test its own handler, or make its own errors).
Numbers: 0 NF, 1 SN, 2 RG, 3 OD, 4 FC, 5 OV, 6 OM, 7 UL, 8 BS, 9 DD, 10 /0, 11 ID, 12 TM, 13 OS,
14 LS, 15 ST, 16 CN, 17 FD, 18 AO, 19 DN, 20 IO, 21 FM, 22 NO, 23 IE, 24 DS, 25 UF, 26 NE (file
not found), 27 FE, 28 DF, 29 ND, 30 IS, 31 DE, 32 BP, 33 RW. File and directory errors from DOS
are trappable like any other: `IF ERR=26 THEN ...` for a missing file.

```
10 ON ERROR GOTO 100
20 OPEN "I",#1,"DATA.TXT"
30 PRINT "CONTINUING": END
100 IF ERR=26 THEN PRINT "NO DATA FILE": RESUME 30
110 ON ERROR GOTO 0
```

## Differences from GW-BASIC you will run into

- No `%` integer variables (write `CODE` where the guide has `CODE%`), no `MKD$`/`CVD`,
  no `LOCK`/`UNLOCK`.
- `ERR` numbers are this BASIC's own (see "Error trapping"), not GW-BASIC's.
- The default string space is 2000 bytes (Color BASIC's was 200); `CLEAR n` changes it. A
  single string is still at most 255 characters.
- Unquoted `INPUT` strings end at a comma (Color BASIC behaviour).
- The line editor drops characters above `z`, so `|` (and `{ } ~`) can't be typed.
- Keywords are matched anywhere a word starts, so a variable whose name *begins* with a
  keyword (`GETX`, `LOCK`, `EOFLAG`) is tokenised as the keyword plus letters.

## The DOS interface BASIC uses

BASIC talks to the resident DOS only through BIOS `SWI2` calls (function codes `$13`-`$28`
in `bios/defines.d`, documented there; implemented in `dos/dos.asm`). Every DOS call goes
through ONE generic BIOS handler that indexes a table of DOS entry points (`JT_DOS`), so a
new DOS call is a function code, a table entry and an output-mask byte -- no new BIOS
wrapper. Names are NUL-terminated path strings that DOS parses itself; handles are small
numbers (files 0-7, directory scans 0-3, separate spaces); sizes and positions are 32-bit
in the interface and in DOS (files run to 4GB, though a FAT16 volume holds at most 2GB; `ERR_TOOBIG` only for a position past 32 bits).
Calls: open (read / write / append / update), close, getc/putc, read/write, readline/
writeline, seek (from start / current / end), stat (by handle or by path), flush, kill,
rename, mkdir, rmdir, chdir, getcwd, opendir/readdir/closedir, and a version query.
DOS keeps 8 file slots (BASIC uses 4 for its file numbers and one for `LOAD`/`SAVE`), each
with its own 512-byte sector buffer. Seeking and writing past the end zero-fills the gap so
stale disk data never shows through, and both FAT copies are kept in sync.

## Adding a keyword (the part that has gone wrong before)

A statement or function needs entries in several tables that must stay in step:

1. its word in the dictionary -- statements in the `LAA66` list before `TAB(`, functions in
   the `LAB1A` list -- at the same position as
2. its handler `FDB` in `CMD_TAB` (statements) or `FUNC_TAB` (functions; the ones taking one
   numeric argument go before `LEFT$`).

Token numbers, `TOK_HIGH_EXEC`, `NUM_SEC_FNS` and the `COMVEC` counts are all derived by
the assembler from those tables -- never type them. A function that returns a string must
end with `JMP LB69B` (skipping the caller's type check) like `CHR$` does. Then add the new
word to `../simulator/tests/test_basic309_token_audit.cpp`; it cross-checks the dictionaries,
counts, `TOK_*` constants and that each handler sits at its word's position, and fails on any
`TOK_*` symbol it doesn't know.

## Tests

From `../simulator/build` (after `reinit_disk.bat`): `pugputer_tests` runs everything;
`pugputer_tests seqfiles randomfiles` runs only tests whose names contain those words.

- `test_basic309_interp_regression.cpp` -- exact-output cases for the ordinary interpreter.
- `test_basic309_token_audit.cpp` -- the table audit above.
- `test_basic309_seqfiles.cpp`, `test_basic309_randomfiles.cpp` -- the guide's Examples 1-6
  and every file statement and error, driven with real keystrokes through the whole disk
  boot chain.
- `test_basic309_load_save_golden.cpp`, `test_basic309_files_kill_name.cpp`,
  `test_basic309_sdboot_golden.cpp` -- `LOAD`/`SAVE`, `FILES`/`KILL`/`NAME`, and the boot itself.
- `test_dos_file_api.cpp`, `test_dos_stream_api.cpp`, `test_dos_dirs.cpp` -- the DOS file
  layer called directly (the last one checks the directory tree on the disk with an
  independent FAT16 reader, `fat16_reader.hpp`).
- `test_basic309_dirs.cpp` -- `MKDIR`/`CHDIR`/`RMDIR` and paths in every disk statement.
- `test_basic309_errors.cpp` -- `ON ERROR GOTO`, `RESUME` in its three forms, `ERR`/`ERL`,
  `ERROR n`, trapping through `GOSUB`/`FOR`, trapped DOS errors, the 2000-byte string space, and
  `KILL`/`NAME`'s second chance for names without an extension.

The disk-backed tests share `disk.img`, so each one deletes the files it uses before and
after.
