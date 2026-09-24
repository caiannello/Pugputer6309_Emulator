// Register-level R65C51 UART behavior, tested directly against the
// IDevice interface (no CPU involved) -- see uart_echo golden test for
// the full CPU+IRQ+ISR path.
#include "test_framework.hpp"
#include "pugputer/uart_r65c51.hpp"

using pugputer::UartR65C51;

namespace {
constexpr uint8_t ST_IRQ = 0x80, ST_DSR = 0x40, ST_DCD = 0x20, ST_TDRE = 0x10, ST_RDRF = 0x08,
                   ST_OVRN = 0x04, ST_FE = 0x02, ST_PE = 0x01;

// $1F/$09 (control/command), matching the real BIOS's init: 19200 baud, 8
// data bits, 1 stop bit, RX IRQ enabled, TX IRQ disabled, DTR ready.
void configure_bios_defaults(UartR65C51& u) {
    u.write(3, 0x1F);
    u.write(2, 0x09);
}
} // namespace

TEST(reset_state) {
    UartR65C51 u;
    u.reset();
    CHECK((u.status_register() & ST_TDRE) != 0);
    CHECK((u.status_register() & ST_RDRF) == 0);
    CHECK((u.status_register() & (ST_OVRN | ST_FE | ST_PE)) == 0);
    CHECK(u.command_register() == 0x00);
    CHECK(u.control_register() == 0x00);
}

TEST(baud_rate_decodes_control_register) {
    UartR65C51 u;
    u.write(3, 0x1F); // SBR=1111
    CHECK(u.current_baud_rate() == 19200u);
    u.write(3, 0x1E); // SBR=1110
    CHECK(u.current_baud_rate() == 9600u);
    u.write(3, 0x18); // SBR=1000
    CHECK(u.current_baud_rate() == 1200u);
    u.write(3, 0x10); // SBR=0000: unsupported external-clock mode
    CHECK(u.current_baud_rate() == 0u);
}

TEST(write_data_clears_tdre_immediately_and_sets_it_after_char_time) {
    UartR65C51 u;
    configure_bios_defaults(u);
    u.write(0, 0x42);
    CHECK((u.status_register() & ST_TDRE) == 0); // busy right after the write

    u.tick(1); // nowhere near a full character time at 19200 baud
    CHECK((u.status_register() & ST_TDRE) == 0);

    u.tick(5000); // comfortably more than one character time
    CHECK((u.status_register() & ST_TDRE) != 0);

    uint8_t out = 0;
    CHECK(u.tx_dequeue(out));
    CHECK(out == 0x42);
}

TEST(write_data_timing_matches_configured_baud_rate_exactly) {
    UartR65C51 u;
    configure_bios_defaults(u); // 19200 baud, 8N1 -> 10 bit times/char
    u.write(0, 0x55);
    // cpu_clock_hz (3,579,545 default) / 19200 baud * 10 bits = 1864.35 -> 1864 cycles
    u.tick(1863);
    CHECK((u.status_register() & ST_TDRE) == 0);
    u.tick(1);
    CHECK((u.status_register() & ST_TDRE) != 0);
}

TEST(write_data_while_busy_overwrites_the_in_flight_byte) {
    UartR65C51 u;
    configure_bios_defaults(u);
    u.write(0, 0xAA);
    u.tick(1); // not complete yet
    u.write(0, 0xBB); // overwrites 0xAA before it ever went out
    u.tick(5000);

    uint8_t out = 0;
    CHECK(u.tx_dequeue(out));
    CHECK(out == 0xBB);
    CHECK(!u.tx_dequeue(out)); // 0xAA never appears
}

TEST(rx_enqueue_sets_rdrf_after_char_time_and_read_clears_it) {
    UartR65C51 u;
    configure_bios_defaults(u);
    CHECK(u.rx_enqueue(0x37));
    CHECK((u.status_register() & ST_RDRF) == 0);

    u.tick(5000);
    CHECK((u.status_register() & ST_RDRF) != 0);

    uint8_t v = u.read(0);
    CHECK(v == 0x37);
    CHECK((u.status_register() & ST_RDRF) == 0);
}

