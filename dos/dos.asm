;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 DOS
;    FILE: dos.asm
;
; Loaded by bios/sdcard.asm's SD_BOOT_TRY from the FAT16 volume's reserved
; sectors (not ROM -- this is disk payload, assembled to a flat raw binary
; and written there by simulator/tools/mkdiskimg.cpp) into RAM at ORG below,
; which must match wherever bios/main.asm's EndOfVars/USER_RAM currently
; falls (see bios/pugbios.map after a bios rebuild) -- same kind of fixed,
; hand-verified cross-module constant as loader.asm's RUN_ADRS or
; basic309's RESVEC.
;
; Two jobs, both against the same FAT16 volume (BPB fields parsed once at
; boot into resident variables both share):
;
; 1. Boot-time: find "BASIC.COM" in the root directory, walk its cluster
;    chain loading it to $C000, jump to basic309's RESVEC.
; 2. Resident file API for BASIC (LOAD/SAVE/FILES/KILL/NAME and file I/O
;    statements): right before jumping to BASIC, patches bios/main.asm's
;    JT_DOS_* vectors (a RAM vector table BIOS's SWI2 B_FOPEN_NAME/etc.
;    indirect through -- same pattern serio.asm's UT_INIT already uses for
;    JT_IRQ) with the DOS_* routines below, so they stay reachable for as
;    long as BASIC runs. DOS's own RAM footprint (code, per-file sector
;    buffers, variables) sits entirely below basic309's WORKBASE, which
;    BASIC never touches, so nothing needs to relocate for this to work --
;    DOS simply never gets overwritten. If DOS's footprint grows, raise
;    WORKBASE in basic309/exbasrom309.asm to stay above its last byte.
;
; Files are byte streams with a position: sequential read, write (create or
; truncate), append, and update (read/write/seek in place). Up to NSLOTS
; files can be open at once, each with its own 512-byte sector buffer.
;
; No command shell, no long filenames, no subdirectories, files capped at
; 64KB (the on-disk size field is the real 32-bit FAT16 field, but this
; DOS only ever reads/writes the low 16 bits of it -- more than enough
; for a BASIC program or data file). Assumes 512-byte sectors throughout
; (mkdiskimg.cpp always uses that) and a power-of-two sectors-per-cluster
; (FAT16 requires it).
;------------------------------------------------------------------------------
    INCLUDE defines.d
;------------------------------------------------------------------------------
    ORG  $04FE          ; MUST match bios/pugbios.map's EndOfVars/USER_RAM
;------------------------------------------------------------------------------
BASIC_ENTRY   equ $C000   ; basic309's fixed entry: a JMP RESVEC at the start of its image
; bios/main.asm's DOS_JTAB slots (see bios/pugbios.map after a bios
; rebuild) -- fixed, hand-verified constants, same reasoning as
; BASIC_ENTRY above; DOS can't EXTERN these since it's assembled and
; linked completely separately from bios/.
JT_DOS_OPEN      equ $002B
JT_DOS_READLINE  equ $002D
JT_DOS_WRITELINE equ $002F
JT_DOS_CLOSE     equ $0031
JT_DOS_DIRFIRST  equ $0033
JT_DOS_DIRNEXT   equ $0035
JT_DOS_KILL      equ $0037
JT_DOS_RENAME    equ $0039
JT_DOS_FGETC     equ $003B
JT_DOS_FPUTC     equ $003D
JT_DOS_FREAD     equ $003F
JT_DOS_FWRITE    equ $0041
JT_DOS_FSEEK     equ $0043
JT_DOS_FSTAT     equ $0045
;------------------------------------------------------------------------------
NSLOTS      equ 5        ; open files at once. Callers may hold up to NSLOTS-1
                         ; of them and still have a slot free for LOAD/SAVE.
;------------------------------------------------------------------------------
fslot       STRUCT
inuse       rmb 1        ; 0 = free
mode        rmb 1        ; FOPEN_READ/WRITE/APPEND/UPDATE
startclus   rmb 2        ; file's first cluster (0 = none allocated yet)
size        rmb 2        ; file size in bytes (low 16 bits)
pos         rmb 2        ; current byte position
dirlba      rmb 2        ; sector holding this file's directory entry
dirofs      rmb 2        ; byte offset of the entry within that sector --
                         ; 2 bytes: with 16 entries/sector, the 9th-16th
                         ; entry's offset (256-480) doesn't fit in 1 byte
bufptr      rmb 2        ; this slot's 512-byte data buffer (in SLOTBUFS)
bufsec      rmb 1        ; file sector index held in that buffer; $FF = none
dirty       rmb 1        ; buffer modified since it was loaded
cacheidx    rmb 1        ; cluster index (within the file) of cacheclus ...
cacheclus   rmb 2        ; ... a cached spot in the chain (0 = none), so
                         ; sequential access doesn't re-walk from the start
            ENDS
;------------------------------------------------------------------------------
DOS_START   LDX  #0             ; LBA 0: the boot sector
            LDY  #DOSBUF
            JSR  BLKREAD

            ; Pull the BPB fields we need. Each multi-byte field is stored
            ; little-endian; reading the high byte then the low byte (in
            ; the opposite order LDD would) reconstructs it correctly into
            ; D without a byte-swap step.
            LDA  DOSBUF+13      ; sectors per cluster, offset $0D (1 byte)
            STA  SECPERCLUS
            ; A power of two, so "which cluster holds file sector N" is a
            ; shift and "which sector within it" is a mask -- no divide.
            DECA
            STA  SPCMASK
            CLR  SPCSHIFT
            LDA  SECPERCLUS
SHIFTLOOP   CMPA #1
            BLS  SHIFTDONE
            LSRA
            INC  SPCSHIFT
            BRA  SHIFTLOOP
SHIFTDONE
            ; Nothing is open at boot. Clear the whole file table rather
            ; than trusting RAM to already be zero (it isn't on real
            ; hardware, and a stray nonzero "inuse" would hide a slot).
            LDX  #FSLOTS
            CLR  ,X
            LDY  #FSLOTS
            LDW  #NSLOTS*sizeof{fslot}
            TFM  X,Y+
            LDA  DOSBUF+15      ; reserved sector count, offset $0E/$0F
            LDB  DOSBUF+14
            STD  RESSEC
            LDA  DOSBUF+16      ; number of FATs, offset $10 (1 byte)
            STA  NUMFATS
            LDA  DOSBUF+18      ; root entry count, offset $11/$12
            LDB  DOSBUF+17
            STD  ROOTENTCNT
            LDA  DOSBUF+20      ; total sectors (16-bit), offset $13/$14
            LDB  DOSBUF+19
            STD  TOTALSEC
            LDA  DOSBUF+23      ; sectors per FAT, offset $16/$17
            LDB  DOSBUF+22
            STD  SECPERFAT

            ; FATLBA = RESSEC (the first FAT starts right after the
            ; reserved sectors).
            LDD  RESSEC
            STD  FATLBA

            ; ROOTLBA = RESSEC + NUMFATS*SECPERFAT (NUMFATS is always a
            ; small integer -- 1 or 2 -- so a counted add-loop is simpler
            ; than a general multiply). The counter lives in memory
            ; (FATCNT), not in B, since B is also D's low byte and every
            ; LDD/ADDD/STD below touches it -- a register-based counter
            ; here would get silently clobbered by the very accumulator
            ; arithmetic it's supposed to be counting. FATCNT must be set
            ; up BEFORE reloading D with RESSEC below -- LDA NUMFATS also
            ; touches D's high byte (A), so doing it after would clobber
            ; the very accumulator value it's about to start summing into.
            LDA  NUMFATS
            STA  FATCNT
            LDD  RESSEC         ; D = the running total, seeded with RESSEC
