;------------------------------------------------------------------------------
; pa_obj.asm -- pugasm: object files (lwtools' LWOBJ16, for lwlink or PUGLINK).
;
; In an object file an address is relative to its section, whose place only the
; linker decides; a symbol from another file (IMPORT) has no value here at all.
; A value is kept as a constant plus up to MAXTERMS "terms", each a coefficient
; times a section's base or an import (EVNT, EVTERMS): what lwasm's expression
; simplifier makes of the expressions that can be relocated (sums, differences
; and constant multiples of those). A value with terms left over after the
; operand is complete is relocatable: it sizes as unknown (the largest form)
; and its bytes go out as zeros with a relocation record for the linker, which
; the object file carries in lwasm's form. Anything else (dividing a section
; address, say) is "too complex", as lwasm's own linker couldn't take it either.
;------------------------------------------------------------------------------
; A term: TK_SECT or TK_IMP, the section's number (in the last byte) or the
; import record (a far pointer), the coefficient.
T_KIND      equ  0
T_ID        equ  1
T_COEF      equ  4
TSZ         equ  6
MAXTERMS    equ  4
TK_SECT     equ  1
TK_IMP      equ  2
; A section (SECTAB, MAXSECT of them, numbered from 1 in the order they appear).
SE_NAME     equ  0                 ; up to SNAMEMAX characters, NUL-terminated
SE_FLAGS    equ  32                ; SEF_*
SE_OFF      equ  33                ; where it was left (the next instance goes on)
SE_LEN      equ  35                ; bytes in it so far (pass 2)
SE_CPOS     equ  37                ; bytes in its last chunk
SE_FIRST    equ  39                ; its bytes: a chain of chunks (far pointers)
SE_LAST     equ  42
SE_RELOCS   equ  45                ; its relocation records, newest first
SE_SIZE     equ  48
SNAMEMAX    equ  31
MAXSECT     equ  16
SEF_BSS     equ  1
SEF_CONST   equ  2
; A chunk of section bytes: +0 the next chunk, +3 CHUNKSZ bytes.
CHUNKSZ     equ  1021
; A relocation record: +0 the next, +3 its size (1, 2), +4 its offset in the
; section, +6 the constant, +8 how many terms, +9 the terms.
RL_NEXT     equ  0
RL_SIZE     equ  3
RL_OFF      equ  4
RL_CONST    equ  6
RL_NT       equ  8
RL_TERMS    equ  9
; An import or export record: +0 the next, +3 the name.
NL_NEXT     equ  0
NL_NAME     equ  3
;------------------------------------------------------------------------------
; Terms.
;------------------------------------------------------------------------------
; TNEW = a term: added to the value's (merged with one like it; dropped if its
; coefficient comes to 0). Too many: the value is "complex".
TADD        PSHS D,X,Y
            LDB  EVNT
            LDX  #EVTERMS
TA_FIND     TSTB
            BEQ  TA_NEW
            LDA  T_KIND,X
            CMPA TNEW+T_KIND
            BNE  TA_NEXT
            LDA  T_ID,X
            CMPA TNEW+T_ID
            BNE  TA_NEXT
            LDA  T_ID+1,X
            CMPA TNEW+T_ID+1
            BNE  TA_NEXT
            LDA  T_ID+2,X
            CMPA TNEW+T_ID+2
            BNE  TA_NEXT
            LDD  T_COEF,X              ; like terms: the coefficients add
            ADDD TNEW+T_COEF
            STD  T_COEF,X
            BNE  TA_RET
            JSR  TREMOVE
            BRA  TA_RET
TA_NEXT     LEAX TSZ,X
            DECB
            BRA  TA_FIND
TA_NEW      LDD  TNEW+T_COEF
            BEQ  TA_RET
            LDA  EVNT
            CMPA #MAXTERMS
            BHS  TA_FULL
            LDY  #TNEW
            LDB  #TSZ
TA_COPY     LDA  ,Y+
            STA  ,X+
            DECB
            BNE  TA_COPY
            INC  EVNT
TA_RET      PULS D,X,Y,PC
TA_FULL     LDA  <EVFLAGS
            ORA  #EF_COMPLEX
            STA  <EVFLAGS
            BRA  TA_RET
; X = a term of the value: taken out (the ones after it move down).
TREMOVE     PSHS D,X,Y
            LDB  EVNT
            LDA  #TSZ
            MUL
            ADDD #EVTERMS
            PSHS D                     ; the end of the terms
            LEAY TSZ,X
TRM_LOOP     CMPY ,S
            BHS  TRM_DONE
            LDA  ,Y+
            STA  ,X+
            BRA  TRM_LOOP
