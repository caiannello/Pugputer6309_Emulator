# The game kit

Tools for making a game's graphics (and, to come, its music) on the Pugputer itself, on the
video card's screen and with the card's mouse and keyboard. In the emulator those are the video
window's: click into it and use it, not the terminal. (If the window is closed while one of
these runs, the terminal's keys are given to the card instead, so Esc still works.) What they
make, a game loads straight into the card.

| File | |
|---|---|
| `tilekit.asm` | `TILEKIT.COM`, the tile set and map editor (below); it includes the next nine |
| `tk_map.asm` | its map |
| `tk_layer.asm` | its three layers |
| `tk_ldlg.asm` | the layer's questions (its tile set, kind of tiles, screen, map size) |
| `tk_proj.asm` | its projects (`.TKT`) |
| `tk_src.asm` | its export as assembly source |
| `tk_ini.asm` | reading `TILEKIT.INI` |
| `TILEKIT.INI` | the palettes a new tile set starts with (below); `mkdiskimg` puts it in `/CMD` |
| `tk_draw.asm` | its screen |
| `tk_file.asm` | its files, and the questions it asks |
| `gk_ui.asm` | what the kit's editors share: the mouse and keys, the editor drawn on sprites ("surfaces") so the card's three layers are all the work's, text on them, the palette and the editor's own colors from it, the mouse pointer, a line of typing |

`compile.sh` (or `compile.bat`) assembles it with lwtools into `build/tilekit.bin`, which
carries its own program header; `mkdiskimg` puts it in `/CMD` as `TILEKIT.COM`. On the
Pugputer, the release disk's `/ASM/GAMEKIT` has the sources: `ASM -o TILEKIT.COM tilekit.asm`
there makes the same program.

## TILEKIT

```
TILEKIT [file]
```

With a file, it opens it: a project (a name ending in `.TKT`), a map (`.MAP`) with its tile set,
or a tile set (`.TLS`, which is added to a name without an extension). A name that isn't a file
yet is the new set's (or map's). Without one, it asks what to make (Ctrl+N asks again):

- **tiles** 8x8 or 16x16 (T),
- **colors** 16 a tile (4 bits a pixel; which 16 -- one of the palette's 16 rows -- is chosen
  where the tile is placed, so one tile can be drawn in several) or 256 (8 bits a pixel) (D),
- **screen** 320x240 or 640x480 (R): how the map is shown, as the game will show it,
- **the map's width and height** (W, H): 32, 64, 128 or 256 cells each, 16384 cells (32KB) at
  most -- the card's own map sizes,
- **keep the tiles** (K): just a new map for the layer being edited, on its tile set.

That makes three layers, each with a map of that size, all on that tile set (the layer
questions, below, give a layer one of its own). They are the card's own tile layers, so a set
and a map are what a game's tile layer uses as they are. A new set's palette comes from
`TILEKIT.INI` (below).

### Layers

The card has three tile layers, and TILEKIT edits all three -- one at a time, seeing them all,
as a game would show them (the editor itself is drawn on sprites, in front of them). Each layer
has a **map** and a **tile set**: its own, or another layer's (layers can share one -- fewer
tiles to draw, and less video memory). The palette is the card's: every layer's.

The **layer bar**, the panel's top row, shows the layers from the back to the front; the one
being edited is lit up, a hidden one dim, and `...` asks about the one being edited.

| | |
|---|---|
| a layer's button, or 1 2 3 | edit that layer: its tile set comes up in the panel, the tools draw on its map |
| right-click, or Shift+1 2 3 | show or hide it |
| `[` `]` | move the layer being edited back or forward |
| `...`, or Ctrl+L | the layer's questions (below) |

The view is one: every layer scrolls with it, at its own resolution, so they stay lined up.

**The layer's questions** (in the panel; a row's key, or a click on it; Enter does it, Esc
doesn't):

| | |
|---|---|
| S | its tile set: its own, or layer 1's, 2's or 3's |
| T, D | its own set's tiles: 8x8 or 16x16, 16 or 256 colors (another's: as they are) |
| R | its screen: 320x240 or 640x480 |
| W, H | its map's width and height |

What can be kept is: a map made larger or smaller keeps its cells where they were (cut off, or
tile 0 around them); tiles of 16 colors made 256 keep their pixels, each in the palette row the
tile was last used in. Tiles of 256 colors made 16, or of another size, can't be: the tile set
starts again with one blank tile -- after you say yes. (The other layers on that set change with
it.)