FATLOOP     TST  FATCNT         ; TST, not LDA -- checking the counter must
            BEQ  FATDONE        ; not touch D (A specifically), since D is
            ADDD SECPERFAT      ; the running accumulator here
            DEC  FATCNT
            BRA  FATLOOP
FATDONE     STD  ROOTLBA

            ; ROOTDIRSEC = ROOTENTCNT*32/512 = ROOTENTCNT/16 exactly (a
            ; 32-byte entry, 512-byte sector) -- four right shifts of the
            ; 16-bit value instead of a divide.
            LDD  ROOTENTCNT
            LSRA
            RORB
            LSRA
            RORB
            LSRA
            RORB
            LSRA
            RORB
            STD  ROOTDIRSEC

            ; DATALBA = ROOTLBA + ROOTDIRSEC
            LDD  ROOTLBA
            ADDD ROOTDIRSEC
            STD  DATALBA

            ; TOTALCLUS = (TOTALSEC - DATALBA) / SECPERCLUS, via repeated
            ; subtraction (SECPERCLUS is small; this runs once, at boot --
            ; simplicity over speed). MAXCLUS = TOTALCLUS+2 (clusters are
            ; numbered from 2) is ALLOC_CLUSTER's scan bound.
            CLRA
            LDB  SECPERCLUS
            STD  SECPERCLUS16
            LDD  TOTALSEC
            SUBD DATALBA
            STD  TMPD
            LDD  #0
            STD  TOTALCLUS
TCLOOP      LDD  TMPD
            CMPD SECPERCLUS16
            BLO  TCDONE
            SUBD SECPERCLUS16
            STD  TMPD
            LDD  TOTALCLUS
            ADDD #1
            STD  TOTALCLUS
            BRA  TCLOOP
TCDONE      LDD  TOTALCLUS
            ADDD #2
            STD  MAXCLUS

            ; Find BASIC.COM and load its cluster chain to $C000.
            LDX  #BASICNAME
            JSR  FIND_DIRENT
            LBCS NOTFOUND
            LDD  #$C000
            STD  DESTPTR
            LDD  FOUND_CLUSTER
            STD  CURCLUS
LOADCLUS    LDD  CURCLUS
            JSR  CLUS_TO_LBA
            STD  RDLBA
            LDA  SECPERCLUS
            STA  MULCNT
RDCLUSLOOP  TST  MULCNT
            BEQ  RDCLUS_DONE
            LDX  RDLBA
            LDY  DESTPTR
            JSR  BLKREAD
            LDD  RDLBA
            ADDD #1
            STD  RDLBA
            LDD  DESTPTR
            ADDD #512
            STD  DESTPTR
            DEC  MULCNT
            BRA  RDCLUSLOOP
RDCLUS_DONE
            LDD  CURCLUS
            JSR  NEXT_CLUSTER
            CMPD #$FFF8         ; $FFF8-$FFFF: end of chain
            BHS  ALLDONE
            STD  CURCLUS
            JMP  LOADCLUS

            ; Patch bios/main.asm's DOS_JTAB so LOAD/SAVE can reach the
            ; resident file API below for as long as BASIC runs, then
            ; hand off. Never returns.
ALLDONE     LDX  #DOS_OPEN
            STX  JT_DOS_OPEN
            LDX  #DOS_READLINE
            STX  JT_DOS_READLINE
            LDX  #DOS_WRITELINE
            STX  JT_DOS_WRITELINE
            LDX  #DOS_CLOSE
            STX  JT_DOS_CLOSE
            LDX  #DOS_DIR_FIRST
            STX  JT_DOS_DIRFIRST
            LDX  #DOS_DIR_NEXT
            STX  JT_DOS_DIRNEXT
            LDX  #DOS_KILL
            STX  JT_DOS_KILL
            LDX  #DOS_RENAME
            STX  JT_DOS_RENAME
            LDX  #DOS_FGETC
            STX  JT_DOS_FGETC
            LDX  #DOS_FPUTC
            STX  JT_DOS_FPUTC
            LDX  #DOS_FREAD
            STX  JT_DOS_FREAD
            LDX  #DOS_FWRITE
            STX  JT_DOS_FWRITE
            LDX  #DOS_FSEEK
            STX  JT_DOS_FSEEK
            LDX  #DOS_FSTAT
            STX  JT_DOS_FSTAT
            JMP  BASIC_ENTRY

NOTFOUND    LDX  #MSG_NOBASIC
            LDB  #F_STDOUT
            LDA  #B_PUTS
            SWI2
HANG        BRA  HANG           ; nothing else to do -- not resumable
;==============================================================================
; Low-level block/FAT/directory primitives, shared by the boot-time loader
; above and the resident file API below.
;==============================================================================
; X=16-bit LBA, Y=RAM buffer adrs. See bios/defines.d's B_BLK_READ. X/Y are
; preserved by SWI2 (interrupt entry stacks them, RTI restores them, and
; the handler never touches those frame slots) so nothing here needs to
; save/restore them manually. Returns A=status, carry=error, same as SWI2
; itself always leaves them.
;------------------------------------------------------------------------------
BLKREAD     LDA  #B_BLK_READ
            SWI2
            RTS
;------------------------------------------------------------------------------
BLKWRITE    LDA  #B_BLK_WRITE
            SWI2
            RTS
