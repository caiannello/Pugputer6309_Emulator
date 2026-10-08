# The game kit

Tools for making a game's graphics (and, to come, its music) on the Pugputer itself, on the
video card's screen and with the card's mouse and keyboard. In the emulator those are the video
window's: click into it and use it, not the terminal. (If the window is closed while one of
these runs, the terminal's keys are given to the card instead, so Esc still works.) What they
make, a game loads straight into the card.

| File | |
|---|---|
| `tilekit.asm` | `TILEKIT.COM`, the tile set and map editor (below); it includes the next five |
| `tk_map.asm` | its map |
| `tk_src.asm` | its export as assembly source |
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

With a file, it opens it: a map (a name ending in `.MAP`) with its tile set, or a tile set
(`.TLS`, which is added to a name without an extension). A name that isn't a file yet is the new
set's (or map's). Without one, it asks what to make:

- **tiles** 8x8 or 16x16 (T),
- **colors** 16 a tile (4 bits a pixel; which 16 -- one of the palette's 16 rows -- is chosen
  where the tile is placed, so one tile can be drawn in several) or 256 (8 bits a pixel) (D),
- **screen** 320x240 or 640x480 (R): how the map is shown, as the game will show it,
- **the map's width and height** (W, H): 32, 64, 128 or 256 cells each, 16384 cells (32KB) at
  most -- the card's own map sizes,
- **keep the tiles** (K): just a new map, for the tile set there is. This is how several maps
  share one set.

Those are the card's own tile layers, so a set and a map are what a game's tile layer uses as
they are.

### The screen

- **Left:** the map, as the card's tile layer shows it, the cell under the mouse framed. A tile
  being drawn changes wherever it is in the map as it is drawn. A map smaller than the screen
  has what is past its end shaded (the card would show the map over again there).
- **Right, from the top:** the tile set's file; the tools; the tile magnified, to draw in; the
  palette (16 rows of 16); red, green and blue of the color picked, and that color; the set, 10
  tiles a row, with NEW and DUP; the map's file. A `*` after a name: changed since saved.
- **Bottom:** the keys (or a message, or a question); the tile, the flips, the color, the map's
  size, the cell under the mouse, the kind of set.

### The tools

The same tools work on the map's cells and on the tile's pixels, whichever the mouse is over:

| | on the map | on the tile |
|---|---|---|
| **pen** (P) | puts the tile down (flipped, in the color's row) | draws in the color |
| **line** (L) | a line of it, from where the button goes down to where it comes up | of the color |
| **fill** (F) | every cell like the one clicked that touches it (not diagonally) | every pixel of its color that touches it |
| **pick** (K or I) | the cell's tile, flips and row become the pen's | the pixel's color becomes the one to draw with |
| **eraser** (E) | tile 0 | color 0 |
| **clear** (button, C) | every cell tile 0 | every pixel 0 |
| **undo** (button, U, Ctrl+Z) | the last change, whichever it was: 16 steps, of the tiles and the map together |

The right button always does what the eraser does. Clear is for whichever was drawn on last.

A blank map is tile 0 everywhere, so keep tile 0 blank (see-through) for empty cells; while it
isn't, drawing on it shows all over the map.

A large fill takes a while: a 64x64 map, about half a second.

### The mouse

| | |
|---|---|
| a tool button | that tool; the last two are buttons: **clear** and **undo** |
| the map, the magnified tile | the tool, with the left button; the right button rubs out |
| the map, the middle button | drags the map along |
| the wheel, over the map | scrolls it up and down (with Shift, across) a cell a click |
| a color | the color to draw with (in a 16-color set, also its row: the tiles are shown in it, and put on the map with it) |
| red, green, blue | drag along a bar to set the picked color's part of it: the whole screen changes as it goes, as the palette is the card's |
| a tile in the set | that tile; the wheel scrolls the set |
| NEW, DUP | a blank tile, or a copy of this one, at the end of the set |

### The keys

| | |
|---|---|
| P L F K E | the tools |
| C | clear the tile or the map |
| U, Ctrl+Z | undo |
| N, D | a new tile; a copy of this one |
| `,` `.` | the previous or next tile |
| H, V | flip what the pen puts on the map: across, down |
| + (=), - | the next or previous color |
| PgUp, PgDn | the previous or next row of the palette |
| arrows | scroll the map a cell (with Shift, 8); Home: back to its top left |
| Ctrl+S | save: the tile set, then the map, each if it has changed (a name asked for if it has none: the map's file names its set's, so the set needs one) |
| Ctrl+A | save as: both, asking both names |
| Ctrl+E | export as assembly source: the tile set's module, then the map's (below) |
| Ctrl+O | open a map (`.MAP`, with its set) or a tile set (and a new map) |
| Ctrl+N | a new set and map, or a new map for this set |
| Esc | back to the shell |

A file name is typed at the bottom: Enter takes it, Esc gives up. Opening, making new or
leaving with changes not saved asks first (Y or N).

### The editor's colors

The editor draws itself in colors from the set's palette, which it may not change: the darkest
(its background), the brightest (its text), one about 3/8 of the way between (the grid,
buttons) and the most yellow (what is picked). When a color is changed they are chosen again,
and the screen redrawn in them.

### The files

A tile set (`.TLS`):

| Offset | |
|---|---|
| 0 | `PTS1` |
| 4 | the tile size (8 or 16), bits a pixel (4 or 8), flags (bit 0: 640x480), 0 |
| 8 | how many tiles (2 bytes, high first), then 6 bytes of 0 |
| 16 | the palette: 256 colors, RGB565, 2 bytes each, high byte first -- as the card holds it |
| 528 | the tiles, one after another, as the card holds them: rows of pixels, packed from the high bits (8x8 at 4 bits: 32 bytes a tile) |

At most 1024 tiles (8x8), 512 (16x16, 16 colors) or 256 (16x16, 256 colors): 64KB.

A map (`.MAP`):

| Offset | |
|---|---|
| 0 | `PTM1` |
| 4 | its width, then its height, in cells (2 bytes each, high first): 32, 64, 128 or 256 |
| 8 | its tile set's file name, as it was saved (40 bytes: the name, then 0s) |
| 48 | the cells, a row at a time, 2 bytes each, high first -- the card's map entries: the tile (bits 0-9), flipped across (10), flipped down (11), the palette row (12-15) |

So a game reads the palette into `$040200`, the tiles to where its tile layer's `L_TILEBASE`
points and the cells to its `L_MAPBASE`, as they are, and sets `L_MAP` to the size.

### Exporting as assembly source

Ctrl+E writes the tile set and the map as assembly source, each a module of its own for a game
to `INCLUDE` (after `VIDCARD.D`): first the set's (its name asked for, the set's file's with
`.ASM` to start with), then the map's. Esc at the first goes on to the second, so a second map
of a set already exported can be exported alone -- several maps share one set's module. Each
module's labels start with its file's name (`LV1.ASM`: `LV1_...`; an `X` first if that starts
with a digit), so they don't clash:

