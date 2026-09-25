#include "pugputer/com_port_bridge.hpp"

#include "pugputer/uart_r65c51.hpp"

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#else
#include <cerrno>
#include <cstdlib>
#include <cstring>
#include <fcntl.h>
#include <poll.h>
#include <termios.h>
#include <unistd.h>
#endif

namespace pugputer {

ComPortBridge::ComPortBridge() = default;

ComPortBridge::~ComPortBridge() {
    close();
}

#ifdef _WIN32

bool ComPortBridge::open(const std::string& port_name, unsigned baud_rate) {
    close();

    // The "\\.\" prefix is required for COM10+ and harmless for COM1-9.
    std::string full_name = "\\\\.\\" + port_name;
    HANDLE h = CreateFileA(full_name.c_str(), GENERIC_READ | GENERIC_WRITE, 0, nullptr, OPEN_EXISTING, 0, nullptr);
    if (h == INVALID_HANDLE_VALUE) {
        last_error_ = "CreateFileA(\"" + full_name + "\") failed, GetLastError=" + std::to_string(GetLastError());
        return false;
    }

    DCB dcb{};
    dcb.DCBlength = sizeof(dcb);
    if (!GetCommState(h, &dcb)) {
        last_error_ = "GetCommState failed, GetLastError=" + std::to_string(GetLastError());
        CloseHandle(h);
        return false;
    }
    dcb.BaudRate = baud_rate;
    dcb.ByteSize = 8;
    dcb.Parity = NOPARITY;
    dcb.StopBits = ONESTOPBIT;
    dcb.fBinary = TRUE;
    dcb.fParity = FALSE;
    dcb.fOutxCtsFlow = FALSE;
    dcb.fOutxDsrFlow = FALSE;
    dcb.fDtrControl = DTR_CONTROL_ENABLE;
    dcb.fRtsControl = RTS_CONTROL_ENABLE;
    if (!SetCommState(h, &dcb)) {
        last_error_ = "SetCommState failed, GetLastError=" + std::to_string(GetLastError());
        CloseHandle(h);
        return false;
    }

    // Non-blocking-ish reads: ReadFile returns immediately with whatever
    // bytes are already available (possibly zero) instead of waiting.
    COMMTIMEOUTS timeouts{};
    timeouts.ReadIntervalTimeout = MAXDWORD;
    timeouts.ReadTotalTimeoutConstant = 0;
    timeouts.ReadTotalTimeoutMultiplier = 0;
    timeouts.WriteTotalTimeoutConstant = 1000; // don't hang forever if the peer stalls
    timeouts.WriteTotalTimeoutMultiplier = 0;
    if (!SetCommTimeouts(h, &timeouts)) {
        last_error_ = "SetCommTimeouts failed, GetLastError=" + std::to_string(GetLastError());
        CloseHandle(h);
        return false;
    }

    handle_ = h;
    device_name_ = port_name;
    last_error_.clear();
    return true;
}

void ComPortBridge::close() {
    if (handle_) {
        CloseHandle(static_cast<HANDLE>(handle_));
        handle_ = nullptr;
    }
}

void ComPortBridge::poll(UartR65C51& uart) {
    if (!handle_) return;
    HANDLE h = static_cast<HANDLE>(handle_);

    uint8_t in_buf[256];
    DWORD read = 0;
    if (ReadFile(h, in_buf, sizeof(in_buf), &read, nullptr) && read > 0) {
        for (DWORD i = 0; i < read; ++i) uart.rx_enqueue(in_buf[i]);
    }

    uint8_t out_buf[256];
    DWORD n = 0;
    uint8_t byte;
    while (n < sizeof(out_buf) && uart.tx_dequeue(byte)) {
        out_buf[n++] = byte;
    }
    if (n > 0) {
        DWORD written = 0;
        WriteFile(h, out_buf, n, &written, nullptr);
    }
}

#else // POSIX

namespace {
speed_t to_speed(unsigned baud_rate) {
    switch (baud_rate) {
    case 300: return B300;
    case 1200: return B1200;
    case 2400: return B2400;
    case 4800: return B4800;
    case 9600: return B9600;
    case 38400: return B38400;
    case 57600: return B57600;
    case 115200: return B115200;
    default: return B19200;
    }
}

// Raw 8N1: no line editing, echo, signals or newline translation either way.
bool make_raw(int fd, unsigned baud_rate) {
    termios tio{};
    if (tcgetattr(fd, &tio) != 0) return false;
    cfmakeraw(&tio);
    tio.c_cflag |= CLOCAL | CREAD;
    tio.c_cflag &= ~(CSTOPB | PARENB);
#ifdef CRTSCTS
    tio.c_cflag &= ~CRTSCTS;
#endif
    tio.c_cc[VMIN] = 0;
    tio.c_cc[VTIME] = 0;
    cfsetispeed(&tio, to_speed(baud_rate));
    cfsetospeed(&tio, to_speed(baud_rate));
    return tcsetattr(fd, TCSANOW, &tio) == 0;
}
} // namespace

bool ComPortBridge::open(const std::string& port_name, unsigned baud_rate) {
    close();

    if (port_name == "pty") {
        int master = posix_openpt(O_RDWR | O_NOCTTY);
        if (master < 0 || grantpt(master) != 0 || unlockpt(master) != 0) {
            last_error_ = std::string("could not create a pseudo-terminal: ") + std::strerror(errno);
            if (master >= 0) ::close(master);
            return false;
        }
        const char* slave_name = ptsname(master);
        // Holding the slave side open keeps the pair alive while no terminal is attached:
        // the machine's output waits there (and a reader that comes and goes doesn't
        // make the master side fail with EIO).
        int slave = slave_name ? ::open(slave_name, O_RDWR | O_NOCTTY) : -1;
        if (slave < 0 || !make_raw(slave, baud_rate)) {
            last_error_ = std::string("could not set up the pseudo-terminal: ") + std::strerror(errno);
            if (slave >= 0) ::close(slave);
            ::close(master);
            return false;
        }
        fcntl(master, F_SETFL, fcntl(master, F_GETFL) | O_NONBLOCK);
        fd_ = master;
        pty_slave_fd_ = slave;
        device_name_ = slave_name;
    } else {
        std::string path = port_name.find('/') == std::string::npos ? "/dev/" + port_name : port_name;
        int fd = ::open(path.c_str(), O_RDWR | O_NOCTTY | O_NONBLOCK);
        if (fd < 0) {
            last_error_ = "open(\"" + path + "\") failed: " + std::strerror(errno);
            return false;
        }
        if (!isatty(fd) || !make_raw(fd, baud_rate)) {
            last_error_ = path + " is not a serial port (could not set 8N1 raw mode)";
            ::close(fd);
            return false;
        }
        fd_ = fd;
        device_name_ = path;
    }
    write_stalled_ = false;
    last_error_.clear();
    return true;
}

void ComPortBridge::close() {
    if (fd_ >= 0) {
        ::close(fd_);
        fd_ = -1;
    }
    if (pty_slave_fd_ >= 0) {
        ::close(pty_slave_fd_);
        pty_slave_fd_ = -1;
    }
}

void ComPortBridge::poll(UartR65C51& uart) {
    if (fd_ < 0) return;

    uint8_t in_buf[256];
    ssize_t got = ::read(fd_, in_buf, sizeof(in_buf));
    for (ssize_t i = 0; i < got; ++i) uart.rx_enqueue(in_buf[i]);

    uint8_t out_buf[256];
    size_t n = 0;
    uint8_t byte;
    while (n < sizeof(out_buf) && uart.tx_dequeue(byte)) {
        out_buf[n++] = byte;
    }
    // Like the Windows version's one-second write timeout: wait for a slow port to take
    // the bytes, but not forever -- and once a wait has timed out (nothing is reading),
    // drop output rather than slowing the emulator down, until a write gets through.
    size_t done = 0;
    while (done < n) {
        ssize_t w = ::write(fd_, out_buf + done, n - done);
        if (w > 0) {
            done += static_cast<size_t>(w);
            write_stalled_ = false;
        } else if (w < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) && !write_stalled_) {
            pollfd p{fd_, POLLOUT, 0};
            if (::poll(&p, 1, 1000) <= 0) write_stalled_ = true;
        } else if (w < 0 && errno == EINTR) {
            continue;
        } else {
            break;
        }
    }
}

#endif

} // namespace pugputer
