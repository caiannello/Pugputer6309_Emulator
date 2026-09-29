// pugputer-video: the video card's window for the emulator on Linux (and other POSIX systems).
// The emulator is linked fully statically so that it runs on any Linux; a window needs SDL2,
// which can't be, so it lives in this separate program -- the way the emulator's sound goes
// to aplay. The emulator starts it (video_out.cpp) and talks to it through two pipes:
//
//   stdin   frames, one after another: 640x480 pixels, 4 bytes each (0x00RRGGBB, little-endian
//           -- as the emulator holds them), rows top first
//   stdout  what is typed into the window, as a terminal sends it
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

namespace {
constexpr int kW = 640, kH = 480;
constexpr size_t kFrameBytes = static_cast<size_t>(kW) * kH * 4;

std::mutex g_lock;
std::vector<uint8_t> g_frame(kFrameBytes);
bool g_fresh = false;
std::atomic<bool> g_input_done{false};

// Reads frames from stdin as they come; the newest one is shown.
void read_frames() {
    std::vector<uint8_t> buf(kFrameBytes);
    for (;;) {
        size_t got = 0;
        while (got < kFrameBytes) {
            ssize_t n = read(STDIN_FILENO, buf.data() + got, kFrameBytes - got);
            if (n <= 0) {
                g_input_done = true;
                return;
            }
            got += static_cast<size_t>(n);
        }
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
    SDL_RenderSetLogicalSize(ren, kW, kH); // as big as fits, in the picture's own shape
    SDL_SetRenderDrawColor(ren, 0, 0, 0, 255);
    SDL_StartTextInput();
    std::thread(read_frames).detach();

    bool open = true;
    while (open && !g_input_done) {
        SDL_Event e;
        bool got = SDL_WaitEventTimeout(&e, 5) != 0;
        while (got) {
            if (e.type == SDL_QUIT || (e.type == SDL_WINDOWEVENT && e.window.event == SDL_WINDOWEVENT_CLOSE)) {
                open = false;
            } else if (e.type == SDL_TEXTINPUT) {
                for (const char* s = e.text.text; *s; ++s)
                    if (static_cast<unsigned char>(*s) < 0x80) send(*s);
            } else if (e.type == SDL_KEYDOWN) {
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
