;------------------------------------------------------------------------------
; pa_sym.asm -- pugasm: the symbol table.
;
; A symbol is a heap record, chained into one of NHASH buckets (HASHTAB: a far
; pointer each), newest first. A SET symbol gets a new record (a "version") every
; time it is set; a lookup from line n finds the newest version set before line n,
; which on pass 2 is the value it had at that point of pass 1. A local symbol
; (a name with @, ? or $ in it) belongs to the context it was defined in (a new
; one starts at each blank line and in each macro expansion).
;------------------------------------------------------------------------------
SR_NEXT     equ  0                 ; the next record in the bucket (far pointer)
SR_FLAGS    equ  3                 ; SF_*
SR_SEQ      equ  4                 ; the line (sequence number) that defined it
SR_VAL      equ  6                 ; the value, 32 bits; SF_EXPR: a far pointer to
                                   ; the expression record
SR_CTX      equ  10                ; a local symbol's context ($FFFF: global)
SR_ADJ      equ  12                ; SF_INEXACT: see PCX
SR_SECT     equ  14                ; the section it is in (obj; 0 = none)
SR_NAME     equ  15                ; the name, NUL-terminated
SF_SET      equ  $01
SF_EXPR     equ  $02
SF_LOCAL    equ  $04
SF_INEXACT  equ  $08
SF_BUSY     equ  $10               ; being evaluated (a circular definition)
SF_IMPORT   equ  $40
SF_SECTREL  equ  $80
; An expression record: +0 the defining line's PC, +2 its context, +4 PCX,
; +5 PCADJ, +7 the operand text (NUL-terminated).
EX_PC       equ  0
EX_CTX      equ  2
EX_PCX      equ  4
EX_ADJ      equ  5
EX_TEXT     equ  7
EXTEXTMAX   equ  120
;------------------------------------------------------------------------------
; NAMEBUF: -> X = its bucket in HASHTAB.
HASHNAME    PSHS D
            LDX  #NAMEBUF
            CLRB
HN_LOOP     LDA  ,X+
            BEQ  HN_DONE
            ASLB                       ; rotate left and add
            ADCB #0
            PSHS A
            ADDB ,S+
            BRA  HN_LOOP
HN_DONE     LDA  #3
            MUL
            LDX  #HASHTAB
            LEAX D,X
            PULS D,PC
; Carry clear if the name in NAMEBUF is a local one (it has @, ? or $).
ISLOCAL     PSHS A,X
            LDX  #NAMEBUF
IL_LOOP     LDA  ,X+
            BEQ  IL_NO
            CMPA #'@'
            BEQ  IL_YES
            CMPA #'?'
            BEQ  IL_YES
            CMPA #'$'
            BEQ  IL_YES
            BRA  IL_LOOP
IL_NO       ORCC #1
            PULS A,X,PC
IL_YES      ANDCC #$FE
            PULS A,X,PC
; Looks up NAMEBUF: -> SYMP = its record (the page mapped, X = its address),
; carry clear; carry set if there is none. For a SET symbol, the newest version
; set before the current line (LSEQ), or failing that the newest there is.
SYMFIND     JSR  HASHNAME
            LDD  ,X                    ; the bucket's first record
            STD  <FARP
            LDA  2,X
            STA  <FARP+2
            CLR  <SYMP                 ; no SET fallback yet
            LDD  #$FFFF                ; the context to match
            STD  <SFCTX
            JSR  ISLOCAL
            BCS  SF3_NEXT
            LDD  <CONTEXT
            STD  <SFCTX
SF3_NEXT    JSR  FARMAP
            BEQ  SF3_END
            PSHS X
            LEAX SR_NAME,X
            LDY  #NAMEBUF
            JSR  STRCMP
            PULS X
            BNE  SF3_SKIP
            LDD  SR_CTX,X
            CMPD <SFCTX
            BNE  SF3_SKIP
            LDA  SR_FLAGS,X
            BITA #SF_SET
            BEQ  SF3_HIT
            LDD  SR_SEQ,X              ; a SET version: set before this line?
            CMPD <LSEQ
            BLO  SF3_HIT
            TST  <SYMP                 ; no: remember the newest, keep looking
            BNE  SF3_SKIP
            LDD  <FARP
            STD  <SYMP
            LDA  <FARP+2
            STA  <SYMP+2
SF3_SKIP    LDD  SR_NEXT,X
            STD  <FARP
            LDA  SR_NEXT+2,X
            STA  <FARP+2
            BRA  SF3_NEXT
SF3_HIT     LDD  <FARP
            STD  <SYMP
            LDA  <FARP+2
            STA  <SYMP+2
            ANDCC #$FE
            RTS
