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
            CLR  <DSINTR
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
            CMPA #3
            BNE  DS_NINTR
            STA  <DSINTR               ; interrupt
            BRA  DS_TAKEN
DS_NINTR    CMPA #1
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
            BEQ  DS_STRUCT
            CMPA #K_UNION
            BEQ  DS_STRUCT
            CMPA #K_ENUM
            BEQ  DS_ENUM
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
DS_NCHAR    BITA #SB_LONG
            BEQ  DS_NLONG
            BITA #SB_SHORT
            BNE  DS_BAD
            LDX  #TYP_ULONG
            BITA #SB_UNS
            BNE  DS_SET
            LDX  #TYP_LONG
            BRA  DS_SET
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
DS_STRUCT   JSR  DS_ALONE              ; struct / union: the type
            JSR  STRUCTSPEC
            BRA  DS_SPEC
DS_ENUM     JSR  DS_ALONE              ; enum: int
            JSR  ENUMSPEC
DS_SPEC     STX  <SPTDEF
            LDA  #1
            STA  <SPANY
            JMP  DS_LOOP
DS_ALONE    TST  <SPBITS               ; (with no other type)
            BNE  DS_BAD
            LDD  <SPTDEF
            BNE  DS_BAD
            RTS
DS_FLOAT    LDX  #M_FLOAT
            JMP  ERROR
DSTAB       FCB  K_TYPEDEF,1,SC_TYPEDEF
            FCB  K_INTERRUPT,3,0
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
; struct, union and enum.
;------------------------------------------------------------------------------
DECLSZ      equ  DSINTR+1-DSTYPE
; SAVEDECL: the declaration being read (DSTYPE to DSINTR) onto the stack,
; under the return address. RESTDECL: back (from there).
SAVEDECL    PULS X
            LEAS -DECLSZ,S
            PSHS X,Y
            LEAY 4,S
            LDX  #DSTYPE
            LDW  #DECLSZ
            TFM  X+,Y+
            PULS X,Y
            JMP  ,X
RESTDECL    PULS X
            PSHS X,Y
            LEAX 4,S
            LDY  #DSTYPE
            LDW  #DECLSZ
            TFM  X+,Y+
            PULS X,Y
            LEAS DECLSZ,S
            JMP  ,X
; struct or union (the token), its tag and/or its members -> X = the type.
STRUCTSPEC  JSR  SAVEDECL
            LDA  <TOK
            PSHS A                     ; 2,S: the keyword
            JSR  NEXT
            CLRD
            PSHS D                     ; ,S: the tag (0: none)
            LDA  <TOK
            CMPA #T_ID
            BNE  SS_NONAME
            LDD  <TOKV
            STD  ,S
            JSR  NEXT
            LDY  ,S
            LDX  NM_TAG,Y
            LDA  <TOK
            CMPA #'{'
            BEQ  SS_DEFINE
            CMPA #';'
            BEQ  SS_DECL
            CMPX #0                    ; struct tag: the one it means now, or a
            BNE  SS_FOUND              ; new one here
SS_NEW      BSR  SS_TAG
            BRA  SS_END
SS_DECL     CMPX #0                    ; struct tag; : one here
            BEQ  SS_NEW
            LDA  SY_DEPTH,X
            CMPA <DEPTH
            BNE  SS_NEW
SS_FOUND    LDA  SY_VAL+1,X            ; (a tag of the same kind)
            CMPA 2,S
            BNE  SS_WRONG
            LDX  SY_TYPE,X
            BRA  SS_END
SS_DEFINE   CMPX #0                    ; struct tag {: the one here, if it was
            BEQ  SS_DNEW               ; only declared, or a new one
            LDA  SY_DEPTH,X
            CMPA <DEPTH
            BNE  SS_DNEW
            LDA  SY_VAL+1,X
            CMPA 2,S
            BNE  SS_WRONG
            LDX  SY_TYPE,X
            LDA  TY_FL,X
            BITA #TYF_NOSIZE
            BNE  SS_BODY
            LDY  ,S
            LDX  #M_REDEF
            JMP  ERRORN
SS_DNEW     BSR  SS_TAG
            BRA  SS_BODY
