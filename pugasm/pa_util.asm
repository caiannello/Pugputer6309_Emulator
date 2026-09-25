;------------------------------------------------------------------------------
; pa_util.asm -- pugasm: console output, strings, numbers, character classes.
;------------------------------------------------------------------------------
; X = a NUL-terminated string -> the console. Keeps every register.
PRINTS      PSHS D,X,Y
            LDB  #F_STDOUT
            LDA  #B_PUTS
            SWI2
            PULS D,X,Y,PC
PRINTC      PSHS D,X,Y                 ; A = a character
            PSHSW
            TFR  A,E
            LDB  #F_STDOUT
            LDA  #B_PUTC
            SWI2
            PULSW
            PULS D,X,Y,PC
PRINTNL     PSHS A
            LDA  #CR
            BSR  PRINTC
            LDA  #LF
            BSR  PRINTC
            PULS A,PC
PRINTDEC    PSHS D,X                   ; D = an unsigned number, in decimal
            LDX  #NUMBUF
            JSR  DECSTR
            LDX  #NUMBUF
            BSR  PRINTS
            PULS D,X,PC
;------------------------------------------------------------------------------
; D = an unsigned number, X = where: its decimal digits, NUL-terminated. X ends at
; the NUL. Keeps D.
DECSTR      PSHS D,Y,U
            LDU  #DECPOW
            CLR  ,-S                   ; a digit printed yet?
DS_POW      CLR  ,-S                   ; this digit
DS_SUB      CMPD ,U
            BLO  DS_EMIT
            SUBD ,U
            INC  ,S
            BRA  DS_SUB
DS_EMIT     PSHS D
            LDA  2,S
            BNE  DS_PUT
            TST  3,S
            BNE  DS_PUT
            CMPU #DECPOW_LAST
            BNE  DS_SKIP
DS_PUT      ADDA #'0'
            STA  ,X+
            INC  3,S
DS_SKIP     PULS D
            LEAS 1,S
            LEAU 2,U
            CMPU #DECPOW_END
            BNE  DS_POW
            LEAS 1,S
            CLR  ,X
            PULS D,Y,U,PC
DECPOW      FDB  10000,1000,100,10
DECPOW_LAST FDB  1
DECPOW_END
; D = a number: its decimal digits, 5 of them with leading zeros ("%05d"). X as
; DECSTR.
DEC5STR     PSHS D,Y,U
            LDU  #DECPOW
D5_POW      CLR  ,-S
D5_SUB      CMPD ,U
            BLO  D5_EMIT
            SUBD ,U
            INC  ,S
            BRA  D5_SUB
D5_EMIT     PSHS B
            LDB  1,S
            ADDB #'0'
            STB  ,X+
            PULS B
            LEAS 1,S
            LEAU 2,U
            CMPU #DECPOW_END
            BNE  D5_POW
            CLR  ,X
            PULS D,Y,U,PC
; A = a byte: its two hex digits at X (X advances). Keeps A.
HEX2        PSHS A
            LSRA
            LSRA
            LSRA
            LSRA
            BSR  HEXDIG
            LDA  ,S
            ANDA #$0F
            BSR  HEXDIG
            PULS A,PC
HEXDIG      CMPA #10
            BLO  HD_NUM
            ADDA #7
HD_NUM      ADDA #'0'
            STA  ,X+
            RTS
HEX4        PSHS D                     ; D = a word: four hex digits at X
            BSR  HEX2
            TFR  B,A
            BSR  HEX2
            PULS D,PC
;------------------------------------------------------------------------------
; X -> Y, with its NUL; Y ends at the NUL (so more can be added). X ends after it.
STRCPY      PSHS A
SC_LOOP     LDA  ,X+
            STA  ,Y+
            BNE  SC_LOOP
            LEAY -1,Y
            PULS A,PC
; X = a string: -> D = its length. Keeps X.
STRLEN      PSHS X
            CLRD
SL_LOOP     TST  ,X+
            BEQ  SL_RET
            ADDD #1
            BRA  SL_LOOP
SL_RET      PULS X,PC
; Z set if the strings at X and Y are the same, ignoring case. Keeps X and Y.
STRCMPI     PSHS D,X,Y
CI_LOOP     LDA  ,Y+
            JSR  UPCASE
            TFR  A,B
            LDA  ,X+
            JSR  UPCASE
            PSHS B
            CMPA ,S+
            BNE  CI_RET
            TSTA
            BNE  CI_LOOP
CI_RET      PULS D,X,Y,PC
; Z set if the strings at X and Y are the same (case counts). Keeps X and Y.
STRCMP      PSHS A,X,Y
SE_LOOP     LDA  ,X+
            CMPA ,Y+
            BNE  SE_RET
            TSTA
            BNE  SE_LOOP
SE_RET      PULS A,X,Y,PC
UPCASE      CMPA #'a'
            BLO  UC_RET
            CMPA #'z'
            BHI  UC_RET
            SUBA #$20
UC_RET      RTS
LOWCASE     CMPA #'A'
            BLO  LC_RET
            CMPA #'Z'
            BHI  LC_RET
            ADDA #$20
