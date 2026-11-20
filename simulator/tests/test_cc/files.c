#include <stdio.h>
#include <stdlib.h>
#include <limits.h>

int main(void)
{
    FILE *f = fopen("seek.dat", "w+");
    long pos, end;
    int c, d;
    fputs("0123456789", f);
    pos = ftell(f);
    fseek(f, 3L, SEEK_SET);
    c = fgetc(f);
    fseek(f, -2L, SEEK_END);
    d = fgetc(f);
    end = ftell(f);
    fseek(f, -5L, SEEK_CUR);
    printf("file %ld %c %c %ld %c\n", pos, c, d, end, fgetc(f));
    fclose(f);
    remove("seek.dat");
    printf("atol %ld %ld %ld\n", atol("  -123456789"), atol("+42x"), labs(-70000L));
    printf("limits %ld %ld %lu\n", LONG_MIN, LONG_MAX, ULONG_MAX);
    fprintf(stderr, "to stderr\n");
    return 0;
}
