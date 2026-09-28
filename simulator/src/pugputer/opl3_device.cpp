#include "pugputer/opl3_device.hpp"

#include <algorithm>
#include <iterator>

#include "../../third_party/nuked-opl3/opl3.h"

namespace pugputer {

namespace {
constexpr size_t kChunk = 512;  // frames made at a time (the size of buf_)
constexpr double kTimer1Us = 80.0;  // timer 1 counts in 80us steps,
constexpr double kTimer2Us = 320.0; // timer 2 in 320us steps
constexpr int16_t kQuiet = 16;      // output this close to 0 counts as silence
constexpr double kMaxRest = 10.0;   // an idle spell shorter than this (seconds) is a rest
} // namespace

Opl3Device::Opl3Device(uint32_t sample_rate, double cpu_clock_hz)
    : chip_(new opl3_chip()), rate_(sample_rate), cpu_hz_(cpu_clock_hz) {
    reset();
}

Opl3Device::~Opl3Device() { delete chip_; }

void Opl3Device::reset() {
    OPL3_Reset(chip_, rate_);
    std::fill(std::begin(regs_), std::end(regs_), uint8_t(0));
    address_ = 0;
    status_ = 0;
    t1_on_ = t2_on_ = false;
    t1_us_ = t2_us_ = 0;
    if (active_ && sink_) sink_->idle();
    active_ = false;
    due_ = 0;
    quiet_ = 0;
}

uint8_t Opl3Device::read(uint16_t offset) {
    // The status register answers on the first address; the others read as the bus
    // floats (they aren't readable on the chip).
    return (offset & 3) == 0 ? status_ : 0xFF;
}

void Opl3Device::write(uint16_t offset, uint8_t value) {
    switch (offset & 3) {
    case 0:
        address_ = value;
        break;
    case 2:
        address_ = static_cast<uint16_t>(0x100 | value);
        break;
    default:
        write_register(address_, value);
        break;
    }
}

void Opl3Device::write_register(uint16_t r, uint8_t v) {
    catch_up(); // the write lands at this moment in the sound
    ++writes_;
    if (r == 0x04) { // timer control (Nuked OPL3 has no timers: it isn't told)
        if (v & 0x80) {
            status_ = 0; // RST: the flags go, and the rest of the write is ignored
            return;
        }
        bool t1 = (v & 0x01) != 0, t2 = (v & 0x02) != 0;
        if (t1 && !t1_on_) t1_us_ = 0; // a timer starting counts from its preset
        if (t2 && !t2_on_) t2_us_ = 0;
        t1_on_ = t1;
        t2_on_ = t2;
        regs_[r] = v;
        return;
    }
    regs_[r] = v;
    OPL3_WriteReg(chip_, r, v);
    if (r == 0x02 || r == 0x03) return; // (timer presets: nothing to hear)
    if (!active_) {
        active_ = true;
        due_ = 0;
        // Back from idle soon enough to be a rest in the music: the silence it was is
        // played before this write, so the music keeps its time (the emulator ran ahead
        // meanwhile, and now waits for the sound to catch up).
        double rest = static_cast<double>(cycles_ - idle_at_) / cpu_hz_;
        if (sink_ && idle_at_ != 0 && rest < kMaxRest) {
            std::fill(std::begin(buf_), std::end(buf_), int16_t(0));
            for (size_t n = static_cast<size_t>(rest * rate_); n > 0;) {
                size_t k = std::min(n, kChunk);
                sink_->write(buf_, k);
                frames_made_ += k;
                n -= k;
            }
        }
    }
    quiet_ = 0;
}

void Opl3Device::tick(uint32_t cpu_cycles) {
    cycles_ += cpu_cycles;
    double us = cpu_cycles * 1e6 / cpu_hz_;
    if (t1_on_) {
        double period = (256 - regs_[0x02]) * kTimer1Us;
        for (t1_us_ += us; t1_us_ >= period; t1_us_ -= period)
            if (!(regs_[0x04] & 0x40)) status_ |= 0x40;
    }
    if (t2_on_) {
        double period = (256 - regs_[0x03]) * kTimer2Us;
        for (t2_us_ += us; t2_us_ >= period; t2_us_ -= period)
            if (!(regs_[0x04] & 0x20)) status_ |= 0x20;
    }
    status_ = static_cast<uint8_t>((status_ & 0x60) | ((status_ & 0x60) ? 0x80 : 0));
    if (!active_ || !sink_) return;
    due_ += cpu_cycles * static_cast<double>(rate_) / cpu_hz_;
    if (due_ >= kChunk) catch_up();
}

void Opl3Device::catch_up() {
    if (!active_ || !sink_) {
        due_ = 0;
        return;
    }
    size_t n = static_cast<size_t>(due_);
    due_ -= static_cast<double>(n);
    while (n > 0 && active_) {
        size_t k = std::min(n, kChunk);
        generate(k);
        n -= k;
    }
}

void Opl3Device::generate(size_t frames) {
    OPL3_GenerateStream(chip_, buf_, static_cast<uint32_t>(frames));
    frames_made_ += frames;
    bool silent = true;
    for (size_t i = 0; i < 2 * frames && silent; ++i) silent = buf_[i] >= -kQuiet && buf_[i] <= kQuiet;
    quiet_ = silent ? quiet_ + frames : 0;
    sink_->write(buf_, frames);
    if (quiet_ >= rate_) { // a second of silence, and no writes: stop until the next one
        active_ = false;
        due_ = 0;
        idle_at_ = cycles_;
        sink_->idle();
    }
}

} // namespace pugputer
