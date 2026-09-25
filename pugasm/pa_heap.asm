;------------------------------------------------------------------------------
; pa_heap.asm -- pugasm: the heap in banked RAM.
;
; Symbols, macros, structs and stored expressions are allocated from RAM pages
; (B_PAGE_ALLOC) that are mapped one at a time into bank 3, $C000-$EFFF (the
; ROM and I/O hide the rest of each 16KB page). A "far pointer" is 3 bytes: the
; page's index in PAGES (1 up; 0 = null) and the address in the window. Nothing
; is ever freed until the end, and nothing crosses a page.
;------------------------------------------------------------------------------
HEAPINIT    CLR  <NPAGES
            CLR  <HEAPPG
            CLR  <MAPPED               ; bank 3 holds its own page (3)
            RTS
; A = a page index (0 = the program's own page 3): maps it. Keeps every register.
MAPPG       CMPA <MAPPED
            BEQ  MP_RET
            PSHS D,X,Y,U
            PSHSW
            STA  <MAPPED
            LDE  #3
            TSTA
            BEQ  MP_SET
            LDX  #PAGES-1
            LDE  A,X
MP_SET      LDB  #3
            LDA  #B_BANK_SET
            SWI2
            PULSW
            PULS D,X,Y,U
MP_RET      RTS
; D = a size: -> A = page index, X = address of that many bytes (mapped).
HALLOC      PSHS D
            TST  <HEAPPG
            BEQ  HA_NEW
            LDD  <HEAPPTR
            ADDD ,S
            BCS  HA_NEW
            CMPD #WINEND
            BLS  HA_FITS
HA_NEW      LDA  <NPAGES
            CMPA #MAXPAGES
            BHS  HA_FULL
            LDA  #B_PAGE_ALLOC
            SWI2
            BCS  HA_FULL
            LDB  <NPAGES
            LDX  #PAGES
            ABX
            STA  ,X
            INC  <NPAGES
            LDA  <NPAGES
            STA  <HEAPPG
            LDD  #WINDOW
            STD  <HEAPPTR
HA_FITS     LDX  <HEAPPTR
            LDD  <HEAPPTR
            ADDD ,S++
            STD  <HEAPPTR
            LDA  <HEAPPG
            JMP  MAPPG
HA_FULL     LDX  #M_NOMEM
            JMP  FATAL
; FARP = a far pointer: maps its page, -> X = the address. Z set if it is null.
FARMAP      LDA  <FARP
            BEQ  FM_NULL
            JSR  MAPPG
            LDX  <FARP+1
            ANDCC #$FB
            RTS
FM_NULL     ORCC #4
            RTS
; Leaving: bank 3 back to its own page, the heap pages given back.
HEAPDONE    CLRA
            JSR  MAPPG
HD_LOOP     LDB  <NPAGES
            BEQ  HD_RET
            DEC  <NPAGES
            LDX  #PAGES-1
            ABX
            LDB  ,X
            LDA  #B_PAGE_FREE
            SWI2
            BRA  HD_LOOP
HD_RET      RTS
;------------------------------------------------------------------------------
; End of pa_heap.asm
;------------------------------------------------------------------------------
