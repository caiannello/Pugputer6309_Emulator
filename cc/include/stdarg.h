/* stdarg.h -- CC (the Pugputer's C compiler). Arguments are on the stack
   in order, each a whole number of 16-bit words (a char's value in the second
   byte of its word), so a va_list is just a pointer to the next one. */
#ifndef _STDARG_H
#define _STDARG_H

typedef char *va_list;
#define va_start(ap, last) ((ap) = (char *)&(last) + sizeof(last))
#define va_arg(ap, type) (*(type *)(((ap) += sizeof(type)) - sizeof(type)))
#define va_end(ap) ((void)0)

#endif
