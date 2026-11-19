;------------------------------------------------------------------------------
; cc1_expr.asm -- CC1: expressions, parsed to trees (X = a node, always).
; Their types are worked out as they're built: arrays and functions become
; pointers where C makes them, pointer arithmetic is scaled, the operands'
; types decide signedness, and constants are folded. (The builders keep what
; they work on in EL, ER, EOP, ETY, EUNS; the parser keeps its own on the
; stack, as NEXT changes X and Y.)
;------------------------------------------------------------------------------
RESETNODES  LDD  #NODES
            STD  <NODEP
            RTS
; A = an operation -> X = a new node for it (cleared). Keeps Y.
NEWNODE     LDX  <NODEP
            CMPX #NODES+MAXNODES*NODESZ
            BHS  NN_FULL
            PSHS A
            LEAX NODESZ,X
            STX  <NODEP
            LEAX -NODESZ,X
            CLRD
            STD  ,X
            STD  2,X
            STD  4,X
            STD  6,X
            STD  8,X
            STD  10,X
            PULS A
            STA  N_OP,X
            RTS
NN_FULL     LDX  #M_COMPLEX
            JMP  ERROR
; D = a number, Y = its type -> X = a node for it.
MKNUM       PSHS D
            LDA  #O_NUM
            BSR  NEWNODE
            PULS D
            STD  N_V,X
            STY  N_TYPE,X
            RTS
; X = a node, Y = a type, A = an operation -> X = a node of it over X.
MKUNODE     PSHS X,Y
            JSR  NEWNODE
            PULS D,Y
            STD  N_L,X
            STY  N_TYPE,X
            RTS
;------------------------------------------------------------------------------
; Conversions.
;------------------------------------------------------------------------------
; X = a node used for its value: an array is a pointer to its first element,
; a function a pointer to it.
DECAY       LDY  N_TYPE,X
            LDA  TY_KIND,Y
            CMPA #TK_ARRAY
            BEQ  DY_ARRAY
            CMPA #TK_FUNC
            BEQ  DY_FUNC
            RTS
DY_ARRAY    PSHS X                     ; the address, as a pointer to the
            LDX  TY_BASE,Y             ; element
            JSR  PTRTO
            TFR  X,Y
            PULS X
            LDA  N_OP,X
            CMPA #O_DEREF
            BEQ  DY_DEREF
            CMPA #O_STR
            BEQ  DY_RETYPE
            LDA  #O_ADDR
            JMP  MKUNODE
DY_DEREF    LDX  N_L,X                 ; *(p) of an array: p itself
DY_RETYPE   STY  N_TYPE,X
            CLR  N_FL,X
            RTS
DY_FUNC     PSHS X
            TFR  Y,X
            JSR  PTRTO
            TFR  X,Y
            PULS X
            LDA  #O_ADDR
            JMP  MKUNODE
; X = a node, Y = a type: X converted to it, as assignment does -> X.
MKCONVERT   PSHS Y
            JSR  DECAY
            PULS Y
            LDA  TY_KIND,Y
            CMPA #TK_VOID
            BEQ  MC_RET
            EXG  X,Y
            JSR  TISSCALAR
            EXG  X,Y
            BCS  MC_BAD
            PSHS X
            LDX  N_TYPE,X
            JSR  TISSCALAR
            PULS X
            BCS  MC_BAD
            EXG  X,Y                   ; to a char: a cast, unless it's that
            JSR  TISCHAR               ; char already
            EXG  X,Y
            BCS  MC_RET
            PSHS Y
            LDY  N_TYPE,X
            LDA  TY_KIND,Y
            PULS Y
            CMPA TY_KIND,Y
            BEQ  MC_RET
            JMP  MKCAST
MC_RET      RTS
MC_BAD      LDX  #M_BADCONV
            JMP  ERROR
; X = a node, Y = a type: (type) X -> X.
MKCAST      LDA  TY_KIND,Y
            CMPA #TK_VOID
            BEQ  CA_NODE
            PSHS Y
            JSR  DECAY
            PULS Y
            EXG  X,Y
            JSR  TISSCALAR
            EXG  X,Y
            BCS  CA_BAD
            PSHS X
            LDX  N_TYPE,X
            JSR  TISSCALAR
            PULS X
            BCS  CA_BAD
            LDA  N_OP,X                ; a number: its new value
            CMPA #O_NUM
            BNE  CA_NODE
            EXG  X,Y
            JSR  TISCHAR
            EXG  X,Y
            BCS  CA_RETYPE
            LDA  TY_KIND,Y
            LDB  N_V+1,X
            CMPA #TK_UCHAR
            BEQ  CA_UCHAR
            SEX
            BRA  CA_SET
CA_UCHAR    CLRA
CA_SET      STD  N_V,X
CA_RETYPE   STY  N_TYPE,X
            RTS
CA_NODE     LDA  #O_CAST
            JMP  MKUNODE
CA_BAD      LDX  #M_BADCAST
            JMP  ERROR
; X, Y = (promoted) integer types -> X = the type of an arithmetic operation
; on them: unsigned int if either is, otherwise int. (long comes later.)
USUALTYPE   JSR  TISLONG
            BCC  UT_LONG
            EXG  X,Y
            JSR  TISLONG
            BCC  UT_LONG
            LDA  TY_KIND,X
            CMPA #TK_UINT
            BEQ  UT_UNS
            LDA  TY_KIND,Y
            CMPA #TK_UINT
            BEQ  UT_UNS
            LDX  #TYP_INT
            RTS
UT_UNS      LDX  #TYP_UINT
            RTS
