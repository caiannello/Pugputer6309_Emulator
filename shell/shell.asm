;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 shell
;    FILE: shell.asm
;
; The command interpreter DOS starts at boot (and again whenever a program calls
; B_EXIT): /SHELL.COM, an ordinary program file (8-byte header, see EXE_* in
; bios/defines.d) that loads at $4000. It talks to the console and to DOS only
; through BIOS SWI2 calls, like any program.
;
; A line is a command word followed by arguments. Built-in commands:
;   DIR [path]      CD [path]       MD|MKDIR path    RD|RMDIR path
;   DEL|ERASE path  REN old new     TYPE file        COPY from to
;   VER             MEM             HELP
; Anything else is a program: NAME runs NAME.COM (or NAME as typed, if it has an
; extension) from the current directory, else from the root, passing the rest of
; the line as its command tail (see B_EXEC / B_ARGS).
;------------------------------------------------------------------------------
    INCLUDE defines.d
;------------------------------------------------------------------------------
SHELL_BASE  equ  $4000
LINEMAX     equ  79            ; longest command line
WORDMAX     equ  40            ; longest command word / program path
PATHMAXLEN  equ  80
;------------------------------------------------------------------------------
    ORG  SHELL_BASE-EXE_HDRSIZE
    FDB  EXE_MAGIC             ; the program header
    FDB  SHELL_BASE            ; load address
    FDB  START                 ; entry
    FDB  0                     ; flags
;------------------------------------------------------------------------------
START       LDS  #$7F00
            LDX  #MSG_BANNER
            JSR  PUTS
MAIN        JSR  PROMPT
            JSR  READLINE
            JSR  NEWLINE
            JSR  DISPATCH
            BRA  MAIN
;------------------------------------------------------------------------------
; Console helpers (all preserve X and Y; they trash A, B, E).
;------------------------------------------------------------------------------
PUTS        LDB  #F_STDOUT             ; X = a NUL-terminated string
            LDA  #B_PUTS
            SWI2
            RTS
PUTC        TFR  A,E                   ; A = a character
            LDB  #F_STDOUT
            LDA  #B_PUTC
            SWI2
            RTS
NEWLINE     LDA  #CR
            JSR  PUTC
            LDA  #LF
            JMP  PUTC
PUTSP       LDA  #' '
            JMP  PUTC
GETC        LDB  #F_STDIN              ; -> A = the next key (waits for one)
            LDA  #B_GETC
            SWI2
            BCS  GETC
            RTS
PUTHEX      PSHS A                     ; A as two hex digits
            LSRA
            LSRA
            LSRA
            LSRA
            BSR  HEXDIG
            PULS A
            ANDA #$0F
HEXDIG      CMPA #10
            BLO  HD_NUM
            ADDA #7
HD_NUM      ADDA #'0'
            JMP  PUTC
;------------------------------------------------------------------------------
; The unsigned 32-bit value in Q (D = high word, W = low word) in decimal.
;------------------------------------------------------------------------------
PRINTDEC    STQ  PDVAL
            CLR  PDSTART
            LDX  #PDPOW
PD_DIGIT    CLR  PDDIG
PD_SUB      LDQ  PDVAL                 ; subtract this power of ten while it fits
            SUBW 2,X
            SBCD ,X
            BCS  PD_EMIT
            STQ  PDVAL
            INC  PDDIG
            BRA  PD_SUB
PD_EMIT     LDA  PDDIG
            BNE  PD_PRINT
            TST  PDSTART
            BNE  PD_PRINT
            CMPX #PDPOW_LAST
            BNE  PD_NEXT               ; a leading zero
PD_PRINT    INC  PDSTART
            ADDA #'0'
            JSR  PUTC
PD_NEXT     LEAX 4,X
            CMPX #PDPOW_END
            BNE  PD_DIGIT
            RTS
PDPOW       FDB  $3B9A,$CA00           ; 1000000000
            FDB  $05F5,$E100           ; 100000000
            FDB  $0098,$9680           ; 10000000
            FDB  $000F,$4240           ; 1000000
            FDB  $0001,$86A0           ; 100000
            FDB  $0000,$2710           ; 10000
            FDB  $0000,$03E8           ; 1000
            FDB  $0000,$0064           ; 100
            FDB  $0000,$000A           ; 10
