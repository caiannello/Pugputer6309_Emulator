;------------------------------------------------------------------------------
; cc1_long.asm -- CC1: code for longs and structs.
;
; A long's value is made in Q (D the high word, W the low one), as it is in
; memory (big-endian): LDQ and STQ move it. Pushed, it's PSHSW / PSHS D, so the
; high word is at ,S and the low at 2,S. The library's helpers for * / % and
; the shifts take the left side in Q and the right on the stack (at 2,S as
; they see it: a long, or a shift's count, an int), keep X, and leave the
; result in Q; the caller takes the right side off again.
;
; A struct's value is its address, in D. Copying one is __scopy (X = where to,
; D = from, the size in an FDB after the JSR), which leaves D = where to.
;------------------------------------------------------------------------------
; X = a node: carry clear if its type is a long. Keeps every register.
ISLONGN     PSHS X
            LDX  N_TYPE,X
            JSR  TISLONG
            PULS X,PC
; GEN of a long-typed node (X): GLTAB's, or GEN's own (0).
GENL        LDB  N_OP,X
            CMPB #O_XOR
            LBHI GEN_DO
            DECB
            LSLB
            LDY  #GLTAB
            LDY  B,Y
            LBEQ GEN_DO
            JMP  ,Y
GLTAB       FDB  GL_NUM,GL_LOAD,0,0,GL_LOAD,GL_NEG,GL_COM,0,GL_CAST
            FDB  0,0,0,0,0,0,0,0,0,0,0,0,GL_LOAD
            FDB  GL_BIN,GL_BIN,GL_BIN,GL_BIN,GL_BIN,GL_BIN,GL_BIN,GL_BIN
            FDB  GL_BIN,GL_BIN
; GEN of a struct-typed node (X): a variable's address; the rest as GEN has
; them (a call, an assignment, ?:, a comma).
GENS        LDB  N_OP,X
            CMPB #O_SYM
            BEQ  GENSADDR
            CMPB #O_DEREF
            BEQ  GENSADDR
            CMPB #O_FRAME
            LBNE GEN_DO
; X = an lvalue: its address -> D.
GENSADDR    JSR  GENADDR
            JSR  ADDROPX
            LDX  #S_TFRXD
            JMP  EMITL
;------------------------------------------------------------------------------
; Operands of longs.
;------------------------------------------------------------------------------
; X = a node: carry clear if it is a long, used as it is (OPND), and (a
; number) a long's (OPVH = its high word). Keeps X and Y.
OPNDL       JSR  ISLONGN
            BCS  OL_RET
            JSR  OPND
            BCS  OL_RET
            LDA  <OPM
            CMPA #OM_IMM
            BNE  OL_YES
            LDA  N_OP,X
            CMPA #O_NUM
            BNE  OL_NO
            LDD  N_X,X
            STD  <OPVH
OL_YES      ANDCC #$FE
OL_RET      RTS
OL_NO       ORCC #1
            RTS
; The operand (OPM etc.) at an address, put in X: then it's 0,X. (So a long's
; two halves can be got at: n,X and n+2,X.)
ADDROPX     LDA  <OPM
            CMPA #OM_XOFF
            BEQ  AO_XOFF
            LDX  #S_LEAX
            CMPA #OM_UOFF
            BEQ  AO_EMIT
            LDX  #S_LDX
            LDB  #OM_IMM
            CMPA #OM_EXT
            BEQ  AO_MODE
            LDB  #OM_EXT
            CMPA #OM_IND
            BEQ  AO_MODE
            LDB  #OM_UOFF              ; (OM_UIND)
AO_MODE     STB  <OPM
AO_EMIT     JSR  OPI
AO_SET      CLRD
            STD  <OPV
            STD  <OPS
            STD  <OPL
            LDA  #OM_XOFF
            STA  <OPM
            RTS
AO_XOFF     LDD  <OPV
            BEQ  AO_SET
            LDX  #S_LEAX
            BRA  AO_EMIT
; [p] or [n,U]: made 0,X (the pointer loaded), for a long's halves.
FIXIND      LDA  <OPM
            CMPA #OM_IND
            BEQ  ADDROPX
            CMPA #OM_UIND
            BEQ  ADDROPX
            RTS
