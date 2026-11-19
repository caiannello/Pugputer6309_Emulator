;------------------------------------------------------------------------------
; cc1_gen.asm -- CC1: trees into code, and writing the output.
;
; A value is made in D (a char's widened to an int, as it's loaded). An operand
; that's simple -- a number, a variable, *p for a pointer variable, an element
; of an array at a constant index -- is used straight from where it is (OPND:
; OPM, OPV, OPS, OPL say how). Otherwise the right side is made first and
; pushed, the left made, and the operation done with ,S++.
;------------------------------------------------------------------------------
HB_DIV      equ  1                 ; the library's helpers (HELPERS, IMPORTed)
HB_UDIV     equ  2
HB_MOD      equ  4
HB_UMOD     equ  8
HB_SHL      equ  16
HB_SHR      equ  32
HB_USHR     equ  64
HELPNAMES   FCN  "__div"
            FCN  "__udiv"
            FCN  "__mod"
            FCN  "__umod"
            FCN  "__shl"
            FCN  "__shr"
            FCN  "__ushr"
            FCB  0
;------------------------------------------------------------------------------
; Writing. These keep every register.
;------------------------------------------------------------------------------
OUTC        PSHS U
            LDU  #OUTSTRM
            JSR  SPUTC
            PULS U,PC
OUTS        PSHS X,U
            LDU  #OUTSTRM
            JSR  SPUTS
            PULS X,U,PC
OUTNL       PSHS U
            LDU  #OUTSTRM
            JSR  SPUTNL
            PULS U,PC
; D, signed, in decimal.
OUTDEC      PSHS D,X,Y
            TSTA
            BPL  OD_POS
            LDA  #'-'
            BSR  OUTC
            LDD  ,S
            NEGD
OD_POS      LDX  #NUMBUF
            JSR  DECSTR
            LDX  #NUMBUF
            BSR  OUTS
            PULS D,X,Y,PC
; D, a label's number: Ln.
OUTLBL      PSHS D,X,Y
            LDA  #'L'
            BSR  OUTC
            LDD  ,S
            LDX  #NUMBUF
            JSR  DECSTR
            LDX  #NUMBUF
            BSR  OUTS
            PULS D,X,Y,PC
