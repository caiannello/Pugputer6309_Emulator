* relocatable expressions: sums, differences, multiples
    SECT code
A1  FCB 1,2,3
A2
X1  EQU  A2+(-1*A1)
X2  EQU  0-A1
X3  EQU  A1-A1
X4  EQU  A2-A2
X5  EQU  A1-0
X6  EQU  (A2)-(A1)
X7  EQU  A2+-A1
    ENDSECT