SF3_END     TST  <SYMP                 ; only SET versions from later lines
            BEQ  SF3_NONE
            LDD  <SYMP
            STD  <FARP
            LDA  <SYMP+2
            STA  <FARP+2
            JSR  FARMAP
            ANDCC #$FE
            RTS
SF3_NONE    ORCC #1
            RTS
; A new record for NAMEBUF: A = its flags (SF_SET / SF_EXPR ...), the value in
; EVAL (or, SF_EXPR, the expression record in FARP), EVADJ, the section in
; SECTNUM. -> SYMP = the record (mapped, X = its address).
SYMNEW      STA  <TMPB
            LDX  #NAMEBUF
            JSR  STRLEN
            ADDD #SR_NAME+1
            JSR  HALLOC                ; A:X = the new record
            STA  <SYMP
            STX  <SYMP+1
            PSHS X
            LDX  #NAMEBUF              ; the name
            LDY  ,S
            LEAY SR_NAME,Y
            JSR  STRCPY
            PULS X
            LDA  <TMPB
            STA  SR_FLAGS,X
            LDD  <LSEQ
            STD  SR_SEQ,X
            LDD  #$FFFF
            STD  SR_CTX,X
            JSR  ISLOCAL
            BCS  SN_GLOBAL
            LDD  <CONTEXT
            STD  SR_CTX,X
            LDA  SR_FLAGS,X
            ORA  #SF_LOCAL
            STA  SR_FLAGS,X
SN_GLOBAL   LDA  <TMPB
            BITA #SF_EXPR
            BEQ  SN_VALUE
            LDD  <FARP
            STD  SR_VAL,X
            LDA  <FARP+2
            STA  SR_VAL+2,X
            BRA  SN_ADJ
SN_VALUE    LDQ  <EVAL
            STQ  SR_VAL,X
SN_ADJ      LDD  <EVADJ
            STD  SR_ADJ,X
            LDA  <SECTNUM
            STA  SR_SECT,X
            PSHS X                     ; link it in at the head of its bucket
            JSR  HASHNAME              ; (main memory: the page stays mapped)
            LDY  ,S
            LDD  ,X
            STD  SR_NEXT,Y
            LDA  2,X
            STA  SR_NEXT+2,Y
            LDD  <SYMP
            STD  ,X
            LDA  <SYMP+2
            STA  2,X
            LDD  <NSYMS
            ADDD #1
            STD  <NSYMS
            PULS X,PC
; Defines NAMEBUF on this line: A = SF_SET or 0, the value as SYMNEW (from the
; last evaluation, EVFLAGS saying whether it is known and exact). An unknown
; value keeps the operand text (EXPSTART .. EXP) to evaluate when it is used.
; Pass 2 only checks: a second definition of the same name is an error.
SYMDEF      STA  <TMPB2
            JSR  SYMFIND
            BCS  SD_NEW
            LDA  SR_FLAGS,X            ; there is one already
            BITA #SF_SET
            BEQ  SD_THERE
            LDA  <TMPB2                ; a SET symbol: set again
            BEQ  SD_DUP                ; (EQU of a SET symbol: an error)
            BRA  SD_NEW
SD_THERE    LDD  SR_SEQ,X              ; ours (pass 2: defined on this very line)?
            CMPD <LSEQ
            BEQ  SD_RET
SD_DUP      LDA  #ER_DUPSYM
            JMP  ERROR