; X = a symbol: its name in the output (_name, or a static local's Ln).
OUTSYMNAME  PSHS D,X
            LDA  SY_KIND,X
            CMPA #SK_STATLOC
            BEQ  ON_LBL
            LDA  #'_'
            BSR  OUTC
            LDX  SY_NAME,X
            LEAX NM_TEXT,X
            BSR  OUTS
            PULS D,X,PC
ON_LBL      LDD  SY_VAL,X
            BSR  OUTLBL
            PULS D,X,PC
; X = a mnemonic: " MNEMONIC " (the operand comes next).
EMITI       PSHS A
            LDA  #' '
            BSR  OUTC
            BSR  OUTS
            BSR  OUTC
            PULS A,PC
; X = a whole instruction: " TEXT", a line.
EMITL       PSHS A
            LDA  #' '
            BSR  OUTC
            BSR  OUTS
            BSR  OUTNL
            PULS A,PC
; X = instructions, NUL-terminated each, an empty one after the last: lines.
EMITLINES   PSHS X
EL_LOOP     TST  ,X
            BEQ  EL_RET
            BSR  EMITL
EL_SKIP     TST  ,X+
            BNE  EL_SKIP
            BRA  EL_LOOP
EL_RET      PULS X,PC
; D = a label: "Ln" here, on its own line.
LABELHERE   BSR  OUTLBL
            LBRA OUTNL
; D = a label: " LBRA Ln".
JUMPTO      PSHS X
            LDX  #S_LBRA
            BSR  EMITI
            BSR  OUTLBL
            JSR  OUTNL
            PULS X,PC
; A = a section (SEC_*): the output goes on in it. (0: as it is.)
SECT        TSTA
            BEQ  SN_RET
            CMPA <CURSECT
            BEQ  SN_RET
            STA  <CURSECT
            PSHS D,X
            LDX  #S_SECTION
            BSR  EMITI
            LDX  #SECTNAMES
            DECA
            LDB  #7
            MUL
            ABX
            JSR  OUTS
            JSR  OUTNL
            PULS D,X
SN_RET      RTS
SECTNAMES   FCB  'c','o','d','e',0,0,0
            FCB  'r','o','d','a','t','a',0
            FCB  'd','a','t','a',0,0,0
            FCB  'b','s','s',0,0,0,0
;------------------------------------------------------------------------------
; Operands.
;------------------------------------------------------------------------------
; The operand OPM etc. describe -> the output.
EMITOP      PSHS D
            LDA  <OPM
            CMPA #OM_IMM
            BEQ  EO_IMM
            CMPA #OM_EXT
            BEQ  EO_VAL
            CMPA #OM_IND
            BEQ  EO_IND
            CMPA #OM_UOFF
            BEQ  EO_UOFF
            CMPA #OM_UIND
            BEQ  EO_UIND
            CMPA #OM_XOFF
            BEQ  EO_XOFF
            LDX  #S_POP                ; OM_POP
            JSR  OUTS
            PULS D,PC
EO_IMM      LDA  #'#'
            JSR  OUTC
EO_VAL      BSR  EO_VALUE
            PULS D,PC
EO_IND      LDA  #'['
            JSR  OUTC
            BSR  EO_VALUE
            LDA  #']'
            JSR  OUTC
            PULS D,PC
EO_UOFF     LDD  <OPV
            JSR  OUTDEC
            LDX  #S_COMMAU
            JSR  OUTS
            PULS D,PC
EO_UIND     LDA  #'['
            JSR  OUTC
            LDD  <OPV
            JSR  OUTDEC
            LDX  #S_COMMAU
            JSR  OUTS
            LDA  #']'
            JSR  OUTC
            PULS D,PC
EO_XOFF     LDD  <OPV
            BEQ  EO_X0
            JSR  OUTDEC
EO_X0       LDX  #S_COMMAX
            JSR  OUTS
            PULS D,PC
; A value: symbol+n, label+n, or n.
EO_VALUE    LDX  <OPS
            BEQ  EV_LBL
            JSR  OUTSYMNAME
            BRA  EV_OFF
EV_LBL      LDD  <OPL
            BEQ  EV_NUM
            JSR  OUTLBL
EV_OFF      LDD  <OPV
            BEQ  EV_RET
            BMI  EV_NUM
            LDA  #'+'
            JSR  OUTC
EV_NUM      LDD  <OPV
            JMP  OUTDEC
EV_RET      RTS
; X = a mnemonic: " MNEMONIC operand", a line.
OPI         JSR  EMITI
            JSR  EMITOP
            JMP  OUTNL
; X = a node: carry clear if it is an operand as it is, with no code (OPM etc.
; describe it: a number or an address as #v, or where the value is in
; memory). Keeps X and Y.
OPND        PSHS X,Y
            CLRD
            STD  <OPV
            STD  <OPS
            STD  <OPL
            LDA  N_OP,X
            CMPA #O_NUM
            BEQ  OP_NUM
            CMPA #O_STR
            BEQ  OP_STR
            CMPA #O_ADDR
            BEQ  OP_ADDR
            CMPA #O_SYM
            BEQ  OP_SYM
            CMPA #O_FRAME
            BEQ  OP_FRAME
            CMPA #O_DEREF
            BEQ  OP_DEREF
            CMPA #O_CAST
            BEQ  OP_CAST
OP_NO       ORCC #1
            PULS X,Y,PC
OP_YES      STA  <OPM
            ANDCC #$FE
            PULS X,Y,PC
OP_NUM      LDD  N_V,X
            STD  <OPV
OP_IMM      LDA  #OM_IMM
            BRA  OP_YES
OP_STR      LDD  N_V,X
            STD  <OPL
            BRA  OP_IMM
OP_ADDR     LDX  N_L,X                 ; &global, &"..."
            LDA  N_OP,X
            CMPA #O_STR
            BEQ  OP_STR
            CMPA #O_SYM
            BNE  OP_NO
            LDY  N_V,X
            LDA  SY_KIND,Y
            CMPA #SK_LOCAL
            BEQ  OP_NO
            STY  <OPS
            BRA  OP_IMM
OP_SYM      LDY  N_V,X                 ; a variable
            LDA  SY_KIND,Y
            CMPA #SK_LOCAL
            BEQ  OP_LOCAL
            STY  <OPS
            LDA  #OM_EXT
            BRA  OP_YES
OP_LOCAL    LDD  SY_VAL,Y
            STD  <OPV
            LDA  #OM_UOFF
            BRA  OP_YES
OP_FRAME    LDD  N_V,X
            STD  <OPV
            LDA  #OM_UOFF
            BRA  OP_YES
OP_CAST     LDY  N_TYPE,X              ; a cast that changes nothing (between
            LDD  TY_SIZE,Y             ; words)
            CMPD #2
            BNE  OP_NO
            LDX  N_L,X
            LDY  N_TYPE,X
            LDD  TY_SIZE,Y
            CMPD #2
            BNE  OP_NO
            LEAS 4,S
            LBRA OPND
OP_DEREF    LDX  N_L,X                 ; *(what?)
            LDA  N_OP,X
            CMPA #O_NUM
            BEQ  OD_NUM
            CMPA #O_SYM
            BEQ  OD_PTR
            CMPA #O_ADD
            BNE  OP_NO
            LDY  N_R,X                 ; *(&x + n)
            LDA  N_OP,Y
            CMPA #O_NUM
            LBNE OP_NO
            LDD  N_V,Y
            STD  <OPV
            LDX  N_L,X
            LDA  N_OP,X
            CMPA #O_ADDR
            LBNE OP_NO
            LDX  N_L,X
            LDA  N_OP,X
            CMPA #O_FRAME
            BEQ  OD_FRAME
            CMPA #O_STR
            BEQ  OD_STR
            CMPA #O_SYM
            LBNE OP_NO
            LDY  N_V,X
            LDA  SY_KIND,Y
            CMPA #SK_LOCAL
            BEQ  OD_LOCAL
            STY  <OPS
OD_EXT      LDA  #OM_EXT
            LBRA OP_YES
OD_STR      LDD  N_V,X
            STD  <OPL
            BRA  OD_EXT
OD_LOCAL    LDD  SY_VAL,Y
            ADDD <OPV
            STD  <OPV
            LDA  #OM_UOFF
            LBRA OP_YES
OD_FRAME    LDD  N_V,X
            ADDD <OPV
            STD  <OPV
            LDA  #OM_UOFF
            LBRA OP_YES
OD_NUM      LDD  N_V,X                 ; *(n): memory at n
            STD  <OPV
            BRA  OD_EXT
OD_PTR      LDY  N_V,X                 ; *p: [p]
            LDA  SY_KIND,Y
            CMPA #SK_LOCAL
            BEQ  OD_PLOCAL
            STY  <OPS
            LDA  #OM_IND
            LBRA OP_YES
OD_PLOCAL   LDD  SY_VAL,Y
            STD  <OPV
            LDA  #OM_UIND
            LBRA OP_YES
; Carry clear if X is an operand as it is that a word operation can take (a
; number, or a word in memory).
OPNDW       JSR  OPND
            BCS  OW_RET
            LDA  <OPM
            CMPA #OM_IMM
            BEQ  OW_YES
            PSHS Y
            LDY  N_TYPE,X
            LDD  TY_SIZE,Y
            PULS Y
            CMPD #2
            BEQ  OW_YES
            ORCC #1
            RTS
OW_YES      ANDCC #$FE
OW_RET      RTS
; X = a node whose value is an address: code that loads it into X (D isn't
; touched). Carry set (and nothing written) if it can't be done so.
XLOAD       JSR  OPNDW
            BCS  XL_ADDR
            LDA  <OPM                  ; a number, &global, or a word in memory:
            CMPA #OM_IMM               ; LDX it
            BEQ  XL_LDX
            LDY  N_TYPE,X
            LDA  TY_KIND,Y
            CMPA #TK_PTR
            BNE  XL_NO
XL_LDX      LDX  #S_LDX
            JSR  OPI
            ANDCC #$FE
            RTS
XL_ADDR     LDA  N_OP,X                ; &local: LEAX n,U
            CMPA #O_ADDR
            BNE  XL_NO
            LDY  N_L,X
            LDA  N_OP,Y
            CMPA #O_FRAME
            BEQ  XL_LEA
            CMPA #O_SYM
            BNE  XL_NO
            LDY  N_V,Y
            LDA  SY_KIND,Y
            CMPA #SK_LOCAL
            BNE  XL_NO
            LDD  SY_VAL,Y
            BRA  XL_LEAD
XL_LEA      LDD  N_V,Y
XL_LEAD     STD  <OPV
            LDA  #OM_UOFF
            STA  <OPM
            LDX  #S_LEAX
            JSR  OPI
            ANDCC #$FE
            RTS
XL_NO       ORCC #1
            RTS
; Carry clear if XLOAD could do X (nothing written).
XLOADOK     JSR  OPNDW
            BCS  XO_ADDR
            LDA  <OPM
            CMPA #OM_IMM
            BEQ  XO_YES
            LDY  N_TYPE,X
            LDA  TY_KIND,Y
            CMPA #TK_PTR
            BNE  XO_NO
XO_YES      ANDCC #$FE
            RTS
XO_ADDR     LDA  N_OP,X
            CMPA #O_ADDR
            BNE  XO_NO
            LDY  N_L,X
            LDA  N_OP,Y
            CMPA #O_FRAME
            BEQ  XO_YES
            CMPA #O_SYM
            BNE  XO_NO
            LDY  N_V,Y
            LDA  SY_KIND,Y
            CMPA #SK_LOCAL
            BEQ  XO_YES
XO_NO       ORCC #1
            RTS
; X = an lvalue -> OPM etc. = where it is (code may be written to work that
; out, which leaves the address in X).
GENADDR     JSR  OPND
            BCC  GA_RET
            LDA  N_OP,X
            CMPA #O_DEREF
            BNE  GA_BAD
            LDX  N_L,X                 ; *(address)
            LDA  N_OP,X
            CMPA #O_ADD
            BEQ  GA_ADD
            CMPA #O_SUB
            BEQ  GA_SUB
GA_ANY      PSHS X                     ; X = the address (as XLOAD or GEN make
            JSR  XLOAD                 ; it)
            PULS X
            BCC  GA_X0
            JSR  GEN
            LDX  #S_TFRDX
            JSR  EMITL
GA_X0       CLRD
GA_XOFF     STD  <OPV
            LDA  #OM_XOFF
            STA  <OPM
            CLRD
            STD  <OPS
            STD  <OPL
GA_RET      RTS
GA_BAD      LDX  #M_INTADDR
            JMP  ERROR
GA_ADD      LDY  N_R,X                 ; *(a + n): n,X
            LDA  N_OP,Y
            CMPA #O_NUM
            BNE  GA_ADDV
            PSHS X
            LDX  N_L,X
            JSR  XLOAD
            PULS X
            BCS  GA_ANY
            LDY  N_R,X                 ; (XLOAD changes Y)
            LDD  N_V,Y
            BRA  GA_XOFF
GA_ADDV     PSHS X                     ; *(a + i): i in D, a in X, LEAX D,X
            LDX  N_L,X
            JSR  XLOADOK
            PULS X
            BCS  GA_ANY
            PSHS X
            LDX  N_R,X
            JSR  GEN
            LDX  ,S
            LDX  N_L,X
            JSR  XLOAD
            PULS X
            LDX  #S_LEAXDX
            JSR  EMITL
            BRA  GA_X0
GA_SUB      LDY  N_R,X                 ; *(a - n): -n,X
            LDA  N_OP,Y
            CMPA #O_NUM
            BNE  GA_ANY
            PSHS X
            LDX  N_L,X
            JSR  XLOAD
            PULS X
            BCS  GA_ANY
            LDY  N_R,X
            CLRD
            SUBD N_V,Y
            BRA  GA_XOFF
; Load / store the operand (OPM etc.), of the type X: a char is widened.
LOADOP      JSR  TISCHAR
            BCS  LO_WORD
            PSHS X
            LDX  #S_LDB
            JSR  OPI
            PULS X
WIDEN       JSR  TISCHAR               ; (X = a char type: D from B)
            BCS  WI_RET
            PSHS X
            LDA  TY_KIND,X
            LDX  #S_SEX
            CMPA #TK_UCHAR
            BNE  WI_EMIT
            LDX  #S_CLRA
WI_EMIT     JSR  EMITL
            PULS X
WI_RET      RTS
LO_WORD     PSHS X
            LDX  #S_LDD
            JSR  OPI
            PULS X,PC
STOREOP     PSHS X
            JSR  TISCHAR
            LDX  #S_STB
            BCC  ST_EMIT
            LDX  #S_STD
ST_EMIT     JSR  OPI
            PULS X,PC
; The operand's 7 bytes onto the stack, and back (they're used and kept by
; the caller, under its return address).
SAVEOP      PULS Y
            LDA  <OPM
            LDX  <OPV
            PSHS A,X
            LDX  <OPS
            LDD  <OPL
            PSHS D,X
            JMP  ,Y
