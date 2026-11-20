;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 C library
;    FILE: farcall.asm -- banked code (overlays): calls to it, and loading it
;
; A function in "#pragma bank N" code is linked to run at $C000 (bank 3, the
; window), in section ovlN; LINK writes the overlays after the program's body
; (EXE_MORE: see link.asm's OVLOUT). CC1 gives each such function a stub, in
; fixed memory, under its real name: LDB #N / LDX #body / JMP __farcall.
;
; __farcall: B = an overlay, X = a function in it, the caller's return
; address at ,S (its arguments above). The return address and the page now in
; the window go on a side stack of their own, so the arguments are where the
; function expects them; the overlay's page goes in the window, the function
; is called, and on its return the window's page and the return address come
; back. D and W pass through both ways (a long in Q too). It keeps Y and U.
;
; Linked only when a stub uses __farcall, this also puts code in two of CRT0's
; sections (CC.SCR places them so that they fall through):
;   init_ovl (at the start, B = the program file, left open by DOS): the stack
;   below $C000 (the window can't be remapped while the stack is in it), a
;   page for each overlay (B_PAGE_ALLOC), the overlays read into them.
;   fini_ovl (in exit()): the pages freed.
;------------------------------------------------------------------------------
            INCLUDE defines.d
            INCLUDE libc.d
WINDOW      equ  $C000
FDEPTH      equ  48                ; far calls within far calls
NOVL        equ  16                ; overlays 1..15
            EXPORT __farcall
            IMPORT s_heap
;------------------------------------------------------------------------------
            SECTION code
__farcall   STX  ftarget
            PSHS U                     ; (U: the side stack, for a moment)
            LDU  fsp
            LDA  ovlcur
            STA  ,U
            LDX  2,S                   ; the caller's return
            STX  1,U
            LEAU 3,U
            STU  fsp
            PULS U
            LEAS 2,S
            LDX  #ovltab               ; the overlay in the window
            LDE  B,X
            STE  ovlcur
            LDB  #3
            LDA  #B_BANK_SET
            SWI2
            JSR  [ftarget]
            LEAS -2,S                  ; (the return address goes here)
            PSHSW
            PSHS D,U                   ; ,S D, 2,S U, 4,S W, 6,S the return
            LDU  fsp
            LEAU -3,U
            STU  fsp
            LDE  ,U                    ; the caller's page back
            STE  ovlcur
            LDD  1,U
            STD  6,S
            LDB  #3
            LDA  #B_BANK_SET
            SWI2
            PULS D,U
            PULSW
            RTS
            ENDSECT
;------------------------------------------------------------------------------
            SECTION init_ovl
            LDS  #WINDOW               ; the stack below the window
            STB  ovlh
            LDX  #fstack
            STX  fsp
            LDX  #s_heap               ; the fixed part must end below it
            CMPX #WINDOW
            BHI  OI_BIG
            LDB  #3
            LDA  #B_BANK_GET
            SWI2
            STA  ovlcur
OI_NEXT     LDX  #ovlhdr               ; FCB N, FDB address, FDB size
            LDY  #5
            LDB  ovlh
            LDA  #B_FREAD
            SWI2
            BCS  OI_BAD
            CMPX #0
            BEQ  OI_BAD
            LDB  ovlhdr                ; (the end: FCB 0, no more)
            BEQ  OI_DONE
            CMPX #5
            BNE  OI_BAD
            CMPB #NOVL
            BHS  OI_BAD
            LDX  #ovltab               ; its page (the first time: a new one)
            LDA  B,X
            BNE  OI_HAVE
            PSHS B,X
            LDA  #B_PAGE_ALLOC
            SWI2
            PULS B,X
            BCS  OI_NOMEM
            STA  B,X
OI_HAVE     TFR  A,E
            LDB  #3
            LDA  #B_BANK_SET
            SWI2
            LDX  ovlhdr+1              ; its bytes, there
            LDY  ovlhdr+3
            LDB  ovlh
            LDA  #B_FREAD
            SWI2
            BCS  OI_BAD
            CMPX ovlhdr+3
            BNE  OI_BAD
            BRA  OI_NEXT
OI_BIG      LDX  #m_big
            BRA  OI_FAIL
OI_NOMEM    LDX  #m_nomem
            BRA  OI_FAIL
OI_BAD      LDX  #m_bad
OI_FAIL     LDB  #F_STDOUT
            LDA  #B_PUTS
            SWI2
            JSR  FREEOVL
            LDB  #255
            LDA  #B_EXIT
            SWI2
OI_DONE     LDB  ovlh
            LDA  #B_FCLOSE_NAME
            SWI2
            ENDSECT                    ; (on into CRT0's init_end)
;------------------------------------------------------------------------------
            SECTION fini_ovl
            JSR  FREEOVL
            ENDSECT                    ; (on into CRT0's fini_end)
;------------------------------------------------------------------------------
            SECTION code
; The overlays' pages go back.
FREEOVL     LDX  #ovltab+1
FO_LOOP     LDB  ,X
            BEQ  FO_NEXT
            CLR  ,X
            PSHS X
            LDA  #B_PAGE_FREE
            SWI2
            PULS X
FO_NEXT     LEAX 1,X
            CMPX #ovltab+NOVL
            BLO  FO_LOOP
            RTS
m_big       FCC  "The program is too big for its overlays"
            FCB  CR,LF,0
m_nomem     FCC  "No memory for the program's overlays"
            FCB  CR,LF,0
m_bad       FCC  "Can't read the program's overlays"
            FCB  CR,LF,0
            ENDSECT
;------------------------------------------------------------------------------
            SECTION data               ; (init_ovl runs before bss is cleared)
ovltab      ZMB  NOVL                  ; overlay -> its page (0: none)
fsp         FDB  0                     ; the side stack: page, return
ovlcur      FCB  0                     ; the page in the window
            ENDSECT
            SECTION bss
ftarget     RMB  2
fstack      RMB  3*FDEPTH
ovlh        RMB  1                     ; (init_ovl's)
ovlhdr      RMB  5
            ENDSECT
;------------------------------------------------------------------------------
; End of farcall.asm
;------------------------------------------------------------------------------
