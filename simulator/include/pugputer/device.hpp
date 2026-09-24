// Minimal interface every memory-mapped IO device implements to plug into
// SystemBus (system_bus.hpp). Kept deliberately small: an address-relative
// read/write pair, a reset hook, an optional per-step timing tick, and an
// optional level-sensitive interrupt output. RAM/ROM don't need any of
// this -- SystemBus handles the flat backing store itself -- this is only
// for devices with register-level behavior (UART, future timer/keyboard/
// display/SD-card controllers, etc).
#pragma once

#include <cstdint>

namespace pugputer {

// Which CPU interrupt input a device's irq_asserted() output feeds, per
// the system's wiring. IRQ/FIRQ are level-sensitive (SystemBus recomputes
// them every step as the OR of every device driving that line); NMI is
// edge-triggered (SystemBus pulses it on a device's false->true
// transition). Most devices only ever use one line; None means the
// device has no interrupt output at all.
enum class IrqLine { None, IRQ, FIRQ, NMI };

class IDevice {
public:
    virtual ~IDevice() = default;

    // addr is relative to this device's mapped base address (i.e. 0 is
    // always the first byte of the device's window, regardless of where
    // SystemBus mapped it).
    virtual uint8_t read(uint16_t offset) = 0;
    virtual void write(uint16_t offset, uint8_t value) = 0;

    // Restores the device to its power-on/reset state.
    virtual void reset() = 0;

    // Called once per CPU step with the number of cycles that step
    // consumed, so devices can advance any internal timing state (baud
    // rate pacing, countdown timers, etc). Devices with no timing needs
    // don't need to override this.
    virtual void tick(uint32_t cpu_cycles) { (void)cpu_cycles; }

    // Current level of this device's interrupt output. SystemBus polls
    // this after every step for every device mapped to a given IrqLine
    // and ORs them together.
    virtual bool irq_asserted() const { return false; }
};

} // namespace pugputer