**Room.** Each layer has 48KB of the card's video memory: its own tile set at the start, its
map at the end (the editor has the rest). A tile set can have as many tiles as its layer's map
leaves room for -- with a 64x64 map (8KB), 1280 8x8 tiles of 16 colors (1024 at most, the
card's), 640 of 256 colors, 160 16x16 of 256 colors; with a 256x64 map (32KB), 64 of those.
More tiles, or a larger map, than fit are refused (the layer's questions check first).

### 16 colors: the palette's rows

In a 16-color set a tile's pixels aren't colors but places in a row, 0-15: the palette is 16
rows of 16, and **each cell of the map picks the row** its tile's colors come from (bits 12-15
of the cell). So one tile can be put down in several rows -- a red brick and a blue one. Pixel
0 shows through, whatever row.

Clicking a color picks two things: its place in its row (what the pen draws in a tile) and its
row (what the tile is shown in while it is edited, and what cells are put down with). The mark
left of the palette is the row.

Each tile also remembers the row it was last used in -- drawn on, put on the map, or picked up
from it -- and the tile set shows it in that row, so the other tiles look as they were meant to
while you try this one in another. Selecting a tile picks its row again (the same place in it),
and the rows are saved with the set.

### The screen

- **Left:** the three layers' maps, as the card shows them, the cell under the mouse framed (in
  the layer being edited). A tile being drawn changes wherever it is in the maps as it is drawn.
  (A map smaller than the screen shows over again past its end -- the card's maps wrap around;
  clicks there do nothing.)
- **Right, from the top:** the layer bar; the tile set's file; the tools; the tile magnified, to
  draw in; the palette (16 rows of 16); red, green and blue of the color picked, and that color;
  the set, 10 tiles a row, with NEW and DUP; the map's file; the project's. A `*` after a name:
  changed since saved.
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
| 1 2 3, Shift+1 2 3, `[` `]`, Ctrl+L | the layers (above) |
| Ctrl+S | save the project: everything that has changed (below) |
| Ctrl+A | save the project as another name |
| Ctrl+W | save the layer's tile set, then its map, under names asked for (Esc skips one) |
| Ctrl+E | export the project as assembly source (below) |
| Ctrl+O | open a project (`.TKT`), or into the layer being edited a map (`.MAP`, with its set) or a tile set |
| Ctrl+N | a new project (or with K, a new map for the layer being edited) |
| Esc | back to the shell |

A file name is typed at the bottom: Enter takes it, Esc gives up. Opening, making new or
leaving with changes not saved (in any layer) asks first (Y or N).

### Projects

A project is everything at once, under one name: a `.TKT` file naming each layer's tile set and
map files, with how each is shown, the layers' order and the palette. Ctrl+S saves it (asking
its name the first time) and with it every tile set and map that has changed; any that have no
names yet are named after the project -- `GAME.TKT`'s are `GAME1.TLS`, `GAME1.MAP`,
`GAME2.MAP` ... (a set by the number of the layer whose room it is in). Opening it opens them
all. The sets and maps are ordinary `.TLS` and `.MAP` files: they can be opened alone, or named
by other projects. It is text:

```
; TILEKIT project
[PROJECT]
ORDER 1 2 3          the layers, from the back
EDIT 2               the one being edited
[LAYER1]             (and [LAYER2], [LAYER3])
TILES GAME1.TLS      its tile set: layers naming the same file share it
MAP GAME1.MAP        its map
SCREEN 320           320 (x240) or 640 (x480)
SHOW YES             or NO
[PALETTE]
000000 840000 ...    256 colors, RRGGBB
```

### TILEKIT.INI: the palettes a set starts with

A new tile set starts with the palette in `TILEKIT.INI` for its kind -- `[PALETTE8]` for 256
colors, `[PALETTE4]` for 16 -- looked for in the current directory, then in `/CMD`. It is text,
to change with EDIT (or on the PC, in `gamekit/`, before the disk is made):

```
; a comment, to the end of the line
[PALETTE8]
000000 800000 008000 808000 ...    up to 256 colors, RRGGBB in hex, from color 0
[PALETTE4]
000000 1D2B53 7E2553 008751 ...    (a # before one is allowed; spaces, commas, lines between)
```

Colors not given are the card's own (xterm's), and with no `TILEKIT.INI` at all a set starts
with those. The one that comes with TILEKIT has xterm's 256 for 256-color sets, and for
16-color sets rows of 16 made for tiles: PICO-8's 16, grays, twelve hues from dark to light,
earth and skin tones, and the C64's 16. A set's palette, changed or not, is saved with it (and
exported with it).

