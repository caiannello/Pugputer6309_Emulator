// An idealized, transport-agnostic block-storage device -- closer to ATA
// PIO mode than real SPI/SD card protocol, since the real Pugputer6309
// SD/SPI transport hardware isn't chosen yet (see bios/sdcard.asm's file
// header). Backed by a raw disk image file (the same format real
// SD-flashing tools like dd/Win32DiskImager consume -- see
// pugputer/fat16_image.hpp, which builds one).
//
// Register window (4 bytes, see bios/defines.d's SD_LBA/SD_DATA/SD_CMDSTA):
//   offset 0-1: SD_LBA, 16-bit block number, big-endian (offset 0 = high
//               byte) to match a plain STX/LDX from the CPU side.
//   offset 2:   SD_DATA, a streaming port into/out of the active 512-byte
//               sector buffer; an auto-incrementing cursor advances on
//               every access and resets to 0 after a command completes.
//   offset 3:   SD_CMDSTA -- write issues a command (1=read the block at
//               the current LBA into the buffer, 2=write the buffer to
//               the block at the current LBA); read returns status (bit0
//               BUSY, always clear here since this model completes
//               synchronously; bit1 CARD_PRESENT; bit2 ERROR -- the last
//               READ/WRITE command's underlying file I/O actually failed
//               (permissions, disk full, etc.), cleared by the next
//               command).
#pragma once

#include <array>
#include <cstdint>
#include <fstream>
#include <string>

#include "pugputer/device.hpp"

namespace pugputer {

class SdCardDevice : public IDevice {
public:
    static constexpr size_t kBlockSize = 512;

    SdCardDevice() = default;

    // Attaches a pre-built disk image (see fat16_image.hpp) for reading
    // and writing. Returns false if the file can't be opened -- the
    // device then just reports CARD_PRESENT clear, same as no image
    // attached at all.
    bool open(const std::string& path);
    bool is_open() const { return file_.is_open(); }

    // IDevice
    uint8_t read(uint16_t offset) override;
    void write(uint16_t offset, uint8_t value) override;
    void reset() override;

private:
    std::fstream file_;
    uint16_t lba_ = 0;
    std::array<uint8_t, kBlockSize> buffer_{};
    uint16_t cursor_ = 0;
    bool last_error_ = false;

    void do_command(uint8_t cmd);
};

} // namespace pugputer
