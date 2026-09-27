;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 utilities
;    FILE: move.asm
;
; MOVE.COM: moves (or renames) a file:
;
;   MOVE from [to]
;
; The destination follows COPY's rules: with no "to", the current directory under
; the source's own name; if "to" is a directory (one that exists, or a path ending
; in "/"), in it under the source's own name; otherwise "to" is the new path.
;
; An existing file is never overwritten ("Already exists"). Within one directory
; the entry is just renamed (B_RENAME_NAME), so a directory can be renamed too;
; to another directory a file is copied and then the original deleted (DOS has no
; call that moves an entry between directories). If the copy fails, the partial
; copy is deleted and the original is left alone.
;------------------------------------------------------------------------------
    INCLUDE defines.d
;------------------------------------------------------------------------------
MV_BASE     equ  $4000
PATHMAX     equ  128               ; a path buffer, with its NUL
ST_ATTR     equ  8                 ; where the attribute is in B_STAT's 16 bytes
;------------------------------------------------------------------------------
    ORG  MV_BASE-EXE_HDRSIZE
    FDB  EXE_MAGIC             ; the program header
    FDB  MV_BASE               ; load address
    FDB  START                 ; entry
    FDB  0                     ; flags
;------------------------------------------------------------------------------
START       LDS  #$7F00
            LDA  #B_ARGS               ; the tail, copied (it lives in DOS's RAM)
            SWI2
            LDY  #ARGBUF
            LDB  #PATHMAX-1
MV_TAIL     LDA  ,X+
            STA  ,Y+
            BEQ  MV_SPLIT
            DECB
            BNE  MV_TAIL
            CLR  ,Y
MV_SPLIT    LDX  #ARGBUF               ; SRCP = the first word, DSTP = the second (or 0)
            JSR  SKIPSP
            LBEQ USAGE
            STX  SRCP
            JSR  ENDWORD
            JSR  SKIPSP
            BNE  MV_HASDST
            LDX  #0
MV_HASDST   STX  DSTP
            BEQ  MV_NAMES
            JSR  ENDWORD
MV_NAMES    JSR  DSTNAME
            LBCS FAIL
;------------------------------------------------------------------------------
; The source must exist; the destination must not.
            LDX  SRCP
            LDY  #STATBUF
            LDA  #B_STAT
            SWI2
            LBCS FAIL
            LDA  STATBUF+ST_ATTR
            STA  SRCATTR
            LDX  DSTP
            LDY  #STATBUF
            LDA  #B_STAT
            SWI2
            BCS  MV_DSTFREE
            LDA  #ERR_EXISTS
            LBRA FAIL
MV_DSTFREE  CMPA #ERR_NOTFOUND
            LBNE FAIL                  ; (a bad path, a missing directory, ...)
;------------------------------------------------------------------------------
; The same directory? Each one's parent, as DOS names it (CD there, ask, CD back).
            LDX  #ORIGCWD
            LDY  #PATHMAX
            LDA  #B_GETCWD
            SWI2
            LBCS FAIL
            LDX  SRCP
            LDY  #CANON1
            JSR  PARENTOF
            LBCS FAIL
            STX  SRCNAME
            LDX  DSTP
            LDY  #CANON2
            JSR  PARENTOF
            LBCS FAIL
            STX  DSTNAMEP
            LDX  #CANON1
            LDY  #CANON2
MV_CMP      LDA  ,X+
            CMPA ,Y+
            BNE  MV_OTHER
            TSTA
            BNE  MV_CMP
;------------------------------------------------------------------------------
; Same directory: a rename.
            LDX  SRCP
            LDY  DSTNAMEP
            LDA  #B_RENAME_NAME
            SWI2
            LBCS FAIL
            BRA  MOVED
;------------------------------------------------------------------------------
; Another directory: copy the file, then delete the original.
MV_OTHER    LDA  SRCATTR
            ANDA #ATTR_DIR
            BEQ  MV_COPY
            LDX  #MSG_DIRMOVE
            LBRA SAY
MV_COPY     JSR  COPYFILE
            BCC  MV_KILL
            STA  ERRSAVE               ; a partial copy: deleted, the original kept
            LDX  DSTP
            LDA  #B_KILL_NAME
            SWI2
            LDA  ERRSAVE
            BRA  FAIL
MV_KILL     LDX  SRCP
            LDA  #B_KILL_NAME
            SWI2
            BCS  FAIL
MOVED       LDX  #MSG_MOVED
            BRA  SAY
;------------------------------------------------------------------------------
; X = a string: past its blanks. Z set (A = 0) if nothing is left.
SKIPSP      LDA  ,X
            CMPA #' '
            BNE  SS_DONE
            LEAX 1,X
            BRA  SKIPSP
SS_DONE     TSTA
            RTS
; X = a word: its end (a blank) becomes a NUL; X -> past it.
ENDWORD     LDA  ,X+
            BEQ  EW_END
            CMPA #' '
            BNE  ENDWORD
            CLR  -1,X
            RTS
