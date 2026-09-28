// The emulator's sound output: an AudioSink (pugputer/opl3_device.hpp) that plays what it
// is given on the host's sound device. write() blocks while about a quarter of a second
// is already waiting to be played, which is what keeps the emulator to real time while
// music plays.
//
// Windows: the waveOut API (winmm, part of Windows). Elsewhere: the frames are piped to
// the first of aplay (ALSA), pacat (PulseAudio) and pw-cat (PipeWire) that is installed,
// so the program links no sound library (the Linux release is fully static).
#pragma once

#include <cstddef>
#include <cstdint>
#include <memory>
#include <string>

#include "pugputer/opl3_device.hpp"

class AudioOut : public pugputer::AudioSink {
public:
    AudioOut();
    ~AudioOut() override;
    // 16-bit stereo at `rate`. False (and why, in error()) if there is no way to play.
    bool open(uint32_t rate);
    void close();
    // What it plays through (for the start-up message).
    const std::string& description() const { return description_; }
    const std::string& error() const { return error_; }

    void write(const int16_t* frames, size_t count) override;
    void idle() override;

private:
    struct Impl;
    std::unique_ptr<Impl> impl_;
    std::string description_, error_;
};
