#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

typedef unsigned char byte;
typedef int (*binop)(int, int);

char *names[] = { "zero", "one", "two", "three" };
int grid[3][4] = { {1, 2, 3, 4}, {5, 6, 7, 8}, {9, 10, 11, 12} };
byte table[] = { 1, 2, 250, 255 };
int *gp = &grid[1][2];

static int add(int a, int b) { return a + b; }
static int mul(int a, int b) { return a * b; }
int apply(binop f, int a, int b) { return f(a, b); }

void swap(int *a, int *b) { int t = *a; *a = *b; *b = t; }

void upcase(char *s)
{
    for (; *s; s++)
        *s = toupper(*s);
}

int count(char **list, int n, char c)
{
    int i, k = 0;
    char *p;
    for (i = 0; i < n; i++)
        for (p = list[i]; *p; p++)
            if (*p == c)
                k++;
    return k;
}

int main(void)
{
    int i, j, total;
    char word[16] = "pugputer";
    int nums[5] = { 3, 1, 4 };
    char **pp;
    byte b;
    unsigned x, y;
    binop ops[2];

    printf("1: %s %s %d\n", names[2], names[3], (int)sizeof(names));
    total = 0;
    for (i = 0; i < 3; i++)
        for (j = 0; j < 4; j++)
            total += grid[i][j];
    printf("2: %d %d %d\n", total, grid[2][1], *gp);
    printf("3: %d %d %d %d\n", table[2], table[3], (int)sizeof(table), table[0] + table[3]);
    printf("4: %d %d\n", apply(add, 3, 4), apply(mul, 3, 4));
    ops[0] = add;
    ops[1] = mul;
    printf("5: %d %d\n", ops[0](10, 5), (*ops[1])(10, 5));
    i = 1; j = 2;
    swap(&i, &j);
    printf("6: %d %d\n", i, j);
    upcase(word);
    printf("7: %s %d %c\n", word, (int)strlen(word), word[7]);
    printf("8: %d %d %d %d %d\n", nums[0], nums[2], nums[3], nums[4], (int)sizeof nums);
    pp = names;
    printf("9: %s %c %d\n", *(pp + 1), **pp, count(names, 4, 'e'));
    b = 200;
    b += 100;
    printf("10: %d\n", b);
    x = 65000; y = 3;
    printf("11: %d %d %d\n", x > y, (int)x > (int)y, x / y);
    {
        int i = 99;
        printf("12: %d\n", i);
    }
    printf("13: %d\n", i);
    i = (j = 5, j * 2);
    printf("14: %d %d\n", i, j);
    printf("15: %s\n", i > 5 ? "big" : "small");
    printf("16: %d %d %d\n", (char)300, (byte)-1, (int)'A');
    printf("17: %d %d\n", sizeof(char *), sizeof(grid[0]));
    i = 0x7fff;
    i++;
    printf("18: %d %u\n", i, i);
    printf("19: %d %d\n", abs(-42), atoi("1234") + 1);
    exit(3);
    printf("never\n");
    return 0;
}