TRM_DONE     LEAS 2,S
            DEC  EVNT
            PULS D,X,Y,PC
; D = a factor: every coefficient times it (terms that come to 0 go).
TSCALE      PSHS D,X,Y
            LDX  #EVTERMS
            LDB  EVNT
TSC_LOOP    TSTB
            BEQ  TSC_CLEAN
            PSHS B
            LDD  T_COEF,X
            MULD 1,S
            STW  T_COEF,X
            PULS B
            LEAX TSZ,X
            DECB
            BRA  TSC_LOOP
TSC_CLEAN   LDX  #EVTERMS
            CLRB
TSC_CL      CMPB EVNT
            BHS  TSC_RET
            LDY  T_COEF,X
            BNE  TSC_ADV
            JSR  TREMOVE
            BRA  TSC_CL
TSC_ADV     LEAX TSZ,X
            INCB
            BRA  TSC_CL
TSC_RET     PULS D,X,Y,PC
; The current section's base (+1, or -1 with TSECTM1) added to the value, if
; there is a current section.
TSECT1      LDD  #1
            BRA  TSECTD
TSECTM1     LDD  #-1
TSECTD      TST  <SECTNUM
            BEQ  TS_RET
            PSHS D,Y                   ; (a constant section's base is 0)
            JSR  SECTENT
            LDA  SE_FLAGS,Y
            BITA #SEF_CONST
            PULS D,Y
            BNE  TS_RET
            STD  TNEW+T_COEF
            LDA  #TK_SECT
            STA  TNEW+T_KIND
            CLR  TNEW+T_ID
            CLR  TNEW+T_ID+1
            LDA  <SECTNUM
            STA  TNEW+T_ID+2
            JMP  TADD
TS_RET      RTS
; B = a section number: carry clear if every term of the value is that
; section's base (so, with that section's base 0, the value is a constant).
TALLSECT    PSHS D,X
            LDA  <EVFLAGS
            BITA #EF_COMPLEX
            BNE  TAS_NO
            LDX  #EVTERMS
            LDA  EVNT
TAS_LOOP    TSTA
            BEQ  TAS_YES
            PSHS A
            LDA  T_KIND,X
            CMPA #TK_SECT
            BNE  TAS_NO1
            CMPB T_ID+2,X
            BNE  TAS_NO1
            PULS A
            LEAX TSZ,X
            DECA
            BRA  TAS_LOOP
TAS_NO1     LEAS 1,S
TAS_NO      ORCC #1
            PULS D,X,PC
TAS_YES     ANDCC #$FE
            PULS D,X,PC
; The value's terms, when they are all one section's base: -> B = that section,
; carry clear. Carry set otherwise (or if there are none).
TSAMESECT   LDA  EVNT
            BEQ  TSS_NO
            LDA  EVTERMS+T_KIND
            CMPA #TK_SECT
            BNE  TSS_NO
            LDB  EVTERMS+T_ID+2
            JMP  TALLSECT
TSS_NO      ORCC #1
            RTS
; After an operand's expression (EVALS / EVALV): a PC-relative operand has the
; current section's base taken off (SUBPC); a value with terms left is
; relocatable (EF_RELOC), and unknown for sizing (SIZE mode).
RELFIN      TST  SUBPC
            BEQ  RF_NOSUB
            CLR  SUBPC
            JSR  TSECTM1
RF_NOSUB    LDA  <EVFLAGS
            TST  EVNT
            BNE  RF_REL
            BITA #EF_COMPLEX
            BEQ  RF_RET
RF_REL      ORA  #EF_RELOC
            TST  <EVMODE
            BNE  RF_ST
            ANDA #~EF_KNOWN
RF_ST       STA  <EVFLAGS
RF_RET      ANDCC #$FE                 ; (it parsed)
            RTS
;------------------------------------------------------------------------------
; Relocatable bytes: A = how many (1 or 2): zeros, and (pass 2) a relocation
; record for the linker.
;------------------------------------------------------------------------------
RELEMIT     PSHS A
            LDA  <PASS
            CMPA #2
            BNE  RE_ZEROS
            TST  <SECTNUM              ; (outside a section EMITB complains)
            BEQ  RE_ZEROS
            LDA  <EVFLAGS
            BITA #EF_COMPLEX
            BNE  RE_CPLX
            LDA  ,S
            CMPA #4
            BEQ  RE_CPLX
            JSR  RELREC
            BRA  RE_ZEROS
RE_CPLX     LDA  #ER_COMPLEX
            JSR  ERROR
RE_ZEROS    PULS B
RE_LOOP     CLRA
            JSR  EMITB
            DECB
            BNE  RE_LOOP
            RTS