;------------------------------------------------------------------------------
; Zeros all 512 bytes of DOSBUF (same replicate-one-byte-forward TFM idiom
; bios/main.asm's V_RESET uses to zero its own RAM). Trashes A, X, Y, W.
;------------------------------------------------------------------------------
CLEAR_DOSBUF
            LDX  #DOSBUF
            CLR  ,X
            LDY  #DOSBUF
            LDW  #512
            TFM  X,Y+
            RTS
;------------------------------------------------------------------------------
; IN: D = cluster number. OUT: D = that cluster's starting LBA. Trashes
; A, B (via the internal MULCNT-style counted loop -- see FATLOOP above
; for why the counter lives in memory, not a register).
;------------------------------------------------------------------------------
CLUS_TO_LBA STD  CTLCLUS
            SUBD #2
            STD  TMPD
            LDA  SECPERCLUS
            STA  MULCNT
            LDD  #0
CTL_LOOP    TST  MULCNT
            BEQ  CTL_DONE
            ADDD TMPD
            DEC  MULCNT
            BRA  CTL_LOOP
CTL_DONE    ADDD DATALBA
            RTS
;------------------------------------------------------------------------------
; IN: D = cluster number. OUT: X = pointer into DOSBUF at this cluster's
; FAT entry (2 bytes, little-endian); FATSECLBA_CUR = the LBA that sector
; was loaded from (for a caller that wants to modify and write it back).
; Trashes A, B.
;------------------------------------------------------------------------------
LOAD_FAT_ENTRY
            STD  LFECLUS
            CLRA
            LDB  LFECLUS         ; cluster's high byte, zero-extended
            ADDD FATLBA
            STD  FATSECLBA_CUR
            LDA  LFECLUS+1       ; cluster's low byte
            LDB  #2
            MUL                  ; D = low_byte*2 = byte offset within sector
            STD  LFEOFS
            LDX  FATSECLBA_CUR
            LDY  #DOSBUF
            JSR  BLKREAD
            LDX  #DOSBUF
            LDD  LFEOFS
            LEAX D,X
            RTS
;------------------------------------------------------------------------------
; IN: D = cluster number. OUT: D = next cluster in the chain ($FFF8-$FFFF
; = end of chain). Trashes A, B, X.
;------------------------------------------------------------------------------
NEXT_CLUSTER
            JSR  LOAD_FAT_ENTRY
            LDA  1,X             ; FAT entries are little-endian too
            LDB  ,X
            RTS
;------------------------------------------------------------------------------
; IN: D = cluster to modify. SETVAL (set by the caller first) = the new
; value. Trashes A, B, X, Y.
;------------------------------------------------------------------------------
SET_FAT_ENTRY
            JSR  LOAD_FAT_ENTRY
            LDD  SETVAL
            STB  ,X              ; little-endian, same reasoning as
            STA  1,X             ; OPEN_WRITE_INIT's cluster/size writes
            LDX  FATSECLBA_CUR
            LDY  #DOSBUF
            JSR  BLKWRITE
            RTS
;------------------------------------------------------------------------------
; Scans the FAT for a free (zero) entry, from cluster 2 up to MAXCLUS.
; OUT: carry clear + D = the free cluster number, its FAT entry already
; written as end-of-chain ($FFFF) so it's claimed; carry set = disk full.
; Trashes A, B, X, Y.
;------------------------------------------------------------------------------
ALLOC_CLUSTER
            LDD  #2
            STD  ACCLUS
AC_LOOP     LDD  ACCLUS
            CMPD MAXCLUS
            BHS  AC_FULL
            JSR  LOAD_FAT_ENTRY
            LDA  1,X
            LDB  ,X
            BNE  AC_NEXT
            LDD  #$FFFF          ; both bytes equal -- byte order is moot
            STD  ,X
            LDX  FATSECLBA_CUR
            LDY  #DOSBUF
            JSR  BLKWRITE
            LDD  ACCLUS
            ANDCC #$FE
            RTS
AC_NEXT     LDD  ACCLUS
            ADDD #1
            STD  ACCLUS
            BRA  AC_LOOP
AC_FULL     ORCC #1
            RTS
;------------------------------------------------------------------------------
; IN: D = starting cluster. Walks the chain, zeroing every FAT entry
; (freeing it). Trashes A, B, D, X, Y.
;------------------------------------------------------------------------------
FREE_CHAIN  STD  FCCLUS
FC_LOOP     LDD  FCCLUS
            CMPD #$FFF8
            BHS  FC_DONE
            JSR  LOAD_FAT_ENTRY
            LDA  1,X
            LDB  ,X
            STD  FCNEXT
            LDD  #0
            STD  ,X
            LDX  FATSECLBA_CUR
            LDY  #DOSBUF
            JSR  BLKWRITE
            LDD  FCNEXT
            STD  FCCLUS
            BRA  FC_LOOP
FC_DONE     RTS
;------------------------------------------------------------------------------
; IN: A = slot index (0-3). OUT: X = that slot's base address. Trashes
; A, B, D.
;------------------------------------------------------------------------------
SLOT_ADDR   TFR  A,B
            LDA  #sizeof{fslot}
            MUL
            LDX  #FSLOTS
            LEAX D,X
            RTS
;------------------------------------------------------------------------------
; IN: X = pointer to an 11-byte name (space-padded 8.3, no dot). OUT:
; carry clear if found (FOUND_LBA/FOUND_OFS/FOUND_CLUSTER/FOUND_SIZE set);
; carry set if not found. Trashes A, B, D, X, Y.
;------------------------------------------------------------------------------
FIND_DIRENT STX  FDNAME
            LDD  ROOTLBA
            STD  FDLBA
            LDD  ROOTDIRSEC
            STD  FDSECLEFT
FD_SECLOOP  LDD  FDSECLEFT
            BEQ  FD_NOTFOUND
            LDX  FDLBA
            LDY  #DOSBUF
            JSR  BLKREAD
            LDX  #DOSBUF
            LDB  #16
FD_ENTLOOP  PSHS B,X
            LDB  #11
            LDY  FDNAME
FD_CMP      LDA  ,X+
            CMPA ,Y+
            BNE  FD_NOMATCH
            DECB
            BNE  FD_CMP
            PULS B,X             ; X = start of this 32-byte entry
            LDD  FDLBA
            STD  FOUND_LBA
            TFR  X,D
            SUBD #DOSBUF
            STD  FOUND_OFS       ; 0..480 -- doesn't fit in 1 byte (16
                                 ; entries/sector, entry 9+ is >= 256)
            LDA  27,X
            LDB  26,X
            STD  FOUND_CLUSTER
            LDA  29,X
            LDB  28,X
            STD  FOUND_SIZE
            LDA  31,X
            LDB  30,X
            STD  FOUND_SIZEHI    ; nonzero = a file this DOS can't fully handle
            ANDCC #$FE
            RTS
FD_NOMATCH  PULS B,X
            LEAX 32,X
            DECB
            BNE  FD_ENTLOOP
            LDD  FDLBA
            ADDD #1
            STD  FDLBA
            LDD  FDSECLEFT
            SUBD #1
            STD  FDSECLEFT
            BRA  FD_SECLOOP
FD_NOTFOUND ORCC #1
            RTS
;------------------------------------------------------------------------------
; Scans the root directory for a free entry (first byte $00=never used or
; $E5=deleted). OUT: carry clear + FOUND_LBA/FOUND_OFS set; carry set if
; the root directory is completely full. Trashes A, B, D, X, Y.
;------------------------------------------------------------------------------
FIND_FREE_DIRENT
            LDD  ROOTLBA
            STD  FDLBA
            LDD  ROOTDIRSEC
            STD  FDSECLEFT
FFD_SECLOOP LDD  FDSECLEFT
            BEQ  FD_NOTFOUND     ; reuse FIND_DIRENT's not-found exit
            LDX  FDLBA
            LDY  #DOSBUF
            JSR  BLKREAD
            LDX  #DOSBUF
            LDB  #16
FFD_ENTLOOP LDA  ,X
            BEQ  FFD_GOTIT
            CMPA #$E5
            BEQ  FFD_GOTIT
            LEAX 32,X
            DECB
            BNE  FFD_ENTLOOP
            LDD  FDLBA
            ADDD #1
            STD  FDLBA
            LDD  FDSECLEFT
            SUBD #1
            STD  FDSECLEFT
            BRA  FFD_SECLOOP
FFD_GOTIT   LDD  FDLBA
            STD  FOUND_LBA
            TFR  X,D
            SUBD #DOSBUF
            STD  FOUND_OFS
            ANDCC #$FE
            RTS
;==============================================================================
; Resident file API -- see DOS_JTAB patching in ALLDONE above. Each of these
; is a plain subroutine (RTS, carry=error), called by bios/sdcard.asm's BIOS_*
; handlers, which own finishing the SWI2 response.
;
; Every open file has its own slot (fslot) and its own 512-byte sector buffer
; (SLOTBUFS), so any number of files can be open at once and used in any
; interleaving without disturbing each other. DOSBUF is separate scratch used
; only for FAT and directory sectors -- never as a file's data buffer.
;==============================================================================
; IN: B = fileref. OUT: carry clear + CUR_SLOT/X = that open slot; carry set +
; A = ERR_BADDEV if B isn't the fileref of an open file. Trashes A, B, D.
;------------------------------------------------------------------------------
SLOT_CHECK  CMPB #NSLOTS
            BHS  SC_BAD
            TFR  B,A
            JSR  SLOT_ADDR
            TST  fslot.inuse,X
            BEQ  SC_BAD
            STX  CUR_SLOT
            ANDCC #$FE
            RTS
