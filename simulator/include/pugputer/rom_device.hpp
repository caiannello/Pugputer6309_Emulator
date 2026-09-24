// A fixed-size, read-only memory device: reads return its contents,
// writes are silently ignored (the contents never change). This is what
// makes RAM-size-detection scans (write a probe byte, read it back, see
// it didn't "stick") work correctly against a mapped ROM region -- see
// simulator/README.md.
#pragma once

#include <cstdint>
#include <vector>

#include "pugputer/device.hpp"

namespace pugputer {

class RomDevice : public IDevice {
public:
    explicit RomDevice(uint16_t size) : data_(size, 0) {}

    uint8_t read(uint16_t offset) override {
        return offset < data_.size() ? data_[offset] : 0xFF;
    }
    void write(uint16_t, uint8_t) override {
        // Real ROM: writes have no effect on what reads back.
    }
    void reset() override {
        // ROM contents don't change on reset.
    }

    // Host-facing: (re)load the ROM's contents, e.g. from a byte range
    // just pulled out of RAM after an S-record load (see srec_loader.hpp).
    void load(const uint8_t* src, size_t n) {
        size_t count = n < data_.size() ? n : data_.size();
        for (size_t i = 0; i < count; ++i) data_[i] = src[i];
    }

    uint8_t* data() { return data_.data(); }
    const uint8_t* data() const { return data_.data(); }
    size_t size() const { return data_.size(); }

private:
    std::vector<uint8_t> data_;
};

} // namespace pugputer
