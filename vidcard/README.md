# The Pugputer 6309 video card

A color graphics card for the Pugputer's bus, built on an RP2350 board (Olimex RP2350-PICO2-XXL)
with its picture on DVI/HDMI: 640x480 at 60 frames a second. To a program it is 32 registers at
`$FF80-$FF9F` and a 24-bit address space of its own:

- **three layers**, each a text screen (80x30 in 256 colors, with a font in video memory), a
  tile map (8x8 or 16x16 tiles, 1-8 bits a pixel, flips, per-tile palettes, scrolling) or a
  bitmap (1-8 bits a pixel), at 640x480 or at 320x240 with its pixels doubled;
- **128 sprites** (8 to 64 pixels square, 4 or 8 bits a pixel, flips), placed between the layers;
- **256 colors** from 65536 (RGB565), starting as the xterm palette ANSI terminals use;
- **drawing commands** the card carries out itself: lines, rectangles, circles, discs, triangles,
  characters, blits, memory copies and fills;
- **interrupts** at vertical blank, at a chosen line, and when the commands are done;
- **256KB of video memory**, and the board's **8MB PSRAM** for everything else;
- a **mouse and keyboard** on its USB port: the mouse's position and buttons, a queue of key
  presses and releases, and a pointer (sprite 0) that follows the mouse by itself.

The card's behavior is written once, in portable C (`core/`), which the emulator runs and the
card's firmware (`firmware/`) runs too. The emulator shows it in a window (see "In the emulator").
"On the card" describes the hardware and how the RP2350 does it, and the limits it may impose
that the emulator doesn't. The same board also gives the Pugputer its SD card (see "The SD
card").

| File | |
|---|---|
| `core/vc.h`, `core/vc.c` | the card: registers, address space, commands, the scanline renderer |
| `core/vc_font.c` | the font it starts with (ToshibaSat 8x16, code page 437; see `../NOTICE.md`) |
| `firmware/` | the RP2350's firmware: the bus, the picture, the SD card (`firmware/README.md`) |
| `hardware/VIDCARD.PLD` | the card's address decoder (ATF16V8B, CUPL): /CS, SD-select, and the OPL3's select |
| `vidcard.d` | the registers and constants for 6309 programs (`INCLUDE "vidcard.d"`) |
| `tools/font2c.py` | makes `vc_font.c` from an 8x16 CP437 font (BDF, or a pixel-outline TrueType font) |
| `tools/make_vidgfx.py` | makes `VIDGFX.ASM` (below) from `tools/vidgfx.template`, working out its drawing commands |
| `../demo/programs/ASM/VIDEO/` | the demos: `VIDDEMO` (everything at once), `VIDTEXT` (text layers), `VIDTILES` (tiles and sprites), `VIDGFX` (bitmaps, commands, palette, interrupts, PSRAM), `VIDMOUSE` (the mouse and keyboard), `MANDEL` (the Mandelbrot set, with the MC6839 floating-point ROM), and `VIDLIB.ASM`, the helpers they share |
| `../basic309/` | BASIC's statements for the card (`SCREEN`, `LINE`, `CIRCLE`, `SPRITE`, ...: `../basic309/README.md`) |

## Registers ($FF80-$FF9F)