RESTOP      PULS Y
            PULS D,X
            STX  <OPS
            STD  <OPL
            PULS A,X
            STA  <OPM
            STX  <OPV
            JMP  ,Y
;------------------------------------------------------------------------------
; Expressions: X = a tree -> code leaving its value in D.
;------------------------------------------------------------------------------
GEN         LDB  N_OP,X
            DECB
            LSLB
            LDY  #GENTAB
            JMP  [B,Y]
GENTAB      FDB  G_NUM,G_SYM,G_STR,G_ADDR,G_DEREF,G_NEG,G_COM,G_BOOL,G_CAST
            FDB  G_INCDEC,G_INCDEC,G_INCDEC,G_INCDEC,G_CALL,GA_BAD,G_COND
            FDB  G_COMMA,G_ASSIGN,G_ASGOP,G_BOOL,G_BOOL,G_SYM
            FDB  G_BIN,G_BIN,G_BIN,G_DIV,G_DIV,G_SHIFT,G_SHIFT,G_BIN,G_BIN,G_BIN
            FDB  G_BOOL,G_BOOL,G_BOOL,G_BOOL,G_BOOL,G_BOOL
G_NUM       LDD  N_V,X
            BNE  G_IMM
            LDX  #S_CLRD
            JMP  EMITL
G_STR
G_IMM       JSR  OPND                  ; #n, #Ln, #_name
            LDX  #S_LDD
            JMP  OPI
G_SYM       JSR  OPND                  ; a variable
            LDX  N_TYPE,X
            JMP  LOADOP
