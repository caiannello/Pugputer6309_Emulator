# HD6309 CPU Emulator

A cycle-counted HD6309 (and 6809-compatible emulation-mode) CPU core in
C++17, built as a static library and a shared library (DLL) behind a
stable C API (`include/hd6309/hd6309.h`), with a test suite that mixes
direct unit tests and "golden" tests assembled with the HD6309-mode
cross-assembler already in this repo (`lwtools-4.20/lwasm`).

This is meant to become the CPU core of a full Pugputer6309 machine
simulator (BIOS ROM, interrupt vectors, 16 Hz NMI, UART/keyboard/
graphics/SD-card peripherals, RAM paging). To keep that possible, **the
CPU never owns memory** -- every access goes through `read`/`write`
callbacks supplied at creation time (`hd6309_create`). A simple flat
64KB RAM bus is provided for standalone use and for this test suite;
the real machine simulator should install its own callback doing
paging/ROM-overlay/IO dispatch instead.

On top of that CPU core, `pugputer_system` (in `include/pugputer/` and
`src/pugputer/`) adds a `SystemBus` (CPU + flat RAM + a table of
memory-mapped IO devices, wiring each device's interrupt output to the
right CPU line) and the first real device: a register-exact emulation of
the Pugputer6309's R65C51 UART. See "System bus + IO devices" below.

## Building

```
cmake -S . -B build -G "Visual Studio 17 2022"
cmake --build build --config Debug
ctest --test-dir build -C Debug --output-on-failure
```

(or open a Visual Studio developer shell and use `-G Ninja` for a faster
iterate/build/test loop.) Requires CMake 3.15+ and a C++17 compiler.

The disk-backed tests need `bios/pugbios.s19`, `dos/dos.bin` and
`basic309/exbasrom309.s19`/`.lst`/`disk.img` to exist: run `reinit_disk.bat` from the
repository root first (it rebuilds all three programs and regenerates `disk.img`). The
full `pugputer_tests` run takes a few minutes; pass name fragments to run just some
(`pugputer_tests seqfiles randomfiles`). BASIC itself -- the dialect, the file statements,
adding keywords -- is documented in `basic309/README.md`.

Produces:
- `hd6309.lib` / `hd6309.dll` (`hd6309_shared` target) -- the public C
  API surface for out-of-process or cross-language consumers.
- `hd6309.lib` (`hd6309_static` target) -- same sources, linked directly
  by the test suite.
- `pugputer_system.lib` (`pugputer_system` target) -- `SystemBus` +
  `IDevice` + `UartR65C51` (+ the Windows COM-port bridge, when
  `PUGPUTER_BUILD_COM_BRIDGE` is on, the default on Windows), linked on
  top of `hd6309_static`. Static only for now -- an in-process
  integration layer, not a DLL boundary that needs its own ABI yet.
- `hd6309_tests` / `pugputer_tests` -- the two test executables, both
  registered with CTest.
- `uart_demo` / `basic309_demo` / `basic309_sdboot_demo` (Windows only) --
  small standalone interactive demos; see below.

## API

See `include/hd6309/hd6309.h` for the full surface. In short:

```c
hd6309_t* cpu = hd6309_create(read_fn, write_fn, ctx);
hd6309_reset(cpu);
hd6309_set_irq(cpu, 1);           // level-sensitive
hd6309_nmi_pulse(cpu);            // edge-triggered
uint64_t cycles = hd6309_step(cpu);
uint64_t consumed = hd6309_run(cpu, 100000);
hd6309_add_breakpoint(cpu, 0x9000);
hd6309_regs_t regs; hd6309_get_regs(cpu, &regs);
```

`hd6309_ram_bus_create()` gives a ready-to-use flat 64KB RAM bus for
tools/tests that don't need a custom memory map.

## Ground truth used for opcodes and cycle counts

Rather than trust the OCR'd programming manual in `Claude_Readme/` for
opcode bytes and per-addressing-mode cycle counts, this emulator was
built directly against `lwtools-4.20/lwasm/instab.c` (the authoritative
opcode/addressing-mode table used by the working cross-assembler already
in this repo) and `lwtools-4.20/lwasm/cycle.c` (its per-opcode cycle
table, which separately gives 6809-emulation-mode and 6309-native-mode
timing). That source caught real gaps in the programming manual's
Appendix A -- e.g. `NEGW`/`ASRW`/`ASLW` ($1050/$1057/$1058) are absent
from both `instab.c` and `cycle.c` even though Appendix A lists them;
this emulator treats them as illegal (they trap), matching the
assembler rather than the manual.