UT_LONG     LDX  #M_NOTYET
            JMP  ERROR
; X = a type -> X = its promoted type (char -> int).
PROMOTE     JSR  TISCHAR
            BCS  PR_RET
            LDX  #TYP_INT
PR_RET      RTS
; EL's and ER's types -> X, Y, promoted.
PROMBOTH    LDX  <ER
            LDX  N_TYPE,X
            BSR  PROMOTE
            TFR  X,Y
            LDX  <EL
            LDX  N_TYPE,X
            BRA  PROMOTE
; An error unless EL and ER are integers (BOTHINT) or scalars (BOTHSCALAR).
BOTHINT     LDX  <EL
            LDX  N_TYPE,X
            JSR  TISINT
            BCS  BI_BAD
            LDX  <ER
            LDX  N_TYPE,X
            JSR  TISINT
            BCS  BI_BAD
            RTS
BI_BAD      LDX  #M_NOTINT
            JMP  ERROR
BOTHSCALAR  LDX  <EL
            LDX  N_TYPE,X
            JSR  TISSCALAR
            BCS  BS_BAD
            LDX  <ER
            LDX  N_TYPE,X
            JSR  TISSCALAR
            BCS  BS_BAD
            RTS
BS_BAD      LDX  #M_NOTSCALAR
            JMP  ERROR
; Carry clear if EL and ER are both numbers.
BOTHNUM     LDX  <EL
            LDA  N_OP,X
            CMPA #O_NUM
            BNE  BN_NO
            LDX  <ER
            LDA  N_OP,X
            CMPA #O_NUM
            BNE  BN_NO
            ANDCC #$FE
            RTS
BN_NO       ORCC #1
            RTS
; EUNS = NF_UNS if the type X is unsigned, or 0.
SETUNS      CLR  <EUNS
            JSR  TISUNS
            BCS  SU_RET
            LDA  #NF_UNS
            STA  <EUNS
SU_RET      RTS
;------------------------------------------------------------------------------
; The operators.
;------------------------------------------------------------------------------
; X = left, Y = right, A = an operation (O_ADD to O_GE, O_LAND, O_LOR) -> X =
; the node.
MKBINARY    STA  <EOP
            PSHS Y
            JSR  DECAY
            STX  <EL
            PULS X
            JSR  DECAY
            STX  <ER
            LDA  <EOP
            CMPA #O_LAND
            BEQ  MB_LOGIC
            CMPA #O_LOR
            BEQ  MB_LOGIC
            CMPA #O_EQ
            BHS  MB_COMPARE
            CMPA #O_ADD
            LBEQ MB_ADD
            CMPA #O_SUB
            LBEQ MB_SUB
MB_ARITH    JSR  BOTHINT               ; integers
            JSR  PROMBOTH
            LDA  <EOP
            CMPA #O_SHL                ; a shift: the left one's type
            BEQ  MB_TYPE
            CMPA #O_SHR
            BEQ  MB_TYPE
            JSR  USUALTYPE
MB_TYPE     STX  <ETY
            JSR  SETUNS
MB_BUILD    JSR  BOTHNUM
            BCS  BINNODE
            JSR  FOLD
            LDX  <EL
            STD  N_V,X
            LDD  <ETY
            STD  N_TYPE,X
            RTS
; The node: EOP, EL, ER, ETY, EUNS -> X.
BINNODE     LDA  <EOP
            JSR  NEWNODE
            LDD  <EL
            STD  N_L,X
            LDD  <ER
            STD  N_R,X
            LDD  <ETY
            STD  N_TYPE,X
            LDA  <EUNS
            STA  N_FL,X
            RTS
MB_LOGIC    JSR  BOTHSCALAR            ; && ||
            LDX  #TYP_INT
            STX  <ETY
            CLR  <EUNS
            BRA  MB_BUILD
MB_COMPARE  JSR  BOTHSCALAR            ; == != < > <= >=: int, signed or not
            JSR  PROMBOTH              ; as the operands are
            JSR  SETUNS
            TFR  Y,X
            LDA  <EUNS
            PSHS A
            JSR  SETUNS
            PULS A
            ORA  <EUNS
            STA  <EUNS
            LDX  #TYP_INT
            STX  <ETY
            BRA  MB_BUILD
MB_ADD      LDX  <EL                   ; pointer + integer
            LDX  N_TYPE,X
            JSR  TISPTR
            BCC  MA_PTR
            LDX  <ER                   ; integer + pointer: the other way round
            LDX  N_TYPE,X
            JSR  TISPTR
            LBCS MB_ARITH
            LDD  <EL
            LDX  <ER
            STX  <EL
            STD  <ER
MA_PTR      LDX  <ER
            LDX  N_TYPE,X
            JSR  TISINT
            LBCS BI_BAD
            JSR  SCALEER
            LDX  <EL
            LDX  N_TYPE,X
            STX  <ETY
            CLR  <EUNS
            LBRA MB_BUILD
MB_SUB      LDX  <EL
            LDX  N_TYPE,X
            JSR  TISPTR
            LBCS MB_ARITH
            LDX  <ER
            LDX  N_TYPE,X
            JSR  TISPTR
            BCC  MS_PTRS
            BRA  MA_PTR                ; pointer - integer
MS_PTRS     LDY  <EL                   ; pointer - pointer: the difference /
            LDY  N_TYPE,Y              ; the size of what they point to
            LDY  TY_BASE,Y
            LDD  TY_SIZE,Y
            PSHS D
            LDX  #TYP_INT
            STX  <ETY
            CLR  <EUNS
            JSR  BOTHNUM
            BCC  MS_FOLD
            JSR  BINNODE
            BRA  MS_DIV
