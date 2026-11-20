;------------------------------------------------------------------------------
; cc1_lex.asm -- CC1: reading the .I file, its tokens, and the names.
;------------------------------------------------------------------------------
; The keywords, then the names a token can't tell (EXPECT's messages).
LEXINIT     LDD  #1
            STD  <LINENO
            LDA  #1
            STA  <ATBOL
            LDX  #KEYWORDS             ; each keyword's name gets its token
            LDB  #K_FIRST
LI_KW       TST  ,X
            BEQ  LI_RET
            PSHS B
            LDY  #NAMEBUF
            JSR  STRCPY                ; (X ends after its NUL)
            PSHS X
            JSR  INTERN
            LDB  2,S
            STB  NM_KW,X
            PULS X
            PULS B
            INCB
            BRA  LI_KW
LI_RET      RTS
KEYWORDS    FCN  "auto"
            FCN  "break"
            FCN  "case"
            FCN  "char"
            FCN  "const"
            FCN  "continue"
            FCN  "default"
            FCN  "do"
            FCN  "double"
            FCN  "else"
            FCN  "enum"
            FCN  "extern"
            FCN  "float"
            FCN  "for"
            FCN  "goto"
            FCN  "if"
            FCN  "int"
            FCN  "long"
            FCN  "register"
            FCN  "return"
            FCN  "short"
            FCN  "signed"
            FCN  "sizeof"
            FCN  "static"
            FCN  "struct"
            FCN  "switch"
            FCN  "typedef"
            FCN  "union"
            FCN  "unsigned"
            FCN  "void"
            FCN  "volatile"
            FCN  "while"
            FCN  "asm"
            FCN  "interrupt"
            FCN  "_Bool"
            FCB  0
;------------------------------------------------------------------------------
; Characters.
;------------------------------------------------------------------------------
; -> A = the next byte of the file; carry set at its end. Keeps B, X, Y, U.
INBYTE      TST  <RAWF
            BEQ  IB_BUF
            CLR  <RAWF
            LDA  <RAWC
            ANDCC #$FE
            RTS
IB_BUF      PSHS B,X
            LDX  <INPOS
            CMPX <INEND
            BLO  IB_HAVE
            TST  <INEOF
            BNE  IB_END
            PSHS Y
            LDX  #INBUF
            LDY  #INBUFSZ
            LDB  <INH
            LDA  #B_FREAD
            SWI2
            PULS Y
            BCS  IB_EOF
            CMPX #0
            BEQ  IB_EOF
            TFR  X,D
            ADDD #INBUF
            STD  <INEND
            LDX  #INBUF
IB_HAVE     LDA  ,X+
            STX  <INPOS
            ANDCC #$FE
            PULS B,X,PC
IB_EOF      LDA  #1
            STA  <INEOF
IB_END      ORCC #1
            PULS B,X,PC
; -> A = the next character: CR LF, CR and LF are LF (and counted in LINENO).
; Carry set at the end. Keeps B, X, Y, U.
GETCH       TST  <UNGF
            BEQ  GC_READ
            CLR  <UNGF
            LDA  <UNGC
            ANDCC #$FE
            RTS
GC_READ     BSR  INBYTE
            BCS  GC_RET
            CMPA #CR
            BEQ  GC_CR
            CMPA #LF
            BEQ  GC_NL
            ANDCC #$FE
GC_RET      RTS
GC_CR       BSR  INBYTE
            BCS  GC_NL
            CMPA #LF
            BEQ  GC_NL
            STA  <RAWC
            LDA  #1
            STA  <RAWF
GC_NL       INC  <LINENO+1
            BNE  GC_LF
            INC  <LINENO
GC_LF       LDA  #LF
            ANDCC #$FE
            RTS
; A goes back, to be read again. Keeps every register.
UNGETCH     STA  <UNGC
            PSHS A
            LDA  #1
            STA  <UNGF
            PULS A,PC
; Carry clear if A may start a name (a letter or _), or be in one (ISIDCH: a
; digit too).
ISIDCH      JSR  ISDIGIT
            BCC  ID_RET
ISIDST      CMPA #'_'
            BEQ  ID_YES
            JMP  ISALPHA
ID_YES      ANDCC #$FE
ID_RET      RTS
; A = a hex digit -> A = its value; carry set if it isn't one.
HEXVAL      CMPA #'0'
            BLO  HV_NO
            CMPA #'9'
            BLS  HV_DIG
            ORA  #$20
            CMPA #'a'
            BLO  HV_NO
            CMPA #'f'
            BHI  HV_NO
            SUBA #'a'-10
            ANDCC #$FE
            RTS
