;------------------------------------------------------------------------------
; pa_expr.asm -- pugasm: expressions, as lwasm parses them.
;
; EXPR parses and evaluates the expression at EXP: 32-bit values (C int), the
; operators and precedences of lwtools' lw_expr (unary - ~ ^; * / % \; + -;
; & | ! ^; && ||), and lwasm's terms: $hex %bin @oct &dec 0xhex, numbers with a
; base suffix (H Q O B), 'c and "cc characters, * (the line's address), symbols.
; -> EVAL, EVFLAGS (EF_KNOWN: every symbol known ...), EVADJ, EVLIT (it was a
; single number); EXP past the expression. Carry set if there is no expression
; or it doesn't parse.
;------------------------------------------------------------------------------
OP_PLUS     equ  1
OP_MINUS    equ  2
OP_TIMES    equ  3
OP_DIV      equ  4
OP_MOD      equ  5
OP_IDIV     equ  6
OP_LAND     equ  7
OP_LOR      equ  8
OP_BAND     equ  9
OP_BOR      equ  10
OP_BXOR     equ  11
;------------------------------------------------------------------------------
EXPR        LDD  <EXP
            STD  <EXPSTART
            LDA  #1
            STA  <EVLIT
            CLRA
; A = the lowest precedence to take: parses a term and the operators above it.
EXPRP       PSHS A
            JSR  TERM
            BCS  EP_FAIL
EP_LOOP     LDX  <EXP
            LDA  ,X
            JSR  ISEXPEND
            BCC  EP_DONE
            JSR  FINDOP                ; A = precedence, B = operator, Y past it
            BCS  EP_FAIL
            CMPA ,S
            BLS  EP_DONE               ; not above the level we were called for
            STY  <EXP
            CLR  <EVLIT
            PSHS D                     ; the operator, then the left operand
            LDD  <EVADJ
            PSHS D
            LDB  <EVFLAGS
            PSHS B
            LDQ  <EVAL
            PSHSW
            PSHS D
            LDA  7,S                   ; the right operand, at the operator's level
            JSR  EXPRP
            BCS  EP_FAIL9
            LEAX ,S                    ; X = the left operand, 8,S = the operator
            LDB  8,S
            JSR  APPLYOP
            LEAS 9,S
            BRA  EP_LOOP
EP_DONE     LEAS 1,S
            ANDCC #$FE
            RTS
EP_FAIL9    LEAS 9,S
EP_FAIL     LEAS 1,S
            ORCC #1
            RTS
; Carry clear if A ends an expression: NUL, a space, ) , ] ;
ISEXPEND    TSTA
            BEQ  IE_YES
            CMPA #')'
            BEQ  IE_YES
            CMPA #','
            BEQ  IE_YES
            CMPA #']'
            BEQ  IE_YES
            CMPA #';'
            BEQ  IE_YES
            JMP  ISSPACE
IE_YES      ANDCC #$FE
            RTS
; X = where an operator should be: -> A = its precedence, B = its code, Y just
; past it; carry set if there isn't one. (The first match in lw_expr's order.)
FINDOP      LDY  #OPTABLE
FO_TRY      LDA  ,Y
            BEQ  FO_NONE
            CMPA ,X
            BNE  FO_NEXT
            LDA  1,Y
            BEQ  FO_ONE
            CMPA 1,X
            BNE  FO_NEXT
            LDD  2,Y                   ; a two-character operator
            LEAY 2,X
            ANDCC #$FE
            RTS
FO_ONE      LDD  2,Y
            LEAY 1,X
            ANDCC #$FE
            RTS
FO_NEXT     LEAY 4,Y
            BRA  FO_TRY
FO_NONE     ORCC #1
            RTS