SC_BAD      LDA  #ERR_BADDEV
            ORCC #1
            RTS
;------------------------------------------------------------------------------
; FOUND_LBA/FOUND_OFS = a directory entry (from FIND_DIRENT). OUT: carry clear
; if no open file uses it; carry set + A = ERR_ISOPEN if one does. Trashes A,
; B, D, X.
;------------------------------------------------------------------------------
CHECK_NOT_OPEN
            CLR  CNO_IDX
CNO_LOOP    LDA  CNO_IDX
            CMPA #NSLOTS
            BHS  CNO_OK
            JSR  SLOT_ADDR
            TST  fslot.inuse,X
            BEQ  CNO_NEXT
            LDD  fslot.dirlba,X
            CMPD FOUND_LBA
            BNE  CNO_NEXT
            LDD  fslot.dirofs,X
            CMPD FOUND_OFS
            BEQ  CNO_BUSY
CNO_NEXT    INC  CNO_IDX
            BRA  CNO_LOOP
CNO_OK      ANDCC #$FE
            RTS
CNO_BUSY    LDA  #ERR_ISOPEN
            ORCC #1
            RTS
;------------------------------------------------------------------------------
; IN: X = 11-byte 8.3 filename, A = mode (FOPEN_READ/WRITE/APPEND/UPDATE).
; OUT: carry clear + A = fileref (0..NSLOTS-1); carry set + A = error code.
;   READ    must exist; read and seek only.
;   WRITE   created, or truncated if it exists; write only.
;   APPEND  created if missing; existing contents kept, writes go at the end.
;   UPDATE  created if missing; existing contents kept; read, write and seek.
; A file that's already open (in any slot) can't be opened again.
;------------------------------------------------------------------------------
DOS_OPEN    STX  OPEN_NAME
            STA  OPEN_MODE
            CMPA #FOPEN_UPDATE
            BLS  OPEN_MODE_OK
            LDA  #ERR_BADMODE
            ORCC #1
            RTS
OPEN_MODE_OK
            CLR  OPEN_SLOTIDX
OPEN_FINDSLOT
            LDA  OPEN_SLOTIDX
            CMPA #NSLOTS
            BLO  OPEN_CHECKSLOT
            LDA  #ERR_NOSLOT
            ORCC #1
            RTS
OPEN_CHECKSLOT
            JSR  SLOT_ADDR
            TST  fslot.inuse,X
            BEQ  OPEN_GOTSLOT
            INC  OPEN_SLOTIDX
            BRA  OPEN_FINDSLOT
OPEN_GOTSLOT
            STX  OPEN_SLOTPTR
            LDX  OPEN_NAME
            JSR  FIND_DIRENT
            BCC  OPEN_FOUND
            LDA  OPEN_MODE
            BEQ  OPEN_NOTFOUND_READ
            JSR  FIND_FREE_DIRENT
            BCS  OPEN_NOSPACE
            LDD  #0                   ; brand-new empty file: no clusters yet
            STD  FOUND_CLUSTER
            STD  FOUND_SIZE
            STD  FOUND_SIZEHI
            BRA  OPEN_WRITE_ENTRY
OPEN_NOTFOUND_READ
            LDA  #ERR_NOTFOUND
            ORCC #1
            RTS
OPEN_NOSPACE
            LDA  #ERR_NOSPACE
            ORCC #1
            RTS
OPEN_IOERR  LDA  #ERR_IOERR
            ORCC #1
            RTS
OPEN_TOOBIG LDA  #ERR_BADMODE
            ORCC #1
            RTS
OPEN_FOUND  JSR  CHECK_NOT_OPEN
            BCC  OPEN_FOUND2
            RTS                       ; carry set, A = ERR_ISOPEN
OPEN_FOUND2 LDD  FOUND_SIZEHI
            BEQ  OPEN_SIZE_OK
            ; Bigger than 64KB: readable (the first 64KB), and WRITE simply
            ; truncates it, but appending/updating would need the high word.
            LDA  OPEN_MODE
            CMPA #FOPEN_APPEND
            BHS  OPEN_TOOBIG
            LDD  #$FFFF
            STD  FOUND_SIZE
OPEN_SIZE_OK
            LDA  OPEN_MODE
            BEQ  OPEN_INIT            ; read: directory untouched
            CMPA #FOPEN_WRITE
            BNE  OPEN_INIT            ; append/update keep the contents
            LDD  FOUND_CLUSTER        ; write: truncate -- free the old chain
            BEQ  OPEN_TRUNC_DONE
            JSR  FREE_CHAIN
OPEN_TRUNC_DONE
            LDD  #0
            STD  FOUND_CLUSTER
            STD  FOUND_SIZE
OPEN_WRITE_ENTRY
            ; (Re)write this file's directory entry as an empty file: name,
            ; ARCHIVE attribute, then zeros for the rest (dates, cluster, size).
            LDX  FOUND_LBA
            LDY  #DOSBUF
            JSR  BLKREAD
            BCS  OPEN_IOERR
            LDD  FOUND_OFS
            LDX  #DOSBUF
            LEAX D,X                  ; X = this entry's start within DOSBUF
            LDY  OPEN_NAME
            LDB  #11
OW_COPYNAME LDA  ,Y+
            STA  ,X+
            DECB
            BNE  OW_COPYNAME
            LDA  #$20                 ; ARCHIVE attribute, entry offset 11
            STA  ,X+
            LDB  #20
OW_ZEROREST CLR  ,X+                  ; offsets 12..31
            DECB
            BNE  OW_ZEROREST
            LDX  FOUND_LBA
            LDY  #DOSBUF
            JSR  BLKWRITE
            BCS  OPEN_IOERR
OPEN_INIT   LDX  OPEN_SLOTPTR
            LDA  #1
            STA  fslot.inuse,X
            LDA  OPEN_MODE
            STA  fslot.mode,X
            LDD  FOUND_CLUSTER
            STD  fslot.startclus,X
            LDD  FOUND_SIZE
            STD  fslot.size,X
            LDD  #0
            STD  fslot.pos,X
            LDA  OPEN_MODE
            CMPA #FOPEN_APPEND
            BNE  OI_NOAPPEND
            LDD  FOUND_SIZE           ; append: start at the end
            STD  fslot.pos,X
OI_NOAPPEND LDD  FOUND_LBA
            STD  fslot.dirlba,X
            LDD  FOUND_OFS
            STD  fslot.dirofs,X
            LDA  #$FF
            STA  fslot.bufsec,X       ; nothing cached yet
            CLR  fslot.dirty,X
            CLR  fslot.cacheidx,X
            LDD  #0
            STD  fslot.cacheclus,X
            LDA  OPEN_SLOTIDX         ; this slot's buffer: SLOTBUFS + idx*512
            ASLA
            CLRB
            ADDD #SLOTBUFS
            STD  fslot.bufptr,X
            LDA  OPEN_SLOTIDX
            ANDCC #$FE
            RTS
;------------------------------------------------------------------------------
; IN: B = fileref, X = dest buf, Y = max len. OUT: carry clear + X = actual
; length read (0 = EOF or an empty line); carry set + A = error. Reads a line,
; stopping at CR or LF (excluded), EOF, or a full buffer. A CR also takes an
; immediately following LF, so CR, LF and CRLF terminated files all read as
; ordinary lines (and a bare LF line is a blank line, not swallowed).
;------------------------------------------------------------------------------
DOS_READLINE
            STX  RL_DEST
            STY  RL_MAX
            JSR  SLOT_CHECK
            BCS  RL_RET
            LDD  #0
            STD  RL_COUNT