MS_FOLD     JSR  FOLD
            LDX  <EL
            STD  N_V,X
            LDD  <ETY
            STD  N_TYPE,X
MS_DIV      PULS D
            CMPD #1
            BLS  MS_RET
            STX  <EL
            LDY  #TYP_INT
            JSR  MKNUM
            STX  <ER
            LDA  #O_DIV
            STA  <EOP
            CLR  <EUNS
            JMP  MB_BUILD
MS_RET      RTS
; ER (an integer added to a pointer, EL) times the size of what EL points to.
SCALEER     LDY  <EL
            LDY  N_TYPE,Y
            LDY  TY_BASE,Y
            LDD  TY_SIZE,Y
            LDX  <ER
            JSR  SCALE
            STX  <ER
            RTS
; X = an integer node, D = a size -> X = it times the size.
SCALE       CMPD #1
            BEQ  SC_RET
            PSHS D
            LDA  N_OP,X
            CMPA #O_NUM
            BNE  SC_NODE
            LDD  N_V,X
            MULD ,S++
            STW  N_V,X
            LDD  #TYP_INT
            STD  N_TYPE,X
            RTS
SC_NODE     PSHS X
            LDD  2,S
            LDY  #TYP_INT
            JSR  MKNUM
            TFR  X,Y
            PULS X
            LEAS 2,S
            PSHS X,Y
            LDA  #O_MUL
            JSR  NEWNODE
            PULS D,Y
            STD  N_L,X
            STY  N_R,X
            LDD  #TYP_INT
            STD  N_TYPE,X
SC_RET      RTS
; EOP on EL's and ER's numbers (EUNS: unsigned) -> D.
FOLD        LDX  <EL
            LDD  N_V,X
            STD  <FA
            LDX  <ER
            LDD  N_V,X
            STD  <FB
            LDB  <EOP
            SUBB #O_LAND
            LSLB
            LDX  #FOLDTAB
            LDD  B,X
            BEQ  FD_INTERNAL
            TFR  D,X
            LDD  <FA
            JMP  ,X
FD_INTERNAL LDX  #M_INTERNAL
            JMP  ERROR
FOLDTAB     FDB  FO_LAND,FO_LOR,0,FO_ADD,FO_SUB,FO_MUL,FO_DIV,FO_MOD,FO_SHL
            FDB  FO_SHR,FO_AND,FO_OR,FO_XOR,FO_EQ,FO_NE,FO_LT,FO_GT,FO_LE,FO_GE
FO_LAND     CMPD #0
            BEQ  FO_0
            LDD  <FB
            BEQ  FO_0
            BRA  FO_1
FO_LOR      CMPD #0
            BNE  FO_1
            LDD  <FB
            BNE  FO_1
FO_0        CLRD
            RTS
FO_1        LDD  #1
            RTS
FO_ADD      ADDD <FB
            RTS
FO_SUB      SUBD <FB
            RTS
FO_MUL      MULD <FB
            TFR  W,D
            RTS
FO_AND      ANDD <FB
            RTS
FO_OR       ORD  <FB
            RTS
FO_XOR      EORD <FB
            RTS
FO_DIV      BSR  FO_DIVIDE
            LDD  MA+2
            RTS
FO_MOD      BSR  FO_DIVIDE
            LDD  MB+2
            RTS
FO_DIVIDE   LDD  <FB                   ; MA / MB in 32 bits, from 16 (signed or
            BEQ  FO_DIV0               ; not)
            STD  MB+2
            LDD  <FA
            STD  MA+2
            CLRD
            TST  <EUNS
            BNE  FO_DPOS
            TST  MA+2
            BPL  FO_DA
            LDD  #$FFFF
FO_DA       STD  MA
            CLRD
            TST  MB+2
            BPL  FO_DB
            LDD  #$FFFF
FO_DB       STD  MB
            JMP  DIV32
FO_DPOS     STD  MA
            STD  MB
            JMP  DIV32
FO_DIV0     LDX  #M_DIV0
            JMP  ERROR
FO_SHL      LDX  <FB
FO_SL       BEQ  FO_SRET
            LSLD
            LEAX -1,X
            BRA  FO_SL
FO_SHR      LDX  <FB
FO_SR       BEQ  FO_SRET
            TST  <EUNS
            BNE  FO_SRU
            ASRD
            BRA  FO_SRN
FO_SRU      LSRD
FO_SRN      LEAX -1,X
            BRA  FO_SR
FO_SRET     RTS
FO_EQ       CMPD <FB
            BEQ  FO_1
            LBRA FO_0
FO_NE       CMPD <FB
            LBNE FO_1
            LBRA FO_0
FO_LT       TST  <EUNS
            BNE  FO_LTU
            CMPD <FB
            LBLT FO_1
            LBRA FO_0
FO_LTU      CMPD <FB
            LBLO FO_1
            LBRA FO_0
FO_GT       TST  <EUNS
            BNE  FO_GTU
            CMPD <FB
            LBGT FO_1
            LBRA FO_0
FO_GTU      CMPD <FB
            LBHI FO_1
            LBRA FO_0
FO_LE       TST  <EUNS
            BNE  FO_LEU
            CMPD <FB
            LBLE FO_1
            LBRA FO_0
FO_LEU      CMPD <FB
            LBLS FO_1
            LBRA FO_0
FO_GE       TST  <EUNS
            BNE  FO_GEU
            CMPD <FB
            LBGE FO_1
            LBRA FO_0
FO_GEU      CMPD <FB
            LBHS FO_1
            LBRA FO_0
