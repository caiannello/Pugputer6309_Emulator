;------------------------------------------------------------------------------
; PROJECT: Pugputer 6309 C library
;    FILE: spawn.asm -- int spawn(const char *path, const char *tail): runs a
;          program as a child (B_EXEC, EXEC_CHILD) -> its exit code (0..255),
;          or -1 if it couldn't be started. The caller's memory is as it was
;          when the child ends; the child's open files are closed.
;------------------------------------------------------------------------------
            INCLUDE defines.d
            EXPORT _spawn
            SECTION code
_spawn      PSHS Y,U
            LDX  6,S
            LDY  8,S
            LDE  #EXEC_CHILD
            LDA  #B_EXEC
            SWI2
            BCS  SP_FAIL
            CLRA
            PULS Y,U,PC
SP_FAIL     LDD  #-1
            PULS Y,U,PC
            ENDSECT