RL_LOOP     LDD  RL_COUNT
            CMPD RL_MAX
            BHS  RL_DONE
            JSR  FILE_GETBYTE
            BCS  RL_DONE
            CMPA #CR
            BEQ  RL_CR
            CMPA #LF
            BEQ  RL_DONE
RL_STORE    PSHS A                   ; save the byte -- LDD RL_COUNT below
            LDX  RL_DEST              ; would otherwise clobber A (D = A:B)
            LDD  RL_COUNT
            LEAX D,X
            PULS A
            STA  ,X
            LDD  RL_COUNT
            ADDD #1
            STD  RL_COUNT
            BRA  RL_LOOP
RL_CR       JSR  FILE_GETBYTE         ; a CR takes an immediately following LF
            BCS  RL_DONE              ; with it (CRLF) -- so the file position
            CMPA #LF                  ; is left at the start of the next line
            BEQ  RL_DONE
            LDX  CUR_SLOT             ; anything else isn't ours: step back over it
            LDD  fslot.pos,X
            SUBD #1
            STD  fslot.pos,X
RL_DONE     LDX  RL_COUNT
            ANDCC #$FE
RL_RET      RTS
;------------------------------------------------------------------------------
; IN: B = fileref, X = src buf, Y = len. OUT: carry clear on success; carry
; set + A = error. Writes Y bytes from the buffer plus a trailing CR.
;------------------------------------------------------------------------------
DOS_WRITELINE
            STX  WL_SRC
            STY  WL_LEN
            JSR  SLOT_CHECK
            BCS  WL_RET
            LDD  #0
            STD  WL_I
WL_LOOP     LDD  WL_I
            CMPD WL_LEN
            BHS  WL_DOCR
            LDX  WL_SRC
            LDD  WL_I
            LEAX D,X
            LDA  ,X
            JSR  FILE_PUTBYTE
            BCS  WL_RET
            LDD  WL_I
            ADDD #1
            STD  WL_I
            BRA  WL_LOOP
WL_DOCR     LDA  #CR
            JSR  FILE_PUTBYTE
WL_RET      RTS
;------------------------------------------------------------------------------
; IN: B = fileref. Finalizes: a file opened for writing has its buffered
; sector flushed and its directory entry updated with the final first cluster
; and size; a file opened for reading just frees its slot. The slot is freed
; even if a write-back fails (that error is still reported). Trashes A, B, D,
; X, Y.
;------------------------------------------------------------------------------
DOS_CLOSE   JSR  SLOT_CHECK
            BCS  DC_RET
            CLR  DC_STATUS            ; 0 = no error so far
            LDX  CUR_SLOT
            LDA  fslot.mode,X
            BEQ  DC_FREE              ; read mode: nothing to write back
            JSR  FLUSH_SLOT
            BCC  DC_DIRENT
            STA  DC_STATUS            ; remember it, but finish closing anyway
DC_DIRENT   LDX  CUR_SLOT
            LDD  fslot.dirlba,X
            STD  FGBTMP
            LDD  fslot.dirofs,X
            STD  DC_DIROFS
            LDD  fslot.size,X
            STD  DC_SIZE
            LDD  fslot.startclus,X
            STD  DC_CLUS
            LDX  FGBTMP
            LDY  #DOSBUF
            JSR  BLKREAD
            BCS  DC_IOERR
            LDD  DC_DIROFS
            LDX  #DOSBUF
            LEAX D,X                  ; X = this file's directory entry
            LDD  DC_CLUS              ; little-endian, same reasoning as
            STB  26,X                 ; DOS_OPEN's directory writes
            STA  27,X
            LDD  DC_SIZE
            STB  28,X
            STA  29,X
            LDD  #0
            STD  30,X                 ; size's high word: always 0 here
            LDX  FGBTMP
            LDY  #DOSBUF
            JSR  BLKWRITE
            BCC  DC_FREE
DC_IOERR    LDA  #ERR_IOERR
            STA  DC_STATUS
DC_FREE     LDX  CUR_SLOT
            CLR  fslot.inuse,X
            LDA  DC_STATUS
            BEQ  DC_OK
            ORCC #1
            RTS
DC_OK       ANDCC #$FE
DC_RET      RTS
;------------------------------------------------------------------------------
; IN: B = fileref. OUT: carry clear + A = next byte; carry set + A = ERR_EOF at
; end of file (or another error code).
;------------------------------------------------------------------------------
DOS_FGETC   JSR  SLOT_CHECK
            BCS  FGC_RET
            JSR  FILE_GETBYTE
FGC_RET     RTS
;------------------------------------------------------------------------------
; IN: A = the byte, B = fileref. OUT: carry clear on success.
;------------------------------------------------------------------------------
DOS_FPUTC   STA  FP_BYTE
            JSR  SLOT_CHECK
            BCS  FPC_RET
            LDA  FP_BYTE
            JSR  FILE_PUTBYTE
FPC_RET     RTS
;------------------------------------------------------------------------------
; IN: B = fileref, X = dest buf, Y = max len. OUT: carry clear + X = number of
; bytes read (less than Y only at end of file); carry set + A = error.
;------------------------------------------------------------------------------
DOS_FREAD   STX  IO_BUF
            STY  IO_LEN
            JSR  SLOT_CHECK
            BCS  FR_RET
            LDD  #0
            STD  IO_CNT
FR_LOOP     LDD  IO_CNT
            CMPD IO_LEN
            BHS  FR_DONE
            JSR  FILE_GETBYTE
            BCC  FR_STORE
            CMPA #ERR_EOF
            BEQ  FR_DONE              ; short read: end of file
            ORCC #1                   ; a real error
            RTS
FR_STORE    LDX  IO_BUF
            PSHS A
            LDD  IO_CNT
            LEAX D,X
            PULS A
            STA  ,X
            LDD  IO_CNT
            ADDD #1
            STD  IO_CNT
            BRA  FR_LOOP
FR_DONE     LDX  IO_CNT
            ANDCC #$FE
FR_RET      RTS
;------------------------------------------------------------------------------
; IN: B = fileref, X = src buf, Y = len. OUT: carry clear on success.
;------------------------------------------------------------------------------
DOS_FWRITE  STX  IO_BUF
            STY  IO_LEN
            JSR  SLOT_CHECK
            BCS  FW_RET
            LDD  #0
            STD  IO_CNT
FW_LOOP     LDD  IO_CNT
            CMPD IO_LEN
            BHS  FW_DONE
            LDX  IO_BUF
            LDD  IO_CNT
            LEAX D,X
            LDA  ,X
            JSR  FILE_PUTBYTE
            BCS  FW_RET
            LDD  IO_CNT
            ADDD #1
            STD  IO_CNT
            BRA  FW_LOOP
FW_DONE     ANDCC #$FE
FW_RET      RTS
;------------------------------------------------------------------------------
; IN: B = fileref, X = new byte position. Read and update modes only.
;------------------------------------------------------------------------------
DOS_FSEEK   STX  SK_POS
            JSR  SLOT_CHECK
            BCS  SK_RET
            LDX  CUR_SLOT
            LDA  fslot.mode,X
            BEQ  SK_OK                ; read
            CMPA #FOPEN_UPDATE
            BEQ  SK_OK
            LDA  #ERR_BADMODE
            ORCC #1
            RTS
SK_OK       LDD  SK_POS
            STD  fslot.pos,X
            ANDCC #$FE
SK_RET      RTS
;------------------------------------------------------------------------------
; IN: B = fileref. OUT: carry clear + X = file size, Y = current position.
;------------------------------------------------------------------------------
DOS_FSTAT   JSR  SLOT_CHECK
            BCS  FS_RET
            LDX  CUR_SLOT
            LDY  fslot.pos,X
            LDX  fslot.size,X
            ANDCC #$FE
