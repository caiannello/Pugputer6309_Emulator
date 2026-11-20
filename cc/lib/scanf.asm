;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 C library
;    FILE: scanf.asm -- scanf(), fscanf(), sscanf(), vscanf(), vfscanf(),
;          vsscanf()
;
; The format: white space matches any amount of it in the input (none too);
; an ordinary character matches itself; a conversion is %[*][width][h|hh|l]
; and one of:
;   d i u o x X p   an integer (an optional sign; i: 0x... hex, 0... octal,
;                   else decimal; x: an optional 0x). Stored as an int (h too),
;                   a char (hh), a long (l)
;   c               width characters (1 if none given), as they are: no NUL
;   s               characters up to white space, and a NUL
;   [set] [^set]    characters in the set (or not in it: ^), and a NUL. A ]
;                   first is in the set, and a-z is a range
;   e f g E F G     a float (a double, with l: the same), through __sfhook
;                   (fltio.asm's, linked when the program uses floats with
;                   "..."): without it, the conversion fails
;   n               how many characters have been read so far (nothing read)
;   %               a %
; Every conversion but c, [ and n skips white space first. * reads but stores
; nothing. -> how many were stored; EOF if the input ended before the first.
; The character that ends a conversion is put back (ungetc), so it's the
; next one read, by this or by anything after it.
;------------------------------------------------------------------------------
    INCLUDE defines.d
    INCLUDE libc.d
FBUFSZ      equ  40
            EXPORT _scanf,_fscanf,_sscanf,_vscanf,_vfscanf,_vsscanf
            IMPORT __iob,__getc,__sfhook
            SECTION code
;------------------------------------------------------------------------------
; int scanf(const char *fmt, ...), int vscanf(const char *fmt, va_list ap)
_scanf      PSHS Y,U                   ; (6 fmt, 8 the arguments)
            LEAY 8,S
            BRA  SC_STDIN
_vscanf     PSHS Y,U                   ; (6 fmt, 8 ap)
            LDY  8,S
SC_STDIN    LDX  #__iob
            STX  sfile
            LDX  6,S
            BRA  SC_GO
; int fscanf(FILE *f, const char *fmt, ...), int vfscanf(FILE *f, const char
; *fmt, va_list ap)
_fscanf     PSHS Y,U                   ; (6 f, 8 fmt, 10 the arguments)
            LEAY 10,S
            BRA  SC_FILE
_vfscanf    PSHS Y,U                   ; (6 f, 8 fmt, 10 ap)
            LDY  10,S
SC_FILE     LDX  6,S
            STX  sfile
            LDX  8,S
            BRA  SC_GO
; int sscanf(const char *s, const char *fmt, ...), int vsscanf(const char *s,
; const char *fmt, va_list ap)
_sscanf     PSHS Y,U                   ; (6 s, 8 fmt, 10 the arguments)
            LEAY 10,S
            BRA  SC_STR
_vsscanf    PSHS Y,U                   ; (6 s, 8 fmt, 10 ap)
            LDY  10,S
SC_STR      LDX  6,S
            STX  sstr
            CLRD
            STD  sfile
            LDX  8,S
SC_GO       BSR  DOSCAN
            PULS Y,U,PC
;------------------------------------------------------------------------------
; X = the format, Y = the arguments -> D = how many were stored (or EOF).
DOSCAN      STX  sfmt
            CLRD
            STD  nassign
            STD  nread
            CLR  seof
SC_LOOP     LDX  sfmt
            LDB  ,X+
            STX  sfmt
            TSTB
            LBEQ SC_END
            JSR  ISSP
            BCS  SC_NOTSP
            JSR  SKIPWS                ; white space: any amount
            BRA  SC_LOOP
SC_NOTSP    CMPB #'%'
            BEQ  SC_CONV
SC_LIT      PSHS B                     ; a character: itself next
            JSR  GETCH
            BCS  SC_LEOF
            CMPB ,S+
            BEQ  SC_LOOP
            JSR  UNGETCH
            LBRA SC_END
SC_LEOF     LEAS 1,S
            LBRA SC_END
SC_CONV     CLR  ssup                  ; %[*][width][h|hh|l]type
            CLR  slen
            CLRD
            STD  swidth
            LDX  sfmt
            LDB  ,X+
            CMPB #'*'
            BNE  SC_WDIG
            INC  ssup
            LDB  ,X+
SC_WDIG     SUBB #'0'                  ; the width
            CMPB #9
            BHI  SC_WEND
            PSHS B
            LDD  swidth
            LSLD
            PSHS D
            LSLD
            LSLD
            ADDD ,S++
            ADDB ,S+
            ADCA #0
            STD  swidth
            LDB  ,X+
            BRA  SC_WDIG
SC_WEND     ADDB #'0'
            CMPB #'h'                  ; h (an int, as it is), hh (a char)
            BNE  SC_LL
            LDB  ,X+
            CMPB #'h'
            BNE  SC_TYPE
            LDA  #1
            STA  slen
            LDB  ,X+
            BRA  SC_TYPE
SC_LL       CMPB #'l'                  ; l, L: a long (or a double)
            BEQ  SC_LONG
            CMPB #'L'
            BNE  SC_TYPE
SC_LONG     LDA  #2
            STA  slen
            LDB  ,X+
SC_TYPE     STX  sfmt
            LDX  swidth                ; (no width: as many as there are)
            BNE  SC_HASW
            LDX  #$7FFF
            CMPB #'c'
            BNE  SC_SETW
            LDX  #1                    ; (%c: one)
SC_SETW     STX  swidth
SC_HASW     CMPB #'%'
            BNE  SC_N
            JSR  SKIPWS
            LDB  #'%'
            LBRA SC_LIT
SC_N        CMPB #'n'
            LBEQ SC_COUNT
            CMPB #'c'
            LBEQ SC_CHARS
            CMPB #'s'
            LBEQ SC_WORD
            CMPB #'['
            LBEQ SC_SET
            LDA  #10
            CMPB #'d'
            LBEQ SC_INT
            CMPB #'u'
            LBEQ SC_INT
            CLRA
            CMPB #'i'
            LBEQ SC_INT
            LDA  #8
            CMPB #'o'
            LBEQ SC_INT
            LDA  #16
            CMPB #'x'
            LBEQ SC_INT
            CMPB #'X'
            LBEQ SC_INT
            CMPB #'p'
            LBEQ SC_INT
            ORB  #$20
            CMPB #'e'
            LBEQ SC_FLT
            CMPB #'f'
            LBEQ SC_FLT
            CMPB #'g'
            LBEQ SC_FLT
SC_END      LDD  nassign               ; the end: how many, or EOF if the
            BNE  SC_RET                ; input ran out first
            TST  seof
            BEQ  SC_RET
            LDD  #EOF
SC_RET      RTS
; A conversion done: counted if it was stored.
SC_DONE     TST  ssup
            LBNE SC_LOOP
            LDD  nassign
            ADDD #1
            STD  nassign
            LBRA SC_LOOP
; U = where the next argument points (0 with *).
SC_PTR      LDU  #0
            TST  ssup
            BNE  SP_RET
            LDU  ,Y++
SP_RET      RTS
;------------------------------------------------------------------------------
; %n: how many characters so far.
SC_COUNT    BSR  SC_PTR
            CMPU #0
            LBEQ SC_LOOP
            LDD  nread
            TST  slen
            BEQ  SN_INT
            LDA  slen
            CMPA #1
            BEQ  SN_CHAR
            CLRA                       ; (a long)
            CLRB
            STD  ,U++
            LDD  nread
SN_INT      STD  ,U
            LBRA SC_LOOP
SN_CHAR     STB  ,U
            LBRA SC_LOOP
; %c: width characters, as they are.
SC_CHARS    BSR  SC_PTR
            CLRD
            STD  scount
SC_CLOOP    JSR  NEXTW
            BCS  SC_CEND
            JSR  PUTU
            BRA  SC_CLOOP
SC_CEND     LDD  scount
            LBEQ SC_END
            BRA  SC_DONE
; %s: up to white space, and a NUL.
SC_WORD     JSR  SKIPWS
            LBCS SC_END
            BSR  SC_PTR
            CLRD
            STD  scount
SC_WLOOP    JSR  NEXTW
            BCS  SC_WEND2
            JSR  ISSP
            BCC  SC_WBACK
            JSR  PUTU
            BRA  SC_WLOOP
SC_WBACK    JSR  UNGETCH
SC_WEND2    LDD  scount
            LBEQ SC_END
            CLRB
            JSR  PUTNUL
            LBRA SC_DONE
; %[set]: the characters in the set (or, with ^, not in it), and a NUL.
SC_SET      LDX  #sset                 ; the set: 256 bits
            CLRB
SS_CLR      CLR  ,X+
            DECB
            CMPB #$E0
            BNE  SS_CLR
            CLR  ssetneg
            LDX  sfmt
            LDB  ,X
            CMPB #'^'
            BNE  SS_FIRST
            INC  ssetneg
            LEAX 1,X
            LDB  ,X
SS_FIRST    CMPB #']'                  ; (a ] first is in it)
            BNE  SS_LOOP
            JSR  SETBIT
            LEAX 1,X
SS_LOOP     LDB  ,X+
            BEQ  SS_ENDF               ; (no ]: the format ends)
            CMPB #']'
            BEQ  SS_END
            LDA  ,X                    ; a-z: a range
            CMPA #'-'
            BNE  SS_ONE
            LDA  1,X
            BEQ  SS_ONE
            CMPA #']'
            BEQ  SS_ONE
            LEAX 2,X