; Two characters (second 0 = none), the precedence, the code. In lw_expr's order.
OPTABLE     FCB  '+',0,100,OP_PLUS
            FCB  '-',0,100,OP_MINUS
            FCB  '*',0,150,OP_TIMES
            FCB  '/',0,150,OP_DIV
            FCB  '%',0,150,OP_MOD
            FCB  $5C,0,150,OP_IDIV     ; backslash
            FCB  '&','&',25,OP_LAND
            FCB  '|','|',25,OP_LOR
            FCB  '&',0,50,OP_BAND
            FCB  '|',0,50,OP_BOR
            FCB  '!',0,50,OP_BOR
            FCB  '^',0,50,OP_BXOR
            FCB  0
;------------------------------------------------------------------------------
; X = the left operand (value 0-3, flags 4, adj 5-6), B = the operator, EVAL...
; = the right one: -> EVAL... = the result.
;------------------------------------------------------------------------------
APPLYOP     STB  <TMPB2
            LDA  4,X                   ; the flags
            ANDA <EVFLAGS
            ANDA #EF_KNOWN
            PSHS A
            LDA  4,X
            ORA  <EVFLAGS
            ANDA #EF_UNDEF|EF_COMPLEX
            ORA  ,S
            STA  ,S
            LDA  4,X                   ; inexactness (see PCX): only + and - keep a range
            ORA  <EVFLAGS
            BITA #EF_INEXACT
            BEQ  AO_EXACT
            LDB  <TMPB2
            CMPB #OP_PLUS
            BEQ  AO_XPLUS
            CMPB #OP_MINUS
            BEQ  AO_XMINUS
AO_XNONE    LDA  ,S
            ORA  #EF_INEXACT|EF_NORANGE
            STA  ,S
            BRA  AO_EXACT
AO_XPLUS    LDA  4,X
            ORA  <EVFLAGS
            ANDA #EF_INEXACT|EF_NORANGE
            ORA  ,S
            STA  ,S
            LDD  5,X
            ADDD <EVADJ
            STD  <EVADJ
            BRA  AO_EXACT
AO_XMINUS   LDA  <EVFLAGS              ; the right side inexact?
            BITA #EF_INEXACT
            BEQ  AO_XLEFT
            LDA  4,X                   ; both, by the same amount: it cancels
            BITA #EF_INEXACT
            BEQ  AO_XNONE
            ORA  <EVFLAGS
            BITA #EF_NORANGE
            BNE  AO_XNONE
            LDD  5,X
            CMPD <EVADJ
            BNE  AO_XNONE
            CLRD
            STD  <EVADJ
            BRA  AO_EXACT
AO_XLEFT    LDA  4,X
            ANDA #EF_INEXACT|EF_NORANGE
            ORA  ,S
            STA  ,S
            LDD  5,X
            STD  <EVADJ
AO_EXACT    PULS A
            STA  <EVFLAGS
            LDB  <TMPB2                ; now the value
            CMPB #OP_PLUS
            BEQ  AO_PLUS
            CMPB #OP_MINUS
            BEQ  AO_MINUS
            CMPB #OP_TIMES
            BEQ  AO_TIMES
            CMPB #OP_DIV
            BEQ  AO_DIV
            CMPB #OP_IDIV
            BEQ  AO_DIV
            CMPB #OP_MOD
            BEQ  AO_MOD
            CMPB #OP_LAND
            LBEQ AO_LAND
            CMPB #OP_LOR
            LBEQ AO_LOR
            CMPB #OP_BAND
            LBEQ AO_BAND
            CMPB #OP_BOR
            LBEQ AO_BOR
            LBRA AO_BXOR
AO_PLUS     LDQ  ,X
            ADDW <EVAL+2
            ADCD <EVAL
            STQ  <EVAL
            RTS
AO_MINUS    LDQ  ,X
            SUBW <EVAL+2
            SBCD <EVAL
            STQ  <EVAL
            RTS
AO_TIMES    LDQ  ,X
            STQ  <MA
            LDQ  <EVAL
            STQ  <MB
            JSR  MUL32
            LDQ  <MA
            STQ  <EVAL
            RTS
AO_DIV      BSR  AO_DIVIDE
            BCS  AO_ZERO
            LDQ  <MA
            STQ  <EVAL
            RTS
