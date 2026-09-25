# EDIT, the text editor

`EDIT.COM` (`edit.asm`) is a full-screen text editor for the serial console, modelled on
**GNU nano 2.2** with only its elementary functions. It needs an ANSI (VT100 / xterm) terminal:
Tera Term, PuTTY, Windows Terminal, or the emulator's own console window.

```
EDIT [file]
```

opens `file`, or an empty buffer. A name that doesn't exist yet is a new file ("New File");
it is created when you write it out.

## The screen

```
  EDIT 1.0                     File: NOTES.TXT                    Modified

the text ...
                              [ line 3/10, col 5 ]
^G Get Help  ^O WriteOut  ^R Read File ^Y Prev Page ^K Cut Text  ^C Cur Pos
^X Exit      M-A Mark Text^W Where Is  ^V Next Page ^U UnCut TextM-6 Copy Text
```

The title bar and the shortcut keys are in inverse video. The status line shows where the cursor
is, and messages such as `[ Wrote 10 lines ]` until the next key. Questions ("File Name to
Write:") appear there too, with their own keys below. Lines too long for the screen show a `$`
at the edge; the cursor's line scrolls sideways a page at a time, as in nano.

EDIT asks the terminal for its size (the cursor-position report, `ESC [ 6 n`). It asks at the
start, on `^L`, and again whenever the keyboard goes quiet for about half a second after some
typing, so resizing the window is picked up by the next pause. A terminal that doesn't answer
gets 80 x 24.

## Keys

`^` is Ctrl. `M-` is Meta: Alt with the key, or press and release Esc and then the key (as in
nano). In Tera Term, Alt only works as Meta if *Setup > Keyboard > Meta key* is on; Esc then the
key always works.

| Keys | |
|---|---|
| `^G` `F1` | help (`^X` or any key leaves it) |
| `^X` `F2` | exit; if the text changed, asks "Save modified buffer?" (Y, N or `^C`) |
| `^O` `F3` | write the file out; asks for the name, the file's own to start with |
| `^R` `F5` | open another file in place of this one ("Read File" into a new buffer); Enter alone gives an empty new buffer |
| `^W` `F6` | search, ignoring case; Enter alone searches for the last text again |
| `M-W` | search again |
| `^K` `F9` | cut the line, or the marked text |
| `^U` `F10` | paste ("uncut") what was cut or copied |
| `M-A` `^^` | set / unset the mark: the text between it and the cursor is shown in inverse |
| `M-6` `M-^` | copy the line (and move to the next), or the marked text |
| `M-\` `M-\|` | first line |
| `M-/` `M-?` | last line |
| `^Y` `F7` PgUp, `^V` `F8` PgDn | a page up / down |
| `^A` Home, `^E` End | start / end of the line |
| `^P` `^N` `^B` `^F`, the arrows | up, down, left, right |
| `^D` Del, `^H` Backspace | delete the character at / before the cursor |
| `^C` `F11` | where the cursor is: line, column and character, with percentages |
| `^L` | redraw the screen (and ask its size again) |

As in nano, cutting lines one after another collects them all in the cut buffer, and `^U`
pastes them back together. Anything else in between starts the next cut afresh. Up and down aim
for the column you were at. Tab inserts a tab; tab stops are every 8 columns.

## Files

- **Line endings.** A file whose lines end in bare LF is written back that way. Anything else,
  and new files, get CR LF, like the rest of the system. The last line always gets a line ending.
- **Size.** The text and the cut buffer share the RAM from the end of the program to `$EFFF`,
  about 37 KB (`ARENA_LO` in `edit.lst`). A bigger file isn't opened: "File too large to edit".
  When the space is full, typing or pasting says "Out of memory". Cutting doesn't free space,
  because the cut text moves into the cut buffer.
- **Writing to another name** that already exists asks "File exists, OVERWRITE ?" first.

## How it works

- The text is a gap buffer: the text before the cursor, the gap, the text after it. The cut
  buffer sits at the very top of the same space and grows downwards. Moving the cursor moves the
  gap with `TFM`; searching first moves the gap to the end, so the text is all in one piece.
- At 19200 baud a full repaint takes about a second, so the screen is updated a row at a time.
  `DIRTY` flags mark the text rows to redraw. Scrolling by one line and opening or closing a line
  use the terminal's scroll region (`ESC [ 3 ; n r`) with insert / delete line (`ESC [ L` /
  `ESC [ M`). The status line is only redrawn when its text changes, and the output is sent a
  buffer at a time with `B_PUT`.
- Keys are parsed from what the terminal sends: `ESC [` and `ESC O` sequences (xterm, VT100,
  Linux console), `ESC` + key for Meta. The size report comes in the same way, as a "resize"
  key, whenever it arrives.
- It enters the terminal's alternate screen (`ESC [ ? 1049 h`) while it runs, so the shell's
  screen comes back afterwards on terminals that have one.

`compile.bat` builds `edit.bin`, which carries its own program header (load and entry `$3400`).
`../simulator/tools/mkdiskimg` puts it on the disk image as `EDIT.COM`. The tests are in
`../simulator/tests/test_edit.cpp`: they drive EDIT with keystrokes through the whole boot chain
and check both the screen (through a small terminal model) and the files it writes.

## Not done

- Undo, replace, go to line, justify, spell checking, syntax colouring, more than one buffer.
- Files bigger than about 37 KB. The RAM pages above 64 KB (`B_PAGE_ALLOC`) could hold much
  more.
- Terminal resizes are noticed at the next pause in typing, not the moment they happen. The
  serial line has no signal for them, and the emulator doesn't run the 16 Hz clock that could
  time a regular check.
