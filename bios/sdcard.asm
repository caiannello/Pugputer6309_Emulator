;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 BIOS
;    FILE: sdcard.asm
;  AUTHOR: CRAIG IANNELLO, PUGBUTT.COM
;
; SD/block storage driver, plus the disk-boot sequence (SD_BOOT_TRY, called
; from V_RESET). The register interface (see SD_LBA/SD_DATA/SD_CMDSTA in
; defines.d) is an idealized, transport-agnostic block device -- closer to
; ATA PIO mode than real SPI/SD card protocol -- since the real SD/SPI
; transport hardware isn't chosen yet (VIA-bit-banged vs. MCU-offloaded).
; Whichever one is chosen later, only this file's SD_READ_BLOCK/
; SD_WRITE_BLOCK need to change -- everything above them (BIOS_BLK_READ/
; WRITE, SD_BOOT_TRY, and every future caller) stays the same.
;
; SD_BOOT_TRY reads block 0 (the FAT16 boot sector) into free RAM (whatever
; USER_RAM currently points at -- nothing else needs that RAM yet, this
; early in V_RESET) as scratch. If it doesn't look like a valid FAT16
; volume, it just returns and V_RESET falls through to the existing
; S-record loader prompt exactly as before -- this is also what happens
; today when no SD device is mapped at all, since an unmapped read reads
; back as zero, which never matches the boot signature. If valid, it loads
; the volume's reserved sectors (which hold dos/dos.asm -- see that file's
; header for the FAT16 root-directory/cluster-chain walk) to that same
; scratch address, overwriting the now-unneeded boot sector bytes, and
; jumps there. Never returns on success.
;------------------------------------------------------------------------------
    INCLUDE defines.d
;------------------------------------------------------------------------------
SD_READ_BLOCK   EXPORT
SD_WRITE_BLOCK  EXPORT
BIOS_BLK_READ   EXPORT
BIOS_BLK_WRITE  EXPORT
BIOS_BLK_READ32  EXPORT
BIOS_BLK_WRITE32 EXPORT
BIOS_DOS        EXPORT
SD_BOOT_TRY     EXPORT
;------------------------------------------------------------------------------
BC_OK       EXTERN          ; main.asm
BC_ERR      EXTERN
USER_RAM    EXTERN
JT_DOS         EXTERN     ; main.asm -- DOS call vectors, patched by dos/dos.asm at boot
DOSMASK        EXTERN     ; (defaulting to DOS_NOTPRESENT if no disk-resident DOS ever ran)
;------------------------------------------------------------------------------
    SECT bss
;------------------------------------------------------------------------------
SDBOOT_CNT  RMB  2          ; SD_BOOT_TRY's remaining-sectors-to-load counter
    ENDSECT
;------------------------------------------------------------------------------
    SECT code
;------------------------------------------------------------------------------
FAT16_SIG   FCC  "FAT16   "     ; BPB FS-type string, offset $36 -- no
                                 ; trailing zero, matched byte-for-byte below
;------------------------------------------------------------------------------
; X=16-bit LBA, Y=destination RAM address. Reads 512 bytes into [Y..Y+511].
; Carry set on failure (no card present) -- [Y..Y+511] is then undefined.
; Trashes A, B, X, W. SD_READ_BLOCK32 is the same with the LBA's high word in W
; (SD_READ_BLOCK is high word 0).
;------------------------------------------------------------------------------
SD_READ_BLOCK
            LDW  #0
SD_READ_BLOCK32
            PSHS Y
            STW  SD_LBA           ; the high word, latched by SETHI ...
            LDA  #SD_CMD_SETHI
            STA  SD_CMDSTA
            STX  SD_LBA           ; ... then the low word
            LDA  #SD_CMD_READ
            STA  SD_CMDSTA
SDRD_WAIT   LDA  SD_CMDSTA
            BITA #SD_STA_BUSY
            BNE  SDRD_WAIT
            BITA #SD_STA_CARD
            BEQ  SDRD_FAIL
            BITA #SD_STA_ERROR   ; the underlying file read actually
            BNE  SDRD_FAIL       ; failed (not just "no card")
            LDX  #512
SDRD_LOOP   LDA  SD_DATA
            STA  ,Y+
            LEAX -1,X
            BNE  SDRD_LOOP
            ANDCC #$FE
            PULS Y,PC
SDRD_FAIL   ORCC #$01
            PULS Y,PC
;------------------------------------------------------------------------------
; X=16-bit LBA, Y=source RAM address. Writes [Y..Y+511] to the block. Carry
; set on failure (no card present). Trashes A, B, X, W. SD_WRITE_BLOCK32: the
; LBA's high word in W.
;------------------------------------------------------------------------------
SD_WRITE_BLOCK
            LDW  #0
