;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 C library
;    FILE: strtod.asm -- double strtod(const char *s, char **end),
;          double atof(const char *s)
;
; Spaces, a sign, digits (with a point among them, or not), an exponent (e or
; E, a sign, digits); or inf, infinity or nan, in any case. *end (if end isn't
; NULL) = just past what was taken, or s if there was no number (then 0). The
; digits are worked out as fpcore's __fdec2f does them (CC1 reads constants
; the same way): the first nine significant ones exactly, the rest as zeros.
;
; __sfloat: X = a string -> Q = its number, X = just past it (as it was if
; there's none). Keeps Y and U. scanf's %e %f %g use it, through __sfhook.
;------------------------------------------------------------------------------
    INCLUDE defines.d
    INCLUDE libc.d
            EXPORT _strtod,_atof,__sfloat
            IMPORT __fdec2f
            SECTION code
_strtod     PSHS Y
            LDX  4,S
            BSR  __sfloat
            LDY  6,S
            BEQ  SD_RET
            STX  ,Y
SD_RET      PULS Y,PC
_atof       LDX  2,S
__sfloat    PSHS Y,U
            STX  sstart
SF_SPACE    LDA  ,X+                   ; spaces: ' ' and \t \n \v \f \r
            CMPA #' '
            BEQ  SF_SPACE
            CMPA #9
            BLO  SF_SIGN
            CMPA #13
            BLS  SF_SPACE
SF_SIGN     LEAX -1,X
            CLR  sneg
            CMPA #'-'
            BNE  SF_PLUS
            INC  sneg
            BRA  SF_SKIP
SF_PLUS     CMPA #'+'
            BNE  SF_WORD
SF_SKIP     LEAX 1,X
SF_WORD     LDY  #w_inf                ; inf, infinity, nan
            JSR  SMATCH
            BCS  SF_NAN
            LDY  #w_inity
            JSR  SMATCH
            LDD  #$7F80
            BRA  SF_SPEC
SF_NAN      LDY  #w_nan
            JSR  SMATCH
            BCS  SF_NUM
            LDD  #$7FC0
SF_SPEC     CLRW
            LBRA SF_SIGNED
SF_NUM      CLRD                       ; the digits -> sm (and se)
            STD  sm
            STD  sm+2
            STD  se
            CLR  sdigs
            CLR  safter
SF_DIG      LDA  ,X
            CMPA #'.'
            BNE  SF_D1
            TST  safter
            BNE  SF_DEND
            INC  safter
            LEAX 1,X
            BRA  SF_DIG
SF_D1       SUBA #'0'
            CMPA #9
            BHI  SF_DEND
            LDB  #1                    ; (there was a digit)
            STB  sdigs
            JSR  SDIGIT
            LEAX 1,X
            BRA  SF_DIG
SF_DEND     TST  sdigs
            BEQ  SF_NONE
            LDA  ,X                    ; an exponent (Y: in case it isn't one)
            ORA  #$20
            CMPA #'e'
            BNE  SF_MAKE
            LEAY 1,X
            CLR  sxneg
            LDA  ,Y
            CMPA #'-'
            BNE  SF_XPLUS
            INC  sxneg
            BRA  SF_XSKIP
SF_XPLUS    CMPA #'+'
            BNE  SF_XFIRST
SF_XSKIP    LEAY 1,Y
SF_XFIRST   LDA  ,Y
            SUBA #'0'
            CMPA #9
            BHI  SF_MAKE               ; (no digits: the e isn't part of it)
            CLRD
            STD  sx
SF_XDIG     LDB  ,Y
            SUBB #'0'
            CMPB #9
            BHI  SF_XEND
            LEAY 1,Y
            CLRA
            PSHS D
            LDD  sx                    ; (it stops growing at 1000)
            CMPD #1000
            BHS  SF_XSKIP2
            LSLD
            PSHS D
            LSLD
            LSLD
            ADDD ,S++
            ADDD ,S
            STD  sx
SF_XSKIP2   LEAS 2,S
            BRA  SF_XDIG
SF_XEND     TFR  Y,X
            LDD  sx
            TST  sxneg
            BEQ  SF_XADD
            NEGD
SF_XADD     ADDD se
            STD  se
SF_MAKE     PSHS X
            LDQ  sm
            LDX  se
            JSR  __fdec2f
            PULS X
SF_SIGNED   TST  sneg
            BEQ  SF_RET
            EORA #$80
SF_RET      PULS Y,U,PC
SF_NONE     LDX  sstart                ; no number: 0, and nothing taken
            CLRD
            CLRW
            PULS Y,U,PC
; Y = a word (lower case): carry clear, and X past it, if the string at X
; begins with it (in any case).
SMATCH      PSHS X
SM_LOOP     LDA  ,Y+
            BEQ  SM_YES
            LDB  ,X+
            ORB  #$20
            PSHS A
            CMPB ,S+
            BEQ  SM_LOOP
            PULS X
            ORCC #1
            RTS
SM_YES      LEAS 2,S
            ANDCC #$FE
            RTS
; A = a digit: sm = sm * 10 + it while there's room (se one less after the
; point); when there isn't, it's dropped (se one more before the point).
SDIGIT      TFR  A,B
            CLRA
            STD  sd
            LDD  sm
            CMPD #$17D7                ; (400000000)
            BLO  SG_ADD
            BHI  SG_DROP
            LDD  sm+2
            CMPD #$8400
            BHS  SG_DROP
SG_ADD      LDQ  sm
            ADDR W,W
            ROLD
            STQ  sm2
            ADDR W,W
            ROLD
            ADDR W,W
            ROLD
            ADDW sm2+2
            ADCD sm2
            ADDW sd
            ADCD #0
            STQ  sm
            TST  safter
            BEQ  SG_RET
            LDD  se
            SUBD #1
            STD  se
SG_RET      RTS
SG_DROP     TST  safter
            BNE  SG_RET
            LDD  se
            ADDD #1
            STD  se
            RTS
w_inf       FCN  "inf"
w_inity     FCN  "inity"
w_nan       FCN  "nan"
            ENDSECT
;------------------------------------------------------------------------------
            SECTION bss
sstart      RMB  2
sm          RMB  4                     ; the digits
sm2         RMB  4
se          RMB  2                     ; times 10 to this
sx          RMB  2                     ; the exponent part
sd          RMB  2
sneg        RMB  1
sxneg       RMB  1
sdigs       RMB  1
safter      RMB  1                     ; past the point
            ENDSECT
;------------------------------------------------------------------------------
; End of strtod.asm
;------------------------------------------------------------------------------
