;------------------------------------------------------------------------------
; cc1_flt.asm -- CC1: code for floats (and doubles, which are the same).
;
; A float's value is made in Q, as a long's is, so moving one (loads, stores,
; arguments, results, ?: and the rest) is cc1_long.asm's. Arithmetic is the
; library's helpers (__fadd __fsub __fmul __fdiv: the left in Q, the right
; pushed, as the long ones), comparing is __fcmp (which leaves the flags for a
; signed branch), and the conversions are __ltof and __ftol (and the unsigned
; ones). - turns the sign bit over. Constants are folded with the same
; routines: fpcore.asm is part of CC1, so a folded constant has the bits the
; program would have made.
;------------------------------------------------------------------------------
; The helpers' numbers (HELPNAMES).
H_FADD      equ  16                    ; __fadd __fsub __fmul __fdiv: + - * /
H_FCMP      equ  20
H_LTOF      equ  21                    ; __ultof next
H_FTOL      equ  23                    ; __ftoul next
H_FINC      equ  25                    ; __fdec next
H_FLTUSED   equ  27                    ; (not called: only IMPORTed)
; X = a node: carry clear if its type is a float (ISFLTN), or a long or a
; float (ISQN). They keep every register.
ISFLTN      PSHS X
            LDX  N_TYPE,X
            JSR  TISFLOAT
            PULS X,PC
ISQN        PSHS X
            LDX  N_TYPE,X
            JSR  TISQ
            PULS X,PC
; __fltused is IMPORTed: a float (or a pointer to one) was given to "..." or a
; function with no prototype -- printf's or scanf's, it may be -- so the
; library's float conversions for them (fltio.asm) are linked. Keeps all.
FLTUSE      PSHS B
            LDB  #H_FLTUSED
            JSR  HELPBIT
            PULS B,PC
;------------------------------------------------------------------------------
; Values -> Q.
;------------------------------------------------------------------------------
GENF        LDB  N_OP,X
            CMPB #O_DIV
            LBHI GEN_DO
            DECB
            LSLB
            LDY  #GFTAB
            LDY  B,Y
            LBEQ GEN_DO
            JMP  ,Y
GFTAB       FDB  GL_NUM,GL_LOAD,0,0,GL_LOAD,GF_NEG,0,0,GF_CAST
            FDB  0,0,0,0,0,0,0,0,0,0,0,0,GL_LOAD
            FDB  GF_BIN,GF_BIN,GF_BIN,GF_BIN
GF_NEG      LDX  N_L,X
            JSR  GEN
            LDX  #S_EORA80
            JMP  EMITL
; + - * /: the right pushed, the left in Q, the helper.
GF_BIN      PSHS X
            LDX  N_R,X
            JSR  GEN
            JSR  PUSHQ
            LDX  ,S
            LDX  N_L,X
            JSR  GEN
            PULS X
            LDB  N_OP,X
            SUBB #O_ADD-H_FADD
            JSR  CALLHELP
            LDX  #S_LEAS4
            JMP  EMITL
; (float) x: from a long, __ltof (__ultof); from an int or a char, made a long
; first; from a float, as it is.
GF_CAST     PSHS X
            LDX  N_L,X
            JSR  GEN
            PULS X
            LDX  N_L,X
            JSR  ISFLTN
            BCC  GX_RET
            LDB  #H_LTOF
            JSR  ISLONGN
            BCC  GX_LONG
            PSHS B,X
            LDX  N_TYPE,X
            JSR  TISUNS
            PULS B,X
            LDX  #S_SEXQ
            BCS  GX_EXT
            LDX  #S_ZEXQ
GX_EXT      JSR  EMITLINES
            JMP  CALLHELP
GX_LONG     LDY  N_TYPE,X
            LDA  TY_KIND,Y
            CMPA #TK_ULONG
            BNE  GX_CALL
            INCB
GX_CALL     JMP  CALLHELP
GX_RET      RTS
; A float made a long (X = the cast to a long, or to something shorter, whose
; operand is a float and in Q): __ftol, or __ftoul for an unsigned long.
FTOLONG     LDB  #H_FTOL
            LDY  N_TYPE,X
            LDA  TY_KIND,Y
            CMPA #TK_ULONG
            BNE  FL_CALL
            INCB