| Offset | Name | |
|---|---|---|
| `$00-$02` | `ADDR0` H, M, L | data port 0's address (24 bits, high byte first) |
| `$03-$04` | `INC0` H, L | its step: a signed 16-bit number added after each `DATA0` read or write |
| `$05` | `DATA0` | reads or writes the byte at `ADDR0`, then steps |
| `$06-$0B` | `ADDR1`, `INC1`, `DATA1` | data port 1, the same |
| `$0C` | `CTRL` | write `$80`: reset the card (see "At reset") |
| `$0D` | `STATUS` | read: bit 7 in vertical blank, bit 6 commands still running, bit 5 command queue full, bit 4 a key event waiting |
| `$0E` | `IEN` | interrupt enables: bit 0 vertical blank, 1 line, 2 commands done, 3 input |
| `$0F` | `ISR` | interrupt flags, the same bits; writing 1s clears them. `/IRQ` is low while `IEN AND ISR` isn't 0 |
| `$10-$11` | `LINE` H, L | read: the line being drawn (0-524; 480-524 are vertical blank). Write: the line for the line interrupt |
| `$12` | `CMD` | drawing commands, a byte at a time (see "Drawing commands") |
| `$13` | `FRAME` | frames shown, modulo 256 |
| `$14` | `INCTRL` | input: bit 0 the pointer (sprite 0 follows the mouse), bit 1 keys go to the card; write bit 7: empty the key queue (see "Mouse and keyboard") |
| `$15-$16` | `MOUSEX` H, L | read: the mouse's X, 0-639. Reading the high byte takes a snapshot of X and Y |
| `$17-$18` | `MOUSEY` H, L | read: its Y, 0-479, as of that snapshot |
| `$19` | `MOUSEB` | read: buttons, bit 0 left, 1 right, 2 middle; bit 7 a mouse has been seen |
| `$1A` | `WHEEL` | read: wheel clicks since the last read, signed (+ away from you) |
| `$1B` | `KEY` | read: takes the next key event off the queue, and gives its USB usage code (0: none) |
| `$1C` | `KEYCHAR` | read: that event's character (0: none); bit 7 set if it was a release |
| `$1D` | `KEYMODS` | read: the modifier keys held now (USB's modifier byte: bit 0 left Ctrl, 1 left Shift, 2 left Alt, 3 left GUI, 4-7 the right ones) |
| `$1E` | `ID` | reads `'V'` (`$56`) |
| `$1F` | `VERSION` | reads `$11` (1.1; 1.0 had no `$14-$1D`) |

The rest read 0. The multi-byte registers are big-endian, so `STD` and `LDD` work on them:
`LDA #bank : STA VC_ADDR0 : LDX #addr : STX VC_ADDR0M` points port 0 at `bank:addr`.

**Write the ports with store instructions only.** `CLR`, `INC`, `NEG` and the like read the
register first, and reading `DATA0`/`DATA1` moves the port on. `TFM` is the fast way to move a
block: `TFM X+,Y` with Y at a `DATA` port (or `CMD`) sends W bytes, one every 3 cycles.

## The address space

| Address | |
|---|---|
| `$000000-$03FFFF` | video memory (256KB): everything the picture is made from |
| `$040000-$04003F` | the display settings (below) |
| `$040200-$0403FF` | the palette: 256 colors, 2 bytes each, RGB565 (`RRRRRGGG GGGBBBBB`), high byte first |
| `$800000-$FFFFFF` | the PSRAM (8MB): space for pictures, maps and sounds not on screen yet; `COPY` moves them |

Anything else reads 0 and ignores writes. Layer, sprite and font addresses must be in video
memory (only their low 18 bits count).

## Display settings ($040000)

| Offset | Name | |
|---|---|---|
| `$00` | `DC_CTRL` | bits 0-2: layers 0-2 on; bit 3: sprites on |
| `$01` | `DC_BACK` | the backdrop color: shown wherever every layer and sprite is transparent |
| `$02` | `SPR_CTRL` | bit 0: sprite coordinates are 640x480 pixels (else 320x240, each pixel doubled) |
| `$03` | `SPR_COUNT` | how many sprite table entries are in use (0-128) |
| `$04-$06` | `SPR_BASE` | the sprite table's address |
| `$10-$1F` | layer 0 | (drawn first, at the back) |
| `$20-$2F` | layer 1 | |
| `$30-$3F` | layer 2 | (drawn last, in front) |

Each layer:

| Offset | Name | |
|---|---|---|
| `+$0` | `L_MODE` | bits 0-1: 0 text, 1 tiles, 2 bitmap. Bit 2: hires (640x480; else 320x240 doubled). Bits 3-4: bits a pixel, 1, 2, 4 or 8 (tiles, bitmap). Bit 5: big (16x16 tiles; an 8x16 font, else 8x8) |
| `+$1` | `L_MAP` | the map's size in cells: bits 0-1 width, bits 2-3 height, each 32, 64, 128 or 256 |
| `+$2-$4` | `L_MAPBASE` | the map (text, tiles), or the pixels (bitmap) |
| `+$5-$7` | `L_TILEBASE` | the tiles' pixels, or the font |
| `+$8-$9` | `L_HSCROLL` | where the layer's left edge is in the map or bitmap |
| `+$A-$B` | `L_VSCROLL` | and its top edge |
| `+$C-$D` | `L_STRIDE` | a bitmap's bytes per row |
| `+$E` | `L_PALOFS` | a bitmap's palette offset, times 16, below 8 bits a pixel |

**Transparency:** color 0 is transparent everywhere -- in text backgrounds, tiles, bitmaps and
sprites -- so a pixel of 0 shows what is behind it, down to the backdrop. (So a layer can't show
palette entry 0 itself; the backdrop can.)

**Text layer:** a cell is 4 bytes: the character, its color, its background color, and a spare
byte (0). The font is 8 pixels wide, 8 or 16 lines tall, one byte a line (the leftmost pixel in
bit 7), 256 characters one after another. A text map scrolls and wraps around like a tile map.

**Tile layer:** a map entry is 2 bytes: bits 0-9 the tile (0-1023), bit 10 flipped across,
bit 11 flipped down, bits 12-15 the palette offset (the pixel's color is offset x 16 + its value;
8-bit tiles are colors themselves). A tile's pixels are row by row, packed from the high bits
down: 8x8 at 4 bits is 32 bytes. The map wraps around as it scrolls.

**Bitmap layer:** `L_STRIDE` bytes a row, pixels packed like tiles; its width is
`L_STRIDE * 8 / bits`. Scrolled past the left, right or top edge shows nothing (transparent);
it has no bottom edge but the end of video memory.

**Sprites:** 8 bytes each in the sprite table, high bytes first:

| Byte | |
|---|---|
| 0-1 | the image's address / 32 |
| 2-3 | X, signed |
| 4-5 | Y, signed |
| 6 | bits 0-1 width and 2-3 height (8, 16, 32 or 64); bit 4 flipped across, 5 flipped down; bits 6-7 priority: 0 not shown, 1 in front of layer 0, 2 of layer 1, 3 of layer 2 |
| 7 | bits 0-3 palette offset (4-bit images); bit 7: 8 bits a pixel (else 4) |

Among sprites of the same priority, the lower-numbered one is in front. **At most 32 sprites are
drawn on any line**: the first 32 in the table that cross it.

## Timing and interrupts

The picture is 525 lines a frame, 60 frames a second; lines 0-479 are shown and 480-524 are
vertical blank. Each line is drawn just before it is shown, from the settings as they are then,
so a change made during a line shows from the next line on: a line interrupt can change scrolling
or colors part-way down the screen.

- Vertical blank (`ISR` bit 0) begins at line 480: the time to change what's on screen without
  tearing. `FRAME` counts up then.
- The line interrupt (bit 1) comes as the line in `LINE` begins.
- Commands done (bit 2): the queue has emptied.
- Input (bit 3): a key event was queued, or the mouse moved, clicked or turned its wheel.

A program can poll `ISR` (and write the bit back to clear it), or enable the interrupt in `IEN`
and handle `/IRQ`, which it shares with the UART and the other cards: take it through the BIOS's
RAM jump table (`RAM_IRQV` in `bios/defines.d`: keep the old address, put your handler's, jump
to the old one when the interrupt isn't the card's, and put it back before `B_EXIT`). A handler
that writes the card while the program also does should keep a data port to itself -- `VIDGFX`
sets port 1 on the backdrop with a step of 0 and changes it every 8 lines.

## Mouse and keyboard

The card has a USB host port for a mouse and a keyboard (through a hub, for both). What they do
is in registers `$14-$1D`, the same on the card and in the emulator (where they are the video
window's mouse and keys).

**The mouse.** `LDD VC_MOUSEX` then `LDD VC_MOUSEY` read where it is, in 640x480 pixels
whatever the layers' resolutions (halve them for 320x240): reading `MOUSEX`'s high byte takes a
snapshot of both, so the pair can't tear as the mouse moves. `MOUSEB` has the buttons, and
`WHEEL` counts the wheel's clicks until it is read.

**The pointer.** With `INCTRL` bit 0 set, the card puts sprite 0 where the mouse is at the start
of every vertical blank (writing its X and Y in the sprite table, halved if the sprites are in
320x240 coordinates). The program draws sprite 0 as an arrow (its hot spot at the image's top
left) and the pointer moves with no work from the CPU. In the emulator the PC's own pointer is
hidden over the window while this bit is set.

**Keys.** Each key pressed or released (and pressed again as a held key repeats) is an event in
a queue of 32. Reading `KEY` takes the oldest one off: its USB HID usage code (the key's
place, whatever the layout: `$04` A ... `$1D` Z, `$1E` 1 ... `$27` 0, `$28` Enter, `$29` Esc,
`$4F-$52` the arrows, `$E0-$E7` the modifiers; `vidcard.d` names the rest), or 0 if there was
none. Then `KEYCHAR` has the character it types on a US keyboard (with Shift, Caps Lock and Ctrl:
Ctrl+A is 1), 0 for keys like the arrows, with bit 7 set for a release. `KEYMODS` has the
modifiers held now. `STATUS` bit 4 says an event is waiting. A full queue loses new events;
writing `$80` to `INCTRL` empties it.

**Whose keys.** In the emulator, keys typed into the video window go to the UART, as the
terminal's do, until the program sets `INCTRL` bit 1: then they go to the card's queue (and the
UART sees none of them). A program that takes them should clear the bit before it ends (or
reset the card, which does). If the window is closed (or there is none, `--no-video`) while a
program takes the keys, the terminal's keys become the card's instead -- each character as the
key a US keyboard would press for it, Shift and Ctrl with it, and the arrows and the like from
their escape sequences -- so the program can still be told to stop. The window also lets go of
the mouse's buttons when it loses the focus, so a drag that ends in another window doesn't stay
held. On the card, a USB keyboard's keys always go to the queue, and the
UART's are the terminal's.

A reset (`CTRL` `$80`) clears `INCTRL` and the queue; it leaves the mouse where it is.

## Drawing commands

Commands are written to `CMD` a byte at a time: the opcode, then its parameters. Two-byte
parameters are high byte first, and coordinates are signed, so `FDB` makes them. Everything is
drawn into the **target**, a bitmap anywhere in the address space (in video memory, or in
PSRAM), clipped to its edges, in the current **color**.

| Op | Command | Parameters (bytes) | |
|---|---|---|---|
| `$00` | NOP | | |
| `$01` | TARGET | addr 3, stride 2, width 2, height 2, bits 1 | where drawing goes: 1, 2, 4 or 8 bits a pixel |
| `$02` | COLOR | color 1 | (only its low bits, below 8 bits a pixel) |
| `$03` | PLOT | x, y | |
| `$04` | LINE | x0, y0, x1, y1 | both ends drawn |
| `$05` | RECT | x, y, w, h | the outline |
| `$06` | FILLRECT | x, y, w, h | |
| `$07` | CIRCLE | x, y, r | the outline |
| `$08` | DISC | x, y, r | the circle, filled |
| `$09` | CLEAR | | all of the target, in the color |
| `$0A` | COPY | src 3, dst 3, length 3 | bytes, anywhere in the address space, overlapping or not |
| `$0B` | FILL | dst 3, length 3, value 1 | bytes |
| `$0C` | BLIT | src 3, stride 2, w, h, x, y, flags 1 | a w x h rectangle of pixels (at the target's depth) to x, y; flags bit 0: 0 is transparent |
| `$0D` | TRIANGLE | x0, y0, x1, y1, x2, y2 | filled |
| `$0E` | FONT | addr 3, height 1 | the font `CHAR` draws with |
| `$0F` | CHAR | x, y, char 1 | a character's pixels in the color (the rest untouched) |

An unknown opcode is ignored. `STATUS` bit 6 is set while commands are queued or running: wait
for it to clear before reading back what they drew, or before changing memory they may still use.

## At reset

After power-on or a write of `$80` to `CTRL`:

- the palette is xterm's 256 colors: 0-15 the standard ones (7 light gray, 15 white), 16-231 a
  6x6x6 cube (16 + 36r + 6g + b, each 0-5), 232-255 grays -- the numbers BASIC's `LCOLOR` uses;
- layer 0 is on: an 80x30 text screen, hires, 8x16 font -- its map (128 x 32 cells) at `$038000`,
  all spaces in color 7 on 0, the font at `$03F000`; layers 1 and 2 and the sprites are off;
- the sprite table is at `$037C00`, 128 entries; the backdrop is color 0 (black);
- both ports at address 0, step 1; no interrupts enabled; line interrupt at line 0;
- the draw target is nothing (so drawing does nothing), the color 15, the font the built-in one;
- the rest of video memory is 0. The PSRAM is left as it was.

So text can go on the screen right away: port 0 to `$038000 + (row*128 + col)*4`, then the
character, its color, its background, 0.

## Programming it

From `VIDCARD.D`. A 320x240 bitmap at 8 bits a pixel on layer 0, a red disc on it, and
waiting for the next vertical blank:

```
            LDA  #VC_CFG/$10000
            STA  VC_ADDR0
            LDX  #LAYER0          ; the layer's settings
            STX  VC_ADDR0M
            LDD  #1
            STD  VC_INC0
            LDX  #BITMAP
            LDY  #VC_DATA0
            LDW  #16
            TFM  X+,Y
            LDX  #PICTURE
            LDY  #VC_CMD
            LDW  #PICEND-PICTURE
            TFM  X+,Y
WAIT        LDA  VC_ISR
            BITA #VC_I_VSYNC
            BEQ  WAIT
            STA  VC_ISR           ; (clears it)
            ...
BITMAP      FCB  LM_BITMAP+LM_8BPP,0,0,0,0,0,0,0
            FDB  0,0,320          ; no scrolling; 320 bytes a row
            FCB  0,0
PICTURE     FCB  C_TARGET,0,0,0
            FDB  320,320,240
            FCB  8
            FCB  C_COLOR,196,C_DISC
            FDB  160,120,50
PICEND
```

The demos in `/ASM/VIDEO` on the demo disk use everything the card has, and BASIC has
statements for it (`../basic309/README.md`, "Statements for the video card").

## In the emulator

The emulator (`pugputer`, from `simulator/tools/basic309_sdboot_demo.cpp`) has the card at
`$FF80`, running this same C (`simulator/src/pugputer/video_device.cpp`), its beam in step with
the CPU's clock. A window opens when a program first uses the card; keys typed into it go to the
UART like the console's (or, when the program asks for them, to the card's key queue), and its
mouse is the card's mouse ("Mouse and keyboard").

- While the window is open the emulator keeps to the real machine's speed: 60 frames a second,
  so what waits for vertical blank runs as fast as it would on the Pugputer. `--turbo` lets it
  run flat out (the window then shows a frame every 1/60 s of real time).
- `--scale N` makes the window N times 640x480 (it can be resized too); `--no-video`, no window.
- Windows: a plain Win32 window. Linux: `pugputer-video`, a small SDL2 program beside the
  emulator, which feeds it frames through a pipe (the emulator is linked statically, and SDL2
  can't be). It is built along with the emulator when SDL2's development files are installed
  (`sudo apt install libsdl2-dev`), and needs the SDL2 library to run (`libsdl2-2.0-0`, on most
  desktops already). Without it, or without a display, the emulator says why and goes on
  without a window.
- Commands happen at once in the emulator, where on the card they take time: wait for
  `STATUS` bit 6 anyway.

`simulator/tests/test_vidcard.cpp` checks the registers, every kind of layer, sprites, commands
and timing; `test_vidcard_demo.cpp` assembles the demo with ASM on the emulated machine and runs
it.

## On the card

The firmware is in `firmware/` (how to build and flash it: `firmware/README.md`). It is written
but not yet tried on the hardware.

**Board and bus.** The Olimex RP2350-PICO2-XXL (RP2350B, 16MB flash, 8MB PSRAM, microSD), its
bus pins in one run for PIO (GPIO 16-47), through two TXS0108E level shifters (5V bus, 3.3V
GPIO):

| GPIO | | GPIO | |
|---|---|---|---|
| 32 | /CS: the GAL's select, for `$FF80-$FF9F` *and* `$FFD8-$FFDB` | 42-46 | A0-A4 |
| 33 | R/W, straight from the CPU (valid with the address) | 47 | SD-select: the GAL's second output, high for `$FFD8-$FFDB` |
| 34-41 | D0-D7 | 29 | /RES, through a 10K/20K divider (5V to 3.3V): when it falls, the card and the SD interface are reset, as the emulator does |
| 30 | to the gate of an IRLML6344 (10K to ground) that pulls the bus's shared /IRQ low: high = asserted | 31 | the level shifters' OE (10K to ground: off until the firmware is ready) |
| 12-19 | DVI: D2+ D2- CK+ CK- D1+ D1- D0+ D0- (220 ohm each) | 25 | the board's LED: lit while the SD card is ready, dark while it's busy |
| 8 | the PSRAM's chip select (on the board) | 9-11, 24 | the microSD, SPI1: CS, SCK, MOSI, MISO (on the board) |
| 0-1 | UART0 (the UEXT connector): the firmware's messages, 115200 baud | | |

- **The GAL** (ATF16V8B; its equations are `hardware/VIDCARD.PLD`, from /IO, A2-A7, E and Q)
  makes **/CS**, low for either `$FF80-$FF9F` or `$FFD8-$FFDB`, and **SD-select**, high only for
  `$FFD8-$FFDB`. The card reads A0-A4 and SD-select as one 6-bit register number: 0-31 are the
  video card's registers, and the SD card's four land at 56-59 (A0-A4 = `$18-$1B`, plus 32). It
  also selects the **YMF262 (OPL3)**, which shares the card: **/OPL**, low for `$FFE0-$FFE3`
  while E is high.
- **/CS times every access**, so the GAL qualifies its decode with E or Q: /CS is low only while
  E or Q is high, from Q rising (the address valid) to E falling. It then goes high between bus
  cycles, even between two back-to-back accesses to the card (an `LDD`, a `TFM`). The card
  answers a read as /CS falls and drives the data until it rises; it takes a write's data as
  /CS rises, when E falls.
- **R/W** says which: the card samples it as /CS falls, and has until E falls, about 150ns, to
  drive a read's data.
- **The Pugputer's /RD and /WR aren't used.** The CPU card's GAL makes them from R/W alone (/WR
  is R/W, /RD its inverse, a little later), not gated by E, so they say whether a cycle reads or
  writes but not *when* its data is valid. During back-to-back writes (an `STD`, a `TFM`) /WR
  stays low throughout, with no edge between them, and a part that takes its data as /WR rises
  takes it when the address changes, at the start of the next cycle. They'd be true strobes if
  the GAL gated them with E (low only while E is high): worth doing the next time it's
  reprogrammed. This card doesn't depend on it either way.
- HDMI connector pin 18 wants +5V (from VCC): displays use it to see that a source is there, and
  without it some show the picture but keep flashing "check signal" over it.
- VSYS from the bus's VCC through a Schottky diode (the board has its own from USB's VBUS), so
  the card runs from the bus and USB can stay plugged in. The level shifters' 5V side is VCC
  itself, not VSYS: with the Pugputer off and the card on USB, they're unpowered on that side
  and keep out of the bus.

**Serving the bus.** One PIO block (its GPIO window set to 16-47) with two state machines
(`firmware/src/bus.pio`):
- **reads** take the register number as an index into a 64-byte copy of the registers kept in
  SRAM; a chained DMA fetches the byte, which is driven onto D0-D7 until /CS rises -- no CPU in
  the way;
- **every access** (reads too: some have side effects, like a data port stepping on) is logged,
  {read or write, register, data, with a write's taken as /CS rises}, by DMA into a ring of 4096,
  and an interrupt on core 0 applies them in order and brings the copy up to date
  (`DATA0`/`DATA1` hold the byte at the port's address, fetched again after every access). The
  CPU's fastest accesses (`TFM`, one every 840ns) set how quickly that must happen.
- Drawing commands go into a 4KB queue that core 0's main loop works through; `STATUS` says
  busy while any are waiting, and "queue full" near its end. A reset waits for the command
  being drawn to finish, and the accesses after it wait in the ring until it's done.

**Drawing the picture.** Core 1 runs `vc_render_line()` a line ahead of the beam into one of two
line buffers; HSTX's TMDS encoder sends it out as DVI (RGB565 in, 640x480, pixel clock 25.2MHz:
the system clock is 252MHz, HSTX half of it). Core 0 serves the registers and runs the commands.
Video memory and the settings are in SRAM; the PSRAM (through the XIP cache) is only read by
`COPY`, `BLIT` and the ports. The firmware runs from SRAM too (copied from flash at start).

**The SD card.** The Pugputer's SD interface (`SD_LBA`, `SD_DATA`, `SD_CMDSTA` at `$FFD8-$FFDB`:
`../bios/defines.d`) is the board's microSD card, so the BIOS, DOS and the emulator need no
change. The firmware works it in SPI mode (25MHz once it's awake): a block comes off the card in
about 0.3ms, while the BIOS takes about 2.3ms to copy one out of `SD_DATA`, so SPI mode is no
bottleneck. Reads keep `BUSY` set until the block is in the buffer. Writes are taken at once and
written while the CPU gets on (SD cards may take up to 250ms over a write, about as long as the
BIOS waits): another write or a read waits for it, and if it can't be written, the next command
fails once with `ERROR`. Until the card has woken up at power-on, the status says `BUSY`. The
board's card-detect switch isn't wired to a GPIO, so `CARD` means "the card answered".

**Mouse and keyboard.** The RP2350's USB port as a host (TinyUSB's HID host, through a small
hub for a keyboard and a mouse, whose 5V then comes from the bus, not from the board's VBUS
diode), in the boot protocols: a mouse reports how far it moved, which `vc_mouse_by()` adds up, and a keyboard
reports the keys held, whose changes become `vc_key()` calls (with the repeat of a held key made
by the firmware). If USB host turns out not to fit beside the picture, a PIO USB port on spare
GPIOs, or a separate input card at another address with the same registers, would do instead.
(Not in the firmware yet: it comes once the bus, the picture and the SD card work.)

**Limits to confirm on the hardware.** A line takes 31.8us: about 4700 cycles at 150MHz, 8000 at
252MHz. Three hires layers plus 32 wide sprites on one line may not fit in that. If they don't,
the firmware will document a smaller budget (fewer hires layers, or fewer sprite pixels on a line)
and the C here will be made to keep to it too, so the emulator shows what the card can do.
The CPU's fastest writes (`TFM`, one every 840ns) set how quickly core 0 must take a register
write.
