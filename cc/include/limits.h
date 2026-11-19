/* limits.h -- CC (the Pugputer's C compiler): char is signed, int 16 bits. */
#ifndef _LIMITS_H
#define _LIMITS_H

#define CHAR_BIT 8
#define SCHAR_MIN (-128)
#define SCHAR_MAX 127
#define UCHAR_MAX 255
#define CHAR_MIN SCHAR_MIN
#define CHAR_MAX SCHAR_MAX
#define SHRT_MIN (-32767 - 1)
#define SHRT_MAX 32767
#define USHRT_MAX 65535U
#define INT_MIN (-32767 - 1)
#define INT_MAX 32767
#define UINT_MAX 65535U

#endif