SD_NEW      LDA  <PASS                 ; (pass 2 finds pass 1's record above)
            CMPA #2
            BNE  SD_MAKE
            LDA  <TMPB2                ; except a SET version, which pass 2 finds
            BNE  SD_RET                ; by line: nothing to do
            LDA  #ER_PHASE
            JMP  ERROR
SD_MAKE     LDA  <EVFLAGS
            BITA #EF_KNOWN
            BNE  SD_KNOWN
            JSR  SAVEEXPR              ; -> FARP
            LDA  <TMPB2
            ORA  #SF_EXPR
            JMP  SYMNEW
SD_KNOWN    LDA  <TMPB2
            LDB  <EVFLAGS
            BITB #EF_INEXACT
            BEQ  SD_MK2
            ORA  #SF_INEXACT
SD_MK2      JMP  SYMNEW
SD_RET      RTS
; The operand text EXPSTART .. EXP -> a new expression record in FARP.
SAVEEXPR    LDD  <EXP
            SUBD <EXPSTART
            CMPD #EXTEXTMAX
            BLS  SX_LEN
            LDD  #EXTEXTMAX
SX_LEN      STD  <TMP
            ADDD #EX_TEXT+1
            JSR  HALLOC
            STA  <FARP
            STX  <FARP+1
            LDD  <STARPC
            STD  EX_PC,X
            LDD  <CONTEXT
            STD  EX_CTX,X
            LDA  <PCX
            STA  EX_PCX,X
            LDD  <PCADJ
            STD  EX_ADJ,X
            LEAY EX_TEXT,X
            LDX  <EXPSTART
            LDB  <TMP+1
            BEQ  SX_END
SX_COPY     LDA  ,X+
            STA  ,Y+
            DECB
            BNE  SX_COPY
SX_END      CLR  ,Y
            RTS
;------------------------------------------------------------------------------
; The value of the symbol in NAMEBUF, for an expression: -> EVAL, EVFLAGS, EVADJ.
; Unknown if it isn't defined, or (SIZE mode) is defined at or after CUTSEQ.
;------------------------------------------------------------------------------
SYMVALUE    JSR  SYMFIND
            BCS  SV_UNDEF
; The same for a record already found: SYMP (mapped, X).
SYMVALREC   LDA  <EVMODE
            BNE  SV_ANY
            LDD  SR_SEQ,X
            CMPD <CUTSEQ
            BHS  SV_UNKNOWN
SV_ANY      LDA  SR_FLAGS,X
            BITA #SF_IMPORT
            LBNE SV_IMPORT
            BITA #SF_EXPR
            BNE  SV_EXPR
            LDQ  SR_VAL,X
            STQ  <EVAL
            LDD  SR_ADJ,X
            STD  <EVADJ
            LDB  #EF_KNOWN
            BITA #SF_INEXACT
            BEQ  SV_FLAGS
            ORB  #EF_INEXACT
SV_FLAGS    STB  <EVFLAGS
            BITA #SF_SECTREL
            LBNE SV_SECT
            RTS
; Symbols from other files and section-relative ones: object output (not yet).
SV_IMPORT   BRA  SV_UNKNOWN
SV_SECT     RTS
SV_UNDEF    LDA  <EVMODE               ; (pass 2, VALUE: truly undefined)
            BEQ  SV_UNKNOWN
            LDA  <PASS
            CMPA #2
            BNE  SV_UNKNOWN
            CLRD
            CLRW
            STQ  <EVAL
            LDA  #EF_UNDEF
            STA  <EVFLAGS
            RTS
SV_UNKNOWN  CLRD
            CLRW
            STQ  <EVAL
            CLR  <EVFLAGS
            RTS
; A symbol whose value is an expression: evaluate that, at its own line's PC and
; context, with the current cutoff. The text is copied to the stack first (other
; symbols' pages get mapped while it is read).
SV_EXPR     BITA #SF_BUSY
            BNE  SV_UNKNOWN            ; circular
            ORA  #SF_BUSY
            STA  SR_FLAGS,X
            LDA  <EVDEPTH
            CMPA #8
            BHS  SV_DEEP
            INC  <EVDEPTH
            LDD  <SYMP                 ; remember the symbol (to clear SF_BUSY)
            PSHS D
            LDA  <SYMP+2
            PSHS A
            LDD  <EXP                  ; and the state the caller is parsing with
            PSHS D
            LDD  <STARPC
            PSHS D
            LDD  <CONTEXT
            PSHS D
            LDD  <EXPSTART
            PSHS D
            LDD  SR_VAL,X              ; the expression record
            STD  <FARP
            LDA  SR_VAL+2,X
            STA  <FARP+2
            JSR  FARMAP
            LDD  EX_PC,X
            STD  <STARPC
            LDD  EX_CTX,X
            STD  <CONTEXT
            LEAS -(EXTEXTMAX+2),S      ; its text -> the stack
            LEAX EX_TEXT,X
            LEAY ,S
            JSR  STRCPY
            LEAX ,S
            STX  <EXP
            JSR  EXPR
            LEAS EXTEXTMAX+2,S
            PULS D
            STD  <EXPSTART
            PULS D
            STD  <CONTEXT
            PULS D
            STD  <STARPC
            PULS D
            STD  <EXP
            PULS A                     ; clear SF_BUSY on the symbol
            STA  <FARP+2
            PULS D
            STD  <FARP
            JSR  FARMAP
            LDA  SR_FLAGS,X
            ANDA #~SF_BUSY
            STA  SR_FLAGS,X
            DEC  <EVDEPTH
            CLR  <EVLIT
            RTS
SV_DEEP     ANDA #~SF_BUSY
            STA  SR_FLAGS,X
            LBRA SV_UNKNOWN
;------------------------------------------------------------------------------
; End of pa_sym.asm
;------------------------------------------------------------------------------
