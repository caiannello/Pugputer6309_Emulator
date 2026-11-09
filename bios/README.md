# The BIOS

`pugbios.s19` is the 4KB ROM at `$F000-$FFFF` (code to `$FEFF`, the I/O window, the vectors
at `$FFF0`). Build it with `compile.bat` (or `..\reinit_disk.bat`, which rebuilds everything).
Every call, argument and error code is documented in `defines.d`; this file collects what
isn't obvious from there.

## Layout

| Module | |
|---|---|
| `main.asm` | reset, the SWI2 dispatcher and its tables, the fault handlers, the vector table |
| `devio.asm` | device table, stdio aliases, `B_PUTC`/`B_GETC`/... |
| `serio.asm` | interrupt-driven UART driver (126-byte RX and TX rings) |
| `sdcard.asm` | block driver (32-bit block numbers), the disk-boot sequence, the DOS call gateway |
| `banks.asm` | RAM banking: page probing and allocation, bank get/set, page copy |
| `loader.asm` | the S-record boot prompt (used when there is no bootable disk) |
| `time.asm` | the 16 Hz NMI tick |
| `helpers.asm` | string helpers, the ring buffer |

RAM below `EndOfVars` (`pugbios.map`, currently `$05AE`) is the BIOS's; DOS loads at `DOS_LOAD`
(`$0600`). About 380 bytes of the ROM code area are free.

## Which devices are there

`B_DQUERY` returns a bitmap of the devices registered (bit n: device n): the null device, the
console's three aliases and the UART always (`$010F`), and the video card (`F_VDP`, bit 9:
`$030F`) when the BIOS found it at boot. It looks for the card with reads only, of its last two
registers: `ID` (`$FF9E`) must read `'V'` and `VERSION` (`$FF9F`) `$11` or later. A write would
wake the emulator's video window. With no card there, a read gets whatever the bus floats at on
the machine, or the RAM underneath in the emulator, not that pair.
BASIC's `SCREEN` asks `B_DQUERY` and stops with `?NV ERROR` (34) when the card isn't there.

## The console

| At power-on | Console | Then |
|---|---|---|
| No video card | the UART | the S-record loader (the SD card is on the video card) |
| The card, a bootable SD card | the card | DOS |
| The card, no bootable SD card | the card | "Insert a bootable SD card and press a key.", with the S-record loader open on the UART meanwhile |

`DEV_VC_DETECT` makes the card the console when its `STATUS` register says so (bit 0: the firmware
always does, and the emulator when it has a window: `../vidcard/README.md`, "The console"). It
then resets the card and points `F_STDOUT`, `F_STDERR` and `F_STDIN` at it, and `F_VDP` is a real
device: output goes to the card's ANSI terminal, which does the escape sequences itself, so the
ROM needs only a few bytes for it. A card that doesn't say so takes the null device's routines
(nothing to read, writes dropped), and the console stays on the UART.

- **Input** is the card's keyboard, or else what comes in on the UART: both work at once, except
  that while a program has taken the card's keys (`INCTRL` bit 1) only the UART does.
- **The boot banner, the "no disk" message, a failed boot and a crash report** go to both the UART
  and the screen (`CON_PUTS`). Everything else goes to the screen only: the UART at 19200 baud
  would take over a second for a full screen. A crash resets the card first, so the message can
  be seen whatever the program had on the display.
- **A key at the "no disk" message** starts the boot again, from the reset. It's the card's
  keyboard only: what comes in on the UART is for the S-record loader.

## At power-on

The video card's RP2350 starts when the CPU does, so the BIOS gives it time:

- `DEV_VC_DETECT` reads the card's ID again and again for about half a second (`VC_WAKE`) before
  deciding there's no card: the card keeps its level shifters off the bus until its firmware is
  running, some tens of ms. A boot without a card is half a second slower for it.
- `SD_BOOT_TRY` gives the SD card about 3 seconds (`SD_WAKE`) to stop saying BUSY before it reads
  the boot sector: the card's firmware is on the bus before it has woken the microSD card. If the
  status reads with any of bits 3-7 set (they're always 0), nothing's there and it doesn't wait.
- `SD_WRITE_BLOCK` waits for BUSY to clear before it looks at CARD.

`test_basic309_video.cpp` boots with both coming up late (the devices' `set_wake_cycles()`).

The 16 Hz NMI tick (`time.asm`) is the CPU card's; the emulator doesn't make it yet, so on the
machine it's the one BIOS code path the tests haven't run.

## What the BIOS does when things go wrong

- **SD card.** A command the card reports as failed is retried (`SD_TRIES` = 3 attempts in all);
  a card that stays BUSY for `SD_TIMEOUT` polls gives `ERR_TIMEOUT` instead of hanging; no card
  is `ERR_NOCARD`; repeated failure is `ERR_IOERR`. A block buffer that is not entirely below
  the ROM (`$F000`) is `ERR_BADPARAM` -- a transfer there would land on the hardware registers.
  (DOS turns every block failure into `ERR_IOERR` for its callers.)
- **Disk boot.** `SD_BOOT_TRY` only loads DOS from a volume whose boot sector has the `$55AA`
  signature, the FAT16 type string, 512-byte sectors and a reserved-sector count that leaves
  room for DOS in bank 0 (`DOS_MAXSECT`); anything else falls through to the S-record prompt.
  A read failure part-way through loading DOS says "Disk boot failed" and does the same.
- **UART.** Receive errors are remembered until asked for: `B_IOCTL` on `F_UART` with function
  `UT_IOC_GETERR` returns (in `B`) bit 0 parity, bit 1 framing, bit 2 receiver overrun, bit 3
  "the RX ring overflowed and a byte was dropped", and clears them. Interrupt masks are
  preserved: `B_PUTC` and friends never leave interrupts enabled for a caller that had them off.
- **S-record loader.** Lines longer than the buffer, byte counts that don't fit or don't match
  the line, records with no data, non-hex characters, and destinations below the BIOS's RAM
  or reaching the ROM/I/O area (`$F000` up, where the bank registers live) are rejected with
  " <- bad rec"; nothing is loaded.
- **A crashing program.** An illegal opcode, a divide by zero or an `SWI` prints where it
  happened, then the BIOS puts the machine right -- system stack, direct page 0, banks 1-3 back
  to the reset mapping (pages 1-3), interrupts on -- and calls `B_EXIT`: with DOS present the
  shell restarts; without one you get the S-record prompt. (The breakpoint handler used to fall
  into its own message strings and execute them.)

## Stack

A BIOS or DOS call needs only a few dozen bytes of the caller's stack: the deepest DOS path in
`test_bios_audit.cpp`'s battery (file creation in a subdirectory, directory growth, FAT
allocation) used 44 bytes including the 14-byte `SWI2` frame and the nested block call. An
interrupt adds another 14 (the UART ISR is short). A program should keep at least 128 bytes
free. The BIOS's own 512-byte stack is the one DOS and the first program start on
(`BOOT_SP`); the shell moves to `$7F00`, BASIC sets its own.

## Not done

- No direct-call entry (a fixed `JSR` table) alongside `SWI2`: the frame push/pop costs about 40
  cycles a call, which nothing measured so far needs back.
- The UART's transmit side blocks (with interrupts serviced) when the ring is full; it has no
  timeout, so a stuck `CTS` line would stop output. A real board may want one.
