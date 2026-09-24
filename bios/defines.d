; -----------------------------------------------------------------------------
; PROJECT: Pugputer 6309 BIOS
;    FILE: defines.d
;  AUTHOR: CRAIG IANNELLO, PUGBUTT.COM
;
; Global hardware equates, BIOS call codes, and shared data structures.
; -----------------------------------------------------------------------------

; -----------------------------------------------------------------------------
; IO DEVICE BASE ADDRESSES (full memory map, even where a driver isn't built
; yet -- these mirror the fixed hardware address decode, not code)
; -----------------------------------------------------------------------------

BANK_BASE   equ  $FFEC      ; ffec - ffef: Memory Bank Regs 0...3 (Built-in)
ACIA_BASE   equ  $FFE8      ; ffe8 - ffeb: Serial UART R65C51P2 (Built-in)
VDP_BASE    equ  $FFE4      ; ffe4 - ffe7: Video Chip V9958 (optional card)
OPL3_BASE   equ  $FFE0      ; ffe0 - ffe3: Music Chip YMF262 (optional card)
SD_BASE     equ  $FFD8      ; ffd8 - ffdb: SD/block storage (Built-in; see
                             ;              sdcard.asm -- an idealized block
                             ;              register interface, not real SPI/
                             ;              SD protocol, since the real
                             ;              transport hardware isn't decided)
VIA_BASE    equ  $FFB0      ; ffb0 - ffbf: W65C22 VIA (optional card)

; Memory bank registers 0..3 (write-only; readable copies kept in
; SBANK_1...SBANK_3 -- see main.asm)

MBANK_0     equ  BANK_BASE+0
MBANK_1     equ  BANK_BASE+1
MBANK_2     equ  BANK_BASE+2
MBANK_3     equ  BANK_BASE+3

; UART registers

UT_DAT      equ  ACIA_BASE+0  ; R65C51P2 UART DATA REGISTER (RD: RX, WR: TX)
UT_STA      equ  ACIA_BASE+1  ; READ: UART STATUS REG, WRITE: PROGRAM RESET
UT_CMD      equ  ACIA_BASE+2  ; COMMAND REG (parity, echo, IRQ enables, DTR)
UT_CTL      equ  ACIA_BASE+3  ; CONTROL REG (baud rate, word length, stop bits)

; UART constants

SBUFSZ      equ  $7E        ; SIZE OF THE SERIAL INPUT / OUTPUT RING BUFFERS
SUARTCTL    equ  $1F        ; %0001 1111 = 19200 BAUD,
                             ;              EXTERNAL RECEIVER CLOCK,
                             ;              8 DATA BITS,
                             ;              1 STOP BIT.
SUARTCMD    equ  $09        ; %0000 1001 = ODD PARITY CHECK, BUT
                             ;              PARITY CHECK DISABLED.
                             ;              NORMAL RECEIVER MODE, NO ECHO.
                             ;              RTSB LOW, TX INTERRUPT DISABLED.
                             ;              IRQB RX INTERRUPT ENABLED.
                             ;              DATA TERMINAL READY, DTRB LOW.

; SD/block storage registers (see sdcard.asm). SD_LBA is a single 16-bit
; register (STX/LDX-friendly: high byte at +0, low byte at +1, matching the
; 6309's natural big-endian STX order) rather than two separately-named
; byte registers.

SD_LBA      equ  SD_BASE+0  ; 16-bit block number (r/w) -- 64K blocks *
                             ; 512B = 32MB max
SD_DATA     equ  SD_BASE+2  ; stream port into/out of the active 512-byte
                             ; sector buffer; cursor auto-increments and
                             ; resets to 0 after each READ/WRITE command
SD_CMDSTA   equ  SD_BASE+3  ; WRITE: command (1=READ block at LBA into
                             ; buffer, 2=WRITE buffer to block at LBA).
                             ; READ: status (bit0 BUSY, bit1 CARD_PRESENT)

SD_CMD_READ  equ  1
SD_CMD_WRITE equ  2
SD_STA_BUSY  equ  %00000001
SD_STA_CARD  equ  %00000010
SD_STA_ERROR equ  %00000100  ; the last READ/WRITE command's underlying
                             ; file I/O actually failed (permissions,
                             ; disk full, etc.); cleared by the next cmd
; -----------------------------------------------------------------------------
; Device ref / fileref numbers
;
; A "device ref" and a "fileref" are the same number space. Built-in devices
; are usable directly as filerefs (no open needed -- they have no per-open
; state). B_FOPEN exists for forward compatibility with future file-backed
; devices (e.g. SD card files) that DO need per-open state; for a plain
; device it just validates the ref and hands it back.
; -----------------------------------------------------------------------------
F_NULL      equ  $00        ; Discards writes, reads return nothing
F_STDOUT    equ  $01        ; Aliased to the console device at BIOS init
F_STDIN     equ  $02
F_STDERR    equ  $03        ; (reserved numbering: 4-7 unused for now)
F_UART      equ  $08        ; Direct access to the UART, bypassing stdio
F_VDP       equ  $09        ; reserved for a future video card driver
F_VIA_KB    equ  $0A        ; reserved for a future VIA/keyboard driver
NUM_DEVICES equ  $0C        ; size of the device driver table (0..$0B)

; -----------------------------------------------------------------------------
; BIOS Functions - function type codes passed in reg A when doing a BIOS
; call (SWI2). Common arg: B = device ref / fileref, where applicable.
; -----------------------------------------------------------------------------
B_DQUERY    equ  $00        ; Returns bitmap of present devices in D
B_REG_DEV   equ  $01        ; B: devref, X: read fn, Y: write fn, U: ioctl fn
B_DEREG_DEV equ  $02        ; B: devref
B_FSTAT     equ  $03        ; (reserved; not implemented until SD exists)
B_FDIR      equ  $04        ; (reserved; not implemented until SD exists)
B_FOPEN     equ  $05        ; B: devref, E: flags -> A: fileref (== devref)
B_FCLOSE    equ  $06        ; B: fileref
B_FDELETE   equ  $07        ; (reserved; not implemented until SD exists)
B_FMOVE     equ  $08        ; (reserved; not implemented until SD exists)
B_PUTC      equ  $09        ; B: fileref, E: the char (blocks if buf full)
B_PUTS      equ  $0A        ; B: fileref, X: adrs of null-terminated string
B_PUT       equ  $0B        ; B: fileref, X: adrs of bytes, Y: len
B_GETC      equ  $0C        ; B: fileref -> A: char, or carry set if none
B_GETS      equ  $0D        ; B: fileref, X: buf adrs, Y: buf len (raw, no
                             ; echo, stops at CR or full) -> X: strlen
B_GET       equ  $0E        ; B: fileref, X: buf adrs, Y: max len (non-
                             ; blocking) -> X: actual len read
B_IOCTL     equ  $0F        ; B: fileref, E: func code, F: param byte
B_FSEEK     equ  $10        ; (reserved; not implemented until SD exists)
B_BLK_READ  equ  $11        ; X: 16-bit LBA, Y: RAM buffer adrs -> reads
                             ; 512 bytes from the SD device into [Y..Y+511]
B_BLK_WRITE equ  $12        ; X: 16-bit LBA, Y: RAM buffer adrs -> writes
                             ; [Y..Y+511] to the SD device
; Resident DOS file calls (dos/dos.asm) -- these indirect through DOS_JTAB
; (see main.asm), so they fail cleanly with ERR_NOTSUP if no disk-resident
; DOS ever patched it (e.g. a boot path with no SD card).
B_FOPEN_NAME  equ $13        ; X: 8.3 filename, 11 bytes fixed, space-padded,
                             ; no dot (e.g. "BASIC   COM" -- matches a raw
                             ; FAT16 directory entry name field exactly),
                             ; E: mode (0=read, 1=write) -> A: fileref
B_READLINE    equ $14        ; B: fileref, X: dest buf, Y: max len ->
                             ; X: actual length read (0 = EOF) -- matches
                             ; B_GET/B_GETS's existing X-for-actual-length
                             ; convention
B_WRITELINE   equ $15        ; B: fileref, X: src buf, Y: len -> writes
                             ; the line plus a trailing CR
B_FCLOSE_NAME equ $16        ; B: fileref -> finalizes the file
B_DIR_FIRST   equ $17        ; X: dest buf (16 bytes: 11 name + 1 attr + 4
                             ; size) -> fills buf with the first live
                             ; (non-deleted, non-empty-slot) directory
                             ; entry; carry set = directory has no entries
B_DIR_NEXT    equ $18        ; same signature/buffer, continues the scan
                             ; started by B_DIR_FIRST; carry set = no more
B_KILL_NAME   equ $19        ; X: 8.3 filename -> deletes it
B_RENAME_NAME equ $1A        ; X: old 8.3 filename, Y: new 8.3 filename ->
                             ; renames; fails if old is missing or new
                             ; already exists
; Byte-level access to open DOS files (mode-dependent; see FOPEN_* below).
; Each open file has its own sector buffer, so several can be open and
; interleaved freely.
B_FGETC     equ  $1B         ; B: fileref -> A: next byte, or carry set +
                             ; A=ERR_EOF at end of file
B_FPUTC     equ  $1C         ; B: fileref, E: the byte (write/append/update)
B_FREAD     equ  $1D         ; B: fileref, X: buf, Y: len -> X: bytes actually
                             ; read (short only at end of file)
B_FWRITE    equ  $1E         ; B: fileref, X: buf, Y: len
B_FSEEK_NAME equ $1F         ; B: fileref, X: new byte position (read or
                             ; update mode). Positions past the end read as
                             ; end-of-file; an update-mode write there
                             ; zero-fills the gap.
B_FSTAT_NAME equ $20         ; B: fileref -> X: file size in bytes, Y: current
                             ; byte position
NUM_BCALLS  equ  $21
NUM_DOS_JT  equ  B_FSTAT_NAME-B_FOPEN_NAME+1 ; DOS-resident calls (B_FOPEN_NAME
                             ; through B_FSTAT_NAME): one JT_DOS_* slot each,
                             ; in main.asm, in call-code order

; BIOS call status codes (returned in A; carry set on any non-OK status)

ERR_OK      equ  $00
ERR_BADFN   equ  $01        ; unknown BIOS function code
ERR_BADDEV  equ  $02        ; devref/fileref out of range or not registered
ERR_NOTSUP  equ  $03        ; operation not supported by this device
ERR_IOERR   equ  $04        ; block IO failed (no card / bad block, etc.)
ERR_NOTFOUND equ $05        ; B_FOPEN_NAME: file not found (read mode)
ERR_NOSPACE equ  $06        ; B_WRITELINE: disk full (no free clusters)
ERR_NOSLOT  equ  $07        ; B_FOPEN_NAME: no free open-file slot
ERR_EXISTS  equ  $08        ; B_RENAME_NAME: target name already exists
ERR_EOF     equ  $09        ; B_FGETC: no more data in the file
ERR_ISOPEN  equ  $0A        ; file is already open (open/kill/rename)
ERR_BADMODE equ  $0B        ; operation not allowed in the file's open mode

; B_FOPEN_NAME mode values
FOPEN_READ   equ $00        ; must exist; read (and seek) only
FOPEN_WRITE  equ $01        ; create, or truncate an existing file; write only
FOPEN_APPEND equ $02        ; create if missing; writes go at the end
FOPEN_UPDATE equ $03        ; create if missing; read/write/seek in place,
                            ; existing contents kept

; UART ioctl function codes (used with B_IOCTL on F_UART or aliases)

UT_IOC_SETCTL equ $00       ; F: new UART Control Register value (raw HW
                             ; encoding -- baud rate / word length / stop
                             ; bits, see R65C51 datasheet Control Register).
                             ; Waits for TX idle before applying.

; -----------------------------------------------------------------------------
; Native-mode interrupt/SWI stack frame offsets, relative to S immediately
; after entry (i.e. S points at the stacked CC). Confirmed against the 6309
; native-mode register stacking order: PC,U,Y,X,DP,F,E,B,A,CC pushed in that
; order, so CC ends up nearest the post-entry S. A BIOS call handler (see
; devio.asm) reads its arguments from these offsets and, since RTI restores
; registers FROM this frame rather than from whatever's live in the CPU at
; the time, must write any return values back to these same offsets before
; returning -- leaving a result only in a live register is silently lost.
; -----------------------------------------------------------------------------
SWI2_CC     equ  0
SWI2_A      equ  1
SWI2_B      equ  2
SWI2_E      equ  3
SWI2_F      equ  4
SWI2_DP     equ  5
SWI2_X      equ  6
SWI2_Y      equ  8
SWI2_U      equ  10
SWI2_PC     equ  12

; -----------------------------------------------------------------------------
; MISC CONSTANTS
; -----------------------------------------------------------------------------
ESCAPE      equ  $1B        ; ASCII CODE FOR ESCAPE
LF          equ  $0A        ; LINE FEED
CR          equ  $0D        ; CARRIAGE RETURN
SPACE       equ  $20
TILDE       equ  $7E

; -----------------------------------------------------------------------------
; Generic circular byte buffer (methods in helpers.asm). Used for the UART's
; RX and TX buffers, sized identically via SBUFSZ so both instances share one
; implementation of the push/pop logic.
; -----------------------------------------------------------------------------
circbuf     STRUCT
head        rmb  1          ; write index into buf (0..SBUFSZ-1)
tail        rmb  1          ; read index into buf
count       rmb  1          ; number of bytes currently buffered
buf         rmb  SBUFSZ     ; storage
            ENDS

; -----------------------------------------------------------------------------
; Device driver descriptor - one per registered device (see devio.asm).
; A device with no per-byte concept of "read" (i.e. write-only) or no ioctl
; support simply registers a null (0) pointer for that entry.
; -----------------------------------------------------------------------------
devdrv      STRUCT
flags       rmb  1          ; bit 0: slot in use
read        rmw  1          ; (X=buf,Y=maxlen) -> Y=actual len, non-blocking
write       rmw  1          ; (X=buf,Y=len) -> blocks until all len sent
ioctl       rmw  1          ; (A=func,B=param) -> A=status, carry=error
            ENDS
; -----------------------------------------------------------------------------
; END OF DEFINES.D
; -----------------------------------------------------------------------------
