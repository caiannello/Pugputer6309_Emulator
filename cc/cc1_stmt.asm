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
STATEMENT   LDA  <TOK
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
            FDB  ST_LATER
            FCB  0
ST_LATER    LDX  #M_NOTYET
            JMP  ERROR
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
; switch (e) s: the value in D, a jump to the tests after s (CMPD #v / LBEQ
; for each case, then to default), so the cases are known by then.
ST_SWITCH   JSR  NEXT
            JSR  PARENEXPR
            LDY  N_TYPE,X
            EXG  X,Y
            JSR  TISINT
            EXG  X,Y
            LBCS SW_NOTINT
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
            LDX  #S_CMPD
            JSR  EMITI
            LDA  #'#'
            JSR  OUTC
            LDX  ,S
            LDD  ,X
            JSR  OUTDEC
            JSR  OUTNL
            LDX  #S_LBEQ
            JSR  EMITI
            LDX  ,S
            LDD  2,X
            JSR  OUTLBL
            JSR  OUTNL
            PULS X
            LEAX 4,X
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
            RTS
SW_NOTINT   LDX  #M_SWINT
            JMP  ERROR
ST_CASE     TST  <INSWITCH
            BEQ  CA_OUT
            JSR  NEXT
            JSR  RESETNODES
            JSR  CONSTEXPR
            PSHS D
            LDA  #':'
            JSR  EXPECT
            LDX  <CASEP
            CMPX #CASES+MAXCASES*4
            BHS  CA_MANY
            PULS D
            STD  ,X
            PSHS X
            JSR  NEWLABEL
            PULS X
            STD  2,X
            LEAX 4,X
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
; return [e]; : the value (as the function's type) in D.
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
            JSR  MKCONVERT
            JSR  GEN
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
M_RETVOID   FCN  "a value returned from a void function"
S_CMPD      FCN  "CMPD"
S_LBEQ      FCN  "LBEQ"
;------------------------------------------------------------------------------
; End of cc1_stmt.asm
;------------------------------------------------------------------------------
