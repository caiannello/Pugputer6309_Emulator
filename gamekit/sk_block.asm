;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 game kit
;    FILE: sk_block.asm
;
; SONGKIT's blocks: a pattern's cells copied, cut, pasted and cleared -- an
; overlay of its own (OV_BLOCK). The clipboard is in the overlay's page too,
; after its code (CLIP, songkit.asm): so with it in bank 2, and the pattern
; buffer in the window (bank 1), a block goes straight from one to the other.
; It keeps what was copied from pattern to pattern, and song to song.
;
; A block is whole cells: rows SBR0-SBR1 of tracks SBT0-SBT1 (as the grid
; shows them: TLIST's), from SELBOX (sk_core.asm). In the clipboard, row by
; row, each row's cells (CBTRKS of them, 5 bytes each) one after another.
;
;   BCOPY      the block into the clipboard (A: 0 "Copied", else "Cut")
;   BCLEAR     the block's cells blank
;   BPASTE     the clipboard into the pattern at the cursor (as much as fits);
;              the block, then, what it went into. Carry set if it's empty.
;
; They change the buffer only: the pattern page packs it into the song after.
;------------------------------------------------------------------------------
BCOPY       STA  BKCUT
            LDA  SBR1
            SUBA SBR0
            INCA
            STA  CBROWS
            LDA  SBT1
            SUBA SBT0
            INCA
            STA  CBTRKS
            LDY  #CLIP
            LDA  SBR0
            STA  BKR
BC1         JSR  TICKPOLL       ; (the window the player's, for a tick: the buffer
            JSR  EMAP           ; again after)
            LDA  BKR
            JSR  BKROW
            LDB  SBT0
BC2         JSR  BKCELL
            LDW  #5
            TFM  U+,Y+
            INCB
            CMPB SBT1
            BLS  BC2
            INC  BKR
            LDA  BKR
            CMPA SBR1
            BLS  BC1
            LDX  #S_COPIED
            TST  BKCUT
            BEQ  BC3
            LDX  #S_CUT
BC3         JSR  MSG
            JMP  BKSAY
; BCLEAR: the block's cells blank.
BCLEAR      LDA  SBR0
            STA  BKR
BL1         JSR  TICKPOLL
            JSR  EMAP
            LDA  BKR
            JSR  BKROW
            LDB  SBT0
BL2         JSR  BKCELL
            CLR  ,U
            CLR  1,U
            CLR  2,U
            CLR  3,U
            CLR  4,U
            INCB
            CMPB SBT1
            BLS  BL2
            INC  BKR
            LDA  BKR
            CMPA SBR1
            BLS  BL1
            RTS
; BPASTE: the clipboard into the pattern, its first cell at the cursor's -- the
; rows and tracks past the pattern's end left out.
BPASTE      LDA  CBROWS
            BNE  BP1
            LDX  #S_CBEMPTY
            JSR  MSG
            ORCC #1
            RTS
BP1         LDA  PROWS          ; how many rows, how many tracks
            SUBA CROW
            CMPA CBROWS
            BLS  BP2
            LDA  CBROWS
BP2         STA  BKNR
            LDA  NTL
            SUBA CTRK
            CMPA CBTRKS
            BLS  BP3
            LDA  CBTRKS
BP3         STA  BKNT
            LDA  CBTRKS         ; (a clipboard row's bytes)
            LDB  #5
            MUL
            STB  BKRB
            LDY  #CLIP
            CLR  BKI
BP4         JSR  TICKPOLL
            JSR  EMAP
            LDA  CROW
            ADDA BKI
            JSR  BKROW
            PSHS Y
            LDB  CTRK
            CLR  BKJ
BP5         JSR  BKCELL
            LDW  #5
            TFM  Y+,U+
            INCB
            INC  BKJ
            LDA  BKJ
            CMPA BKNT
            BLO  BP5
            PULS Y
            LDB  BKRB
            LEAY B,Y
            INC  BKI
            LDA  BKI
            CMPA BKNR
            BLO  BP4
            LDA  CROW           ; the block: what it went into
            STA  SELR
            ADDA BKNR
            DECA
            STA  SELR2
            LDA  CTRK
            STA  SELT
            ADDA BKNT
            DECA
            STA  SELT2
            LDA  #1
            STA  SELON
            JSR  SELBOX
            LDX  #S_PASTED
            JSR  MSG
            BSR  BKSAY
            ANDCC #$FE
            RTS
; BKSAY: after the message, the block's size: "N rows, M tracks".
BKSAY       LDA  SBR1
            SUBA SBR0
            INCA
            LDX  #S_ROWS
            LDY  #S_ROW
            BSR  BKSAY1
            LDA  SBT1
            SUBA SBT0
            INCA
            LDX  #S_TRKS
            LDY  #S_TRK
BKSAY1      PSHS A,X,Y
            JSR  TXDEC
            PULS A,X,Y
            CMPA #1             ; (one: "row", "track")
            BNE  BKSAY2
            TFR  Y,X
BKSAY2      JMP  TXSTR
; BKROW: X, row A of the buffer (in the window).
BKROW       LDB  #ROWB
            MUL
            ADDD #WINDOW
            TFR  D,X
            RTS
; BKCELL: U, track B's cell in the row at X. (B, X, Y kept.)
BKCELL      PSHS B
            LDU  #TLIST
            LDA  B,U
            LDB  #5
            MUL
            LEAU D,X
            PULS B,PC
S_COPIED    FCC  "Copied: "
            FCB  0
S_CUT       FCC  "Cut: "
            FCB  0
S_PASTED    FCC  "Pasted: "
            FCB  0
S_ROWS      FCC  " rows, "
            FCB  0
S_ROW       FCC  " row, "
            FCB  0
S_TRKS      FCC  " tracks"
            FCB  0
S_TRK       FCC  " track"
            FCB  0
S_CBEMPTY   FCC  "Nothing copied yet: the clipboard is empty"
            FCB  0
