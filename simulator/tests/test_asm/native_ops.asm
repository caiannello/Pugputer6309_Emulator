; Exercises HD6309-native instructions: TFM block copy, BAND, MULD.
        org $8000
start   ldx #$3000
        ldy #$4000
        ldd #$0000
        ldb #$04
        tfr d,w         ; W = 4 (byte count for TFM)
        tfm x+,y+
        ldx #$4000
        lda ,x
        sta $2000       ; expect first copied byte, $11

        lda #$01
        sta $0050
        band a,0,0,<$50
        sta $2001       ; expect $01 (1 AND 1)

        ldd #$0005
        muld #3
        std $2002       ; expect high word of 15 = $0000
        stw $2004       ; expect low word of 15 = $000F

loop    bra loop
        end
