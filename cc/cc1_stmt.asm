;------------------------------------------------------------------------------
; cc1_stmt.asm -- CC1: statements. Each is made into code as it's read.
; (GENJUMP, cc1_gen.asm: X = a tree, Y = a label, A = 1 to jump there if the
; tree is true, 0 if it's false.)
;------------------------------------------------------------------------------
; { declarations and statements } (a scope of its own).
COMPOUND    LDA  #'{'
            JSR  EXPECT
            JSR  PUSHSCOPE
            LDD  <FRAMESZ              ; its locals' space is used again after it
            PSHS D
CO_LOOP     LDA  <TOK
            CMPA #'}'
            BEQ  CO_END
            TSTA
            BEQ  CO_EOF
            JSR  ISDECLSTART
            BCS  CO_STMT
            JSR  LOCALDECL
            BRA  CO_LOOP
CO_STMT     JSR  STATEMENT
            BRA  CO_LOOP
CO_END      JSR  NEXT
            JSR  POPSCOPE
            PULS D
            STD  <FRAMESZ
            RTS
CO_EOF      LDX  #M_EOFBLOCK
            JMP  ERROR
; One statement.
STATEMENT   JSR  STKCHK
            LDA  <TOK
            LDX  #STMTAB
ST_FIND     TST  ,X
            BEQ  ST_OTHER
            CMPA ,X
            BEQ  ST_GOT
            LEAX 3,X
            BRA  ST_FIND
ST_GOT      JMP  [1,X]
ST_OTHER    CMPA #T_ID                 ; NAME: is a label
            BNE  ST_EXPR
            JSR  PEEK
            CMPA #':'
            BEQ  ST_LABEL
ST_EXPR     JSR  RESETNODES            ; an expression
            JSR  EXPR
            JSR  GENVOID
            LDA  #';'
            JMP  EXPECT
ST_LABEL    LDY  <TOKV
            LDA  #1
            JSR  FINDLABEL
            JSR  LABELHERE
            JSR  NEXT
            JSR  NEXT
            BRA  STATEMENT
STMTAB      FCB  '{'
            FDB  COMPOUND
            FCB  ';'
            FDB  NEXT
            FCB  K_IF
            FDB  ST_IF
            FCB  K_WHILE
            FDB  ST_WHILE
            FCB  K_DO
            FDB  ST_DO
            FCB  K_FOR
            FDB  ST_FOR
            FCB  K_SWITCH
            FDB  ST_SWITCH
            FCB  K_CASE
            FDB  ST_CASE
            FCB  K_DEFAULT
            FDB  ST_DEFAULT
            FCB  K_BREAK
            FDB  ST_BREAK
            FCB  K_CONTINUE
            FDB  ST_CONT
            FCB  K_RETURN
            FDB  ST_RETURN
            FCB  K_GOTO
            FDB  ST_GOTO
            FCB  K_ASM
            FDB  ST_ASM
            FCB  0
; ( expression ) -> X = its tree (the nodes begin again).
PARENEXPR   LDA  #'('
            JSR  EXPECT
            JSR  RESETNODES
            JSR  EXPR
            PSHS X
            LDA  #')'
            JSR  EXPECT
            PULS X,PC
; if (e) s [else s]
ST_IF       JSR  NEXT
            JSR  PARENEXPR
            PSHS X
            JSR  NEWLABEL              ; the else
            PULS X
            PSHS D
            TFR  D,Y
            CLRA
            JSR  GENJUMP
            JSR  STATEMENT
            LDA  <TOK
            CMPA #K_ELSE
            BEQ  IF_ELSE
            PULS D
            JMP  LABELHERE
IF_ELSE     JSR  NEXT
            JSR  NEWLABEL              ; the end
            PSHS D
            JSR  JUMPTO
            LDD  2,S
            JSR  LABELHERE
            JSR  STATEMENT
            PULS D
            JSR  LABELHERE
            LEAS 2,S
            RTS
; D = break's label, X = continue's: they're set, the old ones kept on the
; stack (under the return address) until LOOPEND puts them back.
LOOPLBLS    PULS Y                     ; (the return address)
            PSHS D
            LDD  <BRKLBL
            PSHS D
            LDD  <CONTLBL
            PSHS D
            LDD  4,S
            STD  <BRKLBL
            STX  <CONTLBL
            JMP  ,Y
LOOPEND     PULS Y
            PULS D
            STD  <CONTLBL
            PULS D
            STD  <BRKLBL
            LEAS 2,S
            JMP  ,Y
; while (e) s
ST_WHILE    JSR  NEXT
            JSR  NEWLABEL              ; the top
            PSHS D
            JSR  LABELHERE
            JSR  NEWLABEL              ; the end
            LDX  ,S
            JSR  LOOPLBLS
            JSR  PARENEXPR
            LDY  <BRKLBL
            CLRA
            JSR  GENJUMP
            JSR  STATEMENT
            LDD  <CONTLBL
            JSR  JUMPTO
            LDD  <BRKLBL
            JSR  LABELHERE
            JSR  LOOPEND
            LEAS 2,S
            RTS
; do s while (e);
ST_DO       JSR  NEXT
            JSR  NEWLABEL              ; the top
            PSHS D
            JSR  LABELHERE
            JSR  NEWLABEL              ; continue's: the test
            PSHS D
            JSR  NEWLABEL              ; the end
            LDX  ,S
            JSR  LOOPLBLS
            JSR  STATEMENT
            LDA  #K_WHILE
            JSR  EXPECT
            JSR  PARENEXPR
            LDD  <CONTLBL
            JSR  LABELHERE
            LDY  8,S
            LDA  #1
            JSR  GENJUMP
            LDD  <BRKLBL
            JSR  LABELHERE
            JSR  LOOPEND
            LEAS 4,S
            LDA  #';'
            JMP  EXPECT
; for (init; cond; next) s: init, then
;   LBRA Lcond / Lnext: next / Lcond: if !cond goto Lend / s / LBRA Lnext / Lend
; (cond's and next's trees are both kept until they're made into code).
ST_FOR      JSR  NEXT
            LDA  #'('
            JSR  EXPECT
            JSR  PUSHSCOPE             ; (for a declaration in init)
            LDD  <FRAMESZ
            PSHS D
            LDA  <TOK
            CMPA #';'
            BEQ  FO_NOINIT
            JSR  ISDECLSTART
            BCS  FO_EINIT
            JSR  LOCALDECL
            BRA  FO_COND
FO_EINIT    JSR  RESETNODES
            JSR  EXPR
            JSR  GENVOID
FO_NOINIT   LDA  #';'
            JSR  EXPECT
FO_COND     JSR  RESETNODES
            CLRD
            PSHS D                     ; cond (0: none)
            LDA  <TOK
            CMPA #';'
            BEQ  FO_NOCOND
            JSR  EXPR
            STX  ,S
FO_NOCOND   LDA  #';'
            JSR  EXPECT
            CLRD
            PSHS D                     ; next (0: none)
            LDA  <TOK
            CMPA #')'
            BEQ  FO_NONEXT
            JSR  EXPR
            STX  ,S
FO_NONEXT   LDA  #')'
            JSR  EXPECT
            JSR  NEWLABEL              ; Lcond
            PSHS D
            JSR  JUMPTO
            JSR  NEWLABEL              ; Lnext
            PSHS D
            JSR  LABELHERE
            LDX  4,S                   ; (,S Lnext, 2,S Lcond, 4,S next,
            BEQ  FO_N0                 ; 6,S cond, 8,S the frame)
            JSR  GENVOID
FO_N0       LDD  2,S
            JSR  LABELHERE
            JSR  NEWLABEL              ; Lend
            LDX  ,S
            JSR  LOOPLBLS              ; (6 bytes more on the stack)
            LDX  12,S
            BEQ  FO_C0
            LDY  <BRKLBL
            CLRA
            JSR  GENJUMP
FO_C0       JSR  STATEMENT
            LDD  <CONTLBL
            JSR  JUMPTO
            LDD  <BRKLBL
            JSR  LABELHERE
            JSR  LOOPEND
            LEAS 8,S
            PULS D
            STD  <FRAMESZ
            JMP  POPSCOPE
; switch (e) s: the value in D (a long's in Q), a jump to the tests after s
; (CMPD #v / LBEQ for each case, then to default), so the cases are known by
; then. A case is 6 bytes in CASES: its value (high word, low word), label.
ST_SWITCH   JSR  NEXT
            JSR  PARENEXPR
            PSHS X
            LDX  N_TYPE,X
            JSR  TISINT
            LBCS SW_NOTINT
            JSR  PROMOTE               ; the cases' type
            LDD  <SWTYPE
            STX  <SWTYPE
            PULS X
            PSHS D                     ; (the switch around it's)
            JSR  GEN
            JSR  NEWLABEL              ; the tests
            PSHS D
            JSR  JUMPTO
            LDD  <SWCASES
            PSHS D
            LDD  <SWDEFLT
            PSHS D
            LDA  <INSWITCH
            PSHS A
            LDD  <CASEP
            STD  <SWCASES
            CLRD
            STD  <SWDEFLT
            LDA  #1
            STA  <INSWITCH
            JSR  NEWLABEL              ; the end (continue is still the loop's)
            LDX  <CONTLBL
            JSR  LOOPLBLS
            JSR  STATEMENT
            LDD  <BRKLBL
            JSR  JUMPTO
            LDD  11,S                  ; (,S..5,S LOOPLBLS's, 6,S INSWITCH,
            JSR  LABELHERE             ; 7,S SWDEFLT, 9,S SWCASES, 11,S tests)
            LDX  <SWCASES
SW_TEST     CMPX <CASEP
            BHS  SW_DFLT
            PSHS X
            LDX  <SWTYPE
            JSR  TISLONG
            BCC  SW_LONG
            LDX  ,S                    ; CMPD #v / LBEQ case
            LDD  2,X
            LDX  #S_CMPD
            JSR  EMITIMM
SW_EQ       LDX  ,S
            LDD  4,X
            LDX  #S_LBEQ
            JSR  EMITLBL
            PULS X
            LEAX 6,X
            BRA  SW_TEST
SW_LONG     JSR  NEWLABEL              ; a long: CMPD #high / LBNE next /
            PSHS D                     ; CMPW #low / LBEQ case / next:
            LDX  2,S
            LDD  ,X
            LDX  #S_CMPD
            JSR  EMITIMM
            LDD  ,S
            LDX  #S_LBNE
            JSR  EMITLBL
            LDX  2,S
            LDD  2,X
            LDX  #S_CMPW
            JSR  EMITIMM
            LDX  2,S
            LDD  4,X
            LDX  #S_LBEQ
            JSR  EMITLBL
            PULS D
            JSR  LABELHERE
            PULS X
            LEAX 6,X
            BRA  SW_TEST
SW_DFLT     LDD  <SWDEFLT
            BEQ  SW_END
            JSR  JUMPTO
SW_END      LDD  <BRKLBL
            JSR  LABELHERE
            LDD  <SWCASES
            STD  <CASEP
            JSR  LOOPEND
            PULS A
            STA  <INSWITCH
            PULS D
            STD  <SWDEFLT
            PULS D
            STD  <SWCASES
            LEAS 2,S
            PULS D
            STD  <SWTYPE
            RTS
SW_NOTINT   LDX  #M_SWINT
            JMP  ERROR
; X = a mnemonic, D = a number: " MNEM #n". EMITLBL: D = a label: " MNEM Ln".
EMITIMM     JSR  EMITI
            PSHS A
            LDA  #'#'
            JSR  OUTC
            PULS A
            JSR  OUTDEC
            JMP  OUTNL
EMITLBL     JSR  EMITI
            JSR  OUTLBL
            JMP  OUTNL
ST_CASE     TST  <INSWITCH
            BEQ  CA_OUT
            JSR  NEXT
            JSR  RESETNODES
            JSR  CONSTEXPR             ; (X = its number: made the switch's
            LDY  <SWTYPE               ; type, in place)
            JSR  MKCONVERT
            LDD  N_V,X
            LDY  N_X,X
            PSHS D,Y
            LDA  #':'
            JSR  EXPECT
            LDX  <CASEP
            CMPX #CASES+MAXCASES*6
            BHS  CA_MANY
            PULS D,Y
            STY  ,X
            STD  2,X
            PSHS X
            JSR  NEWLABEL
            PULS X
            STD  4,X
            LEAX 6,X
            STX  <CASEP
            JSR  LABELHERE
            JMP  STATEMENT
CA_OUT      LDX  #M_CASEOUT
            JMP  ERROR
CA_MANY     LDX  #M_MANYCASE
            JMP  ERROR
ST_DEFAULT  TST  <INSWITCH
            BEQ  CA_OUT
            JSR  NEXT
            LDA  #':'
            JSR  EXPECT
            LDD  <SWDEFLT
            BNE  DE_TWICE
            JSR  NEWLABEL
            STD  <SWDEFLT
            JSR  LABELHERE
            JMP  STATEMENT
DE_TWICE    LDX  #M_DEFTWICE
            JMP  ERROR
ST_BREAK    JSR  NEXT
            LDD  <BRKLBL
            BEQ  BK_OUT
            JSR  JUMPTO
            LDA  #';'
            JMP  EXPECT
BK_OUT      LDX  #M_BRKOUT
            JMP  ERROR
ST_CONT     JSR  NEXT
            LDD  <CONTLBL
            BEQ  CT_OUT
            JSR  JUMPTO
            LDA  #';'
            JMP  EXPECT
CT_OUT      LDX  #M_CONTOUT
            JMP  ERROR
; return [e]; : the value (as the function's type) in D (a long's in Q). A
; struct is copied to where 4,U says, its address then in D.
ST_RETURN   JSR  NEXT
            LDA  <TOK
            CMPA #';'
            BEQ  RE_JUMP
            JSR  RESETNODES
            JSR  EXPR
            LDY  <CURFUNC
            LDY  SY_TYPE,Y
            LDY  TY_BASE,Y
            LDA  TY_KIND,Y
            CMPA #TK_VOID
            BEQ  RE_VOIDV
            PSHS Y
            JSR  MKCONVERT
            JSR  GEN
            PULS X
            JSR  TISSTRUCT
            BCS  RE_JUMP
            PSHS X
            LDX  #S_LDX4U
            JSR  EMITL
            PULS X
            JSR  SCOPY
RE_JUMP     LDD  <RETLBL
            JSR  JUMPTO
            LDA  #';'
            JMP  EXPECT
RE_VOIDV    LDX  #M_RETVOID
            JMP  ERROR
ST_GOTO     JSR  NEXT
            LDA  <TOK
            CMPA #T_ID
            BNE  GO_BAD
            LDY  <TOKV
            CLRA
            JSR  FINDLABEL
            JSR  JUMPTO
            JSR  NEXT
            LDA  #';'
            JMP  EXPECT
GO_BAD      LDA  #T_ID
            JMP  EXPECT
;------------------------------------------------------------------------------
M_EOFBLOCK  FCN  "the file ends inside a block"
M_SWINT     FCN  "switch needs an integer"
M_CASEOUT   FCN  "case or default outside a switch"
M_MANYCASE  FCN  "too many cases"
M_DEFTWICE  FCN  "two defaults in a switch"
M_BRKOUT    FCN  "break outside a loop or a switch"
M_CONTOUT   FCN  "continue outside a loop"
;------------------------------------------------------------------------------
; asm { lines }: the lines into the output as they are, except that a C name
; in an operand (after the mnemonic) is made what it is in assembly: a local
; n,U, a global _name, a static Ln, an enum's constant its value. (Register
; names are left alone.) An indented line is an instruction; one that isn't
; starts with a label. In a function or at file level (then in code).
;------------------------------------------------------------------------------
ST_ASM      JSR  ASMBLOCK
            JMP  NEXT
; TOK = asm (nothing looked ahead at: the text after it is read here).
ASMBLOCK    LDA  <FUNCSECT             ; (code, or a function's ovlN)
            JSR  SECT
            JSR  SKIPBLANK
            BCS  AB_EOF
            CMPA #'{'
            BNE  AB_BRACE
            LDA  #1
            PSHS A                     ; 1,S: braces open
            PSHS A                     ; ,S: at a line's start
AB_NEWLINE  LDY  #DIRBUF
AB_CHAR     JSR  GETCH
            BCS  AB_EOF
            CMPA #LF
            BEQ  AB_EOL
            TST  ,S
            BEQ  AB_MID
            CLR  ,S
            CMPA #'#'                  ; (a #line from CPP)
            BNE  AB_MID
            JSR  DIRLINE
            LDA  #1
            STA  ,S
            BRA  AB_NEWLINE
AB_MID      CMPA #'{'
            BNE  AB_NOPEN
            INC  1,S
AB_NOPEN    CMPA #'}'
            BNE  AB_PUT
            DEC  1,S
            BEQ  AB_END
AB_PUT      CMPY #DIRBUF+255           ; (past 255 characters: dropped)
            BHS  AB_CHAR
            STA  ,Y+
            BRA  AB_CHAR
AB_EOL      CLR  ,Y
            BSR  ASMLINE
            LDA  #1
            STA  ,S
            BRA  AB_NEWLINE
AB_END      CLR  ,Y
            BSR  ASMLINE
            LEAS 2,S
            RTS
AB_EOF      LDX  #M_EOFASM
            JMP  ERROR
AB_BRACE    LDA  #'{'
            JMP  EP_BAD
; DIRBUF, a line of an asm block -> the output.
ASMLINE     LDX  #DIRBUF
            CLRB                       ; B = the field: 0 a label, 1 the
            LDA  ,X                    ; mnemonic, 2 on its operands
            BEQ  AM_RET
            JSR  ISSPACE
            BCS  AM_GO
            JSR  SKIPSP                ; indented: one space before it
            LDA  ,X
            BEQ  AM_RET
            LDA  #' '
            JSR  OUTC
            LDB  #1
AM_GO       PSHS B
            CLRD
            PSHS D                     ; ,S after a name's character, 1,S in a
AM_LOOP     LDA  ,X                    ; word, 2,S the field
            BEQ  AM_END
            JSR  ISSPACE
            BCS  AM_NSP
            CLR  ,S                    ; a space: a word ends
            TST  1,S
            BEQ  AM_OUT
            CLR  1,S
            INC  2,S
AM_OUT      JSR  OUTC
            LEAX 1,X
            BRA  AM_LOOP
AM_NSP      TST  1,S                   ; a word starts: the mnemonic? (TMP3)
            BNE  AM_INW
            LDB  2,S
            CMPB #1
            BNE  AM_INW
            STX  <TMP3
AM_INW      LDB  #1
            STB  1,S
            CMPA #';'                  ; a comment: the rest as it is
            BEQ  AM_REST
            CMPA #'"'
            BEQ  AM_STR
            JSR  ISIDST
            BCS  AM_PLAIN
            TST  ,S
            BNE  AM_PLAIN
            BSR  AM_NAME
            BRA  AM_LOOP
AM_PLAIN    CLR  ,S
            JSR  ISIDCH
            BCS  AM_OUT
            INC  ,S
            BRA  AM_OUT
AM_STR      JSR  OUTC                  ; "...": as it is
            LEAX 1,X
            LDA  ,X
            BEQ  AM_END
            CMPA #'"'
            BNE  AM_STR
            BRA  AM_OUT
AM_REST     JSR  OUTS
AM_END      LEAS 3,S
            JMP  OUTNL
AM_RET      RTS
; A name at X (the field 2,S of the caller's): out as it is, or what it means.
; X ends after it.
AM_NAME     STX  <TMP2                 ; (where it starts)
            LDY  #NAMEBUF
            LDB  #NAMEMAX
AN_COPY     LDA  ,X
            JSR  ISIDCH
            BCS  AN_END
            LEAX 1,X
            TSTB
            BEQ  AN_COPY
            STA  ,Y+
            DECB
            BRA  AN_COPY
AN_END      CLR  ,Y
            LDA  #1
            STA  2,S                   ; (a name's character last)
            PSHS X
            LDA  6,S
            CMPA #2
            BLO  AN_ASIS
            LDX  #REGNAMES             ; a register's name: the register
AN_REG      TST  ,X                    ; next to "," (or after "-"), or after
            BEQ  AN_LOOK               ; PSHS, TFR and the like
            LDY  #NAMEBUF
            JSR  STRCMPI
            BEQ  AN_ISREG
AN_RSKIP    TST  ,X+
            BNE  AN_RSKIP
            BRA  AN_REG
AN_ISREG    LDX  ,S
            LDA  ,X
            CMPA #44
            BEQ  AN_ASIS
            LDX  <TMP2
            LDA  -1,X
            CMPA #44
            BEQ  AN_ASIS
            CMPA #'-'
            BEQ  AN_ASIS
            JSR  MNEMREG
            BCC  AN_ASIS
AN_LOOK     JSR  FINDNAME
            BEQ  AN_ASIS
            LDX  NM_SYM,X
            BEQ  AN_ASIS
            LDA  SY_KIND,X
            CMPA #SK_EXTREF
            BNE  AN_KIND
            LDX  SY_VAL,X
            LDA  SY_KIND,X
AN_KIND     CMPA #SK_LOCAL
            BEQ  AN_LOCAL
            CMPA #SK_ENUMC
            BEQ  AN_ENUM
            CMPA #SK_GLOBAL
            BEQ  AN_GLOBAL
            CMPA #SK_STATLOC
            BNE  AN_ASIS
AN_GLOBAL   LDA  SY_FL,X               ; _name, Ln
            ORA  #SF_USED
            STA  SY_FL,X
            JSR  OUTSYMNAME
            PULS X,PC
AN_LOCAL    LDD  SY_VAL,X              ; n,U
            JSR  OUTDEC
            LDX  #S_COMMAU
            JSR  OUTS
            PULS X,PC
AN_ENUM     LDD  SY_VAL,X
            JSR  OUTDEC
            PULS X,PC
AN_ASIS     LDX  #NAMEBUF
            JSR  OUTS
            PULS X,PC
; Carry clear if the mnemonic at TMP3 takes only registers (REGOPS).
MNEMREG     LDY  #REGOPS
MR_ENTRY    TST  ,Y
            BEQ  MR_NO
            LDX  <TMP3
MR_CMP      LDA  ,Y
            BEQ  MR_END
            LDB  ,X+
            ORB  #$20
            PSHS B
            CMPA ,S+
            BNE  MR_SKIP
            LEAY 1,Y
            BRA  MR_CMP
MR_END      LDA  ,X                    ; (and the word ends there)
            BEQ  MR_YES
            JSR  ISSPACE
            BCC  MR_YES
MR_SKIP     TST  ,Y+
            BNE  MR_SKIP
            BRA  MR_ENTRY
MR_YES      ANDCC #$FE
            RTS
MR_NO       ORCC #1
            RTS
REGOPS      FCN  "pshs"
            FCN  "puls"
            FCN  "pshu"
            FCN  "pulu"
            FCN  "tfr"
            FCN  "exg"
            FCN  "tfm"
            FCN  "addr"
            FCN  "adcr"
            FCN  "subr"
            FCN  "sbcr"
            FCN  "andr"
            FCN  "orr"
            FCN  "eorr"
            FCN  "cmpr"
            FCB  0
REGNAMES    FCN  "a"
            FCN  "b"
            FCN  "d"
            FCN  "e"
            FCN  "f"
            FCN  "w"
            FCN  "q"
            FCN  "v"
            FCN  "x"
            FCN  "y"
            FCN  "u"
            FCN  "s"
            FCN  "pc"
            FCN  "pcr"
            FCN  "dp"
            FCN  "cc"
            FCN  "md"
            FCB  0
M_EOFASM    FCN  "the file ends inside asm { }"
S_CMPW      FCN  "CMPW"
S_LDX4U     FCN  "LDX 4,U"
M_RETVOID   FCN  "a value returned from a void function"
S_CMPD      FCN  "CMPD"
S_LBEQ      FCN  "LBEQ"
;------------------------------------------------------------------------------
; End of cc1_stmt.asm
;------------------------------------------------------------------------------