; X = an operand, A = O_NEG, O_COM or O_NOT -> X.
MKUNARY     STA  <EOP
            JSR  DECAY
            STX  <EL
            LDA  <EOP
            CMPA #O_NOT
            BEQ  MU_NOT
            LDX  N_TYPE,X              ; - ~: an integer, promoted
            JSR  TISINT
            LBCS BI_BAD
            JSR  PROMOTE
            STX  <ETY
            LDX  <EL
            LDA  N_OP,X
            CMPA #O_NUM
            BNE  MU_NODE
            LDD  N_V,X
            LDA  <EOP
            CMPA #O_NEG
            BEQ  MU_NEG
            LDD  N_V,X
            COMD
            BRA  MU_FOLD
MU_NEG      LDD  N_V,X
            NEGD
MU_FOLD     STD  N_V,X
            LDD  <ETY
            STD  N_TYPE,X
            RTS
MU_NOT      LDX  N_TYPE,X              ; !: a scalar, -> int
            JSR  TISSCALAR
            LBCS BS_BAD
            LDX  #TYP_INT
            STX  <ETY
            LDX  <EL
            LDA  N_OP,X
            CMPA #O_NUM
            BNE  MU_NODE
            LDD  N_V,X
            BEQ  MU_TRUE
            CLRD
            BRA  MU_FOLD
MU_TRUE     LDD  #1
            BRA  MU_FOLD
MU_NODE     LDY  <ETY
            LDA  <EOP
            JMP  MKUNODE
; &X -> X.
MKADDR      LDA  N_OP,X
            CMPA #O_DEREF
            BEQ  MD_UNDER
            CMPA #O_SYM
            BEQ  MD_ADDR
            CMPA #O_FRAME
            BEQ  MD_ADDR
            CMPA #O_STR
            BEQ  MD_ADDR
            LDX  #M_NOADDR
            JMP  ERROR
MD_UNDER    LDX  N_L,X                 ; &*p: p
            RTS
MD_ADDR     PSHS X
            LDX  N_TYPE,X
            JSR  PTRTO
            TFR  X,Y
            PULS X
            LDA  #O_ADDR
            JMP  MKUNODE
; *X -> X.
MKDEREF     JSR  DECAY
            LDY  N_TYPE,X
            LDA  TY_KIND,Y
            CMPA #TK_PTR
            BNE  MR_BAD
            LDY  TY_BASE,Y
            LDA  TY_KIND,Y
            CMPA #TK_VOID
            BEQ  MR_VOID
            LDA  N_OP,X                ; *&x: x
            CMPA #O_ADDR
            BEQ  MR_UNDER
            LDA  #O_DEREF
            JSR  MKUNODE
            LDY  N_TYPE,X
            LDA  TY_KIND,Y
            CMPA #TK_FUNC
            BEQ  MR_RET
            LDA  #NF_LVAL
            STA  N_FL,X
MR_RET      RTS
MR_UNDER    LDX  N_L,X
            RTS
MR_BAD      LDX  #M_NOTPTR
            JMP  ERROR
MR_VOID     LDX  #M_DEREFVOID
            JMP  ERROR
; X = an lvalue, A = O_PREINC .. O_POSTDEC -> X.
MKINCDEC    PSHS A
            BSR  CHECKLVAL
            LDY  N_TYPE,X
            EXG  X,Y
            JSR  TISSCALAR
            EXG  X,Y
            LBCS BS_BAD
            LDD  #1                    ; the step: 1, or what a pointer points
            LDA  TY_KIND,Y             ; to's size
            CMPA #TK_PTR
            BNE  MI_STEP
            PSHS Y
            LDY  TY_BASE,Y
            LDD  TY_SIZE,Y
            PULS Y
            BRA  MI_NODE
MI_STEP     LDD  #1
MI_NODE     PSHS D
            LDA  2,S
            JSR  MKUNODE
            PULS D
            STD  N_V,X
            LEAS 1,S
            RTS
; An error unless X is an lvalue that may be assigned to. Keeps X and Y.
CHECKLVAL   LDA  N_FL,X
            BITA #NF_LVAL
            BEQ  CL_BAD
            PSHS Y
            LDY  N_TYPE,X
            LDA  TY_KIND,Y
            PULS Y
            CMPA #TK_ARRAY
            BEQ  CL_BAD
            CMPA #TK_FUNC
            BEQ  CL_BAD
            RTS
CL_BAD      LDX  #M_NOTLVAL
            JMP  ERROR
; X = Y -> X.
MKASSIGN    BSR  CHECKLVAL
            PSHS X
            TFR  Y,X
            LDY  ,S
            LDY  N_TYPE,Y
            JSR  MKCONVERT
            TFR  X,Y
            PULS X
            PSHS X,Y
            LDA  #O_ASSIGN
            JSR  NEWNODE
            PULS D,Y
            STD  N_L,X
            STY  N_R,X
            TFR  D,Y
            LDD  N_TYPE,Y
            STD  N_TYPE,X
            RTS
; X op= Y (A = the binary operation) -> X.
MKASGOP     STA  <EOP
            BSR  CHECKLVAL
            STX  <EL
            TFR  Y,X
            JSR  DECAY
            STX  <ER
            LDX  <EL
            LDX  N_TYPE,X
            JSR  TISPTR
            BCS  MG_INT
            LDA  <EOP                  ; pointer += integer, -= integer
            CMPA #O_ADD
            BEQ  MG_PTR
            CMPA #O_SUB
            BNE  MG_INT
MG_PTR      LDX  <ER
            LDX  N_TYPE,X
            JSR  TISINT
            LBCS BI_BAD
            JSR  SCALEER
            CLR  <EUNS
            BRA  MG_NODE