| The set's module (`TILES.ASM`) | |
|---|---|
| `TILES_TSIZE`, `TILES_BPP`, `TILES_NTILES` | the tile size, bits a pixel, how many tiles |
| `TILES_TBYTES` | the tiles' bytes, all told (`TILES_THALF`: half that) |
| `TILES_LMODE` | `L_MODE` for a tile layer showing them (tiles, bits a pixel, 640x480 or not, 16x16 or not) |
| `TILES_TOCARD` | a routine: the palette into the card, and the tiles to A:X in video memory |
| `TILES_PAL` | the palette: 256 `FDB`s, RGB565 |
| `TILES_TILES` | the tiles, `FCB`s as the card holds them, each after a `; tile n` comment |

| The map's module (`LV1.ASM`) | |
|---|---|
| `LV1_W`, `LV1_H` | its size, in cells |
| `LV1_LMAP` | `L_MAP` for a tile layer showing it |
| `LV1_BYTES` | its cells' bytes |
| `LV1_TOCARD` | a routine: the cells to A:X in video memory |
| `LV1_CELLS` | the cells, `FDB`s, a row at a time, each after a `; row n` comment |

A game, then:

```
            INCLUDE "VIDCARD.D"
            ...
            LDA  #$02           ; the tiles to $020000
            LDX  #$0000
            JSR  TILES_TOCARD
            LDA  #$01           ; the map to $016000
            LDX  #$6000
            JSR  LV1_TOCARD
            ...                 ; and a layer: L_MODE TILES_LMODE, L_MAP LV1_LMAP,
                                ; L_MAPBASE $016000, L_TILEBASE $020000
            INCLUDE "TILES.ASM"
            INCLUDE "LV1.ASM"
```

The data is part of the program then, so it has to fit in its memory beside the code (a
program can be about 44KB): a large set, or many maps, a game reads from the `.TLS` and `.MAP`
files instead, whose layout is above -- the palette, tiles and cells in them are in the card's
form too, ready to be copied through a data port.

### On the card

TILEKIT sets the card up itself: layer 0 is the map (at `$016000`, up to 32KB; the tiles at
`$020000`), layer 1 the panel on the right (a bitmap 176 pixels wide, 8 bits a pixel, at
`$000000`, scrolled to the screen's right edge -- left of it, a bitmap shows nothing), layer 2
the reset text screen (which also shades what is past a small map). Sprite 0 is the pointer,
which the card moves with the mouse (`INCTRL` bit 0); sprite 1 frames the cell under it (its
image at `$036000`). The map's undo steps are copies of it the card makes in its PSRAM
(`$800000`, 32KB each).

### Still to come

Metatiles (8x16, 32x32), and the music editor.
