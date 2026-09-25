;------------------------------------------------------------------------------
; pa_out.asm -- pugasm: the output file (raw, .COM, S-records), the symbol table
; at the end of the listing, and the messages.
;------------------------------------------------------------------------------
; Before each pass.
PASSINIT    CLRD
            STD  <RAWZERO
            STD  <FIRSTADDR
            STD  <SRECCNT
            CLR  <SRECLEN
            CLR  <SRECLAST             ; (no byte yet: the next starts a record)
            CLR  <S0DONE
            CLR  <STARTED
            RTS
; Before pass 2: the output (and listing) files. A .COM file starts with its
; program header, from what pass 1 found.
OPENOUT     LDA  <FORMAT
            CMPA #FMT_OBJ
            BNE  OO_OPEN
            LDX  #M_NOOBJ
            JMP  FATAL
OO_OPEN     LDU  #OUTSTRM
            LDX  #OUTNAME
            JSR  SOPEN
            BCC  OO_OK
            LDX  #M_NOOUT
            JMP  FATAL
OO_OK       LDA  #1
            STA  <OUTON
            LDA  <FORMAT
            CMPA #FMT_COM
            BNE  OO_LIST
            LDD  #EXE_MAGIC            ; "PX", load, entry, flags
            JSR  SPUTW
            LDD  <FIRSTADDR
            JSR  SPUTW
            LDD  <FIRSTADDR
            TST  <HAVEEXEC
            BEQ  OO_ENTRY
            LDD  <EXECADDR
OO_ENTRY    JSR  SPUTW
            CLRD
            JSR  SPUTW
OO_LIST     TST  <LISTON
            BEQ  OO_RET
            LDU  #LSTSTRM
            LDX  #LSTNAME
            JSR  SOPEN
            BCC  OO_RET
            LDX  #M_NOLIST
            JSR  PRINTS
            CLR  <LISTON
OO_RET      RTS
SPUTW       PSHS B                     ; D -> the stream U, high byte first
            JSR  SPUTC
            PULS A
            JMP  SPUTC
; The first byte of the output: RAWZERO counts the space reserved before it
; (since the last ORG), which raw output writes as zeros (as lwasm does).
OUTSTART    LDA  <FORMAT
            CMPA #FMT_SREC
            BEQ  OS2_RET
            LDD  <RAWZERO
            TFR  D,X
            LDU  #OUTSTRM
            CLRA
OS2_LOOP    CMPX #0
            BEQ  OS2_DONE
            JSR  SPUTC
            LEAX -1,X
            BRA  OS2_LOOP
OS2_DONE    LDA  #1
            STA  <STARTED
OS2_RET     RTS
; A = an output byte, at PC (pass 2).
OUTBYTE     LDB  <FORMAT
            CMPB #FMT_SREC
            BEQ  SRECBYTE
            LDU  #OUTSTRM
            JMP  SPUTC
; D = bytes of reserved space at PC (pass 2, after the first output byte): raw
; output fills them with zeros.
OUTSKIP     PSHS D
            LDB  <FORMAT
            CMPB #FMT_SREC
            PULS D
            BEQ  OK2_RET
            TFR  D,X
            LDU  #OUTSTRM
            CLRA
OK2_LOOP    CMPX #0
            BEQ  OK2_RET
            JSR  SPUTC
            LEAX -1,X
            BRA  OK2_LOOP
