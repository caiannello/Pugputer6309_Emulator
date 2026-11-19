;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 C library
;    FILE: malloc.asm -- malloc(), free(), calloc(), realloc(), sbrk()
;
; The heap grows from the end of the program (CRT0's __brk) towards the stack;
; sbrk keeps MARGIN bytes free below where the stack is when it's called.
; A block is a 2-byte header (its whole size, even, at least 4) and then what
; the program gets. Free blocks are in a list in address order, each with the
; next one's address after its size; malloc takes the first that is big enough
; (splitting it if enough is left over), and free puts a block back in its
; place, joining it to the free blocks just before and after it.
;------------------------------------------------------------------------------
MARGIN      equ  512
BK_SIZE     equ  0
BK_NEXT     equ  2
            EXPORT _malloc,_free,_calloc,_realloc,_sbrk
            IMPORT __brk
            SECTION code
;------------------------------------------------------------------------------
; void *sbrk(int n): the heap grown by n bytes -> where they start; (void *)-1
; if there isn't room.
_sbrk       LDD  __brk
            ADDD 2,S
            BCS  SB_FAIL
            PSHS D
            TFR  S,D
            SUBD #MARGIN
            BCS  SB_FAIL2
            CMPD ,S
            BLO  SB_FAIL2
            PULS D
            LDX  __brk
            STD  __brk
            TFR  X,D
            RTS
SB_FAIL2    LEAS 2,S
SB_FAIL     LDD  #-1
            RTS
;------------------------------------------------------------------------------
; void *malloc(size_t n) -> the space, or NULL.
_malloc     LDD  2,S
            ADDD #3                    ; the header, and even
            BCS  MA_NONE
            ANDB #$FE
            CMPD #4
            BHS  MA_SIZE
            LDD  #4
MA_SIZE     STD  need
            LDX  #flist-BK_NEXT        ; X: the block before (flist, as if a
MA_LOOP     STX  prev                  ; block's next)
            LDX  BK_NEXT,X
            BEQ  MA_GROW
            LDD  BK_SIZE,X
            CMPD need
            BHS  MA_FIT
            BRA  MA_LOOP
MA_FIT      SUBD need                  ; what is left over
            CMPD #4
            BLO  MA_WHOLE
            STD  blk                   ; split: the rest, at X + need, a free
            LDW  BK_NEXT,X             ; block in X's place in the list
            PSHS X
            LDD  need
            LEAX D,X
            LDD  blk
            STD  BK_SIZE,X
            STW  BK_NEXT,X
            TFR  X,D
            LDX  prev
            STD  BK_NEXT,X
            PULS X
            LDD  need
            STD  BK_SIZE,X
            BRA  MA_GIVE
MA_WHOLE    LDD  BK_NEXT,X             ; the whole block: out of the list
            PSHS X
            LDX  prev
            STD  BK_NEXT,X
            PULS X
MA_GIVE     LEAX 2,X
            TFR  X,D
            RTS
MA_GROW     LDD  need                  ; none: a new block from sbrk
            PSHS D
            JSR  _sbrk
            LEAS 2,S
            CMPD #-1
            BEQ  MA_NONE
            TFR  D,X
            LDD  need
            STD  BK_SIZE,X
            BRA  MA_GIVE
MA_NONE     CLRD
            RTS
;------------------------------------------------------------------------------
; void free(void *p): p from malloc (or NULL: nothing).
_free       LDD  2,S
            BEQ  FR_RET
            PSHS U
            SUBD #2
            STD  blk
            LDX  #flist-BK_NEXT        ; the free block before it, X
FR_FIND     LDD  BK_NEXT,X
            BEQ  FR_HERE
            CMPD blk
            BHI  FR_HERE
            TFR  D,X
            BRA  FR_FIND
FR_HERE     STX  prev                  ; in the list between prev and D
            LDX  blk
            STD  BK_NEXT,X
            LDX  prev
            LDD  blk
            STD  BK_NEXT,X
            LDX  blk                   ; joined to the next, if they touch
            BSR  FR_JOIN
            LDX  prev                  ; and the one before to it
            CMPX #flist-BK_NEXT
            BEQ  FR_DONE
            BSR  FR_JOIN
FR_DONE     PULS U,PC
FR_JOIN     LDD  BK_SIZE,X             ; X and the block after it, if they
            LEAU D,X                   ; touch: one block (U kept)
            CMPU BK_NEXT,X
            BNE  FR_NOJOIN
            ADDD BK_SIZE,U
            STD  BK_SIZE,X
            LDD  BK_NEXT,U
            STD  BK_NEXT,X
FR_NOJOIN   RTS
FR_RET      RTS
;------------------------------------------------------------------------------
; void *calloc(size_t n, size_t size): malloc'd and cleared (NULL if n * size
; doesn't fit in 16 bits).
_calloc     LDD  2,S
            MULD 4,S
            CMPD #0                    ; (MULD's Z is only for D)
            BNE  CA_NONE
            TSTW
            BMI  CA_NONE               ; (MULD is signed: keep below 32K)
            PSHSW
            JSR  _malloc
            PULSW
            CMPD #0
            BEQ  CA_RET
            PSHS D,Y
            TFR  D,Y
            LDX  #zero
            TFM  X,Y+
            PULS D,Y,PC
CA_NONE     CLRD
CA_RET      RTS
;------------------------------------------------------------------------------
; void *realloc(void *p, size_t n): p's space made n bytes (moved, perhaps)
; -> where it is, or NULL (p left alone). NULL p: malloc(n); n of 0: free(p).
_realloc    LDD  2,S
            BNE  RA_HAVE
            LDD  4,S
            PSHS D
            JSR  _malloc
            LEAS 2,S
            RTS
RA_HAVE     LDD  4,S
            BNE  RA_SIZE
            LDD  2,S
            PSHS D
            JSR  _free
            LEAS 2,S
            CLRD
            RTS
RA_SIZE     LDX  2,S                   ; big enough already: as it is
            LDD  -2,X
            SUBD #2
            CMPD 4,S
            BHS  RA_SAME
            PSHS D                     ; (its size, then the new space)
            LDD  6,S
            PSHS D
            JSR  _malloc
            LEAS 2,S
            CMPD #0
            BEQ  RA_FAIL
            PSHS D,Y                   ; copied, and the old one freed
            TFR  D,Y
            LDX  8,S
            LDW  4,S
            TFM  X+,Y+
            LDD  8,S
            PSHS D
            JSR  _free
            LEAS 2,S
            PULS D,Y
            LEAS 2,S
            RTS
RA_FAIL     LEAS 2,S
            CLRD
            RTS
RA_SAME     TFR  X,D
            RTS
zero        FCB  0
            ENDSECT
;------------------------------------------------------------------------------
            SECTION bss
flist       RMB  2                     ; the first free block
need        RMB  2
prev        RMB  2
blk         RMB  2
            ENDSECT
;------------------------------------------------------------------------------
; End of malloc.asm
;------------------------------------------------------------------------------
