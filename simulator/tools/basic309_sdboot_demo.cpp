// Like basic309_demo, but boots through the REAL disk chain instead of a
// hand-wired PC hijack: bios/pugbios.s19's own $FFFE reset vector runs its
// cold-start, its SD_BOOT_TRY (bios/sdcard.asm) finds and loads
// dos/dos.asm from disk.img's reserved sectors, and dos.asm's own FAT16
// root-directory scan finds and loads BASIC.COM before jumping to it --
// nothing here tells the emulator where BASIC.COM is. Build disk.img
// first with mkdiskimg.
//
//   basic309_sdboot_demo                     -- console bridge, default paths
//   basic309_sdboot_demo --com COM10         -- COM port bridge (Linux: --com /dev/ttyUSB0)
//   basic309_sdboot_demo --com pty           -- (Linux) bridge to a new pseudo-terminal
//   basic309_sdboot_demo --bios path\to.s19  -- load a different BIOS image
//   basic309_sdboot_demo --disk path\to.img  -- load a different disk image
//   basic309_sdboot_demo --help
//
// Unless --bios / --disk say otherwise, pugbios.s19 and disk.img are looked for
// next to the executable first (that is how the binary release is laid out), and
// then at the paths this build was configured with (the source tree).
//
// In console mode the console acts as an ANSI terminal both ways, like the ones a
// real Pugputer is used from: escape sequences the machine sends are carried out
// (EDIT.COM draws its screen with them, and asks the terminal's size), and keys
// arrive as a terminal sends them -- arrows and function keys as escape sequences,
// Alt+key as Esc then the key, Ctrl+C as ^C. Ctrl+Break (or closing the window)
// quits; on Linux, Ctrl+\ (or closing the terminal) quits.
#ifdef _WIN32
#ifndef NOMINMAX
#define NOMINMAX
#endif
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#else
#include <climits>
#include <csignal>
#include <fcntl.h>
#include <poll.h>
#include <termios.h>
#include <unistd.h>
#endif

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <string>
#include <vector>

#include "pugputer/rom_device.hpp"
#include "pugputer/sdcard_device.hpp"
#include "pugputer/srec_loader.hpp"
#include "pugputer/system_bus.hpp"
#include "pugputer/uart_r65c51.hpp"
#ifdef PUGPUTER_HAVE_COM_BRIDGE
#include "pugputer/com_port_bridge.hpp"
#endif

using pugputer::IrqLine;
using pugputer::load_srec_file;
using pugputer::RomDevice;
using pugputer::SdCardDevice;
using pugputer::SrecLoadResult;
using pugputer::SystemBus;
using pugputer::UartR65C51;