G_ADDR      JSR  OPND                  ; &x
            BCC  G_IMM
            JSR  XLOAD
            BCS  G_ADDRX
G_TFRXD     LDX  #S_TFRXD
            JMP  EMITL
G_ADDRX     LDX  N_L,X                 ; (&*(...): the address GENADDR finds)
            JSR  GENADDR
            LDA  <OPM
            CMPA #OM_XOFF
            LBNE GA_BAD
            LDX  #S_LEAX
            JSR  OPI
            BRA  G_TFRXD
G_DEREF     PSHS X
            JSR  GENADDR
            PULS X
            LDX  N_TYPE,X
            JMP  LOADOP
G_NEG       LDX  N_L,X
            JSR  GEN
            LDX  #S_NEGD
            JMP  EMITL
G_COM       LDX  N_L,X
            JSR  GEN
            LDX  #S_COMD
            JMP  EMITL
G_CAST      PSHS X                     ; (type) x
            LDX  N_L,X
            JSR  GEN
            PULS X
            LDY  N_L,X
            LDX  N_TYPE,X
            JSR  TISCHAR
            BCS  GT_RET
            PSHS Y                     ; to a char: widened again (unless it's
            LDY  N_TYPE,Y              ; that char already)
            LDA  TY_KIND,Y
            PULS Y
            CMPA TY_KIND,X
            BEQ  GT_RET
            JMP  WIDEN
GT_RET      RTS
; A truth value as 0 or 1.
G_BOOL      PSHS X
            JSR  NEWLABEL              ; true
            PSHS D
            JSR  NEWLABEL              ; the end
            PSHS D
            LDX  4,S
            LDY  2,S
            LDA  #1
            JSR  GENJUMP
            LDX  #S_CLRD
            JSR  EMITL
            LDX  #S_BRA
            JSR  EMITI
            LDD  ,S
            JSR  OUTLBL
            JSR  OUTNL
            LDD  2,S
            JSR  LABELHERE
            LDX  #S_LDD1
            JSR  EMITL
            PULS D
            JSR  LABELHERE
            LEAS 4,S
            RTS
; c ? a : b
G_COND      PSHS X
            JSR  NEWLABEL              ; b
            PSHS D
            JSR  NEWLABEL              ; the end
            PSHS D
            LDX  4,S
            LDX  N_L,X
            LDY  2,S
            CLRA
            JSR  GENJUMP
            LDX  4,S
            LDX  N_R,X
            JSR  GEN
            LDD  ,S
            JSR  JUMPTO
            LDD  2,S
            JSR  LABELHERE
            LDX  4,S
            LDX  N_X,X
            JSR  GEN
            PULS D
            JSR  LABELHERE
            LEAS 4,S
            RTS
G_COMMA     PSHS X
            LDX  N_L,X
            JSR  GENVOID
            PULS X
            LDX  N_R,X
            JMP  GEN
G_ASSIGN    LDA  #1
            JMP  GENASSIGN
G_ASGOP     LDA  #1
            JMP  GENASGOP
G_INCDEC    LDA  #1
            JMP  GENINCDEC
; + - & | ^ *: the right side as an operand if it is one, else pushed.
G_BIN       LDA  N_OP,X
            SUBA #O_ADD
            LDB  #5
            MUL
            LDY  #BINMNEM
            LEAY B,Y
            PSHS X,Y                   ; ,S the node, 2,S its mnemonic
            LDX  N_R,X
            JSR  OPNDW
            BCS  GB_LEFT
            LDX  ,S                    ; x op operand
            LDX  N_L,X
            JSR  GEN
            LDX  ,S
            LDX  N_R,X
            JSR  OPND
            BRA  GB_DO
GB_LEFT     LDX  ,S                    ; operand op x, when op doesn't mind
            LDA  N_OP,X
            CMPA #O_SUB
            BEQ  GB_PUSH
            LDX  N_L,X
            JSR  OPNDW
            BCS  GB_PUSH
            LDX  ,S
            LDX  N_R,X
            JSR  GEN
            LDX  ,S
            LDX  N_L,X
            JSR  OPND
            BRA  GB_DO
GB_PUSH     LDX  ,S                    ; the right side pushed
            LDX  N_R,X
            JSR  GEN
            LDX  #S_PSHSD
            JSR  EMITL
            LDX  ,S
            LDX  N_L,X
            JSR  GEN
            LDA  #OM_POP
            STA  <OPM
GB_DO       PULS X,Y
            LDA  N_OP,X
            TFR  Y,X
            JSR  OPI
            CMPA #O_MUL
            BNE  GB_RET
            LDX  #S_TFRWD
            JMP  EMITL
GB_RET      RTS
BINMNEM     FCN  "ADDD"
            FCN  "SUBD"
            FCN  "MULD"
            FCC  "----"                ; (/ and %: helpers)
            FCB  0
            FCC  "----"
            FCB  0
            FCC  "----"                ; (<< >>: shifts, helpers)
            FCB  0
            FCC  "----"
            FCB  0
            FCN  "ANDD"
            FCN  "ORD "
            FCN  "EORD"
; / %: the library's helpers (D = left, X = right).
G_DIV       PSHS X
            LDX  N_R,X
            JSR  OPNDW
            PULS X
            BCS  GD_PUSH
            PSHS X
            LDX  N_L,X
            JSR  GEN
            LDX  ,S
            LDX  N_R,X
            JSR  OPND
            LDX  #S_LDX
            JSR  OPI
            PULS X
            BRA  GD_CALL
GD_PUSH     PSHS X
            LDX  N_R,X
            JSR  GEN
            LDX  #S_PSHSD
            JSR  EMITL
            LDX  ,S
            LDX  N_L,X
            JSR  GEN
            LDX  #S_PULSX
            JSR  EMITL
            PULS X
GD_CALL     LDA  N_OP,X                ; the helper: by the operation, and
            LDY  N_TYPE,X              ; whether it's unsigned
            CLRB
            EXG  X,Y
            JSR  TISUNS
            EXG  X,Y
            BCS  GD_SIGNED
            INCB
GD_SIGNED   JMP  HELPJSR
; << >>: by a number, shifts; otherwise a helper.
G_SHIFT     LDY  N_R,X
            LDA  N_OP,Y
            CMPA #O_NUM
            LBNE G_DIV
            PSHS X
            LDX  N_L,X
            JSR  GEN
            PULS X
