/* stdio.h -- CC (the Pugputer's C compiler): LIBC.A's files and console. */
#ifndef _STDIO_H
#define _STDIO_H

#include <stddef.h>

/* A FILE is 4 bytes of libc's (cc/lib/libc.d), never looked into: a struct
   that isn't defined. The console's three are the first of libc's __iob (C's
   _iob). */
typedef struct _iobuf FILE;
extern char _iob[];
#define stdin  ((FILE *)&_iob[0])
#define stdout ((FILE *)&_iob[4])
#define stderr ((FILE *)&_iob[8])

#define EOF (-1)
#define SEEK_SET 0
#define SEEK_CUR 1
#define SEEK_END 2

int printf(const char *fmt, ...);
int fprintf(FILE *f, const char *fmt, ...);
int sprintf(char *buf, const char *fmt, ...);
int vprintf(const char *fmt, char *ap);
int vfprintf(FILE *f, const char *fmt, char *ap);
int vsprintf(char *buf, const char *fmt, char *ap);

int putchar(int c);
int getchar(void);
int puts(const char *s);
int fputs(const char *s, FILE *f);
char *fgets(char *buf, int n, FILE *f);
int fputc(int c, FILE *f);
int fgetc(FILE *f);
int putc(int c, FILE *f);
int getc(FILE *f);
int ungetc(int c, FILE *f);

FILE *fopen(const char *name, const char *mode);
int fclose(FILE *f);
size_t fread(void *p, size_t size, size_t n, FILE *f);
size_t fwrite(const void *p, size_t size, size_t n, FILE *f);
void rewind(FILE *f);
int fflush(FILE *f);
int feof(FILE *f);
int ferror(FILE *f);
void clearerr(FILE *f);
int remove(const char *name);
int rename(const char *oldname, const char *newname);
int fseek(FILE *f, long offset, int whence);
long ftell(FILE *f);

#endif