MG_INT      JSR  BOTHINT
            JSR  PROMBOTH
            LDA  <EOP
            CMPA #O_SHL
            BEQ  MG_TYPE
            CMPA #O_SHR
            BEQ  MG_TYPE
            JSR  USUALTYPE
MG_TYPE     JSR  SETUNS
MG_NODE     LDX  <EL
            LDD  N_TYPE,X
            STD  <ETY
            JSR  BINNODE
            LDA  #O_ASGOP
            STA  N_OP,X
            LDB  <EOP
            CLRA
            STD  N_V,X
            RTS
; X = what's called, Y = the arguments (O_ARGs), B = how many -> X.
MKCALL      PSHS B,Y
            JSR  DECAY                 ; (a function is a pointer to it now)
            LDY  N_TYPE,X
            LDA  TY_KIND,Y
            CMPA #TK_PTR
            BNE  ML_BAD
            LDY  TY_BASE,Y
            LDA  TY_KIND,Y
            CMPA #TK_FUNC
            BNE  ML_BAD
            PSHS X,Y                   ; ,S callee, 2,S its type, 4,S count,
            LDY  TY_PAR,Y              ; 5,S the arguments
            LDA  PL_FL,Y
            BITA #PLF_PROTO
            BEQ  ML_ARGS               ; (no prototype: as they are)
            LDB  PL_N,Y                ; how many: as many as the parameters,
            CMPB 4,S                   ; or more with "..."
            BHI  ML_COUNT
            BEQ  ML_CONV
            BITA #PLF_VAR
            BEQ  ML_COUNT
ML_CONV     LEAY PL_PAR,Y              ; each converted to its parameter's type
            LDX  5,S
ML_CLOOP    TSTB
            BEQ  ML_ARGS
            PSHS B,X,Y
            LDY  ,Y
            LDX  N_L,X
            JSR  MKCONVERT
            TFR  X,W
            PULS B,X,Y
            STW  N_L,X
            LDX  N_R,X
            LEAY 4,Y
            DECB
            BRA  ML_CLOOP
ML_ARGS     LDX  5,S                   ; the rest as their values are
ML_DLOOP    BEQ  ML_NODE
            PSHS X
            LDX  N_L,X
            JSR  DECAY
            TFR  X,D
            PULS X
            STD  N_L,X
            LDX  N_R,X
            BRA  ML_DLOOP
ML_NODE     LDA  #O_CALL
            JSR  NEWNODE
            PULS D,Y
            STD  N_L,X
            LDD  TY_BASE,Y
            STD  N_TYPE,X
            PULS B,Y
            STY  N_R,X
            CLRA
            STD  N_X,X
            RTS
ML_BAD      LDX  #M_NOTFUNC
            JMP  ERROR
ML_COUNT    LDX  #M_ARGCOUNT
            JMP  ERROR
; X = a condition, Y = the value if it's true, D = if it's false -> X.
MKCOND      PSHS D,Y
            JSR  DECAY
            STX  <EOPND
            LDX  N_TYPE,X
            JSR  TISSCALAR
            LBCS BS_BAD
            LDX  2,S
            JSR  DECAY
            STX  <EL
            PULS X
            JSR  DECAY
            STX  <ER
            LEAS 2,S
            LDX  <EL                   ; the type: integers -> the usual one;
            LDY  N_TYPE,X              ; a pointer (and 0) -> the pointer's;
            LDA  TY_KIND,Y             ; void -> void
            CMPA #TK_PTR
            BEQ  MO_TYPE
            CMPA #TK_VOID
            BEQ  MO_TYPE
            LDX  <ER
            LDY  N_TYPE,X
            LDA  TY_KIND,Y
            CMPA #TK_PTR
            BEQ  MO_TYPE
            JSR  BOTHINT
            JSR  PROMBOTH
            JSR  USUALTYPE
            TFR  X,Y
MO_TYPE     STY  <ETY
            LDX  <EOPND                ; a constant condition: one or the other
            LDA  N_OP,X
            CMPA #O_NUM
            BNE  MO_NODE
            LDD  N_V,X
            BEQ  MO_FALSE
            LDX  <EL
            RTS
MO_FALSE    LDX  <ER
            RTS
MO_NODE     LDA  #O_COND
            JSR  NEWNODE
            LDD  <EOPND
            STD  N_L,X
            LDD  <EL
            STD  N_R,X
            LDD  <ER
            STD  N_X,X
            LDD  <ETY
            STD  N_TYPE,X
            RTS
; X , Y -> X.
MKCOMMA     PSHS X
            TFR  Y,X
            JSR  DECAY
            TFR  X,Y
            PULS X
            PSHS X,Y
            LDA  #O_COMMA
            JSR  NEWNODE
            PULS D,Y
            STD  N_L,X
            STY  N_R,X
            LDD  N_TYPE,Y
            STD  N_TYPE,X
            RTS
;------------------------------------------------------------------------------
; The parser.
;------------------------------------------------------------------------------
; expression: assignments, with commas between.
EXPR        JSR  ASSIGNEXPR
EX_LOOP     LDA  <TOK
            CMPA #44
            BNE  EX_RET
            PSHS X
            JSR  NEXT
            JSR  ASSIGNEXPR
            TFR  X,Y
            PULS X
            JSR  MKCOMMA
            BRA  EX_LOOP
