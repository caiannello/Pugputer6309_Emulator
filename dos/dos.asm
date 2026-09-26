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
; 1. Boot-time: start the shell (/CMD/SHELL.COM, or /SHELL.COM on a disk laid
;    out before /CMD), or failing that BASIC (/CMD/BASIC.COM or /BASIC.COM), as a
;    program (B_EXEC).
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
; Sizes, positions and block numbers are 32-bit: files run to 4GB (a FAT16 volume
; itself holds at most 2GB) and volumes may be any size FAT16 allows (the BIOS
; block calls take 32-bit LBAs). One FAT sector is cached (FATBUF), and free
; clusters are searched from where the last search ended, so big files don't
; cost a disk read per cluster. Assumes 512-byte sectors throughout
; (mkdiskimg.cpp always uses that) and a power-of-two sectors-per-cluster (FAT16
; requires it).
;
; Metadata updates are ordered so that a crash (power cut) between two disk
; writes leaves the volume usable: at worst clusters are LOST (marked used but
; in no file), never shared by two files or reachable after being freed --
; a new directory is written before its entry, a deleted entry's mark goes to
; disk before its chain is freed, a truncated file's empty entry before the old
; chain is freed, and a grown directory's new cluster is zeroed before being linked.
;------------------------------------------------------------------------------
    INCLUDE defines.d
;------------------------------------------------------------------------------
    ORG  DOS_LOAD       ; where the BIOS loads and starts us (defines.d)
;------------------------------------------------------------------------------
ARGMAX      equ  79         ; longest command tail kept (B_EXEC / B_ARGS)
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
size        rmb 4        ; file size in bytes (32-bit, big-endian)
pos         rmb 4        ; current byte position (32-bit, big-endian)
dirlba      rmb 4        ; sector holding this file's directory entry (32-bit LBA)
dirofs      rmb 2        ; byte offset of the entry within that sector --
                         ; 2 bytes: with 16 entries/sector, the 9th-16th
                         ; entry's offset (256-480) doesn't fit in 1 byte
bufptr      rmb 2        ; this slot's 512-byte data buffer (in SLOTBUFS)
bufsec      rmb 3        ; file sector index held in that buffer (24 bits);
                         ; first byte $FF = none
dirty       rmb 1        ; buffer modified since it was loaded
cacheidx    rmb 2        ; cluster index (within the file) of cacheclus ...
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
lba         rmb 4        ; the sector being read (32-bit LBA)
left        rmb 2        ; root only: sectors left, counting the current one
idx         rmb 1        ; next entry (0..15) in that sector
            ENDS
;------------------------------------------------------------------------------
DOS_START   STY  JT_BASE        ; the BIOS's call table (see SD_BOOT_TRY)
            STS  BOOT_SP        ; programs start (and B_EXIT restarts the shell) on this stack
            LDQ  #0             ; LBA 0: the boot sector
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
            LDD  #$FFFF
            STD  FATBUFSEC      ; no FAT sector cached yet
            CLR  FATDIRTY
            LDD  #2
            STD  ALLOC_HINT     ; the first free-cluster search starts at the start
            LDX  #PATH_DEFAULT
            JSR  DOS_PATH       ; the program search path starts as "/CMD"
            LDA  DOSBUF+15      ; reserved sector count, offset $0E/$0F
            LDB  DOSBUF+14
            STD  RESSEC
            LDA  DOSBUF+16      ; number of FATs, offset $10 (1 byte)
            STA  NUMFATS
            LDA  DOSBUF+18      ; root entry count, offset $11/$12
            LDB  DOSBUF+17
            STD  ROOTENTCNT
            LDA  DOSBUF+23      ; sectors per FAT, offset $16/$17
            LDB  DOSBUF+22
            STD  SECPERFAT

            ; Total sectors (32-bit): the 16-bit field at offset $13 if it is
            ; nonzero, else the 32-bit one at offset $20 (volumes over 65535
            ; sectors). Kept big-endian in TOTALSEC.
            LDD  #0
            STD  TOTALSEC
            LDA  DOSBUF+20
            LDB  DOSBUF+19
            STD  TOTALSEC+2
            BNE  TS_DONE
            LDA  DOSBUF+35
            LDB  DOSBUF+34
            STD  TOTALSEC
            LDA  DOSBUF+33
            LDB  DOSBUF+32
            STD  TOTALSEC+2
TS_DONE

            ; FATLBA = RESSEC (the first FAT starts right after the
            ; reserved sectors).
            LDD  RESSEC
            STD  FATLBA

            ; ROOTLBA = RESSEC + NUMFATS*SECPERFAT (NUMFATS is always a
            ; small integer -- 1 or 2 -- so a counted add-loop is simpler
            ; than a general multiply), as a 32-bit sum. The counter lives in
            ; memory (FATCNT), not in a register that is also part of the
            ; accumulator: a counter in B would be clobbered by the very
            ; arithmetic it is counting.
            LDA  NUMFATS
            STA  FATCNT
            LDD  #0
            LDW  RESSEC         ; Q = the running total, seeded with RESSEC
FATLOOP     TST  FATCNT
            BEQ  FATDONE
            ADDW SECPERFAT
            ADCD #0
            DEC  FATCNT
            BRA  FATLOOP
FATDONE     STQ  ROOTLBA

            ; ROOTDIRSEC = ROOTENTCNT*32/512 = ROOTENTCNT/16 exactly (a
            ; 32-byte entry, 512-byte sector) -- four right shifts of the
            ; 16-bit value instead of a divide.
            LDD  ROOTENTCNT
            LSRD
            LSRD
            LSRD
            LSRD
            STD  ROOTDIRSEC

            ; DATALBA = ROOTLBA + ROOTDIRSEC
            LDQ  ROOTLBA
            ADDW ROOTDIRSEC
            ADCD #0
            STQ  DATALBA

            ; TOTALCLUS = (TOTALSEC - DATALBA) >> SPCSHIFT, capped at what a
            ; FAT16 volume can number ($FFF4 clusters). MAXCLUS = TOTALCLUS+2
            ; (clusters are numbered from 2) is ALLOC_CLUSTER's scan bound, and
            ; is also capped by what the FAT sectors can hold.
            LDA  SPCSHIFT
            STA  MULCNT
            LDQ  TOTALSEC
            SUBW DATALBA+2
            SBCD DATALBA
TCLOOP      TST  MULCNT
            BEQ  TCDONE
            LSRD
            RORW
            DEC  MULCNT
            BRA  TCLOOP
TCDONE      TSTD
            BNE  TC_CAP
            CMPW #$FFF4
            BLS  TC_STORE
TC_CAP      LDW  #$FFF4
TC_STORE    STW  TOTALCLUS
            TFR  W,D
            ADDD #2
            STD  MAXCLUS
            LDD  SECPERFAT      ; entries the FAT can hold: SECPERFAT*256
            TSTA
            BNE  MC_OK          ; 256+ FAT sectors: more than the cap anyway
            TFR  B,A
            CLRB
            CMPD MAXCLUS
            BHS  MC_OK
            STD  MAXCLUS
MC_OK

            ; Install the resident file API in the BIOS's DOS call table, in
            ; function-code order, then start the first program: the shell
            ; (/SHELL.COM), or on a disk without one, BASIC. Never returns.
            LDX  #DOS_ENTRIES
            LDY  JT_BASE
            LDW  #NUM_DOS_JT*2
            TFM  X+,Y+
RUN_STARTUP LDX  #PATH_SHELL     ; /CMD/SHELL.COM ...
            BSR  RS_TRY
            LDX  #PATH_SHELL+4   ; ... else /SHELL.COM (the same name without "/CMD")
            BSR  RS_TRY
            LDX  #PATH_BASIC
            BSR  RS_TRY
            LDX  #PATH_BASIC+4
            BSR  RS_TRY
            LDX  #MSG_NOSHELL
            LDB  #F_STDOUT
            LDA  #B_PUTS
            SWI2
