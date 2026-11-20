;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 C library
;    FILE: pugbank.asm -- <pug/bank.h>: data in banked RAM
;
; A far address is a page (from page_alloc) and an offset in it, 0 to $3FFF.
; far_read/far_write copy between it and ordinary (near) memory through
; B_PAGE_COPY, whatever the banks show, so no mapping changes. A near range
; may cross banks; a far one must stay in its page.
;
;   int page_alloc(void)               a free page, or -1
;   void page_free(int page)
;   int bank_get(int bank)             the page mapped in bank 0..3
;   int bank_map(int bank, int page)   page into bank 1..3 -> the page that was
;                                      there, or -1 (not the stack's bank)
;   int far_read(void *dst, int page, unsigned off, unsigned n)    0, or -1
;   int far_write(int page, unsigned off, const void *src, unsigned n)
;   int far_peek(int page, unsigned off)                the byte (0..255)
;   void far_poke(int page, unsigned off, int value)
;------------------------------------------------------------------------------
            INCLUDE defines.d
            EXPORT _page_alloc,_page_free,_bank_get,_bank_map
            EXPORT _far_read,_far_write,_far_peek,_far_poke
            SECTION code
_page_alloc LDA  #B_PAGE_ALLOC
            SWI2
            BCS  PB_FAIL
PB_A        TFR  A,B
            CLRA
            RTS
PB_FAIL     LDD  #-1
            RTS
_page_free  LDB  3,S
            LDA  #B_PAGE_FREE
            SWI2
            RTS
_bank_get   LDB  3,S
            LDA  #B_BANK_GET
            SWI2
            BRA  PB_A
_bank_map   LDB  3,S
            LDA  #B_BANK_GET
            SWI2
            BCS  PB_FAIL
            PSHS A                     ; (the page that was there)
            LDB  4,S
            LDE  6,S
            LDA  #B_BANK_SET
            SWI2
            PULS B
            BCS  PB_FAIL
            CLRA
            RTS
;------------------------------------------------------------------------------
; The frame: ,S near, 2,S far offset, 4,S left, 6,S far page, 7,S direction (1:
; to near), 8,S the near part's page; 9,S Y, 11,S U, 13,S the return, 15,S on
; the arguments.
_far_read   PSHS Y,U
            LEAS -9,S
            LDD  15,S                  ; (dst, page, off, n)
            STD  ,S
            LDA  18,S
            STA  6,S
            LDD  19,S
            STD  2,S
            LDA  #1
            BRA  FC_GO
_far_write  PSHS Y,U
            LEAS -9,S
            LDA  16,S                  ; (page, off, src, n)
            STA  6,S
            LDD  17,S
            STD  2,S
            LDD  19,S
            STD  ,S
            CLRA
FC_GO       STA  7,S
            LDD  21,S
            STD  4,S
            ADDD 2,S                   ; the far range: inside its page
            BCS  FC_FAIL
            CMPD #$4000
            BHI  FC_FAIL
FC_LOOP     LDD  4,S
            BEQ  FC_OK
            TFR  D,W                   ; this time: what's left, to the far
            LDD  #$4000                ; page's end and to the end of the near
            SUBD 2,S                   ; part's bank
            BSR  FC_MIN
            LDD  ,S
            ANDA #$3F
            SUBD #$4000
            NEGD
            BSR  FC_MIN
            TFR  W,U
            LDB  ,S                    ; the near part's page
            LSRB
            LSRB
            LSRB
            LSRB
            LSRB
            LSRB
            LDA  #B_BANK_GET
            SWI2
            STA  8,S
            LDD  ,S
            ANDA #$3F
            TST  7,S
            BEQ  FC_TOFAR
            TFR  D,Y                   ; far -> near
            LDX  2,S
            LDB  6,S
            LDE  8,S
            BRA  FC_COPY
FC_TOFAR    TFR  D,X                   ; near -> far
            LDY  2,S
            LDB  8,S
            LDE  6,S
FC_COPY     LDA  #B_PAGE_COPY
            SWI2
            BCS  FC_FAIL
            LDD  ,S                    ; on by U bytes
            ADDR U,D
            STD  ,S
            LDD  2,S
            ADDR U,D
            STD  2,S
            LDD  4,S
            SUBR U,D
            STD  4,S
            BRA  FC_LOOP
FC_OK       CLRD
            BRA  FC_RET
FC_FAIL     LDD  #-1
FC_RET      LEAS 9,S
            PULS Y,U,PC
; W = the lesser of W and D (unsigned).
FC_MIN      CMPR D,W
            BLS  FM_RET
            TFR  D,W
FM_RET      RTS
;------------------------------------------------------------------------------
_far_peek   LEAS -1,S                  ; (,S the byte, 3,S page, 5,S off)
            LDD  #1
            PSHS D
            LDD  7,S
            PSHS D
            LDD  7,S
            PSHS D
            LEAX 6,S
            PSHS X
            JSR  _far_read
            LEAS 8,S
            CMPD #0
            BNE  FP_FAIL
            LDB  ,S+
            CLRA
            RTS
FP_FAIL     LEAS 1,S
            RTS
_far_poke   LDB  7,S                   ; (3,S page, 5,S off, 7,S value)
            PSHS B
            LDD  #1
            PSHS D
            LEAX 2,S
            PSHS X
            LDD  9,S                   ; (off, then page)
            PSHS D
            LDD  9,S
            PSHS D
            JSR  _far_write
            LEAS 9,S
            RTS
            ENDSECT