EX_RET      RTS
ASSIGNEXPR  JSR  CONDEXPR
            LDA  <TOK
            CMPA #'='
            BEQ  AS_SIMPLE
            CMPA #T_MULEQ
            BLO  AS_RET
            CMPA #T_OREQ
            BHI  AS_RET
            SUBA #T_MULEQ              ; op=
            LDY  #ASGOPS
            LDA  A,Y
            PSHS A,X
            JSR  NEXT
            JSR  ASSIGNEXPR
            TFR  X,Y
            PULS A,X
            JMP  MKASGOP
AS_SIMPLE   PSHS X
            JSR  NEXT
            JSR  ASSIGNEXPR
            TFR  X,Y
            PULS X
            JMP  MKASSIGN
AS_RET      RTS
ASGOPS      FCB  O_MUL,O_DIV,O_MOD,O_ADD,O_SUB,O_SHL,O_SHR,O_AND,O_XOR,O_OR
; c ? a : b
CONDEXPR    LDB  #1
            JSR  BINEXPR
            LDA  <TOK
            CMPA #'?'
            BNE  CE_RET
            PSHS X
            JSR  NEXT
            JSR  EXPR
            PSHS X
            LDA  #':'
            JSR  EXPECT
            JSR  CONDEXPR
            TFR  X,D
            PULS Y
            PULS X
            JMP  MKCOND
CE_RET      RTS
; A constant expression -> D (in the nodes as they are: no RESETNODES).
CONSTEXPR   JSR  CONDEXPR
            LDA  N_OP,X
            CMPA #O_NUM
            BNE  CX_BAD
            LDD  N_V,X
            RTS
CX_BAD      LDX  #M_NOTCONST2
            JMP  ERROR
; The binary operators of precedence B and above (precedence climbing).
BINEXPR     PSHS B
            JSR  UNARY
BX_LOOP     LDA  <TOK
            LDY  #BINOPS
BX_FIND     LDB  ,Y
            BEQ  BX_RET
            CMPA ,Y
            BEQ  BX_GOT
            LEAY 3,Y
            BRA  BX_FIND
BX_GOT      LDD  1,Y                   ; A = the operation, B = its precedence
            CMPB ,S
            BLO  BX_RET
            PSHS A,B,X
            JSR  NEXT
            LDB  1,S
            INCB
            JSR  BINEXPR
            TFR  X,Y
            PULS A,B,X
            JSR  MKBINARY
            BRA  BX_LOOP
BX_RET      PULS B,PC
BINOPS      FCB  T_OROR,O_LOR,1
            FCB  T_ANDAND,O_LAND,2
            FCB  '|',O_OR,3
            FCB  '^',O_XOR,4
            FCB  '&',O_AND,5
            FCB  T_EQ,O_EQ,6
            FCB  T_NE,O_NE,6
            FCB  '<',O_LT,7
            FCB  '>',O_GT,7
            FCB  T_LE,O_LE,7
            FCB  T_GE,O_GE,7
            FCB  T_SHL,O_SHL,8
            FCB  T_SHR,O_SHR,8
            FCB  '+',O_ADD,9
            FCB  '-',O_SUB,9
            FCB  '*',O_MUL,10
            FCB  '/',O_DIV,10
            FCB  '%',O_MOD,10
            FCB  0
; Unary operators, casts, sizeof.
UNARY       LDA  <TOK
            LDY  #UNOPS
UN_FIND     TST  ,Y
            BEQ  UN_OTHER
            CMPA ,Y
            BEQ  UN_GOT
            LEAY 3,Y
            BRA  UN_FIND
UN_GOT      LDD  1,Y                   ; (A = the routine's number, B = the op)
            PSHS D
            JSR  NEXT
            BSR  UNARY
            PULS D
            CMPA #1
            BEQ  UN_INC
            CMPA #2
            BEQ  UN_ADDR
            CMPA #3
            BEQ  UN_DEREF
            CMPA #4
            BEQ  UN_PLUS
            TFR  B,A
            JMP  MKUNARY
UN_INC      TFR  B,A
            JMP  MKINCDEC
UN_ADDR     JMP  MKADDR
UN_DEREF    JMP  MKDEREF
UN_PLUS     JSR  DECAY
            PSHS X
            LDX  N_TYPE,X
            JSR  TISINT
            PULS X
            LBCS BI_BAD
            RTS
UN_OTHER    CMPA #K_SIZEOF
            BEQ  UN_SIZEOF
            CMPA #'('
            LBNE POSTFIX
            JSR  PEEK                  ; ( type ) : a cast
            JSR  ISTYPEAHEAD
            LBCS POSTFIX
            JSR  NEXT
            JSR  TYPENAME
            PSHS X
            LDA  #')'
            JSR  EXPECT
            JSR  UNARY
            PULS Y
            JMP  MKCAST
UN_SIZEOF   JSR  NEXT
            LDA  <TOK
            CMPA #'('
            BNE  SZ_EXPR
            JSR  PEEK
            JSR  ISTYPEAHEAD
            BCS  SZ_EXPR
            JSR  NEXT                  ; sizeof ( type )
            JSR  TYPENAME
            PSHS X
            LDA  #')'
            JSR  EXPECT
            PULS X
            BRA  SZ_SIZE
SZ_EXPR     JSR  UNARY                 ; sizeof expression (not made into code)
            LDX  N_TYPE,X
SZ_SIZE     LDD  TY_SIZE,X
            BEQ  SZ_NONE
            LDY  #TYP_UINT
            JMP  MKNUM
SZ_NONE     LDX  #M_SIZEOF
            JMP  ERROR
UNOPS       FCB  T_INC,1,O_PREINC
            FCB  T_DEC,1,O_PREDEC
            FCB  '&',2,0
            FCB  '*',3,0
            FCB  '+',4,0
            FCB  '-',0,O_NEG
            FCB  '~',0,O_COM
            FCB  '!',0,O_NOT
            FCB  0
; Carry clear if the token looked ahead at (AHEAD) begins a type's name.
ISTYPEAHEAD LDA  <AHEAD
            CMPA #T_ID
            BEQ  TA_ID
            LDX  #TYPEWORDS
TA_FIND     TST  ,X
            BEQ  TA_NO
            CMPA ,X+
            BNE  TA_FIND
TA_YES      ANDCC #$FE
            RTS
TA_ID       LDX  <AHEADV
            LDX  NM_SYM,X
            BEQ  TA_NO
            LDA  SY_KIND,X
            CMPA #SK_TYPEDEF
            BEQ  TA_YES
TA_NO       ORCC #1
            RTS
TYPEWORDS   FCB  K_VOID,K_CHAR,K_SHORT,K_INT,K_LONG,K_SIGNED,K_UNSIGNED
            FCB  K_CONST,K_VOLATILE,K_STRUCT,K_UNION,K_ENUM,K_FLOAT,K_DOUBLE,0
; A type's name (in a cast or sizeof) -> X = the type. (The declaration it
; may be in is kept as it was.)
TYPENAME    LDX  <DSTYPE
            LDY  <DNAME
            LDA  <DSSC
            LDB  <ABSTRACT
            PSHS D,X,Y
            LDX  <DTYPE
            PSHS X
            JSR  DECLSPEC
            BCS  TN_BAD
            LDA  <DSSC
            BNE  TN_BAD
            LDA  #1
            STA  <ABSTRACT
            JSR  DECLARATOR
            LDX  <DTYPE
            PULS Y
            STY  <DTYPE
            PULS D
            STA  <DSSC
            STB  <ABSTRACT
            PULS Y
            STY  <DSTYPE
            PULS Y
            STY  <DNAME
            RTS
