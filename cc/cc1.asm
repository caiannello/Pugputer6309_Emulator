;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 C compiler
;    FILE: cc1.asm
;
; CC1.COM: the compiler proper, CC's second stage (see DESIGN.md). It reads
; one preprocessed file (CPP's .I) and writes its assembly language (.ASM),
; for ASM (or lwasm) to make an object file of.
;
;   CC1 [-o FILE] file
;     -o FILE   the output (default: the source's name with .ASM)
;     -T        (testing) the tokens instead, one a line
;
; The C it takes: char, short, int, long, signed, unsigned, void, pointers,
; arrays, functions with prototypes (and "..."), struct, union, enum, typedef,
; extern and static, initializers, string literals, locals in any block, every
; statement and every operator, asm { } and interrupt (not yet: bit-fields,
; float, -9). The calling convention is cc/README.md's.
;
; How it works: one top-level declaration at a time; a function one statement
; at a time. Each full expression is parsed to a tree (NODES, used again for
; the next one), its types worked out and its constants folded as it is built,
; then made into code straight away (cc1_gen.asm). Names, types and the
; symbols at file level last to the end (the heap, growing up from HEAPBASE);
; a function's locals go when it ends (they are allocated from the top down).
; The first error ends it: the message, and no output.
;
; Memory: the direct page $3400, the program from $3500, its buffers, the heap,
; the stack below $F000.
;------------------------------------------------------------------------------
    INCLUDE defines.d
;------------------------------------------------------------------------------
DPAGE       equ  $3400             ; the direct page (not part of the file)
PA_BASE     equ  $3500
STACKTOP    equ  $F000
STACKSZ     equ  3072              ; below STACKTOP: the stack; below that, the heap
NAMEMAX     equ  62                ; significant characters in a name
PATHMAX     equ  79
INBUFSZ     equ  512
STRMAX      equ  1024              ; a string literal's bytes
NHASH       equ  256               ; name hash buckets (2 bytes each)
MAXNODES    equ  500
OPSTKSZ     equ  384               ; declarator operations being collected
PTMPSZ      equ  512               ; parameters being collected
MAXCASES    equ  256
MAXLABELS   equ  64                ; goto labels in one function
MAXDEPTH    equ  32                ; nested scopes
;------------------------------------------------------------------------------
; Tokens. A character stands for itself ('+', ';', ...); these are the rest.
T_EOF       equ  0
T_ID        equ  $80               ; TOKV = the name record
T_NUM       equ  $81               ; TOKV = the value (32 bits), TOKFL = TF_*
T_STR       equ  $82               ; TOKSB = the bytes, TOKSL = how many
T_INC       equ  $83               ; ++
T_DEC       equ  $84               ; --
T_ARROW     equ  $85               ; ->
T_SHL       equ  $86               ; <<
T_SHR       equ  $87               ; >>
T_LE        equ  $88               ; <=
T_GE        equ  $89               ; >=
T_EQ        equ  $8A               ; ==
T_NE        equ  $8B               ; !=
T_ANDAND    equ  $8C               ; &&
T_OROR      equ  $8D               ; ||
T_ELLIP     equ  $8E               ; ...
T_MULEQ     equ  $8F               ; *= and the other assignments: in the
T_DIVEQ     equ  $90               ; order of ASGOPS (cc1_expr.asm)
T_MODEQ     equ  $91
T_ADDEQ     equ  $92
T_SUBEQ     equ  $93
T_SHLEQ     equ  $94
T_SHREQ     equ  $95
T_ANDEQ     equ  $96
T_XOREQ     equ  $97
T_OREQ      equ  $98
; Keywords (KEYWORDS, cc1_lex.asm, is in this order)
K_FIRST     equ  $A0
K_AUTO      equ  $A0
K_BREAK     equ  $A1
K_CASE      equ  $A2
K_CHAR      equ  $A3
K_CONST     equ  $A4
K_CONTINUE  equ  $A5
K_DEFAULT   equ  $A6
K_DO        equ  $A7
K_DOUBLE    equ  $A8
K_ELSE      equ  $A9
K_ENUM      equ  $AA
K_EXTERN    equ  $AB
K_FLOAT     equ  $AC
K_FOR       equ  $AD
K_GOTO      equ  $AE
K_IF        equ  $AF
K_INT       equ  $B0
K_LONG      equ  $B1
K_REGISTER  equ  $B2
K_RETURN    equ  $B3
K_SHORT     equ  $B4
K_SIGNED    equ  $B5
K_SIZEOF    equ  $B6
K_STATIC    equ  $B7
K_STRUCT    equ  $B8
K_SWITCH    equ  $B9
K_TYPEDEF   equ  $BA
K_UNION     equ  $BB
K_UNSIGNED  equ  $BC
K_VOID      equ  $BD
K_VOLATILE  equ  $BE
K_WHILE     equ  $BF
K_ASM       equ  $C0
K_INTERRUPT equ  $C1
K_LAST      equ  $C1
TF_UNS      equ  1                 ; a number's suffix: u
TF_LONG     equ  2                 ; l
TF_NDEC     equ  4                 ; written in hex or octal
TF_CHAR     equ  8                 ; a character constant
;------------------------------------------------------------------------------
; A name (interned: one record per spelling):
NM_NEXT     equ  0                 ; the next in its hash bucket
NM_SYM      equ  2                 ; the symbol it means now (0: none)
NM_TAG      equ  4                 ; the struct, union or enum tag it means now
NM_KW       equ  6                 ; a keyword's token (0: not one)
NM_TEXT     equ  7                 ; the spelling, NUL-terminated
; A type:
TY_KIND     equ  0                 ; TK_*
TY_FL       equ  1                 ; TYF_*
TY_BASE     equ  2                 ; what it points to / is an array of /
TY_SIZE     equ  4                 ; returns; its size in bytes
TY_N        equ  6                 ; an array's elements
TY_PTR      equ  8                 ; the pointer type to it (made when asked)
TY_PAR      equ  10                ; a function's parameters (PL_*); a struct's
TYSIZE      equ  12                ; members (MB_*)
TK_VOID     equ  0
TK_CHAR     equ  1                 ; char (signed)
TK_SCHAR    equ  2
TK_UCHAR    equ  3
TK_INT      equ  4                 ; (short too)
TK_UINT     equ  5
TK_LONG     equ  6
TK_ULONG    equ  7
TK_PTR      equ  8
TK_ARRAY    equ  9
TK_FUNC     equ  10
TK_STRUCT   equ  11                ; (and union: TYF_UNION)
TYF_NOSIZE  equ  1                 ; an array of no size given (yet), a struct
TYF_UNION   equ  2                 ; not defined (yet)
; A struct's or union's member:
ME_NEXT     equ  0
ME_NAME     equ  2
ME_TYPE     equ  4
ME_OFF      equ  6
MESIZE      equ  8
; A parameter list (a function type's TY_PAR):
PL_N        equ  0                 ; how many
PL_FL       equ  1                 ; PLF_*
PL_PAR      equ  2                 ; then, each: its type, its name (or 0)
PLF_PROTO   equ  1                 ; a prototype (not "()")
PLF_VAR     equ  2                 ; ends with "..."
; A symbol:
SY_NAME     equ  0
SY_SHADOW   equ  2                 ; the one with the same name it hides
SY_NEXT     equ  4                 ; the next in its scope
SY_KIND     equ  6                 ; SK_*
SY_FL       equ  7                 ; SF_*
SY_TYPE     equ  8
SY_VAL      equ  10                ; a local's offset from U; a label number; an
SY_DEPTH    equ  12                ; enum constant's value; a tag's keyword; an
SYSIZE      equ  13                ; extern in a block: the file's symbol
                                   ; (SY_DEPTH: the scope it's in, 0: the file)
SK_GLOBAL   equ  1                 ; an object or function at file level: _name
SK_LOCAL    equ  2                 ; on the stack: n,U
SK_STATLOC  equ  3                 ; a static in a function: Ln
SK_TYPEDEF  equ  4
SK_TAG      equ  5                 ; a struct, union or enum tag (NM_TAG)
SK_ENUMC    equ  6                 ; an enum's constant
SK_EXTREF   equ  7                 ; an extern declared in a block
SF_DEFINED  equ  1                 ; defined in this file (not just declared)
SF_USED     equ  2                 ; referred to (IMPORTed, if not defined)
SF_STATIC   equ  4                 ; static (not EXPORTed)
SF_TENT     equ  8                 ; a tentative definition (int x;): to bss
SF_EXTERN   equ  16                ; declared extern
SF_INTR     equ  32                ; an interrupt function (RTI)
; An expression node:
N_OP        equ  0                 ; O_*
N_FL        equ  1                 ; NF_*
N_TYPE      equ  2
N_L         equ  4
N_R         equ  6
N_V         equ  8                 ; O_NUM: the value (its low word); O_SYM:
N_X         equ  10                ; the symbol; O_STR: the label; O_ASGOP: the
NODESZ      equ  12                ; operation; inc/dec: the step; O_CALL of a
NF_LVAL     equ  1                 ; struct: where it goes (n,U). N_X: O_NUM:
NF_UNS      equ  2                 ; a long's high word; ?:'s third; a call's
                                   ; arguments' size in words
O_NUM       equ  1
O_SYM       equ  2
O_STR       equ  3
O_ADDR      equ  4
O_DEREF     equ  5
O_NEG       equ  6
O_COM       equ  7
O_NOT       equ  8
O_CAST      equ  9
O_PREINC    equ  10
O_PREDEC    equ  11
O_POSTINC   equ  12
O_POSTDEC   equ  13
O_CALL      equ  14
O_ARG       equ  15
O_COND      equ  16
O_COMMA     equ  17
O_ASSIGN    equ  18
O_ASGOP     equ  19
O_LAND      equ  20
O_LOR       equ  21
O_FRAME     equ  22                ; a local's bytes (N_V = their offset)
O_ADD       equ  23                ; the binary operators, from here on
O_SUB       equ  24
O_MUL       equ  25
O_DIV       equ  26
O_MOD       equ  27
O_SHL       equ  28
O_SHR       equ  29
O_AND       equ  30
O_OR        equ  31
O_XOR       equ  32
O_EQ        equ  33                ; the comparisons, from here on
O_NE        equ  34
O_LT        equ  35
O_GT        equ  36
O_LE        equ  37
O_GE        equ  38
O_LAST      equ  38
; Storage classes (DSSC)
SC_NONE     equ  0
SC_TYPEDEF  equ  1
SC_EXTERN   equ  2
SC_STATIC   equ  3
SC_AUTO     equ  4
; Declarator operations (OPSTK: 3 bytes each)
DO_PTR      equ  1
DO_ARRAY    equ  2                 ; the count ($FFFF: none given)
DO_FUNC     equ  3                 ; the parameter list
; Operand modes (cc1_gen.asm)
OM_IMM      equ  1                 ; #v
OM_EXT      equ  2                 ; v (memory at an address)
OM_IND      equ  3                 ; [v]
OM_UOFF     equ  4                 ; n,U
OM_UIND     equ  5                 ; [n,U]
OM_XOFF     equ  6                 ; n,X
OM_POP      equ  7                 ; ,S++
; Output sections
SEC_NONE    equ  0
SEC_CODE    equ  1
SEC_RODATA  equ  2
SEC_DATA    equ  3
SEC_BSS     equ  4
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
            DVAR MA,4                  ; 32-bit arithmetic (pa_util.asm)
            DVAR MB,4
            DVAR MQ,4
            DVAR MSIGN,1
            DVAR TESTTOK,1             ; -T
            DVAR OUTON,1
            DVAR INH,1                 ; the input
            DVAR INPOS,2
            DVAR INEND,2
            DVAR INEOF,1
            DVAR RAWF,1                ; a byte put back (CR's look-ahead)
            DVAR RAWC,1
            DVAR UNGF,1                ; a character put back
            DVAR UNGC,1
            DVAR LINENO,2
            DVAR ATBOL,1               ; at the start of a line
            DVAR HEAPLO,2              ; the heap: what lasts grows up from here,
            DVAR HEAPHI,2              ; a function's down from here
            DVAR TOK,1                 ; the current token
            DVAR TOKV,4
            DVAR TOKSB,2
            DVAR TOKSL,2
            DVAR TOKLN,2
            DVAR TOKFL,1
            DVAR AHEAD,1               ; another, looked ahead at (AHEADF: there)
            DVAR AHEADV,4
            DVAR AHEADSB,2
            DVAR AHEADSL,2
            DVAR AHEADLN,2
            DVAR AHEADFL,1
            DVAR LXTOK,1               ; what LEX made
            DVAR LXV,4
            DVAR LXSB,2
            DVAR LXSL,2
            DVAR LXLN,2
            DVAR LXFL,1
            DVAR AHEADF,1
            DVAR TMP,2
            DVAR TMP2,2
            DVAR TMP3,2
            DVAR TMPB,1
            DVAR TMPB2,1
            DVAR LABELNO,2             ; the last label number used
            DVAR CURSECT,1             ; the output's section (SEC_*)
            DVAR DEPTH,1               ; the scope (0: the file)
            DVAR NODEP,2               ; the next free node
            DVAR DSTYPE,2              ; declaration specifiers: the type,
            DVAR DSSC,1                ; the storage class
            DVAR DNAME,2               ; a declarator's name (0: none)
            DVAR DTYPE,2               ; and its type
            DVAR OPTOP,2               ; OPSTK's top
            DVAR PTTOP,2               ; PTMP's top
            DVAR ABSTRACT,1            ; a declarator may have no name
            DVAR SPBITS,1              ; DECLSPEC: the type words seen,
            DVAR SPTDEF,2              ; a typedef's (or struct's) type,
            DVAR SPANY,1               ; anything at all,
            DVAR DSINTR,1              ; interrupt (DSTYPE to here: SAVEDECL)
            DVAR CURFUNC,2             ; the function being compiled (symbol)
            DVAR RETLBL,2              ; its return's label
            DVAR FRAMESZ,2             ; its locals: so far, in this block
            DVAR MAXFRAME,2            ; and at most
            DVAR BRKLBL,2              ; where break goes (0: nowhere)
            DVAR CONTLBL,2             ; and continue
            DVAR CASEP,2               ; CASES's top
            DVAR SWCASES,2             ; the switch's first case
            DVAR SWDEFLT,2             ; its default's label (0: none)
            DVAR INSWITCH,1
            DVAR SWTYPE,2              ; its cases' type
            DVAR NLABELS,1             ; goto labels
            DVAR OPM,1                 ; an operand (cc1_gen.asm): its mode,
            DVAR OPV,2                 ; number or offset,
            DVAR OPS,2                 ; symbol (or 0),
            DVAR OPL,2                 ; label (or 0)
            DVAR OPVH,2                ; a long number's high word
            DVAR CVSYM,2               ; a constant (EVALCONST): its symbol,
            DVAR CVLBL,2               ; label,
            DVAR CVVAL,2               ; value or offset
            DVAR EXPECTED,1            ; the token EXPECT wanted
            DVAR FRMLBL,2              ; the label EQU'd to the frame's size
            DVAR HELPERS,2             ; the library's helpers used (bit n: the
                                       ; n'th of HELPNAMES, from bit 0 of +1)
            DVAR IMODE,1               ; an initializer: 0 data, 1 code (n,U)
            DVAR IBASE,2               ; code: the object's place (n,U)
            DVAR IDONE,2               ; its bytes done so far
            DVAR EL,2                  ; an operator being built: its left,
            DVAR ER,2                  ; right,
            DVAR EOP,1                 ; operation,
            DVAR ETY,2                 ; type,
            DVAR EUNS,1                ; NF_UNS if its operands are unsigned
            DVAR FA,2                  ; folding: the values
            DVAR FB,2
            DVAR EOPND,2               ; ?:'s condition
            DVAR CMPUNS,1              ; CMPGEN: an unsigned comparison
            DVAR AGNEED,1              ; op= and ++/--: the value wanted,
            DVAR AGNODE,2              ; the node,
            DVAR AGSAVE,7              ; where x is (OPM...)
DP_END      equ  DP_VP
;------------------------------------------------------------------------------
    ORG  PA_BASE-EXE_HDRSIZE
    FDB  EXE_MAGIC                 ; the program header
    FDB  PA_BASE                   ; load address
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
            LDX  #ZERO
            LDY  #VARS
            LDW  #VARSEND-VARS
            TFM  X,Y+
            LDD  #HEAPBASE
            STD  <HEAPLO
            LDD  #STACKTOP-STACKSZ
            STD  <HEAPHI
            LDD  #CASES
            STD  <CASEP
            LDD  #OPSTK
            STD  <OPTOP
            LDD  #PTMP
            STD  <PTTOP
            LDD  #NODES
            STD  <NODEP
            JSR  CMDLINE
            JSR  LEXINIT
            LDX  #SRCNAME              ; the input
            LDE  #FOPEN_READ
            LDA  #B_FOPEN_NAME
            SWI2
            BCC  ST_IN
            LDX  #M_NOSRC
            JSR  PRINTS
            LDX  #SRCNAME
            JMP  FATAL
ST_IN       STA  <INH
            LDU  #OUTSTRM              ; the output
            LDX  #OUTNAME
            JSR  SOPEN
            BCC  ST_OUT
            LDX  #M_NOOUT
            JSR  PRINTS
            LDX  #OUTNAME
            JMP  FATAL
ST_OUT      LDA  #1
            STA  <OUTON
            JSR  NEXT                  ; the first token
            TST  <TESTTOK
            BEQ  ST_COMPILE
            JSR  TOKDUMP
            BRA  ST_END
ST_COMPILE  JSR  PROGRAM
ST_END      CLR  <OUTON
            LDU  #OUTSTRM
            JSR  SCLOSE
            LDA  #B_EXIT
            SWI2
; A fatal error: X = the message (on the console). The output goes.
FATAL       JSR  PRINTS
            JSR  PRINTNL
            TST  <OUTON
            BEQ  FA_EXIT
            CLR  <OUTON
            LDU  #OUTSTRM
            CLR  1,U                   ; (not flushed: that may be what failed)
            LDB  ,U
            LDA  #B_FCLOSE_NAME
            SWI2
            LDX  #OUTNAME
            LDA  #B_KILL_NAME
            SWI2
FA_EXIT     LDA  #B_EXIT
            SWI2
; An error in the source: X = the message. "FILE:LINE: error: message".
ERROR       PSHS X
            LDX  #CURFILE
            JSR  PRINTS
            LDA  #':'
            JSR  PRINTC
            LDD  <TOKLN
            JSR  PRINTDEC
            LDX  #M_ERRPFX
            JSR  PRINTS
            PULS X
            JMP  FATAL
; ERRORN: the same, with " 'NAME'" after (Y = the name record).
ERRORN      PSHS X
            LDX  #CURFILE
            JSR  PRINTS
            LDA  #':'
            JSR  PRINTC
            LDD  <TOKLN
            JSR  PRINTDEC
            LDX  #M_ERRPFX
            JSR  PRINTS
            PULS X
            JSR  PRINTS
            LDX  #M_QUOTE1
            JSR  PRINTS
            LEAX NM_TEXT,Y
            JSR  PRINTS
            LDA  #$27
            JSR  PRINTC
            LDX  #ZERO
            JMP  FATAL
;------------------------------------------------------------------------------
; The command line.
;------------------------------------------------------------------------------
CMDLINE     LDA  #B_ARGS
            SWI2
CL_NEXT     JSR  SKIPSP
            LDA  ,X
            BEQ  CL_DONE
            CMPA #'-'
            BNE  CL_FILE
            LDA  1,X
            LEAX 2,X
            CMPA #'o'
            BEQ  CL_OUT
            CMPA #'T'
            BEQ  CL_TEST
            BRA  USAGE
CL_TEST     LDA  #1
            STA  <TESTTOK
            BRA  CL_NEXT
CL_OUT      JSR  OPTARG
            LDY  #OUTNAME
            JSR  GETWORD
            BRA  CL_NEXT
CL_FILE     TST  SRCNAME
            BNE  USAGE
            LDY  #SRCNAME
            JSR  GETWORD
            BRA  CL_NEXT
CL_DONE     TST  SRCNAME
            BEQ  USAGE
            LDX  #SRCNAME              ; the file's name, for the messages
            LDY  #CURFILE
            JSR  STRCPY
            TST  OUTNAME
            LBNE CL_RET
            LDX  #EXT_ASM
            LDY  #OUTNAME
            JMP  NEWEXT
CL_RET      RTS
USAGE       LDX  #M_USAGE
            JSR  PRINTS
            LDA  #B_EXIT
            SWI2
; X is just past an option letter: to its argument (attached, or the next word).
OPTARG      LDA  ,X
            BEQ  OA_NEXT
            JSR  ISSPACE
            LBCS OA_RET
OA_NEXT     JSR  SKIPSP
            LDA  ,X
            LBEQ USAGE
OA_RET      RTS
; X -> Y: a word (to a space or the end), at most PATHMAX characters; Y ends at
; its NUL.
GETWORD     LDB  #PATHMAX
GW_LOOP     LDA  ,X
            BEQ  GW_END
            JSR  ISSPACE
            LBCC GW_END
            LEAX 1,X
            TSTB
            BEQ  GW_LOOP
            STA  ,Y+
            DECB
            BRA  GW_LOOP
GW_END      CLR  ,Y
            RTS
; SRCNAME with its extension replaced by the one at X -> Y.
NEWEXT      PSHS X
            PSHS Y
            LDX  #SRCNAME
            JSR  STRCPY
            TFR  Y,U
NE_BACK     CMPY ,S
            LBEQ NE_ADD
            LDA  -1,Y
            CMPA #'/'
            BEQ  NE_ADD
            CMPA #'.'
            LBEQ NE_DOT
            LEAY -1,Y
            LBRA NE_BACK
NE_DOT      LEAY -1,Y
            BRA  NE_PUT
NE_ADD      TFR  U,Y
NE_PUT      LEAS 2,S
            PULS X
            JMP  STRCPY
;------------------------------------------------------------------------------
; The heap. ALLOC: D bytes that last (cleared) -> X. TALLOC: D bytes that go
; when the function ends -> X.
;------------------------------------------------------------------------------
ALLOC       PSHS D
            LDX  <HEAPLO
            ADDD <HEAPLO
            BCS  AL_FULL
            CMPD <HEAPHI
            BHI  AL_FULL
            STD  <HEAPLO
AL_CLEAR    PSHS X,Y
            TFR  X,Y
            LDX  #ZERO
            LDW  4,S
            BEQ  AL_RET
            TFM  X,Y+
AL_RET      PULS X,Y
            PULS D,PC
AL_FULL     LDX  #M_NOMEM
            JMP  ERROR
TALLOC      PSHS D
            LDD  <HEAPHI
            SUBD ,S
            BCS  AL_FULL
            CMPD <HEAPLO
            BLO  AL_FULL
            STD  <HEAPHI
            TFR  D,X
            BRA  AL_CLEAR
;------------------------------------------------------------------------------
    INCLUDE cc1_lex.asm
    INCLUDE cc1_sym.asm
    INCLUDE cc1_decl.asm
    INCLUDE cc1_stmt.asm
    INCLUDE cc1_expr.asm
    INCLUDE cc1_gen.asm
    INCLUDE cc1_long.asm
    INCLUDE pa_util.asm
    INCLUDE pa_strm.asm
;------------------------------------------------------------------------------
M_USAGE     FCC  "Usage: CC1 [-o out] file"
            FCB  CR,LF,0
M_NOSRC     FCN  "Cannot open "
M_NOOUT     FCN  "Cannot create "
M_WRITEERR  FCN  "Cannot write the output (disk full?)"
M_ERRPFX    FCN  ": error: "
M_QUOTE1    FCB  ' ',$27,0
M_NOMEM     FCN  "out of memory"
EXT_ASM     FCN  ".ASM"
;------------------------------------------------------------------------------
PA_END      equ  *
;------------------------------------------------------------------------------
; Variables and buffers after the program (none of this is in the file).
;------------------------------------------------------------------------------
VARS        equ  *
VP          SET  VARS
            VAR  SRCNAME,PATHMAX+1
            VAR  OUTNAME,PATHMAX+1
            VAR  CURFILE,PATHMAX+1     ; the source file (#line), for messages
            VAR  NAMEBUF,NAMEMAX+2
            VAR  DIRBUF,256            ; a #line or #pragma line
            VAR  INBUF,INBUFSZ
            VAR  STRB0,STRMAX+2        ; string literals' bytes (two: one for
            VAR  STRB1,STRMAX+2        ; the token looked ahead at)
            VAR  HASHTAB,NHASH*2
            VAR  OUTSTRM,4+256
            VAR  NODES,MAXNODES*NODESZ
            VAR  OPSTK,OPSTKSZ
            VAR  PTMP,PTMPSZ
            VAR  CASES,MAXCASES*6      ; a switch's cases: value (32 bits), label
            VAR  LABELS,MAXLABELS*5    ; goto labels: name, label, defined
            VAR  SCOPES,MAXDEPTH*2     ; each scope's symbols (a list)
            VAR  NUMBUF,16
            VAR  ERRBUF,64
VARSEND     equ  VP
HEAPBASE    equ  VARSEND
;------------------------------------------------------------------------------
; End of cc1.asm
;------------------------------------------------------------------------------