OK2_RET     RTS
;------------------------------------------------------------------------------
; S-records, as lwasm writes them: an S0 header, S1 records of up to 16 bytes
; (a new one at every address jump and every 16-byte boundary), S5 with their
; count, S9 with the exec address (END's operand).
;------------------------------------------------------------------------------
SRECBYTE    PSHS A
            TST  <SRECLAST             ; a new record here?
            BEQ  SB_NEW
            LDD  <SRLASTAD
            ADDD #1
            CMPD <PC
            BNE  SB_NEW
            LDB  <PC+1
            ANDB #15
            BNE  SB_ADD
SB_NEW      TST  <S0DONE
            BNE  SB_FLUSH
            JSR  SRECS0
SB_FLUSH    JSR  SRECFLUSH
            LDD  <PC
            STD  <SRECADDR
SB_ADD      LDB  <SRECLEN
            LDX  #SRECBUF
            ABX
            PULS A
            STA  ,X
            INC  <SRECLEN
            LDD  <PC
            STD  <SRLASTAD
            LDA  #1
            STA  <SRECLAST
            RTS
; The S0 header: "[pugasm 1.0] " and the source's name.
SRECS0      LDA  #1
            STA  <S0DONE
            LDX  #M_SRECHDR
            LDY  #WORKBUF
            JSR  STRCPY
            LDX  #SRCNAME
            LDB  #50-13                ; (lwasm keeps the header under 51)
S0_NAME     LDA  ,X+
            BEQ  S0_NAMED
            STA  ,Y+
            DECB
            BNE  S0_NAME
S0_NAMED    CLR  ,Y
            LDU  #OUTSTRM
            LDX  #WORKBUF
            JSR  STRLEN
            ADDB #3
            STB  <SRECSUM              ; the checksum starts with the count
            LDD  #$5330
            JSR  SPUTW
            LDA  <SRECSUM
            JSR  SPUTHEX
            CLRA
            JSR  SPUTHEX
            JSR  SPUTHEX
S0_DATA     LDA  ,X+
            BEQ  S0_END
            PSHS A
            ADDA <SRECSUM
            STA  <SRECSUM
            PULS A
            JSR  SPUTHEX
            BRA  S0_DATA
S0_END      LDA  <SRECSUM
            COMA
            JSR  SPUTHEX
            JMP  SPUTNL
; The record so far (if any) -> the file.
SRECFLUSH   LDB  <SRECLEN
            BEQ  SF3_RET
            LDU  #OUTSTRM
            ADDB #3
            STB  <SRECSUM
            LDD  #$5331
            JSR  SPUTW
            LDA  <SRECSUM
            JSR  SPUTHEX
            LDD  <SRECADDR
            JSR  SPUTHEX
            PSHS B
            ADDA <SRECSUM
            STA  <SRECSUM
            PULS A
            JSR  SPUTHEX
            ADDA <SRECSUM
            STA  <SRECSUM
            LDX  #SRECBUF
            LDB  <SRECLEN
SF3_DATA    LDA  ,X+
            JSR  SPUTHEX
            ADDA <SRECSUM
            STA  <SRECSUM
            DECB
            BNE  SF3_DATA
            LDA  <SRECSUM
            COMA
            JSR  SPUTHEX
            JSR  SPUTNL
            CLR  <SRECLEN
            LDD  <SRECCNT
            ADDD #1
            STD  <SRECCNT
SF3_RET     RTS
; The end: the last record, S5, S9.
SRECEND     JSR  SRECFLUSH
            LDD  <SRECCNT
            BEQ  SE3_RET
            LDU  #OUTSTRM
            LDD  #$5335
            LDX  <SRECCNT
            BSR  SRECWORD
            LDD  #$5339
            LDX  <EXECADDR
SRECWORD    JSR  SPUTW                 ; "Sn03" X, checksum
            LDA  #3
            STA  <SRECSUM
            JSR  SPUTHEX
            TFR  X,D
            JSR  SPUTHEX
            PSHS B
            ADDA <SRECSUM
            STA  <SRECSUM
            PULS A
            JSR  SPUTHEX
            ADDA <SRECSUM
            COMA
            JSR  SPUTHEX
            JMP  SPUTNL
SE3_RET     RTS
; A -> two hex digits in the stream U. Keeps A and X.
SPUTHEX     PSHS A,X
            LDX  #NUMBUF
            JSR  HEX2
            LDA  NUMBUF
            JSR  SPUTC
            LDA  NUMBUF+1
            JSR  SPUTC
            PULS A,X,PC
;------------------------------------------------------------------------------
; After pass 2.
CLOSEOUT    LDA  <FORMAT
            CMPA #FMT_SREC
            BNE  CO3_CLOSE
            JSR  SRECEND
CO3_CLOSE   LDU  #OUTSTRM
            JSR  SCLOSE
            CLR  <OUTON
            LDD  <ERRCNT               ; errors: no output (lwasm doesn't write one)
            BEQ  CO3_RET
            LDX  #OUTNAME
            LDA  #B_KILL_NAME
            SWI2
            LDX  #M_NOOUTPUT
            JSR  PRINTS
CO3_RET     RTS
CLOSELIST   LDU  #LSTSTRM
            JSR  SCLOSE
            LDD  <ERRCNT               ; errors: no listing either (as lwasm)
            BEQ  CL3_RET
            LDX  #LSTNAME
            LDA  #B_KILL_NAME
            SWI2
CL3_RET     RTS
; A fatal error: everything shut.
CLOSEALL    JSR  CLOSEINPUTS
            LDU  #LSTSTRM
            JSR  SCLOSE
            TST  <OUTON
            BEQ  CA_RET
            LDU  #OUTSTRM
            JSR  SCLOSE
            LDX  #OUTNAME
            LDA  #B_KILL_NAME
            SWI2
CA_RET      RTS
;------------------------------------------------------------------------------
; The symbol table at the end of the listing, in lwasm's order: names compared
; ignoring case; for the same name, globals before locals and locals by context,
; SET versions newest first; names that differ only in case, in the order they
; were defined.
;------------------------------------------------------------------------------
LISTSYMS    LDU  #LSTSTRM
            JSR  SPUTNL
            LDX  #M_SYMTAB
            JSR  SPUTS
            JSR  SPUTNL
            LDD  <NSYMS
            LBEQ LS_RET
            CMPD #4000                 ; (one heap page of pointers)
            BLS  LS_FITS
            LDX  #M_MANYSYMS
            JMP  SPUTS
LS_FITS     STD  <TMP
            ADDD <TMP
            ADDD <TMP                  ; 3 bytes each
            JSR  HALLOC                ; the array: its page, its address
            STA  <ARRPG
            STX  <ARRADDR
            STX  <ARRPTR
            LDX  #HASHTAB              ; fill it from the buckets
            STX  <HBKT
LS_BUCKET   LDX  <HBKT
            LDD  ,X
            STD  <FARP
            LDA  2,X
            STA  <FARP+2
LS_CHAIN    JSR  FARMAP
            BEQ  LS_NEXTB
            LDD  SR_NEXT,X             ; (the next one, for after)
            STD  <TMP3
            LDA  SR_NEXT+2,X
            STA  <TMPB
            LDA  <ARRPG
            JSR  MAPPG
            LDY  <ARRPTR
            LDD  <FARP
            STD  ,Y++
            LDA  <FARP+2
            STA  ,Y+
            STY  <ARRPTR
            LDD  <TMP3
            STD  <FARP
            LDA  <TMPB
            STA  <FARP+2
            BRA  LS_CHAIN
LS_NEXTB    LDX  <HBKT
            LEAX 3,X
            STX  <HBKT
            CMPX #HASHTAB+NHASH*3
            BLO  LS_BUCKET
            JSR  HEAPSORT
            LDD  #0                    ; print them in order
            STD  <TMP2
LS_PRINT    LDD  <TMP2
            CMPD <NSYMS
            BHS  LS_RET
            JSR  ARRGET                ; -> FARP
            JSR  LISTSYM
            LDD  <TMP2
            ADDD #1
            STD  <TMP2
            BRA  LS_PRINT
LS_RET      RTS
; D = an index: -> FARP = that element of the array. Keeps D.
ARRGET      PSHS D,X
            LDA  <ARRPG
            JSR  MAPPG
            LDD  ,S
            ADDD ,S
            ADDD ,S
            ADDD <ARRADDR
            TFR  D,X
            LDD  ,X
            STD  <FARP
            LDA  2,X
            STA  <FARP+2
            PULS D,X,PC
; D = an index: that element = FARP. Keeps D.
ARRPUT      PSHS D,X
            LDA  <ARRPG
            JSR  MAPPG
            LDD  ,S
            ADDD ,S
            ADDD ,S
            ADDD <ARRADDR
            TFR  D,X
            LDD  <FARP
            STD  ,X
            LDA  <FARP+2
            STA  2,X
            PULS D,X,PC
; One line: "[SG] NAME                             VALUE"
LISTSYM     JSR  FARMAP
            LDU  #LSTSTRM
            LDA  #'['
            JSR  SPUTC
            LDA  #' '
            LDB  SR_FLAGS,X
            BITB #SF_SET
            BEQ  LY_NOTSET
            LDA  #'S'
LY_NOTSET   JSR  SPUTC
            LDA  #'G'
            LDB  SR_CTX,X
            CMPB #$FF
            BEQ  LY_GLOBAL
            LDA  #'L'
LY_GLOBAL   JSR  SPUTC
            LDA  #']'
            JSR  SPUTC
            LDA  #' '
            JSR  SPUTC
            PSHS X                     ; the name, padded to 32
            LEAX SR_NAME,X
            JSR  STRLEN
            PSHS D
            JSR  SPUTS
            PULS D
            CMPD #32
            BHS  LY_PADDED
            NEGB
            ADDB #32
            JSR  SPACESTO
LY_PADDED   LDA  #' '
            JSR  SPUTC
            PULS X
            LDA  SR_FLAGS,X            ; the value
            BITA #SF_EXPR
            BNE  LY_EXPR
            LDQ  SR_VAL,X
            STQ  <EVAL
            BRA  LY_HEX
LY_EXPR     LDD  <FARP                 ; (evaluated as a reference would be)
            STD  <SYMP
            LDA  <FARP+2
            STA  <SYMP+2
            LDA  #1
            STA  <EVMODE
            JSR  SYMVALREC
            LDA  <EVFLAGS
            BITA #EF_KNOWN
            BNE  LY_HEX
            LDU  #LSTSTRM
            LDX  #M_INCOMPLETE
            JSR  SPUTS
            JMP  SPUTNL
LY_HEX      LDU  #LSTSTRM              ; %04X of the 32-bit value
            LDX  #NUMBUF
            LDA  <EVAL
            JSR  HEX2
            LDA  <EVAL+1
            JSR  HEX2
            LDD  <EVAL+2
            JSR  HEX4
            CLR  ,X
            LDX  #NUMBUF               ; (at least 4 digits)
LY_SKIP     LDA  ,X
            CMPA #'0'
            BNE  LY_OUT
            CMPX #NUMBUF+4
            BHS  LY_OUT
            LEAX 1,X
            BRA  LY_SKIP
LY_OUT      JSR  SPUTS
            JMP  SPUTNL
;------------------------------------------------------------------------------
; Heap sort of the array (NSYMS elements) with SYMCMP.
;------------------------------------------------------------------------------
HEAPSORT    LDD  <NSYMS                ; build the heap: sift down from n/2-1 to 0
            LSRA
            RORB
HS_BUILD    SUBD #1
            BMI  HS_SORT
            STD  <HSI
            LDD  <NSYMS
            STD  <HSN
            LDD  <HSI
            JSR  SIFTDOWN
            LDD  <HSI
            BRA  HS_BUILD
HS_SORT     LDD  <NSYMS                ; then take the largest to the end
HS_LOOP     SUBD #1
            BLE  HS_RET
            STD  <HSN                  ; swap 0 and n-1
            LDD  #0
            JSR  ARRGET
            LDD  <FARP
            STD  <FARP2
            LDA  <FARP+2
            STA  <FARP2+2
            LDD  <HSN
            JSR  ARRGET
            LDD  #0
            JSR  ARRPUT
            LDD  <FARP2
            STD  <FARP
            LDA  <FARP2+2
            STA  <FARP+2
            LDD  <HSN
            JSR  ARRPUT
            LDD  #0
            JSR  SIFTDOWN
            LDD  <HSN
            BRA  HS_LOOP
HS_RET      RTS
; D = an index: sifts it down in the heap of HSN elements.
SIFTDOWN    STD  <HSJ
SD5_LOOP    LDD  <HSJ                  ; the larger child
            ASLB
            ROLA
            ADDD #1
            CMPD <HSN
            BHS  SD5_RET
            STD  <HSK
            ADDD #1
            CMPD <HSN
            BHS  SD5_ONE
            JSR  ARRGET                ; right > left?
            JSR  SAVEKEY2
            LDD  <HSK
            JSR  ARRGET
            JSR  SYMCMP                ; FARP (left) vs key 2 (right)
            BGE  SD5_ONE
            LDD  <HSK
            ADDD #1
            STD  <HSK
SD5_ONE     LDD  <HSK                  ; the child > this one?
            JSR  ARRGET
            JSR  SAVEKEY2
            LDD  <HSJ
            JSR  ARRGET
            JSR  SYMCMP                ; this vs the child
            BGE  SD5_RET
            LDD  <HSJ                  ; swap them
            JSR  ARRGET
            LDD  <FARP
            STD  <FARP2
            LDA  <FARP+2
            STA  <FARP2+2
            LDD  <HSK
            JSR  ARRGET
            LDD  <HSJ
            JSR  ARRPUT
            LDD  <FARP2
            STD  <FARP
            LDA  <FARP2+2
            STA  <FARP+2
            LDD  <HSK
            JSR  ARRPUT
            LDD  <HSK
            STD  <HSJ
            BRA  SD5_LOOP
SD5_RET     RTS
; The symbol at FARP -> key 2 (KEY2: its name, KEY2CTX, KEY2SEQ).
SAVEKEY2    JSR  FARMAP
            LDD  SR_CTX,X
            STD  <KEY2CTX
            LDD  SR_SEQ,X
            STD  <KEY2SEQ
            LEAX SR_NAME,X
            LDY  #KEY2
            JMP  STRCPY
; The symbol at FARP against key 2, in lwasm's order: -> the flags for a signed
; comparison (BLT: it comes before, BGE: after or the same).
SYMCMP      JSR  FARMAP
            PSHS X
            LEAX SR_NAME,X
            LDY  #KEY2
SC5_LOOP    LDA  ,X+                   ; names, ignoring case
            JSR  LOWCASE
            STA  <TMPB
            LDA  ,Y+
            JSR  LOWCASE
            CMPA <TMPB
            BNE  SC5_DIFF
            TSTA
            BNE  SC5_LOOP
            PULS X                     ; the same ignoring case: exactly the same?
            PSHS X
            LEAX SR_NAME,X
            LDY  #KEY2
            JSR  STRCMP
            PULS X
            BNE  SC5_CASE
            LDD  SR_CTX,X              ; by context (global -1 first)
            CMPD <KEY2CTX
            BNE  SC5_RET
            LDD  <KEY2SEQ              ; SET versions: newest first
            CMPD SR_SEQ,X
            BRA  SC5_UNS
SC5_CASE    LDD  SR_SEQ,X              ; case variants: in order of definition
            CMPD <KEY2SEQ
SC5_UNS     BEQ  SC5_RET               ; (an unsigned comparison, as -1 / 0 / 1)
            BLO  SC5_LESS
SC5_MORE    LDA  #1
            RTS
SC5_DIFF    PULS X
            CMPA <TMPB                 ; key 2's character vs ours
            BLO  SC5_MORE
SC5_LESS    LDA  #-1
SC5_RET     RTS
;------------------------------------------------------------------------------
; Errors (ER_*: their order in ERRTAB) and messages.
;------------------------------------------------------------------------------
ER_BADOPND  equ  1
ER_BADOP    equ  2
ER_6309ONLY equ  3
ER_6809ONLY equ  4
ER_UNDEF    equ  5
ER_UNRESOLVED equ 6
ER_NOTCONST equ  7
ER_BYTEOVF  equ  8
ER_IMMED    equ  9
ER_ILL5     equ  10
ER_NW8      equ  11
ER_BADREG   equ  12
ER_UNKOP    equ  13
ER_BITUNRES equ  14
ER_BITINV   equ  15
ER_IMMUNRES equ  16
ER_DIV0     equ  17
ER_DUPSYM   equ  18
ER_PHASE    equ  19
ER_USER     equ  20
ER_UNSUP    equ  21
ER_BADEXPR  equ  22
ER_ORGUNK   equ  23
ER_MISSSYM  equ  24
ER_SETDPOBJ equ  25
ER_SETDPUNK equ  26
ER_CNTUNK   equ  27
ER_NEGRES   equ  28
ER_ALIGN    equ  29
ER_EXECADDR equ  30
ER_FILENAME equ  31
ER_FILEOPEN equ  32
ER_COND     equ  33
ER_OBJONLY  equ  34
ER_MACRECUR equ  35
ER_MACNONAME equ 36
ER_MACDUPE  equ  37
ER_ENDM     equ  38
ER_STRECUR  equ  39
ER_STRNOSYM equ  40
ER_STRDUPE  equ  41
ER_STRNONAME equ 42
ERRTAB      FCN  "Bad operand"
            FCN  "Bad opcode"
            FCN  "Illegal use of 6309 instruction in 6809 mode"
            FCN  "Illegal use of 6809 instruction in 6309 mode"
            FCN  "Undefined symbol"
            FCN  "Expression not fully resolved"
            FCN  "Expression must be constant"
            FCN  "Byte overflow"
            FCN  "Immediate mode not allowed"
            FCN  "Illegal 5 bit offset"
            FCN  "n,W cannot be 8 bit"
            FCN  "Bad register"
            FCN  "Unknown operation"
            FCN  "Bit number must be fully resolved"
            FCN  "Invalid bit number"
            FCN  "Immediate byte must be fully resolved"
            FCN  "Division by zero"
            FCN  "Multiply defined symbol"
            FCN  "Phase error (a line assembled differently on pass 2)"
            FCN  "User Specified: "
            FCN  "Not supported by pugasm"
            FCN  "Bad expression"
            FCN  "ORG address must be known when it is reached"
            FCN  "Missing symbol"
            FCN  "SETDP not permitted for object target"
            FCN  "SETDP must be constant on pass 1"
            FCN  "Count must be known when it is reached"
            FCN  "Negative reservation sizes make no sense!"
            FCN  "Invalid alignment"
            FCN  "Exec address not constant!"
            FCN  "Missing filename"
            FCN  "Cannot open file"
            FCN  "Conditions must be constant on pass 1"
            FCN  "Only supported for object target"
            FCN  "Attempt to define a macro inside a macro"
            FCN  "Missing macro name"
            FCN  "Duplicate macro definition"
            FCN  "ENDM without MACRO"
            FCN  "Attempt to define a structure inside a structure"
            FCN  "Structure definition with no effect - no symbol"
            FCN  "Duplicate structure definition"
            FCN  "Cannot declare a structure without a symbol name."
M_ERRSEP    FCN  ") : ERROR : "
M_ERRORS    FCB  ' '
            FCC  "error(s)"
            FCB  CR,LF,0
M_NOOUTPUT  FCC  "Not doing output due to assembly errors."
            FCB  CR,LF,0
M_WARNING   FCN  "Warning: "
M_USAGE     FCC  "Usage: PUGASM [-f raw|srec|com|obj] [-o out] [-l[list]] [-s]"
            FCB  CR,LF
            FCC  "              [-I dir] [-3|-9] file"
            FCB  CR,LF,0
M_BADFMT    FCN  "Invalid output format"
M_NOMEM     FCN  "Out of memory"
M_WRITEERR  FCN  "Cannot write the output (disk full?)"
M_DEEP      FCN  "INCLUDEs and macros nested too deeply"
M_NOSOURCE  FCN  "Cannot open the source file"
M_NOINCLUDE FCN  "Cannot open include file "
M_NOOUT     FCN  "Cannot create the output file"
M_NOLIST    FCB  CR,LF
            FCC  "Cannot create the listing file"
            FCB  CR,LF,0
M_NOOBJ     FCN  "Object output isn't done yet"
M_SRECHDR   FCN  "[pugasm 1.0] "
M_SYMTAB    FCN  "Symbol Table:"
M_MANYSYMS  FCC  "(too many symbols to list)"
            FCB  CR,LF,0
M_INCOMPLETE FCN "<<incomplete>>"
M_UNNAMED   FCN  "____"
M_SIZEOF    FCN  "sizeof{"
;------------------------------------------------------------------------------
; End of pa_out.asm
;------------------------------------------------------------------------------