; A = the size: a relocation record for the value at PC, at the head of the
; section's list.
RELREC      PSHS A
            LDB  EVNT
            LDA  #TSZ
            MUL
            ADDD #RL_TERMS
            JSR  HALLOC                ; A:X, mapped
            STA  TFAR
            STX  TFAR+1
            JSR  SECTENT               ; Y = the section
            LDD  SE_RELOCS,Y
            STD  RL_NEXT,X
            LDA  SE_RELOCS+2,Y
            STA  RL_NEXT+2,X
            LDD  TFAR
            STD  SE_RELOCS,Y
            LDA  TFAR+2
            STA  SE_RELOCS+2,Y
            PULS A
            STA  RL_SIZE,X
            LDD  <PC
            STD  RL_OFF,X
            LDD  <EVAL+2
            STD  RL_CONST,X
            LDB  EVNT
            STB  RL_NT,X
            LDA  #TSZ
            MUL
            TFR  D,W
            LEAY RL_TERMS,X
            LDX  #EVTERMS
            TFM  X+,Y+
            RTS
;------------------------------------------------------------------------------
; Section bytes (pass 2).
;------------------------------------------------------------------------------
; B = a section number: -> Y = its entry. SECTENT: the current section's.
SECTENTB    PSHS D
            DECB
            LDA  #SE_SIZE
            MUL
            ADDD #SECTAB
            TFR  D,Y
            PULS D,PC
SECTENT     PSHS B
            LDB  <SECTNUM
            BSR  SECTENTB
            PULS B,PC
; A = a byte for the current section (outside one: an error, once a line).
SECTBYTE    PSHS D,X,Y
            TST  <SECTNUM
            BNE  SBY_IN
            TST  <LINEERR
            BNE  SBY_RET
            LDA  #ER_NOSECT
            JSR  ERROR
            BRA  SBY_RET
SBY_IN      JSR  SECTENT
            LDA  SE_FLAGS,Y            ; bss and constant sections: counted only
            BITA #SEF_BSS|SEF_CONST
            BNE  SBY_COUNT
            TST  SE_LAST,Y
            BEQ  SBY_NEW
            LDD  SE_CPOS,Y
            CMPD #CHUNKSZ
            BLO  SBY_PUT
SBY_NEW     LDD  #CHUNKSZ+3            ; another chunk
            JSR  HALLOC
            CLR  ,X
            PSHS A,X
            TST  SE_LAST,Y
            BNE  SBY_LINK
            LDA  ,S
            STA  SE_FIRST,Y
            LDD  1,S
            STD  SE_FIRST+1,Y
            BRA  SBY_SETL
SBY_LINK    LDA  SE_LAST,Y
            JSR  MAPPG
            LDX  SE_LAST+1,Y
            LDA  ,S
            STA  ,X
            LDD  1,S
            STD  1,X
SBY_SETL    PULS A,X
            STA  SE_LAST,Y
            STX  SE_LAST+1,Y
            CLRD
            STD  SE_CPOS,Y
SBY_PUT     LDA  SE_LAST,Y
            JSR  MAPPG
            LDX  SE_LAST+1,Y
            LEAX 3,X
            LDD  SE_CPOS,Y
            LEAX D,X
            LDA  ,S
            STA  ,X
            LDD  SE_CPOS,Y
            ADDD #1
            STD  SE_CPOS,Y
SBY_COUNT   LDD  SE_LEN,Y
            ADDD #1
            STD  SE_LEN,Y
SBY_RET     PULS D,X,Y,PC
; D = bytes of reserved space in the current section (RMB): zeros in the
; object file, as lwasm writes them (outside a section: nothing).
SECTSKIP    PSHS D,X,Y
            TST  <SECTNUM
            BEQ  SSK_RET
            JSR  SECTENT
            LDA  SE_FLAGS,Y
            BITA #SEF_BSS|SEF_CONST
            BEQ  SSK_ZEROS
            LDD  SE_LEN,Y              ; (bss: only the length)
            ADDD ,S
            STD  SE_LEN,Y
            BRA  SSK_RET
SSK_ZEROS   LDX  ,S
SSK_LOOP    CMPX #0
            BEQ  SSK_RET
            CLRA
            JSR  SECTBYTE
            LEAX -1,X
            BRA  SSK_LOOP
SSK_RET     PULS D,X,Y,PC
; Carry set if the current section is bss or constant (FILL and ALIGN only
; reserve space there).
SECTISBSS   TST  <SECTNUM
            BEQ  SIB_NO
            PSHS Y
            JSR  SECTENT
            LDA  SE_FLAGS,Y
            PULS Y
            BITA #SEF_BSS|SEF_CONST
            BEQ  SIB_NO
            ORCC #1
            RTS