FS_RET      RTS
;------------------------------------------------------------------------------
; IN: X = destination 16-byte buffer (11 name + 1 attr + 4 size). OUT:
; carry clear + buffer filled with the first live (non-deleted) directory
; entry; carry set = the directory has no entries at all. Trashes A, B, D,
; X, Y.
;------------------------------------------------------------------------------
DOS_DIR_FIRST
            STX  DIRDEST
            LDD  ROOTLBA
            STD  DIRLBA_CUR
            LDD  ROOTDIRSEC
            STD  DIRSECLEFT
            CLR  DIRENTIDX
            BRA  DDS_LOADSEC
;------------------------------------------------------------------------------
; Same signature as DOS_DIR_FIRST; continues the scan it started (resuming
; from DIRLBA_CUR/DIRSECLEFT/DIRENTIDX, left where the previous call
; stopped). Trashes A, B, D, X, Y.
;------------------------------------------------------------------------------
DOS_DIR_NEXT
            STX  DIRDEST
DDS_LOADSEC LDD  DIRSECLEFT
            BEQ  DDS_EOF
            LDX  DIRLBA_CUR
            LDY  #DOSBUF
            JSR  BLKREAD
DDS_ENTLOOP LDB  DIRENTIDX
            CMPB #16
            BLO  DDS_CHECKENT
            LDD  DIRLBA_CUR
            ADDD #1
            STD  DIRLBA_CUR
            LDD  DIRSECLEFT
            SUBD #1
            STD  DIRSECLEFT
            CLR  DIRENTIDX
            BRA  DDS_LOADSEC
DDS_CHECKENT
            LDB  DIRENTIDX
            LDA  #32
            MUL                  ; D = DIRENTIDX*32 (max 15*32=480, fits D)
            LDX  #DOSBUF
            LEAX D,X             ; X = this entry's address
            LDA  ,X
            BEQ  DDS_EOF         ; $00 -- never used, and everything after
                                 ; it is too (compact-directory convention)
            INC  DIRENTIDX       ; advance for the NEXT call regardless
            CMPA #$E5
            BEQ  DDS_ENTLOOP     ; deleted -- skip, try the next one
            LDY  DIRDEST
            LDB  #11
DDS_CPNAME  LDA  ,X+
            STA  ,Y+
            DECB
            BNE  DDS_CPNAME      ; X now at offset 11 (attribute byte)
            LDA  ,X
            STA  ,Y+             ; attribute
            LEAX 17,X            ; 11+17=28, the size field
            LDA  ,X+
            STA  ,Y+
            LDA  ,X+
            STA  ,Y+
            LDA  ,X+
            STA  ,Y+
            LDA  ,X
            STA  ,Y
            ANDCC #$FE
            RTS
DDS_EOF     ORCC #1
            RTS
;------------------------------------------------------------------------------
; IN: X = 11-byte 8.3 filename. Frees its cluster chain (if any) and marks
; its directory entry deleted ($E5). OUT: carry clear = deleted; carry set
; + A=ERR_NOTFOUND. Trashes A, B, D, X, Y.
;------------------------------------------------------------------------------
DOS_KILL    JSR  FIND_DIRENT
            BCS  DK_NOTFOUND
            JSR  CHECK_NOT_OPEN  ; deleting a file out from under an open
            BCC  DK_GO           ; handle would corrupt it
            RTS                  ; carry set, A = ERR_ISOPEN
DK_GO       LDD  FOUND_CLUSTER
            BEQ  DK_MARKDEL      ; cluster 0 -- empty file, nothing to free
            JSR  FREE_CHAIN
DK_MARKDEL  LDX  FOUND_LBA
            LDY  #DOSBUF
            JSR  BLKREAD
            LDD  FOUND_OFS
            LDX  #DOSBUF
            LEAX D,X
            LDA  #$E5
            STA  ,X
            LDX  FOUND_LBA
            LDY  #DOSBUF
            JSR  BLKWRITE
            ANDCC #$FE
            RTS
DK_NOTFOUND LDA  #ERR_NOTFOUND
            ORCC #1
            RTS
