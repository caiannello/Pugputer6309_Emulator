;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 C compiler
;    FILE: cpp.asm
;
; CPP.COM: the C preprocessor, CC's first stage (see DESIGN.md).
;
;   CPP [options] file
;     -o FILE          the output (default: the source's name with .I)
;     -I DIR           where #include looks before /INCLUDE (up to 4)
;     -D NAME[=VALUE]  defines NAME, as VALUE or 1 (NAME(args)=VALUE works too)
;     -U NAME          forgets a predefined NAME
;
; It does what C's preprocessor does: a backslash at the end of a line joins
; the next, comments become a space, and #include, #define (object-like and
; function-like, with # and ## and "..." with __VA_ARGS__), #undef, #if,
; #ifdef, #ifndef, #elif, #else, #endif, #line, #error and #warning are carried
; out. #pragma lines are passed on as they are. __LINE__, __FILE__,
; __PUGPUTER__ and __6309__ are predefined. #if works in 32 bits.
;
; The output has no blank lines. "#line N" lines (and #line N "FILE" when the
; file changes) keep CC1's line numbers those of the source.
;
; #include "F" looks next to the file doing the #include, then in each -I
; directory, then in /INCLUDE; #include <F> skips the first.
;
; Macro expansion works on one line, in LBUF, in place: a macro's name (and its
; arguments) are replaced there by its replacement, which is then scanned again.
; An argument that isn't next to # or ## is expanded first, as the standard
; has it: a copy of it, above the end of the line, is scanned the same way (the
; call's state saved on the stack meanwhile). Marker bytes in the text keep
; track of what may be expanded (MK_*):
;   MK_END     ends the replacement of the macro last pushed on the active
;              stack (ACTSTK): while it is there, its name isn't expanded;
;   MK_PAINT   before a name: never to be expanded (it was its own macro's, or
;              one being expanded at the time).
; MK_END becomes MK_NOP (nothing) as the scan passes it, and they are all left
; out of the output. A macro's body keeps its parameters as MK_PARAM n, # p as
; MK_STR n, and ## as MK_PASTE.
;
; Memory: the direct page $3400, the program from $3500, then its buffers, the
; stack below $C000. The macros live in RAM pages from B_PAGE_ALLOC, mapped into
; bank 3, $C000-$EFFF (pa_heap.asm).
;------------------------------------------------------------------------------
    INCLUDE defines.d
;------------------------------------------------------------------------------
DPAGE       equ  $3400             ; the direct page (not part of the file)
PA_BASE     equ  $3500
WINDOW      equ  $C000             ; bank 3: where heap pages are mapped
WINEND      equ  $F000
STACKTOP    equ  $C000
MAXPAGES    equ  32
NAMEMAX     equ  63                ; the longest name (longer ones are cut)
PATHMAX     equ  79
MAXINCDIR   equ  4
MAXDEPTH    equ  8                 ; nested #includes
LBUFMAX     equ  6144              ; a line, as macro expansion grows it
RBUFMAX     equ  2048              ; one macro's replacement
BODYMAX     equ  1024              ; one macro's body
PARBUFSZ    equ  512               ; the parameters' names, while defining
MAXPARAMS   equ  32
MAXACT      equ  80                ; active stack entries (3 bytes each)
MAXCOND     equ  32                ; nested #ifs
MAXNEST     equ  16                ; arguments being expanded at once
SAVESZ      equ  CS_END-CS_BEG+4*(MAXPARAMS+1)*2
NHASH       equ  128               ; macro hash buckets
SYNCMAX     equ  8                 ; up to this many lines' gap: blank lines,
DEFSSZ      equ  256               ; more: #line
; Marker bytes (1-7: no source byte is one, as bytes 0-8 are read as spaces)
MK_END      equ  1
MK_PAINT    equ  2
MK_NOP      equ  3
MK_PARAM    equ  4                 ; (bodies) MK_PARAM n
MK_STR      equ  5                 ; (bodies) MK_STR n
MK_PASTE    equ  6                 ; (bodies)
MK_LAST     equ  7                 ; (the highest)
; A macro record (in the heap):
MR_NEXT     equ  0                 ; the next in its bucket (far pointer)
MR_FLAGS    equ  3                 ; MF_*
MR_NPAR     equ  4                 ; parameters (with "..." as one)
MR_BLEN     equ  5                 ; the body's length
MR_NAME     equ  7                 ; the name, NUL-terminated, then the body
MF_FUNC     equ  1                 ; function-like
MF_VAR      equ  2                 ; its last parameter is "..."
MF_LINE     equ  4                 ; __LINE__
MF_FILE     equ  8                 ; __FILE__
; An input record (INSTACK, one for each open file):
IR_HANDLE   equ  0
IR_POS      equ  1                 ; the next byte in the buffer
IR_LEN      equ  3                 ; bytes in the buffer
IR_LINE     equ  5                 ; the line being read
IR_EOF      equ  7
IR_UNGF     equ  8                 ; a byte was put back
IR_UNGC     equ  9
IR_BUF      equ  10                ; its 256-byte buffer
IR_COND     equ  12                ; CONDSP when it was opened
IR_PATH     equ  13                ; its path (as #line and __FILE__ see it)
INREC       equ  IR_PATH+PATHMAX+NAMEMAX+2
; A conditional (CONDSTK) entry:
CS_OUTER    equ  1                 ; the lines around it are skipped
CS_TAKEN    equ  2                 ; a branch has been taken
CS_ELSE     equ  4                 ; #else has been seen
; #if's operators
OP_LOR      equ  1
OP_LAND     equ  2
OP_BOR      equ  3
OP_XOR      equ  4
OP_BAND     equ  5
OP_EQ       equ  6
OP_NE       equ  7
OP_LT       equ  8
OP_GT       equ  9
OP_LE       equ  10
OP_GE       equ  11
OP_SHL      equ  12
OP_SHR      equ  13
OP_ADD      equ  14
OP_SUB      equ  15
OP_MUL      equ  16
OP_DIV      equ  17
OP_MOD      equ  18
;------------------------------------------------------------------------------
; DVAR name,size: a direct-page variable. VAR name,size: one after the program.
DVAR        MACRO
\1          equ  DP_VP
DP_VP       SET  DP_VP+\2
            ENDM
VAR         MACRO
\1          equ  VP
VP          SET  VP+\2
            ENDM
; MA onto the stack, and back.
PUSHMA      MACRO
            LDQ  MA
            PSHSW
            PSHS D
            ENDM
PULLMA      MACRO
            PULS D
            PULSW
            STQ  MA
            ENDM
DP_VP       SET  DPAGE
            DVAR MAPPED,1              ; pa_heap.asm
            DVAR NPAGES,1
            DVAR HEAPPG,1
            DVAR HEAPPTR,2
            DVAR FARP,3
            DVAR MA,4                  ; 32-bit arithmetic (pa_util.asm)
            DVAR MB,4
            DVAR MQ,4
            DVAR MSIGN,1
            DVAR ISP,1                 ; open files
            DVAR INP,2                 ; the current one's record
            DVAR PEEKF,1               ; NEXTCH's byte put back
            DVAR PEEKC,1
            DVAR STARTLN,2             ; the line LBUF's began on
            DVAR SKIP,1                ; lines are being skipped (#if)
            DVAR CONDSP,1              ; CONDSTK entries
            DVAR ERRCNT,2
            DVAR OUTLINE,2             ; the line number of the next output line
            DVAR FILECHG,1             ; the file has changed: #line N "F" next
            DVAR OUTON,1               ; the output is open
            DVAR ASP,1                 ; ACTSTK entries
            DVAR NINCDIR,1
            DVAR GOTANY,1              ; GETLINE read something
            DVAR INSTR,1               ; a literal's quote
            DVAR LONGERR,1             ; "line too long" said
            DVAR TMP,2
            DVAR TMP2,2
            DVAR TMPB,1
            DVAR PREVP,3               ; the link to it (page 0: a bucket)
            DVAR RPTR,2                ; the end of the replacement in RBUF
            DVAR RBFULL,1              ; RBUF overflowed
            DVAR PDEPTH,1              ; parentheses
            DVAR AEND,2                ; the end of an argument
            DVAR SPPEND,1              ; # : a space to write
            DVAR NEWLEN,2              ; SPLICE
            DVAR DELTA,2
            DVAR DEFFL,1               ; #define: flags, parameters
            DVAR DEFNP,1
            DVAR PARPTR,2
            DVAR BODYLEN,2
            DVAR BODYERR,1
            DVAR DEFPTR,2              ; the end of DEFS
            DVAR DIRARG,2              ; the directive's operands
            DVAR EVERR,1               ; #if: an error has been said
            DVAR EVBASE,1
            DVAR INCKIND,1             ; '"' or '<'
            DVAR QUOTE,1
CS_BEG      equ  DP_VP             ; a call's state (saved while an argument
            DVAR LEND,2                ; is expanded): the NUL ending the text,
            DVAR INVQ,2                ; the call's start, just after it,
            DVAR INVZ,2
            DVAR NARGS,1               ; its arguments,
            DVAR MACP,3                ; the macro (far pointer),
            DVAR MFLAGS,1              ; its flags, parameters, body length,
            DVAR MNPAR,1
            DVAR MBLEN,2
            DVAR BSTART,2              ; its body,
            DVAR BEND,2
            DVAR PASTENX,1             ; ## came last in it,
            DVAR SCRP,2                ; where arguments' copies go,
            DVAR MOREOK,1              ; lines may be read for arguments
CS_END      equ  DP_VP
            DVAR NEST,1                ; arguments being expanded
DP_END      equ  DP_VP
;------------------------------------------------------------------------------
    ORG  PA_BASE-EXE_HDRSIZE
    FDB  EXE_MAGIC                 ; the program header
    FDB  PA_BASE                   ; load address
    FDB  START                     ; entry
    FDB  0                         ; flags
    SETDP DPAGE/256
;------------------------------------------------------------------------------
START       LDS  #STACKTOP
            LDA  #DPAGE/256
            TFR  A,DP
            LDX  #ZERO                 ; clear the variables
            LDY  #DPAGE
            LDW  #DP_END-DPAGE
            TFM  X,Y+
            LDX  #ZERO
            LDY  #VARS
            LDW  #VARSEND-VARS
            TFM  X,Y+
            JSR  HEAPINIT
            JSR  CMDLINE
            JSR  PREDEF
            LDU  #OUTSTRM
            LDX  #OUTNAME
            JSR  SOPEN
            BCC  ST_OUT
            LDX  #M_NOOUT
            JSR  PRINTS
            LDX  #OUTNAME
            JMP  FATAL2
ST_OUT      LDA  #1
            STA  <OUTON
            LDX  #SRCNAME
            LDY  #PATHBUF
            JSR  STRCPY
            JSR  TRYOPEN
            BCC  ST_SRC
            LDX  #M_NOSRC
            JSR  PRINTS
            LDX  #SRCNAME
            JMP  FATAL
ST_SRC      LDX  #PATHBUF
            JSR  PUSHFILE
            JSR  MAINLOOP
            CLR  <OUTON
            LDU  #OUTSTRM
            JSR  SCLOSE
            LDD  <ERRCNT
            BEQ  ST_DONE
            JSR  KILLOUT
            LDD  <ERRCNT
            JSR  PRINTDEC
            LDX  #M_ERRORS
            JSR  PRINTS
ST_DONE     JSR  HEAPDONE
            LDA  #B_EXIT
            SWI2
; A fatal error: X = the message. The output goes; then the program ends.
FATAL       JSR  PRINTS
            JSR  PRINTNL
            TST  <OUTON
            BEQ  FATAL3
            CLR  <OUTON
            LDU  #OUTSTRM
            CLR  1,U                   ; (not flushed: that may be what failed)
            LDB  ,U
            LDA  #B_FCLOSE_NAME
            SWI2
            JSR  KILLOUT
FATAL3      JSR  HEAPDONE
            LDA  #B_EXIT
            SWI2
FATAL2      JSR  PRINTS                ; (no output to remove)
            JSR  PRINTNL
            BRA  FATAL3
KILLOUT     LDX  #OUTNAME
            LDA  #B_KILL_NAME
            SWI2
            RTS
;------------------------------------------------------------------------------
; The command line.
;------------------------------------------------------------------------------
CMDLINE     LDY  #DEFS
            STY  <DEFPTR
            LDA  #B_ARGS
            SWI2
CL_NEXT     JSR  SKIPSP
            LDA  ,X
            BEQ  CL_DONE
            CMPA #'-'
            BNE  CL_FILE
            LDA  1,X
            LEAX 2,X
            CMPA #'o'
            BEQ  CL_OUT
            CMPA #'I'
            BEQ  CL_INC
            CMPA #'D'
            BEQ  CL_DEF
            CMPA #'U'
            BEQ  CL_DEF
            BRA  USAGE
CL_OUT      JSR  OPTARG
            LDY  #OUTNAME
            JSR  GETWORD
            BRA  CL_NEXT
CL_INC      JSR  OPTARG
            LDA  <NINCDIR
            CMPA #MAXINCDIR
            BHS  CL_INC2
            LDB  #PATHMAX+1
            MUL
            LDY  #INCDIRS
            LEAY D,Y
            INC  <NINCDIR
            JSR  GETWORD
            BRA  CL_NEXT
CL_INC2     LDY  #NAMEBUF              ; (too many: dropped)
            JSR  GETWORD
            BRA  CL_NEXT
CL_DEF      PSHS A                     ; DEFS: 'D' or 'U', then the text
            JSR  OPTARG
            LDY  <DEFPTR
            CMPY #DEFS+DEFSSZ-PATHMAX-3
            BHS  USAGE
            PULS A
            STA  ,Y+
            JSR  GETWORD
            LEAY 1,Y
            CLR  ,Y
            STY  <DEFPTR
            BRA  CL_NEXT
CL_FILE     TST  SRCNAME
            BNE  USAGE
            LDY  #SRCNAME
            JSR  GETWORD
            BRA  CL_NEXT
CL_DONE     TST  SRCNAME
            BEQ  USAGE
            TST  OUTNAME
            BNE  CL_RET
            LDX  #EXT_I
            LDY  #OUTNAME
            JMP  NEWEXT
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
; X -> Y: a word (to a space or the end), at most PATHMAX characters; Y ends at
; its NUL.
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
; SRCNAME with its extension replaced by the one at X -> Y.
NEWEXT      PSHS X
            PSHS Y
            LDX  #SRCNAME
            JSR  STRCPY
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
NE_DOT      LEAY -1,Y
            BRA  NE_PUT
NE_ADD      TFR  U,Y
NE_PUT      LEAS 2,S
            PULS X
            JMP  STRCPY
;------------------------------------------------------------------------------
; The predefined macros, then -D and -U.
;------------------------------------------------------------------------------
PREDEF      LDX  #PD_LINE
            JSR  DEFTEXT
            LDA  #MF_LINE
            JSR  SETFLAG
            LDX  #PD_FILE
            JSR  DEFTEXT
            LDA  #MF_FILE
            JSR  SETFLAG
            LDX  #PD_PUG
            JSR  DEFTEXT
            LDX  #PD_6309
            JSR  DEFTEXT
            LDX  #DEFS
PD_LOOP     LDA  ,X+
            BEQ  PD_RET
            CMPA #'U'
            BEQ  PD_UNDEF
            LDY  #LBUF                 ; -D: NAME=VALUE is "NAME VALUE"
            CLR  <TMPB
PD_COPY     LDA  ,X+
            BEQ  PD_END
            CMPA #'='
            BNE  PD_PUT
            TST  <TMPB
            BNE  PD_PUT
            INC  <TMPB
            LDA  #' '
PD_PUT      STA  ,Y+
            BRA  PD_COPY
PD_END      TST  <TMPB
            BNE  PD_DEF
            LDD  #' '*256+'1'          ; NAME alone is "NAME 1"
            STD  ,Y++
PD_DEF      CLR  ,Y
            PSHS X
            LDX  #LBUF
            JSR  DEFLINE
            PULS X
            BRA  PD_LOOP
PD_UNDEF    JSR  READID
PD_SKIP     LDA  ,X+
            BNE  PD_SKIP
            PSHS X
            JSR  LOOKUP
            BCS  PD_UNONE
            JSR  UNLINK
PD_UNONE    PULS X
            BRA  PD_LOOP
PD_RET      RTS
; X = "NAME BODY": defined, as #define does.
DEFTEXT     LDY  #LBUF
            JSR  STRCPY
            LDX  #LBUF
            JMP  DEFLINE
; A = flags for the macro just defined (MACP).
SETFLAG     PSHS A
            LDA  <MACP
            JSR  MAPPG
            LDX  <MACP+1
            PULS A
            ORA  MR_FLAGS,X
            STA  MR_FLAGS,X
            RTS
;------------------------------------------------------------------------------
; The files being read.
;------------------------------------------------------------------------------
; X = a path, A = the file open on it: the next level of input.
PUSHFILE    LDB  <ISP
            CMPB #MAXDEPTH
            BLO  PF_ROOM
            TFR  A,B
            LDA  #B_FCLOSE_NAME
            SWI2
            LDX  #M_DEEP
            JMP  ERROR
PF_ROOM     PSHS A,X
            LDA  #INREC
            MUL
            LDU  #INSTACK
            LEAU D,U
            STU  <INP
            PULS A
            STA  IR_HANDLE,U
            CLRD
            STD  IR_POS,U
            STD  IR_LEN,U
            CLR  IR_EOF,U
            CLR  IR_UNGF,U
            INCB
            STD  IR_LINE,U
            LDX  #INBUFS
            TFR  X,D
            ADDA <ISP
            STD  IR_BUF,U
            LDA  <CONDSP
            STA  IR_COND,U
            PULS X
            LEAY IR_PATH,U
            JSR  STRCPY
            INC  <ISP
            LDA  #1
            STA  <FILECHG
            RTS
; The current file is done: back to the one that #included it.
POPFILE     LDU  <INP
            LDB  IR_HANDLE,U
            LDA  #B_FCLOSE_NAME
            SWI2
            LDA  IR_COND,U
            CMPA <CONDSP
            BHS  PO_OK
            LDX  #M_UNTERMIF           ; a #if it began is still open
            JSR  ERROR
            LDU  <INP
            LDA  IR_COND,U
            STA  <CONDSP
            LDX  #CONDSTK
            LDB  A,X
            ANDB #CS_OUTER
            STB  <SKIP
PO_OK       DEC  <ISP
            LEAU -INREC,U
            STU  <INP
            LDA  #1
            STA  <FILECHG
            RTS
; -> A = the current file's next byte: CR LF, CR and LF are LF (and the line
; is counted), bytes 0-8 are spaces. Carry set at the end. Keeps B, X, Y, U.
RAWCH       PSHS B,X,U
            LDU  <INP
            BSR  RC_BYTE
            BCS  RC_RET
            CMPA #CR
            BEQ  RC_CR
            CMPA #LF
            BEQ  RC_NL
            CMPA #8
            BHI  RC_OK
            LDA  #' '
RC_OK       ANDCC #$FE
RC_RET      PULS B,X,U,PC
RC_CR       BSR  RC_BYTE
            BCS  RC_NL
            CMPA #LF
            BEQ  RC_NL
            STA  IR_UNGC,U
            LDA  #1
            STA  IR_UNGF,U
RC_NL       LDX  IR_LINE,U
            LEAX 1,X
            STX  IR_LINE,U
            LDA  #LF
            ANDCC #$FE
            PULS B,X,U,PC
RC_BYTE     TST  IR_UNGF,U
            BEQ  RB_BUF
            CLR  IR_UNGF,U
            LDA  IR_UNGC,U
            ANDCC #$FE
            RTS
RB_BUF      LDD  IR_POS,U
            CMPD IR_LEN,U
            BLO  RB_HAVE
            TST  IR_EOF,U
            BNE  RB_END
            PSHS Y
            LDX  IR_BUF,U
            LDY  #256
            LDB  IR_HANDLE,U
            LDA  #B_FREAD
            SWI2
            PULS Y
            BCS  RB_EOF
            CMPX #0
            BEQ  RB_EOF
            STX  IR_LEN,U
            CLRD
            STD  IR_POS,U
RB_HAVE     LDX  IR_BUF,U
            LEAX D,X
            ADDD #1
            STD  IR_POS,U
            LDA  ,X
            ANDCC #$FE
            RTS
RB_EOF      LDA  #1
            STA  IR_EOF,U
RB_END      ORCC #1
            RTS
; -> A = the next character, a backslash and the end of a line skipped. Carry
; set at the end.
NEXTCH      TST  <PEEKF
            BEQ  NC_READ
            CLR  <PEEKF
            LDA  <PEEKC
            ANDCC #$FE
            RTS
NC_READ     JSR  RAWCH
            BCS  NC_RET
            CMPA #'\'
            BNE  NC_OK
            JSR  RAWCH
            BCS  NC_BS
            CMPA #LF
            BEQ  NC_READ               ; joined
            PSHS U                     ; (not: that byte comes next)
            LDU  <INP
            STA  IR_UNGC,U
            LDA  #1
            STA  IR_UNGF,U
            PULS U
NC_BS       LDA  #'\'
NC_OK       ANDCC #$FE
NC_RET      RTS
UNNEXT      STA  <PEEKC
            LDA  #1
            STA  <PEEKF
            LDA  <PEEKC
            RTS
; Y = where: the next line, its comments a space each, NUL-terminated (LEND at
; the NUL). Carry set if the file had nothing more.
GETLINE     CLR  <GOTANY
GL_LOOP     JSR  NEXTCH
            LBCS GL_EOF
            STA  <GOTANY               ; (never 0)
            CMPA #LF
            LBEQ GL_END
            CMPA #'/'
            BEQ  GL_SLASH
            CMPA #'"'
            BEQ  GL_LIT
            CMPA #$27
            BEQ  GL_LIT
GL_PUT      BSR  GL_STORE
            BRA  GL_LOOP
GL_STORE    CMPY #LBUF+LBUFMAX
            BHS  GL_LONG
            STA  ,Y+
            RTS
GL_LONG     TST  <LONGERR
            BNE  GL_LRET
            INC  <LONGERR
            PSHS X
            LDX  #M_LONGLINE
            JSR  ERROR
            PULS X
GL_LRET     RTS
GL_SLASH    JSR  NEXTCH
            BCS  GL_SL1
            CMPA #'*'
            BEQ  GL_BLOCK
            CMPA #'/'
            BEQ  GL_LCMT
            JSR  UNNEXT
GL_SL1      LDA  #'/'
            BRA  GL_PUT
GL_LCMT     JSR  NEXTCH                ; // to the end of the line
            BCS  GL_END
            CMPA #LF
            BNE  GL_LCMT
            BRA  GL_END
GL_BLOCK    JSR  NEXTCH                ; /* to */
            BCS  GL_UNTERM
            CMPA #'*'
            BNE  GL_BLOCK
GL_B2       JSR  NEXTCH
            BCS  GL_UNTERM
            CMPA #'/'
            BEQ  GL_BEND
            CMPA #'*'
            BEQ  GL_B2
            BRA  GL_BLOCK
GL_BEND     LDA  #' '
            BRA  GL_PUT
GL_UNTERM   PSHS X
            LDX  #M_UNTERMCMT
            JSR  ERROR
            PULS X
            BRA  GL_END
GL_LIT      STA  <INSTR                ; a literal, to its quote or the line's end
            BSR  GL_STORE
GL_L1       JSR  NEXTCH
            BCS  GL_END
            CMPA #LF
            BEQ  GL_END
            BSR  GL_STORE
            CMPA <INSTR
            LBEQ GL_LOOP
            CMPA #'\'
            BNE  GL_L1
            JSR  NEXTCH
            BCS  GL_END
            CMPA #LF
            BEQ  GL_END
            JSR  GL_STORE
            BRA  GL_L1
GL_EOF      TST  <GOTANY
            BEQ  GL_NONE
GL_END      CLR  ,Y
            STY  <LEND
            ANDCC #$FE
            RTS
GL_NONE     CLR  ,Y
            STY  <LEND
            ORCC #1
            RTS
; Another line onto the end of LBUF (after a space), for a call's arguments.
; Carry set if there's none. Keeps X and Y.
APPENDLINE  PSHS X,Y
            LDY  <LEND
            CMPY #LBUF+LBUFMAX-2
            BHS  AL_NO
            LDA  #' '
            STA  ,Y+
            JSR  GETLINE
            BCC  AL_YES
            LDX  <LEND
            LEAX -1,X
            CLR  ,X
            STX  <LEND
AL_NO       ORCC #1
            PULS X,Y,PC
AL_YES      ANDCC #$FE
            PULS X,Y,PC
;------------------------------------------------------------------------------
; The main loop: a line at a time.
;------------------------------------------------------------------------------
MAINLOOP    LDU  <INP
            LDD  IR_LINE,U
            STD  <STARTLN
            CLR  <LONGERR
            LDY  #LBUF
            JSR  GETLINE
            BCC  ML_GOT
            JSR  POPFILE
            TST  <ISP
            BNE  MAINLOOP
            RTS
ML_GOT      LDX  #LBUF
            JSR  SKIPWS
            LDA  ,X
            CMPA #'#'
            BNE  ML_TEXT
            JSR  DIRECTIVE
            BRA  MAINLOOP
ML_TEXT     TST  <SKIP
            BNE  MAINLOOP
            LDA  #1
            STA  <MOREOK
            LDX  #LBUF
            JSR  SCAN
            CLR  <MOREOK
            LDX  #LBUF
            JSR  EMITLINE
            BRA  MAINLOOP
; X = a line: written, without its markers, unless there's nothing in it.
EMITLINE    PSHS X
EM_CHECK    LDA  ,X+
            BEQ  EM_EMPTY
            CMPA #' '
            BEQ  EM_CHECK
            CMPA #9
            BEQ  EM_CHECK
            CMPA #MK_LAST
            BHI  EM_SOME
            BLO  EM_CHECK
            LEAX 1,X
            BRA  EM_CHECK
EM_EMPTY    PULS X,PC
EM_SOME     JSR  SYNC
            PULS X
            LDU  #OUTSTRM
EM_LOOP     LDA  ,X+
            BEQ  EM_END
            CMPA #MK_LAST
            BHI  EM_PUT
            BLO  EM_LOOP
            LEAX 1,X
            BRA  EM_LOOP
EM_PUT      JSR  SPUTC
            BRA  EM_LOOP
EM_END      JSR  SPUTNL
            LDD  <OUTLINE
            ADDD #1
            STD  <OUTLINE
            RTS
; Before a line is written: the output brought to STARTLN (blank lines, or
; #line).
SYNC        LDU  #OUTSTRM
            TST  <FILECHG
            BNE  YN_FILE
            LDD  <STARTLN
            SUBD <OUTLINE
            BLO  YN_LINE
            CMPD #SYNCMAX
            BHI  YN_LINE
YN_NL       TSTB
            BEQ  YN_DONE
            JSR  SPUTNL
            DECB
            BRA  YN_NL
YN_DONE     LDD  <STARTLN
            STD  <OUTLINE
            RTS
YN_LINE     LDX  #S_LINE
            JSR  SPUTS
            LDD  <STARTLN
            JSR  SPUTDEC
            JSR  SPUTNL
            BRA  YN_DONE
YN_FILE     CLR  <FILECHG
            LDX  #S_LINE
            JSR  SPUTS
            LDD  <STARTLN
            JSR  SPUTDEC
            LDA  #' '
            JSR  SPUTC
            LDA  #'"'
            JSR  SPUTC
            LDX  <INP
            LEAX IR_PATH,X
            JSR  SPUTS
            LDA  #'"'
            JSR  SPUTC
            JSR  SPUTNL
            BRA  YN_DONE
SPUTDEC     LDX  #NUMBUF
            JSR  DECSTR
            LDX  #NUMBUF
            JMP  SPUTS
;------------------------------------------------------------------------------
; Errors: X = the message. "FILE:LINE: error: message" on the console. ERRORN
; adds " 'NAME'" (Y = the name).
;------------------------------------------------------------------------------
ERROR       PSHS D,X,Y,U
            LDY  #0
            BRA  ER_COUNT
ERRORN      PSHS D,X,Y,U
ER_COUNT    LDD  <ERRCNT
            ADDD #1
            STD  <ERRCNT
            LDX  #M_ERRPFX
            BRA  ER_SAY
WARN        PSHS D,X,Y,U
            LDY  #0
            LDX  #M_WARNPFX
ER_SAY      JSR  WHERE
            JSR  PRINTS
            LDX  2,S
            JSR  PRINTS
            CMPY #0
            BEQ  ER_NL
            LDX  #M_QUOTE1
            JSR  PRINTS
            TFR  Y,X
            JSR  PRINTS
            LDA  #$27
            JSR  PRINTC
ER_NL       JSR  PRINTNL
            PULS D,X,Y,U,PC
WHERE       PSHS X
            LDA  <ISP
            BEQ  WH_CMD
            LDX  <INP
            LEAX IR_PATH,X
            JSR  PRINTS
            LDA  #':'
            JSR  PRINTC
            LDD  <STARTLN
            JSR  PRINTDEC
            LDA  #':'
            JSR  PRINTC
            LDA  #' '
            JSR  PRINTC
            PULS X,PC
WH_CMD      LDX  #M_CMDLINE
            JSR  PRINTS
            PULS X,PC
;------------------------------------------------------------------------------
; Characters and names.
;------------------------------------------------------------------------------
; Carry clear if A may start a name (a letter or _), or be in one (ISIDCH: a
; digit too).
ISIDCH      JSR  ISDIGIT
            BCC  ID_RET
ISIDST      CMPA #'_'
            BEQ  ID_YES
            JMP  ISALPHA
ID_YES      ANDCC #$FE
ID_RET      RTS
; X: past spaces and tabs.
SKIPWS      LDA  ,X
            CMPA #' '
            BEQ  SW_1
            CMPA #9
            BNE  SW_RET
SW_1        LEAX 1,X
            BRA  SKIPWS
SW_RET      RTS
; X: past spaces, tabs and markers.
SKIPWSMK    LDA  ,X
            BEQ  SM_RET
            CMPA #' '
            BEQ  SM_1
            CMPA #9
            BEQ  SM_1
            CMPA #MK_LAST
            BHI  SM_RET
            BLO  SM_1
            LEAX 1,X
SM_1        LEAX 1,X
            BRA  SKIPWSMK
SM_RET      RTS
; X at a name: it -> NAMEBUF (the first NAMEMAX characters); X after it.
; Keeps Y.
READID      PSHS Y
            LDY  #NAMEBUF
            LDB  #NAMEMAX
RI_LOOP     LDA  ,X
            JSR  ISIDCH
            BCS  RI_END
            LEAX 1,X
            TSTB
            BEQ  RI_LOOP
            STA  ,Y+
            DECB
            BRA  RI_LOOP
RI_END      CLR  ,Y
            PULS Y,PC
SKIPID      LDA  ,X
            JSR  ISIDCH
            BCS  SI_RET
            LEAX 1,X
            BRA  SKIPID
SI_RET      RTS
; X at a quote: past the literal (to its closing quote, or the line's end).
SKIPLIT     LDA  ,X+
            STA  <QUOTE
LT_LOOP     LDA  ,X
            BEQ  LT_RET
            LEAX 1,X
            CMPA <QUOTE
            BEQ  LT_RET
            CMPA #'\'
            BNE  LT_LOOP
            TST  ,X
            BEQ  LT_RET
            LEAX 1,X
            BRA  LT_LOOP
LT_RET      RTS
; X at a number (a digit, or . and a digit): past it (a "preprocessing
; number": digits, letters, _, ., and e+ e- p+ p-).
SKIPNUM     LEAX 1,X
NM_LOOP     LDA  ,X
            CMPA #'e'
            BEQ  NM_EXP
            CMPA #'E'
            BEQ  NM_EXP
            CMPA #'p'
            BEQ  NM_EXP
            CMPA #'P'
            BEQ  NM_EXP
            CMPA #'.'
            BEQ  NM_1
            JSR  ISIDCH
            BCS  NM_RET
NM_1        LEAX 1,X
            BRA  NM_LOOP
NM_EXP      LDB  1,X
            CMPB #'+'
            BEQ  NM_2
            CMPB #'-'
            BNE  NM_1
NM_2        LEAX 2,X
            BRA  NM_LOOP
NM_RET      RTS
;------------------------------------------------------------------------------
; The macros: in RAM pages, a hash table of chains.
;------------------------------------------------------------------------------
; NAMEBUF -> X = its bucket in HASHTAB.
HASHNAME    LDX  #NAMEBUF
            CLRB
HN_LOOP     LDA  ,X+
            BEQ  HN_END
            LSLB
            ADCB #0
            PSHS A
            EORB ,S+
            BRA  HN_LOOP
HN_END      ANDB #NHASH-1
            LDA  #3
            MUL
            LDX  #HASHTAB
            LEAX D,X
            RTS
; Is NAMEBUF a macro? Carry clear if so: MACP = it (mapped), MFLAGS, MNPAR,
; MBLEN = its own, PREVP = the link to it.
LOOKUP      JSR  HASHNAME
            CLR  <PREVP
            STX  <PREVP+1
LK_LOOP     LDA  <PREVP
            JSR  MAPPG
            LDX  <PREVP+1
            LDA  ,X
            STA  <MACP
            LDD  1,X
            STD  <MACP+1
            LDA  <MACP
            BEQ  LK_NO
            JSR  MAPPG
            LDX  <MACP+1
            LEAX MR_NAME,X
            LDY  #NAMEBUF
            JSR  STRCMP
            BEQ  LK_YES
            LDA  <MACP
            STA  <PREVP
            LDD  <MACP+1
            STD  <PREVP+1
            BRA  LK_LOOP
LK_YES      LDX  <MACP+1
            LDA  MR_FLAGS,X
            STA  <MFLAGS
            LDA  MR_NPAR,X
            STA  <MNPAR
            LDD  MR_BLEN,X
            STD  <MBLEN
            ANDCC #$FE
            RTS
LK_NO       ORCC #1
            RTS
; The macro LOOKUP found is taken out of its chain.
UNLINK      LDA  <MACP
            JSR  MAPPG
            LDX  <MACP+1
            LDA  ,X
            STA  <FARP
            LDD  1,X
            STD  <FARP+1
            LDA  <PREVP
            JSR  MAPPG
            LDX  <PREVP+1
            LDA  <FARP
            STA  ,X
            LDD  <FARP+1
            STD  1,X
            RTS
; A new macro: DEFNAME, DEFFL, DEFNP, and BODYLEN bytes at BODYBUF. -> MACP.
ADDMACRO    LDX  #DEFNAME
            LDY  #NAMEBUF
            JSR  STRCPY
            LDX  #DEFNAME
            JSR  STRLEN
            ADDD #MR_NAME+1
            ADDD <BODYLEN
            STD  <TMP
            JSR  HASHNAME
            STX  <TMP2
            LDD  <TMP
            JSR  HALLOC                ; A = page, X = the record (mapped)
            STA  <MACP
            STX  <MACP+1
            LDY  <TMP2                 ; first in its bucket
            LDA  ,Y
            STA  MR_NEXT,X
            LDD  1,Y
            STD  MR_NEXT+1,X
            LDA  <MACP
            STA  ,Y
            LDD  <MACP+1
            STD  1,Y
            LDA  <DEFFL
            STA  MR_FLAGS,X
            LDA  <DEFNP
            STA  MR_NPAR,X
            LDD  <BODYLEN
            STD  MR_BLEN,X
            LEAY MR_NAME,X
            LDX  #DEFNAME
            JSR  STRCPY
            LEAY 1,Y
            LDX  #BODYBUF
            LDW  <BODYLEN
            BEQ  AM_RET
            TFM  X+,Y+
AM_RET      RTS
;------------------------------------------------------------------------------
; Directives. X = the line, at its '#'.
;------------------------------------------------------------------------------
DIRECTIVE   LEAX 1,X
            JSR  SKIPWS
            LDA  ,X
            BEQ  DR_RET                ; "#" alone
            JSR  ISDIGIT               ; "# 12 "file"" is #line
            BCS  DR_NAME
            TST  <SKIP
            BNE  DR_RET
            JMP  DO_LINE
DR_NAME     JSR  ISIDST
            BCS  DR_BAD
            JSR  READID
            JSR  SKIPWS
            STX  <DIRARG
            LDY  #DIRTAB
DR_FIND     LDA  ,Y
            BEQ  DR_BAD
            LDX  #NAMEBUF
            JSR  STRCMP
            BEQ  DR_GOT
DR_SKIP     LDA  ,Y+
            BNE  DR_SKIP
            LEAY 3,Y
            BRA  DR_FIND
DR_GOT      LDA  ,Y+
            BNE  DR_GOT
            LDA  ,Y+                   ; 1: carried out while skipping too
            BNE  DR_RUN
            TST  <SKIP
            BNE  DR_RET
DR_RUN      LDX  <DIRARG
            JMP  [,Y]
DR_BAD      TST  <SKIP
            BNE  DR_RET
            LDX  #M_BADDIR
            JMP  ERROR
DR_RET      RTS
DIRTAB      FCN  "define"
            FCB  0
            FDB  DO_DEFINE
            FCN  "include"
            FCB  0
            FDB  DO_INCLUDE
            FCN  "if"
            FCB  1
            FDB  DO_IF
            FCN  "ifdef"
            FCB  1
            FDB  DO_IFDEF
            FCN  "ifndef"
            FCB  1
            FDB  DO_IFNDEF
            FCN  "elif"
            FCB  1
            FDB  DO_ELIF
            FCN  "else"
            FCB  1
            FDB  DO_ELSE
            FCN  "endif"
            FCB  1
            FDB  DO_ENDIF
            FCN  "undef"
            FCB  0
            FDB  DO_UNDEF
            FCN  "line"
            FCB  0
            FDB  DO_LINE
            FCN  "error"
            FCB  0
            FDB  DO_ERROR
            FCN  "warning"
            FCB  0
            FDB  DO_WARNING
            FCN  "pragma"
            FCB  0
            FDB  DO_PRAGMA
            FCB  0
;------------------------------------------------------------------------------
; #define (and -D, and the predefined ones). X at the name.
;------------------------------------------------------------------------------
DO_DEFINE
DEFLINE     LDA  ,X
            JSR  ISIDST
            BCC  DL_NAME
            LDX  #M_NOMACNAME
            JMP  ERROR
DL_NAME     JSR  READID
            PSHS X
            LDX  #NAMEBUF
            LDY  #DEFNAME
            JSR  STRCPY
            PULS X
            CLR  <DEFFL
            CLR  <DEFNP
            CLR  <BODYERR
            LDY  #PARBUF
            STY  <PARPTR
            LDA  ,X
            CMPA #'('
            LBNE DL_BODY
            LEAX 1,X                   ; function-like: the parameters
            LDA  #MF_FUNC
            STA  <DEFFL
            JSR  SKIPWS
            LDA  ,X
            CMPA #')'
            BEQ  DL_PEND
DL_PARAM    JSR  SKIPWS
            LDA  ,X
            CMPA #'.'
            BEQ  DL_DOTS
            JSR  ISIDST
            BCS  DL_PBAD
            JSR  READID
            JSR  ADDPARAM
            BCS  DL_PBAD
            JSR  SKIPWS
            LDA  ,X+
            CMPA #44                   ; ','
            BEQ  DL_PARAM
            CMPA #')'
            BEQ  DL_BODY
DL_PBAD     LDX  #M_BADPARAMS
            JMP  ERROR
DL_DOTS     LDA  1,X
            CMPA #'.'
            BNE  DL_PBAD
            LDA  2,X
            CMPA #'.'
            BNE  DL_PBAD
            LEAX 3,X
            PSHS X
            LDX  #S_VAARGS
            LDY  #NAMEBUF
            JSR  STRCPY
            PULS X
            JSR  ADDPARAM
            BCS  DL_PBAD
            LDA  <DEFFL
            ORA  #MF_VAR
            STA  <DEFFL
            JSR  SKIPWS
            LDA  ,X+
            CMPA #')'
            BNE  DL_PBAD
            BRA  DL_BODY
DL_PEND     LEAX 1,X
DL_BODY     JSR  SKIPWS                ; the body -> BODYBUF
            LDY  #BODYBUF
DB_LOOP     LDA  ,X
            LBEQ DB_END
            CMPA #' '
            BEQ  DB_SPACE
            CMPA #9
            BEQ  DB_SPACE
            CMPA #'#'
            BEQ  DB_HASH
            CMPA #'"'
            LBEQ DB_LIT
            CMPA #$27
            LBEQ DB_LIT
            JSR  ISDIGIT
            LBCC DB_NUM
            CMPA #'.'
            LBEQ DB_DOT
            JSR  ISIDST
            LBCC DB_ID
DB_CHAR     LEAX 1,X
            JSR  BPUT
            BRA  DB_LOOP
DB_SPACE    JSR  SKIPWS                ; spaces: one, and none after ##
            LDA  ,X
            LBEQ DB_END
            LDA  -1,Y
            CMPY #BODYBUF
            BEQ  DB_LOOP
            CMPA #MK_PASTE
            BEQ  DB_LOOP
            LDA  #' '
            JSR  BPUT
            BRA  DB_LOOP
DB_HASH     LDA  1,X
            CMPA #'#'
            BEQ  DB_PASTE
            LDA  <DEFFL
            BITA #MF_FUNC
            BEQ  DB_HCHAR
            LEAX 1,X                   ; # parameter
            JSR  SKIPWS
            LDA  ,X
            JSR  ISIDST
            BCS  DB_HBAD
            JSR  READID
            JSR  FINDPARAM
            BCS  DB_HBAD
            LDA  #MK_STR
            JSR  BPUT
            TFR  B,A
            JSR  BPUT
            LBRA DB_LOOP
DB_HCHAR    LDA  #'#'
            BRA  DB_CHAR
DB_HBAD     LDX  #M_HASHPARAM
            JMP  ERROR
DB_PASTE    LEAX 2,X
            JSR  TRIMBODY
            CMPY #BODYBUF
            BEQ  DB_PBAD
            LDA  #MK_PASTE
            JSR  BPUT
            JSR  SKIPWS
            LDA  ,X
            LBNE DB_LOOP
DB_PBAD     LDX  #M_PASTEEND
            JMP  ERROR
DB_LIT      STA  <INSTR
            LEAX 1,X
            JSR  BPUT
DB_LITL     LDA  ,X
            LBEQ DB_LOOP
            LEAX 1,X
            JSR  BPUT
            CMPA <INSTR
            LBEQ DB_LOOP
            CMPA #'\'
            BNE  DB_LITL
            LDA  ,X
            LBEQ DB_LOOP
            LEAX 1,X
            JSR  BPUT
            BRA  DB_LITL
DB_DOT      LDA  1,X
            JSR  ISDIGIT
            LDA  ,X
            LBCS DB_CHAR
DB_NUM      LDA  ,X+                   ; a number
            JSR  BPUT
DB_NLOOP    LDA  ,X
            CMPA #'e'
            BEQ  DB_NEXP
            CMPA #'E'
            BEQ  DB_NEXP
            CMPA #'p'
            BEQ  DB_NEXP
            CMPA #'P'
            BEQ  DB_NEXP
            CMPA #'.'
            BEQ  DB_N1
            JSR  ISIDCH
            LBCS DB_LOOP
DB_N1       LEAX 1,X
            JSR  BPUT
            BRA  DB_NLOOP
DB_NEXP     LDB  1,X
            CMPB #'+'
            BEQ  DB_N2
            CMPB #'-'
            BNE  DB_N1
DB_N2       LEAX 1,X
            JSR  BPUT
            LDA  ,X
            BRA  DB_N1
DB_ID       JSR  READID                ; a name: a parameter?
            LDA  <DEFFL
            BITA #MF_FUNC
            BEQ  DB_IDCOPY
            JSR  FINDPARAM
            BCS  DB_IDCOPY
            LDA  #MK_PARAM
            JSR  BPUT
            TFR  B,A
            JSR  BPUT
            LBRA DB_LOOP
DB_IDCOPY   PSHS X
            LDX  #NAMEBUF
DB_IC       LDA  ,X+
            BEQ  DB_ICE
            JSR  BPUT
            BRA  DB_IC
DB_ICE      PULS X
            LBRA DB_LOOP
DB_END      JSR  TRIMBODY
            TST  <BODYERR
            BEQ  DB_SIZE
            LDX  #M_BODYLONG
            JMP  ERROR
DB_SIZE     TFR  Y,D
            SUBD #BODYBUF
            STD  <BODYLEN
            LDX  #DEFNAME              ; a new definition replaces the old
            LDY  #NAMEBUF
            JSR  STRCPY
            JSR  LOOKUP
            BCS  DB_NEW
            JSR  UNLINK
DB_NEW      JMP  ADDMACRO
BPUT        CMPY #BODYBUF+BODYMAX
            BHS  BP_FULL
            STA  ,Y+
            RTS
BP_FULL     STA  <BODYERR
            RTS
; Y back past the spaces at the end of BODYBUF's text.
TRIMBODY    CMPY #BODYBUF
            BEQ  TB_RET
            LDA  -1,Y
            CMPA #' '
            BNE  TB_RET
            LEAY -1,Y
            BRA  TRIMBODY
TB_RET      RTS
; NAMEBUF -> PARBUF, a parameter. Carry set if there's no room.
ADDPARAM    LDA  <DEFNP
            CMPA #MAXPARAMS
            BHS  AP_NO
            LDY  <PARPTR
            CMPY #PARBUF+PARBUFSZ-NAMEMAX-2
            BHS  AP_NO
            PSHS X
            LDX  #NAMEBUF
            JSR  STRCPY
            LEAY 1,Y
            STY  <PARPTR
            PULS X
            INC  <DEFNP
            ANDCC #$FE
            RTS
AP_NO       ORCC #1
            RTS
; Is NAMEBUF a parameter? Carry clear if so: B = its number.
FINDPARAM   PSHS X,Y
            LDY  #PARBUF
            CLRB
FM_LOOP     CMPB <DEFNP
            BHS  FM_NO
            LDX  #NAMEBUF
            JSR  STRCMP
            BEQ  FM_YES
FM_SKIP     TST  ,Y+
            BNE  FM_SKIP
            INCB
            BRA  FM_LOOP
FM_YES      ANDCC #$FE
            PULS X,Y,PC
FM_NO       ORCC #1
            PULS X,Y,PC
;------------------------------------------------------------------------------
; #undef
;------------------------------------------------------------------------------
DO_UNDEF    LDA  ,X
            JSR  ISIDST
            BCS  DU_BAD
            JSR  READID
            JSR  LOOKUP
            BCS  DU_RET
            JMP  UNLINK
DU_BAD      LDX  #M_NOMACNAME
            JMP  ERROR
DU_RET      RTS
;------------------------------------------------------------------------------
; #include
;------------------------------------------------------------------------------
DO_INCLUDE  LDA  ,X
            CMPA #'"'
            BEQ  DN_GOT
            CMPA #'<'
            BEQ  DN_GOT
            PSHS X                     ; a macro that gives one of those
            CLR  <MOREOK
            JSR  SCAN
            PULS X
            JSR  SKIPWSMK
            LDA  ,X
            CMPA #'"'
            BEQ  DN_GOT
            CMPA #'<'
            BEQ  DN_GOT
DN_BAD      LDX  #M_INCBAD
            JMP  ERROR
DN_GOT      STA  <INCKIND
            LDB  #'"'
            CMPA #'<'
            BNE  DN_DELIM
            LDB  #'>'
DN_DELIM    STB  <INSTR
            LEAX 1,X
            LDY  #INCNAME
            CLRB
DN_COPY     LDA  ,X+
            BEQ  DN_BAD
            CMPA <INSTR
            BEQ  DN_END
            CMPA #MK_LAST
            BHI  DN_PUT
            BLO  DN_COPY
            LEAX 1,X
            BRA  DN_COPY
DN_PUT      CMPB #PATHMAX
            BHS  DN_COPY
            STA  ,Y+
            INCB
            BRA  DN_COPY
DN_END      CLR  ,Y
            TST  INCNAME
            BEQ  DN_BAD
            JSR  FINDINC
            BCS  DN_NOTF
            LDX  #PATHBUF
            JMP  PUSHFILE
DN_NOTF     LDX  #M_NOINC
            LDY  #INCNAME
            JMP  ERRORN
; INCNAME -> A = the file opened, PATHBUF = its path. Carry set if it's nowhere.
FINDINC     LDA  INCNAME
            CMPA #'/'
            BNE  FI_REL
            LDX  #INCNAME
            LDY  #PATHBUF
            JSR  STRCPY
            JMP  TRYOPEN
FI_REL      LDA  <INCKIND
            CMPA #'"'
            BNE  FI_DIRS
            LDU  <INP                  ; "": next to the file doing the #include
            LEAX IR_PATH,U
            LDY  #PATHBUF
            JSR  STRCPY
FI_BACK     CMPY #PATHBUF
            BEQ  FI_CUT
            LDA  -1,Y
            CMPA #'/'
            BEQ  FI_CUT
            LEAY -1,Y
            BRA  FI_BACK
FI_CUT      LDX  #INCNAME
            JSR  STRCPY
            JSR  TRYOPEN
            BCC  FI_RET
FI_DIRS     CLR  <TMPB                 ; then -I's directories
FI_LOOP     LDA  <TMPB
            CMPA <NINCDIR
            BHS  FI_STD
            LDB  #PATHMAX+1
            MUL
            LDX  #INCDIRS
            LEAX D,X
            JSR  TRYDIR
            BCC  FI_RET
            INC  <TMPB
            BRA  FI_LOOP
FI_STD      LDX  #S_INCDIR             ; then /INCLUDE
            JMP  TRYDIR
FI_RET      RTS
; X = a directory: INCNAME there opened (PATHBUF = the path).
TRYDIR      LDY  #PATHBUF
            JSR  STRCPY
            CMPY #PATHBUF
            BEQ  TD_NAME
            LDA  -1,Y
            CMPA #'/'
            BEQ  TD_NAME
            LDA  #'/'
            STA  ,Y+
TD_NAME     LDX  #INCNAME
            JSR  STRCPY
TRYOPEN     LDX  #PATHBUF              ; -> A = the file, or carry set
            LDE  #FOPEN_READ
            LDA  #B_FOPEN_NAME
            SWI2
            RTS
;------------------------------------------------------------------------------
; #line N ["FILE"], #error, #warning, #pragma
;------------------------------------------------------------------------------
DO_LINE     PSHS X
            CLR  <MOREOK
            JSR  SCAN
            PULS X
            JSR  SKIPWSMK
            LDA  ,X
            JSR  ISDIGIT
            BCS  DI_LBAD
            JSR  GETDEC
            LDU  <INP
            STD  IR_LINE,U
            JSR  SKIPWSMK
            LDA  ,X
            BEQ  DI_LDONE
            CMPA #'"'
            BNE  DI_LBAD
            LEAX 1,X
            LEAY IR_PATH,U
            CLRB
DI_LCOPY    LDA  ,X+
            BEQ  DI_LEND
            CMPA #'"'
            BEQ  DI_LEND
            CMPB #PATHMAX
            BHS  DI_LCOPY
            STA  ,Y+
            INCB
            BRA  DI_LCOPY
DI_LEND     CLR  ,Y
DI_LDONE    LDA  #1
            STA  <FILECHG
            RTS
DI_LBAD     LDX  #M_LINEBAD
            JMP  ERROR
; X at digits -> D = their value; X after them.
GETDEC      CLRD
            STD  <TMP
GD_LOOP     LDA  ,X
            JSR  ISDIGIT
            BCS  GD_END
            LEAX 1,X
            SUBA #'0'
            PSHS A
            LDD  <TMP
            LSLD
            PSHS D
            LSLD
            LSLD
            ADDD ,S++
            ADDB ,S+
            ADCA #0
            STD  <TMP
            BRA  GD_LOOP
GD_END      LDD  <TMP
            RTS
DO_ERROR    LDX  #LBUF
            JSR  SKIPWS
            JMP  ERROR
DO_WARNING  LDX  #LBUF
            JSR  SKIPWS
            JMP  WARN
DO_PRAGMA   LDX  #LBUF
            JSR  SKIPWS
            JMP  EMITLINE
;------------------------------------------------------------------------------
; #if and friends. CONDSTK has an entry for each #if open (CS_*).
;------------------------------------------------------------------------------
DO_IFDEF    CLR  <TMPB
            BRA  DI_COMMON
DO_IFNDEF   LDA  #1
            STA  <TMPB
DI_COMMON   JSR  CONDPUSH
            BCS  DI_RET
            LDA  ,X
            JSR  ISIDST
            BCS  DI_NONAME
            JSR  READID
            JSR  LOOKUP
            LDA  #0
            BCS  DI_TRUTH
            LDA  #1
DI_TRUTH    EORA <TMPB
            JMP  CONDSET
DI_NONAME   LDX  #M_NOMACNAME
            JSR  ERROR
            CLRA
            JMP  CONDSET
DO_IF       JSR  CONDPUSH
            BCS  DI_RET
            JSR  EVALIF
            JMP  CONDSET
DI_RET      RTS
; A new entry. Carry set if lines are being skipped already (the whole group
; is skipped: it is marked as having taken its branch).
CONDPUSH    LDB  <CONDSP
            CMPB #MAXCOND
            BHS  CP_DEEP
            LDY  #CONDSTK
            LEAY B,Y
            INC  <CONDSP
            TST  <SKIP
            BEQ  CP_LIVE
            LDA  #CS_OUTER+CS_TAKEN
            STA  ,Y
            ORCC #1
            RTS
CP_LIVE     CLR  ,Y
            ANDCC #$FE
            RTS
CP_DEEP     LDX  #M_CONDDEEP
            JMP  FATAL
; -> Y = the top entry.
TOPCOND     LDB  <CONDSP
            DECB
            LDY  #CONDSTK
            LEAY B,Y
            RTS
; A = whether the top entry's branch is true: taken, or skipped.
CONDSET     PSHS A
            BSR  TOPCOND
            PULS A
            TSTA
            BEQ  CS_FALSE
            LDA  ,Y
            ORA  #CS_TAKEN
            STA  ,Y
            CLR  <SKIP
            RTS
CS_FALSE    LDA  #1
            STA  <SKIP
            RTS
; Carry set (and said) if there's no #if open in this file.
OWNCOND     LDU  <INP
            LDA  IR_COND,U
            CMPA <CONDSP
            BLO  OC_YES
            LDX  #M_NOIF
            JSR  ERROR
            ORCC #1
            RTS
OC_YES      ANDCC #$FE
            RTS
DO_ELIF     JSR  OWNCOND
            BCS  CE_RET
            BSR  TOPCOND
            LDA  ,Y
            BITA #CS_ELSE
            BNE  CE_AFTER
            BITA #CS_OUTER
            BNE  CE_RET
            BITA #CS_TAKEN
            BNE  CE_SKIPIT
            LDX  <DIRARG
            JSR  EVALIF
            JMP  CONDSET
CE_SKIPIT   LDA  #1
            STA  <SKIP
CE_RET      RTS
CE_AFTER    LDX  #M_AFTERELSE
            JMP  ERROR
DO_ELSE     JSR  OWNCOND
            BCS  CE_RET
            BSR  TOPCOND
            LDA  ,Y
            BITA #CS_ELSE
            BNE  CE_AFTER
            ORA  #CS_ELSE
            STA  ,Y
            BITA #CS_OUTER
            BNE  CE_RET
            BITA #CS_TAKEN
            BNE  CE_SKIPIT
            ORA  #CS_TAKEN
            STA  ,Y
            CLR  <SKIP
            RTS
DO_ENDIF    JSR  OWNCOND
            BCS  CE_RET
            JSR  TOPCOND
            LDA  ,Y
            ANDA #CS_OUTER
            STA  <SKIP
            DEC  <CONDSP
            RTS
;------------------------------------------------------------------------------
; #if's expression: X = it (in LBUF). -> A = 1 if it's true, 0 if not. defined
; is done first, then the macros, then what's left (names are 0) is worked out
; (EV_*: U = the text, MA = values).
;------------------------------------------------------------------------------
EVALIF      CLR  <EVERR
            PSHS X
            JSR  DEFPASS
            LDX  ,S
            CLR  <MOREOK
            JSR  SCAN
            PULS U
            JSR  EVSKIP
            LDA  ,U
            BEQ  EF_EMPTY
            JSR  EV_COND
            JSR  EVSKIP
            LDA  ,U
            BEQ  EF_END
            LDX  #M_IFGARB
            JSR  EVERROR
EF_END      TST  <EVERR
            BNE  EF_FALSE
            JSR  ISZMA
            BEQ  EF_FALSE
            LDA  #1
            RTS
EF_FALSE    CLRA
            RTS
EF_EMPTY    LDX  #M_IFNONE
            JSR  ERROR
            CLRA
            RTS
; X = a message: said, unless one has been for this #if already. The rest of
; the expression is then skipped.
EVERROR     TST  <EVERR
            BNE  EE_STOP
            INC  <EVERR
            JSR  ERROR
EE_STOP     LDU  #ZERO
            RTS
; defined NAME and defined(NAME), from X: made 1 or 0 (and spaces).
DEFPASS     LDA  ,X
            LBEQ DP_RET
            CMPA #'"'
            BEQ  DP_LIT
            CMPA #$27
            BEQ  DP_LIT
            JSR  ISDIGIT
            BCC  DP_NUM
            JSR  ISIDST
            BCC  DP_ID
            LEAX 1,X
            BRA  DEFPASS
DP_LIT      JSR  SKIPLIT
            BRA  DEFPASS
DP_NUM      JSR  SKIPNUM
            BRA  DEFPASS
DP_ID       STX  <INVQ
            JSR  READID
            PSHS X
            LDX  #NAMEBUF
            LDY  #S_DEFINED
            JSR  STRCMP
            PULS X
            BNE  DEFPASS
            JSR  SKIPWS
            CLR  <TMPB
            LDA  ,X
            CMPA #'('
            BNE  DP_NAME
            INC  <TMPB
            LEAX 1,X
            JSR  SKIPWS
DP_NAME     LDA  ,X
            JSR  ISIDST
            BCS  DP_BAD
            JSR  READID
            TST  <TMPB
            BEQ  DP_LOOK
            JSR  SKIPWS
            LDA  ,X
            CMPA #')'
            BNE  DP_BAD
            LEAX 1,X
DP_LOOK     PSHS X
            JSR  LOOKUP
            LDB  #'0'
            BCS  DP_FILL
            LDB  #'1'
DP_FILL     PULS X
            LDY  <INVQ
            STB  ,Y+
            STX  <TMP
DP_SPC      CMPY <TMP
            BHS  DEFPASS
            LDA  #' '
            STA  ,Y+
            BRA  DP_SPC
DP_BAD      LDX  #M_DEFBAD
            JSR  ERROR
            INC  <EVERR
DP_RET      RTS
; U: past spaces and markers.
EVSKIP      LDA  ,U
            BEQ  ES_RET
            CMPA #' '
            BEQ  ES_1
            CMPA #9
            BEQ  ES_1
            CMPA #MK_LAST
            BHI  ES_RET
            BLO  ES_1
            LEAU 1,U
ES_1        LEAU 1,U
            BRA  EVSKIP
ES_RET      RTS
; c ? a : b
EV_COND     LDB  #1
            JSR  EV_EXPR
            JSR  EVSKIP
            LDA  ,U
            CMPA #'?'
            BNE  EC_RET
            LEAU 1,U
            PUSHMA
            BSR  EV_COND
            PUSHMA
            JSR  EVSKIP
            LDA  ,U
            CMPA #':'
            BEQ  EC_COLON
            LDX  #M_IFCOLON
            JSR  EVERROR
EC_COLON    LEAU 1,U
            BSR  EV_COND
            PULS D                     ; MB = a
            PULSW
            STQ  MB
            PULS D                     ; c
            PULSW
            TSTD
            BNE  EC_A
            TSTW
            BEQ  EC_RET
EC_A        LDQ  MB
            STQ  MA
EC_RET      RTS
; Binary operators of precedence B and above, by precedence climbing.
EV_EXPR     PSHS B
            JSR  EV_UNARY
EX_LOOP     JSR  EV_PEEKOP             ; A = the operator, B = its precedence
            CMPB ,S
            BLO  EX_RET
            PSHS A
            LDA  <TMPB
            LEAU A,U
            INCB
            PSHS B
            PUSHMA                     ; (LDQ: D goes)
            LDB  4,S
            BSR  EV_EXPR               ; the right side: higher precedences
            LDQ  MA
            STQ  MB
            PULLMA
            LEAS 1,S
            PULS A
            JSR  EV_APPLY
            BRA  EX_LOOP
EX_RET      PULS B,PC
; The operator at U -> A = its OP_*, B = its precedence (0: none), TMPB = its
; length. U doesn't move.
EV_PEEKOP   JSR  EVSKIP
            LDD  ,U
            LDX  #OPTAB
PK_LOOP     TST  ,X
            BEQ  PK_NONE
            CMPA ,X
            BNE  PK_NEXT
            TST  1,X
            BEQ  PK_ONE
            CMPB 1,X
            BEQ  PK_TWO
PK_NEXT     LEAX 4,X
            BRA  PK_LOOP
PK_ONE      LDA  #1
            BRA  PK_GOT
PK_TWO      LDA  #2
PK_GOT      STA  <TMPB
            LDD  2,X
            RTS
PK_NONE     CLRB
            RTS
OPTAB       FCB  '|','|',OP_LOR,1
            FCB  '&','&',OP_LAND,2
            FCB  '=','=',OP_EQ,6
            FCB  '!','=',OP_NE,6
            FCB  '<','<',OP_SHL,8
            FCB  '>','>',OP_SHR,8
            FCB  '<','=',OP_LE,7
            FCB  '>','=',OP_GE,7
            FCB  '|',0,OP_BOR,3
            FCB  '^',0,OP_XOR,4
            FCB  '&',0,OP_BAND,5
            FCB  '<',0,OP_LT,7
            FCB  '>',0,OP_GT,7
            FCB  '+',0,OP_ADD,9
            FCB  '-',0,OP_SUB,9
            FCB  '*',0,OP_MUL,10
            FCB  '/',0,OP_DIV,10
            FCB  '%',0,OP_MOD,10
            FCB  0
; MA = MA op MB (A = the OP_*).
EV_APPLY    DECA
            LSLA
            LDX  #APTAB
            JMP  [A,X]
APTAB       FDB  AY_LOR,AY_LAND,AY_BOR,AY_XOR,AY_BAND,AY_EQ,AY_NE,AY_LT
            FDB  AY_GT,AY_LE,AY_GE,AY_SHL,AY_SHR,AY_ADD,AY_SUB,AY_MUL
            FDB  AY_DIV,AY_MOD
; Z set if MA (ISZMA) or MB (ISZMB) is 0. (LDQ's Z is only bits 31-16's.)
ISZMA       LDD  MA
            BNE  IZ_RET
            LDD  MA+2
IZ_RET      RTS
ISZMB       LDD  MB
            BNE  IZ_RET
            LDD  MB+2
            RTS
MA1         CLRD
            STD  MA
            INCB
            STD  MA+2
            RTS
MA0         CLRD
            STD  MA
            STD  MA+2
            RTS
AY_LOR      BSR  ISZMA
            BNE  MA1
            BSR  ISZMB
            BNE  MA1
            BRA  MA0
AY_LAND     BSR  ISZMA
            BEQ  MA0
            BSR  ISZMB
            BEQ  MA0
            BRA  MA1
AY_BOR      LDD  MA
            ORA  MB
            ORB  MB+1
            STD  MA
            LDD  MA+2
            ORA  MB+2
            ORB  MB+3
            STD  MA+2
            RTS
AY_XOR      LDD  MA
            EORA MB
            EORB MB+1
            STD  MA
            LDD  MA+2
            EORA MB+2
            EORB MB+3
            STD  MA+2
            RTS
AY_BAND     LDD  MA
            ANDA MB
            ANDB MB+1
            STD  MA
            LDD  MA+2
            ANDA MB+2
            ANDB MB+3
            STD  MA+2
            RTS
EQ32        LDD  MA
            CMPD MB
            BNE  EQ_RET
            LDD  MA+2
            CMPD MB+2
EQ_RET      RTS
AY_EQ       BSR  EQ32
            BEQ  MA1
            BRA  MA0
AY_NE       BSR  EQ32
            BNE  MA1
            BRA  MA0
AY_LT       LDQ  MA                    ; (SBCD's N and V are the 32 bits')
            SUBW MB+2
            SBCD MB
            BLT  MA1
            BRA  MA0
AY_GE       LDQ  MA
            SUBW MB+2
            SBCD MB
            LBGE MA1
            LBRA MA0
AY_GT       LDQ  MB
            SUBW MA+2
            SBCD MA
            LBLT MA1
            LBRA MA0
AY_LE       LDQ  MB
            SUBW MA+2
            SBCD MA
            LBGE MA1
            LBRA MA0
AY_ADD      LDQ  MA
            ADDW MB+2
            ADCD MB
            STQ  MA
            RTS
AY_SUB      LDQ  MA
            SUBW MB+2
            SBCD MB
            STQ  MA
            RTS
AY_MUL      JMP  MUL32
AY_DIV      JSR  ISZMB
            BEQ  AY_DIV0
            JMP  DIV32
AY_MOD      JSR  ISZMB
            BEQ  AY_DIV0
            JSR  DIV32
            LDQ  MB
            STQ  MA
            RTS
AY_DIV0     LDX  #M_DIV0
            JSR  EVERROR
            JMP  MA0
; -> B = MB as a shift count; carry set if it's more than 31 (or negative).
SHCOUNT     LDD  MB
            BNE  SH_BIG
            LDD  MB+2
            TSTA
            BNE  SH_BIG
            CMPB #32
            BHS  SH_BIG
            ANDCC #$FE
            RTS
SH_BIG      ORCC #1
            RTS
AY_SHL      BSR  SHCOUNT
            LBCS MA0
AY_SL       TSTB
            BEQ  AY_SRET
            LSL  MA+3
            ROL  MA+2
            ROL  MA+1
            ROL  MA
            DECB
            BRA  AY_SL
AY_SHR      BSR  SHCOUNT
            BCC  AY_SR
            LDB  #32
AY_SR       TSTB
            BEQ  AY_SRET
            ASR  MA
            ROR  MA+1
            ROR  MA+2
            ROR  MA+3
            DECB
            BRA  AY_SR
AY_SRET     RTS
; A primary, with unary operators before it -> MA.
EV_UNARY    JSR  EVSKIP
            LDA  ,U
            CMPA #'('
            BEQ  EU_PAREN
            CMPA #'-'
            BEQ  EU_NEG
            CMPA #'+'
            BEQ  EU_PLUS
            CMPA #'~'
            BEQ  EU_COM
            CMPA #'!'
            BEQ  EU_NOT
            CMPA #$27
            LBEQ EV_CHAR
            JSR  ISDIGIT
            LBCC EV_NUMBER
            JSR  ISIDST
            BCC  EU_ID
            LDX  #M_IFBAD
            JSR  EVERROR
            JMP  MA0
EU_ID       LEAU 1,U                   ; a name that isn't a macro: 0
EU_IDL      LDA  ,U
            JSR  ISIDCH
            LBCS MA0
            LEAU 1,U
            BRA  EU_IDL
EU_PAREN    LEAU 1,U
            JSR  EV_COND
            JSR  EVSKIP
            LDA  ,U
            CMPA #')'
            BEQ  EU_CLOSE
            LDX  #M_IFPAREN
            JMP  EVERROR
EU_CLOSE    LEAU 1,U
            RTS
EU_NEG      LEAU 1,U
            BSR  EV_UNARY
            LDX  #MA
            JMP  NEG32
EU_PLUS     LEAU 1,U
            BRA  EV_UNARY
EU_COM      LEAU 1,U
            BSR  EV_UNARY
            COM  MA
            COM  MA+1
            COM  MA+2
            COM  MA+3
            RTS
EU_NOT      LEAU 1,U
            BSR  EV_UNARY
            JSR  ISZMA
            LBEQ MA1
            JMP  MA0
; A number: decimal, 0x hex, or octal; a u or l after it is skipped.
EV_NUMBER   JSR  MA0
            LDB  #10
            LDA  ,U
            CMPA #'0'
            BNE  EN_BASE
            LDB  #8
            LDA  1,U
            ORA  #$20
            CMPA #'x'
            BNE  EN_BASE
            LDB  #16
            LEAU 2,U
EN_BASE     STB  <EVBASE
EN_LOOP     LDA  ,U
            JSR  HEXVAL
            BCS  EN_SUFFIX
            CMPA <EVBASE
            BHS  EN_SUFFIX
            PSHS A
            CLRD
            STD  MB
            LDB  <EVBASE
            STD  MB+2
            JSR  MUL32
            PULS B
            CLRA
            STD  <TMP
            LDQ  MA
            ADDW <TMP
            ADCD #0
            STQ  MA
            LEAU 1,U
            BRA  EN_LOOP
EN_SUFFIX   LDA  ,U
            ORA  #$20
            CMPA #'u'
            BEQ  EN_SKIP
            CMPA #'l'
            BNE  EN_RET
EN_SKIP     LEAU 1,U
            BRA  EN_SUFFIX
EN_RET      RTS
; A = a hex digit -> A = its value; carry set if it isn't one.
HEXVAL      CMPA #'0'
            BLO  HV_NO
            CMPA #'9'
            BLS  HV_DIG
            ORA  #$20
            CMPA #'a'
            BLO  HV_NO
            CMPA #'f'
            BHI  HV_NO
            SUBA #'a'-10
            ANDCC #$FE
            RTS
HV_DIG      SUBA #'0'
            ANDCC #$FE
            RTS
HV_NO       ORCC #1
            RTS
; 'c' -> MA.
EV_CHAR     LEAU 1,U
            LDA  ,U+
            CMPA #'\'
            BNE  EH_VAL
            JSR  ESCCHAR
EH_VAL      PSHS A
            JSR  MA0
            PULS A
            STA  MA+3
            LDA  ,U
            CMPA #$27
            BNE  EH_BAD
            LEAU 1,U
            RTS
EH_BAD      LDX  #M_IFBAD
            JMP  EVERROR
; U just past a backslash: the escape -> A; U after it.
ESCCHAR      LDA  ,U+
            LDX  #ESCTAB
EP_LOOP     TST  ,X
            BEQ  EP_OCT
            CMPA ,X++
            BNE  EP_LOOP
            LDA  -1,X
            RTS
EP_OCT      CMPA #'x'
            BEQ  EP_HEX
            CMPA #'0'
            BLO  EP_RET
            CMPA #'7'
            BHI  EP_RET
            SUBA #'0'                  ; up to three octal digits
            LDB  #2
EP_OL       PSHS A
            LDA  ,U
            CMPA #'0'
            BLO  EP_OEND
            CMPA #'7'
            BHI  EP_OEND
            LEAU 1,U
            SUBA #'0'
            STA  <TMPB
            PULS A
            LSLA
            LSLA
            LSLA
            ORA  <TMPB
            DECB
            BNE  EP_OL
            RTS
EP_OEND     PULS A,PC
EP_HEX      CLR  <TMPB
EP_HL       LDA  ,U
            JSR  HEXVAL
            BCS  EP_HEND
            LEAU 1,U
            LDB  <TMPB
            LSLB
            LSLB
            LSLB
            LSLB
            PSHS A
            ORB  ,S+
            STB  <TMPB
            BRA  EP_HL
EP_HEND     LDA  <TMPB
EP_RET      RTS
ESCTAB      FCB  'n',10,'t',9,'r',13,'a',7,'b',8,'f',12,'v',11,0
;------------------------------------------------------------------------------
; Macro expansion: from X to the NUL at LEND, in place. MOREOK: a call's
; arguments may go on in the lines after. SCAN begins afresh; SCAN1 goes on
; with the active stack as it is (an argument is expanded so before it goes in
; its macro's replacement, as the standard has it).
;------------------------------------------------------------------------------
SCAN        CLR  <ASP
            CLR  <NEST
SCAN1
XP_LOOP     LDA  ,X
            LBEQ XP_DONE
            CMPA #MK_END
            BEQ  XP_END
            CMPA #MK_PAINT
            BEQ  XP_PAINT
            CMPA #'"'
            BEQ  XP_LIT
            CMPA #$27
            BEQ  XP_LIT
            JSR  ISDIGIT
            BCC  XP_NUM
            CMPA #'.'
            BEQ  XP_DOT
            JSR  ISIDST
            BCC  XP_ID
XP_NEXT     LEAX 1,X
            BRA  XP_LOOP
XP_END      LDA  #MK_NOP               ; a replacement ends
            STA  ,X+
            DEC  <ASP
            BRA  XP_LOOP
XP_PAINT    LEAX 1,X
            JSR  SKIPID
            BRA  XP_LOOP
XP_LIT      JSR  SKIPLIT
            BRA  XP_LOOP
XP_DOT      LDA  1,X
            JSR  ISDIGIT
            BCS  XP_NEXT
XP_NUM      JSR  SKIPNUM
            BRA  XP_LOOP
XP_ID       STX  <INVQ                 ; a name: a macro?
            JSR  READID
            STX  <INVZ
            JSR  LOOKUP
            LDX  <INVZ
            BCS  XP_LOOP
            JSR  ISACTIVE
            BCS  XP_PAINTIT
            LDA  <MFLAGS
            BITA #MF_FUNC
            BEQ  XP_OBJ
            JSR  FINDPAREN             ; function-like: only with arguments
            BCS  XP_LOOP
            JSR  COLLECT
            BCS  XP_LOOP
            JSR  ARGCHECK
            BCS  XP_LOOP
            JSR  PRESCAN
            BCS  XP_TRUNC
            BRA  XP_EXPAND
XP_OBJ      CLR  <NARGS
XP_EXPAND   JSR  BUILDREP
            JSR  SPLICE
            BCS  XP_DONE
            JSR  PUSHMAC
            BCS  XP_TRUNC
            LDX  <INVQ                 ; the replacement is scanned again
            LBRA XP_LOOP
XP_PAINTIT  JSR  PAINT
            LBRA XP_LOOP
XP_TRUNC    LDX  <INVQ                 ; (something overflowed: the line ends)
            CLR  ,X
            STX  <LEND
XP_DONE     RTS
; Is the macro MACP being expanded (on the active stack)? Carry set if so.
; Keeps X.
ISACTIVE    PSHS X
            LDB  <ASP
            LDA  #3
            MUL
            LDX  #ACTSTK
            ABX
IA_LOOP     CMPX #ACTSTK
            BEQ  IA_NO
            LEAX -3,X
            LDA  ,X
            CMPA <MACP
            BNE  IA_LOOP
            LDD  1,X
            CMPD <MACP+1
            BNE  IA_LOOP
            PULS X
            ORCC #1
            RTS
IA_NO       PULS X
            ANDCC #$FE
            RTS
; MACP's replacement begins: it goes on the active stack. Carry set (said) if
; that's full.
PUSHMAC     LDB  <ASP
            CMPB #MAXACT
            BHS  PM_FULL
            LDA  #3
            MUL
            LDY  #ACTSTK
            LEAY D,Y
            LDA  <MACP
            STA  ,Y
            LDD  <MACP+1
            STD  1,Y
            INC  <ASP
            ANDCC #$FE
            RTS
PM_FULL     LDX  #M_DEEPMAC
            JSR  ERROR
            ORCC #1
            RTS
; The name at INVQ (INVZ after it) is never to be expanded: MK_PAINT before
; it. -> X after it.
PAINT       LDD  <LEND
            CMPD #LBUF+LBUFMAX
            BHS  PT_FULL
            SUBD <INVQ
            ADDD #1
            TFR  D,W
            LDX  <LEND
            LEAY 1,X
            TFM  X-,Y-
            LDX  <INVQ
            LDA  #MK_PAINT
            STA  ,X
            LDX  <LEND
            LEAX 1,X
            STX  <LEND
            LDX  <INVZ
            LEAX 1,X
            RTS
PT_FULL     LDX  <INVZ
            RTS
; X after a function-like macro's name: carry clear if a '(' follows (past
; spaces and markers, and the lines after, if MOREOK). X doesn't move.
FINDPAREN   LEAY ,X
FN_LOOP     LDA  ,Y
            BEQ  FN_EOL
            CMPA #'('
            BEQ  FN_YES
            CMPA #' '
            BEQ  FN_1
            CMPA #9
            BEQ  FN_1
            CMPA #MK_NOP
            BEQ  FN_1
            CMPA #MK_END
            BNE  FN_NO
FN_1        LEAY 1,Y
            BRA  FN_LOOP
FN_EOL      TST  <MOREOK
            BEQ  FN_NO
            JSR  APPENDLINE
            BCC  FN_LOOP
FN_NO       ORCC #1
            RTS
FN_YES      ANDCC #$FE
            RTS
; X after the name, a '(' ahead: the arguments -> ARGST/ARGEN, NARGS; INVZ
; after the ')'. An MK_END on the way ends what it ends now (it was begun
; before the call). Carry set (said) if they don't end: X at the end.
COLLECT     CLR  <NARGS
CO_PRE      LDA  ,X
            CMPA #'('
            BEQ  CO_OPEN
            CMPA #MK_END
            BNE  CO_PRE1
            JSR  CO_POP
            BRA  CO_PRE
CO_PRE1     LEAX 1,X
            BRA  CO_PRE
CO_OPEN     LEAX 1,X
            CLR  <PDEPTH
            JSR  CO_START
CO_LOOP     LDA  ,X
            BEQ  CO_EOL
            CMPA #'('
            BEQ  CO_LP
            CMPA #')'
            BEQ  CO_RP
            CMPA #44                   ; ','
            BEQ  CO_COMMA
            CMPA #'"'
            BEQ  CO_LIT
            CMPA #$27
            BEQ  CO_LIT
            CMPA #MK_END
            BEQ  CO_MK
CO_SKIP1    LEAX 1,X
            BRA  CO_LOOP
CO_LIT      JSR  SKIPLIT
            BRA  CO_LOOP
CO_MK       BSR  CO_POP
            BRA  CO_LOOP
CO_LP       INC  <PDEPTH
            BRA  CO_SKIP1
CO_RP       TST  <PDEPTH
            BEQ  CO_CLOSE
            DEC  <PDEPTH
            BRA  CO_SKIP1
CO_COMMA    TST  <PDEPTH
            BNE  CO_SKIP1
            LDA  <MFLAGS               ; in "..."'s part, commas are its
            BITA #MF_VAR
            BEQ  CO_SPLIT
            LDA  <NARGS
            INCA
            CMPA <MNPAR
            BHS  CO_SKIP1
CO_SPLIT    JSR  CO_FINISH
            BCS  CO_MANY
            LEAX 1,X
            JSR  CO_START
            BRA  CO_LOOP
CO_EOL      TST  <MOREOK
            BEQ  CO_UNT
            JSR  APPENDLINE
            BCC  CO_LOOP
CO_UNT      LDX  #M_UNTERMARGS
            BRA  CO_FAIL
CO_MANY     LDX  #M_MANYARGS
CO_FAIL     LDY  #NAMEBUF
            JSR  ERRORN
            LDX  <LEND
            ORCC #1
            RTS
CO_CLOSE    JSR  CO_FINISH
            BCS  CO_MANY
            LEAX 1,X
            STX  <INVZ
            ANDCC #$FE
            RTS
CO_POP      LDA  #MK_NOP
            STA  ,X+
            DEC  <ASP
            RTS
CO_START    LDB  <NARGS
            LSLB
            LDY  #ARGST
            STX  B,Y
            RTS
CO_FINISH   LDB  <NARGS
            CMPB #MAXPARAMS
            BHS  CF_MANY
            LSLB
            LDY  #ARGEN
            STX  B,Y
            INC  <NARGS
            ANDCC #$FE
            RTS
CF_MANY     ORCC #1
            RTS
; Are there as many arguments as parameters? Carry set (said) if not: X =
; INVZ. (One empty argument is none; "..." may get none.)
ARGCHECK    LDA  <MNPAR
            BNE  AC_SOME
            LDA  <NARGS
            CMPA #1
            BNE  AC_BAD
            CLRB
            JSR  ARGRANGE
AC_EMPTY    CMPU <AEND
            BHS  AC_NONE
            LDA  ,U+
            CMPA #' '
            BEQ  AC_EMPTY
            CMPA #9
            BEQ  AC_EMPTY
            CMPA #MK_PASTE
            BHI  AC_BAD
            BRA  AC_EMPTY
AC_NONE     CLR  <NARGS
            BRA  AC_OK
AC_SOME     LDA  <MFLAGS
            BITA #MF_VAR
            BEQ  AC_EXACT
            LDA  <NARGS
            INCA
            CMPA <MNPAR
            BNE  AC_EXACT
            LDB  <NARGS                ; "..." gets an empty argument
            LSLB
            LDY  <INVZ
            LEAY -1,Y
            LDX  #ARGST
            STY  B,X
            LDX  #ARGEN
            STY  B,X
            INC  <NARGS
AC_EXACT    LDA  <NARGS
            CMPA <MNPAR
            BNE  AC_BAD
AC_OK       LDX  <INVZ
            ANDCC #$FE
            RTS
AC_BAD      LDX  #M_ARGCOUNT
            LDY  #NAMEBUF
            JSR  ERRORN
            LDX  <INVZ
            ORCC #1
            RTS
; B = an argument's number -> U = its start, AEND = its end.
ARGRANGE    LSLB
            CLRA
            TFR  D,U
            LDD  ARGEN,U
            STD  <AEND
            LDU  ARGST,U
            RTS
; MACP's body -> BSTART, BEND (mapped).
BODYINFO    LDA  <MACP
            JSR  MAPPG
            LDX  <MACP+1
            LEAX MR_NAME,X
BI_NM       TST  ,X+
            BNE  BI_NM
            STX  <BSTART
            TFR  X,D
            ADDD <MBLEN
            STD  <BEND
            RTS
; The arguments the body uses to be expanded (not by # or ##) are expanded
; first, each in a copy above the line's end -> EXPST/EXPEN. Carry set (said)
; if there's no room.
PRESCAN     LDX  #ZERO
            LDY  #EXPST
            LDW  #(MAXPARAMS+1)*2
            TFM  X,Y+
            LDD  <LEND
            ADDD #1
            STD  <SCRP
            JSR  BODYINFO
            CLR  <PASTENX
            LDX  <BSTART
PS_LOOP     CMPX <BEND
            BHS  PS_DONE
            LDA  ,X+
            CMPA #MK_PASTE
            BEQ  PS_PASTE
            CMPA #MK_STR
            BEQ  PS_STR
            CMPA #MK_PARAM
            BEQ  PS_PARAM
PS_OTHER    CLR  <PASTENX
            BRA  PS_LOOP
PS_PASTE    LDA  #1
            STA  <PASTENX
            BRA  PS_LOOP
PS_STR      LEAX 1,X
            BRA  PS_OTHER
PS_PARAM    LDB  ,X+
            TST  <PASTENX
            BNE  PS_OTHER
            CMPX <BEND
            BHS  PS_EXP
            LDA  ,X
            CMPA #MK_PASTE
            BEQ  PS_OTHER
PS_EXP      PSHS B
            LSLB
            LDY  #EXPST
            LDD  B,Y
            PULS B
            BNE  PS_OTHER              ; (expanded already)
            PSHS X
            JSR  EXPANDARG
            PULS X
            BCS  PS_RET
            LDA  <MACP                 ; (the body's page back)
            JSR  MAPPG
            BRA  PS_OTHER
PS_DONE     ANDCC #$FE
PS_RET      RTS
; Argument B: a copy at SCRP, expanded there (by SCAN1, everything of this
; call's saved on the stack meanwhile) -> EXPST/EXPEN; SCRP after it.
EXPANDARG   PSHS B
            JSR  ARGRANGE
            JSR  ARGLEAD
            LDY  <SCRP
EA_COPY     CMPU <AEND
            BHS  EA_TRIM
            LDA  ,U+
            CMPA #MK_NOP
            BEQ  EA_COPY
            CMPY #LBUF+LBUFMAX-1
            LBHS EA_FULL
            STA  ,Y+
            BRA  EA_COPY
EA_TRIM     CMPY <SCRP
            BLS  EA_NUL
            LDA  -1,Y
            CMPA #' '
            BEQ  EA_T1
            CMPA #9
            BNE  EA_NUL
EA_T1       LEAY -1,Y
            BRA  EA_TRIM
EA_NUL      CLR  ,Y
            LDA  <NEST
            CMPA #MAXNEST
            BHS  EA_DEEP
            INC  <NEST
            LEAS -SAVESZ,S             ; this call's state onto the stack
            PSHS Y
            LDX  #CS_BEG
            LEAY 2,S
            LDW  #CS_END-CS_BEG
            TFM  X+,Y+
            LDX  #ARR_BEG
            LDW  #ARR_END-ARR_BEG
            TFM  X+,Y+
            PULS Y
            STY  <LEND
            CLR  <MOREOK
            LDX  <SCRP
            JSR  SCAN1
            LDY  <LEND                 ; where the expansion ends
            LEAX ,S                    ; the state back
            PSHS Y
            LDY  #CS_BEG
            LDW  #CS_END-CS_BEG
            TFM  X+,Y+
            LDY  #ARR_BEG
            LDW  #ARR_END-ARR_BEG
            TFM  X+,Y+
            PULS Y
            LEAS SAVESZ,S
            DEC  <NEST
            PULS B
            LSLB
            CLRA
            TFR  D,X
            STY  EXPEN,X
            LDD  <SCRP
            STD  EXPST,X
            LEAY 1,Y
            STY  <SCRP
            ANDCC #$FE
            RTS
EA_FULL     LDX  #M_EXPLONG
            BRA  EA_FAIL
EA_DEEP     LDX  #M_DEEPMAC
EA_FAIL     JSR  ERROR
            PULS B
            ORCC #1
            RTS
; MACP's replacement, for the arguments found -> RBUF (RPTR at its end), with
; an MK_END after it.
BUILDREP    LDY  #RBUF
            CLR  <PASTENX
            CLR  <RBFULL
            LDA  <MFLAGS
            BITA #MF_LINE
            LBNE BR_LINE
            BITA #MF_FILE
            LBNE BR_FILE
            JSR  BODYINFO
            LDX  <BSTART
BR_LOOP     CMPX <BEND
            BHS  BR_DONE
            LDA  ,X+
            CMPA #MK_PASTE
            BEQ  BR_PASTE
            CMPA #MK_PARAM
            BEQ  BR_PARAM
            CMPA #MK_STR
            BEQ  BR_STR
            JSR  RPUT
            CLR  <PASTENX
            BRA  BR_LOOP
BR_PASTE    JSR  RTRIM                 ; ##: what's on each side is joined
            LDA  #1
            STA  <PASTENX
            BRA  BR_LOOP
BR_PARAM    LDB  ,X+                   ; a parameter: next to ##, as written;
            TST  <PASTENX              ; otherwise expanded
            BNE  BR_RAW
            CMPX <BEND
            BHS  BR_EXP
            LDA  ,X
            CMPA #MK_PASTE
            BEQ  BR_RAW
BR_EXP      JSR  EXPARG
            BRA  BR_NEXT
BR_RAW      JSR  RAWARG
BR_NEXT     CLR  <PASTENX
            BRA  BR_LOOP
BR_STR      LDB  ,X+
            JSR  STRARG
            BRA  BR_NEXT
BR_DONE     LDA  #MK_END               ; (RBUF has room for it)
            STA  ,Y+
            STY  <RPTR
            RTS
BR_LINE     LDD  <STARTLN
            PSHS Y
            LDX  #NUMBUF
            JSR  DECSTR
            PULS Y
            LDX  #NUMBUF
BR_PUTS     LDA  ,X+
            BEQ  BR_DONE
            JSR  RPUT
            BRA  BR_PUTS
BR_FILE     LDA  #'"'
            JSR  RPUT
            LDX  <INP
            LEAX IR_PATH,X
BR_FL       LDA  ,X+
            BEQ  BR_FE
            JSR  RPUT
            BRA  BR_FL
BR_FE       LDA  #'"'
            JSR  RPUT
            BRA  BR_DONE
RPUT        CMPY #RBUF+RBUFMAX
            BHS  RP_FULL
            STA  ,Y+
            RTS
RP_FULL     STA  <RBFULL
            RTS
; Y back past spaces and tabs (not before RBUF).
RTRIM       CMPY #RBUF
            BEQ  RT_RET
            LDA  -1,Y
            CMPA #' '
            BEQ  RT_1
            CMPA #9
            BNE  RT_RET
RT_1        LEAY -1,Y
            BRA  RTRIM
RT_RET      RTS
; U: past an argument's leading spaces and markers (to AEND).
ARGLEAD     CMPU <AEND
            BHS  AL2_RET
            LDA  ,U
            CMPA #' '
            BEQ  AL2_1
            CMPA #9
            BEQ  AL2_1
            CMPA #MK_LAST
            BHI  AL2_RET
AL2_1       LEAU 1,U
            BRA  ARGLEAD
AL2_RET     RTS
; Argument B as written (no markers, no spaces at either end) -> RBUF.
RAWARG      PSHS X
            JSR  ARGRANGE
            BSR  ARGLEAD
            STY  <TMP2
RA_LOOP     CMPU <AEND
            BHS  RA_TRIM
            LDA  ,U+
            CMPA #MK_LAST
            BLS  RA_LOOP
            JSR  RPUT
            BRA  RA_LOOP
RA_TRIM     CMPY <TMP2
            BLS  RA_END
            LDA  -1,Y
            CMPA #' '
            BEQ  RA_T1
            CMPA #9
            BNE  RA_END
RA_T1       LEAY -1,Y
            BRA  RA_TRIM
RA_END      PULS X,PC
; Argument B as expanded (EXPST) -> RBUF.
EXPARG      PSHS B,X
            LSLB
            CLRA
            TFR  D,U
            LDD  EXPEN,U
            STD  <AEND
            LDU  EXPST,U
            BNE  XA_LOOP
            PULS B,X                   ; (not expanded: as written)
            BRA  RAWARG
XA_LOOP     CMPU <AEND
            BHS  XA_END
            LDA  ,U+
            CMPA #MK_NOP
            BEQ  XA_LOOP
            JSR  RPUT
            BRA  XA_LOOP
XA_END      PULS B,X,PC
; # argument B: as a string literal.
STRARG      PSHS X
            JSR  ARGRANGE
            LDA  #'"'
            JSR  RPUT
            CLR  <INSTR
            CLR  <SPPEND
            BSR  ARGLEAD
SA_LOOP     CMPU <AEND
            BHS  SA_END
            LDA  ,U+
            CMPA #MK_LAST
            BLS  SA_LOOP
            TST  <INSTR
            BNE  SA_IN
            CMPA #' '
            BEQ  SA_SP
            CMPA #9
            BEQ  SA_SP
            TST  <SPPEND               ; spaces between: one
            BEQ  SA_OUT
            CLR  <SPPEND
            PSHS A
            LDA  #' '
            JSR  RPUT
            PULS A
SA_OUT      CMPA #'"'
            BEQ  SA_DQ
            CMPA #$27
            BNE  SA_PUT
            STA  <INSTR
            BRA  SA_PUT
SA_DQ       STA  <INSTR
            BRA  SA_ESC
SA_SP       LDA  #1
            STA  <SPPEND
            BRA  SA_LOOP
SA_IN       CMPA #'\'                  ; in a literal: " and \ get a \
            BEQ  SA_BS
            CMPA <INSTR
            BNE  SA_IN2
            CLR  <INSTR
SA_IN2      CMPA #'"'
            BEQ  SA_ESC
SA_PUT      JSR  RPUT
            BRA  SA_LOOP
SA_ESC      PSHS A
            LDA  #'\'
            JSR  RPUT
            PULS A
            BRA  SA_PUT
SA_BS       JSR  RPUT
            JSR  RPUT
            CMPU <AEND
            BHS  SA_END
            LDA  ,U+
            CMPA #'"'
            BEQ  SA_ESC
            CMPA #'\'
            BEQ  SA_ESC
            BRA  SA_PUT
SA_END      LDA  #'"'
            JSR  RPUT
            PULS X,PC
; [INVQ, INVZ) in LBUF -> the replacement in RBUF. Carry set (said) if the line
; would be too long: it then ends at INVQ.
SPLICE      TST  <RBFULL
            BNE  SPL_FULL
            LDD  <RPTR
            SUBD #RBUF
            STD  <NEWLEN
            LDD  <INVZ
            SUBD <INVQ
            STD  <TMP2
            LDD  <NEWLEN
            SUBD <TMP2
            STD  <DELTA
            ADDD <LEND
            CMPD #LBUF+LBUFMAX
            BHS  SPL_FULL
            LDD  <LEND                 ; the rest of the line (and its NUL) moves
            SUBD <INVZ
            ADDD #1
            TFR  D,W
            LDD  <DELTA
            BEQ  SPL_COPY
            BMI  SPL_DOWN
            LDX  <LEND
            LEAY D,X
            TFM  X-,Y-
            BRA  SPL_MOVED
SPL_DOWN    LDX  <INVZ
            LDY  <INVQ
            LDD  <NEWLEN
            LEAY D,Y
            TFM  X+,Y+
SPL_MOVED   LDD  <LEND
            ADDD <DELTA
            STD  <LEND
SPL_COPY    LDX  #RBUF
            LDY  <INVQ
            LDW  <NEWLEN
            TFM  X+,Y+
            ANDCC #$FE
            RTS
SPL_FULL    LDX  #M_EXPLONG
            JSR  ERROR
            LDX  <INVQ
            CLR  ,X
            STX  <LEND
            ORCC #1
            RTS
;------------------------------------------------------------------------------
    INCLUDE pa_util.asm
    INCLUDE pa_heap.asm
    INCLUDE pa_strm.asm
;------------------------------------------------------------------------------
M_USAGE     FCC  "Usage: CPP [-o out] [-I dir] [-D name[=value]] [-U name] file"
            FCB  CR,LF,0
M_ERRORS    FCB  ' '
            FCC  "error(s)"
            FCB  CR,LF,0
M_NOMEM     FCN  "Out of memory"
M_WRITEERR  FCN  "Cannot write the output (disk full?)"
M_NOSRC     FCN  "Cannot open "
M_NOOUT     FCN  "Cannot create "
M_ERRPFX    FCN  "error: "
M_WARNPFX   FCN  "warning: "
M_CMDLINE   FCN  "<command line>: "
M_QUOTE1    FCB  ' ',$27,0
M_DEEP      FCN  "#include nested too deeply"
M_BADDIR    FCN  "invalid preprocessing directive"
M_NOMACNAME FCN  "macro name missing"
M_BADPARAMS FCN  "invalid macro parameter list"
M_HASHPARAM FCC  "'#' is not followed by a macro parameter"
            FCB  0
M_PASTEEND  FCC  "'##' cannot be at either end of a macro"
            FCB  0
M_BODYLONG  FCN  "macro too long"
M_UNTERMARGS FCN "unterminated arguments to macro"
M_MANYARGS  FCN  "too many arguments to macro"
M_ARGCOUNT  FCN  "wrong number of arguments to macro"
M_EXPLONG   FCN  "line too long after macro expansion"
M_DEEPMAC   FCN  "macros nested too deeply"
M_LONGLINE  FCN  "line too long"
M_UNTERMCMT FCN  "unterminated comment"
M_UNTERMIF  FCN  "unterminated #if"
M_NOIF      FCN  "#elif, #else or #endif without #if"
M_AFTERELSE FCN  "#elif or #else after #else"
M_CONDDEEP  FCN  "#if nested too deeply"
M_IFNONE    FCN  "#if with no expression"
M_IFBAD     FCN  "invalid #if expression"
M_IFGARB    FCN  "missing operator in #if"
M_IFPAREN   FCC  "missing ')' in #if"
            FCB  0
M_IFCOLON   FCC  "missing ':' in #if"
            FCB  0
M_DIV0      FCN  "division by zero in #if"
M_DEFBAD    FCN  "defined needs a macro name"
M_INCBAD    FCC  "#include expects "
            FCB  '"'
            FCC  "FILE"
            FCB  '"'
            FCN  " or <FILE>"
M_NOINC     FCN  "cannot find include file"
M_LINEBAD   FCN  "invalid #line"
S_LINE      FCN  "#line "
S_DEFINED   FCN  "defined"
S_VAARGS    FCN  "__VA_ARGS__"
S_INCDIR    FCN  "/INCLUDE"
EXT_I       FCN  ".I"
PD_LINE     FCN  "__LINE__"
PD_FILE     FCN  "__FILE__"
PD_PUG      FCN  "__PUGPUTER__ 1"
PD_6309     FCN  "__6309__ 1"
;------------------------------------------------------------------------------
PA_END      equ  *
;------------------------------------------------------------------------------
; Variables and buffers after the program (none of this is in the file).
;------------------------------------------------------------------------------
VARS        equ  *
VP          SET  VARS
            VAR  LBUF,LBUFMAX+4        ; the line
            VAR  RBUF,RBUFMAX+4        ; a replacement being built
            VAR  BODYBUF,BODYMAX+2     ; a body being defined
            VAR  PARBUF,PARBUFSZ       ; its parameters' names
            VAR  NAMEBUF,NAMEMAX+2
            VAR  DEFNAME,NAMEMAX+2
            VAR  INCNAME,PATHMAX+2
            VAR  SRCNAME,PATHMAX+1
            VAR  OUTNAME,PATHMAX+1
            VAR  PATHBUF,PATHMAX+NAMEMAX+2
            VAR  INCDIRS,MAXINCDIR*(PATHMAX+1)
            VAR  DEFS,DEFSSZ           ; -D and -U
            VAR  HASHTAB,NHASH*3
            VAR  PAGES,MAXPAGES
            VAR  INSTACK,MAXDEPTH*INREC
            VAR  INBUFS,MAXDEPTH*256
            VAR  OUTSTRM,4+256
            VAR  ACTSTK,MAXACT*3
            VAR  CONDSTK,MAXCOND
ARR_BEG     equ  VP                ; a call's arguments: as written,
            VAR  ARGST,(MAXPARAMS+1)*2
            VAR  ARGEN,(MAXPARAMS+1)*2
            VAR  EXPST,(MAXPARAMS+1)*2 ; and expanded (0: not)
            VAR  EXPEN,(MAXPARAMS+1)*2
ARR_END     equ  VP
            VAR  NUMBUF,16
VARSEND     equ  VP
;------------------------------------------------------------------------------
; End of cpp.asm
;------------------------------------------------------------------------------
