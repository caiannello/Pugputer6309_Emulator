#include "pugputer/video_device.hpp"

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
      cpu_hz_(cpu_clock_hz) {
    card_->psram = psram_.data();
    reset();
}

VideoDevice::~VideoDevice() = default;

uint8_t VideoDevice::read(uint16_t offset) { return vc_read(card_.get(), static_cast<uint8_t>(offset)); }

void VideoDevice::write(uint16_t offset, uint8_t value) {
    active_ = true;
    vc_write(card_.get(), static_cast<uint8_t>(offset), value);
}

void VideoDevice::reset() {
    vc_reset(card_.get());
    card_->line = 0;
    card_->frame = 0;
    cycles_ = 0;
    lines_ = 0;
    next_line_at_ = 0;
    active_ = false;
    drawing_ = false;
    tick(0); // line 0 begins
}

bool VideoDevice::irq_asserted() const { return vc_irq(card_.get()) != 0; }

void VideoDevice::tick(uint32_t cpu_cycles) {
    cycles_ += cpu_cycles;
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
