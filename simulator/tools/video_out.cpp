#include "video_out.hpp"

#include <atomic>
#include <cstdio>
#include <cstring>
#include <deque>
#include <mutex>
#include <thread>
#include <vector>

#ifdef _WIN32
#ifndef NOMINMAX
#define NOMINMAX
#endif
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include <mmsystem.h>
#else
#include <climits>
#include <csignal>
#include <fcntl.h>
#include <string>
#include <sys/wait.h>
#include <unistd.h>
#endif

namespace {
constexpr int kW = pugputer::VideoDevice::kWidth, kH = pugputer::VideoDevice::kHeight;
constexpr auto kFrame = std::chrono::microseconds(16667);
} // namespace

#ifdef _WIN32

// The window has a thread of its own: it shows `pixels` and fills `input`.
struct VideoOut::Impl {
    std::thread thread;
    std::mutex lock;
    std::vector<uint32_t> pixels = std::vector<uint32_t>(static_cast<size_t>(kW) * kH);
    std::deque<Input> input;
    std::atomic<bool> closed{false};
    std::atomic<bool> hide_pointer{false};
    std::atomic<HWND> hwnd{nullptr};
    int scale = 1;
    uint8_t buttons = 0; // (the window's thread only)

    void push(const Input& in) {
        std::lock_guard<std::mutex> g(lock);
        input.push_back(in);
    }
    void chars(const char* s) {
        Input in;
        for (; *s; ++s) {
            in.code = static_cast<uint8_t>(*s);
            push(in);
        }
    }
    void run();
};