SS_RANGE    JSR  SETBIT
            PSHS A
            CMPB ,S+
            BHS  SS_LOOP
            INCB
            BRA  SS_RANGE
SS_ONE      JSR  SETBIT
            BRA  SS_LOOP
SS_ENDF     LEAX -1,X
SS_END      STX  sfmt
            JSR  SC_PTR
            CLRD
            STD  scount
SS_READ     JSR  NEXTW
            BCS  SS_DONE
            JSR  TESTBIT
            BCS  SS_BACK
            JSR  PUTU
            BRA  SS_READ
SS_BACK     JSR  UNGETCH
SS_DONE     LDD  scount
            LBEQ SC_END
            CLRB
            JSR  PUTNUL
            LBRA SC_DONE
; B = a character: its bit in the set.
SETBIT      PSHS D,X
            JSR  BITOF
            ORA  ,X
            STA  ,X
            PULS D,X,PC
; B = a character: carry clear if it's taken (in the set, or not, with ^).
TESTBIT     PSHS D,X
            JSR  BITOF
            ANDA ,X
            BEQ  TB_OUT
            TST  ssetneg
            BNE  TB_NO
TB_YES      ANDCC #$FE
            PULS D,X,PC
TB_OUT      TST  ssetneg
            BNE  TB_YES
