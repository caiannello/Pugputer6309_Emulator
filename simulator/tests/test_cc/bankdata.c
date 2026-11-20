#include <stdio.h>
#include <string.h>
#include <pug/bank.h>

char buf[3000], back[3000];

int main(void)
{
    int a = page_alloc(), b = page_alloc(), old, i, bad = 0;
    char *p = (char *)0x8000;
    for (i = 0; i < 3000; i++)
        buf[i] = (char)(i * 13);
    printf("pages %d %d\n", a > 3, b > a);
    printf("write %d %d\n", far_write(a, 0x3000, buf, 3000), far_write(a, 0x3500, buf, 3000));
    printf("read %d\n", far_read(back, a, 0x3000, 3000));
    for (i = 0; i < 3000; i++)
        if (back[i] != buf[i])
            bad++;
    far_poke(b, 5, 'Z');
    printf("bad %d peek %c %d\n", bad, far_peek(b, 5), far_peek(a, 0x3001));
    old = bank_map(2, b);
    printf("mapped %c %d\n", p[5], bank_get(2) == b);
    strcpy(p + 100, "direct");
    bank_map(2, old);
    far_read(back, b, 100, 7);
    printf("%s %d\n", back, bank_get(2) == old);
    page_free(a);
    page_free(b);
    return 0;
}