HV_DIG      SUBA #'0'
            ANDCC #$FE
            RTS
HV_NO       ORCC #1
            RTS
;------------------------------------------------------------------------------
; Names: NAMEBUF -> X = its record (one per spelling, made the first time).
; FINDNAME: -> X = its record, or 0 (Z set) if there's none.
;------------------------------------------------------------------------------
INTERN      BSR  FINDNAME
            BEQ  IT_NEW
            RTS
FINDNAME    LDX  #NAMEBUF
            CLRB
HN_LOOP     LDA  ,X+
            BEQ  HN_END
            LSLB
            ADCB #0
            PSHS A
            EORB ,S+
            BRA  HN_LOOP
HN_END      CLRA
            LSLB
            ROLA
            LDX  #HASHTAB
            LEAX D,X
            STX  <TMP                  ; the bucket
            LDY  ,X
IT_LOOP     BEQ  IT_NONE
            LEAX NM_TEXT,Y
            PSHS Y
            LDY  #NAMEBUF
            JSR  STRCMP
            PULS Y
            BEQ  IT_FOUND
            LDY  NM_NEXT,Y
            BRA  IT_LOOP
IT_FOUND    LEAX ,Y
            RTS
IT_NONE     LDX  #0
            RTS
IT_NEW      LDX  #NAMEBUF
            JSR  STRLEN
            ADDD #NM_TEXT+1
            JSR  ALLOC
            LDY  <TMP
            LDD  ,Y
            STD  NM_NEXT,X
            STX  ,Y
            PSHS X
            LEAY NM_TEXT,X
            LDX  #NAMEBUF
            JSR  STRCPY
            PULS X,PC
;------------------------------------------------------------------------------
; Tokens. NEXT: the next token -> TOK etc. PEEK: -> A = the one after it
; (AHEAD etc.), which NEXT then takes.
;------------------------------------------------------------------------------
NEXT        TST  <AHEADF
            BNE  NX_AHEAD
            JSR  LEX
            LDX  #LXTOK
            BRA  NX_COPY
NX_AHEAD    CLR  <AHEADF
            LDX  #AHEAD
NX_COPY     LDY  #TOK
            LDW  #12
            TFM  X+,Y+
            RTS
PEEK        TST  <AHEADF
            BNE  PK_HAVE
            JSR  LEX
            LDX  #LXTOK
            LDY  #AHEAD
            LDW  #12
            TFM  X+,Y+
            LDA  #1
            STA  <AHEADF
PK_HAVE     LDA  <AHEAD
            RTS
; A = a token: the current one must be it (and is passed), or it's an error.
EXPECT      CMPA <TOK
            BNE  EP_BAD
            JMP  NEXT
EP_BAD      STA  <EXPECTED
            CMPA #T_ID
            BEQ  EP_ID
            CMPA #$7F
            BHS  EP_GEN
            LDX  #M_EXPECT             ; "expected 'c'"
            LDY  #ERRBUF
            JSR  STRCPY
            STA  ,Y+
            LDA  #$27
            STA  ,Y+
            CLR  ,Y
            LDX  #ERRBUF
            JMP  ERROR
EP_ID       LDX  #M_EXPID
            JMP  ERROR
EP_GEN      LDX  #M_SYNTAX
            JMP  ERROR
; A = a token: if it's the current one, it's passed and carry is clear.
ACCEPT      CMPA <TOK
            BNE  AC_NO
            JSR  NEXT
            ANDCC #$FE
            RTS
AC_NO       ORCC #1
            RTS
; -> A = the next character that isn't white space (a #line or #pragma at
; the start of a line is dealt with on the way). Carry set at the end.
SKIPBLANK   JSR  GETCH
            BCS  SB_RET
            CMPA #LF
            BEQ  SB_NL
            CMPA #' '
            BEQ  SKIPBLANK
            CMPA #9
            BEQ  SKIPBLANK
            CMPA #11
            BEQ  SKIPBLANK
            CMPA #12
            BEQ  SKIPBLANK
            TST  <ATBOL
            BEQ  SB_GOT
            CMPA #'#'
            BNE  SB_GOT
            JSR  DIRLINE
            BRA  SKIPBLANK
