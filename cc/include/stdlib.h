/* stdlib.h -- CC (the Pugputer's C compiler) */
#ifndef _STDLIB_H
#define _STDLIB_H

#include <stddef.h>

#define EXIT_SUCCESS 0
#define EXIT_FAILURE 1
#define RAND_MAX 32767

void *malloc(size_t n);
void free(void *p);
void *calloc(size_t n, size_t size);
void *realloc(void *p, size_t n);
void *sbrk(int n);
int atoi(const char *s);
int abs(int n);
int rand(void);
void srand(unsigned seed);
void exit(int status);

#endif
