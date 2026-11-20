;------------------------------------------------------------------------------
; cc1_sym.asm -- CC1: types, symbols and scopes.
;------------------------------------------------------------------------------
; The basic types (TY_* each; TY_PTR is filled in when a pointer to one is
; made).
TYP_VOID    FCB  TK_VOID,0
            FDB  0,0,0,0,0
TYP_CHAR    FCB  TK_CHAR,0
            FDB  0,1,0,0,0
TYP_SCHAR   FCB  TK_SCHAR,0
            FDB  0,1,0,0,0
TYP_UCHAR   FCB  TK_UCHAR,0
            FDB  0,1,0,0,0
TYP_INT     FCB  TK_INT,0
            FDB  0,2,0,0,0
TYP_UINT    FCB  TK_UINT,0
            FDB  0,2,0,0,0
TYP_LONG    FCB  TK_LONG,0
            FDB  0,4,0,0,0
TYP_ULONG   FCB  TK_ULONG,0
            FDB  0,4,0,0,0
TYP_FLOAT   FCB  TK_FLOAT,0
            FDB  0,4,0,0,0
TYP_BOOL    FCB  TK_UCHAR,TYF_BOOL
            FDB  0,1,0,0,0
;------------------------------------------------------------------------------
; Making types. Each takes X = a type -> X = the new one.
;------------------------------------------------------------------------------
; A pointer to X (one for each type, kept in its TY_PTR).
PTRTO       LDD  TY_PTR,X
            BEQ  PT_NEW
            TFR  D,X
            RTS
PT_NEW      PSHS X
            LDD  #TYSIZE
            JSR  ALLOC
            LDA  #TK_PTR
            STA  TY_KIND,X
            LDD  #2
            STD  TY_SIZE,X
            PULS Y
            STY  TY_BASE,X
            STX  TY_PTR,Y
            RTS
; An array of D (or $FFFF: no size given) of X.
ARRAYOF     PSHS D,X
            LDA  TY_KIND,X
            CMPA #TK_FUNC
            BEQ  AO_FUNC
            CMPA #TK_VOID
            BEQ  AO_VOID
            LDD  #TYSIZE
            JSR  ALLOC
            LDA  #TK_ARRAY
            STA  TY_KIND,X
            PULS D,Y
            STY  TY_BASE,X
            STD  TY_N,X
            CMPD #$FFFF
            BEQ  AO_NOSIZE
            MULD TY_SIZE,Y             ; the size: the count times the element's
            STW  TY_SIZE,X             ; (D is the count)
            RTS
AO_NOSIZE   CLRD
            STD  TY_SIZE,X
            LDA  #TYF_NOSIZE
            STA  TY_FL,X
            RTS
AO_FUNC     LDX  #M_ARRFUNC
            JMP  ERROR
AO_VOID     LDX  #M_ARRVOID
            JMP  ERROR
; A function returning X, with the parameters Y (a PL_ list).
FUNCOF      LDA  TY_KIND,X
            CMPA #TK_ARRAY
            BEQ  FO_BAD
            CMPA #TK_FUNC
            BEQ  FO_BAD
            PSHS X,Y
            LDD  #TYSIZE
            JSR  ALLOC
            LDA  #TK_FUNC
            STA  TY_KIND,X
            PULS D,Y
            STD  TY_BASE,X
            STY  TY_PAR,X
            RTS
FO_BAD      LDX  #M_FUNCRET
            JMP  ERROR
;------------------------------------------------------------------------------
; What a type is (X = it). Carry clear if so; they keep every register.
;------------------------------------------------------------------------------
; An integer: char to unsigned long.
TISINT      PSHS A
            LDA  TY_KIND,X
            CMPA #TK_CHAR
            BLO  TY_NO
            CMPA #TK_ULONG
            BHI  TY_NO
TY_YES      ANDCC #$FE
            PULS A,PC
TY_NO       ORCC #1
            PULS A,PC
TISCHAR     PSHS A
            LDA  TY_KIND,X
            CMPA #TK_CHAR
            BLO  TY_NO
            CMPA #TK_UCHAR
            BHI  TY_NO
            BRA  TY_YES
TISPTR      PSHS A
            LDA  TY_KIND,X
            CMPA #TK_PTR
            BEQ  TY_YES
            BRA  TY_NO
