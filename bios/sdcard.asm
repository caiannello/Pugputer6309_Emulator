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
BIOS_FOPEN_NAME  EXPORT
BIOS_READLINE    EXPORT
BIOS_WRITELINE   EXPORT
BIOS_FCLOSE_NAME EXPORT
BIOS_DIR_FIRST   EXPORT
BIOS_DIR_NEXT    EXPORT
BIOS_KILL_NAME   EXPORT
BIOS_RENAME_NAME EXPORT
BIOS_FGETC       EXPORT
BIOS_FPUTC       EXPORT
BIOS_FREAD       EXPORT
BIOS_FWRITE      EXPORT
BIOS_FSEEK_NAME  EXPORT
BIOS_FSTAT_NAME  EXPORT
SD_BOOT_TRY     EXPORT
;------------------------------------------------------------------------------
BC_OK       EXTERN          ; main.asm
BC_ERR      EXTERN
USER_RAM    EXTERN
JT_DOS_OPEN      EXTERN     ; main.asm -- DOS file-API table, patched by
JT_DOS_READLINE  EXTERN     ; dos/dos.asm at boot (defaults to
JT_DOS_WRITELINE EXTERN     ; DOS_NOTPRESENT if no disk-resident DOS ever
JT_DOS_CLOSE     EXTERN     ; ran -- see main.asm)
JT_DOS_DIRFIRST  EXTERN
JT_DOS_DIRNEXT   EXTERN
JT_DOS_KILL      EXTERN
JT_DOS_RENAME    EXTERN
JT_DOS_FGETC     EXTERN
JT_DOS_FPUTC     EXTERN
JT_DOS_FREAD     EXTERN
JT_DOS_FWRITE    EXTERN
JT_DOS_FSEEK     EXTERN
JT_DOS_FSTAT     EXTERN
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
; Trashes A, B, X.
;------------------------------------------------------------------------------
SD_READ_BLOCK
            PSHS Y
            STX  SD_LBA
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
; set on failure (no card present). Trashes A, B, X.
;------------------------------------------------------------------------------
SD_WRITE_BLOCK
            PSHS Y
            LDA  SD_CMDSTA
            BITA #SD_STA_CARD
            BEQ  SDWR_FAIL
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
; Resident DOS file-API handlers. Each JSRs indirect through its JT_DOS_*
; table slot (main.asm) to whatever dos/dos.asm patched in at boot (or
; DOS_NOTPRESENT's clean-error stub if no disk-resident DOS ever ran) and
; expects a plain RTS back -- carry set + A=error code on failure. This
; file (not the callee) owns finishing the SWI2 frame, same reasoning as
; BIOS_BLK_READ/WRITE above and every other BIOS_* handler: NEVER let the
; callee itself RTI, since it has no way to know whether it's reached via
; a bare JSR (no extra stack frame) or something else -- only the handler
; that's holding the original SWI2 context is allowed to finish it.
;------------------------------------------------------------------------------
; X=filename (null-terminated 8.3), E=mode (FOPEN_READ/FOPEN_WRITE), from
; SWI2_X,S/SWI2_E,S. Success: A=fileref (not a status code -- matches
; BIOS_GETC's existing precedent for a handler whose success value isn't
; ERR_OK, so this can't tail-call the generic BC_OK).
;------------------------------------------------------------------------------
BIOS_FOPEN_NAME
            LDX  SWI2_X,S
            LDA  SWI2_E,S
            JSR  [JT_DOS_OPEN]
            BCS  DOSOPEN_ERR
            STA  SWI2_A,S
            AIM  #$FE,SWI2_CC,S
            RTI
DOSOPEN_ERR STA  SWI2_A,S
            OIM  #$01,SWI2_CC,S
            RTI
;------------------------------------------------------------------------------
; B=fileref, X=dest buf, Y=max len, from SWI2_B,S/SWI2_X,S/SWI2_Y,S.
; Success: X=actual length read (0=EOF) -- matches B_GET/B_GETS's existing
; X-for-actual-length convention, so this can't tail-call BC_OK either.
;------------------------------------------------------------------------------
BIOS_READLINE
            LDB  SWI2_B,S
            LDX  SWI2_X,S
            LDY  SWI2_Y,S
            JSR  [JT_DOS_READLINE]
            BCS  DOSRD_ERR
            STX  SWI2_X,S
            AIM  #$FE,SWI2_CC,S
            RTI
DOSRD_ERR   STA  SWI2_A,S
            OIM  #$01,SWI2_CC,S
            RTI
;------------------------------------------------------------------------------
; B=fileref, X=src buf, Y=len, from SWI2_B,S/SWI2_X,S/SWI2_Y,S. Writes the
; line plus a trailing CR. Plain status result -- BC_OK/BC_ERR both fit.
;------------------------------------------------------------------------------
BIOS_WRITELINE
            LDB  SWI2_B,S
            LDX  SWI2_X,S
            LDY  SWI2_Y,S
            JSR  [JT_DOS_WRITELINE]
            BCS  DOSWR_ERR
            JMP  BC_OK
DOSWR_ERR   JMP  BC_ERR
;------------------------------------------------------------------------------
; B=fileref, from SWI2_B,S. Finalizes the file. Plain status result.
;------------------------------------------------------------------------------
BIOS_FCLOSE_NAME
            LDB  SWI2_B,S
            JSR  [JT_DOS_CLOSE]
            BCS  DOSCL_ERR
            JMP  BC_OK
DOSCL_ERR   JMP  BC_ERR
;------------------------------------------------------------------------------
; X=dest buf (16 bytes), from SWI2_X,S. Fills buf with the first live
; directory entry, or carry set if the directory is empty. Plain status
; result (the buffer itself is the "return value") -- BC_OK/BC_ERR fit.
;------------------------------------------------------------------------------
BIOS_DIR_FIRST
            LDX  SWI2_X,S
            JSR  [JT_DOS_DIRFIRST]
            BCS  DIRFIRST_ERR
            JMP  BC_OK
DIRFIRST_ERR JMP  BC_ERR
;------------------------------------------------------------------------------
; Same signature as BIOS_DIR_FIRST; continues the scan it started.
;------------------------------------------------------------------------------
BIOS_DIR_NEXT
            LDX  SWI2_X,S
            JSR  [JT_DOS_DIRNEXT]
            BCS  DIRNEXT_ERR
            JMP  BC_OK
DIRNEXT_ERR JMP  BC_ERR
;------------------------------------------------------------------------------
; X=8.3 filename, from SWI2_X,S. Deletes it. Plain status result.
;------------------------------------------------------------------------------
BIOS_KILL_NAME
            LDX  SWI2_X,S
            JSR  [JT_DOS_KILL]
            BCS  DOSKILL_ERR
            JMP  BC_OK
DOSKILL_ERR JMP  BC_ERR
;------------------------------------------------------------------------------
; X=old 8.3 filename, Y=new 8.3 filename, from SWI2_X,S/SWI2_Y,S. Renames.
; Plain status result.
;------------------------------------------------------------------------------
BIOS_RENAME_NAME
            LDX  SWI2_X,S
            LDY  SWI2_Y,S
            JSR  [JT_DOS_RENAME]
            BCS  DOSREN_ERR
            JMP  BC_OK
DOSREN_ERR  JMP  BC_ERR
;------------------------------------------------------------------------------
; B=fileref, from SWI2_B,S. Success: A=the byte read (not a status code --
; same precedent as BIOS_FOPEN_NAME's fileref); at end of file, or on any
; error: carry set and A=status (ERR_EOF at end of file).
;------------------------------------------------------------------------------
BIOS_FGETC
            LDB  SWI2_B,S
            JSR  [JT_DOS_FGETC]
            BCS  DOSGC_ERR
            STA  SWI2_A,S
            AIM  #$FE,SWI2_CC,S
            RTI
DOSGC_ERR   STA  SWI2_A,S
            OIM  #$01,SWI2_CC,S
            RTI
;------------------------------------------------------------------------------
; B=fileref, E=the byte, from SWI2_B,S/SWI2_E,S. Plain status result.
;------------------------------------------------------------------------------
BIOS_FPUTC
            LDB  SWI2_B,S
            LDA  SWI2_E,S
            JSR  [JT_DOS_FPUTC]
            BCS  DOSPC_ERR
            JMP  BC_OK
DOSPC_ERR   JMP  BC_ERR
;------------------------------------------------------------------------------
; B=fileref, X=dest buf, Y=len. Success: X=bytes actually read (fewer than Y
; only at end of file) -- same X-for-actual-length convention as BIOS_READLINE.
;------------------------------------------------------------------------------
BIOS_FREAD
            LDB  SWI2_B,S
            LDX  SWI2_X,S
            LDY  SWI2_Y,S
            JSR  [JT_DOS_FREAD]
            BCS  DOSFR_ERR
            STX  SWI2_X,S
            AIM  #$FE,SWI2_CC,S
            RTI
DOSFR_ERR   STA  SWI2_A,S
            OIM  #$01,SWI2_CC,S
            RTI
;------------------------------------------------------------------------------
; B=fileref, X=src buf, Y=len. Plain status result.
;------------------------------------------------------------------------------
BIOS_FWRITE
            LDB  SWI2_B,S
            LDX  SWI2_X,S
            LDY  SWI2_Y,S
            JSR  [JT_DOS_FWRITE]
            BCS  DOSFW_ERR
            JMP  BC_OK
DOSFW_ERR   JMP  BC_ERR
;------------------------------------------------------------------------------
; B=fileref, X=new byte position. Plain status result.
;------------------------------------------------------------------------------
BIOS_FSEEK_NAME
            LDB  SWI2_B,S
            LDX  SWI2_X,S
            JSR  [JT_DOS_FSEEK]
            BCS  DOSSK_ERR
            JMP  BC_OK
DOSSK_ERR   JMP  BC_ERR
;------------------------------------------------------------------------------
; B=fileref. Success: X=file size in bytes, Y=current byte position (both
; returned through the SWI2 frame, like BIOS_READLINE's X).
;------------------------------------------------------------------------------
BIOS_FSTAT_NAME
            LDB  SWI2_B,S
            JSR  [JT_DOS_FSTAT]
            BCS  DOSFS_ERR
            STX  SWI2_X,S
            STY  SWI2_Y,S
            AIM  #$FE,SWI2_CC,S
            RTI
DOSFS_ERR   STA  SWI2_A,S
            OIM  #$01,SWI2_CC,S
            RTI
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
            ; Load the reserved sectors (dos/dos.asm) starting at LBA 1,
            ; straight into [USER_RAM], overwriting the boot-sector scratch
            ; now that the fields needed from it have been extracted.
            LDX  #1
            LDY  <USER_RAM
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
SDBOOT_GO   LDX  <USER_RAM
            JMP  ,X             ; hand off to DOS -- never returns
SDBOOT_NONE RTS                 ; caller falls through to LOADER_START
;------------------------------------------------------------------------------
    ENDSECT
;------------------------------------------------------------------------------
; End of sdcard.asm
;------------------------------------------------------------------------------