HANG        BRA  HANG           ; nothing else to do -- not resumable
RS_TRY      LDY  #0             ; X = a program to start, with no command tail
            JMP  DOS_EXEC       ; (returns only if it couldn't start it)
;==============================================================================
; Low-level block/FAT/directory primitives, shared by the boot-time loader
; above and the resident file API below.
;==============================================================================
; Q = the 32-bit LBA (D = high word, W = low word), Y = RAM buffer adrs. See
; bios/defines.d's B_BLK_READ32. Y is preserved by SWI2 (interrupt entry stacks
; it, RTI restores it, and the handler never touches that frame slot) so nothing
; here needs to save/restore it manually; Q is NOT preserved. Returns A=status,
; carry=error, same as SWI2 itself always leaves them.
;------------------------------------------------------------------------------
BLKREAD     TFR  W,X            ; the call wants the low word in X, the high in W
            TFR  D,W
            LDA  #B_BLK_READ32
            SWI2
            RTS
;------------------------------------------------------------------------------
BLKWRITE    TFR  W,X
            TFR  D,W
            LDA  #B_BLK_WRITE32
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
; Small helpers for 24-bit (file sector numbers) and 32-bit big-endian values.
;------------------------------------------------------------------------------
; Compares the 3-byte values at X and Y: the flags are those of "CMP [X],[Y]"
; (Z = equal, C = [X] is lower). Trashes A, B.
CMP24       LDA  ,X
            CMPA ,Y
            BNE  C24_RET
            LDD  1,X
            CMPD 1,Y
C24_RET     RTS
; Copies the 3 bytes at X to Y. Trashes A, B.
COPY24      LDA  ,X
            STA  ,Y
            LDD  1,X
            STD  1,Y
            RTS
; Adds 1 to the 3-byte value at X.
INC24       INC  2,X
            BNE  I24_RET
            INC  1,X
            BNE  I24_RET
            INC  ,X
I24_RET     RTS
; The 32-bit value at X, divided by 512 (>> 9), as a 3-byte value at Y: which
; 512-byte sector a byte count or position falls in. Trashes A, B.
SHR9        LDA  ,X
            STA  ,Y
            LDD  1,X
            STD  1,Y
            LSR  ,Y
            ROR  1,Y
            ROR  2,Y
            RTS
;------------------------------------------------------------------------------
; IN: D = cluster number (2 and up). OUT: Q = that cluster's starting LBA (32-bit)
; = DATALBA + ((cluster-2) << SPCSHIFT). CLUS_SIC_TO_LBA adds SICW (a 16-bit
; sector-within-cluster the caller has set) as well. Trashes A, B, X.
;------------------------------------------------------------------------------
CLUS_TO_LBA LDX  #0
            STX  SICW
CLUS_SIC_TO_LBA
            SUBD #2
            TFR  D,W
            LDA  SPCSHIFT
            STA  MULCNT         ; a counter in memory: D and W are busy
            CLRD
CTL_LOOP    TST  MULCNT
            BEQ  CTL_ADD
            ADDR W,W            ; Q <<= 1
            ROLD
            DEC  MULCNT
            BRA  CTL_LOOP
CTL_ADD     ADDW DATALBA+2
            ADCD DATALBA
            ADDW SICW
            ADCD #0
            RTS
;------------------------------------------------------------------------------
; The FAT. One FAT sector at a time is cached in FATBUF (FATBUFSEC = which sector
; of the FAT, $FFFF = none), so walking a file's chain -- usually contiguous, so
; consecutive clusters share a sector -- and scanning for free clusters cost one
; disk read per FAT sector, not one per cluster. Changes are written back (to
; both FAT copies) when another FAT sector is needed and at the COMMIT POINTS
; below, not one disk write per changed entry; the places where the order of disk
; writes matters (see the header) all commit explicitly. WRITE_FAT is the
; "I changed FATBUF" call; FAT_COMMIT does the writing.
;
; IN: D = cluster number. OUT: carry clear + X = pointer into FATBUF at this
; cluster's FAT entry (2 bytes, little-endian); carry set + A = ERR_IOERR.
; Trashes A, B, Y (and the FATBUF contents, when the entry is in another sector).
;------------------------------------------------------------------------------
LOAD_FAT_ENTRY
            STD  LFECLUS
            TFR  A,B            ; the entry's FAT sector: cluster / 256
            CLRA
            STD  LFESEC
            CMPD FATBUFSEC
            BEQ  LFE_HAVE
            JSR  FAT_COMMIT     ; the sector we are leaving may hold changes
            BCS  LFE_RET
            LDD  #0             ; Q = FATLBA + sector
            LDW  FATLBA
            ADDW LFESEC
            ADCD #0
            LDY  #FATBUF
            JSR  BLKREAD
            BCS  LFE_ERR
            LDD  LFESEC
            STD  FATBUFSEC
LFE_HAVE    LDA  LFECLUS+1      ; cluster's low byte
            LDB  #2
            MUL                 ; D = low_byte*2 = byte offset within sector
            LDX  #FATBUF
            LEAX D,X
            ANDCC #$FE
            RTS
LFE_ERR     LDX  #$FFFF
            STX  FATBUFSEC      ; whatever is in FATBUF now is not to be trusted
            LDA  #ERR_IOERR
            ORCC #1
LFE_RET     RTS
;------------------------------------------------------------------------------
; "FATBUF was changed" -- callers use this after modifying an entry. It only
; marks the cached sector; FAT_COMMIT writes it. Always succeeds (carry clear).
;------------------------------------------------------------------------------
WRITE_FAT   LDA  #1
            STA  FATDIRTY
            ANDCC #$FE
            RTS
;------------------------------------------------------------------------------
; A commit point: writes FATBUF back to disk if it has changes -- to EVERY copy of
; the FAT, so the second one never falls behind the first. OUT: carry clear, or
; set + A = ERR_IOERR. Trashes A, B, D, X, Y, W.
;------------------------------------------------------------------------------
FAT_COMMIT  TST  FATDIRTY
            BNE  FCM_WRITE
            ANDCC #$FE
            RTS
FCM_WRITE   CLR  FATDIRTY
            LDD  #0             ; Q = FATLBA + FATBUFSEC
            LDW  FATLBA
            ADDW FATBUFSEC
            ADCD #0
            STQ  WF_LBA
            LDY  #FATBUF
            JSR  BLKWRITE
            BCS  WF_ERR
            LDA  NUMFATS
            CMPA #2
            BLO  WF_OK
            LDQ  WF_LBA
            ADDW SECPERFAT      ; the same sector in the second FAT
            ADCD #0
            LDY  #FATBUF
            JSR  BLKWRITE
            BCS  WF_ERR
WF_OK       ANDCC #$FE
            RTS
WF_ERR      LDX  #$FFFF
            STX  FATBUFSEC      ; disk and cache may now disagree: re-read next time
            LDA  #ERR_IOERR
            ORCC #1
            RTS
;------------------------------------------------------------------------------
; IN: D = cluster number. OUT: carry clear + D = next cluster in the chain
; ($FFF8-$FFFF = end of chain); carry set (D = $FFFF, so a caller that ignores
; the carry sees an end of chain) on an I/O error. Trashes A, B, X, Y.
;------------------------------------------------------------------------------
NEXT_CLUSTER
            JSR  LOAD_FAT_ENTRY
            BCS  NXC_ERR
            LDA  1,X             ; FAT entries are little-endian too
            LDB  ,X
            ANDCC #$FE
            RTS
NXC_ERR     LDD  #$FFFF
            ORCC #1
            RTS
