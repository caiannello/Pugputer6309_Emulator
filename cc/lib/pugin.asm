;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 C library (LIBPUG.A)
;    FILE: pugin.asm -- <pug/input.h>: keyboard, mouse and gamepads (the video
;          card's USB port)
;------------------------------------------------------------------------------
            INCLUDE defines.d
            INCLUDE vidcard.d
            EXPORT _key_grab,_key_get,_key_mods,_key_waiting
            EXPORT _mouse_get,_mouse_wheel,_mouse_pointer,_pad_get
            IMPORT __vc_inctrl
            SECTION code
; void key_grab(int on): the keys to the program (key_get), not the console;
; the queue emptied either way. A program that takes them gives them back
; before it ends.
_key_grab   LDB  #VC_IN_KEYS
            BRA  IN_BIT
; void mouse_pointer(int on): sprite 0 follows the mouse (the program draws it)
_mouse_pointer LDB #VC_IN_PTR
IN_BIT      LDA  __vc_inctrl
            TST  3,S
            BNE  IB_ON
            COMB
            PSHS B
            ANDA ,S+
            BRA  IB_SET
IB_ON       PSHS B
            ORA  ,S+
IB_SET      STA  __vc_inctrl
            ORA  #VC_IN_FLUSH
            STA  VC_INCTRL
            RTS
; int key_get(int *ch): the next key event -> its USB usage code (KEY_...; 0:
; none), and *ch (if ch isn't 0) its character (0: none; | 0x80: a release)
_key_get    LDB  VC_KEY
            CLRA
            PSHS D
            TSTB
            BEQ  KG_NONE
            LDB  VC_KEYCHAR
KG_NONE     LDX  4,S
            BEQ  KG_RET
            CLRA
            STD  ,X
KG_RET      PULS D,PC
; int key_mods(void): the modifier keys held (KM_...)
_key_mods   LDB  VC_KEYMODS
            CLRA
            RTS
; int key_waiting(void): nonzero if a key event is waiting
_key_waiting LDB VC_STATUS
            ANDB #VC_S_KEY
            CLRA
            RTS
; int mouse_get(int *x, int *y): where it is (640x480) -> its buttons
; (MB_LEFT, MB_RIGHT, MB_MID; MB_SEEN: there is a mouse)
_mouse_get  LDD  VC_MOUSEX             ; (X first: the snapshot)
            LDX  2,S
            BEQ  MG_Y
            STD  ,X
MG_Y        LDD  VC_MOUSEY
            LDX  4,S
            BEQ  MG_B
            STD  ,X
MG_B        LDB  VC_MOUSEB
            CLRA
            RTS
; int mouse_wheel(void): clicks since the last call (+: away)
_mouse_wheel LDB VC_WHEEL
            SEX
            RTS
; int pad_get(int n, struct pad *p): pad n's 8 bytes (0-3) -> 1 if it's there
_pad_get    LDA  #VC_PAD/$10000
            STA  VC_ADDR0
            LDD  2,S
            LSLD
            LSLD
            LSLD
            ADDD #VC_PAD&$FFFF
            STD  VC_ADDR0M
            LDD  #1
            STD  VC_INC0
            PSHS Y
            LDY  6,S
            LDX  #VC_DATA0
            LDW  #8
            TFM  X,Y+
            LDB  [6,S]                 ; (PD_FLAGS: connected?)
            PULS Y
            CLRA
            ROLB
            ROLA
            TFR  A,B
            CLRA
            RTS
            ENDSECT
;------------------------------------------------------------------------------
; End of pugin.asm
;------------------------------------------------------------------------------
