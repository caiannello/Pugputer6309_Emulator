# Utilities

Small programs for the shell, each an ordinary program file in `/CMD` on the disk (see
`../shell/README.md`). `compile.bat` / `compile.sh` assemble them (`../reinit_disk.bat` does it
with everything else), and `../simulator/tools/mkdiskimg` puts them on the disk image.

## HEXDUMP

```
HEXDUMP file
```

shows a file as hex and ASCII, 16 bytes a line:

```
000000  48 65 6C 6C 6F 2C 20 77  6F 72 6C 64 21 0D 0A 00  |Hello, world!...|
000010  7F 80 FF 20 7E                                    |... ~|
```

The offset is 24 bits (6 hex digits). Bytes outside `$20`-`$7E` show as dots in the ASCII
column, and a short last line leaves its missing bytes blank. Ctrl-C stops it.

## MOVE

```
MOVE from [to]
```

moves a file to another directory, or renames it:

- With no `to`, the file goes to the current directory under its own name.
- If `to` is a directory (one that exists, or a path ending in `/`), the file goes into it under
  its own name.
- Otherwise `to` is the file's new path (and name).

The shell's `COPY from [to]` follows the same rules. MOVE never overwrites a file: if the
destination exists, it says "Already exists" and changes nothing.

Within one directory the entry is simply renamed, so this also renames a directory. To another
directory, a file is copied and then the original deleted, because DOS has no call that moves an
entry between directories (and has no room left below BASIC's workspace for one). If the copy
fails (a full disk, say), the partial copy is deleted and the original is left as it was. A
directory can only be renamed in place.
