;------------------------------------------------------------------------------
; pa_io.asm -- pugasm: the command line, and the input stack (source files,
; INCLUDEs and macro expansions) that READLINE takes lines from. (The output
; streams are in pa_strm.asm, shared with PUGLINK.)
;------------------------------------------------------------------------------
; An input record (INSTACK, one a level; INP = the top one):
IR_TYPE     equ  0                 ; IT_FILE or IT_MACRO
IR_HANDLE   equ  1                 ; file: the DOS handle
IR_POS      equ  2                 ; file: next byte in the buffer
IR_LEN      equ  4                 ; file: bytes in the buffer
IR_LINENO   equ  6                 ; the line number of the last line read
IR_EOF      equ  8                 ; file: the end has been reached
IR_UNGETF   equ  9                 ; file: a byte was put back
IR_UNGETC   equ  10
IR_BUF      equ  11                ; file: its 256-byte buffer
IR_MLINE    equ  13                ; macro: the next body line (far pointer)
IR_SAVECTX  equ  16                ; macro: the local-symbol context to go back to
IR_NARGS    equ  18                ; macro: the arguments
IR_ARGS     equ  19                ; macro: where they are (NUL-terminated, in a row)
IR_MACP     equ  21                ; macro: its record (far pointer)
IR_SPEC     equ  32                ; the name shown in the listing (47 characters)
IR_PATH     equ  80                ; file: the path it was opened by
INREC       equ  160
IT_FILE     equ  1
IT_MACRO    equ  2
;------------------------------------------------------------------------------
; The command line.
;------------------------------------------------------------------------------
CMDLINE     LDA  #B_ARGS
            SWI2
CL_NEXT     JSR  SKIPSP
            LDA  ,X
            LBEQ CL_DONE
            CMPA #'-'
            LBNE CL_FILE
            LDA  1,X
            CMPA #'-'
            BEQ  CL_LONG
            LEAX 2,X                   ; a short option: -3 -9 -s -l[f] -o f -f f -I d
            CMPA #'3'
            BEQ  CL_6309
            CMPA #'9'
            BEQ  CL_6809
            CMPA #'s'
            BEQ  CL_SYMS
            CMPA #'l'
            BEQ  CL_LIST
            CMPA #'o'
            BEQ  CL_OUT
            CMPA #'f'
            BEQ  CL_FMT
            CMPA #'I'
            BEQ  CL_INC
            LBRA USAGE
CL_6309     CLR  <CPU
            BRA  CL_NEXT
CL_6809     LDA  #1
            STA  <CPU
            BRA  CL_NEXT
CL_SYMS     LDA  #1
            STA  <SYMLIST
            BRA  CL_NEXT
CL_LIST     LDA  #1                    ; -l, or -lFILE (no space)
            STA  <LISTON
            LDA  ,X
            BEQ  CL_NEXT
            JSR  ISSPACE
            BCC  CL_NEXT
CL_LISTNM   LDY  #LSTNAME
            JSR  GETWORD
            BRA  CL_NEXT
CL_OUT      JSR  OPTARG
            LDY  #OUTNAME
            JSR  GETWORD
            BRA  CL_NEXT
CL_FMT      JSR  OPTARG
            JSR  SETFORMAT
            BRA  CL_NEXT
CL_INC      JSR  OPTARG
            JSR  ADDINCDIR
            BRA  CL_NEXT
CL_LONG     LDY  #LONGOPTS             ; --name or --name=value
CL_LTRY     LDA  ,Y
            LBEQ USAGE
            JSR  PREFIX                ; does X start with the name at Y?
            BEQ  CL_LFOUND
CL_LSKIP    LDA  ,Y+                   ; next entry: past its name and its code
            BNE  CL_LSKIP
            LEAY 1,Y
            BRA  CL_LTRY
CL_LFOUND   LDA  ,Y                    ; X is past the name; Y at its code
            CMPA #1
            BEQ  CL_6309
            CMPA #2
            BEQ  CL_6809
            CMPA #3
            BEQ  CL_SYMS
            CMPA #4
            BEQ  CL_LLIST
            CMPA #5
            BEQ  CL_OUT2
            CMPA #6
            BEQ  CL_FMT2
            CMPA #7
            BEQ  CL_INC2
            LBRA USAGE
CL_LLIST    LDA  #1                    ; --list or --list=FILE
            STA  <LISTON
            LDA  ,X
            CMPA #'='
            LBNE CL_NEXT
            LEAX 1,X
            BRA  CL_LISTNM
CL_OUT2     LDY  #OUTNAME
            JSR  GETWORD
            LBRA CL_NEXT
CL_FMT2     JSR  SETFORMAT
            LBRA CL_NEXT
CL_INC2     JSR  ADDINCDIR
            LBRA CL_NEXT