PDPOW_LAST  FDB  $0000,$0001           ; 1
PDPOW_END
;------------------------------------------------------------------------------
; A = a DOS error code: prints its message.
;------------------------------------------------------------------------------
PRINT_ERR   STA  ERRCODE
            LDX  #ERRTAB
PE_LOOP     LDA  ,X
            BEQ  PE_GENERIC
            CMPA ERRCODE
            BEQ  PE_FOUND
            LEAX 3,X
            BRA  PE_LOOP
PE_FOUND    LDX  1,X
            JSR  PUTS
            JMP  NEWLINE
PE_GENERIC  LDX  #MSG_ERR
            JSR  PUTS
            LDA  ERRCODE
            JSR  PUTHEX
            JMP  NEWLINE
ERRTAB      FCB  ERR_NOTFOUND
            FDB  MSG_NOTFOUND
            FCB  ERR_EXISTS
            FDB  MSG_EXISTS
            FCB  ERR_NOSPACE
            FDB  MSG_NOSPACE
            FCB  ERR_ISOPEN
            FDB  MSG_ISOPEN
            FCB  ERR_NOTDIR
            FDB  MSG_NOTDIR
            FCB  ERR_ISDIR
            FDB  MSG_ISDIR
            FCB  ERR_NOTEMPTY
            FDB  MSG_NOTEMPTY
            FCB  ERR_BADPATH
            FDB  MSG_BADPATH
            FCB  ERR_NOSLOT
            FDB  MSG_NOSLOT
            FCB  ERR_BADEXE
            FDB  MSG_BADEXE
            FCB  ERR_TOOBIG
            FDB  MSG_TOOBIG
            FCB  ERR_IOERR
            FDB  MSG_IOERR
            FCB  0
;------------------------------------------------------------------------------
; "/DIR> " -- the current directory, then ">".
;------------------------------------------------------------------------------
PROMPT      LDX  #PATHBUF
            LDY  #PATHMAXLEN
            LDA  #B_GETCWD
            SWI2
            BCS  PR_NOCWD
            LDX  #PATHBUF
            JSR  PUTS
PR_NOCWD    LDA  #'>'
            JSR  PUTC
            JMP  PUTSP
;------------------------------------------------------------------------------
; Reads a line into LINEBUF (NUL-terminated), echoing it. Backspace/Delete
; erase, Ctrl-C abandons the line, other control characters are ignored.
;------------------------------------------------------------------------------
READLINE    CLR  LINELEN
RL_KEY      JSR  GETC
            CMPA #CR
            BEQ  RL_END
            CMPA #LF
            BEQ  RL_END
            CMPA #8
            BEQ  RL_BS
            CMPA #$7F
            BEQ  RL_BS
            CMPA #3
            BEQ  RL_CANCEL
            CMPA #' '
            BLO  RL_KEY
            LDB  LINELEN
            CMPB #LINEMAX
            BHS  RL_KEY                ; line full: ignore
            LDX  #LINEBUF
            ABX
            STA  ,X
            INC  LINELEN
            JSR  PUTC                  ; echo
            BRA  RL_KEY
RL_BS       TST  LINELEN
            BEQ  RL_KEY
            DEC  LINELEN
            LDX  #MSG_BS
            JSR  PUTS
            BRA  RL_KEY
RL_CANCEL   LDX  #MSG_CANCEL
            JSR  PUTS
            CLR  LINELEN
RL_END      LDB  LINELEN
            LDX  #LINEBUF
            ABX
            CLR  ,X
            RTS
;------------------------------------------------------------------------------
; Splits LINEBUF into the command word (CMDWORD, upper-cased) and ARGP (the rest of
; the line after its leading blanks, in LINEBUF), then runs a built-in or a program.
;------------------------------------------------------------------------------
DISPATCH    LDX  #LINEBUF
DS_SKIP     LDA  ,X
            CMPA #' '
            BNE  DS_WORD
            LEAX 1,X
            BRA  DS_SKIP
DS_WORD     TSTA
            BEQ  DS_RET                ; a blank line
            LDY  #CMDWORD
            LDB  #WORDMAX
DS_COPY     LDA  ,X
            BEQ  DS_COPIED
            CMPA #' '
            BEQ  DS_COPIED
            TSTB
            BEQ  DS_LONG               ; a word too long to be anything
            CMPA #'a'
            BLO  DS_STORE
            CMPA #'z'
            BHI  DS_STORE
            SUBA #$20
