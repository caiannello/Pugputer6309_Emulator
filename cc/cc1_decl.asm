;------------------------------------------------------------------------------
; cc1_decl.asm -- CC1: declarations (at file level and in blocks), function
; definitions, initializers, and the end of the file.
;------------------------------------------------------------------------------
SB_VOID     equ  1                 ; the type words (SPBITS)
SB_CHAR     equ  2
SB_SHORT    equ  4
SB_INT      equ  8
SB_SIGNED   equ  16
SB_UNS      equ  32
SB_LONG     equ  64
; The whole file, a declaration at a time.
PROGRAM     LDA  <TOK
            BEQ  PR_END
            JSR  EXTDECL
            BRA  PROGRAM
PR_END      JMP  FINISHFILE
;------------------------------------------------------------------------------
; Declaration specifiers -> DSTYPE, DSSC. Carry set if there were none.
;------------------------------------------------------------------------------
DECLSPEC    CLR  <DSSC
            CLR  <SPBITS
            CLR  <SPANY
            CLRD
            STD  <SPTDEF
DS_LOOP     LDA  <TOK
            LDX  #DSTAB
DS_FIND     TST  ,X
            BEQ  DS_OTHER
            CMPA ,X
            BEQ  DS_GOT
            LEAX 3,X
            BRA  DS_FIND
DS_GOT      LDA  1,X
            BEQ  DS_TAKEN              ; const, volatile: no matter
            CMPA #1
            BNE  DS_BIT
            TST  <DSSC                 ; a storage class
            LBNE DS_TWOSC
            LDA  2,X
            STA  <DSSC
            BRA  DS_TAKEN
DS_BIT      LDA  2,X                   ; a type word
            TST  <SPTDEF
            LBNE DS_BAD
            TST  <SPTDEF+1
            LBNE DS_BAD
            BITA <SPBITS
            LBNE DS_BAD
            ORA  <SPBITS
            STA  <SPBITS
DS_TAKEN    LDA  #1
            STA  <SPANY
            JSR  NEXT
            BRA  DS_LOOP
DS_OTHER    CMPA #T_ID                 ; a typedef's name (with nothing else)
            BNE  DS_NOTID
            TST  <SPBITS
            BNE  DS_END
            LDD  <SPTDEF
            BNE  DS_END
            LDX  <TOKV
            LDX  NM_SYM,X
            BEQ  DS_END
            LDA  SY_KIND,X
            CMPA #SK_TYPEDEF
            BNE  DS_END
            LDD  SY_TYPE,X
            STD  <SPTDEF
            BRA  DS_TAKEN
DS_NOTID    CMPA #K_STRUCT
            BEQ  DS_LATER
            CMPA #K_UNION
            BEQ  DS_LATER
            CMPA #K_ENUM
            BEQ  DS_LATER
            CMPA #K_FLOAT
            BEQ  DS_FLOAT
            CMPA #K_DOUBLE
            BEQ  DS_FLOAT
DS_END      TST  <SPANY
            BNE  DS_TYPE
            ORCC #1
            RTS
DS_TYPE     LDX  <SPTDEF               ; the type the words make
            BNE  DS_SET
            LDA  <SPBITS
            LDX  #TYP_VOID
            BITA #SB_VOID
            BNE  DS_SET
            BITA #SB_CHAR
            BEQ  DS_NCHAR
            LDX  #TYP_UCHAR
            BITA #SB_UNS
            BNE  DS_SET
            LDX  #TYP_SCHAR
            BITA #SB_SIGNED
            BNE  DS_SET
            LDX  #TYP_CHAR
            BRA  DS_SET
DS_NCHAR    BITA #SB_LONG              ; (long: CC's next phase)
            BEQ  DS_NLONG
            LDX  #M_NOLONG
            JMP  ERROR
DS_NLONG    LDX  #TYP_UINT
            BITA #SB_UNS
            BNE  DS_SET
            LDX  #TYP_INT
DS_SET      STX  <DSTYPE
            ANDCC #$FE
            RTS
DS_TWOSC    LDX  #M_TWOSC
            JMP  ERROR
DS_BAD      LDX  #M_BADTYPE
            JMP  ERROR
DS_LATER    LDX  #M_NOSTRUCT
            JMP  ERROR
DS_FLOAT    LDX  #M_FLOAT
            JMP  ERROR
DSTAB       FCB  K_TYPEDEF,1,SC_TYPEDEF
            FCB  K_EXTERN,1,SC_EXTERN
            FCB  K_STATIC,1,SC_STATIC
            FCB  K_AUTO,1,SC_AUTO
            FCB  K_REGISTER,1,SC_AUTO
            FCB  K_CONST,0,0
            FCB  K_VOLATILE,0,0
            FCB  K_VOID,2,SB_VOID
            FCB  K_CHAR,2,SB_CHAR
            FCB  K_SHORT,2,SB_SHORT
            FCB  K_INT,2,SB_INT
            FCB  K_SIGNED,2,SB_SIGNED
            FCB  K_UNSIGNED,2,SB_UNS
            FCB  K_LONG,2,SB_LONG
            FCB  0
; Carry clear if the current token begins declaration specifiers. Keeps X.
ISDECLSTART PSHS X
            LDA  <TOK
            CMPA #T_ID
            BEQ  DK_ID
            CMPA #K_STRUCT
            BEQ  DK_YES
            CMPA #K_UNION
            BEQ  DK_YES
            CMPA #K_ENUM
            BEQ  DK_YES
            CMPA #K_FLOAT
            BEQ  DK_YES
            CMPA #K_DOUBLE
            BEQ  DK_YES
            LDX  #DSTAB
DK_FIND     TST  ,X
            BEQ  DK_NOTONE
            CMPA ,X
            BEQ  DK_YES
            LEAX 3,X
            BRA  DK_FIND
