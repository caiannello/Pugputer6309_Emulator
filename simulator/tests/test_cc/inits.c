#include <stdio.h>
#include <string.h>

struct item { char name[8]; int qty; long price; };
struct item stock[] = { { "nut", 10, 25 }, "bolt", 4, 100000L, { "gear" } };
int grid[2][3] = { 1, 2, 3, { 4, 5 } };
union num { int i; char c[2]; } un = { 0x4142 };
struct { int a; struct { char b; int c; } in; } nest = { 1, 2, 3 };
int counter = 7;
static long total;

struct item *find(char *name)
{
    struct item *p;
    for (p = stock; p < stock + sizeof stock / sizeof stock[0]; p++)
        if (strcmp(p->name, name) == 0)
            return p;
    return 0;
}

long value(struct item it) { return it.qty * it.price; }

int lsw(long v)
{
    switch (v) {
    case 0: return 1;
    case 100000L: return 2;
    case -1: return 3;
    default: return 4;
    }
}

int twice(int x)
{
    asm {
        ldd   x
        lslb
        rola
        std   x
    }
    return x;
}

interrupt void isr(void) { counter++; }

int main(void)
{
    int loc[] = { 9, 8, 7, 6 };
    struct item one = { "pin", 3, 2 };
    struct item two = one;
    struct item *ip;
    long l = 1, m;
    int i, j;

    printf("stock %d %s %d %ld %s %d %ld\n", (int)(sizeof stock / sizeof stock[0]),
           stock[0].name, stock[0].qty, stock[1].price, stock[2].name, stock[2].qty, stock[2].price);
    for (i = 0; i < 2; i++)
        for (j = 0; j < 3; j++)
            printf("%d", grid[i][j]);
    printf(" un %x %c nest %d %d %d\n", un.i, un.c[1], nest.a, nest.in.b, nest.in.c);
    printf("loc %d %d %d\n", (int)sizeof loc, loc[0], loc[3]);
    two.qty = 5;
    printf("two %s %d %d\n", two.name, two.qty, one.qty);
    ip = find("bolt");
    printf("find %s %ld %ld\n", ip->name, value(*ip), value(stock[0]));
    for (i = 0; i < 3; i++)
        total += value(stock[i]);
    printf("total %ld\n", total);
    printf("lsw %d %d %d %d\n", lsw(0), lsw(100000L), lsw(-1), lsw(5));
    printf("twice %d\n", twice(21));
    {
        int counter = 99;
        {
            extern int counter;
            printf("extern %d\n", counter);
        }
        printf("local %d\n", counter);
    }
    for (i = 0; i < 20; i++)
        l *= 3;
    m = l;
    m /= 1000;
    m <<= 2;
    m |= 1;
    m -= 0x10000L;
    printf("ops %ld %ld %ld\n", l, m, l > m ? l - m : m - l);
    printf("ulong %lu %d\n", (unsigned long)l * 2, (unsigned long)l * 2 > 3000000000UL);
    return 0;
}