;------------------------------------------------------------------------------
; IN: D = cluster to modify. SETVAL (set by the caller first) = the new
; value. OUT: carry clear, or set + A = ERR_IOERR. Trashes A, B, X, Y.
;------------------------------------------------------------------------------
SET_FAT_ENTRY
            JSR  LOAD_FAT_ENTRY
            BCS  SFE_RET
            LDD  SETVAL
            STB  ,X              ; little-endian, same reasoning as
            STA  1,X             ; OPEN_WRITE_INIT's cluster/size writes
            JMP  WRITE_FAT
SFE_RET     RTS
;------------------------------------------------------------------------------
; Finds a free (zero) FAT entry, searching from where the last search ended (ALLOC_HINT)
; to MAXCLUS and then, if needed, from cluster 2 back up to the start point -- so
; a run of allocations doesn't rescan the clusters already handed out.
; OUT: carry clear + D = the free cluster number, its FAT entry already
; written as end-of-chain ($FFFF) so it's claimed; carry set + A = ERR_NOSPACE
; (disk full) or ERR_IOERR. Trashes A, B, X, Y.
;------------------------------------------------------------------------------
ALLOC_CLUSTER
            LDD  ALLOC_HINT
            CMPD MAXCLUS
            BLO  AC_START
            LDD  #2
AC_START    STD  ACCLUS
            STD  ACSTART
            CLR  ACWRAP
AC_LOOP     LDD  ACCLUS
            TST  ACWRAP
            BEQ  AC_NOTWRAPPED
            CMPD ACSTART        ; second lap: stop where we started
            BHS  AC_FULL
AC_NOTWRAPPED
            CMPD MAXCLUS
            BLO  AC_CHECK
            TST  ACWRAP         ; the end of the FAT: lap once from the start
            BNE  AC_FULL
            INC  ACWRAP
            LDD  #2
            STD  ACCLUS
            BRA  AC_LOOP
AC_CHECK    JSR  LOAD_FAT_ENTRY
            BCS  AC_RET
            LDA  1,X
            LDB  ,X
            TSTD                 ; (LDB alone would test only the low byte)
            BNE  AC_NEXT
            LDD  #$FFFF          ; both bytes equal -- byte order is moot
            STD  ,X
            JSR  WRITE_FAT
            BCS  AC_RET
            LDD  ACCLUS
            ADDD #1
            STD  ALLOC_HINT      ; the next search starts just after this one
            LDD  ACCLUS
            ANDCC #$FE
            RTS
AC_NEXT     LDD  ACCLUS
            ADDD #1
            STD  ACCLUS
            BRA  AC_LOOP
AC_FULL     LDA  #ERR_NOSPACE
            ORCC #1
AC_RET      RTS
;------------------------------------------------------------------------------
; IN: D = starting cluster. Walks the chain, zeroing every FAT entry
; (freeing it). OUT: carry clear, or set + A = ERR_IOERR (part of the chain may
; then stay allocated -- a leak, never a corruption). Trashes A, B, D, X, Y.
;------------------------------------------------------------------------------
FREE_CHAIN  STD  FCCLUS
FC_LOOP     LDD  FCCLUS
            CMPD #$FFF8
            BHS  FC_DONE
            CMPD #2
            BLO  FC_DONE         ; never follow a link to cluster 0/1 (a corrupt chain)
            CMPD ALLOC_HINT
            BHS  FC_NOHINT
            STD  ALLOC_HINT      ; the search should look at what we free
FC_NOHINT   LDD  FCCLUS
            JSR  LOAD_FAT_ENTRY
            BCS  FC_RET
            LDA  1,X
            LDB  ,X
            STD  FCNEXT
            LDD  #0
            STD  ,X
            JSR  WRITE_FAT
            BCS  FC_RET
            LDD  FCNEXT
            STD  FCCLUS
            BRA  FC_LOOP
FC_DONE     JMP  FAT_COMMIT     ; the freed clusters are on disk before we return
FC_RET      RTS
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
            LDQ  ROOTLBA
            STQ  DS_LBA
            LDD  ROOTDIRSEC
            STD  DS_LEFT
            BRA  DS_LOAD
DSS_SUB     JSR  DS_SETLBA
DS_LOAD     LDQ  DS_LBA           ; (re)reads the current sector
            LDY  #DOSBUF
            JSR  BLKREAD
            BCS  DSL_ERR
            RTS                   ; carry clear
DSL_ERR     LDA  #ERR_IOERR
            ORCC #1
            RTS
