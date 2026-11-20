/* float.h -- CC (the Pugputer's C compiler): float, double and long double
   are all IEEE 754's single precision, rounded to the nearest. There are no
   denormals: a result smaller than FLT_MIN is a zero. */
#ifndef _FLOAT_H
#define _FLOAT_H

#define FLT_RADIX 2
#define FLT_ROUNDS 1
#define FLT_EVAL_METHOD 0

#define FLT_MANT_DIG 24
#define FLT_DIG 6
#define FLT_DECIMAL_DIG 9
#define FLT_MIN_EXP (-125)
#define FLT_MIN_10_EXP (-37)
#define FLT_MAX_EXP 128
#define FLT_MAX_10_EXP 38
#define FLT_MAX 3.40282347e38F
#define FLT_MIN 1.17549435e-38F
#define FLT_EPSILON 1.19209290e-7F

#define DBL_MANT_DIG FLT_MANT_DIG
#define DBL_DIG FLT_DIG
#define DBL_DECIMAL_DIG FLT_DECIMAL_DIG
#define DBL_MIN_EXP FLT_MIN_EXP
#define DBL_MIN_10_EXP FLT_MIN_10_EXP
#define DBL_MAX_EXP FLT_MAX_EXP
#define DBL_MAX_10_EXP FLT_MAX_10_EXP
#define DBL_MAX FLT_MAX
#define DBL_MIN FLT_MIN
#define DBL_EPSILON FLT_EPSILON

#define LDBL_MANT_DIG FLT_MANT_DIG
#define LDBL_DIG FLT_DIG
#define LDBL_MIN_EXP FLT_MIN_EXP
#define LDBL_MIN_10_EXP FLT_MIN_10_EXP
#define LDBL_MAX_EXP FLT_MAX_EXP
#define LDBL_MAX_10_EXP FLT_MAX_10_EXP
#define LDBL_MAX FLT_MAX
#define LDBL_MIN FLT_MIN
#define LDBL_EPSILON FLT_EPSILON

#define DECIMAL_DIG FLT_DECIMAL_DIG

#endif
