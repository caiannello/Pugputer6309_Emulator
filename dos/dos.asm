;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 DOS
;    FILE: dos.asm
;
; Loaded by bios/sdcard.asm's SD_BOOT_TRY from the FAT16 volume's reserved
; sectors (not ROM -- this is disk payload, assembled to a flat raw binary
; and written there by simulator/tools/mkdiskimg.cpp) into RAM at DOS_LOAD
; (bios/defines.d, shared by the BIOS's loader and this ORG, so it can't
; drift; it just has to be above the BIOS's RAM, which test_bios_layout checks).
;
; Two jobs, both against the same FAT16 volume (BPB fields parsed once at
; boot into resident variables both share):
;
; 1. Boot-time: find "BASIC.COM" in the root directory, walk its cluster
;    chain loading it to $C000, jump to BASIC_ENTRY.
; 2. Resident file API (see the B_* DOS calls in bios/defines.d): SD_BOOT_TRY
;    passes the address of the BIOS's DOS call table (JT_DOS) in Y; right
;    before jumping to BASIC, DOS copies its DOS_ENTRIES table there, so the
;    routines below stay reachable through the BIOS's SWI2 calls for as long as
;    programs run. DOS's own RAM footprint (code, per-file sector buffers,
;    variables) sits entirely below basic309's WORKBASE, which BASIC never
;    touches, so nothing needs to relocate for this to work -- DOS simply never
;    gets overwritten. If DOS's footprint grows, raise WORKBASE in
;    basic309/exbasrom309.asm to stay above its last byte.
;
; Files are byte streams with a position: sequential read, write (create or
; truncate), append, and update (read/write/seek in place). Up to NSLOTS files
; can be open at once, each with its own 512-byte sector buffer. Files live in
; a tree of directories: paths use "/" as the separator, a leading "/" names
; the root, and there is one system-wide current directory (CWDCLUS). Names are
; 8.3 (no long filenames); a directory is the root (a fixed run of sectors) or
; a cluster chain like any file.
;
; Files are capped at 64KB-1 for now (the API takes 32-bit sizes and positions
; -- a larger value is ERR_TOOBIG -- and the on-disk size field is the real
; 32-bit FAT16 field, but only its low 16 bits are used). Assumes 512-byte
; sectors throughout (mkdiskimg.cpp always uses that) and a power-of-two
; sectors-per-cluster (FAT16 requires it).
;------------------------------------------------------------------------------
    INCLUDE defines.d
;------------------------------------------------------------------------------
    ORG  DOS_LOAD       ; where the BIOS loads and starts us (defines.d)
;------------------------------------------------------------------------------
BASIC_ENTRY   equ $C000   ; basic309's fixed entry: a JMP RESVEC at the start of its image
;------------------------------------------------------------------------------
NSLOTS      equ DOS_NFILES  ; open files at once (defines.d). Callers may hold up to
                            ; NSLOTS-1 of them and still have a slot free for LOAD/SAVE.
NDIRH       equ DOS_NDIRS   ; directory scans open at once
PATHMAX     equ 64          ; longest absolute path B_GETCWD can build
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
; One open directory scan (B_OPENDIR/B_READDIR): the DS_* iteration state
; (see DS_START below) saved between calls, plus the next entry to look at.
dhandle     STRUCT
inuse       rmb 1
dir         rmb 2        ; the directory's first cluster (0 = root)
cur         rmb 2        ; cluster the scan is in
sic         rmb 1        ; sector within that cluster
lba         rmb 2        ; the sector being read
left        rmb 2        ; root only: sectors left, counting the current one
idx         rmb 1        ; next entry (0..15) in that sector
            ENDS
;------------------------------------------------------------------------------
DOS_START   STY  JT_BASE        ; the BIOS's call table (see SD_BOOT_TRY)
            LDX  #0             ; LBA 0: the boot sector
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
            LDX  #DHANDLES
            CLR  ,X
            LDY  #DHANDLES
            LDW  #NDIRH*sizeof{dhandle}
            TFM  X,Y+
            LDD  #0
            STD  CWDCLUS        ; the current directory starts at the root
            STD  FD_DIR
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

            ; Find BASIC.COM (in the root) and load its cluster chain to $C000.
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

            ; Install the resident file API in the BIOS's DOS call table, in
            ; function-code order, then hand off. Never returns.
ALLDONE     LDX  #DOS_ENTRIES
            LDY  JT_BASE
            LDW  #NUM_DOS_JT*2
            TFM  X+,Y+
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
; Writes the FAT sector in DOSBUF (the one LOAD_FAT_ENTRY loaded, at
; FATSECLBA_CUR) back to disk -- to EVERY copy of the FAT, so the second one
; never falls behind the first. OUT: carry as the last write left it. Trashes
; A, B, D, X, Y.
;------------------------------------------------------------------------------
WRITE_FAT   LDX  FATSECLBA_CUR
            LDY  #DOSBUF
            JSR  BLKWRITE
            BCS  WF_RET
            LDA  NUMFATS
            CMPA #2
            BLO  WF_OK
            LDD  FATSECLBA_CUR
            ADDD SECPERFAT        ; the same sector in the second FAT
            TFR  D,X
            LDY  #DOSBUF
            JSR  BLKWRITE
            RTS
