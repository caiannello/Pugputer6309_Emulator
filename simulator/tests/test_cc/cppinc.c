#include "cppa.h"
int main_after_a;
#include <cppb.h>
int x = A_VAL + B_VAL;
#if (1 << 20) == 0x100000 && -1 < 0 && (7 / 2 == 3) && (7 % 3 == 1) && ~0 == -1
int arith_ok;
#endif
#if 'A' == 65 && '\n' == 10 && '\x41' == 65 && '\101' == 65
int chars_ok;
#endif
#if 0
#error not this
' unbalanced quote in skipped text
#else
int else_ok;
#endif
#if defined FROMCMD && FROMCMD == 7 && !defined(__6309__) == 0
int cmd_ok;
#endif
#ifdef __PUGPUTER__
int pug_ok;
#endif
#if 1 ? 2 : 3 == 2
int tern_ok;
#endif
#pragma something here
#line 100 "renamed.c"
int line = __LINE__; char *f = __FILE__;
