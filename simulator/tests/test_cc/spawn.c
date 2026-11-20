/* spawn(): a child (KID.COM, which runs copies of itself) in pages of its
   own; this program's memory, in all three banks, is as it was after. */
#include <stdio.h>
#include <pug/sys.h>

char big[20000];

int main(void)
{
    unsigned i, bad = 0;
    int r;
    for (i = 0; i < sizeof big; i++)
        big[i] = (char)(i * 7 + 3);
    r = spawn("KID.COM", "3 hello");
    for (i = 0; i < sizeof big; i++)
        if (big[i] != (char)(i * 7 + 3))
            bad++;
    printf("parent: kid said %d, %u bytes changed\n", r, bad);
    printf("missing: %d\n", spawn("NOPE.COM", ""));
    printf("again: %d\n", spawn("KID.COM", "0 again"));
    return 0;
}
