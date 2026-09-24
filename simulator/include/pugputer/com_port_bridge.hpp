// Bridges a UartR65C51 to a real (or com0com-virtual) Windows COM port.
// Windows-only; only compiled when PUGPUTER_BUILD_COM_BRIDGE is enabled
// (see simulator/CMakeLists.txt). Deliberately has no background thread:
// poll() is meant to be called periodically from the host's own loop
// (e.g. once per SystemBus::run() batch), which keeps this
// concurrency-free.
//
// To use with com0com: install com0com, create a port pair (e.g.
// CNCA0<->CNCB0, which Windows exposes as COM10/COM11 by default -- see
// simulator/README.md), point this bridge at one end (open("COM10")) and
// a terminal program (PuTTY, TeraTerm, ...) at the other (COM11).
#pragma once

#include <cstdint>
#include <string>

namespace pugputer {

class UartR65C51;

class ComPortBridge {
public:
    ComPortBridge();
    ~ComPortBridge();
    ComPortBridge(const ComPortBridge&) = delete;
    ComPortBridge& operator=(const ComPortBridge&) = delete;

    // port_name is a bare name like "COM10" (the "\\\\.\\" prefix needed
    // for COM ports above 9 is added internally). Returns false on
    // failure (port doesn't exist, already in use, etc) -- check
    // last_error() for a message.
    bool open(const std::string& port_name, unsigned baud_rate = 19200);
    void close();
    bool is_open() const { return handle_ != nullptr; }
    const std::string& last_error() const { return last_error_; }

    // Pumps host<->UART bytes: drains anything waiting on the COM port
    // into uart.rx_enqueue(), and writes out anything uart.tx_dequeue()
    // has ready. Non-blocking (reads return immediately with whatever is
    // available, possibly nothing).
    void poll(UartR65C51& uart);

private:
    void* handle_ = nullptr; // HANDLE, kept opaque so <windows.h> doesn't leak into this header
    std::string last_error_;
};

} // namespace pugputer
