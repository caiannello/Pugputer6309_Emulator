// The video card's picture in a window (pugputer/video_device.hpp's VideoSink), and the
// keys typed into it, for the UART -- so the window can be used like the terminal.
//
// The window opens with the first frame, which is when a program first uses the card, and
// takes every frame after that, holding the emulator to the card's 60 frames a second of real
// time (a game that waits for vertical blank then runs at its real speed). With turbo on, the
// emulator runs flat out and the window shows a frame every 1/60 s of real time. Closing the
// window stops all that: the card goes on, unseen, at full speed.
//
// Windows: a plain Win32 window (GDI), on a thread of its own. Elsewhere: pugputer-video
// (pugputer_video.cpp, an SDL2 program beside the emulator), fed through a pipe -- the emulator
// itself is linked statically, which SDL2 can't be. When it can't be started (not built, no
// display), it says why and the emulator goes on without a window.
#pragma once

#include <chrono>
#include <cstdint>
#include <memory>

#include "pugputer/video_device.hpp"

class VideoOut : public pugputer::VideoSink {
public:
    VideoOut();
    ~VideoOut() override;
    VideoOut(const VideoOut&) = delete;
    VideoOut& operator=(const VideoOut&) = delete;

    void set_turbo(bool on) { turbo_ = on; }
    void set_scale(int scale) { scale_ = scale < 1 ? 1 : scale; }

    bool wants_frame() override;
    void frame(const uint32_t* pixels) override;

    // The next byte typed into the window, if any.
    bool poll_key(uint8_t& byte);

    struct Impl;

private:
    void open();                      // the window, when the first frame comes
    void show(const uint32_t* pixels); // a new picture for it
    bool closed() const;              // it has been closed (or couldn't open)

    std::unique_ptr<Impl> impl_;
    bool turbo_ = false;
    int scale_ = 1;
    bool opened_ = false;
    std::chrono::steady_clock::time_point next_{};  // when the next frame is due (paced)
    std::chrono::steady_clock::time_point shown_{}; // when a frame was last shown (turbo)
};
