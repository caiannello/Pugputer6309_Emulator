/* spawn.c's child: "KID n word" runs KID n-1 (down to 0), keeps a file open
   (which ending closes), and ends with the exit code n + 10. */
#include <stdio.h>
#include <stdlib.h>
#include <pug/sys.h>

char mine[18000];

int main(int argc, char **argv)
{
    int depth = atoi(argv[1]);
    char tail[20];
    FILE *f;
    int r = 0;
    unsigned i;
    sprintf(tail, "KID%d.DAT", depth);
    f = fopen(tail, "w");
    fputs("left open", f);
    for (i = 0; i < sizeof mine; i++)
        mine[i] = (char)depth;
    if (depth > 0) {
        sprintf(tail, "%d deeper", depth - 1);
        r = spawn("KID.COM", tail);
    }
    for (i = 0; i < sizeof mine; i++)
        if (mine[i] != (char)depth) {
            printf("kid %d: memory changed\n", depth);
            break;
        }
    printf("kid %d (%s): its kid said %d\n", depth, argv[2], r);
    exit(depth + 10);
    return 0;
}