SIB_NO      ANDCC #$FE
            RTS
; Before each pass: no section, and each one empty and at 0.
OBJPASS     CLR  <SECTNUM
            LDB  NSECT
            BEQ  OP_RET
OP_LOOP     JSR  SECTENTB
            LEAX SE_OFF,Y
            LDA  #SE_SIZE-SE_OFF
OP_CLR      CLR  ,X+
            DECA
            BNE  OP_CLR
            DECB
            BNE  OP_LOOP
OP_RET      RTS
;------------------------------------------------------------------------------
; SECTION name[,flag] / SECT: start (or go on with) a section. ENDSECTION /
; ENDSECT: leave it. (lwasm: a context break each, an address from 0 outside.)
;------------------------------------------------------------------------------
D_SECTION   LDA  <FORMAT
            CMPA #FMT_OBJ
            BEQ  SC6_OBJ
            JSR  SKIPOPND
            LDA  #ER_SECTTARGET
            JMP  ERROR
SC6_OBJ     LDX  <EXP
            LDA  ,X
            BEQ  SC6_NONAME
            JSR  ISSPACE
            BCS  SC6_NAMED
SC6_NONAME  LDA  #ER_SECTNAME
            JMP  ERROR
SC6_NAMED   JSR  SECTLEAVE             ; the current one keeps its place
            LDY  #NAMEBUF              ; the name -> NAMEBUF
            LDB  #SNAMEMAX
SC6_NCH     LDA  ,X
            BEQ  SC6_NEND
            CMPA #','
            BEQ  SC6_NEND
            JSR  ISSPACE
            BCC  SC6_NEND
            LEAX 1,X
            TSTB
            BEQ  SC6_NCH
            STA  ,Y+
            DECB
            BRA  SC6_NCH
SC6_NEND    CLR  ,Y
            CLR  WORKBUF               ; the flag -> WORKBUF
            LDA  ,X
            CMPA #','
            BNE  SC6_NOOPT
            LEAX 1,X
            LDY  #WORKBUF
            LDB  #15
SC6_OCH     LDA  ,X
            BEQ  SC6_OEND
            JSR  ISSPACE
            BCC  SC6_OEND
            LEAX 1,X
            TSTB
            BEQ  SC6_OCH
            STA  ,Y+
            DECB
            BRA  SC6_OCH
SC6_OEND    CLR  ,Y
SC6_NOOPT   STX  <EXP
            JSR  SECTFIND              ; -> B
            LBCC SC6_HAVE
            LDA  NSECT                 ; a new one
            CMPA #MAXSECT
            BLO  SC6_ROOM
            LDA  #ER_MANYSECT
            JMP  ERROR
SC6_ROOM    CLR  TMPF                  ; its flags: from the name, then the option
            LDX  #NAMEBUF
            LDY  #M_NBSS+1             ; "bss"
            JSR  STRCMPI
            BEQ  SC6_ISBSS
            LDX  #NAMEBUF
            LDY  #M_DOTBSS
            JSR  STRCMPI
            BNE  SC6_NOTBSS
SC6_ISBSS   LDA  #SEF_BSS
            STA  TMPF
SC6_NOTBSS  LDX  #NAMEBUF
            LDY  #M_UCONST
            JSR  STRCMPI
            BEQ  SC6_ISCON
            LDX  #NAMEBUF
            LDY  #M_UCONSTS
            JSR  STRCMPI
            BNE  SC6_OPT
SC6_ISCON   LDA  TMPF
            ORA  #SEF_CONST
            STA  TMPF
SC6_OPT     TST  WORKBUF
            BEQ  SC6_MAKE
            LDX  #WORKBUF
            LDY  #M_NBSS+1             ; "bss"
            JSR  STRCMPI
            BNE  SC6_O2
            LDA  TMPF
            ORA  #SEF_BSS
            BRA  SC6_OSET
SC6_O2      LDX  #WORKBUF
            LDY  #M_NBSS               ; "!bss"
            JSR  STRCMPI
            BNE  SC6_O3
            LDA  TMPF
            ANDA #~SEF_BSS
            BRA  SC6_OSET
SC6_O3      LDX  #WORKBUF              ; "constant", "!constant" (lwasm: both set it)
            LDY  #M_NCONST+1
            JSR  STRCMPI
            BEQ  SC6_OCON
            LDX  #WORKBUF
            LDY  #M_NCONST
            JSR  STRCMPI
            BEQ  SC6_OCON
            LDA  #ER_SECTFLAG
            JMP  ERROR
