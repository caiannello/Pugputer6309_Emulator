/* banked.c's: compiled with CC -b 3, so in overlay 3. It calls back into
   bank 1. */
int f1(int x);

int far3(int x) { return x * 3 + f1(0); }
