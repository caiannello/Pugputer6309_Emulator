/* Banked code: functions in overlays 1 and 2 (and far.c's, compiled with
   -b 3) calling each other, fixed code, and back; recursion in a bank; a
   pointer to a banked function; a long and a pointer as results. */
#include <stdio.h>
#include <string.h>

int f2(int x);
int pong(int n);
int far3(int x);

long fixed_twice(long x) { return x * 2; }

#pragma bank 1
static int helper1(int x) { return x + 1; }
int f1(int x) { return helper1(x) * 10; }
long g1(long l) { return fixed_twice(l) + f2(3); }
int fib(int n) { return n < 2 ? n : fib(n - 1) + fib(n - 2); }
int ping(int n) { return n == 0 ? 100 : pong(n - 1) + 1; }
char *greet(char *buf) { strcpy(buf, "hi from bank 1"); return buf; }

#pragma bank 2
int f2(int x) { return x * x; }
int callback(int (*fp)(int), int v) { return fp(v); }
int pong(int n) { return n == 0 ? 200 : ping(n - 1) + 2; }

#pragma bank 0
int main(void)
{
    char buf[20];
    int (*fp)(int) = f2;
    printf("%d %ld %d %d\n", f1(4), g1(100000L), f2(5), callback(f1, 7));
    printf("fib %d ping %d pong %d fp %d\n", fib(15), ping(7), pong(4), fp(9));
    printf("%s\n", greet(buf));
    printf("far3 %d\n", far3(14));
    return 0;
}
