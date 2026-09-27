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