;------------------------------------------------------------------------------
; IN: X = 11-byte OLD 8.3 filename, Y = 11-byte NEW 8.3 filename. OUT:
; carry clear = renamed; carry set + A=ERR_NOTFOUND (old doesn't exist) or
; A=ERR_EXISTS (new name is already taken). Trashes A, B, D, X, Y.
;------------------------------------------------------------------------------
DOS_RENAME  STY  RENAME_NEW
            JSR  FIND_DIRENT     ; X = old name -- must already exist
            BCS  DR_NOTFOUND
            JSR  CHECK_NOT_OPEN  ; renaming an open file would leave its
            BCC  DR_OLDCLOSED    ; handle pointing at the wrong name
            RTS                  ; carry set, A = ERR_ISOPEN
DR_OLDCLOSED
            LDD  FOUND_LBA
            STD  DR_OLDLBA
            LDD  FOUND_OFS
            STD  DR_OLDOFS
            LDX  RENAME_NEW
            JSR  FIND_DIRENT     ; does the NEW name already exist?
            BCC  DR_EXISTS       ; found -- refuse to collide
            LDX  DR_OLDLBA
            LDY  #DOSBUF
            JSR  BLKREAD
            LDD  DR_OLDOFS
            LDX  #DOSBUF
            LEAX D,X
            LDY  RENAME_NEW
            LDB  #11
DR_COPYNAME LDA  ,Y+
            STA  ,X+
            DECB
            BNE  DR_COPYNAME
            LDX  DR_OLDLBA
            LDY  #DOSBUF
            JSR  BLKWRITE
            ANDCC #$FE
            RTS
DR_NOTFOUND LDA  #ERR_NOTFOUND
            ORCC #1
            RTS
DR_EXISTS   LDA  #ERR_EXISTS
            ORCC #1
            RTS
;==============================================================================
; The byte-stream layer under the file API: maps a file's byte position to a
; sector via its FAT cluster chain, and caches one sector per open file in
; that file's own buffer. "File sector N" always means the Nth 512-byte sector
; of the file's data (0-based); "cluster index K" is which cluster of the chain
; holds it. Positions and sizes are 16-bit, so N is at most 127.
;==============================================================================
; IN: CUR_SLOT, LOC_N = file sector index, LOC_EXT = 0 (the sector must already
; be part of the chain) or 1 (allocate/link clusters as needed). OUT: carry
; clear + D = that sector's LBA; carry set + A = error. Remembers the cluster
; it lands on (fslot.cacheidx/cacheclus) so sequential access doesn't re-walk
; the chain from the start. Trashes A, B, X, Y (and DOSBUF via the FAT).
;------------------------------------------------------------------------------
LOCATE_SECTOR
            LDA  LOC_N
            LDB  SPCSHIFT
LS_SHIFT    TSTB
            BEQ  LS_SHDONE
            LSRA
            DECB
            BRA  LS_SHIFT
LS_SHDONE   STA  LOC_K                ; cluster index holding the sector
            LDA  LOC_N
            ANDA SPCMASK
            STA  LOC_SIC              ; sector within that cluster
            LDX  CUR_SLOT
            LDD  fslot.cacheclus,X
            BEQ  LS_FROMSTART
            LDA  fslot.cacheidx,X
            CMPA LOC_K
            BHI  LS_FROMSTART         ; cache is already past the target
            STA  LOC_J
            LDD  fslot.cacheclus,X
            STD  LOC_C
            BRA  LS_WALK
LS_FROMSTART
            CLR  LOC_J
            LDD  fslot.startclus,X
            BNE  LS_SETSTART
            TST  LOC_EXT              ; an empty file has no cluster yet
            BEQ  LS_NOSECT
            JSR  ALLOC_CLUSTER        ; claim the file's first cluster
            BCS  LS_NOSPACE
            LDX  CUR_SLOT             ; ALLOC_CLUSTER trashed X
            STD  fslot.startclus,X
LS_SETSTART STD  LOC_C
LS_WALK     LDA  LOC_J
            CMPA LOC_K
            BEQ  LS_FOUND
            LDD  LOC_C
            JSR  NEXT_CLUSTER         ; D = the next cluster in the chain
            CMPD #$FFF8
            BLO  LS_ADVANCE
            TST  LOC_EXT              ; the chain ends before the target
            BEQ  LS_NOSECT
            JSR  ALLOC_CLUSTER        ; extend it: claim a new cluster ...
            BCS  LS_NOSPACE
            STD  LOC_NEW
            STD  SETVAL
            LDD  LOC_C
            JSR  SET_FAT_ENTRY        ; ... and link the old last one to it
            LDD  LOC_NEW
LS_ADVANCE  STD  LOC_C
            INC  LOC_J
            BRA  LS_WALK
LS_FOUND    LDX  CUR_SLOT
            LDA  LOC_J
            STA  fslot.cacheidx,X
            LDD  LOC_C
            STD  fslot.cacheclus,X
            JSR  CLUS_TO_LBA          ; D = the cluster's first sector
            STD  LOC_TMP
            CLRA
            LDB  LOC_SIC
            ADDD LOC_TMP
            ANDCC #$FE
            RTS
LS_NOSECT   LDA  #ERR_IOERR           ; not part of the file's chain
            ORCC #1
            RTS
LS_NOSPACE  LDA  #ERR_NOSPACE
            ORCC #1
            RTS
;------------------------------------------------------------------------------
; Writes CUR_SLOT's buffer back to disk if it's been modified. OUT: carry
; clear on success; carry set + A = error. Trashes A, B, X, Y.
;------------------------------------------------------------------------------
FLUSH_SLOT  LDX  CUR_SLOT
            TST  fslot.dirty,X
            BEQ  FL_OK
            LDA  fslot.bufsec,X
            STA  LOC_N
            CLR  LOC_EXT              ; a dirty sector was allocated when loaded
            JSR  LOCATE_SECTOR
            BCS  FL_RET
            LDX  CUR_SLOT
            LDY  fslot.bufptr,X
            TFR  D,X                  ; X = LBA
            JSR  BLKWRITE
            BCS  FL_IOERR
            LDX  CUR_SLOT
            CLR  fslot.dirty,X
FL_OK       ANDCC #$FE
FL_RET      RTS
FL_IOERR    LDA  #ERR_IOERR
            ORCC #1
            RTS
;------------------------------------------------------------------------------
; Zeros every byte of CUR_SLOT's buffer. Trashes A, X, Y, W.
;------------------------------------------------------------------------------
ZERO_SLOTBUF
            LDX  CUR_SLOT
            LDX  fslot.bufptr,X
            CLR  ,X
            TFR  X,Y
            LDW  #512
            TFM  X,Y+
            RTS
;------------------------------------------------------------------------------
; Right after a sector is loaded into CUR_SLOT's buffer: if it's the sector
; that holds end-of-file, zeros the buffer from EOF onward. Bytes past EOF on
; disk are stale leftovers, and this keeps them from surfacing as data when
; something later writes beyond the old end (seek + write). IN: SEL_N = the
; sector just loaded. Trashes A, B, X, Y, W.
;------------------------------------------------------------------------------
ZERO_TAIL   LDX  CUR_SLOT
            LDA  fslot.size,X
            LSRA                      ; size >> 9: the sector holding EOF
            CMPA SEL_N
            BNE  ZT_DONE
            LDD  fslot.size,X
            ANDA #1                   ; D = size & 511 = where EOF falls in it
            STD  ZT_OFS
            BEQ  ZT_DONE              ; EOF exactly on a boundary: no tail
            LDW  #512
            SUBW ZT_OFS               ; W = bytes from EOF to the end
            LDD  ZT_OFS
            ADDD fslot.bufptr,X
            TFR  D,X
            CLR  ,X
            TFR  X,Y
            TFM  X,Y+
ZT_DONE     RTS
;------------------------------------------------------------------------------
; Makes file sector A the one in CUR_SLOT's buffer, for READING (it must
; already exist). Flushes the previous sector first if it was modified. OUT:
; carry clear on success; carry set + A = error. Trashes A, B, X, Y, W.
;------------------------------------------------------------------------------
SEL_READ    STA  SEL_N
            LDX  CUR_SLOT
            CMPA fslot.bufsec,X
            BEQ  SEL_OK
            JSR  FLUSH_SLOT
            BCS  SEL_RET
            LDA  SEL_N
            STA  LOC_N
            CLR  LOC_EXT
            JSR  LOCATE_SECTOR
            BCS  SEL_RET
            LDX  CUR_SLOT
            LDY  fslot.bufptr,X
            TFR  D,X
            JSR  BLKREAD
            BCS  SEL_IOERR
            LDX  CUR_SLOT
            LDA  SEL_N
            STA  fslot.bufsec,X
            JSR  ZERO_TAIL
SEL_OK      ANDCC #$FE
SEL_RET     RTS
SEL_IOERR   LDX  CUR_SLOT
            LDA  #$FF
            STA  fslot.bufsec,X       ; the buffer's contents are no good
            LDA  #ERR_IOERR
            ORCC #1
            RTS