WF_OK       ANDCC #$FE
WF_RET      RTS
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
            JSR  WRITE_FAT
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
            JSR  WRITE_FAT
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
            JSR  WRITE_FAT
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
; Directory sector iteration. A directory is either the root (a fixed run of
; ROOTDIRSEC sectors from ROOTLBA) or a subdirectory (a cluster chain like any
; file's). One sector at a time is held in DOSBUF; DS_* say which.
;
; IN: D = the directory's first cluster (0 = root). OUT: carry clear + its
; first sector loaded in DOSBUF; carry set + A = error. Trashes A, B, X, Y.
;------------------------------------------------------------------------------
DS_START    STD  DS_DIR
            STD  DS_CUR
            CLR  DS_SIC
            LDD  DS_DIR
            BNE  DSS_SUB
            LDD  ROOTLBA
            STD  DS_LBA
            LDD  ROOTDIRSEC
            STD  DS_LEFT
            BRA  DS_LOAD
DSS_SUB     JSR  DS_SETLBA
DS_LOAD     LDX  DS_LBA           ; (re)reads the current sector
            LDY  #DOSBUF
            JSR  BLKREAD
            BCS  DSL_ERR
            RTS                   ; carry clear
DSL_ERR     LDA  #ERR_IOERR
            ORCC #1
            RTS
; DS_LBA = the LBA of sector DS_SIC of cluster DS_CUR.
DS_SETLBA   LDD  DS_CUR
            JSR  CLUS_TO_LBA
            STD  DS_TMP
            CLRA
            LDB  DS_SIC
            ADDD DS_TMP
            STD  DS_LBA
            RTS
;------------------------------------------------------------------------------
; Advances to the directory's next sector and loads it. OUT: carry clear on
; success; carry set + A = ERR_EOF past the last sector (or another error).
;------------------------------------------------------------------------------
DS_NEXT     LDD  DS_DIR
            BNE  DSN_SUB
            LDD  DS_LEFT          ; the root: a fixed number of sectors
            SUBD #1
            STD  DS_LEFT
            BEQ  DSN_END
            LDD  DS_LBA
            ADDD #1
            STD  DS_LBA
            BRA  DS_LOAD
DSN_SUB     LDA  DS_SIC
            INCA
            CMPA SECPERCLUS
            BHS  DSN_NEXTCLUS
            STA  DS_SIC
            JSR  DS_SETLBA
            BRA  DS_LOAD
DSN_NEXTCLUS
            LDD  DS_CUR
            JSR  NEXT_CLUSTER
            CMPD #$FFF8
            BHS  DSN_END
            STD  DS_CUR
            CLR  DS_SIC
            JSR  DS_SETLBA
            BRA  DS_LOAD
DSN_END     LDA  #ERR_EOF
            ORCC #1
            RTS
;------------------------------------------------------------------------------
; IN: X = pointer to an 11-byte name (space-padded 8.3, no dot); FD_DIR = the
; directory to search (first cluster, 0 = root). OUT: carry clear if found
; (FOUND_LBA/OFS/CLUSTER/SIZE/SIZEHI/ATTR set, the entry's sector still in
; DOSBUF); carry set + A = ERR_NOTFOUND (or an I/O error). Skips deleted
; entries and volume labels. Trashes A, B, D, X, Y.
;------------------------------------------------------------------------------
FIND_DIRENT STX  FDNAME
            CLR  FD_MODE
            BRA  FD_GO
;------------------------------------------------------------------------------
; The same search, but for the subdirectory entry whose first cluster is D (used
; to find a directory's own name from its parent).
;------------------------------------------------------------------------------
FIND_BYCLUS STD  FD_TARGET
            LDA  #1
            STA  FD_MODE
FD_GO       LDD  FD_DIR
            JSR  DS_START
            LBCS FD_RET
FD_ENTS     LDX  #DOSBUF
            LDB  #16
FD_ENTLOOP  LDA  ,X
            BEQ  FD_NOTFOUND      ; $00: no more entries in this directory
            CMPA #$E5
            BEQ  FD_NEXTENT
            LDA  11,X
            BITA #$08             ; a volume label (or long-name piece): skip
            BNE  FD_NEXTENT
            TST  FD_MODE
            BNE  FD_BYC
            PSHS B,X
            LDB  #11
            LDY  FDNAME
FD_CMP      LDA  ,X+
            CMPA ,Y+
            BNE  FD_NOMATCH
            DECB
            BNE  FD_CMP
            PULS B,X              ; X = start of this 32-byte entry
            BRA  FD_MATCH
FD_NOMATCH  PULS B,X
FD_NEXTENT  LEAX 32,X
            DECB
            BNE  FD_ENTLOOP
            JSR  DS_NEXT
            BCC  FD_ENTS
            CMPA #ERR_EOF
            BEQ  FD_NOTFOUND
            ORCC #1               ; a real error: A says which
            RTS
FD_BYC      BITA #ATTR_DIR
            BEQ  FD_NEXTENT
            PSHS B
            LDA  27,X
            LDB  26,X
            CMPD FD_TARGET
            PULS B
            BNE  FD_NEXTENT
FD_MATCH    LDD  DS_LBA
            STD  FOUND_LBA
            TFR  X,D
            SUBD #DOSBUF
            STD  FOUND_OFS        ; 0..480 -- doesn't fit in 1 byte
            LDA  27,X
            LDB  26,X
            STD  FOUND_CLUSTER
            LDA  29,X
            LDB  28,X
            STD  FOUND_SIZE
            LDA  31,X
            LDB  30,X
            STD  FOUND_SIZEHI     ; nonzero = a file this DOS can't fully handle
            LDA  11,X
            STA  FOUND_ATTR
            ANDCC #$FE
            RTS
FD_NOTFOUND LDA  #ERR_NOTFOUND
            ORCC #1
FD_RET      RTS
;------------------------------------------------------------------------------
; FD_DIR = a directory. Finds a free entry (first byte $00=never used or
; $E5=deleted); if the directory is full, a subdirectory grows by a cluster (the
; root is fixed-size). OUT: carry clear + FOUND_LBA/FOUND_OFS = the free slot;
; carry set + A = ERR_NOSPACE (root full / disk full) or an I/O error. Trashes
; A, B, D, X, Y.
;------------------------------------------------------------------------------
FIND_FREE_DIRENT
            LDD  FD_DIR
            JSR  DS_START
            BCS  FFD_RET
FFD_ENTS    LDX  #DOSBUF
            LDB  #16
FFD_ENTLOOP LDA  ,X
            BEQ  FFD_GOTIT
            CMPA #$E5
            BEQ  FFD_GOTIT
            LEAX 32,X
            DECB
            BNE  FFD_ENTLOOP
            JSR  DS_NEXT
            BCC  FFD_ENTS
            CMPA #ERR_EOF
            BNE  FFD_ERR          ; a real I/O error
            LDD  FD_DIR           ; no free slot anywhere
            BEQ  FFD_FULL         ; the root can't grow
            JMP  EXTEND_DIR       ; a subdirectory can
FFD_GOTIT   LDD  DS_LBA
            STD  FOUND_LBA
            TFR  X,D
            SUBD #DOSBUF
            STD  FOUND_OFS
            ANDCC #$FE
            RTS
FFD_FULL    LDA  #ERR_NOSPACE
FFD_ERR     ORCC #1
FFD_RET     RTS
;------------------------------------------------------------------------------
; Grows the subdirectory the last DS_START/DS_NEXT scan ran off the end of (its
; last cluster is DS_CUR) by one zeroed cluster. OUT: carry clear + FOUND_LBA/
; FOUND_OFS = the first entry of the new cluster; carry set + A = error.
;------------------------------------------------------------------------------
EXTEND_DIR  JSR  ALLOC_CLUSTER    ; D = a free cluster, already marked end-of-chain
            BCC  ED_GOT
            LDA  #ERR_NOSPACE
            RTS                   ; carry still set
ED_GOT      STD  ED_NEW
            STD  SETVAL
            LDD  DS_CUR
            JSR  SET_FAT_ENTRY    ; link the old last cluster to it
            LDD  ED_NEW
            JSR  ZERO_CLUSTER
            BCS  ED_RET
            LDD  ED_NEW
            JSR  CLUS_TO_LBA
            STD  FOUND_LBA
            LDD  #0
            STD  FOUND_OFS
            ANDCC #$FE
ED_RET      RTS
;------------------------------------------------------------------------------
; IN: D = a cluster. Writes zeros over every sector of it (a new directory's
; unused entries must read as $00). OUT: carry clear, or set + A = error.
; Trashes A, B, X, Y, W and DOSBUF.
;------------------------------------------------------------------------------
ZERO_CLUSTER
            STD  ZC_CLUS
            JSR  CLEAR_DOSBUF
            LDD  ZC_CLUS
            JSR  CLUS_TO_LBA
            STD  ZC_LBA
            LDA  SECPERCLUS
            STA  ZC_CNT
ZC_LOOP     LDX  ZC_LBA
            LDY  #DOSBUF
            JSR  BLKWRITE
            BCS  ZC_ERR
            LDD  ZC_LBA
            ADDD #1
            STD  ZC_LBA
            DEC  ZC_CNT
            BNE  ZC_LOOP
            ANDCC #$FE
            RTS
ZC_ERR      LDA  #ERR_IOERR
            ORCC #1
            RTS
;==============================================================================
; Paths. A path is a NUL-terminated string of components separated by "/".
; NEXT_COMPONENT takes them one at a time; RESOLVE_PATH walks all but the last
; through the directory tree and reports what the last one is.
;==============================================================================
; Characters that can't be in an 8.3 name (besides controls, space and DEL).
NC_BADCHARS FCB  $22,$2A,$2B,$2C,$2F,$3A,$3B,$3C,$3D,$3E,$3F,$5B,$5C,$5D,$7C,0
DOT_NAME    FCC  ".          "    ; the "." and ".." directory entries' names
DOTDOT_NAME FCC  "..         "
;------------------------------------------------------------------------------
; IN: A = a name character. OUT: carry clear + A upper-cased if it is valid in
; an 8.3 name; carry set if not. Preserves B, X, Y.
;------------------------------------------------------------------------------
NC_CHAR     CMPA #'a'
            BLO  NCC_CHK
            CMPA #'z'
            BHI  NCC_CHK
            SUBA #$20
NCC_CHK     CMPA #$21
            BLO  NCC_BAD
            CMPA #$7E
            BHI  NCC_BAD
            PSHS U
            LDU  #NC_BADCHARS
NCC_LOOP    TST  ,U
            BEQ  NCC_OK
            CMPA ,U+
            BNE  NCC_LOOP
            PULS U
NCC_BAD     ORCC #1
            RTS
NCC_OK      PULS U
            ANDCC #$FE
            RTS
;------------------------------------------------------------------------------
; Parses the next component of the path at PP_PTR (leading "/"s skipped) and
; advances PP_PTR past it. OUT: carry clear + PP_KIND = 0 (no more components),
; 1 (a name: PP_NAME = its 11-byte 8.3 form, upper-cased), 2 ("."), or 3
; (".."); carry set + A = ERR_BADPATH (a name that isn't valid 8.3).
; Trashes A, B, X, Y.
;------------------------------------------------------------------------------
NEXT_COMPONENT
            LDX  PP_PTR
NC_SKIP     LDA  ,X
            CMPA #'/'
            BNE  NC_START
            LEAX 1,X
            BRA  NC_SKIP
NC_START    TSTA
            BNE  NC_PARSE
            STX  PP_PTR
            CLR  PP_KIND
            ANDCC #$FE
            RTS
NC_PARSE    LDY  #PP_NAME         ; blank the 11-byte name
            LDB  #11
            LDA  #' '
NC_BLANK    STA  ,Y+
            DECB
            BNE  NC_BLANK
            LDA  ,X
            CMPA #'.'
            BNE  NC_NAME0
            LDA  1,X              ; "." or ".."?
            BEQ  NC_DOT
            CMPA #'/'
            BEQ  NC_DOT
            CMPA #'.'
            BNE  NC_NAME0         ; ".X...": no base name -> rejected below
            LDA  2,X
            BEQ  NC_DOTDOT
            CMPA #'/'
            BEQ  NC_DOTDOT
            BRA  NC_BAD
NC_DOT      LEAX 1,X
            LDA  #2
            BRA  NC_KIND
NC_DOTDOT   LEAX 2,X
            LDA  #3
NC_KIND     STX  PP_PTR
            STA  PP_KIND
            ANDCC #$FE
            RTS
NC_NAME0    LDY  #PP_NAME
            LDB  #8
NC_NAME     LDA  ,X
            BEQ  NC_END
            CMPA #'/'
            BEQ  NC_END
            CMPA #'.'
            BEQ  NC_EXT
            LBSR NC_CHAR
            BCS  NC_BAD
            TSTB
            BEQ  NC_BAD           ; a base name longer than 8
            STA  ,Y+
            LEAX 1,X
            DECB
            BRA  NC_NAME
NC_EXT      LEAX 1,X              ; past the dot
            LDY  #PP_NAME+8
            LDB  #3
NC_EXTL     LDA  ,X
            BEQ  NC_END
            CMPA #'/'
            BEQ  NC_END
            CMPA #'.'
            BEQ  NC_BAD           ; a second dot
            LBSR NC_CHAR
            BCS  NC_BAD
            TSTB
            BEQ  NC_BAD           ; an extension longer than 3
            STA  ,Y+
            LEAX 1,X
            DECB
            BRA  NC_EXTL
NC_END      LDA  PP_NAME
            CMPA #' '
            BEQ  NC_BAD           ; ".EXT": no base name
            STX  PP_PTR
            LDA  #1
            STA  PP_KIND
            ANDCC #$FE
            RTS
NC_BAD      LDA  #ERR_BADPATH
            ORCC #1
            RTS
;------------------------------------------------------------------------------
; IN: X = a path. Walks every component but the last through the directory
; tree (starting at the root if the path begins with "/", else at the current
; directory). OUT: carry clear + RP_DIR = the directory containing the last
; component, RP_KIND = what it is (0 = the path had no components, i.e. it is
; RP_DIR itself; 1 = a name, RP_NAME = its 11-byte form; 2 = "."; 3 = ".."); or
; carry set + A = ERR_NOTFOUND / ERR_NOTDIR / ERR_BADPATH / an I/O error.
; Trashes A, B, D, X, Y.
;------------------------------------------------------------------------------
RESOLVE_PATH
            STX  PP_PTR
            LDA  ,X
            CMPA #'/'
            BEQ  RP_ROOT
            LDD  CWDCLUS
            BRA  RP_SET
RP_ROOT     LDD  #0
RP_SET      STD  RP_DIR
RP_LOOP     JSR  NEXT_COMPONENT
            BCS  RP_RET
            LDA  PP_KIND
            STA  RP_KIND
            BEQ  RP_DONE          ; no (more) components
            CMPA #1
            BNE  RP_PEEK
            LDX  #PP_NAME         ; remember the name: the last one is the answer
            LDY  #RP_NAME
            LDW  #11
            TFM  X+,Y+
RP_PEEK     LDX  PP_PTR           ; is this the last component?
RP_PK       LDA  ,X
            CMPA #'/'
            BNE  RP_PK2
            LEAX 1,X
            BRA  RP_PK
RP_PK2      TSTA
            BEQ  RP_DONE          ; yes: report it, don't enter it
            LDA  RP_KIND          ; no: it must be a directory to walk into
            CMPA #2
            BEQ  RP_LOOP          ; "." -- stay where we are
            CMPA #3
            BEQ  RP_UP
            LDD  RP_DIR
            STD  FD_DIR
            LDX  #RP_NAME
            JSR  FIND_DIRENT
            BCS  RP_RET
            LDA  FOUND_ATTR
            ANDA #ATTR_DIR
            BEQ  RP_NOTDIR
            LDD  FOUND_CLUSTER
            STD  RP_DIR
            BRA  RP_LOOP
RP_UP       JSR  PARENT_OF_RPDIR
            BCC  RP_LOOP
            RTS
RP_DONE     ANDCC #$FE
            RTS
RP_NOTDIR   LDA  #ERR_NOTDIR
            ORCC #1
RP_RET      RTS
;------------------------------------------------------------------------------
; RP_DIR := its parent directory (the root's parent is the root). OUT: carry
; clear, or set + A = error. Trashes A, B, D, X, Y.
;------------------------------------------------------------------------------
PARENT_OF_RPDIR
            LDD  RP_DIR
            BEQ  PR_OK
            STD  FD_DIR
            LDX  #DOTDOT_NAME
            JSR  FIND_DIRENT
            BCS  PR_RET
            LDD  FOUND_CLUSTER    ; 0 when the parent is the root
            STD  RP_DIR
PR_OK       ANDCC #$FE
PR_RET      RTS
;------------------------------------------------------------------------------
; IN: X = a path that must name a directory. OUT: carry clear + D = that
; directory's first cluster (0 = root); carry set + A = error (ERR_NOTDIR if it
; names a file). "" and "." are the current directory.
;------------------------------------------------------------------------------
RESOLVE_DIR JSR  RESOLVE_PATH
            BCS  RD_RET
            LDA  RP_KIND
            BEQ  RD_CUR
            CMPA #2
            BEQ  RD_CUR
            CMPA #3
            BEQ  RD_UP
            LDD  RP_DIR
            STD  FD_DIR
            LDX  #RP_NAME
            JSR  FIND_DIRENT
            BCS  RD_RET
            LDA  FOUND_ATTR
            ANDA #ATTR_DIR
            BEQ  RD_NOTDIR
            LDD  FOUND_CLUSTER
            ANDCC #$FE
            RTS
RD_UP       JSR  PARENT_OF_RPDIR
            BCS  RD_RET
RD_CUR      LDD  RP_DIR
            ANDCC #$FE
            RTS
RD_NOTDIR   LDA  #ERR_NOTDIR
            ORCC #1
RD_RET      RTS

;==============================================================================
; Resident file API -- see DOS_ENTRIES at the end (installed in the BIOS's DOS call
; table). Each of these is a plain subroutine (RTS, carry=error), called by
; bios/sdcard.asm's BIOS_DOS, which owns finishing the SWI2 response.
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
; IN: X = a path, A = mode (FOPEN_READ/WRITE/APPEND/UPDATE). OUT: carry clear +
; A = file handle (0..NSLOTS-1); carry set + A = error code.
;   READ    must exist; read and seek only.
;   WRITE   created, or truncated if it exists; write only.
;   APPEND  created if missing; existing contents kept, writes go at the end.
;   UPDATE  created if missing; existing contents kept; read, write and seek.
; A file that's already open (in any slot) can't be opened again; a directory
; can't be opened as a file (ERR_ISDIR).
;------------------------------------------------------------------------------
DOS_OPEN    STA  OPEN_MODE
            CMPA #FOPEN_UPDATE
            BLS  OPEN_MODE_OK
            LDA  #ERR_BADMODE
            ORCC #1
            RTS
OPEN_MODE_OK
            JSR  RESOLVE_PATH
            BCS  OPEN_RET
            LDA  RP_KIND
            CMPA #1
            BEQ  OPEN_ISNAME
OPEN_ISDIR  LDA  #ERR_ISDIR       ; "/", "." or ".." (or an empty path)
            ORCC #1
OPEN_RET    RTS
OPEN_ISNAME CLR  OPEN_SLOTIDX
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
            LDD  RP_DIR
            STD  FD_DIR
            LDX  #RP_NAME
            STX  OPEN_NAME
            JSR  FIND_DIRENT
            BCC  OPEN_FOUND
            CMPA #ERR_NOTFOUND
            BEQ  OPEN_MISSING
            ORCC #1               ; an I/O error: A says which
            RTS
OPEN_MISSING
            LDA  OPEN_MODE
            BEQ  OPEN_NOTFOUND_READ
            JSR  FIND_FREE_DIRENT
            BCS  OPEN_RET         ; A = why (directory/disk full, I/O)
            LDD  #0               ; brand-new empty file: no clusters yet
            STD  FOUND_CLUSTER
            STD  FOUND_SIZE
            STD  FOUND_SIZEHI
            BRA  OPEN_WRITE_ENTRY
OPEN_NOTFOUND_READ
            LDA  #ERR_NOTFOUND
            ORCC #1
            RTS
OPEN_IOERR  LDA  #ERR_IOERR
            ORCC #1
            RTS
OPEN_TOOBIG LDA  #ERR_BADMODE
            ORCC #1
            RTS
OPEN_FOUND  LDA  FOUND_ATTR
            ANDA #ATTR_DIR
            BNE  OPEN_ISDIR
            JSR  CHECK_NOT_OPEN
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
; IN: B = handle. Finalizes: a file opened for writing has its buffered sector
; flushed and its directory entry updated with the final first cluster and size;
; a file opened for reading just frees its slot. The slot is freed even if a
; write-back fails (that error is still reported). Trashes A, B, D, X, Y.
;------------------------------------------------------------------------------
DOS_CLOSE   JSR  SLOT_CHECK
            BCS  DC_RET
            CLR  DC_STATUS            ; 0 = no error so far
            LDX  CUR_SLOT
            LDA  fslot.mode,X
            BEQ  DC_FREE              ; read mode: nothing to write back
            JSR  SYNC_SLOT
            BCC  DC_FREE
            STA  DC_STATUS            ; remember it, but finish closing anyway
DC_FREE     LDX  CUR_SLOT
            CLR  fslot.inuse,X
            LDA  DC_STATUS
            BEQ  DC_OK
            ORCC #1
            RTS
DC_OK       ANDCC #$FE
DC_RET      RTS
;------------------------------------------------------------------------------
; IN: CUR_SLOT, an open writable file. Writes its buffered sector out and updates
; its directory entry (first cluster and size), leaving it open. OUT: carry
; clear on success; carry set + A = the first error. Trashes A, B, D, X, Y.
;------------------------------------------------------------------------------
SYNC_SLOT   CLR  SY_STATUS
            JSR  FLUSH_SLOT
            BCC  SY_DIRENT
            STA  SY_STATUS            ; remember it, but still update the entry
SY_DIRENT   LDX  CUR_SLOT
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
            BCS  SY_IOERR
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
            BCS  SY_IOERR
            LDA  SY_STATUS
            BEQ  SY_OK
            ORCC #1                   ; the flush error, now that the entry is done
            RTS
SY_OK       ANDCC #$FE
            RTS
SY_IOERR    LDA  #ERR_IOERR
            ORCC #1
            RTS
;------------------------------------------------------------------------------
; IN: B = handle, or $FF for every open file. Writes out buffered data and updates
; the directory entries, so the data survives a crash from here on. OUT: carry
; clear, or set + A = an error. Trashes A, B, D, X, Y.
;------------------------------------------------------------------------------
DOS_FFLUSH  CMPB #$FF
            BEQ  FF_ALL
            JSR  SLOT_CHECK
            BCS  FF_RET
            LDX  CUR_SLOT
            LDA  fslot.mode,X
            BEQ  FF_OK                ; read-only: nothing to write
            JMP  SYNC_SLOT
FF_ALL      CLR  FF_IDX
FF_LOOP     LDA  FF_IDX
            CMPA #NSLOTS
            BHS  FF_OK
            JSR  SLOT_ADDR
            TST  fslot.inuse,X
            BEQ  FF_NEXT
            LDA  fslot.mode,X
            BEQ  FF_NEXT
            STX  CUR_SLOT
            JSR  SYNC_SLOT
            BCS  FF_RET
FF_NEXT     INC  FF_IDX
            BRA  FF_LOOP
FF_OK       ANDCC #$FE
FF_RET      RTS
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
; IN: B = handle, A = whence (SEEK_SET/CUR/END), X:Y = 32-bit offset (X = high
; word). Read and update modes only. OUT: carry clear + X:Y = the new position;
; carry set + A = ERR_BADMODE / ERR_TOOBIG (beyond what this DOS handles, 64KB-1).
;------------------------------------------------------------------------------
DOS_FSEEK   STA  SK_WHENCE
            STX  SK_HI
            STY  SK_LO
            JSR  SLOT_CHECK
            BCS  SK_RET
            LDX  CUR_SLOT
            LDA  fslot.mode,X
            BEQ  SK_MODE_OK           ; read
            CMPA #FOPEN_UPDATE
            BEQ  SK_MODE_OK
SK_BADMODE  LDA  #ERR_BADMODE
            ORCC #1
            RTS
SK_MODE_OK  LDD  SK_HI
            BNE  SK_TOOBIG            ; anything over 64KB-1
            LDA  SK_WHENCE
            BEQ  SK_SET
            CMPA #SEEK_CUR
            BEQ  SK_CUR
            CMPA #SEEK_END
            BNE  SK_BADMODE           ; not a whence
            LDD  fslot.size,X
            BRA  SK_ADD
SK_CUR      LDD  fslot.pos,X
SK_ADD      ADDD SK_LO
            BCS  SK_TOOBIG
            BRA  SK_STORE
SK_SET      LDD  SK_LO
SK_STORE    STD  fslot.pos,X
            TFR  D,Y
            LDX  #0
            ANDCC #$FE
            RTS
SK_TOOBIG   LDA  #ERR_TOOBIG
            ORCC #1
SK_RET      RTS
;------------------------------------------------------------------------------
; IN: B = handle, X = dest buffer (16 bytes: size 4, position 4, attr 1, open
; mode 1, 6 reserved; 32-bit values big-endian). OUT: carry clear, buffer filled.
;------------------------------------------------------------------------------
DOS_FSTAT   STX  FS_DEST
            JSR  SLOT_CHECK
            BCS  FS_RET
            LDX  CUR_SLOT
            LDY  FS_DEST
            LDD  #0
            STD  ,Y                   ; size: high word ...
            LDD  fslot.size,X
            STD  2,Y                  ; ... low word
            LDD  #0
            STD  4,Y                  ; position: the same
            LDD  fslot.pos,X
            STD  6,Y
            LDA  #$20                 ; ARCHIVE
            STA  8,Y
            LDA  fslot.mode,X
            STA  9,Y
            LDD  #0
            STD  10,Y
            STD  12,Y
            STD  14,Y
            ANDCC #$FE
FS_RET      RTS
;------------------------------------------------------------------------------
; IN: X = path, Y = dest buffer (the same 16 bytes as DOS_FSTAT; position 0, open
; mode $FF). Works for files and directories (a directory: size 0, attr $10).
;------------------------------------------------------------------------------
DOS_STAT    STY  FS_DEST
            JSR  RESOLVE_PATH
            BCS  ST_RET
            LDA  RP_KIND
            CMPA #1
            BEQ  ST_NAME
            LDD  #0                   ; the root, ".", ".." or "": a directory
            STD  FOUND_SIZE
            STD  FOUND_SIZEHI
            LDA  #ATTR_DIR
            STA  FOUND_ATTR
            BRA  ST_FILL
ST_NAME     LDD  RP_DIR
            STD  FD_DIR
            LDX  #RP_NAME
            JSR  FIND_DIRENT
            BCS  ST_RET
ST_FILL     LDY  FS_DEST
            LDD  FOUND_SIZEHI
            STD  ,Y
            LDD  FOUND_SIZE
            STD  2,Y
            LDD  #0
            STD  4,Y
            STD  6,Y
            LDA  FOUND_ATTR
            STA  8,Y
            LDA  #$FF
            STA  9,Y
            LDD  #0
            STD  10,Y
            STD  12,Y
            STD  14,Y
            ANDCC #$FE
ST_RET      RTS
;------------------------------------------------------------------------------
; Directory scans. Each open scan has its own dhandle holding the DS_* state, so
; several directories can be read at once (and files opened between reads).
;------------------------------------------------------------------------------
; IN: A = scan index. OUT: X = its dhandle. Trashes A, B, D.
DH_ADDR     TFR  A,B
            LDA  #sizeof{dhandle}
            MUL
            LDX  #DHANDLES
            LEAX D,X
            RTS
; IN: B = a scan handle. OUT: carry clear + CUR_DH = its dhandle; carry set +
; A = ERR_BADDEV if it isn't open. Trashes A, B, D, X.
DH_CHECK    CMPB #NDIRH
            BHS  DHC_BAD
            TFR  B,A
            JSR  DH_ADDR
            TST  dhandle.inuse,X
            BEQ  DHC_BAD
            STX  CUR_DH
            ANDCC #$FE
            RTS
DHC_BAD     LDA  #ERR_BADDEV
            ORCC #1
            RTS
; IN: X = a dhandle. Saves the DS_* scan state and DIRENTIDX into it.
DH_SAVE     LDD  DS_DIR
            STD  dhandle.dir,X
            LDD  DS_CUR
            STD  dhandle.cur,X
            LDA  DS_SIC
            STA  dhandle.sic,X
            LDD  DS_LBA
            STD  dhandle.lba,X
            LDD  DS_LEFT
            STD  dhandle.left,X
            LDA  DIRENTIDX
            STA  dhandle.idx,X
            RTS
;------------------------------------------------------------------------------
; IN: X = the path of a directory ("" or "." = the current one). OUT: carry clear
; + A = a scan handle (0..NDIRH-1); carry set + A = error (ERR_NOTFOUND,
; ERR_NOTDIR, ERR_NOSLOT, ...).
;------------------------------------------------------------------------------
DOS_OPENDIR JSR  RESOLVE_DIR
            BCS  OD_RET
            STD  OD_CLUS
            CLR  OD_IDX
OD_FIND     LDA  OD_IDX
            CMPA #NDIRH
            BHS  OD_NOSLOT
            JSR  DH_ADDR
            TST  dhandle.inuse,X
            BEQ  OD_GOT
            INC  OD_IDX
            BRA  OD_FIND
OD_GOT      STX  OD_PTR
            LDD  OD_CLUS
            JSR  DS_START             ; positions on the first sector (and checks it reads)
            BCS  OD_RET
            CLR  DIRENTIDX
            LDX  OD_PTR
            LDA  #1
            STA  dhandle.inuse,X
            JSR  DH_SAVE
            LDA  OD_IDX
            ANDCC #$FE
            RTS
OD_NOSLOT   LDA  #ERR_NOSLOT
            ORCC #1
OD_RET      RTS
;------------------------------------------------------------------------------
; IN: B = a scan handle, X = dest buffer (16 bytes: 11 name + 1 attr + 4 size,
; big-endian). OUT: carry clear + the next live entry ("." and ".." included;
; deleted entries and volume labels skipped); carry set + A = ERR_EOF when there
; are no more. Trashes A, B, D, X, Y.
;------------------------------------------------------------------------------
DOS_READDIR STX  DIRDEST
            JSR  DH_CHECK
            BCS  RDR_RET
            LDX  CUR_DH
            LDD  dhandle.dir,X
            STD  DS_DIR
            LDD  dhandle.cur,X
            STD  DS_CUR
            LDA  dhandle.sic,X
            STA  DS_SIC
            LDD  dhandle.lba,X
            STD  DS_LBA
            LDD  dhandle.left,X
            STD  DS_LEFT
            LDA  dhandle.idx,X
            STA  DIRENTIDX
            JSR  DS_LOAD              ; the sector we were in
            BCS  RDR_RET
RDR_LOOP    LDB  DIRENTIDX
            CMPB #16
            BLO  RDR_CHECK
            JSR  DS_NEXT
            BCS  RDR_RET              ; A = ERR_EOF after the last sector
            CLR  DIRENTIDX
            BRA  RDR_LOOP
RDR_CHECK   LDA  #32
            MUL                       ; D = DIRENTIDX*32 (max 15*32=480)
            LDX  #DOSBUF
            LEAX D,X                  ; X = this entry
            LDA  ,X
            BEQ  RDR_EOF              ; $00: never used, and neither is anything after
            INC  DIRENTIDX            ; the NEXT call starts after this one
            CMPA #$E5
            BEQ  RDR_LOOP             ; deleted
            LDA  11,X
            BITA #$08
            BNE  RDR_LOOP             ; a volume label
            LDY  DIRDEST
            LDB  #11
RDR_CPNAME  LDA  ,X+
            STA  ,Y+
            DECB
            BNE  RDR_CPNAME           ; X now at offset 11 (the attribute)
            LDA  ,X
            STA  ,Y+
            LEAX 17,X                 ; 11+17 = 28: the little-endian size field
            LDA  3,X                  ; ... stored big-endian
            STA  ,Y+
            LDA  2,X
            STA  ,Y+
            LDA  1,X
            STA  ,Y+
            LDA  ,X
            STA  ,Y
            LDX  CUR_DH
            JSR  DH_SAVE
            ANDCC #$FE
RDR_RET     RTS
RDR_EOF     LDA  #ERR_EOF
            ORCC #1
            RTS
;------------------------------------------------------------------------------
; IN: B = a scan handle. Frees it.
;------------------------------------------------------------------------------
DOS_CLOSEDIR
            JSR  DH_CHECK
            BCS  CD_RET
            LDX  CUR_DH
            CLR  dhandle.inuse,X
            ANDCC #$FE
CD_RET      RTS
;------------------------------------------------------------------------------
; IN: X = a path. Frees the file's cluster chain (if any) and marks its
; directory entry deleted ($E5). OUT: carry clear = deleted; carry set + A =
; ERR_NOTFOUND / ERR_ISDIR (use RMDIR) / ERR_ISOPEN. Trashes A, B, D, X, Y.
;------------------------------------------------------------------------------
DOS_KILL    JSR  RESOLVE_PATH
            BCS  DK_RET
            LDA  RP_KIND
            CMPA #1
            BNE  DK_ISDIR
            LDD  RP_DIR
            STD  FD_DIR
            LDX  #RP_NAME
            JSR  FIND_DIRENT
            BCS  DK_RET
            LDA  FOUND_ATTR
            ANDA #ATTR_DIR
            BNE  DK_ISDIR
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
DK_ISDIR    LDA  #ERR_ISDIR
            ORCC #1
DK_RET      RTS
;------------------------------------------------------------------------------
; IN: X = the OLD path, Y = the NEW name (a single component -- the entry stays
; in its directory). OUT: carry clear = renamed; carry set + A = ERR_NOTFOUND
; (old doesn't exist), ERR_EXISTS (the new name is taken), ERR_ISOPEN (an open
; file), ERR_BADPATH. Works on directories too. Trashes A, B, D, X, Y.
;------------------------------------------------------------------------------
DOS_RENAME  STY  RENAME_NEW
            JSR  RESOLVE_PATH
            LBCS DR_RET
            LDA  RP_KIND
            CMPA #1
            LBNE DR_BAD
            LDD  RP_DIR
            STD  FD_DIR
            LDX  #RP_NAME
            JSR  FIND_DIRENT     ; the old name must already exist
            BCS  DR_RET
            LDA  FOUND_ATTR
            ANDA #ATTR_DIR
            BNE  DR_OLDOK        ; a directory: no open-file check applies
            JSR  CHECK_NOT_OPEN  ; renaming an open file would leave its
            BCC  DR_OLDOK        ; handle pointing at the wrong name
            RTS                  ; carry set, A = ERR_ISOPEN
DR_OLDOK    LDD  FOUND_LBA
            STD  DR_OLDLBA
            LDD  FOUND_OFS
            STD  DR_OLDOFS
            LDX  RENAME_NEW
            STX  PP_PTR
            JSR  NEXT_COMPONENT  ; parse the new name into PP_NAME
            BCS  DR_RET
            LDA  PP_KIND
            CMPA #1
            BNE  DR_BAD
            LDX  PP_PTR
            LDA  ,X
            BNE  DR_BAD          ; nothing may follow it (no "/", no second name)
            LDD  RP_DIR
            STD  FD_DIR
            LDX  #PP_NAME
            JSR  FIND_DIRENT     ; does the NEW name already exist?
            BCC  DR_EXISTS       ; found -- refuse to collide
            CMPA #ERR_NOTFOUND
            BEQ  DR_DO
            ORCC #1              ; an I/O error
            RTS
DR_DO       LDX  DR_OLDLBA
            LDY  #DOSBUF
            JSR  BLKREAD
            BCS  DR_IOERR
            LDD  DR_OLDOFS
            LDX  #DOSBUF
            LEAX D,X
            LDY  #PP_NAME
            LDB  #11
DR_COPYNAME LDA  ,Y+
            STA  ,X+
            DECB
            BNE  DR_COPYNAME
            LDX  DR_OLDLBA
            LDY  #DOSBUF
            JSR  BLKWRITE
            BCS  DR_IOERR
            ANDCC #$FE
            RTS
DR_BAD      LDA  #ERR_BADPATH
            ORCC #1
DR_RET      RTS
DR_EXISTS   LDA  #ERR_EXISTS
            ORCC #1
            RTS
DR_IOERR    LDA  #ERR_IOERR
            ORCC #1
            RTS
;------------------------------------------------------------------------------
; IN: X = the path of a new directory. Creates it (with its "." and ".." entries)
; in the directory the path leads to. OUT: carry clear; carry set + A =
; ERR_EXISTS, ERR_NOTFOUND / ERR_NOTDIR (a missing or non-directory parent),
; ERR_BADPATH, ERR_NOSPACE. Trashes A, B, D, X, Y, W and DOSBUF.
;------------------------------------------------------------------------------
DOS_MKDIR   JSR  RESOLVE_PATH
            BCS  MK_RET
            LDA  RP_KIND
            CMPA #1
            BEQ  MK_NAME
MK_EXISTS   LDA  #ERR_EXISTS         ; "/", ".", "..", "": already there
            ORCC #1
MK_RET      RTS
MK_NAME     LDD  RP_DIR
            STD  FD_DIR
            LDX  #RP_NAME
            JSR  FIND_DIRENT
            BCC  MK_EXISTS
            CMPA #ERR_NOTFOUND
            BEQ  MK_GO
            ORCC #1
            RTS
MK_GO       JSR  FIND_FREE_DIRENT ; a slot for the entry (may grow the parent)
            BCS  MK_RET
            LDD  FOUND_LBA
            STD  MK_LBA
            LDD  FOUND_OFS
            STD  MK_OFS
            JSR  ALLOC_CLUSTER   ; the new directory's own cluster
            LBCS MK_NOSPACE
            STD  MK_CLUS
            JSR  ZERO_CLUSTER    ; every entry of it starts free ...
            BCS  MK_RET
            LDX  #DOSBUF         ; ... except "." (itself) and ".." (the parent;
            LDY  #DOT_NAME       ; cluster 0 when that is the root)
            JSR  COPY_NAME11
            LDA  #ATTR_DIR
            STA  ,X
            LDD  MK_CLUS
            STB  15,X            ; entry offset 26 = 11 (attr) + 15
            STA  16,X
            LDX  #DOSBUF+32
            LDY  #DOTDOT_NAME
            JSR  COPY_NAME11
            LDA  #ATTR_DIR
            STA  ,X
            LDD  RP_DIR
            STB  15,X
            STA  16,X
            LDD  MK_CLUS
            JSR  CLUS_TO_LBA
            TFR  D,X
            LDY  #DOSBUF
            JSR  BLKWRITE
            BCS  MK_IOERR
            LDX  MK_LBA          ; finally, its entry in the parent
            LDY  #DOSBUF
            JSR  BLKREAD
            BCS  MK_IOERR
            LDD  MK_OFS
            LDX  #DOSBUF
            LEAX D,X
            LDY  #RP_NAME
            JSR  COPY_NAME11     ; X now at offset 11
            LDA  #ATTR_DIR
            STA  ,X+
            LDB  #20
MK_ZERO     CLR  ,X+             ; offsets 12..31 (dates, cluster, size)
            DECB
            BNE  MK_ZERO
            LEAX -6,X            ; back to offset 26: the first cluster
            LDD  MK_CLUS
            STB  ,X
            STA  1,X
            LDX  MK_LBA
            LDY  #DOSBUF
            JSR  BLKWRITE
            BCS  MK_IOERR
            ANDCC #$FE
            RTS
MK_NOSPACE  LDA  #ERR_NOSPACE
            ORCC #1
            RTS
MK_IOERR    LDA  #ERR_IOERR
            ORCC #1
            RTS
; IN: Y = source, X = destination. Copies 11 bytes; X is left just past them.
; Trashes A, B, Y.
COPY_NAME11 LDB  #11
CN_LOOP     LDA  ,Y+
            STA  ,X+
            DECB
            BNE  CN_LOOP
            RTS
;------------------------------------------------------------------------------
; IN: X = a directory's path. Removes it if it is empty (only "." and ".."). OUT:
; carry clear; carry set + A = ERR_NOTFOUND / ERR_NOTDIR / ERR_NOTEMPTY /
; ERR_ISOPEN (it is the current directory) / ERR_BADPATH.
;------------------------------------------------------------------------------
DOS_RMDIR   JSR  RESOLVE_PATH
            LBCS RM_RET
            LDA  RP_KIND
            CMPA #1
            LBNE RM_BAD
            LDD  RP_DIR
            STD  FD_DIR
            LDX  #RP_NAME
            JSR  FIND_DIRENT
            LBCS RM_RET
            LDA  FOUND_ATTR
            ANDA #ATTR_DIR
            BEQ  RM_NOTDIR
            LDD  FOUND_CLUSTER
            STD  RM_CLUS
            CMPD CWDCLUS
            BEQ  RM_BUSY         ; can't remove the directory we are in
            LDD  FOUND_LBA
            STD  RM_LBA
            LDD  FOUND_OFS
            STD  RM_OFS
            LDD  RM_CLUS
            JSR  DS_START
            BCS  RM_RET
RM_SCAN     LDX  #DOSBUF
            LDB  #16
RM_ENT      LDA  ,X
            BEQ  RM_EMPTY        ; $00: nothing more in the directory
            CMPA #$E5
            BEQ  RM_NEXT         ; deleted
            CMPA #'.'
            BEQ  RM_NEXT         ; "." and ".."
            LDA  #ERR_NOTEMPTY
            ORCC #1
            RTS
RM_NEXT     LEAX 32,X
            DECB
            BNE  RM_ENT
            JSR  DS_NEXT
            BCC  RM_SCAN
            CMPA #ERR_EOF
            BEQ  RM_EMPTY
            ORCC #1
            RTS
RM_EMPTY    LDD  RM_CLUS
            JSR  FREE_CHAIN
            LDX  RM_LBA
            LDY  #DOSBUF
            JSR  BLKREAD
            BCS  RM_IOERR
            LDD  RM_OFS
            LDX  #DOSBUF
            LEAX D,X
            LDA  #$E5
            STA  ,X
            LDX  RM_LBA
            LDY  #DOSBUF
            JSR  BLKWRITE
            BCS  RM_IOERR
            ANDCC #$FE
            RTS
RM_BAD      LDA  #ERR_BADPATH
            ORCC #1
RM_RET      RTS
RM_NOTDIR   LDA  #ERR_NOTDIR
            ORCC #1
            RTS
RM_BUSY     LDA  #ERR_ISOPEN
            ORCC #1
            RTS
RM_IOERR    LDA  #ERR_IOERR
            ORCC #1
            RTS
;------------------------------------------------------------------------------
; IN: X = a directory's path. Makes it the current directory. OUT: carry clear;
; carry set + A = ERR_NOTFOUND / ERR_NOTDIR.
;------------------------------------------------------------------------------
DOS_CHDIR   JSR  RESOLVE_DIR
            BCS  CH_RET
            STD  CWDCLUS
            ANDCC #$FE
CH_RET      RTS
;------------------------------------------------------------------------------
; IN: X = dest buffer, Y = its size. Writes the current directory as an absolute
; path ("/" for the root, else "/A/B") plus a NUL. Built from the disk itself: at
; each level the directory's ".." entry names its parent, and the parent's entry
; pointing back at it names it. OUT: carry clear; carry set + A = ERR_TOOBIG (the
; path doesn't fit, or is longer than PATHMAX).
;------------------------------------------------------------------------------
DOS_GETCWD  STX  GC_DEST
            STY  GC_SIZE
            LDX  #PATHBUF+PATHMAX
            STX  GC_P
            CLR  ,X               ; the terminating NUL; names are prepended before it
            LDD  CWDCLUS
            STD  GC_CUR
GC_LOOP     LDD  GC_CUR
            LBEQ GC_DONE          ; reached the root
            STD  FD_DIR
            LDX  #DOTDOT_NAME
            JSR  FIND_DIRENT      ; this directory's ".." entry -> its parent
            LBCS GC_RET
            LDD  FOUND_CLUSTER
            STD  GC_PAR
            STD  FD_DIR
            LDD  GC_CUR
            JSR  FIND_BYCLUS      ; the parent's entry for it -> its name
            LBCS GC_RET
            LDX  #DOSBUF
            LDD  FOUND_OFS
            LEAX D,X              ; X = that entry
            LDY  #GC_NAME
            LDA  #'/'
            STA  ,Y+
            LDB  #8
GC_BASE     LDA  ,X
            CMPA #' '
            BEQ  GC_BASEDONE
            STA  ,Y+
            LEAX 1,X
            DECB
            BNE  GC_BASE
GC_BASEDONE LDX  #DOSBUF
            LDD  FOUND_OFS
            LEAX D,X
            LEAX 8,X              ; the extension field
            LDA  ,X
            CMPA #' '
            BEQ  GC_NAMEDONE
            LDA  #'.'
            STA  ,Y+
            LDB  #3
GC_EXT      LDA  ,X
            CMPA #' '
            BEQ  GC_NAMEDONE
            STA  ,Y+
            LEAX 1,X
            DECB
            BNE  GC_EXT
GC_NAMEDONE TFR  Y,D
            SUBD #GC_NAME
            STB  GC_LEN           ; "/NAME.EXT" is at most 13 bytes
            LDD  GC_P
            SUBB GC_LEN
            SBCA #0
            CMPD #PATHBUF
            BLO  GC_TOOBIG
            STD  GC_P
            LDX  #GC_NAME
            LDY  GC_P
            LDB  GC_LEN
GC_CP       LDA  ,X+
            STA  ,Y+
            DECB
            BNE  GC_CP
            LDD  GC_PAR
            STD  GC_CUR
            LBRA GC_LOOP
GC_DONE     LDX  GC_P
            CMPX #PATHBUF+PATHMAX
            BNE  GC_COPY
            LEAX -1,X             ; the root itself: just "/"
            LDA  #'/'
            STA  ,X
            STX  GC_P
GC_COPY     LDD  #PATHBUF+PATHMAX+1
            SUBD GC_P             ; bytes to copy, counting the NUL
            CMPD GC_SIZE
            BHI  GC_TOOBIG
            LDX  GC_P
            LDY  GC_DEST
GC_CL       LDA  ,X+
            STA  ,Y+
            BNE  GC_CL
            ANDCC #$FE
            RTS
GC_TOOBIG   LDA  #ERR_TOOBIG
            ORCC #1
GC_RET      RTS
;------------------------------------------------------------------------------
; -> A = the API version (DOS_API_VERSION).
;------------------------------------------------------------------------------
DOS_VERSION LDA  #DOS_API_VERSION
            ANDCC #$FE
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
; The resident API's entry points, in function-code order (bios/defines.d,
; B_FOPEN_NAME upward): ALLDONE copies this table into the BIOS's JT_DOS.
;------------------------------------------------------------------------------
DOS_ENTRIES FDB  DOS_OPEN       ; $13 B_FOPEN_NAME
            FDB  DOS_READLINE   ; $14 B_READLINE
            FDB  DOS_WRITELINE  ; $15 B_WRITELINE
            FDB  DOS_CLOSE      ; $16 B_FCLOSE_NAME
            FDB  DOS_OPENDIR    ; $17 B_OPENDIR
            FDB  DOS_READDIR    ; $18 B_READDIR
            FDB  DOS_KILL       ; $19 B_KILL_NAME
            FDB  DOS_RENAME     ; $1A B_RENAME_NAME
            FDB  DOS_FGETC      ; $1B B_FGETC
            FDB  DOS_FPUTC      ; $1C B_FPUTC
            FDB  DOS_FREAD      ; $1D B_FREAD
            FDB  DOS_FWRITE     ; $1E B_FWRITE
            FDB  DOS_FSEEK      ; $1F B_FSEEK_NAME
            FDB  DOS_FSTAT      ; $20 B_FSTAT_NAME
            FDB  DOS_FFLUSH     ; $21 B_FFLUSH
            FDB  DOS_MKDIR      ; $22 B_MKDIR
            FDB  DOS_RMDIR      ; $23 B_RMDIR
            FDB  DOS_CHDIR      ; $24 B_CHDIR
            FDB  DOS_GETCWD     ; $25 B_GETCWD
            FDB  DOS_CLOSEDIR   ; $26 B_CLOSEDIR
            FDB  DOS_STAT       ; $27 B_STAT
            FDB  DOS_VERSION    ; $28 B_DOS_VERSION
DOS_ENTRIES_END
    IFNE (DOS_ENTRIES_END-DOS_ENTRIES)-2*NUM_DOS_JT
    ERROR "DOS_ENTRIES must have one entry per DOS call (see defines.d)"
    ENDC
;------------------------------------------------------------------------------
DOSBUF        RMB  512
JT_BASE       RMB  2        ; the BIOS's DOS call table (from SD_BOOT_TRY, in Y)
CWDCLUS       RMB  2        ; the current directory's first cluster (0 = root)
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
; Directory search / iteration (FIND_DIRENT, DS_*)
FDNAME        RMB  2
FD_DIR        RMB  2        ; the directory a search runs in (first cluster; 0 = root)
FD_MODE       RMB  1        ; 0 = by name, 1 = by first cluster
FD_TARGET     RMB  2
FOUND_LBA     RMB  2
FOUND_OFS     RMB  2
FOUND_CLUSTER RMB  2
FOUND_SIZE    RMB  2
FOUND_SIZEHI  RMB  2
FOUND_ATTR    RMB  1
DS_DIR        RMB  2
DS_CUR        RMB  2
DS_SIC        RMB  1
DS_LBA        RMB  2
DS_LEFT       RMB  2
DS_TMP        RMB  2
ED_NEW        RMB  2
ZC_CLUS       RMB  2
ZC_LBA        RMB  2
ZC_CNT        RMB  1
; Path parsing (NEXT_COMPONENT, RESOLVE_PATH)
PP_PTR        RMB  2
PP_KIND       RMB  1
PP_NAME       RMB  11
RP_DIR        RMB  2
RP_KIND       RMB  1
RP_NAME       RMB  11
FSLOTS        RMB  NSLOTS*sizeof{fslot}
DHANDLES      RMB  NDIRH*sizeof{dhandle}
OPEN_NAME     RMB  2
OPEN_MODE     RMB  1
OPEN_SLOTIDX  RMB  1
OPEN_SLOTPTR  RMB  2
CUR_SLOT      RMB  2
CUR_DH        RMB  2
RL_DEST       RMB  2
RL_MAX        RMB  2
RL_COUNT      RMB  2
WL_SRC        RMB  2
WL_LEN        RMB  2
WL_I          RMB  2
FGBTMP        RMB  2
DC_DIROFS     RMB  2
DC_SIZE       RMB  2
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
SY_STATUS     RMB  1
FF_IDX        RMB  1
FP_BYTE       RMB  1
IO_BUF        RMB  2
IO_LEN        RMB  2
IO_CNT        RMB  2
SK_WHENCE     RMB  1
SK_HI         RMB  2
SK_LO         RMB  2
FS_DEST       RMB  2
OD_CLUS       RMB  2
OD_IDX        RMB  1
OD_PTR        RMB  2
MK_LBA        RMB  2
MK_OFS        RMB  2
MK_CLUS       RMB  2
RM_CLUS       RMB  2
RM_LBA        RMB  2
RM_OFS        RMB  2
GC_DEST       RMB  2
GC_SIZE       RMB  2
GC_P          RMB  2
GC_CUR        RMB  2
GC_PAR        RMB  2
GC_LEN        RMB  1
GC_NAME       RMB  14
PATHBUF       RMB  PATHMAX+1
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
