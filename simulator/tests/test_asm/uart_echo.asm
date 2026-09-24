; Minimal interrupt-driven UART echo, mirroring the real BIOS's register
; sequence in bios/serio.asm (Control=$1F, Command=$09, IRQ-driven RX,
; TDRE-driven TX) but collapsed into a single ISR with no ring buffers,
; for use as both a golden test program and the uart_demo tool's payload.
        org $8000
ACIA    equ $FFE8
UT_DAT  equ ACIA+0
UT_STA  equ ACIA+1
UT_CMD  equ ACIA+2
UT_CTL  equ ACIA+3

start   lds  #$7F00
        lda  #$1F       ; 19200 baud, 8 data bits, 1 stop bit, internal RX clock
        sta  UT_CTL
        lda  #$09       ; RX IRQ enabled, TX IRQ disabled, DTR ready
        sta  UT_CMD
        andcc #$EF      ; unmask IRQ
loop    bra  loop

irqhndl lda  UT_STA
        bita #$08       ; RDRF?
        beq  chktx
        lda  UT_DAT     ; read clears RDRF
        sta  UT_DAT     ; echo it straight back (also clears TDRE)
chktx   rti
        end

; Note: lwasm's --raw output only keeps the single contiguous block
; starting at the lowest `org` (a separate `org $FFF8 / fdb irqhndl` block
; here gets silently dropped from raw output, confirmed by inspection --
; it is NOT written to the .bin). The IRQ vector at $FFF8 must be poked
; directly by the host loading this binary, pointing at `irqhndl`'s fixed
; address ($8012, per the assembler's own map output for this exact
; source -- re-check the map if this file changes).