CL_FILE     TST  SRCNAME               ; the source file
            LBNE USAGE
            LDY  #SRCNAME
            JSR  GETWORD
            LBRA CL_NEXT
CL_DONE     TST  SRCNAME
            BEQ  USAGE
            TST  OUTNAME               ; default names
            BNE  CL_OUTOK
            LDB  <FORMAT
            LDX  #FMTEXTS
            LDA  #5
            MUL
            ABX
            LDY  #OUTNAME
            JSR  NEWEXT
CL_OUTOK    TST  <LISTON
            BEQ  CL_RET
            TST  LSTNAME
            BNE  CL_RET
            LDX  #EXT_LST
            LDY  #LSTNAME
            JSR  NEWEXT
CL_RET      RTS
USAGE       LDX  #M_USAGE
            JSR  PRINTS
            LDA  #B_EXIT
            SWI2
; X is just past an option letter: to its argument (attached, or the next word).
OPTARG      LDA  ,X
            BEQ  OA_NEXT
            JSR  ISSPACE
            BCS  OA_RET
OA_NEXT     JSR  SKIPSP
            LDA  ,X
            BEQ  USAGE
OA_RET      RTS
; X -> Y: a word (to a space or the end), at most PATHMAX characters.
GETWORD     LDB  #PATHMAX
GW_LOOP     LDA  ,X
            BEQ  GW_END
            JSR  ISSPACE
            BCC  GW_END
            LEAX 1,X
            TSTB
            BEQ  GW_LOOP
            STA  ,Y+
            DECB
            BRA  GW_LOOP
GW_END      CLR  ,Y
            RTS
; Z set if the string at X starts with the (NUL-terminated) one at Y: X then past
; it, Y at its NUL + 1. Otherwise X is unchanged.
PREFIX      PSHS X
PF_LOOP     LDA  ,Y+
            BEQ  PF_YES
            CMPA ,X+
            BEQ  PF_LOOP
            PULS X
            LEAY -1,Y                  ; (not matched: Y back on a name character)
            ANDCC #$FB
            RTS
PF_YES      LEAS 2,S
            ORCC #4
            RTS
; X = a format name: FORMAT.
SETFORMAT   LDY  #NAMEBUF
            JSR  GETWORD
            PSHS X
            LDY  #FMTNAMES
            CLRB
SF_TRY      LDA  ,Y
            BEQ  SF_BAD
            LDX  #NAMEBUF
            JSR  STRCMPI
            BEQ  SF_FOUND
SF_SKIP     TST  ,Y+
            BNE  SF_SKIP
            INCB
            BRA  SF_TRY
SF_FOUND    STB  <FORMAT
            PULS X,PC
SF_BAD      LDX  #M_BADFMT
            JMP  FATAL
; X = a directory: added to INCDIRS.
ADDINCDIR   LDA  <NINCDIR
            CMPA #MAXINCDIR
            BHS  AI_SKIP
            LDB  #PATHMAX+1
            MUL
            LDY  #INCDIRS
            LEAY D,Y
            INC  <NINCDIR
            JMP  GETWORD
AI_SKIP     LDY  #NAMEBUF
            JMP  GETWORD
; SRCNAME with its extension replaced by the one at X -> Y.
NEWEXT      PSHS X                     ; the extension
            PSHS Y                     ; where the name starts
            LDX  #SRCNAME
            JSR  STRCPY                ; Y at the NUL
            TFR  Y,U
NE_BACK     CMPY ,S
            BEQ  NE_ADD
            LDA  -1,Y
            CMPA #'/'
            BEQ  NE_ADD
            CMPA #'.'
            BEQ  NE_DOT
            LEAY -1,Y
            BRA  NE_BACK
NE_DOT      LEAY -1,Y                  ; the dot: the extension goes from here
            BRA  NE_PUT
NE_ADD      TFR  U,Y                   ; no extension: add one at the end
NE_PUT      LEAS 2,S
            PULS X
            JMP  STRCPY
LONGOPTS    FCN  "6309"
            FCB  1
            FCN  "6809"
            FCB  2
            FCN  "symbols"
            FCB  3
            FCN  "list"
            FCB  4
            FCN  "output="
            FCB  5
            FCN  "format="
            FCB  6
            FCN  "includedir="
            FCB  7
            FCB  0
FMTNAMES    FCN  "raw"
            FCN  "srec"
            FCN  "com"
            FCN  "obj"
            FCB  0
FMTEXTS     FCN  ".BIN"
            FCN  ".S19"
            FCN  ".COM"
            FCB  '.','O',0,0,0
