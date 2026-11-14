// pugputer-video: the video card's window for the emulator on Linux (and other POSIX systems).
// The emulator is linked fully statically so that it runs on any Linux; a window needs SDL2,
// which can't be, so it lives in this separate program -- the way the emulator's sound goes
// to aplay. The emulator starts it (video_out.cpp) and talks to it through two pipes:
//
//   stdin   frames, one after another: a 4-byte header ('F', flags: bit 0 hide the mouse
//           pointer -- the program draws its own --, 0, 0), then 640x480 pixels, 4 bytes each
//           (0x00RRGGBB, little-endian -- as the emulator holds them), rows top first
//   stdout  what is typed into the window, as a terminal sends it (bytes below $80), and,
//           each starting with $FF, the keys and the mouse for the card's input registers:
//             $FF 'K' usage down      a key pressed (down 1, again as it repeats) or released
//                                     (0); usage is its USB HID usage code, which SDL's
//                                     scancodes are
//             $FF 'M' x:2 y:2 buttons the mouse moved, or a button went down or up: x, y in
//                                     the picture's pixels (signed, high byte first), buttons
//                                     bit 0 left, 1 right, 2 middle
//             $FF 'W' clicks          the wheel turned (signed; + is away from the user)
//             $FF 'P' pad present vid:2 pid:2 state:8
//                                     a gamepad (0-3) came, changed or went (present 0, and
//                                     the rest 0): its USB IDs, high byte first, and its 8
//                                     bytes as the card's pads have them (vc.h's VC_PAD_*)
//
// The gamepads are SDL's joysticks, the first four to be plugged in, read as the Windows
// window reads them (video_out.cpp): the buttons in the pad's own order, the sticks -127 to
// 127 with a dead zone, the d-pad from its hat -- or, with none, from the left stick.
//
// It ends when the window is closed (the emulator sees the pipe close) or when stdin ends.
//
//   pugputer-video [--scale N]
#include <SDL.h>

#include <atomic>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include <unistd.h>

#include "vc.h"