### The editor's colors

The editor draws itself in colors from the set's palette, which it may not change: the darkest
(its background), the brightest (its text), one about 3/8 of the way between, grays first (the
grid, buttons), and the most yellow (what is picked). When a color is changed they are chosen again,
and the screen redrawn in them.

### The files

A tile set (`.TLS`):

| Offset | |
|---|---|
| 0 | `PTS1` |
| 4 | the tile size (8 or 16), bits a pixel (4 or 8), flags (bit 0: 640x480; bit 1: each tile's row follows the tiles), 0 |
| 8 | how many tiles (2 bytes, high first), then 6 bytes of 0 |
| 16 | the palette: 256 colors, RGB565, 2 bytes each, high byte first -- as the card holds it |
| 528 | the tiles, one after another, as the card holds them: rows of pixels, packed from the high bits (8x8 at 4 bits: 32 bytes a tile) |

| after the tiles | (flags bit 1, 16-color sets) a byte a tile: the row TILEKIT shows it in -- only TILEKIT's; a game can stop reading after the tiles |

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

Ctrl+E writes the project as assembly source for a game to `INCLUDE` (after `VIDCARD.D`): its
name is asked for (`GAME.ASM` -- the project's name, to start with), and with it go a module for
each tile set in use (`GAME1T.ASM` ...) and each map (`GAME1M.ASM`, `GAME2M.ASM`,
`GAME3M.ASM`), each with labels of its own:

| A set's module (`GAME1T.ASM`) | |
|---|---|
| `GAME1T_TSIZE`, `_BPP`, `_NTILES` | the tile size, bits a pixel, how many tiles |
| `GAME1T_TBYTES` | the tiles' bytes, all told (`_THALF`: half that) |
| `GAME1T_LMODE` | `L_MODE` for a tile layer showing them |
| `GAME1T_TOCARD` | a routine: the palette into the card, and the tiles to A:X in video memory |
| `GAME1T_PAL`, `GAME1T_TILES` | the palette (256 `FDB`s, RGB565); the tiles (`FCB`s, as the card holds them, each after a `; tile n` comment) |

| A map's module (`GAME1M.ASM`) | |
|---|---|
| `GAME1M_W`, `_H` | its size, in cells |
| `GAME1M_LMAP` | `L_MAP` for a tile layer showing it |
| `GAME1M_BYTES` | its cells' bytes |
| `GAME1M_TOCARD` | a routine: the cells to A:X in video memory |
| `GAME1M_CELLS` | the cells, `FDB`s, a row at a time, each after a `; row n` comment |

| The project's (`GAME.ASM`) | |
|---|---|
| `GAME_VBASE` | where they go in video memory: change it to suit -- the rest follow |
| `GAME_T1` ..., `GAME_M1` ..., `GAME_END` | where each set and map goes: one after another from `GAME_VBASE` |
| `GAME_TOCARD` | a routine: every set and map into the card, the palette, and the card's three layers set up as they were in TILEKIT (scrolled to 0, 0) |
| `GAME_LAYERS`, `GAME_SHOW` | the three layers' settings (48 bytes, from the back), and `DC_CTRL`'s bits for the ones shown |
| `GAME_PAL` | the palette |

A game, then:

```
            INCLUDE "VIDCARD.D"
            ...
            JSR  GAME_TOCARD    ; everything in place, the layers on
            ...
            INCLUDE "GAME.ASM"  ; (it INCLUDEs the rest)
```

The data is part of the program then, so it has to fit in its memory beside the code (a
program can be about 44KB): large sets, or large maps, a game reads from the `.TLS` and `.MAP`
files instead, whose layout is above -- the palette, tiles and cells in them are in the card's
form too, ready to be copied through a data port.

### On the card

TILEKIT leaves the card's three tile layers to the project: each layer's 48KB room is from
`$000000`, `$00C000`, `$018000` (a tile set at the start, the map at the end). The editor draws
itself on surfaces (`gk_ui.asm`): bitmaps from `$024000` -- the panel in 4 columns, the status
rows in 8 -- shown by 40 sprites in front of the layers (at most 14 on a line, of the card's
32). Sprite 0 is the pointer, which the card moves with the mouse (`INCTRL` bit 0); sprite 1
frames the cell under it. The sprite table is at `$03CC00`; the text is drawn in the card's own
font, at `$03F000`. The maps' undo steps are copies the card makes in its PSRAM (`$800000`,
32KB each), and a map being resized passes through it too.

### Still to come

Metatiles (8x16, 32x32), and the music editor.
