;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 C compiler
;    FILE: cc.asm
;
; CC.COM: compiles, assembles and links C programs. It runs CPP, CC1, ASM and
; LINK as children (B_EXEC with EXEC_CHILD), stopping at the first that fails.
;
;   CC [options] file...
;     file.c      preprocessed, compiled and assembled (FILE.I, FILE.ASM, FILE.O)
;     file.asm    assembled (file.s too)
;     anything else (file.o, lib.a ...) is LINK's
;     -c          stop at the .O files (-S: at the .ASM, -E: at the .I)
;     -o FILE     the output (with -c, -S or -E: one file's)
;     -I DIR, -D NAME[=VALUE], -U NAME     CPP's
;     -L DIR, -l LIB                       LINK's (/LIB, -lpug and -lc are always there)
;     -b N        CC1's: every function banked code, in overlay N (as if each
;                 file began with #pragma bank N)
;     -v          each command, shown as it's run
;     -q          quiet: no banner, and no line as each stage starts
;
; The files made on the way go in the current directory, named as the source
; with .I, .ASM and .O, and are deleted once used (the ones stopped at are
; kept). The program is the first file's name with .COM, unless -o says. The
; tools are looked for in the current directory, then along the search path
; (B_PATH). The exit code is 0, or 1 if something failed. Unless -q, it
; says what it is first, then "FILE: cpp" (cc1, asm) and "link: PROG.COM" as
; each stage starts, so that a long one is seen to be going.
;------------------------------------------------------------------------------
    INCLUDE defines.d
;------------------------------------------------------------------------------
DPAGE       equ  $3400
PA_BASE     equ  $3500
STACKTOP    equ  $F000
LINEMAX     equ  79                ; a command tail (B_EXEC's ARGMAX)
NAMEMAX     equ  79
MAXWORDS    equ  32
LISTMAX     equ  400               ; the objects, the options
;------------------------------------------------------------------------------
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
            DVAR STOP,1                ; 0 (link), 'c', 'S' or 'E'
            DVAR VERBOSE,1
            DVAR QUIET,1
            DVAR FAILED,1
            DVAR NWORDS,1
            DVAR NFILES,1
            DVAR WORDP,2               ; the next word (in WORDS)
            DVAR OUTSET,1              ; -o was given
            DVAR ISC,1                 ; the file being done: a .c (1) or .asm
            DVAR FILEP,2               ; its name
            DVAR PUTP,2                ; where APPEND adds
            DVAR PUTEND,2              ; and the end of the room there
DP_END      equ  DP_VP
;------------------------------------------------------------------------------
    ORG  PA_BASE-EXE_HDRSIZE
    FDB  EXE_MAGIC
    FDB  PA_BASE
    FDB  START
    FDB  0
    SETDP DPAGE/256
;------------------------------------------------------------------------------
START       LDS  #STACKTOP
            LDA  #DPAGE/256
            TFR  A,DP
            LDX  #ZERO                 ; clear the variables
            LDY  #DPAGE
            LDW  #DP_END-DPAGE
            TFM  X,Y+
            LDX  #ZERO
            LDY  #VARS
            LDW  #VARSEND-VARS
            TFM  X,Y+
            JSR  WORDSPLIT
            JSR  OPTIONS
            TST  <NFILES
            LBEQ USAGE
            TST  <STOP                 ; -o with -c/-S/-E: one file
            BEQ  ST_FILES
            TST  <OUTSET
            BEQ  ST_FILES
            LDA  <NFILES
            CMPA #1
            LBNE USAGE
ST_FILES    TST  <QUIET                ; the banner
            BNE  ST_FIRST
            LDX  #M_BANNER
            JSR  PRINTS
ST_FIRST    LDX  #FILES                ; each file
            LDB  <NFILES
ST_LOOP     PSHS B,X
            LDX  ,X
            JSR  DOFILE
            PULS B,X
            TST  <FAILED
            BNE  ST_END
            LEAX 2,X
            DECB
            BNE  ST_LOOP
            TST  <STOP
            BNE  ST_END
            JSR  DOLINK
            JSR  KILLOBJS
ST_END      LDB  <FAILED
            LDA  #B_EXIT
            SWI2
USAGE       LDX  #M_USAGE
            JSR  PRINTS
            LDB  #1
            LDA  #B_EXIT
            SWI2
;------------------------------------------------------------------------------
; The command tail -> WORDS (NWORDS pointers into ARGCOPY, each word ended
; with a NUL).
;------------------------------------------------------------------------------
WORDSPLIT   LDA  #B_ARGS
            SWI2
            LDY  #ARGCOPY
            JSR  STRCPY
            LDX  #ARGCOPY
            LDY  #WORDS
WS_LOOP     JSR  SKIPSP
            LDA  ,X
            BEQ  WS_END
            LDB  <NWORDS
            CMPB #MAXWORDS
            BHS  WS_END
            INC  <NWORDS
            STX  ,Y++
WS_WORD     LDA  ,X
            BEQ  WS_END
            JSR  ISSPACE
            BCC  WS_CUT
            LEAX 1,X
            BRA  WS_WORD
WS_CUT      CLR  ,X+
            BRA  WS_LOOP
WS_END      LDX  #WORDS
            STX  <WORDP
            RTS
; -> X = the next word (carry set if there's none).
NEXTWORD    TST  <NWORDS
            BEQ  NW_NONE
            DEC  <NWORDS
            LDX  <WORDP
            LEAX 2,X
            STX  <WORDP
            LDX  -2,X
            ANDCC #$FE
            RTS
NW_NONE     ORCC #1
            RTS
;------------------------------------------------------------------------------
; The options (and the files, in FILES).
;------------------------------------------------------------------------------
OPTIONS     JSR  NEXTWORD
            BCS  OP_RET
            LDA  ,X
            CMPA #'-'
            BEQ  OP_OPT
            LDB  <NFILES               ; a file
            LDY  #FILES
            LSLB
            STX  B,Y
            INC  <NFILES
            BRA  OPTIONS
OP_RET      RTS
OP_OPT      LDA  1,X
            LEAX 2,X                   ; (X: anything attached)
            CMPA #'c'
            BEQ  OP_STOP
            CMPA #'S'
            BEQ  OP_STOP
            CMPA #'E'
            BEQ  OP_STOP
            CMPA #'v'
            BEQ  OP_V
            CMPA #'q'
            BEQ  OP_Q
            CMPA #'o'
            BEQ  OP_O
            LDY  #S_OPTI               ; -I -D -U: CPP's, " -I DIR"
            CMPA #'I'
            BEQ  OP_CPP
            LDY  #S_OPTD
            CMPA #'D'
            BEQ  OP_CPP
            LDY  #S_OPTU
            CMPA #'U'
            BEQ  OP_CPP
            CMPA #'b'
            BEQ  OP_BANK
            CMPA #'L'
            BEQ  OP_LDIR
            CMPA #'l'
            BEQ  OP_LLIB
            JMP  USAGE
OP_STOP     STA  <STOP
            BRA  OPTIONS
OP_V        INC  <VERBOSE
            BRA  OPTIONS
OP_Q        INC  <QUIET
            BRA  OPTIONS
OP_O        JSR  OPTARG
            LDY  #OUTNAME
            JSR  STRCPY
            INC  <OUTSET
            BRA  OPTIONS
OP_CPP      JSR  OPTARG                ; (Y = the option's text)
            PSHS X
            LDX  #CPPOPT
            BSR  ATEND
            TFR  Y,X
            BSR  APPEND
            PULS X
            BSR  APPEND
            LBRA OPTIONS
OP_BANK     JSR  OPTARG                ; " -b N", CC1's
            PSHS X
            LDX  #CC1OPT
            JSR  ATEND
            LDX  #S_OPTB
            JSR  APPEND
            PULS X
            JSR  APPEND
            JMP  OPTIONS
OP_LDIR     JSR  OPTARG                ; " -L DIR"
            PSHS X
            LDX  #LNKDIR
            BSR  ATEND
            LDX  #S_OPTL
            BSR  APPEND
            PULS X
            BSR  APPEND
            LBRA OPTIONS
OP_LLIB     JSR  OPTARG                ; " -lLIB"
            PSHS X
            LDX  #LNKLIB
            BSR  ATEND
            LDX  #S_OPTLL
            BSR  APPEND
            PULS X
            BSR  APPEND
            LBRA OPTIONS
; X just past an option's letter -> X = its argument (attached, or the next
; word).
OPTARG      TST  ,X
            BNE  OA_RET
            JSR  NEXTWORD
            LBCS USAGE
OA_RET      RTS
; X = a list (LISTMAX bytes, NUL-terminated): PUTP = its end, to add to.
ATEND       PSHS X
            LEAX LISTMAX,X
            STX  <PUTEND
            PULS X
AE_LOOP     TST  ,X
            BEQ  AE_END
            LEAX 1,X
            BRA  AE_LOOP
AE_END      STX  <PUTP
            RTS
; X = a string: added at PUTP (an error if there's no room). Keeps Y.
APPEND      PSHS A,Y
            LDY  <PUTP
AP_LOOP     LDA  ,X+
            BEQ  AP_END
            CMPY <PUTEND
            BHS  AP_FULL
            STA  ,Y+
            BRA  AP_LOOP
AP_END      CLR  ,Y
            STY  <PUTP
            PULS A,Y,PC
AP_FULL     LDX  #M_TOOLONG
            JMP  FAIL
;------------------------------------------------------------------------------
; One file (X = its name): made into an object (or as far as STOP says), which
; is added to OBJS for LINK.
;------------------------------------------------------------------------------
DOFILE      STX  <FILEP
            JSR  MKSTEM                ; STEM, and A = its kind (1 .c, 2 .asm)
            TST  FIRSTSTEM
            BNE  DF_KIND
            PSHS A
            LDX  #STEM
            LDY  #FIRSTSTEM
            JSR  STRCPY
            PULS A
DF_KIND     STA  <ISC
            CMPA #1
            BEQ  DF_C
            CMPA #2
            LBEQ DF_ASM
            LDX  #OBJS                 ; anything else: LINK's
            BSR  ATEND
            LDX  #S_SPACE
            BSR  APPEND
            LDX  <FILEP
            BRA  APPEND
DF_C        LDX  #INAME                ; .c: CPP [opts] -o FILE.I file.c
            LDY  #S_EXTI
            LDA  #'E'
            JSR  OUTFILE
            JSR  NEWTAIL
            LDX  #CPPOPT
            JSR  APPEND
            LDX  #S_OPTO
            JSR  APPEND
            LDX  #INAME
            JSR  APPEND
            LDX  #S_SPACE
            JSR  APPEND
            LDX  <FILEP
            JSR  APPEND
            LDX  #L_CPP
            JSR  STAGE
            LDX  #N_CPP
            JSR  RUN
            LBCS DF_RET
            LDA  <STOP
            CMPA #'E'
            LBEQ DF_RET
            LDX  #ANAME                ; CC1 -o FILE.ASM FILE.I
            LDY  #S_EXTASM
            LDA  #'S'
            JSR  OUTFILE
            JSR  NEWTAIL
            LDX  #CC1OPT
            JSR  APPEND
            LDX  #S_OPTO
            JSR  APPEND
            LDX  #ANAME
            JSR  APPEND
            LDX  #S_SPACE
            JSR  APPEND
            LDX  #INAME
            JSR  APPEND
            LDX  #L_CC1
            JSR  STAGE
            LDX  #N_CC1
            JSR  RUN
            PSHS CC
            LDX  #INAME
            JSR  KILL
            PULS CC
            BCS  DF_RET
            LDA  <STOP
            CMPA #'S'
            BEQ  DF_RET
            BRA  DF_ASSEMBLE
DF_ASM      LDA  <STOP                 ; .asm: assembled (unless -S or -E)
            CMPA #'S'
            BEQ  DF_RET
            CMPA #'E'
            BEQ  DF_RET
            LDX  <FILEP
            LDY  #ANAME
            JSR  STRCPY
DF_ASSEMBLE LDX  #ONAME                ; ASM -f obj -o FILE.O FILE.ASM
            LDY  #S_EXTO
            LDA  #'c'
            JSR  OUTFILE
            JSR  NEWTAIL
            LDX  #S_ASMOPT
            JSR  APPEND
            LDX  #ONAME
            JSR  APPEND
            LDX  #S_SPACE
            JSR  APPEND
            LDX  #ANAME
            JSR  APPEND
            LDX  #L_ASM
            JSR  STAGE
            LDX  #N_ASM
            JSR  RUN
            PSHS CC
            LDA  <ISC                  ; (a .ASM CC1 made goes)
            CMPA #1
            BNE  DF_AKEPT
            LDX  #ANAME
            JSR  KILL
DF_AKEPT    PULS CC
            BCS  DF_RET
            LDX  #OBJS                 ; the object, for LINK
            JSR  ATEND
            LDX  #S_SPACE
            JSR  APPEND
            LDX  #ONAME
            JMP  APPEND
DF_RET      RTS
; X = where a file's name goes, Y = its extension, A = the STOP it's kept at:
; the name is -o's then (if given), or STEM with the extension.
OUTFILE     CMPA <STOP
            BNE  OF_STEM
            TST  <OUTSET
            BEQ  OF_STEM
            TFR  X,Y
            LDX  #OUTNAME
            JMP  STRCPY
OF_STEM     PSHS Y
            TFR  X,Y
            LDX  #STEM
            JSR  STRCPY
            PULS X
            JMP  STRCPY
; FILEP's name -> STEM (the last part, without its extension), A = its kind:
; 1 .C, 2 .ASM or .S, 0 anything else.
MKSTEM      LDX  <FILEP                ; the last part
            TFR  X,Y
MS_FIND     LDA  ,X+
            BEQ  MS_LAST
            CMPA #'/'
            BNE  MS_FIND
            TFR  X,Y
            BRA  MS_FIND
MS_LAST     TFR  Y,X
            LDY  #STEM
            LDB  #12
MS_COPY     LDA  ,X+
            BEQ  MS_NOEXT
            CMPA #'.'
            BEQ  MS_EXT
            STA  ,Y+
            DECB
            BNE  MS_COPY
MS_NOEXT    CLR  ,Y
            CLRA
            RTS
MS_EXT      CLR  ,Y
            LDY  #S_C                  ; (X: the extension)
            JSR  STRCMPI
            BEQ  MS_ISC
            LDY  #S_ASM
            JSR  STRCMPI
            BEQ  MS_ISASM
            LDY  #S_S
            JSR  STRCMPI
            BEQ  MS_ISASM
            CLRA
            RTS
MS_ISC      LDA  #1
            RTS
MS_ISASM    LDA  #2
            RTS
;------------------------------------------------------------------------------
; LINK --quiet-libs -f com -o PROG.COM -s /LIB/CC.SCR -L /LIB [-L ...] /LIB/CRT0.O objects
; [-l ...] -lpug -lc, from a response file (the command tail is too short for it).
;------------------------------------------------------------------------------
DOLINK      LDX  #RSPBUF
            CLR  ,X
            LDD  #RSPBUF+RSPMAX
            STD  <PUTEND
            STX  <PUTP
            LDX  #S_LINK1
            JSR  APPEND
            TST  <OUTSET
            BEQ  DL_DEFAULT
            LDX  #OUTNAME
            JSR  APPEND
            BRA  DL_REST
DL_DEFAULT  LDX  #FIRSTSTEM
            JSR  APPEND
            LDX  #S_EXTCOM
            JSR  APPEND
DL_REST     LDX  #S_LINK2
            JSR  APPEND
            LDX  #LNKDIR
            JSR  APPEND
            LDX  #S_LINK3
            JSR  APPEND
            LDX  #OBJS
            JSR  APPEND
            LDX  #LNKLIB
            JSR  APPEND
            LDX  #S_LINK4
            JSR  APPEND
            LDX  #N_RSP                ; the response file
            LDE  #FOPEN_WRITE
            LDA  #B_FOPEN_NAME
            SWI2
            BCS  DL_NORSP
            PSHS A
            LDD  <PUTP
            SUBD #RSPBUF
            TFR  D,Y
            LDX  #RSPBUF
            LDB  ,S
            LDA  #B_FWRITE
            SWI2
            PULS B
            LDA  #B_FCLOSE_NAME
            SWI2
            BCS  DL_NORSP
            JSR  NEWTAIL               ; LINK @CCLINK.RSP
            LDX  #S_AT
            JSR  APPEND
            TST  <VERBOSE
            BEQ  DL_RUN
            LDX  #N_RSP                ; (-v: what's in it)
            JSR  PRINTS
            LDA  #':'
            JSR  PRINTC
            LDX  #RSPBUF
            JSR  PRINTS
            JSR  PRINTNL
DL_RUN      TST  <QUIET                ; "link: PROG.COM"
            BNE  DL_GO
            LDX  #L_LINK
            JSR  PRINTS
            LDX  #OUTNAME
            TST  <OUTSET
            BNE  DL_NAME
            LDX  #FIRSTSTEM
            JSR  PRINTS
            LDX  #S_EXTCOM
DL_NAME     JSR  PRINTS
            JSR  PRINTNL
DL_GO       LDX  #N_LINK
            JSR  RUN
            LDX  #N_RSP
            JMP  KILL
DL_NORSP    LDX  #M_NORSP
            JMP  FAIL
; The objects made from .c and .asm files: deleted (after the link).
KILLOBJS    LDX  #FILES
            LDB  <NFILES
KO_LOOP     PSHS B,X
            LDX  ,X
            STX  <FILEP
            JSR  MKSTEM
            TSTA
            BEQ  KO_NEXT
            LDX  #STEM
            LDY  #ONAME
            JSR  STRCPY
            LDX  #S_EXTO
            JSR  STRCPY
            LDX  #ONAME
            JSR  KILL
KO_NEXT     PULS B,X
            LEAX 2,X
            DECB
            BNE  KO_LOOP
            RTS
;------------------------------------------------------------------------------
; Running the tools.
;------------------------------------------------------------------------------
; X = a stage's name: "FILE: name", a line (unless -q).
STAGE       TST  <QUIET
            BNE  SG_RET
            PSHS X
            LDX  <FILEP
            JSR  PRINTS
            LDX  #S_COLON
            JSR  PRINTS
            PULS X
            JSR  PRINTS
            JMP  PRINTNL
SG_RET      RTS
; The command tail starts again (TAIL, empty).
NEWTAIL     LDX  #TAIL
            CLR  ,X
            STX  <PUTP
            LDX  #TAIL+LINEMAX
            STX  <PUTEND
            RTS
; X = a tool's name (CPP.COM ...), TAIL its command tail: it's run. Carry set
; if it can't be, or it says it failed (FAILED is set then).
RUN         PSHS X
            JSR  FINDPROG
            BCS  RU_NONE
            TST  <VERBOSE
            BEQ  RU_GO
            LDX  ,S                    ; (-v: "CPP ..." as it would be typed)
RU_NAME     LDA  ,X+
            CMPA #'.'
            BEQ  RU_SHOWN
            JSR  PRINTC
            BRA  RU_NAME
RU_SHOWN    LDA  #' '
            JSR  PRINTC
            LDX  #TAIL
            JSR  PRINTS
            JSR  PRINTNL
RU_GO       LDX  #PROGPATH
            LDY  #TAIL
            LDE  #EXEC_CHILD
            LDA  #B_EXEC
            SWI2
            BCS  RU_CANT
            PULS X
            TSTB
            BNE  RU_FAILED
            ANDCC #$FE
            RTS
RU_FAILED   LDA  #1
            STA  <FAILED
            ORCC #1
            RTS
RU_NONE     LDX  #M_NOPROG
            BRA  RU_SAY
RU_CANT     LDX  #M_NORUN
RU_SAY      JSR  PRINTS
            PULS X
            JSR  PRINTS
            JSR  PRINTNL
            BRA  RU_FAILED
; X = a program's name -> PROGPATH = where it is: here, or in a directory
; of the search path. Carry set if it's nowhere.
FINDPROG    PSHS X
            LDY  #PROGPATH
            JSR  STRCPY
            BSR  FP_STAT
            BCC  FP_RET
            CLRD
            TFR  D,X
            LDA  #B_PATH               ; X = the search path
            SWI2
FP_DIR      LDA  ,X
            BEQ  FP_NONE
            LDY  #PROGPATH             ; a directory ...
FP_COPY     LDA  ,X
            BEQ  FP_SLASH
            CMPA #';'
            BEQ  FP_SEP
            STA  ,Y+
            LEAX 1,X
            CMPY #PROGPATH+NAMEMAX-13
            BLO  FP_COPY
            BRA  FP_NONE
FP_SEP      LEAX 1,X
FP_SLASH    LDA  -1,Y                  ; ... "/" ...
            CMPA #'/'
            BEQ  FP_NAME
            LDA  #'/'
            STA  ,Y+
FP_NAME     PSHS X                     ; ... and the name
            LDX  2,S
            JSR  STRCPY
            PULS X
            BSR  FP_STAT
            BCS  FP_DIR
FP_RET      PULS X,PC
FP_NONE     ORCC #1
            PULS X,PC
FP_STAT     PSHS X
            LDX  #PROGPATH
            LDY  #STATBUF
            LDA  #B_STAT
            SWI2
            PULS X,PC
; X = a file's name: deleted (if it's there).
KILL        LDA  #B_KILL_NAME
            SWI2
            RTS
; X = a message: "CC: " it, and the end (exit code 1).
FAIL        PSHS X
            LDX  #M_CC
            JSR  PRINTS
            PULS X
            JSR  PRINTS
            JSR  PRINTNL
            LDB  #1
            LDA  #B_EXIT
            SWI2
;------------------------------------------------------------------------------
    INCLUDE pa_util.asm
;------------------------------------------------------------------------------
M_BANNER    FCC  "CC: the Pugputer 6309's C compiler"
            FCB  CR,LF,0
M_USAGE     FCC  "Usage: CC [-c|-S|-E] [-o out] [-v] [-q] [-I dir] [-D name[=val]]"
            FCB  CR,LF
            FCC  "          [-U name] [-b bank] [-L dir] [-l lib] file..."
            FCB  CR,LF,0
M_CC        FCN  "CC: "
M_TOOLONG   FCN  "too many options"
M_NORSP     FCN  "cannot write CCLINK.RSP"
M_NOPROG    FCN  "CC: cannot find "
M_NORUN     FCN  "CC: cannot run "
L_CPP       FCN  "cpp"
L_CC1       FCN  "cc1"
L_ASM       FCN  "asm"
L_LINK      FCN  "link: "
S_COLON     FCN  ": "
N_CPP       FCN  "CPP.COM"
N_CC1       FCN  "CC1.COM"
N_ASM       FCN  "ASM.COM"
N_LINK      FCN  "LINK.COM"
N_RSP       FCN  "CCLINK.RSP"
S_AT        FCN  "@CCLINK.RSP"
S_OPTI      FCN  " -I "
S_OPTD      FCN  " -D "
S_OPTU      FCN  " -U "
S_OPTB      FCN  " -b "
S_OPTL      FCN  " -L "
S_OPTLL     FCN  " -l"
S_OPTO      FCN  " -o "
S_SPACE     FCN  " "
S_ASMOPT    FCN  "-f obj -o "
S_EXTI      FCN  ".I"
S_EXTASM    FCN  ".ASM"
S_EXTO      FCN  ".O"
S_EXTCOM    FCN  ".COM"
S_C         FCN  "C"
S_ASM       FCN  "ASM"
S_S         FCN  "S"
S_LINK1     FCN  "--quiet-libs -f com -o "
S_LINK2     FCN  " -s /LIB/CC.SCR -L /LIB"
S_LINK3     FCN  " /LIB/CRT0.O"
S_LINK4     FCN  " -lpug -lc"
;------------------------------------------------------------------------------
PA_END      equ  *
;------------------------------------------------------------------------------
; Variables and buffers after the program (none of this is in the file).
;------------------------------------------------------------------------------
RSPMAX      equ  1000
VARS        equ  *
VP          SET  VARS
            VAR  ARGCOPY,LINEMAX+2
            VAR  WORDS,MAXWORDS*2
            VAR  FILES,MAXWORDS*2
            VAR  OUTNAME,NAMEMAX+1
            VAR  STEM,14
            VAR  FIRSTSTEM,14
            VAR  INAME,NAMEMAX+1
            VAR  ANAME,NAMEMAX+1
            VAR  ONAME,NAMEMAX+1
            VAR  TAIL,LINEMAX+2
            VAR  PROGPATH,NAMEMAX+1
            VAR  STATBUF,16
            VAR  NUMBUF,8
            VAR  CPPOPT,LISTMAX+1
            VAR  CC1OPT,LISTMAX+1
            VAR  LNKDIR,LISTMAX+1
            VAR  LNKLIB,LISTMAX+1
            VAR  OBJS,LISTMAX+1
            VAR  RSPBUF,RSPMAX+1
VARSEND     equ  VP
;------------------------------------------------------------------------------
; End of cc.asm
;------------------------------------------------------------------------------
