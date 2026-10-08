// The video card's picture in a window (pugputer/video_device.hpp's VideoSink), and what is
// done in it: the characters typed, for the UART -- so the window can be used like the
// terminal -- and the keys pressed and released and the mouse, for the card's input registers.
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

    // What happened in the window, oldest first: a character typed (for the UART), a key
    // pressed or released (its USB HID usage code, for the card), the mouse moved or a button
    // went up or down, the wheel turned.
    struct Input {
        enum Kind { Char, Key, Mouse, Wheel } kind = Char;
        uint8_t code = 0;    // Char: the byte; Key: the usage code
        bool down = false;   // Key
        int x = 0, y = 0;    // Mouse: in the card's 640x480 pixels (may be off the picture)
        uint8_t buttons = 0; // Mouse: bit 0 left, 1 right, 2 middle
        int clicks = 0;      // Wheel: + is away from the user
    };
    bool poll(Input& in);

    // Hide the PC's mouse pointer over the window: the program shows its own.
    void set_pointer_hidden(bool hidden);

    // The window is open (it has been opened, and not closed since).
    bool showing() const;

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