EW_END      LEAX -1,X                  ; (stay on the NUL)
            RTS
;------------------------------------------------------------------------------
EXIT        LDA  #B_EXIT
            SWI2
USAGE       LDX  #MSG_USAGE
SAY         BSR  PUTS
            BRA  EXIT
FAIL        LDX  #ERRMSGS              ; A = the error: its message, if it has one
FL_FIND     LDB  ,X+
            BEQ  FL_NUM
            CMPA -1,X
            BEQ  SAY
FL_SKIP     TST  ,X+
            BNE  FL_SKIP
            BRA  FL_FIND
FL_NUM      LDY  #CANON1               ; "Error $nn"
            BSR  HEXBYTE
            CLR  ,Y
            LDX  #MSG_ERR
            BSR  PUTS
            LDX  #CANON1
            BSR  PUTS
            LDX  #MSG_CRLF
            BRA  SAY
PUTS        LDB  #F_STDOUT             ; X = a NUL-terminated string
            LDA  #B_PUTS
            SWI2
            RTS
; A as two hex digits at Y (Y moves on).
HEXBYTE     PSHS A
            LSRA
            LSRA
            LSRA
            LSRA
            BSR  HEXDIG
            PULS A
            ANDA #$0F
HEXDIG      CMPA #10
            BLO  HX_NUM
            ADDA #7
HX_NUM      ADDA #'0'
            STA  ,Y+
            RTS