DS_STORE    STA  ,Y+
            LEAX 1,X
            DECB
            BRA  DS_COPY
DS_COPIED   CLR  ,Y
DS_ARGS     LDA  ,X
            CMPA #' '
            BNE  DS_HAVEARGS
            LEAX 1,X
            BRA  DS_ARGS
DS_HAVEARGS STX  ARGP
            LDU  #COMMANDS
DS_FIND     LDA  ,U
            BEQ  DS_PROGRAM            ; end of the table: not a built-in
            LDX  #CMDWORD
            LEAY ,U
DS_CMP      LDA  ,Y
            CMPA ,X+
            BNE  DS_NEXT
            LEAY 1,Y
            TSTA
            BNE  DS_CMP
            JMP  [,Y]                  ; matched: Y is at the handler's address
DS_NEXT     LDA  ,U+                   ; skip this entry: its name ...
            BNE  DS_NEXT
            LEAU 2,U                   ; ... and its handler address
            BRA  DS_FIND
DS_LONG     LDX  #MSG_BADCMD
            JMP  PUTS
DS_RET      RTS
;------------------------------------------------------------------------------
; Not a built-in: a program. The word becomes a path (".COM" added when its last
; part has no extension), tried as typed and then, for a bare name, in the root.
;------------------------------------------------------------------------------
DS_PROGRAM  LDX  #CMDWORD
            LDY  #PATHBUF
            CLR  HASDOT
            CLR  HASSLASH
PG_LOOP     LDA  ,X+
            BEQ  PG_DONE
            STA  ,Y+
            CMPA #'/'
            BNE  PG_NOTSL
            LDB  #1
            STB  HASSLASH
            CLR  HASDOT
            BRA  PG_LOOP
PG_NOTSL    CMPA #'.'
            BNE  PG_LOOP
            LDB  #1
            STB  HASDOT
            BRA  PG_LOOP
PG_DONE     TST  HASDOT
            BNE  PG_TERM
            LDX  #EXT_COM
PG_EXT      LDA  ,X+
            BEQ  PG_TERM
            STA  ,Y+
            BRA  PG_EXT
PG_TERM     CLR  ,Y
            LDX  #PATHBUF              ; first try: the name as given
            LDY  ARGP
            LDA  #B_EXEC
            SWI2                       ; (comes back only if it could not start it)
            CMPA #ERR_NOTFOUND
            BNE  PG_FAIL
            TST  HASSLASH
            BNE  PG_FAIL               ; an explicit path: no second try
            LDX  #PATHBUF2             ; second try: "/" + the name
            LDA  #'/'
            STA  ,X+
            LDY  #PATHBUF
PG_COPY2    LDA  ,Y+
            STA  ,X+
            BNE  PG_COPY2
            LDX  #PATHBUF2
            LDY  ARGP
            LDA  #B_EXEC
            SWI2
PG_FAIL     CMPA #ERR_NOTFOUND
            BEQ  PG_BAD
            CMPA #ERR_ISDIR
            BEQ  PG_BAD
            CMPA #ERR_BADPATH          ; e.g. a word too long to be an 8.3 name
            BEQ  PG_BAD
            JMP  PRINT_ERR
PG_BAD      LDX  #MSG_BADCMD
            JMP  PUTS
;------------------------------------------------------------------------------
; The built-in commands. Each is entered with ARGP = its argument text and ends with
; RTS; DOS errors come back as carry + A and are printed by ERR_OUT.
;------------------------------------------------------------------------------
ERR_OUT     JMP  PRINT_ERR
NOARG       LDX  #MSG_NOARG
            JMP  PUTS
;------------------------------------------------------------------------------
CMD_DIR     LDX  ARGP
            LDA  #B_OPENDIR
            SWI2
            LBCS ERR_OUT
            STA  DIRH
DR_LOOP     LDB  DIRH
            LDX  #ENTBUF
            LDA  #B_READDIR
            SWI2
            BCS  DR_END                ; ERR_EOF: the end (or an error: stop anyway)
            LDA  ENTBUF
            CMPA #'.'
            BEQ  DR_LOOP               ; "." and ".."
            JSR  PRINT_ENTRY
            BRA  DR_LOOP
DR_END      LDB  DIRH
            LDA  #B_CLOSEDIR
            SWI2
            RTS
