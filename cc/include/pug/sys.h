/* pug/sys.h -- CC (the Pugputer's C compiler): the Pugputer's DOS. */
#ifndef _PUG_SYS_H
#define _PUG_SYS_H

/* Runs the program at path (a .COM, found as written: no search path) with
   the command tail, as a child: when it ends, this program goes on, its
   memory as it was. -> the child's exit code (the low byte of its exit()'s
   status, 0..255), or -1 if it couldn't be started (not found, not a
   program, no memory for it, or children nested too deep). */
int spawn(const char *path, const char *tail);

#endif
