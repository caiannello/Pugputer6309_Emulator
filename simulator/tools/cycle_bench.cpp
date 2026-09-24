// Throwaway benchmark: measures how many emulated 6309 cycles this build can
// execute per real wall-clock second, i.e. the emulator's effective host
// throughput -- not to be confused with the *simulated* UART clock rate
// (cpu_clock_hz_, currently 3,579,545 Hz) used only for cycle-accounting
// pacing of device timing. Runs a tight BRA *-2 self-loop (a 2-byte, 3-cycle
// instruction) out of plain RAM so the number reflects raw hd6309_step()
// dispatch cost, not any particular program's instruction mix.
#include <chrono>
#include <cstdio>

#include "pugputer/system_bus.hpp"

using pugputer::SystemBus;

int main() {
    SystemBus bus; // plain RAM, no devices

    // BRA *-2 at $0200; reset vector points here.
    uint8_t* ram = bus.ram();
    ram[0x0200] = 0x20; // BRA
    ram[0x0201] = 0xFE; // -2
    ram[0xFFFE] = 0x02;
    ram[0xFFFF] = 0x00;
    bus.reset();

    constexpr uint64_t kTargetCycles = 200'000'000;
    auto start = std::chrono::steady_clock::now();
    uint64_t consumed = bus.run(kTargetCycles);
    auto end = std::chrono::steady_clock::now();

    double seconds = std::chrono::duration<double>(end - start).count();
    double hz = static_cast<double>(consumed) / seconds;

    std::printf("Consumed %llu emulated cycles in %.3f s\n",
                static_cast<unsigned long long>(consumed), seconds);
    std::printf("Effective throughput: %.1f emulated Hz (%.1fx a real 3.579545 MHz 6309)\n",
                hz, hz / 3579545.0);
    return 0;
}