; One directory entry (ENTBUF: 11-byte name, attribute, 32-bit size): "NAME.EXT"
; padded to 13 columns, then <DIR> or the size in bytes.
PRINT_ENTRY LDX  #ENTBUF
            LDY  #NAMEBUF
            LDB  #8
PE_B        LDA  ,X+
            CMPA #' '
            BEQ  PE_EXT
            STA  ,Y+
            DECB
            BNE  PE_B
PE_EXT      LDX  #ENTBUF+8
            LDA  ,X
            CMPA #' '
            BEQ  PE_PAD
            LDA  #'.'
            STA  ,Y+
            LDB  #3
PE_E        LDA  ,X+
            CMPA #' '
            BEQ  PE_PAD
            STA  ,Y+
            DECB
            BNE  PE_E
PE_PAD      LDA  #' '
PE_P        CMPY #NAMEBUF+13
            BHS  PE_PDONE
            STA  ,Y+
            BRA  PE_P
PE_PDONE    CLR  ,Y
            LDX  #NAMEBUF
            JSR  PUTS
            LDA  ENTBUF+11
            ANDA #ATTR_DIR
            BEQ  PE_SIZE
            LDX  #MSG_DIRTAG
            JSR  PUTS
            JMP  NEWLINE
PE_SIZE     LDQ  ENTBUF+12
            JSR  PRINTDEC
            JMP  NEWLINE
;------------------------------------------------------------------------------
CMD_CD      LDX  ARGP
            LDA  ,X
            BEQ  CD_SHOW
            LDA  #B_CHDIR
            SWI2
            LBCS ERR_OUT
            RTS
CD_SHOW     LDX  #PATHBUF
            LDY  #PATHMAXLEN
            LDA  #B_GETCWD
            SWI2
            LBCS ERR_OUT
            LDX  #PATHBUF
            JSR  PUTS
            JMP  NEWLINE
;------------------------------------------------------------------------------
CMD_MD      LDA  #B_MKDIR
            BRA  PATHCMD
CMD_RD      LDA  #B_RMDIR
            BRA  PATHCMD
CMD_DEL     LDA  #B_KILL_NAME
PATHCMD     STA  FUNC                  ; a call taking one path: X = ARGP
            LDX  ARGP
            LDA  ,X
            LBEQ NOARG
            LDA  FUNC
            SWI2
            LBCS ERR_OUT
            RTS
;------------------------------------------------------------------------------
; Splits ARGP into two words: ARGP -> the first (NUL-terminated in place), DSTP -> the
; second. Carry set if there aren't two.
SPLIT2      LDX  ARGP
            LDA  ,X
            BEQ  SP_MISSING
SP_SCAN     LDA  ,X+
            BEQ  SP_MISSING
            CMPA #' '
            BNE  SP_SCAN
            CLR  -1,X
SP_SKIP     LDA  ,X
            CMPA #' '
            BNE  SP_SECOND
            LEAX 1,X
            BRA  SP_SKIP
SP_SECOND   TSTA
            BEQ  SP_MISSING
            STX  DSTP
            ANDCC #$FE
            RTS
SP_MISSING  ORCC #1
            RTS
;------------------------------------------------------------------------------
CMD_REN     JSR  SPLIT2
            LBCS NOARG
            LDX  ARGP
            LDY  DSTP
            LDA  #B_RENAME_NAME
            SWI2
            LBCS ERR_OUT
            RTS
;------------------------------------------------------------------------------
CMD_TYPE    LDX  ARGP
            LDA  ,X
            LBEQ NOARG
            LDE  #FOPEN_READ
            LDA  #B_FOPEN_NAME
            SWI2
            LBCS ERR_OUT
            STA  FH1
TY_LOOP     LDB  FH1
            LDX  #IOBUF
            LDY  #128
            LDA  #B_FREAD
            SWI2
            BCS  TY_END
            CMPX #0
            BEQ  TY_END
            TFR  X,Y
            LDX  #IOBUF
            LDB  #F_STDOUT
            LDA  #B_PUT
            SWI2
            BRA  TY_LOOP
TY_END      LDB  FH1
            LDA  #B_FCLOSE_NAME
            SWI2
            JMP  NEWLINE