; X = a mnemonic, A = 0 (the high word) or 2 (the low): " MNEM operand", a
; line. Keeps X.
LOPI        JSR  EMITI
            PSHS A,X
            LDB  <OPM
            CMPB #OM_IMM
            BEQ  LQ_IMM
            CMPB #OM_POP
            BEQ  LQ_POP
            LDD  <OPV                  ; in memory: n+0 or n+2
            PSHS D
            LDB  2,S
            CLRA
            ADDD ,S
            STD  <OPV
            JSR  EMITOP
            PULS D
            STD  <OPV
            BRA  LQ_END
LQ_IMM      LDA  #'#'
            JSR  OUTC
            LDD  <OPV
            TST  ,S
            BNE  LQ_DEC
            LDD  <OPVH
LQ_DEC      JSR  OUTDEC
            BRA  LQ_END
LQ_POP      LDX  #S_COMMAS             ; pushed: ,S and 2,S
            TST  ,S
            BEQ  LQ_S
            LDX  #S_2S
LQ_S        JSR  OUTS
LQ_END      PULS A,X
            JMP  OUTNL
; A = O_ADD, O_SUB, O_AND, O_OR or O_XOR: Q op= the operand.
LOPS        LDX  #S_ADDW
            LDY  #S_ADCD
            CMPA #O_ADD
            BEQ  LS_ARITH
            LDX  #S_SUBW
            LDY  #S_SBCD
            CMPA #O_SUB
            BEQ  LS_ARITH
            LDX  #S_ANDD               ; the logic: on D, then on W (in D for a
            CMPA #O_AND                ; moment)
            BEQ  LS_LOGIC
            LDX  #S_ORD
            CMPA #O_OR
            BEQ  LS_LOGIC
            LDX  #S_EORD
LS_LOGIC    CLRA
            JSR  LOPI
            PSHS X
            LDX  #S_EXGDW
            JSR  EMITL
            PULS X
            LDA  #2
            JSR  LOPI
            LDX  #S_EXGDW
            JMP  EMITL
LS_ARITH    PSHS Y
            LDA  #2
            JSR  LOPI
            PULS X
            CLRA
            JMP  LOPI
; If the operand was pushed: it's taken off.
POPDROP     LDA  <OPM
            CMPA #OM_POP
            BNE  PD_RET
            LDX  #S_LEAS4
            JMP  EMITL
PD_RET      RTS
PUSHQ       PSHS X
            LDX  #S_PUSHQ
            JSR  EMITLINES
            PULS X,PC
POPQ        PSHS X
            LDX  #S_POPQ
            JSR  EMITLINES
            PULS X,PC
; The operand OPNDL found -> Q.
LLOAD       LDA  <OPM
            CMPA #OM_IMM
            BEQ  LL_IMM
            LDX  #S_LDQ
            JMP  OPI
LL_IMM      LDD  <OPVH
            LDX  #S_LDD
            BSR  LL_HALF
            LDD  <OPV
            LDX  #S_LDW
LL_HALF     CMPD #0                    ; LDD #n or CLRD (LDW #n, CLRW)
            BEQ  LL_CLR
            JSR  EMITI
            PSHS A
            LDA  #'#'
            JSR  OUTC
            PULS A
            JSR  OUTDEC
            JMP  OUTNL
LL_CLR      LDA  #' '
            JSR  OUTC
            LDA  2,X
            PSHS A
            LDX  #S_CLR
            JSR  OUTS
            PULS A
            JSR  OUTC
            JMP  OUTNL
;------------------------------------------------------------------------------
; Longs' values -> Q.
;------------------------------------------------------------------------------
GL_NUM      LDD  N_X,X
            STD  <OPVH
            LDD  N_V,X
            STD  <OPV
            BRA  LL_IMM
GL_LOAD     JSR  GENADDR
            LDX  #S_LDQ
            JMP  OPI
GL_NEG      LDX  N_L,X
            JSR  GEN
            LDX  #S_NEGQ
            JMP  EMITLINES
GL_COM      LDX  N_L,X
            JSR  GEN
            LDX  #S_COMQ
            JMP  EMITLINES
GL_CAST     PSHS X                     ; (long) x
            LDX  N_L,X
            JSR  GEN
            LDX  ,S
            LDX  N_L,X
            JSR  ISLONGN
            PULS X
            BCC  GQ_RET                ; from a long: as it is
            LDY  N_L,X                 ; from an int (or a char, widened), a
            LDX  N_TYPE,Y              ; pointer: the sign, or 0
            JSR  TISUNS
            LDX  #S_SEXQ
            BCS  GQ_EMIT
            LDX  #S_ZEXQ