SC6_OCON    LDA  TMPF
            ORA  #SEF_CONST
SC6_OSET    STA  TMPF
SC6_MAKE    INC  NSECT
            LDB  NSECT
            JSR  SECTENTB
            LEAX ,Y                    ; clear it, then name and flags
            LDA  #SE_SIZE
SC6_CLR     CLR  ,X+
            DECA
            BNE  SC6_CLR
            LDX  #NAMEBUF
            JSR  STRCPY
            LDB  NSECT
            JSR  SECTENTB
            LDA  TMPF
            STA  SE_FLAGS,Y
SC6_HAVE    STB  <SECTNUM
            JSR  SECTENTB
            LDA  SE_FLAGS,Y            ; a constant section always starts at 0
            BITA #SEF_CONST
            BEQ  SC6_GO
            CLRD
            STD  SE_OFF,Y
SC6_GO      LDD  SE_OFF,Y
            STD  <PC
            STD  <LADDR
            STD  <STARPC
            CLR  <PCX
            CLR  <LPCX
            CLRD
            STD  <PCADJ
            STD  <LPCADJ
            JMP  NEWCONTEXT
; Leaving the current section (if any): it remembers PC.
SECTLEAVE   TST  <SECTNUM
            BEQ  SLV_RET
            PSHS Y
            JSR  SECTENT
            LDD  <PC
            STD  SE_OFF,Y
            PULS Y
            CLR  <SECTNUM              ; (out of it, even if what follows fails)