SD_WRITE_BLOCK32
            PSHS Y
            LDA  SD_CMDSTA
            BITA #SD_STA_CARD
            BEQ  SDWR_FAIL
            STW  SD_LBA
            LDA  #SD_CMD_SETHI
            STA  SD_CMDSTA
            STX  SD_LBA
            LDX  #512
SDWR_LOOP   LDA  ,Y+
            STA  SD_DATA
            LEAX -1,X
            BNE  SDWR_LOOP
            LDA  #SD_CMD_WRITE
            STA  SD_CMDSTA
SDWR_WAIT   LDA  SD_CMDSTA
            BITA #SD_STA_BUSY
            BNE  SDWR_WAIT
            BITA #SD_STA_ERROR   ; the underlying file write actually
            BNE  SDWR_FAIL       ; failed (permissions, disk full, etc.)
            ANDCC #$FE
            PULS Y,PC
SDWR_FAIL   ORCC #$01
            PULS Y,PC
;------------------------------------------------------------------------------
; SWI2 handlers. X=16-bit LBA, Y=RAM buffer adrs, from SWI2_X,S/SWI2_Y,S --
; same convention as every other BIOS_* handler (see defines.d).
;------------------------------------------------------------------------------
BIOS_BLK_READ
            LDX  SWI2_X,S
            LDY  SWI2_Y,S
            JSR  SD_READ_BLOCK
            BCS  SDBLK_RDERR
            JMP  BC_OK
SDBLK_RDERR LDA  #ERR_IOERR
            JMP  BC_ERR
;------------------------------------------------------------------------------
BIOS_BLK_WRITE
            LDX  SWI2_X,S
            LDY  SWI2_Y,S
            JSR  SD_WRITE_BLOCK
            BCS  SDBLK_WRERR
            JMP  BC_OK
SDBLK_WRERR LDA  #ERR_IOERR
            JMP  BC_ERR
;------------------------------------------------------------------------------
; The 32-bit variants: the LBA's high word is the caller's W (E:F in the frame).
;------------------------------------------------------------------------------
BIOS_BLK_READ32
            LDX  SWI2_X,S
            LDY  SWI2_Y,S
            LDW  SWI2_E,S
            JSR  SD_READ_BLOCK32
            BCS  SDBLK_RDERR
            JMP  BC_OK
;------------------------------------------------------------------------------
BIOS_BLK_WRITE32
            LDX  SWI2_X,S
            LDY  SWI2_Y,S
            LDW  SWI2_E,S
            JSR  SD_WRITE_BLOCK32
            BCS  SDBLK_WRERR
            JMP  BC_OK
;------------------------------------------------------------------------------
; Resident DOS calls (function codes B_FOPEN_NAME and up), ALL through this one
; handler. It loads the registers the DOS routine expects from the caller's SWI2
; frame -- A = the caller's E, B, X, Y (so a "mode", byte or whence goes in E)
; -- and JSRs the routine's entry in the JT_DOS table (whatever dos/dos.asm
; patched in at boot, or DOS_NOTPRESENT's clean-error stub if no disk-resident
; DOS ever ran). The routine is a plain subroutine: carry clear = success, else
; carry set and A = an ERR_* code. This file (never the callee) finishes the
; SWI2 frame -- the callee must never RTI, since only the handler holding the
; original SWI2 context may -- and DOS_OUTMASK below says which results the call
; returns to the caller: bit 0 = A (a value, e.g. a handle or byte; otherwise A
; comes back as ERR_OK), bit 1 = X, bit 2 = Y. Registers a call doesn't return
; are left exactly as the caller had them.
;
; Adding a DOS call: give it the next function code in defines.d, one FDB in
; dos.asm's DOS_ENTRIES, and one byte here -- nothing else changes.
;------------------------------------------------------------------------------
BIOS_DOS    LDB  SWI2_A,S       ; the function code ...
            SUBB #B_FOPEN_NAME  ; ... as an index (0..NUM_DOS_JT-1)
            LDX  #DOS_OUTMASK
            LDA  B,X
            STA  >DOSMASK       ; extended: the caller's DP is not ours
            ASLB
            LDU  #JT_DOS
            LEAU B,U            ; U -> this call's slot
            LDA  SWI2_E,S
            LDB  SWI2_B,S
            LDX  SWI2_X,S
            LDY  SWI2_Y,S
            JSR  [,U]
            BCS  BDOS_ERR
            LDB  >DOSMASK
            BITB #1
            BNE  BDOS_A
            CLRA                ; no value: A = ERR_OK
