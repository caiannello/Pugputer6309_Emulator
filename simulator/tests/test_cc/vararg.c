/* Variadic functions, with <stdarg.h>; argc and argv; a line typed. */
#include <stdio.h>
#include <stdarg.h>
#include <ctype.h>

int sum(int n, ...)
{
    va_list ap;
    int s = 0;
    va_start(ap, n);
    while (n-- > 0)
        s += va_arg(ap, int);
    va_end(ap);
    return s;
}

void say(char *tag, char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    printf("[%s] ", tag);
    vprintf(fmt, ap);
    va_end(ap);
}

int main(int argc, char **argv)
{
    char line[40];
    char *p;
    int i;

    printf("%d %d %d\n", sum(0), sum(3, 1, 2, 3), sum(5, 10, 20, 30, 40, 50));
    say("note", "%s is %d\n", "the answer", 42);
    printf("argc %d:", argc);
    for (i = 1; i < argc; i++)
        printf(" <%s>", argv[i]);
    printf("\n");
    if (fgets(line, sizeof line, stdin)) {
        for (p = line; *p; p++)
            *p = toupper(*p);
        fputs(line, stdout);
    }
    return 0;
}