AO_MOD      BSR  AO_DIVIDE
            BCS  AO_ZERO
            LDQ  <MB
            STQ  <EVAL
            RTS
AO_ZERO     CLRD
            CLRW
            STQ  <EVAL
            RTS
AO_DIVIDE   LDQ  <EVAL                 ; carry set: dividing by zero (0, and an
            BNE  AO_DGO                ; error if both sides are known)
            LDA  <EVFLAGS
            BITA #EF_KNOWN
            BEQ  AO_DZ
            LDA  #ER_DIV0
            JSR  ERROR
AO_DZ       ORCC #1
            RTS
AO_DGO      STQ  <MB
            LDQ  ,X
            STQ  <MA
            JSR  DIV32
            ANDCC #$FE
            RTS
AO_LAND     BSR  AO_TRUTH
            ANDA ,S+
            BRA  AO_BOOL
AO_LOR      BSR  AO_TRUTH
            ORA  ,S+
AO_BOOL     TFR  A,F                   ; the value 0 or 1
            CLRE
            CLRD
            STQ  <EVAL
            RTS
; -> A = right != 0, and on the stack (under the return) left != 0.
AO_TRUTH    PULS Y                     ; (the return address)
            CLRA
            LDQ  ,X
            BEQ  AT_L0
            LDA  #1
AT_L0       PSHS A
            CLRA
            LDQ  <EVAL
            BEQ  AT_R0
            LDA  #1
AT_R0       JMP  ,Y
AO_BAND     LDD  ,X                    ; (no ANDW etc.: a word at a time)
            ANDD <EVAL
            STD  <EVAL
            LDD  2,X
            ANDD <EVAL+2
            STD  <EVAL+2
            RTS
AO_BOR      LDD  ,X
            ORD  <EVAL
            STD  <EVAL
            LDD  2,X
            ORD  <EVAL+2
            STD  <EVAL+2
            RTS
AO_BXOR     LDD  ,X
            EORD <EVAL
            STD  <EVAL
            LDD  2,X
            EORD <EVAL+2
            STD  <EVAL+2
            RTS
;------------------------------------------------------------------------------
; A term: parentheses, unary + - ~ ^, or lwasm's own terms (PTERM).
;------------------------------------------------------------------------------
TERM        LDX  <EXP
TM_AGAIN    LDA  ,X
            LBEQ TM_FAIL
            JSR  ISSPACE
            BCC  TM_FAIL
            CMPA #')'
            BEQ  TM_FAIL
            CMPA #']'
            BEQ  TM_FAIL
            CMPA #'('
            BEQ  TM_PAREN
            CMPA #'+'
            BEQ  TM_PLUS
            CMPA #'-'
            BEQ  TM_NEG
            CMPA #'^'
            BEQ  TM_COM
            CMPA #'~'
            BEQ  TM_COM
            JMP  PTERM
TM_PLUS     LEAX 1,X
            BRA  TM_AGAIN
TM_PAREN    LEAX 1,X
            STX  <EXP
            CLRA
            JSR  EXPRP
            BCS  TM_FAIL
            LDX  <EXP
            LDA  ,X
            CMPA #')'
            BNE  TM_FAIL
            LEAX 1,X
            STX  <EXP
            ANDCC #$FE
            RTS
TM_NEG      LEAX 1,X
            STX  <EXP
            CLR  <EVLIT
            LDA  #200
            JSR  EXPRP
            BCS  TM_FAIL
            LDX  #EVAL
            JSR  NEG32
            BRA  TM_UNX
TM_COM      LEAX 1,X
            STX  <EXP
            CLR  <EVLIT
            LDA  #200
            JSR  EXPRP
            BCS  TM_FAIL
            COM  <EVAL
            COM  <EVAL+1
            COM  <EVAL+2
            COM  <EVAL+3
            TST  <EXPW8                ; (an 8-bit immediate: ~ is 8 bits wide)
            BEQ  TM_UNX
            CLR  <EVAL
            CLR  <EVAL+1
            CLR  <EVAL+2