TN_BAD      LDX  #M_TYPENAME
            JMP  ERROR
; Postfix operators: [] () ++ --.
POSTFIX     JSR  PRIMARY
PX_LOOP     LDA  <TOK
            CMPA #'['
            BEQ  PX_INDEX
            CMPA #'('
            BEQ  PX_CALL
            CMPA #T_INC
            BEQ  PX_INC
            CMPA #T_DEC
            BEQ  PX_DEC
            CMPA #'.'
            BEQ  PX_LATER
            CMPA #T_ARROW
            BEQ  PX_LATER
            RTS
PX_INDEX    PSHS X                     ; a[i] is *(a + i)
            JSR  NEXT
            JSR  EXPR
            PSHS X
            LDA  #']'
            JSR  EXPECT
            PULS Y
            PULS X
            LDA  #O_ADD
            JSR  MKBINARY
            JSR  MKDEREF
            BRA  PX_LOOP
PX_CALL     PSHS X
            JSR  NEXT
            JSR  ARGS
            PULS X
            JSR  MKCALL
            BRA  PX_LOOP
PX_INC      LDA  #O_POSTINC
            BRA  PX_INCDEC
PX_DEC      LDA  #O_POSTDEC
PX_INCDEC   PSHS A,X
            JSR  NEXT
            PULS A,X
            JSR  MKINCDEC
            BRA  PX_LOOP
PX_LATER    LDX  #M_NOTYET
            JMP  ERROR
; After "(": the arguments, to ")" -> Y = the O_ARG list, B = how many.
ARGS        CLRD
            PSHS D                     ; the first
            PSHS D                     ; the last
            CLR  ,-S                   ; how many
            LDA  <TOK
            CMPA #')'
            BEQ  AR_END
AR_LOOP     JSR  ASSIGNEXPR
            PSHS X
            LDA  #O_ARG
            JSR  NEWNODE
            PULS D
            STD  N_L,X
            LDY  1,S
            BEQ  AR_FIRST
            STX  N_R,Y
            BRA  AR_LINK
AR_FIRST    STX  3,S
AR_LINK     STX  1,S
            INC  ,S
            LDA  <TOK
            CMPA #44
            BNE  AR_END
            JSR  NEXT
            BRA  AR_LOOP
AR_END      LDA  #')'
            JSR  EXPECT
            PULS B
            PULS X
            PULS Y,PC
; Names, numbers, strings, ( expression ).
PRIMARY     LDA  <TOK
            CMPA #T_ID
            BEQ  PM_ID
            CMPA #T_NUM
            BEQ  PM_NUM
            CMPA #T_STR
            LBEQ PM_STR
            CMPA #'('
            BEQ  PM_PAREN
            LDX  #M_EXPRESSION
            JMP  ERROR
PM_PAREN    JSR  NEXT
            JSR  EXPR
            PSHS X
            LDA  #')'
            JSR  EXPECT
            PULS X,PC
PM_ID       LDY  <TOKV                 ; a name: what it means now
            LDX  NM_SYM,Y
            BEQ  PM_UNDECL
            LDA  SY_KIND,X
            CMPA #SK_TYPEDEF
            BEQ  PM_TYPE
            LDA  SY_FL,X
            ORA  #SF_USED
            STA  SY_FL,X
            PSHS X
            LDA  #O_SYM
            JSR  NEWNODE
            PULS Y
            STY  N_V,X
            LDD  SY_TYPE,Y
            STD  N_TYPE,X
            LDA  #NF_LVAL
            STA  N_FL,X
            PSHS X
            JSR  NEXT
            PULS X,PC
PM_UNDECL   LDX  #M_UNDECL
            JMP  ERRORN
PM_TYPE     LDX  #M_TYPEHERE
            JMP  ERRORN