; An integer or a float.
TISARITH    PSHS A
            LDA  TY_KIND,X
            CMPA #TK_CHAR
            BLO  TY_NO
            CMPA #TK_FLOAT
            BHI  TY_NO
            BRA  TY_YES
TISFLOAT    PSHS A
            LDA  TY_KIND,X
            CMPA #TK_FLOAT
            BEQ  TY_YES
            BRA  TY_NO
; A value in Q: a long or a float.
TISQ        PSHS A
            LDA  TY_KIND,X
            CMPA #TK_LONG
            BLO  TY_NO
            CMPA #TK_FLOAT
            BHI  TY_NO
            BRA  TY_YES
; An integer, a float or a pointer.
TISSCALAR   PSHS A
            LDA  TY_KIND,X
            CMPA #TK_CHAR
            BLO  TY_NO
            CMPA #TK_PTR
            BHI  TY_NO
            BRA  TY_YES
; Unsigned (after the integer promotions, so unsigned char isn't): unsigned
; int or long, or a pointer.
TISUNS      PSHS A
            LDA  TY_KIND,X
            CMPA #TK_UINT
            BEQ  TY_YES
            CMPA #TK_ULONG
            BEQ  TY_YES
            CMPA #TK_PTR
            BEQ  TY_YES
            BRA  TY_NO
TISLONG     PSHS A
            LDA  TY_KIND,X
            CMPA #TK_LONG
            BEQ  TY_YES
            CMPA #TK_ULONG
            BEQ  TY_YES
            BRA  TY_NO
TISSTRUCT   PSHS A
            LDA  TY_KIND,X
            CMPA #TK_STRUCT
            BEQ  TY_YES
            BRA  TY_NO
TISBOOL     PSHS A
            LDA  TY_FL,X
            ANDA #TYF_BOOL
            PULS A
            BEQ  TB_NO
            ANDCC #$FE
            RTS
TB_NO       ORCC #1
            RTS
; -> A = how a scalar type X is held: 0 in D (16 bits or less), 1 a long in
; Q, 2 a float in Q. Keeps X.
TCLASS      CLRA
            JSR  TISQ
            BCS  TC_RET
            INCA
            JSR  TISFLOAT
            BCS  TC_RET
            INCA
TC_RET      RTS
; -> D = the words an argument of the type X takes on the stack (a long 2, a
; struct its size rounded up, anything else 1). Keeps X.
TWORDS      LDD  #2
            JSR  TISQ
            BCC  TW_RET
            JSR  TISSTRUCT
            BCC  TW_STRUCT
            LDD  #1
TW_RET      RTS
TW_STRUCT   LDD  TY_SIZE,X
            ADDD #1
            LSRA
            RORB
            RTS
; Z set if the types X and Y are the same (or close enough: an array of no
; size is the same as one with a size; a function's parameters aren't
; compared). Keeps X and Y.
TSAME       PSHS D,X,Y
TS_LOOP     PSHS X
            CMPY ,S++
            BEQ  TS_YES
            LDA  TY_KIND,X
            CMPA TY_KIND,Y
            BNE  TS_NO
            CMPA #TK_STRUCT            ; (a struct is only itself)
            BEQ  TS_NO
            CMPA #TK_PTR
            BEQ  TS_BASE
            CMPA #TK_FUNC
            BEQ  TS_BASE
            CMPA #TK_ARRAY
            BNE  TS_YES
            LDD  TY_N,X
            CMPD #$FFFF
            BEQ  TS_BASE
            LDD  TY_N,Y
            CMPD #$FFFF
            BEQ  TS_BASE
            CMPD TY_N,X
            BNE  TS_NO
TS_BASE     LDX  TY_BASE,X
            LDY  TY_BASE,Y
            BRA  TS_LOOP
TS_YES      ORCC #4
            PULS D,X,Y,PC
TS_NO       ANDCC #$FB
            PULS D,X,Y,PC
;------------------------------------------------------------------------------
; Symbols and scopes.
;------------------------------------------------------------------------------
; Y = a name, A = a kind (SK_*), X = a type -> X = a new symbol for them, in
; the current scope (it hides any other of that name until the scope ends).
; NEWTAG: a tag (SK_TAG, A = its keyword), which the name's NM_TAG means.
NEWTAG      STA  <TMPB
            LDA  #SK_TAG
            LDB  #NM_TAG
            BSR  NS_ANY
            LDB  <TMPB
            CLRA
            STD  SY_VAL,X
            RTS
NEWSYM      LDB  #NM_SYM
NS_ANY      PSHS B
            PSHS A,X,Y                 ; (5,S: where in the name it goes)
            LDD  #SYSIZE
            TST  <DEPTH
            BNE  NS_TEMP
            JSR  ALLOC
            BRA  NS_GOT
NS_TEMP     JSR  TALLOC
NS_GOT      LDY  3,S
            STY  SY_NAME,X
            LDB  5,S
            LEAY B,Y
            LDD  ,Y
            STD  SY_SHADOW,X
            STX  ,Y
            LDA  ,S
            STA  SY_KIND,X
            LDD  1,S
            STD  SY_TYPE,X
            LDA  <DEPTH
            STA  SY_DEPTH,X
            LDB  <DEPTH                ; onto the scope's list
            LSLB
            LDY  #SCOPES
            LEAY B,Y
            LDD  ,Y
            STD  SY_NEXT,X
            STX  ,Y
            LEAS 6,S
            RTS
; Y = a name -> X = the symbol of that name at file level; Z set if there's
; none.
GLOBALSYM   LDX  NM_SYM,Y
GS_LOOP     BEQ  GS_RET
            TST  SY_DEPTH,X
            BEQ  GS_FOUND
            LDX  SY_SHADOW,X
            BRA  GS_LOOP
GS_FOUND    ANDCC #$FB
GS_RET      RTS
; Y = a name, X = a type -> X = a new symbol at file level (SK_GLOBAL), even
; inside a function: it goes under the names' local ones.
NEWGLOBAL   TST  <DEPTH
            BNE  NG_DEEP
            LDA  #SK_GLOBAL
            JMP  NEWSYM
NG_DEEP     PSHS X,Y
            LDD  #SYSIZE
            JSR  ALLOC
            LDY  2,S
            STY  SY_NAME,X
            LDA  #SK_GLOBAL
            STA  SY_KIND,X
            LDD  ,S
            STD  SY_TYPE,X
            LDD  SCOPES                ; onto the file's list
            STD  SY_NEXT,X
            STX  SCOPES
            LDD  NM_SYM,Y              ; under the local ones of its name
            BNE  NG_UNDER
            STX  NM_SYM,Y
            BRA  NG_RET
NG_UNDER    TFR  D,Y
NG_LAST     LDD  SY_SHADOW,Y
            BEQ  NG_HERE
            TFR  D,Y
            BRA  NG_LAST
NG_HERE     STX  SY_SHADOW,Y
NG_RET      LEAS 4,S
            RTS
PUSHSCOPE   LDB  <DEPTH
            INCB
            CMPB #MAXDEPTH
            BHS  PS_DEEP
            STB  <DEPTH
            LSLB
            LDX  #SCOPES
            ABX
            CLRD
            STD  ,X
            RTS
PS_DEEP     LDX  #M_DEEP
            JMP  ERROR
; The scope ends: its names mean what they did before it.
POPSCOPE    LDB  <DEPTH
            LSLB
            LDX  #SCOPES
            ABX
            LDX  ,X
PO_LOOP     BEQ  PO_DONE
            LDY  SY_NAME,X
            LDA  SY_KIND,X
            CMPA #SK_TAG
            BNE  PO_SYM
            LEAY NM_TAG-NM_SYM,Y
PO_SYM      LDD  SY_SHADOW,X
            STD  NM_SYM,Y
            LDX  SY_NEXT,X
            BRA  PO_LOOP
PO_DONE     DEC  <DEPTH
            RTS
; -> D = a new label's number.
NEWLABEL    LDD  <LABELNO
            ADDD #1
            STD  <LABELNO
            RTS
;------------------------------------------------------------------------------
M_ARRFUNC   FCN  "array of functions"
M_ARRVOID   FCN  "array of void"
M_FUNCRET   FCN  "a function can't return an array or a function"
M_DEEP      FCN  "blocks nested too deeply"
;------------------------------------------------------------------------------
; End of cc1_sym.asm
;------------------------------------------------------------------------------
