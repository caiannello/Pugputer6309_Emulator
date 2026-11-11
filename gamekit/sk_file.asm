;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 game kit
;    FILE: sk_file.asm
;
; SONGKIT's files. The song is kept as its file is, in RAM pages of its own
; (PAGES, seen through bank 1), where the player plays it and the pattern page
; edits it (sk_pat.asm); its instruments and their names are in INST and the
; names' page (NMPG), to edit. Saving writes the file again with the
; instruments as they are now (their names after the patterns, where the
; header's bytes 13-15 say), the patterns moved along as the instruments
; before them grow or shrink.
;
; An instrument's own file (.INS): "PSI1", its 32 bytes, its name (16).
;
;   NEWSONG    a new song: one empty pattern, one instrument
;   OPEN       ^O: a song, or an instrument (.INS) into the one being edited
;   OPENNAMED  the same, the name in PR_BUF
;   SAVE       ^S, SAVEAS ^A: the song; SAVEINS ^W: the instrument
;   FREEPG     the song's pages given back, bank 1 its own again
;------------------------------------------------------------------------------
INSLEN      equ  52         ; an .INS file

; NEWSONG: carry set if there's no page for it.
NEWSONG     JSR  FREEPG
            LDA  #B_PAGE_ALLOC
            SWI2
            BCS  NS9
            STA  PAGES
            LDA  #1
            STA  NPG
            JSR  MAP0
            LDX  #WINDOW        ; header, order, pattern table, instrument,
            LDB  #128           ; pattern: 119 bytes
NS1         CLR  ,X+
            DECB
            BNE  NS1
            LDX  #NEWHDR
            LDY  #WINDOW
            LDW  #13
            TFM  X+,Y+
            LDA  #64            ; pattern 0: 64 rows, at 117
            STA  WINDOW+81
            LDA  #117
            STA  WINDOW+84
            LDX  #DEFINST
            LDY  #WINDOW+85
            LDW  #SK_ILEN
            TFM  X+,Y+
            LDD  #$1E3F         ; an empty row, and 63 more
            STD  WINDOW+117
            CLR  SSIZE
            LDD  #119
            STD  SSIZE+1
            JSR  PARSE
            JSR  NMAP
            LDX  #DEFNAME
            LDY  #WINDOW
            LDW  #16
            TFM  X+,Y+
            CLR  SONGNAME
            CLR  CHANGED
            LDA  #1
            STA  CURI
            JSR  SETIP
            ANDCC #$FE
NS9         RTS
NEWHDR      FCC  "PSG1"
            FCB  0,0,0,60,6,1,1,1,0 ; (it loops)

;------------------------------------------------------------------------------
; Opening.
;------------------------------------------------------------------------------
OPEN        JSR  SONGOFF
            LDX  #S_ASKOPEN
            LDY  #0
            LDA  #1
            JSR  PRSTART
            LDX  #OPENNAMED
            STX  PR_DO
            LDA  #1
            STA  MODE
            RTS
; OPENNAMED: PR_BUF's name: an instrument (.INS), or a song (.SNG the default).
OPENNAMED   JSR  SONGOFF
            LDX  #PR_BUF
            LDY  #FNAME
            JSR  STRCPY
            JSR  ISINS
            LBEQ LOADINS
            LDX  #FNAME
            LDY  #S_SNG
            JSR  DEFEXT
            TST  CHANGED
            BEQ  OPENSNG
            LDX  #OPENSNG
            LDY  #S_ASKOPEN2
            JMP  ASK
; OPENSNG: the song FNAME, into pages of its own; if it is one, SONGKIT's.
OPENSNG     JSR  SONGOFF
            JSR  LOADF
            LBCS FERR
            JSR  VALID          ; (the new pages' first in the window)
            BCC  OS1
            JSR  FREENEW
            JSR  MAP0           ; (the song's own tables again)
            JSR  TABLES
            LDX  #FNAME
            JSR  MSG
            LDX  #S_NOTSONG
            JMP  TXSTR
OS1         JSR  FREEPG         ; the old song's pages given back, the new ones its
            LDX  #NEWPG
            LDY  #PAGES
            LDW  #MAXPG
            TFM  X+,Y+
            LDA  NNPG
            STA  NPG
            CLR  NNPG
            LDD  SNEW
            STD  SSIZE
            LDA  SNEW+2
            STA  SSIZE+2
            JSR  PARSE
            LDX  #FNAME
            LDY  #SONGNAME
            JSR  STRCPY
            CLR  CHANGED
            LDA  #1
            STA  CURI
            JSR  SETIP
            JSR  JAMSET
            JSR  DRAWCUR
            LDX  #S_OPENED
            JSR  MSG
            LDX  #SONGNAME
            JMP  TXSTR
; LOADINS: the instrument FNAME into the one being edited.
LOADINS     LDX  #FNAME
            LDE  #FOPEN_READ
            LDA  #B_FOPEN_NAME
            SWI2
            LBCS FERR
            STA  FH
            LDB  FH
            LDX  #IOBUF
            LDY  #INSLEN
            LDA  #B_FREAD
            SWI2
            PSHS CC,A,X
            LDB  FH
            LDA  #B_FCLOSE_NAME
            SWI2
            PULS CC,A,X
            BCC  LI1
            CMPA #ERR_EOF
            LBNE FERR
            LDX  #0
LI1         CMPX #INSLEN
            BNE  LI2
            LDD  IOBUF
            CMPD #$5053         ; "PSI1"
            BNE  LI2
            LDD  IOBUF+2
            CMPD #$4931
            BNE  LI2
            LDX  #IOBUF+4
            LDY  IP
            LDW  #SK_ILEN
            TFM  X+,Y+
            LDY  NP
            LDW  #16
            TFM  X+,Y+
            CLR  ,Y
            JSR  PUTNAME
            LDA  #1
            STA  CHANGED
            JSR  JAMREF
            JSR  DRAWCUR
            LDX  #S_OPENED
            JSR  MSG
            LDX  #FNAME
            JMP  TXSTR
LI2         LDX  #FNAME
            JSR  MSG
            LDX  #S_NOTINS
            JMP  TXSTR

; LOADF: the file FNAME into new pages (NEWPG, NNPG), SNEW its size; carry set
; and A the error if it can't be.
LOADF       JSR  FREENEW
            LDX  #FNAME
            LDE  #FOPEN_READ
            LDA  #B_FOPEN_NAME
            SWI2
            BCS  LF9
            STA  FH
LF1         LDA  NNPG
            CMPA #MAXPG
            BHS  LFBIG
            LDA  #B_PAGE_ALLOC
            SWI2
            BCS  LFERR
            LDX  #NEWPG
            LDB  NNPG
            STA  B,X
            INC  NNPG
            TFR  A,E
            LDB  #WBANK
            LDA  #B_BANK_SET
            SWI2
            LDB  FH
            LDX  #WINDOW
            LDY  #$4000
            LDA  #B_FREAD
            SWI2
            BCC  LF2
            CMPA #ERR_EOF
            BNE  LFERR
            LDX  #0
LF2         CMPX #$4000
            BEQ  LF1
            STX  LFLAST         ; its size: (pages - 1) x 16384 + this one's
            LDA  NNPG
            DECA
            TFR  A,B
            LSRA
            LSRA
            STA  SNEW
            ANDB #3
            LSLB
            LSLB
            LSLB
            LSLB
            LSLB
            LSLB
            TFR  B,A
            CLRB
            ADDD LFLAST
            STD  SNEW+1
            LDB  FH
            LDA  #B_FCLOSE_NAME
            SWI2
            ANDCC #$FE
LF9         RTS
LFBIG       LDA  #ERR_TOOBIG
LFERR       PSHS A
            LDB  FH
            LDA  #B_FCLOSE_NAME
            SWI2
            JSR  FREENEW
            PULS A
            ORCC #1
            RTS
; VALID: the song in the new pages is one: carry clear.
VALID       LDB  #WBANK
            LDE  NEWPG
            LDA  #B_BANK_SET
            SWI2
            LDA  SNEW           ; 96 bytes at least
            BNE  VA1
            LDD  SNEW+1
            CMPD #96
            BLO  VABAD
VA1         LDD  WINDOW
            CMPD #$5053         ; "PSG1"
            BNE  VABAD
            LDD  WINDOW+2
            CMPD #$4731
            BNE  VABAD
            TST  WINDOW+10      ; a pattern and an order at least
            BEQ  VABAD
            TST  WINDOW+11
            BEQ  VABAD
            JSR  TABLES         ; its instruments' end in the file
            LDA  SNEW
            BNE  VA2
            LDD  DSTART
            CMPD SNEW+1
            BHI  VABAD
VA2         ANDCC #$FE
            RTS
VABAD       ORCC #1
            RTS
; TABLES: from the header in the window: NORD, NPAT, OLDNI, ITAB, DSTART.
TABLES      LDA  WINDOW+11
            STA  NORD
            LDA  WINDOW+10
            STA  NPAT
            LDA  WINDOW+9
            STA  OLDNI
            LDA  WINDOW+5
            STA  SPAIRS
            LDA  WINDOW+4
            STA  SFLAGS
            LDB  NPAT
            CLRA
            LSLD
            LSLD
            ADDD #SK_HLEN
            ADDB NORD
            ADCA #0
            STD  ITAB
            LDA  OLDNI
            LDB  #SK_ILEN
            MUL
            ADDD ITAB
            STD  DSTART
            RTS
; PARSE: the song in PAGES (SSIZE its size) SONGKIT's: its instruments and
; their names into INST and the names' page; its first order's pattern into
; the pattern buffer, to edit.
PARSE       BSR  PARSE0
            CLR  CURORD         ; its first order, row, track
            CLR  CROW
            CLR  CTRK
            CLR  CCOL
            CLR  TOPROW
            CLR  LTRK
            CLR  AREA
            CLR  OTOP
            LDD  #$FFFF
            STD  PLORD
            JSR  MKTLIST
            JMP  PATLOAD
PARSE0      JSR  MAP0
            JSR  TABLES
            LDD  WINDOW+13      ; its names, and where its patterns end
            STD  NAMEOFS
            LDA  WINDOW+15
            STA  NAMEOFS+2
            LDD  SSIZE
            STD  DEND
            LDA  SSIZE+2
            STA  DEND+2
            LDD  NAMEOFS        ; (names: the patterns end there)
            BNE  PA1
            TST  NAMEOFS+2
            BEQ  PA2
PA1         LDD  NAMEOFS
            STD  DEND
            LDA  NAMEOFS+2
            STA  DEND+2
PA2         JSR  NMAP           ; no names yet
            LDX  #WINDOW
            LDW  #MAXINST*16
            CLR  PTMP
            LDY  #PTMP
            TFM  Y,X+
            JSR  MAP0
            LDA  OLDNI          ; the instruments
            STA  NINST
            BNE  PA4
            LDA  #1             ; (none: the first one a new song has)
            STA  NINST
            LDX  #DEFINST
            LDY  #INST
            LDW  #SK_ILEN
            TFM  X+,Y+
            RTS
PA4         LDX  #WINDOW
            LDD  ITAB
            LEAX D,X
            LDY  #INST
            LDA  OLDNI
            LDB  #SK_ILEN
            MUL
            TFR  D,W
            TFM  X+,Y+
            LDD  NAMEOFS        ; their names, if it has them
            BNE  PA5
            TST  NAMEOFS+2
            BEQ  PA9
PA5         LDA  NAMEOFS
            LDX  NAMEOFS+1
            JSR  RSEEK
            CLR  PNI
PA6         LDA  PNI            ; each, by way of NAMETMP
            CMPA OLDNI
            BHS  PA9
            LDY  #NAMETMP
            LDB  #16
PA7         JSR  RGETB
            STA  ,Y+
            DECB
            BNE  PA7
            JSR  NMAP
            LDA  PNI
            LDB  #16
            MUL
            ADDD #WINDOW
            TFR  D,Y
            LDX  #NAMETMP
            LDW  #16
            TFM  X+,Y+
            LDB  RPG            ; (back to reading)
            JSR  MAPPG
            INC  PNI
            BRA  PA6
PA9         RTS

;------------------------------------------------------------------------------
; Saving.
;------------------------------------------------------------------------------
SAVE        TST  SONGNAME
            BEQ  SAVEAS
            LDX  #SONGNAME
            LDY  #FNAME
            JSR  STRCPY
            JMP  SAVESNG
SAVEAS      JSR  SONGOFF
            LDX  #S_ASKSAVE
            LDY  #SONGNAME
            LDA  #1
            JSR  PRSTART
            LDX  #SAVEAS2
            STX  PR_DO
            LDA  #1
            STA  MODE
            RTS
SAVEAS2     LDX  #PR_BUF
            LDY  #FNAME
            JSR  STRCPY
            LDX  #FNAME
            LDY  #S_SNG
            JSR  DEFEXT
            JSR  SAVESNG
            BCS  SA9
            LDX  #FNAME
            LDY  #SONGNAME
            JSR  STRCPY
            JMP  DRAWTITLE
SA9         RTS
; SAVESNG: the song as FNAME. Carry set if it couldn't be.
SAVESNG     JSR  SONGOFF
            LDX  #FNAME
            LDE  #FOPEN_WRITE
            LDA  #B_FOPEN_NAME
            SWI2
            LBCS FERR
            STA  FH
            LDA  NINST          ; DELTA: how much further on the patterns are
            LDB  #SK_ILEN
            MUL
            STD  DELTA
            LDA  OLDNI
            LDB  #SK_ILEN
            MUL
            STD  SPLEN
            LDD  DELTA
            SUBD SPLEN
            STD  DELTA
            JSR  MAP0           ; the header: the instruments, where the names go
            LDX  #WINDOW
            LDY  #HBUF
            LDW  #SK_HLEN
            TFM  X+,Y+
            LDA  NINST
            STA  HBUF+9
            LDD  DEND+1
            ADDD DELTA
            STD  HBUF+14
            LDA  DEND
            ADCA #0
            TST  DELTA          ; (a negative DELTA: its high byte too)
            BPL  SV1
            DECA
SV1         STA  HBUF+13
            LDX  #HBUF
            LDY  #SK_HLEN
            JSR  FWRITE
            LBCS SVERR
            LDX  #WINDOW+SK_HLEN ; the orders
            LDB  NORD
            CLRA
            TFR  D,Y
            JSR  FWRITE
            LBCS SVERR
            LDX  #WINDOW+SK_HLEN ; the pattern table, each pattern DELTA on
            LDB  NORD
            ABX
            LDY  #IOBUF
            LDE  NPAT
SV2         LDA  ,X+
            STA  ,Y+
            LDA  ,X+
            STA  SPFROM
            LDD  ,X++
            ADDD DELTA
            STD  1,Y
            LDA  SPFROM
            ADCA #0
            TST  DELTA
            BPL  SV3
            DECA
SV3         STA  ,Y
            LEAY 3,Y
            DECE
            BNE  SV2
            LDX  #IOBUF
            LDB  NPAT
            CLRA
            LSLD
            LSLD
            TFR  D,Y
            JSR  FWRITE
            LBCS SVERR
            LDX  #INST          ; the instruments
            LDA  NINST
            LDB  #SK_ILEN
            MUL
            TFR  D,Y
            JSR  FWRITE
            LBCS SVERR
            CLR  SPFROM         ; the patterns, as they are
            LDD  DSTART
            STD  SPFROM+1
            LDD  DEND
            STD  SPTO
            LDA  DEND+2
            STA  SPTO+2
            JSR  WRSPAN
            LBCS SVERR
            JSR  NMAP           ; the names
            LDX  #WINDOW
            LDA  NINST
            LDB  #16
            MUL
            TFR  D,Y
            JSR  FWRITE
            LBCS SVERR
            LDB  FH
            LDA  #B_FCLOSE_NAME
            SWI2
            LBCS FERR
            CLR  CHANGED
            JSR  DRAWTITLE
            LDX  #S_SAVED
            JSR  MSG
            LDX  #FNAME
            JSR  TXSTR
            ANDCC #$FE
            RTS
SVERR       PSHS A
            LDB  FH
            LDA  #B_FCLOSE_NAME
            SWI2
            PULS A
            JSR  FERR
            ORCC #1
            RTS
; SAVEINS: the instrument being edited, as a file of its own.
SAVEINS     LDX  #S_ASKINS
            LDY  #0
            LDA  #1
            JSR  PRSTART
            LDX  #SAVEINS2
            STX  PR_DO
            LDA  #1
            STA  MODE
            RTS
SAVEINS2    LDX  #PR_BUF
            LDY  #FNAME
            JSR  STRCPY
            LDX  #FNAME
            LDY  #S_INS
            JSR  DEFEXT
            LDD  #$5053         ; "PSI1", the instrument, its name
            STD  IOBUF
            LDD  #$4931
            STD  IOBUF+2
            LDX  IP
            LDY  #IOBUF+4
            LDW  #SK_ILEN
            TFM  X+,Y+
            LDX  NP
            LDW  #16
            TFM  X+,Y+
            LDX  #FNAME
            LDE  #FOPEN_WRITE
            LDA  #B_FOPEN_NAME
            SWI2
            LBCS FERR
            STA  FH
            LDX  #IOBUF
            LDY  #INSLEN
            JSR  FWRITE
            LBCS SVERR
            LDB  FH
            LDA  #B_FCLOSE_NAME
            SWI2
            LBCS FERR
            LDX  #S_SAVED
            JSR  MSG
            LDX  #FNAME
            JMP  TXSTR
; FWRITE: Y bytes from X to the file FH. Carry set (A the error) if not.
FWRITE      CMPY #0
            BEQ  FW9
            LDB  FH
            LDA  #B_FWRITE
            SWI2
            RTS
FW9         ANDCC #$FE
            RTS
; WRSPAN: the song's bytes from SPFROM up to SPTO (24 bits) to the file FH,
; from the pages a part of one at a time.
WRSPAN      LDD  SPTO+1         ; what is left
            SUBD SPFROM+1
            STD  SPREM+1
            LDA  SPTO
            SBCA SPFROM
            STA  SPREM
            BMI  WS9            ; (none, or less)
            BNE  WS1
            LDD  SPREM+1
            BEQ  WS9
WS1         LDD  SPFROM+1       ; where in its page
            ANDA #$3F
            STD  RPTR
            LDD  #$4000         ; to the page's end, or less
            SUBD RPTR
            TST  SPREM
            BNE  WS2
            CMPD SPREM+1
            BLS  WS2
            LDD  SPREM+1
WS2         STD  SPLEN
            LDA  SPFROM+1       ; its page
            LSRA
            LSRA
            LSRA
            LSRA
            LSRA
            LSRA
            LDB  SPFROM
            LSLB
            LSLB
            STA  RPG
            ORB  RPG
            JSR  MAPPG
            LDD  RPTR
            ADDD #WINDOW
            TFR  D,X
            LDY  SPLEN
            JSR  FWRITE
            BCS  WS8
            LDD  SPFROM+1
            ADDD SPLEN
            STD  SPFROM+1
            LDA  SPFROM
            ADCA #0
            STA  SPFROM
            BRA  WRSPAN
WS9         ANDCC #$FE
WS8         RTS

;------------------------------------------------------------------------------
; The pages.
;------------------------------------------------------------------------------
; MAP0, MAPPG: the song's page 0, or B, into the window. (All kept.)
MAP0        PSHS B
            CLRB
            BSR  MAPPG
            PULS B,PC
MAPPG       PSHS D,X
            PSHSW
            STB  RPG            ; (past the last: the last shown, RPG as asked)
            CMPB NPG
            BLO  MP1
            LDB  NPG
            DECB
MP1         LDX  #PAGES
            LDE  B,X
            LDB  #WBANK
            LDA  #B_BANK_SET
            SWI2
            PULSW
            PULS D,X,PC
; RSEEK: to A:X in the song's bytes; RGETB: A, the next byte. (The rest kept.)
RSEEK       PSHS D,X
            TFR  X,D
            ANDA #$3F
            ADDD #WINDOW
            STD  RPTR
            LDA  2,S
            LSRA
            LSRA
            LSRA
            LSRA
            LSRA
            LSRA
            LDB  ,S
            LSLB
            LSLB
            STA  RPG
            ORB  RPG
            BSR  MAPPG
            PULS D,X,PC
RGETB       PSHS X
            LDX  RPTR
            LDA  ,X+
            CMPX #WINDOW+$4000
            BNE  RG1
            PSHS B
            LDB  RPG
            INCB
            BSR  MAPPG
            PULS B
            LDX  #WINDOW
RG1         STX  RPTR
            PULS X,PC
; FREEPG: the song's pages given back; FREENEW: a new song's that wasn't one.
FREEPG      LDB  #WBANK
            LDE  WHOME
            LDA  #B_BANK_SET
            SWI2
FP1         TST  NPG
            BEQ  FP9
            DEC  NPG
            LDX  #PAGES
            LDB  NPG
            LDB  B,X
            LDA  #B_PAGE_FREE
            SWI2
            BRA  FP1
FP9         RTS
FREENEW     LDB  #WBANK
            LDE  WHOME
            LDA  #B_BANK_SET
            SWI2
FN1         TST  NNPG
            BEQ  FP9
            DEC  NNPG
            LDX  #NEWPG
            LDB  NNPG
            LDB  B,X
            LDA  #B_PAGE_FREE
            SWI2
            BRA  FN1
; SONGOFF: the song stopped, if it was playing (the window is wanted).
SONGOFF     TST  SONGON
            BEQ  SO9
            JSR  SK_STOP
            CLR  SONGON
            JSR  JAMSET
            JSR  DRAWSTAT
SO9         RTS

;------------------------------------------------------------------------------
; Names.
;------------------------------------------------------------------------------
; STRCPY: the string at X to Y (with its 0).
STRCPY      LDA  ,X+
            STA  ,Y+
            BNE  STRCPY
            RTS
; DEFEXT: the extension at Y on the end of the name at X, if its last part
; has none.
DEFEXT      CLRB                ; (B: a dot since the last /)
DE1         LDA  ,X+
            BEQ  DE3
            CMPA #'.
            BNE  DE2
            INCB
DE2         CMPA #'/
            BNE  DE1
            CLRB
            BRA  DE1
DE3         TSTB
            BNE  DE9
            LEAX -1,X
DE4         LDA  ,Y+
            STA  ,X+
            BNE  DE4
DE9         RTS
; ISINS: FNAME ends in ".INS"? (Z set if so.)
ISINS       LDX  #FNAME
IS1         LDA  ,X+
            BNE  IS1
            LDD  -5,X
            CMPD #$2E49         ; ".I"
            BNE  IS9
            LDD  -3,X
            CMPD #$4E53         ; "NS"
IS9         RTS
; FERR: "FNAME: what went wrong" (A the error).
FERR        PSHS A
            LDX  #FNAME
            JSR  MSG
            LDX  #S_COLON
            JSR  TXSTR
            PULS A
            LDX  #ERRMSGS
FE1         LDB  ,X+
            BEQ  FE3
            CMPA -1,X
            BEQ  FE4
FE2         TST  ,X+
            BNE  FE2
            BRA  FE1
FE3         LDX  #S_DISKERR
FE4         JSR  TXSTR
            ORCC #1
            RTS
ERRMSGS     FCB  ERR_NOTFOUND
            FCC  "File not found"
            FCB  0
            FCB  ERR_ISDIR
            FCC  "Is a directory"
            FCB  0
            FCB  ERR_NOTDIR
            FCC  "Not a directory"
            FCB  0
            FCB  ERR_BADPATH
            FCC  "Bad name or path"
            FCB  0
            FCB  ERR_NOSPACE
            FCC  "The disk is full"
            FCB  0
            FCB  ERR_TOOBIG
            FCC  "Too big"
            FCB  0
            FCB  0
S_DISKERR   FCC  "Disk error"
            FCB  0
S_COLON     FCC  ": "
            FCB  0
S_SNG       FCC  ".SNG"
            FCB  0
S_INS       FCC  ".INS"
            FCB  0
S_ASKOPEN   FCC  "Open (a song, or an instrument .INS): "
            FCB  0
S_ASKOPEN2  FCC  "Changes not saved: open it anyway? (Y or N)"
            FCB  0
S_ASKSAVE   FCC  "Save the song as: "
            FCB  0
S_ASKINS    FCC  "Save the instrument as (.INS): "
            FCB  0
S_OPENED    FCC  "Opened "
            FCB  0
S_SAVED     FCC  "Saved "
            FCB  0
S_NOTSONG   FCC  ": not a SONGKIT song"
            FCB  0
S_NOTINS    FCC  ": not a SONGKIT instrument"
            FCB  0
;------------------------------------------------------------------------------
; End of sk_file.asm
;------------------------------------------------------------------------------