BDOS_A      STA  SWI2_A,S
            BITB #2
            BEQ  BDOS_NOX
            STX  SWI2_X,S
BDOS_NOX    BITB #4
            BEQ  BDOS_NOY
            STY  SWI2_Y,S
BDOS_NOY    AIM  #$FE,SWI2_CC,S
            RTI
BDOS_ERR    STA  SWI2_A,S
            OIM  #$01,SWI2_CC,S
            RTI
; Results each DOS call returns, in function-code order (see the byte above).
DOS_OUTMASK FCB  1              ; $13 B_FOPEN_NAME   A = handle
            FCB  2              ; $14 B_READLINE     X = length
            FCB  0              ; $15 B_WRITELINE
            FCB  0              ; $16 B_FCLOSE_NAME
            FCB  1              ; $17 B_OPENDIR      A = scan handle
            FCB  0              ; $18 B_READDIR      (the entry is in the buffer)
            FCB  0              ; $19 B_KILL_NAME
            FCB  0              ; $1A B_RENAME_NAME
            FCB  1              ; $1B B_FGETC        A = byte
            FCB  0              ; $1C B_FPUTC
            FCB  2              ; $1D B_FREAD        X = bytes read
            FCB  0              ; $1E B_FWRITE
            FCB  6              ; $1F B_FSEEK_NAME   X:Y = new position
            FCB  0              ; $20 B_FSTAT_NAME   (in the buffer)
            FCB  0              ; $21 B_FFLUSH
            FCB  0              ; $22 B_MKDIR
            FCB  0              ; $23 B_RMDIR
            FCB  0              ; $24 B_CHDIR
            FCB  0              ; $25 B_GETCWD       (in the buffer)
            FCB  0              ; $26 B_CLOSEDIR
            FCB  0              ; $27 B_STAT         (in the buffer)
            FCB  1              ; $28 B_DOS_VERSION  A = version
DOS_OUTMASK_END
    IFNE (DOS_OUTMASK_END-DOS_OUTMASK)-NUM_DOS_JT
    ERROR "DOS_OUTMASK must have one byte per DOS call (see defines.d)"
    ENDC
;------------------------------------------------------------------------------
; See file header. Called from V_RESET, right before its existing
; JMP LOADER_START.
;------------------------------------------------------------------------------
SD_BOOT_TRY LDX  #0             ; LBA 0: the boot sector
            LDY  <USER_RAM
            JSR  SD_READ_BLOCK
            BCS  SDBOOT_NONE    ; no card present -- bail out
            LDX  <USER_RAM
            LDD  510,X          ; boot signature, offset $1FE
            CMPD #$55AA
            BNE  SDBOOT_NONE
            LEAX 54,X           ; offset $36: the 8-byte FS type string
            LDY  #FAT16_SIG
            LDB  #8
SDBOOT_CHK  LDA  ,X+
            CMPA ,Y+
            BNE  SDBOOT_NONE
            DECB
            BNE  SDBOOT_CHK
            ; Reserved sector count, offset $0E, stored little-endian --
            ; read the high/low bytes individually (in the opposite order
            ; LDD would) rather than via a single misordered 16-bit load.
            LDX  <USER_RAM
            LDA  15,X           ; high byte, offset $0F
            LDB  14,X           ; low byte, offset $0E
            SUBD #1             ; minus the boot sector itself (already read)
            STD  SDBOOT_CNT
            ; Load the reserved sectors (dos/dos.asm) starting at LBA 1 to
            ; DOS_LOAD (which may overlap the boot-sector scratch: the fields
            ; needed from it have been extracted by now).
            LDX  #1
            LDY  #DOS_LOAD
SDBOOT_LOAD LDD  SDBOOT_CNT
            BEQ  SDBOOT_GO
            PSHS X,Y,D
            JSR  SD_READ_BLOCK
            PULS D,Y,X
            SUBD #1
            STD  SDBOOT_CNT
            LEAX 1,X
            LEAY 512,Y
            BRA  SDBOOT_LOAD
SDBOOT_GO   LDX  #DOS_LOAD
            LDY  #JT_DOS        ; DOS gets its call table's address in Y (no hand-synced constant)
            JMP  ,X             ; hand off to DOS -- never returns
SDBOOT_NONE RTS                 ; caller falls through to LOADER_START
;------------------------------------------------------------------------------
    ENDSECT
;------------------------------------------------------------------------------
; End of sdcard.asm
;------------------------------------------------------------------------------
