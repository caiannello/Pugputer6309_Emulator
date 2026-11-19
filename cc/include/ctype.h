/* ctype.h -- CC (the Pugputer's C compiler) */
#ifndef _CTYPE_H
#define _CTYPE_H

int isalpha(int c);
int isdigit(int c);
int isalnum(int c);
int isxdigit(int c);
int isspace(int c);
int isupper(int c);
int islower(int c);
int ispunct(int c);
int iscntrl(int c);
int isgraph(int c);
int isprint(int c);
int isblank(int c);
int toupper(int c);
int tolower(int c);

#endif