; X = a shift node, its count a number: the shifts (on D).
SHIFTK      LDY  N_R,X
            LDB  N_V+1,Y
            LDA  N_V,Y
            BNE  SH_ALL
            TSTB
            BEQ  SH_RET
            CMPB #16
            BHS  SH_ALL
            LDA  N_OP,X
            CMPA #O_SHL
            BEQ  SH_LEFT
            PSHS X                     ; right: signed or not
            LDX  N_TYPE,X
            JSR  TISUNS
            PULS X
            BCC  SH_URIGHT
            CMPB #8                    ; arithmetic
            BLO  SH_ASRD
            LDX  #S_SBYTE
            JSR  EMITLINES
            SUBB #8
            LDX  #S_ASRB
            BRA  SH_N
SH_ASRD     LDX  #S_ASRD
            BRA  SH_N
SH_URIGHT   CMPB #8
            BLO  SH_LSRD
            LDX  #S_UBYTE
            JSR  EMITLINES
            SUBB #8
            LDX  #S_LSRB
            BRA  SH_N
SH_LSRD     LDX  #S_LSRD
            BRA  SH_N
SH_LEFT     CMPB #8
            BLO  SH_LSLD
            LDX  #S_LBYTE
            JSR  EMITLINES
            SUBB #8
            LDX  #S_LSLA
            BRA  SH_N
SH_LSLD     LDX  #S_LSLD
SH_N        TSTB                       ; B of X
            BEQ  SH_RET
            JSR  EMITL
            DECB
            BRA  SH_N
SH_RET      RTS
SH_ALL      LDA  N_OP,X                ; 16 or more: 0, or all the sign
            CMPA #O_SHL
            BEQ  SH_ZERO
            PSHS X
            LDX  N_TYPE,X
            JSR  TISUNS
            PULS X
            BCC  SH_ZERO
            LDX  #S_SALL
            JMP  EMITLINES
SH_ZERO     LDX  #S_CLRD
            JMP  EMITL
;------------------------------------------------------------------------------
; For the value's effect only (an expression statement): X = a tree.
;------------------------------------------------------------------------------
GENVOID     LDA  N_OP,X
            CMPA #O_ASSIGN
            BEQ  GV_ASSIGN
            CMPA #O_ASGOP
            BEQ  GV_ASGOP
            CMPA #O_PREINC
            BLO  GV_NOTID
            CMPA #O_POSTDEC
            BLS  GV_INCDEC
GV_NOTID    CMPA #O_COMMA
            BEQ  GV_COMMA
            CMPA #O_COND
            BEQ  GV_COND
            CMPA #O_CAST
            BEQ  GV_CAST
            CMPA #O_NUM
            BEQ  GV_RET
            CMPA #O_STR
            BEQ  GV_RET
            CMPA #O_SYM
            BEQ  GV_RET
            JMP  GEN
GV_RET      RTS
GV_ASSIGN   CLRA
            JMP  GENASSIGN
GV_ASGOP    CLRA
            JMP  GENASGOP
GV_INCDEC   CLRA
            JMP  GENINCDEC
GV_COMMA    PSHS X
            LDX  N_L,X
            BSR  GENVOID
            PULS X
            LDX  N_R,X
            BRA  GENVOID
GV_CAST     LDY  N_TYPE,X
            LDA  TY_KIND,Y
            CMPA #TK_VOID
            LBNE GEN
            LDX  N_L,X
            BRA  GENVOID
GV_COND     PSHS X
            JSR  NEWLABEL
            PSHS D
            JSR  NEWLABEL
            PSHS D
            LDX  4,S
            LDX  N_L,X
            LDY  2,S
            CLRA
            JSR  GENJUMP
            LDX  4,S
            LDX  N_R,X
            JSR  GENVOID
            LDD  ,S
            JSR  JUMPTO
            LDD  2,S
            JSR  LABELHERE
            LDX  4,S
            LDX  N_X,X
            JSR  GENVOID
            PULS D
            JSR  LABELHERE
            LEAS 4,S
            RTS
;------------------------------------------------------------------------------
; Jumps: X = a tree, Y = a label, A = 1: jump there if the tree is true; 0:
; if it's false. Otherwise the code goes on.
;------------------------------------------------------------------------------
GENJUMP     LDB  N_OP,X
            CMPB #O_NOT
            BEQ  GJ_NOT
            CMPB #O_LAND
            BEQ  GJ_LAND
            CMPB #O_LOR
            LBEQ GJ_LOR
            CMPB #O_NUM
            BEQ  GJ_NUM
            CMPB #O_COMMA
            BEQ  GJ_COMMA
            CMPB #O_EQ
            LBHS GJ_CMP
            PSHS A,Y                   ; any other: its value, tested
            JSR  GEN
            LDX  #S_TSTD
            JSR  EMITL
            PULS A,Y
            LDX  #S_LBNE
            TSTA
            BNE  GJ_BR
            LDX  #S_LBEQ
GJ_BR       JSR  EMITI
            TFR  Y,D
            JSR  OUTLBL
            JMP  OUTNL
GJ_NOT      EORA #1
            LDX  N_L,X
            BRA  GENJUMP
GJ_NUM      LDB  N_V,X                 ; a constant: always, or never
            ORB  N_V+1,X
            BEQ  GJ_N0
            LDB  #1
GJ_N0       PSHS A
            CMPB ,S+
            BNE  GJ_RET
            TFR  Y,D
            JMP  JUMPTO
GJ_RET      RTS
GJ_COMMA    PSHS A,X,Y
            LDX  N_L,X
            JSR  GENVOID
            PULS A,X,Y
            LDX  N_R,X
            BRA  GENJUMP
GJ_LAND     TSTA                       ; a && b
            BEQ  GJ_ANDF
            PSHS X,Y                   ; true: if !a skip; if b jump; skip:
            JSR  NEWLABEL
            PSHS D                     ; (,S skip, 2,S the node, 4,S the label)
            LDX  2,S
            LDX  N_L,X
            LDY  ,S
            CLRA
            JSR  GENJUMP
            LDX  2,S
            LDX  N_R,X
            LDY  4,S
            LDA  #1
            JSR  GENJUMP
            PULS D
            JSR  LABELHERE
            LEAS 4,S
            RTS
