;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 C library
;    FILE: rand.asm -- int rand(void) (0..RAND_MAX, 32767), void srand(unsigned seed)
;------------------------------------------------------------------------------
; A 16-bit xorshift (7, 9, 8): x ^= x << 7; x ^= x >> 9; x ^= x << 8. Its
; period is 65535; rand() is x's low 15 bits. srand(0) is srand(1).
            EXPORT _rand,_srand
            SECTION code
_rand       LDD  seed
            LDW  #7                    ; x ^= x << 7
            BSR  RN_SHL
            LSRA                       ; x ^= x >> 9: (A >> 1) into B
            TFR  A,B
            CLRA
            EORD seed
            STD  seed
            TFR  B,A                   ; x ^= x << 8
            CLRB
            EORD seed
            STD  seed
            ANDA #$7F
            RTS
; seed ^= seed << W -> D = the new seed.
RN_SHL      LSLD
            DECW
            BNE  RN_SHL
            EORD seed
            STD  seed
            RTS
_srand      LDD  2,S
            BNE  SR_SET
            INCB
SR_SET      STD  seed
            RTS
            ENDSECT
            SECTION data
seed        FDB  1
            ENDSECT
