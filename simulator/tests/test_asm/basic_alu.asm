; Exercises core 6809 addressing modes / ALU ops. Results are written to
; a fixed block at $2000 for the C++ test harness to check.
        org $8000
start   lda #$05
        adda #$03
        sta $2000       ; expect $08

        ldd #$1234
        addd #$0001
        std $2002       ; expect $1235

        ldx #$1000
        leax 5,x
        stx $2004       ; expect $1005

        lda #$7F
        inca
        sta $2006       ; expect $80 (overflow case)

loop    bra loop
        end
