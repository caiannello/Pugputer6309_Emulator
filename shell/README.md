# The shell and program files

`SHELL.COM` (`shell.asm`) is the command interpreter DOS starts at boot, and again every
time a program ends. It is an ordinary program: it uses only BIOS `SWI2` calls.

## Commands

| Command | |
|---|---|
| `DIR [path]` | list a directory: `NAME.EXT`, then the size in bytes or `<DIR>` |
| `CD [path]` | change directory; alone, show the current one (the prompt shows it too) |
| `MD path` / `MKDIR`, `RD path` / `RMDIR` | make / remove a directory |
| `DEL path` / `ERASE` | delete a file |
| `REN old new` | rename (the new name is a single name, in the same directory) |
| `TYPE file` | show a file |
| `COPY from to` | copy a file (overwrites) |
| `VER`, `MEM`, `HELP` | DOS version, installed / free RAM pages, the list above |
| `PATH [dir;dir;...]` | show / set the program search path; `PATH ;` empties it |
| `name [args]` | run the program `name.COM` (or `name` as typed if it has an extension) |

Paths use `/`; the current directory is system-wide and survives a program ending. A program
name is looked for as given (relative to the current directory) and, for a bare name, then in
each directory of the search path in turn. The search path is kept by DOS (`B_PATH`), so it
survives the shell being reloaded after every program; it starts as `/CMD`, where the disk
image keeps its programs. The line editor takes Backspace/Delete and Ctrl-C.

## Program files

A program file is an 8-byte header followed by its body (all 16-bit values big-endian):

    +0  "PX"           magic
    +2  load address   where the body goes: at or above DOS_END (the end of DOS's RAM,
                       in dos/dos.lst) and ending below the ROM ($F000)
    +4  entry address  where execution starts; inside the body
    +6  flags          must be 0 (reserved: a later revision will use it to mark a
                       header extension describing banked segments)

`B_EXEC` (`X` = path, `Y` = command tail or 0) loads and starts a program: on success it does
not return -- the program has the machine (the stack is the boot stack, interrupts are as the
BIOS left them). On failure it returns carry + `ERR_NOTFOUND`, `ERR_BADEXE` (header) or
`ERR_TOOBIG` (would overwrite DOS or the ROM). `B_ARGS` returns the command tail (a
NUL-terminated string in DOS's RAM; copy it if you need it after the next `B_EXEC`). A program
ends with `B_EXIT`: DOS flushes and closes every file the program left open, forgets its
directory scans, and starts the shell again. Programs today occupy banks 0-3 as they are at
reset (banks 1-3 may be remapped through the BIOS bank calls, but the loader only loads into
the identity mapping); BASIC uses the whole $3400-$EFFF range, which is why the shell is
reloaded from disk rather than kept resident.

The shell is `shell.bin` (built by `compile.bat`; `../reinit_disk.bat` does it with everything
else) and lives at `$4000`; its buffers are just RAM after its code. `../simulator/tools/mkdiskimg`
puts it on the disk image as `/CMD/SHELL.COM`, and gives `BASIC.COM` its header. DOS starts
`/CMD/SHELL.COM` at boot, or `/SHELL.COM` on a disk that has no `/CMD`.
