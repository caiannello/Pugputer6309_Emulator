/* CC's test: a program from three files, C and assembly. */
#include <stdio.h>

int add(int a, int b);
int twice(int x);
extern int counter;

int main(void)
{
    int sum = add(2, 3);
    printf("add %d twice %d counter %d\n", sum, twice(21), counter);
    return 0;
}
