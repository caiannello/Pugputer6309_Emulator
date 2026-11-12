;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 game kit
;    FILE: sk_pat.asm
;
; SONGKIT's pattern page: the song's settings, its orders, and the pattern the
; order being edited plays -- a grid of rows and tracks, a cell where they meet
; (a note and an instrument, a volume, an effect and its parameter).
;
; The song stays as its file has it, in its pages (sk_file.asm). The pattern
; being edited is unpacked into a buffer of its own (a page, PBPG, seen through
; the window when it's wanted: 128 rows of 20 cells, 5 bytes each, as the
; player reads a cell), and packed into the song again after each change, the
; bytes after it moved along as it grows or shrinks (SPLICE). The player is
; told (SK_RESYNC): a change is heard at once while the song plays.
;
;   PATLOAD    the pattern order CURORD plays, into the buffer
;   PATSAVE    the buffer packed into the song again
;   MKTLIST    the song's tracks, from its 4-op pairs and rhythm mode
;   DRAWPAT    the whole page
;   PKEY       a key on the page (A its usage code, B its character)
;   PMOUSE     the mouse on it
;   PLAYPOS    where the song is playing, shown when it moves on
;------------------------------------------------------------------------------
GX0         equ  5          ; the grid: its first track's column,
GY0         equ  5          ;   its first row's row,
GROWS       equ  24         ;   how many rows it shows,
GTRKS       equ  5          ;   and how many tracks,
GTW         equ  14         ;   each this wide
NORDV       equ  23         ; orders shown at once
NSETF       equ  13         ; the song's settings (SETTAB)
C_ROWBG     equ  236        ; the cursor's row, behind it
C_PLAYBG    equ  22         ; the row playing, behind it
C_SELBG     equ  54         ; a block's cells, behind them
C_INS       equ  117        ; a cell's instrument, volume, effect
C_VOL       equ  114
C_FX        equ  222

;------------------------------------------------------------------------------
; The buffer, and the song's pages.
;------------------------------------------------------------------------------
; PROWA: X, row A of the buffer (in the window). (A kept.)
PROWA       PSHS A
            LDB  #ROWB
            MUL
            ADDD #WINDOW
            TFR  D,X
            PULS A,PC
; CELLX: X, the cell at the cursor (the buffer in the window).
CELLX       JSR  EMAP
            LDA  CROW
            BSR  PROWA
            LDY  #TLIST
            LDB  CTRK
            LDB  B,Y
            LDA  #5
            MUL
            ABX
            RTS
; PTENT: X, pattern A's entry in the table (the song's first page in the
; window).
PTENT       TFR  A,B
            CLRA
            LSLD
            LSLD
            ADDD #WINDOW+SK_HLEN
            ADDB NORD
            ADCA #0
            TFR  D,X
            RTS
; PBCLR: the buffer blank, and every row's size 0.
PBCLR       LDX  #WINDOW        ; (16 rows at a time, the song's ticks between)
PBC0        JSR  TICKPOLL
            JSR  EMAP
            LDW  #16*ROWB
            CLR  PTMP
            LDY  #PTMP
            TFM  Y,X+
            CMPX #WINDOW+MAXROWS*ROWB
            BLO  PBC0
            LDX  #ROWLEN
            LDB  #MAXROWS
PBC1        CLR  ,X+
            DECB
            BNE  PBC1
            RTS

;------------------------------------------------------------------------------
; Unpacking, packing.
;------------------------------------------------------------------------------
; PATLOAD: order CURORD's pattern into the buffer. PATOK 0 if it can't be
; edited: there's no such pattern, or it has more than MAXROWS rows.
PATLOAD     BSR  PBCLR
            CLR  PATOK
            CLR  SELON          ; (no block in it yet)
            LDA  #64
            STA  PROWS
            JSR  MAP0
            LDX  #WINDOW+SK_HLEN ; its pattern
            LDB  CURORD
            ABX
            LDA  ,X
            STA  CURPAT
            CMPA NPAT
            LBHS PLA9
            BSR  PTENT
            LDA  ,X             ; its rows (0: 64)
            BNE  PLA1
            LDA  #64
PLA1        STA  PROWS
            CMPA #MAXROWS
            LBHI PLA9
            LDA  1,X            ; where it is
            STA  PATOFS
            LDD  2,X
            STD  PATOFS+1
            INC  PATOK
            LDA  PATOFS
            LDX  PATOFS+1
            JSR  RSEEK
            CLR  PKROW
PLA3        LDA  PKROW
            CMPA PROWS
            BHS  PLA8
            JSR  ROWIN          ; a row; A the empty rows after it
            STA  PKN
            TST  RFLAG
            BEQ  PLA4
            JSR  EMAP           ; into the buffer
            LDA  PKROW
            JSR  PROWA
            TFR  X,Y
            LDX  #RBUF
            LDW  #ROWB
            TFM  X+,Y+
            LDA  PKROW
            JSR  ROWSIZE