SB_NL       LDB  #1
            STB  <ATBOL
            BRA  SKIPBLANK
SB_GOT      CLR  <ATBOL
            ANDCC #$FE
SB_RET      RTS
; A line starting with #: "#line N "FILE"" (from CPP) sets the line number and
; the file; anything else (#pragma) is skipped for now.
DIRLINE     LDX  #DIRBUF
            LDB  #255
DL_READ     JSR  GETCH
            BCS  DL_END
            CMPA #LF
            BEQ  DL_END
            TSTB
            BEQ  DL_READ
            STA  ,X+
            DECB
            BRA  DL_READ
DL_END      CLR  ,X
            LDA  #1
            STA  <ATBOL
            LDX  #DIRBUF
            JSR  SKIPSP
            LDY  #S_LINE
            JSR  PREFIX
            BEQ  DL_NUM
            LDA  ,X
            JSR  ISDIGIT
            BCC  DL_NUM
            LDY  #S_PRAGMA             ; #pragma bank N: the functions after it
            JSR  PREFIX                ; are banked code, in ovlN (0: fixed)
            BNE  DL_RET
            JSR  SKIPSP
            LDY  #S_BANK
            JSR  PREFIX
            BNE  DL_RET
            JSR  SKIPSP
            LDA  ,X
            JSR  ISDIGIT
            BCS  DL_BADBANK
            JSR  GETDEC
            CMPD #15
            BHI  DL_BADBANK
            STB  <BANKNO
            RTS
DL_BADBANK  LDX  #M_BADBANK
            JMP  ERROR
DL_NUM      JSR  SKIPSP
            LDA  ,X
            JSR  ISDIGIT
            BCS  DL_RET
            JSR  GETDEC
            STD  <LINENO
            JSR  SKIPSP
            LDA  ,X+
            CMPA #'"'
            BNE  DL_RET
            LDY  #CURFILE
            LDB  #PATHMAX
DL_NAME     LDA  ,X+
            BEQ  DL_NEND
            CMPA #'"'
            BEQ  DL_NEND
            TSTB
            BEQ  DL_NAME
            STA  ,Y+
            DECB
            BRA  DL_NAME
DL_NEND     CLR  ,Y
DL_RET      RTS
; Z set if X starts with the (NUL-terminated) string at Y: X then past it.
PREFIX      PSHS X
PF_LOOP     LDA  ,Y+
            BEQ  PF_YES
            CMPA ,X+
            BEQ  PF_LOOP
            PULS X
            ANDCC #$FB
            RTS
PF_YES      LEAS 2,S
            ORCC #4
            RTS
; X at digits -> D = their value; X after them.
GETDEC      CLRD
            STD  <TMP
GD_LOOP     LDA  ,X
            JSR  ISDIGIT
            BCS  GD_END
            LEAX 1,X
            SUBA #'0'
            PSHS A
            LDD  <TMP
            LSLD
            PSHS D
            LSLD
            LSLD
            ADDD ,S++
            ADDB ,S+
            ADCA #0
            STD  <TMP
            BRA  GD_LOOP
GD_END      LDD  <TMP
            RTS
; The next token -> LXTOK etc.
LEX         CLR  <LXFL
            JSR  SKIPBLANK
            BCC  LX_TOK
            CLR  <LXTOK                ; the end: on the last line (the one
            LDD  <LINENO               ; before, if the file ended with its
            TST  <ATBOL                ; line's end)
            BEQ  LX_EOFLN
            CMPD #1
            BLS  LX_EOFLN
            SUBD #1
LX_EOFLN    STD  <LXLN
            RTS
LX_TOK      LDX  <LINENO
            STX  <LXLN
            JSR  ISIDST
            LBCC LX_ID
            JSR  ISDIGIT
            LBCC LX_NUM
            CMPA #'"'
            LBEQ LX_STR
            CMPA #$27
            LBEQ LX_CHR
            CMPA #'.'
            BEQ  LX_DOT
            STA  <TMPB                 ; punctuation: one character or two
            JSR  GETCH
            BCS  LX_ONE
            STA  <TMPB2
            LDX  #PUNCTAB
LP_LOOP     LDA  ,X
            BEQ  LP_NONE
            CMPA <TMPB
            BNE  LP_NEXT
            LDA  1,X
            CMPA <TMPB2
            BEQ  LP_GOT
LP_NEXT     LEAX 3,X
            BRA  LP_LOOP
LP_GOT      LDA  2,X
            CMPA #T_SHL
            BEQ  LP_3
            CMPA #T_SHR
            BNE  LP_SET
LP_3        PSHS A                     ; <<= and >>=
            JSR  GETCH
            BCS  LP_3NO
            CMPA #'='
            BEQ  LP_3YES
            JSR  UNGETCH
LP_3NO      PULS A
            BRA  LP_SET
LP_3YES     PULS A
            ADDA #T_SHLEQ-T_SHL
LP_SET      STA  <LXTOK
            RTS
LP_NONE     LDA  <TMPB2
            JSR  UNGETCH
LX_ONE      LDA  <TMPB
            LDX  #SINGLES
LO_LOOP     TST  ,X
            BEQ  LO_BAD
            CMPA ,X+
            BNE  LO_LOOP
            STA  <LXTOK
            RTS
LO_BAD      LDX  #M_STRAY
            JMP  ERROR
LX_DOT      JSR  GETCH                 ; . or ...
            BCS  LD_ONE
            CMPA #'.'
            BEQ  LD_TWO
            JSR  ISDIGIT
            LBCC LD_FLOAT
            JSR  UNGETCH
LD_ONE      LDA  #'.'
            STA  <LXTOK
            RTS
LD_TWO      JSR  GETCH
            BCS  LO_BAD
            CMPA #'.'
            BNE  LO_BAD
            LDA  #T_ELLIP
            STA  <LXTOK
            RTS
PUNCTAB     FCB  '+','+',T_INC,'+','=',T_ADDEQ
            FCB  '-','-',T_DEC,'-','=',T_SUBEQ,'-','>',T_ARROW
            FCB  '*','=',T_MULEQ,'/','=',T_DIVEQ,'%','=',T_MODEQ
            FCB  '<','<',T_SHL,'<','=',T_LE,'>','>',T_SHR,'>','=',T_GE
            FCB  '=','=',T_EQ,'!','=',T_NE
            FCB  '&','&',T_ANDAND,'&','=',T_ANDEQ,'|','|',T_OROR,'|','=',T_OREQ
            FCB  '^','=',T_XOREQ
            FCB  0
SINGLES     FCC  "()[]{};:?~!%^&*-+=|<>/"
            FCB  44,0                  ; (and ',')
; A name (A = its first character): a keyword's token, or T_ID (LXV = its
; record).
LX_ID       LDY  #NAMEBUF
            LDB  #NAMEMAX
LI_PUT      TSTB
            BEQ  LI_SKIP
            STA  ,Y+
            DECB
LI_SKIP     JSR  GETCH
            BCS  LI_END
            JSR  ISIDCH
            BCC  LI_PUT
            JSR  UNGETCH
LI_END      CLR  ,Y
            JSR  INTERN
            LDA  NM_KW,X
            BNE  LI_KWTOK
            STX  <LXV
            LDA  #T_ID
LI_KWTOK    STA  <LXTOK
            RTS
; A number (A = its first digit) -> LXV (32 bits), LXFL (u and l). With a .
; or an exponent it's a floating one: LXV its bits, LXFL TF_FLT. (Its digits
; are decimal whatever it began with, so they're kept that way too, in FLM
; and FLE, as they're read.)
LX_NUM      PSHS A
            CLRD
            STD  <LXV
            STD  <LXV+2
            STD  <FLM
            STD  <FLM+2
            STD  <FLE
            CLR  <FLOCT
            PULS A
            LDB  #10
            STB  <TMPB
            CMPA #'0'
            BNE  LN_CHK
            LDB  #8                    ; 0...: octal, or 0x: hex
            STB  <TMPB
            LDB  #TF_NDEC
            STB  <LXFL
            JSR  GETCH
            LBCS LN_END
            CMPA #'x'
            BEQ  LN_HEX
            CMPA #'X'
            BNE  LN_CHK
LN_HEX      LDB  #16
            STB  <TMPB
            JSR  GETCH
            LBCS LN_END
LN_CHK      PSHS A
            JSR  HEXVAL
            BCS  LN_NOT
            CMPA <TMPB
            BLO  LN_DIG
            LDB  <TMPB                 ; an 8 or 9 in an octal number: only a
            CMPB #8                    ; floating one's
            BNE  LN_NOT
            CMPA #9
            BHI  LN_NOT
            INC  <FLOCT
            BRA  LN_DEC
LN_DIG      PSHS A                     ; LXV = LXV * base + the digit
            LDQ  <LXV
            STQ  MA
            CLRD
            STD  MB
            LDB  <TMPB
            STD  MB+2
            JSR  MUL32
            LDB  ,S
            CLRA
            STD  <TMP
            LDQ  MA
            ADDW <TMP
            ADCD #0
            STQ  <LXV
            PULS A
LN_DEC      LEAS 1,S
            LDB  <TMPB
            CMPB #16
            BEQ  LN_NEXT
            CLRB
            JSR  FLDIGIT
LN_NEXT     JSR  GETCH
            BCS  LN_END
            BRA  LN_CHK
LN_NOT      PULS A
            LDB  <TMPB
            CMPB #16
            BEQ  LN_SUF
            CMPA #'.'
            LBEQ LX_FRAC
            CMPA #'e'
            LBEQ LX_EXP
            CMPA #'E'
            LBEQ LX_EXP
LN_SUF      CMPA #'u'                  ; u and l, in any order
            BEQ  LN_U
            CMPA #'U'
            BEQ  LN_U
            CMPA #'l'
            BEQ  LN_L
            CMPA #'L'
            BEQ  LN_L
            JSR  ISIDCH
            LBCC LN_BAD
            JSR  UNGETCH
            BRA  LN_END
LN_U        LDA  #TF_UNS
            BRA  LN_FL
LN_L        LDA  #TF_LONG
LN_FL       ORA  <LXFL
            STA  <LXFL
            JSR  GETCH
            BCC  LN_SUF
LN_END      TST  <FLOCT
            LBNE LN_BAD
            LDA  #T_NUM
            STA  <LXTOK
            RTS
; A floating constant: ".5" (A = its first digit), or after a number's digits
; its . or e.
LD_FLOAT    PSHS A
            CLRD
            STD  <FLM
            STD  <FLM+2
            STD  <FLE
            PULS A
            BRA  LF_DIGIT
LX_FRAC     JSR  GETCH                 ; the digits after the point
            LBCS LF_END
            JSR  ISDIGIT
            BCS  LF_NOTDIG
LF_DIGIT    SUBA #'0'
            LDB  #1
            JSR  FLDIGIT
            BRA  LX_FRAC
LF_NOTDIG   CMPA #'e'
            BEQ  LX_EXP
            CMPA #'E'
            BNE  LF_SUF
LX_EXP      CLRD                       ; e, a sign, digits (at least one)
            STD  <FLX
            CLR  <TMPB2
            JSR  GETCH
            LBCS LN_BAD
            CMPA #'+'
            BEQ  LE_SIGN
            CMPA #'-'
            BNE  LE_FIRST
            INC  <TMPB2
LE_SIGN     JSR  GETCH
            LBCS LN_BAD
LE_FIRST    JSR  ISDIGIT
            LBCS LN_BAD
LE_DIG      SUBA #'0'
            TFR  A,B
            CLRA
            PSHS D
            LDD  <FLX                  ; (it stops growing at 1000: 0 or
            CMPD #1000                 ; infinite anyway)
            BHS  LE_SKIP
            LSLD
            PSHS D
            LSLD
            LSLD
            ADDD ,S++
            ADDD ,S
            STD  <FLX
LE_SKIP     LEAS 2,S
            JSR  GETCH
            PSHS CC,A
            BCS  LE_SUM
            JSR  ISDIGIT
            BCS  LE_SUM
            LEAS 2,S
            BRA  LE_DIG
LE_SUM      LDD  <FLX                  ; FLE += the exponent
            TST  <TMPB2
            BEQ  LE_POS
            NEGD
LE_POS      ADDD <FLE
            STD  <FLE
            PULS CC,A
            BCS  LF_END
LF_SUF      CMPA #'f'                  ; f or l (float, long double: both
            BEQ  LF_SUF1               ; the same)
            CMPA #'F'
            BEQ  LF_SUF1
            CMPA #'l'
            BEQ  LF_SUF1
            CMPA #'L'
            BNE  LF_SUF2
LF_SUF1     JSR  GETCH
            BCS  LF_END
LF_SUF2     JSR  ISIDCH
            BCC  LN_BAD
            JSR  UNGETCH
LF_END      LDQ  <FLM                  ; FLM * 10^FLE
            LDX  <FLE
            JSR  __fdec2f
            STQ  <LXV
            LDA  #TF_FLT
            STA  <LXFL
            LDA  #T_NUM
            STA  <LXTOK
            RTS
; A = a digit, B = 1 if it's after the point: FLM = FLM * 10 + it while
; there's room (FLE one less after the point); when there isn't, it's
; dropped (FLE one more before the point).
FLDIGIT     PSHS B
            TFR  A,B
            CLRA
            STD  <TMP3
            LDX  <FLM
            CMPX #$17D7                ; (400000000: room for one more)
            BLO  FG_ADD
            BHI  FG_DROP
            LDX  <FLM+2
            CMPX #$8400
            BHS  FG_DROP
FG_ADD      LDQ  <FLM
            ADDR W,W
            ROLD
            STQ  MA
            ADDR W,W
            ROLD
            ADDR W,W
            ROLD
            ADDW MA+2
            ADCD MA
            ADDW <TMP3
            ADCD #0
            STQ  <FLM
            TST  ,S+
            BEQ  FG_RET
            LDX  <FLE
            LEAX -1,X
            STX  <FLE
FG_RET      RTS
FG_DROP     TST  ,S+
            BNE  FG_RET
            LDX  <FLE
            LEAX 1,X
            STX  <FLE
            RTS
LN_BAD      LDX  #M_BADNUM
            JMP  ERROR
; A character constant (its value is a char's, so '\xff' is -1).
LX_CHR      JSR  GETCH
            BCS  LC_BAD
            CMPA #LF
            BEQ  LC_BAD
            CMPA #$27
            BEQ  LC_BAD
            CMPA #'\'
            BNE  LC_VAL
            JSR  LXESC
LC_VAL      PSHS A
            JSR  GETCH
            BCS  LC_BAD
            CMPA #$27
            BNE  LC_BAD
            PULS B
            SEX
            STD  <LXV+2
            TFR  A,B
            STD  <LXV
            LDA  #TF_CHAR
            STA  <LXFL
            LDA  #T_NUM
            STA  <LXTOK
            RTS
LC_BAD      LDX  #M_BADCHR
            JMP  ERROR
; After a backslash: the escape -> A.
LXESC       JSR  GETCH
            BCS  LE_RET
            PSHS X
            LDX  #ESCTAB
LE_LOOP     TST  ,X
            BEQ  LE_OTHER
            CMPA ,X++
            BNE  LE_LOOP
            LDA  -1,X
            PULS X,PC
LE_OTHER    PULS X
            CMPA #'x'
            BEQ  LE_HEX
            CMPA #'0'
            BLO  LE_RET
            CMPA #'7'
            BHI  LE_RET
            SUBA #'0'                  ; up to three octal digits
            PSHS B
            LDB  #2
LE_OL       STA  <TMPB2
            JSR  GETCH
            BCS  LE_OEND
            CMPA #'0'
            BLO  LE_OUN
            CMPA #'7'
            BHI  LE_OUN
            SUBA #'0'
            PSHS A
            LDA  <TMPB2
            LSLA
            LSLA
            LSLA
            ORA  ,S+
            DECB
            BNE  LE_OL
            PULS B,PC
LE_OUN      JSR  UNGETCH
LE_OEND     LDA  <TMPB2
            PULS B,PC
LE_HEX      PSHS B
            CLR  <TMPB2
LE_HL       JSR  GETCH
            BCS  LE_HEND
            PSHS A
            JSR  HEXVAL
            BCS  LE_HUN
            LEAS 1,S
            LDB  <TMPB2
            LSLB
            LSLB
            LSLB
            LSLB
            PSHS A
            ORB  ,S+
            STB  <TMPB2
            BRA  LE_HL
LE_HUN      PULS A
            JSR  UNGETCH
LE_HEND     LDA  <TMPB2
            PULS B,PC
LE_RET      RTS
ESCTAB      FCB  'n',10,'t',9,'r',13,'a',7,'b',8,'f',12,'v',11,0
; A string literal (the ones right after it are joined on) -> LXSB, LXSL.
LX_STR      LDX  #STRB0                ; (the buffer the current token isn't
            CMPX <TOKSB                ; using)
            BNE  LS_BUF
            LDX  #STRB1
LS_BUF      STX  <LXSB
            LEAY ,X
            LEAX STRMAX,X
            STX  <TMP3                 ; the limit
LS_LOOP     JSR  GETCH
            BCS  LS_UNT
            CMPA #LF
            BEQ  LS_UNT
            CMPA #'"'
            BEQ  LS_CLOSE
            CMPA #'\'
            BNE  LS_PUT
            JSR  LXESC
LS_PUT      CMPY <TMP3
            BHS  LS_LONG
            STA  ,Y+
            BRA  LS_LOOP
LS_CLOSE    PSHS Y                     ; another one next?
            JSR  SKIPBLANK             ; (a #line on the way uses Y)
            PULS Y
            BCS  LS_DONE
            CMPA #'"'
            BEQ  LS_LOOP
            JSR  UNGETCH
LS_DONE     CLR  ,Y
            TFR  Y,D
            SUBD <LXSB
            STD  <LXSL
            LDA  #T_STR
            STA  <LXTOK
            RTS
LS_UNT      LDX  #M_UNTSTR
            JMP  ERROR
LS_LONG     LDX  #M_LONGSTR
            JMP  ERROR
;------------------------------------------------------------------------------
; -T: the tokens, one a line: the line number, the token's number, and what it
; holds (a name, a number, a string's bytes in hex).
;------------------------------------------------------------------------------
TOKDUMP     LDU  #OUTSTRM
TD_LOOP     LDD  <TOKLN
            JSR  TD_DEC
            LDA  #' '
            JSR  SPUTC
            LDX  #NUMBUF
            LDA  <TOK
            JSR  HEX2
            CLR  ,X
            LDX  #NUMBUF
            JSR  SPUTS
            LDA  <TOK
            CMPA #T_ID
            BEQ  TD_ID
            CMPA #T_NUM
            BEQ  TD_NUM
            CMPA #T_STR
            BEQ  TD_STR
            CMPA #K_FIRST
            BHS  TD_KW
TD_NL       JSR  SPUTNL
            LDA  <TOK
            BEQ  TD_RET
            JSR  NEXT
            LDU  #OUTSTRM
            BRA  TD_LOOP
TD_RET      RTS
TD_KW       LDA  #' '
            JSR  SPUTC
            LDX  #KEYWORDS             ; (the keyword's spelling)
            LDB  <TOK
            SUBB #K_FIRST
TD_KWL      TSTB
            BEQ  TD_KWP
TD_KWS      TST  ,X+
            BNE  TD_KWS
            DECB
            BRA  TD_KWL
TD_KWP      JSR  SPUTS
            BRA  TD_NL
TD_ID       LDA  #' '
            JSR  SPUTC
            LDX  <TOKV
            LEAX NM_TEXT,X
            JSR  SPUTS
            BRA  TD_NL
TD_NUM      LDA  #' '
            JSR  SPUTC
            LDX  #NUMBUF
            LDD  <TOKV
            JSR  HEX4
            LDD  <TOKV+2
            JSR  HEX4
            LDA  #' '
            STA  ,X+
            LDA  <TOKFL
            JSR  HEX2
            CLR  ,X
            LDX  #NUMBUF
            JSR  SPUTS
            BRA  TD_NL
TD_STR      LDA  #' '
            JSR  SPUTC
            LDY  <TOKSB
            LDD  <TOKSL
            JSR  TD_DEC
            LDA  #':'
            JSR  SPUTC
            LDW  <TOKSL
TD_SL       TSTW
            BEQ  TD_NL
            LDX  #NUMBUF
            LDA  ,Y+
            JSR  HEX2
            CLR  ,X
            LDX  #NUMBUF
            JSR  SPUTS
            DECW
            BRA  TD_SL
TD_DEC      LDX  #NUMBUF
            JSR  DECSTR
            LDX  #NUMBUF
            JMP  SPUTS
;------------------------------------------------------------------------------
M_EXPECT    FCC  "expected "
            FCB  $27,0
M_EXPID     FCN  "expected a name"
M_SYNTAX    FCN  "syntax error"
M_STRAY     FCN  "stray character in the program"
M_BADNUM    FCN  "invalid number"
M_BADCHR    FCN  "invalid character constant"
M_UNTSTR    FCN  "unterminated string"
M_LONGSTR   FCN  "string too long"
S_LINE      FCN  "line"
S_PRAGMA    FCN  "pragma"
S_BANK      FCN  "bank"
M_BADBANK   FCN  "#pragma bank needs a number from 0 to 15"
;------------------------------------------------------------------------------
; End of cc1_lex.asm
;------------------------------------------------------------------------------
