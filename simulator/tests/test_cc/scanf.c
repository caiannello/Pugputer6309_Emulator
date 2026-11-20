/* scanf, sscanf and fscanf: integers in every base and size, characters,
   words, sets, %n, *, widths, literal characters and white space, floats,
   the return value (EOF at the end), and the character a conversion stops at
   left for what reads next. */
#include <stdio.h>

int main(void)
{
    int a, b, c, n;
    unsigned u;
    long l;
    char ch, cs[4], w[16], w2[16], w3[16];
    signed char hh;
    float f;
    double d;
    FILE *fp;
    int r;

    r = sscanf("  42 -17 +5", "%d %d %d", &a, &b, &c);
    printf("%d: %d %d %d\n", r, a, b, c);
    r = sscanf("0x1F 017 99 ff 0Xab", "%i %i %i %x %x", &a, &b, &c, &u, &n);
    printf("%d: %d %d %d %u %d\n", r, a, b, c, u, n);
    r = sscanf("777 1010 65535 -100000 300", "%o %d %u %ld %hhd", &a, &b, &u, &l, &hh);
    printf("%d: %d %d %u %ld %d\n", r, a, b, u, l, hh);
    r = sscanf("12345678", "%3d%2d%d", &a, &b, &c);
    printf("%d: %d %d %d\n", r, a, b, c);
    r = sscanf("x=10, y=20;", "x=%d, y=%d;%n", &a, &b, &n);
    printf("%d: %d %d n=%d\n", r, a, b, n);
    r = sscanf("abcd", "%c%3c", &ch, cs);
    cs[3] = 0;
    printf("%d: %c %s\n", r, ch, cs);
    r = sscanf("  hello   world!", "%s %5s%n", w, w2, &n);
    printf("%d: [%s] [%s] %d\n", r, w, w2, n);
    r = sscanf("key=value;rest", "%[a-z]=%[^;];%s", w, w2, w3);
    printf("%d: [%s] [%s] [%s]\n", r, w, w2, w3);
    r = sscanf("]x] 5", "%[]x]%d", w, &a);
    printf("%d: [%s] %d\n", r, w, a);
    r = sscanf("1 2 3", "%d %*d %d", &a, &b);
    printf("%d: %d %d\n", r, a, b);
    r = sscanf("3.25 -1e3 .5 7", "%f %lf %g %e", &f, &d, &f, &d);
    printf("%d: %g %g\n", r, f, d);
    r = sscanf("2.5e-2x", "%f%c", &f, &ch);
    printf("%d: %g %c\n", r, f, ch);
    r = sscanf("100%", "%d%%", &a);
    printf("%d: %d\n", r, a);
    a = 7;
    r = sscanf("abc", "%d", &a);
    printf("%d: %d\n", r, a);
    r = sscanf("", "%d", &a);
    printf("%d\n", r);
    r = sscanf("   ", "%s", w);
    printf("%d\n", r);
    r = sscanf("5 x", "%d %d", &a, &b);
    printf("%d: %d\n", r, a);

    fp = fopen("NUMS.TXT", "w");
    fprintf(fp, "10 20\n3.5 word\n");
    fclose(fp);
    fp = fopen("NUMS.TXT", "r");
    r = fscanf(fp, "%d %d", &a, &b);
    printf("file %d: %d %d", r, a, b);
    r = fscanf(fp, "%f %s", &f, w);
    printf(" %d: %g %s", r, f, w);
    r = fscanf(fp, "%d", &a);
    printf(" %d\n", r);
    fclose(fp);

    printf("? ");
    r = scanf("%d %s", &a, w);
    printf("%d: %d %s\n", r, a, w);
    ch = getchar();
    printf("next %d\n", ch);
    printf("? ");
    r = scanf("%f", &f);
    printf("%d: %g\n", r, f);
    return 0;
}
