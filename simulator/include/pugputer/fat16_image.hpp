// Builds a fresh, unpartitioned ("superfloppy" -- no MBR, sector 0 is the
// FAT16 boot sector directly) disk image: the same raw format real
// SD-flashing tools (dd, Win32DiskImager, Raspberry Pi Imager, ...) write
// byte-for-byte to a physical device, and that mtools/Windows can read.
// This is the on-disk format's single source of truth on the host side;
// dos/dos.asm's parser must stay in sync with it by convention (the same
// relationship srec_loader.cpp has with the S-record spec).
#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace pugputer {

struct Fat16File {
    std::string name; // e.g. "BASIC.COM" or "CMD/BASIC.COM" -- converted to 8.3 internally
    std::vector<uint8_t> data;
};

struct Fat16BuildResult {
    bool ok = false;
    std::string error;
};

// `dos_payload` is written starting at LBA 1 (right after the boot
// sector); its size (rounded up to whole sectors) plus 1 becomes the
// BPB's reserved-sector-count, so bios/sdcard.asm's SD_BOOT_TRY knows how
// much to load. `files` become root-directory entries with their data
// written into the cluster area; a name with "/" in it ("CMD/SHELL.COM") goes in
// that subdirectory, which is created (with "." and "..") on first mention.
// Fails (ok=false) if the files don't fit, the root has too many entries, or the resulting
// cluster count would fall outside FAT16's valid range (4085-65524) --
// adjust total_sectors/sectors_per_cluster if so.
Fat16BuildResult build_fat16_image(const std::string& path, const std::vector<uint8_t>& dos_payload,
                                    const std::vector<Fat16File>& files, uint32_t total_sectors = 16384,
                                    uint8_t sectors_per_cluster = 2, uint16_t root_entry_count = 512,
                                    uint8_t num_fats = 2);

} // namespace pugputer