namespace {
// The keys that type no character, as a terminal sends them.
const char* key_sequence(WPARAM vk) {
    switch (vk) {
    case VK_UP: return "\x1b[A";
    case VK_DOWN: return "\x1b[B";
    case VK_RIGHT: return "\x1b[C";
    case VK_LEFT: return "\x1b[D";
    case VK_HOME: return "\x1b[H";
    case VK_END: return "\x1b[F";
    case VK_INSERT: return "\x1b[2~";
    case VK_DELETE: return "\x1b[3~";
    case VK_PRIOR: return "\x1b[5~";
    case VK_NEXT: return "\x1b[6~";
    default: return nullptr;
    }
}

// A key's USB HID usage code (what the card takes) from its PC scan code (set 1, as a key
// message's lParam carries it, bit 24 the E0 prefix). 0: none.
uint8_t usage_of(LPARAM lp) {
    static const uint8_t plain[0x59] = {
        0,    0x29, 0x1E, 0x1F, 0x20, 0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x2D, 0x2E, 0x2A, 0x2B, // 00
        0x14, 0x1A, 0x08, 0x15, 0x17, 0x1C, 0x18, 0x0C, 0x12, 0x13, 0x2F, 0x30, 0x28, 0xE0, 0x04, 0x16, // 10
        0x07, 0x09, 0x0A, 0x0B, 0x0D, 0x0E, 0x0F, 0x33, 0x34, 0x35, 0xE1, 0x31, 0x1D, 0x1B, 0x06, 0x19, // 20
        0x05, 0x11, 0x10, 0x36, 0x37, 0x38, 0xE5, 0x55, 0xE2, 0x2C, 0x39, 0x3A, 0x3B, 0x3C, 0x3D, 0x3E, // 30
        0x3F, 0x40, 0x41, 0x42, 0x43, 0x48, 0x47, 0x5F, 0x60, 0x61, 0x56, 0x5C, 0x5D, 0x5E, 0x57, 0x59, // 40
        0x5A, 0x5B, 0x62, 0x63, 0,    0,    0x64, 0x44, 0x45};                                          // 50
    unsigned sc = (lp >> 16) & 0xFF;
    if (!(lp & (1 << 24))) return sc < sizeof(plain) ? plain[sc] : 0;
    switch (sc) { // after E0
    case 0x1C: return 0x58; // keypad Enter
    case 0x1D: return 0xE4; // right Ctrl
    case 0x35: return 0x54; // keypad /
    case 0x37: return 0x46; // Print Screen
    case 0x38: return 0xE6; // right Alt
    case 0x45: return 0x53; // Num Lock (without the E0, Pause)
    case 0x47: return 0x4A; // Home
    case 0x48: return 0x52; // Up
    case 0x49: return 0x4B; // Page Up
    case 0x4B: return 0x50; // Left
    case 0x4D: return 0x4F; // Right
    case 0x4F: return 0x4D; // End
    case 0x50: return 0x51; // Down
    case 0x51: return 0x4E; // Page Down
    case 0x52: return 0x49; // Insert
    case 0x53: return 0x4C; // Delete
    case 0x5B: return 0xE3; // left Windows
    case 0x5C: return 0xE7; // right Windows
    case 0x5D: return 0x65; // Menu
    default: return 0;
    }
}

// Where the picture is in the client area: as big as fits, in its own shape.
RECT picture_rect(HWND hwnd) {
    RECT r;
    GetClientRect(hwnd, &r);
    int cw = r.right, ch = r.bottom;
    int dw = cw, dh = cw * kH / kW;
    if (dh > ch) dh = ch, dw = ch * kW / kH;
    int dx = (cw - dw) / 2, dy = (ch - dh) / 2;
    return RECT{dx, dy, dx + dw, dy + dh};
}

LRESULT CALLBACK window_proc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
    auto* self = reinterpret_cast<VideoOut::Impl*>(GetWindowLongPtrA(hwnd, GWLP_USERDATA));
    switch (msg) {
    case WM_NCCREATE:
        SetWindowLongPtrA(hwnd, GWLP_USERDATA,
                          reinterpret_cast<LONG_PTR>(reinterpret_cast<CREATESTRUCTA*>(lp)->lpCreateParams));
        break;
    case WM_ERASEBKGND:
        return 1;
    case WM_SIZE:
        InvalidateRect(hwnd, nullptr, FALSE);
        return 0;
    case WM_PAINT: {
        PAINTSTRUCT ps;
        HDC dc = BeginPaint(hwnd, &ps);
        RECT r;
        GetClientRect(hwnd, &r);
        int cw = r.right, ch = r.bottom;
        RECT p = picture_rect(hwnd); // black around it
        int dx = p.left, dy = p.top, dw = p.right - p.left, dh = p.bottom - p.top;
        PatBlt(dc, 0, 0, cw, dy, BLACKNESS);
        PatBlt(dc, 0, dy + dh, cw, ch - dy - dh, BLACKNESS);
        PatBlt(dc, 0, dy, dx, dh, BLACKNESS);
        PatBlt(dc, dx + dw, dy, cw - dx - dw, dh, BLACKNESS);
        BITMAPINFO bmi{};
        bmi.bmiHeader.biSize = sizeof(bmi.bmiHeader);
        bmi.bmiHeader.biWidth = kW;
        bmi.bmiHeader.biHeight = -kH; // top row first
        bmi.bmiHeader.biPlanes = 1;
        bmi.bmiHeader.biBitCount = 32;
        bmi.bmiHeader.biCompression = BI_RGB;
        SetStretchBltMode(dc, COLORONCOLOR);
        if (self) {
            std::lock_guard<std::mutex> g(self->lock);
            StretchDIBits(dc, dx, dy, dw, dh, 0, 0, kW, kH, self->pixels.data(), &bmi, DIB_RGB_COLORS, SRCCOPY);
        }
        EndPaint(hwnd, &ps);
        return 0;
    }
    case WM_CHAR:
        if (self && wp < 0x80) {
            VideoOut::Input in;
            in.code = static_cast<uint8_t>(wp);
            self->push(in);
        }
        return 0;
    case WM_KEYDOWN:
    case WM_KEYUP:
    case WM_SYSKEYDOWN:
    case WM_SYSKEYUP:
        if (self) {
            bool down = msg == WM_KEYDOWN || msg == WM_SYSKEYDOWN;
            if (uint8_t u = usage_of(lp)) {
                VideoOut::Input in;
                in.kind = VideoOut::Input::Key;
                in.code = u;
                in.down = down;
                self->push(in);
            }
            if (msg == WM_KEYDOWN)
                if (const char* seq = key_sequence(wp)) self->chars(seq);
        }
        if (msg == WM_KEYDOWN || msg == WM_KEYUP) return 0;
        break; // (Alt+F4 and the like)
    case WM_MOUSEMOVE:
    case WM_LBUTTONDOWN:
    case WM_LBUTTONUP:
    case WM_RBUTTONDOWN:
    case WM_RBUTTONUP:
    case WM_MBUTTONDOWN:
    case WM_MBUTTONUP:
        if (self) {
            uint8_t b = static_cast<uint8_t>(((wp & MK_LBUTTON) ? 1 : 0) | ((wp & MK_RBUTTON) ? 2 : 0) |
                                             ((wp & MK_MBUTTON) ? 4 : 0));
            if (b && !self->buttons) SetCapture(hwnd); // a drag goes on outside the window
            if (!b && self->buttons) ReleaseCapture();
            self->buttons = b;
            RECT p = picture_rect(hwnd);
            int w = p.right - p.left, h = p.bottom - p.top;
            if (w > 0 && h > 0) {
                VideoOut::Input in;
                in.kind = VideoOut::Input::Mouse;
                in.x = (static_cast<short>(LOWORD(lp)) - p.left) * kW / w;
                in.y = (static_cast<short>(HIWORD(lp)) - p.top) * kH / h;
                in.buttons = b;
                self->push(in);
            }
        }
        return 0;
    case WM_MOUSEWHEEL:
        if (self) {
            VideoOut::Input in;
            in.kind = VideoOut::Input::Wheel;
            in.clicks = GET_WHEEL_DELTA_WPARAM(wp) / WHEEL_DELTA;
            if (in.clicks) self->push(in);
        }
        return 0;
    case WM_SETCURSOR:
        if (self && self->hide_pointer && LOWORD(lp) == HTCLIENT) {
            SetCursor(nullptr);
            return TRUE;
        }
        break;
    case WM_CLOSE:
        DestroyWindow(hwnd);
        return 0;
    case WM_DESTROY:
        PostQuitMessage(0);
        return 0;
    }
    return DefWindowProcA(hwnd, msg, wp, lp);
}
} // namespace