DK_ID       LDX  <TOKV
            LDX  NM_SYM,X
            BEQ  DK_NOTONE
            LDA  SY_KIND,X
            CMPA #SK_TYPEDEF
            BNE  DK_NOTONE
DK_YES      ANDCC #$FE
            PULS X,PC
DK_NOTONE   ORCC #1
            PULS X,PC
;------------------------------------------------------------------------------
; A declarator, for the type DSTYPE -> DNAME (0: none; ABSTRACT says whether
; that may be), DTYPE. How it's written is collected on OPSTK (DCL), then made
; into the type (APPLYOPS).
;------------------------------------------------------------------------------
DECLARATOR  CLRD
            STD  <DNAME
            LDX  <OPTOP
            PSHS X
            JSR  DCL
            LDX  ,S
            LDY  <DSTYPE
            JSR  APPLYOPS
            STX  <DTYPE
            PULS X
            STX  <OPTOP
            RTS
; X = the first operation (to OPTOP), Y = the type they apply to -> X = the
; type.
APPLYOPS    PSHS X
            TFR  Y,X
AP_LOOP     LDY  ,S
            CMPY <OPTOP
            BHS  AP_DONE
            LEAY 3,Y
            STY  ,S
            LDA  -3,Y
            CMPA #DO_PTR
            BEQ  AP_PTR
            CMPA #DO_ARRAY
            BEQ  AP_ARR
            LDY  -2,Y                  ; a function: its parameters
            JSR  FUNCOF
            BRA  AP_LOOP
AP_PTR      JSR  PTRTO
            BRA  AP_LOOP
AP_ARR      LDD  -2,Y
            JSR  ARRAYOF
            BRA  AP_LOOP
AP_DONE     LEAS 2,S
            RTS
; One declarator's operations -> OPSTK, from OPTOP on, in the order they apply:
; the pointers, then what follows the name ([] and ()) backwards, then what
; was in parentheses around the name.
DCL         LDX  <OPTOP
            PSHS X                     ; S0
            CLR  ,-S                   ; how many pointers
DC_STAR     LDA  <TOK
            CMPA #'*'
            BNE  DC_QUAL
            INC  ,S
            JSR  NEXT
            BRA  DC_STAR
DC_QUAL     CMPA #K_CONST
            BEQ  DC_Q1
            CMPA #K_VOLATILE
            BNE  DC_DIRECT
DC_Q1       JSR  NEXT
            BRA  DC_STAR
