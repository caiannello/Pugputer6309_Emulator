// Runs Pugputer commands from a host script: builds a disk image (DOS, SHELL.COM
// and the files asked for), boots the emulator through the real chain, types each
// command at the shell prompt, prints what the console shows, and copies files
// back out of the disk afterwards. For trying programs quickly (pugasm's tests
// use the same parts through the test harness).
//
//   pugrun [--add HOSTFILE[=NAME]]... [--get NAME=HOSTFILE]... [--disk IMG]
//          [--cycles N] [--quiet] COMMAND [COMMAND...]
//
// Each COMMAND is one shell line (quote it). --add puts a host file in the disk's
// root (as NAME, default its own name); --get copies a file off the disk when all
// the commands are done. --cycles is the budget for each command (default 4e9).
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <iterator>
#include <string>
#include <vector>

#include "fat16_reader.hpp"
#include "pugputer/fat16_image.hpp"
#include "pugputer/rom_device.hpp"
#include "pugputer/sdcard_device.hpp"
#include "pugputer/srec_loader.hpp"
#include "pugputer/system_bus.hpp"
#include "pugputer/uart_r65c51.hpp"

namespace {
bool read_file(const std::string& path, std::vector<uint8_t>& out) {
    std::ifstream f(path, std::ios::binary);
    if (!f) return false;
    out.assign((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
    return true;
}
std::string base_name(const std::string& p) {
    size_t s = p.find_last_of("/\\");
    return s == std::string::npos ? p : p.substr(s + 1);
}
bool ends_with(const std::string& s, const std::string& t) {
    return s.size() >= t.size() && s.compare(s.size() - t.size(), t.size(), t) == 0;
}
} // namespace

int main(int argc, char** argv) {
    std::vector<pugputer::Fat16File> files;
    std::vector<std::pair<std::string, std::string>> gets;
    std::vector<std::string> commands;
    std::string disk = "pugrun.img";
    uint64_t budget = 4000000000ull;
    bool quiet = false;
    for (int i = 1; i < argc; ++i) {
        std::string a = argv[i];
        if (a == "--add" && i + 1 < argc) {
            std::string spec = argv[++i];
            size_t eq = spec.find('=');
            pugputer::Fat16File f;
            std::string host = eq == std::string::npos ? spec : spec.substr(0, eq);
            f.name = eq == std::string::npos ? base_name(spec) : spec.substr(eq + 1);
            if (!read_file(host, f.data)) {
                std::fprintf(stderr, "pugrun: can't read %s\n", host.c_str());
                return 2;
            }
            files.push_back(std::move(f));
        } else if (a == "--get" && i + 1 < argc) {
            std::string spec = argv[++i];
            size_t eq = spec.find('=');
            if (eq == std::string::npos) {
                gets.push_back({spec, spec});
            } else {
                gets.push_back({spec.substr(0, eq), spec.substr(eq + 1)});
            }
        } else if (a == "--disk" && i + 1 < argc) {
            disk = argv[++i];
        } else if (a == "--cycles" && i + 1 < argc) {
            budget = std::strtoull(argv[++i], nullptr, 10);
        } else if (a == "--quiet") {
            quiet = true;
        } else {
            commands.push_back(a);
        }
    }

    std::vector<uint8_t> dos;
    pugputer::Fat16File shell;
    shell.name = "SHELL.COM";
    if (!read_file(DOS_BIN_DEFAULT, dos) || !read_file(SHELL_BIN_DEFAULT, shell.data)) {
        std::fprintf(stderr, "pugrun: dos.bin / shell.bin not built\n");
        return 2;
    }
    files.insert(files.begin(), shell);
    auto built = pugputer::build_fat16_image(disk, dos, files);
    if (!built.ok) {
        std::fprintf(stderr, "pugrun: %s\n", built.error.c_str());
        return 2;
    }

    std::vector<uint8_t> image(65536, 0);
    if (!pugputer::load_srec_file(PUGBIOS_S19_DEFAULT, image.data(), image.size()).ok) {
        std::fprintf(stderr, "pugrun: can't load the BIOS\n");
        return 2;
    }
    pugputer::RomDevice rom(0x1000);
    rom.load(image.data() + 0xF000, 0x1000);
    pugputer::SdCardDevice sd;
    if (!sd.open(disk)) return 2;
    pugputer::SystemBus bus;
    pugputer::UartR65C51 uart;
    std::string out;
    bus.map_device("bios_rom", 0xF000, 0x1000, &rom, pugputer::IrqLine::None);
    bus.map_device("sdcard", 0xFFD8, 4, &sd, pugputer::IrqLine::None);
    bus.map_device("uart", 0xFFE8, 4, &uart, pugputer::IrqLine::IRQ);
    bus.map_bank_registers();
    uart.set_tx_callback([&](uint8_t b) { out += static_cast<char>(b); });
    bus.reset();

    auto run_until_prompt = [&](uint64_t cycles) {
        uint64_t spent = 0;
        while (spent < cycles) {
            spent += bus.run(20000);
            if (ends_with(out, "> ")) return true;
        }
        return false;
    };
    if (!run_until_prompt(50000000)) {
        std::fprintf(stderr, "pugrun: the shell didn't start\n%s\n", out.c_str());
        return 2;
    }
    int rc = 0;
    for (const auto& cmd : commands) {
        out.clear();
        for (char c : cmd) uart.rx_enqueue(static_cast<uint8_t>(c));
        uart.rx_enqueue('\r');
        bus.run(2000000); // (the echo, so the prompt isn't the old one)
        bool done = run_until_prompt(budget);
        if (!quiet) std::fwrite(out.data(), 1, out.size(), stdout);
        if (!done) {
            hd6309_regs_t r{};
            hd6309_get_regs(bus.cpu(), &r);
            std::fprintf(stderr, "\npugrun: '%s' didn't finish (PC=%04X S=%04X X=%04X Y=%04X U=%04X DP=%02X)\n",
                         cmd.c_str(), r.pc, r.s, r.x, r.y, r.u, r.dp);
            std::fprintf(stderr, "pugrun: PCs:");
            for (int k = 0; k < 24; ++k) {
                bus.step();
                hd6309_get_regs(bus.cpu(), &r);
                std::fprintf(stderr, " %04X", r.pc);
            }
            std::fprintf(stderr, "\n");
            rc = 1;
            break;
        }
    }
    Fat16Volume v;
    if (!v.load(disk.c_str())) return 2;
    for (const auto& g : gets) {
        Fat16Volume::Entry e;
        if (!v.find(g.first, e)) {
            std::fprintf(stderr, "pugrun: no %s on the disk\n", g.first.c_str());
            rc = 1;
            continue;
        }
        std::vector<uint8_t> d = v.read(e);
        std::ofstream f(g.second, std::ios::binary);
        f.write(reinterpret_cast<const char*>(d.data()), static_cast<std::streamsize>(d.size()));
    }
    return rc;
}
