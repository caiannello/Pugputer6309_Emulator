;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 C library
;    FILE: stdio.asm -- <stdio.h>'s streams: stdin, stdout, stderr, and the
;          characters and lines of any FILE (fileio.asm opens and closes them)
;
; A FILE (libc.d) is a console device or a DOS file. Text mode (every console,
; and a file opened without "b") writes '\n' as CR LF and reads CR, CR LF or LF
; as '\n'. Output isn't buffered here: DOS buffers each open file itself, and
; the console takes each character as it comes.
;
; stdin, from the console, is read a line at a time, echoed as it is typed:
; Backspace (or DEL) takes back a character, Enter ends the line (it gives
; '\n'), and Ctrl-D at the start of a line is the end of the file.
;------------------------------------------------------------------------------
    INCLUDE defines.d
    INCLUDE libc.d
LBUFSZ      equ  128
            EXPORT __iob,__putc,__getc
            EXPORT _fgetc,_getc,_getchar,_fputc,_putc,_putchar,_ungetc
            EXPORT _fputs,_puts,_fgets
            SECTION code
;------------------------------------------------------------------------------
; X = a FILE, B = a character: written. Carry set on an error (FF_ERR set too).
; Keeps X, Y, U.
__putc      LDA  FL_FLAGS,X
            BITA #FF_WRITE
            BEQ  PC_ERR
            CMPB #10
            BNE  PC_ONE
            BITA #FF_TEXT
            BEQ  PC_ONE
            PSHS B                     ; text: '\n' is CR, then LF
            LDB  #13
            BSR  PC_ONE
            PULS B
            BCS  PC_RET
PC_ONE      PSHS X
            TFR  B,E
            LDB  FL_HANDLE,X
            LDA  FL_FLAGS,X
            BITA #FF_CON
            BEQ  PC_DOS
            LDA  #B_PUTC
            SWI2
            PULS X
            ANDCC #$FE
            RTS
PC_DOS      LDA  #B_FPUTC
            SWI2
            PULS X
            BCC  PC_RET
PC_ERR      LDA  FL_FLAGS,X
            ORA  #FF_ERR
            STA  FL_FLAGS,X
            ORCC #1
PC_RET      RTS
;------------------------------------------------------------------------------
; X = a FILE: -> D = its next character (0..255); carry set (and D = EOF) at
; the end of the file (FF_EOF) or on an error (FF_ERR). Keeps X, Y, U, W.
__getc      LDA  FL_FLAGS,X
            BITA #FF_UNGOT
            BEQ  GC_READ
            ANDA #~FF_UNGOT
            STA  FL_FLAGS,X
            LDB  FL_UNGOT,X
            CLRA
            RTS
GC_READ     BITA #FF_READ
            BEQ  GC_ERR
            BITA #FF_CON
            BNE  GC_CON
            BSR  GC_BYTE
            BCS  GC_FAIL
            LDA  FL_FLAGS,X
            BITA #FF_TEXT
            BEQ  GC_OK
            CMPB #13                   ; text: CR (and an LF after it) is '\n'
            BNE  GC_OK
            BSR  GC_BYTE
            BCS  GC_NL                 ; (the end, or an error: later)
            CMPB #10
            BEQ  GC_NL
            STB  FL_UNGOT,X            ; (not an LF: the next character)
            LDA  FL_FLAGS,X
            ORA  #FF_UNGOT
            STA  FL_FLAGS,X
GC_NL       LDB  #10
GC_OK       CLRA
            RTS
GC_CON      JSR  CONREAD
            BCC  GC_RET
            LDA  #ERR_EOF
GC_FAIL     CMPA #ERR_EOF
            BNE  GC_ERR
            LDA  FL_FLAGS,X
            ORA  #FF_EOF
            BRA  GC_FLAG
GC_ERR      LDA  FL_FLAGS,X
            ORA  #FF_ERR
GC_FLAG     STA  FL_FLAGS,X
            LDD  #EOF
            ORCC #1
GC_RET      RTS
; X = a DOS FILE: -> B = its next byte; carry set (A = the DOS status) if none.
GC_BYTE     PSHS X
            LDB  FL_HANDLE,X
            LDA  #B_FGETC
            SWI2
            PULS X
            BCS  GB_RET
            TFR  A,B
            CLRA
GB_RET      RTS
;------------------------------------------------------------------------------
; X = a console FILE: -> D = the next character of the line being read (a new
; line read when that one is used up); carry set for Ctrl-D at a line's start.
CONREAD     PSHS X
            LDB  lpos
            CMPB llen
            BLO  CR_HAVE
            LDB  FL_HANDLE,X
            STB  conh
            CLR  lpos
            CLR  llen