TM_UNX      LDA  <EVFLAGS              ; an inexact value loses its range
            BITA #EF_INEXACT
            BEQ  TM_OK
            ORA  #EF_NORANGE
            STA  <EVFLAGS
TM_OK       ANDCC #$FE
            RTS
TM_FAIL     ORCC #1
            RTS
; lwasm_parse_term: X at the term.
PTERM       CLRD                       ; a constant unless said otherwise
            CLRW
            STQ  <EVAL
            STD  <EVADJ
            LDB  #EF_KNOWN
            STB  <EVFLAGS
            LDA  ,X
            CMPA #'.'
            BNE  PT_STAR
            LDA  1,X                   ; "." alone: the address, like *
            JSR  ISALPHA
            LBCC PT_SYMNUM
            LDA  1,X
            JSR  ISDIGIT
            LBCC PT_SYMNUM
            BRA  PT_ADDR
PT_STAR     CMPA #'*'
            BNE  PT_BRPT
PT_ADDR     LEAX 1,X
            STX  <EXP
            CLR  <EVLIT
            LDD  <STARPC
            STD  <EVAL+2
            LDA  <PCX
            BEQ  PT_RET
            LDD  <PCADJ
            STD  <EVADJ
            LDA  #EF_KNOWN|EF_INEXACT
            STA  <EVFLAGS
PT_RET      ANDCC #$FE
            RTS
PT_BRPT     CMPA #'<'                  ; branch points: not supported
            BEQ  TM_FAIL
            CMPA #'>'
            BEQ  TM_FAIL
            CMPA #'"'
            BNE  PT_SQ
            LDA  1,X                   ; "cc: two characters
            BEQ  TM_FAIL
            LDB  2,X
            BEQ  TM_FAIL
            STD  <EVAL+2
            LEAX 3,X
            LDA  ,X
            CMPA #'"'
            BNE  PT_DONE
            LEAX 1,X
            BRA  PT_DONE
PT_SQ       CMPA #$27                  ; 'c
            BNE  PT_AMP
            LDB  1,X
            BEQ  TM_FAIL
            STB  <EVAL+3
            LEAX 2,X
            LDA  ,X
            CMPA #$27
            BNE  PT_DONE
            LEAX 1,X
PT_DONE     STX  <EXP
            ANDCC #$FE
            RTS
PT_AMP      CMPA #'&'                  ; &decimal
            BNE  PT_PCT
            LDB  #10
            BRA  PT_RADIX
PT_PCT      CMPA #'%'                  ; %binary
            BNE  PT_DOLLAR
            LDB  #2
            BRA  PT_RADIX
PT_DOLLAR   CMPA #'$'                  ; $hex
            BNE  PT_0X
            LDB  #16
            BRA  PT_RADIX
PT_0X       CMPA #'0'                  ; 0x hex
            BNE  PT_AT
            LDA  1,X
            CMPA #'x'
            BEQ  PT_0XGO
            CMPA #'X'
            BNE  PT_SYMNUM
PT_0XGO     LDA  2,X
            JSR  DIGITVAL
            CMPA #16
            BHS  PT_SYMNUM             ; (lwasm: no value -> NULL; it then fails)
            LEAX 2,X
            LDB  #16
            JSR  RADIXNUM
            LBRA PT_DONE
PT_AT       CMPA #'@'                  ; @octal (only with a digit 0-7 after it)
            BNE  PT_SYMNUM
            LDA  1,X
            CMPA #'0'
            BLO  PT_SYMNUM
            CMPA #'7'
            BHI  PT_SYMNUM
            LDB  #8
; A prefix-radix number: X at the prefix, B = the radix. An optional - after the
; prefix; at least one digit.
PT_RADIX    LEAX 1,X
            CLR  <NUMBIN               ; negative? (NUMBIN: free here)
            LDA  ,X
            CMPA #'-'
            BNE  PT_RDIG
            LEAX 1,X
            INC  <NUMBIN
