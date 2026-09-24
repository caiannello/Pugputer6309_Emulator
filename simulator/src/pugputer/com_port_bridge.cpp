#include "pugputer/com_port_bridge.hpp"

#include "pugputer/uart_r65c51.hpp"

#define WIN32_LEAN_AND_MEAN
#include <windows.h>

namespace pugputer {

ComPortBridge::ComPortBridge() = default;

ComPortBridge::~ComPortBridge() {
    close();
}

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

} // namespace pugputer
