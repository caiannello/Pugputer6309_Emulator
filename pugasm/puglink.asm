;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 linker
;    FILE: puglink.asm
;
; PUGLINK.COM: a linker for the Pugputer, modelled on lwlink (lwtools 4.20). It
; reads LWOBJ16 object files (from PUGASM or lwasm), places their sections as a
; link script says, resolves the references between them, and writes the
; program: the same bytes, S-records and map as lwlink.
;
;   PUGLINK [options] file.o ...
;     -f FMT, --format=FMT     raw (the default), srec, com (raw with a Pugputer
;                              program header: load = the first section's
;                              address, entry = the entry point, if any)
;     -o FILE, --output=FILE   the output (default A.OUT)
;     -m FILE, --map=FILE      a map: the sections, then every symbol
;     -s FILE, --script=FILE   the link script (default: lwlink's, by format)
;     -e SYM, --entry=SYM      the entry point (a symbol, or a hex address)
;     --section-base=SECT=ADDR a load address (with the default script only)
;     -r                       the same as -f raw
;     @FILE                    more arguments, from FILE (the shell's command
;                              line is short; spaces and line ends separate)
;
; A link script, one statement a line (# and ; start comments):
;     section NAME[,bss|,!bss] [load ADDR | high ADDR]    (NAME * = all others)
;     entry ADDR | entry SYMBOL
;     define basesympat PAT / define lensympat PAT        (s_%s, l_%s)
;     pad N, stacksize N                                   (accepted, ignored)
;
; How it works: every object file is read into banked RAM (sections, their
; symbols, relocations and bytes); the script places the sections one after
; another from each load address (or down from it, "high"); each relocation's
; expression (postfix, lwlink's terms) is evaluated with the final addresses and
; patched into the bytes; then the output and the map are written. No libraries.
;------------------------------------------------------------------------------
    INCLUDE defines.d
;------------------------------------------------------------------------------
DPAGE       equ  $3400             ; the direct page (not part of the file)
PL_BASE     equ  $3500
WINDOW      equ  $C000             ; bank 3: where heap pages are mapped
WINEND      equ  $F000
STACKTOP    equ  $C000
PATHMAX     equ  79
SYMMAX      equ  127               ; longest symbol or section name kept
MAXPAGES    equ  48
MAXFILES    equ  32
MAXSLINES   equ  32
MAXBASES    equ  8
CHUNKSZ     equ  1021
SNAMEMAX    equ  31                ; a script's section name
RSPMAX      equ  1023              ; an @FILE's text
ESTKMAX     equ  16                ; relocation expressions: stack depth
; Output formats
FMT_RAW     equ  0
FMT_SREC    equ  1
FMT_COM     equ  2
; Section flags (as in the object file)
SEF_BSS     equ  1
SEF_CONST   equ  2
; A section (heap): its place in the input, in the output, what it holds.
SC_NEXT     equ  0                 ; the next section read (far pointer)
SC_ONEXT    equ  3                 ; the next one placed
SC_FILE     equ  6                 ; its file (1 up)
SC_FLAGS    equ  7
SC_SIZE     equ  8
SC_LOAD     equ  10
SC_PROC     equ  12                ; placed
SC_LOCALS   equ  13                ; its symbols (a list, far pointers)
SC_EXPORTS  equ  16
SC_RELOCS   equ  19
SC_CODE     equ  22                ; its bytes: chunks (+0 next, +3 bytes)
SC_NAME     equ  25
; A symbol (heap)
SY_NEXT     equ  0
SY_VAL      equ  3                 ; its offset in its section
SY_ABS      equ  5                 ; its address (for the map)
SY_FILE     equ  7                 ; its file (0 = synthetic)
SY_NAME     equ  8
; A relocation (heap)
RE_NEXT     equ  0
RE_OFF      equ  3
RE_FLAGS    equ  5                 ; 1: 8 bits
RE_LEN      equ  6                 ; bytes of expression
RE_EXPR     equ  7
; A link-script "section" line (SLINES)
SL_NAME     equ  0                 ; "" = * (the ones not placed yet)
SL_YES      equ  32                ; flags a section must have
SL_NO       equ  33                ; and mustn't
SL_LOAD     equ  34
SL_HASLOAD  equ  36
SL_DOWN     equ  37
SL_SIZE     equ  38
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
            DVAR MAPPED,1              ; (pa_heap.asm)
            DVAR NPAGES,1
            DVAR HEAPPG,1
            DVAR HEAPPTR,2
            DVAR FARP,3
            DVAR FARP2,3
            DVAR MA,4                  ; (pa_util.asm)
            DVAR MB,4
            DVAR MQ,4
            DVAR MSIGN,1
            DVAR TMP,2
            DVAR TMP2,2
            DVAR TMPB,1
            DVAR FORMAT,1
            DVAR NFILES,1
            DVAR NSLINES,1
            DVAR NBASES,1
            DVAR CURFILE,1
            DVAR SECTS,3               ; the sections as read
            DVAR SECTLAST,3
            DVAR OHEAD,3               ; the sections as placed
            DVAR OLAST,3
            DVAR CURSECT,3
            DVAR LADDR,2               ; placing: the next address
            DVAR GROWDN,1              ; ... going down
            DVAR EXECADDR,2
            DVAR EXECSYM,1             ; the entry is a symbol (EXECNAME)
            DVAR ENTRYOPT,1            ; -e given
            DVAR SYNTH,3               ; synthetic symbols
            DVAR SYMERR,1
            DVAR OUTON,1
            DVAR MAPON,1
            DVAR RFLAGS,1              ; reading a relocation
            DVAR RLEN,1
            DVAR RDH,1                 ; the input file: handle
            DVAR RDPOS,2               ; next byte in RDBUF
            DVAR RDLEN,2               ; bytes in RDBUF
            DVAR RDOPEN,1
            DVAR CNT,2
            DVAR PREVCH,3
            DVAR FIRSTCH,3
            DVAR ESP,1                 ; the expression stack
            DVAR EXPP,2
            DVAR PVAL,2                ; patching
            DVAR POFF,2
            DVAR NSYM,2                ; the map's array
            DVAR ARRPG,1
            DVAR ARRADDR,2
            DVAR ARRPTR,2
            DVAR HSI,2
            DVAR HSJ,2
            DVAR HSK,2
            DVAR HSN,2
            DVAR KEY2F,1
            DVAR SRADDR,2
            DVAR SRSUM,1
            DVAR GRPLEN,2
            DVAR GRPLOW,2
            DVAR FOUNDC,1
            DVAR EOP,1                 ; the operator being applied
            DVAR RELP,3                ; the next relocation
            DVAR RESONLY,1             ; PRECONST: only looking
            DVAR PCSECT,3
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
            JSR  HEAPINIT
            JSR  CMDLINE
            JSR  SCRIPT
            JSR  READFILES
            JSR  PRECONST
            JSR  PLACE
            JSR  GENSYMS
            JSR  ENTRY
            JSR  RELOCATE
            TST  <SYMERR
            BNE  QUIT
            JSR  OUTPUT
            TST  <MAPON
            BEQ  QUIT
            JSR  MAP
QUIT        JSR  HEAPDONE
            LDA  #B_EXIT
            SWI2
; X = a message: printed, and everything given up (a partial output deleted).
FATAL       JSR  PRINTS
            JSR  PRINTNL
            TST  <RDOPEN
            BEQ  FT_NORD
            LDB  <RDH
            LDA  #B_FCLOSE_NAME
            SWI2
FT_NORD     TST  <OUTON
            BEQ  FT_NOOUT
            LDU  #OUTSTRM
            JSR  SCLOSE
            LDX  #OUTNAME
            LDA  #B_KILL_NAME
            SWI2
FT_NOOUT    LDU  #MAPSTRM
            JSR  SCLOSE
            JSR  HEAPDONE
            LDA  #B_EXIT
            SWI2
;------------------------------------------------------------------------------
; The command line.
;------------------------------------------------------------------------------
CMDLINE     LDA  #B_ARGS
            SWI2
            JSR  SKIPSP
            TST  ,X
            LBEQ USAGE
            JSR  CLPARSE
            LBRA CL_DONE
; X = arguments: taken in (to the end of the string).
CLPARSE
CL_NEXT     JSR  SKIPSP
            LDA  ,X
            BNE  CL_ARG
            RTS
CL_ARG      CMPA #'@'                  ; @FILE: more arguments, from a file
            LBEQ CL_RESP
            CMPA #'-'
            LBNE CL_FILE
            LDA  1,X
            CMPA #'-'
            BEQ  CL_LONG
            JSR  UPCASE
            LEAX 2,X
            CMPA #'F'
            BEQ  CL_FMT
            CMPA #'O'
            BEQ  CL_OUT
            CMPA #'M'
            BEQ  CL_MAP
            CMPA #'S'
            BEQ  CL_SCR
            CMPA #'E'
            BEQ  CL_ENT
            CMPA #'R'
            LBNE USAGE
            CLR  <FORMAT
            BRA  CL_NEXT
CL_FMT      JSR  OPTARG
CL_FMT2     LDY  #NAMEBUF
            JSR  GETWORD
            JSR  SETFMT
            BRA  CL_NEXT
CL_OUT      JSR  OPTARG
CL_OUT2     LDY  #OUTNAME
            JSR  GETWORD
            BRA  CL_NEXT
CL_MAP      JSR  OPTARG
CL_MAP2     LDY  #MAPNAME
            JSR  GETWORD
            LDA  #1
            STA  <MAPON
            BRA  CL_NEXT
CL_SCR      JSR  OPTARG
CL_SCR2     LDY  #SCRNAME
            JSR  GETWORD
            BRA  CL_NEXT
CL_ENT      JSR  OPTARG
CL_ENT2     LDY  #ENTRYARG
            JSR  GETWORD
            LDA  #1
            STA  <ENTRYOPT
            LBRA CL_NEXT
CL_LONG     LEAX 2,X                   ; --name=value
            LDY  #LO_FORMAT
            JSR  PREFIX
            BEQ  CL_FMT2
            LDY  #LO_OUTPUT
            JSR  PREFIX
            BEQ  CL_OUT2
            LDY  #LO_MAP
            JSR  PREFIX
            BEQ  CL_MAP2
            LDY  #LO_SCRIPT
            JSR  PREFIX
            BEQ  CL_SCR2
            LDY  #LO_ENTRY
            JSR  PREFIX
            BEQ  CL_ENT2
            LDY  #LO_BASE
            JSR  PREFIX
            LBNE USAGE
            LDA  <NBASES               ; SECT=ADDR
            CMPA #MAXBASES
            LBHS USAGE
            LDB  #SL_SIZE
            MUL
            ADDD #BASES
            TFR  D,Y
            INC  <NBASES
            LDB  #SNAMEMAX
CL_BNAME    LDA  ,X
            LBEQ USAGE
            CMPA #'='
            BEQ  CL_BEQ
            LEAX 1,X
            TSTB
            BEQ  CL_BNAME
            STA  ,Y+
            DECB
            BRA  CL_BNAME
CL_BEQ      CLR  ,Y
            LEAX 1,X
            JSR  HEXNUM                ; -> D
            PSHS D
            LDA  <NBASES
            DECA
            LDB  #SL_SIZE
            MUL
            ADDD #BASES
            TFR  D,Y
            PULS D
            STD  SL_LOAD,Y
            LBRA CL_NEXT
CL_FILE     LDA  <NFILES               ; an input file
            CMPA #MAXFILES
            BHS  CL_MANY
            LDB  #PATHMAX+1
            MUL
            ADDD #FILETAB
            TFR  D,Y
            JSR  GETWORD
            INC  <NFILES
            LBRA CL_NEXT
CL_MANY     LDX  #M_MANYFILES
            JMP  FATAL
CL_RESP     TST  RSPIN                 ; (not inside another one)
            LBNE USAGE
            LEAX 1,X
            LDY  #NAME2
            JSR  GETWORD
            PSHS X
            LDX  #NAME2
            JSR  RDOPENF
            BCC  CL_ROPEN
            LDX  #M_NOFILE
            JSR  PRINTS
            LDX  #NAME2
            JMP  FATAL
CL_ROPEN    LDX  #RSPBUF               ; its text, line ends as spaces
CL_RBYTE    JSR  RDBYTE
            BCS  CL_REND
            CMPA #' '
            BHS  CL_RKEEP
            LDA  #' '
CL_RKEEP    CMPX #RSPBUF+RSPMAX
            BHS  CL_RBYTE
            STA  ,X+
            BRA  CL_RBYTE
CL_REND     CLR  ,X
            JSR  RDCLOSE
            INC  RSPIN
            LDX  #RSPBUF
            JSR  CLPARSE
            CLR  RSPIN
            PULS X
            LBRA CL_NEXT
CL_DONE     TST  <NFILES
            BNE  CL_HAVE
            LDX  #M_NOINPUT
            JMP  FATAL
CL_HAVE     TST  OUTNAME
            BNE  CL_RET
            LDX  #M_AOUT
            LDY  #OUTNAME
            JMP  STRCPY
CL_RET      RTS
USAGE       LDX  #M_USAGE
            JSR  PRINTS
            JSR  HEAPDONE
            LDA  #B_EXIT
            SWI2
; X is just past an option letter: to its argument (attached, or the next word).
OPTARG      LDA  ,X
            BEQ  OA_NEXT
            JSR  ISSPACE
            BCS  OA_RET
OA_NEXT     JSR  SKIPSP
OA_RET      RTS
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
; Z set if the string at X starts with the (NUL-terminated) one at Y: X then
; past it. Otherwise X is unchanged.
PREFIX      PSHS X
PF_LOOP     LDA  ,Y+
            BEQ  PF_YES
            CMPA ,X+
            BEQ  PF_LOOP
            PULS X
            ANDCC #$FB
            RTS
PF_YES      LEAS 2,S
            ORCC #4
            RTS
; NAMEBUF = a format name: FORMAT (lwlink's other formats aren't supported).
SETFMT      PSHS X
            LDX  #NAMEBUF
            LDY  #M_RAW
            CLRB
            JSR  STRCMPI
            BEQ  SF_SET
            LDY  #M_SREC
            LDB  #FMT_SREC
            JSR  STRCMPI
            BEQ  SF_SET
            LDY  #M_COM
            LDB  #FMT_COM
            JSR  STRCMPI
            BNE  SF_BAD
SF_SET      STB  <FORMAT
            PULS X,PC
SF_BAD      LDX  #M_BADFMT
            JSR  PRINTS
            LDX  #NAMEBUF
            JMP  FATAL
; X at hex digits (an optional 0x): -> D, X past them (as strtol, base 16).
HEXNUM      CLRD
            PSHS D
            LDA  ,X
            CMPA #'0'
            BNE  HN_LOOP
            LDA  1,X
            JSR  UPCASE
            CMPA #'X'
            BNE  HN_LOOP
            LEAX 2,X
HN_LOOP     LDA  ,X
            JSR  UPCASE
            SUBA #'0'
            BLO  HN_END
            CMPA #9
            BLS  HN_DIG
            SUBA #7
            CMPA #10
            BLO  HN_END
            CMPA #15
            BHI  HN_END
HN_DIG      LEAX 1,X
            PSHS A
            LDD  1,S
            ASLB
            ROLA
            ASLB
            ROLA
            ASLB
            ROLA
            ASLB
            ROLA
            ORB  ,S+
            STD  ,S
            BRA  HN_LOOP
HN_END      PULS D,PC
;------------------------------------------------------------------------------
; The link script: a file (-s), or lwlink's default for the format with any
; --section-base lines first. Then -e, which overrides the script's entry.
;------------------------------------------------------------------------------
SCRIPT      TST  SCRNAME
            BEQ  SC_DEFAULT
            LDX  #SCRNAME
            JSR  RDOPENF
            BCC  SC_READ
            LDX  #M_NOSCRIPT
            JSR  PRINTS
            LDX  #SCRNAME
            JMP  FATAL
SC_READ     JSR  RDLINE                ; -> LINEBUF, carry at the end
            BCS  SC_CLOSE
            JSR  SCRLINE
            BRA  SC_READ
SC_CLOSE    JSR  RDCLOSE
            BRA  SC_ENTRY
SC_DEFAULT  LDA  <NBASES               ; section-base lines: "section S load A"
            BEQ  SC_BUILTIN
            LDX  #BASES
            LDA  <NBASES
            STA  <TMPB
SC_BLOOP    PSHS X
            LDY  #LINEBUF
            PSHS X
            LDX  #M_SECTION
            JSR  STRCPY
            LDA  #' '
            STA  ,Y+
            PULS X
            JSR  STRCPY
            LDX  #M_LOADSP
            JSR  STRCPY
            PULS X
            PSHS X
            LDD  SL_LOAD,X
            LEAX ,Y
            JSR  HEX4
            CLR  ,X
            JSR  SCRLINE
            PULS X
            LEAX SL_SIZE,X
            DEC  <TMPB
            BNE  SC_BLOOP
SC_BUILTIN  LDX  #RAW_SCRIPT
            LDA  <FORMAT
            CMPA #FMT_SREC
            BNE  SC_BLINE
            LDX  #SREC_SCRIPT
SC_BLINE    TST  ,X
            BEQ  SC_ENTRY
            LDY  #LINEBUF              ; (X ends past the NUL: the next line)
            JSR  STRCPY
            PSHS X
            JSR  SCRLINE
            PULS X
            BRA  SC_BLINE
SC_ENTRY    TST  <ENTRYOPT             ; -e: an address if it starts with a digit
            BEQ  SC_RET
            LDA  ENTRYARG
            JSR  ISDIGIT
            BCS  SC_ESYM
            LDX  #ENTRYARG
            JSR  HEXNUM
            STD  <EXECADDR
            CLR  <EXECSYM
            RTS
SC_ESYM     LDX  #ENTRYARG
            LDY  #EXECNAME
            JSR  STRCPY
            LDA  #1
            STA  <EXECSYM
SC_RET      RTS
; LINEBUF = a script line: taken in (lwlink's parse).
SCRLINE     LDX  #LINEBUF
            JSR  SKIPSP
            LDA  ,X
            BEQ  SCL_RET
            CMPA #'#'
            BEQ  SCL_RET
            CMPA #';'
            BEQ  SCL_RET
            LDX  #LINEBUF              ; the first word: from the line's start
            LDY  #WORKBUF              ; (lwlink: so an indented line is bad)
            JSR  GETWORD
            JSR  SKIPSP                ; X: the rest
            LDY  #M_SECTION
            JSR  WORDIS
            LBEQ SL_SECTION
            LDY  #M_ENTRY
            JSR  WORDIS
            LBEQ SL_ENTRY
            LDY  #M_DEFINE
            JSR  WORDIS
            BEQ  SL_DEFINE
            LDY  #M_PAD
            JSR  WORDIS
            BEQ  SCL_RET
            LDY  #M_STACKSIZE
            JSR  WORDIS
            BEQ  SCL_RET
            LDY  #M_SECTOPT
            JSR  WORDIS
            BNE  SL_BAD
            LDX  #M_NOSECTOPT
            JMP  FATAL
SL_BAD      LDX  #SCRNAME              ; "SCRIPT: bad script line: WORD"
            JSR  PRINTS
            LDX  #M_COLON
            JSR  PRINTS
            LDX  #M_BADLINE
            JSR  PRINTS
            LDX  #WORKBUF
            JMP  FATAL
SCL_RET      RTS
; Z set if WORKBUF is the word at Y.
WORDIS      PSHS X
            LDX  #WORKBUF
            JSR  STRCMP
            PULS X,PC
SL_DEFINE   LDY  #WORKBUF              ; "define basesympat|lensympat PATTERN"
            JSR  GETWORD
            JSR  SKIPSP
            LDY  #M_BASESYM
            JSR  WORDIS
            BNE  SL_DLEN
            LDY  #BPAT
            BRA  SL_DPAT
SL_DLEN     LDY  #M_LENSYM
            JSR  WORDIS
            BNE  SCL_RET                ; (others: ignored, as lwlink does)
            LDY  #LPAT
SL_DPAT     LDB  #31
SL_DCH      LDA  ,X+
            BEQ  SL_DEND
            STA  ,Y+
            DECB
            BNE  SL_DCH
SL_DEND     CLR  ,Y
            RTS
SL_ENTRY    PSHS X                     ; "entry ADDR" or "entry SYMBOL"
            JSR  HEXNUM
            TST  ,X
            BNE  SL_ESYM
            LEAS 2,S
            STD  <EXECADDR
            CLR  <EXECSYM
            RTS
SL_ESYM     PULS X                     ; (the rest of the line is the symbol)
            LDY  #EXECNAME
            JSR  STRCPY
            LDA  #1
            STA  <EXECSYM
            RTS
SL_SECTION  LDA  <NSLINES              ; "section NAME[,flags] [load|high ADDR]"
            CMPA #MAXSLINES
            BLO  SL_ROOM
            LDX  #M_MANYLINES
            JMP  FATAL
SL_ROOM     LDB  #SL_SIZE
            MUL
            ADDD #SLINES
            TFR  D,U                   ; U = the new line's entry
            LEAY SL_NAME,U             ; clear it
            LDB  #SL_SIZE
SL_CLR      CLR  ,Y+
            DECB
            BNE  SL_CLR
            LDY  #NAME2                ; NAME[,flags] -> NAME2
            JSR  GETWORD
            JSR  SKIPSP
            LDA  ,X
            BEQ  SL_NOLOAD
            LDY  #M_LOAD
            JSR  PREFIX
            BEQ  SL_LOADAT
            LDY  #M_HIGH
            JSR  PREFIX
            LBNE SL_BAD
            LDA  #1
            STA  SL_DOWN,U
SL_LOADAT   JSR  SKIPSP
            JSR  HEXNUM
            STD  SL_LOAD,U
            LDA  #1
            STA  SL_HASLOAD,U
            BRA  SL_FLAGS
SL_NOLOAD   TST  <NSLINES              ; no address: going on like the last line
            BEQ  SL_FLAGS
            LDA  SL_DOWN-SL_SIZE,U
            STA  SL_DOWN,U
SL_FLAGS    LDX  #NAME2                ; the flags, after a comma
SL_FSCAN    LDA  ,X+
            BEQ  SL_FNONE
            CMPA #','
            BNE  SL_FSCAN
            CLR  -1,X
            LDY  #M_NBSS+1             ; "bss"
            JSR  STRCMP
            BNE  SL_FNOT
            LDA  #SEF_BSS
            STA  SL_YES,U
            BRA  SL_FNONE
SL_FNOT     LDY  #M_NBSS               ; "!bss"
            JSR  STRCMP
            LBNE SL_BAD
            LDA  #SEF_BSS
            STA  SL_NO,U
SL_FNONE    LDX  #NAME2                ; the name ("*": none)
            LDD  ,X
            CMPD #$2A00
            BEQ  SL_WILD
            LEAY SL_NAME,U
            LDB  #SNAMEMAX
SL_NCH      LDA  ,X+
            STA  ,Y+
            BEQ  SL_WILD
            DECB
            BNE  SL_NCH
            CLR  ,Y
SL_WILD     INC  <NSLINES
            RTS
;------------------------------------------------------------------------------
; Reading files: one open at a time, through RDBUF.
;------------------------------------------------------------------------------
; X = a file name: opened. Carry set if it can't be.
RDOPENF     LDE  #FOPEN_READ
            LDA  #B_FOPEN_NAME
            SWI2
            BCS  RO_RET
            STA  <RDH
            LDA  #1
            STA  <RDOPEN
            CLRD
            STD  <RDPOS
            STD  <RDLEN
            ANDCC #$FE
RO_RET      RTS
RDCLOSE     TST  <RDOPEN
            BEQ  RC_RET
            CLR  <RDOPEN
            LDB  <RDH
            LDA  #B_FCLOSE_NAME
            SWI2
RC_RET      RTS
; -> A = the next byte; carry set at the end. Keeps B, X, Y.
RDBYTE      PSHS B,X,Y
            LDD  <RDPOS
            CMPD <RDLEN
            BLO  RB_HAVE
            LDX  #RDBUF
            LDY  #256
            LDB  <RDH
            LDA  #B_FREAD
            SWI2
            BCS  RB_END
            CMPX #0
            BEQ  RB_END
            STX  <RDLEN
            CLRD
            STD  <RDPOS
RB_HAVE     LDX  #RDBUF
            LEAX D,X
            ADDD #1
            STD  <RDPOS
            LDA  ,X
            ANDCC #$FE
            PULS B,X,Y,PC
RB_END      ORCC #1
            PULS B,X,Y,PC
; -> LINEBUF: the next line (CR, LF, or both end it); carry set at the end.
RDLINE      LDX  #LINEBUF
            CLRB
RL_LOOP     JSR  RDBYTE
            BCS  RL_EOF
            CMPA #CR
            BEQ  RL_EOL
            CMPA #LF
            BEQ  RL_EOL
            CMPB #250
            BHS  RL_LOOP
            STA  ,X+
            INCB
            BRA  RL_LOOP
RL_EOL      CLR  ,X
            ANDCC #$FE
            RTS
RL_EOF      CLR  ,X
            TSTB                       ; a last line without an end
            BEQ  RL_END
            ANDCC #$FE
            RTS
RL_END      ORCC #1
            RTS
; The object file's next byte (the end there is an error).
OBYTE       JSR  RDBYTE
            BCS  BADOBJ
            RTS
OWORD       JSR  OBYTE
            TFR  A,B
            JSR  OBYTE
            EXG  A,B
            RTS
; A = its first byte: the rest of a NUL-terminated string -> NAMEBUF.
OSTRING     LDX  #NAMEBUF
            LDB  #SYMMAX
OS_LOOP     STA  ,X
            TSTA
            BEQ  OS_RET
            TSTB
            BEQ  OS_NEXT
            LEAX 1,X
            DECB
OS_NEXT     JSR  OBYTE
            BRA  OS_LOOP
OS_RET      RTS
BADOBJ      JSR  CURNAME
            LDX  #M_BADOBJ
            JMP  FATAL
; The current file's name (and ": ") printed.
CURNAME     LDB  <CURFILE
            JSR  FILENAME
            JSR  PRINTS
            LDX  #M_COLON
            JMP  PRINTS
; B = a file (1 up; 0 = synthetic): -> X = its name.
FILENAME    TSTB
            BNE  FN_FILE
            LDX  #M_SYNTH
            RTS
FN_FILE     PSHS D
            DECB
            LDA  #PATHMAX+1
            MUL
            ADDD #FILETAB
            TFR  D,X
            PULS D,PC
;------------------------------------------------------------------------------
; The object files, into the heap.
;------------------------------------------------------------------------------
READFILES   CLR  <CURFILE
RF_FILE     INC  <CURFILE
            LDB  <CURFILE
            CMPB <NFILES
            BHI  RF_RET
            JSR  FILENAME
            JSR  RDOPENF
            BCC  RF_OPEN
            LDX  #M_NOFILE
            JSR  PRINTS
            LDB  <CURFILE
            JSR  FILENAME
            JMP  FATAL
RF_OPEN     LDY  #M_MAGIC              ; "LWOBJ16" and a NUL
            LDB  #8
RF_MAGIC    JSR  RDBYTE
            BCS  RF_NOTOBJ
            CMPA ,Y+
            BNE  RF_NOTOBJ
            DECB
            BNE  RF_MAGIC
RF_SECT     JSR  OBYTE                 ; a section, or the end
            TSTA
            BEQ  RF_DONE
            JSR  READSECT
            BRA  RF_SECT
RF_DONE     JSR  RDCLOSE
            BRA  RF_FILE
RF_NOTOBJ   JSR  CURNAME
            LDX  #M_NOTOBJ
            JMP  FATAL
RF_RET      RTS
; A = the first byte of a section's name: the section.
READSECT    JSR  OSTRING
            CLR  <TMPB                 ; its flags
RS_FLAG     JSR  OBYTE
            TSTA
            BEQ  RS_FLAGSD
            CMPA #1
            BEQ  RS_BSS
            CMPA #2
            BNE  RS_BADFL
            LDB  #SEF_CONST
            BRA  RS_SETFL
RS_BSS      LDB  #SEF_BSS
RS_SETFL    ORB  <TMPB
            STB  <TMPB
            BRA  RS_FLAG
RS_BADFL    JSR  CURNAME
            LDX  #M_BADFLAG
            JMP  FATAL
RS_FLAGSD   LDX  #NAMEBUF              ; the record
            JSR  STRLEN
            ADDD #SC_NAME+1
            JSR  HALLOC                ; A:X
            STA  <CURSECT
            STX  <CURSECT+1
            PSHS X
            LEAY ,X
            LDB  #SC_NAME
RS_CLR      CLR  ,Y+
            DECB
            BNE  RS_CLR
            LDX  #NAMEBUF
            JSR  STRCPY
            PULS X
            LDA  <CURFILE
            STA  SC_FILE,X
            LDA  <TMPB
            STA  SC_FLAGS,X
            TST  <SECTLAST             ; at the end of the list
            BNE  RS_LINK
            LDD  <CURSECT
            STD  <SECTS
            LDA  <CURSECT+2
            STA  <SECTS+2
            BRA  RS_LAST
RS_LINK     LDD  <SECTLAST
            STD  <FARP
            LDA  <SECTLAST+2
            STA  <FARP+2
            JSR  FARMAP
            LDD  <CURSECT
            STD  SC_NEXT,X
            LDA  <CURSECT+2
            STA  SC_NEXT+2,X
RS_LAST     LDD  <CURSECT
            STD  <SECTLAST
            LDA  <CURSECT+2
            STA  <SECTLAST+2
            LDB  #SC_LOCALS            ; its symbols
            JSR  READSYMS
            LDB  #SC_EXPORTS           ; its exports
            JSR  READSYMS
RS_RELOC    JSR  OBYTE                 ; its relocations
            TSTA
            BEQ  RS_CODE
            JSR  READRELOC
            BRA  RS_RELOC
RS_CODE     JSR  OWORD                 ; its size, its bytes
            PSHS D
            JSR  SECTMAP
            PULS D
            STD  SC_SIZE,X
            LDB  SC_FLAGS,X
            BITB #SEF_BSS
            BNE  RS_RET
            JMP  READCODE
RS_RET      RTS
; CURSECT: mapped, X.
SECTMAP     LDD  <CURSECT
            STD  <FARP
            LDA  <CURSECT+2
            STA  <FARP+2
            JMP  FARMAP
; B = the offset of a list in the section: symbols until a NUL, each at its
; head (as lwlink lists them).
READSYMS    PSHS B
RY_LOOP     JSR  OBYTE
            TSTA
            BEQ  RY_RET
            JSR  OSTRING
            JSR  OWORD
            PSHS D
            LDX  #NAMEBUF
            JSR  STRLEN
            ADDD #SY_NAME+1
            JSR  HALLOC                ; A:X
            STA  <FARP2
            STX  <FARP2+1
            PULS D
            STD  SY_VAL,X
            LDA  <CURFILE
            STA  SY_FILE,X
            LEAY SY_NAME,X
            LDX  #NAMEBUF
            JSR  STRCPY
            LDB  ,S
            JSR  LINKHEAD
            BRA  RY_LOOP
RY_RET      PULS B,PC
; A = the first byte of a relocation's expression: it, and its offset.
READRELOC   CLR  <RFLAGS
            LDX  #EXPRBUF
RR_TERM     TSTA
            BEQ  RR_END
            CMPA #$FF                  ; a flag: kept apart
            BNE  RR_NOTFL
            JSR  OBYTE
            STA  <RFLAGS
            BRA  RR_NEXT
RR_NOTFL    CMPX #EXPRBUF+250
            BHS  RR_BAD
            STA  ,X+
            CMPA #1
            BEQ  RR_INT
            CMPA #2
            BEQ  RR_STR
            CMPA #3
            BEQ  RR_STR
            CMPA #4
            BEQ  RR_OP
            CMPA #5
            BEQ  RR_NEXT
RR_BAD      JSR  CURNAME
            LDX  #M_BADREL
            JMP  FATAL
RR_INT      JSR  OBYTE
            STA  ,X+
RR_OP       JSR  OBYTE
            STA  ,X+
            BRA  RR_NEXT
RR_STR      JSR  OBYTE
            STA  ,X+
            TSTA
            BEQ  RR_NEXT
            CMPX #EXPRBUF+250
            BHS  RR_BAD
            BRA  RR_STR
RR_NEXT     JSR  OBYTE
            BRA  RR_TERM
RR_END      TFR  X,D
            SUBD #EXPRBUF
            STB  <RLEN
            JSR  OWORD                 ; the offset
            STD  <POFF
            LDB  <RLEN
            CLRA
            ADDD #RE_EXPR
            JSR  HALLOC                ; A:X
            STA  <FARP2
            STX  <FARP2+1
            LDD  <POFF
            STD  RE_OFF,X
            LDA  <RFLAGS
            STA  RE_FLAGS,X
            LDB  <RLEN
            STB  RE_LEN,X
            CLRA
            TFR  D,W
            LEAY RE_EXPR,X
            PSHS X
            LDX  #EXPRBUF
            TFM  X+,Y+
            PULS X
            LDB  #SC_RELOCS            ; at the head of the section's list
            JMP  LINKHEAD
; FARP2 = a new record (a symbol or relocation, NEXT at +0), B = the offset of
; a list head in CURSECT: the record goes at the head of that list.
LINKHEAD    PSHS B
            JSR  SECTMAP
            LDB  ,S+
            ABX
            LDD  ,X                    ; the old head
            STD  <PVAL
            LDA  2,X
            STA  <TMPB
            LDA  <FARP2                ; the new head
            STA  ,X
            LDD  <FARP2+1
            STD  1,X
            LDA  <FARP2                ; its next = the old head
            JSR  MAPPG
            LDX  <FARP2+1
            LDD  <PVAL
            STD  0,X
            LDA  <TMPB
            STA  2,X
            RTS
; The section's bytes (CURSECT, SC_SIZE of them) -> chunks.
READCODE    LDD  SC_SIZE,X
            STD  <CNT
            CLR  <PREVCH
            CLR  <FIRSTCH
RD_CHUNK    LDD  <CNT
            BEQ  RD_DONE
            CMPD #CHUNKSZ
            BLS  RD_N
            LDD  #CHUNKSZ
RD_N        PSHS D
            ADDD #3
            JSR  HALLOC                ; A:X
            STA  <FARP2
            STX  <FARP2+1
            CLR  ,X
            TST  <PREVCH               ; linked from the last one
            BNE  RD_LINK
            STA  <FIRSTCH
            STX  <FIRSTCH+1
            BRA  RD_FILL
RD_LINK     LDA  <PREVCH
            JSR  MAPPG
            LDY  <PREVCH+1
            LDA  <FARP2
            STA  ,Y
            STX  1,Y
RD_FILL     LDA  <FARP2
            JSR  MAPPG
            LEAX 3,X
            LDY  ,S                    ; its bytes
RD_BYTE     JSR  OBYTE
            STA  ,X+
            LEAY -1,Y
            BNE  RD_BYTE
            LDD  <CNT
            SUBD ,S++
            STD  <CNT
            LDD  <FARP2
            STD  <PREVCH
            LDA  <FARP2+2
            STA  <PREVCH+2
            BRA  RD_CHUNK
RD_DONE     JSR  SECTMAP
            LDA  <FIRSTCH
            STA  SC_CODE,X
            LDD  <FIRSTCH+1
            STD  SC_CODE+1,X
            RTS
;------------------------------------------------------------------------------
; Before placing (lwlink's resolve_files): every relocation's external names
; looked up once, which brings in each constant section one refers to -- at
; load address 0, and first in the list of sections.
;------------------------------------------------------------------------------
PRECONST    LDA  #1
            STA  <RESONLY
            LDD  <SECTS
            STD  <PCSECT
            LDA  <SECTS+2
            STA  <PCSECT+2
PC_SECT     TST  <PCSECT
            BEQ  PC_RET
            LDD  <PCSECT
            STD  <CURSECT
            LDA  <PCSECT+2
            STA  <CURSECT+2
            JSR  SECTMAP
            LDA  SC_FILE,X
            STA  <CURFILE
            LDD  SC_NEXT,X
            STD  <PCSECT
            LDA  SC_NEXT+2,X
            STA  <PCSECT+2
            LDD  SC_RELOCS,X
            STD  <RELP
            LDA  SC_RELOCS+2,X
            STA  <RELP+2
PC_REL      TST  <RELP
            BEQ  PC_SECT
            LDD  <RELP
            STD  <FARP
            LDA  <RELP+2
            STA  <FARP+2
            JSR  FARMAP
            LDB  RE_LEN,X
            CLRA
            ADDD #RE_EXPR
            TFR  D,W
            LDY  #RLBUF
            TFM  X+,Y+
            CLR  ,Y
            LDD  RLBUF+RE_NEXT
            STD  <RELP
            LDA  RLBUF+RE_NEXT+2
            STA  <RELP+2
            LDX  #RLBUF+RE_EXPR        ; its terms: each external name looked up
PC_TERM     LDA  ,X+
            BEQ  PC_REL
            CMPA #1
            BEQ  PC_SKIP2
            CMPA #4
            BEQ  PC_SKIP1
            CMPA #5
            BEQ  PC_TERM
            CMPA #2
            BNE  PC_SKIPS
            STX  <EXPP
            JSR  TERMNAME
            JSR  FINDEXT
            LDX  <EXPP
            BRA  PC_TERM
PC_SKIP2    LEAX 1,X
PC_SKIP1    LEAX 1,X
            BRA  PC_TERM
PC_SKIPS    LDA  ,X+                   ; (a local name: skipped)
            BNE  PC_SKIPS
            BRA  PC_TERM
PC_RET      CLR  <RESONLY
            RTS
;------------------------------------------------------------------------------
; Placing the sections (lwlink's resolve_sections).
;------------------------------------------------------------------------------
PLACE       CLRD
            STD  <LADDR
            CLR  <GROWDN
            LDU  #SLINES
            LDB  <NSLINES
            LBEQ PL_RET
PL_LINE     PSHS B,U
            TST  SL_HASLOAD,U
            BEQ  PL_NOLOAD
            LDD  SL_LOAD,U
            STD  <LADDR
            LDA  SL_DOWN,U
            STA  <GROWDN
PL_NOLOAD   TST  SL_NAME,U
            BEQ  PL_WILD
            LEAX SL_NAME,U             ; a named one: every instance of it
            LDY  #NAME2
            JSR  STRCPY
            JSR  PLACENAME
            BRA  PL_NEXT
PL_WILD     LDD  <SECTS                ; *: each section not placed, with the
            STD  <CURSECT              ; flags asked for, and all others with
            LDA  <SECTS+2              ; its name
            STA  <CURSECT+2
PL_WLOOP    TST  <CURSECT
            BEQ  PL_NEXT
            JSR  SECTMAP
            LDA  SC_FLAGS,X
            BITA #SEF_CONST
            BNE  PL_WSKIP
            LDU  1,S
            LDB  SL_NO,U
            BEQ  PL_WYES
            BITB SC_FLAGS,X
            BNE  PL_WSKIP
PL_WYES     LDB  SL_YES,U
            BEQ  PL_WPROC
            BITB SC_FLAGS,X
            BEQ  PL_WSKIP
PL_WPROC    TST  SC_PROC,X
            BNE  PL_WSKIP
            LEAX SC_NAME,X
            LDY  #NAME2
            JSR  STRCPY
            LDD  <CURSECT              ; (PLACENAME walks the list itself)
            PSHS D
            LDA  <CURSECT+2
            PSHS A
            JSR  PLACENAME
            PULS A
            STA  <CURSECT+2
            PULS D
            STD  <CURSECT
            JSR  SECTMAP
PL_WSKIP    LDD  SC_NEXT,X
            STD  <CURSECT
            LDA  SC_NEXT+2,X
            STA  <CURSECT+2
            BRA  PL_WLOOP
PL_NEXT     PULS B,U
            LEAU SL_SIZE,U
            DECB
            LBNE PL_LINE
PL_RET      RTS
; NAME2 = a section name: every section of that name (not constant, not placed
; yet), in the order read, placed at LADDR.
PLACENAME   LDD  <SECTS
            STD  <CURSECT
            LDA  <SECTS+2
            STA  <CURSECT+2
PN_LOOP     TST  <CURSECT
            BEQ  PN_RET
            JSR  SECTMAP
            LDA  SC_FLAGS,X
            BITA #SEF_CONST
            BNE  PN_NEXT
            TST  SC_PROC,X
            BNE  PN_NEXT
            PSHS X
            LEAX SC_NAME,X
            LDY  #NAME2
            JSR  STRCMP
            PULS X
            BNE  PN_NEXT
            JSR  PLACEONE
            JSR  SECTMAP
PN_NEXT     LDD  SC_NEXT,X
            STD  <CURSECT
            LDA  SC_NEXT+2,X
            STA  <CURSECT+2
            BRA  PN_LOOP
PN_RET      RTS
; CURSECT (mapped, X): placed at LADDR (below it, going down), at the end of
; the placed list.
PLACEONE    LDA  #1
            STA  SC_PROC,X
            TST  <GROWDN
            BEQ  PO_UP
            LDD  <LADDR
            SUBD SC_SIZE,X
            STD  <LADDR
            STD  SC_LOAD,X
            BRA  PO_LINK
PO_UP       LDD  <LADDR
            STD  SC_LOAD,X
            ADDD SC_SIZE,X
            STD  <LADDR
; CURSECT: at the end of the placed list.
PO_LINK     TST  <OLAST
            BNE  PO_AFTER
            LDD  <CURSECT
            STD  <OHEAD
            LDA  <CURSECT+2
            STA  <OHEAD+2
            BRA  PO_SETL
PO_AFTER    LDD  <OLAST
            STD  <FARP
            LDA  <OLAST+2
            STA  <FARP+2
            JSR  FARMAP
            LDD  <CURSECT
            STD  SC_ONEXT,X
            LDA  <CURSECT+2
            STA  SC_ONEXT+2,X
PO_SETL     LDD  <CURSECT
            STD  <OLAST
            LDA  <CURSECT+2
            STA  <OLAST+2
            RTS
;------------------------------------------------------------------------------
; Synthetic symbols (define basesympat / lensympat): for each run of sections
; of one name, as placed, its lowest address and its total length.
;------------------------------------------------------------------------------
GENSYMS     TST  BPAT
            BNE  GS_GO
            TST  LPAT
            BNE  GS_GO
            RTS
GS_GO       CLR  LASTNAME
            LDD  <OHEAD
            STD  <CURSECT
            LDA  <OHEAD+2
            STA  <CURSECT+2
GS_LOOP     TST  <CURSECT
            BEQ  GS_END
            JSR  SECTMAP
            TST  LASTNAME              ; a new name?
            BEQ  GS_NEW
            PSHS X
            LEAX SC_NAME,X
            LDY  #LASTNAME
            JSR  STRCMP
            PULS X
            BEQ  GS_SAME
            JSR  GSPAIR                ; the last run's symbols
            JSR  SECTMAP
GS_NEW      PSHS X
            LEAX SC_NAME,X
            LDY  #LASTNAME
            JSR  STRCPY
            PULS X
            CLRD
            STD  <GRPLEN
            LDD  SC_LOAD,X
            STD  <GRPLOW
GS_SAME     LDD  <GRPLEN
            ADDD SC_SIZE,X
            STD  <GRPLEN
            LDD  SC_LOAD,X
            CMPD <GRPLOW
            BHS  GS_NOTLOW
            STD  <GRPLOW
GS_NOTLOW   LDD  SC_ONEXT,X
            STD  <CURSECT
            LDA  SC_ONEXT+2,X
            STA  <CURSECT+2
            BRA  GS_LOOP
GS_END      TST  LASTNAME
            BEQ  GS_RET
            JMP  GSPAIR
GS_RET      RTS
; The length symbol, then the base symbol, for LASTNAME.
GSPAIR      TST  LPAT
            BEQ  GP_BASE
            LDX  #LPAT
            LDD  <GRPLEN
            JSR  SYNSYM
GP_BASE     TST  BPAT
            BEQ  GS_RET
            LDX  #BPAT
            LDD  <GRPLOW
; X = a pattern, D = a value: a synthetic symbol (the pattern with %s the name).
SYNSYM      STD  <PVAL
            LDY  #NAMEBUF
SY_PAT      LDA  ,X+
            BEQ  SY_PEND
            CMPA #'%'
            BNE  SY_PCH
            LDA  ,X
            CMPA #'s'
            BNE  SY_PCHP
            LEAX 1,X
            PSHS X
            LDX  #LASTNAME
            JSR  STRCPY
            PULS X
            BRA  SY_PAT
SY_PCHP     LDA  #'%'
SY_PCH      STA  ,Y+
            BRA  SY_PAT
SY_PEND     CLR  ,Y
            LDX  #NAMEBUF
            JSR  STRLEN
            ADDD #SY_NAME+1
            JSR  HALLOC                ; A:X
            PSHS A
            LDD  <SYNTH                ; at the head of SYNTH
            STD  SY_NEXT,X
            LDA  <SYNTH+2
            STA  SY_NEXT+2,X
            PULS A
            STA  <SYNTH
            STX  <SYNTH+1
            LDD  <PVAL
            STD  SY_VAL,X
            STD  SY_ABS,X
            CLR  SY_FILE,X
            LEAY SY_NAME,X
            LDX  #NAMEBUF
            JMP  STRCPY
;------------------------------------------------------------------------------
; The entry point: a symbol from the script or -e (an export, or synthetic).
;------------------------------------------------------------------------------
ENTRY       TST  <EXECSYM
            BEQ  EN_RET
            LDX  #EXECNAME
            LDY  #NAMEBUF
            JSR  STRCPY
            CLR  <CURFILE              ; (no file to look in first)
            JSR  FINDEXT
            BCS  EN_NONE
            STD  <EXECADDR
EN_RET      RTS
EN_NONE     LDX  #M_NOEXT              ; "External symbol S not found"
            JSR  PRINTS
            JSR  PRINTSAN
            LDX  #M_NOTFOUND
            JSR  PRINTS
            JSR  PRINTNL
            LDX  #M_NOEXEC
            JSR  PRINTS
            LDX  #EXECNAME
            JSR  PRINTS
            LDA  #$27
            JSR  PRINTC
            JSR  PRINTNL
            LDA  #1
            STA  <SYMERR
            RTS
;------------------------------------------------------------------------------
; Finding symbols (lwlink's resolve_sym).
;------------------------------------------------------------------------------
; NAMEBUF = an external name, CURFILE = the file referring to it: -> D = its
; value, carry clear; carry set if there is no such export. Synthetic symbols
; first, then that file's exports, then every file's in order.
FINDEXT     LDD  <SYNTH
            STD  <FARP
            LDA  <SYNTH+2
            STA  <FARP+2
FE_SYN      JSR  FARMAP
            BEQ  FE_FILES
            PSHS X
            LEAX SY_NAME,X
            LDY  #NAMEBUF
            JSR  STRCMP
            PULS X
            BEQ  FE_SYNHIT
            LDD  SY_NEXT,X
            STD  <FARP
            LDA  SY_NEXT+2,X
            STA  <FARP+2
            BRA  FE_SYN
FE_SYNHIT   LDD  SY_VAL,X
            ANDCC #$FE
            RTS
FE_FILES    CLR  <FOUNDC
            LDB  <CURFILE              ; its own file first
            BEQ  FE_ALL
            JSR  FINDEXPF
            BCC  FE_RET
FE_ALL      CLRB                       ; then all of them
            JSR  FINDEXPF
FE_RET      RTS
; B = a file (0: every file): its sections' exports searched for NAMEBUF. -> D
; = the value, carry clear; carry set if not found.
FINDEXPF    STB  <TMPB
            LDD  <SECTS
            STD  <FARP2
            LDA  <SECTS+2
            STA  <FARP2+2
FX_SECT     LDA  <FARP2
            LBEQ FX_NONE
            LDD  <FARP2
            STD  <FARP
            LDA  <FARP2+2
            STA  <FARP+2
            JSR  FARMAP
            LDB  <TMPB
            BEQ  FX_ANY
            CMPB SC_FILE,X
            LBNE FX_NEXTS
FX_ANY      LDD  SC_EXPORTS,X
            STD  <FARP
            LDA  SC_EXPORTS+2,X
            STA  <FARP+2
FX_SYM      JSR  FARMAP
            LBEQ FX_NEXTS2
            PSHS X
            LEAX SY_NAME,X
            LDY  #NAMEBUF
            JSR  STRCMP
            PULS X
            BEQ  FX_HIT
            LDD  SY_NEXT,X
            STD  <FARP
            LDA  SY_NEXT+2,X
            STA  <FARP+2
            BRA  FX_SYM
FX_HIT      LDD  SY_VAL,X              ; found, in section FARP2
            STD  <PVAL
            LDD  <FARP2
            STD  <FARP
            LDA  <FARP2+2
            STA  <FARP+2
            JSR  FARMAP
            TST  SC_PROC,X
            BNE  FX_PLACED
            LDA  SC_FLAGS,X            ; not placed: a constant section comes in
            BITA #SEF_CONST            ; (at 0), anything else can't be used
            BNE  FX_CONSTIN
            TST  <RESONLY              ; (except while only looking ahead)
            BNE  FX_PLACED
            BRA  FX_NOTINC
FX_CONSTIN
            LDD  <CURSECT
            PSHS D
            LDA  <CURSECT+2
            PSHS A
            LDD  <FARP2
            STD  <CURSECT
            LDA  <FARP2+2
            STA  <CURSECT+2
            JSR  SECTMAP
            LDA  #1
            STA  SC_PROC,X
            CLRD
            STD  SC_LOAD,X
            JSR  PO_LINK
            PULS A
            STA  <CURSECT+2
            PULS D
            STD  <CURSECT
            LDD  <FARP2
            STD  <FARP
            LDA  <FARP2+2
            STA  <FARP+2
            JSR  FARMAP
FX_PLACED   LDD  <PVAL
            LDB  SC_FLAGS,X
            BITB #SEF_CONST
            BNE  FX_CONST
            LDD  <PVAL
            ADDD SC_LOAD,X
            ANDCC #$FE
            RTS
FX_CONST    LDD  <PVAL
            ANDCC #$FE
            RTS
FX_NOTINC   LDX  #M_SYMIN              ; "Symbol S found in section T (F) which
            JSR  PRINTS                ; is not going to be included"
            LDX  #NAMEBUF
            JSR  PRINTS
            LDX  #M_FOUNDIN
            JSR  PRINTS
            LDD  <FARP2
            STD  <FARP
            LDA  <FARP2+2
            STA  <FARP+2
            JSR  FARMAP
            PSHS X
            LEAX SC_NAME,X
            JSR  PRINTS
            LDX  #M_OPEN
            JSR  PRINTS
            PULS X
            LDB  SC_FILE,X
            JSR  FILENAME
            JSR  PRINTS
            LDX  #M_NOTINC
            JSR  PRINTS
            JSR  PRINTNL
            LDD  <FARP2                ; (and go on looking)
            STD  <FARP
            LDA  <FARP2+2
            STA  <FARP+2
            JSR  FARMAP
            BRA  FX_NEXTS
FX_NEXTS2   LDD  <FARP2
            STD  <FARP
            LDA  <FARP2+2
            STA  <FARP+2
            JSR  FARMAP
FX_NEXTS    LDD  SC_NEXT,X
            STD  <FARP2
            LDA  SC_NEXT+2,X
            STA  <FARP2+2
            LBRA FX_SECT
FX_NONE     ORCC #1
            RTS
; NAMEBUF = a local name, CURSECT = the section referring to it: -> D = its
; value, carry clear; carry set if not found. That section's symbols first,
; then those of every section of its file.
FINDLOCAL   JSR  SECTMAP
            LDA  SC_FILE,X
            STA  <TMPB
            LDD  <CURSECT
            STD  <FARP2
            LDA  <CURSECT+2
            STA  <FARP2+2
            JSR  FLSECT
            BCC  FL_RET
            LDD  <SECTS
            STD  <FARP2
            LDA  <SECTS+2
            STA  <FARP2+2
FL_LOOP     TST  <FARP2
            BEQ  FL_NONE
            LDD  <FARP2
            STD  <FARP
            LDA  <FARP2+2
            STA  <FARP+2
            JSR  FARMAP
            LDA  SC_FILE,X
            CMPA <TMPB
            BNE  FL_NEXT
            JSR  FLSECT
            BCC  FL_RET
            LDD  <FARP2
            STD  <FARP
            LDA  <FARP2+2
            STA  <FARP+2
            JSR  FARMAP
FL_NEXT     LDD  SC_NEXT,X
            STD  <FARP2
            LDA  SC_NEXT+2,X
            STA  <FARP2+2
            BRA  FL_LOOP
FL_NONE     ORCC #1
FL_RET      RTS
; FARP2 = a section: its symbols searched for NAMEBUF -> D, carry clear.
FLSECT      LDD  <FARP2
            STD  <FARP
            LDA  <FARP2+2
            STA  <FARP+2
            JSR  FARMAP
            LDD  SC_LOCALS,X
            STD  <FARP
            LDA  SC_LOCALS+2,X
            STA  <FARP+2
FS_LOOP     JSR  FARMAP
            BEQ  FS_NONE
            PSHS X
            LEAX SY_NAME,X
            LDY  #NAMEBUF
            JSR  STRCMP
            PULS X
            BEQ  FS_HIT
            LDD  SY_NEXT,X
            STD  <FARP
            LDA  SY_NEXT+2,X
            STA  <FARP+2
            BRA  FS_LOOP
FS_HIT      LDD  SY_VAL,X
            STD  <PVAL
            LDD  <FARP2
            STD  <FARP
            LDA  <FARP2+2
            STA  <FARP+2
            JSR  FARMAP
            LDD  <PVAL
            LDB  SC_FLAGS,X
            BITB #SEF_CONST
            BNE  FS_CONST
            LDD  <PVAL
            ADDD SC_LOAD,X
            ANDCC #$FE
            RTS
FS_CONST    LDD  <PVAL
            ANDCC #$FE
            RTS
FS_NONE     ORCC #1
            RTS
;------------------------------------------------------------------------------
; The relocations: each placed section's, each expression evaluated (postfix,
; C int arithmetic) and its value patched into the bytes.
;------------------------------------------------------------------------------
RELOCATE    LDD  <OHEAD
            STD  <CURSECT
            LDA  <OHEAD+2
            STA  <CURSECT+2
RL_SECT     TST  <CURSECT
            LBEQ RL_RET
            JSR  SECTMAP
            LDA  SC_FILE,X
            STA  <CURFILE
            LDD  SC_RELOCS,X
            STD  <RELP
            LDA  SC_RELOCS+2,X
            STA  <RELP+2
RL_REL      TST  <RELP
            BEQ  RL_NEXTS
            LDD  <RELP                 ; a copy of it (RLBUF)
            STD  <FARP
            LDA  <RELP+2
            STA  <FARP+2
            JSR  FARMAP
            LDB  RE_LEN,X
            CLRA
            ADDD #RE_EXPR
            TFR  D,W
            LDY  #RLBUF
            TFM  X+,Y+
            CLR  ,Y                    ; (the expression ends with a NUL)
            LDD  RLBUF+RE_NEXT
            STD  <RELP
            LDA  RLBUF+RE_NEXT+2
            STA  <RELP+2
            JSR  EVALREL               ; -> D, carry if it couldn't be
            BCS  RL_INCOMP
            JSR  PATCH
            BRA  RL_REL
RL_INCOMP   LDX  #M_INCOMP             ; "Incomplete reference at F:S+XX"
            JSR  PRINTS
            JSR  SECTWHERE
            LDA  #'+'
            JSR  PRINTC
            LDD  RLBUF+RE_OFF          ; (%02X: at least 2 digits, no more
            LDX  #NUMBUF               ; leading zeros)
            JSR  HEX4
            CLR  ,X
            LDX  #NUMBUF
RL_OFFZ     LDA  ,X
            CMPA #'0'
            BNE  RL_OFFQ
            CMPX #NUMBUF+2
            BHS  RL_OFFQ
            LEAX 1,X
            BRA  RL_OFFZ
RL_OFFQ     JSR  PRINTS
            JSR  PRINTNL
            LDA  #1
            STA  <SYMERR
            BRA  RL_REL
RL_NEXTS    JSR  SECTMAP
            LDD  SC_ONEXT,X
            STD  <CURSECT
            LDA  SC_ONEXT+2,X
            STA  <CURSECT+2
            LBRA RL_SECT
RL_RET      RTS
; "FILE:SECTION" of CURSECT, printed.
SECTWHERE   LDB  <CURFILE
            JSR  FILENAME
            JSR  PRINTS
            LDA  #':'
            JSR  PRINTC
            JSR  SECTMAP
            LEAX SC_NAME,X
            JMP  PRINTS
; RLBUF = a relocation: its expression's value -> D; carry set if it doesn't
; come to a single number.
EVALREL     CLR  <ESP
            LDX  #RLBUF+RE_EXPR
ER_TERM     LDA  ,X+
            STX  <EXPP
            TSTA
            LBEQ ER_END
            CMPA #1
            BEQ  ER_INT
            CMPA #2
            BEQ  ER_EXT
            CMPA #3
            BEQ  ER_LOC
            CMPA #4
            LBEQ ER_OP
            JSR  SECTMAP               ; 5: this section's base
            LDD  SC_LOAD,X
            LDX  <EXPP
            BRA  ER_PUSHU
ER_INT      LDD  ,X++                  ; a number (16 bits, signed)
            STX  <EXPP
            PSHS D
            LDD  #0
            TST  ,S
            BPL  ER_IPOS
            LDD  #$FFFF
ER_IPOS     PSHS D
            JSR  EPUSH4
            BCS  ER_FAILX
            LDX  <EXPP
            BRA  ER_TERM
ER_EXT      STX  <EXPP                 ; another file's symbol
            JSR  TERMNAME
            JSR  FINDEXT
            BCC  ER_SYMV
            LDX  #M_NOEXT
            JMP  ER_NOTFOUND
ER_LOC      STX  <EXPP                 ; a symbol of this file ("" = the base)
            JSR  TERMNAME
            TST  NAMEBUF
            BNE  ER_LNAMED
            JSR  SECTMAP
            LDD  SC_LOAD,X
            BRA  ER_SYMV
ER_LNAMED   JSR  FINDLOCAL
            BCC  ER_SYMV
            LDX  #M_NOLOC
            JMP  ER_NOTFOUND
ER_SYMV     LDX  <EXPP
ER_PUSHU    STX  <EXPP                 ; D (16 bits, unsigned) pushed
            PSHS D
            CLRD
            PSHS D
            JSR  EPUSH4
            BCS  ER_FAILX
            LDX  <EXPP
            BRA  ER_TERM
ER_FAILX    ORCC #1
            RTS
; X at a term's name: -> NAMEBUF, EXPP past it.
TERMNAME    LDX  <EXPP
            LDY  #NAMEBUF
TN_LOOP     LDA  ,X+
            STA  ,Y+
            BNE  TN_LOOP
            STX  <EXPP
            RTS
; X = the message: "... symbol NAME not found in FILE:SECT" (the reference is
; then incomplete).
ER_NOTFOUND JSR  PRINTS
            JSR  PRINTSAN
            LDX  #M_NOTFOUNDIN
            JSR  PRINTS
            JSR  SECTWHERE
            JSR  PRINTNL
            LDA  #1
            STA  <SYMERR
            ORCC #1
            RTS
ER_OP       LDB  ,X+                   ; an operator
            STB  <EOP
            STX  <EXPP
            CMPB #12
            BEQ  ER_NEG
            CMPB #13
            BEQ  ER_COM
            LDA  <ESP                  ; binary: a op b
            CMPA #2
            BLO  ER_FAILX
            JSR  EPOP                  ; b -> MB
            LDQ  <MA
            STQ  <MB
            JSR  EPOP                  ; a -> MA
            LDB  <EOP
            JSR  APPLY                 ; -> MA; carry: dividing by 0 / unknown
            BCS  ER_FAILX
ER_REPUSH   LDQ  <MA
            PSHSW
            PSHS D
            JSR  EPUSH4
            LDX  <EXPP
            LBRA ER_TERM
ER_NEG      TST  <ESP
            BEQ  ER_FAILX
            JSR  EPOP
            LDX  #MA
            JSR  NEG32
            BRA  ER_REPUSH
ER_COM      TST  <ESP
            BEQ  ER_FAILX
            JSR  EPOP
            COM  <MA
            COM  <MA+1
            COM  <MA+2
            COM  <MA+3
            BRA  ER_REPUSH
ER_END      LDA  <ESP                  ; one value: the result
            CMPA #1
            LBNE ER_FAILX
            JSR  EPOP
            LDD  <MA+2
            ANDCC #$FE
            RTS
; The 4 bytes on the stack (under the return address) -> the expression stack.
EPUSH4      LDA  <ESP
            CMPA #ESTKMAX
            BHS  EP_FULL
            LDB  #4
            MUL
            ADDD #ESTACK
            TFR  D,Y
            LDD  2,S
            STD  ,Y
            LDD  4,S
            STD  2,Y
            INC  <ESP
            LDX  ,S                    ; (drop the 4 bytes)
            LEAS 6,S
            ANDCC #$FE
            JMP  ,X
EP_FULL     LDX  ,S
            LEAS 6,S
            ORCC #1
            JMP  ,X
; The top of the expression stack -> MA.
EPOP        DEC  <ESP
            LDA  <ESP
            LDB  #4
            MUL
            ADDD #ESTACK
            TFR  D,Y
            LDQ  ,Y
            STQ  <MA
            RTS
; MA = MA op MB (B = lwlink's operator): carry set if it can't be done.
APPLY       CMPB #1
            BEQ  AP_PLUS
            CMPB #2
            BEQ  AP_MINUS
            CMPB #3
            BEQ  AP_TIMES
            CMPB #4
            BEQ  AP_DIV
            CMPB #5
            BEQ  AP_MOD
            CMPB #6
            BEQ  AP_DIV
            CMPB #7
            BEQ  AP_AND
            CMPB #8
            BEQ  AP_OR
            CMPB #9
            BEQ  AP_XOR
            CMPB #10
            LBEQ AP_LAND
            CMPB #11
            LBEQ AP_LOR
            ORCC #1
            RTS
AP_PLUS     LDQ  <MA
            ADDW <MB+2
            ADCD <MB
            STQ  <MA
            ANDCC #$FE
            RTS
AP_MINUS    LDQ  <MA
            SUBW <MB+2
            SBCD <MB
            STQ  <MA
            ANDCC #$FE
            RTS
AP_TIMES    JSR  MUL32
            ANDCC #$FE
            RTS
AP_DIV      LDQ  <MB
            BEQ  AP_FAIL
            JSR  DIV32
            ANDCC #$FE
            RTS
AP_MOD      LDQ  <MB
            BEQ  AP_FAIL
            JSR  DIV32
            LDQ  <MB                   ; (the remainder)
            STQ  <MA
            ANDCC #$FE
            RTS
AP_FAIL     ORCC #1
            RTS
AP_AND      LDD  <MA
            ANDD <MB
            STD  <MA
            LDD  <MA+2
            ANDD <MB+2
            STD  <MA+2
            ANDCC #$FE
            RTS
AP_OR       LDD  <MA
            ORD  <MB
            STD  <MA
            LDD  <MA+2
            ORD  <MB+2
            STD  <MA+2
            ANDCC #$FE
            RTS
AP_XOR      LDD  <MA
            EORD <MB
            STD  <MA
            LDD  <MA+2
            EORD <MB+2
            STD  <MA+2
            ANDCC #$FE
            RTS
AP_LAND     BSR  AP_TRUTH
            ANDA <TMPB
            BRA  AP_BOOL
AP_LOR      BSR  AP_TRUTH
            ORA  <TMPB
AP_BOOL     CLR  <MA
            CLR  <MA+1
            CLR  <MA+2
            STA  <MA+3
            ANDCC #$FE
            RTS
; -> A = (MA != 0), TMPB = (MB != 0)
AP_TRUTH    CLR  <TMPB
            LDQ  <MB
            BEQ  AT_B0
            INC  <TMPB
AT_B0       CLRA
            LDQ  <MA
            BEQ  AT_A0
            LDA  #1
            RTS
AT_A0       CLRA
            RTS
; D = a value: into CURSECT's bytes at RLBUF's offset (8 or 16 bits).
PATCH       STD  <PVAL
            LDD  RLBUF+RE_OFF
            STD  <POFF
            LDA  RLBUF+RE_FLAGS
            CMPA #1
            BEQ  PT_LOW
            LDA  <PVAL
            JSR  PATCHB
            LDD  <POFF
            ADDD #1
            STD  <POFF
PT_LOW      LDA  <PVAL+1
; A = a byte: into CURSECT's bytes at POFF.
PATCHB      PSHS A
            JSR  SECTMAP
            LDD  SC_CODE,X
            STD  <FARP
            LDA  SC_CODE+2,X
            STA  <FARP+2
            LDD  <POFF
PB_CHUNK    PSHS D
            JSR  FARMAP
            PULS D
            BEQ  PB_NONE
            CMPD #CHUNKSZ
            BLO  PB_HERE
            SUBD #CHUNKSZ
            PSHS D
            LDD  ,X
            STD  <FARP
            LDA  2,X
            STA  <FARP+2
            PULS D
            BRA  PB_CHUNK
PB_HERE     LEAX 3,X
            LEAX D,X
            PULS A
            STA  ,X
            RTS
PB_NONE     PULS A,PC                  ; (outside the bytes: nothing)
;------------------------------------------------------------------------------
; The output: the placed sections' bytes (not bss), raw, as S-records, or as a
; Pugputer program.
;------------------------------------------------------------------------------
OUTPUT      LDU  #OUTSTRM
            LDX  #OUTNAME
            JSR  SOPEN
            BCC  OU_OPEN
            LDX  #M_NOOUT
            JSR  PRINTS
            LDX  #OUTNAME
            JMP  FATAL
OU_OPEN     LDA  #1
            STA  <OUTON
            LDA  <FORMAT
            CMPA #FMT_COM
            BNE  OU_BODY
            JSR  FIRSTOUT              ; the program header
            LDD  #EXE_MAGIC
            JSR  SPUTW
            LDD  <PVAL
            JSR  SPUTW
            TST  <EXECSYM
            BNE  OU_ENTRY
            LDD  <EXECADDR
            BNE  OU_ENTRY2
            LDD  <PVAL
            BRA  OU_ENTRY2
OU_ENTRY    LDD  <EXECADDR
OU_ENTRY2   JSR  SPUTW
            CLRD
            JSR  SPUTW
OU_BODY     LDD  <OHEAD
            STD  <CURSECT
            LDA  <OHEAD+2
            STA  <CURSECT+2
OU_SECT     TST  <CURSECT
            BEQ  OU_END
            JSR  SECTMAP
            LDA  SC_FLAGS,X
            BITA #SEF_BSS
            BNE  OU_NEXT
            LDD  SC_SIZE,X
            BEQ  OU_NEXT
            LDA  <FORMAT
            CMPA #FMT_SREC
            BNE  OU_RAW
            JSR  SRECSECT
            BRA  OU_NEXT
OU_RAW      JSR  RAWSECT
OU_NEXT     JSR  SECTMAP
            LDD  SC_ONEXT,X
            STD  <CURSECT
            LDA  SC_ONEXT+2,X
            STA  <CURSECT+2
            BRA  OU_SECT
OU_END      LDA  <FORMAT
            CMPA #FMT_SREC
            BNE  OU_CLOSE
            LDX  #M_S903               ; "S903" addr, checksum
            JSR  SPUTS
            LDA  #3
            ADDA <EXECADDR
            ADDA <EXECADDR+1
            COMA
            PSHS A
            LDD  <EXECADDR
            JSR  SPUTHEX4
            PULS A
            JSR  SPUTHEX
            JSR  SPUTNL
OU_CLOSE    JSR  SCLOSE
            CLR  <OUTON
            RTS
; -> PVAL = the first output byte's address (the first placed section with
; bytes, not bss), for a .COM header.
FIRSTOUT    CLRD
            STD  <PVAL
            LDD  <OHEAD
            STD  <FARP
            LDA  <OHEAD+2
            STA  <FARP+2
FO_LOOP     JSR  FARMAP
            BEQ  FO_RET
            LDA  SC_FLAGS,X
            BITA #SEF_BSS
            BNE  FO_NEXT
            LDD  SC_SIZE,X
            BEQ  FO_NEXT
            LDD  SC_LOAD,X
            STD  <PVAL
            RTS
FO_NEXT     LDD  SC_ONEXT,X
            STD  <FARP
            LDA  SC_ONEXT+2,X
            STA  <FARP+2
            BRA  FO_LOOP
FO_RET      RTS
SPUTW       PSHS B                     ; D -> the stream U, high byte first
            JSR  SPUTC
            PULS A
            JMP  SPUTC
; CURSECT's bytes, one at a time: CALLB (X = the byte's address in the
; window, the chunk mapped) for each. BYTECNT counts down.
RAWSECT     LDD  #RAWBYTE
            BRA  SECTBYTES
SRECSECT    JSR  SECTMAP
            LDD  SC_LOAD,X
            STD  <SRADDR
            CLR  SRLEN
            LDD  #SRECBYTE
            JSR  SECTBYTES
            JMP  SRECFLUSH
; D = a routine, called with A = each byte of CURSECT in turn.
SECTBYTES   STD  CALLB
            JSR  SECTMAP
            LDD  SC_SIZE,X
            STD  <CNT
            LDD  SC_CODE,X
            STD  <FARP2
            LDA  SC_CODE+2,X
            STA  <FARP2+2
SB_CHUNK    LDD  <CNT
            BEQ  SB_RET
            LDD  <FARP2
            STD  <FARP
            LDA  <FARP2+2
            STA  <FARP+2
            JSR  FARMAP
            BEQ  SB_RET
            LDD  ,X
            STD  <FARP2
            LDA  2,X
            STA  <FARP2+2
            LEAX 3,X
            LDY  #CHUNKSZ
SB_BYTE     LDA  ,X+
            PSHS X,Y
            JSR  [CALLB]
            PULS X,Y
            LDD  <CNT
            SUBD #1
            STD  <CNT
            BEQ  SB_RET
            LEAY -1,Y
            BNE  SB_BYTE
            BRA  SB_CHUNK
SB_RET      RTS
RAWBYTE     LDU  #OUTSTRM
            JMP  SPUTC
; S-records as lwlink writes them: 16 bytes a record, from each section's
; start; CR LF after each.
SRECBYTE    LDB  SRLEN
            LDX  #SRBUF
            STA  B,X
            INCB
            STB  SRLEN
            CMPB #16
            BLO  SR_RET
SRECFLUSH   LDB  SRLEN
            BEQ  SR_RET
            LDU  #OUTSTRM
            LDX  #M_S1
            JSR  SPUTS
            LDA  SRLEN
            ADDA #3
            STA  <SRSUM
            JSR  SPUTHEX
            LDD  <SRADDR
            JSR  SPUTHEX4
            ADDA <SRSUM
            STA  <SRSUM
            TFR  B,A
            ADDA <SRSUM
            STA  <SRSUM
            LDX  #SRBUF
            LDB  SRLEN
SR_DATA     LDA  ,X+
            JSR  SPUTHEX
            ADDA <SRSUM
            STA  <SRSUM
            DECB
            BNE  SR_DATA
            LDA  <SRSUM
            COMA
            JSR  SPUTHEX
            JSR  SPUTNL
            LDB  SRLEN
            CLRA
            ADDD <SRADDR
            STD  <SRADDR
            CLR  SRLEN
SR_RET      RTS
; A -> two hex digits in the stream U. Keeps A, X.
SPUTHEX     PSHS A,X
            LDX  #NUMBUF
            JSR  HEX2
            LDA  NUMBUF
            JSR  SPUTC
            LDA  NUMBUF+1
            JSR  SPUTC
            PULS A,X,PC
; D -> four hex digits in the stream U. Keeps D.
SPUTHEX4    JSR  SPUTHEX
            PSHS A
            TFR  B,A
            JSR  SPUTHEX
            PULS A,PC
;------------------------------------------------------------------------------
; The map (lwlink's display_map): the sections as placed, then every symbol
; of them (and the synthetic ones), by name, then file.
;------------------------------------------------------------------------------
MAP         LDU  #MAPSTRM
            LDX  #MAPNAME
            JSR  SOPEN
            BCC  MP_OPEN
            LDX  #M_NOMAP
            JSR  PRINTS
            LDX  #MAPNAME
            JMP  FATAL
MP_OPEN     CLRD
            STD  <NSYM
            LDD  <OHEAD                ; the sections (and a count of symbols)
            STD  <CURSECT
            LDA  <OHEAD+2
            STA  <CURSECT+2
MP_SECT     TST  <CURSECT
            LBEQ MP_SYMS
            JSR  SECTMAP
            LDU  #MAPSTRM
            PSHS X
            LDX  #M_MSECT              ; "Section: NAME (FILE) load at AAAA,
            JSR  SPUTS                 ; length LLLL"
            LDX  ,S
            LEAX SC_NAME,X
            JSR  SPUTSAN
            LDX  #M_OPEN
            JSR  SPUTS
            LDX  ,S
            LDB  SC_FILE,X
            JSR  FILENAME
            JSR  SPUTS
            LDX  #M_LOADAT
            JSR  SPUTS
            LDX  ,S
            LDD  SC_LOAD,X
            JSR  SPUTHEX4
            LDX  #M_LENGTH
            JSR  SPUTS
            PULS X
            LDD  SC_SIZE,X
            JSR  SPUTHEX4
            JSR  SPUTNL
            LDD  SC_LOCALS,X           ; its symbols: their addresses, counted
            STD  <FARP
            LDA  SC_LOCALS+2,X
            STA  <FARP+2
            LDD  SC_LOAD,X
            STD  <PVAL
            LDA  SC_FLAGS,X
            BITA #SEF_CONST
            BEQ  MP_SYM
            CLRD
            STD  <PVAL
MP_SYM      JSR  FARMAP
            BEQ  MP_NEXTS
            LDD  SY_VAL,X
            ADDD <PVAL
            STD  SY_ABS,X
            LDD  <NSYM
            ADDD #1
            STD  <NSYM
            LDD  SY_NEXT,X
            STD  <FARP
            LDA  SY_NEXT+2,X
            STA  <FARP+2
            BRA  MP_SYM
MP_NEXTS    JSR  SECTMAP
            LDD  SC_ONEXT,X
            STD  <CURSECT
            LDA  SC_ONEXT+2,X
            STA  <CURSECT+2
            LBRA MP_SECT
MP_SYMS     LDD  <SYNTH                ; the synthetic ones, counted
            STD  <FARP
            LDA  <SYNTH+2
            STA  <FARP+2
MP_SYNC     JSR  FARMAP
            BEQ  MP_ARRAY
            LDD  <NSYM
            ADDD #1
            STD  <NSYM
            LDD  SY_NEXT,X
            STD  <FARP
            LDA  SY_NEXT+2,X
            STA  <FARP+2
            BRA  MP_SYNC
MP_ARRAY    LDD  <NSYM
            LBEQ MP_CLOSE
            CMPD #4000
            BLS  MP_FITS
            LDX  #M_MANYSYMS
            JMP  FATAL
MP_FITS     ADDD <NSYM                 ; the array: 3 bytes each
            ADDD <NSYM
            JSR  HALLOC
            STA  <ARRPG
            STX  <ARRADDR
            STX  <ARRPTR
            LDD  <SYNTH                ; fill it: the synthetic ones
            STD  <FARP
            LDA  <SYNTH+2
            STA  <FARP+2
            JSR  ADDLIST
            LDD  <OHEAD                ; then each section's
            STD  <CURSECT
            LDA  <OHEAD+2
            STA  <CURSECT+2
MP_FILL     TST  <CURSECT
            BEQ  MP_SORT
            JSR  SECTMAP
            LDD  SC_ONEXT,X
            PSHS D
            LDA  SC_ONEXT+2,X
            PSHS A
            LDD  SC_LOCALS,X
            STD  <FARP
            LDA  SC_LOCALS+2,X
            STA  <FARP+2
            JSR  ADDLIST
            PULS A
            STA  <CURSECT+2
            PULS D
            STD  <CURSECT
            BRA  MP_FILL
MP_SORT     JSR  HEAPSORT
            CLRD
            STD  <HSI
MP_PRINT    LDD  <HSI
            CMPD <NSYM
            BHS  MP_CLOSE
            JSR  ARRGET
            JSR  FARMAP
            LDU  #MAPSTRM              ; "Symbol: NAME (FILE) = AAAA"
            PSHS X
            LDX  #M_MSYM
            JSR  SPUTS
            LDX  ,S
            LEAX SY_NAME,X
            JSR  SPUTSAN
            LDX  #M_OPEN
            JSR  SPUTS
            LDX  ,S
            LDB  SY_FILE,X
            JSR  FILENAME
            JSR  SPUTS
            LDX  #M_EQUALS
            JSR  SPUTS
            PULS X
            LDD  SY_ABS,X
            JSR  SPUTHEX4
            JSR  SPUTNL
            LDD  <HSI
            ADDD #1
            STD  <HSI
            BRA  MP_PRINT
MP_CLOSE    LDU  #MAPSTRM
            JMP  SCLOSE
; FARP = a list of symbols: each one's far pointer -> the array.
ADDLIST     JSR  FARMAP
            BEQ  AL_RET
            LDD  SY_NEXT,X
            PSHS D
            LDA  SY_NEXT+2,X
            PSHS A
            LDA  <ARRPG
            JSR  MAPPG
            LDY  <ARRPTR
            LDD  <FARP
            STD  ,Y++
            LDA  <FARP+2
            STA  ,Y+
            STY  <ARRPTR
            PULS A
            STA  <FARP+2
            PULS D
            STD  <FARP
            BRA  ADDLIST
AL_RET      RTS
; U = a stream, X = a name: written as lwlink's sanitize_symbol writes it (\\
; for \, \XX for a control or non-ASCII character).
SPUTSAN     LDA  ,X+
            BEQ  SN_RET
            CMPA #$5C
            BNE  SN_NOTBS
            JSR  SPUTC
            JSR  SPUTC
            BRA  SPUTSAN
SN_NOTBS    CMPA #32
            BLO  SN_HEX
            CMPA #126
            BHI  SN_HEX
            JSR  SPUTC
            BRA  SPUTSAN
SN_HEX      PSHS A
            LDA  #$5C
            JSR  SPUTC
            PULS A
            JSR  SPUTHEX
            BRA  SPUTSAN
SN_RET      RTS
; NAMEBUF, sanitized, on the console.
PRINTSAN    LDX  #NAMEBUF
PS_LOOP     LDA  ,X+
            BEQ  PS_RET
            CMPA #32
            BLO  PS_HEX
            CMPA #126
            BHI  PS_HEX
            JSR  PRINTC
            BRA  PS_LOOP
PS_HEX      PSHS A,X
            LDA  #$5C
            JSR  PRINTC
            LDA  ,S
            LDX  #NUMBUF
            JSR  HEX2
            CLR  ,X
            LDX  #NUMBUF
            JSR  PRINTS
            PULS A,X
            BRA  PS_LOOP
PS_RET      RTS
;------------------------------------------------------------------------------
; Heap sort of the map's array (NSYM far pointers to symbols): by name (strcmp),
; then by file name.
;------------------------------------------------------------------------------
HEAPSORT    LDD  <NSYM
            LSRA
            RORB
HS_BUILD    SUBD #1
            BMI  HS_SORT
            STD  <HSK
            LDD  <NSYM
            STD  <HSN
            LDD  <HSK
            JSR  SIFTDOWN
            LDD  <HSK
            BRA  HS_BUILD
HS_SORT     LDD  <NSYM
HS_LOOP     SUBD #1
            BLE  HS_RET
            STD  <HSN
            JSR  SWAP0N
            LDD  #0
            JSR  SIFTDOWN
            LDD  <HSN
            BRA  HS_LOOP
HS_RET      RTS
; Swaps elements 0 and HSN.
SWAP0N      LDD  #0
            JSR  ARRGET
            LDD  <FARP
            PSHS D
            LDA  <FARP+2
            PSHS A
            LDD  <HSN
            JSR  ARRGET
            LDD  #0
            JSR  ARRPUT
            PULS A
            STA  <FARP+2
            PULS D
            STD  <FARP
            LDD  <HSN
            JMP  ARRPUT
; D = an index: sifted down in the heap of HSN elements.
SIFTDOWN    STD  <HSJ
SD_LOOP     LDD  <HSJ                  ; the larger child
            ASLB
            ROLA
            ADDD #1
            CMPD <HSN
            BHS  SD_RET
            PSHS D
            ADDD #1
            CMPD <HSN
            PULS D
            BHS  SD_ONE
            PSHS D                     ; right > left?
            ADDD #1
            JSR  ARRGET
            JSR  SAVEKEY2
            LDD  ,S
            JSR  ARRGET
            JSR  SYMCMP                ; left vs right
            PULS D
            BGE  SD_ONE
            ADDD #1
SD_ONE      PSHS D                     ; the child > this one?
            JSR  ARRGET
            JSR  SAVEKEY2
            LDD  <HSJ
            JSR  ARRGET
            JSR  SYMCMP
            PULS D
            BGE  SD_RET
            PSHS D                     ; swap them
            JSR  ARRGET
            LDD  <FARP
            STD  <FARP2
            LDA  <FARP+2
            STA  <FARP2+2
            LDD  <HSJ
            JSR  ARRGET
            LDD  ,S
            JSR  ARRPUT
            LDD  <FARP2
            STD  <FARP
            LDA  <FARP2+2
            STA  <FARP+2
            LDD  <HSJ
            JSR  ARRPUT
            PULS D
            STD  <HSJ
            BRA  SD_LOOP
SD_RET      RTS
; D = an index: -> FARP = that element. Keeps D.
ARRGET      PSHS D,X
            LDA  <ARRPG
            JSR  MAPPG
            LDD  ,S
            ADDD ,S
            ADDD ,S
            ADDD <ARRADDR
            TFR  D,X
            LDD  ,X
            STD  <FARP
            LDA  2,X
            STA  <FARP+2
            PULS D,X,PC
; D = an index: that element = FARP. Keeps D.
ARRPUT      PSHS D,X
            LDA  <ARRPG
            JSR  MAPPG
            LDD  ,S
            ADDD ,S
            ADDD ,S
            ADDD <ARRADDR
            TFR  D,X
            LDD  <FARP
            STD  ,X
            LDA  <FARP+2
            STA  2,X
            PULS D,X,PC
; The symbol at FARP -> key 2 (KEY2: its name, KEY2F: its file).
SAVEKEY2    JSR  FARMAP
            LDA  SY_FILE,X
            STA  <KEY2F
            LEAX SY_NAME,X
            LDY  #KEY2
            JMP  STRCPY
; The symbol at FARP against key 2: -> the flags for a signed comparison (BLT:
; before, BGE: after or the same). Names as strcmp (unsigned), then files.
SYMCMP      JSR  FARMAP
            LDB  SY_FILE,X
            LEAX SY_NAME,X
            LDY  #KEY2
SM_LOOP     LDA  ,X+
            CMPA ,Y+
            BNE  SM_DIFF
            TSTA
            BNE  SM_LOOP
            JSR  FILENAME              ; the same name: the files' names
            LDB  <KEY2F
            PSHS X
            JSR  FILENAME
            TFR  X,Y
            PULS X
SM_FLOOP    LDA  ,X+
            CMPA ,Y+
            BNE  SM_DIFF
            TSTA
            BNE  SM_FLOOP
            CLRA                       ; the same
            RTS
SM_DIFF     BLO  SM_LESS               ; (unsigned: ours vs key 2's)
            LDA  #1
            RTS
SM_LESS     LDA  #-1
            RTS
;------------------------------------------------------------------------------
    INCLUDE pa_util.asm
    INCLUDE pa_heap.asm
    INCLUDE pa_strm.asm
;------------------------------------------------------------------------------
; lwlink's built-in scripts (one line each, a NUL between, two at the end).
RAW_SCRIPT  FCN  "define basesympat s_%s"
            FCN  "define lensympat l_%s"
            FCN  "section init load 0000"
            FCN  "section code"
            FCN  "section *,!bss"
            FCN  "section *,bss"
            FCB  0
SREC_SCRIPT FCN  "define basesympat s_%s"
            FCN  "define lensympat l_%s"
            FCN  "section init load 0400"
            FCN  "section code"
            FCN  "section *,!bss"
            FCN  "section *,bss"
            FCN  "entry __start"
            FCB  0
M_MAGIC     FCC  "LWOBJ16"
            FCB  0
M_RAW       FCN  "raw"
M_SREC      FCN  "srec"
M_COM       FCN  "com"
M_SECTION   FCN  "section"
M_ENTRY     FCN  "entry"
M_DEFINE    FCN  "define"
M_PAD       FCN  "pad"
M_STACKSIZE FCN  "stacksize"
M_SECTOPT   FCN  "sectopt"
M_BASESYM   FCN  "basesympat"
M_LENSYM    FCN  "lensympat"
M_LOAD      FCN  "load"
M_HIGH      FCN  "high"
M_LOADSP    FCN  " load "
M_NBSS      FCN  "!bss"
M_AOUT      FCN  "A.OUT"
LO_FORMAT   FCN  "format="
LO_OUTPUT   FCN  "output="
LO_MAP      FCN  "map="
LO_SCRIPT   FCN  "script="
LO_ENTRY    FCN  "entry="
LO_BASE     FCN  "section-base="
M_S1        FCN  "S1"
M_S903      FCN  "S903"
M_MSECT     FCN  "Section: "
M_MSYM      FCN  "Symbol: "
M_OPEN      FCN  " ("
M_LOADAT    FCN  ") load at "
M_LENGTH    FCN  ", length "
M_EQUALS    FCN  ") = "
M_SYNTH     FCN  "<synthetic>"
M_COLON     FCN  ": "
M_USAGE     FCC  "Usage: PUGLINK [-f raw|srec|com] [-o out] [-m map] [-s script]"
            FCB  CR,LF
            FCC  "               [-e entry] [--section-base=S=ADDR] file.o ..."
            FCB  CR,LF,0
M_BADFMT    FCN  "Invalid output format: "
M_NOINPUT   FCN  "No input files"
M_MANYFILES FCN  "Too many input files"
M_NOSCRIPT  FCN  "Can't open file "
M_NOFILE    FCN  "Can't open file "
M_NOOUT     FCN  "Cannot open output file "
M_NOMAP     FCN  "Cannot open map file "
M_NOTOBJ    FCN  "unknown file format"
M_BADOBJ    FCN  "invalid file format"
M_BADFLAG   FCN  "unrecognized section flag"
M_BADREL    FCN  "bad relocation expression"
M_BADLINE   FCN  "bad script line: "
M_NOSECTOPT FCN  "sectopt is not supported"
M_MANYLINES FCN  "Too many section lines in the script"
M_NOEXEC    FCN  "Cannot resolve exec address '"
M_INCOMP    FCN  "Incomplete reference at "
M_NOEXT     FCN  "External symbol "
M_NOLOC     FCN  "Local symbol "
M_NOTFOUNDIN FCC " not found in "
            FCB  0
M_NOTFOUND  FCN  " not found"
M_SYMIN     FCN  "Symbol "
M_FOUNDIN   FCN  " found in section "
M_NOTINC    FCN  ") which is not going to be included"
M_MANYSYMS  FCN  "Too many symbols for the map"
M_NOMEM     FCN  "Out of memory"
M_WRITEERR  FCN  "Cannot write the output (disk full?)"
;------------------------------------------------------------------------------
PL_END      equ  *
;------------------------------------------------------------------------------
; Variables and buffers after the program (none of this is in the file).
;------------------------------------------------------------------------------
VARS        equ  *
VP          SET  VARS
            VAR  OUTNAME,PATHMAX+1
            VAR  MAPNAME,PATHMAX+1
            VAR  SCRNAME,PATHMAX+1
            VAR  EXECNAME,SYMMAX+2
            VAR  ENTRYARG,PATHMAX+1
            VAR  FILETAB,MAXFILES*(PATHMAX+1)
            VAR  SLINES,MAXSLINES*SL_SIZE
            VAR  BASES,MAXBASES*SL_SIZE
            VAR  NAMEBUF,SYMMAX+2
            VAR  NAME2,SYMMAX+2
            VAR  KEY2,SYMMAX+2
            VAR  LASTNAME,SYMMAX+2
            VAR  BPAT,32
            VAR  LPAT,32
            VAR  LINEBUF,256
            VAR  WORKBUF,256
            VAR  EXPRBUF,256
            VAR  RLBUF,RE_EXPR+258
            VAR  RDBUF,256
            VAR  OUTSTRM,4+256
            VAR  MAPSTRM,4+256
            VAR  NUMBUF,16
            VAR  PAGES,MAXPAGES
            VAR  ESTACK,ESTKMAX*4
            VAR  SRBUF,16
            VAR  SRLEN,1
            VAR  CALLB,2
            VAR  RSPIN,1
            VAR  RSPBUF,RSPMAX+1
VARSEND     equ  VP
;------------------------------------------------------------------------------
; End of puglink.asm
;------------------------------------------------------------------------------
