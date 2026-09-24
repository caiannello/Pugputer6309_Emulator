; Exercises the resident DOS file API (bios/defines.d's B_FOPEN_NAME/
; B_READLINE/B_WRITELINE/B_FCLOSE_NAME) directly via SWI2, bypassing
; BASIC's own LOAD/SAVE commands entirely -- see
; test_dos_file_api.cpp, which injects this into RAM and runs it AFTER
; a real BIOS+dos.asm+basic309 boot completes (so DOS_JTAB is patched),
; hijacking PC to `start` instead of feeding it through BASIC.
;
; Writes two lines to TEST    TXT, closes it, reopens it for read,
; confirms both lines round-trip byte-for-byte and a third read reports
; EOF (0 bytes), then writes $AA to RESULT. Any mismatch instead writes
; the byte 'F' plus a 1-based step number (1-8) to RESULT so a failure
; is easy to place without single-stepping.
;
; These equates mirror bios/defines.d (this file is assembled standalone,
; not linked against bios/, so they're duplicated here, not INCLUDEd).
B_FOPEN_NAME  equ $13
B_READLINE    equ $14
B_WRITELINE   equ $15
B_FCLOSE_NAME equ $16
FOPEN_READ    equ $00
FOPEN_WRITE   equ $01

    org $9000
start
            ; --- open for write, mode=1 ---
            LDX  #FNAME
            LDA  #FOPEN_WRITE
            TFR  A,E
            LDA  #B_FOPEN_NAME
            SWI2
            LBCS FAIL1
            STA  FILEREF

            ; --- write "HELLO WORLD" ---
            LDB  FILEREF
            LDX  #LINE1
            LDY  #11
            LDA  #B_WRITELINE
            SWI2
            LBCS FAIL2

            ; --- write "SECOND LINE" ---
            LDB  FILEREF
            LDX  #LINE2
            LDY  #11
            LDA  #B_WRITELINE
            SWI2
            LBCS FAIL3

            ; --- close ---
            LDB  FILEREF
            LDA  #B_FCLOSE_NAME
            SWI2
            LBCS FAIL4

            ; --- reopen for read ---
            LDX  #FNAME
            LDA  #FOPEN_READ
            TFR  A,E
            LDA  #B_FOPEN_NAME
            SWI2
            LBCS FAIL5
            STA  FILEREF

            ; --- read line 1, compare to "HELLO WORLD" ---
            LDB  FILEREF
            LDX  #RBUF
            LDY  #32
            LDA  #B_READLINE
            SWI2
            LBCS FAIL6
            CMPX #11
            LBNE FAIL6
            LDX  #RBUF
            LDY  #LINE1
            LDB  #11
CMP1        LDA  ,X+
            CMPA ,Y+
            LBNE FAIL6
            DECB
            BNE  CMP1

            ; --- read line 2, compare to "SECOND LINE" ---
            LDB  FILEREF
            LDX  #RBUF
            LDY  #32
            LDA  #B_READLINE
            SWI2
            LBCS FAIL7
            CMPX #11
            LBNE FAIL7
            LDX  #RBUF
            LDY  #LINE2
            LDB  #11
CMP2        LDA  ,X+
            CMPA ,Y+
            LBNE FAIL7
            DECB
            BNE  CMP2

            ; --- read again, expect EOF (X=0) ---
            LDB  FILEREF
            LDX  #RBUF
            LDY  #32
            LDA  #B_READLINE
            SWI2
            LBCS FAIL8
            CMPX #0
            LBNE FAIL8

            ; --- close ---
            LDB  FILEREF
            LDA  #B_FCLOSE_NAME
            SWI2

            LDA  #$AA
            STA  RESULT
            BRA  DONE

FAIL1       LDA  #'1
            BRA  FAILCOMMON
FAIL2       LDA  #'2
            BRA  FAILCOMMON
FAIL3       LDA  #'3
            BRA  FAILCOMMON
FAIL4       LDA  #'4
            BRA  FAILCOMMON
FAIL5       LDA  #'5
            BRA  FAILCOMMON
FAIL6       LDA  #'6
            BRA  FAILCOMMON
FAIL7       LDA  #'7
            BRA  FAILCOMMON
FAIL8       LDA  #'8
FAILCOMMON  STA  RESULT+1
            LDA  #'F
            STA  RESULT
DONE        BRA  DONE

FNAME       FCC  "TEST.TXT"
            FCB  0
LINE1       FCC  "HELLO WORLD"
LINE2       FCC  "SECOND LINE"
FILEREF     RMB  1
RESULT      RMB  2
RBUF        RMB  32
