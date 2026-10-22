/* The Pugputer's SD interface at $FFD8-$FFDB (bios/defines.d: SD_LBA, SD_DATA, SD_CMDSTA),
 * on the board's microSD card. */
#ifndef VIDCARD_FW_BLOCKDEV_H
#define VIDCARD_FW_BLOCKDEV_H

#include <stdbool.h>
#include <stdint.h>

/* Its registers say BUSY until blockdev_start() has woken the card. */
void blockdev_init(void);
void blockdev_start(void);
/* Core 0's bus interrupt: an access to register `reg` (0-3). */
void blockdev_access(int reg, int read, uint8_t value);
/* Core 0's main loop: a block to read or write, if one is waiting. */
void blockdev_poll(void);
/* Its four bytes of the register copy (with the copy locked). */
void blockdev_refresh(void);

#endif
