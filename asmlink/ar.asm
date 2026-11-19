;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 librarian
;    FILE: ar.asm
;
; AR.COM: makes and reads the archives (libraries) LINK takes with -l, in
; lwar's format (lwtools 4.20), so that lwar and lwlink on a PC can use them
; too, and AR can use theirs. An archive is "LWAR1V", then each member: its
; name, a NUL, its length (32 bits, high byte first) and its bytes; a NUL ends
; it.
;
;   AR [options] archive [file ...]
;     -c, --create     a new archive of the files (an old one is deleted)
;     -a, --add        the files added at the end (the archive made if missing)
;     -r, --replace    the files added, each member of the same name dropped
;     -l, --list       the members: "NAME: LENGTH bytes" (LENGTH in hex)
;     -x, --extract    the members named (or all of them) written out as files
;     -m, --merge      a file that is an archive adds its members, not itself
;     -n, --nopaths    only a name's last component (after its last /) is kept,
;                      and compared, and used to extract
;     @FILE            more arguments, from FILE (spaces and line ends
;                      separate them: the shell's command line is short)
;
; As lwar does, a member's name is the file's name as given (with -n, its last
; component), and -c, -a and -r keep the members in order, the new ones last.
; Unlike lwar, the archive is written to ARTEMP.TMP beside it and only renamed
; into place once it is complete, so a failure leaves the old archive alone.
;------------------------------------------------------------------------------
    INCLUDE defines.d
;------------------------------------------------------------------------------
DPAGE       equ  $3400             ; the direct page (not part of the file)
PL_BASE     equ  $3500
STACKTOP    equ  $C000
PATHMAX     equ  79
MAXFILES    equ  64
RSPMAX      equ  1023              ; an @FILE's text
BUFSZ       equ  4096              ; copying
; The operations
OP_ADD      equ  1
OP_CREATE   equ  2
OP_REPLACE  equ  3
OP_LIST     equ  4
OP_EXTRACT  equ  5
;------------------------------------------------------------------------------
; DVAR name,size: a direct-page variable. VAR name,size: one after the program.
DVAR        MACRO
\1          equ  DP_VP
DP_VP       SET  DP_VP+\2
            ENDM
VAR         MACRO
\1          equ  VP
VP          SET  VP+\2
            ENDM
DP_VP       SET  DPAGE
            DVAR MA,4                  ; (pa_util.asm)
            DVAR MB,4
            DVAR MQ,4
            DVAR MSIGN,1
            DVAR OP,1                  ; what to do
            DVAR MERGE,1               ; -m
            DVAR NOPATHS,1             ; -n
            DVAR NFILES,1
            DVAR HAVEAR,1              ; the archive was named
            DVAR RH,1                  ; the file being read (a handle)
            DVAR WH,1                  ; ... and written
            DVAR ARH,1                 ; the old archive
            DVAR AROPEN,1
            DVAR OUTH,1                ; the new one (ARTEMP.TMP)
            DVAR OUTOPEN,1
            DVAR INH,1                 ; a file added or extracted
            DVAR INOPEN,1
            DVAR EXISTED,1             ; there was an old archive
            DVAR LEN,4                 ; a member's length
            DVAR CHUNK,2
            DVAR CURF,1                ; the file being added
            DVAR RSPIN,1               ; reading an @FILE
DP_END      equ  DP_VP
;------------------------------------------------------------------------------
    ORG  PL_BASE-EXE_HDRSIZE
    FDB  EXE_MAGIC                 ; the program header
    FDB  PL_BASE                   ; load address
    FDB  START                     ; entry
    FDB  0                         ; flags
    SETDP DPAGE/256
;------------------------------------------------------------------------------
START       LDS  #STACKTOP
            LDA  #DPAGE/256
            TFR  A,DP
            LDX  #ZERO                 ; clear the variables
            LDY  #DPAGE
            LDW  #DP_END-DPAGE
            TFM  X,Y+
            LDY  #VARS
            LDW  #VARSEND-VARS
            TFM  X,Y+
            JSR  CMDLINE
            LDA  <OP
            CMPA #OP_LIST
            LBEQ DOLIST
            CMPA #OP_EXTRACT
            LBEQ DOEXTRACT
            JMP  DOBUILD
; The end: every file closed (a new archive not finished deleted).
QUIT        JSR  CLOSEALL
            LDA  #B_EXIT
            SWI2
; X = a message: printed, and everything given up.
FATAL       JSR  PRINTS
            JSR  PRINTNL
            BRA  QUIT
CLOSEALL    TST  <AROPEN
            BEQ  CA_IN
            CLR  <AROPEN
            LDB  <ARH
            LDA  #B_FCLOSE_NAME
            SWI2
CA_IN       TST  <INOPEN
            BEQ  CA_OUT
            CLR  <INOPEN
            LDB  <INH
            LDA  #B_FCLOSE_NAME
            SWI2
CA_OUT      TST  <OUTOPEN
            BEQ  CA_RET
            CLR  <OUTOPEN
            LDB  <OUTH
            LDA  #B_FCLOSE_NAME
            SWI2
            LDX  #TMPNAME
            LDA  #B_KILL_NAME
            SWI2
CA_RET      RTS
;------------------------------------------------------------------------------
; The command line.
;------------------------------------------------------------------------------
CMDLINE     LDA  #B_ARGS
            SWI2
            JSR  SKIPSP
            TST  ,X
            LBEQ USAGE
            JSR  CLPARSE
            TST  <HAVEAR
            BNE  CL_HAVEAR
            LDX  #M_NOAR
            JMP  FATAL
CL_HAVEAR   TST  <OP
            BNE  CL_RET
            LDX  #M_NOOP
            JMP  FATAL
CL_RET      RTS
; X = arguments: taken in (to the end of the string).
CLPARSE
CP_NEXT     JSR  SKIPSP
            LDA  ,X
            BNE  CP_ARG
            RTS
CP_ARG      CMPA #'@'
            LBEQ CP_RESP
            CMPA #'-'
            BNE  CP_WORD
            LDA  1,X
            CMPA #'-'
            BEQ  CP_LONG
            LEAX 1,X                   ; -letters
CP_SHORT    LDA  ,X
            BEQ  CP_NEXT
            JSR  ISSPACE
            BCC  CP_NEXT
            LEAX 1,X
            JSR  SHORTOPT
            BRA  CP_SHORT
CP_LONG     LEAX 2,X                   ; --word
            LDY  #NAMEBUF
            JSR  GETWORD
            PSHS X
            LDX  #LONGOPTS
CP_LLOOP    LDA  ,X                    ; each: the letter, then the word
            LBEQ USAGE
            LDY  #NAMEBUF
            LEAX 1,X
            JSR  STRCMP
            BEQ  CP_LHIT
CP_LSKIP    TST  ,X+
            BNE  CP_LSKIP
            BRA  CP_LLOOP
CP_LHIT     LDA  -1,X
            JSR  SHORTOPT
            PULS X
            BRA  CP_NEXT
CP_WORD     TST  <HAVEAR               ; the archive, then the files
            BNE  CP_FILE
            LDY  #ARNAME
            JSR  GETWORD
            INC  <HAVEAR
            BRA  CP_NEXT
CP_FILE     LDA  <NFILES
            CMPA #MAXFILES
            BLO  CP_ROOM
            LDX  #M_MANY
            JMP  FATAL
CP_ROOM     LDB  #PATHMAX+1
            MUL
            ADDD #FILETAB
            TFR  D,Y
            JSR  GETWORD
            INC  <NFILES
            LBRA  CP_NEXT
CP_RESP     TST  <RSPIN                ; @FILE (not inside another one)
            LBNE USAGE
            LEAX 1,X
            LDY  #NAMEBUF
            JSR  GETWORD
            PSHS X
            LDX  #NAMEBUF
            LDE  #FOPEN_READ
            LDA  #B_FOPEN_NAME
            SWI2
            BCC  CP_ROPEN
            LDX  #M_NOFILE
            JSR  PRINTS
            LDX  #NAMEBUF
            JMP  FATAL
CP_ROPEN    STA  <INH
            INC  <INOPEN
            TFR  A,B
            LDX  #RSPBUF
            LDY  #RSPMAX
            LDA  #B_FREAD
            SWI2
            PSHS X                     ; (bytes read)
            CLR  <INOPEN
            LDB  <INH
            LDA  #B_FCLOSE_NAME
            SWI2
            PULS D
            LDX  #RSPBUF
            LEAY D,X
            CLR  ,Y                    ; NUL-terminated, line ends as spaces
CP_RSP      LDA  ,X
            BEQ  CP_RDONE
            CMPA #' '
            BHS  CP_RKEEP
            LDA  #' '
            STA  ,X
CP_RKEEP    LEAX 1,X
            BRA  CP_RSP
CP_RDONE    INC  <RSPIN
            LDX  #RSPBUF
            JSR  CLPARSE
            CLR  <RSPIN
            PULS X
            LBRA CP_NEXT
; A = an option letter: done.
SHORTOPT    CMPA #'c'
            BNE  SO_A
            LDB  #OP_CREATE
            BRA  SO_OP
SO_A        CMPA #'a'
            BNE  SO_R
            LDB  #OP_ADD
            BRA  SO_OP
SO_R        CMPA #'r'
            BNE  SO_L
            LDB  #OP_REPLACE
            BRA  SO_OP
SO_L        CMPA #'l'
            BNE  SO_X
            LDB  #OP_LIST
            BRA  SO_OP
SO_X        CMPA #'x'
            BNE  SO_M
            LDB  #OP_EXTRACT
SO_OP       STB  <OP
            RTS
SO_M        CMPA #'m'
            BNE  SO_N
            INC  <MERGE
            RTS
SO_N        CMPA #'n'
            BNE  SO_D
            INC  <NOPATHS
            RTS
SO_D        CMPA #'d'                  ; (lwar's debug: accepted, ignored)
            BNE  USAGE
            RTS
USAGE       LDX  #M_USAGE
            JSR  PRINTS
            JMP  QUIT
; X -> Y: a word (to a space or the end), at most PATHMAX characters.
GETWORD     LDB  #PATHMAX
GW_LOOP     LDA  ,X
            BEQ  GW_END
            JSR  ISSPACE
            BCC  GW_END
            LEAX 1,X
            TSTB
            BEQ  GW_LOOP
            STA  ,Y+
            DECB
            BRA  GW_LOOP
GW_END      CLR  ,Y
            RTS
; B = a file (0 up) -> X = its name.
FILENAME    PSHS D
            LDA  #PATHMAX+1
            MUL
            ADDD #FILETAB
            TFR  D,X
            PULS D,PC
; X = a name: -> X = what lwar keeps of it (with -n, what follows its last /).
BASENAME    TST  <NOPATHS
            BEQ  BN_RET
            PSHS Y
            TFR  X,Y
BN_LOOP     LDA  ,Y+
            BEQ  BN_END
            CMPA #'/'
            BNE  BN_LOOP
            TFR  Y,X
            BRA  BN_LOOP
BN_END      PULS Y
BN_RET      RTS
;------------------------------------------------------------------------------
; Reading an archive: the file RH.
;------------------------------------------------------------------------------
; -> A = the next byte; carry set at the end of the file.
RBYTE       PSHS B
            LDB  <RH
            LDA  #B_FGETC
            SWI2
            PULS B,PC
; ARNAME opened (ARH, RH) and its "LWAR1V" checked. Carry set if it can't be
; opened.
OPENAR      LDX  #ARNAME
            LDE  #FOPEN_READ
            LDA  #B_FOPEN_NAME
            SWI2
            BCS  OA_RET
            STA  <ARH
            STA  <RH
            INC  <AROPEN
            LDX  #RSPBUF
            LDY  #6
            TFR  A,B
            LDA  #B_FREAD
            SWI2
            BCS  OA_BAD
            CMPX #6
            BNE  OA_BAD
            LDX  #RSPBUF
            LDY  #M_MAGIC
            LDB  #6
OA_CMP      LDA  ,X+
            CMPA ,Y+
            BNE  OA_BAD
            DECB
            BNE  OA_CMP
            ANDCC #$FE
OA_RET      RTS
OA_BAD      LDX  #ARNAME               ; "NAME is not a valid archive file."
            JSR  PRINTS
            LDX  #M_NOTAR
            JMP  FATAL
; The next member's name (into NAMEBUF) and length (LEN). Carry set at the end
; of the archive (a NUL, or the end of the file).
MEMBER      JSR  RBYTE
            BCS  MB_END
            TSTA
            BEQ  MB_END
            LDX  #NAMEBUF
            LDB  #PATHMAX
MB_NAME     STA  ,X
            TSTA
            BEQ  MB_LEN
            TSTB
            BEQ  MB_NEXT
            LEAX 1,X
            DECB
MB_NEXT     JSR  RBYTE
            BCC  MB_NAME
            BRA  BADAR
MB_LEN      LDX  #LEN
            LDB  #4
MB_LBYTE    JSR  RBYTE
            BCS  BADAR
            STA  ,X+
            DECB
            BNE  MB_LBYTE
            ANDCC #$FE
            RTS
MB_END      ORCC #1
            RTS
BADAR       LDX  #M_BADAR
            JMP  FATAL
; The file RH: LEN bytes skipped.
SKIPLEN     LDB  <RH
            LDX  <LEN
            LDY  <LEN+2
            LDE  #SEEK_CUR
            LDA  #B_FSEEK_NAME
            SWI2
            BCS  BADAR
            RTS
; LEN bytes from RH to WH.
COPYLEN     LDD  <LEN                  ; this time: at most BUFSZ
            BNE  CY_BIG
            LDD  <LEN+2
            BEQ  CY_RET
            CMPD #BUFSZ
            BLS  CY_N
CY_BIG      LDD  #BUFSZ
CY_N        STD  <CHUNK
            TFR  D,Y
            LDX  #BUF
            LDB  <RH
            LDA  #B_FREAD
            SWI2
            BCS  BADAR
            CMPX <CHUNK
            BNE  BADAR
            LDY  <CHUNK
            LDX  #BUF
            JSR  WRITE
            LDQ  <LEN
            SUBW <CHUNK
            SBCD #0
            STQ  <LEN
            BRA  COPYLEN
CY_RET      RTS
; X = bytes, Y = how many: written to WH.
WRITE       CMPY #0
            BEQ  WR_RET
            LDB  <WH
            LDA  #B_FWRITE
            SWI2
            BCS  WR_FAIL
WR_RET      RTS
WR_FAIL     LDX  #M_WRITEERR
            JMP  FATAL
; X = a string: written to WH, with its NUL.
WRITESTR    JSR  STRLEN
            ADDD #1
            TFR  D,Y
            BRA  WRITE
; LEN: written to WH (4 bytes, high first).
WRITELEN    LDX  #LEN
            LDY  #4
            BRA  WRITE
;------------------------------------------------------------------------------
; -l: the members.
;------------------------------------------------------------------------------
DOLIST      JSR  OPENAR
            BCC  DL_LOOP
            LDX  #M_NOOPEN
            JSR  PRINTS
            LDX  #ARNAME
            JMP  FATAL
DL_LOOP     JSR  MEMBER
            LBCS QUIT
            LDX  #NAMEBUF              ; "NAME: LLLL bytes" (lwar's %04lx)
            JSR  PRINTS
            LDX  #M_COLON
            JSR  PRINTS
            LDX  #NUMBUF
            LDY  #LEN
            LDB  #4
DL_HEX      LDA  ,Y+
            JSR  HEX2L
            DECB
            BNE  DL_HEX
            CLR  ,X
            LDX  #NUMBUF               ; at least 4 digits
            LDB  #4
DL_ZERO     LDA  ,X
            CMPA #'0'
            BNE  DL_NUM
            LEAX 1,X
            DECB
            BNE  DL_ZERO
DL_NUM      JSR  PRINTS
            LDX  #M_BYTES
            JSR  PRINTS
            JSR  PRINTNL
            JSR  SKIPLEN
            BRA  DL_LOOP
; A = a byte: two lower-case hex digits at X (X advances).
HEX2L       PSHS A
            LSRA
            LSRA
            LSRA
            LSRA
            BSR  HEXDL
            LDA  ,S
            ANDA #$0F
            BSR  HEXDL
            PULS A,PC
HEXDL       CMPA #10
            BLO  HL_NUM
            ADDA #'a'-'0'-10
HL_NUM      ADDA #'0'
            STA  ,X+
            RTS
;------------------------------------------------------------------------------
; -x: the members named (all of them if none are), each to a file.
;------------------------------------------------------------------------------
DOEXTRACT   JSR  OPENAR
            BCC  DX_LOOP
            LDX  #M_NOOPEN
            JSR  PRINTS
            LDX  #ARNAME
            JMP  FATAL
DX_LOOP     JSR  MEMBER
            LBCS QUIT
            LDX  #NAMEBUF
            JSR  BASENAME
            STX  <CHUNK                ; (the name it goes to)
            JSR  WANTED
            BCS  DX_SKIP
            LDX  <CHUNK
            LDE  #FOPEN_WRITE
            LDA  #B_FOPEN_NAME
            SWI2
            BCC  DX_OPEN
            LDX  #M_NOEXTR             ; "Cannot extract 'NAME'"
            JSR  PRINTS
            LDX  <CHUNK
            JSR  PRINTS
            LDX  #M_QUOTE
            JMP  FATAL
DX_OPEN     STA  <INH
            STA  <WH
            INC  <INOPEN
            JSR  COPYLEN
            CLR  <INOPEN
            LDB  <INH
            LDA  #B_FCLOSE_NAME
            SWI2
            BRA  DX_LOOP
DX_SKIP     JSR  SKIPLEN
            BRA  DX_LOOP
; X = a member's name (as BASENAME leaves it): carry clear if it is one of the
; files (or none were named). Keeps X.
WANTED      TST  <NFILES
            BEQ  WA_YES
            CLRB
WA_LOOP     PSHS B,X
            JSR  FILENAME
            JSR  BASENAME
            TFR  X,Y
            LDX  1,S
            JSR  STRCMP
            PULS B,X
            BEQ  WA_YES
            INCB
            CMPB <NFILES
            BLO  WA_LOOP
            ORCC #1
            RTS
WA_YES      ANDCC #$FE
            RTS
;------------------------------------------------------------------------------
; -c, -a, -r: a new archive, ARTEMP.TMP in the archive's directory: the old
; one's members (-a: all; -r: those not being replaced), then the files; then
; the old one deleted and the new one renamed in its place.
;------------------------------------------------------------------------------
DOBUILD     LDX  #ARNAME               ; TMPNAME: the directory, ARTEMP.TMP;
            LDY  #TMPNAME              ; NEWNAME: the archive's own name
            LDU  #TMPNAME
DB_DIR      LDA  ,X+
            STA  ,Y+
            BEQ  DB_DIREND
            CMPA #'/'
            BNE  DB_DIR
            TFR  Y,U                   ; (just past the last /)
            STX  <CHUNK
            BRA  DB_DIR
DB_DIREND   LDX  <CHUNK
            BNE  DB_HASDIR
            LDX  #ARNAME
DB_HASDIR   LDY  #NEWNAME
            JSR  STRCPY
            TFR  U,Y
            LDX  #M_TMP
            JSR  STRCPY
            LDA  <OP                   ; -c: the old one goes first, as in lwar
            CMPA #OP_CREATE
            BNE  DB_OPEN
            LDX  #ARNAME
            LDA  #B_KILL_NAME
            SWI2
DB_OPEN     LDX  #TMPNAME
            LDE  #FOPEN_WRITE
            LDA  #B_FOPEN_NAME
            SWI2
            BCC  DB_OUT
            LDX  #M_NOCREATE
            JSR  PRINTS
            LDX  #TMPNAME
            JMP  FATAL
DB_OUT      STA  <OUTH
            STA  <WH
            INC  <OUTOPEN
            LDX  #M_MAGIC
            LDY  #6
            JSR  WRITE
            LDA  <OP                   ; the old members
            CMPA #OP_CREATE
            BEQ  DB_FILES
            JSR  OPENAR
            BCS  DB_FILES              ; (none: a new archive)
            INC  <EXISTED
DB_OLD      JSR  MEMBER
            BCS  DB_OLDEND
            LDX  #NAMEBUF
            LDA  <OP
            CMPA #OP_REPLACE
            BNE  DB_KEEP
            JSR  BASENAME              ; -r: one being replaced is dropped
            TST  <NFILES
            BEQ  DB_KEEP
            JSR  WANTED
            BCC  DB_DROP
DB_KEEP     JSR  WRITESTR
            JSR  WRITELEN
            JSR  COPYLEN
            BRA  DB_OLD
DB_DROP     JSR  SKIPLEN
            BRA  DB_OLD
DB_OLDEND   CLR  <AROPEN
            LDB  <ARH
            LDA  #B_FCLOSE_NAME
            SWI2
DB_FILES    CLR  <CURF                 ; the files
DB_FILE     LDB  <CURF
            CMPB <NFILES
            LBHS DB_END
            JSR  FILENAME
            LDE  #FOPEN_READ
            LDA  #B_FOPEN_NAME
            SWI2
            BCC  DB_FOPEN
            LDX  #M_NOFILE
            JSR  PRINTS
            LDB  <CURF
            JSR  FILENAME
            JMP  FATAL
DB_FOPEN    STA  <INH
            STA  <RH
            INC  <INOPEN
            TST  <MERGE                ; -m: an archive's members
            BEQ  DB_WHOLE
            TFR  A,B
            LDX  #RSPBUF
            LDY  #6
            LDA  #B_FREAD
            SWI2
            BCS  DB_REWIND
            CMPX #6
            BNE  DB_REWIND
            LDX  #RSPBUF
            LDY  #M_MAGIC
            LDB  #6
DB_MCMP     LDA  ,X+
            CMPA ,Y+
            BNE  DB_REWIND
            DECB
            BNE  DB_MCMP
DB_MERGE    JSR  MEMBER
            BCS  DB_FDONE
            LDX  #NAMEBUF
            JSR  WRITESTR
            JSR  WRITELEN
            JSR  COPYLEN
            BRA  DB_MERGE
DB_REWIND   LDB  <INH                  ; (not an archive: from the start)
            LDX  #0
            LDY  #0
            LDE  #SEEK_SET
            LDA  #B_FSEEK_NAME
            SWI2
DB_WHOLE    LDB  <INH                  ; the file: its name, length, bytes
            LDX  #RSPBUF
            LDA  #B_FSTAT_NAME
            SWI2
            LDQ  RSPBUF
            STQ  <LEN
            LDB  <CURF
            JSR  FILENAME
            JSR  BASENAME
            JSR  WRITESTR
            JSR  WRITELEN
            JSR  COPYLEN
DB_FDONE    CLR  <INOPEN
            LDB  <INH
            LDA  #B_FCLOSE_NAME
            SWI2
            INC  <CURF
            LBRA DB_FILE
DB_END      LDX  #ZERO                 ; the end
            LDY  #1
            JSR  WRITE
            CLR  <OUTOPEN
            LDB  <OUTH
            LDA  #B_FCLOSE_NAME
            SWI2
            BCS  WR_FAIL2
            TST  <EXISTED              ; the old one out, the new one in
            BEQ  DB_RENAME
            LDX  #ARNAME
            LDA  #B_KILL_NAME
            SWI2
DB_RENAME   LDX  #TMPNAME
            LDY  #NEWNAME
            LDA  #B_RENAME_NAME
            SWI2
            LBCC QUIT
            LDX  #M_NORENAME
            JSR  PRINTS
            LDX  #TMPNAME
            JMP  FATAL
WR_FAIL2    LDX  #TMPNAME
            LDA  #B_KILL_NAME
            SWI2
            LDX  #M_WRITEERR
            JMP  FATAL
;------------------------------------------------------------------------------
    INCLUDE pa_util.asm
;------------------------------------------------------------------------------
M_MAGIC     FCC  "LWAR1V"
M_TMP       FCN  "ARTEMP.TMP"
LONGOPTS    FCB  'r'
            FCN  "replace"
            FCB  'x'
            FCN  "extract"
            FCB  'a'
            FCN  "add"
            FCB  'l'
            FCN  "list"
            FCB  'c'
            FCN  "create"
            FCB  'm'
            FCN  "merge"
            FCB  'n'
            FCN  "nopaths"
            FCB  'd'
            FCN  "debug"
            FCB  0
M_COLON     FCN  ": "
M_BYTES     FCN  " bytes"
M_QUOTE     FCN  "'"
M_USAGE     FCC  "Usage: AR -c|-a|-r|-l|-x [-m] [-n] archive [file ...]"
            FCB  CR,LF
            FCC  "  -c create  -a add  -r replace  -l list  -x extract"
            FCB  CR,LF
            FCC  "  -m add archives' members  -n names without paths"
            FCB  CR,LF
            FCC  "  @FILE more arguments from FILE"
            FCB  CR,LF,0
M_NOAR      FCN  "You must specify an archive file."
M_NOOP      FCN  "You must specify an operation."
M_MANY      FCN  "Too many files"
M_NOFILE    FCN  "Cannot open file "
M_NOOPEN    FCN  "Cannot open archive file "
M_NOTAR     FCN  " is not a valid archive file."
M_BADAR     FCN  "Bad archive file"
M_NOEXTR    FCN  "Cannot extract '"
M_NOCREATE  FCN  "Cannot create "
M_NORENAME  FCN  "Cannot rename "
M_WRITEERR  FCN  "Cannot write the archive (disk full?)"
;------------------------------------------------------------------------------
PL_END      equ  *
;------------------------------------------------------------------------------
; Variables and buffers after the program (none of this is in the file).
;------------------------------------------------------------------------------
VARS        equ  *
VP          SET  VARS
            VAR  ARNAME,PATHMAX+1
            VAR  TMPNAME,PATHMAX+16
            VAR  NEWNAME,PATHMAX+1
            VAR  NAMEBUF,PATHMAX+1
            VAR  NUMBUF,16
            VAR  FILETAB,MAXFILES*(PATHMAX+1)
            VAR  RSPBUF,RSPMAX+1
VARSEND     equ  VP
BUF         equ  VARSEND               ; copying (not cleared)
;------------------------------------------------------------------------------
; End of ar.asm
;------------------------------------------------------------------------------
