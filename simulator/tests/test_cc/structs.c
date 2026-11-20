#include <stdio.h>

enum color { RED, GREEN = 5, BLUE };
struct pt { int x; int y; };
struct rect { struct pt a, b; char name[6]; };
union u { long l; int i[2]; char c[4]; };

struct pt mid(struct pt p, struct pt q)
{
    struct pt r;
    r.x = (p.x + q.x) / 2;
    r.y = (p.y + q.y) / 2;
    return r;
}

long fact(int n) { return n <= 1 ? 1L : n * fact(n - 1); }

struct rect g = { { 1, 2 }, 3, 4, "box" };
long big = 100000;

int main(void)
{
    struct pt p, q, *pp;
    struct rect r;
    union u v;
    long a, b;
    int i;
    enum color c = BLUE;

    printf("enum %d %d %d %d\n", RED, GREEN, BLUE, c);
    p.x = 10; p.y = 20;
    q = p;
    q.x += 5;
    pp = &q;
    pp->y = pp->y * 2;
    printf("pt %d %d %d %d\n", p.x, p.y, q.x, pp->y);
    r.a = p;
    r.b = mid(p, q);
    printf("mid %d %d\n", r.b.x, r.b.y);
    printf("g %d %d %d %d %s %d\n", g.a.x, g.a.y, g.b.x, g.b.y, g.name, (int)sizeof(struct rect));
    v.l = 0x12345678L;
    printf("union %x %x %x\n", v.i[0], v.i[1], v.c[3]);
    a = 70000;
    b = a * 3 + big;
    printf("long %ld %ld\n", a, b);
    printf("div %ld %ld %ld\n", b / 7, b % 7, -b / 7);
    printf("shift %lx %lx %ld\n", a << 4, b >> 3, -a >> 2);
    printf("cmp %d %d %d %d\n", a < b, a > b, a == 70000, b != 0);
    for (i = 1; i <= 12; i += 11)
        printf("fact %d = %ld\n", i, fact(i));
    a = -5;
    a++;
    b = a--;
    printf("incdec %ld %ld\n", a, b);
    i = (int)(b * 1000);
    printf("cast %d %lu\n", i, (unsigned long)40000u);
    return 0;
}
