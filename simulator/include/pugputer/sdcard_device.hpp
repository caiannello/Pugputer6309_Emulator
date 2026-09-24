// An idealized, transport-agnostic block-storage device -- closer to ATA
// PIO mode than real SPI/SD card protocol, since the real Pugputer6309
// SD/SPI transport hardware isn't chosen yet (see bios/sdcard.asm's file
// header). Backed by a raw disk image file (the same format real
// SD-flashing tools like dd/Win32DiskImager consume -- see
// pugputer/fat16_image.hpp, which builds one).
//
// Register window (4 bytes, see bios/defines.d's SD_LBA/SD_DATA/SD_CMDSTA):
//   offset 0-1: SD_LBA, the LOW 16 bits of the block number, big-endian (offset 0
//               = high byte) to match a plain STX/LDX from the CPU side. Bits
//               31..16 are latched separately by the SETHI command (below) and
//               stay put until the next SETHI; they are 0 after reset.
//   offset 2:   SD_DATA, a streaming port into/out of the active 512-byte
//               sector buffer; an auto-incrementing cursor advances on
//               every access and resets to 0 after a command completes.
//   offset 3:   SD_CMDSTA -- write issues a command (1=read the block at
//               the current LBA into the buffer, 2=write the buffer to
//               the block at the current LBA, 3=SETHI: latch SD_LBA's current
//               value as block-number bits 31..16); read returns status (bit0
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
#include <vector>

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

    // Test hook: every block write the CPU makes is appended, in order, to `log`
    // (nullptr stops logging). Replaying a prefix of the log onto the original
    // image gives exactly what a power cut between two block writes would leave.
    struct WriteRecord {
        uint32_t lba;
        std::array<uint8_t, kBlockSize> data;
    };
    void record_writes(std::vector<WriteRecord>* log) { write_log_ = log; }

    // Test hooks that make the card misbehave, for the BIOS's error handling:
    //   set_card_present(false)  -- the CARD_PRESENT status bit reads 0 (card pulled out)
    //   set_stuck_busy(true)     -- BUSY never clears (a card that hangs)
    //   fail_next_reads(n) / fail_next_writes(n)
    //                            -- the next n read / write COMMANDS report ERROR and do
    //                               nothing (a transient failure a retry can get past)
    // commands_issued() counts every read/write command the CPU has issued, retries included.
    void set_card_present(bool present) { card_present_ = present; }
    void set_stuck_busy(bool stuck) { stuck_busy_ = stuck; }
    void fail_next_reads(int n) { fail_reads_ = n; }
    void fail_next_writes(int n) { fail_writes_ = n; }
    // Every read command after the first `n` fails (a card that dies partway through).
    void fail_reads_after(int64_t n) { fail_reads_after_ = n; }
    uint64_t commands_issued() const { return commands_; }

    // IDevice
    uint8_t read(uint16_t offset) override;
    void write(uint16_t offset, uint8_t value) override;
    void reset() override;

private:
    std::fstream file_;
    uint16_t lba_ = 0;    // SD_LBA: the low word
    uint16_t lba_hi_ = 0; // latched by the SETHI command: the high word
    std::array<uint8_t, kBlockSize> buffer_{};
    uint16_t cursor_ = 0;
    bool last_error_ = false;
    std::vector<WriteRecord>* write_log_ = nullptr;
    bool card_present_ = true;
    bool stuck_busy_ = false;
    int fail_reads_ = 0;
    int fail_writes_ = 0;
    int64_t fail_reads_after_ = -1;
    uint64_t commands_ = 0;

    void do_command(uint8_t cmd);
};

} // namespace pugputer