EXT_LST     FCN  ".LST"
;------------------------------------------------------------------------------
; The input stack.
;------------------------------------------------------------------------------
; -> U = a new (cleared) record on top of the stack.
PUSHIN      LDA  <ISP
            CMPA #MAXDEPTH
            BHS  PI_DEEP
            LDB  #INREC
            MUL
            LDU  #INSTACK
            LEAU D,U
            STU  <INP
            PSHS X
            LDX  #INBUFS               ; its buffer: INBUFS + level * 256
            TFR  X,D
            ADDA <ISP
            STD  IR_BUF,U
            LDX  #MACARGS              ; its macro arguments: MACARGS + level * 128
            LDA  <ISP
            LDB  #128
            MUL
            LEAX D,X
            STX  IR_ARGS,U
            PULS X
            INC  <ISP
            LDD  #0
            STD  IR_POS,U
            STD  IR_LEN,U
            STD  IR_LINENO,U
            CLR  IR_EOF,U
            CLR  IR_UNGETF,U
            CLR  IR_SPEC,U
            CLR  IR_PATH,U
            RTS
PI_DEEP     LDX  #M_DEEP
            JMP  FATAL
; Drops the top record (closing its file, or ending its macro).
POPIN       LDU  <INP
            LDA  IR_TYPE,U
            CMPA #IT_FILE
            BNE  PO_MAC
            LDB  IR_HANDLE,U
            LDA  #B_FCLOSE_NAME
            SWI2
            BRA  PO_DROP
PO_MAC      LDD  IR_SAVECTX,U          ; a macro ends: its context goes
            STD  <CONTEXT
            LDA  <ISP                  ; a noexpand one: its line is listed
            CMPA <NXLEVEL
            BNE  PO_DROP
            JSR  NXFLUSH
            LDU  <INP
PO_DROP     DEC  <ISP
            LEAU -INREC,U
            STU  <INP
            RTS
CLOSEINPUTS TST  <ISP
            BEQ  CI2_RET
            BSR  POPIN
            BRA  CLOSEINPUTS
CI2_RET     RTS
; X = the source file's name: opened as the first level.
OPENTOP     JSR  PUSHIN
            LDA  #IT_FILE
            STA  IR_TYPE,U
            PSHS X
            LEAY IR_SPEC,U
            JSR  COPYSPEC
            PULS X
            LEAY IR_PATH,U
            JSR  STRCPY
            LEAX IR_PATH,U
            LDE  #FOPEN_READ
            LDA  #B_FOPEN_NAME
            SWI2
            BCS  OT_FAIL
            STA  IR_HANDLE,U
            RTS
OT_FAIL     LDX  #M_NOSOURCE
            JMP  FATAL
; X -> Y: a name for the listing, at most 47 characters.
COPYSPEC    LDB  #47
CY_LOOP     LDA  ,X+
            BEQ  CY_END
            STA  ,Y+
            DECB
            BNE  CY_LOOP
CY_END      CLR  ,Y
            RTS
; U = a file record: -> A = its next byte, or carry set at the end. Keeps B and X.
INGETC      PSHS B
            BSR  IG_GET
            PULS B,PC                  ; (PULS keeps the carry)
IG_GET      TST  IR_UNGETF,U
            BEQ  IG_BUF
            CLR  IR_UNGETF,U
            LDA  IR_UNGETC,U
            ANDCC #$FE
            RTS
IG_BUF      LDD  IR_POS,U
            CMPD IR_LEN,U
            BLO  IG_HAVE
            TST  IR_EOF,U
            BNE  IG_END
            PSHS X,Y                   ; refill the buffer
            LDX  IR_BUF,U
            LDY  #256
            LDB  IR_HANDLE,U
            LDA  #B_FREAD
            SWI2
            BCS  IG_ENDX
            CMPX #0
            BEQ  IG_ENDX
            STX  IR_LEN,U
            LDD  #0
            STD  IR_POS,U
            PULS X,Y
IG_HAVE     PSHS X
            LDX  IR_BUF,U
            LDD  IR_POS,U
            LEAX D,X
            ADDD #1
            STD  IR_POS,U
            LDA  ,X
            PULS X
            ANDCC #$FE
            RTS
IG_ENDX     PULS X,Y
            LDA  #1
            STA  IR_EOF,U
IG_END      ORCC #1
            RTS
; The next line -> LINEBUF (and CURSPEC / CURLNO for the listing); carry set when
; there are no more.
READLINE    LDA  <ISP
            BNE  RL_HAVE
            ORCC #1
            RTS
RL_HAVE     LDU  <INP
            LDA  IR_TYPE,U
            CMPA #IT_MACRO
            BNE  RL_FILE
            JSR  MACLINE               ; (pa_dir.asm) carry set: the macro is over
            BCC  RL_GOT
            JSR  POPIN
            BRA  READLINE
RL_FILE     LDX  #LINEBUF
            CLRB                       ; characters kept
            CLR  <TMPB                 ; anything read at all?