GQ_EMIT     JMP  EMITLINES
GQ_RET      RTS
; + - & | ^ (operands in place, or the right pushed), * / % (helpers), << >>.
GL_BIN      LDA  N_OP,X
            CMPA #O_MUL
            BEQ  GL_HELP
            CMPA #O_DIV
            BEQ  GL_HELP
            CMPA #O_MOD
            BEQ  GL_HELP
            CMPA #O_SHL
            LBEQ GL_SHIFT
            CMPA #O_SHR
            LBEQ GL_SHIFT
            PSHS X
            LDX  N_R,X
            JSR  OPNDL
            BCS  GB2_LEFT
            LDX  ,S                    ; x op operand
            LDX  N_L,X
            JSR  GEN
            LDX  ,S
            LDX  N_R,X
            BRA  GB2_OPND
GB2_LEFT    LDX  ,S                    ; operand op x (not -)
            LDA  N_OP,X
            CMPA #O_SUB
            BEQ  GB2_PUSH
            LDX  N_L,X
            JSR  OPNDL
            BCS  GB2_PUSH
            LDX  ,S
            LDX  N_R,X
            JSR  GEN
            LDX  ,S
            LDX  N_L,X
GB2_OPND    JSR  OPNDL
            JSR  FIXIND
            BRA  GB2_DO
GB2_PUSH    LDX  ,S                    ; the right side pushed
            LDX  N_R,X
            JSR  GEN
            JSR  PUSHQ
            LDX  ,S
            LDX  N_L,X
            JSR  GEN
            LDA  #OM_POP
            STA  <OPM
GB2_DO      PULS X
            LDA  N_OP,X
            JSR  LOPS
            JMP  POPDROP
GL_HELP     PSHS X                     ; the right pushed, the left in Q, a
            LDX  N_R,X                 ; helper
            JSR  GEN
            JSR  PUSHQ
            LDX  ,S
            LDX  N_L,X
            JSR  GEN
            PULS X
            LDA  N_OP,X
            JSR  LHELPIDX
            JSR  CALLHELP
            LDX  #S_LEAS4
            JMP  EMITL
GL_SHIFT    LDY  N_R,X                 ; << >> by 1 to 4, or 16: shifts
            LDA  N_OP,Y
            CMPA #O_NUM
            BNE  GS_VAR
            LDD  N_V,Y
            BEQ  GS_NONE
            CMPD #16
            BEQ  GS_16
            CMPD #4
            BHI  GS_VAR
            PSHS B,X
            LDX  N_L,X
            JSR  GEN
            PULS B,X
            LDY  #S_LSLQ
            JSR  GS_LINES
GS_N        JSR  EMITLINES
            DECB
            BNE  GS_N
            RTS
GS_NONE     LDX  N_L,X
            JMP  GEN
GS_16       PSHS X
            LDX  N_L,X
            JSR  GEN
            PULS X
            LDY  #S_SHL16
            JSR  GS_LINES
            JMP  EMITLINES
GS_VAR      PSHS X                     ; otherwise the helper, the count
            LDX  N_R,X                 ; pushed
            JSR  GEN
            LDX  #S_PSHSD
            JSR  EMITL
            LDX  ,S
            LDX  N_L,X
            JSR  GEN
            PULS X
            LDA  N_OP,X
            JSR  LHELPIDX
            JSR  CALLHELP
            LDX  #S_LEAS2
            JMP  EMITL
; X = a shift node, Y = the left shift's lines (the signed right's, the
; unsigned right's follow, each list 1+ lines and an empty one) -> X = this
; one's.
GS_LINES    LDA  N_OP,X
            CMPA #O_SHL
            BEQ  GL_THIS
            BSR  GL_SKIP
            LDA  N_FL,X
            BITA #NF_UNS
            BEQ  GL_THIS
            BSR  GL_SKIP
GL_THIS     TFR  Y,X
            RTS
GL_SKIP     TST  ,Y+                   ; Y past one list
            BNE  GL_SKIP
            TST  ,Y
            BNE  GL_SKIP
            LEAY 1,Y
            RTS
