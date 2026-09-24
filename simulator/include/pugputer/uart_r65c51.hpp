// R65C51 ACIA-compatible UART, register-exact against
// Claude_Readme/Pugputer6309_CPU_Card/R65C51_text.txt and validated
// against the real driver in bios/serio.asm. See simulator/README.md for
// the documented simplifications (DCD/DSR don't drive IRQ; SBR=0000
// "external clock" mode is unsupported; TIC=00 doesn't actually gate the
// transmitter, only the TDRE-IRQ).
//
// The UART has its own fixed 1.8432MHz crystal (independent of the CPU
// clock) driving its internal baud-rate generator, matching the real
// Pugputer6309 hardware. cpu_clock_hz (settable, defaults to the
// Pugputer6309's 14.318MHz/4 = 3,579,545 Hz) is only used to convert
// "CPU cycles elapsed" (from tick()) into "UART character time elapsed"
// for pacing TDRE/RDRF against the configured baud rate.
#pragma once

#include <cstdint>
#include <deque>
#include <functional>

#include "pugputer/device.hpp"

namespace pugputer {

class UartR65C51 : public IDevice {
public:
    explicit UartR65C51(double uart_crystal_hz = 1843200.0);

    // IDevice
    uint8_t read(uint16_t offset) override;
    void write(uint16_t offset, uint8_t value) override;
    void reset() override;
    void tick(uint32_t cpu_cycles) override;
    bool irq_asserted() const override { return irq_flag_; }

    // --- host-facing byte I/O -------------------------------------------
    // Host -> UART: a byte "arriving on the wire". Returns false if the
    // internal not-yet-arrived queue is full (very large; this should
    // only happen if the host force-feeds bytes far faster than the
    // configured baud rate for a long time without the CPU ever reading).
    bool rx_enqueue(uint8_t byte);

    // UART -> host: pops one byte the UART has finished transmitting, if
    // any. Returns false if nothing is pending. Usable instead of, or
    // alongside, set_tx_callback() -- every transmitted byte goes to
    // both if both are in use.
    bool tx_dequeue(uint8_t& out);
    using TxCallback = std::function<void(uint8_t)>;
    void set_tx_callback(TxCallback cb) { tx_cb_ = std::move(cb); }

    // --- modem control lines (host-driven; default: always ready) ------
    void set_dsr(bool ready) { dsr_ready_ = ready; }
    void set_dcd(bool detected) { dcd_detected_ = detected; }
    void set_cts(bool clear_to_send) { cts_clear_ = clear_to_send; }

    // --- configuration / introspection ----------------------------------
    void set_cpu_clock_hz(double hz) { cpu_clock_hz_ = hz; }
    uint8_t status_register() const;
    uint8_t command_register() const { return command_; }
    uint8_t control_register() const { return control_; }
    unsigned current_baud_rate() const;

private:
    // register-visible state
    uint8_t command_ = 0;
    uint8_t control_ = 0;
    bool irq_flag_ = false; // Status bit 7 latch; cleared only by a Status-register read
    bool dsr_ready_ = true, dcd_detected_ = true, cts_clear_ = true;
    bool overrun_ = false, framing_error_ = false, parity_error_ = false;
    bool tdre_ = true;
    bool rdrf_ = false;
    uint8_t rx_data_ = 0;

    // TX in-flight state
    bool tx_active_ = false;
    uint8_t tx_shift_byte_ = 0;
    int64_t tx_cycles_remaining_ = 0;

    // RX in-flight state
    std::deque<uint8_t> rx_pending_; // host-enqueued bytes not yet "arrived"
    bool rx_active_ = false;
    uint8_t rx_shift_byte_ = 0;
    int64_t rx_cycles_remaining_ = 0;

    double uart_crystal_hz_;
    double cpu_clock_hz_ = 3579545.0; // Pugputer6309 main CPU clock: 14.318MHz / 4

    TxCallback tx_cb_;
    std::deque<uint8_t> tx_queue_;

    unsigned baud_rate() const;
    double bits_per_char() const;
    uint32_t cycles_per_char() const;

    bool tx_irq_enabled() const { return (command_ & 0x01) && ((command_ >> 2) & 0x3) == 0x1; }
    bool rx_irq_enabled() const { return (command_ & 0x01) && ((command_ >> 1) & 0x1) == 0; }
};

} // namespace pugputer