;------------------------------------------------------------------------------
; Makes file sector A the one in CUR_SLOT's buffer, for WRITING. A sector that
; already holds data is loaded (so a partial write doesn't lose the rest); a
; sector wholly past EOF is claimed and starts zeroed -- and any whole sectors
; between the old EOF and it are written out as zeros, so a seek-and-write
; past the end never exposes stale disk contents. OUT: as SEL_READ.
;------------------------------------------------------------------------------
SEL_WRITE   STA  SEL_N
            LDX  CUR_SLOT
            CMPA fslot.bufsec,X
            LBEQ SEW_OK
            JSR  FLUSH_SLOT
            LBCS SEW_RET
            LDX  CUR_SLOT
            LDA  fslot.size,X
            LSRA
            STA  SEW_AS               ; size >> 9 ...
            LDA  fslot.size,X
            ANDA #1
            ORA  fslot.size+1,X       ; ... nonzero if size & 511 <> 0
            BEQ  SEW_NOROUND
            INC  SEW_AS               ; SEW_AS = sectors holding data
SEW_NOROUND LDA  SEL_N
            CMPA SEW_AS
            BHS  SEW_BEYOND
            STA  LOC_N                ; the sector already holds data: load it
            CLR  LOC_EXT
            JSR  LOCATE_SECTOR
            LBCS SEW_RET
            LDX  CUR_SLOT
            LDY  fslot.bufptr,X
            TFR  D,X
            JSR  BLKREAD
            LBCS SEW_IOERR
            LDX  CUR_SLOT
            LDA  SEL_N
            STA  fslot.bufsec,X
            JSR  ZERO_TAIL
            BRA  SEW_OK
SEW_BEYOND  LDX  CUR_SLOT             ; wholly past EOF: the buffer is scratch
            LDA  #$FF                 ; (zeroed) from here on
            STA  fslot.bufsec,X
            JSR  ZERO_SLOTBUF
            LDA  SEW_AS
            STA  SEW_S
SEW_GAP     LDA  SEW_S
            CMPA SEL_N
            BHS  SEW_TARGET
            STA  LOC_N                ; a gap sector: allocate it, write zeros
            LDA  #1
            STA  LOC_EXT
            JSR  LOCATE_SECTOR
            LBCS SEW_RET
            LDX  CUR_SLOT
            LDY  fslot.bufptr,X
            TFR  D,X
            JSR  BLKWRITE
            LBCS SEW_IOERR
            INC  SEW_S
            BRA  SEW_GAP
SEW_TARGET  LDA  SEL_N
            STA  LOC_N
            LDA  #1
            STA  LOC_EXT
            JSR  LOCATE_SECTOR        ; make sure the target sector exists
            LBCS SEW_RET
            LDX  CUR_SLOT
            LDA  SEL_N
            STA  fslot.bufsec,X       ; buffer is still all zeros
SEW_OK      ANDCC #$FE
SEW_RET     RTS
SEW_IOERR   LDX  CUR_SLOT
            LDA  #$FF
            STA  fslot.bufsec,X
            LDA  #ERR_IOERR
            ORCC #1
            RTS
;------------------------------------------------------------------------------
; IN: CUR_SLOT. OUT: carry clear + A = the byte at the file position, which
; advances; carry set + A = ERR_EOF at/after the end (or another error).
; Allowed in read and update modes.
;------------------------------------------------------------------------------
FILE_GETBYTE
            LDX  CUR_SLOT
            LDA  fslot.mode,X
            BEQ  GB_MODEOK
            CMPA #FOPEN_UPDATE
            BNE  GB_BADMODE
GB_MODEOK   LDD  fslot.pos,X
            CMPD fslot.size,X
            BHS  GB_EOF
            LDA  fslot.pos,X          ; high byte of pos, halved = sector index
            LSRA
            JSR  SEL_READ
            BCS  GB_RET
            LDX  CUR_SLOT
            LDD  fslot.pos,X
            ANDA #1                   ; D = offset within the sector
            ADDD fslot.bufptr,X
            TFR  D,Y
            LDA  ,Y
            PSHS A
            LDD  fslot.pos,X
            ADDD #1
            STD  fslot.pos,X
            PULS A
            ANDCC #$FE
GB_RET      RTS
GB_EOF      LDA  #ERR_EOF
            ORCC #1
            RTS
GB_BADMODE  LDA  #ERR_BADMODE
            ORCC #1
            RTS
;------------------------------------------------------------------------------
; IN: CUR_SLOT, A = the byte. Writes it at the file position (which advances,
; growing the file if it's past the end). OUT: carry clear on success; carry set
; + A = error. Allowed in write, append and update modes. The largest file is
; 65535 bytes.
;------------------------------------------------------------------------------
FILE_PUTBYTE
            STA  PB_BYTE
            LDX  CUR_SLOT
            LDA  fslot.mode,X
            BEQ  PB_BADMODE           ; read-only
            LDD  fslot.pos,X
            CMPD #$FFFF
            BEQ  PB_FULL
            LDA  fslot.pos,X
            LSRA
            JSR  SEL_WRITE
            BCS  PB_RET
            LDX  CUR_SLOT
            LDD  fslot.pos,X
            ANDA #1
            ADDD fslot.bufptr,X
            TFR  D,Y
            LDA  PB_BYTE
            STA  ,Y
            LDA  #1
            STA  fslot.dirty,X
            LDD  fslot.pos,X
            ADDD #1
            STD  fslot.pos,X
            CMPD fslot.size,X
            BLS  PB_NOGROW
            STD  fslot.size,X         ; wrote past the old end: the file grew
PB_NOGROW   ANDCC #$FE
PB_RET      RTS
PB_BADMODE  LDA  #ERR_BADMODE
            ORCC #1
            RTS
PB_FULL     LDA  #ERR_NOSPACE
            ORCC #1
            RTS
;------------------------------------------------------------------------------
BASICNAME   FCC  "BASIC   COM"      ; 8.3 name, space-padded, no dot
MSG_NOBASIC FCC  "BASIC.COM not found on disk"
            FCB  LF,CR,0
;------------------------------------------------------------------------------
DOSBUF        RMB  512
RESSEC        RMB  2
SECPERCLUS    RMB  1
SECPERCLUS16  RMB  2
NUMFATS       RMB  1
FATCNT        RMB  1
MULCNT        RMB  1
ROOTENTCNT    RMB  2
SECPERFAT     RMB  2
TOTALSEC      RMB  2
TOTALCLUS     RMB  2
MAXCLUS       RMB  2
FATLBA        RMB  2
ROOTLBA       RMB  2
ROOTDIRSEC    RMB  2
DATALBA       RMB  2
CURCLUS       RMB  2
TMPD          RMB  2
RDLBA         RMB  2
DESTPTR       RMB  2
FATSECLBA_CUR RMB  2
LFECLUS       RMB  2
LFEOFS        RMB  2
CTLCLUS       RMB  2
ACCLUS        RMB  2
FCCLUS        RMB  2
FCNEXT        RMB  2
SETVAL        RMB  2
FDNAME        RMB  2
FDLBA         RMB  2
FDSECLEFT     RMB  2
FOUND_LBA     RMB  2
FOUND_OFS     RMB  2
FOUND_CLUSTER RMB  2
FOUND_SIZE    RMB  2
FOUND_SIZEHI  RMB  2
FSLOTS        RMB  NSLOTS*sizeof{fslot}
OPEN_NAME     RMB  2
OPEN_MODE     RMB  1
OPEN_SLOTIDX  RMB  1
OPEN_SLOTPTR  RMB  2
CUR_SLOT      RMB  2
RL_DEST       RMB  2
RL_MAX        RMB  2
RL_COUNT      RMB  2
WL_SRC        RMB  2
WL_LEN        RMB  2
WL_I          RMB  2
FGBTMP        RMB  2
DC_DIROFS     RMB  2
DC_SIZE       RMB  2
DIRLBA_CUR    RMB  2
DIRSECLEFT    RMB  2
DIRENTIDX     RMB  1
DIRDEST       RMB  2
RENAME_NEW    RMB  2
DR_OLDLBA     RMB  2
DR_OLDOFS     RMB  2
SPCSHIFT      RMB  1        ; log2(sectors per cluster)
SPCMASK       RMB  1        ; sectors per cluster - 1
CNO_IDX       RMB  1
DC_CLUS       RMB  2
DC_STATUS     RMB  1
FP_BYTE       RMB  1
IO_BUF        RMB  2
IO_LEN        RMB  2
IO_CNT        RMB  2
SK_POS        RMB  2
LOC_N         RMB  1        ; LOCATE_SECTOR arguments/scratch
LOC_EXT       RMB  1
LOC_K         RMB  1
LOC_SIC       RMB  1
LOC_J         RMB  1
LOC_C         RMB  2
LOC_NEW       RMB  2
LOC_TMP       RMB  2
SEL_N         RMB  1        ; SEL_READ/SEL_WRITE scratch
SEW_AS        RMB  1
SEW_S         RMB  1
ZT_OFS        RMB  2
PB_BYTE       RMB  1
; Per-file sector buffers: NSLOTS x 512 bytes. RMB only (no bytes in
; dos.bin), and last, so nothing after it is affected by its size.
SLOTBUFS      RMB  NSLOTS*512
;------------------------------------------------------------------------------
; End of dos.asm
;------------------------------------------------------------------------------