GJ_ANDF     PSHS X,Y                   ; false: if !a jump; if !b jump
            LDX  N_L,X
            CLRA
            JSR  GENJUMP
            PULS X,Y
            LDX  N_R,X
            CLRA
            JMP  GENJUMP
GJ_LOR      TSTA                       ; a || b
            BEQ  GJ_ORF
            PSHS X,Y                   ; true: if a jump; if b jump
            LDX  N_L,X
            LDA  #1
            JSR  GENJUMP
            PULS X,Y
            LDX  N_R,X
            LDA  #1
            JMP  GENJUMP
GJ_ORF      PSHS X,Y                   ; false: if a skip; if !b jump; skip:
            JSR  NEWLABEL
            PSHS D
            LDX  2,S
            LDX  N_L,X
            LDY  ,S
            LDA  #1
            JSR  GENJUMP
            LDX  2,S
            LDX  N_R,X
            LDY  4,S
            CLRA
            JSR  GENJUMP
            PULS D
            JSR  LABELHERE
            LEAS 4,S
            RTS
; A comparison: CMPGEN, then the branch for it (signed or not).
GJ_CMP      PSHS A,Y
            JSR  CMPGEN                ; -> B = the comparison (O_EQ..), maybe
            PULS A,Y                   ; swapped
            TSTA
            BNE  GJ_SENSE
            LDX  #INVOP                ; jump if false: the opposite
            SUBB #O_EQ
            LDB  B,X
GJ_SENSE    SUBB #O_EQ
            LDA  #5
            MUL
            LDX  #BRSIGNED
            TST  <CMPUNS
            BEQ  GJ_MNEM
            LDX  #BRUNSIGNED
GJ_MNEM     ABX
            JSR  EMITI
            TFR  Y,D
            JSR  OUTLBL
            JMP  OUTNL
INVOP       FCB  O_NE,O_EQ,O_GE,O_LE,O_GT,O_LT
SWAPOP      FCB  O_EQ,O_NE,O_GT,O_LT,O_GE,O_LE
BRSIGNED    FCN  "LBEQ"
            FCN  "LBNE"
            FCN  "LBLT"
            FCN  "LBGT"
            FCN  "LBLE"
            FCN  "LBGE"
BRUNSIGNED  FCN  "LBEQ"
            FCN  "LBNE"
            FCN  "LBLO"
            FCN  "LBHI"
            FCN  "LBLS"
            FCN  "LBHS"