void VideoOut::Impl::run() {
    timeBeginPeriod(1); // for pacing to 1/60 s
    WNDCLASSA wc{};
    wc.lpfnWndProc = window_proc;
    wc.hInstance = GetModuleHandleA(nullptr);
    wc.lpszClassName = "PugputerVideo";
    wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
    RegisterClassA(&wc);
    RECT r{0, 0, kW * scale, kH * scale};
    AdjustWindowRect(&r, WS_OVERLAPPEDWINDOW, FALSE);
    HWND h = CreateWindowExA(0, wc.lpszClassName, "Pugputer 6309 - video", WS_OVERLAPPEDWINDOW, CW_USEDEFAULT,
                             CW_USEDEFAULT, r.right - r.left, r.bottom - r.top, nullptr, nullptr, wc.hInstance, this);
    if (h) {
        hwnd = h;
        ShowWindow(h, SW_SHOWNOACTIVATE); // the typing stays where it was
        MSG m;
        while (GetMessageA(&m, nullptr, 0, 0) > 0) {
            TranslateMessage(&m);
            DispatchMessageA(&m);
        }
        hwnd = nullptr;
    }
    closed = true;
    timeEndPeriod(1);
}

VideoOut::VideoOut() : impl_(new Impl) {}

VideoOut::~VideoOut() {
    if (impl_->thread.joinable()) {
        if (HWND h = impl_->hwnd) PostMessageA(h, WM_CLOSE, 0, 0);
        impl_->thread.join();
    }
}

