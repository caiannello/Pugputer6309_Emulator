// The YMF262 (OPL3) at $FFE0-$FFE3 (pugputer/opl3_device.hpp): the device on its own --
// registers, sound only while it is playing, timers and status -- and a demo song
// (demo/programs/ASM/VGM) assembled with ASM and played by the emulated machine, heard
// through a sink that keeps what it is given.
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <iterator>
#include <string>
#include <vector>

#include "basic309_session.hpp"
#include "disk_images.hpp"
#include "fat16_reader.hpp"
#include "pugputer/opl3_device.hpp"
#include "test_framework.hpp"

using pugputer::Opl3Device;

namespace {

constexpr double kHz = Opl3Device::kPugputerCpuHz;

// Keeps count of what it's given.
struct Capture : pugputer::AudioSink {
    uint64_t frames = 0, loud = 0, idles = 0;
    int peak = 0;
    void write(const int16_t* f, size_t n) override {
        for (size_t i = 0; i < 2 * n; ++i) {
            int v = std::abs(static_cast<int>(f[i]));
            if (v > peak) peak = v;
            if (v > 64 && (i & 1) == 0) ++loud;
        }
        frames += n;
    }
    void idle() override { ++idles; }
};

void reg(Opl3Device& d, uint16_t r, uint8_t v) {
    d.write(r & 0x100 ? 2 : 0, static_cast<uint8_t>(r));
    d.write(r & 0x100 ? 3 : 1, v);
}
// Runs the device for `seconds` of CPU time, in 100-cycle steps.
void run(Opl3Device& d, double seconds) {
    for (uint64_t c = static_cast<uint64_t>(seconds * kHz); c > 0; c -= std::min<uint64_t>(c, 100))
        d.tick(static_cast<uint32_t>(std::min<uint64_t>(c, 100)));
}
// Channel 0 of bank 0: a plain sine-ish tone (A4, about 440 Hz), keyed on.
void note_on(Opl3Device& d) {
    reg(d, 0x20, 0x21); // modulator: sustained, multiple 1
    reg(d, 0x23, 0x21); // carrier
    reg(d, 0x40, 0x3F); // modulator silent
    reg(d, 0x43, 0x00); // carrier loudest
    reg(d, 0x60, 0xF0); // fast attack
    reg(d, 0x63, 0xF0);
    reg(d, 0x80, 0x0F); // sustain, fast release
    reg(d, 0x83, 0x0F);
    reg(d, 0xC0, 0x31); // both speakers, additive
    reg(d, 0xA0, 0x44); // F-number $244, block 4
    reg(d, 0xB0, 0x32); // key on
}

std::string host_text(const std::string& path) {
    std::ifstream f(path, std::ios::binary);
    return std::string((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
}

} // namespace

TEST(opl3_plays_a_note_and_goes_quiet_after_it) {
    Opl3Device d;
    Capture c;
    d.set_sink(&c);
    run(d, 0.5);
    CHECK(!d.active() && c.frames == 0); // nothing written: nothing made, full speed
    note_on(d);
    CHECK(d.active());
    run(d, 0.25);
    // A quarter of a second of CPU time is a quarter of a second of sound.
    CHECK(std::llabs(static_cast<long long>(c.frames) - 12000) < 600);
    CHECK(c.peak > 2000);
    CHECK(c.loud > 6000);
    reg(d, 0xB0, 0x12); // key off: it fades, and a second after silence the chip goes idle
    uint64_t before = c.frames;
    run(d, 2.0);
    CHECK(!d.active());
    CHECK(c.idles == 1);
    CHECK(c.frames > before + 48000 && c.frames < before + 2 * 48000);
    uint64_t idle_frames = c.frames;
    run(d, 1.0);
    CHECK(c.frames == idle_frames); // idle: no frames
    note_on(d);                     // a write wakes it -- and a short idle spell was a rest in
    CHECK(d.active());              // the music: its silence goes out first, to keep the time
    CHECK(c.frames >= idle_frames + 48000 && c.frames < idle_frames + 2 * 48000);
    run(d, 0.1);
    CHECK(c.frames > idle_frames + 48000 + 4000);
    // A long pause (someone typing at the shell) isn't played back.
    reg(d, 0xB0, 0x12);
    run(d, 3.0);
    CHECK(!d.active());
    uint64_t now = c.frames;
    run(d, 12.0);
    note_on(d);
    CHECK(c.frames == now);
}

TEST(opl3_without_a_sink_keeps_its_registers_but_makes_no_sound) {
    Opl3Device d;
    note_on(d);
    run(d, 0.1);
    CHECK(d.frames_made() == 0);
    CHECK(d.reg(0xA0) == 0x44 && d.reg(0xB0) == 0x32);
    CHECK(d.register_writes() == 11);
    // Bank 1: the address written at offset 2 is register $100 + value.
    d.write(2, 0x05);
    d.write(3, 0x01); // OPL3 mode on
    CHECK(d.reg(0x105) == 0x01 && d.reg(0x005) == 0x00);
    // A data write goes to the last address of either bank.
    d.write(1, 0x07);
    CHECK(d.reg(0x105) == 0x07);
    d.reset();
    CHECK(d.reg(0xA0) == 0 && d.read(0) == 0 && !d.active());
}

TEST(opl3_timers_set_their_flags_in_the_status_register) {
    Opl3Device d;
    CHECK(d.read(0) == 0x00);
    CHECK(d.read(1) == 0xFF && d.read(2) == 0xFF); // only offset 0 reads (the status)
    reg(d, 0x02, 0xFF); // timer 1: one 80us step
    reg(d, 0x04, 0x01); // start it
    run(d, 50e-6);
    CHECK(d.read(0) == 0x00);
    run(d, 40e-6);
    CHECK(d.read(0) == 0xC0); // IRQ and T1
    reg(d, 0x04, 0x80);       // RST: the flags go; the timer keeps running
    CHECK(d.read(0) == 0x00);
    run(d, 80e-6);
    CHECK(d.read(0) == 0xC0);
    reg(d, 0x04, 0x80);
    reg(d, 0x04, 0x41); // masked: it runs, but sets no flag
    run(d, 1e-3);
    CHECK(d.read(0) == 0x00);
    // Timer 2 counts in 320us steps: from $FE, two of them.
    reg(d, 0x03, 0xFE);
    reg(d, 0x04, 0x02); // timer 2 only (timer 1 stops)
    run(d, 600e-6);
    CHECK(d.read(0) == 0x00);
    run(d, 50e-6);
    CHECK(d.read(0) == 0xA0); // IRQ and T2
    CHECK(!d.active());       // timers alone don't make it play
}

TEST(opl3_a_demo_song_assembles_and_plays_in_time) {
    // /ASM/VGM/VGXWINGF.ASM, as the demo disk has it, assembled with ASM and run.
    std::string src = host_text(std::string(DEMO_DIR) + "/ASM/VGM/VGXWINGF.ASM");
    std::vector<uint8_t> asm_com;
    {
        std::string a = host_text(ASM_BIN_PATH);
        asm_com.assign(a.begin(), a.end());
    }
    CHECK(!src.empty() && !asm_com.empty());
    pugputer::Fat16File f1, f2;
    f1.name = "VGXWINGF.ASM";
    f1.data.assign(src.begin(), src.end());
    f2.name = "ASM.COM";
    f2.data = asm_com;
    std::string img = build_image("opl3_song.img", 32768, 4, {f1, f2});
    Basic309Session s;
    CHECK(s.boot_shell(PUGBIOS_S19_PATH, img.c_str()));
    Opl3Device opl3;
    Capture c;
    opl3.set_sink(&c);
    s.bus.map_device("opl3", 0xFFE0, 4, &opl3);
    auto run_cmd = [&](const std::string& cmd, uint64_t budget) -> uint64_t {
        s.received.clear();
        for (char ch : cmd) s.send_byte(static_cast<uint8_t>(ch));
        s.send_byte('\r');
        uint64_t spent = 0;
        while (spent < budget) {
            spent += s.bus.run(20000);
            const std::string& r = s.received;
            if (r.size() > cmd.size() + 4 && r.compare(r.size() - 3, 3, "/> ") == 0) return spent;
        }
        return 0;
    };
    CHECK(run_cmd("ASM -f com vgxwingf.asm", 20000000000ull) != 0);
    CHECK(s.received.find("rror") == std::string::npos);
    Fat16Volume v;
    Fat16Volume::Entry e;
    CHECK(v.load(img.c_str()) && v.find("/VGXWINGF.COM", e));
    CHECK(opl3.register_writes() == 0 && c.frames == 0);
    // The same as the release disk's ready-made /DEMO/VGXWINGF.COM: lwasm's raw image
    // (demo/compile) with the header mkdiskimg gives it.
    std::string raw = host_text(std::string(REPO_DIR) + "/demo/build/vgxwingf.bin");
    std::vector<uint8_t> made = v.read(e);
    CHECK(!raw.empty() && std::string(made.begin(), made.end()) == std::string("PX\x40\x00\x40\x00\x00\x00", 8) + raw);

    uint64_t cycles = run_cmd("VGXWINGF", 400000000ull);
    CHECK(cycles != 0);
    double seconds = cycles / kHz;
    // The song is 1949929 samples at 44100 Hz (44.2 s); its delay loop takes 78 cycles
    // a sample where 81.2 would be exact, so the real machine plays it about 4% fast.
    CHECK(seconds > 40.0 && seconds < 44.5);
    std::printf("  played for %.1f s of CPU time; %llu register writes\n", seconds,
                static_cast<unsigned long long>(opl3.register_writes()));
    // Every write of the song (3181), the six at the start, and the silencing at the end.
    CHECK(opl3.register_writes() == 3181 + 6 + 2 * (9 + 22 + 3));
    CHECK(c.loud > 48000 * 20); // sound for most of it
    CHECK(c.peak > 4000);
    // Frames kept pace with the CPU's time while it played.
    CHECK(static_cast<double>(c.frames) > seconds * 48000 * 0.95);
    CHECK(static_cast<double>(c.frames) < (seconds + 1.5) * 48000);
    // After the song: silence, and then idle (full speed again).
    s.bus.run(static_cast<uint64_t>(1.5 * kHz));
    CHECK(!opl3.active());
    CHECK(c.idles >= 1);
}
