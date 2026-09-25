;------------------------------------------------------------------------------
; pa_insn.asm -- pugasm: the instructions, one handler for each lwasm operand
; class. Each handler parses the operand at EXP, decides the form (sizing from
; what is known before this line: SIZE mode), and emits the bytes (values in
; VALUE mode). The same code runs in both passes; pass 1 only counts the bytes.
;------------------------------------------------------------------------------
INSNHAND    FDB  H_INH,H_GEN0,H_GEN8,H_GEN16,H_GEN32,H_IMM8,H_INDEXED,H_REL
            FDB  H_RLIST,H_RTOR,H_TFMRTOR,H_TFM,H_BITBIT,H_LOGICMEM
;------------------------------------------------------------------------------
H_INH       CLRB
            JSR  GETOP
            JSR  EMITOP
            JMP  SKIPOPND
H_GEN0      CLRA
            BRA  GENCOMMON
H_GEN8      LDA  #1
            BRA  GENCOMMON
H_GEN16     LDA  #2
            BRA  GENCOMMON
H_GEN32     LDA  #4
GENCOMMON   STA  <OPSIZE
            CLR  <GENEXTRA
            LDX  <EXP
            LDA  ,X
            CMPA #'#'
            BNE  GENADDR
            TST  <OPSIZE               ; immediate
            BNE  GC_IMM
            JSR  SKIPOPND
            LDA  #ER_IMMED
            JMP  ERROR
GC_IMM      LEAX 1,X
            STX  <EXP
            LDA  <OPSIZE
            CMPA #1
            BNE  GC_NOW8
            INC  <EXPW8
GC_NOW8     JSR  EVALV
            BCS  BADOPND
            LDA  <OPSIZE
            CMPA #1
            BNE  GC_NOCHK
            JSR  CHKBYTE
GC_NOCHK    LDB  #3
            JSR  GETOP
            JSR  EMITOP
            LDA  <OPSIZE
            JMP  EMITVAL
BADOPND     LDA  #ER_BADOPND
            JMP  ERROR
; A general (non-immediate) operand: direct, extended, or indexed. GENEXTRA:
; one more byte (GENXB) after the opcode (AIM and company).
GENADDR     LDX  <EXP
            LDA  ,X
            CMPA #','
            LBEQ IDXGEN
            CMPA #'['
            LBEQ IDXGEN
            STX  <GASTART              ; (to go back to for indexed)
            LDB  #$FF                  ; the mode: -1 to be decided, 0 direct,
            STB  <GENMODE              ; 2 extended
            CMPA #'<'
            BNE  GA_STAR
            LEAX 1,X
            CLR  <GENMODE
            LDA  ,X
            CMPA #'<'                  ; << is indexed
            BNE  GA_EXPR
            LBRA GA_TOIDX
GA_STAR     CMPA #'*'                  ; *expr: direct (asxxxx), if a term follows
            BNE  GA_GT
            LDA  1,X
            JSR  ISSTARDP
            BCS  GA_EXPR
            CLR  <GENMODE
            LEAX 1,X
            BRA  GA_EXPR
GA_GT       CMPA #'>'
            BNE  GA_EXPR
            LEAX 1,X
            LDA  #2
            STA  <GENMODE
GA_EXPR     STX  <EXP
            STX  <GAEXPR
            JSR  EVALS
            PSHS CC
            LDX  <EXP                  ; followed by a comma: indexed after all
            LDA  ,X
            CMPA #','
            BEQ  GA_IDXCC
            PULS CC
            BCS  BADOPND
            LDA  <GENMODE
            BPL  GA_EMIT
            LDA  <FORMAT               ; (object files: always extended)
            CMPA #FMT_OBJ
            BEQ  GA_EXT
            LDA  <EVFLAGS              ; direct if in the direct page, going by what
            BITA #EF_KNOWN             ; is known (lwasm's range, for inexact)
            BEQ  GA_EXT
            BITA #EF_INEXACT
            BEQ  GA_V
            BITA #EF_NORANGE
            BNE  GA_EXT
            LDD  <EVAL+2
            SUBD <EVADJ
            BRA  GA_CMP
GA_V        LDD  <EVAL+2
GA_CMP      CMPA <DPVAL
            BEQ  GA_DIR
GA_EXT      LDA  #2
            STA  <GENMODE
            BRA  GA_EMIT
GA_DIR      CLR  <GENMODE
GA_EMIT     LDX  <GAEXPR
            STX  <EXP
            JSR  EVALV
            LDB  <GENMODE
            JSR  GETOP
            JSR  EMITOP
            JSR  EMITEXTRA
            LDA  <GENMODE
            BEQ  GA_ONE
            LDA  #2
            JMP  EMITVAL
GA_ONE      LDA  #1
            JMP  EMITVAL
GA_IDXCC    PULS CC
GA_TOIDX    LDX  <GASTART
            STX  <EXP
IDXGEN      LDB  #1                    ; indexed: the opcode is the second one
            JSR  GETOP
            STD  <IDXOP
            LDA  <GENEXTRA
            STA  <IDXELEN
            JMP  IDXDO