namespace {
constexpr int kW = 640, kH = 480;
constexpr size_t kFrameBytes = static_cast<size_t>(kW) * kH * 4;

std::mutex g_lock;
std::vector<uint8_t> g_frame(kFrameBytes);
bool g_fresh = false;
std::atomic<bool> g_input_done{false};
std::atomic<bool> g_hide_pointer{false};

bool read_all(uint8_t* p, size_t len) {
    size_t got = 0;
    while (got < len) {
        ssize_t n = read(STDIN_FILENO, p + got, len - got);
        if (n <= 0) return false;
        got += static_cast<size_t>(n);
    }
    return true;
}

// Reads frames from stdin as they come; the newest one is shown.
void read_frames() {
    std::vector<uint8_t> buf(kFrameBytes);
    for (;;) {
        uint8_t header[4];
        if (!read_all(header, sizeof(header)) || header[0] != 'F' || !read_all(buf.data(), kFrameBytes)) {
            g_input_done = true;
            return;
        }
        g_hide_pointer = (header[1] & 1) != 0;
        std::lock_guard<std::mutex> g(g_lock);
        g_frame.swap(buf);
        g_fresh = true;
    }
}

void send(const char* s, size_t n) {
    while (n > 0) {
        ssize_t w = write(STDOUT_FILENO, s, n);
        if (w <= 0) return;
        s += w;
        n -= static_cast<size_t>(w);
    }
}
void send(const char* s) { send(s, std::strlen(s)); }
void send(char c) { send(&c, 1); }

void send_key(SDL_Scancode sc, bool down) {
    if (sc <= 0 || sc > 0xE7) return; // (not a key the USB keyboard page has)
    const char rec[4] = {'\xFF', 'K', static_cast<char>(sc), static_cast<char>(down ? 1 : 0)};
    send(rec, sizeof(rec));
}

void send_mouse(int x, int y, uint8_t buttons) {
    const char rec[7] = {'\xFF', 'M', static_cast<char>(x >> 8), static_cast<char>(x), static_cast<char>(y >> 8),
                         static_cast<char>(y), static_cast<char>(buttons)};
    send(rec, sizeof(rec));
}

// SDL's button mask as the card's: bit 0 left, 1 right, 2 middle.
uint8_t card_buttons(uint32_t mask) {
    return static_cast<uint8_t>(((mask & SDL_BUTTON_LMASK) ? 1 : 0) | ((mask & SDL_BUTTON_RMASK) ? 2 : 0) |
                                ((mask & SDL_BUTTON_MMASK) ? 4 : 0));
}

// The gamepads, as the card's pads 0-3.
struct Pad {
    SDL_Joystick* joy = nullptr;
    SDL_GameController* pad = nullptr; // when SDL knows its layout: then the sticks come from it
    SDL_JoystickID id = -1;
    uint8_t sent[8] = {};
    bool fresh = false; // just plugged in: it has yet to be sent
};
Pad g_pads[VC_PADS];

void send_pad(int n, bool present, uint16_t vid, uint16_t pid, const uint8_t* state) {
    char rec[16] = {'\xFF', 'P', static_cast<char>(n), static_cast<char>(present ? 1 : 0),
                    static_cast<char>(vid >> 8), static_cast<char>(vid), static_cast<char>(pid >> 8),
                    static_cast<char>(pid)};
    if (state) std::memcpy(rec + 8, state, 8);
    send(rec, sizeof(rec));
}

// An axis as the card's sticks have it: -127 to 127, and values close to the middle read 0
// (as the firmware's axis_value in usbhost.c).
uint8_t pad_axis(int16_t v) {
    long n = (static_cast<long>(v) * 2 + 1) * 127 / 65535;
    return static_cast<uint8_t>(static_cast<int8_t>(n > -8 && n < 8 ? 0 : n));
}

void pad_added(int index) {
    int n = 0;
    while (n < VC_PADS && g_pads[n].joy) ++n;
    if (n == VC_PADS) return; // (four already)
    Pad& p = g_pads[n];
    if (SDL_IsGameController(index)) p.pad = SDL_GameControllerOpen(index);
    p.joy = p.pad ? SDL_GameControllerGetJoystick(p.pad) : SDL_JoystickOpen(index);
    if (!p.joy) return;
    p.id = SDL_JoystickInstanceID(p.joy);
    p.fresh = true;
}

void pad_removed(SDL_JoystickID id) {
    for (int n = 0; n < VC_PADS; ++n) {
        Pad& p = g_pads[n];
        if (!p.joy || p.id != id) continue;
        if (p.pad) SDL_GameControllerClose(p.pad);
        else SDL_JoystickClose(p.joy);
        p = Pad();
        send_pad(n, false, 0, 0, nullptr);
    }
}

// Each pad's state now, sent if it has changed.
void poll_pads() {
    for (int n = 0; n < VC_PADS; ++n) {
        Pad& p = g_pads[n];
        if (!p.joy) continue;
        uint8_t s[8] = {};
        int axes = SDL_JoystickNumAxes(p.joy);
        if (p.pad) {
            s[VC_PAD_LX] = pad_axis(SDL_GameControllerGetAxis(p.pad, SDL_CONTROLLER_AXIS_LEFTX));
            s[VC_PAD_LY] = pad_axis(SDL_GameControllerGetAxis(p.pad, SDL_CONTROLLER_AXIS_LEFTY));
            s[VC_PAD_RX] = pad_axis(SDL_GameControllerGetAxis(p.pad, SDL_CONTROLLER_AXIS_RIGHTX));
            s[VC_PAD_RY] = pad_axis(SDL_GameControllerGetAxis(p.pad, SDL_CONTROLLER_AXIS_RIGHTY));
        } else { // (the right stick is the third and fourth axes: Z and Rz, as on Windows)
            for (int a = 0; a < 4 && a < axes; ++a) s[VC_PAD_LX + a] = pad_axis(SDL_JoystickGetAxis(p.joy, a));
        }
        int buttons = SDL_JoystickNumButtons(p.joy);
        for (int b = 0; b < 16 && b < buttons; ++b)
            if (SDL_JoystickGetButton(p.joy, b)) s[VC_PAD_BTN1 + b / 8] |= static_cast<uint8_t>(1 << (b % 8));
        if (SDL_JoystickNumHats(p.joy) > 0) {
            uint8_t hat = SDL_JoystickGetHat(p.joy, 0);
            s[VC_PAD_DPAD] = static_cast<uint8_t>(((hat & SDL_HAT_UP) ? VC_PAD_UP : 0) | ((hat & SDL_HAT_DOWN) ? VC_PAD_DOWN : 0) |
                                                  ((hat & SDL_HAT_LEFT) ? VC_PAD_LEFT : 0) | ((hat & SDL_HAT_RIGHT) ? VC_PAD_RIGHT : 0));
        } else { // (a simple pad's cross is its X and Y)
            int8_t lx = static_cast<int8_t>(s[VC_PAD_LX]), ly = static_cast<int8_t>(s[VC_PAD_LY]);
            s[VC_PAD_DPAD] = static_cast<uint8_t>((ly <= -64 ? VC_PAD_UP : 0) | (ly >= 64 ? VC_PAD_DOWN : 0) |
                                                  (lx <= -64 ? VC_PAD_LEFT : 0) | (lx >= 64 ? VC_PAD_RIGHT : 0));
        }
        if (p.fresh || std::memcmp(s, p.sent, sizeof(s)) != 0) {
            p.fresh = false;
            std::memcpy(p.sent, s, sizeof(s));
            send_pad(n, true, SDL_JoystickGetVendor(p.joy), SDL_JoystickGetProduct(p.joy), s);
        }
    }
}

// The keys that type no character, as a terminal sends them.
const char* key_sequence(SDL_Keycode k) {
    switch (k) {
    case SDLK_UP: return "\x1b[A";
    case SDLK_DOWN: return "\x1b[B";
    case SDLK_RIGHT: return "\x1b[C";
    case SDLK_LEFT: return "\x1b[D";
    case SDLK_HOME: return "\x1b[H";
    case SDLK_END: return "\x1b[F";
    case SDLK_INSERT: return "\x1b[2~";
    case SDLK_DELETE: return "\x1b[3~";
    case SDLK_PAGEUP: return "\x1b[5~";
    case SDLK_PAGEDOWN: return "\x1b[6~";
    default: return nullptr;
    }
}
} // namespace

