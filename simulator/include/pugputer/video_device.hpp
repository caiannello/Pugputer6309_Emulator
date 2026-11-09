// The Pugputer 6309 video card at $FF80-$FF9F: the card itself is vidcard/core (the same C
// the card's firmware is to run); this puts it on the bus and moves its beam in step with
// the CPU. 60 frames a second of CPU time, 525 lines each: every line is drawn as the beam
// reaches it, so what a program changes mid-frame shows from the next line on, as on the
// card, and the interrupt flags (vertical blank, line) follow the beam.
//
// Drawing commands go into a queue as on the card (64KB; STATUS says full with 64 bytes or
// fewer left, and bytes sent then are lost), and each takes as long as the card's firmware
// takes over it, measured on the hardware: STATUS says busy, and the next command waits,
// until then, and the commands-done interrupt comes at its end. (A command's pixels are all
// there from its start, where the card's appear as it goes.)
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
    // Test hook: the card is off the bus for the next `cycles` CPU cycles, as at power-on,
    // until the RP2350's firmware turns its level shifters on: reads float ($FF) and
    // writes are lost. Not undone by reset() (/RES doesn't restart the firmware).
    void set_wake_cycles(uint64_t cycles) { wake_ = cycles; }
    // Test hook: drawing commands take no time (the card as it was emulated before its
    // queue was): each runs as its last byte arrives.
    void set_instant_commands(bool on) { instant_ = on; }

    // The drawing-command queue as on the card.
    static constexpr uint32_t kQueueSize = 65536;
    static constexpr uint32_t kQueueFullAt = kQueueSize - 64;
    // The CPU cycles a command takes on the card: opcode, and its work (vc_card.work's count:
    // pixels drawn or looked at, or bytes COPYed or FILLed).
    uint64_t command_cycles(uint8_t opcode, uint32_t work) const;
    // Command bytes waiting, and those lost so far because the queue was full.
    uint32_t commands_waiting() const { return queue_len_; }
    uint64_t command_bytes_lost() const { return lost_; }

    uint8_t read(uint16_t offset) override;
    void write(uint16_t offset, uint8_t value) override;
    void reset() override;
    void tick(uint32_t cpu_cycles) override;
    bool irq_asserted() const override;

    // The mouse and keyboard (the window's, or a test's): see vc.h, vc_mouse_to and vc_key.
    void mouse_to(int x, int y, uint8_t buttons);
    void mouse_wheel(int clicks);
    void key(uint8_t usage, bool down);
    // A gamepad (0-3): its 8 bytes as a program reads them, or nullptr when it's unplugged
    // (see vc.h, vc_pad).
    void pad(int n, const uint8_t* state);
    // Which pad it is, before its first pad() (USB vendor and product IDs: they pick its
    // button map; see vc.h, vc_pad_id).
    void pad_id(int n, uint16_t vid, uint16_t pid);
    // The program's VC_IN_CTRL: bit 0, sprite 0 is its mouse pointer; bit 1, it takes the
    // keys typed into the window (they go to the card, not the UART).
    uint8_t input_ctrl() const;

    // Written to since the last reset.
    bool active() const { return active_; }
    // The last frame drawn (0x00RRGGBB).
    const uint32_t* pixels() const { return pixels_.data(); }
    uint32_t pixel(int x, int y) const { return pixels_[static_cast<size_t>(y) * kWidth + x]; }
    uint64_t frames_drawn() const { return frames_drawn_; }
    vc_card& card() { return *card_; }

private:
    void begin_line(uint16_t line);
    void run_commands();   // feed the queue to the card, as far as the time allows
    bool commands_busy() const { return queue_len_ || cycles_ < busy_until_; }

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
    uint64_t wake_ = 0; // cycles until the card answers (set_wake_cycles)
    bool instant_ = false;
    std::vector<uint8_t> queue_;
    uint32_t queue_head_ = 0, queue_len_ = 0;
    uint64_t lost_ = 0;
    uint64_t busy_until_ = 0;  // when the command running ends (cycles_)
    uint64_t arrived_ = 0;     // when the last byte was queued
    bool done_pending_ = false; // its commands-done interrupt is held until then
};

} // namespace pugputer