; DS_LBA = the LBA of sector DS_SIC of cluster DS_CUR.
DS_SETLBA   CLR  SICW
            LDA  DS_SIC
            STA  SICW+1
            LDD  DS_CUR
            JSR  CLUS_SIC_TO_LBA
            STQ  DS_LBA
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
            LDQ  DS_LBA
            ADDW #1
            ADCD #0
            STQ  DS_LBA
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
            BCS  DSL_ERR          ; the FAT couldn't be read
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
; (FOUND_LBA/OFS/CLUSTER/SIZE/ATTR set, the entry's sector still in
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
            LBEQ FD_NOTFOUND      ; $00: no more entries in this directory
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
FD_MATCH    LDQ  DS_LBA
            STQ  FOUND_LBA
            TFR  X,D
            SUBD #DOSBUF
            STD  FOUND_OFS        ; 0..480 -- doesn't fit in 1 byte
            LDA  27,X
            LDB  26,X
            STD  FOUND_CLUSTER
            LDA  31,X             ; the size: 4 bytes, little-endian on disk,
            STA  FOUND_SIZE       ; kept big-endian here
            LDA  30,X
            STA  FOUND_SIZE+1
            LDA  29,X
            STA  FOUND_SIZE+2
            LDA  28,X
            STA  FOUND_SIZE+3
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
FFD_GOTIT   LDQ  DS_LBA
            STQ  FOUND_LBA
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
            BCS  ED_RET           ; A = why (disk full / I/O)
            STD  ED_NEW
            JSR  ZERO_CLUSTER     ; zero it BEFORE linking it in: a crash in between
            BCS  ED_RET           ; loses a cluster, but never leaves a directory
            LDD  ED_NEW           ; that ends in a cluster of garbage entries
            STD  SETVAL
            LDD  DS_CUR
            JSR  SET_FAT_ENTRY    ; link the old last cluster to it
            BCS  ED_RET
            JSR  FAT_COMMIT       ; entries are about to be put in the new cluster
            BCS  ED_RET
            LDD  ED_NEW
            JSR  CLUS_TO_LBA
            STQ  FOUND_LBA
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
            STQ  ZC_LBA
            LDA  SECPERCLUS
            STA  ZC_CNT
ZC_LOOP     LDQ  ZC_LBA
            LDY  #DOSBUF
            JSR  BLKWRITE
            BCS  ZC_ERR
            LDQ  ZC_LBA
            ADDW #1
            ADCD #0
            STQ  ZC_LBA
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
            LDD  fslot.dirlba+2,X
            CMPD FOUND_LBA+2
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
            STD  FOUND_SIZE+2
            STD  OPEN_OLDCLUS
            BRA  OPEN_WRITE_ENTRY
OPEN_NOTFOUND_READ
            LDA  #ERR_NOTFOUND
            ORCC #1
            RTS
OPEN_IOERR  LDA  #ERR_IOERR
            ORCC #1
            RTS
OPEN_FOUND  LDA  FOUND_ATTR
            ANDA #ATTR_DIR
            BNE  OPEN_ISDIR
            JSR  CHECK_NOT_OPEN
            BCC  OPEN_FOUND2
            RTS                       ; carry set, A = ERR_ISOPEN
OPEN_FOUND2 LDA  OPEN_MODE
            BEQ  OPEN_INIT            ; read: directory untouched
            CMPA #FOPEN_WRITE
            BNE  OPEN_INIT            ; append/update keep the contents
            LDD  FOUND_CLUSTER        ; write: truncate. The entry is rewritten as an
            STD  OPEN_OLDCLUS         ; empty file FIRST and the old chain freed after,
            LDD  #0                   ; so a crash in between leaks clusters instead of
            STD  FOUND_CLUSTER        ; leaving an entry that points at freed ones.
            STD  FOUND_SIZE
            STD  FOUND_SIZE+2
OPEN_WRITE_ENTRY
            ; (Re)write this file's directory entry as an empty file: name,
            ; ARCHIVE attribute, then zeros for the rest (dates, cluster, size).
            LDQ  FOUND_LBA
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
            LDQ  FOUND_LBA
            LDY  #DOSBUF
            JSR  BLKWRITE
            BCS  OPEN_IOERR
            LDD  OPEN_OLDCLUS         ; now the old contents' clusters can go
            BEQ  OPEN_INIT
            JSR  FREE_CHAIN
            LBCS OPEN_RET
OPEN_INIT   LDX  OPEN_SLOTPTR
            LDA  #1
            STA  fslot.inuse,X
            LDA  OPEN_MODE
            STA  fslot.mode,X
            LDD  FOUND_CLUSTER
            STD  fslot.startclus,X
            LDQ  FOUND_SIZE
            STQ  fslot.size,X
            LDQ  #0
            STQ  fslot.pos,X
            LDA  OPEN_MODE
            CMPA #FOPEN_APPEND
            BNE  OI_NOAPPEND
            LDQ  FOUND_SIZE           ; append: start at the end
            STQ  fslot.pos,X
OI_NOAPPEND LDQ  FOUND_LBA
            STQ  fslot.dirlba,X
            LDD  FOUND_OFS
            STD  fslot.dirofs,X
            LDA  #$FF
            STA  fslot.bufsec,X       ; nothing cached yet
            CLR  fslot.dirty,X
            LDD  #0
            STD  fslot.cacheidx,X
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
            LDQ  fslot.pos,X
            SUBW #1
            SBCD #0
            STQ  fslot.pos,X
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
SY_DIRENT   JSR  FAT_COMMIT           ; the entry is about to name clusters: their FAT
            BCS  SY_IOERR             ; links go to disk first
            LDX  CUR_SLOT
            LDQ  fslot.dirlba,X
            STQ  SY_LBA
            LDD  fslot.dirofs,X
            STD  DC_DIROFS
            LDQ  fslot.size,X
            STQ  SY_SIZE
            LDD  fslot.startclus,X
            STD  DC_CLUS
            LDQ  SY_LBA
            LDY  #DOSBUF
            JSR  BLKREAD
            BCS  SY_IOERR
            LDD  DC_DIROFS
            LDX  #DOSBUF
            LEAX D,X                  ; X = this file's directory entry
            LDD  DC_CLUS              ; little-endian, same reasoning as
            STB  26,X                 ; DOS_OPEN's directory writes
            STA  27,X
            LDA  SY_SIZE+3            ; the size: 4 bytes, little-endian on disk
            STA  28,X
            LDA  SY_SIZE+2
            STA  29,X
            LDA  SY_SIZE+1
            STA  30,X
            LDA  SY_SIZE
            STA  31,X
            LDQ  SY_LBA
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
            JSR  FILE_READ
            BCS  FR_RET
            LDX  IO_CNT
            ANDCC #$FE
FR_RET      RTS
;------------------------------------------------------------------------------
; IN: B = fileref, X = src buf, Y = len. OUT: carry clear on success.
;------------------------------------------------------------------------------
DOS_FWRITE  STX  IO_BUF
            STY  IO_LEN
            JSR  SLOT_CHECK
            BCS  FW_RET
            JSR  FILE_WRITE
FW_RET      RTS
;------------------------------------------------------------------------------
; IN: B = handle, A = whence (SEEK_SET/CUR/END), X:Y = 32-bit offset (X = high
; word). Read and update modes only. OUT: carry clear + X:Y = the new position;
; carry set + A = ERR_BADMODE / ERR_TOOBIG (a position beyond 32 bits).
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
SK_MODE_OK  LDA  SK_WHENCE
            BEQ  SK_SET
            CMPA #SEEK_CUR
            BEQ  SK_CUR
            CMPA #SEEK_END
            BNE  SK_BADMODE           ; not a whence
            LDQ  fslot.size,X
            BRA  SK_ADD
SK_CUR      LDQ  fslot.pos,X
SK_ADD      ADDW SK_LO
            ADCD SK_HI
            BCS  SK_TOOBIG
            BRA  SK_STORE
SK_SET      LDD  SK_HI
            LDW  SK_LO
SK_STORE    STQ  fslot.pos,X
            TFR  D,X                  ; X:Y = the new position
            TFR  W,Y
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
            LDQ  fslot.size,X
            STQ  ,Y
            LDQ  fslot.pos,X
            STQ  4,Y
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
            STD  FOUND_SIZE+2
            LDA  #ATTR_DIR
            STA  FOUND_ATTR
            BRA  ST_FILL
ST_NAME     LDD  RP_DIR
            STD  FD_DIR
            LDX  #RP_NAME
            JSR  FIND_DIRENT
            BCS  ST_RET
ST_FILL     LDY  FS_DEST
            LDQ  FOUND_SIZE
            STQ  ,Y
            LDQ  #0
            STQ  4,Y
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
            LDQ  DS_LBA
            STQ  dhandle.lba,X
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
            LDQ  dhandle.lba,X
            STQ  DS_LBA
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
            STD  DK_CLUS
            LDQ  FOUND_LBA       ; the entry is marked deleted FIRST and the chain
            LDY  #DOSBUF         ; freed after: a crash in between leaks clusters,
            JSR  BLKREAD         ; where the other order could leave a live entry
            BCS  DK_IOERR        ; pointing at clusters another file then claims
            LDD  FOUND_OFS
            LDX  #DOSBUF
            LEAX D,X
            LDA  #$E5
            STA  ,X
            LDQ  FOUND_LBA
            LDY  #DOSBUF
            JSR  BLKWRITE
            BCS  DK_IOERR
            LDD  DK_CLUS
            BEQ  DK_DONE         ; cluster 0 -- empty file, nothing to free
            JMP  FREE_CHAIN
DK_DONE     ANDCC #$FE
            RTS
DK_IOERR    LDA  #ERR_IOERR
            ORCC #1
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
DR_OLDOK    LDQ  FOUND_LBA
            STQ  DR_OLDLBA
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
DR_DO       LDQ  DR_OLDLBA
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
            LDQ  DR_OLDLBA
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
            LDQ  FOUND_LBA
            STQ  MK_LBA
            LDD  FOUND_OFS
            STD  MK_OFS
            JSR  ALLOC_CLUSTER   ; the new directory's own cluster
            LBCS MK_RET          ; A = disk full / I/O error
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
            LDY  #DOSBUF
            JSR  BLKWRITE
            BCS  MK_IOERR
            JSR  FAT_COMMIT      ; the new cluster is really allocated on disk ...
            BCS  MK_IOERR
            LDQ  MK_LBA          ; ... before the parent's entry for it goes in
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
            LDQ  MK_LBA
            LDY  #DOSBUF
            JSR  BLKWRITE
            BCS  MK_IOERR
            ANDCC #$FE
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
            LDQ  FOUND_LBA
            STQ  RM_LBA
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
RM_EMPTY    LDQ  RM_LBA          ; the entry goes first, then the cluster (see DOS_KILL)
            LDY  #DOSBUF
            JSR  BLKREAD
            BCS  RM_IOERR
            LDD  RM_OFS
            LDX  #DOSBUF
            LEAX D,X
            LDA  #$E5
            STA  ,X
            LDQ  RM_LBA
            LDY  #DOSBUF
            JSR  BLKWRITE
            BCS  RM_IOERR
            LDD  RM_CLUS
            JMP  FREE_CHAIN
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
; Programs. A program file is an 8-byte header (see EXE_* in defines.d) followed by
; the body. B_EXEC loads the body where the header says and jumps to the entry
; address; a program ends with B_EXIT, which starts the shell again.
;==============================================================================
; IN: X = the program's path, Y = its command tail (NUL-terminated string in the
; caller's memory) or 0. On success: does not return -- the program is running,
; on the boot stack. On failure: carry set + A = ERR_NOTFOUND / ERR_ISDIR / ... /
; ERR_BADEXE (bad header) / ERR_TOOBIG (doesn't fit where it asks to go). The
; command tail is copied first (the program may load over the caller's copy) and
; the path is parsed by the open, so nothing depends on the caller's memory once
; the body starts loading.
;------------------------------------------------------------------------------
DOS_EXEC    STX  EX_PATH
            LDX  #ARGBUF          ; copy the command tail
            LDB  #ARGMAX
            CMPY #0
            BEQ  EX_ARGEND
EX_ARGLOOP  LDA  ,Y+
            BEQ  EX_ARGEND
            STA  ,X+
            DECB
            BNE  EX_ARGLOOP
EX_ARGEND   CLR  ,X
            LDX  EX_PATH
            LDA  #FOPEN_READ
            JSR  DOS_OPEN
            LBCS EX_RET
            STA  EX_H
            TFR  A,B
            JSR  SLOT_CHECK
            LDD  #HDRBUF
            STD  IO_BUF
            LDD  #EXE_HDRSIZE
            STD  IO_LEN
            JSR  FILE_READ
            LBCS EX_FAIL
            LDD  IO_CNT
            CMPD #EXE_HDRSIZE
            LBNE EX_BAD
            LDD  HDRBUF
            CMPD #EXE_MAGIC
            LBNE EX_BAD
            LDD  HDRBUF+6         ; flags: none defined yet
            LBNE EX_BAD
            LDD  HDRBUF+2
            STD  EX_LOAD
            LDD  HDRBUF+4
            STD  EX_ENTRY
            LDX  CUR_SLOT
            LDQ  fslot.size,X     ; the body is the rest of the file
            SUBW #EXE_HDRSIZE
            SBCD #0
            TSTD
            LBNE EX_TOOBIG
            STW  EX_LEN
            LDD  EX_LOAD
            CMPD #DOS_END
            LBLO EX_TOOBIG        ; it would overwrite the BIOS or DOS
            ADDD EX_LEN
            LBCS EX_TOOBIG
            CMPD #EXE_MAXTOP
            LBHI EX_TOOBIG        ; ... or run into the ROM
            LDD  EX_ENTRY
            SUBD EX_LOAD
            LBLO EX_BAD           ; the entry must lie inside the body
            CMPD EX_LEN
            LBHS EX_BAD
            LDD  EX_LOAD
            STD  IO_BUF
            LDD  EX_LEN
            STD  IO_LEN
            LDS  BOOT_SP          ; the body may load over the caller's stack (the
                                  ; shell's is at $7F00), so from here on DOS runs on
                                  ; the boot stack: the caller's frame is abandoned,
                                  ; and a failure can only restart the shell
            JSR  FILE_READ
            BCS  EX_LOADFAIL
            LDD  IO_CNT
            CMPD EX_LEN
            BNE  EX_LOADFAIL
            LDB  EX_H
            JSR  DOS_CLOSE
            JMP  [EX_ENTRY]       ; the program has the machine
EX_LOADFAIL LDB  EX_H             ; (the caller's memory may be half overwritten)
            JSR  DOS_CLOSE
            JMP  DOS_EXIT
EX_TOOBIG   LDA  #ERR_TOOBIG
            BRA  EX_FAIL
EX_BAD      LDA  #ERR_BADEXE
EX_FAIL     STA  EX_ERR           ; close the file (an error there is not the news)
            LDB  EX_H
            JSR  DOS_CLOSE
            LDA  EX_ERR
            ORCC #1
EX_RET      RTS
;------------------------------------------------------------------------------
; -> X = the current command tail (see B_EXEC), NUL-terminated.
;------------------------------------------------------------------------------
DOS_ARGS    LDX  #ARGBUF
            ANDCC #$FE
            RTS
;------------------------------------------------------------------------------
; IN: X = a new program search path (NUL-terminated) or 0. -> X = the current one
; (PATHVAR). ERR_TOOBIG if the new one is longer than PATHVARMAX: the old one is
; kept. DOS only keeps it, across B_EXIT, for the shell, which does the searching.
;------------------------------------------------------------------------------
DOS_PATH    CMPX #0
            BEQ  PT_DONE
            TFR  X,Y              ; measure it first: a bad one changes nothing
            LDB  #PATHVARMAX+1
PT_LEN      LDA  ,Y+
            BEQ  PT_COPY
            DECB
            BNE  PT_LEN
            LDA  #ERR_TOOBIG
            ORCC #1
            RTS
PT_COPY     LDY  #PATHVAR
PT_LOOP     LDA  ,X+
            STA  ,Y+
            BNE  PT_LOOP
PT_DONE     LDX  #PATHVAR
            ANDCC #$FE
            RTS
;------------------------------------------------------------------------------
; The program is done. Closes every open file (flushing what was written) and
; every directory scan, then starts the shell again on the boot stack. Never
; returns.
;------------------------------------------------------------------------------
DOS_EXIT    LDS  BOOT_SP
            CLR  FF_IDX
EXT_LOOP    LDA  FF_IDX
            CMPA #NSLOTS
            BHS  EXT_DONE
            JSR  SLOT_ADDR
            TST  fslot.inuse,X
            BEQ  EXT_NEXT
            LDB  FF_IDX
            JSR  DOS_CLOSE        ; (a write error here has nobody to tell)
EXT_NEXT    INC  FF_IDX
            BRA  EXT_LOOP
EXT_DONE    LDX  #DHANDLES
            CLR  ,X
            LDY  #DHANDLES
            LDW  #NDIRH*sizeof{dhandle}
            TFM  X,Y+
            JSR  FAT_COMMIT
            JMP  RUN_STARTUP
;==============================================================================
; The byte-stream layer under the file API: maps a file's byte position to a
; sector via its FAT cluster chain, and caches one sector per open file in
; that file's own buffer. "File sector N" always means the Nth 512-byte sector
; of the file's data (0-based), a 24-bit number (files run to 4GB); "cluster
; index K" is which cluster of the chain holds it. Sizes and positions are
; 32-bit big-endian.
;==============================================================================
; IN: CUR_SLOT, LOC_N = file sector index (3 bytes), LOC_EXT = 0 (the sector must
; already be part of the chain) or 1 (allocate/link clusters as needed). OUT: carry
; clear + Q = that sector's LBA; carry set + A = error. Remembers the cluster it
; lands on (fslot.cacheidx/cacheclus) so sequential access doesn't re-walk the
; chain from the start. Trashes A, B, X, Y, W (and FATBUF via the FAT).
;------------------------------------------------------------------------------
LOCATE_SECTOR
            LDA  SPCSHIFT
            STA  MULCNT
            LDX  #LOC_N
            LDY  #LOC_K3
            JSR  COPY24
LS_SHIFT    TST  MULCNT
            BEQ  LS_SHDONE
            LSR  LOC_K3
            ROR  LOC_K3+1
            ROR  LOC_K3+2
            DEC  MULCNT
            BRA  LS_SHIFT
LS_SHDONE   TST  LOC_K3
            LBNE LS_TOOBIG            ; 65536+ clusters can't be in one FAT16 file
            LDD  LOC_K3+1
            STD  LOC_K                ; cluster index holding the sector
            CLR  LOC_SIC
            LDA  LOC_N+2
            ANDA SPCMASK
            STA  LOC_SIC+1            ; sector within that cluster (a word, for SICW)
            LDX  CUR_SLOT
            LDD  fslot.cacheclus,X
            BEQ  LS_FROMSTART
            LDD  fslot.cacheidx,X
            CMPD LOC_K
            BHI  LS_FROMSTART         ; cache is already past the target
            STD  LOC_J
            LDD  fslot.cacheclus,X
            STD  LOC_C
            BRA  LS_WALK
LS_FROMSTART
            LDD  #0
            STD  LOC_J
            LDD  fslot.startclus,X
            BNE  LS_SETSTART
            TST  LOC_EXT              ; an empty file has no cluster yet
            BEQ  LS_NOSECT
            JSR  ALLOC_CLUSTER        ; claim the file's first cluster
            BCS  LS_ERR
            LDX  CUR_SLOT             ; ALLOC_CLUSTER trashed X
            STD  fslot.startclus,X
LS_SETSTART STD  LOC_C
LS_WALK     LDD  LOC_J
            CMPD LOC_K
            BEQ  LS_FOUND
            LDD  LOC_C
            JSR  NEXT_CLUSTER         ; D = the next cluster in the chain
            BCS  LS_IOERR
            CMPD #$FFF8
            BLO  LS_ADVANCE
            TST  LOC_EXT              ; the chain ends before the target
            BEQ  LS_NOSECT
            JSR  ALLOC_CLUSTER        ; extend it: claim a new cluster ...
            BCS  LS_ERR
            STD  LOC_NEW
            STD  SETVAL
            LDD  LOC_C
            JSR  SET_FAT_ENTRY        ; ... and link the old last one to it
            BCS  LS_ERR
            LDD  LOC_NEW
LS_ADVANCE  STD  LOC_C
            LDD  LOC_J
            ADDD #1
            STD  LOC_J
            BRA  LS_WALK
LS_FOUND    LDX  CUR_SLOT
            LDD  LOC_J
            STD  fslot.cacheidx,X
            LDD  LOC_C
            STD  fslot.cacheclus,X
            LDD  LOC_SIC
            STD  SICW
            LDD  LOC_C
            JSR  CLUS_SIC_TO_LBA      ; Q = the sector's LBA
            ANDCC #$FE
            RTS
LS_NOSECT
LS_IOERR    LDA  #ERR_IOERR           ; not part of the file's chain / a FAT read failed
LS_ERR      ORCC #1                   ; (A already says why)
            RTS
LS_TOOBIG   LDA  #ERR_TOOBIG
            ORCC #1
            RTS
;------------------------------------------------------------------------------
; Writes CUR_SLOT's buffer back to disk if it's been modified. OUT: carry
; clear on success; carry set + A = error. Trashes A, B, X, Y, W.
;------------------------------------------------------------------------------
FLUSH_SLOT  LDX  CUR_SLOT
            TST  fslot.dirty,X
            BEQ  FL_OK
            LEAX fslot.bufsec,X
            LDY  #LOC_N
            JSR  COPY24
            CLR  LOC_EXT              ; a dirty sector was allocated when loaded
            JSR  LOCATE_SECTOR
            BCS  FL_RET
            LDX  CUR_SLOT
            LDY  fslot.bufptr,X
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
            LEAX fslot.size,X
            LDY  #ZT_SEC
            JSR  SHR9                 ; the sector holding EOF
            LDX  #ZT_SEC
            LDY  #SEL_N
            JSR  CMP24
            BNE  ZT_DONE              ; not this one
            LDX  CUR_SLOT
            LDD  fslot.size+2,X
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
; Makes file sector SEL_N (3 bytes) the one in CUR_SLOT's buffer, for READING (it
; must already exist). Flushes the previous sector first if it was modified. OUT:
; carry clear on success; carry set + A = error. Trashes A, B, X, Y, W.
;------------------------------------------------------------------------------
SEL_READ    LDX  CUR_SLOT
            LEAX fslot.bufsec,X
            LDY  #SEL_N
            JSR  CMP24
            BEQ  SEL_OK
            JSR  FLUSH_SLOT
            BCS  SEL_RET
            LDX  #SEL_N
            LDY  #LOC_N
            JSR  COPY24
            CLR  LOC_EXT
            JSR  LOCATE_SECTOR
            BCS  SEL_RET
            LDX  CUR_SLOT
            LDY  fslot.bufptr,X
            JSR  BLKREAD
            BCS  SEL_IOERR
            LDX  CUR_SLOT
            LEAY fslot.bufsec,X
            LDX  #SEL_N
            JSR  COPY24
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
; Makes file sector SEL_N the one in CUR_SLOT's buffer, for WRITING. A sector that
; already holds data is loaded (so a partial write doesn't lose the rest); a
; sector wholly past EOF is claimed and starts zeroed -- and any whole sectors
; between the old EOF and it are written out as zeros, so a seek-and-write
; past the end never exposes stale disk contents. OUT: as SEL_READ.
;------------------------------------------------------------------------------
SEL_WRITE   LDX  CUR_SLOT
            LEAX fslot.bufsec,X
            LDY  #SEL_N
            JSR  CMP24
            LBEQ SEW_OK
            JSR  FLUSH_SLOT
            LBCS SEW_RET
            LDX  CUR_SLOT
            LEAX fslot.size,X
            LDY  #SEW_AS
            JSR  SHR9                 ; size >> 9 ...
            LDX  CUR_SLOT
            LDA  fslot.size+2,X
            ANDA #1
            ORA  fslot.size+3,X       ; ... nonzero if size & 511 <> 0
            BEQ  SEW_NOROUND
            LDX  #SEW_AS
            JSR  INC24                ; SEW_AS = the number of sectors holding data
SEW_NOROUND LDX  #SEL_N
            LDY  #SEW_AS
            JSR  CMP24
            BHS  SEW_BEYOND
            LDX  #SEL_N               ; the sector already holds data: load it
            LDY  #LOC_N
            JSR  COPY24
            CLR  LOC_EXT
            JSR  LOCATE_SECTOR
            LBCS SEW_RET
            LDX  CUR_SLOT
            LDY  fslot.bufptr,X
            JSR  BLKREAD
            LBCS SEW_IOERR
            LDX  CUR_SLOT
            LEAY fslot.bufsec,X
            LDX  #SEL_N
            JSR  COPY24
            JSR  ZERO_TAIL
            BRA  SEW_OK
SEW_BEYOND  LDX  CUR_SLOT             ; wholly past EOF: the buffer is scratch
            LDA  #$FF                 ; (zeroed) from here on
            STA  fslot.bufsec,X
            JSR  ZERO_SLOTBUF
            LDX  #SEW_AS
            LDY  #SEW_S
            JSR  COPY24
SEW_GAP     LDX  #SEW_S
            LDY  #SEL_N
            JSR  CMP24
            BHS  SEW_TARGET
            LDX  #SEW_S               ; a gap sector: allocate it, write zeros
            LDY  #LOC_N
            JSR  COPY24
            LDA  #1
            STA  LOC_EXT
            JSR  LOCATE_SECTOR
            LBCS SEW_RET
            LDX  CUR_SLOT
            LDY  fslot.bufptr,X
            JSR  BLKWRITE
            LBCS SEW_IOERR
            LDX  #SEW_S
            JSR  INC24
            BRA  SEW_GAP
SEW_TARGET  LDX  #SEL_N
            LDY  #LOC_N
            JSR  COPY24
            LDA  #1
            STA  LOC_EXT
            JSR  LOCATE_SECTOR        ; make sure the target sector exists
            LBCS SEW_RET
            LDX  CUR_SLOT
            LEAY fslot.bufsec,X
            LDX  #SEL_N
            JSR  COPY24               ; buffer is still all zeros
SEW_OK      ANDCC #$FE
SEW_RET     RTS
SEW_IOERR   LDX  CUR_SLOT
            LDA  #$FF
            STA  fslot.bufsec,X
            LDA  #ERR_IOERR
            ORCC #1
            RTS
;------------------------------------------------------------------------------
; IN: CUR_SLOT, IO_BUF = destination, IO_LEN = how many bytes. Reads from the file
; position, which advances, a sector-sized piece at a time (block copies, not a
; byte at a time). OUT: carry clear + IO_CNT = bytes read (less than IO_LEN only
; at end of file); carry set + A = error. Allowed in read and update modes.
;------------------------------------------------------------------------------
FILE_READ   LDX  CUR_SLOT
            LDA  fslot.mode,X
            BEQ  FRD_MODEOK
            CMPA #FOPEN_UPDATE
            LBNE FRD_BADMODE
FRD_MODEOK  LDD  #0
            STD  IO_CNT
FRD_LOOP    LDD  IO_LEN
            SUBD IO_CNT
            LBEQ FRD_OK               ; asked-for count reached
            STD  FR_WANT
            LDX  CUR_SLOT
            LDQ  fslot.size,X         ; Q = size - pos: how much of the file is left
            SUBW fslot.pos+2,X
            SBCD fslot.pos,X
            BCS  FRD_OK               ; pos is beyond the size: end of file
            TSTD
            BNE  FRD_CAP
            TSTW
            BEQ  FRD_OK               ; pos == size: end of file
            BRA  FRD_AVAIL
FRD_CAP     LDW  #$FFFF               ; 64KB or more left: more than any request
FRD_AVAIL   STW  FR_N                 ; n = min(bytes wanted, bytes left in the file,
            LDD  fslot.pos+2,X        ;         bytes left in this sector)
            ANDA #1
            STD  FR_OFF               ; offset of pos within its sector
            LDD  #512
            SUBD FR_OFF
            CMPD FR_N
            BHS  FRD_N1
            STD  FR_N
FRD_N1      LDD  FR_WANT
            CMPD FR_N
            BHS  FRD_N2
            STD  FR_N
FRD_N2      LEAX fslot.pos,X
            LDY  #SEL_N
            JSR  SHR9
            JSR  SEL_READ
            BCS  FRD_RET
            LDX  CUR_SLOT
            LDD  FR_OFF
            ADDD fslot.bufptr,X
            TFR  D,X                  ; source: this sector's buffer, at the offset
            LDD  IO_BUF
            ADDD IO_CNT
            TFR  D,Y                  ; destination: the caller's buffer
            LDW  FR_N
            TFM  X+,Y+
            LDX  CUR_SLOT
            LDQ  fslot.pos,X
            ADDW FR_N
            ADCD #0
            STQ  fslot.pos,X
            LDD  IO_CNT
            ADDD FR_N
            STD  IO_CNT
            LBRA FRD_LOOP
FRD_OK      ANDCC #$FE
FRD_RET     RTS
FRD_BADMODE LDA  #ERR_BADMODE
            ORCC #1
            RTS
;------------------------------------------------------------------------------
; IN: CUR_SLOT, IO_BUF = the data, IO_LEN = how many bytes. Writes at the file
; position (which advances, growing the file if it's past the end), a sector-
; sized piece at a time. OUT: carry clear + IO_CNT = IO_LEN; carry set + A = error.
; Allowed in write, append and update modes.
;------------------------------------------------------------------------------
FILE_WRITE  LDX  CUR_SLOT
            LDA  fslot.mode,X
            LBEQ FWR_BADMODE          ; read-only
            LDD  #0
            STD  IO_CNT
FWR_LOOP    LDD  IO_LEN
            SUBD IO_CNT
            LBEQ FWR_OK
            STD  FR_WANT
            LDX  CUR_SLOT
            LDD  fslot.pos+2,X
            ANDA #1
            STD  FR_OFF               ; offset of pos within its sector
            LDD  #512
            SUBD FR_OFF
            STD  FR_N                 ; n = min(bytes wanted, room left in this sector)
            CMPD FR_WANT
            BLS  FWR_N1
            LDD  FR_WANT
            STD  FR_N
FWR_N1      LDQ  fslot.pos,X          ; a file can't run past 32 bits
            ADDW FR_N
            ADCD #0
            BCS  FWR_FULL
            LEAX fslot.pos,X
            LDY  #SEL_N
            JSR  SHR9
            JSR  SEL_WRITE
            BCS  FWR_RET
            LDX  CUR_SLOT
            LDD  FR_OFF
            ADDD fslot.bufptr,X
            TFR  D,Y                  ; destination: this sector's buffer, at the offset
            LDD  IO_BUF
            ADDD IO_CNT
            TFR  D,X                  ; source: the caller's data
            LDW  FR_N
            TFM  X+,Y+
            LDX  CUR_SLOT
            LDA  #1
            STA  fslot.dirty,X
            LDQ  fslot.pos,X
            ADDW FR_N
            ADCD #0
            STQ  fslot.pos,X
            SUBW fslot.size+2,X       ; past the old end? then the file grew
            SBCD fslot.size,X
            BCS  FWR_NOGROW
            LDQ  fslot.pos,X
            STQ  fslot.size,X
FWR_NOGROW  LDD  IO_CNT
            ADDD FR_N
            STD  IO_CNT
            LBRA FWR_LOOP
FWR_OK      ANDCC #$FE
FWR_RET     RTS
FWR_BADMODE LDA  #ERR_BADMODE
            ORCC #1
            RTS
FWR_FULL    LDA  #ERR_TOOBIG
            ORCC #1
            RTS
;------------------------------------------------------------------------------
; IN: CUR_SLOT. OUT: carry clear + A = the byte at the file position, which
; advances; carry set + A = ERR_EOF at/after the end (or another error code).
; Allowed in read and update modes. (One byte at a time, for FGETC and the line
; reader; FILE_READ is the block path.)
;------------------------------------------------------------------------------
FILE_GETBYTE
            LDX  CUR_SLOT
            LDA  fslot.mode,X
            BEQ  GB_MODEOK
            CMPA #FOPEN_UPDATE
            BNE  GB_BADMODE
GB_MODEOK   LDQ  fslot.size,X         ; anything left? (size - pos)
            SUBW fslot.pos+2,X
            SBCD fslot.pos,X
            BCS  GB_EOF
            TSTD
            BNE  GB_HAVE
            TSTW
            BEQ  GB_EOF
GB_HAVE     LEAX fslot.pos,X
            LDY  #SEL_N
            JSR  SHR9
            JSR  SEL_READ             ; (returns at once when it is the buffered sector)
            BCS  GB_RET
            LDX  CUR_SLOT
            LDD  fslot.pos+2,X
            ANDA #1                   ; D = offset within the sector
            ADDD fslot.bufptr,X
            TFR  D,Y
            LDA  ,Y
            PSHS A
            LDQ  fslot.pos,X
            ADDW #1
            ADCD #0
            STQ  fslot.pos,X
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
; + A = error. Allowed in write, append and update modes.
;------------------------------------------------------------------------------
FILE_PUTBYTE
            STA  PB_BYTE
            LDX  CUR_SLOT
            LDA  fslot.mode,X
            BEQ  PB_BADMODE           ; read-only
            LDQ  fslot.pos,X
            ADDW #1                   ; pos + 1 must still fit in 32 bits
            ADCD #0
            BCS  PB_FULL
            LEAX fslot.pos,X
            LDY  #SEL_N
            JSR  SHR9
            JSR  SEL_WRITE
            BCS  PB_RET
            LDX  CUR_SLOT
            LDD  fslot.pos+2,X
            ANDA #1
            ADDD fslot.bufptr,X
            TFR  D,Y
            LDA  PB_BYTE
            STA  ,Y
            LDA  #1
            STA  fslot.dirty,X
            LDQ  fslot.pos,X
            ADDW #1
            ADCD #0
            STQ  fslot.pos,X
            SUBW fslot.size+2,X
            SBCD fslot.size,X
            BCS  PB_NOGROW
            LDQ  fslot.pos,X          ; wrote past the old end: the file grew
            STQ  fslot.size,X
PB_NOGROW   ANDCC #$FE
PB_RET      RTS
PB_BADMODE  LDA  #ERR_BADMODE
            ORCC #1
            RTS
PB_FULL     LDA  #ERR_TOOBIG
            ORCC #1
            RTS
;------------------------------------------------------------------------------
PATH_SHELL  FCC  "/CMD/SHELL.COM"
            FCB  0
PATH_BASIC  FCC  "/CMD/BASIC.COM"
            FCB  0
PATH_DEFAULT FCC "/CMD"
            FCB  0
MSG_NOSHELL FCC  "No SHELL.COM or BASIC.COM on the disk"
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
            FDB  DOS_EXEC       ; $29 B_EXEC
            FDB  DOS_ARGS       ; $2A B_ARGS
            FDB  DOS_EXIT       ; $2B B_EXIT
            FDB  DOS_PATH       ; $2C B_PATH
DOS_ENTRIES_END
    IFNE (DOS_ENTRIES_END-DOS_ENTRIES)-2*NUM_DOS_JT
    ERROR "DOS_ENTRIES must have one entry per DOS call (see defines.d)"
    ENDC
;------------------------------------------------------------------------------
JT_BASE       RMB  2        ; the BIOS's DOS call table (from SD_BOOT_TRY, in Y)
CWDCLUS       RMB  2        ; the current directory's first cluster (0 = root)
RESSEC        RMB  2
SECPERCLUS    RMB  1
NUMFATS       RMB  1
FATCNT        RMB  1
MULCNT        RMB  1
ROOTENTCNT    RMB  2
SECPERFAT     RMB  2
TOTALSEC      RMB  4        ; 32-bit values are big-endian (LDQ/STQ order)
TOTALCLUS     RMB  2
MAXCLUS       RMB  2
FATLBA        RMB  2
ROOTLBA       RMB  4
ROOTDIRSEC    RMB  2
DATALBA       RMB  4
BOOT_SP       RMB  2        ; the stack DOS started on: programs start on it
ARGBUF        RMB  ARGMAX+1 ; the command tail of the program being started
PATHVAR       RMB  PATHVARMAX+1 ; the program search path (B_PATH)
HDRBUF        RMB  EXE_HDRSIZE
EX_PATH       RMB  2
EX_H          RMB  1
EX_LOAD       RMB  2
EX_ENTRY      RMB  2
EX_LEN        RMB  2
EX_ERR        RMB  1
SICW          RMB  2        ; CLUS_SIC_TO_LBA: sector within the cluster
; The FAT cache and free-cluster search
FATBUFSEC     RMB  2        ; which sector of the FAT FATBUF holds ($FFFF = none)
LFECLUS       RMB  2
LFESEC        RMB  2
WF_LBA        RMB  4
ALLOC_HINT    RMB  2        ; where the next free-cluster search starts
ACCLUS        RMB  2
ACSTART       RMB  2
ACWRAP        RMB  1
FCCLUS        RMB  2
FCNEXT        RMB  2
SETVAL        RMB  2
FATDIRTY      RMB  1        ; FATBUF has changes not yet on disk (see FAT_COMMIT)
; Directory search / iteration (FIND_DIRENT, DS_*)
FDNAME        RMB  2
FD_DIR        RMB  2        ; the directory a search runs in (first cluster; 0 = root)
FD_MODE       RMB  1        ; 0 = by name, 1 = by first cluster
FD_TARGET     RMB  2
FOUND_LBA     RMB  4
FOUND_OFS     RMB  2
FOUND_CLUSTER RMB  2
FOUND_SIZE    RMB  4
FOUND_ATTR    RMB  1
DS_DIR        RMB  2
DS_CUR        RMB  2
DS_SIC        RMB  1
DS_LBA        RMB  4
DS_LEFT       RMB  2
ED_NEW        RMB  2
ZC_CLUS       RMB  2
ZC_LBA        RMB  4
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
OPEN_OLDCLUS  RMB  2
CUR_SLOT      RMB  2
CUR_DH        RMB  2
RL_DEST       RMB  2
RL_MAX        RMB  2
RL_COUNT      RMB  2
WL_SRC        RMB  2
WL_LEN        RMB  2
WL_I          RMB  2
DC_DIROFS     RMB  2
DIRENTIDX     RMB  1
DIRDEST       RMB  2
RENAME_NEW    RMB  2
DR_OLDLBA     RMB  4
DR_OLDOFS     RMB  2
SPCSHIFT      RMB  1        ; log2(sectors per cluster)
SPCMASK       RMB  1        ; sectors per cluster - 1
CNO_IDX       RMB  1
DC_CLUS       RMB  2
DC_STATUS     RMB  1
SY_STATUS     RMB  1
SY_LBA        RMB  4
SY_SIZE       RMB  4
DK_CLUS       RMB  2
FF_IDX        RMB  1
FP_BYTE       RMB  1
IO_BUF        RMB  2
IO_LEN        RMB  2
IO_CNT        RMB  2
FR_WANT       RMB  2
FR_OFF        RMB  2
FR_N          RMB  2
SK_WHENCE     RMB  1
SK_HI         RMB  2
SK_LO         RMB  2
FS_DEST       RMB  2
OD_CLUS       RMB  2
OD_IDX        RMB  1
OD_PTR        RMB  2
MK_LBA        RMB  4
MK_OFS        RMB  2
MK_CLUS       RMB  2
RM_CLUS       RMB  2
RM_LBA        RMB  4
RM_OFS        RMB  2
GC_DEST       RMB  2
GC_SIZE       RMB  2
GC_P          RMB  2
GC_CUR        RMB  2
GC_PAR        RMB  2
GC_LEN        RMB  1
GC_NAME       RMB  14
PATHBUF       RMB  PATHMAX+1
LOC_N         RMB  3        ; LOCATE_SECTOR arguments/scratch (file sector numbers: 24 bits)
LOC_K3        RMB  3
LOC_EXT       RMB  1
LOC_K         RMB  2
LOC_SIC       RMB  2
LOC_J         RMB  2
LOC_C         RMB  2
LOC_NEW       RMB  2
SEL_N         RMB  3        ; SEL_READ/SEL_WRITE: the file sector wanted
SEW_AS        RMB  3
SEW_S         RMB  3
ZT_SEC        RMB  3
ZT_OFS        RMB  2
PB_BYTE       RMB  1
; The big buffers are just addresses after the last variable -- no bytes in
; dos.bin, so they cost no disk space and no load time (they are zero
; anyway: the BIOS clears RAM at reset and DOS clears what it relies on).
DOSBUF        equ  *        ; directory / boot sectors (512)
FATBUF        equ  DOSBUF+512   ; the cached FAT sector (512)
SLOTBUFS      equ  FATBUF+512   ; per-file sector buffers: NSLOTS x 512
DOS_END       equ  SLOTBUFS+NSLOTS*512
;------------------------------------------------------------------------------
; End of dos.asm
;------------------------------------------------------------------------------
