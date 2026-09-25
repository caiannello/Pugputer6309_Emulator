* Directives, expressions, macros, structs, conditionals: compared with lwasm.
# a comment with a hash
        ORG     $2000
; ---- expressions
        FCB     1+2*3,(1+2)*3,10/3,-10/3,10%3,-10%3,7\2
        FCB     1&&0,1||0,2&&3,0||0,$F0&$3C,$F0|$0F,$F0!$0F,$FF^$0F
        FDB     -1,~0,^1,'A,"AB,'A','B','',"CD"
        FDB     &-5,%-101,$-10,@17,17q,17o,1011b,0FFh,12,0x1F,$1f
        FQB     $12345678,-2,100000*3,$7FFFFFFF+1
        FDB     4-2-1,2*3+4*5,100/10/2,1-(2-3)
        FDB     fwd1,fwd2,fwd1-fwd2,*,*+3,.
        FCB     'x'+1,"ab"&$FF
fwd2    EQU     fwd1+1
fwd1    EQU     $30
chain1  EQU     chain2*2
chain2  EQU     chain3+1
chain3  EQU     5
        FDB     chain1,chain2,chain3
; ---- SET
cnt     SET     1
        FCB     cnt
cnt     SET     cnt+1
        FCB     cnt
cnt     SET     cnt*10
        FCB     cnt
; ---- local labels
loop@   NOP
        BRA     loop@
lp?x    BRA     lp?x
a$b     BRA     a$b

loop@   NOP
        BRA     loop@
; ---- data
        FCC     /Hello, world/
        FCC     "quote/slash"
        FCC     'single'
        FCN     "with NUL"
        FCS     "high"
        FCC     "a string long enough to spill into several listing lines"
        RMB     3
        RMD     2
        RMQ     1
        ZMB     5
        ZMD     2
        ZMQ     1
        FILL    $AA,6
        ALIGN   16
        ALIGN   8,$55
        FCB     1
        ALIGN   4
; ---- conditionals
        IFEQ    0
        FCB     $01
        ELSE
        FCB     $02
        ENDC
        IFNE    0
        FCB     $03
        IFEQ    0
        FCB     $04
        ENDC
        ELSE
        FCB     $05
        ENDC
        IFGT    1
        FCB     $06
        ENDC
        IFGE    0
        FCB     $07
        ENDC
        IFLT    -1
        FCB     $08
        ENDC
        IFLE    1
        FCB     $09
        ENDC
        IF      2-2
        FCB     $0A
        ENDIF
        IFDEF   fwd1
        FCB     $0B
        ENDC
        IFDEF   nothere|fwd2
        FCB     $0C
        ENDC
        IFNDEF  nothere
        FCB     $0D
        ENDC
        IFDEF   later
        FCB     $0E
        ENDC
later   EQU     1
; ---- macros
twice   MACRO
        FCB     \1,\1
        ENDM
pair    MACRO   noexpand
\1lbl   FDB     \2,\3
        ENDM
all     MACRO
        FCB     \#,\*
        FCC     /\0/
        FCB     {1}+{2}
        ENDM
        twice   7
        pair    one,$1234,$5678
        all     1,2,3
        all     4\,5,6
        FDB     onelbl
nest    MACRO
        twice   \1
        IFEQ    \1-9
        FCB     $99
        ENDC
        ENDM
        nest    9
        nest    8
??twice FCB     $77
; ---- structs
pt      STRUCT
x       RMB     2
y       RMB     2
        RMB     1
        ENDSTRUCT
rect    STRUCT
tl      pt
br      pt
col     RMB     1
        ENDS
        FCB     sizeof{pt},sizeof{rect},rect.br,rect.br.y,rect.col,pt.____4
here    rect
        FDB     here.br.x,sizeof{here}
; ---- the direct page
        SETDP   $20
        LDA     $2010
        LDA     <$10
        LDA     *+5
        SETDP   0
        LDA     $10
; ---- odd line forms
100     LDA     #1
lab:    LDB     #2
  lab2: LDB     #3
equal   =       $44
        FCB     equal
	LDA	#1	tabs in the line
        END
