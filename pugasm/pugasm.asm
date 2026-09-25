;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 assembler
;    FILE: pugasm.asm
;
; PUGASM.COM: a 6809/6309 assembler for the Pugputer, modelled on lwasm (lwtools
; 4.20) and producing the same code for the same source: the same mnemonics
; (the table is generated from lwasm's), expression syntax, directives, forward-
; reference sizing, listing and symbol table.
;
;   PUGASM [options] file
;     -f FMT, --format=FMT   raw (the default), srec, com (raw with a Pugputer
;                            program header: load = the first address, entry =
;                            END's operand or the first address), obj
;     -o FILE, --output=FILE the output (default: the source's name with .BIN,
;                            .S19, .COM or .O)
;     -l[FILE], --list[=FILE]  a listing (default: the source's name with .LST)
;     -s, --symbols          the symbol table at the end of the listing
;     -I DIR, --includedir=DIR  where INCLUDE also looks (up to 4)
;     -3, --6309 (the default)  -9, --6809
;
; How it works: two passes over the source, read from the disk each time (with
; INCLUDE files and macro expansions). Pass 1 decides every line's size and
; defines the symbols; pass 2 does it all again and writes the output and the
; listing. lwasm (with its default pragma "forwardrefmax") sizes an instruction
; from what is known when it reaches the line, so a symbol defined further down
; gets the largest form; pass 2 reproduces that by treating any symbol defined at
; or after the current line as unknown for sizing (SIZE mode), then evaluates the
; operand again with everything known for the bytes (VALUE mode).
;
; Memory: the direct page $3400 holds the busy variables, the program runs from
; $3500, then its buffers, the stack below $C000; the symbols, macros and stored
; expressions live in RAM pages from B_PAGE_ALLOC, mapped one at a time into bank
; 3 ($C000-$EFFF: 12KB of each page is used).
;------------------------------------------------------------------------------
    INCLUDE defines.d
;------------------------------------------------------------------------------
DPAGE       equ  $3400             ; the direct page (not part of the file)
PA_BASE     equ  $3500
WINDOW      equ  $C000             ; bank 3: where heap pages are mapped
WINEND      equ  $F000
STACKTOP    equ  $C000
LINEMAX     equ  255               ; longest source line kept (the rest is dropped)
NAMEMAX     equ  63                ; longest symbol name
PATHMAX     equ  79
MAXINCDIR   equ  4
MAXDEPTH    equ  8                 ; nested INCLUDEs and macro expansions
MAXPAGES    equ  48
NHASH       equ  256               ; symbol hash buckets
; Output formats
FMT_RAW     equ  0
FMT_SREC    equ  1
FMT_COM     equ  2
FMT_OBJ     equ  3
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
DP_VP       SET  DPAGE
            DVAR PASS,1                ; 1 or 2
            DVAR LSEQ,2                ; the line's sequence number in the pass
            DVAR CUTSEQ,2              ; symbols defined at/after this are unknown
            DVAR PC,2                  ; the address of the current line
            DVAR PCX,1                 ; nonzero: PC isn't exact on pass 1 (see
            DVAR PCADJ,2               ; pa_dir.asm, RMB) and by how much
            DVAR LADDR,2               ; the address the current line started at
            DVAR LLEN,2                ; the line's length (bytes of address space)
            DVAR DPVAL,1               ; SETDP
            DVAR CONTEXT,2             ; local-symbol context
            DVAR NEXTCTX,2
            DVAR CPU,1                 ; 0 = 6309, 1 = 6809
            DVAR FORMAT,1
            DVAR ERRCNT,2              ; errors in pass 2
            DVAR LINEERR,1             ; this line has had an error
            DVAR SKIPCOND,1            ; skipping: IF nesting level + 1 (0 = not)
            DVAR CONDLVL,1             ; IF nesting while assembling
            DVAR INMACRO,1             ; defining a macro
            DVAR INSTRUCT,1            ; defining a struct
            DVAR ENDSEEN,1
            DVAR LISTON,1              ; a listing is being written
            DVAR SYMLIST,1             ; -s
            DVAR OUTON,1               ; output file open (pass 2)
            DVAR MAPPED,1              ; the heap page mapped in bank 3 (0 = none)
            DVAR NPAGES,1
            DVAR HEAPPG,1              ; allocating in this page (index)
            DVAR HEAPPTR,2             ; ... here
            DVAR TMP,2
            DVAR TMP2,2
            DVAR TMP3,2
            DVAR TMPB,1
            DVAR OPCLASS,1             ; the line's operation
            DVAR OPFLAGS,1
            DVAR OPENTRY,2             ; its table entry (opcodes at +2 after flags)
            DVAR LABEL,1               ; the line has a label (in LABELNAME)
            DVAR SYMSET,1              ; the handler defined the label itself
            DVAR SETDATA,1
            DVAR OPERP,2               ; the operand
            DVAR EXP,2                 ; expression parser input pointer
            DVAR EVMODE,1              ; 0 = SIZE (cutoff), 1 = VALUE
            DVAR EVFLAGS,1             ; result flags (EF_*)
            DVAR EVLIT,1               ; the expression was one numeric literal
            DVAR EVAL,4                ; result value
            DVAR EVADJ,2               ; inexact adjustment (see PCX)
            DVAR NBYTES,2              ; bytes emitted by this line (listing)
            DVAR LSHOW,1               ; listing prefix kind (LS_*)
            DVAR LSHOWV,2              ; value for it
            DVAR EXECADDR,2
            DVAR HAVEEXEC,1
            DVAR FIRSTOUT,1            ; no output byte yet
            DVAR FIRSTADDR,2           ; the first output byte's address (pass 1)
            DVAR RAWZERO,2             ; raw: pending zeros before the first byte
            DVAR ISP,1                 ; input stack depth
            DVAR INP,2                 ; the current input record
            DVAR NINCDIR,1
            DVAR MACDEF,3              ; macro being defined: its record
            DVAR MACLAST,3             ; its last line record
            DVAR STRUCTP,3             ; struct being defined
            DVAR NOMACRO,1
            DVAR STOPERR,1
            DVAR IDXPB,1               ; indexed: post byte being built
            DVAR IDXLEN,1              ; indexed: offset bytes (0, 1, 2) / 5-bit
            DVAR IDXMODE,1
            DVAR GENMODE,1             ; direct 0 / indexed 1 / extended 2 / imm 3
            DVAR OPSIZE,1              ; immediate size (1, 2, 4)
            DVAR RLEN,1                ; instruction's opcode length
            DVAR MA,4                  ; 32-bit arithmetic (pa_util.asm)
            DVAR MB,4
            DVAR MQ,4
            DVAR MSIGN,1
            DVAR SYMP,3                ; a symbol record (far pointer)
            DVAR FARP,3                ; a far pointer being worked on
            DVAR CURSPEC,2             ; the line's file (or macro) name, for the listing
            DVAR CURLNO,2              ; and its line number there
            DVAR TMPB2,1
            DVAR SECTNUM,1             ; the current section (obj; 0 = none)
            DVAR NSYMS,2               ; symbol records
            DVAR EXPSTART,2            ; where the expression being parsed began
            DVAR STARPC,2              ; the value of "*"
            DVAR EVDEPTH,1             ; symbols-with-expressions being evaluated
            DVAR NUMV,16               ; number parsing: decimal, binary, hex, octal
            DVAR NUMTYPE,1
            DVAR NUMBIN,1
            DVAR LSOFFON,1             ; listing: a struct offset to show
            DVAR LSOFF,2
            DVAR LSHOWQ,1              ; listing: the value isn't known ("????")
            DVAR LREPB,1               ; listing: the byte repeated past LBYTES
            DVAR MACNOEXP,1            ; MACRO: "noexpand" was given
            DVAR NXSTART,1             ; a noexpand macro was just called
            DVAR NXLEVEL,1             ; its input level (0: none being held)
            DVAR NXCNT,2               ; the bytes its lines made
            DVAR NXADDR,2              ; the calling line: its address,
            DVAR NXSPEC,2              ; file, line number, label
            DVAR NXLNO,2
            DVAR NXLAB,1
            DVAR NXSYMSET,1
            DVAR EXPW8,1               ; expressions: ~ is 8 bits wide
            DVAR HASOP,1
            DVAR WASMACRO,1
            DVAR OPTOK,2               ; the operation as written
            DVAR OPTOKEND,2
            DVAR OPSP,2                ; its opcodes
            DVAR LPCX,1                ; PCX and PCADJ at the start of the line
            DVAR LPCADJ,2
            DVAR SKIPMACRO,1           ; a MACRO inside skipped lines
            DVAR SKIPCOUNT,1           ; IF nesting while skipping
            DVAR MACROS,3              ; the macros (a list, newest first)
            DVAR STRUCTS,3             ; the structs
            DVAR FLDLAST,3             ; the last field of the struct being defined
            DVAR FLDP,3
            DVAR STRSIZE,2             ; the size of the struct so far
            DVAR SAVEDPC,2
            DVAR INSTDEPTH,1
            DVAR GENEXTRA,1            ; AIM etc.: a byte after the opcode
            DVAR GENXB,1
            DVAR GASTART,2
            DVAR GAEXPR,2
            DVAR IDXOP,2               ; indexed: the opcode
            DVAR IDXELEN,1             ; bytes between it and the post byte
            DVAR IDXLINT,1             ; offset bytes (-1: to decide, 3: 5-bit)
            DVAR IDXEXPR,2             ; the offset expression
            DVAR IDXPCR,1
            DVAR IDXINDIR,1
            DVAR IDXF0,1
            DVAR IDXRN,1
            DVAR STARTED,1             ; the output file has its first byte
            DVAR SRECLEN,1             ; S-records: bytes in the current one
            DVAR SRECADDR,2            ; its address
            DVAR SRECLAST,1            ; a byte has been written (SRLASTAD valid)
            DVAR SRLASTAD,2
            DVAR SRECCNT,2             ; S1 records written
            DVAR SRECSUM,1
            DVAR S0DONE,1
            DVAR ARRPG,1               ; the symbol listing's array
            DVAR ARRADDR,2
            DVAR ARRPTR,2
            DVAR HBKT,2
            DVAR HSI,2                 ; heap sort
            DVAR HSN,2
            DVAR HSJ,2
            DVAR HSK,2
            DVAR FARP2,3
            DVAR KEY2CTX,2
            DVAR KEY2SEQ,2
            DVAR SFCTX,2               ; SYMFIND: the context to match
            DVAR INSTBASE,2            ; struct instances: the base address
            DVAR BBIT1,1               ; BAND etc.: the bit numbers
            DVAR BBIT2,1
DP_END      equ  DP_VP
;------------------------------------------------------------------------------
; Evaluation result flags (EVFLAGS)
EF_KNOWN    equ  $01               ; every symbol known (defined before the cutoff)
EF_INEXACT  equ  $02               ; depends on an address that pass 1 can't fix
EF_NORANGE  equ  $04               ; ... through something other than + and -
EF_UNDEF    equ  $08               ; an undefined symbol (VALUE mode)
EF_COMPLEX  equ  $10               ; (obj) relocatable in a way that can't be kept
; Listing prefix kinds (LSHOW)
LS_NONE     equ  0                 ; 22 blanks
LS_ADDR     equ  1                 ; the address and the bytes
LS_VALUE    equ  2                 ; "     VVVV             " (EQU, SET, ...)
LS_BYTE     equ  3                 ; "     VV               " (SETDP)
LS_STRUCT   equ  4                 ; "VVVVs                 "
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
            LDY  #VARS
            LDW  #VARSEND-VARS
            TFM  X,Y+
            JSR  CMDLINE               ; options, file names
            JSR  HEAPINIT
            LDA  #1
            STA  <PASS
            JSR  DOPASS
            TST  <STOPERR
            BNE  FINISH
            JSR  OPENOUT               ; output and listing files
            LDA  #2
            STA  <PASS
            JSR  DOPASS
            JSR  CLOSEOUT
            TST  <LISTON
            BEQ  FINISH
            TST  <SYMLIST
            BEQ  FIN_LIST
            JSR  LISTSYMS
FIN_LIST    JSR  CLOSELIST
FINISH      JSR  HEAPDONE
            LDD  <ERRCNT
            BEQ  FIN_OK
            JSR  PRINTDEC
            LDX  #M_ERRORS
            JSR  PRINTS
FIN_OK      LDA  #B_EXIT
            SWI2
; A fatal error: X = the message. Tidies up and leaves.
FATAL       JSR  PRINTS
            JSR  PRINTNL
            JSR  CLOSEALL
            JSR  HEAPDONE
            LDA  #B_EXIT
            SWI2
;------------------------------------------------------------------------------
; One pass over the source.
;------------------------------------------------------------------------------
DOPASS      CLRD
            STD  <LSEQ
            STD  <PC
            STD  <PCADJ
            STD  <CONTEXT
            STD  <NEXTCTX
            CLR  <PCX
            CLR  <DPVAL
            CLR  <SKIPCOND
            CLR  <CONDLVL
            CLR  <INMACRO
            CLR  <NXLEVEL
            CLR  <NXSTART
            CLR  <INSTRUCT
            CLR  <ENDSEEN
            LDA  #1
            STA  <FIRSTOUT
            JSR  PASSINIT              ; per-format / section state
            LDX  #SRCNAME
            JSR  OPENTOP
DP_LINE     JSR  READLINE              ; -> LINEBUF, or carry at the end
            BCS  DP_DONE
            JSR  DOLINE
            TST  <ENDSEEN
            BNE  DP_FINI
            TST  <STOPERR
            BEQ  DP_LINE
DP_FINI     JSR  CLOSEINPUTS
DP_DONE     RTS
;------------------------------------------------------------------------------
    INCLUDE pa_util.asm
    INCLUDE pa_heap.asm
    INCLUDE pa_io.asm
    INCLUDE pa_sym.asm
    INCLUDE pa_expr.asm
    INCLUDE pa_line.asm
    INCLUDE pa_insn.asm
    INCLUDE pa_dir.asm
    INCLUDE pa_out.asm
    INCLUDE pa_itab.asm
;------------------------------------------------------------------------------
PA_END      equ  *
;------------------------------------------------------------------------------
; Variables and buffers after the program (none of this is in the file).
;------------------------------------------------------------------------------
VARS        equ  *
VP          SET  VARS
            VAR  LINEBUF,LINEMAX+2     ; the current source line
            VAR  WORKBUF,LINEMAX+2     ; a macro line being built, etc.
            VAR  LABELNAME,NAMEMAX+2
            VAR  OPNAME,16
            VAR  NAMEBUF,NAMEMAX+2     ; a symbol name being looked up
            VAR  SRCNAME,PATHMAX+1
            VAR  OUTNAME,PATHMAX+1
            VAR  LSTNAME,PATHMAX+1
            VAR  PATHBUF,PATHMAX+NAMEMAX+2
            VAR  FNAMEBUF,PATHMAX+2
            VAR  KEY2,NAMEMAX+2        ; the symbol listing's sort
            VAR  INCDIRS,MAXINCDIR*(PATHMAX+1)
            VAR  HASHTAB,NHASH*3
            VAR  PAGES,MAXPAGES
            VAR  INSTACK,MAXDEPTH*160  ; input records (INREC each, see pa_io.asm)
            VAR  INBUFS,MAXDEPTH*256   ; file buffers, one a level
            VAR  MACARGS,MAXDEPTH*128  ; macro arguments, one area a level
            VAR  OUTSTRM,4+256         ; the output file (pa_io.asm streams)
            VAR  LSTSTRM,4+256         ; the listing file
            VAR  LBYTES,256            ; the bytes of the current line
            VAR  NXLINE,256            ; a noexpand macro's calling line
            VAR  NXBYTES,256           ; and the bytes it made
            VAR  NUMBUF,16
            VAR  SRECBUF,40
            VAR  EVSTACK,4
VARSEND     equ  VP
;------------------------------------------------------------------------------
; End of pugasm.asm
;------------------------------------------------------------------------------