FL_CALL     JMP  CALLHELP
;------------------------------------------------------------------------------
; Comparing floats: X = the comparison -> code, B = the comparison, CMPUNS 0
; (as CMPGEN). __fcmp's flags are a signed comparison's.
;------------------------------------------------------------------------------
CMPF        CLR  <CMPUNS
            LDB  N_OP,X
            PSHS B,X
            LDX  N_R,X
            JSR  GEN
            JSR  PUSHQ
            LDX  1,S
            LDX  N_L,X
            JSR  GEN
            LDB  #H_FCMP
            JSR  CALLHELP
            LDX  #S_LEAS4
            JSR  EMITL
            PULS B,X,PC
;------------------------------------------------------------------------------
; x op= y for a float x (y made a float already): y pushed, where x is, LDQ x,
; the helper (which keeps X), STQ x. A = 1 if the value is wanted (in Q
; anyway).
;------------------------------------------------------------------------------
GF_ASGOP    PSHS X
            LDX  N_R,X
            JSR  GEN
            JSR  PUSHQ
            LDX  ,S
            LDX  N_L,X
            JSR  GENADDR
            PULS X
            STX  <AGNODE
            JSR  AGKEEP
            LDX  #S_LDQ
            JSR  OPI
            LDX  <AGNODE
            LDB  N_V+1,X
            SUBB #O_ADD-H_FADD
            JSR  CALLHELP
            LDX  #S_LEAS4
            JSR  EMITL
            JSR  AGBACK
            LDX  #S_STQ
            JMP  OPI
;------------------------------------------------------------------------------
; Folding: EOP on EL's and ER's numbers (floats) -> EL's high word (N_X), and D
; its low one, as FOLD32 does; a comparison's 0 or 1.
;------------------------------------------------------------------------------
FOLDF       LDB  <EOP
            CMPB #O_EQ
            BHS  FF_CMP
            LDX  #__fadd
            CMPB #O_ADD
            BEQ  FF_GO
            LDX  #__fsub
            CMPB #O_SUB
            BEQ  FF_GO
            LDX  #__fmul
            CMPB #O_MUL
            BEQ  FF_GO
            LDX  #__fdiv
            CMPB #O_DIV
            LBNE FD_INTERNAL
FF_GO       BSR  FF_CALL
            LDX  <EL
            STD  N_X,X
            STW  N_V,X
            TFR  W,D
            RTS
FF_CMP      LDX  #__fcmp
            BSR  FF_CALL
            STD  <TMP2
            LDX  <EL
            CLRD
            STD  N_X,X
            LDB  <EOP
            SUBB #O_EQ
            LSLB
            LDX  #FFCTAB
            ABX
            LDD  <TMP2                 ; (its flags for the branch)
            JMP  [,X]
FFCTAB      FDB  FZ_EQ,FZ_NE,FZ_LT,FZ_GT,FZ_LE,FZ_GE
FZ_EQ       LBEQ FO_1
            LBRA FO_0
FZ_NE       LBNE FO_1
            LBRA FO_0
FZ_LT       LBLT FO_1
            LBRA FO_0
FZ_GT       LBGT FO_1
            LBRA FO_0
FZ_LE       LBLE FO_1
            LBRA FO_0
FZ_GE       LBGE FO_1
            LBRA FO_0
; X = a routine of fpcore's: Q = EL's number op ER's.
FF_CALL     STX  <TMP
            LDX  <ER
            LDD  N_X,X
            LDW  N_V,X
            PSHSW
            PSHS D
            LDX  <EL
            LDD  N_X,X
            LDW  N_V,X
            JSR  [TMP]
            LEAS 4,S
            RTS
; X = a number: if it's a float, an int of its truth (0 or 1) instead (for
; && and ||). Keeps X.
FTRUTH      JSR  ISFLTN
            BCS  FR_RET
            JSR  NUMZERO
            BEQ  FR_0
            LDD  #1
            BRA  FR_SET
FR_0        CLRD
FR_SET      STD  N_V,X
            CLRD
            STD  N_X,X
            LDD  #TYP_INT
            STD  N_TYPE,X
FR_RET      RTS
;------------------------------------------------------------------------------
S_EORA80    FCN  "EORA #$80"
S_ANDA7F    FCN  "ANDA #$7F"
;------------------------------------------------------------------------------
; End of cc1_flt.asm
;------------------------------------------------------------------------------