RL_CHAR     JSR  INGETC
            BCS  RL_EOF
            INC  <TMPB
            CMPA #CR
            BEQ  RL_CR
            CMPA #LF
            BEQ  RL_LF
            CMPB #LINEMAX
            BHS  RL_CHAR               ; too long: the rest is dropped
            STA  ,X+
            INCB
            BRA  RL_CHAR
RL_CR       JSR  INGETC                ; CR LF is one line end
            BCS  RL_END
            CMPA #LF
            BEQ  RL_END
            BRA  RL_UNGET
RL_LF       JSR  INGETC                ; and so is LF CR
            BCS  RL_END
            CMPA #CR
            BEQ  RL_END
RL_UNGET    STA  IR_UNGETC,U
            LDA  #1
            STA  IR_UNGETF,U
            BRA  RL_END
RL_EOF      TST  <TMPB
            BNE  RL_END
            JSR  POPIN                 ; the file is done
            BRA  READLINE
RL_END      CLR  ,X
            LDD  IR_LINENO,U
            ADDD #1
            STD  IR_LINENO,U
RL_GOT      LDU  <INP
            LEAX IR_SPEC,U
            STX  <CURSPEC
            LDD  IR_LINENO,U
            STD  <CURLNO
            ANDCC #$FE
            RTS
;------------------------------------------------------------------------------
; INCLUDE files: X = the name (as written). Looked for next to the file the
; INCLUDE is in, then in each -I directory. -> an input level for it, U = its
; record; carry set if it can't be found. OPENSTAND does the same search without
; making a level: -> A = a DOS handle.
;------------------------------------------------------------------------------
OPENINC     PSHS X
            JSR  FINDFILE
            BCS  OI_FAIL
            PSHS A
            JSR  PUSHIN
            PULS A
            STA  IR_HANDLE,U
            LDA  #IT_FILE
            STA  IR_TYPE,U
            PULS X
            LEAY IR_SPEC,U
            JSR  COPYSPEC
            LDX  #PATHBUF
            LEAY IR_PATH,U
            JSR  STRCPY
            ANDCC #$FE
            RTS
OI_FAIL     PULS X
            ORCC #1
            RTS
OPENSTAND   EQU  FINDFILE
; X = a name: -> A = a DOS handle opened for reading, PATHBUF = its path; carry
; set if it is nowhere.
FINDFILE    PSHS X
            LDA  ,X                    ; an absolute path: only as it is
            CMPA #'/'
            BNE  FF_REL
            LDY  #PATHBUF
            JSR  STRCPY
            BRA  FF_LAST
FF_REL      LDY  #PATHBUF              ; the directory of the file doing the INCLUDE
            JSR  CURDIR
            LDX  ,S
            JSR  STRCPY
            JSR  TRYOPEN
            BCC  FF_OK
            CLR  <TMPB                 ; then each -I directory
FF_INC      LDA  <TMPB
            CMPA <NINCDIR
            BHS  FF_FAIL
            LDB  #PATHMAX+1
            MUL
            LDX  #INCDIRS
            LEAX D,X
            LDY  #PATHBUF
            JSR  STRCPY
            CMPY #PATHBUF
            BEQ  FF_NOSL
            LDA  -1,Y
            CMPA #'/'
            BEQ  FF_NOSL
            LDA  #'/'
            STA  ,Y+
FF_NOSL     LDX  ,S
            JSR  STRCPY
            INC  <TMPB
            JSR  TRYOPEN
            BCS  FF_INC
FF_OK       PULS X,PC
FF_LAST     JSR  TRYOPEN
            BCC  FF_OK
FF_FAIL     ORCC #1
            PULS X,PC
TRYOPEN     LDX  #PATHBUF              ; -> A = handle, carry if it won't open
            LDE  #FOPEN_READ
            LDA  #B_FOPEN_NAME
            SWI2
            RTS
; -> Y = PATHBUF + the directory part of the innermost file being read ("" or
; "dir/"), copied there.
CURDIR      LDU  <INP
CD_FIND     CMPU #INSTACK
            BLO  CD_NONE
            LDA  IR_TYPE,U
            CMPA #IT_FILE
            BEQ  CD_FILE
            LEAU -INREC,U
            BRA  CD_FIND
CD_NONE     LDY  #PATHBUF
            CLR  ,Y
            RTS
CD_FILE     LEAX IR_PATH,U             ; copy the path, then cut it after its last /
            LDY  #PATHBUF
            JSR  STRCPY
CD_BACK     CMPY #PATHBUF
            BEQ  CD_CUT
            LDA  -1,Y
            CMPA #'/'
            BEQ  CD_CUT
            LEAY -1,Y
            BRA  CD_BACK
CD_CUT      CLR  ,Y
            RTS
;------------------------------------------------------------------------------
; End of pa_io.asm
;------------------------------------------------------------------------------
