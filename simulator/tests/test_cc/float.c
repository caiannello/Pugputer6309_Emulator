/* float and double (the same: IEEE single, in Q): arithmetic, comparisons,
   conversions both ways, constants folded at compile time, op= and ++,
   arguments and results, arrays and struct members, printf's %e %f %g and
   its flags, atof and strtod, and _Bool. */
#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>

struct pt { int id; float x, y; };

static float g = 1.5f;
static double third = 1.0 / 3.0;        /* folded */
static float big = 1e30, tiny = -2.5e-30;
static int fromf = 2.75;                /* 2 */
static float fromi = 7, fromu = 40000u, froml = -100000L;
static float tab[] = { 0.5, -1.25, 3, 1e-3 };
static bool flag = 42;                  /* 1 */

float half(float x) { return x / 2; }
double twice(double x) { return x * 2.0; }
float sum(float *a, int n)
{
    float s = 0;
    int i;
    for (i = 0; i < n; i++)
        s += a[i];
    return s;
}
struct pt mid(struct pt a, struct pt b)
{
    struct pt m;
    m.id = a.id + b.id;
    m.x = (a.x + b.x) / 2;
    m.y = (a.y + b.y) / 2;
    return m;
}
int sign(float x) { return x < 0 ? -1 : x > 0 ? 1 : 0; }

int main(void)
{
    float a = 3.0, b = 4.0, c;
    double d;
    int i;
    long l;
    unsigned u;
    char ch;
    struct pt p, q;
    bool t;
    char *end;

    c = a * a + b * b;
    printf("%f %f %f\n", a, b, c);
    printf("%.2f %.0f %.0f %.3f %.1f\n", c / 7, 2.5, 3.5, -0.0005, 0.05);
    printf("%e %E %.3e %e\n", c, 1234.5678, -0.000123456, 0.0);
    printf("%g %g %g %g %g %G\n", 100000.0, 1000000.0, 0.0001, 0.00001, 3.14159265, 1e-10);
    printf("%g %g %#g %g %.3g\n", 0.0, 1.5, 1.5, 100.0, 2.71828);
    printf("[%8.3f] [%-8.2f] [%+.1f] [% .1f] [%08.2f] [%+08.2f]\n", 3.14159, 2.5, 1.0, 1.0, -3.5, 3.5);
    printf("%f %f %f\n", big / big, 1e38 * 10, -1e38 * 1e38);
    printf("%.1f %.1f %.1f\n", 1.0 / 0.0, -1.0 / 0.0, 0.0 / 0.0);

    printf("statics %g %.7f %g %g %d %g %g %g %d\n", g, third, big, tiny, fromf, fromi, fromu, froml, flag);
    printf("tab %g %g %g %g sum %g\n", tab[0], tab[1], tab[2], tab[3], sum(tab, 4));
    printf("calls %g %g %g %d %d %d\n", half(5), twice(1.25), half(twice(3)), sign(-2.5), sign(0), sign(1e-20));

    i = 7.99;
    l = -123456.7;
    u = 50000.5;
    ch = 65.9;
    printf("to int %d %ld %u %c %d %d\n", i, l, u, ch, (int)-2.5, (int)(c / 3));
    d = i;
    printf("from int %g %g %g %g\n", d, (float)l, (float)u, (double)ch);
    l = 1234567;
    printf("long %g %.1f %ld\n", (float)l, (float)l, (long)(float)l);
    l = 16777217;
    printf("rounded %.1f\n", (float)l);

    d = 1.0;
    for (i = 0; i < 10; i++)
        d = d * 2;
    printf("loop %g", d);
    d = 0;
    for (i = 0; i < 10; i++)
        d += 0.1;
    printf(" %.6f %d\n", d, d == 1.0);

    a = 10;
    a += 2.5;
    a -= 1;
    a *= 4;
    a /= 8;
    printf("op= %g", a);
    i = 10;
    i *= 1.5;
    printf(" %d", i);
    i /= 0.25;
    printf(" %d", i);
    l = 3;
    l += 0.75;
    printf(" %ld\n", l);
    a = 1.5;
    b = a++;
    c = ++a;
    printf("incdec %g %g %g", a, b, c);
    b = a--;
    c = --a;
    printf(" %g %g %g\n", a, b, c);

    printf("compare %d %d %d %d %d %d", a < b, a > b, a <= a, a >= b, a == a, a != b);
    printf(" %d %d %d", -0.0 == 0.0, 2 < 2.5, 3 > 2.5f);
    a = 0;
    if (a) printf(" bad");
    if (!a) printf(" not");
    a = -0.0;
    if (a) printf(" bad");
    a = 0.001;
    if (a && 1) printf(" and");
    if (0.0 || a) printf(" or");
    printf(" %d %d\n", !a, a ? 5 : 6);

    p.id = 1; p.x = 1.0; p.y = 2.0;
    q.id = 2; q.x = 4.0; q.y = -6.0;
    p = mid(p, q);
    printf("struct %d %g %g\n", p.id, p.x, p.y);

    printf("atof %g %g %g %g %g %g\n", atof("12.5"), atof("  -3e2"), atof(".5e-1"), atof("1e40"), atof("+inf"), atof("x"));
    d = strtod("6.25kg", &end);
    printf("strtod %g [%s]", d, end);
    d = strtod("nope", &end);
    printf(" %g [%s]", d, end);
    d = strtod("1e+", &end);
    printf(" %g [%s]\n", d, end);

    t = 0.5;
    printf("bool %d %d %d", t, (bool)0.0, (bool)3);
    t = 0;
    t = t + 7;
    printf(" %d %d\n", t, (int)sizeof(bool));
    printf("sizes %d %d %d\n", (int)sizeof(float), (int)sizeof(double), (int)sizeof(long double));
    return 0;
}
