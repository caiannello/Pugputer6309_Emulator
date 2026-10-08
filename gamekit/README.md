# The game kit

Tools for making a game's graphics (and, to come, its music) on the Pugputer itself, on the
video card's screen and with the card's mouse and keyboard. In the emulator those are the video
window's: click into it and use it, not the terminal. What they make, a game loads straight into
the card.

| File | |
|---|---|
| `tilekit.asm` | `TILEKIT.COM`, the tile set editor (below); it includes the next three |
| `tk_draw.asm` | its screen |
| `tk_file.asm` | its files, and the questions it asks |
| `gk_ui.asm` | what the kit's editors share: the mouse and keys, text on the screen, the palette and the editor's own colors from it, the mouse pointer, a line of typing |

`compile.sh` (or `compile.bat`) assembles it with lwtools into `build/tilekit.bin`, which
carries its own program header; `mkdiskimg` puts it in `/CMD` as `TILEKIT.COM`. On the
Pugputer, the release disk's `/ASM/GAMEKIT` has the sources: `ASM -o TILEKIT.COM tilekit.asm`
there makes the same program.

## TILEKIT

```
TILEKIT [file]
```

With a file, it opens that tile set (`.TLS` is added to a name without an extension); a name
that isn't a file yet is the new set's. Without one, it asks what kind of set to make:

- **tiles** 8x8 or 16x16 (T),
- **colors** 16 a tile (4 bits a pixel; which 16 -- one of the palette's 16 rows -- is chosen
  where the tile is placed, so one tile can be drawn in several) or 256 (8 bits a pixel) (D),
- **screen** 320x240 or 640x480 (R): how the tiles are shown on the left, as the game will
  show them.

Those are the card's own tile layers, so a set is what a game's tile layer uses as it is.

### The screen

- **Left:** the tile being edited, over and over, as the card's tile layer shows it -- to see
  that its edges meet.
- **Right, from the top:** the tools; the tile magnified, to draw in; the palette (16 rows of
  16); red, green and blue of the color picked, and that color; the set, 10 tiles a row, with
  NEW and DUP.
- **Bottom:** the keys (or a message, or a question), and the tile number, the kind of set,
  the tool and the color.

### The mouse

| | |
|---|---|
| a tool button | that tool; the last two are buttons: **clear** (the tile all 0) and **undo** |
| the magnified tile | the tool, with the left button; the right button draws 0 whatever the tool |
| a color | the color to draw with (in a 16-color set, also the row the tiles are shown in) |
| red, green, blue | drag along a bar to set the picked color's part of it: the whole screen changes as it goes, as the palette is the card's |
| a tile in the set | that tile to edit; the wheel scrolls the set |
| NEW, DUP | a blank tile, or a copy of this one, at the end of the set |

The tools: **pen** (P), **line** (L: from where the button goes down to where it comes up),
**fill** (F: the area of one color that touches the pixel, not diagonally), **pick** (K or I:
the color under the mouse becomes the one to draw with), **eraser** (E: the pen in 0).

Color 0 is see-through on the card (in every layer, tiles included): the magnified tile and the
set show it as the editor's background, and the palette shows it as a hollow square.

### The keys

| | |
|---|---|
| P L F K E | the tools |
| C | clear the tile |
| U, Ctrl+Z | undo (16 steps, of any tiles) |
| N, D | a new tile; a copy of this one |
| arrows | the previous or next tile; up and down, a row of the set |
| + (=), - | the next or previous color |
| PgUp, PgDn | the previous or next row of the palette |
| Ctrl+S | save (the name asked for, the current one to start with) |
| Ctrl+O | open another set |
| Ctrl+N | a new set |
| Esc | back to the shell |

A file name is typed at the bottom: Enter takes it, Esc gives up. Opening another set, making a
new one or leaving with changes not saved asks first (Y or N).

### The editor's colors

The editor draws itself in colors from the set's palette, which it may not change: the darkest
(its background), the brightest (its text), one about 3/8 of the way between (the grid,
buttons) and the most yellow (what is picked). When a color is changed they are chosen again,
and the screen redrawn in them.

### The file (.TLS)

| Offset | |
|---|---|
| 0 | `PTS1` |
| 4 | the tile size (8 or 16), bits a pixel (4 or 8), flags (bit 0: 640x480), 0 |
| 8 | how many tiles (2 bytes, high first), then 6 bytes of 0 |
| 16 | the palette: 256 colors, RGB565, 2 bytes each, high byte first -- as the card holds it |
| 528 | the tiles, one after another, as the card holds them: rows of pixels, packed from the high bits (8x8 at 4 bits: 32 bytes a tile) |

So a game reads the palette into `$040200` and the tiles to where its tile layer's
`L_TILEBASE` points, as they are. At most 1024 tiles (8x8), 512 (16x16, 16 colors) or 256
(16x16, 256 colors): 64KB.

### On the card

TILEKIT sets the card up itself: layer 0 is a tile layer of the set (its map, 32x32 at
`$016000`, all the tile being edited), layer 1 the panel on the right (a bitmap 176 pixels wide,
8 bits a pixel, at `$000000`, scrolled to the screen's right edge -- left of it, a bitmap shows
nothing), layer 2 the reset text screen; the tiles are at `$020000`, the pointer's image at
`$037800`. The pointer is sprite 0, which the card moves with the mouse (`INCTRL` bit 0).

### Still to come

Tile maps (milestone 2: the left becomes a map to place tiles in, with the same tools, flips
and palette rows), saving as assembly source to `INCLUDE` (milestone 3), and the music editor.