TB_NO       ORCC #1
            PULS D,X,PC
BITOF       PSHS B                     ; B -> X = its byte, A = its bit
            LSRB
            LSRB
            LSRB
            LDX  #sset
            ABX
            PULS B
            ANDB #7
            LDA  #1
BO_SHIFT    DECB
            BMI  BO_RET
            LSLA
            BRA  BO_SHIFT
BO_RET      RTS
; B = a character: stored at U (if U isn't 0), counted.
PUTU        CMPU #0
            BEQ  PU_COUNT
            STB  ,U+
PU_COUNT    PSHS D
            LDD  scount
            ADDD #1
            STD  scount
            PULS D,PC
PUTNUL      CMPU #0
            BEQ  PN_RET
            STB  ,U
PN_RET      RTS
;------------------------------------------------------------------------------
; Integers: A = the base (0: as the number says).
SC_INT      STA  sbase
            JSR  SKIPWS
            LBCS SC_END
            CLR  sneg
            CLR  sany
            CLRD
            STD  sval
            STD  sval+2
            JSR  NEXTW
            LBCS SC_IEND
            CMPB #'-'
            BNE  SC_IPLUS
            INC  sneg
            BRA  SC_ISIGN
SC_IPLUS    CMPB #'+'
            BNE  SC_IPFX
SC_ISIGN    JSR  NEXTW
            LBCS SC_IEND
SC_IPFX     LDA  sbase                 ; 0, 0x: what base (i), or skipped (x)
            BEQ  SC_I0
            CMPA #16
            BNE  SC_IDIG
SC_I0       CMPB #'0'
            BNE  SC_I10
            LDA  #1
            STA  sany
            JSR  NEXTW
            BCS  SC_IEND
            PSHS B
            ORB  #$20
            CMPB #'x'
            PULS B
            BNE  SC_I8
            LDA  #16
            STA  sbase
            JSR  NEXTW
            BCS  SC_IEND
            BRA  SC_IDIG
SC_I8       TST  sbase
            BNE  SC_IDIG
            LDA  #8
            STA  sbase
            BRA  SC_IDIG
SC_I10      TST  sbase
            BNE  SC_IDIG
            LDA  #10
            STA  sbase
SC_IDIG     JSR  DIGVAL                ; the digits
            CMPA sbase
            BHS  SC_INOT
            STA  sdigit
            JSR  MULBASE
            CLRA
            LDB  sdigit
            STD  stmp2
            LDQ  sval
            ADDW stmp2
            ADCD #0
            STQ  sval
            LDA  #1
            STA  sany
            JSR  NEXTW
            BCS  SC_IEND
            BRA  SC_IDIG
SC_INOT     JSR  UNGETCH
SC_IEND     TST  sany
            LBEQ SC_END
            LDQ  sval
            TST  sneg
            BEQ  SC_ISTORE
            COMD
            COMW
            ADDW #1
            ADCD #0
SC_ISTORE   JSR  SC_PTR
            CMPU #0
            LBEQ SC_DONE
            TST  slen
            BEQ  SC_IWORD
            PSHS A
            LDA  slen
            CMPA #1
            PULS A
            BEQ  SC_IBYTE
            STQ  ,U                    ; (l: a long)
            LBRA SC_DONE
SC_IWORD    STW  ,U
            LBRA SC_DONE
SC_IBYTE    STF  ,U
            LBRA SC_DONE
; B = a character -> A = its value as a digit (to 15), or $FF.
DIGVAL      TFR  B,A
            SUBA #'0'
            CMPA #9
            BLS  DV_RET
            TFR  B,A
            ORA  #$20
            SUBA #'a'
            CMPA #5
            BHI  DV_NO
            ADDA #10
DV_RET      RTS
DV_NO       LDA  #$FF
            RTS
; sval = sval * sbase (8, 10 or 16).
MULBASE     LDB  sbase
            CMPB #10
            BEQ  MB_TEN
            CMPB #8                    ; (8: 3 places, 16: 4)
            BNE  MB_16
            LDB  #3
            BRA  MB_N
MB_16       LDB  #4
MB_N        STB  sshift
            LDQ  sval
MB_SHIFT    ADDR W,W
            ROLD
            DEC  sshift
            BNE  MB_SHIFT
            STQ  sval
            RTS
MB_TEN      LDQ  sval
            ADDR W,W
            ROLD
            STQ  stmp
            ADDR W,W
            ROLD
            ADDR W,W
            ROLD
            ADDW stmp+2
            ADCD stmp
            STQ  sval
            RTS
;------------------------------------------------------------------------------
; Floats: the characters a float's made of (a sign; digits with a point; an
; e, a sign, digits) into fbuf, then __sfhook's routine makes it.
SC_FLT      JSR  SKIPWS
            LBCS SC_END
            LDX  #fbuf
            STX  sbp
            CLR  fdigs
            CLR  fpt
            CLR  fexp
            LDA  #1
            STA  fsgn                  ; (a sign may come here)