bool VideoOut::closed() const { return impl_->closed; }

void VideoOut::open() {
    impl_->scale = scale_;
    impl_->thread = std::thread([this] { impl_->run(); });
}

void VideoOut::show(const uint32_t* pixels) {
    {
        std::lock_guard<std::mutex> g(impl_->lock);
        std::memcpy(impl_->pixels.data(), pixels, impl_->pixels.size() * sizeof(uint32_t));
    }
    if (HWND h = impl_->hwnd) InvalidateRect(h, nullptr, FALSE);
}

bool VideoOut::poll(Input& in) {
    std::lock_guard<std::mutex> g(impl_->lock);
    if (impl_->input.empty()) return false;
    in = impl_->input.front();
    impl_->input.pop_front();
    return true;
}

void VideoOut::set_pointer_hidden(bool hidden) { impl_->hide_pointer = hidden; }

#else // POSIX: the window is pugputer-video, another program (see pugputer_video.cpp)

struct VideoOut::Impl {
    pid_t pid = -1;
    int to = -1;   // frames go down this pipe ...
    int from = -1; // ... and what is done in the window comes back up this one
    bool closed = false;
    bool hide_pointer = false;
    std::vector<uint8_t> got; // from it, not yet made into input
    std::deque<Input> input;
    void finish() {
        if (to >= 0) close(to);
        if (from >= 0) close(from);
        to = from = -1;
        if (pid > 0) waitpid(pid, nullptr, 0);
        pid = -1;
        closed = true;
    }
};

namespace {
// pugputer-video beside this program.
std::string helper_path() {
    char path[PATH_MAX] = {0};
    ssize_t n = readlink("/proc/self/exe", path, sizeof(path) - 1);
    std::string p = n > 0 ? std::string(path, static_cast<size_t>(n)) : std::string();
    size_t slash = p.find_last_of('/');
    return (slash == std::string::npos ? std::string(".") : p.substr(0, slash)) + "/pugputer-video";
}
} // namespace

VideoOut::VideoOut() : impl_(new Impl) {}

VideoOut::~VideoOut() { impl_->finish(); }

bool VideoOut::closed() const { return impl_->closed; }

void VideoOut::open() {
    std::string path = helper_path();
    int down[2], up[2];
    if (pipe(down) != 0) {
        impl_->closed = true;
        return;
    }
    if (pipe(up) != 0) {
        close(down[0]);
        close(down[1]);
        impl_->closed = true;
        return;
    }
    std::signal(SIGPIPE, SIG_IGN); // a window that closes must not take the emulator with it
    std::string scale = std::to_string(scale_);
    pid_t pid = fork();
    if (pid == 0) {
        dup2(down[0], STDIN_FILENO);
        dup2(up[1], STDOUT_FILENO);
        close(down[0]);
        close(down[1]);
        close(up[0]);
        close(up[1]);
        execl(path.c_str(), "pugputer-video", "--scale", scale.c_str(), static_cast<char*>(nullptr));
        std::fprintf(stderr, "\r\nNo video window: %s isn't there (it is built along with the emulator when SDL2's "
                             "development files are installed: sudo apt install libsdl2-dev).\r\n",
                     path.c_str());
        _exit(127);
    }
    close(down[0]);
    close(up[1]);
    if (pid < 0) {
        close(down[1]);
        close(up[0]);
        impl_->closed = true;
        return;
    }
    impl_->pid = pid;
    impl_->to = down[1];
    impl_->from = up[0];
    fcntl(impl_->to, F_SETFD, FD_CLOEXEC);
    fcntl(impl_->from, F_SETFD, FD_CLOEXEC);
    fcntl(impl_->from, F_SETFL, fcntl(impl_->from, F_GETFL) | O_NONBLOCK);
}