; A = O_MUL, O_DIV, O_MOD, O_SHL or O_SHR, X = the node (its NF_UNS) -> B = the
; long helper's number.
LHELPIDX    LDB  #8
            CMPA #O_MUL
            BEQ  LH_RET
            LDB  #13
            CMPA #O_SHL
            BEQ  LH_RET
            LDB  #9
            CMPA #O_DIV
            BEQ  LH_UNS
            LDB  #11
            CMPA #O_MOD
            BEQ  LH_UNS
            LDB  #14
LH_UNS      LDA  N_FL,X
            BITA #NF_UNS
            BEQ  LH_RET
            INCB
LH_RET      RTS
;------------------------------------------------------------------------------
; Assignments to longs (A = 1 if the value's wanted: it's in Q anyway).
;------------------------------------------------------------------------------
GL_ASSIGN   PSHS X
            LDX  N_L,X
            JSR  OPND
            BCS  GA2_NLEFT
            LDX  ,S                    ; x where it is: y, then STQ
            LDX  N_R,X
            JSR  GEN
            LDX  ,S
            LDX  N_L,X
            JSR  OPND
            BRA  GA2_STORE
GA2_NLEFT   LDX  ,S
            LDX  N_R,X
            JSR  OPNDL
            BCS  GA2_PUSH
            LDX  ,S                    ; y where it is: where x is, then y
            LDX  N_L,X
            JSR  GENADDR
            JSR  SAVEOP
            LDX  7,S
            LDX  N_R,X
            JSR  OPNDL
            JSR  LLOAD
            JSR  RESTOP
            BRA  GA2_STORE
GA2_PUSH    LDX  ,S                    ; neither: y pushed
            LDX  N_R,X
            JSR  GEN
            JSR  PUSHQ
            LDX  ,S
            LDX  N_L,X
            JSR  GENADDR
            JSR  POPQ
GA2_STORE   LDX  #S_STQ
            JSR  OPI
            PULS X,PC