SF_LOOP     JSR  NEXTW
            BCS  SF_END
            LDX  sbp
            CMPX #fbuf+FBUFSZ
            BHS  SF_BACK
            CMPB #'+'
            BEQ  SF_SIGN
            CMPB #'-'
            BNE  SF_DIGIT
SF_SIGN     TST  fsgn
            BEQ  SF_BACK
            CLR  fsgn
            BRA  SF_TAKE
SF_DIGIT    CLR  fsgn
            CMPB #'0'
            BLO  SF_POINT
            CMPB #'9'
            BHI  SF_POINT
            TST  fexp
            BNE  SF_TAKE
            INC  fdigs
            BRA  SF_TAKE
SF_POINT    CMPB #'.'
            BNE  SF_E
            TST  fpt
            BNE  SF_BACK
            TST  fexp
            BNE  SF_BACK
            INC  fpt
            BRA  SF_TAKE
SF_E        PSHS B
            ORB  #$20
            CMPB #'e'
            PULS B
            BNE  SF_BACK
            TST  fdigs
            BEQ  SF_BACK
            TST  fexp
            BNE  SF_BACK
            INC  fexp
            INC  fsgn
SF_TAKE     STB  ,X+
            STX  sbp
            BRA  SF_LOOP
SF_BACK     JSR  UNGETCH
SF_END      LDX  sbp
            CLR  ,X
            TST  fdigs
            LBEQ SC_END
            LDX  __sfhook              ; (no float conversions linked: no)
            LBEQ SC_END
            PSHS X
            LDX  #fbuf
            JSR  [,S++]
            PSHS D
            JSR  SC_PTR
            PULS D
            CMPU #0
            LBEQ SC_DONE
            STQ  ,U
            LBRA SC_DONE