DC_DIRECT   CMPA #'('
            BNE  DC_NAME
            TST  <ABSTRACT             ; with no name needed, "(" is a function's
            BEQ  DC_NEST               ; parameters, unless * ( [ or a name
            JSR  PEEK                  ; (not a type's) follows
            CMPA #'*'
            BEQ  DC_NEST
            CMPA #'('
            BEQ  DC_NEST
            CMPA #'['
            BEQ  DC_NEST
            CMPA #T_ID
            BNE  DC_SUFFIX
            LDX  <AHEADV
            LDX  NM_SYM,X
            BEQ  DC_NEST
            LDA  SY_KIND,X
            CMPA #SK_TYPEDEF
            BEQ  DC_SUFFIX
DC_NEST     JSR  NEXT
            JSR  DCL
            LDA  #')'
            JSR  EXPECT
            BRA  DC_SUFFIX
DC_NAME     CMPA #T_ID
            BNE  DC_SUFFIX
            LDD  <TOKV
            STD  <DNAME
            JSR  NEXT
DC_SUFFIX   LDX  <OPTOP
            PSHS X                     ; S1
DC_SLOOP    LDA  <TOK
            CMPA #'['
            BEQ  DC_ARRAY
            CMPA #'('
            BEQ  DC_FUNC
            BRA  DC_REORDER
DC_ARRAY    JSR  NEXT
            LDA  <TOK
            CMPA #']'
            BEQ  DC_ANOSZ
            JSR  CONSTEXPR
            TSTA
            BMI  DC_ANEG
            BRA  DC_AEND
DC_ANOSZ    LDD  #$FFFF
DC_AEND     PSHS D
            LDA  #']'
            JSR  EXPECT
            PULS X
            LDA  #DO_ARRAY
            JSR  PUSHOP
            BRA  DC_SLOOP
DC_ANEG     LDX  #M_NEGSIZE
            JMP  ERROR
DC_FUNC     JSR  NEXT
            JSR  PARAMS
            LDA  #DO_FUNC
            JSR  PUSHOP
            BRA  DC_SLOOP
DC_REORDER  LDY  <OPTOP                ; the order they apply in, built after
            LDB  2,S                   ; them, then moved back to S0
DR_PTRS     TSTB
            BEQ  DR_SUF
            JSR  OPROOM
            LDA  #DO_PTR
            STA  ,Y
            LEAY 3,Y
            DECB
            BRA  DR_PTRS
DR_SUF      LDX  <OPTOP
DR_SL       CMPX ,S
            BLS  DR_INNER
            LEAX -3,X
            JSR  OPCOPY
            LEAX -3,X
            BRA  DR_SL
DR_INNER    LDX  3,S
DR_IL       CMPX ,S
            BHS  DR_MOVE
            JSR  OPCOPY
            BRA  DR_IL
DR_MOVE     TFR  Y,D
            SUBD <OPTOP
            TFR  D,W
            LDX  <OPTOP
            LDY  3,S
            TSTW
            BEQ  DR_SET
            TFM  X+,Y+
DR_SET      STY  <OPTOP
            LEAS 5,S
            RTS
; The operation at X -> Y (both past it). Carry: no room is an error.
OPCOPY      JSR  OPROOM
            LDA  ,X+
            STA  ,Y+
            LDD  ,X++
            STD  ,Y++
            RTS
OPROOM      CMPY #OPSTK+OPSTKSZ-3
            BHS  OP_FULL
            RTS
OP_FULL     LDX  #M_DCLCOMPLEX
            JMP  ERROR
; A = an operation, X = its operand: onto OPSTK.
PUSHOP      LDY  <OPTOP
            BSR  OPROOM
            STA  ,Y+
            STX  ,Y++
            STY  <OPTOP
            RTS
; After "(": a function's parameters, to the ")" -> X = their list (PL_*).
PARAMS      LDX  <DSTYPE               ; (the declaration they're in)
            LDY  <DNAME
            LDA  <DSSC
            LDB  <ABSTRACT
            PSHS D,X,Y
            LDX  <PTTOP
            PSHS X                     ; P0: where the parameters go
            CLR  ,-S                   ; PL_FL
            LDA  <TOK
            CMPA #')'
            LBEQ PL2_END                ; (): no prototype
            LDA  #PLF_PROTO
            STA  ,S
            LDA  <TOK
            CMPA #K_VOID
            BNE  PL2_LOOP
            JSR  PEEK
            CMPA #')'
            BNE  PL2_LOOP
            JSR  NEXT                  ; (void)
            BRA  PL2_END
PL2_LOOP     LDA  <TOK
            CMPA #T_ELLIP
            BEQ  PL2_VAR
            JSR  DECLSPEC
            LBCS PL2_BAD
            LDA  #1
            STA  <ABSTRACT
            JSR  DECLARATOR
            LDX  <DTYPE                ; arrays and functions are passed as
            LDA  TY_KIND,X             ; pointers
            CMPA #TK_ARRAY
            BNE  PL2_FN
            LDX  TY_BASE,X
            JSR  PTRTO
            BRA  PL2_TYPE
PL2_FN       CMPA #TK_FUNC
            BNE  PL2_TYPE
            JSR  PTRTO
PL2_TYPE     LDY  <PTTOP
            CMPY #PTMP+PTMPSZ-4
            BHS  PL2_MANY
            STX  ,Y++
            LDD  <DNAME
            STD  ,Y++
            STY  <PTTOP
            LDA  <TOK
            CMPA #44
            BNE  PL2_END
            JSR  NEXT
            BRA  PL2_LOOP
PL2_VAR      JSR  NEXT
            LDA  ,S
            ORA  #PLF_VAR
            STA  ,S
PL2_END      LDA  #')'
            JSR  EXPECT
            LDD  <PTTOP                ; the list, from P0 to PTTOP
            SUBD 1,S
            PSHS D
            ADDD #PL_PAR
            JSR  ALLOC
            PULS D
            TFR  D,W
            LSRD
            LSRD
            STB  PL_N,X
            LDA  ,S
            STA  PL_FL,X
            LEAY PL_PAR,X
            PSHS X
            LDX  3,S
            STX  <PTTOP
            TSTW
            BEQ  PL2_COPIED
            TFM  X+,Y+
PL2_COPIED   PULS X
            LEAS 3,S
            PULS D
            STA  <DSSC
            STB  <ABSTRACT
            PULS Y
            STY  <DSTYPE
            PULS Y
            STY  <DNAME
            RTS
PL2_BAD      LDX  #M_PARAM
            JMP  ERROR
PL2_MANY     LDX  #M_MANYPAR
            JMP  ERROR
;------------------------------------------------------------------------------
; A declaration at file level (or a function's definition).
;------------------------------------------------------------------------------
EXTDECL     JSR  DECLSPEC
            BCC  ED_HAVE
            LDA  <TOK                  ; none: "f() {...}" is int, as of old
            CMPA #T_ID
            BNE  ED_SYNTAX
            LDX  #TYP_INT
            STX  <DSTYPE
            CLR  <DSSC
ED_HAVE     LDA  <TOK
            CMPA #';'
            BNE  ED_LOOP
            JMP  NEXT
ED_LOOP     CLR  <ABSTRACT
            JSR  DECLARATOR
            LDY  <DNAME
            BEQ  ED_NONAME
            LDA  <DSSC
            CMPA #SC_TYPEDEF
            BEQ  ED_TDEF
            LDX  <DTYPE
            LDA  TY_KIND,X
            CMPA #TK_FUNC
            BEQ  ED_FUNC
            JSR  DECLOBJ               ; an object
            LDA  <TOK
            CMPA #'='
            BNE  ED_NEXT
            PSHS X
            JSR  NEXT
            PULS X
            JSR  GLOBINIT
            BRA  ED_NEXT
ED_FUNC     JSR  DECLFUNC
            LDA  <TOK
            CMPA #'{'
            BNE  ED_NEXT
            JMP  FUNCDEF
ED_TDEF     JSR  DEFTYPEDEF
ED_NEXT     LDA  <TOK
            CMPA #44
            BNE  ED_END
            JSR  NEXT
            BRA  ED_LOOP
ED_END      LDA  #';'
            JMP  EXPECT
ED_NONAME   LDX  #M_NONAME
            JMP  ERROR
ED_SYNTAX   LDX  #M_DECL
            JMP  ERROR
; typedef: DNAME (Y) means DTYPE.
DEFTYPEDEF  LDX  NM_SYM,Y
            BEQ  DT_NEW
            LDA  SY_DEPTH,X            ; again in the same scope: the same type
            CMPA <DEPTH
            BNE  DT_NEW
            LDA  SY_KIND,X
            CMPA #SK_TYPEDEF
            BNE  DT_REDECL
            PSHS Y
            LDX  SY_TYPE,X
            LDY  <DTYPE
            JSR  TSAME
            PULS Y
            BNE  DT_REDECL
            RTS
DT_NEW      LDX  <DTYPE
            LDA  #SK_TYPEDEF
            JMP  NEWSYM
DT_REDECL   JMP  REDECL
; Y = DNAME is an object of type DTYPE at file level (or extern in a block)
; -> X = its symbol. Not extern: a definition (only tentative, so far).
DECLOBJ     JSR  GLOBALSYM
            BEQ  DO_NEW
            LDA  SY_KIND,X             ; declared before: the same type
            CMPA #SK_GLOBAL
            LBNE REDECL
            PSHS X,Y
            LDX  SY_TYPE,X
            LDY  <DTYPE
            JSR  TSAME
            PULS X,Y
            LBNE CONFLICT
            LDY  SY_TYPE,X             ; an array: the size, if this gives it
            LDA  TY_FL,Y
            BITA #TYF_NOSIZE
            BEQ  DO_FLAGS
            LDY  <DTYPE
            LDA  TY_FL,Y
            BITA #TYF_NOSIZE
            BNE  DO_FLAGS
            STY  SY_TYPE,X
            BRA  DO_FLAGS
DO_NEW      LDX  <DTYPE
            JSR  NEWGLOBAL
DO_FLAGS    LDA  <DSSC
            CMPA #SC_STATIC
            BNE  DO_NSTAT
            LDA  SY_FL,X
            ORA  #SF_STATIC
            STA  SY_FL,X
            LDA  <DSSC
DO_NSTAT    LDB  #SF_TENT
            CMPA #SC_EXTERN
            BNE  DO_SETFL
            LDB  #SF_EXTERN
DO_SETFL    ORB  SY_FL,X
            STB  SY_FL,X
            RTS
; Y = DNAME is a function of type DTYPE -> X = its symbol.
DECLFUNC    JSR  GLOBALSYM
            BEQ  DF_NEW
            LDA  SY_KIND,X
            CMPA #SK_GLOBAL
            LBNE REDECL
            PSHS X,Y
            LDX  SY_TYPE,X
            LDY  <DTYPE
            JSR  TSAME
            PULS X,Y
            LBNE CONFLICT
            LDY  SY_TYPE,X             ; a prototype now, where there was none:
            LDY  TY_PAR,Y              ; it's kept
            LDA  PL_FL,Y
            BITA #PLF_PROTO
            BNE  DF_FLAGS
            LDY  <DTYPE
            STY  SY_TYPE,X
            BRA  DF_FLAGS
DF_NEW      LDX  <DTYPE
            JSR  NEWGLOBAL
DF_FLAGS    LDA  <DSSC
            CMPA #SC_STATIC
            BNE  DF_RET
            LDA  SY_FL,X
            ORA  #SF_STATIC
            STA  SY_FL,X
DF_RET      RTS
REDECL      LDX  #M_REDECL
            JMP  ERRORN
CONFLICT    LDX  #M_CONFLICT
            JMP  ERRORN
;------------------------------------------------------------------------------
; Initializers at file level, and for static locals: data.
;------------------------------------------------------------------------------
; X = a symbol at file level, its initializer next: defined.
GLOBINIT    LDA  SY_FL,X
            BITA #SF_DEFINED
            BNE  GI_REDEF
            ORA  #SF_DEFINED
            ANDA #$FF-SF_TENT
            STA  SY_FL,X
            PSHS X
            LDA  #SEC_DATA
            JSR  SECT
            LDX  ,S
            JSR  EXPORTSYM
            LDX  ,S
            JSR  LABELSYM
            LDX  ,S
            LDX  SY_TYPE,X
            JSR  INITDATA
            PULS X
; An array that had no size has the one its initializer gave (D).
SIZEFROMINIT PSHS D
            LDY  SY_TYPE,X
            LDA  TY_FL,Y
            BITA #TYF_NOSIZE
            PULS D
            BEQ  GI_RET
            PSHS X
            LDX  TY_BASE,Y
            JSR  ARRAYOF
            TFR  X,Y
            PULS X
            STY  SY_TYPE,X
GI_RET      RTS
GI_REDEF    LDY  SY_NAME,X
            LDX  #M_REDEF
            JMP  ERRORN
; X = a type: its initializer -> data. -> D = the elements an array has.
INITDATA    LDA  TY_KIND,X
            CMPA #TK_ARRAY
            BEQ  IN_ARRAY
            LDA  <TOK                  ; a scalar, maybe in braces
            CMPA #'{'
            BNE  IN_SCALAR
            PSHS X
            JSR  NEXT
            PULS X
            JSR  INITDATA
            LDA  #'}'
            JMP  EXPECT
IN_SCALAR   PSHS X
            JSR  RESETNODES
            JSR  ASSIGNEXPR
            JSR  DECAY
            JSR  EVALCONST
            BCS  IN_NOTCONST
            PULS X
            JSR  TISCHAR
            BCS  IN_WORD
            LDD  <CVSYM                ; a char: a number
            BNE  IN_NOTCONST
            LDD  <CVLBL
            BNE  IN_NOTCONST
            LDX  #S_FCB
            JSR  EMITI
            LDD  <CVVAL
            CLRA
            JSR  OUTDEC
            JMP  OUTNL
IN_WORD     JSR  TISLONG
            BCC  IN_LONG
            LDX  #S_FDB
            JSR  EMITI
            JSR  OUTCONST
            JMP  OUTNL
IN_LONG     LDX  #M_NOTYET
            JMP  ERROR
IN_NOTCONST LDX  #M_NOTCONST
            JMP  ERROR
IN_ARRAY    LDY  TY_BASE,X             ; an array
            PSHS X,Y                   ; (the type, the element type)
            LDX  TY_BASE,X
            JSR  TISCHAR
            BCS  IN_BRACE
            LDA  <TOK
            CMPA #T_STR
            BNE  IN_BRACE
            LDX  ,S                    ; chars from a string
            LDD  TY_N,X
            CMPD #$FFFF
            BNE  IN_SSIZED
            LDD  <TOKSL
            ADDD #1
IN_SSIZED   PSHS D                     ; the array's size
            LDD  <TOKSL
            CMPD ,S
            BHI  IN_SLONG
            BEQ  IN_SBYTES
            ADDD #1                    ; with its NUL, if that fits
IN_SBYTES   LDX  <TOKSB
            JSR  EMITBYTES
            PSHS D
            LDD  2,S
            SUBD ,S++
            JSR  EMITZEROS
            JSR  NEXT
            PULS D
            LEAS 4,S
            RTS
IN_SLONG    LDX  #M_STRLONG
            JMP  ERROR
IN_BRACE    LDA  #'{'
            JSR  EXPECT
            CLRD
            PSHS D                     ; how many so far
IN_ELOOP    LDA  <TOK                  ; (,S: the count, 2,S: the type, 4,S:
            CMPA #'}'                  ; the element type)
            BEQ  IN_EEND
            LDX  2,S
            LDD  TY_N,X
            CMPD ,S
            BLS  IN_MANY
            LDX  4,S
            JSR  INITDATA
            LDD  ,S
            ADDD #1
            STD  ,S
            LDA  <TOK
            CMPA #44
            BNE  IN_EEND
            JSR  NEXT
            BRA  IN_ELOOP
IN_EEND     LDA  #'}'
            JSR  EXPECT
            LDX  2,S                   ; the rest: zeros
            LDD  TY_N,X
            CMPD #$FFFF
            BEQ  IN_ECOUNT
            SUBD ,S
            LDX  4,S
            MULD TY_SIZE,X
            TFR  W,D
            JSR  EMITZEROS
            LDX  2,S
            LDD  TY_N,X
            STD  ,S
IN_ECOUNT   PULS D
            LEAS 4,S
            RTS
IN_MANY     LDX  #M_MANYINIT
            JMP  ERROR
; The constant EVALCONST found -> the output (an FDB's operand).
OUTCONST    LDX  <CVSYM
            BEQ  OC_LBL
            JSR  OUTSYMNAME
            BRA  OC_OFF
OC_LBL      LDD  <CVLBL
            BEQ  OC_NUM
            JSR  OUTLBL
OC_OFF      LDD  <CVVAL                ; symbol+n, symbol-n
            BEQ  OC_RET
            BMI  OC_NUM
            LDA  #'+'
            JSR  OUTC
OC_NUM      LDD  <CVVAL
            JMP  OUTDEC
OC_RET      RTS
; X = bytes, D = how many: FCB lines (D and X kept).
EMITBYTES   PSHS D,X,Y
            TFR  D,Y
EB_LINE     CMPY #0
            BEQ  EB_RET
            LDX  #S_FCB
            JSR  EMITI
            LDB  #16                   ; up to 16 a line
            LDX  2,S
EB_BYTE     PSHS B
            LDB  ,X+
            CLRA
            JSR  OUTDEC
            PULS B
            LEAY -1,Y
            BEQ  EB_END
            DECB
            BEQ  EB_END
            LDA  #44
            JSR  OUTC
            BRA  EB_BYTE
EB_END      STX  2,S
            JSR  OUTNL
            BRA  EB_LINE
EB_RET      PULS D,X,Y,PC
; D = how many zero bytes (none if D <= 0): ZMB.
EMITZEROS   CMPD #0
            BLE  EZ_RET
            PSHS D
            LDX  #S_ZMB
            JSR  EMITI
            PULS D
            JSR  OUTDEC
            JMP  OUTNL
EZ_RET      RTS
;------------------------------------------------------------------------------
; A function's definition: X = its symbol, DTYPE its type (with the
; parameters' names), "{" next.
;------------------------------------------------------------------------------
FUNCDEF     LDA  SY_FL,X
            BITA #SF_DEFINED
            LBNE GI_REDEF
            ORA  #SF_DEFINED
            STA  SY_FL,X
            STX  <CURFUNC
            LDY  <DTYPE
            STY  SY_TYPE,X
            LDA  #SEC_CODE
            JSR  SECT
            LDX  <CURFUNC
            JSR  EXPORTSYM
            LDX  <CURFUNC
            JSR  LABELSYM
            LDX  #S_PSHSU
            JSR  EMITL
            LDX  #S_TFRSU
            JSR  EMITL
            JSR  NEWLABEL              ; LEAS -Ln,S: Ln is the frame's size
            STD  <FRMLBL
            LDX  #S_LEAS
            JSR  EMITI
            LDA  #'-'
            JSR  OUTC
            LDD  <FRMLBL
            JSR  OUTLBL
            LDX  #S_COMMAS
            JSR  OUTS
            JSR  OUTNL
            JSR  NEWLABEL
            STD  <RETLBL
            CLRD
            STD  <FRAMESZ
            STD  <MAXFRAME
            STD  <BRKLBL
            STD  <CONTLBL
            CLR  <NLABELS
            CLR  <INSWITCH
            JSR  PUSHSCOPE
            LDX  <DTYPE                ; the parameters: 4,U on, a word each (a
            LDX  TY_PAR,X              ; char in its second byte)
            LDB  PL_N,X
            LEAY PL_PAR,X
            LDX  #4
            PSHS B,X,Y
FD_PAR      TST  ,S
            BEQ  FD_BODY
            LDY  3,S
            LDX  ,Y
            LDY  2,Y
            BEQ  FD_NONAME
            LDA  #SK_LOCAL
            JSR  NEWSYM
            PSHS X
            LDX  SY_TYPE,X
            JSR  TISCHAR
            PULS X
            LDD  1,S
            BCS  FD_OFF
            ADDD #1
FD_OFF      STD  SY_VAL,X
            LDD  1,S
            ADDD #2
            STD  1,S
            LDD  3,S
            ADDD #4
            STD  3,S
            DEC  ,S
            BRA  FD_PAR
FD_NONAME   LDX  #M_PARNAME
            JMP  ERROR
FD_BODY     LEAS 5,S
            JSR  COMPOUND
            LDD  <RETLBL               ; the end
            JSR  LABELHERE
            LDX  #S_LEASU
            JSR  EMITL
            LDX  #S_PULSU
            JSR  EMITL
            LDD  <FRMLBL
            JSR  OUTLBL
            LDX  #S_EQU
            JSR  OUTS
            LDD  <MAXFRAME
            JSR  OUTDEC
            JSR  OUTNL
            JSR  CHECKLABELS
            JSR  POPSCOPE
            LDD  #STACKTOP-STACKSZ     ; its locals go
            STD  <HEAPHI
            CLRD
            STD  <CURFUNC
            RTS
;------------------------------------------------------------------------------
; A declaration in a block.
;------------------------------------------------------------------------------
LOCALDECL   JSR  DECLSPEC
            LDA  <TOK
            CMPA #';'
            BNE  LD_LOOP
            JMP  NEXT
LD_LOOP     CLR  <ABSTRACT
            JSR  DECLARATOR
            LDY  <DNAME
            LBEQ ED_NONAME
            LDA  <DSSC
            CMPA #SC_TYPEDEF
            BNE  LD_NTDEF
            JSR  DEFTYPEDEF
            BRA  LD_NEXT
LD_NTDEF    LDX  <DTYPE
            LDA  TY_KIND,X
            CMPA #TK_FUNC
            BNE  LD_NFUNC
            JSR  DECLFUNC              ; a function's prototype
            BRA  LD_NEXT
LD_NFUNC    LDA  <DSSC
            CMPA #SC_EXTERN
            BNE  LD_NEXTERN
            JSR  DECLOBJ
            BRA  LD_NEXT
LD_NEXTERN  LDX  NM_SYM,Y              ; not twice in a block
            BEQ  LD_FRESH
            LDA  SY_DEPTH,X
            CMPA <DEPTH
            LBEQ REDECL
LD_FRESH    LDA  <DSSC
            CMPA #SC_STATIC
            BNE  LD_AUTO
            JSR  STATLOCAL
            BRA  LD_NEXT
LD_AUTO     JSR  AUTOLOCAL
LD_NEXT     LDA  <TOK
            CMPA #44
            BNE  LD_END
            JSR  NEXT
            BRA  LD_LOOP
LD_END      LDA  #';'
            JMP  EXPECT
; A static in a block: Y = its name, DTYPE its type. Its storage is labelled
; Ln, in data or bss.
STATLOCAL   LDX  <DTYPE
            LDA  #SK_STATLOC
            JSR  NEWSYM
            LDA  #SF_DEFINED+SF_STATIC
            STA  SY_FL,X
            PSHS X
            JSR  NEWLABEL
            PULS X
            STD  SY_VAL,X
            LDA  <TOK
            CMPA #'='
            BNE  SL_BSS
            PSHS X
            JSR  NEXT
            LDA  #SEC_DATA
            JSR  SECT
            LDX  ,S
            JSR  LABELSYM
            LDX  ,S
            LDX  SY_TYPE,X
            JSR  INITDATA
            PULS X
            JSR  SIZEFROMINIT
            BRA  SL_CODE
SL_BSS      PSHS X
            LDA  #SEC_BSS
            JSR  SECT
            PULS X
            JSR  RMBSYM
SL_CODE     LDA  #SEC_CODE
            JMP  SECT
; An automatic local: Y = its name, DTYPE its type. It gets a place in the
; frame (n,U, below U); an initializer is code.
AUTOLOCAL   LDX  <DTYPE
            LDA  TY_FL,X
            BITA #TYF_NOSIZE
            BEQ  AU_SIZED
            LDA  <TOK                  ; char s[] = "...": the string's size
            CMPA #'='
            BNE  AU_NOSIZE
            PSHS X,Y
            JSR  PEEK
            PULS X,Y
            CMPA #T_STR
            BNE  AU_NOSIZE
            LDD  <AHEADSL
            ADDD #1
            PSHS Y
            LDX  TY_BASE,X
            JSR  ARRAYOF
            PULS Y
AU_SIZED    LDD  TY_SIZE,X
            BEQ  AU_NOSIZE
            ADDD <FRAMESZ
            STD  <FRAMESZ
            CMPD <MAXFRAME
            BLS  AU_MAX
            STD  <MAXFRAME
AU_MAX      LDA  #SK_LOCAL
            JSR  NEWSYM
            CLRD
            SUBD <FRAMESZ
            STD  SY_VAL,X
            LDA  <TOK
            CMPA #'='
            BNE  AU_RET
            PSHS X
            JSR  NEXT
            PULS X
            LDD  SY_VAL,X
            LDX  SY_TYPE,X
            JMP  LINIT
AU_RET      RTS
AU_NOSIZE   LDX  #M_NOSIZE
            JMP  ERRORN
; A local's initializer: X = the type, D = where (n,U).
LINIT       PSHS D,X
            LDA  TY_KIND,X
            CMPA #TK_ARRAY
            BEQ  LI_ARRAY
            LDA  <TOK                  ; a scalar, maybe in braces
            CMPA #'{'
            BNE  LI_SCALAR
            JSR  NEXT
            PULS D,X
            JSR  LINIT
            LDA  #'}'
            JMP  EXPECT
LI_SCALAR   JSR  RESETNODES
            LDA  #O_FRAME              ; its place = the expression
            JSR  NEWNODE
            LDD  ,S
            STD  N_V,X
            LDD  2,S
            STD  N_TYPE,X
            LDA  #NF_LVAL
            STA  N_FL,X
            PSHS X
            JSR  ASSIGNEXPR
            TFR  X,Y
            PULS X
            JSR  MKASSIGN
            JSR  GENVOID
            PULS D,X,PC
LI_ARRAY    LDX  2,S                   ; an array: 2,S = its type, ,S = where
            LDX  TY_BASE,X
            JSR  TISCHAR
            LBCS LI_BRACE
            LDA  <TOK
            CMPA #T_STR
            LBNE LI_BRACE
            LDX  2,S                   ; chars from a string: copied from one
            LDD  <TOKSL                ; in rodata
            CMPD TY_N,X
            LBHI IN_SLONG
            BEQ  LI_SNONUL
            ADDD #1
LI_SNONUL   PSHS D                     ; the bytes copied
            JSR  EMITSTRING            ; -> D = its label
            PSHS D
            LDX  #S_PSHSY
            JSR  EMITL
            LDX  #S_LDX
            JSR  EMITI
            LDA  #'#'
            JSR  OUTC
            PULS D
            JSR  OUTLBL
            JSR  OUTNL
            LDX  #S_LEAY
            JSR  EMITI
            LDD  2,S
            JSR  OUTDEC
            LDX  #S_COMMAU
            JSR  OUTS
            JSR  OUTNL
            LDX  #S_LDW
            JSR  EMITI
            LDA  #'#'
            JSR  OUTC
            LDD  ,S
            JSR  OUTDEC
            JSR  OUTNL
            LDX  #S_TFMXY
            JSR  EMITL
            LDX  4,S                   ; the rest: the NUL again, from X-1
            LDD  TY_N,X
            SUBD ,S++
            BEQ  LI_SDONE
            PSHS D
            LDX  #S_LEAXM1
            JSR  EMITL
            LDX  #S_LDW
            JSR  EMITI
            LDA  #'#'
            JSR  OUTC
            PULS D
            JSR  OUTDEC
            JSR  OUTNL
            LDX  #S_TFMX1
            JSR  EMITL
LI_SDONE    LDX  #S_PULSY
            JSR  EMITL
            JSR  NEXT
            PULS D,X,PC
LI_BRACE    LDA  #'{'
            JSR  EXPECT
            CLRD
            PSHS D                     ; elements so far
LI_ELOOP    LDA  <TOK
            CMPA #'}'
            BEQ  LI_EEND
            LDX  4,S
            LDD  TY_N,X
            CMPD ,S
            LBLS IN_MANY
            LDY  TY_BASE,X             ; this one's place: where + n * its size
            LDD  TY_SIZE,Y
            MULD ,S
            TFR  W,D
            ADDD 2,S
            TFR  Y,X
            JSR  LINIT
            LDD  ,S
            ADDD #1
            STD  ,S
            LDA  <TOK
            CMPA #44
            BNE  LI_EEND
            JSR  NEXT
            BRA  LI_ELOOP
LI_EEND     LDA  #'}'
            JSR  EXPECT
            LDX  4,S                   ; the rest: zeros
            LDY  TY_BASE,X
            LDD  TY_SIZE,Y
            MULD ,S
            TFR  W,D                   ; the bytes done
            PSHS D
            ADDD 4,S
            TFR  D,Y                   ; where the rest starts
            LDD  TY_SIZE,X
            SUBD ,S++
            JSR  ZEROFILL
            PULS D
            PULS D,X,PC
; D = how many bytes, Y = where (n,U): code making them zeros.
ZEROFILL    CMPD #0
            BLE  ZF_RET
            CMPD #6
            BHI  ZF_TFM
ZF_CLR      PSHS D,Y                   ; a few: CLR n,U each
            LDX  #S_CLR
            JSR  EMITI
            LDD  2,S
            JSR  OUTDEC
            LDX  #S_COMMAU
            JSR  OUTS
            JSR  OUTNL
            PULS D,Y
            LEAY 1,Y
            SUBD #1
            BNE  ZF_CLR
ZF_RET      RTS
ZF_TFM      PSHS D,Y                   ; more: TFM from a zero on the stack
            LDX  #S_PSHSY
            JSR  EMITL
            LDX  #S_LEAY
            JSR  EMITI
            LDD  2,S
            JSR  OUTDEC
            LDX  #S_COMMAU
            JSR  OUTS
            JSR  OUTNL
            LDX  #S_LDW
            JSR  EMITI
            LDA  #'#'
            JSR  OUTC
            LDD  ,S
            JSR  OUTDEC
            JSR  OUTNL
            LDX  #S_ZEROTFM
            JSR  EMITLINES
            PULS D,Y,PC
;------------------------------------------------------------------------------
; The goto labels: Y = a name, A = 1 if it's being defined -> D = its label.
;------------------------------------------------------------------------------
FINDLABEL   PSHS A
            LDX  #LABELS
            LDB  <NLABELS
FL_LOOP     TSTB
            BEQ  FL_NEW
            CMPY ,X
            BEQ  FL_FOUND
            LEAX 5,X
            DECB
            BRA  FL_LOOP
FL_FOUND    PULS A
            TSTA
            BEQ  FL_RET
            TST  4,X
            BNE  FL_TWICE
            STA  4,X
FL_RET      LDD  2,X
            RTS
FL_TWICE    LDX  #M_LBLTWICE
            JMP  ERRORN
FL_NEW      LDA  <NLABELS
            CMPA #MAXLABELS
            BHS  FL_MANY
            INC  <NLABELS
            STY  ,X
            PSHS X
            JSR  NEWLABEL
            PULS X
            STD  2,X
            PULS A
            STA  4,X
            RTS
FL_MANY     LDX  #M_MANYLBL
            JMP  ERROR
CHECKLABELS LDX  #LABELS
            LDB  <NLABELS
CK_LOOP     TSTB
            BEQ  CK_RET
            TST  4,X
            BEQ  CK_UNDEF
            LEAX 5,X
            DECB
            BRA  CK_LOOP
CK_UNDEF    LDY  ,X
            LDX  #M_NOLABEL
            JMP  ERRORN
CK_RET      RTS
;------------------------------------------------------------------------------
; The end of the file: the tentative definitions (int x;) in bss, IMPORT for
; what's used and not here, and the library's helpers used.
;------------------------------------------------------------------------------
FINISHFILE  LDX  SCOPES
FF_LOOP     BEQ  FF_HELP
            LDA  SY_KIND,X
            CMPA #SK_GLOBAL
            BNE  FF_NEXT
            LDA  SY_FL,X
            BITA #SF_DEFINED
            BNE  FF_NEXT
            BITA #SF_TENT
            BNE  FF_TENT
            BITA #SF_USED
            BEQ  FF_NEXT
            PSHS X
            LDX  #S_IMPORT
            JSR  EMITI
            LDX  ,S
            JSR  OUTSYMNAME
            JSR  OUTNL
            PULS X
            BRA  FF_NEXT
FF_TENT     PSHS X
            LDA  #SEC_BSS
            JSR  SECT
            LDX  ,S
            JSR  EXPORTSYM
            PULS X
            JSR  RMBSYM
FF_NEXT     LDX  SY_NEXT,X
            BRA  FF_LOOP
FF_HELP     LDX  #HELPNAMES
            LDB  #1
FF_HLOOP    TST  ,X
            BEQ  FF_RET
            BITB <HELPERS
            BEQ  FF_HSKIP
            PSHS B,X
            LDX  #S_IMPORT
            JSR  EMITI
            LDX  1,S
            JSR  OUTS
            JSR  OUTNL
            PULS B,X
FF_HSKIP    TST  ,X+
            BNE  FF_HSKIP
            LSLB
            BRA  FF_HLOOP
FF_RET      RTS
; X = a symbol: "NAME RMB size". Keeps X.
RMBSYM      JSR  OUTSYMNAME
            PSHS X
            LDX  #S_RMB
            JSR  OUTS
            LDX  ,S
            LDX  SY_TYPE,X
            LDD  TY_SIZE,X
            BNE  RS_SIZE
            LDD  #1
RS_SIZE     JSR  OUTDEC
            JSR  OUTNL
            PULS X,PC
; X = a symbol: " EXPORT _name", unless it's static.
EXPORTSYM   LDA  SY_FL,X
            BITA #SF_STATIC
            BNE  ES_RET
            PSHS X
            LDX  #S_EXPORT
            JSR  EMITI
            PULS X
            JSR  OUTSYMNAME
            JMP  OUTNL
ES_RET      RTS
; X = a symbol: its label, on a line of its own.
LABELSYM    JSR  OUTSYMNAME
            JMP  OUTNL
;------------------------------------------------------------------------------
M_TWOSC     FCN  "more than one storage class"
M_BADTYPE   FCN  "invalid type"
M_NOTYET    FCN  "not supported yet"
M_NOLONG    FCN  "long is not supported yet"
M_NOSTRUCT  FCN  "struct, union and enum are not supported yet"
M_NEGSIZE   FCN  "array size is negative"
M_DCLCOMPLEX FCN "declaration too complex"
M_PARAM     FCN  "a parameter declaration was expected"
M_MANYPAR   FCN  "too many parameters"
M_NONAME    FCN  "a name was expected in the declaration"
M_DECL      FCN  "a declaration was expected"
M_REDECL    FCN  "redeclared:"
M_CONFLICT  FCN  "conflicting types for"
M_REDEF     FCN  "redefinition of"
M_NOTCONST  FCN  "initializer is not a constant"
M_STRLONG   FCN  "string too long for its array"
M_MANYINIT  FCN  "too many initializers"
M_PARNAME   FCN  "a parameter has no name"
M_NOSIZE    FCN  "no size for"
M_LBLTWICE  FCN  "label defined twice:"
M_MANYLBL   FCN  "too many labels in one function"
M_NOLABEL   FCN  "label used but not defined:"
S_FCB       FCN  "FCB"
S_FDB       FCN  "FDB"
S_ZMB       FCN  "ZMB"
S_RMB       FCN  " RMB "
S_EQU       FCN  " EQU "
S_IMPORT    FCN  "IMPORT"
S_EXPORT    FCN  "EXPORT"
S_PSHSU     FCN  "PSHS U"
S_TFRSU     FCN  "TFR S,U"
S_LEAS      FCN  "LEAS"
S_COMMAS    FCN  ",S"
S_COMMAU    FCN  ",U"
S_LEASU     FCN  "LEAS ,U"
S_PULSU     FCN  "PULS U,PC"
S_PSHSY     FCN  "PSHS Y"
S_PULSY     FCN  "PULS Y"
S_LDX       FCN  "LDX"
S_LEAY      FCN  "LEAY"
S_LDW       FCN  "LDW"
S_CLR       FCN  "CLR"
S_TFMXY     FCN  "TFM X+,Y+"
S_TFMX1     FCN  "TFM X,Y+"
S_LEAXM1    FCN  "LEAX -1,X"
S_ZEROTFM   FCN  "CLR ,-S"             ; (EMITLINES: lines until an empty one)
            FCN  "TFR S,X"
            FCN  "TFM X,Y+"
            FCN  "LEAS 1,S"
            FCN  "PULS Y"
            FCB  0
;------------------------------------------------------------------------------
; End of cc1_decl.asm
;------------------------------------------------------------------------------