namespace {
constexpr uint16_t kBiosBase = 0xF000;
constexpr uint32_t kBiosSize = 0x1000; // $F000-$FFFF

#ifdef _WIN32
constexpr const char* kQuitKey = "Ctrl+Break";
#else
constexpr const char* kQuitKey = "Ctrl+\\";
#endif

// The full path of this program, or "" if it can't be found.
std::string exe_path() {
#ifdef _WIN32
    char path[MAX_PATH] = {0};
    DWORD n = GetModuleFileNameA(nullptr, path, MAX_PATH);
    if (n > 0 && n < MAX_PATH) return std::string(path, n);
#else
    char path[PATH_MAX] = {0};
    ssize_t n = readlink("/proc/self/exe", path, sizeof(path) - 1);
    if (n > 0) return std::string(path, static_cast<size_t>(n));
#endif
    return std::string();
}

// `name` next to the executable if it is there, else `fallback`.
std::string find_default(const char* name, const char* fallback) {
    std::string beside = exe_path();
    size_t slash = beside.find_last_of("\\/");
    if (slash != std::string::npos) {
        beside = beside.substr(0, slash + 1) + name;
        if (std::ifstream(beside, std::ios::binary).good()) return beside;
    }
    return fallback;
}

void usage() {
    std::printf(
        "Pugputer 6309 emulator: boots the BIOS, DOS, the shell and BASIC.\n"
        "\n"
#ifdef _WIN32
        "  --com COMn       connect the UART to a COM port (e.g. one end of a com0com pair)\n"
        "                   instead of this console\n"
#else
        "  --com DEVICE     connect the UART to a serial port (e.g. /dev/ttyUSB0) instead of\n"
        "                   this terminal\n"
        "  --com pty        connect the UART to a new pseudo-terminal, and print its name for\n"
        "                   a terminal program (screen, picocom, minicom, ...) to open\n"
#endif
        "  --bios FILE      BIOS image, Motorola S-record (default: pugbios.s19 beside this program)\n"
        "  --disk FILE      FAT16 disk image (default: disk.img beside this program)\n"
        "  --help           this text\n"
        "\n"
        "In console mode, type at the prompt; %s quits.\n",
        kQuitKey);
}

#ifdef _WIN32

// The console as an ANSI terminal (see the top of the file), and put back as it was
// when the program ends.
HANDLE g_in = INVALID_HANDLE_VALUE, g_out = INVALID_HANDLE_VALUE;
DWORD g_in_mode = 0, g_out_mode = 0;
bool g_modes_saved = false;
bool g_vt_input = false; // the console sends escape sequences itself (Windows 10 1809 on)

void restore_console() {
    if (!g_modes_saved) return;
    std::fputs("\x1b[r\x1b[0m\x1b[?1049l", stdout); // what a program may have left set
    std::fflush(stdout);
    SetConsoleMode(g_in, g_in_mode);
    SetConsoleMode(g_out, g_out_mode);
    g_modes_saved = false;
}

BOOL WINAPI on_console_ctrl(DWORD) {
    restore_console();
    return FALSE; // and the default handler ends the program
}

void setup_console() {
    g_in = GetStdHandle(STD_INPUT_HANDLE);
    g_out = GetStdHandle(STD_OUTPUT_HANDLE);
    if (!GetConsoleMode(g_in, &g_in_mode) || !GetConsoleMode(g_out, &g_out_mode)) return; // redirected
    g_modes_saved = true;
    SetConsoleMode(g_out, g_out_mode | ENABLE_PROCESSED_OUTPUT | ENABLE_VIRTUAL_TERMINAL_PROCESSING |
                              DISABLE_NEWLINE_AUTO_RETURN);
    // No line editing or echo, and Ctrl+C is a key like any other.
    // (ENABLE_EXTENDED_FLAGS keeps Quick Edit, mouse selection, as it was.)
    DWORD in = g_in_mode & ~(ENABLE_PROCESSED_INPUT | ENABLE_LINE_INPUT | ENABLE_ECHO_INPUT | ENABLE_MOUSE_INPUT);
    in |= ENABLE_EXTENDED_FLAGS;
    g_vt_input = SetConsoleMode(g_in, in | ENABLE_VIRTUAL_TERMINAL_INPUT) != 0;
    if (!g_vt_input) SetConsoleMode(g_in, in);
    SetConsoleCtrlHandler(on_console_ctrl, TRUE);
    std::atexit(restore_console);
}

// Without the console's own escape sequences (older Windows): the keys EDIT uses.
const char* key_sequence(WORD vk) {
    switch (vk) {
    case VK_UP: return "\x1b[A";
    case VK_DOWN: return "\x1b[B";
    case VK_RIGHT: return "\x1b[C";
    case VK_LEFT: return "\x1b[D";
    case VK_HOME: return "\x1b[H";
    case VK_END: return "\x1b[F";
    case VK_INSERT: return "\x1b[2~";
    case VK_DELETE: return "\x1b[3~";
    case VK_PRIOR: return "\x1b[5~";
    case VK_NEXT: return "\x1b[6~";
    case VK_F1: return "\x1bOP";
    case VK_F2: return "\x1bOQ";
    case VK_F3: return "\x1bOR";
    case VK_F4: return "\x1bOS";
    case VK_F5: return "\x1b[15~";
    case VK_F6: return "\x1b[17~";
    case VK_F7: return "\x1b[18~";
    case VK_F8: return "\x1b[19~";
    case VK_F9: return "\x1b[20~";
    case VK_F10: return "\x1b[21~";
    case VK_F11: return "\x1b[23~";
    case VK_F12: return "\x1b[24~";
    default: return nullptr;
    }
}

// Whatever has been typed (and the console's replies to the machine's queries) -> the UART.
void poll_console(UartR65C51& uart) {
    DWORD pending = 0;
    while (GetNumberOfConsoleInputEvents(g_in, &pending) && pending > 0) {
        INPUT_RECORD rec[32];
        DWORD got = 0;
        if (!ReadConsoleInputA(g_in, rec, 32, &got) || got == 0) return;
        for (DWORD i = 0; i < got; ++i) {
            if (rec[i].EventType != KEY_EVENT || !rec[i].Event.KeyEvent.bKeyDown) continue;
            const KEY_EVENT_RECORD& k = rec[i].Event.KeyEvent;
            char ch = k.uChar.AsciiChar;
            for (WORD n = 0; n < (k.wRepeatCount ? k.wRepeatCount : 1); ++n) {
                if (g_vt_input) {
                    if (ch) uart.rx_enqueue(static_cast<uint8_t>(ch));
                } else if (ch) {
                    if (k.dwControlKeyState & (LEFT_ALT_PRESSED | RIGHT_ALT_PRESSED)) uart.rx_enqueue(0x1B);
                    uart.rx_enqueue(static_cast<uint8_t>(ch));
                } else if (const char* seq = key_sequence(k.wVirtualKeyCode)) {
                    while (*seq) uart.rx_enqueue(static_cast<uint8_t>(*seq++));
                }
            }
        }
    }
}

#else // POSIX

// The terminal is already an ANSI terminal; it only needs raw mode (no line editing,
// echo or newline translation), with Ctrl+C and Ctrl+Z passed on as keys. Ctrl+\ is
// left as the quit key.
termios g_saved_tio;
bool g_modes_saved = false;
bool g_stdin_tty = false;
bool g_stdin_eof = false;

void restore_console() {
    if (!g_modes_saved) return;
    static const char reset[] = "\x1b[r\x1b[0m\x1b[?1049l"; // what a program may have left set
    ssize_t ignored = write(STDOUT_FILENO, reset, sizeof(reset) - 1);
    (void)ignored;
    tcsetattr(STDIN_FILENO, TCSANOW, &g_saved_tio);
    g_modes_saved = false;
}

void on_signal(int sig) {
    restore_console(); // (only async-signal-safe calls in there)
    if (sig == SIGQUIT) _exit(0); // Ctrl+\ is the way to quit, not a crash (no core dump)
    std::signal(sig, SIG_DFL);
    std::raise(sig);
}

void setup_console() {
    g_stdin_tty = isatty(STDIN_FILENO) != 0;
    if (!g_stdin_tty || tcgetattr(STDIN_FILENO, &g_saved_tio) != 0) return; // redirected
    termios tio = g_saved_tio;
    tio.c_iflag &= ~(IGNBRK | BRKINT | PARMRK | ISTRIP | INLCR | IGNCR | ICRNL | IXON);
    tio.c_oflag &= ~OPOST;
    tio.c_lflag &= ~(ICANON | ECHO | ECHONL | IEXTEN);
    tio.c_cc[VINTR] = _POSIX_VDISABLE;
    tio.c_cc[VSUSP] = _POSIX_VDISABLE;
    tio.c_cc[VMIN] = 0;
    tio.c_cc[VTIME] = 0;
    if (tcsetattr(STDIN_FILENO, TCSANOW, &tio) != 0) return;
    g_modes_saved = true;
    for (int sig : {SIGQUIT, SIGINT, SIGTERM, SIGHUP}) std::signal(sig, on_signal);
    std::atexit(restore_console);
}

// Whatever has been typed (and the terminal's replies to the machine's queries) -> the UART.
void poll_console(UartR65C51& uart) {
    if (g_stdin_eof) return;
    pollfd p{STDIN_FILENO, POLLIN, 0};
    while (::poll(&p, 1, 0) > 0 && (p.revents & (POLLIN | POLLHUP))) {
        uint8_t buf[256];
        ssize_t got = read(STDIN_FILENO, buf, sizeof(buf));
        if (got <= 0) {
            if (got == 0 && !g_stdin_tty) g_stdin_eof = true; // end of piped input
            return;
        }
        for (ssize_t i = 0; i < got; ++i) {
            // Backspace: most terminals send DEL, the Windows console (and a real Pugputer's
            // usual terminal setting) BS -- the one BASIC's line editor knows.
            uint8_t b = buf[i];
            if (g_stdin_tty && b == 0x7F) b = 0x08;
            uart.rx_enqueue(b);
        }
    }
}
#endif
} // namespace