PLA4        JSR  TICKPOLL       ; (the song's tick, if one is due)
            LDB  RPG            ; (back to reading)
            JSR  MAPPG
            LDA  PKROW
            ADDA PKN
            BCS  PLA8
            INCA
            BEQ  PLA8
            STA  PKROW
            BRA  PLA3
PLA8        LDB  RPG            ; how long it was: to where the reading stopped
            ANDB #3
            LDA  #64
            MUL
            PSHS B
            LDD  RPTR
            SUBD #WINDOW
            ORA  ,S+
            SUBD PATOFS+1
            STD  PATLEN
PLA9        RTS
; ROWIN: a packed row read (RGETB) into RBUF -- RFLAG not 0 if it has a cell;
; A, the empty rows after it.
ROWIN       LDX  #RBUF
            LDB  #ROWB
RIN0        CLR  ,X+
            DECB
            BNE  RIN0
            CLR  RFLAG
            LDA  #24            ; (a song gone wrong can't hold it here)
            STA  RGUARD
RIN1        JSR  RGETB
            CMPA #$1F
            BEQ  RIN8
            CMPA #$1E
            BNE  RIN2
            JMP  RGETB
RIN2        STA  RENT
            ANDA #$1F
            LDX  #RJUNK         ; (a track there isn't: passed over)
            CMPA #SK_NTRK
            BHS  RIN3
            LDB  #5
            MUL
            LDX  #RBUF
            ABX
            INC  RFLAG
RIN3        LDA  RENT
            BITA #$20
            BEQ  RIN4
            JSR  RGETB
            STA  ,X
            JSR  RGETB
            STA  1,X
RIN4        LDA  RENT
            BITA #$40
            BEQ  RIN5
            JSR  RGETB
            STA  2,X
RIN5        LDA  RENT
            BITA #$80
            BEQ  RIN6
            JSR  RGETB
            STA  3,X
            JSR  RGETB
            STA  4,X
RIN6        DEC  RGUARD
            BNE  RIN1
RIN8        CLRA
            RTS
; ROWSIZE: ROWLEN for row A, the bytes its cells take packed (the buffer in
; the window). (A kept.)
ROWSIZE     PSHS A
            JSR  PROWA
            CLRB
            LDE  #SK_NTRK
RSZ1        CLRF                ; this cell's
            LDA  ,X
            ORA  1,X
            BEQ  RSZ2
            ADDF #2
RSZ2        TST  2,X
            BEQ  RSZ3
            INCF
RSZ3        LDA  3,X
            ORA  4,X
            BEQ  RSZ4
            ADDF #2
RSZ4        TSTF
            BEQ  RSZ5
            INCF                ; and its entry's byte
            ADDR F,B
RSZ5        LEAX 5,X
            DECE
            BNE  RSZ1
            PULS A
            LDX  #ROWLEN
            STB  A,X
            RTS
; ROWSALL: every row's size again.
ROWSALL     JSR  EMAP
            CLRA
RSA1        CMPA PROWS
            BHS  RSA9
            BSR  ROWSIZE
            INCA
            BRA  RSA1
RSA9        RTS
; PKRUN: B, the empty rows after row PKROW (to the pattern's end). (Y kept.)
PKRUN       LDX  #ROWLEN
            LDA  PKROW
            CLRB
PKR1        INCA
            CMPA PROWS
            BHS  PKR9
            TST  A,X
            BNE  PKR9
            INCB
            BRA  PKR1
PKR9        RTS
; PKSIZE: D, the bytes the buffer's rows (PROWS of them) take packed.
PKSIZE      LDD  #0
            STD  PKLEN
            CLR  PKROW
PKZ1        LDA  PKROW
            CMPA PROWS
            BHS  PKZ9
            LDX  #ROWLEN        ; its cells, and the byte that ends it
            LDB  A,X
            CLRA
            ADDD PKLEN
            ADDD #1
            STD  PKLEN
            BSR  PKRUN          ; ($1E n: the empty rows after it, a byte more)
            TSTB
            BEQ  PKZ2
            LDX  PKLEN
            LEAX 1,X
            STX  PKLEN
PKZ2        INCB
            ADDB PKROW
            STB  PKROW
            BRA  PKZ1
PKZ9        LDD  PKLEN
            RTS
; PKWRITE: the buffer's rows packed into the song, from WOFS on.
PKWRITE     CLR  PKROW
PKW1        LDA  PKROW
            CMPA PROWS
            LBHS PKW9
            LDY  #WBUF
            LDX  #ROWLEN
            TST  A,X
            BEQ  PKW5
            JSR  EMAP
            JSR  PROWA
            CLRB                ; the track
PKW2        CLRA                ; its entry's bits
            TST  ,X
            BNE  PKW2A
            TST  1,X
            BEQ  PKW2B
PKW2A       ORA  #$20
PKW2B       TST  2,X
            BEQ  PKW2C
            ORA  #$40
PKW2C       TST  3,X
            BNE  PKW2D
            TST  4,X
            BEQ  PKW2E
PKW2D       ORA  #$80
PKW2E       TSTA
            BEQ  PKW4
            STB  ,Y             ; the entry: its bits and its track
            ORA  ,Y
            STA  ,Y+
            BITA #$20
            BEQ  PKW3A
            LDU  ,X
            STU  ,Y++
PKW3A       BITA #$40
            BEQ  PKW3B
            LDF  2,X
            STF  ,Y+
PKW3B       BITA #$80
            BEQ  PKW4
            LDU  3,X
            STU  ,Y++
PKW4        LEAX 5,X
            INCB
            CMPB #SK_NTRK
            BLO  PKW2
PKW5        JSR  PKRUN          ; its end
            TSTB
            BNE  PKW6
            LDA  #$1F
            STA  ,Y+
            BRA  PKW7
PKW6        LDA  #$1E
            STA  ,Y+
            STB  ,Y+
PKW7        INCB
            ADDB PKROW
            STB  PKROW
            TFR  Y,D
            SUBD #WBUF
            TFR  D,Y
            LDX  #WBUF
            BSR  IMGPUT
            LBRA PKW1
PKW9        RTS
; IMGPUT: Y bytes from X into the song at WOFS (3 bytes), WOFS on past them.
; The song's pages reach that far already.
IMGPUT      STY  IPREM
IPU1        LDD  IPREM
            BEQ  IPU9
            PSHS X
            LDX  #WOFS
            BSR  OFSMAP         ; Y: where, D: its page's room
            CMPD IPREM
            BLS  IPU2
            LDD  IPREM
IPU2        STD  IPN
            TFR  D,W
            PULS X
            TFM  X+,Y+
            LDD  IPREM
            SUBD IPN
            STD  IPREM
            LDD  WOFS+1
            ADDD IPN
            STD  WOFS+1
            LDA  WOFS
            ADCA #0
            STA  WOFS
            BRA  IPU1
IPU9        RTS
; OFSMAP: the song's page with the offset at X (3 bytes) into the window; Y,
; its address there; D, the bytes from there to the page's end. (X kept.)
OFSMAP      LDA  1,X
            LSRA
            LSRA
            LSRA
            LSRA
            LSRA
            LSRA
            LDB  ,X
            LSLB
            LSLB
            PSHS A
            ORB  ,S+
            JSR  MAPPG
            LDD  1,X
            ANDA #$3F
            PSHS D
            ADDD #WINDOW
            TFR  D,Y
            LDD  #$4000
            SUBD ,S++
            RTS

; PATSAVE: the buffer packed into the song, in place of the pattern as it was
; (and the player told). Carry set if there's no room for it.
PATSAVE     TST  PATOK
            BEQ  PSV9
            JSR  PKSIZE
            STD  SLNEW
            LDD  PATLEN
            STD  SLOLD
            LDD  PATOFS+1
            STD  SLAT+1
            LDA  PATOFS
            STA  SLAT
            JSR  SPLICE
            BCS  PSVFULL
            LDD  SLNEW
            STD  PATLEN
            LDD  PATOFS+1       ; (WOFS after SPLICE, which uses it)
            STD  WOFS+1
            LDA  PATOFS
            STA  WOFS
            JSR  PKWRITE
            JSR  MAP0           ; its rows, in the table
            LDA  CURPAT
            JSR  PTENT
            LDA  PROWS
            STA  ,X
            JSR  MARK
            JSR  RESYNC
PSV9        ANDCC #$FE
            RTS
PSVFULL     LDX  #S_NOROOM
            JSR  MSG
            ORCC #1
            RTS
; RESYNC: the player told the song has changed, if it's playing.
RESYNC      TST  SONGON
            BEQ  RSY9
            JMP  SK_RESYNC
RSY9        RTS
; MARK: the song changed (the title bar says so).
MARK        TST  CHANGED
            BNE  MRK9
            INC  CHANGED
            JMP  DRAWTITLE
MRK9        RTS

;------------------------------------------------------------------------------
; SPLICE: the song's bytes from SLAT (3 bytes) on: SLOLD of them become SLNEW
; -- those after them moved along (to DEND, which moves too), the pages that
; takes found first -- and every pattern's place in the table after them moved
; with them, and PATOFS. The bytes that are new aren't written. Carry set if
; there's no room (nothing changed then).
;------------------------------------------------------------------------------
SPLICE      LDD  SLNEW
            SUBD SLOLD
            STD  SLD
            LBEQ SLC9
            LDD  SLAT+1         ; from (the threshold: what moves), to, how many
            ADDD SLOLD
            STD  SLSRC+1
            STD  SLTHR+1
            LDA  SLAT
            ADCA #0
            STA  SLSRC
            STA  SLTHR
            LDD  SLAT+1
            ADDD SLNEW
            STD  SLDST+1
            LDA  SLAT
            ADCA #0
            STA  SLDST
            LDD  DEND+1
            SUBD SLSRC+1
            STD  SLLEN+1
            LDA  DEND
            SBCA SLSRC
            STA  SLLEN
            TST  SLD
            LBMI SLF1
            LDD  DEND+1         ; growing: the pages for its new end first
            ADDD SLD
            STD  WOFS+1
            LDA  DEND
            ADCA #0
            STA  WOFS
            JSR  ROOM
            LBCS SLC9X
SLB1        LDD  SLLEN+1        ; then from the back, a part at a time
            BNE  SLB2
            TST  SLLEN
            LBEQ SLFIX
SLB2        LDD  SLSRC+1        ; (a part ends where a page starts, at each end)
            ADDD SLLEN+1
            SUBD #1
            ANDA #$3F
            ADDD #1
            STD  SLN
            LDD  SLDST+1
            ADDD SLLEN+1
            SUBD #1
            ANDA #$3F
            ADDD #1
            CMPD SLN
            BHS  SLB3
            STD  SLN
SLB3        JSR  SLMIN
            LDD  SLLEN+1
            SUBD SLN
            STD  SLLEN+1
            LDA  SLLEN
            SBCA #0
            STA  SLLEN
            LDD  SLSRC+1
            ADDD SLLEN+1
            STD  SLCF+1
            LDA  SLSRC
            ADCA SLLEN
            STA  SLCF
            LDD  SLDST+1
            ADDD SLLEN+1
            STD  SLCT+1
            LDA  SLDST
            ADCA SLLEN
            STA  SLCT
            JSR  SLCOPY
            BRA  SLB1
SLF1        LDD  SLLEN+1        ; shrinking: from the front
            BNE  SLF2
            TST  SLLEN
            LBEQ SLFIX
SLF2        LDD  SLSRC+1        ; (a part ends where a page does, at each end)
            ANDA #$3F
            STD  SLN
            LDD  #$4000
            SUBD SLN
            STD  SLN
            LDD  SLDST+1
            ANDA #$3F
            PSHS D
            LDD  #$4000
            SUBD ,S++
            CMPD SLN
            BHS  SLF3
            STD  SLN
SLF3        BSR  SLMIN
            LDD  SLSRC+1
            STD  SLCF+1
            LDA  SLSRC
            STA  SLCF
            LDD  SLDST+1
            STD  SLCT+1
            LDA  SLDST
            STA  SLCT
            BSR  SLCOPY
            LDX  #SLSRC
            BSR  SLADV
            LDX  #SLDST
            BSR  SLADV
            LDD  SLLEN+1
            SUBD SLN
            STD  SLLEN+1
            LDA  SLLEN
            SBCA #0
            STA  SLLEN
            BRA  SLF1
; SLMIN: SLN no more than 1024 (IOBUF), or what's left.
SLMIN       LDD  #1024
            CMPD SLN
            BHS  SLM1
            STD  SLN
SLM1        TST  SLLEN
            BNE  SLM9
            LDD  SLLEN+1
            CMPD SLN
            BHS  SLM9
            STD  SLN
SLM9        RTS
; SLADV: the offset at X (3 bytes) SLN on.
SLADV       LDD  1,X
            ADDD SLN
            STD  1,X
            LDA  ,X
            ADCA #0
            STA  ,X
            RTS
; SLCOPY: SLN bytes from SLCF to SLCT in the song (each inside a page), by way
; of IOBUF.
SLCOPY      LDX  #SLCF
            JSR  OFSMAP
            TFR  Y,X
            LDY  #IOBUF
            LDW  SLN
            TFM  X+,Y+
            LDX  #SLCT
            JSR  OFSMAP
            LDX  #IOBUF
            LDW  SLN
            TFM  X+,Y+
            RTS
SLFIX       LDD  DEND+1         ; its end moved
            ADDD SLD
            STD  DEND+1
            LDA  DEND
            ADCA #0
            TST  SLD
            BPL  SLX1
            DECA
SLX1        STA  DEND
            JSR  MAP0           ; the table: where it is now (it moved with the
            LDD  #SK_HLEN       ; orders' end if that came after the threshold)
            ADDB NORD
            ADCA #0
            STD  SLN
            TST  SLTHR
            BNE  SLX2
            LDD  SLTHR+1
            CMPD SLN
            BHI  SLX2
            LDD  SLN
            ADDD SLD
            STD  SLN
SLX2        LDD  SLN
            ADDD #WINDOW+1
            TFR  D,X
            LDE  NPAT
SLX3        BSR  SLADJ          ; each pattern's place
            LEAX 4,X
            DECE
            BNE  SLX3
            LDX  #PATOFS
            BSR  SLADJ
SLC9        ANDCC #$FE
            RTS
SLC9X       ORCC #1
            RTS
; SLADJ: the offset at X (3 bytes) SLD on, if it is at SLTHR or after it.
; (X kept.)
SLADJ       LDA  ,X
            CMPA SLTHR
            BLO  SLA9
            BHI  SLA1
            LDD  1,X
            CMPD SLTHR+1
            BLO  SLA9
SLA1        LDD  1,X
            ADDD SLD
            STD  1,X
            LDA  ,X
            ADCA #0
            TST  SLD
            BPL  SLA2
            DECA
SLA2        STA  ,X
SLA9        RTS
; ROOM: pages enough for the song to reach WOFS (its end, 3 bytes) -- taken if
; need be; carry set if there aren't.
ROOM        LDD  WOFS+1         ; the last page wanted: (end - 1) / 16384
            SUBD #1
            LDB  WOFS
            SBCB #0
            LSLB
            LSLB
            LSRA
            LSRA
            LSRA
            LSRA
            LSRA
            LSRA
            PSHS A
            ORB  ,S+
            INCB
            STB  PTMP
RM1         LDB  PTMP
            CMPB NPG
            BLS  RM9
            LDA  NPG
            CMPA #MAXPG
            BHS  RMBAD
            LDA  #B_PAGE_ALLOC
            SWI2
            BCS  RMBAD
            LDX  #PAGES
            LDB  NPG
            STA  B,X
            INC  NPG
            BRA  RM1
RM9         LDA  NPG            ; (the player's count too)
            STA  SK_NPG
            ANDCC #$FE
            RTS
RMBAD       ORCC #1
            RTS

;------------------------------------------------------------------------------
; Orders and patterns.
;------------------------------------------------------------------------------
; INSORD: an order put in at B, playing pattern A (those from B on, one on).
; Carry set if it can't be (255 already, or no room).
INSORD      STD  IOPK
            LDA  NORD
            CMPA #255
            BHS  IOFULL
            LDB  IOPK+1
            CLRA
            ADDD #SK_HLEN
            STD  SLAT+1
            CLR  SLAT
            LDD  #0
            STD  SLOLD
            LDD  #1
            STD  SLNEW
            JSR  SPLICE
            BCS  IOFULL
            JSR  MAP0
            LDX  #WINDOW+SK_HLEN
            LDB  IOPK+1
            ABX
            LDA  IOPK
            STA  ,X
            INC  WINDOW+11
            LDA  WINDOW+12      ; the loop, at it or after: on one too
            CMPA #$FF
            BEQ  IO1
            CMPA IOPK+1
            BLO  IO1
            INC  WINDOW+12
IO1         JSR  TABLES
            TST  SONGON         ; and the order playing
            BEQ  IO2
            LDA  SK_ORD
            CMPA IOPK+1
            BLO  IO2
            INC  SK_ORD
IO2         JSR  RESYNC
            JSR  MARK
            ANDCC #$FE
            RTS
IOFULL      LDX  #S_NOROOM
            JSR  MSG
            ORCC #1
            RTS
; REPORD (^R): this order again, after it.
REPORD      LDA  CURPAT
            LDB  CURORD
            INCB
            BSR  INSORD
            BCS  RPO9
            INC  CURORD
            JSR  PATLOAD
            JSR  PLAYJMP
            JMP  NEWVIEW
RPO9        RTS
; DELORD (^X): this order taken out (not its pattern) -- unless it's the only one.
DELORD      LDA  NORD
            CMPA #1
            BLS  RPO9
            LDB  CURORD
            CLRA
            ADDD #SK_HLEN
            STD  SLAT+1
            CLR  SLAT
            LDD  #1
            STD  SLOLD
            LDD  #0
            STD  SLNEW
            JSR  SPLICE
            JSR  MAP0
            DEC  WINDOW+11
            LDA  WINDOW+12      ; the loop: after it, one back; past the end: the last
            CMPA #$FF
            BEQ  DLO3
            CMPA CURORD
            BLS  DLO2
            DECA
DLO2        CMPA WINDOW+11
            BLO  DLO2A
            LDA  WINDOW+11
            DECA
DLO2A       STA  WINDOW+12
DLO3        JSR  TABLES
            TST  SONGON
            BEQ  DLO4
            LDA  SK_ORD
            CMPA CURORD
            BLS  DLO4
            DEC  SK_ORD
DLO4        LDA  CURORD
            CMPA NORD
            BLO  DLO5
            DEC  CURORD
DLO5        JSR  RESYNC
            JSR  MARK
            JSR  PATLOAD
            JSR  PLAYJMP
            LDA  #5
            JSR  DRAWSETF
            JMP  NEWVIEW
; NEWPAT (^N), DUPPAT (^D): a new pattern -- empty (with this one's rows), or a
; copy of this one -- played by a new order after this one, and edited.
NEWPAT      JSR  PBCLR
            TST  PATOK
            BNE  ADDPAT
            LDA  #64
            STA  PROWS
            BRA  ADDPAT
DUPPAT      TST  PATOK
            BEQ  NEWPAT
ADDPAT      LDA  NPAT
            CMPA #255
            LBHS APFULL
            LDA  NORD
            CMPA #255
            LBHS APFULL
            JSR  PKSIZE         ; room for it all first: its bytes, its entry, an order
            STD  APSIZE
            ADDD #5
            ADDD DEND+1
            STD  WOFS+1
            LDA  DEND
            ADCA #0
            STA  WOFS
            JSR  ROOM
            LBCS APFULL
            LDD  ITAB           ; its entry, after the table's others
            STD  SLAT+1
            CLR  SLAT
            LDD  #0
            STD  SLOLD
            LDD  #4
            STD  SLNEW
            JSR  SPLICE
            LDD  DEND+1         ; its bytes, at the end
            STD  SLAT+1
            LDA  DEND
            STA  SLAT
            LDD  #0
            STD  SLOLD
            LDD  APSIZE
            STD  SLNEW
            STD  PATLEN
            JSR  SPLICE
            LDD  SLAT+1         ; (its place after SPLICE: what was at its place
            STD  PATOFS+1       ; before moved on past it)
            STD  WOFS+1
            LDA  SLAT
            STA  PATOFS
            STA  WOFS
            JSR  PKWRITE
            JSR  MAP0
            LDA  NPAT
            JSR  PTENT
            LDA  PROWS
            STA  ,X
            LDA  PATOFS
            STA  1,X
            LDD  PATOFS+1
            STD  2,X
            INC  WINDOW+10
            JSR  TABLES
            LDA  NPAT           ; and an order after this one, playing it
            DECA
            LDB  CURORD
            INCB
            JSR  INSORD
            INC  CURORD
            JSR  PATLOAD
            JSR  PLAYJMP
            JMP  NEWVIEW
APFULL      LDX  #S_NOROOM
            JMP  MSG
; KPAT: A +1 or -1: this order plays the pattern after, or before, this one.
KPAT        LDB  CURPAT         ; (one there isn't: the last there is)
            CMPB NPAT
            BLO  KPT1
            LDA  NPAT
            DECA
            BRA  KPT2
KPT1        ADDA CURPAT
            CMPA NPAT           ; (-1 is $FF: no)
            BHS  KPT9
KPT2        PSHS A
            JSR  MAP0
            LDX  #WINDOW+SK_HLEN
            LDB  CURORD
            ABX
            PULS A
            STA  ,X
            JSR  RESYNC
            JSR  MARK
            JSR  PATLOAD
            JMP  NEWVIEW
KPT9        RTS

;------------------------------------------------------------------------------
; The song's tracks.
;------------------------------------------------------------------------------
; MKTLIST: TLIST, the song's tracks in order (NTL of them): the channels that
; aren't a 4-op pair's second, and in rhythm mode the cymbal and the hi-hat.
MKTLIST     CLR  SELON          ; (the tracks may be others now: no block)
            LDX  #TLIST
            CLRB
MKT1        TFR  B,A
            CLRF
            CMPA #9
            BLO  MKT2
            SUBA #9
            LDF  #3
MKT2        SUBA #3             ; an array's channels 3-5: a pair's second?
            BLO  MKT3
            CMPA #3
            BHS  MKT3
            ADDR F,A
            LDY  #SKBITS
            LDA  A,Y
            BITA SPAIRS
            BNE  MKT4
MKT3        STB  ,X+
MKT4        INCB
            CMPB #18
            BLO  MKT1
            LDA  SFLAGS
            BITA #1
            BEQ  MKT5
            LDD  #$1213
            STD  ,X++
MKT5        TFR  X,D
            SUBD #TLIST
            STB  NTL
            LDA  CTRK           ; (the cursor on one of them)
            CMPA NTL
            BLO  MKT9
            LDA  NTL
            DECA
            STA  CTRK
MKT9        RTS
; TKIND: X, what track A is ("", " 4-op", a drum's name).
TKIND       LDX  #S_KINDS
            LDB  SFLAGS
            BITB #1
            BEQ  TKD2
            LDY  #DRUMTKS
            LEAX 8,X
TKD1        CMPA ,Y+
            BEQ  TKD9
            LEAX 8,X
            CMPY #DRUMTKS+5
            BLO  TKD1
TKD2        LDX  #S_KINDS
            TFR  A,B
            CLRF
            CMPB #9
            BLO  TKD3
            SUBB #9
            LDF  #3
TKD3        CMPB #3
            BHS  TKD9
            ADDR F,B
            LDY  #SKBITS
            LDB  B,Y
            BITB SPAIRS
            BEQ  TKD9
            LDX  #S_KINDS+48
TKD9        RTS
DRUMTKS     FCB  6,7,8,18,19

;------------------------------------------------------------------------------
; Drawing the page.
;------------------------------------------------------------------------------
DRAWPAT     BSR  DRAWUI
            JSR  VIEWFIX
            JSR  DRAWORDS
            JSR  DRAWSTAT
            JMP  DRAWGRID
; REDRAWUI: the page again over the grid as it is (its own layer, which the
; help left alone).
REDRAWUI    BSR  DRAWUI
            JSR  DRAWORDS
            JSR  DRAWHEAD
            JMP  DRAWSTAT
; DRAWUI: the screen's layer: the grid's window clear, the title, the labels,
; the settings.
DRAWUI      JSR  TXCLR
            JSR  PHOLE
            JSR  DRAWTITLE
            LDX  #PLABELS
            JSR  DRAWLAB
            CLRA
DPT1        PSHS A
            JSR  DRAWSETF
            PULS A
            INCA
            CMPA #NSETF
            BLO  DPT1
            RTS
; NEWVIEW: after PATLOAD: the cursor on one of its rows, and what shows the
; pattern drawn again.
NEWVIEW     LDA  CROW
            CMPA PROWS
            BLO  NVW1
            LDA  PROWS
            DECA
            STA  CROW
NVW1        JSR  VIEWFIX
            JSR  DRAWORDS
            LDA  #4
            JSR  DRAWSETF
            JSR  DRAWGRID
            JMP  DRAWSTAT
; VIEWFIX: the rows and tracks shown moved, if need be, for the cursor to be
; among them; F not 0 if they were.
VIEWFIX     CLRF
            LDA  CROW
            CMPA TOPROW
            BHS  VFX1
            STA  TOPROW
            INCF
VFX1        SUBA TOPROW
            CMPA #GROWS
            BLO  VFX2
            LDA  CROW
            SUBA #GROWS-1
            STA  TOPROW
            INCF
VFX2        LDA  CTRK
            CMPA LTRK
            BHS  VFX3
            STA  LTRK
            INCF
VFX3        SUBA LTRK
            CMPA #GTRKS
            BLO  VFX4
            LDA  CTRK
            SUBA #GTRKS-1
            STA  LTRK
            INCF
VFX4        RTS
; CURMOVED: the cursor moved (A the row it was on): the rows it was and is on
; drawn again -- the grid scrolled first, if the rows shown had to move; all
; of it drawn again, if the tracks shown did.
CURMOVED    PSHS A
            LDB  LTRK
            PSHS B
            BSR  VIEWFIX
            PULS B
            CMPB LTRK
            BEQ  CMV0
            PULS A
            JMP  DRAWGRID
CMV0        TSTF
            BEQ  CMV1
            JSR  SETVS
CMV1        PULS A
            CMPA CROW
            BEQ  CMV2
            JSR  DRAWROW
CMV2        LDA  CROW
            JMP  DRAWROW

; DRAWSETF: the song's setting A (SETTAB), lit if it is the one picked.
DRAWSETF    STA  DRN
            LDB  #3
            MUL
            LDX  #SETTAB
            ABX
            LDA  ,X
            LDB  1,X
            JSR  TXAT
            LDB  2,X
            STB  DRF            ; (its width)
            CLRB
            TST  AREA
            BEQ  DSF1
            LDA  DRN
            CMPA SETF
            BNE  DSF1
            LDB  #C_CURBG
DSF1        STB  TXBG
            LDA  #C_VALUE
            STA  TXFG
            JSR  MAP0
            LDA  DRN
            BNE  DSF2
            LDX  #WINDOW+16     ; the title
            BRA  DSFTXT
DSF2        CMPA #1
            BNE  DSF3
            LDX  #WINDOW+48     ; the author
DSFTXT      CLRB
DSFT1       LDA  ,X+
            LBEQ DSFPAD
            JSR  TXCH
            INCB
            CMPB #32
            BLO  DSFT1
            BRA  DSFPAD
DSF3        CMPA #2
            BNE  DSF4
            LDA  WINDOW+8       ; ticks a row
            BRA  DSFDEC
DSF4        CMPA #3
            BNE  DSF5
            LDA  WINDOW+7       ; ticks a second
            BRA  DSFDEC
DSF5        CMPA #4
            BNE  DSF6
            LDA  PROWS          ; this pattern's rows
DSFDEC      JSR  TXDEC
            BRA  DSFPAD
DSF6        CMPA #5
            BNE  DSF7
            LDA  WINDOW+12      ; the loop
            CMPA #$FF
            BNE  DSF6A
            LDX  #S_NONE
            JSR  PSTR
            BRA  DSFPAD
DSF6A       JSR  HEX2
            LDB  #2
            BRA  DSFPAD
DSF7        CMPA #6
            BNE  DSF8
            LDX  #S_NO          ; rhythm mode
            LDA  WINDOW+4
            BITA #1
            BEQ  DSF7A
            LDX  #S_YES
DSF7A       JSR  PSTR
            BRA  DSFPAD
DSF8        SUBA #7             ; a 4-op pair: its first channel, bright if it's on
            LDX  #SKBITS
            LDB  A,X
            PSHS A
            LDA  #C_DIM
            BITB WINDOW+5
            BEQ  DSF8A
            LDA  #C_VALUE
DSF8A       STA  TXFG
            PULS A
            LDX  #S_PAIRS
            LSLA
            LEAX A,X
            LDA  ,X+
            JSR  TXCH
            LDA  ,X
            JSR  TXCH
            LDB  #2
DSFPAD      NEGB
            ADDB DRF
            BLE  DSF9
            JSR  TXSPC
DSF9        CLR  TXBG
            RTS

; DRAWORDS: the orders (those that fit, the one being edited among them):
; each its pattern; the one being edited lit, the one playing in orange, the
; loop's marked >.
DRAWORDS    LDA  CURORD
            CMPA OTOP
            BHS  DOR1
            STA  OTOP
DOR1        SUBA OTOP
            CMPA #NORDV
            BLO  DOR2
            LDA  CURORD
            SUBA #NORDV-1
            STA  OTOP
DOR2        LDA  #9
            LDB  #3
            JSR  TXAT
            JSR  MAP0
            LDB  OTOP
            STB  DRN
            LDE  #NORDV
DOR3        LDB  DRN
            CMPB NORD
            BHS  DOR8
            CLR  TXBG
            LDA  #C_VALUE
            STA  TXFG
            CMPB CURORD
            BNE  DOR4
            LDA  #C_CURBG
            STA  TXBG
DOR4        CMPB PLORD
            BNE  DOR5
            LDA  #C_OUT
            STA  TXFG
DOR5        LDA  #$20
            CMPB WINDOW+12
            BNE  DOR6
            LDA  #'>
DOR6        JSR  TXCH
            LDX  #WINDOW+SK_HLEN
            ABX
            LDA  ,X
            JSR  HEX2
            INC  DRN
            DECE
            BNE  DOR3
            CLR  TXBG
            RTS
DOR8        CLR  TXBG
            LDB  #3
            JSR  TXSPC
            DECE
            BNE  DOR8
            RTS

; DRAWHEAD: above the grid, the tracks shown: each its number and what it is.
DRAWHEAD    CLRA
            LDB  #GY0-1
            JSR  TXAT
            CLR  TXBG
            LDB  #GX0
            JSR  TXSPC
            CLR  DRS
DHD1        LDA  LTRK
            ADDA DRS
            CMPA NTL
            BHS  DHD8
            LDX  #TLIST
            LDA  A,X
            PSHS A
            JSR  ISMUTE         ; its box: [M], muted
            LDB  #'M
            JSR  CHKBOX
            LDA  ,S
            LDB  #C_HEAD
            STB  TXFG
            JSR  TXDEC
            STB  DRN
            PULS A
            JSR  TKIND
            LDA  #C_LABEL
            STA  TXFG
            JSR  PSTR
            ADDB DRN
            NEGB
            ADDB #GTW-4
            JSR  TXSPC
            INC  DRS
            LDA  DRS
            CMPA #GTRKS
            BLO  DHD1
DHD8        LDA  DRS
            LDB  #GTW
            MUL
            NEGB
            ADDB #80-GX0
            JMP  TXSPC

; DRAWGRID: the tracks' heads; the grid's layer scrolled to the rows shown,
; and they drawn at once -- the others queued, drawn a few at a time as the
; main loop goes round (RQSTEP).
DRAWGRID    JSR  DRAWHEAD
            BSR  SETVS
            LDA  TOPROW
            STA  DGR
            LDB  #GROWS
            STB  DGN
DGR1        LDA  DGR
            ANDA #MAXROWS-1
            JSR  DRAWROW
            INC  DGR
            DEC  DGN
            BNE  DGR1
            LDA  DGR            ; the rest, from the next on
            ANDA #MAXROWS-1
            STA  RQR
            LDA  #MAXROWS-GROWS
            STA  RQN
            TST  PATOK          ; (a pattern not edited here: why)
            BNE  DGR9
            LDX  #S_NOPAT
            LDA  CURPAT
            CMPA NPAT
            BHS  DGR2
            LDX  #S_LONGPAT
DGR2        JMP  MSG
DGR9        RTS
; RQSTEP: a few of the rows queued, drawn.
RQSTEP      LDB  #4
RQS1        TST  RQN
            BEQ  RQS9
            PSHS B
            LDA  RQR
            JSR  DRAWROW
            LDA  RQR
            INCA
            ANDA #MAXROWS-1
            STA  RQR
            DEC  RQN
            PULS B
            DECB
            BNE  RQS1
RQS9        RTS
; SETVS: the grid's layer scrolled for row TOPROW to be at the screen's row
; GY0 (its 128 rows go round).
SETVS       LDA  #VC_CFG/$10000
            LDX  #LAYER0+L_VSCROLL
            JSR  UIPORT
            LDA  TOPROW
            SUBA #GY0
            ANDA #MAXROWS-1
            LDB  #16
            MUL
            STA  VC_DATA0
            STB  VC_DATA0
            RTS
; PHOLE: the screen's cells over the grid left clear (color 0: nothing), for
; the grid's layer to be seen.
PHOLE       LDB  #GY0
PHO1        CLRA
            JSR  TXAT
            LDE  #80
PHO2        LDA  #$20
            STA  VC_DATA0
            CLRA
            STA  VC_DATA0
            STA  VC_DATA0
            STA  VC_DATA0
            DECE
            BNE  PHO2
            INCB
            CMPB #GY0+GROWS
            BLO  PHO1
            RTS

; DRAWROW: row A of the pattern (0-127), in the grid's layer: its number, then
; a cell for each track shown; behind it, the color of the row playing or the
; cursor's; the cursor's field lit. (A row past the pattern's end: blank.)
DRAWROW     JSR  TICKPOLL       ; (a tick due: first)
            STA  DRR
            TFR  A,B
            CLRA
            JSR  GXAT
            CLRA
            LDB  DRR
            CMPB CROW
            BNE  DRW1
            LDA  #C_ROWBG
DRW1        CMPB PLROW
            BNE  DRW2
            LDB  PLORD
            CMPB CURORD
            BNE  DRW2
            LDA  #C_PLAYBG
DRW2        STA  DRBG
            STA  DRBGR
            STA  TXBG
            TST  PATOK
            LBEQ DRWBL
            LDA  DRR
            CMPA PROWS
            LBHS DRWBL
            LDB  #2
            JSR  TXSPC
            LDB  #C_DIM         ; its number: each fourth brighter
            LDA  DRR
            BITA #3
            BNE  DRW3
            LDB  #C_LABEL
DRW3        STB  TXFG
            JSR  HEX2
            LDA  #$20
            JSR  TXCH
            JSR  EMAP
            LDA  DRR
            JSR  PROWA
            STX  DRX
            CLR  DRS
DRW4        LDA  LTRK
            ADDA DRS
            CMPA NTL
            BHS  DRW7
            LDX  #TLIST
            LDB  A,X
            LDA  #5
            MUL
            LDX  DRX
            ABX
            LDA  #$FF           ; the cursor's field, if it's in this cell
            LDB  DRR
            CMPB CROW
            BNE  DRW5
            TST  AREA
            BNE  DRW5
            LDB  LTRK
            ADDB DRS
            CMPB CTRK
            BNE  DRW5
            LDA  CCOL
DRW5        STA  DRF
            LDA  DRBGR          ; behind it: the row's color, or the block's
            TST  SELON
            BEQ  DRW6
            LDB  DRR
            CMPB SBR0
            BLO  DRW6
            CMPB SBR1
            BHI  DRW6
            LDB  LTRK
            ADDB DRS
            CMPB SBT0
            BLO  DRW6
            CMPB SBT1
            BHI  DRW6
            LDA  #C_SELBG
DRW6        STA  DRBG
            BSR  DRAWCELL
            INC  DRS
            LDA  DRS
            CMPA #GTRKS
            BLO  DRW4
DRW7        LDA  DRBGR
            STA  TXBG
            LDA  DRS
            LDB  #GTW
            MUL
            NEGB
            ADDB #80-GX0
            JSR  TXSPC
            CLR  TXBG
DRW9        RTS
DRWBL       LDB  #80
            JSR  TXSPC
            CLR  TXBG
            RTS

; DRAWCELL: the cell at X -- its field DRF lit (0 the note, 1 and 2 the
; instrument's digits, 3 and 4 the volume's, 5 the effect, 6 and 7 its
; parameter's), and a space after it. (X kept.)
DRAWCELL    CLRB                ; the note
            JSR  CBG
            LDA  ,X
            BEQ  DCE1
            CMPA #$7F
            BEQ  DCE2
            CMPA #96
            BHI  DCE1
            LDB  #C_VALUE
            STB  TXFG
            JSR  NOTENAME
            BRA  DCE3
DCE1        LDB  #C_DIM
            STB  TXFG
            LDA  #'.
            BRA  DCE2A
DCE2        LDB  #C_VALUE       ; (the key let go)
            STB  TXFG
            LDA  #'=
DCE2A       JSR  TXCH
            JSR  TXCH
            JSR  TXCH
DCE3        BSR  DSPC
            LDA  1,X            ; the instrument
            LDB  #C_INS
            LDE  #1
            BSR  CHEX2
            BSR  DSPC
            LDA  2,X            ; the volume (one more than it; 0: none)
            LDB  #C_VOL
            LDE  #3
            TSTA
            BEQ  DCE4
            DECA
            BSR  CHEX2N
            BRA  DCE5
DCE4        BSR  CHEX2
DCE5        BSR  DSPC
            LDA  3,X            ; the effect and its parameter
            ORA  4,X
            BNE  DCE6
            LDB  #C_DIM
            STB  TXFG
            LDB  #5
            BSR  CBG
            LDA  #'.
            JSR  TXCH
            CLRA
            LDE  #6
            BSR  CHEX2
            BRA  DSPC
DCE6        LDB  #C_FX
            STB  TXFG
            LDB  #5
            BSR  CBG
            LDA  3,X
            BNE  DCE7
            LDA  #'.
DCE7        JSR  TXCH
            LDA  4,X
            LDB  #C_FX
            LDE  #6
            BSR  CHEX2N
DSPC        LDA  DRBG           ; a space, the row's
            STA  TXBG
            LDA  #$20
            JMP  TXCH
; CBG: the background for field B: lit if it's DRF, else the row's. (B, X kept.)
CBG         LDA  DRBG
            CMPB DRF
            BNE  CBG1
            LDA  #C_CURBG
CBG1        STA  TXBG
            RTS
; CHEX2: A as two hex digits in color B (0: two dots, dim), its fields E and
; E+1; CHEX2N: the same, 0 as 00. (X kept.)
CHEX2       TSTA
            BNE  CHEX2N
            LDB  #C_DIM
            STB  TXFG
            TFR  E,B
            BSR  CBG
            LDA  #'.
            JSR  TXCH
            INCE
            TFR  E,B
            BSR  CBG
            LDA  #'.
            JMP  TXCH
CHEX2N      STB  TXFG
            PSHS A
            TFR  E,B
            BSR  CBG
            LDA  ,S
            LSRA
            LSRA
            LSRA
            LSRA
            BSR  HEX1
            INCE
            TFR  E,B
            BSR  CBG
            PULS A
            ANDA #$0F
            BRA  HEX1
; HEX2: A as two hex digits; HEX1: A's low digit (0-15). (X kept.)
HEX2        PSHS A
            LSRA
            LSRA
            LSRA
            LSRA
            BSR  HEX1
            PULS A
            ANDA #$0F
HEX1        ADDA #'0
            CMPA #'9
            BLS  HEX1A
            ADDA #7
HEX1A       JMP  TXCH

; PSTAT: the pattern page's status: the octave the keys play, the instrument
; they enter (its number and name), the pattern (of how many), and whether
; the song is playing.
PSTAT       LDA  #2
            LDB  #29
            JSR  TXAT
            CLR  TXBG
            LDA  #C_LABEL
            STA  TXFG
            LDX  #S_POCT
            JSR  TXSTR
            LDA  #C_VALUE
            STA  TXFG
            LDA  OCT
            ADDA #'0
            JSR  TXCH
            LDA  #C_LABEL
            STA  TXFG
            LDX  #S_INSTR
            JSR  TXSTR
            LDA  #C_VALUE
            STA  TXFG
            LDA  CURI
            BSR  HEX2
            LDA  #$20
            JSR  TXCH
            LDX  NP
            JSR  PSTR
            NEGB
            ADDB #17
            JSR  TXSPC
            LDA  #C_LABEL
            STA  TXFG
            LDX  #S_PATT
            JSR  TXSTR
            LDA  #C_VALUE
            STA  TXFG
            LDA  CURPAT
            BSR  HEX2
            LDA  #C_LABEL
            STA  TXFG
            LDA  #'/
            JSR  TXCH
            LDA  #C_VALUE
            STA  TXFG
            LDA  NPAT
            JSR  HEX2
            LDA  #$20           ; (column 44)
            JSR  TXCH
            LDA  RECORD
            LDB  #'x
            JSR  CHKBOX
            LDX  #S_REC
            JSR  TXSTR
            LDA  #$20           ; (column 55)
            JSR  TXCH
            LDA  LOOPPAT
            LDB  #'x
            JSR  CHKBOX
            LDX  #S_LOOP
            JMP  TXSTR
; CHKBOX: a box, "[x] ": checked (B the mark) if A isn't 0. (All kept.)
CHKBOX      PSHS D
            LDA  #C_LABEL
            STA  TXFG
            LDA  #'[
            JSR  TXCH
            LDA  #$20
            TST  ,S
            BEQ  CKB1
            LDA  #C_MSG
            STA  TXFG
            LDA  1,S
CKB1        JSR  TXCH
            LDA  #C_LABEL
            STA  TXFG
            LDA  #']
            JSR  TXCH
            LDA  #$20
            JSR  TXCH
            PULS D,PC
; KREC (^E): Record on or off. KLOOP (^P): Loop pattern on or off.
KREC        LDA  RECORD
            EORA #1
            STA  RECORD
            CLR  RKEY
            JMP  DRAWSTAT
KLOOP       LDA  LOOPPAT
            EORA #1
            STA  LOOPPAT
            STA  SK_PLOOP
            JMP  DRAWSTAT
; ISMUTE: track A muted? (A not 0 if so.)
ISMUTE      TFR  A,B
            LSRB
            LSRB
            LSRB
            ANDA #7
            LDX  #SKBITS
            LDA  A,X
            LDX  #MUTES
            ANDA B,X
            RTS
; KMUTE (^M): the cursor's track muted, or not. TOGMUTE: track A's the same
; (its note let go, if it's muted as the song plays).
KMUTE       LDX  #TLIST
            LDB  CTRK
            LDA  B,X
TOGMUTE     STA  MTRK
            TFR  A,B
            LSRB
            LSRB
            LSRB
            ANDA #7
            LDX  #SKBITS
            LDA  A,X
            LDX  #MUTES
            EORA B,X
            STA  B,X
            LDD  MUTES          ; (the player's to know)
            STD  SK_MUTE
            LDA  MUTES+2
            STA  SK_MUTE+2
            TST  SONGON
            BEQ  TGM1
            LDA  MTRK
            BSR  ISMUTE
            BEQ  TGM1
            LDB  MTRK
            JSR  SK_TOFF
TGM1        JMP  DRAWHEAD
; PLAYJMP: as the song plays, the order chosen played from its start (the
; notes sounding let go).
PLAYJMP     TST  SONGON
            BEQ  PJ9
            CLRB
PJ1         PSHS B
            JSR  SK_TOFF
            PULS B
            INCB
            CMPB #SK_NTRK
            BLO  PJ1
            LDA  CURORD
            JSR  SKORDER
            CLR  SK_TICKN
            CLR  SK_JFL
PJ9         RTS
; PRECUP: key A let go (kept): recording as the song plays, if it's the key
; of the note put in last, its end put in -- in the row playing, or (let go
; in the row it went in) the row after, if nothing's there.
PRECUP      TST  PAGE
            LBNE PRU9
            TST  RECORD
            LBEQ PRU9
            TST  SONGON
            LBEQ PRU9
            TST  PATOK
            BEQ  PRU9
            TST  RKEY
            BEQ  PRU9
            CMPA RKEY
            BNE  PRU9
            PSHS A
            CLR  RKEY
            CLR  PNEXT
            LDB  CROW           ; the row playing (the cursor's)
            LDA  CURORD
            CMPA RORD
            BNE  PRU3
            CMPB RROW
            BNE  PRU3
            INCB                ; (the row it went in: the next)
            CMPB PROWS
            BHS  PRU8
            INC  PNEXT
PRU3        STB  PTGT
            LDA  CROW
            STA  PSVROW
            LDA  CTRK
            STA  PSVTRK
            STB  CROW
            LDA  RTRK
            STA  CTRK
            JSR  CELLX
            TST  PNEXT
            BEQ  PRU4
            TST  ,X             ; (a note there already: that ends it)
            BNE  PRU7
PRU4        LDA  #$7F
            STA  ,X
            CLR  1,X
            JSR  EMAP
            LDA  CROW
            JSR  ROWSIZE
            JSR  PATSAVE
            INC  PNEXT          ; (drawn again, below)
PRU7        LDA  PSVROW
            STA  CROW
            LDA  PSVTRK
            STA  CTRK
            TST  PNEXT
            BEQ  PRU8
            LDA  PTGT
            JSR  DRAWROW
PRU8        PULS A
PRU9        RTS

; PLAYPOS: where the song is playing (PLORD, PLROW), shown when it moves on:
; the row lit, and the order.
PLAYPOS     TST  PAGE
            LBNE PPS9
            LDD  #$FFFF         ; (nowhere, unless it's playing)
            TST  SONGON
            BEQ  PPS1
            LDA  SK_ORD
            LDB  SK_ROW
PPS1        CMPD PLORD
            BEQ  PPS9
            LDX  PLORD          ; the old, the new
            STD  PLORD
            STX  PPOLD
            CMPA #$FF           ; following the song: its order, its row
            BEQ  PPS1A
            CMPA CURORD
            BEQ  PPS1B
            STA  CURORD         ; (another order: its pattern)
            LDA  PLROW
            STA  CROW
            BSR  FOLTOP
            JSR  PATLOAD
            JSR  DRAWORDS
            LDA  #4
            JSR  DRAWSETF
            JSR  DRAWGRID
            JMP  DRAWSTAT
PPS1B       LDA  CROW           ; the cursor on the row playing, in the middle
            LDB  PLROW
            STB  CROW
            PSHS A
            BSR  FOLTOP
            JSR  SETVS
            PULS A
            JSR  DRAWROW
PPS1A       LDA  PPOLD          ; the old row, if it's this order's
            CMPA CURORD
            BNE  PPS2
            LDA  PPOLD+1
            JSR  DRAWROW
PPS2        LDA  PLORD          ; the new
            CMPA CURORD
            BNE  PPS3
            LDA  PLROW
            JSR  DRAWROW
PPS3        LDA  PLORD
            CMPA PPOLD
            BEQ  PPS9
            JMP  DRAWORDS
PPS9        RTS
; FOLTOP: TOPROW for the cursor's row to be in the middle of those shown.
FOLTOP      LDA  CROW
            SUBA #GROWS/2-1
            ANDA #MAXROWS-1
            STA  TOPROW
            RTS

;------------------------------------------------------------------------------
; The keys.
;------------------------------------------------------------------------------
PKEY        LDB  KEYMODS
            BITB #VC_MOD_CTL
            BEQ  PKY1
            LDX  #PCTLTAB
            BSR  TFIND
            BCS  PKY9
            JMP  [1,X]
PKY1        BITB #VC_MOD_ALT    ; Alt+Insert, Alt+Delete: the order again, out
            BEQ  PKYSH
            CMPA #K_INSERT
            LBEQ REPORD
            CMPA #K_DELETE
            LBEQ DELORD
PKYSH       BITB #VC_MOD_SHF
            BEQ  PKY2
            CMPA #K_DELETE      ; Shift+Delete: the row out, in this track
            BNE  PKYSH1
            CLRA
            JMP  ROWDEL
PKYSH1      LDX  #PMOVTAB       ; Shift and a cursor key: a block
            BSR  TFIND
            LBCC SELEXT
PKY2        LDX  #PMOVTAB       ; the cursor moved (the block let go)
            BSR  TFIND
            BCS  PKY2A
            PSHS X
            JSR  SELOFF
            PULS X
            JMP  [1,X]
PKY2A       LDX  #PKEYTAB
            BSR  TFIND
            BCS  PKY3
            JMP  [1,X]
PKY3        TST  AREA           ; the rest: what's typed into a cell
            BNE  PKY9
            CMPA #K_LCTRL       ; (Shift, Ctrl, Alt alone: nothing, the block kept)
            BHS  PKY9
            PSHS A              ; (the block let go)
            JSR  SELOFF
            PULS A
            JMP  PENTRY
PKY9        RTS
; TFIND: key A in the table at X (a byte each, its routine after it): X its
; entry, carry clear; carry set if it isn't there.
TFIND       LDB  ,X
            BEQ  TFD9
            CMPA ,X
            BEQ  TFD1
            LEAX 3,X
            BRA  TFIND
TFD1        ANDCC #$FE
            RTS
TFD9        ORCC #1
            RTS
PMOVTAB     FCB  K_UP           ; (with Shift: SELEXT)
            FDB  PUP
            FCB  K_DOWN
            FDB  PDOWN
            FCB  K_LEFT
            FDB  PLEFT
            FCB  K_RIGHT
            FDB  PRIGHT
            FCB  K_PGUP
            FDB  PPGUP
            FCB  K_PGDN
            FDB  PPGDN
            FCB  K_HOME
            FDB  PHOME
            FCB  K_END
            FDB  PEND
            FCB  0
PKEYTAB     FCB  $2E            ; = (and +)
            FDB  PPLUS
            FCB  $57            ; + on the keypad
            FDB  PPLUS
            FCB  $2D            ; -
            FDB  PMINUS
            FCB  $56            ; - on the keypad
            FDB  PMINUS
            FCB  $2F            ; [
            FDB  KOCTDN
            FCB  $30            ; ]
            FDB  KOCTUP
            FCB  K_DELETE
            FDB  PDEL
            FCB  K_INSERT
            FDB  PINS1
            FCB  K_TAB
            FDB  KTAB
            FCB  K_SPACE
            FDB  KSONG
            FCB  K_ENTER
            FDB  PENTER
            FCB  K_ESC
            FDB  PESC
            FCB  K_BKSP
            FDB  KHUSH
            FCB  0
PCTLTAB     FCB  K_LEFT         ; ^Left, ^Right: the instrument before, after
            FDB  KPREV
            FCB  K_RIGHT
            FDB  KNEXT
            FCB  K_UP           ; ^Up, ^Down: the order before, after
            FDB  PORDUP
            FCB  K_DOWN
            FDB  PORDDN
            FCB  K_INSERT
            FDB  PINSALL
            FCB  K_DELETE
            FDB  PDELALL
            FCB  $11            ; ^N
            FDB  NEWPAT
            FCB  $07            ; ^D
            FDB  DUPPAT
            FCB  $06            ; ^C, ^X, ^V: the block copied, cut, pasted
            FDB  PCOPY
            FCB  $1B
            FDB  PCUT
            FCB  $19
            FDB  PPASTE
            FCB  $12            ; ^O
            FDB  O_OPEN
            FCB  $16            ; ^S
            FDB  O_SAVE
            FCB  $04            ; ^A
            FDB  O_SAVEAS
            FCB  $1A            ; ^W
            FDB  O_SAVEINS
            FCB  $08            ; ^E: Record
            FDB  KREC
            FCB  $13            ; ^P: Loop pattern
            FDB  KLOOP
            FCB  $10            ; ^M: mute the track
            FDB  KMUTE
            FCB  0

; The cursor: up, down, left, right; in the grid, or among the settings.
PUP         TST  AREA
            BNE  GDN9
GUP         LDA  CROW
            BNE  GUP1
            LDA  SETF           ; from the first row, up to the settings
            JMP  PICKSET
GUP1        DECA
GMOVE       LDB  CROW           ; (A: the row it's to be on)
            STA  CROW
            TFR  B,A
            JMP  CURMOVED
PDOWN       TST  AREA
            BEQ  GDOWN
            CLR  AREA           ; from the settings, back to the grid
            LDA  SETF
            JSR  DRAWSETF
            LDA  CROW
            JMP  DRAWROW
GDOWN       LDA  CROW
            INCA
            CMPA PROWS
            BLO  GMOVE
GDN9        RTS
PPGUP       LDA  CROW
            SUBA #16
            BCC  GMOVE
            CLRA
            BRA  GMOVE
PPGDN       LDA  CROW
            ADDA #16
            CMPA PROWS
            BLO  GMOVE
PEND        LDA  PROWS
            DECA
            BRA  GMOVE
PHOME       CLRA
            BRA  GMOVE
PLEFT       TST  AREA
            BNE  SLEFT
            LDA  CCOL
            BEQ  PLF1
            DEC  CCOL
            BRA  PLF3
PLF1        LDA  CTRK           ; (from a cell's first field, the last before it)
            BEQ  GDN9
            DEC  CTRK
            LDA  #7
            STA  CCOL
PLF3        LDA  CROW
            JMP  CURMOVED
PRIGHT      TST  AREA
            BNE  SRIGHT
            LDA  CCOL
            CMPA #7
            BHS  PRT1
            INC  CCOL
            BRA  PLF3
PRT1        LDA  CTRK
            INCA
            CMPA NTL
            BHS  GDN9
            STA  CTRK
            CLR  CCOL
            BRA  PLF3
SLEFT       LDA  SETF
            BEQ  GDN9
            DECA
            BRA  PICKSET
SRIGHT      LDA  SETF
            INCA
            CMPA #NSETF
            BHS  GDN9
; PICKSET: setting A the one picked (the cursor among the settings).
PICKSET     LDB  SETF
            STA  SETF
            PSHS B
            LDB  AREA
            LDA  #1
            STA  AREA
            TSTB
            BNE  PKS1
            LDA  CROW           ; (the cursor's field not lit now)
            JSR  DRAWROW
PKS1        PULS A
            JSR  DRAWSETF
            LDA  SETF
            JMP  DRAWSETF
; PORDUP, PORDDN: the order before, after.
PORDUP      LDA  CURORD
            LBEQ GDN9
            DEC  CURORD
            BRA  PORD
PORDDN      LDA  CURORD
            INCA
            CMPA NORD
            LBHS GDN9
            STA  CURORD
PORD        JSR  PATLOAD
            JSR  PLAYJMP
            JMP  NEWVIEW
; PPLUS, PMINUS: + and -: a setting changed; in the grid, the order's pattern.
PPLUS       LDA  #1
            BRA  PPM1
PMINUS      LDA  #-1
PPM1        TST  AREA
            LBNE KSET
            JMP  KPAT
; PENTER: Enter, on the title or the author: typed again.
PENTER      TST  AREA
            LBEQ GDN9
            LDA  SETF
            CMPA #2
            LBLO KTEXT
            RTS

; PENTRY: key A typed at the cursor: in the note column a note (a piano key;
; 1: the key let go), in the others a digit (the effect's: 0-9 and A-Z).
PENTRY      TST  PATOK
            LBEQ PEN9
            LDB  CCOL
            BNE  PEDIG
            CMPA #$1E           ; 1
            BNE  PENOTE
            TST  RECORD         ; (Record off: nothing goes in)
            LBEQ PEN9
            JSR  CELLX
            LDA  #$7F
            STA  ,X
            CLR  1,X
            LBRA PEDONE
PENOTE      JSR  PIANOKEY
            LBCS PEN9
            STA  PDKEY
            STB  PDNOTE
            TST  RECORD         ; Record off: only heard
            LBEQ PAUDIT
            TST  SONGON         ; as the song plays: once a key (not as it
            BEQ  PENO2          ; repeats), its end to come as it's let go
            LDX  #TLIST
            LDB  CTRK
            LDB  B,X
            CMPB VTRK
            BNE  PENO1
            CMPA VKEY
            LBEQ PEN9
PENO1       STA  RKEY
            LDA  CTRK
            STA  RTRK
            LDA  CROW
            STA  RROW
            LDA  CURORD
            STA  RORD
PENO2       JSR  CELLX
            LDA  PDNOTE
            STA  ,X
            LDA  CURI
            STA  1,X
            JSR  PAUDIT
            BRA  PEDONE
PEDIG       JSR  KEYHEX         ; (Record or not: only the note column plays)
            LBCS PEN9
            LDB  CCOL
            CMPB #5
            BNE  PENIB
            CMPA #10            ; the effect: its character
            BLO  PEFX1
            ADDA #7
PEFX1       ADDA #'0
            PSHS A
            JSR  CELLX
            PULS A
            STA  3,X
            BRA  PEDONE
PENIB       CMPA #16
            BHS  PEN9
            STA  PNIB
            JSR  CELLX
            LDY  #CELOFS
            LDB  CCOL
            LDB  B,Y
            STB  PKIND
            ABX                 ; X: its byte
            LDA  ,X
            CMPB #2             ; (the volume: one more than it; 0: none)
            BNE  PEN1
            TSTA
            BEQ  PEN1
            DECA
PEN1        LDY  #CELHI
            LDB  CCOL
            TST  B,Y
            BEQ  PEN2
            ANDA #$0F           ; its high digit
            LDB  PNIB
            LSLB
            LSLB
            LSLB
            LSLB
            PSHS B
            ORA  ,S+
            BRA  PEN3
PEN2        ANDA #$F0           ; its low one
            ORA  PNIB
PEN3        LDB  PKIND
            CMPB #2
            BNE  PEN4
            CMPA #$3F
            BLS  PEN3A
            LDA  #$3F
PEN3A       INCA
PEN4        STA  ,X
PEDONE      JSR  EMAP           ; packed into the song; the cursor down a row
            LDA  CROW
            JSR  ROWSIZE
            JSR  PATSAVE
            LDA  CROW
            TST  SONGON         ; (as the song plays, the cursor is the song's)
            BNE  PED1
            INCA
            CMPA PROWS
            BLO  PED1
            DECA
PED1        JMP  GMOVE
PEN9        RTS
CELOFS      FCB  0,1,1,2,2,3,4,4 ; each field's byte in a cell
CELHI       FCB  0,1,0,1,0,0,1,0 ;   and whether it's the high digit
; PDEL: Delete: the field at the cursor cleared (the note and its instrument,
; the instrument, the volume, the effect and its parameter).
PDEL        TST  AREA
            BNE  PEN9
            TST  SELON          ; (a block: all of it)
            LBNE PCLEAR
            TST  PATOK
            BEQ  PEN9
            JSR  CELLX
            LDB  CCOL
            BNE  PDL1
            CLR  ,X
            CLR  1,X
            BRA  PEDONE
PDL1        CMPB #3
            BHS  PDL2
            CLR  1,X
            BRA  PEDONE
PDL2        CMPB #5
            BHS  PDL3
            CLR  2,X
            BRA  PEDONE
PDL3        CLR  3,X
            CLR  4,X
            BRA  PEDONE
; KEYHEX: key A a digit or a letter? A its value (0-9, then A-Z as 10-35),
; carry clear; carry set if not.
KEYHEX      CMPA #$27           ; 0
            BEQ  KHX0
            CMPA #$1E           ; 1-9
            BLO  KHXL
            CMPA #$26
            BHI  KHXNO
            SUBA #$1D
            BRA  KHXOK
KHX0        CLRA
            BRA  KHXOK
KHXL        CMPA #$04           ; A-Z
            BLO  KHXNO
            CMPA #$1D
            BHI  KHXNO
            ADDA #6
KHXOK       ANDCC #$FE
            RTS
KHXNO       ORCC #1
            RTS
; PAUDIT: note PDNOTE heard on the cursor's track while key PDKEY is held
; (voice 0's: PIANOUP lets it go).
PAUDIT      LDX  #TLIST
            LDB  CTRK
            LDB  B,X
            LDA  VKEY           ; voice 0's last note: the same key held (repeating),
            BEQ  PAU1           ; heard already; on another track, let go
            CMPB VTRK
            BNE  PAU0
            CMPA PDKEY
            BNE  PAU1
            RTS
PAU0        PSHS B
            LDB  VTRK
            LDA  #$7F
            CLRE
            JSR  SK_JAM
            PULS B
PAU1        STB  VTRK
            LDA  PDKEY
            STA  VKEY
            LDA  PDNOTE
            LDE  CURI
            JMP  SK_JAM

;------------------------------------------------------------------------------
; Blocks: Shift and the cursor's keys (or the mouse, dragged) select one --
; whole cells, from where it began to where the cursor is taken; ^C, ^X, ^V
; copy, cut, paste (sk_block.asm, its own overlay, has the clipboard); Delete
; clears it; Esc, or the cursor moved without Shift, lets it go. Its corners
; are kept apart from the cursor, which may go on with the song.
;------------------------------------------------------------------------------
; SELEXT: Shift and cursor key A: the cursor moved (a row up, down, 16, to the
; first or last; a track left, right), the block's far corner with it -- the
; block begun at the cursor, if there's none.
SELEXT      TST  AREA
            LBNE SX9
            TST  PATOK
            LBEQ SX9
            PSHS A
            JSR  SELSAVE
            TST  SELON
            BNE  SX1
            LDA  CROW
            STA  SELR
            LDA  CTRK
            STA  SELT
SX1         PULS A
            LDB  CROW           ; B the row it's to be on, E the track
            LDE  CTRK
            CMPA #K_UP
            BNE  SX2
            TSTB
            BEQ  SXGO
            DECB
            BRA  SXGO
SX2         CMPA #K_DOWN
            BNE  SX3
            INCB
            CMPB PROWS
            BLO  SXGO
            DECB
            BRA  SXGO
SX3         CMPA #K_PGUP
            BNE  SX4
            SUBB #16
            BCC  SXGO
            CLRB
            BRA  SXGO
SX4         CMPA #K_PGDN
            BNE  SX5
            ADDB #16
            CMPB PROWS
            BLO  SXGO
SXLAST      LDB  PROWS
            DECB
            BRA  SXGO
SX5         CMPA #K_END
            BEQ  SXLAST
            CMPA #K_HOME
            BNE  SX6
            CLRB
            BRA  SXGO
SX6         CMPA #K_LEFT
            BNE  SX7
            TSTE
            BEQ  SXGO
            DECE
            BRA  SXGO
SX7         INCE                ; (K_RIGHT)
            CMPE NTL
            BLO  SXGO
            DECE
SXGO        STB  SELR2
            STE  SELT2
; SELTO: the block to its far corner (SELR2, SELT2, after SELSAVE): the
; cursor there, and what has changed drawn again.
SELTO       LDA  #1
            STA  SELON
            JSR  SELBOX
            LDA  CROW           ; (the rows it was and is on drawn)
            LDB  SELR2
            STB  CROW
            LDB  SELT2
            STB  CTRK
            JSR  CURMOVED
            JMP  SELDIFF
SX9         RTS
; SELSAVE: the block as it is drawn now kept (OBON, OB*), for SELDIFF.
SELSAVE     LDA  SELON
            STA  OBON
            LDD  SBR0
            STD  OBR0
            LDD  SBT0
            STD  OBT0
            RTS
; SELOFF: no block (any there was, its rows drawn again without it).
SELOFF      TST  SELON
            BEQ  SX9
            BSR  SELSAVE
            CLR  SELON
; SELDIFF: the rows that look different now -- in the block before (SELSAVE)
; or in it now, not both; or in both, if its tracks have changed -- drawn
; again: those shown at once, the others queued (as DRAWGRID does).
SELDIFF     CLR  SDQ
            CLR  SDR
SD1         LDA  SDR
            CMPA PROWS
            BHS  SD8
            CLRB                ; B: 1 in it before, 2 now
            TST  OBON
            BEQ  SD2
            CMPA OBR0
            BLO  SD2
            CMPA OBR1
            BHI  SD2
            INCB
SD2         TST  SELON
            BEQ  SD3
            CMPA SBR0
            BLO  SD3
            CMPA SBR1
            BHI  SD3
            ADDB #2
SD3         TSTB
            BEQ  SD7
            CMPB #3
            BNE  SD4
            LDB  OBT0
            CMPB SBT0
            BNE  SD4
            LDB  OBT1
            CMPB SBT1
            BEQ  SD7
SD4         SUBA TOPROW         ; shown?
            ANDA #MAXROWS-1
            CMPA #GROWS
            BHS  SD6
            LDA  SDR
            JSR  DRAWROW
            BRA  SD7
SD6         INC  SDQ
SD7         INC  SDR
            BRA  SD1
SD8         TST  SDQ
            BEQ  SD9
            LDA  TOPROW
            ADDA #GROWS
            ANDA #MAXROWS-1
            STA  RQR
            LDA  #MAXROWS-GROWS
            STA  RQN
SD9         RTS
; PESC: Esc: a block let go; with none, back to the shell (KQUIT).
PESC        TST  SELON
            LBEQ KQUIT
            LBRA SELOFF
; PCOPY (^C): the block (or the cursor's cell) into the clipboard.
PCOPY       TST  AREA
            BNE  PBK9
            TST  PATOK
            BEQ  PBK9
            JSR  SELBOX
            CLRA
            JMP  O_BCOPY
; PCUT (^X): the same, then cleared.
PCUT        BSR  PBKOK
            BCS  PBK9
            JSR  SELBOX
            LDA  #1
            JSR  O_BCOPY
            JSR  O_BCLEAR
            BRA  PBKDONE
; PCLEAR (Delete, with a block): the block cleared.
PCLEAR      BSR  PBKOK
            BCS  PBK9
            JSR  SELBOX
            JSR  O_BCLEAR
            BRA  PBKDONE
; PPASTE (^V): the clipboard into the pattern at the cursor (the block, then,
; what it went into).
PPASTE      BSR  PBKOK
            BCS  PBK9
            JSR  O_BPASTE
            BCS  PBK9
PBKDONE     JSR  ROWSALL        ; packed into the song
            JSR  PATSAVE
            JMP  DRAWGRID
; PBKOK: may the pattern be changed (the grid's, and one edited here)? Carry
; set if not. (Record off too: a block's change is asked for, not played along.)
PBKOK       TST  AREA
            BNE  PBKNO
            TST  PATOK
            BNE  PBKYES
PBKNO       ORCC #1
            RTS
PBKYES      ANDCC #$FE
            RTS
PBK9        RTS

; PINS1, PINSALL: Insert, ^Insert: a blank row at the cursor, those below it
; down one (the pattern's last lost) -- in the cursor's track, or in all.
PINS1       CLRA
            BRA  ROWINS
PINSALL     LDA  #1
ROWINS      STA  PALL
            TST  PATOK
            BEQ  RWI9
            JSR  EMAP
            BSR  TRKOFS
            STB  PKN
            LDA  PROWS
            DECA
            STA  PKROW
RWI1        LDA  PKROW
            CMPA CROW
            BLS  RWI2
            DECA
            JSR  PROWA          ; the row above into this one
            LEAY ROWB,X
            BSR  ROWCOPY
            DEC  PKROW
            BRA  RWI1
RWI2        LDA  CROW
            JSR  PROWA
            BSR  ROWCLR
            BRA  ROWDONE
; PDELALL: ^Delete (and ROWDEL with A 0, Shift+Delete): the row at the cursor
; out, those below it up one -- in all the tracks, or in the cursor's.
PDELALL     LDA  #1
ROWDEL      STA  PALL
            TST  PATOK
            BEQ  RWI9
            JSR  EMAP
            BSR  TRKOFS
            STB  PKN
            LDA  CROW
            STA  PKROW
RWD1        LDA  PKROW
            INCA
            CMPA PROWS
            BHS  RWD2
            JSR  PROWA          ; the row below into this one
            LEAY -ROWB,X
            BSR  ROWCOPY
            INC  PKROW
            BRA  RWD1
RWD2        LDA  PKROW
            JSR  PROWA
            BSR  ROWCLR
ROWDONE     JSR  ROWSALL
            JSR  PATSAVE
            JMP  DRAWGRID
RWI9        RTS
; TRKOFS: B, where the cursor's track's cell is in a row.
TRKOFS      LDX  #TLIST
            LDB  CTRK
            LDA  B,X
            LDB  #5
            MUL
            RTS
; ROWCOPY: X's row into Y's -- all of it (PALL), or the cell PKN in.
ROWCOPY     LDW  #ROWB
            TST  PALL
            BNE  RCP1
            LDB  PKN
            ABX
            LEAY B,Y
            LDW  #5
RCP1        TFM  X+,Y+
            RTS
; ROWCLR: X's row blank -- all of it, or the cell PKN in.
ROWCLR      LDW  #ROWB
            TST  PALL
            BNE  RCL1
            LDB  PKN
            ABX
            LDW  #5
RCL1        CLR  PTMP
            LDY  #PTMP
            TFM  Y,X+
            RTS

;------------------------------------------------------------------------------
; The song's settings.
;------------------------------------------------------------------------------
; KSET: A +1 or -1: the setting picked (SETF) changed by it.
KSET        STA  FTSTEP
            LDB  SETF
            CMPB #2
            LBLO KTEXT          ; the title, the author: typed again
            JSR  MAP0
            CMPB #2
            BNE  KST3
            LDA  WINDOW+8       ; ticks a row: 1-31
            ADDA FTSTEP
            LBEQ KST9
            CMPA #31
            LBHI KST9
            STA  WINDOW+8
            TST  SONGON
            LBEQ KSTOK
            STA  SK_SPEED
            LBRA KSTOK
KST3        CMPB #3
            BNE  KST4
            LDA  WINDOW+7       ; ticks a second: 32-255
            ADDA FTSTEP
            CMPA #32
            LBLO KST9
            STA  WINDOW+7
            TST  SONGON
            BEQ  KSTOK
            JSR  SKRATE
            BRA  KSTOK
KST4        CMPB #4
            BNE  KST5
            TST  PATOK          ; this pattern's rows: 1-128
            BEQ  KST9
            LDA  PROWS
            ADDA FTSTEP
            BEQ  KST9
            CMPA #MAXROWS
            BHI  KST9
            STA  PROWS
            JSR  PATSAVE
            JSR  NEWVIEW
            BRA  KSTOK
KST5        CMPB #5
            BNE  KST6
            LDA  WINDOW+12      ; the loop: none, or an order
            LDB  FTSTEP
            BMI  KST5M
            INCA
            CMPA NORD
            BHS  KST9
            BRA  KST5S
KST5M       CMPA #$FF
            BEQ  KST9
            DECA
KST5S       STA  WINDOW+12
            STA  SK_HDR+12      ; (the player's too, if it's playing)
            JSR  DRAWORDS
            BRA  KSTOK
KST6        JSR  SONGOFF        ; rhythm mode, a 4-op pair: the tracks change
            JSR  MAP0           ; (the song stopped first)
            LDB  SETF
            CMPB #6
            BNE  KST7
            LDA  WINDOW+4
            EORA #1
            STA  WINDOW+4
            BRA  KST8
KST7        SUBB #7
            LDX  #SKBITS
            LDA  B,X
            EORA WINDOW+5
            STA  WINDOW+5
KST8        JSR  TABLES
            JSR  MKTLIST
            JSR  JAMSET
            JSR  MARK
            JMP  DRAWPAT
KSTOK       JSR  MARK
            LDA  SETF
            JMP  DRAWSETF
KST9        RTS
; KTEXT: the title or the author (SETF 0, 1) typed again.
KTEXT       JSR  MAP0
            LDX  #WINDOW+16
            LDY  #S_ASKTITLE
            TST  SETF
            BEQ  KTX1
            LDX  #WINDOW+48
            LDY  #S_ASKBY
KTX1        PSHS Y
            LDY  #HBUF          ; (with a 0 after it)
            LDW  #32
            TFM  X+,Y+
            CLR  ,Y
            PULS X
            LDY  #HBUF
            LDA  #2
            JSR  PRSTART
            LDX  #KTEXT2
            JSR  SETPRDO        ; (PR_DO, in this overlay)
            LDA  #1
            STA  MODE
            RTS
KTEXT2      JSR  MAP0
            LDY  #WINDOW+16
            TST  SETF
            BEQ  KTX2
            LDY  #WINDOW+48
KTX2        LDX  #PR_BUF        ; (0s after it)
            LDB  #32
KTX3        LDA  ,X+
            STA  ,Y+
            BEQ  KTX4
            DECB
            BNE  KTX3
            BRA  KTX5
KTX4        DECB
            BEQ  KTX5
            CLR  ,Y+
            BRA  KTX4
KTX5        JSR  CLRMSG
            JSR  MARK
            LDA  SETF
            JMP  DRAWSETF

;------------------------------------------------------------------------------
; The mouse: a click picks a cell, an order or a setting (the title, the
; author: typed again); the wheel over a setting changes it, over the grid
; moves the cursor.
;------------------------------------------------------------------------------
PMOUSE      LDD  MOUSEY
            LSRD
            LSRD
            LSRD
            LSRD
            STB  MROW
            LDD  MOUSEX
            LSRD
            LSRD
            LSRD
            STB  MCOL
            LDA  PRESSED
            BITA #VC_MB_LEFT
            BEQ  PMS4
            JSR  PMCLICK
PMS4        LDA  BUTTONS        ; held (from a click on a cell): a block dragged
            BITA #VC_MB_LEFT
            BNE  PMS4A
            CLR  DRAG
            BRA  PMS5
PMS4A       TST  DRAG
            BEQ  PMS5
            JSR  PMDRAG
PMS5        LDA  WHEEL
            BEQ  PMS9
            LDB  MROW
            CMPB #3
            BHS  PMS6
            JSR  SFHIT
            BCS  PMS9
            CMPA #2             ; (not the title, the author)
            BLO  PMS9
            JSR  PICKSET
            LDA  #1
            TST  WHEEL
            BPL  PMS5A
            LDA  #-1
PMS5A       JMP  KSET
PMS6        CMPB #GY0
            BLO  PMS9
            CLR  AREA
            JSR  SELOFF
            TST  WHEEL
            LBPL GUP
            JMP  GDOWN
PMS9        RTS
PMCLICK     LDB  MROW
            CMPB #29
            LBEQ PMSTAT
            CMPB #3
            LBEQ PMORD
            LBLO PMSET
            CMPB #GY0-1
            LBEQ PMHEAD
            JSR  MGRID          ; a cell: the cursor on it (the block let go), and a
            LBCS PMC9           ; block begun there, if the mouse is dragged
            JSR  SELOFF
            JSR  MGRID
            STB  CTRK
            STB  SELT
            STB  SELT2
            STA  CCOL
            LDA  #1
            STA  DRAG
            TST  AREA           ; (from the settings: the one picked not lit now)
            BEQ  PMC1
            CLR  AREA
            LDA  SETF
            JSR  DRAWSETF
PMC1        LDA  CROW
            LDB  PTMP
            STB  CROW
            STB  SELR
            STB  SELR2
            JMP  CURMOVED
; MGRID: the cell under the mouse: carry clear, PTMP its row, B its track (of
; TLIST), A its field; carry set if it isn't over one.
MGRID       LDB  MROW
            SUBB #GY0
            BLO  MGNO
            CMPB #GROWS
            BHS  MGNO
            ADDB TOPROW
            ANDB #MAXROWS-1
            CMPB PROWS
            BHS  MGNO
            STB  PTMP           ; the row
            LDB  MCOL
            SUBB #GX0
            BLO  MGNO
            CLRA
            DIVD #GTW           ; B the track shown, A where in its cell
            CMPB #GTRKS
            BHS  MGNO
            ADDB LTRK
            CMPB NTL
            BHS  MGNO
            LDX  #COLFLD
            LDA  A,X
            ANDCC #$FE
            RTS
MGNO        ORCC #1
            RTS
; PMDRAG: the mouse held from a click on a cell: over another, the block from
; that one to this (the cursor here).
PMDRAG      BSR  MGRID
            BCS  PMD9
            CMPB SELT2
            BNE  PMD1
            LDA  PTMP
            CMPA SELR2
            BEQ  PMD9
PMD1        PSHS B
            JSR  SELSAVE
            PULS B
            STB  SELT2
            LDA  PTMP
            STA  SELR2
            JMP  SELTO
PMD9        RTS
PMORD       LDB  MCOL
            SUBB #9
            BLO  PMC9
            CLRA
            DIVD #3
            ADDB OTOP
            BCS  PMC9
            CMPB NORD
            BHS  PMC9
            STB  CURORD
            JMP  PORD
PMSTAT      TST  MSGUP          ; the status line's boxes (not a message)
            BNE  PMC9
            LDB  MCOL
            CMPB #44
            BLO  PMC9
            CMPB #54
            LBLO KREC
            CMPB #55
            BLO  PMC9
            CMPB #71
            LBLO KLOOP
            RTS
PMHEAD      LDB  MCOL           ; a track's head: muted, or not
            SUBB #GX0
            BLO  PMC9
            CLRA
            DIVD #GTW
            CMPB #GTRKS
            BHS  PMC9
            ADDB LTRK
            CMPB NTL
            BHS  PMC9
            LDX  #TLIST
            LDA  B,X
            JMP  TOGMUTE
PMSET       BSR  SFHIT
            BCS  PMC9
            JSR  PICKSET
            LDA  SETF
            CMPA #2
            LBLO KTEXT
PMC9        RTS
COLFLD      FCB  0,0,0,0,1,2,2,3,4,4,5,6,7,7 ; a cell's columns: their fields
; SFHIT: the setting under the mouse: A, carry clear (carry set: none).
SFHIT       LDX  #SETTAB
            CLRA
SFH1        LDB  1,X
            CMPB MROW
            BNE  SFH2
            LDB  MCOL
            SUBB ,X
            BLO  SFH2
            CMPB 2,X
            BHS  SFH2
            ANDCC #$FE
            RTS
SFH2        LEAX 3,X
            INCA
            CMPA #NSETF
            BLO  SFH1
            ORCC #1
            RTS

;------------------------------------------------------------------------------
; The page's words.
;------------------------------------------------------------------------------
SETTAB      FCB  8,1,32         ; each setting: its column, row and width --
            FCB  46,1,32        ;   the title, the author,
            FCB  8,2,2          ;   ticks a row, ticks a second,
            FCB  17,2,3
            FCB  27,2,3         ;   this pattern's rows, the loop,
            FCB  37,2,4
            FCB  50,2,3         ;   rhythm mode,
            FCB  60,2,2         ;   and the 4-op pairs: 0+3 1+4 2+5, in each
            FCB  63,2,2         ;   array
            FCB  66,2,2
            FCB  69,2,2
            FCB  72,2,2
            FCB  75,2,2
S_PAIRS     FCC  "0 1 2 9 1011"
PLABELS     FCB  2,1,C_LABEL
            FCC  "Title"
            FCB  0
            FCB  43,1,C_LABEL
            FCC  "By"
            FCB  0
            FCB  2,2,C_LABEL
            FCC  "Speed"
            FCB  0
            FCB  12,2,C_LABEL
            FCC  "Rate"
            FCB  0
            FCB  22,2,C_LABEL
            FCC  "Rows"
            FCB  0
            FCB  32,2,C_LABEL
            FCC  "Loop"
            FCB  0
            FCB  43,2,C_LABEL
            FCC  "Rhythm"
            FCB  0
            FCB  55,2,C_LABEL
            FCC  "4-op"
            FCB  0
            FCB  2,3,C_LABEL
            FCC  "Orders"
            FCB  0
            FCB  $FF,$FF
S_KINDS     FCB  0,0,0,0,0,0,0,0 ; (8 apart: a 2-op channel, the drums, 4-op)
            FCC  " bass"
            FCB  0,0,0
            FCC  " snare"
            FCB  0,0
            FCC  " tom"
            FCB  0,0,0,0
            FCC  " cymbal"
            FCB  0
            FCC  " hi-hat"
            FCB  0
            FCC  " 4-op"
            FCB  0,0,0
S_NONE      FCC  "none"
            FCB  0
S_POCT      FCC  "Oct "
            FCB  0
S_INSTR     FCC  "  Inst "
            FCB  0
S_PATT      FCC  "Pat "
            FCB  0
S_REC       FCC  "Record"
            FCB  0
S_LOOP      FCC  "Loop pattern"
            FCB  0
S_NOPAT     FCC  "There's no such pattern: + - pick one."
            FCB  0
S_LONGPAT   FCC  "More than 128 rows: SONGKIT plays it, but doesn't edit it."
            FCB  0
S_NOROOM    FCC  "No room for that"
            FCB  0
S_ASKTITLE  FCC  "The song's title: "
            FCB  0
S_ASKBY     FCC  "Its author: "
            FCB  0
;------------------------------------------------------------------------------
; End of sk_pat.asm
;------------------------------------------------------------------------------
