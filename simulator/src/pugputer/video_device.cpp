#include "pugputer/video_device.hpp"

#include <algorithm>
#include <cmath>
#include <cstdlib>

#include "vc.h"

namespace pugputer {

void VideoDevice::CardDeleter::operator()(vc_card* c) const { std::free(c); }

VideoDevice::VideoDevice(double cpu_clock_hz)
    : card_(static_cast<vc_card*>(std::calloc(1, sizeof(vc_card)))),
      psram_(VC_PSRAM_SIZE),
      pixels_(static_cast<size_t>(kWidth) * kHeight),
      line_(kWidth),
      cpu_hz_(cpu_clock_hz),
      queue_(kQueueSize) {
    card_->psram = psram_.data();
    reset();
}

VideoDevice::~VideoDevice() = default;

// How long the card's firmware (336MHz) takes over each command, from its last byte to its
// end: a + b * work, in ns, fitted to every command VIDGFX (both pages), MANDEL and VIDDEMO
// sent (the diag firmware's timings, 2026-11-07). They include what interrupts it while it
// runs: the bus, and core 0's share of drawing the picture. Where the fit's a came out below
// a command's fixed cost (about 450ns: TARGET, COLOR, FONT), or a sample's work never
// varied, b is from the mean instead.
uint64_t VideoDevice::command_cycles(uint8_t opcode, uint32_t work) const {
    struct Cost {
        double a, b;
    };
    static constexpr Cost kCost[VC_C_COUNT] = {
        {450, 0},       // NOP
        {450, 0},       // TARGET
        {450, 0},       // COLOR
        {450, 1040},    // PLOT
        {24990, 211},   // LINE
        {53780, 250},   // RECT
        {219490, 180},  // FILLRECT
        {450, 714},     // CIRCLE
        {77340, 201},   // DISC
        {499520, 241},  // CLEAR
        {450, 181},     // COPY
        {3470, 113},    // FILL
        {450, 613},     // BLIT (from the PSRAM)
        {122920, 229},  // TRIANGLE
        {450, 0},       // FONT
        {450, 97},      // CHAR
    };
    const Cost& k = kCost[opcode < VC_C_COUNT ? opcode : 0];
    return static_cast<uint64_t>((k.a + k.b * work) * 1e-9 * cpu_hz_ + 0.5);
}

uint8_t VideoDevice::read(uint16_t offset) {
    if (wake_) return 0xFF; // (not answering yet: the bus floats)
    uint8_t v = vc_read(card_.get(), static_cast<uint8_t>(offset));
    if ((offset & 0x1F) == VC_STATUS && !instant_) {
        if (commands_busy()) v |= VC_STATUS_BUSY;
        if (queue_len_ >= kQueueFullAt) v |= VC_STATUS_FULL;
    }
    return v;
}

void VideoDevice::write(uint16_t offset, uint8_t value) {
    if (wake_) return;
    active_ = true;
    const uint8_t reg = static_cast<uint8_t>(offset & 0x1F);
    if (reg == VC_CMD && !instant_) {
        if (queue_len_ < kQueueSize) {
            queue_[(queue_head_ + queue_len_) % kQueueSize] = value;
            ++queue_len_;
            arrived_ = cycles_;
        } else {
            ++lost_; // (STATUS said full)
        }
        run_commands();
        return;
    }
    if (reg == VC_CTRL && (value & 0x80)) {
        // A reset: the commands sent before it are dropped, as on the card (it would undo
        // them anyway).
        queue_len_ = 0;
        busy_until_ = cycles_;
        done_pending_ = false;
    }
    vc_write(card_.get(), reg, value);
}

void VideoDevice::run_commands() {
    vc_card* c = card_.get();
    for (;;) {
        if (cycles_ < busy_until_) return; // (the one running isn't done)
        if (done_pending_) {
            c->isr |= VC_IRQ_CMDDONE;
            done_pending_ = false;
        }
        if (!queue_len_) return;
        const uint8_t b = queue_[queue_head_];
        queue_head_ = (queue_head_ + 1) % kQueueSize;
        --queue_len_;
        const uint32_t work = c->work;
        const uint8_t isr = c->isr;
        vc_write(c, VC_CMD, b);
        if (c->cmd_len == 0) { // (that byte ended a command, which has run)
            // (from when the one before ended, or its bytes came, whichever was later)
            busy_until_ = std::max(busy_until_, arrived_) + command_cycles(c->cmd[0], c->work - work);
            if (!(isr & VC_IRQ_CMDDONE)) { // its interrupt: at its end
                c->isr &= static_cast<uint8_t>(~VC_IRQ_CMDDONE);
                done_pending_ = true;
            }
        }
    }
}

void VideoDevice::reset() {
    vc_reset(card_.get());
    card_->line = 0;
    card_->frame = 0;
    queue_len_ = 0;
    busy_until_ = 0;
    arrived_ = 0;
    done_pending_ = false;
    cycles_ = 0;
    lines_ = 0;
    next_line_at_ = 0;
    active_ = false;
    drawing_ = false;
    tick(0); // line 0 begins
}

void VideoDevice::mouse_to(int x, int y, uint8_t buttons) { vc_mouse_to(card_.get(), x, y, buttons); }

void VideoDevice::mouse_wheel(int clicks) { vc_mouse_wheel(card_.get(), clicks); }

void VideoDevice::key(uint8_t usage, bool down) { vc_key(card_.get(), usage, down ? 1 : 0); }

uint8_t VideoDevice::input_ctrl() const { return card_->in_ctrl; }

bool VideoDevice::irq_asserted() const { return vc_irq(card_.get()) != 0; }

void VideoDevice::tick(uint32_t cpu_cycles) {
    wake_ = wake_ > cpu_cycles ? wake_ - cpu_cycles : 0;
    cycles_ += cpu_cycles;
    if (done_pending_ || queue_len_) run_commands();
    while (cycles_ >= next_line_at_) {
        begin_line(static_cast<uint16_t>(lines_ % VC_LINES));
        ++lines_;
        // Line n begins at n / (60 * 525) seconds.
        next_line_at_ = static_cast<uint64_t>(std::ceil(static_cast<double>(lines_) * cpu_hz_ / (VC_FPS * VC_LINES)));
    }
}

void VideoDevice::begin_line(uint16_t line) {
    if (line == 0) drawing_ = active_ && (draw_all_ || (sink_ && sink_->wants_frame()));
    vc_begin_line(card_.get(), line);
    if (line < kHeight && drawing_) {
        vc_render_line(card_.get(), line, line_.data());
        uint32_t* row = pixels_.data() + static_cast<size_t>(line) * kWidth;
        for (int x = 0; x < kWidth; ++x) row[x] = vc_rgb888(line_[x]);
    }
    if (line == kHeight && active_) {
        if (drawing_) ++frames_drawn_;
        if (sink_) sink_->frame(drawing_ ? pixels_.data() : nullptr);
    }
}

} // namespace pugputer