int main(int argc, char** argv) {
    std::string com_port;
    std::string bios_path = find_default("pugbios.s19", PUGBIOS_S19_DEFAULT);
    std::string disk_path = find_default("disk.img", DISK_IMG_DEFAULT);
    for (int i = 1; i < argc; ++i) {
        if (std::strcmp(argv[i], "--help") == 0 || std::strcmp(argv[i], "-h") == 0 || std::strcmp(argv[i], "/?") == 0) {
            usage();
            return 0;
        } else if (std::strcmp(argv[i], "--com") == 0 && i + 1 < argc) {
            com_port = argv[++i];
        } else if (std::strcmp(argv[i], "--bios") == 0 && i + 1 < argc) {
            bios_path = argv[++i];
        } else if (std::strcmp(argv[i], "--disk") == 0 && i + 1 < argc) {
            disk_path = argv[++i];
        }
    }

    std::vector<uint8_t> bios_image(65536, 0);
    SrecLoadResult bios_load = load_srec_file(bios_path, bios_image.data(), bios_image.size());
    if (!bios_load.ok) {
        std::fprintf(stderr, "Failed to load BIOS image '%s': %s\n", bios_path.c_str(), bios_load.error.c_str());
        return 1;
    }
    std::printf("Loaded %s ($%04X-$%04X)\n", bios_path.c_str(), bios_load.min_addr, bios_load.max_addr);

    RomDevice bios_rom(static_cast<uint16_t>(kBiosSize));
    bios_rom.load(bios_image.data() + kBiosBase, kBiosSize);

    SdCardDevice sdcard;
    if (!sdcard.open(disk_path)) {
        std::fprintf(stderr, "Failed to open disk image '%s' (is it next to the program? see --help)\n", disk_path.c_str());
        return 1;
    }
    std::printf("Attached disk image %s\n", disk_path.c_str());

    SystemBus bus; // RAM starts entirely zeroed
    UartR65C51 uart;
    bus.map_device("bios_rom", kBiosBase, static_cast<uint16_t>(kBiosSize), &bios_rom, IrqLine::None);
    bus.map_device("sdcard", 0xFFD8, 4, &sdcard, IrqLine::None);
    bus.map_device("uart", 0xFFE8, 4, &uart, IrqLine::IRQ);
    bus.map_bank_registers(); // $FFEC-$FFEF: the BIOS programs the RAM banks at reset

    bool use_com = false;
#ifdef PUGPUTER_HAVE_COM_BRIDGE
    pugputer::ComPortBridge bridge;
    if (!com_port.empty()) {
        if (bridge.open(com_port, uart.current_baud_rate())) {
            use_com = true;
#ifdef _WIN32
            std::printf("Bridging UART to %s. Connect a terminal to the other end of the com0com pair.\n",
                        com_port.c_str());
#else
            std::printf("Bridging UART to %s. Connect a terminal to it at 19200 baud, 8N1, for example:\n"
                        "    screen %s 19200\n"
                        "Ctrl+C here stops the emulator.\n",
                        bridge.device_name().c_str(), bridge.device_name().c_str());
#endif
        } else {
            std::fprintf(stderr, "Failed to open %s: %s\nFalling back to console.\n", com_port.c_str(),
                         bridge.last_error().c_str());
        }
    }
#else
    if (!com_port.empty()) {
        std::fprintf(stderr, "This build has no COM-port bridge support; using the console instead.\n");
    }
#endif

    if (!use_com) {
        std::printf("Bridging UART to this console. Type to send bytes; %s to quit.\n"
                    "(At the shell prompt, type BASIC to start BASIC; SYSTEM leaves it.)\n\n",
                    kQuitKey);
        setup_console();
        uart.set_tx_callback([](uint8_t b) {
            std::putchar(b);
            std::fflush(stdout);
        });
    }
    std::fflush(stdout);
    std::fflush(stderr);

    bus.reset(); // PC comes from the real BIOS $FFFE vector -- the whole
                 // boot chain (BIOS -> SD_BOOT_TRY -> dos.asm -> BASIC.COM)
                 // runs for real from here, no PC hijack.

    for (;;) {
        bus.run(20000);
        if (use_com) {
#ifdef PUGPUTER_HAVE_COM_BRIDGE
            bridge.poll(uart);
#endif
        } else {
            poll_console(uart);
        }
    }
}
