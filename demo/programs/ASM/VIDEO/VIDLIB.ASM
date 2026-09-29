;------------------------------------------------------------------------------
; VIDLIB.ASM: small helpers the video card demos share (INCLUDE it after the
; program's own code; VIDCARD.D first). Port 0 is theirs to use; port 1 is left
; to whatever else is going on (an interrupt handler, in VIDGFX).
;------------------------------------------------------------------------------
F_STDIN     equ  $02        ; the BIOS calls used (see /ASM/DEFINES.D)
B_GETC      equ  $0C
B_EXIT      equ  $2B

; PORT0: point data port 0 at A:X (the address's bits 23-16, 15-0), step 1.
PORT0       STA  VC_ADDR0
            STX  VC_ADDR0M
            LDD  #1
            STD  VC_INC0
            RTS
; SENDCMD: W bytes at X to the command port.
SENDCMD     LDY  #VC_CMD
            TFM  X+,Y
            RTS
; SENDDAT: W bytes at X to data port 0.
SENDDAT     LDY  #VC_DATA0
            TFM  X+,Y
            RTS
; CMDD: the two bytes of D (high first) to the command port.
CMDD        STA  VC_CMD
            STB  VC_CMD
            RTS
; PRINT: the string at X (0 at its end) into text cells from port 0 on:
; each character in color B on background E.
PRINT       LDA  ,X+
            BEQ  PRINTED
            STA  VC_DATA0
            STB  VC_DATA0
            STE  VC_DATA0
            CLRA
            STA  VC_DATA0
            BRA  PRINT
PRINTED     RTS
; TEXTAT: port 0 to the text cell at column A, row B of a 128-cell-wide map at
; VL_MAP (bits 15-0 of its address; bits 23-16 in VL_MAPH).
TEXTAT      PSHS A
            LDA  #128
            MUL                 ; D = row * 128
            ADDB ,S+
            ADCA #0             ; + column
            LSLD
            LSLD                ; * 4 bytes a cell
            ADDD VL_MAP
            TFR  D,X
            LDA  VL_MAPH
            BRA  PORT0
VL_MAPH     FCB  VC_TEXTMAP/$10000
VL_MAP      FDB  VC_TEXTMAP&$FFFF
; VBLANK: wait for the next vertical blank (and count it in VL_FRAMES).
VBLANK      LDA  #VC_I_VSYNC
            STA  VC_ISR         ; (clear the flag, then wait for the card to set it)
VBLANK1     LDA  VC_ISR
            BITA #VC_I_VSYNC
            BEQ  VBLANK1
            LDD  VL_FRAMES
            ADDD #1
            STD  VL_FRAMES
            RTS
VL_FRAMES   FDB  0
; GETKEY: a key typed? Carry clear and the key in A if so.
GETKEY      LDB  #F_STDIN
            LDA  #B_GETC
            SWI2
            RTS
; QUIT: the card as it started, and back to the shell.
QUIT        LDA  #$80
            STA  VC_CTRL
            LDA  #B_EXIT
            SWI2
; RANDOM: a pseudo-random number in D (a 16-bit xorshift).
RANDOM      LDD  VL_SEED
            PSHS D
            LSLD                ; x ^= x << 7
            LSLD
            LSLD
            LSLD
            LSLD
            LSLD
            LSLD
            EORA ,S
            EORB 1,S
            STD  ,S
            TFR  A,B            ; x ^= x >> 9
            CLRA
            LSRB
            EORA ,S
            EORB 1,S
            STD  ,S
            LSLD                ; x ^= x << 8
            LSLD
            LSLD
            LSLD
            LSLD
            LSLD
            LSLD
            LSLD
            EORA ,S
            EORB 1,S
            LEAS 2,S
            STD  VL_SEED
            RTS
VL_SEED     FDB  $ACE1
; SETCOLOR: palette entry A to the RGB565 color in X.
SETCOLOR    LDB  #2
            MUL                 ; D = A * 2
            ADDD #VC_PAL&$FFFF
            PSHS X
            TFR  D,X
            LDA  #VC_PAL/$10000
            BSR  PORT0X
            PULS D
            STA  VC_DATA0
            STB  VC_DATA0
            RTS
PORT0X      JMP  PORT0
