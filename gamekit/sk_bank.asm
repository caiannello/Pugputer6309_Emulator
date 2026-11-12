;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 game kit
;    FILE: sk_bank.asm
;
; SONGKIT's bank page (^B, from either of the others), an overlay of its own
; (OV_BANK): instrument banks on the disk -- WOPL files (gamekit/README.md) --
; to take instruments from. On the left, a folder's bank files (.WOP) and its
; folders; beside them, the 128 instruments of the bank being looked at; on the
; right, the one at the cursor, and the song's instrument being edited.
;
; The keys play the one at the cursor, so it can be heard before it is taken:
; it is made SONGKIT's (BKCONV) and put after the song's instruments, one more
; for the player (BKJAM). Enter adds it to the song; ^R puts it over the song's
; instrument being edited. Each one taken keeps where it came from (its
; source: SRCAT). ^P puts the song's instrument into the bank, at the cursor --
; a bank of one's own, made with ^N.
;
; The bank looked at is kept after this code, in the overlay's page (BKDATA),
; and the folder's list (BKFILES): only addresses, not in SONGKIT.COM.
;
;   BKOPEN     ^B: the bank page (the first time, /BANKS listed -- or the
;              shell's folder if there is none)
;   BKDRAW     the whole page
;   BKEY       a key, on the bank page
;   BKMOUSE    the mouse, on the bank page
;------------------------------------------------------------------------------
BK_MAXF     equ  64         ; the files and folders listed, at most
BK_FW       equ  14         ; each: its name ("NAME.EXT"; a folder "NAME/"), 0
BK_TOP      equ  6          ; the lists' first row, and how many rows they have
BK_ROWS     equ  21
BK_FCOL     equ  2          ; the files' column, the instruments', the right side's
BK_ICOL     equ  17
BK_RCOL     equ  57
BK_RW       equ  23         ;   (its width)
BK_DIRMAX   equ  31         ; the longest folder's path
WOP_HLEN    equ  19         ; a WOPL file's header
; An instrument in a WOPL file (62 bytes; 66 from version 3), as SONGKIT reads it:
W_KOFF      equ  32         ; its key's offset (signed, 2 bytes, high first)
W_DKEY      equ  38         ; the key a drum plays
W_FLAGS     equ  39         ; bit 0: 4 operators; 1: two 2-op voices; 2: blank;
                            ; 3-5: its drum in rhythm mode; 6: a fixed note
W_FB1       equ  40         ; $C0 for its first channel (or voice), its second
W_FB2       equ  41
W_CAR1      equ  42         ; its operators, 5 bytes each ($20 $40 $60 $80 $E0)
W_MOD1      equ  47
W_CAR2      equ  52
W_MOD2      equ  57

;------------------------------------------------------------------------------
; The page, and back.
;------------------------------------------------------------------------------
BKOPEN      LDA  PAGE
            CMPA #2
            BEQ  BKO9
            STA  BKFROM
            LDA  PLAYON         ; (Play on: the instrument page's, kept)
            STA  BKPLSV
            LDA  #2
            STA  PAGE
            CLR  BKJAM
            TST  SONGON         ; (the chip for the keys, unless the song plays)
            BNE  BKO1
            JSR  JAMSET
BKO1        LDA  #$FF           ; (no click yet)
            STA  BKCLKI
            TST  BKUP           ; the first time: a folder listed
            BNE  BKO2
            INC  BKUP
            JSR  BKHOME
BKO2        JSR  BKAUD
            JMP  BKDRAW
BKO9        RTS
; BKBACK (Tab, Esc, ^B): back to the page it came from.
BKBACK      LDA  BKPLSV
            STA  PLAYON
            CLR  BKJAM
            LDA  BKFROM
            STA  PAGE
            JSR  USEINST
            TST  SONGON
            BNE  BKBK1
            JSR  JAMSET
BKBK1       JMP  DRAWCUR

;------------------------------------------------------------------------------
; Folders.
;------------------------------------------------------------------------------
; BKHOME: /BANKS listed; or, if there is none, the shell's folder; or the root.
BKHOME      LDX  #S_BANKS
            LDY  #BKDIR
            JSR  BKCPY
            JSR  BKSCAN
            BCC  BKH9
            LDX  #BKDIR
            LDY  #BK_DIRMAX+1
            LDA  #B_GETCWD
            SWI2
            BCS  BKH1
            JSR  BKSCAN
            BCC  BKH9
BKH1        LDD  #$2F00         ; "/"
            STD  BKDIR
            JSR  BKSCAN
BKH9        RTS
; BKSCAN: the folder BKDIR listed: its folders, and its files named .WOP (the
; cursor on the first). Carry set if it can't be.
BKSCAN      CLR  BKNF
            CLR  BKFC
            CLR  BKFT
            LDX  #BKDIR
            LDA  #B_OPENDIR
            SWI2
            BCS  BKS9
            STA  BKSCN
BKS1        LDA  BKNF
            CMPA #BK_MAXF
            BHS  BKS8
            LDB  BKSCN
            LDX  #BKENT
            LDA  #B_READDIR
            SWI2
            BCS  BKS8           ; (no more)
            LDD  BKENT          ; "." left out (".." kept: the folder up)
            CMPD #$2E20
            BEQ  BKS1
            LDA  BKENT+11
            BITA #$08           ; (a volume's label)
            BNE  BKS1
            BITA #ATTR_DIR
            BNE  BKS3
            LDD  BKENT+8        ; a file: .WOP only
            CMPD #$574F         ; "WO"
            BNE  BKS1
            LDA  BKENT+10
            CMPA #'P
            BNE  BKS1
BKS3        BSR  BKENAME
            INC  BKNF
            BRA  BKS1
BKS8        LDB  BKSCN
            LDA  #B_CLOSEDIR
            SWI2
            ANDCC #$FE
BKS9        RTS
; BKENAME: the entry read (BKENT) as a name, in the list's next place.
BKENAME     LDA  BKNF
            JSR  BKFAT
            TFR  X,Y
            LDX  #BKENT
            LDB  #8
BKE1        LDA  ,X+
            CMPA #$20
            BEQ  BKE2
            STA  ,Y+
            DECB
            BNE  BKE1
BKE2        LDX  #BKENT+8       ; its extension, if it has one
            LDA  ,X
            CMPA #$20
            BEQ  BKE4
            LDA  #'.
            STA  ,Y+
            LDB  #3
BKE3        LDA  ,X+
            CMPA #$20
            BEQ  BKE4
            STA  ,Y+
            DECB
            BNE  BKE3
BKE4        LDA  BKENT+11       ; a folder: "/" after it
            BITA #ATTR_DIR
            BEQ  BKE5
            LDA  #'/
            STA  ,Y+
BKE5        CLR  ,Y
            RTS
; BKFAT: X, the list's entry A.
BKFAT       LDB  #BK_FW
            MUL
            ADDD #BKFILES
            TFR  D,X
            RTS
; BKISDIR: the entry at X a folder (its name ends in "/")? Z set if so.
BKISDIR     PSHS X
BKID1       LDA  ,X+
            BNE  BKID1
            LDA  -2,X
            CMPA #'/
            PULS X,PC
; BKFENT (Enter on the files): a folder listed (".." the one it is in), or a
; bank file read -- the cursor to its instruments.
BKFENT      LDA  BKNF
            BEQ  BKFE9
            LDA  BKFC
            BSR  BKFAT
            BSR  BKISDIR
            BEQ  BKFDIR
            LDY  #BKFILE
            JSR  BKCPY
            JSR  BKLOAD
            BCS  BKFE2
            LDA  #1
            STA  BKFOC
BKFE2       JSR  BKAUD
            JSR  BKDRAW
            JMP  BKOOPS
BKFE9       RTS
BKFDIR      LDD  ,X
            CMPD #$2E2E         ; ".."
            BNE  BKFD2
            JSR  BKUPDIR
            BRA  BKFD5
BKFD2       JSR  BKMKP          ; the folder's path, its "/" taken off
            BCS  BKFD8
            DECB
            CMPB #BK_DIRMAX
            BHI  BKFD8
            LDX  #BKPATH
            ABX
            CLR  ,X
            LDX  #BKPATH
            LDY  #BKDIR
            JSR  BKCPY
BKFD5       JSR  BKSCAN
            BCC  BKFD6
            JSR  BKHOME         ; (gone: back to the first)
BKFD6       CLR  BKFOC
            JMP  BKDRAW
BKFD8       LDX  #S_DEEP
            JMP  MSG
; BKUPDIR: the folder BKDIR's own: the last "/" and what follows it gone
; (the root's "/" kept).
BKUPDIR     LDX  #BKDIR
            LDY  #0
BKU1        LDA  ,X+
            BEQ  BKU2
            CMPA #'/
            BNE  BKU1
            LEAY -1,X
            BRA  BKU1
BKU2        CMPY #0
            BEQ  BKU9
            CMPY #BKDIR
            BNE  BKU3
            LEAY 1,Y
BKU3        CLR  ,Y
BKU9        RTS
; BKMKP: BKPATH, the folder and the name at X; B its length. Carry set if it
; is too long (cut off).
BKMKP       PSHS X
            LDX  #BKDIR
            LDY  #BKPATH
            CLRB
BKMP1       LDA  ,X+
            BEQ  BKMP2
            STA  ,Y+
            INCB
            BRA  BKMP1
BKMP2       TSTB                ; (a "/" between them, unless the folder ends in one)
            BEQ  BKMP3
            LDA  -1,Y
            CMPA #'/
            BEQ  BKMP3
            LDA  #'/
            STA  ,Y+
            INCB
BKMP3       PULS X
BKMP4       LDA  ,X+
            STA  ,Y+
            BEQ  BKMP9
            INCB
            CMPB #BK_DIRMAX+13
            BLS  BKMP4
            CLR  -1,Y
            ORCC #1
            RTS
BKMP9       ANDCC #$FE
            RTS
; BKFINDF: the cursor on the file BKFILE, if it is listed.
BKFINDF     CLRA
BKFF1       CMPA BKNF
            BHS  BKFF9
            PSHS A
            JSR  BKFAT
            LDY  #BKFILE
            BSR  BKSAME
            PULS A
            BEQ  BKFF2
            INCA
            BRA  BKFF1
BKFF2       SUBA BKFC           ; (moved there)
            CLR  BKFOC
            JSR  BKMOVE0
BKFF9       RTS
; BKSAME: the strings at X and Y the same? Z set if so.
BKSAME      LDA  ,X+
            CMPA ,Y+
            BNE  BKSM9
            TSTA
            BNE  BKSAME
BKSM9       RTS
; BKCPY: the string at X to Y, with its 0.
BKCPY       LDA  ,X+
            STA  ,Y+
            BNE  BKCPY
            RTS

;------------------------------------------------------------------------------
; A bank file.
;------------------------------------------------------------------------------
; BKLOAD: the bank file BKFILE, in the folder: its header, and its first bank.
; Carry set if it can't be read, or isn't a WOPL bank (BKERR says which: BKOOPS).
BKLOAD      CLR  BKHAVE
            CLR  BKNI
            CLR  BKNB
            CLR  BKB
            LDX  #BKFILE
            JSR  BKMKP
            LDE  #FOPEN_READ
            JSR  BKFOPEN
            LBCS BKL9
            LDX  #BKHDR
            LDY  #WOP_HLEN
            JSR  BKREAD
            LBCS BKL8
            LDX  #BKHDR         ; "WOPL3-BANK", 0
            LDY  #S_WOPL
            LDB  #11
BKL1        LDA  ,X+
            CMPA ,Y+
            BNE  BKLBAD
            DECB
            BNE  BKL1
            LDA  BKHDR+12       ; its version: 1-3 (low byte first)
            BNE  BKLBAD
            LDA  BKHDR+11
            BEQ  BKLBAD
            CMPA #3
            BHI  BKLBAD
            LDB  #62            ; an instrument's bytes: 66 from version 3
            CMPA #3
            BLO  BKL2
            LDB  #66
BKL2        STB  BKIS
            LDA  #128
            MUL
            STD  BKBSZ
            LDD  BKHDR+13       ; its melodic banks, its percussion banks
            STD  BKMB
            LDD  BKHDR+15
            STD  BKPB
            LDD  #WOP_HLEN      ; the instruments after the header -- and from
            STD  BKBASE         ; version 2, the banks' names
            LDA  BKHDR+11
            CMPA #2
            BLO  BKL3
            LDD  BKMB
            ADDD BKPB
            BCS  BKLBAD
            MULD #34
            TSTD
            BNE  BKLBAD
            ADDW #WOP_HLEN
            BCS  BKLBAD
            STW  BKBASE
BKL3        LDD  BKMB           ; those to look at: 127 of each at most
            BSR  BKCLAMP
            STB  BKNM
            LDD  BKPB
            BSR  BKCLAMP
            ADDB BKNM
            STB  BKNB
            BEQ  BKLBAD
            JSR  BKCLOSE
            LDA  #1
            STA  BKHAVE
            JMP  BKBANK
BKLBAD      LDA  #$FF
            STA  BKERR
BKL8        JSR  BKCLOSE
            ORCC #1
BKL9        RTS
BKCLAMP     CMPD #127
            BLS  BKCL9
            LDB  #127
BKCL9       RTS
; BKFIDX: D, the bank looked at (BKB) as the file counts them: the melodic
; first, then the percussion.
BKFIDX      LDB  BKB
            CLRA
            CMPB BKNM
            BLO  BKFI9
            SUBB BKNM
            ADDD BKMB
BKFI9       RTS
; BKBANK: bank BKB read: its name, its instruments (into BKDATA). Carry set if
; it can't be (BKERR).
BKBANK      LDX  #BKFILE
            JSR  BKMKP
            LDE  #FOPEN_READ
            JSR  BKFOPEN
            BCS  BKBN8
            CLR  BKBNAME
            LDA  BKHDR+11       ; its name (from version 2)
            CMPA #2
            BLO  BKBN2
            BSR  BKFIDX
            MULD #34
            ADDW #WOP_HLEN
            ADCD #0
            JSR  BKSEEK
            BCS  BKBN7
            LDX  #BKBNAME
            LDY  #32
            JSR  BKREAD
            BCS  BKBN7
            CLR  BKBNAME+32
BKBN2       BSR  BKFIDX         ; its instruments, 8 at a time (the song's
            MULD BKBSZ          ; ticks let in between)
            ADDW BKBASE
            ADCD #0
            JSR  BKSEEK
            BCS  BKBN7
            LDX  #BKDATA
            LDA  #16
            STA  BKCNT
BKBN3       JSR  TICKPOLL
            LDB  BKIS
            LDA  #8
            MUL
            TFR  D,Y
            PSHS X,Y
            JSR  BKREAD
            PULS X,Y
            BCS  BKBN7
            TFR  Y,D
            LEAX D,X
            DEC  BKCNT
            BNE  BKBN3
            JSR  BKCLOSE
            LDA  #128
            STA  BKNI
            ANDCC #$FE
            RTS
BKBN7       JSR  BKCLOSE
BKBN8       CLR  BKHAVE
            CLR  BKNI
            ORCC #1
            RTS
; BKFOPEN: BKPATH opened (E: how), BKFH; carry set if not (BKERR the error;
; FNAME the path, for saying so).
BKFOPEN     LDX  #BKPATH
            LDY  #FNAME
            JSR  BKCPY
            LDX  #BKPATH
            LDA  #B_FOPEN_NAME
            SWI2
            BCS  BKFO8
            STA  BKFH
            RTS
BKFO8       STA  BKERR
            RTS
; BKREAD: Y bytes from the file to X; carry set if not all of them (BKERR:
; the error, or $FF if the file ends first).
BKREAD      PSHS Y
            LDB  BKFH
            LDA  #B_FREAD
            SWI2
            BCS  BKRD8
            CMPX ,S++
            BNE  BKRD7
            ANDCC #$FE
            RTS
BKRD8       LEAS 2,S
            CMPA #ERR_EOF
            BNE  BKRD6
BKRD7       LDA  #$FF
BKRD6       STA  BKERR
            ORCC #1
            RTS
; BKWRITE: Y bytes from X to the file; carry set if not (BKERR).
BKWRITE     LDB  BKFH
            LDA  #B_FWRITE
            SWI2
            BCC  BKWR9
            STA  BKERR
BKWR9       RTS
; BKSEEK: the file to D:W (from its start); carry set if not (BKERR).
BKSEEK      TFR  D,X
            TFR  W,Y
            LDB  BKFH
            LDE  #SEEK_SET
            LDA  #B_FSEEK_NAME
            SWI2
            BCC  BKSK9
            STA  BKERR
BKSK9       RTS
; BKCLOSE: the file closed; carry set if that went wrong (BKERR).
BKCLOSE     LDB  BKFH
            LDA  #B_FCLOSE_NAME
            SWI2
            BCC  BKCS9
            STA  BKERR
BKCS9       RTS
; BKOOPS: what went wrong, if anything (BKERR: 0, nothing; $FF, FNAME isn't a
; WOPL bank; or the disk's error), on the bottom row.
BKOOPS       LDA  BKERR
            BEQ  BKSY9
            CLR  BKERR
            CMPA #$FF
            LBNE O_FERR
            LDX  #FNAME
            JSR  MSG
            LDX  #S_NOTBANK
            JMP  TXSTR
BKSY9       RTS

;------------------------------------------------------------------------------
; The instruments.
;------------------------------------------------------------------------------
; BKREC: X, instrument A of the bank read.
BKREC       LDB  BKIS
            MUL
            ADDD #BKDATA
            TFR  D,X
            RTS
; BKCONV: the bank's instrument at X (program BKIC of bank BKB) as SONGKIT's:
; BKINS, BKNAME, BKSRC, and what the keys play it on (BKPLAY). Two 2-op voices
; (pseudo 4-op): the first; a drum (the percussion banks', or a fixed note):
; the note its key plays.
BKCONV      TFR  X,U
            LDX  #BKZ           ; (all 0 to start with)
            LDY  #BKINS
            LDW  #SK_ILEN+32
            TFM  X,Y+
            LEAX ,U             ; its name: 16 of its characters
            LDY  #BKNAME
            LDB  #16
BKC1        LDA  ,X+
            BEQ  BKC2
            STA  ,Y+
            DECB
            BNE  BKC1
BKC2        TST  BKNAME         ; (none: "Program 105")
            BNE  BKC2B
            LDY  #BKNAME
            LDX  #S_PROGN
            JSR  BKPUTS
            LDA  BKIC
            JSR  BKPUTD
BKC2B       LDA  W_FLAGS,U      ; its drum in rhythm mode, if it says: Play on
            LSRA
            LSRA
            LSRA
            ANDA #7
            CMPA #5
            BLS  BKC2A
            CLRA
BKC2A       STA  BKPLAY
            LDA  W_FB1,U        ; feedback, connection
            ANDA #$0F
            STA  BKINS+1
            LEAX W_MOD1,U       ; operators 1 and 2: its first channel's
            LDY  #BKINS+3       ; modulator and carrier
            LDW  #5
            TFM  X+,Y+
            LEAX W_CAR1,U
            LDW  #5
            TFM  X+,Y+
            LDA  W_FLAGS,U      ; 4 operators (not two voices): 3 and 4 too
            BITA #2
            BNE  BKC3
            BITA #1
            BEQ  BKC3
            LDA  #1
            STA  BKINS
            LDA  W_FB2,U
            ANDA #1
            STA  BKINS+2
            LEAX W_MOD2,U
            LDW  #5
            TFM  X+,Y+
            LEAX W_CAR2,U
            LDW  #5
            TFM  X+,Y+
BKC3        LDD  W_KOFF,U       ; the key: a drum's, fixed; or a transpose
            STD  BKKOFF
            LDA  BKB
            CMPA BKNM
            BHS  BKC5           ; (a percussion bank's: its key, or the program's)
            LDA  W_FLAGS,U
            BITA #$40
            BEQ  BKC7
            LDA  W_DKEY,U
            BRA  BKC6
BKC5        LDA  W_DKEY,U
            BNE  BKC6
            LDA  BKIC
BKC6        ANDA #$7F           ; the note: its key (MIDI's: 60 is C-4), and the
            TFR  A,B            ; offset; 1-96
            CLRA
            ADDD BKKOFF
            SUBD #11
            CMPD #1
            BGE  BKC6A
            LDD  #1
BKC6A       CMPD #96
            BLE  BKC6B
            LDD  #96
BKC6B       STB  BKINS+23
            LDA  BKINS
            ORA  #2
            STA  BKINS
            BRA  BKC8
BKC7        LDD  BKKOFF         ; a transpose: 4 octaves at most
            CMPD #-48
            BGE  BKC7A
            LDD  #-48
BKC7A       CMPD #48
            BLE  BKC7B
            LDD  #48
BKC7B       STB  BKINS+23
BKC8        LDX  #BKFILE        ; where it came from: the file, the bank, the
            LDY  #BKSRC         ; program, flags
            LDB  #12
BKC9        LDA  ,X+
            BEQ  BKC10
            STA  ,Y+
            DECB
            BNE  BKC9
BKC10       LDA  BKB
            CMPA BKNM
            BLO  BKC11
            SUBA BKNM
            ORA  #$80
BKC11       STA  BKSRC+12
            LDA  BKIC
            STA  BKSRC+13
            LDA  W_FLAGS,U
            LSRA
            ANDA #1
            STA  BKSRC+14
            RTS
; BKAUD: the instrument at the cursor made SONGKIT's (BKCONV), and put after
; the song's own for the keys to play (BKJAM) -- unless no bank is read, or
; the song has 255 already.
BKAUD       CLR  BKJAM
            TST  BKHAVE
            BEQ  BKA8
            LDA  BKIC
            JSR  BKREC
            JSR  BKCONV
            LDA  BKPLAY
            STA  PLAYON
            LDA  NINST
            CMPA #MAXINST
            BHS  BKA8
            JSR  IMAP
            LDA  NINST
            LDB  #SK_ILEN
            MUL
            ADDD #WINDOW
            TFR  D,Y
            LDX  #BKINS
            LDW  #SK_ILEN
            TFM  X+,Y+
            LDA  NINST
            INCA
            STA  BKJAM
BKA8        JMP  USEINST
; BKTAKE: the instrument at the cursor, to take: carry set if it can't be (no
; bank read, or it's blank) -- said why.
BKTAKE      TST  BKHAVE
            BEQ  BKT8
            LDA  BKIC
            JSR  BKREC
            LDA  W_FLAGS,X
            BITA #4
            BNE  BKT7
            JSR  BKCONV
            ANDCC #$FE
            RTS
BKT7        LDX  #S_BLANK
            BRA  BKT9
BKT8        LDX  #S_NOBANK
BKT9        JSR  MSG
            ORCC #1
            RTS
; BKADD (Enter on the instruments): it added to the song, after the last; the
; one edited.
BKADD       BSR  BKTAKE
            BCS  BKAD9
            LDX  #BKINS
            LDY  #BKNAME
            LDU  #BKSRC
            JSR  ADDINST0
            BCS  BKAD8
            JSR  O_DRAWTITLE
            JSR  BKAUD
            JSR  BKDRSONG
            LDX  #S_ADDED
            JSR  MSG
            LDA  CURI
            JMP  TXDEC
BKAD8       LDX  #S_FULL
            JMP  MSG
BKAD9       RTS
; BKREPQ (^R): over the song's instrument being edited? Asked.
BKREPQ      BSR  BKTAKE
            BCS  BKAD9
            LDY  #BKLINE
            LDX  #S_REPQ
            JSR  BKPUTS
            JSR  BKPUTI
            LDX  #S_YN
            JSR  BKPUTS
            CLR  ,Y
            LDX  #BKREPL
            LDY  #BKLINE
            JMP  ASK
BKREPL      BSR  BKTAKE
            BCS  BKAD9
            LDX  #BKINS
            LDY  #CURINST
            LDW  #SK_ILEN
            TFM  X+,Y+
            LDX  #BKNAME
            LDY  #CURNAME
            LDW  #16
            TFM  X+,Y+
            CLR  ,Y
            LDX  #BKSRC
            LDY  #CURSRC
            LDW  #16
            TFM  X+,Y+
            JSR  PUTNAME
            JSR  PUTSRC
            LDA  #1
            STA  CHANGED
            JSR  JAMREF         ; (into its page; heard so wherever it plays)
            JSR  O_DRAWTITLE
            JSR  BKAUD
            JSR  BKDRSONG
            LDX  #S_REPLACED
            JSR  MSG
            LDA  CURI
            JMP  TXDEC
; BKPUTI: "instrument 3, NAME" at Y (Y past it).
BKPUTI      LDX  #S_INSTN
            JSR  BKPUTS
            LDA  CURI
            JSR  BKPUTD
            LDA  #',
            STA  ,Y+
            LDA  #$20
            STA  ,Y+
            LDX  #CURNAME
            JMP  BKPUTS
; BKPUTQ (^P): the song's instrument being edited into the bank, at the
; cursor? Asked.
BKPUTQ      TST  BKHAVE
            BNE  BKPQ1
            LDX  #S_NOBANK
            JMP  MSG
BKPQ1       LDY  #BKLINE
            LDX  #S_PUTQ
            JSR  BKPUTS
            JSR  BKPUTI
            LDX  #S_PUTQ2
            JSR  BKPUTS
            LDA  BKIC
            JSR  BKPUTD
            LDX  #S_YN
            JSR  BKPUTS
            CLR  ,Y
            LDX  #BKPUT
            LDY  #BKLINE
            JMP  ASK
BKPUT       JSR  BKMKREC        ; (as the bank's: BKWREC)
            LDX  #BKFILE
            JSR  BKMKP
            LDE  #FOPEN_UPDATE
            JSR  BKFOPEN
            BCS  BKPU8
            JSR  BKFIDX         ; where: the bank's instruments, the cursor's
            MULD BKBSZ
            ADDW BKBASE
            ADCD #0
            STD  BKOFS
            STW  BKOFS+2
            LDA  BKIC
            LDB  BKIS
            MUL
            ADDD BKOFS+2
            TFR  D,W
            LDD  BKOFS
            ADCD #0
            JSR  BKSEEK
            BCS  BKPU7
            LDX  #BKWREC
            LDB  BKIS
            CLRA
            TFR  D,Y
            JSR  BKWRITE
            BCS  BKPU7
            JSR  BKCLOSE
            BCS  BKPU8
            LDA  BKIC           ; and into the bank as it is shown
            JSR  BKREC
            TFR  X,Y
            LDX  #BKWREC
            LDB  BKIS
            CLRA
            TFR  D,W
            TFM  X+,Y+
            JSR  BKAUD
            LDA  BKIC
            JSR  BKDRI1
            JSR  BKDRINFO
            LDX  #S_PUT
            JSR  MSG
            LDX  #BKFILE
            JMP  TXSTR
BKPU7       JSR  BKCLOSE
BKPU8       JMP  BKOOPS
; BKMKREC: the song's instrument being edited, as a bank's (BKWREC): its
; operators the other way round (SONGKIT's 1 2 3 4: the bank's MOD1 CAR1 MOD2
; CAR2); a fixed note as the key a drum plays, a transpose as the key's offset.
; (Its fine tune and outputs a bank doesn't have.)
BKMKREC     LDX  #BKZ
            LDY  #BKWREC
            LDW  #66
            TFM  X,Y+
            LDX  #CURNAME
            LDY  #BKWREC
            LDW  #16
            TFM  X+,Y+
            LDB  CURINST        ; 4 operators, a fixed note
            ANDB #1
            STB  BKWREC+W_FLAGS
            LDB  CURINST
            BITB #2
            BEQ  BKMR1
            LDA  BKWREC+W_FLAGS
            ORA  #$40
            STA  BKWREC+W_FLAGS
            LDB  CURINST+23
            ADDB #11
            STB  BKWREC+W_DKEY
            BRA  BKMR2
BKMR1       LDB  CURINST+23
            SEX
            STD  BKWREC+W_KOFF
BKMR2       LDD  CURINST+1
            STD  BKWREC+W_FB1
            LDX  #CURINST+8
            LDY  #BKWREC+W_CAR1
            LDW  #5
            TFM  X+,Y+
            LDX  #CURINST+3
            LDW  #5
            TFM  X+,Y+
            LDA  CURINST
            BITA #1
            BEQ  BKMR9
            LDX  #CURINST+18
            LDW  #5
            TFM  X+,Y+
            LDX  #CURINST+13
            LDW  #5
            TFM  X+,Y+
            RTS
BKMR9       CLR  BKWREC+W_FB2
            RTS
; BKNEWQ (^N): a new bank file, in the folder: its name asked.
BKNEWQ      LDX  #S_ASKNEW
            LDY  #0
            LDA  #1
            JSR  PRSTART
            LDX  #BKNEW
            JSR  SETPRDO
            LDA  #1
            STA  MODE
            RTS
; BKNEW: the bank file PR_BUF (.WOP if it has no extension) made: one melodic
; bank, named as the file is, of 128 blank instruments; then read.
BKNEW       LDX  #PR_BUF
            LDY  #BKNEWN
            CLRB
            CLR  BKE            ; (a dot)
BKN1        LDA  ,X+
            BEQ  BKN2
            CMPA #'/
            BEQ  BKNBAD
            CMPA #'.
            BNE  BKN1A
            INC  BKE
BKN1A       STA  ,Y+
            INCB
            CMPB #12
            BHI  BKNBAD
            BRA  BKN1
BKN2        TSTB
            LBEQ BKNE9
            TST  BKE
            BNE  BKN3
            CMPB #8
            BHI  BKNBAD
            LDX  #S_WOP
            JSR  BKPUTS
BKN3        CLR  ,Y
            LDX  #BKNEWN
            JSR  BKMKP
            LDX  #BKPATH        ; (there already: not made again)
            LDY  #BKENT
            LDA  #B_STAT
            SWI2
            BCS  BKN4
            LDX  #BKNEWN
            JSR  MSG
            LDX  #S_EXISTS
            JMP  TXSTR
BKNBAD      LDX  #S_BADNAME
            JMP  MSG
BKN4        LDE  #FOPEN_WRITE
            JSR  BKFOPEN
            LBCS BKNE8
            LDX  #BKNHDR        ; the header: version 3, one melodic bank
            LDY  #WOP_HLEN
            JSR  BKWRITE
            LBCS BKNE7
            LDX  #BKZ           ; the bank's name: the file's, to its dot
            LDY  #BKWREC
            LDW  #66
            TFM  X,Y+
            LDX  #BKNEWN
            LDY  #BKWREC
BKN5        LDA  ,X+
            CMPA #'.
            BEQ  BKN6
            STA  ,Y+
            TSTA
            BNE  BKN5
BKN6        LDX  #BKWREC
            LDY  #34
            JSR  BKWRITE
            BCS  BKNE7
            LDX  #BKZ           ; its instruments, blank
            LDY  #BKWREC
            LDW  #34
            TFM  X,Y+
            LDA  #4
            STA  BKWREC+W_FLAGS
            LDA  #128
            STA  BKCNT
BKN7        LDX  #BKWREC
            LDY  #66
            JSR  BKWRITE
            BCS  BKNE7
            DEC  BKCNT
            BNE  BKN7
            JSR  BKCLOSE
            BCS  BKNE8
            JSR  BKSCAN         ; listed again, and read
            LDX  #BKNEWN
            LDY  #BKFILE
            JSR  BKCPY
            JSR  BKFINDF
            JSR  BKLOAD
            BCS  BKNE6
            LDA  #1
            STA  BKFOC
BKNE6       JSR  BKAUD
            JSR  BKDRAW
            TST  BKERR
            BNE  BKNE8
            LDX  #S_MADE
            JSR  MSG
            LDX  #BKFILE
            JMP  TXSTR
BKNE7       JSR  BKCLOSE
BKNE8       JMP  BKOOPS
BKNE9       RTS
; BKPUTS: the string at X to Y, without its 0 (Y past it). BKPUTD: A in
; decimal there.
BKPUTS      LDA  ,X+
            BEQ  BKPS9
            STA  ,Y+
            BRA  BKPUTS
BKPS9       RTS
BKPUTD      TFR  A,B
            CLRA
            CMPB #100
            BLO  BKPD1
            DIVD #100           ; (B the hundreds, A the rest)
            ADDB #'0
            STB  ,Y+
            TFR  A,B
            CLRA
            DIVD #10
            BRA  BKPD2
BKPD1       CMPB #10
            BLO  BKPD3
            DIVD #10
BKPD2       ADDB #'0
            STB  ,Y+
            TFR  A,B
BKPD3       ADDB #'0
            STB  ,Y+
            RTS

;------------------------------------------------------------------------------
; The keys, the mouse.
;------------------------------------------------------------------------------
BKEY        LDB  KEYMODS
            BITB #VC_MOD_CTL
            BNE  BKEY2
            JSR  PIANODN        ; a note? (the instrument at the cursor)
            BCC  BKEY9
            LDX  #BKKTAB
            BRA  BKEY3
BKEY2       LDX  #BKCTAB
BKEY3       LDB  ,X
            BEQ  BKEY9
            CMPA ,X
            BEQ  BKEY4
            LEAX 3,X
            BRA  BKEY3
BKEY4       JMP  [1,X]
BKEY9       RTS
BKKTAB      FCB  K_UP
            FDB  BKKUP
            FCB  K_DOWN
            FDB  BKKDN
            FCB  K_PGUP
            FDB  BKKPU
            FCB  K_PGDN
            FDB  BKKPD
            FCB  K_HOME
            FDB  BKKHOME
            FCB  K_END
            FDB  BKKEND
            FCB  K_LEFT
            FDB  BKKLEFT
            FCB  K_RIGHT
            FDB  BKKRIGHT
            FCB  K_ENTER
            FDB  BKKENT
            FCB  K_KPENTER
            FDB  BKKENT
            FCB  K_TAB
            FDB  BKBACK
            FCB  K_ESC
            FDB  BKBACK
            FCB  K_SPACE
            FDB  KSONG
            FCB  K_BKSP
            FDB  KHUSH
            FCB  $2F            ; [
            FDB  KOCTDN
            FCB  $30            ; ]
            FDB  KOCTUP
            FCB  0
BKCTAB      FCB  $05            ; ^B: back
            FDB  BKBACK
            FCB  $15            ; ^R: over the song's instrument
            FDB  BKREPQ
            FCB  $13            ; ^P: the song's instrument into the bank
            FDB  BKPUTQ
            FCB  $11            ; ^N: a new bank file
            FDB  BKNEWQ
            FCB  K_LEFT         ; ^Left, ^Right: the bank before, after
            FDB  BKPREVB
            FCB  K_RIGHT
            FDB  BKNEXTB
            FCB  K_UP           ; ^Up, ^Down: the song's instrument before, after
            FDB  BKSPREV
            FCB  K_DOWN
            FDB  BKSNEXT
            FCB  $16            ; ^S
            FDB  O_SAVE
            FCB  $04            ; ^A
            FDB  O_SAVEAS
            FCB  0
BKKUP       LDA  #-1
            JMP  BKMOVE
BKKDN       LDA  #1
            JMP  BKMOVE
BKKPU       LDA  #-BK_ROWS
            JMP  BKMOVE
BKKPD       LDA  #BK_ROWS
            JMP  BKMOVE
BKKHOME     LDA  #-128
            JMP  BKMOVE
BKKEND      LDA  #127
            JMP  BKMOVE
BKKLEFT     CLRA
            JMP  BKFOCUS
BKKRIGHT    TST  BKHAVE
            BEQ  BKKR9
            LDA  #1
            JMP  BKFOCUS
BKKR9       RTS
BKKENT      TST  BKFOC
            LBEQ BKFENT
            JMP  BKADD
; BKPREVB, BKNEXTB: the bank before, after (of the file's).
BKPREVB     TST  BKHAVE
            BEQ  BKBS9
            LDA  BKB
            BEQ  BKBS9
            DECA
            BRA  BKBS1
BKNEXTB     TST  BKHAVE
            BEQ  BKBS9
            LDA  BKB
            INCA
            CMPA BKNB
            BHS  BKBS9
BKBS1       STA  BKB
            JSR  BKBANK
            BCC  BKBS2
            CLR  BKFOC
BKBS2       JSR  BKAUD
            JSR  BKDRAW
            JMP  BKOOPS
BKBS9       RTS
; BKSPREV, BKSNEXT: the song's instrument before, after: the one edited.
BKSPREV     LDA  CURI
            CMPA #1
            BLS  BKBS9
            DEC  CURI
            BRA  BKSI
BKSNEXT     LDA  CURI
            CMPA NINST
            BHS  BKBS9
            INC  CURI
BKSI        JSR  SETIP
            JMP  BKDRSONG
; BKFOCUS: the cursor to list A (0 the files, 1 the instruments).
BKFOCUS     CMPA BKFOC
            BEQ  BKFC9
            STA  BKFOC
            LDA  BKFC
            JSR  BKDRF1
            LDA  BKIC
            JMP  BKDRI1
BKFC9       RTS
; BKMOVE: the cursor A (signed) further on in its list, kept to it, the list
; scrolled to show it (and the instrument it's on made ready to play).
; BKMOVE0: the same, nothing drawn.
BKMOVE      LDB  BKFOC
            STB  BKDRW
            BSR  BKMV0
            BCS  BKMV9
            TST  BKFOC
            BNE  BKMV5
            LDA  BKFT           ; the files: all of them again if they scrolled,
            CMPA BKOT           ; or the old row and the new
            LBNE BKDRFILES
            LDA  BKOLD
            JSR  BKDRF1
            LDA  BKFC
            JMP  BKDRF1
BKMV5       JSR  BKAUD          ; the instruments: the same, and the one now at
            JSR  BKDRINFO       ; the cursor
            LDA  BKIT
            CMPA BKOT
            LBNE BKDRINS
            LDA  BKOLD
            JSR  BKDRI1
            LDA  BKIC
            JMP  BKDRI1
BKMV9       RTS
BKMOVE0     CLR  BKDRW
BKMV0       LDX  #BKFC          ; (the list: its cursor, its first row shown,
            TST  BKFOC          ; how many it has)
            BEQ  BKMV1
            LDX  #BKIC
BKMV1       LDB  2,X
            BEQ  BKMVNO
            STB  BKCNT
            LDB  ,X
            STB  BKOLD
            LDB  1,X
            STB  BKOT
            TFR  A,B
            SEX
            STD  BKTMP
            LDB  ,X
            CLRA
            ADDD BKTMP
            BPL  BKMV2
            LDD  #0
BKMV2       TSTA
            BNE  BKMV3
            CMPB BKCNT
            BLO  BKMV4
BKMV3       LDB  BKCNT
            DECB
BKMV4       STB  ,X
            CMPB 1,X            ; scrolled to it
            BHS  BKMV6
            STB  1,X
            BRA  BKMV7
BKMV6       SUBB 1,X
            CMPB #BK_ROWS
            BLO  BKMV7
            LDB  ,X
            SUBB #BK_ROWS-1
            STB  1,X
BKMV7       ANDCC #$FE
            RTS
BKMVNO      ORCC #1
            RTS

; BKMOUSE: a click on a file, a folder or an instrument puts the cursor there
; (a file or folder clicked again: Enter; an instrument clicked twice, quickly:
; over the song's instrument being edited, as ^R, not asked); the wheel over a
; list moves its cursor.
BKMOUSE     LDA  PRESSED
            BITA #VC_MB_LEFT
            BEQ  BKMS5
            JSR  BKHIT
            BCS  BKMS5
            TSTA
            BNE  BKMS2
            TST  BKFOC          ; a file, a folder
            BNE  BKMS1
            CMPB BKFC
            LBEQ BKFENT
BKMS1       PSHS B
            JSR  BKFOCUS
            PULS B
            TFR  B,A
            SUBA BKFC
            JMP  BKMOVE
BKMS2       PSHS B              ; an instrument
            JSR  BKFOCUS
            PULS B
            CMPB BKCLKI         ; (the same one again, within half a second)
            BNE  BKMS3
            LDA  VC_FRAME
            SUBA BKCLKF
            CMPA #30
            BHS  BKMS3
            LDA  #$FF
            STA  BKCLKI
            JMP  BKREPL
BKMS3       STB  BKCLKI
            LDA  VC_FRAME
            STA  BKCLKF
            TFR  B,A
            SUBA BKIC
            JMP  BKMOVE
BKMS5       LDA  WHEEL
            BEQ  BKMS9
            JSR  BKHIT
            BCS  BKMS9
            JSR  BKFOCUS
            LDA  WHEEL          ; (up: the cursor up)
            NEGA
            JMP  BKMOVE
BKMS9       RTS
; BKHIT: the list under the mouse -> A (0 the files, 1 the instruments), B the
; entry there; carry set if none.
BKHIT       LDD  MOUSEY
            LSRD
            LSRD
            LSRD
            LSRD
            SUBB #BK_TOP
            BLO  BKHT8
            CMPB #BK_ROWS
            BHS  BKHT8
            STB  BKTMP
            LDD  MOUSEX
            LSRD
            LSRD
            LSRD
            CMPB #BK_ICOL-1
            BHS  BKHT2
            CMPB #BK_FCOL
            BLO  BKHT8
            LDB  BKTMP          ; the files
            ADDB BKFT
            CMPB BKNF
            BHS  BKHT8
            CLRA
            ANDCC #$FE
            RTS
BKHT2       CMPB #BK_RCOL-2
            BHS  BKHT8
            TST  BKHAVE
            BEQ  BKHT8
            LDB  BKTMP          ; the instruments
            ADDB BKIT
            BMI  BKHT8
            LDA  #1
            ANDCC #$FE
            RTS
BKHT8       ORCC #1
            RTS

;------------------------------------------------------------------------------
; Drawing it.
;------------------------------------------------------------------------------
BKDRAW      JSR  TXCLR
            JSR  O_DRAWTITLE
            LDX  #BKLABS
            JSR  DRAWLAB
            JSR  BKDRHEAD
            JSR  BKDRFILES
            JSR  BKDRINS
            JSR  BKDRINFO
            JSR  BKDRSONG
            JMP  O_DRAWSTAT
; BKDRHEAD: the folder, the file, the bank.
BKDRHEAD    CLR  TXBG
            LDA  #C_VALUE
            STA  TXFG
            LDD  #$0902
            JSR  TXAT
            LDX  #BKDIR
            LDB  #BK_DIRMAX+2
            JSR  BKSTRW
            LDD  #$3302
            JSR  TXAT
            LDX  #BKFILE
            TST  BKFILE
            BNE  BKDH1
            LDA  #C_DIM
            STA  TXFG
            LDX  #S_BKNONE
BKDH1       LDB  #13
            JSR  BKSTRW
            LDB  #3
            JSR  TXROWCLR
            LDD  #$0203
            JSR  TXAT
            LDA  #C_LABEL
            STA  TXFG
            LDX  #S_BANK
            JSR  TXSTR
            LDD  #$0903
            JSR  TXAT
            TST  BKHAVE
            BNE  BKDH2
            LDA  #C_DIM
            STA  TXFG
            LDX  #S_NOBANK
            JMP  TXSTR
BKDH2       LDA  #C_VALUE       ; melodic 0, percussion 0 ...
            STA  TXFG
            LDX  #S_MEL
            LDA  BKB
            CMPA BKNM
            BLO  BKDH3
            SUBA BKNM
            LDX  #S_PER
BKDH3       JSR  TXSTR
            JSR  TXDEC
            LDD  #$1A03         ; its name
            JSR  TXAT
            LDX  #BKBNAME
            JSR  TXSTR
            LDD  #$3C03         ; which of how many
            JSR  TXAT
            LDA  #C_LABEL
            STA  TXFG
            LDA  #'(
            JSR  TXCH
            LDA  BKB
            INCA
            JSR  TXDEC
            LDX  #S_BKOF
            JSR  TXSTR
            LDA  BKNB
            JSR  TXDEC
            LDA  #')
            JMP  TXCH
; BKDRFILES: the files' list; BKDRF1: its entry A (if it's shown), lit if
; it's the cursor's.
BKDRFILES   CLR  BKN
BKDF1       JSR  TICKPOLL
            LDA  BKFT
            ADDA BKN
            BSR  BKDRF1
            INC  BKN
            LDA  BKN
            CMPA #BK_ROWS
            BLO  BKDF1
            RTS
BKDRF1      STA  BKE
            SUBA BKFT
            BLO  BKDF9
            CMPA #BK_ROWS
            BHS  BKDF9
            ADDA #BK_TOP
            TFR  A,B
            LDA  #BK_FCOL
            JSR  TXAT
            CLR  TXBG
            LDA  BKE
            CMPA BKNF
            BHS  BKDF8
            CMPA BKFC           ; (the cursor's: lit; dimmer when it's in the
            BNE  BKDF2          ; other list)
            LDA  #C_CURBG
            TST  BKFOC
            BEQ  BKDF1A
            LDA  #C_BARBG
BKDF1A      STA  TXBG
BKDF2       LDA  BKE
            JSR  BKFAT
            LDA  #C_VALUE       ; (a folder as a label; the bank read, orange)
            STA  TXFG
            JSR  BKISDIR
            BNE  BKDF3
            LDA  #C_LABEL
            STA  TXFG
            BRA  BKDF4
BKDF3       TST  BKHAVE
            BEQ  BKDF4
            PSHS X
            LDY  #BKFILE
            JSR  BKSAME
            PULS X
            BNE  BKDF4
            LDA  #C_OUT
            STA  TXFG
BKDF4       LDB  #BK_FW
            JMP  BKSTRW
BKDF8       LDB  #BK_FW
            JMP  TXSPC
BKDF9       RTS
; BKDRINS: the instruments' list; BKDRI1: instrument A's row (if it's shown),
; lit if it's the cursor's.
BKDRINS     CLR  BKN
BKDI1       JSR  TICKPOLL
            LDA  BKIT
            ADDA BKN
            BSR  BKDRI1
            INC  BKN
            LDA  BKN
            CMPA #BK_ROWS
            BLO  BKDI1
            RTS
BKDRI1      STA  BKE
            SUBA BKIT
            BLO  BKDF9
            CMPA #BK_ROWS
            BHS  BKDF9
            ADDA #BK_TOP
            TFR  A,B
            LDA  #BK_ICOL
            JSR  TXAT
            CLR  TXBG
            TST  BKHAVE
            BEQ  BKDI8
            TST  BKFOC          ; (the other list's: dimmer)
            BNE  BKDI1A
            LDA  BKE
            CMPA BKIC
            BNE  BKDI2
            LDA  #C_BARBG
            STA  TXBG
            BRA  BKDI2
BKDI1A      LDA  BKE
            CMPA BKIC
            BNE  BKDI2
            LDA  #C_CURBG
            STA  TXBG
BKDI2       LDA  #C_LABEL       ; its number, its name (dim: blank)
            STA  TXFG
            LDA  BKE
            JSR  BKDEC3
            LDA  #$20
            JSR  TXCH
            LDA  BKE
            JSR  BKREC
            LDA  #C_VALUE
            LDB  W_FLAGS,X
            BITB #4
            BEQ  BKDI3
            LDA  #C_DIM
BKDI3       STA  TXFG
            LDB  #32
            JSR  BKSTRW
            LDB  #2
            JMP  TXSPC
BKDI8       LDB  #38
            JMP  TXSPC
; BKDRINFO: the instrument at the cursor, on the right: its operators, its
; note, its drum.
BKDRINFO    LDB  #BK_TOP
BKDN1       LDA  #BK_RCOL
            JSR  TXAT
            CLR  TXBG
            PSHS B
            LDB  #BK_RW
            JSR  TXSPC
            PULS B
            INCB
            CMPB #BK_TOP+4
            BLO  BKDN1
            TST  BKHAVE
            LBEQ BKDN9
            LDA  BKIC
            JSR  BKREC
            LDA  W_FLAGS,X
            STA  BKE
            LDD  #BK_RCOL*256+BK_TOP
            JSR  TXAT
            LDA  #C_VALUE
            STA  TXFG
            LDX  #S_2OP
            LDA  BKE
            BITA #1
            BEQ  BKDN2
            LDX  #S_4OP
BKDN2       BITA #2
            BEQ  BKDN3
            LDX  #S_2VOICE
BKDN3       JSR  TXSTR
            LDD  #BK_RCOL*256+BK_TOP+1
            JSR  TXAT
            LDA  #C_LABEL
            STA  TXFG
            LDA  BKINS
            BITA #2
            BEQ  BKDN4
            LDX  #S_FIXED
            JSR  TXSTR
            LDA  #C_VALUE
            STA  TXFG
            LDA  BKINS+23
            JSR  O_NOTENAME
            BRA  BKDN5
BKDN4       LDX  #S_XPOSE2
            JSR  TXSTR
            LDA  #C_VALUE
            STA  TXFG
            LDA  BKINS+23
            JSR  TXSGN
BKDN5       LDA  BKPLAY         ; a drum, in rhythm mode
            BEQ  BKDN6
            LDD  #BK_RCOL*256+BK_TOP+2
            JSR  TXAT
            LDA  #C_LABEL
            STA  TXFG
            LDX  #S_PLAYSON
            JSR  TXSTR
            LDA  #C_VALUE
            STA  TXFG
            LDA  BKPLAY
            DECA
            LDB  #10
            MUL
            ADDD #S_DRUMS
            TFR  D,X
            JSR  TXSTR
BKDN6       LDA  BKE            ; blank
            BITA #4
            BEQ  BKDN9
            LDD  #BK_RCOL*256+BK_TOP+3
            JSR  TXAT
            LDA  #C_DIM
            STA  TXFG
            LDX  #S_BLANK2
            JSR  TXSTR
BKDN9       RTS
; BKDRSONG: the song's instrument being edited (what ^R puts it over, what ^P
; puts into the bank).
BKDRSONG    CLR  TXBG
            LDD  #BK_RCOL*256+13
            JSR  TXAT
            LDA  #C_LABEL
            STA  TXFG
            LDX  #S_INSTN2
            JSR  TXSTR
            LDA  #C_VALUE
            STA  TXFG
            LDA  CURI
            JSR  TXDEC
            LDX  #S_BKOF
            JSR  TXSTR
            LDA  NINST
            JSR  TXDEC
            LDB  #4
            JSR  TXSPC
            LDD  #BK_RCOL*256+14
            JSR  TXAT
            LDX  #CURNAME
            LDB  #BK_RW
            JMP  BKSTRW
; BKSTRW: the string at X, B characters wide (cut off there, or spaces after).
BKSTRW      STB  BKCNT
BKSW1       TST  BKCNT
            BEQ  BKSW9
            LDA  ,X+
            BEQ  BKSW2
            JSR  TXCH
            DEC  BKCNT
            BRA  BKSW1
BKSW2       LDB  BKCNT
            JMP  TXSPC
BKSW9       RTS
; BKDEC3: A as 3 digits.
BKDEC3      TFR  A,B
            CLRA
            DIVD #100
            PSHS A
            TFR  B,A
            ADDA #'0
            JSR  TXCH
            PULS B
            CLRA
            DIVD #10
            PSHS A
            TFR  B,A
            ADDA #'0
            JSR  TXCH
            PULS A
            ADDA #'0
            JMP  TXCH

;------------------------------------------------------------------------------
; Its words.
;------------------------------------------------------------------------------
BKLABS      FCB  2,2,C_LABEL
            FCC  "Folder"
            FCB  0
            FCB  46,2,C_LABEL
            FCC  "File"
            FCB  0
            FCB  BK_FCOL,5,C_HEAD
            FCC  "Files"
            FCB  0
            FCB  BK_ICOL,5,C_HEAD
            FCC  "Instruments"
            FCB  0
            FCB  BK_RCOL,5,C_HEAD
            FCC  "At the cursor"
            FCB  0
            FCB  BK_RCOL,12,C_HEAD
            FCC  "In the song"
            FCB  0
            FCB  2,28,C_HELP
            FCC  "Enter: add to the song  ^R: over the song's  ^P: the song's in here  Tab: back"
            FCB  0
            FCB  $FF,$FF
S_BANKS     FCC  "/BANKS"
            FCB  0
S_WOPL      FCC  "WOPL3-BANK"
            FCB  0
S_WOP       FCC  ".WOP"
            FCB  0
; A new bank's header: version 3, one melodic bank, no percussion, no flags,
; the volume model 0.
BKNHDR      FCC  "WOPL3-BANK"
            FCB  0,3,0,0,1,0,0,0,0
S_NOTBANK   FCC  ": not a WOPL bank"
            FCB  0
S_DEEP      FCC  "That folder is too far down"
            FCB  0
S_BKNONE      FCC  "-"
            FCB  0
S_BANK      FCC  "Bank"
            FCB  0
S_NOBANK    FCC  "No bank read: Enter on a bank file reads it"
            FCB  0
S_MEL       FCC  "melodic "
            FCB  0
S_PER       FCC  "percussion "
            FCB  0
S_BKOF      FCC  " of "
            FCB  0
S_2OP       FCC  "2 operators"
            FCB  0
S_4OP       FCC  "4 operators"
            FCB  0
S_2VOICE    FCC  "2 voices: the 1st taken"
            FCB  0
S_FIXED     FCC  "Fixed note "
            FCB  0
S_XPOSE2    FCC  "Transpose "
            FCB  0
S_PLAYSON   FCC  "Plays on "
            FCB  0
S_DRUMS     FCC  "bass drum"        ; (10 apart)
            FCB  0
            FCC  "snare"
            FCB  0,0,0,0,0
            FCC  "tom-tom"
            FCB  0,0,0
            FCC  "cymbal"
            FCB  0,0,0,0
            FCC  "hi-hat"
            FCB  0,0,0,0
S_BLANK2    FCC  "Blank: no sound"
            FCB  0
S_INSTN2    FCC  "Instrument "
            FCB  0
S_BLANK     FCC  "That one is blank: nothing to take"
            FCB  0
S_ADDED     FCC  "Added to the song: instrument "
            FCB  0
S_REPLACED  FCC  "Put over it: instrument "
            FCB  0
S_REPQ      FCC  "Put it over "
            FCB  0
S_INSTN     FCC  "instrument "
            FCB  0
S_YN        FCC  "? (Y or N)"
            FCB  0
S_PUTQ      FCC  "Put "
            FCB  0
S_PUTQ2     FCC  " into the bank, at "
            FCB  0
S_PUT       FCC  "Put into "
            FCB  0
S_ASKNEW    FCC  "A new bank file (.WOP): "
            FCB  0
S_EXISTS    FCC  " is there already"
            FCB  0
S_BADNAME   FCC  "A bank file's name: up to 8 letters, then .WOP"
            FCB  0
S_MADE      FCC  "Made "
            FCB  0
S_PROGN     FCC  "Program "
            FCB  0

;------------------------------------------------------------------------------
; Its variables (in its page, kept while other overlays are in bank 2).
;------------------------------------------------------------------------------
BKZ         FCB  0          ; (a 0, for clearing)
BKUP        RMB  1          ; a folder listed (the first time the page is shown)
BKFROM      RMB  1          ; the page it came from
BKPLSV      RMB  1          ; Play on, as the instrument page had it
BKFOC       RMB  1          ; the list with the cursor: 0 the files, 1 the instruments
BKFC        RMB  1          ; the files: the cursor, the first shown, how many
BKFT        RMB  1
BKNF        RMB  1
BKIC        RMB  1          ; the instruments: the same (128, or 0 with no bank)
BKIT        RMB  1
BKNI        RMB  1
BKOLD       RMB  1          ; (BKMOVE's: the cursor, the first shown, before)
BKOT        RMB  1
BKDRW       RMB  1
BKHAVE      RMB  1          ; a bank file read
BKERR       RMB  1          ; what went wrong (BKOOPS)
BKDIR       RMB  BK_DIRMAX+1 ; the folder
BKFILE      RMB  13         ; the bank file read (in it)
BKNEWN      RMB  13         ; (a new one's name)
BKPATH      RMB  BK_DIRMAX+15 ; (a path: the folder and a name)
BKHDR       RMB  WOP_HLEN   ; its header
BKIS        RMB  1          ; an instrument's bytes in it: 62, or 66
BKBSZ       RMB  2          ; a bank's: 128 of them
BKMB        RMB  2          ; its melodic banks, its percussion banks
BKPB        RMB  2
BKNM        RMB  1          ; those to look at: the melodic (127 at most), all
BKNB        RMB  1
BKB         RMB  1          ; the one looked at (the melodic first)
BKBASE      RMB  2          ; where the first one's instruments are in the file
BKBNAME     RMB  33         ; its name
BKFH        RMB  1
BKSCN       RMB  1
BKENT       RMB  16         ; a folder's entry read
BKINS       RMB  SK_ILEN    ; the instrument at the cursor, as SONGKIT's: it,
BKNAME      RMB  16         ;   its name,
BKSRC       RMB  16         ;   where it came from (all 64 cleared together)
BKPLAY      RMB  1          ; its drum, in rhythm mode (Play on)
BKKOFF      RMB  2          ; (its key's offset)
BKWREC      RMB  66         ; an instrument as a bank's (^P; a new bank's)
BKOFS       RMB  4
BKLINE      RMB  80         ; a question made
BKN         RMB  1          ; (drawing)
BKE         RMB  1
BKCNT       RMB  1
BKTMP       RMB  2
BKCLKI      RMB  1          ; the instrument clicked last ($FF: none), the frame
BKCLKF      RMB  1          ;   it was clicked in (a double click)
;------------------------------------------------------------------------------
; End of sk_bank.asm
;------------------------------------------------------------------------------