;------------------------------------------------------------------------------
CMD_COPY    JSR  SPLIT2
            LBCS NOARG
            LDX  ARGP
            LDE  #FOPEN_READ
            LDA  #B_FOPEN_NAME
            SWI2
            LBCS ERR_OUT
            STA  FH1
            LDX  DSTP
            LDE  #FOPEN_WRITE
            LDA  #B_FOPEN_NAME
            SWI2
            BCS  CP_OPENFAIL
            STA  FH2
CP_LOOP     LDB  FH1
            LDX  #IOBUF
            LDY  #512
            LDA  #B_FREAD
            SWI2
            BCS  CP_FAIL
            CMPX #0
            BEQ  CP_DONE
            TFR  X,Y
            LDX  #IOBUF
            LDB  FH2
            LDA  #B_FWRITE
            SWI2
            BCS  CP_FAIL
            BRA  CP_LOOP
CP_DONE     LDB  FH2
            LDA  #B_FCLOSE_NAME
            SWI2
            BCS  CP_CLOSE1
            LDB  FH1
            LDA  #B_FCLOSE_NAME
            SWI2
            LDX  #MSG_COPIED
            JMP  PUTS
CP_FAIL     STA  ERRSAVE               ; a read or write failed: close both, say why
            LDB  FH2
            LDA  #B_FCLOSE_NAME
            SWI2
            LDB  FH1
            LDA  #B_FCLOSE_NAME
            SWI2
            LDA  ERRSAVE
            JMP  PRINT_ERR
CP_OPENFAIL STA  ERRSAVE               ; the destination wouldn't open: close the source
            LDB  FH1
            LDA  #B_FCLOSE_NAME
            SWI2
            LDA  ERRSAVE
            JMP  PRINT_ERR
CP_CLOSE1   STA  ERRSAVE               ; the destination failed to close (disk full ...)
            LDB  FH1
            LDA  #B_FCLOSE_NAME
            SWI2
            LDA  ERRSAVE
            JMP  PRINT_ERR
;------------------------------------------------------------------------------
CMD_VER     LDA  #B_DOS_VERSION
            SWI2
            STA  VERBYTE
            LDX  #MSG_VER
            JSR  PUTS
            LDA  VERBYTE
            LSRA
            LSRA
            LSRA
            LSRA
            ADDA #'0'
            JSR  PUTC
            LDA  #'.'
            JSR  PUTC
            LDA  VERBYTE
            ANDA #$0F
            ADDA #'0'
            JSR  PUTC
            JMP  NEWLINE
;------------------------------------------------------------------------------
CMD_MEM     LDA  #B_PAGE_INFO
            SWI2                       ; X = installed 16KB pages, Y = pages free
            STX  MEMTOT
            STY  MEMFREE
            LDX  #MSG_RAM
            JSR  PUTS
            LDD  MEMTOT
            JSR  PRINT_KB
            LDX  #MSG_PAGES
            JSR  PUTS
            LDD  MEMFREE
            JSR  PRINT_KB
            LDX  #MSG_FREE
            JSR  PUTS
            JMP  NEWLINE
; D = a number of 16KB pages: prints it as KB.
PRINT_KB    ASLD
            ASLD
            ASLD
            ASLD
            TFR  D,W
            CLRD
            JMP  PRINTDEC
;------------------------------------------------------------------------------
CMD_HELP    LDX  #MSG_HELP
            JMP  PUTS
;------------------------------------------------------------------------------
; The built-ins: NAME, NUL, the handler's address.
COMMANDS    FCC  "DIR"
            FCB  0
            FDB  CMD_DIR
            FCC  "CD"
            FCB  0
            FDB  CMD_CD
            FCC  "CHDIR"
            FCB  0
            FDB  CMD_CD
            FCC  "MD"
            FCB  0
            FDB  CMD_MD
            FCC  "MKDIR"
            FCB  0
            FDB  CMD_MD
            FCC  "RD"
            FCB  0
            FDB  CMD_RD
            FCC  "RMDIR"
            FCB  0
            FDB  CMD_RD
            FCC  "DEL"
            FCB  0
            FDB  CMD_DEL
            FCC  "ERASE"
            FCB  0
            FDB  CMD_DEL
            FCC  "REN"
            FCB  0
            FDB  CMD_REN
            FCC  "TYPE"
            FCB  0
            FDB  CMD_TYPE
            FCC  "COPY"
            FCB  0
            FDB  CMD_COPY
            FCC  "VER"
            FCB  0
            FDB  CMD_VER
            FCC  "MEM"
            FCB  0
            FDB  CMD_MEM
            FCC  "HELP"
            FCB  0
            FDB  CMD_HELP
            FCB  0