;------------------------------------------------------------------------------
; The destination (SRCP = from, DSTP = to or 0), made into a file's path in DSTP:
; with no "to", the source's own name in the current directory; if "to" is a
; directory (one that exists, or a path ending in "/"), the source's name in it;
; otherwise "to" itself. Carry set + A = ERR_BADPATH if it would be too long.
; (The same rules as the shell's COPY.)
DSTNAME     LDX  SRCP                  ; SRCNM = the source's last component
            STX  SRCNM
DN_SCAN     LDA  ,X+
            BEQ  DN_DST
            CMPA #'/'
            BNE  DN_SCAN
            STX  SRCNM
            BRA  DN_SCAN
DN_DST      LDX  DSTP
            BNE  DN_GIVEN
            LDX  SRCNM                 ; none: the source's name, here
            STX  DSTP
            ANDCC #$FE
            RTS
DN_GIVEN    LDA  ,X+                   ; ends in "/"?
            BNE  DN_GIVEN
            LDA  -2,X
            CMPA #'/'
            BEQ  DN_INDIR
            LDX  DSTP                  ; a directory that exists?
            LDA  #B_OPENDIR
            SWI2
            BCS  DN_FILE
            TFR  A,B
            LDA  #B_CLOSEDIR
            SWI2
            LDA  #'/'                  ; "to/name"
            BRA  DN_BUILD
DN_INDIR    CLRA                       ; "to/" + "name"
DN_BUILD    LDY  #DSTBUF
            LDX  DSTP
            LDB  #PATHMAX-1            ; room left in DSTBUF, less its NUL
DN_CPDST    TST  ,X
            BEQ  DN_SEP
            DECB
            BEQ  DN_LONG
            LDE  ,X+
            STE  ,Y+
            BRA  DN_CPDST
DN_SEP      TSTA
            BEQ  DN_NAME
            DECB
            BEQ  DN_LONG
            STA  ,Y+
DN_NAME     LDX  SRCNM
DN_CPNAME   LDA  ,X+
            STA  ,Y+
            BEQ  DN_BUILT
            DECB
            BNE  DN_CPNAME
DN_LONG     LDA  #ERR_BADPATH
            ORCC #1
            RTS
DN_BUILT    LDX  #DSTBUF
            STX  DSTP
DN_FILE     ANDCC #$FE
            RTS
;------------------------------------------------------------------------------
; X = a path: its directory, as B_GETCWD names it, into Y (PATHMAX bytes).
; -> X = the path's last component. Carry set + A = the error if the directory
; isn't there (the current directory is always put back).
PARENTOF    STY  PO_OUT
            STX  PO_START
            STX  PO_NAME
            LDU  #0                    ; U -> the last "/", or 0 if none
PO_SCAN     LDA  ,X+
            BEQ  PO_END
            CMPA #'/'
            BNE  PO_SCAN
            LEAU -1,X
            STX  PO_NAME
            BRA  PO_SCAN
PO_END      LDY  #PARBUF
            CMPU #0
            BNE  PO_SLASH
            LDD  #'.*256               ; no "/": the current directory
            STD  ,Y
            BRA  PO_CD
PO_SLASH    CMPU PO_START              ; "/name": the root
            BNE  PO_PART
            LDD  #'/*256
            STD  ,Y
            BRA  PO_CD
PO_PART     LDX  PO_START              ; "dir/name": everything before the "/"
PO_COPY     CMPR X,U
            BEQ  PO_CUT
            LDA  ,X+
            STA  ,Y+
            BRA  PO_COPY
PO_CUT      CLR  ,Y
PO_CD       LDX  #PARBUF
            LDA  #B_CHDIR
            SWI2
            BCS  PO_RET
            LDX  PO_OUT
            LDY  #PATHMAX
            LDA  #B_GETCWD
            SWI2
            PSHS CC,A
            LDX  #ORIGCWD
            LDA  #B_CHDIR
            SWI2
            PULS CC,A
PO_RET      LDX  PO_NAME
            RTS
;------------------------------------------------------------------------------
; Copies SRCP to DSTP (a new file). Carry set + A = the error.
COPYFILE    LDX  SRCP
            LDE  #FOPEN_READ
            LDA  #B_FOPEN_NAME
            SWI2
            BCS  CF_RET
            STA  FH1
            LDX  DSTP
            LDE  #FOPEN_WRITE
            LDA  #B_FOPEN_NAME
            SWI2
            BCS  CF_FAIL1
            STA  FH2
CF_LOOP     LDB  FH1
            LDX  #IOBUF
            LDY  #512
            LDA  #B_FREAD
            SWI2
            BCC  CF_GOT
            CMPA #ERR_EOF
            BEQ  CF_DONE
            BRA  CF_FAIL2
CF_GOT      CMPX #0
            BEQ  CF_DONE
            TFR  X,Y
            LDX  #IOBUF
            LDB  FH2
            LDA  #B_FWRITE
            SWI2
            BCS  CF_FAIL2
            BRA  CF_LOOP
CF_DONE     LDB  FH2
            LDA  #B_FCLOSE_NAME
            SWI2
            BCS  CF_FAIL1
            LDB  FH1
            LDA  #B_FCLOSE_NAME
            SWI2
            ANDCC #$FE
CF_RET      RTS
CF_FAIL2    STA  ERRSAVE               ; close both, keep the first error
            LDB  FH2
            LDA  #B_FCLOSE_NAME
            SWI2
            LDA  ERRSAVE
CF_FAIL1    STA  ERRSAVE
            LDB  FH1
            LDA  #B_FCLOSE_NAME
            SWI2
            LDA  ERRSAVE
            ORCC #1
            RTS
;------------------------------------------------------------------------------
MSG_USAGE   FCC  "Usage: MOVE from [to]"
MSG_CRLF    FCB  CR,LF,0
MSG_MOVED   FCC  "        1 file moved"
            FCB  CR,LF,0
MSG_DIRMOVE FCC  "A directory can only be renamed in place"
            FCB  CR,LF,0
MSG_ERR     FCC  "Error $"
            FCB  0
ERRMSGS     FCB  ERR_NOTFOUND          ; (code, message; 0 ends the list)
            FCC  "File not found"
            FCB  CR,LF,0
            FCB  ERR_EXISTS
            FCC  "Already exists"
            FCB  CR,LF,0
            FCB  ERR_NOSPACE
            FCC  "Disk full"
            FCB  CR,LF,0
            FCB  ERR_ISOPEN
            FCC  "File is in use"
            FCB  CR,LF,0
            FCB  ERR_NOTDIR
            FCC  "Not a directory"
            FCB  CR,LF,0
            FCB  ERR_ISDIR
            FCC  "Is a directory"
            FCB  CR,LF,0
            FCB  ERR_BADPATH
            FCC  "Bad name or path"
            FCB  CR,LF,0
            FCB  ERR_NOSLOT
            FCC  "Too many open files"
            FCB  CR,LF,0
            FCB  ERR_IOERR
            FCC  "Disk error"
            FCB  CR,LF,0
            FCB  0
;------------------------------------------------------------------------------
; Variables and buffers are just addresses after the last byte of code.
;------------------------------------------------------------------------------
ARGBUF      equ  *                     ; the command tail
DSTBUF      equ  ARGBUF+PATHMAX        ; a destination built by DSTNAME
ORIGCWD     equ  DSTBUF+PATHMAX        ; the current directory at the start
PARBUF      equ  ORIGCWD+PATHMAX       ; a path's directory part
CANON1      equ  PARBUF+PATHMAX        ; the source's directory, as DOS names it
CANON2      equ  CANON1+PATHMAX        ; the destination's
STATBUF     equ  CANON2+PATHMAX        ; 16
IOBUF       equ  STATBUF+16            ; 512
SRCP        equ  IOBUF+512             ; 2
DSTP        equ  SRCP+2                ; 2
SRCNM       equ  DSTP+2                ; 2
SRCNAME     equ  SRCNM+2               ; 2
DSTNAMEP    equ  SRCNAME+2             ; 2
PO_OUT      equ  DSTNAMEP+2            ; 2
PO_NAME     equ  PO_OUT+2              ; 2
PO_START    equ  PO_NAME+2             ; 2
SRCATTR     equ  PO_START+2
ERRSAVE     equ  SRCATTR+1
FH1         equ  ERRSAVE+1
FH2         equ  FH1+1
MV_END      equ  FH2+1
;------------------------------------------------------------------------------
; End of move.asm
;------------------------------------------------------------------------------