TEST(overrun_drops_a_byte_that_completes_while_rdrf_still_set) {
    UartR65C51 u;
    configure_bios_defaults(u);
    CHECK(u.rx_enqueue(0x01));
    CHECK(u.rx_enqueue(0x02));

    u.tick(5000); // first byte arrives, RDRF set
    CHECK((u.status_register() & ST_RDRF) != 0);
    u.tick(5000); // second byte's char-time elapses too, while RDRF is still set
    CHECK((u.status_register() & ST_OVRN) != 0);

    uint8_t v = u.read(0);
    CHECK(v == 0x01); // the first byte survives; the second was dropped
    CHECK((u.status_register() & ST_OVRN) == 0); // reading Data clears OVRN too
}

TEST(programmed_reset_clears_command_low_bits_but_preserves_parity_bits_and_control) {
    UartR65C51 u;
    u.write(3, 0x1F);        // Control
    u.write(2, 0xE9);        // Command: PMC=11,PME=1 (bits 7-5=111), plus REM/TIC/IRD/DTR set
    u.write(1, 0x00);        // Programmed Reset (value written is irrelevant)
    CHECK(u.command_register() == 0xE0); // bits 7-5 preserved, bits 4-0 cleared
    CHECK(u.control_register() == 0x1F); // Control untouched by a programmed reset
}

TEST(programmed_reset_clears_overrun) {
    UartR65C51 u;
    configure_bios_defaults(u);
    u.rx_enqueue(0x01);
    u.rx_enqueue(0x02);
    u.tick(5000);
    u.tick(5000);
    CHECK((u.status_register() & ST_OVRN) != 0);
    u.write(1, 0x00); // Programmed Reset
    CHECK((u.status_register() & ST_OVRN) == 0);
}

TEST(irq_latches_when_tdre_transitions_true_while_tx_irq_enabled) {
    UartR65C51 u;
    u.write(3, 0x1F);
    u.write(2, 0x05); // DTR=1, IRD=0, TIC=01 (TX IRQ enabled)
    CHECK(u.irq_asserted()); // TDRE was already true when TX IRQ got enabled (see next test too)
    u.read(1);                // ack it
    CHECK(!u.irq_asserted());

    u.write(0, 0x10);
    CHECK(!u.irq_asserted()); // TDRE just went busy, no new completion yet
    u.tick(5000);
    CHECK(u.irq_asserted()); // TDRE transitioned back to 1 -> latches IRQ
}

TEST(irq_latches_when_command_write_enables_an_already_true_condition) {
    UartR65C51 u;
    u.write(3, 0x1F);
    u.write(2, 0x01); // DTR=1, IRD=1 (RX IRQ disabled), TIC=00 (TX IRQ disabled, transmitter idle/TDRE=1)
    CHECK(!u.irq_asserted());

    u.write(2, 0x05); // enable TX IRQ (TIC 00->01) while TDRE is already 1
    CHECK(u.irq_asserted()); // matches the BIOS's documented idle-transmitter-kick behavior
}

TEST(irq_latches_when_rdrf_transitions_true_while_rx_irq_enabled) {
    UartR65C51 u;
    configure_bios_defaults(u); // RX IRQ enabled by default
    CHECK(!u.irq_asserted());
    u.rx_enqueue(0x41);
    u.tick(5000);
    CHECK(u.irq_asserted());
    u.read(1);
    CHECK(!u.irq_asserted());
}

TEST(dtr_zero_disables_the_receiver_and_all_interrupts) {
    UartR65C51 u;
    u.write(3, 0x1F);
    u.write(2, 0x00); // DTR=0, IRD=0 (would otherwise enable RX IRQ)
    u.rx_enqueue(0x41);
    u.tick(5000);
    // DTR=0 disables the receiver outright (not just its interrupt): a
    // byte that hasn't started arriving yet never does.
    CHECK((u.status_register() & ST_RDRF) == 0);
    CHECK(!u.irq_asserted());

    u.write(2, 0x01); // DTR=1 (IRD still 0 -> RX IRQ enabled), receiver now live
    u.tick(5000);
    CHECK((u.status_register() & ST_RDRF) != 0);
    CHECK(u.irq_asserted());
}

TEST(dtr_zero_lets_an_in_progress_receive_finish) {
    UartR65C51 u;
    u.write(3, 0x1F);
    u.write(2, 0x01); // DTR=1, IRD=0: receiver live
    u.rx_enqueue(0x41);
    u.tick(1); // start the in-flight receive, but nowhere near complete
    u.write(2, 0x00); // DTR=0 mid-character
    u.tick(5000); // the already-in-flight byte still completes per the datasheet
    CHECK((u.status_register() & ST_RDRF) != 0);
}