EMITEXTRA   TST  <GENEXTRA
            BEQ  EE_RET
            LDA  <GENXB
            JMP  EMITB
EE_RET      RTS
; Carry clear if A may follow * to make it a direct-page prefix (lwasm).
ISSTARDP    JSR  ISDIGIT
            BCC  SD2_RET
            JSR  ISALPHA
            BCC  SD2_RET
            CMPA #'_'
            BEQ  SD2_YES
            CMPA #'.'
            BEQ  SD2_YES
            CMPA #'?'
            BEQ  SD2_YES
            CMPA #'@'
            BEQ  SD2_YES
            CMPA #'*'
            BEQ  SD2_YES
            CMPA #'+'
            BEQ  SD2_YES
            CMPA #'-'
            BEQ  SD2_YES
            ORCC #1
            RTS
SD2_YES     ANDCC #$FE
SD2_RET     RTS
;------------------------------------------------------------------------------
; Indexed addressing (LEAx, and the general operands). IDXOP = the opcode,
; IDXELEN = extra bytes between it and the post byte.
;------------------------------------------------------------------------------
H_INDEXED   CLRB
            JSR  GETOP
            STD  <IDXOP
            CLR  <IDXELEN
            CLR  <GENEXTRA
IDXDO       JSR  IDXPARSE
            BCS  ID_RET0
            LDX  <EXP                  ; (the end of the operand, for afterwards:
            PSHS X                     ; the offset gets evaluated again)
            BSR  ID_BODY
            PULS X
            STX  <EXP
ID_RET0     RTS
ID_BODY     LDA  <IDXLINT
            BPL  ID_EMIT
            JSR  IDXRESOLVE
ID_EMIT     LDD  <IDXOP
            JSR  EMITOP
            JSR  EMITEXTRA
            LDA  <IDXLINT
            CMPA #3
            BEQ  ID_FIVE
            LDA  <IDXPB
            JSR  EMITB
            LDA  <IDXLINT
            BEQ  ID_RET
            JSR  IDXVALUE              ; the offset
            LDA  <IDXLINT
            CMPA #1
            BNE  ID_EMITV
            LDX  #128                  ; an 8-bit offset must fit
            LDY  #255
            JSR  CHKRANGE
            LDA  #1
ID_EMITV    JMP  EMITVAL
ID_RET      RTS
ID_FIVE     JSR  IDXVALUE              ; <<n,R: a 5-bit offset in the post byte
            JSR  CHKVAL
            LDX  #16
            LDY  #31
            JSR  INRANGE
            BCC  ID_5OK
            LDQ  <EVAL                 ; (or 0xFFF0 up)
            TSTA
            BMI  ID_5BAD
            BNE  ID_5OK
            TSTB
            BNE  ID_5OK
            CMPW #$FFF0
            BHS  ID_5OK
ID_5BAD     LDA  #ER_BYTEOVF
            JSR  ERROR
ID_5OK      LDA  <EVAL+3
            ANDA #$1F
            ORA  <IDXPB
            JMP  EMITB
