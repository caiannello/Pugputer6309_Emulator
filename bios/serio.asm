;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 BIOS
;    FILE: serio.asm
;  AUTHOR: CRAIG IANNELLO, PUGBUTT.COM
;
; Buffered, interrupt-driven serial driver for the R65C51P2 UART. Registers
; itself with devio.asm as the F_UART device (and, via devio's stdio
; aliasing, backs stdin/stdout/stderr too).
;
; TX design note: UT_ISR is the ONLY code that ever writes UT_DAT or advances
; the TX ring buffer's tail. UT_PUTC1 (the shared enqueue primitive behind
; both UT_WRITE and UT_PUTS) only ever pushes into the ring buffer and, if
; the transmitter is idle, flips on the TX interrupt enable -- it never
; touches UT_DAT itself. That single-writer rule is deliberate: the old
; bootloader's UT_PUTC had a second, separate code path that pulled a byte
; from the tail and wrote UT_DAT directly to "kick off" a fresh transmission,
; duplicating what the ISR does. Two paths mutating the same head/tail/count
; state is exactly the kind of thing that produces a rare desync, which
; matches a hang the old TX_END path even left a comment about. Enabling the
; TX interrupt on an idle (TDRE already set) UART causes an immediate IRQ, so
; the ISR ends up sending the first byte of a burst too -- just one interrupt
; latency later, which is not a problem at 19200 baud.
;------------------------------------------------------------------------------
    INCLUDE defines.d
;------------------------------------------------------------------------------
UT_INIT     EXPORT
UT_READ     EXPORT          ; devdrv.read   (X=buf,Y=maxlen) -> Y=actual len
UT_WRITE    EXPORT          ; devdrv.write  (X=buf,Y=len), blocks until sent
UT_IOCTL    EXPORT          ; devdrv.ioctl  (A=func,B=param) -> A=status
UT_PUTS     EXPORT          ; internal convenience: Y=null-terminated string
UT_GETC     EXPORT          ; internal convenience: -> A=char, carry=none
;------------------------------------------------------------------------------
JT_IRQ      EXTERN          ; RAM interrupt jump table, IRQ vector
DEV_REGISTER EXTERN         ; devio.asm
S_LEN       EXTERN          ; helpers.asm
CBUF_INIT   EXTERN
CBUF_PUT    EXTERN
CBUF_GET    EXTERN
;------------------------------------------------------------------------------
    SECT bss
;------------------------------------------------------------------------------
SRXBUF      circbuf         ; serial input ring buffer
STXBUF      circbuf         ; serial output ring buffer
STXIE       RMB  1          ; 0 = transmitter idle, 1 = transmitting
SNEXTISR    RMB  2          ; prior IRQ handler, for chaining if not our irq
TSTA        RMB  1          ; temp copy of UART status during ISR
GETC1_SCRATCH RMB 1         ; UT_GETC's 1-byte scratch
    ENDSECT
;------------------------------------------------------------------------------
    SECT code
;------------------------------------------------------------------------------
UT_INIT     LDX  #SRXBUF
            JSR  CBUF_INIT
            LDX  #STXBUF
            JSR  CBUF_INIT
            CLR  STXIE
            LDX  JT_IRQ+1   ; preserve whatever IRQ handler was already
            STX  SNEXTISR   ; installed, so we can chain to it if a future
                             ; IRQ turns out not to be ours.
            LDX  #UT_ISR
            STX  JT_IRQ+1
            LDA  #SUARTCTL  ; 19200 baud, 8 data bits, 1 stop bit
            STA  UT_CTL
            LDA  #SUARTCMD  ; RX IRQ enabled, TX IRQ initially disabled
            STA  UT_CMD
            LDB  #F_UART
            LDX  #UT_READ
            LDY  #UT_WRITE
            LDU  #UT_IOCTL
            JSR  DEV_REGISTER
            RTS
;------------------------------------------------------------------------------
UT_ISR      LDA  UT_STA
            STA  TSTA
            TIM  #128,TSTA  ; bit 7 clear: this IRQ wasn't the UART's doing
            BEQ  NOT_UART
CHK_RX      TIM  #8,TSTA    ; bit 3: Receiver Data Register Full
            BEQ  CHK_TX
