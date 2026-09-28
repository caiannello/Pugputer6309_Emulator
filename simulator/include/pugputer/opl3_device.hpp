// The Yamaha YMF262 (OPL3) FM synthesizer, as the Pugputer6309's music card puts it at
// $FFE0-$FFE3: offset 0 = address (register array 0, and a read gives the status),
// 1 = data, 2 = address (array 1), 3 = data. A data write goes to the last address
// written, of either array. The sound itself is Nuked OPL3's (third_party/nuked-opl3);
// this adds the chip's two timers and status register, which Nuked OPL3 leaves to its host.
//
// Time is the CPU's: tick() turns emulated cycles into stereo frames at the sample rate
// asked for, and hands them to an AudioSink. So the music keeps the tempo the program
// times it to, however fast the emulator runs -- and a sink that blocks while its output
// is full (a sound card) holds the emulator to real time while music plays.
//
// Frames are only made while the chip is "active": from a register write until it has
// been silent, with no writes, for a second. The rest of the time nothing is made, the
// sink isn't called, and the emulator runs as fast as it can. When a write comes less
// than ten seconds (of CPU time) after it went idle, that was a rest in the music: the
// silence is sent first, so the music keeps its time. Without a sink the chip is kept
// (timers, registers) but no sound is made at all.
#pragma once

#include <cstddef>
#include <cstdint>

#include "pugputer/device.hpp"

struct _opl3_chip;

namespace pugputer {

class AudioSink {
public:
    virtual ~AudioSink() = default;
    // `count` stereo frames, left then right, 16-bit signed, at the device's sample rate.
    virtual void write(const int16_t* frames, size_t count) = 0;
    // The chip has gone quiet: no more frames until it plays again (a good moment to
    // send out anything held back).
    virtual void idle() {}
};

class Opl3Device : public IDevice {
public:
    static constexpr double kPugputerCpuHz = 3579545.0; // 14.318MHz / 4

    explicit Opl3Device(uint32_t sample_rate = 48000, double cpu_clock_hz = kPugputerCpuHz);
    ~Opl3Device() override;
    Opl3Device(const Opl3Device&) = delete;
    Opl3Device& operator=(const Opl3Device&) = delete;

    void set_sink(AudioSink* sink) { sink_ = sink; }
    uint32_t sample_rate() const { return rate_; }

    uint8_t read(uint16_t offset) override;
    void write(uint16_t offset, uint8_t value) override;
    void reset() override;
    void tick(uint32_t cpu_cycles) override;

    // Making sound (see above).
    bool active() const { return active_; }
    // Counters, for tests and curiosity.
    uint64_t frames_made() const { return frames_made_; }
    uint64_t register_writes() const { return writes_; }
    uint8_t reg(uint16_t r) const { return regs_[r & 0x1FF]; } // last value written

private:
    void generate(size_t frames);
    void catch_up(); // makes the frames due so far
    void write_register(uint16_t r, uint8_t v);

    _opl3_chip* chip_;
    AudioSink* sink_ = nullptr;
    uint32_t rate_;
    double cpu_hz_;
    uint16_t address_ = 0; // latched register number, 0..$1FF
    uint8_t regs_[0x200] = {};
    uint8_t status_ = 0;   // bit 7 IRQ, bit 6 timer 1, bit 5 timer 2
    bool t1_on_ = false, t2_on_ = false;
    double t1_us_ = 0, t2_us_ = 0; // time into the current timer period
    bool active_ = false;
    double due_ = 0;          // frames owed to the sink (fractional)
    uint64_t quiet_ = 0;      // silent frames in a row, since the last write
    uint64_t cycles_ = 0;     // CPU cycles so far
    uint64_t idle_at_ = 0;    // when it last went idle (0: never)
    uint64_t frames_made_ = 0, writes_ = 0;
    int16_t buf_[2 * 512];
};

} // namespace pugputer