PT_RDIG     LDA  ,X
            JSR  DIGITVAL
            PSHS B
            CMPA ,S+
            LBHS TM_FAIL
            JSR  RADIXNUM
            TST  <NUMBIN
            LBEQ PT_DONE
            PSHS X
            LDX  #EVAL
            JSR  NEG32
            PULS X
            LBRA PT_DONE
; A symbol, or a number with an optional suffix (lwasm's rules).
PT_SYMNUM   CLRB                       ; count the symbol characters
            CLR  <TMPB2                ; a $ among them?
            PSHS X
PS_COUNT    LDA  ,X
            JSR  ISSYM
            BCS  PS_COUNTED
            CMPA #'$'
            BNE  PS_NOTD
            INC  <TMPB2
PS_NOTD     LEAX 1,X
            INCB
            BRA  PS_COUNT
PS_COUNTED  LDA  ,X                    ; a {...} part belongs to the name
            CMPA #'{'
            BNE  PS_NOBRACE
PS_BRACE    LEAX 1,X
            INCB
            LDA  ,X
            BEQ  PS_NOBRACE
            CMPA #'}'
            BNE  PS_BRACE
            LEAX 1,X
            INCB
PS_NOBRACE  PULS X
            TSTB
            LBEQ TM_FAIL
            TST  <TMPB2
            BNE  PT_SYMBOL
            LDA  ,X
            JSR  ISDIGIT
            BCC  PT_NUMBER
PT_SYMBOL   CMPB #NAMEMAX              ; the name -> NAMEBUF
            BLS  PS_LEN
            LDB  #NAMEMAX
PS_LEN      LDY  #NAMEBUF
PS_COPY     LDA  ,X+
            STA  ,Y+
            DECB
            BNE  PS_COPY
            CLR  ,Y
PS_SKIPREST LDA  ,X                    ; (past the rest of an over-long name)
            JSR  ISSYM
            BCS  PS_GOT
            LEAX 1,X
            BRA  PS_SKIPREST
PS_GOT      STX  <EXP
            CLR  <EVLIT
            JSR  SYMVALUE
            ANDCC #$FE
            RTS
; A number: decimal, or with a base suffix; lwasm tries all four bases at once.
PT_NUMBER   PSHS X
            LDX  #NUMV
            LDW  #16
            LDY  #ZERO
            TFM  Y,X+
            PULS X
            LDA  #15                   ; 1 bin, 2 oct, 4 dec, 8 hex
            STA  <NUMTYPE
            CLR  <NUMBIN
PN_LOOP     LDA  ,X
            JSR  UPCASE
            JSR  ISNUMCH
            BCC  PN_CHAR
            TST  <NUMBIN               ; the end: binary, or decimal
            LBNE PN_BIN
            LDA  <NUMTYPE
            BITA #4
            LBEQ TM_FAIL
            LBRA PN_DEC
PN_CHAR     LEAX 1,X
            TST  <NUMBIN               ; anything after a B: it wasn't binary
            BEQ  PN_SW
            CLR  <NUMBIN
            LDB  <NUMTYPE
            ANDB #14
            STB  <NUMTYPE
PN_SW       CMPA #'Q'
            LBEQ PN_OCT
            CMPA #'O'
            LBEQ PN_OCT
            CMPA #'H'
            LBEQ PN_HEX
            CMPA #'B'
            BNE  PN_DIGIT
            LDB  <NUMTYPE              ; B: maybe the end of a binary number
            BITB #1
            BEQ  PN_DIGIT
            INC  <NUMBIN
            LDB  #9
            STB  <NUMTYPE
PN_DIGIT    SUBA #'0'
            CMPA #9
            BLS  PN_D9
            SUBA #7
PN_D9       STA  <TMPB2
            LDB  <NUMTYPE
            BITB #8
            BEQ  PN_NOHEX
            LDY  #NUMV+8
            LDB  #16
            JSR  NUMACC
PN_NOHEX    LDB  <NUMTYPE
            BITB #4
            BEQ  PN_NODEC
            LDA  <TMPB2
            CMPA #9
            BLS  PN_DECOK
            ANDB #11
            STB  <NUMTYPE
            BRA  PN_NODEC
PN_DECOK    LDY  #NUMV
            LDB  #10
            JSR  NUMACC
PN_NODEC    LDB  <NUMTYPE
            BITB #2
            BEQ  PN_NOOCT
            LDA  <TMPB2
            CMPA #7
            BLS  PN_OCTOK
            ANDB #13
            STB  <NUMTYPE
            BRA  PN_NOOCT
PN_OCTOK    LDY  #NUMV+12
            LDB  #8
            JSR  NUMACC
PN_NOOCT    LDB  <NUMTYPE
            BITB #1
            BEQ  PN_NOBIN
            LDA  <TMPB2
            CMPA #1
            BLS  PN_BINOK
            ANDB #14
            STB  <NUMTYPE
            BRA  PN_NOBIN
PN_BINOK    LDY  #NUMV+4
            LDB  #2
            JSR  NUMACC
PN_NOBIN    TST  <NUMTYPE
            LBEQ TM_FAIL
            LBRA PN_LOOP
PN_OCT      LDA  <NUMTYPE
            BITA #2
            LBEQ TM_FAIL
            LDY  #NUMV+12
            BRA  PN_VAL
PN_HEX      LDA  <NUMTYPE
            BITA #8
            LBEQ TM_FAIL
            LDY  #NUMV+8
            BRA  PN_VAL
PN_BIN      LDY  #NUMV+4
            BRA  PN_VAL
PN_DEC      LDY  #NUMV
PN_VAL      LDQ  ,Y
            STQ  <EVAL
            LBRA PT_DONE
; Carry clear if A (upper case) is one of 0-9 A-F H O Q.
ISNUMCH     JSR  ISDIGIT
            BCC  NC_RET
            CMPA #'A'
            BLO  NC_NO
            CMPA #'F'
            BLS  NC_YES
            CMPA #'H'
            BEQ  NC_YES
            CMPA #'O'
            BEQ  NC_YES
            CMPA #'Q'
            BEQ  NC_YES
NC_NO       ORCC #1
            RTS
NC_YES      ANDCC #$FE
NC_RET      RTS
; Y = a 32-bit accumulator, B = the radix, TMPB2 = a digit: Y = Y * B + digit.
NUMACC      PSHS D,X
            PSHSW
            CLR  <MB                   ; MB = the radix
            CLR  <MB+1
            CLR  <MB+2
            STB  <MB+3
            LDQ  ,Y
            STQ  <MA
            JSR  MUL32
            LDQ  <MA
            ADDF <TMPB2                ; + the digit
            BCC  NA_NC1
            INCE
            BNE  NA_NC1
            ADDD #1
NA_NC1      STQ  ,Y
            PULSW
            PULS D,X,PC
; A = a character: -> A = its digit value (0-35), 99 if it isn't one.
DIGITVAL    JSR  UPCASE
            CMPA #'0'
            BLO  DV2_NO
            CMPA #'9'
            BLS  DV2_DIG
            CMPA #'A'
            BLO  DV2_NO
            CMPA #'Z'
            BHI  DV2_NO
            SUBA #'A'-10
            RTS
DV2_DIG     SUBA #'0'
            RTS
DV2_NO      LDA  #99
            RTS
; X at the first digit, B = the radix (2, 8, 10, 16): the digits -> EVAL, X past
; them.
RADIXNUM    PSHS B
            CLRD
            CLRW
            STQ  <EVAL
RN_LOOP     LDA  ,X
            JSR  DIGITVAL
            CMPA ,S
            BHS  RN_END
            STA  <TMPB2
            LDB  ,S
            LDY  #EVAL
            JSR  NUMACC
            LEAX 1,X
            BRA  RN_LOOP
RN_END      PULS B,PC
;------------------------------------------------------------------------------
; End of pa_expr.asm
;------------------------------------------------------------------------------