namespace {
// All of it down the pipe; false if the window has gone.
bool write_all(int fd, const char* p, size_t left) {
    while (left > 0) {
        ssize_t n = write(fd, p, left);
        if (n <= 0) return false;
        p += n;
        left -= static_cast<size_t>(n);
    }
    return true;
}
} // namespace

void VideoOut::show(const uint32_t* pixels) {
    if (impl_->to < 0) return;
    // Each frame: a 4-byte header ('F', flags: bit 0 hide the pointer, 0, 0), then the pixels.
    const char header[4] = {'F', static_cast<char>(impl_->hide_pointer ? 1 : 0), 0, 0};
    if (!write_all(impl_->to, header, sizeof(header)) ||
        !write_all(impl_->to, reinterpret_cast<const char*>(pixels), static_cast<size_t>(kW) * kH * sizeof(uint32_t)))
        impl_->finish(); // the window is gone
}

void VideoOut::set_pointer_hidden(bool hidden) { impl_->hide_pointer = hidden; }

// What pugputer-video sends (see pugputer_video.cpp): characters typed, below $80, and
// $FF-prefixed records -- 'K' usage down, 'M' x(2) y(2) buttons, 'W' clicks -- of the keys and
// the mouse.
bool VideoOut::poll(Input& in) {
    if (impl_->input.empty() && impl_->from >= 0) {
        uint8_t buf[256];
        ssize_t n = read(impl_->from, buf, sizeof(buf));
        if (n > 0) {
            std::vector<uint8_t>& g = impl_->got;
            g.insert(g.end(), buf, buf + n);
            size_t i = 0;
            while (i < g.size()) {
                Input e;
                if (g[i] != 0xFF) {
                    e.code = g[i++];
                } else {
                    if (i + 1 >= g.size()) break;
                    uint8_t kind = g[i + 1];
                    size_t len = kind == 'K' ? 4 : kind == 'M' ? 7 : kind == 'W' ? 3 : 2;
                    if (i + len > g.size()) break; // the rest is still on its way
                    const uint8_t* r = g.data() + i + 2;
                    i += len;
                    if (kind == 'K') {
                        e.kind = Input::Key;
                        e.code = r[0];
                        e.down = r[1] != 0;
                    } else if (kind == 'M') {
                        e.kind = Input::Mouse;
                        e.x = static_cast<int16_t>(r[0] << 8 | r[1]);
                        e.y = static_cast<int16_t>(r[2] << 8 | r[3]);
                        e.buttons = r[4];
                    } else if (kind == 'W') {
                        e.kind = Input::Wheel;
                        e.clicks = static_cast<int8_t>(r[0]);
                    } else {
                        continue;
                    }
                }
                impl_->input.push_back(e);
            }
            g.erase(g.begin(), g.begin() + static_cast<std::ptrdiff_t>(i));
        } else if (n == 0) {
            impl_->finish(); // the window was closed
        }
    }
    if (impl_->input.empty()) return false;
    in = impl_->input.front();
    impl_->input.pop_front();
    return true;
}

#endif

bool VideoOut::wants_frame() {
    if (closed()) return false;
    if (!turbo_) return true;
    return std::chrono::steady_clock::now() - shown_ >= kFrame;
}

void VideoOut::frame(const uint32_t* pixels) {
    if (!opened_) {
        opened_ = true;
        open();
    }
    if (closed()) return;
    auto now = std::chrono::steady_clock::now();
    if (pixels) {
        show(pixels);
        shown_ = now;
    }
    if (turbo_) return;
    // A frame each 1/60 s: the emulator waits for its time. (Far behind -- a slow moment on
    // the PC -- it starts counting again from now instead of hurrying to catch up.)
    if (now - next_ > std::chrono::milliseconds(100)) next_ = now;
    next_ += kFrame;
    if (next_ > now) std::this_thread::sleep_until(next_);
}
