;------------------------------------------------------------------------------
; pa_line.asm -- pugasm: one source line (lwasm's pass-1 rules for what is a
; label, an operation and an operand), emitting bytes, errors, the listing.
;------------------------------------------------------------------------------
DOLINE      LDD  <LSEQ
            ADDD #1
            STD  <LSEQ
            STD  <CUTSEQ
            LDD  <PC
            STD  <LADDR
            STD  <STARPC
            CLRD
            STD  <NBYTES
            CLR  <LABEL
            CLR  <SYMSET
            CLR  <LINEERR
            CLR  <OPCLASS
            CLR  <OPFLAGS
            CLR  <NOMACRO
            CLR  <LSHOW
            CLR  <LSOFFON
            CLR  <EXPW8
            CLR  <HASOP
            LDA  <PCX                  ; (a label goes by the line's start)
            STA  <LPCX
            LDD  <PCADJ
            STD  <LPCADJ
            LDA  <INMACRO
            STA  <WASMACRO
            LDX  #LINEBUF
            LDA  ,X
            LBEQ DL_BLANK
            JSR  ISCOMMENT
            LBEQ DL_NEXT
            JSR  ISDIGIT               ; a line number (digits, then a space)?
            BCS  DL_NOLN
            TFR  X,Y
DL_LNDIG    LEAY 1,Y
            LDA  ,Y
            JSR  ISDIGIT
            BCC  DL_LNDIG
            LDA  ,Y
            BEQ  DL_NOLN
            JSR  ISSPACE
            BCS  DL_NOLN
            LEAX 1,Y
DL_NOLN     LDA  ,X
            LBEQ DL_BLANK
            JSR  ISCOMMENT
            LBEQ DL_NEXT
            CLR  <TMPB                 ; the line starts with a space?
            JSR  ISSPACE
            BCS  DL_TOK
            INC  <TMPB
            JSR  SKIPSP
            LDA  ,X
            LBEQ DL_BLANK
DL_TOK      TFR  X,Y                   ; Y = the first token
DL_TEND     LDA  ,X
            BEQ  DL_TENDED
            CMPA #':'
            BEQ  DL_TENDED
            CMPA #'='
            BEQ  DL_TENDED
            JSR  ISSPACE
            BCC  DL_TENDED
            LEAX 1,X
            BRA  DL_TEND
DL_TENDED   LDA  ,X                    ; a label: at the start of the line, or
            CMPA #':'                  ; followed by : or =
            BEQ  DL_LABEL
            CMPA #'='
            BEQ  DL_LABEL
            TST  <TMPB
            BNE  DL_OPTOK              ; no label: Y..X is the operation
DL_LABEL    LDA  ,Y
            JSR  ISCOMMENT
            LBEQ DL_NEXT
            PSHS X                     ; the label -> LABELNAME
            TFR  X,D
            PSHS Y
            SUBD ,S++                  ; its length
            LDX  #LABELNAME
            JSR  COPYN
            PULS X
            LDA  #1
            STA  <LABEL
            LDA  ,X
            CMPA #':'
            BNE  DL_AFTERL
            LEAX 1,X
DL_AFTERL   JSR  SKIPSP
            TFR  X,Y
            LDA  ,X
            CMPA #'='
            BNE  DL_OPSCAN
            LEAX 1,X                   ; "=": an operation of one character
            BRA  DL_OPTOK
DL_OPSCAN   LDA  ,X
            BEQ  DL_OPTOK
            JSR  ISSPACE
            BCC  DL_OPTOK
            LEAX 1,X
            BRA  DL_OPSCAN
DL_OPTOK    LDA  <LABEL                ; "!" is a breakpoint marker, not a label
            BEQ  DL_OPNAME
            LDD  LABELNAME
            CMPD #$2100
            BNE  DL_OPNAME
            CLR  <LABEL
DL_OPNAME   STY  <OPTOK                ; the operation: Y..X
            STX  <OPTOKEND
            LDA  ,Y                    ; ?? before it: no macro expansion
            CMPA #'?'
            BNE  DL_NOQQ
            LDA  1,Y
            CMPA #'?'
            BNE  DL_NOQQ
            LEAY 2,Y
            STY  <OPTOK
            INC  <NOMACRO
DL_NOQQ     CMPX <OPTOK
            LBLS DL_LINEDONE           ; no operation
            INC  <HASOP
            JSR  SKIPSP                ; the operand
            STX  <OPERP
            STX  <EXP
            JSR  OPLOOKUP              ; -> OPCLASS etc., carry if unknown
            BCC  DL_KNOWN
            LDA  [OPTOK]               ; an unknown "operation" that is a comment
            JSR  ISCOMMENT
            LBEQ DL_LINEDONE
DL_KNOWN    TST  <INMACRO              ; inside a macro definition: only ENDM counts
            BEQ  DL_NOTMAC
            LDA  <OPFLAGS
            BITA #OF_ENDM
            LBEQ DL_LINEDONE
DL_NOTMAC   TST  <SKIPCOND             ; skipping: only conditionals count
            BEQ  DL_NOTSKIP
            LDA  <OPFLAGS
            BITA #OF_COND
            LBEQ DL_LINEDONE
DL_NOTSKIP  TST  <OPCLASS
            BEQ  DL_OTHER
            LDA  <OPFLAGS              ; the other CPU's instruction?
            TST  <CPU
            BEQ  DL_ON6309
            BITA #OF_IS6309
            BNE  DL_OTHER
            BRA  DL_DOIT
DL_ON6309   BITA #OF_IS6809
            BNE  DL_OTHER
DL_DOIT     TST  <INSTRUCT             ; in a struct, only struct operations
            BEQ  DL_CALL
            BITA #OF_STRUCT
            BNE  DL_CALL
            LDA  #ER_BADOPND
            JSR  ERROR
            BRA  DL_LINEDONE
DL_CALL     JSR  DISPATCH
            LDX  <EXP                  ; the operand must be all used
            LDA  ,X
            BEQ  DL_LINEDONE
            JSR  ISSPACE
            BCC  DL_LINEDONE
            TST  <LINEERR
            BNE  DL_LINEDONE
            LDA  #ER_BADOPND
            JSR  ERROR
            BRA  DL_LINEDONE
DL_OTHER    LDA  [OPTOK]               ; not an operation: a macro, a struct?
            CMPA #';'
            BEQ  DL_LINEDONE
            CMPA #'*'
            BEQ  DL_LINEDONE
            TST  <NOMACRO
            BNE  DL_NOTMACRO
            JSR  MACEXPAND
            BCC  DL_LINEDONE
DL_NOTMACRO JSR  STRUCTINST
            BCC  DL_LINEDONE
            LDA  #ER_BADOP
            TST  <OPCLASS
            BEQ  DL_BADOP
            LDA  #ER_6309ONLY          ; (the wrong CPU)
            TST  <CPU
            BNE  DL_BADOP
            LDA  #ER_6809ONLY
DL_BADOP    JSR  ERROR
DL_LINEDONE TST  <WASMACRO             ; a line of a macro being defined
            BEQ  DL_NOADD
            TST  <INMACRO
            BEQ  DL_NOADD
            JSR  MACADDLINE
DL_NOADD    TST  <SKIPCOND
            BNE  DL_NEXT
            TST  <INMACRO
            BNE  DL_NEXT
            TST  <LABEL
            BEQ  DL_NEXT
            TST  <SYMSET
            BNE  DL_NEXT
            LDX  #LABELNAME            ; the label: this line's address
            LDY  #NAMEBUF
            JSR  STRCPY
            CLRD
            STD  <EVAL
            LDD  <LADDR
            STD  <EVAL+2
            LDA  #EF_KNOWN
            LDB  <LPCX
            BEQ  DL_LEXACT
            ORA  #EF_INEXACT
DL_LEXACT   STA  <EVFLAGS
            LDD  <LPCADJ
            STD  <EVADJ
            CLRA
            JSR  SYMDEF
DL_NEXT     LDA  <PASS
            CMPA #2
            BNE  DL_RET
            TST  <NXLEVEL
            BNE  NXHOLD
            TST  <LISTON
            BEQ  DL_RET
            JMP  LISTLINE
DL_RET      RTS
; Inside a noexpand macro (pass 2): the line isn't listed, its bytes are kept
; for the calling line (kept here too, when it's the calling line).
NXHOLD      TST  <NXSTART
            BEQ  NH_BYTES
            CLR  <NXSTART
            LDX  #LINEBUF
            LDY  #NXLINE
            JSR  STRCPY
            LDD  <LADDR
            STD  <NXADDR
            LDD  <CURSPEC
            STD  <NXSPEC
            LDD  <CURLNO
            STD  <NXLNO
            LDA  <LABEL
            STA  <NXLAB
            LDA  <SYMSET
            STA  <NXSYMSET
            CLRD
            STD  <NXCNT
NH_BYTES    LDX  #LBYTES
            LDD  <NBYTES
            ADDD <NXCNT
            PSHS D                     ; the new count
NH_LOOP     LDD  <NXCNT
            CMPD ,S
            BHS  NH_DONE
            CMPD #256
            BHS  NH_SKIP
            LDY  #NXBYTES
            LEAY D,Y
            LDA  ,X+
            STA  ,Y
NH_SKIP     LDD  <NXCNT
            ADDD #1
            STD  <NXCNT
            BRA  NH_LOOP
NH_DONE     PULS D,PC
; The noexpand macro is over: its calling line is listed with all its bytes.
NXFLUSH     CLR  <NXLEVEL
            TST  <LISTON
            BEQ  NF_RET
            LDX  #NXLINE
            LDY  #LINEBUF
            JSR  STRCPY
            LDX  #NXBYTES
            LDY  #LBYTES
            LDW  #256
            TFM  X+,Y+
            LDD  <NXCNT
            STD  <NBYTES
            LDD  <NXADDR
            STD  <LADDR
            LDD  <NXSPEC
            STD  <CURSPEC
            LDD  <NXLNO
            STD  <CURLNO
            LDA  <NXLAB
            STA  <LABEL
            LDA  <NXSYMSET
            STA  <SYMSET
            CLR  <LSOFFON
            CLR  <LSHOW
            LDD  <PC
            PSHS D
            LDD  <LADDR
            STD  <PC
            JSR  LISTLINE
            PULS D
            STD  <PC
NF_RET      RTS
DL_BLANK    JSR  NEWCONTEXT            ; a blank line: a new local-symbol context
            LBRA DL_NEXT
; Z set if A is a comment character (* ; #).
ISCOMMENT   CMPA #'*'
            BEQ  IC2_RET
            CMPA #';'
            BEQ  IC2_RET
            CMPA #'#'
IC2_RET     RTS
NEWCONTEXT  LDD  <NEXTCTX
            ADDD #1
            STD  <NEXTCTX
            STD  <CONTEXT
            RTS
; Y = characters, D = how many, X = where: copied, NUL-terminated (at most
; NAMEMAX).
COPYN       CMPD #NAMEMAX
            BLS  CN_LEN
            LDD  #NAMEMAX
CN_LEN      TFR  B,A
            TSTA
            BEQ  CN_END
CN_LOOP     LDB  ,Y+
            STB  ,X+
            DECA
            BNE  CN_LOOP
CN_END      CLR  ,X
            RTS
;------------------------------------------------------------------------------
; The operation OPTOK..OPTOKEND -> OPENTRY, OPCLASS, OPFLAGS, OPSP (its opcodes);
; carry set (OPCLASS 0) if there's no such operation.
;------------------------------------------------------------------------------
OPLOOKUP    LDY  <OPTOK                ; upper case -> OPNAME
            LDX  #OPNAME
            LDB  #15
OL_COPY     CMPY <OPTOKEND
            BHS  OL_COPIED
            LDA  ,Y+
            JSR  UPCASE
            STA  ,X+
            DECB
            BNE  OL_COPY
            BRA  OL_NONE               ; too long to be one
OL_COPIED   CLR  ,X
            LDD  #0                    ; binary search: TMP = low, TMP2 = high
            STD  <TMP
            LDD  #OPCOUNT-1
            STD  <TMP2
OL_LOOP     LDD  <TMP
            CMPD <TMP2
            BGT  OL_NONE
            ADDD <TMP2
            LSRA
            RORB
            STD  <TMP3                 ; the middle
            ASLB
            ROLA
            LDX  #OPINDEX
            LDX  D,X                   ; its entry
            JSR  OPCMP                 ; OPNAME vs the entry: A < 0, = 0, > 0
            BEQ  OL_FOUND
            BMI  OL_LOWER
            LDD  <TMP3
            ADDD #1
            STD  <TMP
            BRA  OL_LOOP
OL_LOWER    LDD  <TMP3
            SUBD #1
            STD  <TMP2
            BRA  OL_LOOP
OL_FOUND    STX  <OPENTRY
            LDB  ,X                    ; past the name
            INCB
            ABX
            LDD  ,X
            STA  <OPCLASS
            STB  <OPFLAGS
            LEAX 2,X
            STX  <OPSP
            ANDCC #$FE
            RTS
OL_NONE     CLR  <OPCLASS
            CLR  <OPFLAGS
            ORCC #1
            RTS
; OPNAME against the table entry at X: -> A negative, zero or positive, as
; OPNAME sorts before, equal to or after it. Keeps X.
OPCMP       PSHS X
            LDB  ,X+                   ; its length
            LDY  #OPNAME
OC_LOOP     TSTB
            BEQ  OC_END                ; the entry's name is done
            LDA  ,Y+
            BEQ  OC_LESS               ; OPNAME is done first: it sorts before
            CMPA ,X+
            BLO  OC_LESS
            BHI  OC_MORE
            DECB
            BRA  OC_LOOP
OC_END      LDA  ,Y
            BEQ  OC_EQ
OC_MORE     LDA  #1
            PULS X,PC
OC_LESS     LDA  #-1
            PULS X,PC
OC_EQ       CLRA
            PULS X,PC
; Calls the handler for OPCLASS.
DISPATCH    LDB  <OPCLASS
            CMPB #CL_DIRECTIVE
            BHS  DS2_DIR
            DECB
            ASLB
            LDX  #INSNHAND
            JMP  [B,X]
DS2_DIR     CMPB #CL_UNSUP
            BEQ  DS2_UNSUP
            SUBB #CL_DIRECTIVE
            CLRA
            ASLB
            ROLA
            LDX  #DIRHAND
            LEAX D,X
            JMP  [,X]
DS2_UNSUP   JSR  SKIPOPND
            LDA  #ER_UNSUP
            JMP  ERROR
; EXP: past the operand (to a space or the end).
SKIPOPND    LDX  <EXP
SO2_LOOP    LDA  ,X
            BEQ  SO2_END
            JSR  ISSPACE
            BCC  SO2_END
            LEAX 1,X
            BRA  SO2_LOOP
SO2_END     STX  <EXP
            RTS
;------------------------------------------------------------------------------
; Bytes. EMITB puts A at PC (pass 2: into the output and the listing) and moves
; PC on; RESERVE moves PC on by D without bytes (RMB).
;------------------------------------------------------------------------------
EMITB       PSHS D,X
            TST  <FIRSTOUT             ; the first byte of the output: where it
            BEQ  EB_NOTFIRST           ; starts (reserved space before it counts)
            CLR  <FIRSTOUT
            LDD  <PC
            SUBD <RAWZERO
            STD  <FIRSTADDR
            LDB  <PASS
            CMPB #2
            BNE  EB_NOTFIRST
            JSR  OUTSTART
EB_NOTFIRST LDB  <PASS
            CMPB #2
            BNE  EB_PC
            LDD  <NBYTES               ; for the listing
            CMPD #256
            BHS  EB_NOBUF
            LDX  #LBYTES
            LEAX D,X
            LDA  ,S
            STA  ,X
EB_NOBUF    LDD  <NBYTES
            ADDD #1
            STD  <NBYTES
            LDA  ,S
            JSR  OUTBYTE               ; (pa_out.asm) at PC
EB_PC       LDD  <PC
            ADDD #1
            STD  <PC
            PULS D,X,PC
RESERVE     PSHS D
            TST  <FIRSTOUT             ; before the first byte: counted (raw
            BEQ  RS_AFTER              ; output writes zeros for it then)
            LDD  <RAWZERO
            ADDD ,S
            STD  <RAWZERO
            BRA  RS_PC
RS_AFTER    LDB  <PASS
            CMPB #2
            BNE  RS_PC
            LDD  ,S
            JSR  OUTSKIP               ; (pa_out.asm)
RS_PC       LDD  <PC
            ADDD ,S++
            STD  <PC
            RTS
; D = an opcode (one or two bytes): emitted.
EMITOP      TSTA
            BEQ  EO_ONE
            PSHS B
            JSR  EMITB
            PULS B
EO_ONE      TFR  B,A
            JMP  EMITB
; B = an index 0-3: -> D = that opcode of the operation.
GETOP       LDX  <OPSP
            ASLB
            LDD  B,X
            RTS
; D = an opcode: -> B = its length (1 or 2).
OPLEN       TSTA
            BEQ  OPL_ONE
            LDB  #2
            RTS
OPL_ONE     LDB  #1
            RTS
; A = 1, 2 or 4: the low bytes of EVAL, emitted (big-endian). Pass 2 complains
; about an undefined or unresolved value (and emits zeros for it).
EMITVAL     PSHS A
            JSR  CHKVAL
            PULS A
            LDX  #EVAL+4
            NEGA
            LEAX A,X
EV2_LOOP    LDA  ,X+
            JSR  EMITB
            CMPX #EVAL+4
            BNE  EV2_LOOP
            RTS
; Pass 2: an error if EVAL isn't a usable value (then zero).
CHKVAL      LDA  <EVFLAGS
            BITA #EF_UNDEF
            BEQ  CK_DEF
            LDA  #ER_UNDEF
            JSR  ERROR
            BRA  CK_ZERO
CK_DEF      BITA #EF_KNOWN
            BNE  CK_OK
            LDA  #ER_UNRESOLVED
            JSR  ERROR
CK_ZERO     CLRD
            CLRW
            STQ  <EVAL
CK_OK       RTS
; Evaluate the expression at EXP in SIZE mode (known = defined before this
; line) / in VALUE mode (everything there is). Carry set: no expression.
EVALS       CLR  <EVMODE
            JMP  EXPR
EVALV       LDA  #1
            STA  <EVMODE
            JMP  EXPR
;------------------------------------------------------------------------------
; Errors. Pass 1 says nothing (pass 2 finds the same problems on the same lines).
;------------------------------------------------------------------------------
ERROR       PSHS D,X,Y,U
            LDB  <PASS
            CMPB #2
            BNE  ER_QUIET
            INC  <LINEERR
            LDX  <ERRCNT
            LEAX 1,X
            STX  <ERRCNT
            LDX  <CURSPEC              ; NAME(12) : ERROR : message
            JSR  PRINTS
            LDA  #'('
            JSR  PRINTC
            LDD  <CURLNO
            JSR  PRINTDEC
            LDX  #M_ERRSEP
            JSR  PRINTS
            LDA  ,S
            JSR  ERRMSG                ; -> X
            JSR  PRINTS
            LDA  ,S
            CMPA #ER_USER              ; ERROR "..." shows its text
            BNE  ER_NL
            LDX  <OPERP
            JSR  PRINTS
ER_NL       JSR  PRINTNL
            LDX  <CURSPEC              ; NAME:00012 the line
            JSR  PRINTS
            LDA  #':'
            JSR  PRINTC
            LDD  <CURLNO
            LDX  #NUMBUF
            JSR  DEC5STR
            LDX  #NUMBUF
            JSR  PRINTS
            LDA  #' '
            JSR  PRINTC
            LDX  #LINEBUF
            JSR  PRINTS
            JSR  PRINTNL
            JSR  PRINTNL
ER_QUIET    PULS D,X,Y,U,PC
; A = an error code: -> X = its message.
ERRMSG      LDX  #ERRTAB
EM_FIND     DECA
            BEQ  EM_GOT
EM_SKIP     TST  ,X+
            BNE  EM_SKIP
            BRA  EM_FIND
EM_GOT      RTS
;------------------------------------------------------------------------------
; The listing line (pass 2): lwasm's layout.
;------------------------------------------------------------------------------
LISTLINE    LDU  #LSTSTRM
            LDX  #WORKBUF              ; the 22-character prefix -> WORKBUF
            LDD  <PC                   ; the line took up space, or has bytes, or
            SUBD <LADDR                ; a label of its own: the address
            BNE  LL_ADDR
            LDD  <NBYTES
            BNE  LL_ADDR
            TST  <LABEL
            BEQ  LL_NOADDR
            TST  <SYMSET
            BEQ  LL_ADDR
LL_NOADDR   TST  <LSOFFON              ; in a struct: "0003s"
            BEQ  LL_NOSOFF
            LDD  <LSOFF
            JSR  HEX4
            LDA  #'s'
            STA  ,X+
            LDB  #17
            BRA  LL_PAD
LL_NOSOFF   LDA  <LSHOW
            CMPA #LS_BYTE              ; SETDP: "     VV"
            BNE  LL_NOBYTE
            LDB  #5
            JSR  PUTSPACES
            LDA  <LSHOWV+1
            JSR  HEX2
            LDB  #15
            BRA  LL_PAD
LL_NOBYTE   CMPA #LS_VALUE             ; EQU, SET: "     VVVV" or "     ????"
            BNE  LL_BLANK
            LDB  #5
            JSR  PUTSPACES
            TST  <LSHOWQ
            BNE  LL_UNKNOWN
            LDD  <LSHOWV
            JSR  HEX4
            LDB  #13
            BRA  LL_PAD
LL_UNKNOWN  LDD  #$3F3F               ; ????
            STD  ,X++
            STD  ,X++
            LDB  #13
            BRA  LL_PAD
LL_BLANK    LDB  #22
            BRA  LL_PAD
LL_ADDR     LDD  <LADDR                ; "AAAA BBBBBBBBBBBBBBBB "
            JSR  HEX4
            LDA  #' '
            STA  ,X+
            CLRB                       ; up to 8 bytes, blanks for the rest
LL_BLOOP    CMPB #8
            BHS  LL_BDONE
            CLRA
            CMPD <NBYTES
            BHS  LL_BPAD
            LDY  #LBYTES
            LDA  B,Y
            JSR  HEX2
            INCB
            BRA  LL_BLOOP
LL_BPAD     LDA  #' '
            STA  ,X+
            STA  ,X+
            INCB
            BRA  LL_BLOOP
LL_BDONE    LDB  #1
LL_PAD      JSR  PUTSPACES
            CLR  ,X
            LDX  #WORKBUF
            JSR  SPUTS
            LDA  #'('                  ; "(%17.17s):%05d "
            JSR  SPUTC
            LDX  <CURSPEC
            JSR  STRLEN
            CMPD #17
            BHS  LL_SPEC17
            NEGB
            ADDB #17
            JSR  SPACESTO
            LDX  <CURSPEC
            JSR  SPUTS
            BRA  LL_SPECD
LL_SPEC17   LDX  <CURSPEC
            LDB  #17
LL_SPECC    LDA  ,X+
            JSR  SPUTC
            DECB
            BNE  LL_SPECC
LL_SPECD    LDA  #')'
            JSR  SPUTC
            LDA  #':'
            JSR  SPUTC
            LDD  <CURLNO
            LDX  #NUMBUF
            JSR  DEC5STR
            LDX  #NUMBUF
            JSR  SPUTS
            LDB  #9                    ; " " and the empty cycle-count column
            JSR  SPACESTO
            LDX  #LINEBUF              ; the text, tabs to every 8 columns
            CLRB                       ; the column
LL_TEXT     LDA  ,X+
            BEQ  LL_EOL
            CMPA #9
            BEQ  LL_TAB
            JSR  SPUTC
            INCB
            BRA  LL_TEXT
LL_TAB      LDA  #' '                  ; a tab at a tab stop is a whole 8 wide
            JSR  SPUTC
            INCB
LL_TABL     BITB #7
            BEQ  LL_TEXT
            JSR  SPUTC
            INCB
            BRA  LL_TABL
LL_EOL      JSR  SPUTNL
            LDD  <NBYTES               ; more than 8 bytes: 8 a line after it
            CMPD #8
            BLS  LL_RET
            LDD  #8
            STD  <TMP
LL_MORE     LDD  <TMP
            CMPD <NBYTES
            BHS  LL_MOREEND
            ANDB #7
            BNE  LL_MOREB
            LDD  <TMP
            CMPD #8
            BEQ  LL_FIRSTM
            JSR  SPUTNL
LL_FIRSTM   LDB  #5
            JSR  SPACESTO
LL_MOREB    LDD  <TMP                  ; the byte (beyond the buffer: a repeat)
            CMPD #256
            BHS  LL_REP
            LDX  #LBYTES
            LEAX D,X
            LDA  ,X
            BRA  LL_HEXB
LL_REP      LDA  <LREPB
LL_HEXB     LDX  #NUMBUF
            JSR  HEX2
            CLR  ,X
            LDX  #NUMBUF
            JSR  SPUTS
            LDD  <TMP
            ADDD #1
            STD  <TMP
            BRA  LL_MORE
LL_MOREEND  JSR  SPUTNL
LL_RET      RTS
; B spaces -> X.
PUTSPACES   TSTB
            BEQ  PS2_RET
            LDA  #' '
PS2_LOOP    STA  ,X+
            DECB
            BNE  PS2_LOOP
PS2_RET     RTS
; B spaces -> the stream U.
SPACESTO    TSTB
            BEQ  ST2_RET
            LDA  #' '
ST2_LOOP    JSR  SPUTC
            DECB
            BNE  ST2_LOOP
ST2_RET     RTS
;------------------------------------------------------------------------------
; End of pa_line.asm
;------------------------------------------------------------------------------