; The offset (VALUE mode) -> EVAL; for PCR, relative to the end of the line.
IDXVALUE    LDX  <IDXEXPR
            STX  <EXP
            LDA  <IDXPCR               ; (PCR: less the section's base)
            STA  SUBPC
            JSR  EVALV
            TST  <IDXPCR
            BEQ  IV_RET
            LDD  <IDXOP                ; the whole length
            JSR  OPLEN
            ADDB <IDXELEN
            INCB                       ; the post byte
            ADDB <IDXLINT
            CLRA
            ADDD <LADDR
            STD  <TMP
            LDQ  <EVAL
            SUBW <TMP
            SBCD #0
            STQ  <EVAL
IV_RET      RTS
; Parses the indexed operand at EXP -> IDXPB, IDXLINT (-1 = the size is still to
; be decided, 0/1/2 offset bytes, 3 forced 5 bits), IDXEXPR, IDXPCR. Carry set
; after an error.
IDXPARSE    CLR  <IDXINDIR
            CLR  <IDXPCR
            CLR  <IDXF0
            LDX  <EXP
            LDA  ,X
            CMPA #'['
            BNE  IP_1
            INC  <IDXINDIR
            LEAX 1,X
IP_1        LDA  ,X
            CMPA #','
            LBNE IP_ACC
            LEAX 1,X                   ; ,R ,R+ ,R++ ,-R ,--R
            CLR  <TMPB                 ; the increment: -2 .. 2
            LDA  ,X
            CMPA #'-'
            BNE  IP_REG
            LEAX 1,X
            LDA  #-1
            STA  <TMPB
            LDA  ,X
            CMPA #'-'
            BNE  IP_REG
            LEAX 1,X
            LDA  #-2
            STA  <TMPB
IP_REG      LDA  ,X
            JSR  IDXREG4               ; -> B = 0-4 (X Y U S W)
            LBCS IP_BAD
            STB  <IDXRN
            LEAX 1,X
            LDA  ,X
            CMPA #'+'
            BNE  IP_NOINC
            TST  <TMPB
            LBNE IP_BAD
            LDA  #1
            STA  <TMPB
            LEAX 1,X
            LDA  ,X
            CMPA #'+'
            BNE  IP_NOINC
            LDA  #2
            STA  <TMPB
            LEAX 1,X
IP_NOINC    TST  <IDXINDIR
            BEQ  IP_NOIND
            LDA  ,X
            CMPA #']'
            LBNE IP_BAD
            LEAX 1,X
IP_NOIND    STX  <EXP
            LDA  <IDXINDIR             ; indirect or W: no single +/-
            BNE  IP_CHK1
            LDA  <IDXRN
            CMPA #4
            BNE  IP_PBRXYUS
IP_CHK1     LDA  <TMPB
            CMPA #1
            LBEQ IP_BAD
            CMPA #-1
            LBEQ IP_BAD
            LDA  <IDXRN
            CMPA #4
            BNE  IP_PBRXYUS
            LDB  <TMPB                 ; ,W forms
            LDA  #$90                  ; [,W]  [,--W] $F0  [,W++] $D0
            TST  <IDXINDIR
            BNE  IP_WIND
            LDA  #$8F                  ; ,W  ,--W $EF  ,W++ $CF
IP_WIND     TSTB
            BEQ  IP_SETPB
            ADDA #$60
            CMPB #-2
            BEQ  IP_SETPB
            SUBA #$20
            BRA  IP_SETPB
IP_PBRXYUS  LDB  <TMPB                 ; X Y U S: $84 none, $80 +, $81 ++,
            LDX  #INCDECPB+2           ; $82 -, $83 --
            LDA  B,X
            LDB  <IDXRN
            ASLB
            ASLB
            ASLB
            ASLB
            ASLB
            PSHS B
            ORA  ,S+
            TST  <IDXINDIR
            BEQ  IP_SETPB
            ORA  #$10
IP_SETPB    STA  <IDXPB
            CLR  <IDXLINT
            ANDCC #$FE
            RTS
INCDECPB    FCB  $83,$82,$84,$80,$81   ; indexed by increment -2 .. 2
IP_ACC      JSR  UPCASE                ; A,R B,R D,R (and E,R F,R W,R)
            LDB  1,X
            CMPB #','
            BNE  IP_EXPR0
            LDY  #ACCPB
IP_ACCFIND  LDB  ,Y
            BEQ  IP_EXPR0
            CMPA ,Y
            BEQ  IP_ACCGOT
            LEAY 3,Y
            BRA  IP_ACCFIND
IP_ACCGOT   LDB  2,Y                   ; the 6309 ones only on a 6309
            BEQ  IP_ACCOK
            TST  <CPU
            BNE  IP_EXPR0
IP_ACCOK    LDA  1,Y
            STA  <TMPB
            LEAX 2,X
            LDA  ,X
            JSR  IDXREG4
            LBCS IP_BAD
            CMPB #4
            LBEQ IP_BAD                ; (not W)
            LEAX 1,X
            TST  <IDXINDIR
            BEQ  IP_ACCPB
            LDA  ,X
            CMPA #']'
            LBNE IP_BAD
            LEAX 1,X
IP_ACCPB    STX  <EXP
            ASLB
            ASLB
            ASLB
            ASLB
            ASLB
            LDA  <IDXINDIR
            BEQ  IP_ACCN
            ORB  #$10
IP_ACCN     ORB  <TMPB
            TFR  B,A
            LBRA IP_SETPB
ACCPB       FCB  'A',$86,0,'B',$85,0,'D',$8B,0,'E',$87,1,'F',$8A,1,'W',$8E,1,0
IP_EXPR0    LDX  <EXP                  ; an offset expression
            TST  <IDXINDIR
            BEQ  IP_EXPRX
            LEAX 1,X
IP_EXPRX    LDA  #-1
            STA  <IDXLINT
            LDA  ,X
            CMPA #'<'
            BNE  IP_GT
            LDA  #1
            STA  <IDXLINT
            LEAX 1,X
            LDA  ,X
            CMPA #'<'
            BNE  IP_EXPR
            LDA  #3
            STA  <IDXLINT
            LEAX 1,X
            TST  <IDXINDIR
            BEQ  IP_EXPR
            LDA  #ER_ILL5
            BRA  IP_ERR
IP_GT       CMPA #'>'
            BNE  IP_EXPR
            LDA  #2
            STA  <IDXLINT
            LEAX 1,X
IP_EXPR     LDA  ,X                    ; "0," : a zero that stays 5-bit
            CMPA #'0'
            BNE  IP_NOF0
            LDA  1,X
            CMPA #','
            BNE  IP_NOF0
            INC  <IDXF0
IP_NOF0     STX  <IDXEXPR
            STX  <EXP
            JSR  EVALS
            BCS  IP_BAD
            LDX  <EXP
            LDA  ,X
            CMPA #','
            BEQ  IP_COMMA
            LDA  <IDXLINT              ; [expr]: extended indirect
            CMPA #1
            BEQ  IP_BAD
            LDA  ,X
            CMPA #']'
            BNE  IP_BAD
            LEAX 1,X
            STX  <EXP
            LDA  #2
            STA  <IDXLINT
            LDA  #$9F
            STA  <IDXPB
            ANDCC #$FE
            RTS
IP_BAD      LDA  #ER_BADOPND
IP_ERR      JSR  ERROR
            ORCC #1
            RTS
IP_BADREG   LDA  #ER_BADREG
            BRA  IP_ERR
IP_COMMA    LEAX 1,X                   ; the register
            LDY  #REGS_IDX
            TST  <CPU
            BEQ  IP_R3
            LDY  #REGS_IDX9
IP_R3       JSR  LOOKUPREG3
            BCS  IP_BADREG
            STA  <IDXRN
            TST  <IDXINDIR
            BEQ  IP_R3OK
            LDA  ,X
            CMPA #']'
            BNE  IP_BAD
            LEAX 1,X
IP_R3OK     STX  <EXP
            LDA  <IDXRN
            CMPA #3
            BHI  IP_NOTXYUS
            LDB  <IDXLINT              ; X Y U S with a forced size
            CMPB #1
            BEQ  IP_X8
            CMPB #2
            BEQ  IP_X16
            CMPB #3
            BNE  IP_AUTO
            ASLA                       ; <<n: rn << 5 (the offset goes in later)
            ASLA
            ASLA
            ASLA
            ASLA
            BRA  IP_PBDONE
IP_X8       LDB  #$88
            BRA  IP_XFORCE
IP_X16      LDB  #$89
IP_XFORCE   ASLA
            ASLA
            ASLA
            ASLA
            ASLA
            PSHS B
            ORA  ,S+
            TST  <IDXINDIR
            BEQ  IP_PBDONE
            ORA  #$10
IP_PBDONE   STA  <IDXPB
            ANDCC #$FE
            RTS
IP_NOTXYUS  CMPA #4
            BNE  IP_PC
            LDB  <IDXLINT              ; n,W: 16 bits or none
            CMPB #1
            BEQ  IP_NW8
            CMPB #3
            BEQ  IP_ILL5
            CMPB #2
            BEQ  IP_W16
            LDA  #4                    ; to decide: (lwasm leaves out "0," here)
            TST  <IDXINDIR
            BEQ  IP_PBDONE
            ORA  #$80
            BRA  IP_PBDONE
IP_W16      LDA  #$AF
            TST  <IDXINDIR
            BEQ  IP_PBDONE
            LDA  #$B0
            BRA  IP_PBDONE
IP_NW8      LDA  #ER_NW8
            LBRA IP_ERR
IP_ILL5     LDA  #ER_ILL5
            LBRA IP_ERR
IP_PC       CMPA #5                    ; PCR: relative to the end of the line
            BNE  IP_PCABS
            INC  <IDXPCR
IP_PCABS    LDB  <IDXLINT
            CMPB #3
            BEQ  IP_ILL5
            CMPB #1
            BNE  IP_PC16
            LDA  #$8C
            BRA  IP_PCF
IP_PC16     CMPB #2
            BNE  IP_AUTO
            LDA  #$8D
IP_PCF      TST  <IDXINDIR
            BEQ  IP_PBDONE
            ORA  #$10
            BRA  IP_PBDONE
IP_AUTO     LDA  <IDXRN                ; still to decide: indir*$80 | rn | f0*$40
            TST  <IDXINDIR
            BEQ  IP_AUTO1
            ORA  #$80
IP_AUTO1    TST  <IDXF0
            BEQ  IP_PBDONE
            ORA  #$40
            BRA  IP_PBDONE
; A = a register letter: -> B = 0-4 for X Y U S W (W only on a 6309); carry if
; it is none of them.
IDXREG4     JSR  UPCASE
            LDB  #4
            CMPA #'W'
            BNE  IR4_XYUS
            TST  <CPU
            BNE  IR4_NO
            ANDCC #$FE
            RTS
IR4_XYUS    CLRB
            CMPA #'X'
            BEQ  IR4_YES
            INCB
            CMPA #'Y'
            BEQ  IR4_YES
            INCB
            CMPA #'U'
            BEQ  IR4_YES
            INCB
            CMPA #'S'
            BEQ  IR4_YES
IR4_NO      ORCC #1
            RTS
IR4_YES     ANDCC #$FE
            RTS
; The offset size, when nothing forced it (lwasm's insn_resolve_indexed_aux):
; from the value if it's known and exact, else 16 bits.
IDXRESOLVE  LDX  <IDXEXPR
            STX  <EXP
            LDA  <IDXPCR
            STA  SUBPC
            JSR  EVALS
            LDA  <EVFLAGS
            BITA #EF_KNOWN
            LBEQ IR_16
            BITA #EF_INEXACT
            LBNE IR_16
            TST  <IDXPCR
            BEQ  IR_VAL
            TST  <LPCX                 ; (this line's own address isn't exact)
            LBNE IR_16
            LDD  <IDXOP                ; PCR: the offset, supposing 8 bits
            JSR  OPLEN
            ADDB <IDXELEN
            ADDB #2
            CLRA
            ADDD <LADDR
            STD  <TMP
            LDQ  <EVAL
            SUBW <TMP
            SBCD #0
            STQ  <EVAL
IR_VAL      LDA  <IDXPB
            ANDA #7
            STA  <TMPB                 ; the register (0-6)
            LDQ  <EVAL                 ; zero: no offset (X Y U S W; not after "0,")
            BNE  IR_NOT0
            LDA  <TMPB
            CMPA #4
            BHI  IR_NOT0
            LDA  <IDXPB
            BITA #$40
            BNE  IR_NOT0
            LDB  <TMPB
            CMPB #4
            BEQ  IR_0W
            LDA  <IDXPB
            ANDA #3
            JSR  RN5
            ORA  #$84
            CLR  <IDXLINT              ; (no offset bytes)
            LBRA IR_IND10
IR_0W       LDA  #$8F
            LDB  <IDXPB
            BPL  IR_SET0
            LDA  #$90
IR_SET0     STA  <IDXPB
            CLR  <IDXLINT
            RTS
IR_NOT0     LDX  #128                  ; beyond 8 bits: 16
            LDY  #255
            JSR  INRANGE
            BCS  IR_16
            LDA  <IDXPB                ; 8 bits: indirect, W, PC(R), or not 5 bits
            BMI  IR_8
            LDA  <TMPB
            CMPA #3
            BHI  IR_8
            LDX  #16
            LDY  #31
            JSR  INRANGE
            BCS  IR_8
            CLR  <IDXLINT              ; 5 bits (X Y U S, not indirect)
            LDA  <IDXPB
            ANDA #3
            JSR  RN5
            LDB  <EVAL+3
            ANDB #$1F
            PSHS B
            ORA  ,S+
            STA  <IDXPB
            RTS
IR_8        LDA  #1
            STA  <IDXLINT
            LDA  <TMPB
            CMPA #3
            BHI  IR_8NOT
            LDA  <IDXPB
            ANDA #3
            JSR  RN5
            ORA  #$88
            BRA  IR_IND10
IR_8NOT     CMPA #4
            BNE  IR_8PC
            LDA  #2                    ; W has no 8-bit form: 16 (zero was above)
            STA  <IDXLINT
            LDA  #$AF
            BRA  IR_W
IR_8PC      LDA  #$8C
            BRA  IR_IND10
IR_16       LDA  #2
            STA  <IDXLINT
            LDA  <IDXPB
            ANDA #7
            CMPA #3
            BHI  IR_16NOT
            LDA  <IDXPB
            ANDA #3
            JSR  RN5
            ORA  #$89
            BRA  IR_IND10
IR_16NOT    CMPA #4
            BNE  IR_16PC
            LDA  #$AF
IR_W        LDB  <IDXPB                ; [n,W]: $B0
            BPL  IR_SETPB
            LDA  #$B0
            BRA  IR_SETPB
IR_16PC     LDA  #$8D
IR_IND10    LDB  <IDXPB                ; indirect: +$10
            BPL  IR_SETPB
            ORA  #$10
IR_SETPB    STA  <IDXPB
            RTS
RN5         ASLA                       ; A = 0-3: A << 5
            ASLA
            ASLA
            ASLA
            ASLA
            RTS
;------------------------------------------------------------------------------
H_IMM8      LDX  <EXP                  ; ANDCC ORCC CWAI LDMD BITMD: #n
            LDA  ,X
            CMPA #'#'
            LBNE BADOPND
            LEAX 1,X
            STX  <EXP
            INC  <EXPW8
            JSR  EVALV
            LBCS BADOPND
            CLRB
            JSR  GETOP
            JSR  EMITOP
            JSR  CHKBYTE
            LDA  #1
            JMP  EMITVAL
;------------------------------------------------------------------------------
H_REL       LDX  <EXP                  ; branches: the size is in the mnemonic
            LDA  ,X
            CMPA #'#'
            BNE  HR_1
            LEAX 1,X
            STX  <EXP
HR_1        LDA  #1                    ; (less the section's base)
            STA  SUBPC
            JSR  EVALV
            LBCS BADOPND
            LDB  #1
            JSR  GETOP
            CMPB #8
            BNE  HR_LONG
            LDB  #2                    ; 8 bits
            JSR  GETOP
            STD  <TMP2
            JSR  OPLEN
            INCB
            BSR  HR_OFFSET
            LDA  <EVFLAGS
            BITA #EF_UNDEF
            BEQ  HR_DEF
            LDA  #ER_UNDEF
            JSR  ERROR
            BRA  HR_EMIT8
HR_DEF      BITA #EF_KNOWN
            BNE  HR_KNOWN
            LDA  #ER_NOTCONST
            JSR  ERROR
            BRA  HR_EMIT8
HR_KNOWN    LDX  #128
            LDY  #255
            JSR  CHKRANGE
HR_EMIT8    LDD  <TMP2
            JSR  EMITOP
            LDA  <EVFLAGS
            BITA #EF_RELOC
            BEQ  HR_PLAIN8
            LDA  #1
            JMP  EMITVAL
HR_PLAIN8   LDA  <EVAL+3
            JMP  EMITB
HR_LONG     LDB  #3                    ; 16 bits
            JSR  GETOP
            STD  <TMP2
            JSR  OPLEN
            ADDB #2
            BSR  HR_OFFSET
            LDD  <TMP2
            JSR  EMITOP
            LDA  #2
            JMP  EMITVAL
; B = the instruction's length: EVAL = the target - the end of the line.
HR_OFFSET   CLRA
            ADDD <LADDR
            STD  <TMP
            LDQ  <EVAL
            SUBW <TMP
            SBCD #0
            STQ  <EVAL
            RTS
;------------------------------------------------------------------------------
H_RLIST     LDX  <EXP                  ; PSHS PULS PSHU PULU
            CLR  <TMPB                 ; the post byte
HL_LOOP     LDA  ,X
            BEQ  HL_DONE
            JSR  ISSPACE
            BCC  HL_DONE
            CMPA #';'
            BEQ  HL_DONE
            CMPA #'*'
            BEQ  HL_DONE
            LDY  #REGS_RL
            JSR  LOOKUPREG2
            BCS  HL_BADREG
            PSHS A
            LDA  ,X                    ; followed by , or the end
            BEQ  HL_SEP
            CMPA #','
            BEQ  HL_COMMA
            CMPA #';'
            BEQ  HL_SEP
            CMPA #'*'
            BEQ  HL_SEP
            JSR  ISSPACE
            BCC  HL_SEP
            LDA  #ER_BADOPND
            JSR  ERROR
            BRA  HL_SEP
HL_COMMA    LEAX 1,X
HL_SEP      PULS A
            PSHS X
            LDX  <OPSP                 ; PSHU/PULU can't take U, PSHS/PULS S
            LDB  1,X
            PULS X
            BITB #2
            BEQ  HL_SSTACK
            CMPA #6
            BEQ  HL_BADU
            BRA  HL_BIT
HL_SSTACK   CMPA #9
            BEQ  HL_BADU
HL_BIT      LDB  #6                    ; D = A and B
            CMPA #8
            BEQ  HL_OR
            LDB  #$40                  ; S = U's bit
            CMPA #9
            BEQ  HL_OR
            LDB  #1
            TSTA
HL_SHIFT    BEQ  HL_OR
            ASLB
            DECA
            BRA  HL_SHIFT
HL_OR       ORB  <TMPB
            STB  <TMPB
            BRA  HL_LOOP
HL_BADU     STX  <EXP
            LDA  #ER_BADREG
            JMP  ERROR
HL_BADREG   STX  <EXP
            LDA  #ER_BADREG
            JMP  ERROR
HL_DONE     STX  <EXP
            TST  <TMPB
            BNE  HL_EMIT
            LDA  #ER_BADOPND
            JSR  ERROR
HL_EMIT     CLRB
            JSR  GETOP
            JSR  EMITOP
            LDA  <TMPB
            JMP  EMITB
;------------------------------------------------------------------------------
H_RTOR      LDY  #REGS_RR              ; TFR EXG ADDR ... r0,r1
            TST  <CPU
            BEQ  RT_GO
            LDY  #REGS_RR9
RT_GO       STY  <TMP3
RT_PARSE    LDX  <EXP
            JSR  LOOKUPREG2
            BCS  RT_BAD
            STA  <TMPB
            LDA  ,X+
            CMPA #','
            BNE  RT_BAD
            LDY  <TMP3
            JSR  LOOKUPREG2
            BCS  RT_BAD
            STX  <EXP
            PSHS A
            LDA  <TMPB
            ASLA
            ASLA
            ASLA
            ASLA
            ORA  ,S+
            BRA  RT_EMIT
RT_BAD      STX  <EXP
            LDA  #ER_BADOPND
            JSR  ERROR
            CLRA
RT_EMIT     PSHS A
            CLRB
            JSR  GETOP
            JSR  EMITOP
            PULS A
            JMP  EMITB
H_TFMRTOR   LDY  #REGS_TR              ; the TFM register pairs (as TFR)
            STY  <TMP3
            BRA  RT_PARSE
;------------------------------------------------------------------------------
H_TFM       LDX  <EXP                  ; TFM r0+,r1+ | r0-,r1- | r0+,r1 | r0,r1+
            CLR  <TMPB2                ; which: +1 r0+, 2 r0-, 4 r1+, 8 r1-
            LDA  ,X+
            JSR  TFMREG
            LBCS TF_BADREG
            STA  <TMPB
            LDA  ,X
            CMPA #'+'
            BNE  TF_M0
            LEAX 1,X
            LDA  #1
            STA  <TMPB2
            BRA  TF_COMMA
TF_M0       CMPA #'-'
            BNE  TF_COMMA
            LEAX 1,X
            LDA  #2
            STA  <TMPB2
TF_COMMA    LDA  ,X+
            CMPA #','
            BNE  TF_UNK
            LDA  ,X+
            JSR  TFMREG
            BCS  TF_BADREG
            STA  <TMP
            LDA  ,X
            CMPA #'+'
            BNE  TF_M1
            LEAX 1,X
            LDA  <TMPB2
            ORA  #4
            STA  <TMPB2
            BRA  TF_END
TF_M1       CMPA #'-'
            BNE  TF_END
            LEAX 1,X
            LDA  <TMPB2
            ORA  #8
            STA  <TMPB2
TF_END      STX  <EXP
            LDA  ,X
            BEQ  TF_ENDOK
            JSR  ISSPACE
            BCC  TF_ENDOK
            LDA  #ER_BADOPND
            JMP  ERROR
TF_ENDOK    LDA  <TMPB                 ; only D X Y U S
            CMPA #4
            BHI  TF_BADREG2
            LDA  <TMP
            CMPA #4
            BLS  TF_KIND
TF_BADREG2  LDA  #ER_BADREG
            JSR  ERROR
TF_KIND     LDA  <TMPB2
            CLRB
            CMPA #5                    ; r0+,r1+: the first opcode
            BEQ  TF_OP
            INCB
            CMPA #10                   ; r0-,r1-
            BEQ  TF_OP
            INCB
            CMPA #1                    ; r0+,r1
            BEQ  TF_OP
            INCB
            CMPA #4                    ; r0,r1+
            BEQ  TF_OP
TF_UNK      STX  <EXP
            LDA  #ER_UNKOP
            JMP  ERROR
TF_OP       JSR  GETOP
            JSR  EMITOP
            LDA  <TMPB
            ASLA
            ASLA
            ASLA
            ASLA
            ORA  <TMP
            JMP  EMITB
TF_BADREG   STX  <EXP
            LDA  #ER_BADREG
            JMP  ERROR
; A = a character: -> A = its place in "DXYUS   AB  00EF" (as strchr), carry if
; it isn't there.
TFMREG      JSR  UPCASE
            PSHS X
            LDX  #TFMREGS
            CLRB
TR_LOOP     CMPA B,X
            BEQ  TR_GOT
            INCB
            CMPB #16
            BLO  TR_LOOP
            TSTA                       ; (strchr finds the NUL too)
            BEQ  TR_GOT
            PULS X
            ORCC #1
            RTS
TR_GOT      TFR  B,A
            PULS X
            ANDCC #$FE
            RTS
TFMREGS     FCC  "DXYUS   AB  00EF"
;------------------------------------------------------------------------------
H_BITBIT    LDX  <EXP                  ; BAND etc.: r,bit,bit,address
            LDA  ,X+
            JSR  UPCASE
            LDB  #1
            CMPA #'A'
            BEQ  BB_REG
            INCB
            CMPA #'B'
            BEQ  BB_REG
            CLRB
            CMPA #'C'
            BNE  BB_BADREG
            LDA  ,X
            JSR  UPCASE
            CMPA #'C'
            BNE  BB_BADREG
            LEAX 1,X
BB_REG      STB  <TMPB
            LDA  ,X+
            CMPA #','
            BNE  BB_BAD
            STX  <EXP
            JSR  EVALV                 ; the first bit number
            BCS  BB_BAD
            JSR  BITNUM
            STA  <BBIT1
            LDX  <EXP
            LDA  ,X+
            CMPA #','
            BNE  BB_BAD
            STX  <EXP
            JSR  EVALV                 ; the second
            BCS  BB_BAD
            JSR  BITNUM
            STA  <BBIT2
            LDX  <EXP
            LDA  ,X+
            CMPA #','
            BNE  BB_BAD
            LDA  ,X                    ; (a < is ignored)
            CMPA #'<'
            BNE  BB_ADDR
            LEAX 1,X
BB_ADDR     STX  <EXP
            JSR  EVALV
            BCS  BB_BAD
            LDA  <EVFLAGS              ; the address must be in the direct page
            BITA #EF_KNOWN
            BEQ  BB_EMIT
            LDD  <EVAL+2
            SUBA <DPVAL
            BEQ  BB_EMIT
            LDA  #ER_BYTEOVF
            JSR  ERROR
BB_EMIT     CLRB
            JSR  GETOP
            JSR  EMITOP
            LDA  <TMPB                 ; r << 6 | bit << 3 | bit
            LDB  #64
            MUL
            TFR  B,A
            LDB  <BBIT1
            ASLB
            ASLB
            ASLB
            PSHS B
            ORA  ,S+
            ORA  <BBIT2
            JSR  EMITB
            LDA  #1
            JMP  EMITVAL
BB_BADREG   STX  <EXP
            LDA  #ER_BADREG
            JMP  ERROR
BB_BAD      STX  <EXP
            LDA  #ER_BADOPND
            JMP  ERROR
; EVAL = a bit number: -> A (pass 2: it must be known, and 0-7).
BITNUM      LDA  <EVFLAGS
            BITA #EF_KNOWN
            BNE  BN_KNOWN
            LDA  #ER_BITUNRES
            JSR  ERROR
            CLRA
            RTS
BN_KNOWN    LDX  #0
            LDY  #7
            JSR  INRANGE
            BCC  BN_OK
            LDA  #ER_BITINV
            JSR  ERROR
            CLRA
            RTS
BN_OK       LDA  <EVAL+3
            RTS
;------------------------------------------------------------------------------
H_LOGICMEM  LDX  <EXP                  ; AIM OIM EIM TIM: #n,address
            LDA  ,X
            CMPA #'#'
            BNE  LM_1
            LEAX 1,X
LM_1        STX  <EXP
            JSR  EVALV
            LBCS BADOPND
            LDA  <EVFLAGS
            BITA #EF_KNOWN
            BNE  LM_KNOWN
            LDA  #ER_IMMUNRES
            JSR  ERROR
LM_KNOWN    LDA  <EVAL+3
            STA  <GENXB
            LDX  <EXP
            LDA  ,X
            CMPA #','
            BEQ  LM_SEP
            CMPA #';'
            LBNE BADOPND
LM_SEP      LEAX 1,X
            STX  <EXP
            LDA  #1
            STA  <GENEXTRA
            JMP  GENADDR
;------------------------------------------------------------------------------
; Register names, as lwasm looks them up.
;------------------------------------------------------------------------------
; Y = a table of 2-character names, X = the text: -> A = the name's index, X
; past it; carry set if none matches.
LOOKUPREG2  CLRB
L2_LOOP     LDA  ,Y
            BEQ  LR_NONE
            LDA  ,X
            JSR  UPCASE
            CMPA ,Y
            BNE  L2_NEXT
            LDA  1,Y
            CMPA #' '
            BNE  L2_TWO
            LDA  1,X                   ; a 1-letter name: not followed by a letter
            CMPA #' '
            BEQ  L2_ONE
            JSR  ISALPHA
            BCS  L2_ONE
            BRA  L2_NEXT
L2_TWO      LDA  1,X
            JSR  UPCASE
            CMPA 1,Y
            BEQ  L2_TWOOK
L2_NEXT     LEAY 2,Y
            INCB
            BRA  L2_LOOP
L2_ONE      LEAX 1,X
            BRA  LR_GOT
L2_TWOOK    LEAX 2,X
LR_GOT      TFR  B,A
            ANDCC #$FE
            RTS
LR_NONE     ORCC #1
            RTS
; The same with 3-character names.
LOOKUPREG3  CLRB
L3_LOOP     LDA  ,Y
            BEQ  LR_NONE
            LDA  ,X
            JSR  UPCASE
            CMPA ,Y
            BNE  L3_NEXT
            LDA  1,Y
            CMPA #' '
            BNE  L3_TWO
            LDA  1,X
            CMPA #' '
            BEQ  L3_ONE
            JSR  ISALPHA
            BCS  L3_ONE
            BRA  L3_NEXT
L3_TWO      LDA  1,X
            JSR  UPCASE
            CMPA 1,Y
            BNE  L3_NEXT
            LDA  2,Y
            CMPA #' '
            BNE  L3_THREE
            LDA  2,X
            CMPA #' '
            BEQ  L3_2OK
            JSR  ISALPHA
            BCS  L3_2OK
            BRA  L3_NEXT
L3_THREE    LDA  2,X
            JSR  UPCASE
            CMPA 2,Y
            BEQ  L3_3OK
L3_NEXT     LEAY 3,Y
            INCB
            BRA  L3_LOOP
L3_ONE      LEAX 1,X
            BRA  LR_GOT
L3_2OK      LEAX 2,X
            BRA  LR_GOT
L3_3OK      LEAX 3,X
            BRA  LR_GOT
REGS_IDX    FCN  "X  Y  U  S  W  PCRPC "
REGS_IDX9   FCN  "X  Y  U  S     PCRPC "
REGS_RL     FCN  "CCA B DPX Y U PCD S "
REGS_RR     FCN  "D X Y U S PCW V A B CCDP0 0 E F "
REGS_RR9    FCN  "D X Y U S PC    A B CCDP        "
REGS_TR     FCN  "D X Y U S       A B     0 0 E F "
;------------------------------------------------------------------------------
; Value checks (pass 2 complains).
;------------------------------------------------------------------------------
; X = an offset, Y = a span: carry clear if X + EVAL is 0..Y (so EVAL is -X ..
; Y-X), as a 32-bit signed value.
INRANGE     PSHSW
            PSHS D
            LDQ  <EVAL
            ADDR X,W
            ADCD #0
            BNE  IR2_OUT
            CMPR Y,W
            BHI  IR2_OUT
            PULS D
            PULSW
            ANDCC #$FE
            RTS
IR2_OUT     PULS D
            PULSW
            ORCC #1
            RTS
; The same, as an error ("Byte overflow") if EVAL is known and outside.
CHKRANGE    LDA  <EVFLAGS
            BITA #EF_KNOWN
            BEQ  CR_RET
            BITA #EF_RELOC             ; (the linker's business)
            BNE  CR_RET
            JSR  INRANGE
            BCC  CR_RET
            LDA  #ER_BYTEOVF
            JMP  ERROR
CR_RET      RTS
; An 8-bit immediate: -128 .. 255.
CHKBYTE     LDX  #128
            LDY  #383
            BRA  CHKRANGE
;------------------------------------------------------------------------------
; End of pa_insn.asm
;------------------------------------------------------------------------------