HANDL_RX    LDA  UT_DAT     ; pull the byte, freeing the UART's holding
            LDX  #SRXBUF    ; register, regardless of buffer room -- an
            JSR  CBUF_PUT   ; overrun here just means the oldest unread byte
                             ; gets silently dropped rather than the UART
                             ; itself locking up. (X is interrupt-context
                             ; scratch here -- RTI restores the caller's X.)
CHK_TX      TIM  #16,TSTA   ; bit 4: Transmitter Data Register Empty
            BEQ  IQ_DONE
HANDL_TX    LDX  #STXBUF
            JSR  CBUF_GET
            BCS  TX_END     ; nothing left to send
            STA  UT_DAT
            RTI
TX_END      LDA  #SUARTCMD  ; back to the resting command reg (TX IRQ off)
            STA  UT_CMD
            CLR  STXIE
IQ_DONE     RTI
NOT_UART    JMP  [SNEXTISR]
;------------------------------------------------------------------------------
; Enqueue one byte (in A) for transmission, blocking until there's room in
; the TX ring buffer. Kicks the transmitter if it's currently idle. See the
; file header for why this never touches UT_DAT itself.
;------------------------------------------------------------------------------
UT_PUTC1    PSHS X
UTP1_WAIT   ORCC #$10       ; guard the buffer check+push against the ISR
            LDX  #STXBUF
            JSR  CBUF_PUT
            BCC  UTP1_GOTROOM
            ANDCC #$EF      ; no room yet -- allow IRQ so the ISR can drain
            BRA  UTP1_WAIT  ; the buffer, then retry
UTP1_GOTROOM
            LDB  STXIE
            BNE  UTP1_DONE  ; already transmitting; the ISR will get to it
            LDB  #1
            STB  STXIE
            LDB  #$05       ; RTS low, TX interrupt enabled
            STB  UT_CMD     ; TDRE is already set on an idle UART, so this
UTP1_DONE   ANDCC #$EF      ; enable fires the IRQ that sends the byte.
            PULS X,PC
;------------------------------------------------------------------------------
; devdrv.write: X=source buf, Y=byte count. Always accepts and sends all of
; it (blocking on buffer room as needed); there's nothing meaningful to
; report back beyond that, so there's no separate "actual count" out param.
;------------------------------------------------------------------------------
UT_WRITE    PSHS A,B,X,Y
UTW_LOOP    CMPY #0
            BEQ  UTW_DONE
            LDA  ,X+
            JSR  UT_PUTC1
            LEAY -1,Y
            BRA  UTW_LOOP
UTW_DONE    PULS A,B,X,Y,PC
;------------------------------------------------------------------------------
; Convenience for ROM code (boot banner, prompts): send a null-terminated
; string at Y. Not part of the devdrv vtable -- callers that only know a
; fileref go through devio's B_PUTS, which does the same S_LEN+write dance
; against whatever device the fileref resolves to.
;------------------------------------------------------------------------------
UT_PUTS     PSHS D,X,Y
            TFR  Y,X
            JSR  S_LEN      ; D = length
            TFR  D,Y
            JSR  UT_WRITE
            PULS D,X,Y,PC
;------------------------------------------------------------------------------
; Convenience for ROM code: non-blocking single-char read. Carry set means
; nothing was available (A is not meaningful in that case).
;------------------------------------------------------------------------------
UT_GETC     PSHS X,Y
            LDX  #GETC1_SCRATCH
            LDY  #1
            JSR  UT_READ
            CMPY #0
            BEQ  UGC_NONE
            LDA  GETC1_SCRATCH
            ANDCC #$FE
            PULS X,Y,PC
UGC_NONE    ORCC #$01
            PULS X,Y,PC
;------------------------------------------------------------------------------
; devdrv.read: X=dest buf, Y=max bytes wanted. Non-blocking -- copies
; whatever is already sitting in the RX ring buffer, up to Y bytes, and
; returns immediately. Returns actual count copied in Y (0 if none ready).
;------------------------------------------------------------------------------
UT_READ     PSHS A,B,U
            TFR  Y,U        ; U = remaining room in caller's buffer
            CLRB            ; B = count copied so far
UTR_LOOP    CMPU #0
            BEQ  UTR_DONE
            PSHS X
            ORCC #$10
            LDX  #SRXBUF
            JSR  CBUF_GET
            ANDCC #$EF
            PULS X
            BCS  UTR_DONE   ; ring buffer empty -- stop, don't block
            STA  ,X+
            LEAU -1,U
            INCB
            BRA  UTR_LOOP
UTR_DONE    CLRA
            TFR  D,Y        ; Y = zero-extended B (actual byte count)
            PULS A,B,U,PC
;------------------------------------------------------------------------------
; devdrv.ioctl: A=func code, B=param byte. Only UT_IOC_SETCTL exists today
; (raw R65C51 Control Register value -- baud rate / word length / stop
; bits). Waits for the transmitter to go idle first so a baud change can't
; corrupt a byte already in flight.
;------------------------------------------------------------------------------
UT_IOCTL    CMPA #UT_IOC_SETCTL
            BNE  UTIOC_BADFN
            PSHS B
UTIOC_WAIT  LDA  STXIE
            BNE  UTIOC_WAIT
            PULS B
            STB  UT_CTL
            LDA  #ERR_OK
            ANDCC #$FE
            RTS
UTIOC_BADFN LDA  #ERR_NOTSUP
            ORCC #$01
            RTS
;------------------------------------------------------------------------------
    ENDSECT
;------------------------------------------------------------------------------
; End of serio.asm
;------------------------------------------------------------------------------
