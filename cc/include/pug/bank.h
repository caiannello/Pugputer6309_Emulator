/* pug/bank.h -- CC (the Pugputer's C compiler): data in banked RAM.

   The Pugputer has up to 4MB of RAM in 16KB pages; a program sees 64KB of
   it at a time, as four banks. A far address is a page (from page_alloc)
   and an offset in it, 0 to 0x3FFF. far_read and far_write copy between one
   and a program's own (near) memory, whatever the banks show. A program
   that maps a page into a bank itself (bank_map) can use it directly there,
   through ordinary pointers: not bank 0 (the system's), and not the bank
   its stack is in (CC's programs: bank 3, $C000-$EFFF; with banked code,
   bank 3 is the overlays' window and the stack is in bank 2). */
#ifndef _PUG_BANK_H
#define _PUG_BANK_H

int page_alloc(void);           /* a free page, or -1 */
void page_free(int page);       /* (a program's pages aren't freed for it) */
int bank_get(int bank);         /* the page mapped in bank 0..3 */
int bank_map(int bank, int page);       /* -> the page that was there, or -1 */

int far_read(void *dst, int page, unsigned off, unsigned n);       /* 0, or -1 */
int far_write(int page, unsigned off, const void *src, unsigned n);
int far_peek(int page, unsigned off);   /* the byte, 0..255 (-1: no such page) */
void far_poke(int page, unsigned off, int value);

#endif
