#include "pugputer/uart_r65c51.hpp"

namespace pugputer {

UartR65C51::UartR65C51(double uart_crystal_hz) : uart_crystal_hz_(uart_crystal_hz) {}

uint8_t UartR65C51::read(uint16_t offset) {
    switch (offset & 0x3) {
        case 0: { // Receiver Data Register: reading clears RDRF and the self-clearing error bits
            rdrf_ = false;
            overrun_ = false;
            framing_error_ = false;
            parity_error_ = false;
            return rx_data_;
        }
        case 1: { // Status Register: reading clears the IRQ latch (the only way to clear it)
            uint8_t s = status_register();
            irq_flag_ = false;
            return s;
        }
        case 2:
            return command_;
        default: // 3
            return control_;
    }
}

void UartR65C51::write(uint16_t offset, uint8_t value) {
    switch (offset & 0x3) {
        case 0: { // Transmit Data Register: always accepts and overwrites any in-flight byte
            tx_shift_byte_ = value;
            tx_active_ = true;
            tx_cycles_remaining_ = static_cast<int64_t>(cycles_per_char());
            tdre_ = false;
            break;
        }
        case 1: { // Programmed Reset: clears Command bits 4-0 only; Control is untouched
            command_ &= 0xE0;
            overrun_ = false;
            break;
        }
        case 2: { // Command Register
            command_ = value;
            // An interrupt condition that's already true, newly enabled by this write,
            // (re-)latches IRQ immediately -- this is what lets the BIOS kick an idle
            // transmitter awake by writing Command with TIC 10->01.
            if (tdre_ && tx_irq_enabled()) irq_flag_ = true;
            if (rdrf_ && rx_irq_enabled()) irq_flag_ = true;
            break;
        }
        default: // 3: Control Register
            control_ = value;
            break;
    }
}

void UartR65C51::reset() {
    command_ = 0;
    control_ = 0;
    irq_flag_ = false;
    overrun_ = false;
    framing_error_ = false;
    parity_error_ = false;
    tdre_ = true;
    rdrf_ = false;
    rx_data_ = 0;
    tx_active_ = false;
    tx_cycles_remaining_ = 0;
    rx_active_ = false;
    rx_cycles_remaining_ = 0;
    rx_pending_.clear();
    tx_queue_.clear();
    // dsr_ready_/dcd_detected_/cts_clear_ are host-controlled modem lines,
    // not something a chip reset would change -- left as-is.
}

void UartR65C51::tick(uint32_t cpu_cycles) {
    if (tx_active_) {
        tx_cycles_remaining_ -= cpu_cycles;
        if (tx_cycles_remaining_ <= 0) {
            tx_active_ = false;
            tdre_ = true;
            if (tx_cb_) tx_cb_(tx_shift_byte_);
            tx_queue_.push_back(tx_shift_byte_);
            if (tx_irq_enabled()) irq_flag_ = true;
        }
    }

    // The shift register keeps assembling incoming bytes regardless of
    // whether the CPU has read the previous one -- matching real
    // hardware, where overrun means a byte genuinely completed while
    // RDRF was still set, and gets dropped (not "waits patiently"). DTR=0
    // (Command bit 0) disables the receiver -- but per the datasheet, a
    // character already in progress finishes normally; only starting a
    // *new* one is gated.
    if (!rx_active_ && !rx_pending_.empty() && (command_ & 0x01)) {
        rx_active_ = true;
        rx_shift_byte_ = rx_pending_.front();
        rx_pending_.pop_front();
        rx_cycles_remaining_ = static_cast<int64_t>(cycles_per_char());
    }
    if (rx_active_) {
        rx_cycles_remaining_ -= cpu_cycles;
        if (rx_cycles_remaining_ <= 0) {
            rx_active_ = false;
            if (rdrf_) {
                overrun_ = true; // previous byte still unread: this one is dropped
            } else {
                rx_data_ = rx_shift_byte_;
                rdrf_ = true;
                if (rx_irq_enabled()) irq_flag_ = true;
            }
        }
    }
}

bool UartR65C51::rx_enqueue(uint8_t byte) {
    if (rx_pending_.size() >= 65536) return false; // pathological backpressure guard
    rx_pending_.push_back(byte);
    return true;
}

bool UartR65C51::tx_dequeue(uint8_t& out) {
    if (tx_queue_.empty()) return false;
    out = tx_queue_.front();
    tx_queue_.pop_front();
    return true;
}

uint8_t UartR65C51::status_register() const {
    uint8_t s = 0;
    if (irq_flag_) s |= 0x80;
    if (!dsr_ready_) s |= 0x40;
    if (!dcd_detected_) s |= 0x20;
    if (tdre_) s |= 0x10;
    if (rdrf_) s |= 0x08;
    if (overrun_) s |= 0x04;
    if (framing_error_) s |= 0x02;
    if (parity_error_) s |= 0x01;
    return s;
}

unsigned UartR65C51::baud_rate() const {
    // Index 0 (SBR=0000) is "16x external clock" -- unsupported here (no
    // simulated external RxC source), signaled by a 0 divisor.
    static const unsigned divisors[16] = {
        0, 36864, 24576, 16769, 13704, 12288, 6144, 3072, 1536, 1024, 768, 512, 384, 256, 192, 96,
    };
    unsigned sbr = control_ & 0x0F;
    unsigned div = divisors[sbr];
    if (div == 0) return 0;
    return static_cast<unsigned>(uart_crystal_hz_ / div + 0.5);
}

double UartR65C51::bits_per_char() const {
    static const int word_lengths[4] = { 8, 7, 6, 5 }; // WL (Control bits 6-5): 00,01,10,11
    unsigned wl_code = (control_ >> 5) & 0x3;
    int data_bits = word_lengths[wl_code];
    bool parity_enabled = (command_ & 0x20) != 0; // PME (Command bit 5)
    double parity_bits = parity_enabled ? 1.0 : 0.0;
    bool sbn = (control_ & 0x80) != 0;
    double stop_bits;
    if (!sbn) {
        stop_bits = 1.0;
    } else if (data_bits == 5 && !parity_enabled) {
        stop_bits = 1.5;
    } else if (data_bits == 8 && parity_enabled) {
        stop_bits = 1.0;
    } else {
        stop_bits = 2.0;
    }
    return 1.0 + data_bits + parity_bits + stop_bits; // + 1 start bit
}

uint32_t UartR65C51::cycles_per_char() const {
    unsigned baud = baud_rate();
    if (baud == 0) return 0xFFFFFFFFu; // unsupported external-clock mode: never completes
    double cycles = cpu_clock_hz_ / static_cast<double>(baud) * bits_per_char();
    if (cycles < 1.0) cycles = 1.0;
    return static_cast<uint32_t>(cycles + 0.5);
}

unsigned UartR65C51::current_baud_rate() const {
    return baud_rate();
}

} // namespace pugputer
