#include <stdio.h>
#include <string.h>

int g = 5;
int garr[4] = {10, 20, 30};
char msg[] = "hello";
char *pmsg = "world";
unsigned u = 40000;
static int counter;
int squares[5];

int fact(int n) { return n <= 1 ? 1 : n * fact(n - 1); }

int sum(int *p, int n)
{
    int s = 0;
    while (n-- > 0)
        s += *p++;
    return s;
}

void fill(char *buf, char c, int n)
{
    int i;
    for (i = 0; i < n; i++)
        buf[i] = c;
    buf[n] = 0;
}

int classify(int c)
{
    switch (c) {
    case 'a': case 'e': case 'i': case 'o': case 'u':
        return 1;
    case ' ':
        return 2;
    default:
        if (c >= '0' && c <= '9')
            return 3;
    }
    return 0;
}

int next(void) { static int n = 100; return n++; }

int main(void)
{
    int i, j, *p;
    char buf[12];
    char c = -3;
    unsigned char uc = 250;

    printf("1: %d %d %d\n", g, garr[1], garr[3]);
    printf("2: %s %s %c\n", msg, pmsg, msg[1]);
    printf("3: %d %d\n", fact(7), sum(garr, 4));
    printf("4: %u %u %d\n", u, u / 3, -17 / 5);
    printf("5: %d %d %d %d\n", 17 % 5, -17 % 5, 7 << 3, -64 >> 2);
    printf("6: %u %d\n", u >> 4, (int)(u % 7));
    i = 3; j = 4;
    printf("7: %d %d %d %d\n", i * j, i - j, i & j | 8, i ^ j);
    printf("8: %d %d %d\n", i < j, i == j, !i);
    printf("9: %d %d\n", c, uc);
    c += 10;
    uc += 10;
    printf("10: %d %d\n", c, uc);
    fill(buf, 'x', 5);
    printf("11: %s %d\n", buf, strlen(buf));
    for (i = 0; i < 5; i++)
        squares[i] = i * i;
    p = squares;
    printf("12: %d %d %d\n", p[4], *(p + 2), p[4] - p[3]);
    p = &squares[1];
    printf("13: %d %d\n", *p, (int)(p - squares));
    j = 0;
    for (i = 0; i < 20; i++) {
        if (i == 3)
            continue;
        if (i == 8)
            break;
        j += i;
    }
    printf("14: %d\n", j);
    i = 0;
    do { i += 7; } while (i < 30);
    printf("15: %d\n", i);
    printf("16: %d %d %d %d\n", classify('e'), classify(' '), classify('7'), classify('z'));
    printf("17: %d %d %d\n", next(), next(), counter);
    i = 10;
    j = i++ + ++i;
    printf("18: %d %d\n", i, j);
    i = 5;
    i *= 3; i -= 2; i <<= 1; i /= 3; i %= 5;
    printf("19: %d\n", i);
    printf("20: %d %d\n", sizeof(int), sizeof buf);
    i = 0;
    if (i || fact(3) == 6) printf("21: or\n");
    if (i && fact(100)) printf("never\n"); else printf("22: and\n");
    goto skip;
    printf("never\n");
skip:
    printf("23: %s\n", strcmp("abc", "abd") < 0 ? "less" : "more");
    return 0;
}