;------------------------------------------------------------------------------
; The input.
;------------------------------------------------------------------------------
; -> B = the next character (D 0..255); carry set (and seof) at the end.
GETCH       LDX  sfile
            BEQ  GC_STR
            JSR  __getc
            BCS  GC_EOF
            BRA  GC_GOT
GC_STR      LDX  sstr
            LDB  ,X
            BEQ  GC_EOF
            LEAX 1,X
            STX  sstr
            CLRA
GC_GOT      PSHS D
            LDD  nread
            ADDD #1
            STD  nread
            PULS D
            ANDCC #$FE
            RTS
GC_EOF      LDA  #1
            STA  seof
            LDD  #EOF
            ORCC #1
            RTS
; The next character, if the width allows another (carry set if it doesn't,
; or at the end).
NEXTW       LDX  swidth
            BEQ  NW_NONE
            LEAX -1,X
            STX  swidth
            BRA  GETCH
NW_NONE     ORCC #1
            RTS
; B = the character just read: put back, to be read again.
UNGETCH     PSHS D
            LDD  nread
            SUBD #1
            STD  nread
            LDX  sfile
            BEQ  UG_STR
            LDB  1,S
            STB  FL_UNGOT,X
            LDA  FL_FLAGS,X
            ORA  #FF_UNGOT
            ANDA #~FF_EOF
            STA  FL_FLAGS,X
            PULS D,PC
UG_STR      LDX  sstr
            LEAX -1,X
            STX  sstr
            PULS D,PC
; White space skipped (the first character after it put back). Carry set if
; the input ended.
SKIPWS      BSR  GETCH
            BCS  SW_RET
            BSR  ISSP
            BCC  SKIPWS
            BSR  UNGETCH
            ANDCC #$FE
SW_RET      RTS
; Carry clear if B is white space (' ', \t \n \v \f \r).
ISSP        CMPB #' '
            BEQ  IS_YES
            CMPB #9
            BLO  IS_NO
            CMPB #13
            BHI  IS_NO
IS_YES      ANDCC #$FE
            RTS
IS_NO       ORCC #1
            RTS
            ENDSECT
;------------------------------------------------------------------------------
            SECTION bss
sfile       RMB  2                     ; the input: a FILE, or (0) ...
sstr        RMB  2                     ; ... a string
sfmt        RMB  2
nassign     RMB  2
nread       RMB  2
swidth      RMB  2
scount      RMB  2
sval        RMB  4
stmp        RMB  4
stmp2       RMB  2
sbp         RMB  2
seof        RMB  1
ssup        RMB  1                     ; *
slen        RMB  1                     ; 0 int, 1 char (hh), 2 long (l)
sbase       RMB  1
sneg        RMB  1
sany        RMB  1
sdigit      RMB  1
sshift      RMB  1
ssetneg     RMB  1
fdigs       RMB  1
fpt         RMB  1
fexp        RMB  1
fsgn        RMB  1
sset        RMB  32
fbuf        RMB  FBUFSZ+1
            ENDSECT
;------------------------------------------------------------------------------
; End of scanf.asm
;------------------------------------------------------------------------------