PM_NUM      LDA  <TOKFL                ; a number: int, or unsigned int if it's
            BITA #TF_LONG              ; u or doesn't fit in an int
            BNE  PM_LONG
            LDY  #TYP_INT
            BITA #TF_UNS
            BNE  PM_UNS
            LDD  <TOKV                 ; (a char's -1 is $FFFFFFFF)
            CMPD #$FFFF
            BEQ  PM_NEG
            CMPD #0
            BNE  PM_LONG
            LDD  <TOKV+2
            BPL  PM_MAKE
            LDY  #TYP_UINT
            BRA  PM_MAKE
PM_NEG      LDD  <TOKV+2
            BPL  PM_LONG
            BRA  PM_MAKE
PM_UNS      LDY  #TYP_UINT
            LDD  <TOKV
            BNE  PM_LONG
PM_MAKE     LDD  <TOKV+2
            JSR  MKNUM
            PSHS X
            JSR  NEXT
            PULS X,PC
PM_LONG     LDX  #M_LONGNUM
            JMP  ERROR
PM_STR      JSR  EMITSTRING            ; a string: its bytes in rodata, now
            LDY  #TYP_CHAR
            PSHS D
            LDD  <TOKSL
            ADDD #1
            TFR  Y,X
            JSR  ARRAYOF
            TFR  X,Y
            PULS D
            JSR  MKNUM
            LDA  #O_STR
            STA  N_OP,X
            PSHS X
            JSR  NEXT
            PULS X,PC
; The current token's string, and its NUL, into rodata -> D = its label.
EMITSTRING  LDA  <CURSECT
            PSHS A
            LDA  #SEC_RODATA
            JSR  SECT
            JSR  NEWLABEL
            PSHS D
            JSR  LABELHERE
            LDX  <TOKSB
            LDD  <TOKSL
            ADDD #1
            JSR  EMITBYTES
            LDA  2,S                   ; the section it was in
            JSR  SECT
            PULS D
            LEAS 1,S
            RTS
; X = a tree: is it a constant (for an initializer)? Carry clear if so: CVSYM
; (a symbol) or CVLBL (a label) plus CVVAL, or just CVVAL.
EVALCONST   CLRD
            STD  <CVSYM
            STD  <CVLBL
            STD  <CVVAL
EC_NODE     LDA  N_OP,X
            CMPA #O_NUM
            BEQ  EC_NUM
            CMPA #O_STR
            BEQ  EC_STR
            CMPA #O_ADDR
            BEQ  EC_ADDR
            CMPA #O_ADD
            BEQ  EC_ADD
            CMPA #O_SUB
            BEQ  EC_SUB
            CMPA #O_CAST
            BEQ  EC_CAST
EC_NO       ORCC #1
            RTS
EC_NUM      LDD  <CVVAL
            ADDD N_V,X
            STD  <CVVAL
            ANDCC #$FE
            RTS
EC_STR      LDD  <CVSYM
            BNE  EC_NO
            LDD  <CVLBL
            BNE  EC_NO
            LDD  N_V,X
            STD  <CVLBL
            ANDCC #$FE
            RTS
EC_ADDR     LDX  N_L,X                 ; &name (not a local's)
            LDA  N_OP,X
            CMPA #O_STR
            BEQ  EC_STR
            CMPA #O_SYM
            BNE  EC_NO
            LDY  N_V,X
            LDA  SY_KIND,Y
            CMPA #SK_GLOBAL
            BEQ  EC_SYM
            CMPA #SK_STATLOC
            BNE  EC_NO
EC_SYM      LDD  <CVSYM
            BNE  EC_NO
            LDD  <CVLBL
            BNE  EC_NO
            STY  <CVSYM
            ANDCC #$FE
            RTS
EC_ADD      PSHS X
            LDX  N_L,X
            BSR  EC_NODE
            PULS X
            BCS  EC_NO
            LDX  N_R,X
            BRA  EC_NODE
EC_SUB      PSHS X
            LDX  N_L,X
            BSR  EC_NODE
            PULS X
            BCS  EC_NO
            LDX  N_R,X
            LDA  N_OP,X
            CMPA #O_NUM
            BNE  EC_NO
            LDD  <CVVAL
            SUBD N_V,X
            STD  <CVVAL
            ANDCC #$FE
            RTS
EC_CAST     LDX  N_L,X
            LBRA EC_NODE
;------------------------------------------------------------------------------
M_COMPLEX   FCN  "expression too complex"
M_BADCONV   FCN  "incompatible types"
M_BADCAST   FCN  "invalid cast"
M_NOTINT    FCN  "an integer was expected"
M_NOTSCALAR FCN  "a number or a pointer was expected"
M_INTERNAL  FCN  "internal error"
M_DIV0      FCN  "division by zero"
M_NOADDR    FCN  "can't take the address of that"
M_NOTPTR    FCN  "a pointer was expected"
M_DEREFVOID FCN  "a void pointer can't be followed"
M_NOTLVAL   FCN  "that can't be assigned to"
M_NOTFUNC   FCN  "that isn't a function"
M_ARGCOUNT  FCN  "wrong number of arguments"
M_NOTCONST2 FCN  "a constant was expected"
M_SIZEOF    FCN  "sizeof of something with no size"
M_TYPENAME  FCN  "a type was expected"
M_EXPRESSION FCN "an expression was expected"
M_UNDECL    FCN  "undeclared:"
M_TYPEHERE  FCN  "a type's name where a value was expected:"
M_LONGNUM   FCN  "constant too large (long isn't supported yet)"
;------------------------------------------------------------------------------
; End of cc1_expr.asm
;------------------------------------------------------------------------------
