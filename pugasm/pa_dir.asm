;------------------------------------------------------------------------------
; pa_dir.asm -- pugasm: the directives (lwasm's pseudo operations), conditional
; assembly, macros and structs.
;------------------------------------------------------------------------------
DIRHAND     FDB  D_ORG,D_EQU,D_SET,D_SETDP,D_FCB,D_FDB,D_FQB,D_FCC,D_FCN,D_FCS
            FDB  D_RMB,D_RMD,D_RMQ,D_ZMB,D_ZMD,D_ZMQ,D_FILL,D_ALIGN,D_END
            FDB  D_INCLUDE,D_INCLUDEBIN,D_IFEQ,D_IFNE,D_IFGT,D_IFGE,D_IFLT
            FDB  D_IFLE,D_IFDEF,D_IFNDEF,D_ELSE,D_ENDC,D_MACRO,D_ENDM,D_STRUCT
            FDB  D_ENDSTRUCT,D_SECTION,D_ENDSECTION,D_EXPORT,D_IMPORT,D_EXTERN
            FDB  D_EXTDEP,D_ERROR,D_WARNING,D_NOOP,D_PRAGMA,D_PRAGMA
;------------------------------------------------------------------------------
BADEXPR     LDA  #ER_BADEXPR
            JMP  ERROR
D_ORG       JSR  EVALS
            BCS  DO_BAD
            LDA  <EVFLAGS
            BITA #EF_KNOWN
            BNE  DO_KNOWN
            LDA  #ER_ORGUNK
            JMP  ERROR
DO_KNOWN    LDD  <EVAL+2
            STD  <PC
            STD  <LADDR                ; (a label on the line gets the new address)
            CLR  <PCX
            CLRD
            STD  <PCADJ
            LDA  <EVFLAGS
            BITA #EF_INEXACT
            BEQ  DO_EXACT
            INC  <PCX
            LDD  <EVADJ
            STD  <PCADJ
DO_EXACT    LDA  <PCX
            STA  <LPCX
            LDD  <PCADJ
            STD  <LPCADJ
            TST  <FIRSTOUT             ; (raw output starts at the last ORG
            BEQ  DO_RET                ; before the first byte)
            CLRD
            STD  <RAWZERO
            RTS
DO_BAD      LDA  #ER_BADOPND
            JMP  ERROR
DO_RET      RTS
;------------------------------------------------------------------------------
D_EQU       CLRA
            BRA  EQUSET
D_SET       LDA  #SF_SET
EQUSET      STA  <TMPB
            TST  <LABEL
            BNE  EQ_HAVE
            JSR  SKIPOPND
            LDA  #ER_MISSSYM
            JMP  ERROR
EQ_HAVE     JSR  EVALV
            BCS  DO_BAD
            LDA  #1
            STA  <SYMSET
            LDA  #LS_VALUE             ; the listing shows the value
            STA  <LSHOW
            LDD  <EVAL+2
            STD  <LSHOWV
            LDA  <EVFLAGS
            ANDA #EF_KNOWN
            EORA #EF_KNOWN
            STA  <LSHOWQ
            LDB  <SECTNUM              ; (object output: relative to another
            JSR  TALLSECT              ; section, or imported: "????")
            BCC  EQ_SHOWN
            LDA  #1
            STA  <LSHOWQ
EQ_SHOWN
            LDX  #LABELNAME
            LDY  #NAMEBUF
            JSR  STRCPY
            LDA  <TMPB
            JMP  SYMDEF
;------------------------------------------------------------------------------
D_SETDP     LDA  <FORMAT
            CMPA #FMT_OBJ
            BNE  SD4_GO
            JSR  SKIPOPND
            LDA  #ER_SETDPOBJ
            JMP  ERROR
SD4_GO      JSR  EVALS
            BCS  DO_BAD
            LDA  <EVFLAGS
            BITA #EF_KNOWN
            BNE  SD4_KNOWN
            LDA  #ER_SETDPUNK
            JMP  ERROR
SD4_KNOWN   LDA  <EVAL+3
            STA  <DPVAL
            STA  <LSHOWV+1
            LDA  #LS_BYTE
            STA  <LSHOW
            RTS
;------------------------------------------------------------------------------
D_FCB       LDA  #1
            BRA  DATALIST
D_FDB       LDA  #2
            BRA  DATALIST
D_FQB       LDA  #4
DATALIST    STA  <OPSIZE
DL2_LOOP    JSR  EVALV
            LBCS BADEXPR
            LDA  <OPSIZE
            JSR  EMITVAL
            LDX  <EXP
            LDA  ,X
            CMPA #','
            BNE  DL2_RET
            LEAX 1,X
            STX  <EXP
            BRA  DL2_LOOP
DL2_RET     RTS
; FCC /text/ (any delimiter), FCN (and a NUL), FCS (the last with bit 7 set).
D_FCC       CLRA
            BRA  STRING
D_FCN       LDA  #1
            BRA  STRING
D_FCS       LDA  #2
STRING      STA  <TMPB
            LDX  <EXP
            LDA  ,X+
            BEQ  ST3_BAD
            STA  <TMPB2                ; the delimiter
            TFR  X,Y                   ; the text starts at Y
ST3_FIND    LDA  ,X
            BEQ  ST3_BAD
            CMPA <TMPB2
            BEQ  ST3_FOUND
            LEAX 1,X
            BRA  ST3_FIND
ST3_BAD     JSR  SKIPOPND
            LDA  #ER_BADOPND
            JMP  ERROR
ST3_FOUND   LEAX 1,X                   ; past the closing delimiter
            STX  <EXP
            LEAX -1,X                  ; the end of the text
            STX  <TMP
ST3_EMIT    CMPY <TMP
            BHS  ST3_DONE
            LDA  ,Y+
            LDB  <TMPB
            CMPB #2
            BNE  ST3_PUT
            CMPY <TMP                  ; FCS: the last one
            BLO  ST3_PUT
            ORA  #$80
ST3_PUT     JSR  EMITB
            BRA  ST3_EMIT
ST3_DONE    LDA  <TMPB
            CMPA #1
            BNE  ST3_RET
            CLRA
            JMP  EMITB
ST3_RET     RTS
;------------------------------------------------------------------------------
; RMB n, RMD n, RMQ n: space. In a struct: a field. The count has to be known
; here; lwasm only takes it at once if it is a bare number, so any other count
; leaves the addresses after it inexact on pass 1 (see PCX).
D_RMB       LDA  #1
            BRA  RESV
D_RMD       LDA  #2
            BRA  RESV
D_RMQ       LDA  #4
RESV        STA  <OPSIZE
            JSR  EVALS
            LBCS BADEXPR
            TST  <INSTRUCT
            LBNE STRUCTFIELD
            JSR  COUNTN                ; -> D = the count (0 after an error)
            BCS  RV_RET
            TST  <EVLIT
            BNE  RV_EXACT
            PSHS D                     ; not a bare number: inexact from here on
            LDA  #1
            STA  <PCX
            LDD  <PCADJ
            ADDD ,S
            STD  <PCADJ
            PULS D
RV_EXACT    JMP  RESERVE
RV_RET      RTS
; EVAL (known, not negative) * OPSIZE -> D; carry set after an error.
COUNTN      LDA  <EVFLAGS
            BITA #EF_KNOWN
            BNE  CT2_KNOWN
            LDA  #ER_CNTUNK
            JSR  ERROR
            ORCC #1
            RTS
CT2_KNOWN   TST  <EVAL
            BPL  CT2_POS
            LDA  #ER_NEGRES
            JSR  ERROR
            ORCC #1
            RTS
CT2_POS     LDD  <EVAL+2
            PSHS D
            LDB  <OPSIZE
            CMPB #1
            BEQ  CT2_DONE
            LDD  ,S                    ; x2
            ASLB
            ROLA
            STD  ,S
            LDB  <OPSIZE
            CMPB #2
            BEQ  CT2_DONE
            LDD  ,S                    ; x4
            ASLB
            ROLA
            STD  ,S
CT2_DONE    PULS D
            ANDCC #$FE
            RTS
; ZMB n, ZMD n, ZMQ n: that many zeros.
D_ZMB       LDA  #1
            BRA  ZEROS
D_ZMD       LDA  #2
            BRA  ZEROS
D_ZMQ       LDA  #4
ZEROS       STA  <OPSIZE
            JSR  EVALS
            LBCS BADEXPR
            JSR  COUNTN
            BCS  ZR_RET
            TST  <EVLIT
            BNE  ZR_EXACT
            PSHS D
            LDA  #1
            STA  <PCX
            LDD  <PCADJ
            ADDD ,S
            STD  <PCADJ
            PULS D
ZR_EXACT    CLR  <LREPB
            CLR  <TMPB2
            JMP  FILLN
ZR_RET      RTS
; D = a count, TMPB2 = a byte: emitted that many times. FILLB: FILL and ALIGN,
; which in a bss section only reserve the space.
FILLB       PSHS D
            JSR  SECTISBSS
            PULS D
            LBCS RESERVE
FILLN       TFR  D,X
FN_LOOP     CMPX #0
            BEQ  FN_RET
            LDA  <TMPB2
            JSR  EMITB
            LEAX -1,X
            BRA  FN_LOOP
FN_RET      RTS
; FILL value,count
D_FILL      JSR  EVALV
            BCS  FI_BAD
            LDA  <EVAL+3
            STA  <TMPB2
            STA  <LREPB
            LDX  <EXP
            LDA  ,X
            CMPA #','
            BNE  FI_BAD
            LEAX 1,X
            STX  <EXP
            JSR  EVALS
            BCS  FI_BAD
            LDA  #1
            STA  <OPSIZE
            LDA  <LREPB                ; (evaluating the count used TMPB2)
            PSHS A
            JSR  COUNTN
            TFR  D,X                   ; (the count)
            PULS A
            BCS  FI_RET
            STA  <TMPB2
            STA  <LREPB
            TFR  X,D
            JMP  FILLB
FI_BAD      LDA  #ER_BADOPND
            JMP  ERROR
FI_RET      RTS
; ALIGN n[,fill]: fill bytes up to a multiple of n.
D_ALIGN     JSR  EVALS
            BCS  FI_BAD
            LDD  <EVAL+2
            STD  <TMP3                 ; the alignment
            CLR  <TMPB2
            LDX  <EXP
            LDA  ,X
            CMPA #','
            BNE  AL_GO
            LEAX 1,X
            STX  <EXP
            JSR  EVALV
            BCS  FI_BAD
            LDA  <EVAL+3
            STA  <TMPB2
AL_GO       LDD  <TMP3
            BGT  AL_OK
            LDA  #ER_ALIGN
            JMP  ERROR
AL_OK       LDD  <PC                   ; PC mod n (repeated subtraction: n small)
AL_MOD      CMPD <TMP3
            BLO  AL_MODDED
            SUBD <TMP3
            BRA  AL_MOD
AL_MODDED   CMPD #0
            BEQ  AL_RET
            STD  <TMP
            LDD  <TMP3
            SUBD <TMP
            JMP  FILLB                 ; (the fill byte is in TMPB2)
AL_RET      RTS
;------------------------------------------------------------------------------
D_END       LDA  #1
            STA  <ENDSEEN
            LDA  <FORMAT
            CMPA #FMT_RAW
            BEQ  EN_SKIP
            CMPA #FMT_OBJ
            BEQ  EN_SKIP
            LDX  <EXP
            LDA  ,X
            BEQ  EN_RET
            JSR  ISSPACE
            BCC  EN_RET
            JSR  EVALV
            BCS  DO_BAD2
            LDA  <EVFLAGS
            BITA #EF_KNOWN
            BNE  EN_EXEC
            LDA  #ER_EXECADDR
            JMP  ERROR
EN_EXEC     LDD  <EVAL+2
            STD  <EXECADDR
            LDA  #1
            STA  <HAVEEXEC
EN_RET      RTS
EN_SKIP     JMP  SKIPOPND
DO_BAD2     LDA  #ER_BADEXPR
            JMP  ERROR
;------------------------------------------------------------------------------
; INCLUDE file, INCLUDEBIN file: the name as it is, or in quotes.
GETFNAME    LDX  <EXP                  ; -> FNAMEBUF = the name; EXP past it
            LDY  #FNAMEBUF
            LDA  ,X
            BEQ  GF_NONE
            CMPA #'"'
            BEQ  GF_QUOTED
            CMPA #$27
            BEQ  GF_QUOTED
GF_PLAIN    LDA  ,X
            BEQ  GF_END
            JSR  ISSPACE
            BCC  GF_END
            STA  ,Y+
            LEAX 1,X
            CMPY #FNAMEBUF+PATHMAX
            BLO  GF_PLAIN
            BRA  GF_END
GF_QUOTED   STA  <TMPB2
            LEAX 1,X
GF_QLOOP    LDA  ,X
            BEQ  GF_END
            LEAX 1,X
            CMPA <TMPB2
            BEQ  GF_END
            STA  ,Y+
            CMPY #FNAMEBUF+PATHMAX
            BLO  GF_QLOOP
GF_END      CLR  ,Y
            STX  <EXP
            ANDCC #$FE
            RTS
GF_NONE     LDA  #ER_FILENAME
            JSR  ERROR
            ORCC #1
            RTS
D_INCLUDE   JSR  GETFNAME
            BCS  IN_RET
            LDX  #FNAMEBUF
            JSR  OPENINC
            BCC  IN_RET
            LDX  #M_NOINCLUDE          ; (lwasm stops too)
            JSR  PRINTS
            LDX  #FNAMEBUF
            JSR  FATAL
IN_RET      RTS
D_INCLUDEBIN JSR GETFNAME
            BCS  IN_RET
            LDX  #FNAMEBUF
            JSR  FINDFILE
            BCC  IB_OPEN
            LDA  #ER_FILEOPEN
            JMP  ERROR
IB_OPEN     STA  <TMPB2                ; the handle
            CLR  <LREPB
IB_READ     LDB  <TMPB2
            LDX  #WORKBUF
            LDY  #128
            LDA  #B_FREAD
            SWI2
            BCS  IB_DONE
            CMPX #0
            BEQ  IB_DONE
            TFR  X,D
            LDX  #WORKBUF
IB_BYTE     PSHS D
            LDA  ,X+
            JSR  EMITB
            PULS D
            SUBD #1
            BNE  IB_BYTE
            BRA  IB_READ
IB_DONE     LDB  <TMPB2
            LDA  #B_FCLOSE_NAME
            SWI2
            RTS
;------------------------------------------------------------------------------
; Conditional assembly (lwasm's skipcond / skipcount / skipmacro).
;------------------------------------------------------------------------------
D_IFEQ      LDA  #1
            BRA  IFCOND
D_IFNE      LDA  #2
            BRA  IFCOND
D_IFGT      LDA  #3
            BRA  IFCOND
D_IFGE      LDA  #4
            BRA  IFCOND
D_IFLT      LDA  #5
            BRA  IFCOND
D_IFLE      LDA  #6
IFCOND      STA  <TMPB
            JSR  IFNESTED              ; already skipping: just count it
            BCC  IFC_RET
            JSR  EVALS
            BCS  IFC_BADX
            LDA  <EVFLAGS
            BITA #EF_KNOWN
            BNE  IFC_KNOWN
            LDA  #ER_COND
            JMP  ERROR
IFC_BADX    LDA  #ER_BADEXPR
            JMP  ERROR
IFC_KNOWN   LDQ  <EVAL                 ; is the condition false?
            PSHS CC                    ; (Z: zero, N: negative)
            LDA  <TMPB
            PULS CC
            BEQ  IFC_ZERO
            BMI  IFC_NEG
            CMPA #1                    ; a positive value: false for EQ LT LE
            BEQ  SKIPSTART
            CMPA #5
            BEQ  SKIPSTART
            CMPA #6
            BEQ  SKIPSTART
            RTS
IFC_ZERO    CMPA #2                    ; zero: false for NE GT LT
            BEQ  SKIPSTART
            CMPA #3
            BEQ  SKIPSTART
            CMPA #5
            BEQ  SKIPSTART
            RTS
IFC_NEG     CMPA #1                    ; negative: false for EQ GT GE
            BEQ  SKIPSTART
            CMPA #3
            BEQ  SKIPSTART
            CMPA #4
            BEQ  SKIPSTART
IFC_RET     RTS
SKIPSTART   LDA  #1
            STA  <SKIPCOND
            STA  <SKIPCOUNT
            RTS
; Carry clear if lines are being skipped (not in a skipped macro): the IF is
; counted and its operand ignored.
IFNESTED    TST  <SKIPCOND
            BEQ  IN2_NO
            TST  <SKIPMACRO
            BNE  IN2_NO
            INC  <SKIPCOUNT
            JSR  SKIPOPND
            ANDCC #$FE
            RTS
IN2_NO      ORCC #1
            RTS
; IFDEF a[|b...]: skip unless one of them is defined (before this line).
D_IFDEF     JSR  IFNESTED
            BCC  IFC_RET
ID2_NAME    JSR  CONDNAME
            JSR  DEFINED
            BCC  ID2_YES
            LDX  <EXP
            LDA  ,X
            CMPA #'|'
            BNE  ID2_NO
            LEAX 1,X
            STX  <EXP
            BRA  ID2_NAME
ID2_NO      BSR  SKIPSTART
ID2_YES     JMP  SKIPOPND
D_IFNDEF    JSR  IFNESTED
            BCC  IFC_RET
            JSR  CONDNAME
            JSR  DEFINED
            BCS  IFC_RET
            BRA  SKIPSTART
; The name at EXP (to a space, | or &) -> NAMEBUF.
CONDNAME    LDX  <EXP
            LDY  #NAMEBUF
            LDB  #NAMEMAX
CN2_LOOP    LDA  ,X
            BEQ  CN2_END
            CMPA #'|'
            BEQ  CN2_END
            CMPA #'&'
            BEQ  CN2_END
            JSR  ISSPACE
            BCC  CN2_END
            LEAX 1,X
            TSTB
            BEQ  CN2_LOOP
            STA  ,Y+
            DECB
            BRA  CN2_LOOP
CN2_END     CLR  ,Y
            STX  <EXP
            RTS
; Carry clear if NAMEBUF is a symbol defined before this line.
DEFINED     JSR  SYMFIND
            BCS  DF_RET
            LDD  SR_SEQ,X
            CMPD <LSEQ
            BHS  DF_NO
            ANDCC #$FE
DF_RET      RTS
DF_NO       ORCC #1
            RTS
D_ELSE      JSR  SKIPOPND
            TST  <SKIPMACRO
            BNE  EL_RET
            TST  <SKIPCOND
            LBEQ SKIPSTART
            LDA  <SKIPCOUNT
            CMPA #1
            BNE  EL_RET
            CLR  <SKIPCOUNT
            CLR  <SKIPCOND
EL_RET      RTS
D_ENDC      JSR  SKIPOPND
            TST  <SKIPCOND
            BEQ  EC_RET
            TST  <SKIPMACRO
            BNE  EC_RET
            DEC  <SKIPCOUNT
            BGT  EC_RET
            CLR  <SKIPCOND
EC_RET      RTS
;------------------------------------------------------------------------------
D_ERROR     JSR  SKIPOPND
            LDA  #ER_USER
            JMP  ERROR
D_WARNING   JSR  SKIPOPND
            LDA  <PASS
            CMPA #2
            BNE  EC_RET
            LDX  #M_WARNING
            JSR  PRINTS
            LDX  <OPERP
            JSR  PRINTS
            JMP  PRINTNL
D_NOOP      JMP  SKIPOPND
D_PRAGMA    JMP  SKIPOPND
;------------------------------------------------------------------------------
; Macros. A macro record: +0 the next macro, +3 its first line (far pointers),
; +6 the line that defined it, +8 flags (1: noexpand), +9 the name. A line: +0
; the next, +3 the text.
;------------------------------------------------------------------------------
MR_NEXT     equ  0
MR_LINES    equ  3
MR_SEQ      equ  6
MR_FLAGS    equ  8
MR_NAME     equ  9
D_MACRO     TST  <SKIPCOND             ; a macro in skipped lines: skip it all
            BEQ  MC_GO
            LDA  #1
            STA  <SKIPMACRO
            JMP  SKIPOPND
MC_GO       CLR  <MACNOEXP          ; "noexpand": listed as the one line
            LDX  <EXP
            LDY  #M_NOEXPAND
MC_NXCMP    LDA  ,Y+
            BEQ  MC_NXEND
            LDB  ,X+
            ORB  #$20
            PSHS B
            CMPA ,S+
            BEQ  MC_NXCMP
            BRA  MC_NXNO
MC_NXEND    LDA  ,X
            JSR  ISSYM
            BCC  MC_NXNO
            INC  <MACNOEXP
MC_NXNO     JSR  SKIPOPND
            TST  <INMACRO
            BEQ  MC_NOTIN
            LDA  #ER_MACRECUR
            JMP  ERROR
MC_NOTIN    TST  <LABEL
            BNE  MC_NAMED
            LDA  #ER_MACNONAME
            JMP  ERROR
MC_NAMED    LDX  #LABELNAME
            JSR  MACFIND
            BCS  MC_NEW
            LDD  MR_SEQ,X              ; (pass 2 finds its own)
            CMPD <LSEQ
            BEQ  MC_START
            LDA  #ER_MACDUPE
            JMP  ERROR
MC_NEW      LDA  <PASS
            CMPA #1
            BNE  MC_START
            LDX  #LABELNAME            ; a new record, at the head of the list
            JSR  STRLEN
            ADDD #MR_NAME+1
            JSR  HALLOC
            STA  <MACDEF
            STX  <MACDEF+1
            LDD  <MACROS
            STD  MR_NEXT,X
            LDA  <MACROS+2
            STA  MR_NEXT+2,X
            CLR  MR_LINES,X
            LDD  <LSEQ
            STD  MR_SEQ,X
            LDA  <MACNOEXP
            STA  MR_FLAGS,X
            LEAY MR_NAME,X
            LDX  #LABELNAME
            JSR  STRCPY
            LDD  <MACDEF
            STD  <MACROS
            LDA  <MACDEF+2
            STA  <MACROS+2
            CLR  <MACLAST              ; no lines yet
MC_START    LDA  #1
            STA  <INMACRO
            RTS
D_ENDM      TST  <SKIPCOND
            BEQ  EM2_GO
            CLR  <SKIPMACRO
            RTS
EM2_GO      TST  <INMACRO
            BNE  EM2_END
            LDA  #ER_ENDM
            JMP  ERROR
EM2_END     CLR  <INMACRO
            JMP  NEWCONTEXT            ; (a macro definition is a context break)
; Pass 1: LINEBUF -> the next line of the macro being defined.
MACADDLINE  LDA  <PASS
            CMPA #1
            BNE  MA2_RET
            LDX  #LINEBUF
            JSR  STRLEN
            ADDD #4
            JSR  HALLOC                ; A:X = the new line
            STA  <FARP
            STX  <FARP+1
            CLR  ,X                    ; (no next yet)
            LEAY 3,X
            LDX  #LINEBUF
            JSR  STRCPY
            TST  <MACLAST              ; link it after the last one
            BNE  MA2_AFTER
            LDA  <MACDEF               ; (the first: into the macro record)
            JSR  MAPPG
            LDX  <MACDEF+1
            LEAX MR_LINES,X
            BRA  MA2_LINK
MA2_AFTER   LDA  <MACLAST
            JSR  MAPPG
            LDX  <MACLAST+1
MA2_LINK    LDD  <FARP
            STD  ,X
            LDA  <FARP+2
            STA  2,X
            LDD  <FARP
            STD  <MACLAST
            LDA  <FARP+2
            STA  <MACLAST+2
MA2_RET     RTS
; X = a name: -> its macro record (mapped, X = its address), carry clear; carry
; set if there is none. Case doesn't matter.
MACFIND     STX  <TMP
            LDD  <MACROS
            STD  <FARP
            LDA  <MACROS+2
            STA  <FARP+2
MF2_LOOP    JSR  FARMAP
            BEQ  MF2_NONE
            PSHS X
            LEAY MR_NAME,X
            LDX  <TMP
            JSR  STRCMPI
            PULS X
            BEQ  MF2_FOUND
            LDD  MR_NEXT,X
            STD  <FARP
            LDA  MR_NEXT+2,X
            STA  <FARP+2
            BRA  MF2_LOOP
MF2_FOUND   ANDCC #$FE
            RTS
MF2_NONE    ORCC #1
            RTS
; The operation (OPTOK..OPTOKEND) as a macro: expands it (a new input level),
; carry clear; carry set if there is no such macro.
MACEXPAND   LDY  <OPTOK                ; the name -> NAMEBUF
            LDX  #NAMEBUF
            LDB  #NAMEMAX
ME2_COPY    CMPY <OPTOKEND
            BHS  ME2_COPIED
            LDA  ,Y+
            STA  ,X+
            DECB
            BNE  ME2_COPY
ME2_COPIED  CLR  ,X
            LDX  #NAMEBUF
            JSR  MACFIND
            BCC  ME2_FOUND
            RTS
ME2_FOUND   TST  MR_FLAGS,X            ; noexpand (and not inside one): its
            BEQ  ME2_EXPAND            ; lines' bytes go to the calling line
            LDA  <PASS
            CMPA #2
            BNE  ME2_EXPAND
            TST  <NXLEVEL
            BNE  ME2_EXPAND
            LDA  <ISP
            INCA
            STA  <NXLEVEL
            LDA  #1
            STA  <NXSTART
ME2_EXPAND  LDD  MR_LINES,X            ; its first line
            STD  <TMP2
            LDA  MR_LINES+2,X
            STA  <TMPB2
            LEAX MR_NAME,X             ; its name (for the listing), to WORKBUF
            LDY  #WORKBUF
            JSR  STRCPY
            JSR  PUSHIN
            LDA  #IT_MACRO
            STA  IR_TYPE,U
            LDD  <TMP2
            STD  IR_MLINE,U
            LDA  <TMPB2
            STA  IR_MLINE+2,U
            LDD  <CONTEXT
            STD  IR_SAVECTX,U
            LDX  #WORKBUF
            LEAY IR_SPEC,U
            JSR  COPYSPEC
            JSR  NEWCONTEXT
            LDX  <EXP                  ; the arguments -> the level's area
            LDY  IR_ARGS,U
            CLR  IR_NARGS,U
ME2_ARG     LDA  ,X
            BEQ  ME2_DONE
            JSR  ISSPACE
            BCC  ME2_DONE
            INC  IR_NARGS,U
ME2_ACH     LDA  ,X
            BEQ  ME2_AEND
            CMPA #','
            BEQ  ME2_AEND
            JSR  ISSPACE
            BCC  ME2_AEND
            CMPA #$5C                  ; \x is x (and doesn't end the argument)
            BNE  ME2_APUT
            LDA  1,X
            BEQ  ME2_APUT0
            LEAX 1,X
ME2_APUT0   LDA  ,X
ME2_APUT    LEAX 1,X
            PSHS D
            TFR  Y,D
            SUBD IR_ARGS,U
            CMPD #126
            PULS D
            BHS  ME2_ACH               ; (too long: dropped)
            STA  ,Y+
            BRA  ME2_ACH
ME2_AEND    CLR  ,Y+
            LDA  ,X
            CMPA #','
            BNE  ME2_ARG
            LEAX 1,X
            BRA  ME2_ARG
ME2_DONE    STX  <EXP
            ANDCC #$FE
            RTS
M_NOEXPAND  FCC  "noexpand"
            FCB  0
; U = a macro level: its next line -> LINEBUF, with the arguments put in (\1..\9,
; \0 the name, \* all, \# how many, {n}); carry set at the end.
MACLINE     LDD  IR_MLINE,U
            STD  <FARP
            LDA  IR_MLINE+2,U
            STA  <FARP+2
            JSR  FARMAP
            BNE  ML2_HAVE
            ORCC #1
            RTS
ML2_HAVE    LDD  ,X                    ; the next one, for next time
            STD  IR_MLINE,U
            LDA  2,X
            STA  IR_MLINE+2,U
            LEAX 3,X                   ; the text
            LDY  #LINEBUF
ML2_CHAR    LDA  ,X+
            LBEQ ML2_END
            CMPA #$5C
            BEQ  ML2_BSL
            CMPA #'{'
            BEQ  ML2_BRACE
ML2_PUT     JSR  ML2_OUT
            BRA  ML2_CHAR
ML2_BSL     LDA  ,X
            CMPA #'*'
            BEQ  ML2_ALL
            CMPA #'#'
            BEQ  ML2_COUNT
            JSR  ISDIGIT
            BCS  ML2_PLAIN
            LEAX 1,X
            SUBA #'0'
            BRA  ML2_ARGN
ML2_PLAIN   LDA  #$5C
            BRA  ML2_PUT
ML2_BRACE   CLRB                       ; {n}: n (0 if no digits)
ML2_BDIG    LDA  ,X
            JSR  ISDIGIT
            BCS  ML2_BEND
            LEAX 1,X
            SUBA #'0'
            PSHS A
            LDA  #10
            MUL
            ADDB ,S+
            BRA  ML2_BDIG
ML2_BEND    LDA  ,X
            CMPA #'}'
            BNE  ML2_BNUM
            LEAX 1,X
ML2_BNUM    TFR  B,A
ML2_ARGN    TSTA                       ; A = n: 0 = the name, 1.. = an argument
            BNE  ML2_ARGK
            PSHS X
            LEAX IR_SPEC,U
            BSR  ML2_OUTS
            PULS X
            BRA  ML2_CHAR
ML2_ARGK    CMPA IR_NARGS,U
            BHI  ML2_CHAR              ; (no such argument: nothing)
            PSHS X
            BSR  ML2_ARGP              ; -> X = argument A
            BSR  ML2_OUTS
            PULS X
            BRA  ML2_CHAR
ML2_ALL     LEAX 1,X                   ; \*: all of them, with commas
            PSHS X
            LDA  #1
ML2_ALOOP   CMPA IR_NARGS,U
            BHI  ML2_ADONE
            PSHS A
            BSR  ML2_ARGP
            BSR  ML2_OUTS
            PULS A
            CMPA IR_NARGS,U
            BEQ  ML2_ANOC
            PSHS A
            LDA  #','
            BSR  ML2_OUT
            PULS A
ML2_ANOC    INCA
            BRA  ML2_ALOOP
ML2_ADONE   PULS X
            LBRA ML2_CHAR
ML2_COUNT   LEAX 1,X                   ; \#: how many
            PSHS X
            LDB  IR_NARGS,U
            CLRA
            LDX  #NUMBUF
            JSR  DECSTR
            LDX  #NUMBUF
            BSR  ML2_OUTS
            PULS X
            LBRA ML2_CHAR
ML2_END     CLR  ,Y
            LDD  IR_LINENO,U
            ADDD #1
            STD  IR_LINENO,U
            ANDCC #$FE
            RTS
ML2_OUT     CMPY #LINEBUF+LINEMAX      ; A -> the line (if there is room)
            BHS  ML2_ORET
            STA  ,Y+
ML2_ORET    RTS
ML2_OUTS    LDA  ,X+                   ; X = a string -> the line
            BEQ  ML2_ORET
            BSR  ML2_OUT
            BRA  ML2_OUTS
ML2_ARGP    LDX  IR_ARGS,U             ; A = n (1..): -> X = argument n
ML2_APL     DECA
            BEQ  ML2_ARET
ML2_ASKIP   TST  ,X+
            BNE  ML2_ASKIP
            BRA  ML2_APL
ML2_ARET    RTS
;------------------------------------------------------------------------------
; Structs. A struct record: +0 the next struct, +3 its first field (far
; pointers), +6 its size, +8 the line that defined it, +10 the name. A field:
; +0 the next, +3 its size, +5 a struct it is an instance of (far; 0 = none),
; +8 its name ("" if none).
;------------------------------------------------------------------------------
SR2_NEXT    equ  0
SR2_FIELDS  equ  3
SR2_SIZE    equ  6
SR2_SEQ     equ  8
SR2_NAME    equ  10
FR_NEXT     equ  0
FR_SIZE     equ  3
FR_SUB      equ  5
FR_NAME     equ  8
D_STRUCT    JSR  SKIPOPND
            LDA  #1
            STA  <SYMSET
            TST  <INSTRUCT
            BEQ  SS_NOTIN
            LDA  #ER_STRECUR
            JMP  ERROR
SS_NOTIN    TST  <LABEL
            BNE  SS_NAMED
            LDA  #ER_STRNOSYM
            JMP  ERROR
SS_NAMED    LDX  #LABELNAME
            JSR  STRUCTFIND
            BCS  SS_NEW
            LDD  SR2_SEQ,X
            CMPD <LSEQ
            BEQ  SS_START
            LDA  #ER_STRDUPE
            JMP  ERROR
SS_NEW      LDA  <PASS
            CMPA #1
            BNE  SS_START
            LDX  #LABELNAME
            JSR  STRLEN
            ADDD #SR2_NAME+1
            JSR  HALLOC
            STA  <STRUCTP
            STX  <STRUCTP+1
            LDD  <STRUCTS
            STD  SR2_NEXT,X
            LDA  <STRUCTS+2
            STA  SR2_NEXT+2,X
            CLR  SR2_FIELDS,X
            CLRD
            STD  SR2_SIZE,X
            LDD  <LSEQ
            STD  SR2_SEQ,X
            LEAY SR2_NAME,X
            LDX  #LABELNAME
            JSR  STRCPY
            LDD  <STRUCTP
            STD  <STRUCTS
            LDA  <STRUCTP+2
            STA  <STRUCTS+2
            CLR  <FLDLAST
            BRA  SS_BEGIN
SS_START    STX  <STRUCTP+1            ; (pass 2: the record found)
            LDA  <FARP
            STA  <STRUCTP
SS_BEGIN    LDA  #1
            STA  <INSTRUCT
            CLRD
            STD  <STRSIZE
            LDD  <PC                   ; addresses inside the struct are 0
            STD  <SAVEDPC
            CLRD
            STD  <PC
            STD  <LADDR                ; (this line too, as in lwasm)
            RTS
; RMB (etc.) in a struct: a field of EVAL * OPSIZE bytes.
STRUCTFIELD LDA  <EVFLAGS
            BITA #EF_KNOWN
            BNE  SF4_KNOWN
            LDA  #ER_NOTCONST
            JMP  ERROR
SF4_KNOWN   JSR  COUNTN
            BCS  SF4_RET
            STD  <TMP3
            CLRA                       ; not an instance
            STA  <FARP
            JMP  ADDFIELD
SF4_RET     RTS
; A field of TMP3 bytes (FARP = the struct it instantiates, or 0), named by the
; line's label (if any): added to the struct being defined.
ADDFIELD    LDA  #1
            STA  <SYMSET
            STA  <LSOFFON
            LDD  <STRSIZE              ; its offset (the listing shows it)
            STD  <LSOFF
            ADDD <TMP3
            STD  <STRSIZE
            LDA  <PASS
            CMPA #1
            BNE  AF_RET
            LDD  <FARP                 ; (keep the substruct pointer)
            STD  <TMP2
            LDA  <FARP+2
            STA  <TMPB2
            LDX  #LABELNAME
            TST  <LABEL
            BNE  AF_NAME
            LDX  #ZERO
AF_NAME     STX  <TMP
            JSR  STRLEN
            ADDD #FR_NAME+1
            JSR  HALLOC
            STA  <FARP
            STX  <FARP+1
            CLR  FR_NEXT,X
            LDD  <TMP3
            STD  FR_SIZE,X
            LDD  <TMP2
            STD  FR_SUB,X
            LDA  <TMPB2
            STA  FR_SUB+2,X
            LEAY FR_NAME,X
            LDX  <TMP
            JSR  STRCPY
            TST  <FLDLAST              ; link it at the end
            BNE  AF_AFTER
            LDA  <STRUCTP
            JSR  MAPPG
            LDX  <STRUCTP+1
            LEAX SR2_FIELDS,X
            BRA  AF_LINK
AF_AFTER    LDA  <FLDLAST
            JSR  MAPPG
            LDX  <FLDLAST+1
AF_LINK     LDD  <FARP
            STD  ,X
            LDA  <FARP+2
            STA  2,X
            LDD  <FARP
            STD  <FLDLAST
            LDA  <FARP+2
            STA  <FLDLAST+2
AF_RET      RTS
D_ENDSTRUCT JSR  SKIPOPND
            TST  <INSTRUCT
            BNE  ES_IN
            RTS                        ; (lwasm: a warning)
ES_IN       LDA  <PASS                 ; pass 1: the size into the record
            CMPA #1
            BNE  ES_SYMS
            LDA  <STRUCTP
            JSR  MAPPG
            LDX  <STRUCTP+1
            LDD  <STRSIZE
            STD  SR2_SIZE,X
ES_SYMS     LDA  <STRUCTP              ; name.field symbols (at 0), sizeof{name}
            STA  <FARP
            LDD  <STRUCTP+1
            STD  <FARP+1
            JSR  FARMAP
            LEAX SR2_NAME,X
            LDY  #WORKBUF
            JSR  STRCPY
            CLRD
            STD  <INSTBASE             ; the base address
            JSR  INSTANTIATE
            LDA  #1
            STA  <LSOFFON
            LDD  <STRSIZE
            STD  <LSOFF
            CLR  <INSTRUCT
            LDD  <SAVEDPC
            STD  <PC
            STD  <LADDR
            RTS
; The operation (OPTOK..) as a struct: an instance (a field, inside a struct);
; carry set if there's no such struct.
STRUCTINST  LDY  <OPTOK
            LDX  #NAMEBUF
            LDB  #NAMEMAX
SI2_COPY    CMPY <OPTOKEND
            BHS  SI2_COPIED
            LDA  ,Y+
            STA  ,X+
            DECB
            BNE  SI2_COPY
SI2_COPIED  CLR  ,X
            LDX  #NAMEBUF
            JSR  STRUCTFIND
            BCC  SI2_FOUND
            RTS
SI2_FOUND   TST  <LABEL
            BNE  SI2_NAMED
            LDA  #ER_STRNONAME
            JSR  ERROR
            ORCC #1
            RTS
SI2_NAMED   LDD  SR2_SIZE,X
            STD  <TMP3
            TST  <INSTRUCT
            BEQ  SI2_INST
            JSR  ADDFIELD              ; inside a struct: a field of that type (FARP)
            ANDCC #$FE
            RTS
SI2_INST    LDX  #LABELNAME            ; label.field symbols, at this address
            LDY  #WORKBUF
            JSR  STRCPY
            LDD  <TMP3
            PSHS D                     ; (the size, to reserve)
            LDD  <LADDR
            STD  <INSTBASE
            JSR  INSTANTIATE
            PULS D
            JSR  RESERVE
            ANDCC #$FE
            RTS
; FARP = a struct record, WORKBUF = a prefix, INSTBASE = a base address: defines
; prefix.field = base + offset for every field (and the fields of fields), and
; sizeof{prefix}.
INSTANTIATE LDA  <INSTDEPTH
            CMPA #6
            LBHS IS_RET
            INC  <INSTDEPTH
            JSR  FARMAP
            LDD  SR2_SIZE,X            ; 2,S: the size, for sizeof{}
            PSHS D
            LDD  SR2_FIELDS,X          ; FLDP: the first field
            STD  <FLDP
            LDA  SR2_FIELDS+2,X
            STA  <FLDP+2
            CLRD                       ; 0,S: the offset so far
            PSHS D
IS_FIELD    LDD  <FLDP
            STD  <FARP
            LDA  <FLDP+2
            STA  <FARP+2
            JSR  FARMAP
            LBEQ IS_SIZEOF
            LDD  FR_NEXT,X             ; FLDP = the one after it
            STD  <FLDP
            LDA  FR_NEXT+2,X
            STA  <FLDP+2
            LDD  FR_SIZE,X             ; 3,S: its size (the offset moves to 5,S)
            PSHS D
            LDA  FR_SUB+2,X            ; 0,S: the struct it is, if any
            PSHS A
            LDD  FR_SUB,X
            PSHS D
            LEAX FR_NAME,X             ; NAMEBUF = prefix.name (or prefix.____n)
            PSHS X
            LDX  #WORKBUF
            LDY  #NAMEBUF
            JSR  STRCPY
            LDA  #'.'
            STA  ,Y+
            PULS X
            TST  ,X
            BNE  IS_NAMED
            LDX  #M_UNNAMED
            JSR  STRCPY
            LDD  5,S                   ; (the offset)
            LDX  #NUMBUF
            JSR  DECSTR
            LDX  #NUMBUF
IS_NAMED    JSR  STRCPY
            LDD  <INSTBASE                 ; = base + offset
            ADDD 5,S
            STD  <EVAL+2
            CLRD
            STD  <EVAL
            STD  <EVADJ
            LDA  #EF_KNOWN
            STA  <EVFLAGS
            CLR  EVNT                  ; (an instance in a section: relative to
            TST  <INSTRUCT             ; it; inside a struct, only offsets)
            BNE  IS_OFFSET
            JSR  TSECT1
IS_OFFSET   CLRA
            JSR  SYMDEF
            PULS D                     ; a field that is itself a struct: its fields
            STD  <FARP                 ; too, under prefix.name
            PULS A
            STA  <FARP+2
            TST  <FARP
            BEQ  IS_NOSUB
            LDX  #WORKBUF              ; (the prefix's length, to put it back)
            JSR  STRLEN
            PSHS D
            LDX  #NAMEBUF              ; the longer prefix
            LDY  #WORKBUF
            JSR  STRCPY
            LDD  <INSTBASE                 ; the base: + this field's offset
            PSHS D
            ADDD 6,S
            STD  <INSTBASE
            LDD  <FLDP                 ; (the next field of this level)
            PSHS D
            LDA  <FLDP+2
            PSHS A
            JSR  INSTANTIATE
            PULS A
            STA  <FLDP+2
            PULS D
            STD  <FLDP
            PULS D
            STD  <INSTBASE
            PULS D
            LDX  #WORKBUF
            CLR  D,X
IS_NOSUB    PULS D                     ; the offset += the field's size
            ADDD ,S
            STD  ,S
            LBRA IS_FIELD
IS_SIZEOF   LDX  #M_SIZEOF             ; sizeof{prefix}
            LDY  #NAMEBUF
            JSR  STRCPY
            LDX  #WORKBUF
            JSR  STRCPY
            LDA  #'}'
            STA  ,Y+
            CLR  ,Y
            CLRD
            STD  <EVAL
            STD  <EVADJ
            LDD  2,S
            STD  <EVAL+2
            LDA  #EF_KNOWN
            STA  <EVFLAGS
            CLR  EVNT                  ; (a size: a constant)
            CLRA
            JSR  SYMDEF
            LEAS 4,S
            DEC  <INSTDEPTH
IS_RET      RTS
; X = a name: -> its struct record (FARP, mapped, X), carry clear; carry set if
; there is none. (Case counts, as in lwasm.)
STRUCTFIND  STX  <TMP
            LDD  <STRUCTS
            STD  <FARP
            LDA  <STRUCTS+2
            STA  <FARP+2
SF5_LOOP    JSR  FARMAP
            BEQ  SF5_NONE
            PSHS X
            LEAY SR2_NAME,X
            LDX  <TMP
            JSR  STRCMP
            PULS X
            BEQ  SF5_FOUND
            LDD  SR2_NEXT,X
            STD  <FARP
            LDA  SR2_NEXT+2,X
            STA  <FARP+2
            BRA  SF5_LOOP
SF5_FOUND   ANDCC #$FE
            RTS
SF5_NONE    ORCC #1
            RTS
;------------------------------------------------------------------------------
; End of pa_dir.asm
;------------------------------------------------------------------------------
