// The Pugputer 6309 video card at $FF80-$FF9F: the card itself is vidcard/core (the same C
// the card's firmware is to run); this puts it on the bus and moves its beam in step with
// the CPU. 60 frames a second of CPU time, 525 lines each: every line is drawn as the beam
// reaches it, so what a program changes mid-frame shows from the next line on, as on the
// card, and the interrupt flags (vertical blank, line) follow the beam.
//
// The frames go to a VideoSink (the emulator's window). Until a program first writes to
// the card nothing is drawn or sent -- the machine is at full speed and no window opens --
// and afterwards only the frames the sink asks for are drawn (the window takes one per
// frame and holds the emulator to real time; see the emulator's --turbo).
#pragma once

#include <cstdint>
#include <memory>
#include <vector>

#include "pugputer/device.hpp"

struct vc_card;

namespace pugputer {

class VideoSink {
public:
    virtual ~VideoSink() = default;
    // Asked as each frame starts: should it be drawn?
    virtual bool wants_frame() = 0;
    // At the start of vertical blank, each frame: the picture (0x00RRGGBB, 640x480, rows
    // top first), or null if this frame wasn't drawn.
    virtual void frame(const uint32_t* pixels) = 0;
};

class VideoDevice : public IDevice {
public:
    static constexpr uint16_t kBase = 0xFF80;
    static constexpr uint16_t kSize = 0x20;
    static constexpr int kWidth = 640, kHeight = 480;

    explicit VideoDevice(double cpu_clock_hz = 3579545.0);
    ~VideoDevice() override;
    VideoDevice(const VideoDevice&) = delete;
    VideoDevice& operator=(const VideoDevice&) = delete;

    void set_sink(VideoSink* sink) { sink_ = sink; }
    // Draw every frame whether or not a sink wants it (tests).
    void set_draw_all(bool on) { draw_all_ = on; }

    uint8_t read(uint16_t offset) override;
    void write(uint16_t offset, uint8_t value) override;
    void reset() override;
    void tick(uint32_t cpu_cycles) override;
    bool irq_asserted() const override;

    // Written to since the last reset.
    bool active() const { return active_; }
    // The last frame drawn (0x00RRGGBB).
    const uint32_t* pixels() const { return pixels_.data(); }
    uint32_t pixel(int x, int y) const { return pixels_[static_cast<size_t>(y) * kWidth + x]; }
    uint64_t frames_drawn() const { return frames_drawn_; }
    vc_card& card() { return *card_; }

private:
    void begin_line(uint16_t line);

    struct CardDeleter {
        void operator()(vc_card* c) const;
    };
    std::unique_ptr<vc_card, CardDeleter> card_;
    std::vector<uint8_t> psram_;
    std::vector<uint32_t> pixels_;
    std::vector<uint16_t> line_;
    VideoSink* sink_ = nullptr;
    double cpu_hz_;
    uint64_t cycles_ = 0;
    uint64_t lines_ = 0;      // lines begun since reset
    uint64_t next_line_at_ = 0; // cycle count at which the next one begins
    bool active_ = false;
    bool drawing_ = false;    // this frame is being drawn
    bool draw_all_ = false;
    uint64_t frames_drawn_ = 0;
};

} // namespace pugputer
