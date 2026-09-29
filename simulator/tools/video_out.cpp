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

// The window has a thread of its own: it shows `pixels` and fills `keys`.
struct VideoOut::Impl {
    std::thread thread;
    std::mutex lock;
    std::vector<uint32_t> pixels = std::vector<uint32_t>(static_cast<size_t>(kW) * kH);
    std::deque<uint8_t> keys;
    std::atomic<bool> closed{false};
    std::atomic<HWND> hwnd{nullptr};
    int scale = 1;

    void key(const char* s) {
        std::lock_guard<std::mutex> g(lock);
        while (*s) keys.push_back(static_cast<uint8_t>(*s++));
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
        // As big as fits, in the picture's own shape; black around it.
        int dw = cw, dh = cw * kH / kW;
        if (dh > ch) dh = ch, dw = ch * kW / kH;
        int dx = (cw - dw) / 2, dy = (ch - dh) / 2;
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
            std::lock_guard<std::mutex> g(self->lock);
            self->keys.push_back(static_cast<uint8_t>(wp));
        }
        return 0;
    case WM_KEYDOWN:
        if (self)
            if (const char* seq = key_sequence(wp)) self->key(seq);
        return 0;
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

bool VideoOut::poll_key(uint8_t& byte) {
    std::lock_guard<std::mutex> g(impl_->lock);
    if (impl_->keys.empty()) return false;
    byte = impl_->keys.front();
    impl_->keys.pop_front();
    return true;
}

#else // POSIX: the window is pugputer-video, another program (see pugputer_video.cpp)

struct VideoOut::Impl {
    pid_t pid = -1;
    int to = -1;   // frames go down this pipe ...
    int from = -1; // ... and keys come back up this one
    bool closed = false;
    std::deque<uint8_t> keys;
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

void VideoOut::show(const uint32_t* pixels) {
    if (impl_->to < 0) return;
    const char* p = reinterpret_cast<const char*>(pixels);
    size_t left = static_cast<size_t>(kW) * kH * sizeof(uint32_t);
    while (left > 0) {
        ssize_t n = write(impl_->to, p, left);
        if (n <= 0) { // the window is gone
            impl_->finish();
            return;
        }
        p += n;
        left -= static_cast<size_t>(n);
    }
}

bool VideoOut::poll_key(uint8_t& byte) {
    if (impl_->keys.empty() && impl_->from >= 0) {
        uint8_t buf[64];
        ssize_t n = read(impl_->from, buf, sizeof(buf));
        if (n > 0) impl_->keys.insert(impl_->keys.end(), buf, buf + n);
        else if (n == 0) impl_->finish(); // the window was closed
    }
    if (impl_->keys.empty()) return false;
    byte = impl_->keys.front();
    impl_->keys.pop_front();
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
