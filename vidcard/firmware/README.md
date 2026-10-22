# The video card's firmware

The Pugputer 6309 video card on an Olimex RP2350-PICO2-XXL: the card of `../core` on the bus at
`$FF80-$FF9F`, its picture out by DVI (640x480, 60Hz), and the Pugputer's SD interface at
`$FFD8-$FFDB` on the board's microSD card. The wiring, and how it all works, is in
`../README.md`, "On the card" and "The SD card".

**Status: it builds, but hasn't been tried on the hardware yet.** Not in it yet: the mouse and
keyboard (USB host).

| File | |
|---|---|
| `src/config.h` | the pins and clocks |
| `src/main.c` | start-up; core 0's main loop |
| `src/bus.pio`, `src/bus.c` | the bus: reads answered by PIO and DMA from a copy of the registers; every access logged by DMA for core 0's interrupt |
| `src/card.c` | the card between the bus, the drawing commands (a queue) and the beam; keeps the register copy up to date |
| `src/dvi.c` | the picture: HSTX's TMDS encoder, two DMA channels, core 1 drawing a line ahead |
| `src/sd.c` | the microSD card in SPI mode |
| `src/blockdev.c` | the SD interface's registers (as the emulator's `SdCardDevice`), on `sd.c` |
| `../core/` | the card itself: the same C the emulator runs (built here with `VC_ATOMIC_FLAGS`) |

## Building

With VS Code's Raspberry Pi Pico extension (it installs the Pico SDK 2.3.1, the compiler and the
tools): open this folder, let the extension import it as a project, and build. Or by hand,
from this folder (the paths are where the extension puts things):

```
cmake -S . -B build -G Ninja -DPICO_SDK_PATH=%USERPROFILE%/.pico-sdk/sdk/2.3.1 ^
      -DPICO_TOOLCHAIN_PATH=%USERPROFILE%/.pico-sdk/toolchain/15_2_Rel1 ^
      -Dpicotool_DIR=%USERPROFILE%/.pico-sdk/picotool/2.3.1/picotool ^
      -Dpioasm_DIR=%USERPROFILE%/.pico-sdk/tools/2.3.1/pioasm
cmake --build build
```

That makes `build/vidcard.uf2` (and `.elf`, for a debugger).

## Flashing

Hold the board's BOOT button while plugging in USB (or while pressing RESET): it shows up as a
drive; copy `vidcard.uf2` onto it. Or `picotool load -x build/vidcard.uf2` with the board in
BOOTSEL mode.

Plug a serial adapter (3.3V) into the UEXT connector's UART (GPIO0 TX, GPIO1 RX, 115200 baud)
to see what it says at start:

```
Pugputer 6309 video card: 252 MHz, PSRAM 8192 KB, SD card ready
```

The same line shows at the top of the screen at power-on, until a program resets the card.

## Trying it, step by step

1. **The picture alone**: the board on USB power, a display on the HDMI connector, nothing on the
   bus. The card's reset screen should show, with the line above at the top.
2. **The SD card alone**: a card in the slot; the LED lights when it has answered, and the UART
   says so.
3. **On the bus**: `/CS` and SD-select from the GAL, R/W, the level shifters. Then from the
   Pugputer: `VIDDEMO` and the other demos in `/DEMO`, and booting from the card.
