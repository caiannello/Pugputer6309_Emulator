;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 game kit
;    FILE: sk_core.asm
;
; The parts of SONGKIT every overlay uses, so they stay in the core (bank 3,
; with the variables): the song's pages and the other pages in the window
; (bank 1), the song's bytes read through it, the player's ticks in the middle
; of long work, the instrument being edited, a message and labels drawn.
; (A message's text, a label's, may be in the caller's overlay: these read it
; at once, while that overlay is still the one in bank 2.)
;------------------------------------------------------------------------------

MAXROWS     equ  128        ; the longest pattern edited here
ROWB        equ  100        ; a row in the buffer: 20 cells of 5 bytes

; EMAP, NMAP, IMAP: the pattern buffer's page, the names', or the
; instruments', into the window. (All kept.)
EMAP        PSHS D,X
            PSHSW
            LDE  PBPG
            BRA  EMAP1
IMAP        PSHS D,X
            PSHSW
            LDE  INPG
            BRA  EMAP1
NMAP        PSHS D,X
            PSHSW
            LDE  NMPG
EMAP1       LDB  #WBANK
            LDA  #B_BANK_SET
            SWI2
            PULSW
            PULS D,X,PC
; TICKPOLL: in the middle of long work (with the song as it should be), the
; song's tick, if one is due -- the window the player's for it; the caller's
; page to be put in it again after. (All kept.)
TICKPOLL    TST  SONGON
            BEQ  TKP9
            PSHS D,X,Y,U
            PSHSW
            LDB  SK_PG
            JSR  SKMAP
            JSR  SK_POLL
            PULSW
            PULS D,X,Y,U
TKP9        RTS

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
; FREEPG: the song's pages given back, bank 1 its own again.
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
; SONGOFF: the song stopped, if it was playing (the window is wanted).
SONGOFF     TST  SONGON
            BEQ  SO9
            JSR  SK_STOP
            CLR  SONGON
            JSR  JAMSET
            JSR  O_DRAWSTAT
SO9         RTS

; SETIP: IP and NP, the instrument being edited and its name (copies, in
; CURINST and CURNAME, of the instruments' and names' pages': PUTINST and
; PUTNAME put them back).
SETIP       LDX  #CURINST
            STX  IP
            LDX  #CURNAME
            STX  NP
            BSR  INSTAT
            LDY  #CURINST
            LDW  #SK_ILEN
            TFM  X+,Y+
            BSR  NAMEAT
            LDY  #CURNAME
            LDW  #16
            TFM  X+,Y+
            CLR  ,Y
            RTS
PUTINST     BSR  INSTAT
            TFR  X,Y
            LDX  #CURINST
            LDW  #SK_ILEN
            TFM  X+,Y+
            RTS
; INSTAT: X, instrument CURI in the instruments' page (in the window).
INSTAT      JSR  IMAP
            LDA  CURI
            DECA
            LDB  #SK_ILEN
            MUL
            ADDD #WINDOW
            TFR  D,X
            RTS
PUTNAME     BSR  NAMEAT
            TFR  X,Y
            LDX  #CURNAME
            LDW  #16
            TFM  X+,Y+
            RTS
; NAMEAT: X, instrument CURI's name in the names' page (in the window).
NAMEAT      JSR  NMAP
            LDA  CURI
            DECA
            LDB  #16
            MUL
            ADDD #WINDOW
            TFR  D,X
            RTS
; DRAWLAB: the labels at X: each its column, its row, its color, its text
; (the song's ticks let in as it goes: the window may be the player's after).
DRAWLAB     JSR  TICKPOLL
            LDD  ,X++
            CMPA #$FF
            BEQ  DL9
            JSR  TXAT
            PSHS A
            LDA  ,X+
            STA  TXFG
            PULS A
            JSR  TXSTR
            BRA  DRAWLAB
DL9         RTS
; MSG: the message at X on the bottom row (over the status, until the next
; key).
MSG         PSHS X
            LDA  #1
            STA  MSGUP
            LDB  #29
            JSR  TXROWCLR
            CLRA
            JSR  TXAT
            LDA  #C_MSG
            STA  TXFG
            PULS X
            JMP  TXSTR

; SELBOX: the block -- rows SBR0-SBR1, tracks SBT0-SBT1 (TLIST's) -- from its
; corners (SELR, SELT and SELR2, SELT2, either way round); with none (SELON
; 0), the cursor's cell.
SELBOX      TST  SELON
            BNE  SBX1
            LDA  CROW
            STA  SBR0
            STA  SBR1
            LDA  CTRK
            STA  SBT0
            STA  SBT1
            RTS
SBX1        LDA  SELR
            LDB  SELR2
            BSR  SBXORD
            STD  SBR0
            LDA  SELT
            LDB  SELT2
            BSR  SBXORD
            STD  SBT0
            RTS
SBXORD      PSHS B              ; A, B the smaller, the larger
            CMPA ,S+
            BLS  SBX9
            EXG  A,B
SBX9        RTS