int main(int argc, char** argv) {
    int scale = 1;
    for (int i = 1; i < argc; ++i)
        if (std::strcmp(argv[i], "--scale") == 0 && i + 1 < argc) scale = std::atoi(argv[++i]);
    if (scale < 1) scale = 1;

    SDL_SetHint(SDL_HINT_NO_SIGNAL_HANDLERS, "1"); // the emulator's terminal keys stay its own
    // The gamepads work whichever window has the focus (as on Windows), and through the kernel's
    // own drivers, which keep a pad's buttons in its own order -- SDL's drivers for some pads
    // would put them in SDL's.
    SDL_SetHint(SDL_HINT_JOYSTICK_ALLOW_BACKGROUND_EVENTS, "1");
    SDL_SetHint(SDL_HINT_JOYSTICK_HIDAPI, "0");
    if (SDL_Init(SDL_INIT_VIDEO) != 0) {
        std::fprintf(stderr, "\r\npugputer-video: no window: %s\r\n", SDL_GetError());
        return 1;
    }
    SDL_Window* win = SDL_CreateWindow("Pugputer 6309 - video", SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED,
                                       kW * scale, kH * scale, SDL_WINDOW_RESIZABLE);
    SDL_Renderer* ren = win ? SDL_CreateRenderer(win, -1, 0) : nullptr;
    // (RGB888 is SDL's 32-bit XRGB: the top byte, 0 here, isn't taken for alpha.)
    SDL_Texture* tex = ren ? SDL_CreateTexture(ren, SDL_PIXELFORMAT_RGB888, SDL_TEXTUREACCESS_STREAMING, kW, kH)
                           : nullptr;
    if (!tex) {
        std::fprintf(stderr, "\r\npugputer-video: no window: %s\r\n", SDL_GetError());
        SDL_Quit();
        return 1;
    }
    SDL_InitSubSystem(SDL_INIT_GAMECONTROLLER); // (without it, simply no gamepads)
    SDL_RenderSetLogicalSize(ren, kW, kH); // as big as fits, in the picture's own shape
    SDL_SetRenderDrawColor(ren, 0, 0, 0, 255);
    SDL_StartTextInput();
    std::thread(read_frames).detach();

    bool open = true, hidden = false;
    uint8_t buttons = 0;
    int mx = 0, my = 0; // where the mouse was last, in the picture's pixels
    while (open && !g_input_done) {
        if (hidden != g_hide_pointer) {
            hidden = g_hide_pointer;
            SDL_ShowCursor(hidden ? SDL_DISABLE : SDL_ENABLE);
        }
        SDL_Event e;
        bool got = SDL_WaitEventTimeout(&e, 5) != 0;
        while (got) {
            if (e.type == SDL_QUIT || (e.type == SDL_WINDOWEVENT && e.window.event == SDL_WINDOWEVENT_CLOSE)) {
                open = false;
            } else if (e.type == SDL_WINDOWEVENT && e.window.event == SDL_WINDOWEVENT_FOCUS_LOST) {
                // Gone to another window: no button is held here any more (a release there
                // would never reach us, and the program would go on drawing).
                if (buttons) send_mouse(mx, my, buttons = 0);
            } else if (e.type == SDL_WINDOWEVENT && e.window.event == SDL_WINDOWEVENT_ENTER) {
                // Back over the window: the buttons as they really are now.
                int wx, wy;
                uint8_t now = card_buttons(SDL_GetMouseState(&wx, &wy));
                float lx, ly;
                SDL_RenderWindowToLogical(ren, wx, wy, &lx, &ly);
                mx = static_cast<int>(lx);
                my = static_cast<int>(ly);
                if (now != buttons) send_mouse(mx, my, buttons = now);
            } else if (e.type == SDL_TEXTINPUT) {
                for (const char* s = e.text.text; *s; ++s)
                    if (static_cast<unsigned char>(*s) < 0x80) send(*s);
            } else if (e.type == SDL_KEYUP) {
                send_key(e.key.keysym.scancode, false);
            } else if (e.type == SDL_MOUSEMOTION) {
                // (In the picture's pixels: SDL_RenderSetLogicalSize has the renderer scale them.
                // The buttons as SDL has them, so one release we missed can't leave one held.)
                mx = e.motion.x;
                my = e.motion.y;
                buttons = card_buttons(e.motion.state);
                send_mouse(mx, my, buttons);
            } else if (e.type == SDL_MOUSEBUTTONDOWN || e.type == SDL_MOUSEBUTTONUP) {
                uint8_t bit = 0;
                if (e.button.button == SDL_BUTTON_LEFT) bit = 1;
                else if (e.button.button == SDL_BUTTON_RIGHT) bit = 2;
                else if (e.button.button == SDL_BUTTON_MIDDLE) bit = 4;
                buttons = static_cast<uint8_t>(e.type == SDL_MOUSEBUTTONDOWN ? buttons | bit : buttons & ~bit);
                mx = e.button.x;
                my = e.button.y;
                send_mouse(mx, my, buttons);
            } else if (e.type == SDL_MOUSEWHEEL) {
                int clicks = e.wheel.direction == SDL_MOUSEWHEEL_FLIPPED ? -e.wheel.y : e.wheel.y;
                if (clicks) {
                    const char rec[3] = {'\xFF', 'W', static_cast<char>(clicks)};
                    send(rec, sizeof(rec));
                }
            } else if (e.type == SDL_JOYDEVICEADDED) {
                pad_added(e.jdevice.which);
            } else if (e.type == SDL_JOYDEVICEREMOVED) {
                pad_removed(e.jdevice.which);
            } else if (e.type == SDL_KEYDOWN) {
                send_key(e.key.keysym.scancode, true);
                SDL_Keycode k = e.key.keysym.sym;
                if (k == SDLK_RETURN || k == SDLK_KP_ENTER) send('\r');
                else if (k == SDLK_BACKSPACE) send('\b');
                else if (k == SDLK_TAB) send('\t');
                else if (k == SDLK_ESCAPE) send('\x1b');
                else if ((e.key.keysym.mod & KMOD_CTRL) && k >= SDLK_a && k <= SDLK_z)
                    send(static_cast<char>(k - SDLK_a + 1));
                else if (const char* seq = key_sequence(k)) send(seq);
            }
            got = SDL_PollEvent(&e) != 0;
        }
        poll_pads();
        bool show = false;
        {
            std::lock_guard<std::mutex> g(g_lock);
            if (g_fresh) {
                SDL_UpdateTexture(tex, nullptr, g_frame.data(), kW * 4);
                g_fresh = false;
                show = true;
            }
        }
        if (show) {
            SDL_RenderClear(ren);
            SDL_RenderCopy(ren, tex, nullptr, nullptr);
            SDL_RenderPresent(ren);
        }
    }
    SDL_DestroyTexture(tex);
    SDL_DestroyRenderer(ren);
    SDL_DestroyWindow(win);
    SDL_Quit();
    std::_Exit(0); // (the reader thread may still be blocked in read)
}