SS_NONAME   LDA  <TOK                  ; struct {: no tag
            CMPA #'{'
            LBNE EP_ID
            LDA  2,S
            BSR  NEWSTYPE
SS_BODY     JSR  MEMBERS
SS_END      STX  <TMP2
            LEAS 3,S
            JSR  RESTDECL
            LDX  <TMP2
            RTS
SS_WRONG    LDY  ,S
            LDX  #M_WRONGTAG
            JMP  ERRORN
; A new type, and the tag (,S+2 on entry) for it here -> X = the type.
SS_TAG      LDA  4,S
            BSR  NEWSTYPE
            PSHS X
            LDY  4,S
            LDA  6,S
            JSR  NEWTAG
            PULS X,PC
; A = K_STRUCT or K_UNION -> X = a new type for it, not yet defined.
NEWSTYPE    PSHS A
            LDD  #TYSIZE
            JSR  ALLOC
            LDA  #TK_STRUCT
            STA  TY_KIND,X
            LDB  #TYF_NOSIZE
            PULS A
            CMPA #K_UNION
            BNE  NT_FL
            ORB  #TYF_UNION
NT_FL       STB  TY_FL,X
            RTS
; X = a struct type, "{" next: its members, to the "}" (and past it).
MEMBERS     PSHS X                     ; 2,S: the type
            CLRD
            PSHS D                     ; ,S: the last member so far
            JSR  NEXT
MS_DECL     LDA  <TOK
            CMPA #'}'
            LBEQ MS_END
            JSR  DECLSPEC
            LBCS MS_BAD
            LDA  <DSSC
            LBNE MS_BAD
            LDA  <TOK
            CMPA #';'
            LBEQ MS_SEMI
MS_LOOP     CLR  <ABSTRACT
            JSR  DECLARATOR
            LDY  <DNAME
            LBEQ ED_NONAME
            LDA  <TOK
            CMPA #':'
            LBEQ MS_BITS
            LDX  <DTYPE                ; it needs a size
            LDA  TY_KIND,X
            CMPA #TK_FUNC
            LBEQ MS_FUNC
            LDA  TY_FL,X
            BITA #TYF_NOSIZE
            LBNE MS_NOSIZE
            LDD  TY_SIZE,X
            LBEQ MS_NOSIZE
            LDX  2,S                   ; not twice
            LDX  TY_PAR,X
MS_DUP      BEQ  MS_NEW
            CMPY ME_NAME,X
            LBEQ MS_TWICE
            LDX  ME_NEXT,X
            BRA  MS_DUP
MS_NEW      LDD  #MESIZE
            JSR  ALLOC
            STY  ME_NAME,X
            LDY  <DTYPE
            STY  ME_TYPE,X
            LDY  2,S
            LDA  TY_FL,Y
            BITA #TYF_UNION
            BNE  MS_UNION
            LDD  TY_SIZE,Y             ; a struct's: after the others
            STD  ME_OFF,X
            PSHS X
            LDX  <DTYPE
            ADDD TY_SIZE,X
            STD  TY_SIZE,Y
            PULS X
            BRA  MS_LINK
MS_UNION    PSHS X                     ; a union's: at 0, the size the largest
            LDX  <DTYPE
            LDD  TY_SIZE,X
            CMPD TY_SIZE,Y
            BLS  MS_USIZE
            STD  TY_SIZE,Y
MS_USIZE    PULS X
MS_LINK     LDY  ,S
            BEQ  MS_FIRST
            STX  ME_NEXT,Y
            BRA  MS_LAST
MS_FIRST    LDY  2,S
            STX  TY_PAR,Y
MS_LAST     STX  ,S
            LDA  <TOK
            CMPA #44
            BNE  MS_SEMI
            JSR  NEXT
            LBRA MS_LOOP
MS_SEMI     LDA  #';'
            JSR  EXPECT
            LBRA MS_DECL
MS_END      JSR  NEXT
            PULS D,X
            LDD  TY_PAR,X
            BEQ  MS_EMPTY
            LDA  TY_FL,X
            ANDA #$FF-TYF_NOSIZE
            STA  TY_FL,X
            RTS
MS_BAD      LDX  #M_MEMBER
            JMP  ERROR
MS_BITS     LDX  #M_BITFIELD
            JMP  ERROR
MS_FUNC     LDX  #M_MEMFUNC
            JMP  ERRORN
MS_NOSIZE   LDX  #M_NOSIZE
            JMP  ERRORN
MS_TWICE    LDX  #M_MEMTWICE
            JMP  ERRORN
MS_EMPTY    LDX  #M_NOMEMBERS
            JMP  ERROR
; X = a struct type, Y = a name -> X = its member of that name.
FINDMEMBER  LDA  TY_FL,X
            BITA #TYF_NOSIZE
            BNE  FM_UNDEF
            LDX  TY_PAR,X
FM_LOOP     BEQ  FM_NONE
            CMPY ME_NAME,X
            BEQ  FM_RET
            LDX  ME_NEXT,X
            BRA  FM_LOOP
FM_RET      RTS
FM_NONE     LDX  #M_NOMEMB
            JMP  ERRORN
FM_UNDEF    LDX  #M_UNDEFSTR
            JMP  ERROR
; enum, its tag and/or its constants -> X = the type (int).
ENUMSPEC    JSR  NEXT
            LDA  <TOK
            CMPA #T_ID
            BNE  EN_BODY
            LDY  <TOKV
            PSHS Y
            JSR  NEXT
            PULS Y
            LDX  NM_TAG,Y
            LDA  <TOK
            CMPA #'{'
            BEQ  EN_DEFINE
            CMPX #0                    ; enum tag: an enum's, if it's known
            LBEQ EN_INT
            LDA  SY_VAL+1,X
            CMPA #K_ENUM
            BEQ  EN_INT
            LDX  #M_WRONGTAG
            JMP  ERRORN
EN_DEFINE   CMPX #0                    ; enum tag {: once in a scope
            BEQ  EN_TAG
            LDA  SY_DEPTH,X
            CMPA <DEPTH
            BNE  EN_TAG
            LDX  #M_REDEF
            JMP  ERRORN
EN_TAG      LDX  #TYP_INT
            LDA  #K_ENUM
            JSR  NEWTAG
EN_BODY     LDA  #'{'
            JSR  EXPECT
            CLRD
            PSHS D                     ; the next constant's value
EN_LOOP     LDA  <TOK
            CMPA #'}'
            BEQ  EN_END
            CMPA #T_ID
            LBNE EP_ID
            LDY  <TOKV
            PSHS Y
            JSR  NEXT
            LDA  <TOK
            CMPA #'='
            BNE  EN_VAL
            JSR  NEXT
            JSR  CONSTEXPR
            STD  2,S
EN_VAL      PULS Y
            LDX  NM_SYM,Y              ; once in a scope
            BEQ  EN_NEW
            LDA  SY_DEPTH,X
            CMPA <DEPTH
            LBEQ REDECL
EN_NEW      LDX  #TYP_INT
            LDA  #SK_ENUMC
            JSR  NEWSYM
            LDD  ,S
            STD  SY_VAL,X
            ADDD #1
            STD  ,S
            LDA  <TOK
            CMPA #44
            BNE  EN_END
            JSR  NEXT
            BRA  EN_LOOP
EN_END      LEAS 2,S
            LDA  #'}'
            JSR  EXPECT
EN_INT      LDX  #TYP_INT
            RTS
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
PARAMS      LDA  <DSINTR               ; (the declaration they're in)
            PSHS A
            LDX  <DSTYPE
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
            PULS A
            STA  <DSINTR
            RTS
PL2_BAD      LDX  #M_PARAM
            JMP  ERROR
PL2_MANY     LDX  #M_MANYPAR
            JMP  ERROR
;------------------------------------------------------------------------------
; A declaration at file level (or a function's definition).
;------------------------------------------------------------------------------
EXTDECL     LDA  <TOK                  ; asm { } (in code)
            CMPA #K_ASM
            LBEQ ST_ASM
            JSR  DECLSPEC
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
            TST  <DSINTR
            BEQ  ED_NINTR
            LDA  SY_FL,X
            ORA  #SF_INTR
            STA  SY_FL,X
ED_NINTR    LDA  <TOK
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
;------------------------------------------------------------------------------
; Initializers. One walk does both kinds: IMODE 0 writes data (FCB, FDB, ZMB)
; where the output is; IMODE 1 writes code storing into the frame at IBASE
; (n,U). The object's bytes are done in order (IDONE: how many so far), so a
; gap (what an initializer leaves out) is zeros: FILLTO.
;------------------------------------------------------------------------------
; X = a type: its initializer -> data. -> D = the elements an array has.
INITDATA    CLR  <IMODE
            CLRD
            STD  <IDONE
            JMP  INIT
; A local's initializer: X = the type, D = where (n,U). A struct may be given
; an expression of its type.
LINIT       STD  <IBASE
            LDA  #1
            STA  <IMODE
            CLRD
            STD  <IDONE
            JSR  TISSTRUCT
            BCS  LT_INIT
            LDA  <TOK
            CMPA #'{'
            BEQ  LT_INIT
            CLRD
            JMP  ISCALAR
LT_INIT     CLRD
            JMP  INIT
; X = a type, D = its offset in the object: one initializer for it. -> D = how
; many elements (an array's; 1 for anything else).
INIT        PSHS D,X                   ; (,S the offset, 2,S the type)
            LDA  TY_KIND,X
            CMPA #TK_ARRAY
            BEQ  IT_ARRAY
            CMPA #TK_STRUCT
            BEQ  IT_AGG
            LDA  <TOK                  ; a scalar, maybe in braces
            CMPA #'{'
            BNE  IT_SCALAR
            JSR  NEXT
            PULS D,X
            BSR  INIT
            LDA  #44
            JSR  ACCEPT
            LDA  #'}'
            JSR  EXPECT
            LDD  #1
            RTS
IT_SCALAR   PULS D,X
            JSR  ISCALAR
            LDD  #1
            RTS
IT_ARRAY    LDX  TY_BASE,X             ; chars from a string, maybe in braces?
            JSR  TISCHAR
            BCS  IT_AGG
            LDA  <TOK
            CMPA #T_STR
            BEQ  IT_STR
            CMPA #'{'
            BNE  IT_AGG
            JSR  PEEK
            CMPA #T_STR
            BNE  IT_AGG
            JSR  NEXT
            PULS D,X
            JSR  ISTRING
            PSHS D
            LDA  #44
            JSR  ACCEPT
            LDA  #'}'
            JSR  EXPECT
            PULS D,PC
IT_STR      PULS D,X
            JMP  ISTRING
IT_AGG      PULS D,X
; An array or a struct (X), at D: its elements, in braces or (brace elision)
; as many as it takes of the list it's in. -> D = how many.
AGG         PSHS D,X
            CLRA
            LDB  <TOK
            CMPB #'{'
            BNE  AG_NB
            INCA
AG_NB       PSHS A
            TSTA
            BEQ  AG_GO
            JSR  NEXT
AG_GO       LDX  3,S                   ; (a struct: its first member)
            LDX  TY_PAR,X
            CLRD
            PSHS D,X                   ; ,S the count, 2,S the next member,
AG_LOOP     LDA  <TOK                  ; 4,S braced, 5,S the offset, 7,S the
            CMPA #'}'                  ; type
            LBEQ AG_END
            LDX  7,S
            LDA  TY_KIND,X
            CMPA #TK_STRUCT
            BEQ  AG_MEMB
            LDD  TY_N,X                ; an array: room for another?
            CMPD #$FFFF
            BEQ  AG_ELEM
            CMPD ,S
            BLS  AG_FULL
AG_ELEM     LDY  TY_BASE,X             ; at offset + count * its size
            LDD  TY_SIZE,Y
            MULD ,S
            TFR  W,D
            ADDD 5,S
            TFR  Y,X
            JSR  INIT
            BRA  AG_NEXT
AG_MEMB     LDY  2,S                   ; a struct: its next member (a union:
            BEQ  AG_FULL               ; only the first)
            LDA  TY_FL,X
            BITA #TYF_UNION
            BEQ  AG_M
            LDD  ,S
            BNE  AG_FULL
AG_M        LDD  ME_OFF,Y
            ADDD 5,S
            LDX  ME_TYPE,Y
            JSR  INIT
            LDX  2,S
            LDX  ME_NEXT,X
            STX  2,S
AG_NEXT     LDD  ,S
            ADDD #1
            STD  ,S
            LDA  <TOK
            CMPA #44
            BNE  AG_END
            TST  4,S                   ; with no braces, once it's full the
            BNE  AG_COMMA              ; comma is the list's around it
            LDX  7,S
            LDA  TY_KIND,X
            CMPA #TK_STRUCT
            BEQ  AG_FS
            LDD  TY_N,X
            CMPD #$FFFF
            BEQ  AG_COMMA
            CMPD ,S
            BLS  AG_END
            BRA  AG_COMMA
AG_FS       LDD  2,S
            BEQ  AG_END
            LDA  TY_FL,X
            BITA #TYF_UNION
            BNE  AG_END
AG_COMMA    JSR  NEXT
            LBRA AG_LOOP
AG_FULL     TST  4,S
            BEQ  AG_END
IN_MANY     LDX  #M_MANYINIT
            JMP  ERROR
AG_END      TST  4,S
            BEQ  AG_FILL
            LDA  #'}'
            JSR  EXPECT
AG_FILL     LDX  7,S                   ; the rest: zeros
            LDA  TY_FL,X
            BITA #TYF_NOSIZE
            BNE  AG_RET
            LDD  TY_SIZE,X
            ADDD 5,S
            JSR  FILLTO
AG_RET      PULS D
            LEAS 7,S
            RTS
; D = an offset: zeros from IDONE to it.
FILLTO      PSHS D
            SUBD <IDONE
            BLS  FT_RET
            TST  <IMODE
            BNE  FT_CODE
            JSR  EMITZEROS
            BRA  FT_SET
FT_CODE     PSHS D
            LDD  <IDONE
            ADDD <IBASE
            TFR  D,Y
            PULS D
            JSR  ZEROFILL
FT_SET      LDD  ,S
            STD  <IDONE
FT_RET      PULS D,PC
; X = a scalar's type (or, in code, a struct's), D = its offset: its
; initializer, an expression.
ISCALAR     PSHS D,X
            JSR  FILLTO
            JSR  RESETNODES
            TST  <IMODE
            BNE  IS_CODE
            JSR  ASSIGNEXPR            ; data: a constant, as the type
            LDY  2,S
            JSR  MKCONVERT
            TFR  X,Y
            LDX  2,S
            JSR  TISCHAR
            BCC  IS_CHAR
            JSR  TISLONG
            BCC  IS_LONG
            TFR  Y,X
            JSR  EVALCONST
            BCS  IN_NOTCONST
            LDX  #S_FDB
            JSR  EMITI
            JSR  OUTCONST
            BRA  IS_NL
IS_CHAR     TFR  Y,X
            JSR  EVALCONST
            BCS  IN_NOTCONST
            LDD  <CVSYM
            BNE  IN_NOTCONST
            LDD  <CVLBL
            BNE  IN_NOTCONST
            LDX  #S_FCB
            JSR  EMITI
            LDD  <CVVAL
            CLRA
            JSR  OUTDEC
            BRA  IS_NL
IS_LONG     LDA  N_OP,Y                ; (a long: a number)
            CMPA #O_NUM
            BNE  IN_NOTCONST
            LDX  #S_FDB
            JSR  EMITI
            LDD  N_X,Y
            JSR  OUTDEC
            LDA  #44
            JSR  OUTC
            LDD  N_V,Y
            JSR  OUTDEC
IS_NL       JSR  OUTNL
IS_DONE     LDX  2,S                   ; done to its end
            LDD  TY_SIZE,X
            ADDD ,S
            STD  <IDONE
            PULS D,X,PC
IS_CODE     LDA  #O_FRAME              ; code: its place = the expression
            JSR  NEWNODE
            LDD  ,S
            ADDD <IBASE
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
            BRA  IS_DONE
IN_NOTCONST LDX  #M_NOTCONST
            JMP  ERROR
; X = an array of chars, D = its offset, a string next: its bytes. -> D = the
; array's size.
ISTRING     PSHS D,X
            JSR  FILLTO
            LDX  2,S
            LDD  TY_N,X
            CMPD #$FFFF
            BNE  IG_SIZED
            LDD  <TOKSL                ; no size: the string's, and its NUL
            ADDD #1
IG_SIZED    PSHS D                     ; (,S the size, 2,S the offset, 4,S
            LDD  <TOKSL                ; the type)
            CMPD ,S
            BHI  IN_SLONG
            BEQ  IG_N
            ADDD #1                    ; the NUL too, if it fits
IG_N        TST  <IMODE
            BNE  IG_CODE
            LDX  <TOKSB
            JSR  EMITBYTES
            BRA  IG_DONE
IG_CODE     CMPD #0                    ; copied from rodata
            BEQ  IG_DONE
            PSHS D
            JSR  EMITSTRING
            LDX  4,S
            EXG  D,X
            ADDD <IBASE
            EXG  D,X
            LDY  ,S
            JSR  COPYCODE
            PULS D
IG_DONE     ADDD 2,S
            STD  <IDONE
            JSR  NEXT
            LDD  ,S                    ; zeros to its end
            ADDD 2,S
            JSR  FILLTO
            PULS D
            LEAS 4,S
            RTS
IN_SLONG    LDX  #M_STRLONG
            JMP  ERROR
; Code copying Y bytes from the label D to X,U.
COPYCODE    PSHS D,X,Y
            LDX  #S_PSHSY
            JSR  EMITL
            LDX  #S_LDX
            JSR  EMITI
            LDA  #'#'
            JSR  OUTC
            LDD  ,S
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
            LDD  4,S
            JSR  OUTDEC
            JSR  OUTNL
            LDX  #S_TFMXY
            JSR  EMITL
            LDX  #S_PULSY
            JSR  EMITL
            PULS D,X,Y,PC
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
            LDA  <BANKNO
            BNE  FD_BANKED
            LDA  #SEC_CODE             ; in code
            STA  <FUNCSECT
            JSR  SECT
            LDX  <CURFUNC
            JSR  EXPORTSYM
            LDX  <CURFUNC
            JSR  LABELSYM
            BRA  FD_PROLOG
FD_BANKED   LDB  SY_FL,X               ; in ovlN (#pragma bank N): its body
            BITB #SF_INTR              ; there, as __b_name, and in code a stub,
            LBNE FD_INTRBANK           ; _name: LDB #N / LDX #__b_name / JMP
            ORB  #SF_BANKED            ; __farcall
            STB  SY_FL,X
            STA  SY_VAL+1,X
            CLR  SY_VAL,X
            LDA  #SEC_CODE
            JSR  SECT
            LDX  <CURFUNC
            JSR  EXPORTSYM
            LDX  <CURFUNC
            JSR  LABELSYM
            CLRA
            LDB  <BANKNO
            LDX  #S_LDB
            JSR  EMITIMM
            LDX  #S_LDX
            JSR  EMITI
            LDA  #'#'
            JSR  OUTC
            LDX  <CURFUNC
            JSR  OUTBODY
            JSR  OUTNL
            LDX  #S_JMPFAR
            JSR  EMITL
            INC  <FARUSED
            LDA  <BANKNO
            ADDA #SEC_OVL-1
            STA  <FUNCSECT
            JSR  SECT
            LDX  <CURFUNC
            JSR  OUTBODY
            JSR  OUTNL
FD_PROLOG   LDX  #S_PSHSU
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
            LDX  <DTYPE                ; the parameters: 4,U on (6,U returning
            LDX  TY_BASE,X             ; a struct: its place is at 4,U), words
            LDY  #4                    ; each (a char in its second byte)
            JSR  TISSTRUCT
            BCS  FD_P4
            LDY  #6
FD_P4       LDX  <DTYPE
            LDX  TY_PAR,X
            LDB  PL_N,X
            LEAX PL_PAR,X
            EXG  X,Y
            PSHS B,X,Y
FD_PAR      TST  ,S
            BEQ  FD_BODY
            LDY  3,S
            LDX  ,Y
            LDY  2,Y
            BEQ  FD_NONAME
            LDA  #SK_LOCAL
            JSR  NEWSYM
            PSHS X                     ; (the symbol)
            LDX  SY_TYPE,X
            JSR  TWORDS                ; the next one's place
            LSLB
            ROLA
            ADDD 3,S
            PSHS D
            LDD  5,S                   ; this one's
            JSR  TISCHAR
            BCS  FD_OFF
            ADDD #1
FD_OFF      LDY  2,S
            STD  SY_VAL,Y
            PULS D
            STD  3,S
            LEAS 2,S
            LDD  3,S
            ADDD #4
            STD  3,S
            DEC  ,S
            BRA  FD_PAR
FD_NONAME   LDX  #M_PARNAME
            JMP  ERROR
FD_INTRBANK LDX  #M_INTRBANK
            JMP  ERROR
; X = a banked function's symbol: its body's name, __b_name. (C reserves the
; names that this could be: _b_name.)
OUTBODY     PSHS X
            LDX  #S_BODY
            JSR  OUTS
            PULS X
            JMP  OUTSYMNAME
FD_BODY     LEAS 5,S
            JSR  COMPOUND
            LDD  <RETLBL               ; the end
            JSR  LABELHERE
            LDX  #S_LEASU
            JSR  EMITL
            LDX  <CURFUNC
            LDA  SY_FL,X
            LDX  #S_PULSU
            BITA #SF_INTR
            BEQ  FD_RTS
            LDX  #S_PULSURTI           ; (an interrupt's: RTI)
            JSR  EMITLINES
            BRA  FD_FRAME
FD_RTS      JSR  EMITL
FD_FRAME
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
            LDA  #SEC_CODE
            STA  <FUNCSECT
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
            PSHS Y
            JSR  DECLFUNC              ; a function's prototype
            BRA  LD_ALIAS
LD_NFUNC    LDA  <DSSC
            CMPA #SC_EXTERN
            BNE  LD_NEXTERN
            PSHS Y
            JSR  DECLOBJ
LD_ALIAS    PULS Y                     ; the name means the file's symbol here
            PSHS X                     ; (in this block)
            LDX  SY_TYPE,X
            LDA  #SK_EXTREF
            JSR  NEWSYM
            PULS D
            STD  SY_VAL,X
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
SL_CODE     LDA  <FUNCSECT
            JMP  SECT
; An automatic local: Y = its name, DTYPE its type. It gets a place in the
; frame (n,U, below U); an initializer is code. An array with no size takes
; its initializer's: a string's, or a { list }'s, which is then made as data
; in rodata (so constants only) and copied.
AUTOLOCAL   LDX  <DTYPE
            CLRD
            PSHS D                     ; the label of a copy in rodata (0: none)
            LDA  TY_FL,X
            BITA #TYF_NOSIZE
            BEQ  AU_SIZED
            LDA  <TOK
            CMPA #'='
            LBNE AU_NOSIZE
            PSHS X,Y
            JSR  PEEK
            PULS X,Y
            CMPA #T_STR
            BEQ  AU_STR
            CMPA #'{'
            LBNE AU_NOSIZE
            PSHS X,Y                   ; = { list }
            JSR  NEXT
            LDA  <CURSECT
            PSHS A                     ; (,S the section, 1,S the type, 3,S
            LDA  #SEC_RODATA           ; the name, 5,S the label)
            JSR  SECT
            JSR  NEWLABEL
            STD  5,S
            JSR  LABELHERE
            LDX  1,S
            JSR  INITDATA
            PSHS D
            LDA  2,S
            JSR  SECT
            PULS D
            LDX  1,S
            LDX  TY_BASE,X
            JSR  ARRAYOF
            LEAS 3,S
            PULS Y
            BRA  AU_SIZED
AU_STR      LDD  <AHEADSL              ; = "...": the string's size
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
            LDD  ,S
            BNE  AU_COPY
            LDA  <TOK
            CMPA #'='
            BNE  AU_RET
            PSHS X
            JSR  NEXT
            PULS X
            LDD  SY_VAL,X
            LDX  SY_TYPE,X
            JSR  LINIT
AU_RET      PULS D,PC
AU_COPY     LDY  SY_TYPE,X             ; the copy
            LDY  TY_SIZE,Y
            LDX  SY_VAL,X
            JSR  COPYCODE
            PULS D,PC
AU_NOSIZE   LDX  #M_NOSIZE
            JMP  ERRORN
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
            LDD  #1
FF_HLOOP    TST  ,X
            BEQ  FF_RET
            PSHS D
            ANDD <HELPERS
            PULS D
            BEQ  FF_HSKIP
            PSHS D,X
            LDX  #S_IMPORT
            JSR  EMITI
            LDX  2,S
            JSR  OUTS
            JSR  OUTNL
            PULS D,X
FF_HSKIP    TST  ,X+
            BNE  FF_HSKIP
            LSLD
            BRA  FF_HLOOP
FF_RET      TST  <FARUSED            ; (the stubs')
            BEQ  FF_DONE
            LDX  #S_IMPORT
            JSR  EMITI
            LDX  #S_FARCALL
            JSR  OUTS
            JSR  OUTNL
FF_DONE     RTS
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
M_WRONGTAG  FCN  "used as the wrong kind of tag:"
M_MEMBER    FCN  "a member's declaration was expected"
M_BITFIELD  FCN  "bit-fields are not supported"
M_MEMFUNC   FCN  "a member can't be a function:"
M_MEMTWICE  FCN  "duplicate member"
M_NOMEMBERS FCN  "a struct or union needs members"
M_NOMEMB    FCN  "no such member:"
M_UNDEFSTR  FCN  "the struct or union isn't defined"
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
M_INTRBANK  FCN  "an interrupt function can't be in banked code"
S_BODY      FCN  "__b"
S_JMPFAR    FCN  "JMP __farcall"
S_FARCALL   FCN  "__farcall"
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
S_PULSURTI  FCN  "PULS U"
            FCN  "RTI"
            FCB  0
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
