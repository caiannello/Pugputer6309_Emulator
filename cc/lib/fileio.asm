;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 C library
;    FILE: fileio.asm -- <stdio.h>'s files: fopen(), fclose(), fread(),
;          fwrite(), fseek(), ftell(), rewind(), fflush(), feof(), ferror(),
;          clearerr(), remove(), rename()
;
; fopen's modes, over DOS's (bios/defines.d, FOPEN_*): "r" read; "w" write (a
; new file, or emptied); "a" write at the end (made if it's missing); "r+" read
; and write in place; "w+" the same, emptied first; "a+" the same, starting at
; the end. A "b" anywhere makes it binary: no CR LF for '\n'.
; DOS has DOS_NFILES files open at once; so does fopen.
;------------------------------------------------------------------------------
    INCLUDE defines.d
    INCLUDE libc.d
            EXPORT _fopen,_fclose,_fread,_fwrite,_fseek,_ftell,_rewind,_fflush
            EXPORT _feof,_ferror,_clearerr,_remove,_rename
            IMPORT __iob,__getc,__putc
            SECTION code
;------------------------------------------------------------------------------
; FILE *fopen(const char *name, const char *mode) -> the FILE, or NULL.
_fopen      PSHS Y                     ; (4,S name, 6,S mode)
            LDX  #__iob+3*FL_SIZE      ; a FILE not in use
FO_SLOT     CMPX #__iob+NFILE*FL_SIZE
            LBHS FO_NULL
            TST  FL_FLAGS,X
            BEQ  FO_FREE
            LEAX FL_SIZE,X
            BRA  FO_SLOT
FO_FREE     STX  fp
            CLR  fplus
            LDY  6,S                   ; the mode
            LDA  ,Y+
            STA  fkind
            LDB  #FOPEN_READ
            CMPA #'r'
            BNE  FO_W
            LDA  #FF_USED|FF_TEXT|FF_READ
            BRA  FO_KIND
FO_W        LDB  #FOPEN_WRITE
            CMPA #'w'
            BEQ  FO_WRITE
            LDB  #FOPEN_APPEND
            CMPA #'a'
            BNE  FO_NULL
FO_WRITE    LDA  #FF_USED|FF_TEXT|FF_WRITE
FO_KIND     STB  fmode
            STA  fflags
FO_MORE     LDA  ,Y+                   ; then "+" and "b", in any order
            BEQ  FO_OPEN
            CMPA #'b'
            BNE  FO_PLUS
            LDA  fflags
            ANDA #~FF_TEXT
            STA  fflags
            BRA  FO_MORE
FO_PLUS     CMPA #'+'
            BNE  FO_MORE
            INC  fplus
            LDA  #FOPEN_UPDATE
            STA  fmode
            LDA  fflags
            ORA  #FF_READ|FF_WRITE
            STA  fflags
            BRA  FO_MORE
FO_OPEN     TST  fplus
            BEQ  FO_GO
            LDA  fkind                 ; "w+": emptied first
            CMPA #'w'
            BNE  FO_GO
            LDX  4,S
            LDA  #B_KILL_NAME
            SWI2
FO_GO       LDX  4,S
            LDE  fmode
            LDA  #B_FOPEN_NAME
            SWI2
            BCS  FO_NULL
            LDX  fp
            STA  FL_HANDLE,X
            LDB  fflags
            STB  FL_FLAGS,X
            TST  fplus                 ; "a+": at the end
            BEQ  FO_RET
            LDB  fkind
            CMPB #'a'
            BNE  FO_RET
            TFR  A,B
            LDX  #0
            LDY  #0
            LDE  #SEEK_END
            LDA  #B_FSEEK_NAME
            SWI2
FO_RET      LDD  fp
            PULS Y,PC
FO_NULL     CLRD
            PULS Y,PC
;------------------------------------------------------------------------------
; int fclose(FILE *f) -> 0, or EOF. (DOS writes out what the file holds.)
_fclose     LDX  2,S
            LDA  FL_FLAGS,X
            BEQ  FC_EOF
            CLR  FL_FLAGS,X
            BITA #FF_CON
            BNE  FC_OK
            LDB  FL_HANDLE,X
            LDA  #B_FCLOSE_NAME
            SWI2
            BCS  FC_EOF
FC_OK       CLRD
            RTS
FC_EOF      LDD  #EOF
            RTS
;------------------------------------------------------------------------------
; size_t fread(void *p, size_t size, size_t n, FILE *f) -> the items read (all
; of each).
_fread      PSHS Y,U                   ; (6 p, 8 size, 10 n, 12 f)
            LDX  12,S
            LDU  6,S
            LDY  #0                    ; Y: the items so far
            LDA  FL_FLAGS,X
            BITA #FF_READ
            BEQ  FR_DONE
            LDD  8,S
            BEQ  FR_DONE
            LDA  FL_FLAGS,X
            BITA #FF_CON|FF_TEXT|FF_UNGOT
            BNE  FR_SLOW
            LDD  8,S                   ; a binary file: DOS's block reads
            CMPD #1
            BNE  FR_ITEM
            LDD  10,S                  ; (items of 1: all at once)
            BSR  RDBLK
            TFR  D,Y
            BRA  FR_DONE
FR_ITEM     CMPY 10,S
            BHS  FR_DONE
            LDD  8,S
            BSR  RDBLK
            CMPD 8,S
            BNE  FR_DONE
            LEAU D,U
            LEAY 1,Y
            BRA  FR_ITEM
FR_SLOW     CMPY 10,S                  ; else a character at a time
            BHS  FR_DONE
            LDW  8,S
FR_BYTE     JSR  __getc
            BCS  FR_DONE
            STB  ,U+
            DECW
            BNE  FR_BYTE
            LEAY 1,Y
            BRA  FR_SLOW
FR_DONE     TFR  Y,D
            PULS Y,U,PC
; X = a DOS FILE, U = a buffer, D = how many bytes: read -> D = how many came
; (fewer: FF_EOF, or FF_ERR, set). Keeps X, U.
RDBLK       PSHS D,X,Y
            TFR  D,Y
            LDB  FL_HANDLE,X
            TFR  U,X
            LDA  #B_FREAD
            SWI2
            BCS  RB_ERR
            TFR  X,D
            CMPD ,S
            BEQ  RB_RET
            LDB  #FF_EOF
            BRA  RB_FLAG
RB_ERR      LDB  #FF_ERR
            LDX  #0
RB_FLAG     PSHS X
            LDX  4,S
            ORB  FL_FLAGS,X
            STB  FL_FLAGS,X
            PULS D
RB_RET      LEAS 2,S
            PULS X,Y,PC
;------------------------------------------------------------------------------
; size_t fwrite(const void *p, size_t size, size_t n, FILE *f) -> the items
; written.
_fwrite     PSHS Y,U                   ; (6 p, 8 size, 10 n, 12 f)
            LDX  12,S
            LDU  6,S
            LDY  #0
            LDA  FL_FLAGS,X
            BITA #FF_WRITE
            BEQ  FW_DONE
            LDD  8,S
            BEQ  FW_DONE
            LDA  FL_FLAGS,X
            BITA #FF_CON|FF_TEXT
            BNE  FW_SLOW
            LDD  8,S                   ; a binary file: DOS's block writes
            CMPD #1
            BNE  FW_ITEM
            LDD  10,S
            BSR  WRBLK
            BCS  FW_DONE
            LDY  10,S
            BRA  FW_DONE
FW_ITEM     CMPY 10,S
            BHS  FW_DONE
            LDD  8,S
            BSR  WRBLK
            BCS  FW_DONE
            LDD  8,S
            LEAU D,U
            LEAY 1,Y
            BRA  FW_ITEM
FW_SLOW     CMPY 10,S
            BHS  FW_DONE
            LDW  8,S
FW_BYTE     LDB  ,U+
            PSHSW                      ; (__putc uses E)
            JSR  __putc
            PULSW
            BCS  FW_DONE
            DECW
            BNE  FW_BYTE
            LEAY 1,Y
            BRA  FW_SLOW
FW_DONE     TFR  Y,D
            PULS Y,U,PC
; X = a DOS FILE, U = bytes, D = how many: written. Carry set on an error
; (FF_ERR too). Keeps X, U.
WRBLK       PSHS X,Y
            TFR  D,Y
            LDB  FL_HANDLE,X
            TFR  U,X
            LDA  #B_FWRITE
            SWI2
            PULS X,Y
            BCC  WB_RET
            LDA  FL_FLAGS,X
            ORA  #FF_ERR
            STA  FL_FLAGS,X
            ORCC #1
WB_RET      RTS
;------------------------------------------------------------------------------
; int fseek(FILE *f, long offset, int whence) -> 0, or -1. (whence: SEEK_SET 0,
; SEEK_CUR 1, SEEK_END 2.) Clears the end of the file, and ungetc's character.
_fseek      PSHS Y                     ; (4 f, 6 offset, 10 whence)
            LDX  4,S
            LDA  FL_FLAGS,X
            BITA #FF_CON
            BNE  FS_FAIL
            ANDA #~(FF_EOF|FF_UNGOT)
            STA  FL_FLAGS,X
            LDB  FL_HANDLE,X
            LDE  11,S
            LDX  6,S
            LDY  8,S
            LDA  #B_FSEEK_NAME
            SWI2
            BCS  FS_FAIL
            CLRD
            PULS Y,PC
FS_FAIL     LDD  #-1
            PULS Y,PC
; void rewind(FILE *f): to the start, the end and any error forgotten.
_rewind     LDX  2,S
            LDA  FL_FLAGS,X
            ANDA #~FF_ERR
            STA  FL_FLAGS,X
            LDD  #SEEK_SET
            PSHS D
            CLRD
            PSHS D
            PSHS D
            PSHS X
            BSR  _fseek
            LEAS 8,S
            RTS
; long ftell(FILE *f) -> the position, or -1.
_ftell      LDX  2,S
            LDA  FL_FLAGS,X
            BITA #FF_CON
            BNE  FT_FAIL
            LDB  FL_HANDLE,X
            LEAS -16,S                 ; (DOS's 16 bytes: the position at +4)
            TFR  S,X
            LDA  #B_FSTAT_NAME
            SWI2
            BCS  FT_FAIL2
            LDX  18,S
            LDA  FL_FLAGS,X            ; (one less for ungetc's character)
            BITA #FF_UNGOT
            BEQ  FT_POS
            LDQ  4,S
            SUBW #1
            SBCD #0
            BRA  FT_RET
FT_POS      LDQ  4,S
FT_RET      LEAS 16,S
            RTS
FT_FAIL2    LEAS 16,S
FT_FAIL     LDQ  #$FFFFFFFF
            RTS
;------------------------------------------------------------------------------
; int fflush(FILE *f): a DOS file's buffered bytes written out now (NULL: every
; file's) -> 0, or EOF.
_fflush     LDX  2,S
            BEQ  FU_ALL
            LDA  FL_FLAGS,X
            BITA #FF_CON
            BNE  FU_OK
            LDB  FL_HANDLE,X
            BRA  FU_GO
FU_ALL      LDB  #$FF
FU_GO       LDA  #B_FFLUSH
            SWI2
            BCS  FU_EOF
FU_OK       CLRD
            RTS
FU_EOF      LDD  #EOF
            RTS
; int feof(FILE *f), int ferror(FILE *f): nonzero at the end / after an error.
; void clearerr(FILE *f): both forgotten.
_feof       LDB  #FF_EOF
            BRA  FE_TEST
_ferror     LDB  #FF_ERR
FE_TEST     LDX  2,S
            ANDB FL_FLAGS,X
            CLRA
            RTS
_clearerr   LDX  2,S
            LDA  FL_FLAGS,X
            ANDA #~(FF_EOF|FF_ERR)
            STA  FL_FLAGS,X
            RTS
;------------------------------------------------------------------------------
; int remove(const char *name) -> 0, or -1.
_remove     LDX  2,S
            LDA  #B_KILL_NAME
            SWI2
            BCS  RM_FAIL
            CLRD
            RTS
RM_FAIL     LDD  #-1
            RTS
; int rename(const char *old, const char *new) -> 0, or -1. The file stays in
; its directory: only new's last part (after any /) is its new name.
_rename     PSHS Y
            LDY  6,S
            TFR  Y,X
RN_LAST     LDA  ,X+
            BEQ  RN_GO
            CMPA #'/'
            BNE  RN_LAST
            TFR  X,Y
            BRA  RN_LAST
RN_GO       LDX  4,S
            LDA  #B_RENAME_NAME
            SWI2
            BCS  RN_FAIL
            CLRD
            PULS Y,PC
RN_FAIL     LDD  #-1
            PULS Y,PC
            ENDSECT
;------------------------------------------------------------------------------
            SECTION bss
fp          RMB  2                     ; fopen's FILE
fmode       RMB  1                     ; ... DOS's mode
fflags      RMB  1                     ; ... the FILE's flags
fkind       RMB  1                     ; ... 'r', 'w' or 'a'
fplus       RMB  1                     ; ... "+"
            ENDSECT
;------------------------------------------------------------------------------
; End of fileio.asm
;------------------------------------------------------------------------------
