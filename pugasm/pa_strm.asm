;------------------------------------------------------------------------------
; pa_strm.asm -- buffered output files (shared by PUGASM and PUGLINK). A stream
; is 4+256 bytes: +0 the DOS handle, +1 open, +2 bytes buffered, +4 the buffer.
; A write error is fatal (M_WRITEERR, FATAL: the program's own).
;------------------------------------------------------------------------------
; U = a stream, X = a file name: creates it. Carry set if it can't.
SOPEN       PSHS D,X
            PSHSW
            LDE  #FOPEN_WRITE
            LDA  #B_FOPEN_NAME
            SWI2
            BCS  SO_RET
            STA  ,U
            LDA  #1
            STA  1,U
            CLR  2,U
            CLR  3,U
            ANDCC #$FE
SO_RET      PULSW
            PULS D,X,PC
; U = a stream, A = a byte. Keeps every register.
SPUTC       PSHS D,X
            LDD  2,U
            LEAX D,U
            ADDD #1
            STD  2,U
            LDA  ,S
            STA  4,X
            LDD  2,U
            CMPD #256
            BLO  SP_RET
            BSR  SFLUSH
SP_RET      PULS D,X,PC
SFLUSH      PSHS D,X,Y
            LDY  2,U
            BEQ  SF2_RET
            LEAX 4,U
            LDB  ,U
            LDA  #B_FWRITE
            SWI2
            BCS  SF2_ERR
            CLR  2,U
            CLR  3,U
SF2_RET     PULS D,X,Y,PC
SF2_ERR     CLR  1,U                   ; (don't try again while closing)
            LDX  #M_WRITEERR
            JMP  FATAL
SCLOSE      PSHS D
            TST  1,U
            BEQ  SC2_RET
            BSR  SFLUSH
            CLR  1,U
            LDB  ,U
            LDA  #B_FCLOSE_NAME
            SWI2
SC2_RET     PULS D,PC
; U = a stream, X = a string: written (X ends after it).
SPUTS       PSHS A
SS_LOOP     LDA  ,X+
            BEQ  SS_RET
            BSR  SPUTC
            BRA  SS_LOOP
SS_RET      PULS A,PC
SPUTNL      PSHS A
            LDA  #CR
            BSR  SPUTC
            LDA  #LF
            BSR  SPUTC
            PULS A,PC
;------------------------------------------------------------------------------
; End of pa_strm.asm
;------------------------------------------------------------------------------
