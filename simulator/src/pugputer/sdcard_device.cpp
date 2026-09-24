#include "pugputer/sdcard_device.hpp"

namespace pugputer {

namespace {
constexpr uint8_t kStaBusy = 0x01;
constexpr uint8_t kStaCard = 0x02;
constexpr uint8_t kStaError = 0x04;
constexpr uint8_t kCmdRead = 1;
constexpr uint8_t kCmdWrite = 2;
constexpr uint8_t kCmdSetHi = 3;
} // namespace

bool SdCardDevice::open(const std::string& path) {
    file_.open(path, std::ios::in | std::ios::out | std::ios::binary);
    return file_.is_open();
}

uint8_t SdCardDevice::read(uint16_t offset) {
    switch (offset) {
        case 0:
            return static_cast<uint8_t>(lba_ >> 8);
        case 1:
            return static_cast<uint8_t>(lba_ & 0xFF);
        case 2: {
            uint8_t b = buffer_[cursor_];
            if (cursor_ + 1 < kBlockSize) ++cursor_;
            return b;
        }
        case 3: {
            uint8_t status = 0; // BUSY always clear -- synchronous model (unless stuck)
            if (stuck_busy_) status |= kStaBusy;
            if (is_open() && card_present_) status |= kStaCard;
            if (last_error_) status |= kStaError;
            return status;
        }
        default:
            return 0xFF;
    }
}

void SdCardDevice::write(uint16_t offset, uint8_t value) {
    switch (offset) {
        case 0:
            lba_ = static_cast<uint16_t>((lba_ & 0x00FF) | (value << 8));
            cursor_ = 0; // a new LBA always precedes a new streaming
            break;       // sequence -- see do_command()'s comment
        case 1:
            lba_ = static_cast<uint16_t>((lba_ & 0xFF00) | value);
            cursor_ = 0;
            break;
        case 2:
            buffer_[cursor_] = value;
            if (cursor_ + 1 < kBlockSize) ++cursor_;
            break;
        case 3:
            do_command(value);
            break;
        default:
            break;
    }
}

void SdCardDevice::do_command(uint8_t cmd) {
    last_error_ = false;
    if (cmd == kCmdSetHi) {
        lba_hi_ = lba_;
        cursor_ = 0;
        return;
    }
    if (!is_open() || !card_present_) {
        last_error_ = true;
        cursor_ = 0;
        return;
    }
    if (cmd == kCmdRead || cmd == kCmdWrite) ++commands_;
    if (cmd == kCmdRead && fail_reads_after_ >= 0 && static_cast<int64_t>(commands_) > fail_reads_after_) {
        last_error_ = true; // dead from here on
        cursor_ = 0;
        return;
    }
    if ((cmd == kCmdRead && fail_reads_ > 0) || (cmd == kCmdWrite && fail_writes_ > 0)) {
        --(cmd == kCmdRead ? fail_reads_ : fail_writes_);
        last_error_ = true; // a transient failure: the command did nothing
        cursor_ = 0;
        return;
    }
    std::streamoff pos = ((static_cast<std::streamoff>(lba_hi_) << 16) | lba_) * static_cast<std::streamoff>(kBlockSize);
    if (cmd == kCmdRead) {
        file_.clear();
        file_.seekg(pos);
        file_.read(reinterpret_cast<char*>(buffer_.data()), static_cast<std::streamsize>(kBlockSize));
        if (!file_) {
            last_error_ = true;
            file_.clear();
            buffer_.fill(0);
        }
    } else if (cmd == kCmdWrite) {
        file_.clear();
        file_.seekp(pos);
        file_.write(reinterpret_cast<const char*>(buffer_.data()), static_cast<std::streamsize>(kBlockSize));
        file_.flush();
        if (!file_) last_error_ = true; // real failure (permissions, disk
                                        // full, etc.) -- checked BEFORE
                                        // clearing the stream's error
                                        // state, unlike before, when this
                                        // check didn't exist at all and
                                        // any write failure silently
                                        // looked like success forever
        file_.clear();
        if (write_log_) write_log_->push_back({(static_cast<uint32_t>(lba_hi_) << 16) | lba_, buffer_});
    }
    // cursor_ resets here too (not just on the LBA write above): after a
    // READ command, the CPU consumes the 512 bytes via SD_DATA reads,
    // which needs to start at 0 -- and this reset must happen now, before
    // that consumption, not merely on the next LBA write (which wouldn't
    // occur until well after those reads).
    cursor_ = 0;
}

void SdCardDevice::reset() {
    lba_ = 0;
    lba_hi_ = 0;
    cursor_ = 0;
    buffer_.fill(0);
}

} // namespace pugputer