LC_RET      RTS
; Carry clear if A is a space or a tab (C isspace, as far as source text goes).
ISSPACE     CMPA #' '
            BEQ  IS_YES
            CMPA #9
            BEQ  IS_YES
            CMPA #10
            BLO  IS_NO
            CMPA #14                   ; LF VT FF CR
            BLO  IS_YES
IS_NO       ORCC #1
            RTS
IS_YES      ANDCC #$FE
            RTS
; X: past spaces and tabs.
SKIPSP      PSHS A
SK_LOOP     LDA  ,X
            BEQ  SK_RET
            BSR  ISSPACE
            BCS  SK_RET
            LEAX 1,X
            BRA  SK_LOOP
SK_RET      PULS A,PC
; Carry clear if A may be in a symbol (lwasm's SYMCHARS: letters, digits, and
; _ @ $ . ?).
ISSYM       CMPA #'a'
            BLO  SY_1
            CMPA #'z'
            BLS  IS_YES
SY_1        CMPA #'A'
            BLO  SY_2
            CMPA #'Z'
            BLS  IS_YES
SY_2        CMPA #'0'
            BLO  SY_3
            CMPA #'9'
            BLS  IS_YES
SY_3        CMPA #'_'
            BEQ  IS_YES
            CMPA #'@'
            BEQ  IS_YES
            CMPA #'$'
            BEQ  IS_YES
            CMPA #'.'
            BEQ  IS_YES
            CMPA #'?'
            BEQ  IS_YES
            BRA  IS_NO
; Carry clear if A is a digit.
ISDIGIT     CMPA #'0'
            BLO  IS_NO
            CMPA #'9'
            BHI  IS_NO
            BRA  IS_YES
; Carry clear if A is a letter.
ISALPHA     CMPA #'A'
            BLO  IS_NO
            CMPA #'z'
            BHI  IS_NO
            CMPA #'Z'
            BLS  IS_YES
            CMPA #'a'
            BHS  IS_YES
            BRA  IS_NO
;------------------------------------------------------------------------------
; 32-bit arithmetic on MA and MB (big-endian, in the direct page area below):
; MUL32: MA = MA * MB (low 32 bits). DIV32: MA = MA / MB, MB = MA % MB, signed,
; truncating toward zero as C does.
;------------------------------------------------------------------------------
MUL32       PSHS D,X
            PSHSW
            LDQ  MA
            STQ  MQ
            CLRD
            CLRW
            STQ  MA                    ; the product
            LDX  #32
ML_LOOP     LDQ  MA                    ; product <<= 1
            ADDR W,W
            ROLD
            STQ  MA
            LDQ  MQ                    ; multiplier <<= 1, its top bit -> C
            ADDR W,W
            ROLD
            STQ  MQ
            BCC  ML_NEXT
            LDQ  MA
            ADDW MB+2
            ADCD MB
            STQ  MA
ML_NEXT     LEAX -1,X
            BNE  ML_LOOP
            PULSW
            PULS D,X,PC
DIV32       PSHS D,X
            PSHSW
            CLR  MSIGN
            TST  MA                    ; work on magnitudes
            BPL  DV_APOS
            LDX  #MA
            JSR  NEG32
            COM  MSIGN                 ; bit 0: the quotient's sign, bit 1: the
            LDA  MSIGN                 ; remainder's (the dividend's)
            ORA  #2
            STA  MSIGN
DV_APOS     TST  MB
            BPL  DV_BPOS
            LDX  #MB
            JSR  NEG32
            LDA  MSIGN
            EORA #1
            STA  MSIGN
DV_BPOS     CLRD                       ; MQ = the remainder so far
            CLRW
            STQ  MQ
            LDX  #32
DV_LOOP     LDQ  MA                    ; dividend <<= 1, its top bit into MQ
            ADDR W,W
            ROLD
            STQ  MA
            LDQ  MQ
            ROLW
            ROLD
            STQ  MQ
            LDQ  MQ                    ; does the divisor go?
            SUBW MB+2
            SBCD MB
            BCS  DV_NO
            STQ  MQ
            INC  MA+3                  ; the quotient bit (the low bit was 0)
DV_NO       LEAX -1,X
            BNE  DV_LOOP
            LDQ  MQ                    ; MB = remainder
            STQ  MB
            LDA  MSIGN
            BITA #1
            BEQ  DV_QOK
            LDX  #MA
            JSR  NEG32
DV_QOK      LDA  MSIGN
            BITA #2
            BEQ  DV_ROK
            LDX  #MB
            JSR  NEG32
DV_ROK      PULSW
            PULS D,X,PC
; X = a 32-bit number: negated in place.
NEG32       PSHS D
            PSHSW
            CLRD
            CLRW
            SUBW 2,X
            SBCD ,X
            STQ  ,X
            PULSW
            PULS D,PC
ZERO        FCB  0
;------------------------------------------------------------------------------
; End of pa_util.asm
;------------------------------------------------------------------------------