; x op= y: y pushed (unless it's a number for + - & | ^), where x is, LDQ x,
; the operation, STQ x.
GL_ASGOP    PSHS X
            JSR  AGIMM
            BCC  GO2_ADDR
            LDX  ,S
            LDX  N_R,X
            JSR  GEN
            LDX  ,S
            LDX  N_R,X
            JSR  ISLONGN
            BCS  GO2_PW
            JSR  PUSHQ
            BRA  GO2_ADDR
GO2_PW      LDX  #S_PSHSD              ; (a shift's count)
            JSR  EMITL
GO2_ADDR    LDX  ,S
            LDX  N_L,X
            JSR  GENADDR
            PULS X
            STX  <AGNODE
            JSR  AGKEEP
            LDX  #S_LDQ
            JSR  OPI
            LDX  <AGNODE
            JSR  AGIMM
            BCS  GO2_STK
            LDY  N_R,X                 ; by a number, in place
            LDD  N_V,Y
            STD  <OPV
            LDD  N_X,Y
            STD  <OPVH
            LDA  #OM_IMM
            STA  <OPM
            LDA  N_V+1,X
            JSR  LOPS
            BRA  GO2_STORE
GO2_STK     LDA  N_V+1,X               ; by what's pushed
            CMPA #O_MUL
            BEQ  GO2_HELP
            CMPA #O_DIV
            BEQ  GO2_HELP
            CMPA #O_MOD
            BEQ  GO2_HELP
            CMPA #O_SHL
            BEQ  GO2_HELP
            CMPA #O_SHR
            BEQ  GO2_HELP
            LDB  #OM_POP
            STB  <OPM
            JSR  LOPS
            LDX  #S_LEAS4
            BRA  GO2_POP
GO2_HELP    JSR  LHELPIDX              ; (the helpers keep X)
            JSR  CALLHELP
            LDX  <AGNODE
            LDA  N_V+1,X
            LDX  #S_LEAS4
            CMPA #O_SHL
            BEQ  GO2_L2
            CMPA #O_SHR
            BNE  GO2_POP
GO2_L2      LDX  #S_LEAS2
GO2_POP     JSR  EMITL
GO2_STORE   JSR  AGBACK
            LDX  #S_STQ
            JMP  OPI
; X = an op= node: carry clear if it's + - & | ^ by a number.
AGIMM       LDY  N_R,X
            LDA  N_OP,Y
            CMPA #O_NUM
            BNE  AI_NO
            LDA  N_V+1,X
            CMPA #O_ADD
            BEQ  AI_YES
            CMPA #O_SUB
            BEQ  AI_YES
            CMPA #O_AND
            BEQ  AI_YES
            CMPA #O_OR
            BEQ  AI_YES
            CMPA #O_XOR
            BEQ  AI_YES
AI_NO       ORCC #1
            RTS
AI_YES      ANDCC #$FE
            RTS
; ++ -- on a long: LDQ, add or take 1, STQ (x++: the old value kept).
GL_INCDEC   PSHS A,X
            LDX  N_L,X
            JSR  GENADDR
            PULS A,X
            STA  <AGNEED
            STX  <AGNODE
            LDX  #S_LDQ
            JSR  OPI
            LDX  <AGNODE
            LDA  N_OP,X
            CLRB                       ; B = 1: x++ and its value wanted
            CMPA #O_POSTINC
            BEQ  GI2_POST
            CMPA #O_POSTDEC
            BNE  GI2_STEP
GI2_POST    TST  <AGNEED
            BEQ  GI2_STEP
            INCB
            JSR  PUSHQ
GI2_STEP    PSHS B
            LDX  #S_INCQ
            CMPA #O_PREINC
            BEQ  GI2_DO
            CMPA #O_POSTINC
            BEQ  GI2_DO
            LDX  #S_DECQ
GI2_DO      JSR  EMITLINES
            LDX  #S_STQ
            JSR  OPI
            PULS B
            TSTB
            BEQ  GI2_RET
            JMP  POPQ
GI2_RET     RTS
;------------------------------------------------------------------------------
; Comparing longs: X = the comparison -> code, B = the comparison to branch
; on, CMPUNS (as CMPGEN). a - b sets the flags < and >= need (SUBW, SBCD); ==
; and != then need D | W (ORR). a > b is b < a, and a <= b is b >= a.
;------------------------------------------------------------------------------
CMPL        LDA  N_FL,X
            ANDA #NF_UNS
            STA  <CMPUNS
            LDB  N_OP,X
            PSHS B,X                   ; (,S the comparison, 1,S the node)
            LDY  N_R,X                 ; against 0
            LDA  N_OP,Y
            CMPA #O_NUM
            BNE  CQ_GEN
            LDD  N_V,Y
            ORD  N_X,Y
            BNE  CQ_GEN
            LDB  ,S
            LDY  #S_ORRWD
            CMPB #O_EQ
            BEQ  CQ_ZERO
            CMPB #O_NE
            BEQ  CQ_ZERO
            TST  <CMPUNS
            BNE  CQ_GEN
            LDY  #S_TSTD               ; (signed: the sign is D's)
            CMPB #O_LT
            BEQ  CQ_ZERO
            CMPB #O_GE
            BNE  CQ_GEN
CQ_ZERO     PSHS Y
            LDX  3,S
            LDX  N_L,X
            JSR  GEN
            PULS X
            JSR  EMITL
            PULS B,X,PC
CQ_GEN      LDX  1,S
            LDY  N_R,X
            LDX  N_L,X
            LDB  ,S
            CMPB #O_GT
            BEQ  CQ_SWAP
            CMPB #O_LE
            BNE  CQ_SIDES
CQ_SWAP     EXG  X,Y
            SUBB #O_EQ
            PSHS X
            LDX  #SWAPOP
            LDB  B,X
            PULS X
            STB  ,S
CQ_SIDES    PSHS X,Y                   ; ,S the left, 2,S the right
            TFR  Y,X
            JSR  OPNDL
            BCS  CQ_PUSH
            LDX  ,S
            JSR  GEN
            LDX  2,S
            JSR  OPNDL
            JSR  FIXIND
            BRA  CQ_SUB
CQ_PUSH     LDX  2,S
            JSR  GEN
            JSR  PUSHQ
            LDX  ,S
            JSR  GEN
            LDA  #OM_POP
            STA  <OPM
CQ_SUB      LDX  #S_SUBW
            LDA  #2
            JSR  LOPI
            LDX  #S_SBCD
            CLRA
            JSR  LOPI
            JSR  POPDROP
            LEAS 4,S
            LDB  ,S
            CMPB #O_EQ
            BEQ  CQ_ORR
            CMPB #O_NE
            BNE  CQ_RET
CQ_ORR      LDX  #S_ORRWD
            JSR  EMITL
CQ_RET      PULS B,X,PC
;------------------------------------------------------------------------------
; Structs.
;------------------------------------------------------------------------------
; x = y, of a struct: __scopy.
GS_ASSIGN   PSHS X
            LDX  N_L,X
            JSR  OPND
            BCS  GS2_PUSH
            LDX  ,S                    ; x where it is: y's address, then x's
            LDX  N_R,X
            JSR  GEN
            LDX  ,S
            LDX  N_L,X
            JSR  OPND
            JSR  ADDROPX
            BRA  GS2_CALL
GS2_PUSH    LDX  ,S                    ; y's address pushed, then x's
            LDX  N_R,X
            JSR  GEN
            LDX  #S_PSHSD
            JSR  EMITL
            LDX  ,S
            LDX  N_L,X
            JSR  GENADDR
            JSR  ADDROPX
            LDX  #S_PULSD
            JSR  EMITL
GS2_CALL    PULS X
            LDX  N_TYPE,X
; X = a struct type: JSR __scopy / FDB its size (X = where to, D = from).
SCOPY       PSHS X
            LDB  #7
            JSR  CALLHELP
            LDX  #S_FDB
            JSR  EMITI
            PULS X
            LDD  TY_SIZE,X
            JSR  OUTDEC
            JMP  OUTNL
; X = a struct type, its address in D: pushed, as an argument.
PUSHSTRUCT  PSHS X
            JSR  TWORDS
            LSLB
            ROLA
            LDX  #S_LEAS
            JSR  EMITI
            PSHS A
            LDA  #'-'
            JSR  OUTC
            PULS A
            JSR  OUTDEC
            LDX  #S_COMMAS
            JSR  OUTS
            JSR  OUTNL
            LDX  #S_TFRSX
            JSR  EMITL
            PULS X
            BRA  SCOPY
;------------------------------------------------------------------------------
S_2S        FCN  "2,S"
S_LDQ       FCN  "LDQ"
S_STQ       FCN  "STQ"
S_ADDW      FCN  "ADDW"
S_ADCD      FCN  "ADCD"
S_SUBW      FCN  "SUBW"
S_SBCD      FCN  "SBCD"
S_ANDD      FCN  "ANDD"
S_ORD       FCN  "ORD"
S_EORD      FCN  "EORD"
S_EXGDW     FCN  "EXG D,W"
S_ORRWD     FCN  "ORR W,D"
S_LEAS4     FCN  "LEAS 4,S"
S_TFRSX     FCN  "TFR S,X"
S_PUSHQ     FCN  "PSHSW"
            FCN  "PSHS D"
            FCB  0
S_POPQ      FCN  "PULS D"
            FCN  "PULSW"
            FCB  0
S_NEGQ      FCN  "COMD"
            FCN  "COMW"
            FCN  "ADDW #1"
            FCN  "ADCD #0"
            FCB  0
S_COMQ      FCN  "COMD"
            FCN  "COMW"
            FCB  0
S_SEXQ      FCN  "TFR D,W"
            FCN  "SEXW"
            FCB  0
S_ZEXQ      FCN  "TFR D,W"
            FCN  "CLRD"
            FCB  0
S_INCQ      FCN  "ADDW #1"
            FCN  "ADCD #0"
            FCB  0
S_DECQ      FCN  "SUBW #1"
            FCN  "SBCD #0"
            FCB  0
S_LSLQ      FCN  "ADDR W,W"            ; << 1
            FCN  "ROLD"
            FCB  0
            FCN  "ASRD"                ; >> 1, signed
            FCN  "RORW"
            FCB  0
            FCN  "LSRD"                ; >> 1, unsigned
            FCN  "RORW"
            FCB  0
S_SHL16     FCN  "TFR W,D"             ; << 16
            FCN  "CLRW"
            FCB  0
            FCN  "TFR D,W"             ; >> 16, signed
            FCN  "SEXW"
            FCB  0
            FCN  "TFR D,W"             ; >> 16, unsigned
            FCN  "CLRD"
            FCB  0
;------------------------------------------------------------------------------
; End of cc1_long.asm
;------------------------------------------------------------------------------