CR_KEY      LDB  conh                  ; (wait for each key)
            LDA  #B_GETC
            SWI2
            BCS  CR_KEY
            CMPA #13
            BEQ  CR_EOL
            CMPA #10
            BEQ  CR_EOL
            CMPA #8
            BEQ  CR_BS
            CMPA #$7F
            BEQ  CR_BS
            CMPA #4
            BEQ  CR_EOT
            CMPA #' '
            BLO  CR_KEY
            LDB  llen                  ; (room is kept for the '\n')
            CMPB #LBUFSZ-1
            BHS  CR_KEY
            LDX  #lbuf
            ABX
            STA  ,X
            INC  llen
            BSR  ECHO
            BRA  CR_KEY
CR_BS       TST  llen
            BEQ  CR_KEY
            DEC  llen
            LDA  #8
            BSR  ECHO
            LDA  #' '
            BSR  ECHO
            LDA  #8
            BSR  ECHO
            BRA  CR_KEY
CR_EOT      TST  llen
            BNE  CR_KEY
            ORCC #1
            PULS X,PC
CR_EOL      LDA  #13
            BSR  ECHO
            LDA  #10
            BSR  ECHO
            LDB  llen
            LDX  #lbuf
            ABX
            LDA  #10
            STA  ,X
            INC  llen
CR_HAVE     LDB  lpos
            INC  lpos
            LDX  #lbuf
            ABX
            LDB  ,X
            CLRA
            PULS X,PC
; A = a character: shown (typing echoed). Keeps D, X, W.
ECHO        PSHS D,X
            PSHSW
            TFR  A,E
            LDB  #F_STDOUT
            LDA  #B_PUTC
            SWI2
            PULSW
            PULS D,X,PC
;------------------------------------------------------------------------------
; int fgetc(FILE *f), int getc(FILE *f), int getchar(void): the next character
; (0..255), or EOF.
_fgetc
_getc       LDX  2,S
            JMP  __getc
_getchar    LDX  #__iob
            JMP  __getc
; int fputc(int c, FILE *f), int putc(int c, FILE *f), int putchar(int c): c
; written -> c (as an unsigned char), or EOF.
_fputc
_putc       LDX  4,S
            BRA  PU_GO
_putchar    LDX  #__iob+FL_SIZE
PU_GO       LDB  3,S
            JSR  __putc
            BCS  PU_EOF
            CLRA
            LDB  3,S
            RTS
PU_EOF      LDD  #EOF
            RTS
; int ungetc(int c, FILE *f): c is fgetc's next -> c, or EOF (c was EOF).
_ungetc     LDD  2,S
            CMPD #EOF
            BEQ  UG_RET
            LDX  4,S
            STB  FL_UNGOT,X
            LDA  FL_FLAGS,X
            ORA  #FF_UNGOT
            ANDA #~FF_EOF
            STA  FL_FLAGS,X
            CLRA
UG_RET      RTS
; int fputs(const char *s, FILE *f) -> 0, or EOF. int puts(const char *s): s
; and '\n' on stdout.
_fputs      PSHS Y
            LDY  4,S
            LDX  6,S
            BSR  PUTSTR
            PULS Y,PC
_puts       PSHS Y
            LDY  4,S
            LDX  #__iob+FL_SIZE
            BSR  PUTSTR
            BCS  PS_RET
            LDB  #10
            JSR  __putc
            BCS  PS_FAIL
            CLRD
PS_RET      PULS Y,PC
PS_FAIL     LDD  #EOF
            PULS Y,PC
; Y = a string, X = a FILE: written -> D = 0, or EOF (carry set).
PUTSTR      LDB  ,Y+
            BEQ  PS_DONE
            JSR  __putc
            BCC  PUTSTR
PS_EOF      LDD  #EOF
            ORCC #1
            RTS
PS_DONE     CLRD
            RTS
; char *fgets(char *buf, int n, FILE *f): a line (with its '\n'), at most n - 1
; characters, and a NUL -> buf; NULL if the end came before any character.
_fgets      PSHS Y
            LDY  4,S
            LDX  8,S
            LDD  6,S
            SUBD #1
            BLT  FG_NULL
            TFR  D,W
FG_LOOP     TSTW
            BEQ  FG_END
            JSR  __getc
            BCS  FG_EOF
            STB  ,Y+
            DECW
            CMPB #10
            BNE  FG_LOOP
FG_END      CLR  ,Y
            LDD  4,S
            PULS Y,PC
FG_EOF      CMPY 4,S
            BNE  FG_END
FG_NULL     CLRD
            PULS Y,PC
            ENDSECT
;------------------------------------------------------------------------------
            SECTION data
__iob       FCB  FF_USED|FF_READ|FF_CON|FF_TEXT,F_STDIN,0,0
            FCB  FF_USED|FF_WRITE|FF_CON|FF_TEXT,F_STDOUT,0,0
            FCB  FF_USED|FF_WRITE|FF_CON|FF_TEXT,F_STDERR,0,0
            ZMB  DOS_NFILES*FL_SIZE
            ENDSECT
            SECTION bss
lbuf        RMB  LBUFSZ                ; stdin's line
lpos        RMB  1
llen        RMB  1
conh        RMB  1
            ENDSECT
;------------------------------------------------------------------------------
; End of stdio.asm
;------------------------------------------------------------------------------