;------------------------------------------------------------------------------
EXT_COM     FCC  ".COM"
            FCB  0
MSG_BANNER  FCB  CR,LF
            FCC  "Pugputer 6309 shell -- HELP lists the commands"
            FCB  CR,LF,0
MSG_BS      FCB  8
            FCC  " "
            FCB  8,0
MSG_CANCEL  FCC  "^C"
            FCB  0
MSG_BADCMD  FCC  "Bad command or file name"
            FCB  CR,LF,0
MSG_NOARG   FCC  "Missing argument"
            FCB  CR,LF,0
MSG_DIRTAG  FCC  "<DIR>"
            FCB  0
MSG_COPIED  FCC  "        1 file copied"
            FCB  CR,LF,0
MSG_VER     FCC  "Pugputer 6309 DOS "
            FCB  0
MSG_RAM     FCC  "RAM: "
            FCB  0
MSG_PAGES   FCC  " KB installed, "
            FCB  0
MSG_FREE    FCC  " KB free for programs"
            FCB  0
MSG_ERR     FCC  "Error $"
            FCB  0
MSG_NOTFOUND FCC "File not found"
            FCB  0
MSG_EXISTS  FCC  "Already exists"
            FCB  0
MSG_NOSPACE FCC  "Disk full"
            FCB  0
MSG_ISOPEN  FCC  "File is in use"
            FCB  0
MSG_NOTDIR  FCC  "Not a directory"
            FCB  0
MSG_ISDIR   FCC  "Is a directory"
            FCB  0
MSG_NOTEMPTY FCC "Directory not empty"
            FCB  0
MSG_BADPATH FCC  "Bad name or path"
            FCB  0
MSG_NOSLOT  FCC  "Too many open files"
            FCB  0
MSG_BADEXE  FCC  "Not a program file"
            FCB  0
MSG_TOOBIG  FCC  "Too big"
            FCB  0
MSG_IOERR   FCC  "Disk error"
            FCB  0
MSG_HELP    FCC  "DIR [path]        list a directory"
            FCB  CR,LF
            FCC  "CD [path]         change directory / show it"
            FCB  CR,LF
            FCC  "MD path  RD path  make / remove a directory"
            FCB  CR,LF
            FCC  "DEL path          delete a file"
            FCB  CR,LF
            FCC  "REN old new       rename"
            FCB  CR,LF
            FCC  "TYPE file         show a file"
            FCB  CR,LF
            FCC  "COPY from to      copy a file"
            FCB  CR,LF
            FCC  "VER  MEM          version, memory"
            FCB  CR,LF
            FCC  "name [args]       run name.COM (BASIC starts BASIC)"
            FCB  CR,LF,0
;------------------------------------------------------------------------------
; Variables and buffers are just addresses after the last byte of code: nothing
; here is in shell.bin.
;------------------------------------------------------------------------------
SHELL_VARS  equ  *
LINEBUF     equ  SHELL_VARS            ; 84
PATHBUF     equ  LINEBUF+84            ; 84
PATHBUF2    equ  PATHBUF+84            ; 88
CMDWORD     equ  PATHBUF2+88           ; 44
ENTBUF      equ  CMDWORD+44            ; 16
NAMEBUF     equ  ENTBUF+16             ; 16
IOBUF       equ  NAMEBUF+16            ; 512
VAR0        equ  IOBUF+512
LINELEN     equ  VAR0
ARGP        equ  VAR0+1                ; 2
DSTP        equ  VAR0+3                ; 2
HASDOT      equ  VAR0+5
HASSLASH    equ  VAR0+6
ERRCODE     equ  VAR0+7
ERRSAVE     equ  VAR0+8
FUNC        equ  VAR0+9
DIRH        equ  VAR0+10
FH1         equ  VAR0+11
FH2         equ  VAR0+12
VERBYTE     equ  VAR0+13
MEMTOT      equ  VAR0+14               ; 2
MEMFREE     equ  VAR0+16               ; 2
PDVAL       equ  VAR0+18               ; 4
PDSTART     equ  VAR0+22
PDDIG       equ  VAR0+23
SHELL_END   equ  VAR0+24
;------------------------------------------------------------------------------
; End of shell.asm
;------------------------------------------------------------------------------