SLV_RET     RTS
; NAMEBUF = a section name: -> B = its number, carry clear; carry set if there
; is no such section. (The name's case counts.)
SECTFIND    LDB  NSECT
            BEQ  SF6_NONE
SF6_LOOP    JSR  SECTENTB
            PSHS B
            LEAX ,Y
            LDY  #NAMEBUF
            JSR  STRCMP
            PULS B
            BEQ  SF6_FOUND
            DECB
            BNE  SF6_LOOP
SF6_NONE    ORCC #1
            RTS
SF6_FOUND   ANDCC #$FE
            RTS
D_ENDSECTION LDA <FORMAT
            CMPA #FMT_OBJ
            BEQ  ES6_OBJ
            JSR  SKIPOPND
            LDA  #ER_SECTTARGET
            JMP  ERROR
ES6_OBJ     TST  <SECTNUM
            BNE  ES6_IN
            JSR  SKIPOPND
            LDA  #ER_ENDSECT
            JMP  ERROR
ES6_IN      JSR  SECTLEAVE
            CLR  <SECTNUM
            CLRD
            STD  <PC
            STD  <LADDR                ; (lwasm: the line's address is 0 too)
            JSR  NEWCONTEXT
            JMP  SKIPOPND
;------------------------------------------------------------------------------
; EXPORT, IMPORT / EXTERN / EXTERNAL, EXTDEP: "name OP" or "OP name,name...".
; Exports and imports are lists built on pass 1 (newest first, as lwasm keeps
; them); pass 2 checks that each export is defined.
;------------------------------------------------------------------------------
D_EXPORT    LDA  #ER_OBJEXPORT
            LDX  #EXPORT1
            BRA  NAMELIST
D_IMPORT
D_EXTERN    LDA  #ER_OBJIMPORT
            LDX  #IMPORT1
            BRA  NAMELIST
D_EXTDEP    LDB  <FORMAT
            CMPB #FMT_OBJ
            BEQ  XD_OBJ
            JSR  SKIPOPND
            LDA  #ER_OBJEXTDEP
            JMP  ERROR
XD_OBJ      LDA  #1
            STA  <SYMSET
            JSR  SKIPOPND
            TST  <SECTNUM
            BNE  XD_RET
            LDA  #ER_EXTDEP
            JMP  ERROR
XD_RET      RTS
; A = the error outside object output, X = what to do with each name (in
; NAMEBUF).
NAMELIST    LDB  <FORMAT
            CMPB #FMT_OBJ
            BEQ  NL_OBJ
            PSHS A
            JSR  SKIPOPND
            PULS A
            JMP  ERROR
NL_OBJ      STX  TFAR                  ; (the handler)
            LDA  #1
            STA  <SYMSET
            TST  <LABEL
            BEQ  NL_LIST
            LDX  #LABELNAME            ; the label is the name
            LDY  #NAMEBUF
            JSR  STRCPY
            JSR  [TFAR]
            JMP  SKIPOPND
NL_LIST     LDX  <EXP
NLS_NAME    LDY  #NAMEBUF
            LDB  #NAMEMAX
NL_CH       LDA  ,X
            BEQ  NL_END
            CMPA #','
            BEQ  NL_END
            JSR  ISSPACE
            BCC  NL_END
            LEAX 1,X
            TSTB
            BEQ  NL_CH
            STA  ,Y+
            DECB
            BRA  NL_CH
NL_END      CLR  ,Y
            STX  <EXP
            TST  NAMEBUF
            BNE  NL_DO
            LDA  #ER_MISSSYM
            JMP  ERROR
NL_DO       JSR  [TFAR]
            LDX  <EXP
            LDA  ,X
            CMPA #','
            BNE  NL_RET
            LEAX 1,X
NL_SKIP     LDA  ,X                    ; (spaces after a comma)
            BEQ  NLS_NAME
            JSR  ISSPACE
            BCS  NLS_NAME
            LEAX 1,X
            BRA  NL_SKIP
NL_RET      RTS
; NAMEBUF: exported. Pass 1 lists it; pass 2 checks it is defined.
EXPORT1     LDA  <PASS
            CMPA #1
            BEQ  EX1_ADD
            JSR  SYMFIND
            BCC  EX1_RET
            LDA  #ER_UNDEFEXP
            JMP  ERROR
EX1_ADD     LDX  #EXPORTS
            BRA  NLADD
EX1_RET     RTS
; NAMEBUF: imported (pass 1 lists it).
IMPORT1     LDA  <PASS
            CMPA #1
            BNE  EX1_RET
            LDX  #IMPORTS
; X = a list head (a far pointer): a new record for NAMEBUF at its head.
NLADD       PSHS X
            LDX  #NAMEBUF
            JSR  STRLEN
            ADDD #NL_NAME+1
            JSR  HALLOC                ; A:X
            LDY  ,S
            PSHS A
            LDD  ,Y                    ; the old head is its next
            STD  NL_NEXT,X
            LDA  2,Y
            STA  NL_NEXT+2,X
            PULS A
            STA  ,Y                    ; it is the head
            STX  1,Y
            LEAY NL_NAME,X
            LDX  #NAMEBUF
            JSR  STRCPY
            PULS X,PC
; NAMEBUF, which isn't a symbol: -> FARP = its import record, carry clear;
; carry set if it isn't imported either (or this isn't object output).
IMPFIND     LDA  <FORMAT
            CMPA #FMT_OBJ
            BNE  IF6_NONE
            LDD  IMPORTS
            STD  <FARP
            LDA  IMPORTS+2
            STA  <FARP+2
IF6_LOOP    JSR  FARMAP
            BEQ  IF6_NONE
            PSHS X
            LEAX NL_NAME,X
            LDY  #NAMEBUF
            JSR  STRCMP
            PULS X
            BEQ  IF6_FOUND
            LDD  NL_NEXT,X
            STD  <FARP
            LDA  NL_NEXT+2,X
            STA  <FARP+2
            BRA  IF6_LOOP
IF6_FOUND   ANDCC #$FE
            RTS
IF6_NONE    ORCC #1
            RTS
;------------------------------------------------------------------------------
; The object file, after pass 2 (lwasm's write_code_obj): "LWOBJ16", then each
; section, newest first: its name, flags, its local symbols (its base as
; "\x02name", then every non-SET symbol defined in it whose value is fixed
; relative to it, in symbol-table order), the exports in it, the relocations,
; its length and bytes. A NUL at the end.
;------------------------------------------------------------------------------
WRITEOBJ    LDU  #OUTSTRM
            LDX  #M_LWOBJ
            JSR  SPUTS
            CLRA
            JSR  SPUTC
            JSR  SORTSYMS
            BCC  WO_SORTED
            LDX  #M_OBJSYMS
            JMP  FATAL
WO_SORTED   LDB  NSECT
            STB  WOSECT
WO_SECT     LDB  WOSECT
            LBEQ WO_END
            JSR  SECTENTB
            STY  WOENT
            LDU  #OUTSTRM
            LEAX SE_NAME,Y             ; the name, the flags
            JSR  SPUTS
            CLRA
            JSR  SPUTC
            LDB  SE_FLAGS,Y
            BITB #SEF_BSS
            BEQ  WO_NOBSS
            LDA  #1
            JSR  SPUTC
WO_NOBSS    BITB #SEF_CONST
            BEQ  WO_NOCON
            LDA  #2
            JSR  SPUTC
WO_NOCON    CLRA
            JSR  SPUTC
            BITB #SEF_CONST            ; the base, as a local symbol
            BNE  WO_SYMS
            LDA  #2
            JSR  SPUTC
            LEAX SE_NAME,Y
            JSR  SPUTS
            CLRA
            JSR  SPUTC
            JSR  SPUTC
            JSR  SPUTC
WO_SYMS     CLRD                       ; the symbols in it
            STD  WOI
WO_SYMLOOP  LDD  WOI
            CMPD <NSYMS
            BHS  WO_SYMEND
            JSR  ARRGET                ; -> FARP
            ADDD #1
            STD  WOI
            JSR  FARMAP
            LDA  SR_SECT,X
            CMPA WOSECT
            BNE  WO_SYMLOOP
            LDA  SR_FLAGS,X
            BITA #SF_SET
            BNE  WO_SYMLOOP
            JSR  WOVALUE               ; its value, fixed in this section?
            BCS  WO_SYMLOOP
            JSR  FARMAP
            LDU  #OUTSTRM
            PSHS X
            LEAX SR_NAME,X
            JSR  SPUTS
            PULS X
            LDA  SR_FLAGS,X
            BITA #SF_LOCAL
            BEQ  WO_GLOBAL
            LDA  #1                    ; a local one: "\x01" and its context
            JSR  SPUTC
            LDD  SR_CTX,X
            LDX  #NUMBUF
            JSR  DECSTR
            LDX  #NUMBUF
            JSR  SPUTS
WO_GLOBAL   CLRA
            JSR  SPUTC
            LDD  <EVAL+2
            JSR  SPUTW
            BRA  WO_SYMLOOP
WO_SYMEND   CLRA
            JSR  SPUTC
            LDD  EXPORTS               ; the exports in it
            STD  WOP
            LDA  EXPORTS+2
            STA  WOP+2
WO_EXPLOOP  LDD  WOP
            STD  <FARP
            LDA  WOP+2
            STA  <FARP+2
            JSR  FARMAP
            BEQ  WO_EXPEND
            LDD  NL_NEXT,X
            STD  WOP
            LDA  NL_NEXT+2,X
            STA  WOP+2
            LEAX NL_NAME,X
            LDY  #NAMEBUF
            JSR  STRCPY
            CLR  <LSEQ                 ; (the newest version, as lwasm finds it)
            CLR  <LSEQ+1
            DEC  <LSEQ
            JSR  SYMFIND
            BCS  WO_EXPLOOP
            LDA  SR_SECT,X
            CMPA WOSECT
            BNE  WO_EXPLOOP
            LDD  <SYMP
            STD  <FARP
            LDA  <SYMP+2
            STA  <FARP+2
            JSR  WOVALUE
            BCS  WO_EXPLOOP
            LDU  #OUTSTRM
            LDX  #NAMEBUF
            JSR  SPUTS
            CLRA
            JSR  SPUTC
            LDD  <EVAL+2
            JSR  SPUTW
            BRA  WO_EXPLOOP
WO_EXPEND   LDU  #OUTSTRM
            CLRA
            JSR  SPUTC
            LDY  WOENT                 ; the relocations
            LDD  SE_RELOCS,Y
            STD  WOP
            LDA  SE_RELOCS+2,Y
            STA  WOP+2
WO_RELLOOP  LDD  WOP
            STD  <FARP
            LDA  WOP+2
            STA  <FARP+2
            JSR  FARMAP
            BEQ  WO_RELEND
            LDD  RL_NEXT,X
            STD  WOP
            LDA  RL_NEXT+2,X
            STA  WOP+2
            LDY  #RLBUF                ; (a copy: the names are on other pages)
            LDW  #RL_TERMS+MAXTERMS*TSZ
            TFM  X+,Y+
            JSR  WORELOC
            BRA  WO_RELLOOP
WO_RELEND   CLRA
            JSR  SPUTC
            LDY  WOENT                 ; the length, the bytes
            LDB  SE_FLAGS,Y
            BITB #SEF_CONST
            BEQ  WO_HASLEN
            CLRD                       ; (a constant section: none)
            BRA  WO_LEN
WO_HASLEN   LDD  SE_LEN,Y
WO_LEN      JSR  SPUTW
            LDB  SE_FLAGS,Y
            BITB #SEF_BSS|SEF_CONST
            BNE  WO_NEXTS
            JSR  WOBYTES
WO_NEXTS    DEC  WOSECT
            LBRA WO_SECT
WO_END      LDU  #OUTSTRM
            CLRA
            JMP  SPUTC
; FARP = a symbol (mapped): its value, in VALUE mode -> EVAL...; carry clear
; if, with the section's base taken as 0, it is a constant.
WOVALUE     LDD  <FARP
            STD  <SYMP
            LDA  <FARP+2
            STA  <SYMP+2
            LDA  #1
            STA  <EVMODE
            JSR  SYMVALREC
            LDA  <EVFLAGS
            BITA #EF_KNOWN
            BEQ  WV_NO
            LDB  WOSECT
            JMP  TALLSECT
WV_NO       ORCC #1
            RTS
; RLBUF = a relocation record: written as lwasm writes its expression -- the
; constant (if not 0), each term (times its coefficient, if not 1), then a "+"
; for each more -- and the offset.
WORELOC     LDU  #OUTSTRM
            LDA  RLBUF+RL_SIZE
            CMPA #1
            BNE  WR_16
            LDD  #$FF01                ; an 8-bit one
            JSR  SPUTW
WR_16       LDB  RLBUF+RL_NT           ; how many parts
            STB  WOCNT
            LDD  RLBUF+RL_CONST
            BEQ  WR_TERMS
            INC  WOCNT
            LDA  #1
            JSR  SPUTC
            LDD  RLBUF+RL_CONST
            JSR  SPUTW
WR_TERMS    LDX  #RLBUF+RL_TERMS
            LDB  RLBUF+RL_NT
WR_TLOOP    TSTB
            BEQ  WR_OPS
            PSHS B,X
            LDD  T_COEF,X
            CMPD #1
            BEQ  WR_NOCOEF
            LDA  #1
            JSR  SPUTC
            LDD  T_COEF,X
            JSR  SPUTW
WR_NOCOEF   LDA  T_KIND,X
            CMPA #TK_SECT
            BNE  WR_IMP
            LDD  #$0302                ; a section's base: "\x02name"
            JSR  SPUTW
            LDB  T_ID+2,X
            JSR  SECTENTB
            LEAX SE_NAME,Y
            JSR  SPUTS
            BRA  WR_TEND
WR_IMP      LDA  #2                    ; an import: its name
            JSR  SPUTC
            LDD  T_ID,X
            STD  <FARP
            LDA  T_ID+2,X
            STA  <FARP+2
            JSR  FARMAP
            LEAX NL_NAME,X
            JSR  SPUTS
WR_TEND     CLRA
            JSR  SPUTC
            LDX  1,S
            LDD  T_COEF,X
            CMPD #1
            BEQ  WR_NEXT
            LDD  #$0403                ; "*"
            JSR  SPUTW
WR_NEXT     PULS B,X
            LEAX TSZ,X
            DECB
            BRA  WR_TLOOP
WR_OPS      DEC  WOCNT                 ; the "+"s
            BEQ  WR_END
            LDD  #$0401
            JSR  SPUTW
            BRA  WR_OPS
WR_END      CLRA
            JSR  SPUTC
            LDD  RLBUF+RL_OFF
            JMP  SPUTW
; Y = a section's entry: its bytes, from its chunks.
WOBYTES     LDD  SE_LEN,Y
            STD  WOI                   ; (bytes still to write)
            LDD  SE_FIRST,Y
            STD  <FARP
            LDA  SE_FIRST+2,Y
            STA  <FARP+2
WB_CHUNK    LDD  WOI
            BEQ  WB_RET
            JSR  FARMAP
            BEQ  WB_RET
            LDD  ,X                    ; (the next one)
            STD  WOP
            LDA  2,X
            STA  WOP+2
            LEAX 3,X
            LDD  WOI
            CMPD #CHUNKSZ
            BLS  WB_N
            LDD  #CHUNKSZ
WB_N        TFR  D,Y
            PSHS D
            LDD  WOI
            SUBD ,S++
            STD  WOI
WB_LOOP     LDA  ,X+
            JSR  SPUTC
            LEAY -1,Y
            BNE  WB_LOOP
            LDD  WOP
            STD  <FARP
            LDA  WOP+2
            STA  <FARP+2
            BRA  WB_CHUNK
WB_RET      RTS
; The listing's symbol table, object output: "c" (a constant) or "s", and a
; value relative to a section says which. X = the record (mapped); the value
; has been evaluated. -> A = 'c' or 's'.
SYMKIND     LDA  EVNT
            BNE  SK_S
            LDA  <EVFLAGS
            BITA #EF_COMPLEX
            BNE  SK_S
            LDA  #'c'
            RTS
SK_S        LDA  #'s'
            RTS
M_LWOBJ     FCN  "LWOBJ16"
M_OBJSYMS   FCN  "Too many symbols for an object file"
M_DOTBSS    FCN  ".bss"
M_NBSS      FCN  "!bss"
M_NCONST    FCN  "!constant"
M_UCONST    FCN  "_constant"
M_UCONSTS   FCN  "_constants"
;------------------------------------------------------------------------------
; End of pa_obj.asm
;------------------------------------------------------------------------------