; X = a comparison: the code comparing its two sides (CMPD). -> B = the
; comparison it makes (swapped, if the sides went the other way), CMPUNS =
; NF_UNS if it's unsigned.
CMPGEN      LDA  N_FL,X
            ANDA #NF_UNS
            STA  <CMPUNS
            LDB  N_OP,X
            PSHS B,X
            LDY  N_R,X                 ; x == 0 etc.: TSTD (CMPD #0, unsigned)
            LDA  N_OP,Y
            CMPA #O_NUM
            BNE  CG_GEN
            LDD  N_V,Y
            BNE  CG_GEN
            LDX  N_L,X
            JSR  GEN
            LDX  #S_TSTD
            TST  <CMPUNS
            BEQ  CG_TST
            LDX  #S_CMPD0
CG_TST      JSR  EMITL
            PULS B,X,PC
CG_GEN      LDX  1,S
            LDX  N_R,X
            JSR  OPNDW
            BCS  CG_LEFT
            LDX  1,S                   ; x CMPD operand
            LDX  N_L,X
            JSR  GEN
            LDX  1,S
            LDX  N_R,X
            JSR  OPND
            BRA  CG_DO
CG_LEFT     LDX  1,S                   ; operand on the left: swapped
            LDX  N_L,X
            JSR  OPNDW
            BCS  CG_PUSH
            LDX  1,S
            LDX  N_R,X
            JSR  GEN
            LDX  1,S
            LDX  N_L,X
            JSR  OPND
            LDB  ,S
            SUBB #O_EQ
            LDX  #SWAPOP
            LDB  B,X
            STB  ,S
            BRA  CG_DO
CG_PUSH     LDX  1,S
            LDX  N_R,X
            JSR  GEN
            LDX  #S_PSHSD
            JSR  EMITL
            LDX  1,S
            LDX  N_L,X
            JSR  GEN
            LDA  #OM_POP
            STA  <OPM
CG_DO       LDX  #S_CMPD
            JSR  OPI
            PULS B,X,PC
;------------------------------------------------------------------------------
; Assignments. A = 1 if the value is wanted too (in D).
;------------------------------------------------------------------------------
GENASSIGN   PSHS A,X
            LDX  N_L,X                 ; the left side as it is?
            JSR  OPND
            BCS  GN_NOTLEFT
            LDX  1,S                   ; yes: the right, then stored
            LDX  N_R,X
            JSR  GEN
            LDX  1,S
            LDX  N_L,X
            JSR  OPND
            BRA  GN_STORE
GN_NOTLEFT  LDX  1,S                   ; the right side as it is?
            LDX  N_R,X
            JSR  OPNDW
            BCS  GN_PUSH
            LDX  1,S                   ; yes: where, then the right loaded
            LDX  N_L,X
            JSR  GENADDR
            JSR  SAVEOP
            LDX  8,S
            LDX  N_R,X
            JSR  OPND
            LDX  #S_LDD
            JSR  OPI
            JSR  RESTOP
            BRA  GN_STORE
GN_PUSH     LDX  1,S                   ; neither: the right pushed
            LDX  N_R,X
            JSR  GEN
            LDX  #S_PSHSD
            JSR  EMITL
            LDX  1,S
            LDX  N_L,X
            JSR  GENADDR
            LDX  #S_PULSD
            JSR  EMITL
GN_STORE    LDX  1,S
            LDX  N_TYPE,X
            JSR  STOREOP
            PULS A,X
            TSTA
            BEQ  GN_RET
            LDX  N_TYPE,X              ; the value: a char's widened
            JMP  WIDEN
GN_RET      RTS
; x op= y: the right side first (pushed, unless it's a number), then where x
; is, x loaded, the operation, x stored. (From GENADDR's return on, nothing
; here makes code of a tree again, so AG* can hold what's needed.)
GENASGOP    PSHS A,X
            LDX  N_R,X
            LDA  N_OP,X
            CMPA #O_NUM
            BEQ  GO_ADDR
            JSR  GEN
            LDX  #S_PSHSD
            JSR  EMITL
GO_ADDR     LDX  1,S
            LDX  N_L,X
            JSR  GENADDR
            PULS A,X
            STA  <AGNEED
            STX  <AGNODE
            JSR  AGKEEP
            LDX  N_L,X                 ; x loaded
            LDX  N_TYPE,X
            JSR  LOADOP
            LDX  <AGNODE
            LDA  N_V+1,X               ; the operation
            LDY  N_R,X
            LDB  N_OP,Y
            CMPB #O_NUM
            BNE  GO_PUSHED
            CMPA #O_SHL                ; by a number
            BEQ  GO_SHIFT
            CMPA #O_SHR
            BEQ  GO_SHIFT
            CMPA #O_DIV
            BEQ  GO_HNUM
            CMPA #O_MOD
            BEQ  GO_HNUM
            PSHS A
            TFR  Y,X
            JSR  OPND
            PULS A
            BRA  GO_OP
GO_PUSHED   CMPA #O_DIV                ; by what's pushed
            BEQ  GO_HPUSH
            CMPA #O_MOD
            BEQ  GO_HPUSH
            CMPA #O_SHL
            BEQ  GO_HPUSH
            CMPA #O_SHR
            BEQ  GO_HPUSH
            LDB  #OM_POP
            STB  <OPM
GO_OP       PSHS A                     ; + - * & | ^
            SUBA #O_ADD
            LDB  #5
            MUL
            LDX  #BINMNEM
            ABX
            JSR  OPI
            PULS A
            CMPA #O_MUL
            BNE  GO_STORE
            LDX  #S_TFRWD
            JSR  EMITL
            BRA  GO_STORE
GO_SHIFT    LDX  <AGNODE               ; (SHIFTK takes the node: its op the
            LDB  N_OP,X                ; shift, for now)
            PSHS B
            STA  N_OP,X
            JSR  SHIFTK
            PULS B
            LDX  <AGNODE
            STB  N_OP,X
            BRA  GO_STORE
GO_HNUM     PSHS A                     ; / % by a number: X = it (x's address,
            JSR  AGXPUSH               ; if X has it, kept)
            LDX  <AGNODE
            LDX  N_R,X
            JSR  OPND
            LDX  #S_LDX
            JSR  OPI
            PULS A
            JSR  AGHELP
            JSR  AGXPULL
            BRA  GO_STORE
GO_HPUSH    PSHS A                     ; / % << >> by what's pushed: X = it
            LDA  <AGSAVE
            CMPA #OM_XOFF
            BNE  GO_HNOX
            LDX  #S_PSHSX              ; (X is x's address: kept)
            JSR  EMITL
            LDX  #S_LDX2S
            JSR  EMITL
            PULS A
            JSR  AGHELP
            LDX  #S_PULSX
            JSR  EMITL
            LDX  #S_LEAS2
            JSR  EMITL
            BRA  GO_STORE
GO_HNOX     LDX  #S_PULSX
            JSR  EMITL
            PULS A
            JSR  AGHELP
GO_STORE    JSR  AGBACK                ; x stored
            LDX  <AGNODE
            LDX  N_L,X
            LDX  N_TYPE,X
            JSR  STOREOP
            TST  <AGNEED
            BEQ  GO_RET
            JMP  WIDEN
GO_RET      RTS
; Where x is (OPM...) -> AGSAVE, and back (AGBACK).
AGKEEP      PSHS X
            LDD  <OPM
            STD  <AGSAVE
            LDD  <OPM+2
            STD  <AGSAVE+2
            LDD  <OPM+4
            STD  <AGSAVE+4
            LDA  <OPM+6
            STA  <AGSAVE+6
            PULS X,PC
AGBACK      LDD  <AGSAVE
            STD  <OPM
            LDD  <AGSAVE+2
            STD  <OPM+2
            LDD  <AGSAVE+4
            STD  <OPM+4
            LDA  <AGSAVE+6
            STA  <OPM+6
            RTS
; PSHS X / PULS X around a helper, if X holds x's address.
AGXPUSH     LDA  <AGSAVE
            CMPA #OM_XOFF
            BNE  AX_RET
            LDX  #S_PSHSX
            JMP  EMITL
AGXPULL     LDA  <AGSAVE
            CMPA #OM_XOFF
            BNE  AX_RET
            LDX  #S_PULSX
            JMP  EMITL
AX_RET      RTS
; A = O_DIV, O_MOD, O_SHL or O_SHR: the helper for the op= node (signed or
; not, as its N_FL says).
AGHELP      LDX  <AGNODE
            CLRB
            PSHS A
            LDA  N_FL,X
            BITA #NF_UNS
            PULS A
            BEQ  HELPJSR
            INCB
; A = O_DIV, O_MOD, O_SHL or O_SHR, B = 1 if unsigned: JSR to the library's
; helper for it (D = the left side, X = the right), which is then IMPORTed.
HELPJSR     CMPA #O_DIV
            BEQ  HJ_IDX
            CMPA #O_MOD
            BNE  HJ_SHL
            ADDB #2
            BRA  HJ_IDX
HJ_SHL      CMPA #O_SHL
            BNE  HJ_SHR
            LDB  #4
            BRA  HJ_IDX
HJ_SHR      ADDB #5
HJ_IDX      LDA  #1                    ; its bit in HELPERS
            PSHS B
HJ_BIT      TSTB
            BEQ  HJ_SET
            LSLA
            DECB
            BRA  HJ_BIT
HJ_SET      ORA  <HELPERS
            STA  <HELPERS
            LDX  #S_JSR
            JSR  EMITI
            LDX  #HELPNAMES            ; its name: the B'th
            PULS B
HJ_FIND     TSTB
            BEQ  HJ_NAME
HJ_SKIP     TST  ,X+
            BNE  HJ_SKIP
            DECB
            BRA  HJ_FIND
HJ_NAME     JSR  OUTS
            JMP  OUTNL
; ++x --x x++ x--.
GENINCDEC   PSHS A,X
            LDX  N_L,X
            JSR  GENADDR
            PULS A,X
            STA  <AGNEED
            STX  <AGNODE
            TSTA                       ; a char, by 1, its value not wanted:
            BNE  GK_LOAD               ; INC or DEC
            LDD  N_V,X
            CMPD #1
            BNE  GK_LOAD
            LDX  N_TYPE,X
            JSR  TISCHAR
            BCS  GK_LOAD
            LDX  <AGNODE
            LDA  N_OP,X
            LDX  #S_INC
            CMPA #O_PREINC
            BEQ  GK_INCDEC
            CMPA #O_POSTINC
            BEQ  GK_INCDEC
            LDX  #S_DEC
GK_INCDEC   JMP  OPI
GK_LOAD     JSR  AGKEEP                ; load, add, store
            LDX  <AGNODE
            LDX  N_TYPE,X
            JSR  LOADOP
            CLRA
            BSR  INCSTEP
            JSR  AGBACK
            LDX  <AGNODE
            LDX  N_TYPE,X
            JSR  STOREOP
            TST  <AGNEED
            BEQ  GK_RET
            LDX  <AGNODE               ; the value: x++ the old one (the step
            LDA  N_OP,X                ; taken off again), ++x the new
            CMPA #O_PREINC
            BEQ  GK_NEW
            CMPA #O_PREDEC
            BEQ  GK_NEW
            LDA  #1
            BRA  INCSTEP
GK_NEW      LDX  N_TYPE,X
            JMP  WIDEN
GK_RET      RTS
; ADDD #step for ++, SUBD #step for -- (A = 1: the other way).
INCSTEP     LDX  <AGNODE
            LDB  N_OP,X
            CMPB #O_PREINC
            BEQ  IS_INC
            CMPB #O_POSTINC
            BEQ  IS_INC
            EORA #1
IS_INC      LDX  #S_ADDD
            TSTA
            BEQ  IS_EMIT
            LDX  #S_SUBD
IS_EMIT     JSR  EMITI
            LDA  #'#'
            JSR  OUTC
            LDX  <AGNODE
            LDD  N_V,X
            JSR  OUTDEC
            JMP  OUTNL
;------------------------------------------------------------------------------
; Calls: the arguments pushed last first, JSR, and the stack back.
;------------------------------------------------------------------------------
G_CALL      PSHS X
            LDX  N_R,X
            JSR  PUSHARGS
            LDX  ,S
            LDX  N_L,X                 ; what's called
            LDA  N_OP,X
            CMPA #O_ADDR               ; a function: JSR _f
            BNE  GL_PTR
            JSR  OPND
            BCS  GL_ANY
            LDA  #OM_EXT
            STA  <OPM
            BRA  GL_JSR
GL_PTR      JSR  OPNDW                 ; a pointer variable: JSR [p]
            BCS  GL_ANY
            LDA  <OPM
            CMPA #OM_EXT
            BEQ  GL_EXT
            CMPA #OM_UOFF
            BNE  GL_ANY
            LDA  #OM_UIND
            STA  <OPM
            BRA  GL_JSR
GL_EXT      LDA  #OM_IND
            STA  <OPM
GL_JSR      LDX  #S_JSR
            JSR  OPI
            BRA  GL_POP
GL_ANY      JSR  GEN                   ; anything else: JSR ,X
            LDX  #S_TFRDX
            JSR  EMITL
            LDX  #S_JSRX
            JSR  EMITL
GL_POP      PULS X
            LDD  N_X,X
            BEQ  GL_RET
            LSLD
            PSHS D
            LDX  #S_LEAS
            JSR  EMITI
            PULS D
            JSR  OUTDEC
            LDX  #S_COMMAS
            JSR  OUTS
            JMP  OUTNL
GL_RET      RTS
; X = an O_ARG list: each pushed, the last first.
PUSHARGS    CMPX #0
            BEQ  PA2_RET
            PSHS X
            LDX  N_R,X
            BSR  PUSHARGS
            PULS X
            LDX  N_L,X
            JSR  GEN
            LDX  #S_PSHSD
            JMP  EMITL
PA2_RET     RTS
;------------------------------------------------------------------------------
M_INTADDR   FCN  "internal error (an address)"
S_LBRA      FCN  "LBRA"
S_BRA       FCN  "BRA"
S_SECTION   FCN  "SECTION"
S_POP       FCN  ",S++"
S_COMMAX    FCN  ",X"
S_LDB       FCN  "LDB"
S_LDD       FCN  "LDD"
S_STB       FCN  "STB"
S_STD       FCN  "STD"
S_LEAX      FCN  "LEAX"
S_JSR       FCN  "JSR"
S_INC       FCN  "INC"
S_DEC       FCN  "DEC"
S_ADDD      FCN  "ADDD"
S_SUBD      FCN  "SUBD"
S_TSTD      FCN  "TSTD"
S_LBNE      FCN  "LBNE"
S_CMPD0     FCN  "CMPD #0"
S_SEX       FCN  "SEX"
S_CLRA      FCN  "CLRA"
S_CLRD      FCN  "CLRD"
S_NEGD      FCN  "NEGD"
S_COMD      FCN  "COMD"
S_LDD1      FCN  "LDD #1"
S_PSHSD     FCN  "PSHS D"
S_PULSD     FCN  "PULS D"
S_PSHSX     FCN  "PSHS X"
S_PULSX     FCN  "PULS X"
S_LDX2S     FCN  "LDX 2,S"
S_LEAS2     FCN  "LEAS 2,S"
S_TFRDX     FCN  "TFR D,X"
S_TFRXD     FCN  "TFR X,D"
S_TFRWD     FCN  "TFR W,D"
S_LEAXDX    FCN  "LEAX D,X"
S_JSRX      FCN  "JSR ,X"
S_ASRD      FCN  "ASRD"
S_LSRD      FCN  "LSRD"
S_LSLD      FCN  "LSLD"
S_ASRB      FCN  "ASRB"
S_LSRB      FCN  "LSRB"
S_LSLA      FCN  "LSLA"
S_SBYTE     FCN  "TFR A,B"             ; >> 8, signed
            FCN  "SEX"
            FCB  0
S_UBYTE     FCN  "TFR A,B"             ; >> 8, unsigned
            FCN  "CLRA"
            FCB  0
S_LBYTE     FCN  "TFR B,A"             ; << 8
            FCN  "CLRB"
            FCB  0
S_SALL      FCN  "TFR A,B"             ; >> 16, signed: the sign
            FCN  "SEX"
            FCN  "TFR A,B"
            FCB  0
;------------------------------------------------------------------------------
; End of cc1_gen.asm
;------------------------------------------------------------------------------