## Known simplifications / approximations

These are documented here rather than silently guessed at:

- **Interrupt response latency** (the fixed overhead of stacking
  registers and fetching the vector for IRQ/FIRQ/NMI) isn't in
  `cycle.c` at all -- it's an asynchronous hardware event, not an
  assembled instruction. This emulator uses the standard published
  6809 figures (19 cycles full-stack, 10 cycles FIRQ's partial stack)
  and a native-mode estimate following the same +2-cycles-for-E/F
  pattern visible on SWI/SWI2/SWI3 in `cycle.c`.
- **RTI's cycle count** is case-dependent (partial- vs full-stack
  restore) in real hardware; `cycle.c` only gives one flattened,
  `CYCLE_ESTIMATED`-flagged number since the assembler can't know which
  case applies at a given call site. This emulator instead uses the
  OCR'd Appendix A figures for both cases (6 partial, 15/17 EM/NM full),
  which are more precise here than `cycle.c`.
- **TFM's per-byte cost** is approximated as 6 base + 3 cycles/byte
  transferred; `cycle.c` flags its own TFM entries `CYCLE_ESTIMATED`
  too, for the same reason (the byte count is a runtime value in W, not
  known at assembly time). TFM *is* correctly interruptible mid-transfer
  here, though: a pending IRQ/FIRQ/NMI breaks out of the copy loop with
  W/pointers left at the correct partial-progress values and PC rewound
  to the start of the TFM instruction, so it resumes correctly on the
  next `hd6309_step()`, matching real HD6309 behavior.
