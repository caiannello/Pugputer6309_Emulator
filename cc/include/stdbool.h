/* stdbool.h -- CC (the Pugputer's C compiler): bool is CC1's _Bool, a byte
   that a value is made 0 or 1 as it's stored (so (bool)0.5 is 1, and
   (bool)256 is 1 too). */
#ifndef _STDBOOL_H
#define _STDBOOL_H

#define bool _Bool
#define true 1
#define false 0
#define __bool_true_false_are_defined 1

#endif
