/*
 * hd6309.h - Public C API for the HD6309 CPU emulator core.
 *
 * This header defines a stable C ABI so the emulator can be linked from
 * C, C++, or bound from other languages, and consumed either as a static
 * or shared (DLL) library. The CPU core never owns memory: all accesses
 * go through the read/write callbacks supplied at creation time, so a
 * future full-machine simulator can install its own paging/IO/ROM-overlay
 * bus without touching this library.
 */
#ifndef HD6309_H
#define HD6309_H

#include <stdint.h>

#ifdef _WIN32
#  ifdef HD6309_BUILD_SHARED
#    define HD6309_API __declspec(dllexport)
#  elif defined(HD6309_USE_SHARED)
#    define HD6309_API __declspec(dllimport)
#  else
#    define HD6309_API
#  endif
#else
#  define HD6309_API
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef struct hd6309_t hd6309_t;

/* Bus callbacks. ctx is the opaque pointer passed to hd6309_create(). */
typedef uint8_t (*hd6309_read_fn)(void* ctx, uint16_t addr);
typedef void (*hd6309_write_fn)(void* ctx, uint16_t addr, uint8_t value);

/* All 6309 registers, in a flat struct for get/set. D = (A<<8)|B,
 * W = (E<<8)|F, Q = (D<<16)|W. MD holds the mode register (bit0=native
 * mode, bit1=native FIRQ mode, bit6=illegal-opcode trap flag,
 * bit7=div-by-zero trap flag). */
typedef struct {
    uint16_t pc, x, y, u, s, v;
    uint8_t a, b, dp, cc, e, f, md;
} hd6309_regs_t;

/* Why hd6309_run() stopped. */
typedef enum {
    HD6309_STOP_CYCLE_BUDGET = 0, /* ran out of the requested cycle budget */
    HD6309_STOP_BREAKPOINT = 1,
    HD6309_STOP_ILLEGAL_OPCODE_TRAP = 2, /* still ran; trap was serviced */
    HD6309_STOP_SYNC = 3,        /* stopped in SYNC, waiting for interrupt */
    HD6309_STOP_HALTED = 4       /* explicitly halted via hd6309_halt() */
} hd6309_stop_reason_t;

HD6309_API hd6309_t* hd6309_create(hd6309_read_fn read_fn, hd6309_write_fn write_fn, void* ctx);
HD6309_API void hd6309_destroy(hd6309_t* cpu);

/* Resets registers and vectors PC through $FFFE, as real hardware does. */
HD6309_API void hd6309_reset(hd6309_t* cpu);

/* Executes exactly one instruction (servicing any pending interrupt
 * first if one is due). Returns the number of cycles consumed. */
HD6309_API uint64_t hd6309_step(hd6309_t* cpu);

/* Runs instructions until max_cycles have been consumed, a breakpoint is
 * hit, or the CPU halts. Returns the number of cycles actually consumed.
 * Use hd6309_get_stop_reason() to find out why it stopped. */
HD6309_API uint64_t hd6309_run(hd6309_t* cpu, uint64_t max_cycles);

HD6309_API hd6309_stop_reason_t hd6309_get_stop_reason(hd6309_t* cpu);

/* Explicit halt/resume, for external tooling (debuggers, etc). A halted
 * CPU still accepts hd6309_step(), but hd6309_run() returns immediately. */
HD6309_API void hd6309_halt(hd6309_t* cpu);
HD6309_API void hd6309_resume(hd6309_t* cpu);
HD6309_API int hd6309_is_halted(hd6309_t* cpu);

/* Level-sensitive IRQ/FIRQ request lines: assert=1 to request, 0 to
 * release. NMI is edge-triggered; call hd6309_nmi_pulse() once per edge. */
HD6309_API void hd6309_set_irq(hd6309_t* cpu, int asserted);
HD6309_API void hd6309_set_firq(hd6309_t* cpu, int asserted);
HD6309_API void hd6309_nmi_pulse(hd6309_t* cpu);

HD6309_API void hd6309_get_regs(hd6309_t* cpu, hd6309_regs_t* out);
HD6309_API void hd6309_set_regs(hd6309_t* cpu, const hd6309_regs_t* in);

HD6309_API uint64_t hd6309_total_cycles(hd6309_t* cpu);

/* Breakpoints fire (and hd6309_run stops) when PC reaches addr just
 * before an instruction fetch. Returns a breakpoint id (>=0) or -1 if
 * the table is full. */
HD6309_API int hd6309_add_breakpoint(hd6309_t* cpu, uint16_t addr);
HD6309_API void hd6309_remove_breakpoint(hd6309_t* cpu, int id);
HD6309_API void hd6309_clear_breakpoints(hd6309_t* cpu);

/* Convenience: reads/writes memory through the installed bus (same path
 * the CPU itself uses), for tooling that wants to poke/inspect memory
 * without going through the callbacks directly. */
HD6309_API uint8_t hd6309_peek(hd6309_t* cpu, uint16_t addr);
HD6309_API void hd6309_poke(hd6309_t* cpu, uint16_t addr, uint8_t value);

/* --- Convenience flat-RAM bus -------------------------------------
 * A simple 64KB RAM block usable as the bus for standalone testing or
 * simple tools. Not intended for the full Pugputer6309 machine sim,
 * which will supply its own paging/IO-aware bus callbacks instead. */
typedef struct hd6309_ram_bus_t hd6309_ram_bus_t;

HD6309_API hd6309_ram_bus_t* hd6309_ram_bus_create(void);
HD6309_API void hd6309_ram_bus_destroy(hd6309_ram_bus_t* bus);
HD6309_API uint8_t* hd6309_ram_bus_data(hd6309_ram_bus_t* bus); /* raw 65536-byte buffer */
HD6309_API hd6309_read_fn hd6309_ram_bus_read_fn(void);
HD6309_API hd6309_write_fn hd6309_ram_bus_write_fn(void);

#ifdef __cplusplus
}
#endif

#endif /* HD6309_H */
