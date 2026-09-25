// Bridges a UartR65C51 to a serial port: a real (or com0com-virtual) COM
// port on Windows, a tty device or a fresh pseudo-terminal on Linux and
// other POSIX systems. Only compiled when PUGPUTER_BUILD_COM_BRIDGE is
// enabled (see simulator/CMakeLists.txt). Deliberately has no background
// thread: poll() is meant to be called periodically from the host's own
// loop (e.g. once per SystemBus::run() batch), which keeps this
// concurrency-free.
//
// To use with com0com: install com0com, create a port pair (e.g.
// CNCA0<->CNCB0, which Windows exposes as COM10/COM11 by default -- see
// simulator/README.md), point this bridge at one end (open("COM10")) and
// a terminal program (PuTTY, TeraTerm, ...) at the other (COM11).
//
// On POSIX, open("pty") needs no extra software: it creates a
// pseudo-terminal and device_name() is the path (e.g. /dev/pts/3) to point
// a terminal program (screen, picocom, minicom, ...) at.
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

    // Windows: port_name is a bare name like "COM10" (the "\\\\.\\" prefix
    // needed for COM ports above 9 is added internally).
    // POSIX: a device path like "/dev/ttyUSB0" ("ttyUSB0" gets "/dev/"
    // added), or "pty" for a new pseudo-terminal.
    // Returns false on failure (port doesn't exist, already in use, etc)
    // -- check last_error() for a message.
    bool open(const std::string& port_name, unsigned baud_rate = 19200);
    void close();
    bool is_open() const { return handle_ != nullptr || fd_ >= 0; }
    const std::string& last_error() const { return last_error_; }
    // The device the other end should open: the pseudo-terminal's path
    // after open("pty"), otherwise the port that was opened.
    const std::string& device_name() const { return device_name_; }

    // Pumps host<->UART bytes: drains anything waiting on the COM port
    // into uart.rx_enqueue(), and writes out anything uart.tx_dequeue()
    // has ready. Non-blocking (reads return immediately with whatever is
    // available, possibly nothing).
    void poll(UartR65C51& uart);

private:
    void* handle_ = nullptr; // Windows: HANDLE, kept opaque so <windows.h> doesn't leak into this header
    int fd_ = -1;            // POSIX: the port, or the pseudo-terminal's master side
    int pty_slave_fd_ = -1;  // POSIX, "pty" only: held open so output waits there until a terminal attaches
    bool write_stalled_ = false; // POSIX: the last write timed out; don't wait again until one gets through
    std::string device_name_;
    std::string last_error_;
};

} // namespace pugputer