- **DIVQ's indexed-addressing cycle count**: `cycle.c` doesn't flag
  DIVQ's indexed variant (`$11AE`) with `CYCLE_ADJ` the way every other
  indexed opcode is flagged, meaning real hardware (or at least the
  assembler's model of it) doesn't add postbyte-dependent extra cycles
  there. This emulator adds them anyway for implementation simplicity
  (one addressing-mode helper shared by every opcode) rather than
  special-casing a single rarely-timing-critical instruction.
- **DIVD/DIVQ/MULD flags** beyond N/Z/V-on-overflow (specifically the
  exact carry-flag behavior) are one of the less-documented corners of
  the real chip; this emulator always clears C for these three
  instructions rather than guessing at undocumented behavior.
- **Undocumented/illegal opcodes** are not emulated for quirk-compatibility
  with real silicon -- any opcode not in `instab.c`'s legal set raises
  the documented Illegal Opcode Trap (vectors through $FFF0, sets
  MD.6), which is enough to run software you control (a BIOS/OS you
  wrote yourself) but won't reproduce undocumented behavior that some
  legacy 6809 software depended on.
- **NMI is not disabled until the stack is first set up** the way real
  6809/6309 hardware masks the very first NMI until software has loaded
  S at least once after reset. This is a minor startup-ordering
  protection this emulator doesn't implement; BIOS code should still set
  up S before enabling NMI regardless.

## System bus + IO devices

### `IDevice` / `SystemBus`

`include/pugputer/device.hpp` defines the interface every memory-mapped
IO device implements:

```cpp
class IDevice {
public:
    virtual uint8_t read(uint16_t offset) = 0;   // offset relative to the device's mapped base
    virtual void write(uint16_t offset, uint8_t value) = 0;
    virtual void reset() = 0;
    virtual void tick(uint32_t cpu_cycles) {}      // advance internal timing state
    virtual bool irq_asserted() const { return false; }
};
```

`SystemBus` (`include/pugputer/system_bus.hpp`) owns an `hd6309_t*`, banked
RAM (below) as the default backing store, and a list of
`DeviceMapping{name, base, size, IDevice*, IrqLine}` entries -- this list
*is* the system-level metadata describing how each device is wired in,
so adding or reconfiguring a device later is a `map_device()` call, not
a change to the bus's dispatch logic:

```cpp
pugputer::SystemBus bus;
pugputer::UartR65C51 uart;
bus.map_device("uart", 0xFFE8, 4, &uart, pugputer::IrqLine::IRQ);
bus.reset();
bus.run(100000); // steps the CPU, ticks every device, updates IRQ/FIRQ/NMI each step
```

**RAM banking.** The Pugputer6309's CPU address space is four 16KB banks; each
of four write-only 8-bit registers at `$FFEC-$FFEF` supplies physical address
bits A21..A14 for its bank (CPU A15,A14 pick the register, CPU A13..A0 are the
offset in the page), so any bank can point at any of 256 pages of a 22-bit
space. `SystemBus` models exactly that: `SystemBus(ram_pages = 64)` installs
1MB (pages beyond the installed RAM read `$FF` and drop writes), and
`bus.map_bank_registers()` makes the registers writable by the CPU. Devices
(ROM, UART, ...) are decoded from the CPU address alone, so banking never
affects them. Until `map_bank_registers()` is called, or after `reset()`, the
banks sit at their reset mapping (banks 0..3 -> pages 0..3), which makes
`bus.ram()[a]` the CPU's view of address `a`; once a program remaps a bank,
use `phys_ram()` (physical addresses) or `read_cpu()`/`write_cpu()` (through the
current banking). The real registers can't be read back -- the BIOS keeps
shadow copies (`SBANK_1..3` in `bios/main.asm`); `bank_register(n)` is the
simulator's own view, for tests. The BIOS keeps bank 0 permanently on page 0
(its variables, and the resident DOS, live there); applications may remap
banks 1-3. All the BIOS-based harnesses and demos call `map_bank_registers()`.

**The BIOS bank service** (`bios/banks.asm`, function codes `$29`-`$2E` in `bios/defines.d`).
Applications never write the bank registers directly (that would desynchronize the shadow
copies); they call the BIOS:

- `B_BANK_GET` / `B_BANK_SET` read and change the page shown in a bank. Bank 0 is refused (it is
  the system's), as is a page that isn't installed and the bank the caller's own stack is in
  (remapping it would strand the SWI2 frame the call returns through) -- `ERR_BADPARAM`.
- `B_PAGE_ALLOC` / `B_PAGE_FREE` / `B_PAGE_INFO` -- an allocator over the 16KB pages: lowest free
  page first, pages 0-3 never handed out (page 0 is the system's; 1-3 are the reset mapping of
  banks 1-3, where a 64KB program such as BASIC runs). `B_PAGE_INFO` reports installed and free
  page counts.
- `B_PAGE_COPY` copies a byte range between two pages (any pair, whatever the banks show)
  through temporary mappings in two banks other than the stack's, with interrupts masked only
  while the mapping differs from the caller's, then restores the caller's mapping.

At reset `PAGE_INIT` probes the RAM (tags at the start of each page, verified ascending) to find
how many pages are installed (4 to 256), so the same BIOS runs on any populated size.
The resident DOS is loaded at the fixed address `DOS_LOAD` (`$0600`), which must stay above the
BIOS's variables (`test_bios_layout` checks it against `pugbios.map`).

`IrqLine::IRQ`/`FIRQ` are level-sensitive: `SystemBus::step()` recomputes
each line every step as the OR of every device mapped to it, and pushes
the result to the CPU. `IrqLine::NMI` is edge-pulsed on a device's
false->true transition (no current device uses it; it's there for a
future timer). Addresses outside every mapping fall through to RAM.

### `UartR65C51` -- R65C51 ACIA-compatible UART

Register-exact against
`Claude_Readme/Pugputer6309_CPU_Card/R65C51_text.txt` and validated
against the real driver in `bios/serio.asm` (Control=`$1F`,
Command=`$09` for 19200 baud/8N1/RX-IRQ-on/TX-IRQ-off/DTR-ready, exactly
matching the BIOS's own init sequence). It has its own fixed 1.8432MHz
crystal (independent of the CPU clock) driving its internal baud-rate
generator, and paces TDRE/RDRF against real character time using a
settable `cpu_clock_hz` (defaults to the Pugputer6309's
14.318MHz/4 = 3,579,545 Hz main clock) to convert CPU cycles into
real time.

Host-facing API:

```cpp
uart.rx_enqueue(byte);                  // host -> UART ("a byte arrived on the wire")
uart.set_tx_callback([](uint8_t b){});  // UART -> host, called as each byte finishes transmitting
uint8_t b; uart.tx_dequeue(b);          // ...or poll instead of/alongside the callback
uart.set_dsr(true); uart.set_dcd(true); uart.set_cts(true); // modem lines, default always-ready
```

Known simplifications (documented in `uart_r65c51.hpp`, same spirit as
the CPU core's own documented gaps):
- DCD/DSR are modeled as simple booleans that reflect in the Status
  register but don't independently trigger IRQ -- the BIOS ISR never
  checks them, so that nuance is out of scope for now.
- Control register SBR=`0000` ("16x external clock") is unsupported --
  there's no simulated external RxC clock source; that baud "rate" reads
  back as 0 and transfers never complete.
- Command register TIC=`00` ("transmitter disabled") only gates whether
  a completed TDRE re-latches IRQ, not whether transmission physically
  happens -- the BIOS only ever uses TIC=`00` as its resting/idle state
  (no data pending anyway), so this doesn't affect real usage.
- DIVD/DIVQ/MULD-style undocumented flag corners don't apply here (the
  UART's status bits are all fully documented), but the exact same
  "always clears C" pattern isn't relevant either -- this device has no
  analogous gap.

### `ComPortBridge` (Windows) + com0com setup

`include/pugputer/com_port_bridge.hpp`, built when
`PUGPUTER_BUILD_COM_BRIDGE` is on (default on Windows), bridges a
`UartR65C51` to a real Windows COM port using `CreateFileA`/`SetCommState`/
`ReadFile`/`WriteFile` -- no background thread, just a `poll(uart)`
method the host calls periodically from its own loop. To use it with a
virtual null-modem pair for a real terminal program to connect to:

1. Install [com0com](https://com0com.sourceforge.net/) (a third-party
   kernel driver -- not something this project installs for you).
2. Use its setup tool to create a port pair (the default `CNCA0<->CNCB0`
   shows up as e.g. `COM10`<->`COM11` in Device Manager).
3. Point this emulator at one end (`ComPortBridge::open("COM10")` /
   `uart_demo --com COM10`) and a terminal program (PuTTY, TeraTerm, ...)
   at the other (`COM11`).

**I could not verify the live loopback through an actual com0com pair**
in the environment this was built in (no com0com installed here, and
installing a kernel driver is outside what I can do) -- I verified the
graceful-failure path (opening a nonexistent port name fails cleanly with
a reported error and `uart_demo` falls back to console mode) and built
`ComPortBridge` carefully against the standard Win32 serial API patterns,
but the actual byte-pumping-through-a-real-port-pair path needs
verification on your end once com0com is installed.

### `uart_demo` -- interactive smoke test

```
uart_demo                 # bridges the UART to this console
uart_demo --com COM10     # bridges it to a COM port instead (see above)
```

Boots a small interrupt-driven echo program (the same one
`tests/test_asm/uart_echo.asm`'s golden test uses, embedded as bytes so
this tool doesn't need `lwasm.exe` at run time) and echoes whatever you
type straight back, exactly like the BIOS's own RX-IRQ -> read Data ->
write Data pattern.

### `RomDevice` + `load_srec_file` -- loading a real ROM image

`include/pugputer/rom_device.hpp`: a fixed-size `IDevice` whose `write()`
is a true no-op -- reads always return the loaded contents, regardless of
what's been written. This is what makes a classic BASIC-style RAM-size
probe (write a test byte, read it back, see it didn't "stick" -> that's
where ROM starts) behave correctly once a `RomDevice` is mapped over a
ROM's address window.

`include/pugputer/srec_loader.hpp`: `load_srec_file(path, mem, mem_size)`
parses a Motorola S-record (`.s19`) file and applies every S1/S2/S3 data
record directly into a caller-supplied buffer, verifying every record's
checksum (a mismatch is reported as an error, not silently loaded) and
rejecting any data record that would fall outside `[0, mem_size)` rather
than truncating or wrapping it. S0/S5/S6/S7/S8/S9 records are parsed and
checksum-validated but produce no writes (a 6809-family reset vector
comes from ROM at `$FFFE`, not from an S19 end record's execution-start
address).

**Loading a ROM image:** load the whole S19 file into a scratch buffer, then
snapshot just the ROM's own address range out of it and hand that to a
`RomDevice` mapped over the same window. (An S19 can hold blocks outside
the ROM window -- those are not part of the ROM and must not be mapped as
read-only.) The BIOS is loaded this way:

```cpp
std::vector<uint8_t> image(65536, 0);
auto result = pugputer::load_srec_file("bios/pugbios.s19", image.data(), image.size());
// result.ok, result.min_addr/max_addr describe what the file covered

pugputer::RomDevice rom(0x1000); // $F000-$FFFF
rom.load(image.data() + 0xF000, 0x1000);

pugputer::SystemBus bus;
bus.map_device("bios_rom", 0xF000, 0x1000, &rom, pugputer::IrqLine::None);
bus.reset(); // PC comes from the ROM's own $FFFE reset vector
```

### `SdCardDevice` + `fat16_image.hpp` -- emulated SD card and disk images

`include/pugputer/sdcard_device.hpp`: an `IDevice` for a block-storage
peripheral, backed by a raw disk image file. Deliberately an *idealized*,
transport-agnostic register interface (closer to ATA PIO mode than real
SPI/SD protocol) rather than a simulated SPI/SD command sequence, since
the real Pugputer6309's SD/SPI transport hardware isn't decided yet
(bit-banged via a VIA vs. offloaded to an MCU) -- see `bios/sdcard.asm`'s
file header. Register window (4 bytes; see `bios/defines.d`'s `SD_LBA`/
`SD_DATA`/`SD_CMDSTA`): a 16-bit LBA register (the low word of a 32-bit
block number; a third command, SETHI, latches the register's value as the
high word, which stays until changed and is 0 after reset), a streaming
data port with an auto-incrementing cursor into a 512-byte sector buffer,
and a command/status register (write = issue read/write block at the
current LBA; read = busy/card-present bits). The BIOS exposes the 32-bit
form as `B_BLK_READ32`/`B_BLK_WRITE32` (the older 16-bit calls always use
high word 0). Commands complete synchronously
(BUSY is always immediately clear) since there's no real transport timing
to model yet.

`include/pugputer/fat16_image.hpp`: `build_fat16_image(path, dos_payload,
files, ...)` writes a fresh, *unpartitioned* ("superfloppy" -- no MBR,
sector 0 is the FAT16 boot sector directly) disk image: the same raw
format real SD-flashing tools (`dd`, Win32DiskImager, Raspberry Pi
Imager, ...) write byte-for-byte to a physical card, and that `mtools`/
Windows can read. `dos_payload` (see `dos/dos.asm` below) is written
starting at LBA 1, right after the boot sector, sized into the BPB's
reserved-sector-count automatically; `files` become normal root-directory
entries with real FAT16 cluster chains. This is the on-disk format's
single source of truth on the host side -- `dos/dos.asm`'s parser must
stay in sync with it by convention (the same relationship `srec_loader`
has with the S-record spec: two independent implementations of one
well-known/self-defined format, not one calling the other).

### `basic309_demo` / `basic309_sdboot_demo` -- running BASIC interactively

```
basic309_sdboot_demo                     # the real thing: BIOS -> SD boot -> DOS -> BASIC.COM, from basic309/disk.img
basic309_sdboot_demo --com COM10         # bridge the UART to a COM port instead (com0com setup above)
basic309_sdboot_demo --bios x.s19 --disk y.img
basic309_demo                            # BASIC copied into RAM and started directly, no disk (LOAD/SAVE/OPEN unavailable)
```

`basic309_sdboot_demo` is the one to use: files you `SAVE` or `OPEN` persist in
`basic309/disk.img` until `reinit_disk.bat` regenerates it. `basic309_demo` skips the disk
(it maps no SD card, so any file statement raises a BASIC error) and exists for quick
interpreter-only experiments.

### `dos/dos.asm` + boot chain -- BASIC as a disk file, not a hijack

Earlier work booted `basic309/exbasrom309.s19` by mapping it as a second
ROM device and setting PC to its entry point directly -- explicitly
flagged at the time as standing in for a real loader. That loader now
exists for real:

```
V_RESET (bios/main.asm)  --calls-->  SD_BOOT_TRY (bios/sdcard.asm)
  reads block 0, checks for a valid FAT16 signature
    none found  -> returns; V_RESET falls through to the existing
                   S-record loader prompt (also what happens with no
                   SdCardDevice mapped at all -- an unmapped read reads
                   back as zero, which never matches the signature)
    found       -> loads the volume's reserved sectors (dos/dos.asm,
                   assembled as a flat raw binary, not ROM) to RAM and
                   jumps there, never returning

dos/dos.asm (a real BIOS client, talks to BIOS purely via SWI2 block calls)
  parses the BPB, installs its calls in the BIOS's JT_DOS table, and starts
  the first program: /SHELL.COM (or, on a disk without one, /BASIC.COM) --
  B_EXEC: read the 8-byte program header ("PX", load, entry, flags), load
  the body at the load address, jump to the entry. It STAYS RESIDENT, so
  the file calls (B_FOPEN_NAME, B_FGETC, B_FWRITE, B_FSEEK_NAME, ... -- see
  bios/defines.d) reach it while programs run; a program ends with B_EXIT,
  which closes its files and starts the shell again. The shell (shell/)
  starts BASIC.COM the same way when you type BASIC.
```

`tests/test_basic309_sdboot_golden.cpp` boots from the BIOS's real
`$FFFE` reset vector with no hand-wired PC hijack anywhere -- nothing in
the test tells the emulator where `SHELL.COM` or `BASIC.COM` is; the disk/DOS chain
finds them. `tools/mkdiskimg.cpp` builds `basic309/disk.img` (`dos/dos.bin`
+ `SHELL.COM` + `BASIC.COM`, the `$C000-$EFFF` image extracted from `exbasrom309.s19`
with a program header, the same bytes the no-disk `basic309_demo` path copies into RAM); `tools/basic309_sdboot_demo.cpp`
is the interactive equivalent of `basic309_demo` for this path
(`--com`/`--bios`/`--disk` flags).

The resident DOS (`dos/dos.asm`) is a small FAT16 file layer with a directory tree: eight
file slots each with a private 512-byte sector buffer, byte-level read/write/seek/size calls,
open modes read / write / append / update (in-place, with zero-filled gaps), cluster
allocation and chain extension (both FAT copies kept in sync), subdirectories (make, remove,
change, get the current directory; directories grow by a cluster when full), path parsing
(`/` separated, absolute or relative to one system-wide current directory, `.` and `..`),
directory scans, flush, delete and rename. The whole interface is documented in
`bios/defines.d` (function codes `$13`-`$28`) and is reached through ONE generic BIOS handler
(`BIOS_DOS` in `bios/sdcard.asm`) indexing the `JT_DOS` table that DOS fills in at boot --
SD_BOOT_TRY passes the table's address to DOS in Y, so no address is hand-copied between the
BIOS and DOS builds. Its tests are `test_dos_file_api.cpp` (one write/close/reopen/read round
trip through raw BIOS calls), `test_dos_stream_api.cpp` (multi-cluster files, interleaved
files, append at sector and cluster boundaries, update and stale-data safety, mode and error
rules, CR/LF line reads, 8 slots) and `test_dos_dirs.cpp` (directories, paths, growth,
rename, scan handles, FSTAT/STAT/seek/flush, FAT copies in sync), using
`tests/dos_session.hpp`, which boots the real chain and then makes BIOS calls itself, and
`tests/fat16_reader.hpp`, an independent FAT16 reader that checks what is really on the disk.

## Test suite

- `test_addressing.cpp` -- every indexed addressing sub-mode (5-bit,
  8/16-bit offset, accumulator offsets including the 6309 E/F/W
  additions, post-inc/pre-dec by 1/2, indirect forms, PC-relative,
  extended indirect, and the 6309-only `,W` family), cross-checked
  against `cycle.c`'s indexed-mode cycle table.
- `test_alu.cpp` -- 8/16-bit ALU flag computation (N Z V C H), the
  read-modify-write family, DAA, MUL, SEX, ABX.
- `test_stack_transfer.cpp` -- PSHS/PULS/PSHU/PULU (including the S/U
  postbyte-bit6 swap), TFR/EXG (including the 8-bit-register-padded-with-$FF
  quirk and the 6309 W/V registers), PSHSW/PULSW.
- `test_native6309.cpp` -- ADDR/CMPR-family register-to-register ALU,
  AIM/OIM/EIM/TIM, the BAND single-bit family, TFM, DIVD (incl.
  divide-by-zero trap), DIVQ, MULD, SEXW, LDQ/STQ, LDMD/BITMD.
- `test_branches_jumps.cpp` -- short/long branch condition logic,
  JMP/JSR/RTS/BSR.
- `test_interrupts.cpp` -- IRQ/FIRQ/NMI/SWI/SWI2/SWI3 vectoring, the
  emulation-mode (12-byte) vs native-mode (14-byte) full stack, FIRQ's
  normal 2-byte stack vs MD.1 native-FIRQ full stack, and CWAI's
  pre-stack-once-don't-double-push behavior.
- `test_asm_golden.cpp` -- assembles `tests/test_asm/*.asm` with the
  real `lwasm.exe` at test-run time, loads the resulting binary, runs
  it, and checks memory results. Skipped automatically (at CMake
  configure time) if `lwasm.exe` isn't found next to this checkout's
  `lwtools-4.20`.

`pugputer_tests` (the `SystemBus`/`UartR65C51` suite):
- `test_uart.cpp` -- register-level UART behavior direct against
  `IDevice`: TDRE/RDRF timing against the configured baud rate,
  overrun (a byte completing while RDRF is still set gets dropped),
  programmed reset's exact bit-clearing, the two IRQ-latching triggers
  (a new TDRE/RDRF transition while enabled; a Command write enabling an
  already-true condition -- the BIOS's documented idle-transmitter-kick
  behavior), DTR=0 disabling the receiver (letting an in-flight
  character finish first, per the datasheet), and the baud-rate decode
  table.
- `test_banking.cpp` -- the bank registers: reset mapping, remapping a bank,
  the page offset coming from CPU A13..A0, banks sharing a page, reaching all
  1MB, uninstalled pages floating high, ROM/IO unaffected, and the CPU running
  code and using a stack through remapped banks.
- `test_bios_banks.cpp` -- the BIOS bank service through real SWI2 calls: page info after boot,
  allocator order/exhaustion/double-free, bank get/set against the hardware registers and their
  refusals (bank 0, uninstalled pages, the stack's bank), RAM-size probing (4 to 256 pages),
  page copy (unaligned, whole page, callers' remapped banks, stack in any bank, interrupt mask
  kept, bad ranges rejected), and the BIOS/DOS memory layout check.
- `test_bios_audit.cpp` -- BIOS robustness (see `../bios/README.md`): SD retries, no card, a
  card stuck BUSY, block buffers reaching the ROM, UART error flags, the S-record loader fed
  malformed and dangerous records, corrupt boot sectors and a card dying mid-load, crashing
  programs recovering to the shell (illegal opcode, bad stack, divide by zero, SWI), and the
  stack the calls need. The SD device has fault-injection hooks for this
  (`set_card_present`, `set_stuck_busy`, `fail_next_reads/writes`, `fail_reads_after`).
- `test_shell.cpp` -- the program loader and the shell, with real keystrokes through the
  whole boot chain (each test on its own small disk image): the built-in commands (DIR, CD,
  MD, RD, DEL, REN, TYPE, COPY, VER, MEM, HELP) and their errors, line editing, running
  programs with a command tail (hand-assembled test programs), the loader's rejections (bad
  magic/flags/entry, would overwrite DOS or run into the ROM), B_EXIT closing and flushing
  files a program left open, and BASIC starting from the shell and `SYSTEM` returning to it.
- `test_dos_bigfiles.cpp` -- 32-bit sizes/positions and block numbers: a 100MB volume with two
  33MB files (read at offsets across block 65536 and 131072, so the SD device's high address word
  is used), new files placed beyond block 131072, files past 64KB appended/updated/gap-filled/
  truncated/deleted, and a full disk failing cleanly without leaks.
- `test_dos_model.cpp` -- a randomized model-based test: hundreds of random file and directory
  operations run through DOS and an in-memory model, compared at every step and against the disk
  (independent reader) for tree, contents, cluster ownership and leaks. Fixed seeds.
- `test_dos_crash.cpp` -- crash safety: the SD device logs every block write of a scripted run,
  and every prefix of the log (a power cut at each write) is checked for a consistent volume
  (no dangling or shared clusters, no garbage directories, completed work intact, no lost
  clusters between operations).
- `test_system_bus.cpp` -- RAM fallback outside any mapping, a mapped
  mock `IDevice` intercepting its address window, IRQ-line OR-ing and
  CPU-mask respecting, and devices receiving the exact cycle count
  `hd6309_step` returned via `tick()`.
- `test_uart_golden.cpp` -- assembles `tests/test_asm/uart_echo.asm`
  (mirroring the BIOS's real UART register sequence) with `lwasm.exe`,
  runs it on a real `SystemBus`, and drives it through
  `rx_enqueue`/`tx_dequeue` -- exercising the full path end to end (UART
  timing -> IRQ assertion -> CPU service -> ISR reading the real
  registers -> TX completion).
- `test_srec_loader.cpp` -- correct byte placement and address-range
  reporting from hand-built S-record fixtures, checksum-corruption
  detection, and out-of-bounds data records being rejected rather than
  silently truncated/wrapped.
- `test_rom_device.cpp` -- reads return loaded contents, writes are true
  no-ops, and (mapped on a real `SystemBus`) a RAM-size-probe-style
  write/read-back sequence correctly sees the write didn't stick.
- `test_sdcard_device.cpp` -- block read/write round-trips against a real
  backing file (verified by reopening it in a second `SdCardDevice`
  instance), distinct LBAs not colliding, and the `SD_DATA` cursor
  resetting after each command and not overrunning its buffer.
- `test_fat16_image.cpp` -- `build_fat16_image`'s boot signature/BPB
  fields, the DOS payload landing at LBA 1 with a correctly-sized
  reserved-sector-count, and files round-tripping through the root
  directory + FAT16 cluster chain via an independent minimal reader
  (deliberately not sharing code with `dos/dos.asm`'s own parser).
- `test_basic309_sdboot_golden.cpp` -- the real end-to-end integration
  test: boots `bios/pugbios.s19` from its actual `$FFFE` reset vector
  against `basic309/disk.img`, with no PC hijack anywhere -- `SD_BOOT_TRY`
  finds and loads `dos/dos.asm`, which starts `SHELL.COM`; the test types
  `BASIC` at the shell and confirms BASIC's actual startup banner and `OK`
  prompt come out the far end.
  Skipped automatically if `bios/pugbios.s19` and/or `basic309/disk.img`
  don't exist.
- `test_basic309_golden.cpp` -- BASIC's banner and `OK` prompt with the BIOS but
  no disk (BASIC copied into RAM, PC set to `$C000`).
- `test_basic309_interp_regression.cpp` -- about 55 exact-output interpreter cases
  (arithmetic, strings, control flow, `PRINT USING`, `INPUT`, ...): the baseline that
  keeps changes to the interpreter from silently altering old behaviour. Uses
  `tests/basic309_session.hpp`, which drives BASIC with paced UART keystrokes.
- `test_basic309_token_audit.cpp` -- cross-checks BASIC's keyword dictionaries, their
  counts, the dispatch tables and every `TOK_*` constant against the assembled image
  and symbol table, then types every keyword and verifies the token byte stored. Fails on
  an unaudited new `TOK_*` symbol. Needs `basic309/exbasrom309.lst` (`build_basic.bat`).
- `test_dos_file_api.cpp`, `test_dos_stream_api.cpp`, `test_dos_dirs.cpp` -- the resident DOS
  file layer and directory tree (above).
- `test_basic309_load_save_golden.cpp`, `test_basic309_files_kill_name.cpp` -- `SAVE` then
  `LOAD` round trip through real keystrokes and the whole disk chain; `FILES`, `KILL`, `NAME`.
- `test_basic309_seqfiles.cpp`, `test_basic309_randomfiles.cpp` -- BASIC file I/O: the
  GW-BASIC guide's sequential Examples 1-3 and random-access Examples 4-6, `OPEN` in both
  syntaxes, `PRINT#`/`WRITE#`/`INPUT#`/`LINE INPUT#`, `FIELD`/`LSET`/`RSET`/`GET`/`PUT`,
  `MKI$`/`MKS$`/`CVI`/`CVS`, `EOF`/`LOF`/`LOC`, when files are closed, and every error.
  Shared helpers: `tests/basic309_file_helpers.hpp`.
- `test_basic309_dirs.cpp` -- `MKDIR`/`CHDIR`/`RMDIR`, paths in `LOAD`/`SAVE`/`KILL`/`NAME`/`OPEN`/
  `FILES`, the directory errors, and the directory statements inside a running program. These share `disk.img`, so each test
  deletes its own files before and after.

`pugputer_tests` takes optional name fragments (`pugputer_tests dos_stream seqfiles`) and
then runs only the tests whose names contain one of them.

Run everything with `ctest --test-dir build --output-on-failure`, or run
`hd6309_tests`/`pugputer_tests` directly for per-check output.
