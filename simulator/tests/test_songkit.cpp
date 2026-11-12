// SONGKIT's player (gamekit/sk_play.asm) in SONGPLAY.COM (gamekit/songplay.asm), run on the
// emulated machine with songs made here, as gamekit/README.md describes them: what it writes
// to the OPL3, at which of the song's ticks, is checked against what the song says. ASM on the
// machine assembles SONGPLAY from its sources, byte for byte what lwasm made.
//
// SONGKIT_SONG=file.sng [SONGKIT_WAV=out.wav] [SONGKIT_SECONDS=n] also plays that song with
// SONGPLAY, as the machine would, into a WAV file (by default beside the song), to listen to.
#include <algorithm>
#include <array>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <iterator>
#include <map>
#include <string>
#include <vector>

#include "basic309_session.hpp"
#include "disk_images.hpp"
#include "fat16_reader.hpp"
#include "pugputer/opl3_device.hpp"
#include "pugputer/video_device.hpp"
#include "test_framework.hpp"
#include "vc.h"

using pugputer::Opl3Device;

namespace {

constexpr double kHz = Opl3Device::kPugputerCpuHz;
constexpr double kTick60 = 52 * 320e-6; // Timer 2 at "60 Hz": 52 steps of 320 us

std::string host_file(const std::string& path) {
    std::ifstream f(path, std::ios::binary);
    return std::string((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
}

pugputer::Fat16File disk_file(const std::string& name, const std::string& data) {
    pugputer::Fat16File f;
    f.name = name;
    f.data.assign(data.begin(), data.end());
    return f;
}

// ---- songs ----------------------------------------------------------------------------------

struct Cell {
    uint8_t note = 0, ins = 0, vol = 0, fx = 0, par = 0;
};
// A note by name: "C-4", "F#2" (1 = C-0 ... 96 = B-7).
uint8_t N(const char* name) {
    static const char* names = "C-C#D-D#E-F-F#G-G#A-A#B-";
    int n = 0;
    while (names[2 * n] != name[0] || names[2 * n + 1] != name[1]) ++n;
    return static_cast<uint8_t>(1 + 12 * (name[2] - '0') + n);
}
constexpr uint8_t OFF = 0x7F;

struct Pattern {
    int rows = 64;
    std::map<std::pair<int, int>, Cell> cells; // (row, track)
    Pattern& put(int row, int track, Cell c) {
        cells[{row, track}] = c;
        return *this;
    }
    bool empty_row(int r) const {
        auto it = cells.lower_bound({r, 0});
        return it == cells.end() || it->first.first != r;
    }
    // Packed: each row's cells, then $1F -- or $1E n when n empty rows follow.
    std::string packed() const {
        std::string out;
        for (int r = 0; r < rows; ++r) {
            for (int t = 0; t < 20; ++t) {
                auto it = cells.find({r, t});
                if (it == cells.end()) continue;
                const Cell& c = it->second;
                uint8_t b = static_cast<uint8_t>(t);
                if (c.note || c.ins) b |= 0x20;
                if (c.vol) b |= 0x40;
                if (c.fx || c.par) b |= 0x80;
                out += static_cast<char>(b);
                if (b & 0x20) out += {static_cast<char>(c.note), static_cast<char>(c.ins)};
                if (b & 0x40) out += static_cast<char>(c.vol);
                if (b & 0x80) out += {static_cast<char>(c.fx), static_cast<char>(c.par)};
            }
            int k = 0;
            while (r + 1 + k < rows && k < 255 && empty_row(r + 1 + k)) ++k;
            if (k) {
                out += {'\x1E', static_cast<char>(k)};
                r += k;
            } else {
                out += '\x1F';
            }
        }
        return out;
    }
};

using Ins = std::array<uint8_t, 32>;
// An instrument: each operator's $20 $40 $60 $80 $E0; $C0 (feedback, connection).
Ins ins2(std::array<uint8_t, 5> op1, std::array<uint8_t, 5> op2, uint8_t c0, uint8_t flags = 0) {
    Ins i{};
    i[0] = flags;
    i[1] = c0;
    std::copy(op1.begin(), op1.end(), i.begin() + 3);
    std::copy(op2.begin(), op2.end(), i.begin() + 8);
    return i;
}

struct Song {
    uint8_t flags = 0, pairs = 0, depth = 0, rate = 60, speed = 6, loop = 0xFF;
    std::string title, author;
    std::vector<uint8_t> orders{0};
    std::vector<Ins> ins;
    std::vector<Pattern> pats;
    std::vector<size_t> pad; // bytes of nothing before each pattern (to put it further on)
    std::string bytes() const {
        std::string h("PSG1", 4);
        h += {static_cast<char>(flags), static_cast<char>(pairs), static_cast<char>(depth),
              static_cast<char>(rate), static_cast<char>(speed), static_cast<char>(ins.size()),
              static_cast<char>(pats.size()), static_cast<char>(orders.size()), static_cast<char>(loop)};
        h += std::string(3, '\0');
        h += (title + std::string(32, '\0')).substr(0, 32);
        h += (author + std::string(32, '\0')).substr(0, 32);
        for (uint8_t o : orders) h += static_cast<char>(o);
        size_t table = h.size();
        h += std::string(4 * pats.size(), '\0');
        for (const Ins& i : ins) h += std::string(i.begin(), i.end());
        for (size_t p = 0; p < pats.size(); ++p) {
            if (p < pad.size()) h += std::string(pad[p], '\x55');
            size_t at = h.size();
            h[table + 4 * p] = static_cast<char>(pats[p].rows);
            h[table + 4 * p + 1] = static_cast<char>(at >> 16);
            h[table + 4 * p + 2] = static_cast<char>(at >> 8);
            h[table + 4 * p + 3] = static_cast<char>(at);
            h += pats[p].packed();
        }
        return h;
    }
};

const Ins kPiano = ins2({0x21, 0x1A, 0xF2, 0x45, 0x01}, {0x21, 0x00, 0xF3, 0x36, 0x00}, 0x06);

// ---- the machine ----------------------------------------------------------------------------

struct Kit {
    std::string img;
    std::string bin; // lwasm's SONGPLAY.COM
    Basic309Session s;
    Opl3Device opl3;
    std::vector<Opl3Device::Write> log;
    bool ok = false;

    explicit Kit(std::vector<pugputer::Fat16File> more = {}) {
        std::string repo = REPO_DIR;
        bin = host_file(repo + "/gamekit/build/songplay.bin");
        std::vector<pugputer::Fat16File> files = {
            disk_file("SONGPLAY.COM", bin),
            disk_file("SONGPLAY.ASM", host_file(repo + "/gamekit/songplay.asm")),
            disk_file("SK_PLAY.ASM", host_file(repo + "/gamekit/sk_play.asm")),
            disk_file("DEFINES.D", host_file(repo + "/bios/defines.d")),
            disk_file("ASM.COM", host_file(ASM_BIN_PATH))};
        for (auto& f : more) files.push_back(std::move(f));
        CHECK(!bin.empty());
        img = build_image("songkit.img", 32768, 4, files);
        CHECK(!img.empty());
        CHECK(s.boot_shell(PUGBIOS_S19_PATH, img.c_str()));
        s.bus.map_device("opl3", 0xFFE0, 4, &opl3);
        opl3.set_log(&log);
        ok = !bin.empty() && !img.empty();
    }
    void type(const std::string& cmd) {
        s.received.clear();
        for (char ch : cmd) s.send_byte(static_cast<uint8_t>(ch));
        s.send_byte('\r');
    }
    // Runs until the shell's prompt is back: the cycles that took (0: it didn't).
    uint64_t prompt(uint64_t budget) {
        for (uint64_t spent = 0; spent < budget;) {
            uint64_t got = s.bus.run(20000);
            if (got == 0) return 0;
            spent += got;
            const std::string& r = s.received;
            if (r.size() > 4 && r.compare(r.size() - 3, 3, "/> ") == 0) return spent;
        }
        return 0;
    }
    uint64_t run(const std::string& cmd, double seconds = 30) {
        type(cmd);
        return prompt(static_cast<uint64_t>(seconds * kHz));
    }
    void seconds(double t) { s.bus.run(static_cast<uint64_t>(t * kHz)); }
};

// The song's ticks, from the log: from Timer 2 started ($04 = $42), each tick's writes
// start with its flags cleared ($04 = $80).
struct Ticks {
    std::vector<std::vector<Opl3Device::Write>> t;
    std::vector<Opl3Device::Write> start; // SK_START's writes, to the timer started
    explicit Ticks(const std::vector<Opl3Device::Write>& log) {
        size_t i = 0;
        while (i < log.size() && !(log[i].reg == 0x04 && log[i].value == 0x42)) ++i;
        size_t from = i;
        while (from > 0 && !(log[from - 1].reg == 0x105 && log[from - 1].value == 0x01)) --from;
        start.assign(log.begin() + static_cast<long>(from ? from - 1 : 0), log.begin() + static_cast<long>(i));
        for (++i; i < log.size(); ++i) {
            if (log[i].reg == 0x04 && log[i].value == 0x80) {
                t.emplace_back();
                continue;
            }
            if (!t.empty()) t.back().push_back(log[i]);
        }
    }
    const std::vector<Opl3Device::Write>& operator[](size_t n) const {
        static const std::vector<Opl3Device::Write> none;
        return n < t.size() ? t[n] : none;
    }
    // The values written to register r in tick n, in order.
    std::vector<int> values(size_t n, uint16_t r) const {
        std::vector<int> v;
        for (auto& w : (*this)[n])
            if (w.reg == r) v.push_back(w.value);
        return v;
    }
    // The registers written in tick n, in order.
    std::vector<int> regs(size_t n) const {
        std::vector<int> v;
        for (auto& w : (*this)[n]) v.push_back(w.reg);
        return v;
    }
    // The last value written to r in ticks 0..n (-1: none).
    int last(size_t n, uint16_t r) const {
        int v = -1;
        for (size_t k = 0; k <= n && k < t.size(); ++k)
            for (auto& w : t[k])
                if (w.reg == r) v = w.value;
        return v;
    }
};

using V = std::vector<int>;

// SONGKIT.COM on the machine with the video card and the OPL3, worked through the card's
// keyboard and mouse as a person at the video window would.
struct Editor {
    std::string img;
    Basic309Session s;
    pugputer::VideoDevice v;
    Opl3Device opl3;
    std::vector<Opl3Device::Write> log;
    bool ok = false;

    explicit Editor(std::vector<pugputer::Fat16File> more = {}) {
        std::string repo = REPO_DIR;
        std::string bin = host_file(repo + "/gamekit/build/songkit.bin");
        std::vector<pugputer::Fat16File> files = {disk_file("SONGKIT.COM", bin)};
        for (auto& f : more) files.push_back(std::move(f));
        CHECK(!bin.empty());
        img = build_image("songkit_ed.img", 32768, 4, files);
        v.set_draw_all(true);
        s.attach_video(&v);
        CHECK(s.boot_shell(PUGBIOS_S19_PATH, img.c_str()));
        s.bus.map_device("opl3", 0xFFE0, 4, &opl3);
        opl3.set_log(&log);
        ok = !bin.empty() && !img.empty();
    }
    void frames(int n = 3) { s.bus.run(static_cast<uint64_t>(n * kHz / 60)); }
    // Starts SONGKIT (with these arguments) and waits for its screen.
    bool start(const std::string& args = "") {
        std::string cmd = "SONGKIT" + (args.empty() ? "" : " " + args);
        for (char ch : cmd) s.send_byte(static_cast<uint8_t>(ch));
        s.send_byte('\r');
        for (int i = 0; i < 200; ++i) {
            frames(6);
            if (row(0).find("SONGKIT") != std::string::npos && row(2).find("Speed") != std::string::npos &&
                row(29).find_first_not_of(' ') != std::string::npos) {
                frames(6);
                return true;
            }
        }
        return false;
    }
    // A key pressed (and let go, unless held), with Ctrl or Shift.
    void key(uint8_t usage, bool ctrl = false, bool shift = false, bool hold = false) {
        if (ctrl) v.key(0xE0, true);
        if (shift) v.key(0xE1, true);
        v.key(usage, true);
        frames(2);
        if (!hold) {
            v.key(usage, false);
            frames(2);
        }
        if (shift) v.key(0xE1, false);
        if (ctrl) v.key(0xE0, false);
        frames(2);
    }
    void up(uint8_t usage) {
        v.key(usage, false);
        frames(3);
    }
    void text(const std::string& t) {
        for (char c : t) {
            if (c >= 'A' && c <= 'Z') key(static_cast<uint8_t>(0x04 + c - 'A'));
            else if (c >= 'a' && c <= 'z') key(static_cast<uint8_t>(0x04 + c - 'a'));
            else if (c >= '1' && c <= '9') key(static_cast<uint8_t>(0x1E + c - '1'));
            else if (c == '0') key(0x27);
            else if (c == '.') key(0x37);
            else if (c == ' ') key(0x2C);
        }
    }
    // The cell (4 bytes) at row r, column c as the screen shows it: SONGKIT's screen (layer 1,
    // its map where the card starts it), or where that is left clear (a space, colors 0),
    // the pattern grid's layer behind it (layer 0: its map at 0, 128 rows, scrolled).
    const uint8_t* cell(int r, int c) {
        const uint8_t* s = v.card().vram + VC_RESET_TEXT_MAP + (r * 128 + c) * 4;
        if (!(s[0] == ' ' && s[1] == 0 && s[2] == 0)) return s;
        const uint8_t* cfg = v.card().cfg;
        int top = (cfg[0x10 + 0x0A] << 8 | cfg[0x10 + 0x0B]) / 16;
        return v.card().vram + (((top + r) & 127) * 128 + c) * 4;
    }
    // Row r of the screen, as text.
    std::string row(int r) {
        std::string out;
        for (int c = 0; c < 80; ++c) out += static_cast<char>(cell(r, c)[0] ? cell(r, c)[0] : ' ');
        return out;
    }
    uint8_t bg(int r, int c) { return cell(r, c)[2]; }
    // SONGKIT_SHOW: the screen as text; SONGKIT_SHOT=file.ppm: as the card shows it.
    void show() {
        for (int r = 0; r < 30; ++r) std::printf("  |%s|\n", row(r).c_str());
        if (const char* shot = std::getenv("SONGKIT_SHOT")) {
            frames(3);
            std::ofstream f(shot, std::ios::binary);
            f << "P6 640 480 255\n";
            for (int i = 0; i < 640 * 480; ++i) {
                uint32_t p = v.pixels()[i];
                char rgb[3] = {static_cast<char>(p >> 16), static_cast<char>(p >> 8), static_cast<char>(p)};
                f.write(rgb, 3);
            }
        }
    }
    // The cell lit up (the field being edited) on row r: its column, or -1.
    int lit(int r) {
        for (int c = 0; c < 80; ++c)
            if (bg(r, c) == 25) return c;
        return -1;
    }
    std::vector<uint8_t> file(const std::string& path) {
        Fat16Volume vol;
        Fat16Volume::Entry e;
        if (!vol.load(img.c_str()) || !vol.find(path, e)) return {};
        return vol.read(e);
    }
};

} // namespace

TEST(songkit_songplay_assembles_on_the_machine_and_says_what_is_wrong) {
    Kit k({disk_file("JUNK.SNG", std::string(200, 'x'))});
    if (!k.ok) return;
    CHECK(k.run("ASM -o SP2.COM songplay.asm", 300) != 0);
    CHECK(k.s.received.find("rror") == std::string::npos);
    if (k.s.received.find("rror") != std::string::npos) std::printf("%s\n", k.s.received.c_str());
    Fat16Volume vol;
    Fat16Volume::Entry e;
    CHECK(vol.load(k.img.c_str()) && vol.find("/SP2.COM", e));
    std::vector<uint8_t> made = vol.read(e);
    CHECK(std::string(made.begin(), made.end()) == k.bin);

    CHECK(k.run("SONGPLAY", 5) != 0 && k.s.received.find("Usage: SONGPLAY file[.SNG]") != std::string::npos);
    CHECK(k.run("SONGPLAY NOSONG", 5) != 0 && k.s.received.find("NOSONG.SNG: File not found") != std::string::npos);
    CHECK(k.run("SONGPLAY junk", 5) != 0 && k.s.received.find("JUNK.SNG: Not a SONGKIT song") != std::string::npos);
    CHECK(k.s.bus.bank_register(2) == 2);
    CHECK(k.opl3.reg(0x105) == 0 && k.opl3.reg(0x04) == 0x60);
}

// Notes on two tracks (array 0's channel 0, array 1's channel 0), at 60 ticks a second and 6
// a row: each one's instrument, volume and pitch written as its row's first tick comes; a key
// off; and the end of a song that doesn't loop.
TEST(songkit_plays_notes_in_time) {
    Song song;
    song.title = "Test one";
    song.ins = {kPiano};
    Pattern p;
    p.rows = 16;
    p.put(0, 0, {N("C-4"), 1}).put(4, 0, {N("E-4")}).put(8, 0, {OFF}).put(12, 9, {N("G-4"), 1, 0x21});
    song.pats = {p};
    Kit k({disk_file("T1.SNG", song.bytes())});
    if (!k.ok) return;
    uint64_t took = k.run("SONGPLAY t1", 10);
    CHECK(took != 0);
    CHECK(k.s.received.find("Playing T1.SNG: Test one (any key stops it)") != std::string::npos);
    Ticks t(k.log);
    // Started: OPL3 mode, no 4-op channels, no rhythm, Timer 2 every 52 steps of 320 us.
    CHECK(t.start.size() > 4);
    CHECK(k.opl3.reg(0x03) == 256 - 52);
    // Row 0: the instrument into channel 0's operators ($00 and $03), $C0 with both outputs,
    // the carrier at full volume, then the note (C-4: F-number $159, block 4), keyed.
    CHECK(t.regs(0) == V({0x0B0, 0x020, 0x040, 0x060, 0x080, 0x0E0, 0x023, 0x043, 0x063, 0x083, 0x0E3, 0x0C0,
                          0x043, 0x0B0, 0x0A0, 0x0B0}));
    CHECK(t.values(0, 0x20) == V({0x21}) && t.values(0, 0x40) == V({0x1A}) && t.values(0, 0x60) == V({0xF2}));
    CHECK(t.values(0, 0x80) == V({0x45}) && t.values(0, 0xE0) == V({0x01}) && t.values(0, 0x63) == V({0xF3}));
    CHECK(t.values(0, 0xC0) == V({0x36}) && t.values(0, 0x43) == V({0x00, 0x00}));
    CHECK(t.values(0, 0xA0) == V({0x59}) && t.values(0, 0xB0) == V({0x00, 0x00, 0x31}));
    for (int n = 1; n < 24; ++n) CHECK(t[n].empty());
    // Row 4: E-4 ($1B3): the key let go and pressed again.
    CHECK(t.regs(24) == V({0xB0, 0xA0, 0xB0}) && t.values(24, 0xA0) == V({0xB3}) && t.values(24, 0xB0) == V({0x11, 0x31}));
    double row4 = (t[24][0].cycle - t[0][0].cycle) / kHz;
    std::printf("  4 rows in %.4f s (%.4f expected)\n", row4, 24 * kTick60);
    CHECK(row4 > 24 * kTick60 - 0.001 && row4 < 24 * kTick60 + 0.001);
    // Row 8: the key let go.
    CHECK(t.regs(48) == V({0xB0}) && t.values(48, 0xB0) == V({0x11}));
    // Row 12: track 9 is array 1's channel 0; volume $20 (from the volume column's $21):
    // the carrier 31 steps down. G-4: $205.
    CHECK(t.values(72, 0x120) == V({0x21}) && t.values(72, 0x1C0) == V({0x36}));
    CHECK(t.values(72, 0x143) == V({0x00, 0x1F}) && t.values(72, 0x1A0) == V({0x05}));
    CHECK(t.values(72, 0x1B0) == V({0x00, 0x00, 0x32}));
    // The song's end, as its 16th row ends: every key let go, and a second later the chip silent and
    // back as it was.
    CHECK(t.values(95, 0xB0) == V({0x11}) && t.values(95, 0x1B0) == V({0x12}));
    CHECK(t.t.size() >= 96 + 55 && t.t.size() <= 96 + 64);
    CHECK(k.opl3.reg(0x105) == 0 && k.opl3.reg(0x04) == 0x60);
    CHECK(k.s.bus.bank_register(2) == 2);
}

// The effects, a row each on track 0, as their ticks go by.
TEST(songkit_plays_the_effects) {
    Song song;
    song.ins = {kPiano};
    Pattern p;
    p.rows = 13;
    p.put(0, 0, {N("C-4"), 1, 0, '0', 0x47});  // arpeggio: C E G
    p.put(2, 0, {0, 0, 0, '1', 0x20});         // up a semitone a tick
    p.put(3, 0, {0, 0, 0, '2', 0x00});         // down, as fast (the last slide's speed)
    p.put(4, 0, {N("G-4"), 0, 0, '3', 0x08});  // slide to G, 8/32 of a semitone a tick
    p.put(5, 0, {0, 0, 0x21});                 // volume 32
    p.put(6, 0, {0, 0, 0, 'C', 0x10});         // volume 16
    p.put(7, 0, {0, 0, 0, 'A', 0x02});         // down 2 a tick
    p.put(8, 0, {0, 0, 0, '8', 0x10});         // left only
    p.put(9, 0, {0, 0, 0, 'E', 0xC2});         // cut at tick 2
    p.put(10, 0, {N("E-4"), 1, 0, 'E', 0xD3}); // played at tick 3
    p.put(11, 0, {0, 0, 0, 'F', 0x03});        // 3 ticks a row from here
    p.put(12, 0, {N("C-4"), 1});
    song.pats = {p};
    Kit k({disk_file("FX.SNG", song.bytes())});
    if (!k.ok) return;
    CHECK(k.run("SONGPLAY fx", 10) != 0);
    Ticks t(k.log);
    // 0xy: the note, +4, +7, a tick each.
    V arp;
    for (int n = 0; n <= 6; ++n) {
        auto a = t.values(n, 0xA0);
        arp.push_back(a.empty() ? -1 : a.back());
    }
    CHECK(arp == V({0x59, 0xB3, 0x05, 0x59, 0xB3, 0x05, 0x59}));
    CHECK(t.values(2, 0xB0) == V({0x32}) && t.values(3, 0xB0) == V({0x31}));
    // 1xx from the next tick of its row: C# D D# E F; then 2xx back down to C.
    V up, down;
    for (int n = 13; n <= 17; ++n) up.push_back(t.values(n, 0xA0).empty() ? -1 : t.values(n, 0xA0)[0]);
    for (int n = 19; n <= 23; ++n) down.push_back(t.values(n, 0xA0).empty() ? -1 : t.values(n, 0xA0)[0]);
    CHECK(t[12].empty() && t[18].empty());
    CHECK(up == V({0x6D, 0x83, 0x9A, 0xB3, 0xCC}));
    CHECK(down == V({0xB3, 0x9A, 0x83, 0x6D, 0x59}));
    // 3xx: no new key, and on toward G 8/32 of a semitone a tick.
    CHECK(t[24].empty());
    V slide;
    for (int n = 25; n <= 29; ++n) slide.push_back(t.values(n, 0xA0).empty() ? -1 : t.values(n, 0xA0)[0]);
    CHECK(slide == V({0x5E, 0x63, 0x68, 0x6D, 0x72}));
    // The volume: the column, Cxx, Axy (63 - volume steps down from the carrier's 0).
    CHECK(t.values(30, 0x43) == V({0x1F}) && t.values(36, 0x43) == V({0x2F}));
    V vol;
    for (int n = 43; n <= 47; ++n) vol.push_back(t.values(n, 0x43).empty() ? -1 : t.values(n, 0x43)[0]);
    CHECK(vol == V({0x31, 0x33, 0x35, 0x37, 0x39}));
    // 8xy: the outputs.
    CHECK(t.values(48, 0xC0) == V({0x16}));
    // ECx: silent at its tick.
    CHECK(t[54].empty() && t[55].empty() && t.values(56, 0x43) == V({0x3F}));
    // EDx: the cell 3 ticks into its row, at full volume again (its instrument).
    CHECK(t[60].empty() && t[62].empty());
    CHECK(t.values(63, 0x43) == V({0x00}) && t.values(63, 0xA0) == V({0xB3}) && t.values(63, 0xB0).back() == 0x31);
    // Fxx: row 12 three ticks after row 11's.
    CHECK(t[69].size() > 0 && t.values(69, 0xA0) == V({0x59}));
    for (int n = 64; n < 69; ++n) CHECK(t.values(n, 0xA0).empty());
}

// The OPL3's 4-op channels and its drums: a song with array 0's channels 0 and 3 paired and
// rhythm mode on.
TEST(songkit_plays_4op_channels_and_drums) {
    Song song;
    song.flags = 1;    // rhythm mode
    song.pairs = 0x01; // channel 0 + 3, array 0
    song.depth = 0xC0;
    Ins four{};
    four[0] = 1;    // 4 operators
    four[1] = 0x0C; // feedback 6, connection 0
    four[2] = 0x01; //   and 1: algorithm 1 -- 1->2 out, 3->4 out
    for (int op = 0; op < 4; ++op) {
        four[3 + 5 * op] = static_cast<uint8_t>(0x21 + op);
        four[4 + 5 * op] = static_cast<uint8_t>(0x10 + op);
        four[5 + 5 * op] = 0xF4;
        four[6 + 5 * op] = 0x44;
        four[7 + 5 * op] = static_cast<uint8_t>(op);
    }
    Ins drum = ins2({0x01, 0x05, 0xF8, 0x47, 0x00}, {0x02, 0x08, 0xF9, 0x48, 0x01}, 0x00);
    drum[0] = 2;         // a fixed note
    drum[23] = N("C-3"); //   C-3
    song.ins = {four, kPiano, drum};
    Pattern p;
    p.rows = 8;
    p.put(0, 0, {N("A-4"), 1}).put(0, 3, {N("C-4"), 2});
    p.put(1, 0, {N("C-4"), 2});
    p.put(2, 6, {N("C-5"), 3});
    p.put(3, 7, {N("C-5"), 3});
    p.put(4, 19, {N("C-5"), 3});
    song.pats = {p};
    Kit k({disk_file("OPS.SNG", song.bytes())});
    if (!k.ok) return;
    CHECK(k.run("SONGPLAY ops", 10) != 0);
    Ticks t(k.log);
    // The chip: channels 0 and 3 paired; deep tremolo and vibrato, and rhythm mode.
    bool pair = false, bd = false;
    for (auto& w : t.start) {
        pair = pair || (w.reg == 0x104 && w.value == 0x01);
        bd = bd || (w.reg == 0xBD && w.value == 0xE0);
    }
    CHECK(pair && bd);
    // Row 0: all four operators ($00 $03 $08 $0B); both $C0s; the carriers (2 and 4) at
    // full volume; A-4 ($244). Track 3 (the pair's second channel) plays nothing.
    CHECK(t.values(0, 0x20) == V({0x21}) && t.values(0, 0x23) == V({0x22}) && t.values(0, 0x28) == V({0x23}));
    CHECK(t.values(0, 0x2B) == V({0x24}) && t.values(0, 0xEB) == V({0x03}));
    CHECK(t.values(0, 0xC0) == V({0x3C}) && t.values(0, 0xC3) == V({0x31}));
    CHECK(t.values(0, 0x43) == V({0x11, 0x11}) && t.values(0, 0x4B) == V({0x13, 0x13}) && t.values(0, 0x40) == V({0x10}));
    CHECK(t.values(0, 0xA0) == V({0x44}) && t.values(0, 0xB0).back() == 0x32);
    CHECK(t.values(0, 0xB3).empty() && t.values(0, 0xA3).empty());
    // Row 1: a 2-op instrument on the 4-op channel: its operators as 1 and 2, 3 and 4 silent,
    // the pair's second connection 1 (so 1->2 is heard alone).
    CHECK(t.values(6, 0x20) == V({0x21}) && t.values(6, 0x23) == V({0x21}));
    CHECK(t.values(6, 0x48) == V({0x3F}) && t.values(6, 0x4B) == V({0x3F}) && t.values(6, 0xC3) == V({0x31}));
    CHECK(t.values(6, 0x43) == V({0x00, 0x00}));
    // Row 2: the bass drum (track 6): channel 6's operators, its fixed note (C-3: $159, block
    // 3) in channel 6 with no key bit, and its bit in $BD let go, then pressed.
    CHECK(t.values(12, 0x30) == V({0x01}) && t.values(12, 0x33) == V({0x02}));
    CHECK(t.values(12, 0xA6) == V({0x59}) && t.values(12, 0xB6) == V({0x0D}));
    CHECK(t.values(12, 0xBD) == V({0xE0, 0xE0, 0xF0}));
    // Row 3: the snare (track 7): one operator ($14), the instrument's second; channel 7's pitch.
    CHECK(t.values(18, 0x34) == V({0x02}) && t.values(18, 0x54) == V({0x08, 0x08}) && t.values(18, 0x31).empty());
    CHECK(t.values(18, 0xA7) == V({0x59}) && t.values(18, 0xBD).back() == 0xF8);
    // Row 4: the hi-hat (track 19): operator $11, the instrument's first.
    CHECK(t.values(24, 0x31) == V({0x01}) && t.values(24, 0x51) == V({0x05, 0x05}) && t.values(24, 0xBD).back() == 0xF9);
}

// A song in two RAM pages, a pattern across the line between them and its instruments in the
// first, played from the pages; Dxx, Bxx, the song's loop, and a key to stop it.
TEST(songkit_reads_across_pages_and_jumps) {
    Song song;
    song.ins = {kPiano, ins2({0x22, 0x1A, 0xF2, 0x45, 0x01}, {0x22, 0x00, 0xF3, 0x36, 0x00}, 0x08)};
    song.orders = {0, 1, 2};
    song.loop = 1;
    Pattern p0, p1, p2;
    p0.rows = 8;
    p0.put(0, 0, {N("C-4"), 1}).put(1, 0, {0, 0, 0, 'D', 4}); // on to order 1's row 4
    p1.rows = 8;
    p1.put(0, 0, {N("D-4"), 1});
    for (int r = 1; r < 4; ++r) p1.put(r, 1, {N("C-4"), 1});
    p1.put(4, 0, {N("E-4"), 1}).put(5, 0, {0, 0, 0, 'B', 2}); // on to order 2
    p2.rows = 4;
    p2.put(0, 0, {N("G-4"), 2});
    song.pats = {p0, p1, p2};
    std::string b = song.bytes();
    size_t p1_len = p1.packed().size();
    song.pad = {0, 16384 - 3 - (b.size() - p1_len - p2.packed().size()), 0}; // p1 from 3 bytes before page 2
    b = song.bytes();
    CHECK(b.size() > 16384 && b.size() < 2 * 16384);
    Kit k({disk_file("JUMPS.SNG", b)});
    if (!k.ok) return;
    k.type("SONGPLAY jumps");
    k.seconds(3.0);
    k.s.send_byte(' ');
    CHECK(k.prompt(static_cast<uint64_t>(2 * kHz)) != 0);
    Ticks t(k.log);
    auto a0 = [&](size_t n) { return t.values(n, 0xA0).empty() ? -1 : t.values(n, 0xA0)[0]; };
    // C (order 0, row 0); row 1's D04: order 1's row 4, E; its B02: order 2, G (the
    // second instrument); then the loop: order 1 from its start, D.
    CHECK(a0(0) == 0x59 && a0(12) == 0xB3 && a0(24) == 0x05 && a0(48) == 0x83);
    CHECK(t.values(24, 0x20) == V({0x22}) && t.values(24, 0xC0) == V({0x38}));
    CHECK(t.values(48, 0x20) == V({0x21}));
    // Order 1's rows 1-3 were passed over the first time, and played the second.
    for (int n = 6; n < 48; ++n) CHECK(t.values(n, 0xB1).empty());
    CHECK(!t.values(54, 0xB1).empty() && !t.values(66, 0xB1).empty());
    CHECK(a0(72) == 0xB3 && a0(84) == 0x05);
    // The key: silent, the window's bank as it was.
    CHECK(k.opl3.reg(0x105) == 0 && k.opl3.reg(0xB0) == 0);
    CHECK(k.s.bus.bank_register(2) == 2);
}

// SONGKIT_SONG: a song, heard (see the top of this file). Nothing without it.
TEST(songkit_song_to_wav) {
    const char* song = std::getenv("SONGKIT_SONG");
    if (!song) return;
    std::string data = host_file(song);
    CHECK(data.size() > 80);
    if (data.size() <= 80) return;
    std::string wav = std::getenv("SONGKIT_WAV") ? std::getenv("SONGKIT_WAV") : std::string(song) + ".wav";
    double most = std::getenv("SONGKIT_SECONDS") ? std::atof(std::getenv("SONGKIT_SECONDS")) : 60;
    struct Keep : pugputer::AudioSink {
        std::vector<int16_t> pcm;
        void write(const int16_t* f, size_t n) override { pcm.insert(pcm.end(), f, f + 2 * n); }
    } keep;
    Kit k({disk_file("SONG.SNG", data)});
    if (!k.ok) return;
    k.opl3.set_sink(&keep);
    k.type("SONGPLAY song");
    uint64_t took = k.prompt(static_cast<uint64_t>(most * kHz));
    if (!took) {
        k.s.send_byte(' ');
        k.prompt(static_cast<uint64_t>(2 * kHz));
    }
    std::printf("  %s", k.s.received.c_str());
    std::ofstream f(wav, std::ios::binary);
    auto le = [&](uint32_t v, int n) {
        for (int i = 0; i < n; ++i) f.put(static_cast<char>(v >> (8 * i)));
    };
    uint32_t bytes = static_cast<uint32_t>(2 * keep.pcm.size());
    f.write("RIFF", 4);
    le(36 + bytes, 4);
    f.write("WAVEfmt ", 8);
    le(16, 4);
    le(1, 2);
    le(2, 2);
    le(k.opl3.sample_rate(), 4);
    le(4 * k.opl3.sample_rate(), 4);
    le(4, 2);
    le(16, 2);
    f.write("data", 4);
    le(bytes, 4);
    f.write(reinterpret_cast<const char*>(keep.pcm.data()), bytes);
    std::printf("  wrote %s: %.1f s\n", wav.c_str(), keep.pcm.size() / 2.0 / k.opl3.sample_rate());
    CHECK(!keep.pcm.empty());
}

// SONGKIT starts on a new song's pattern page: its settings, its one order, its one
// pattern (64 empty rows of 18 tracks, five shown); Tab shows its one instrument.
TEST(songkit_editor_starts_with_a_new_song) {
    Editor e;
    if (!e.ok) return;
    CHECK(e.start());
    if (std::getenv("SONGKIT_SHOW")) e.show();
    CHECK(e.row(0).find("SONGKIT") != std::string::npos && e.row(0).find("(a new song)") != std::string::npos);
    CHECK(e.row(2).find("Speed 6   Rate 60   Rows 64   Loop 00    Rhythm no") != std::string::npos);
    CHECK(e.row(3).find("Orders >00 ") != std::string::npos);
    CHECK(e.row(4).substr(5, 61) == "[ ] 0         [ ] 1         [ ] 2         [ ] 3         [ ] 4");
    CHECK(e.row(5).substr(2, 17) == "00 ... .. .. ... " && e.row(28).substr(2, 2) == "17");
    CHECK(e.row(29).find("F1: help") != std::string::npos);
    CHECK(e.row(29).find("Oct 4  Inst 01 Piano") != std::string::npos);
    CHECK(e.row(29).find("Pat 00/01") != std::string::npos);
    CHECK(e.lit(5) == 5); // (the cursor: the first track's note)
    // F1: the help, over the page (the grid hidden); any key, Esc too, back to the page.
    e.key(0x3A);
    CHECK(e.row(29).find("Any key") != std::string::npos && e.row(2).find("A song plays") != std::string::npos);
    bool both = false;
    for (int r = 8; r < 12; ++r) both = both || e.row(r).find("Both pages") != std::string::npos;
    CHECK(both && e.row(5).find("... ..") == std::string::npos);
    e.key(0x29);
    CHECK(e.row(2).find("Speed 6") != std::string::npos && e.row(5).substr(2, 6) == "00 ...");
    CHECK(e.row(29).find("F1: help") != std::string::npos && e.row(0).find("SONGKIT") != std::string::npos);
    // A message over the status line, until the next key.
    e.key(0x2A); // Backspace
    CHECK(e.row(29).find("All notes off") != std::string::npos);
    e.key(0x2F); // [
    CHECK(e.row(29).find("Oct 3") != std::string::npos && e.row(29).find("F1: help") != std::string::npos);
    e.key(0x30); // ]
    e.key(0x2B); // Tab
    CHECK(e.row(2).find("Instrument 1 of 1") != std::string::npos && e.row(2).find("Piano") != std::string::npos);
    CHECK(e.row(9).find("Attack") != std::string::npos);
    // The default instrument is FM (1>2): operator 2 is the one heard, in orange; 3 and 4
    // (a 2-op instrument's) dim, and no values under them.
    auto fg = [&](int r, int c) { return e.v.card().vram[VC_RESET_TEXT_MAP + (r * 128 + c) * 4 + 1]; };
    CHECK(fg(8, 17) == 250 && fg(8, 25) == 214 && fg(8, 33) == 240 && e.row(9).substr(33, 10) == "          ");
}

namespace {
// SONGKIT's variables, by their names in the listing lwasm made.
uint16_t kit_sym(const std::string& name) {
    static std::string lst = host_file(std::string(REPO_DIR) + "/gamekit/build/songkit.lst");
    std::string key = "[ G] " + name + " ";
    size_t at = lst.find(key);
    if (at == std::string::npos) return 0;
    size_t nl = lst.find('\n', at);
    std::string line = lst.substr(at, nl - at);
    return static_cast<uint16_t>(std::stoul(line.substr(line.find_last_of(' ') + 1), nullptr, 16));
}
// The writes to register r in the log from index `from` on.
V writes_to(const std::vector<Opl3Device::Write>& log, size_t from, uint16_t r) {
    V v;
    for (size_t i = from; i < log.size(); ++i)
        if (log[i].reg == r) v.push_back(log[i].value);
    return v;
}
constexpr uint8_t kRight = 0x4F, kLeft = 0x50, kDown = 0x51, kUp = 0x52, kMinus = 0x2D, kPlus = 0x2E;
constexpr uint8_t kZ = 0x1D, kX = 0x1B, kC = 0x06, kOctDn = 0x2F, kEnter = 0x28, kEsc = 0x29;
} // namespace

// The arrows, + and -, the keys as a piano (notes held, chords, an octave down), a sound
// changed while its note is held, new instruments, a name, and the mouse.
TEST(songkit_editor_edits_and_plays_an_instrument) {
    Editor e;
    if (!e.ok) return;
    CHECK(e.start());
    e.key(0x2B); // (Tab: the instrument page)
    // (the instruments are in a RAM page of their own: INPG says which)
    uint16_t inpg = kit_sym("INPG");
    CHECK(inpg != 0);
    auto ib = [&](int i, int n) {
        size_t page = e.s.bus.read_cpu(inpg);
        return e.s.bus.phys_ram()[page * 16384 + 32 * (i - 1) + n];
    };
    // The first operator's attack is lit; right, then down: the second's decay; - makes it 2.
    CHECK(e.lit(9) == 17);
    e.key(kRight);
    e.key(kDown);
    CHECK(e.lit(10) == 25 && e.lit(9) == -1);
    e.key(kMinus);
    CHECK(e.row(10).substr(25, 6) == "2     " && ib(1, 10) == 0xF2);
    CHECK(e.row(0).find("(a new song)*") != std::string::npos);
    // Z held: C-4 on the first voice (track 0, a 4-op channel: the instrument's two operators
    // as 1 and 2, the pair's second connection 1), keyed; let go, the key up.
    size_t mark = e.log.size();
    e.key(kZ, false, false, true);
    CHECK(writes_to(e.log, mark, 0x23) == V({0x21}) && writes_to(e.log, mark, 0x63) == V({0xF2}));
    CHECK(writes_to(e.log, mark, 0xC3) == V({0x31}) && writes_to(e.log, mark, 0xA0) == V({0x59}));
    CHECK(writes_to(e.log, mark, 0xB0).back() == 0x31);
    // A chord: X too, on the next voice (track 1); a change while they're held: both
    // written again, still keyed.
    e.key(kX, false, false, true);
    CHECK(writes_to(e.log, mark, 0xA1) == V({0x83}) && writes_to(e.log, mark, 0xB1).back() == 0x31);
    mark = e.log.size();
    e.key(kPlus);
    CHECK(ib(1, 10) == 0xF3);
    CHECK(writes_to(e.log, mark, 0x63) == V({0xF3}) && writes_to(e.log, mark, 0x64) == V({0xF3}));
    CHECK(writes_to(e.log, mark, 0xB0) == V({0x31}) && writes_to(e.log, mark, 0xB1) == V({0x31}));
    mark = e.log.size();
    e.up(kZ);
    e.up(kX);
    CHECK(writes_to(e.log, mark, 0xB0) == V({0x11}) && writes_to(e.log, mark, 0xB1) == V({0x11}));
    // An octave down: Z is C-3 (block 3).
    e.key(kOctDn);
    CHECK(e.row(29).find("Octave 3") != std::string::npos);
    mark = e.log.size();
    e.key(kZ);
    V b0 = writes_to(e.log, mark, 0xB0);
    CHECK(std::find(b0.begin(), b0.end(), 0x2D) != b0.end());
    // ^N: a new instrument, the second; ^D: a copy of it, the third.
    e.key(0x11, true);
    CHECK(e.row(2).find("Instrument 2 of 2") != std::string::npos);
    e.key(kMinus); // (its second operator's decay 2)
    e.key(0x07, true);
    CHECK(e.row(2).find("Instrument 3 of 3") != std::string::npos && ib(3, 10) == 0xF2 && ib(2, 10) == 0xF2);
    // PgUp: the second; a click on the name renames it.
    e.key(0x4B);
    CHECK(e.row(2).find("Instrument 2 of 3") != std::string::npos);
    e.v.mouse_to(30 * 8 + 4, 2 * 16 + 8, 0);
    e.frames();
    e.v.mouse_to(30 * 8 + 4, 2 * 16 + 8, 1);
    e.frames();
    e.v.mouse_to(30 * 8 + 4, 2 * 16 + 8, 0);
    e.frames();
    CHECK(e.row(29).find("The instrument's name: Piano_") != std::string::npos);
    for (int i = 0; i < 5; ++i) e.key(0x2A); // backspace
    e.text("Bell 2");
    e.key(kEnter);
    CHECK(e.row(2).find("Name  BELL 2") != std::string::npos || e.row(2).find("Name  bell 2") != std::string::npos);
    // The wheel over the first operator's level: one up.
    e.v.mouse_to(17 * 8 + 4, 13 * 16 + 8, 0);
    e.frames(2); // (the pointer there first, as a hand would have it)
    e.v.mouse_wheel(1);
    e.frames(4);
    CHECK(e.lit(13) == 17 && e.row(13).substr(17, 2) == "27" && (ib(2, 4) & 0x3F) == 27);
    if (std::getenv("SONGKIT_SHOW")) e.show();
}

// Files: an instrument saved (.INS) and opened into another; a new song saved; a song with
// music opened (two RAM pages of it), an instrument added, and saved as another file -- its
// patterns as they were, moved on past the larger instrument table, the names after them;
// Space playing it; and Esc, asked first.
TEST(songkit_editor_opens_and_saves) {
    Song song;
    song.ins = {kPiano, ins2({0x22, 0x1A, 0xF2, 0x45, 0x01}, {0x22, 0x00, 0xF3, 0x36, 0x00}, 0x08)};
    song.orders = {0, 1};
    song.loop = 0;
    Pattern p0, p1;
    p0.rows = 16;
    p0.put(0, 0, {N("C-4"), 1}).put(8, 0, {N("E-4"), 2});
    p1.rows = 16;
    p1.put(0, 0, {N("G-4"), 1});
    song.pats = {p0, p1};
    song.pad = {0, 17000};
    std::string old = song.bytes();
    Editor e({disk_file("TUNE.SNG", old)});
    if (!e.ok) return;
    auto be24 = [](const std::vector<uint8_t>& f, size_t at) { return f[at] << 16 | f[at + 1] << 8 | f[at + 2]; };
    auto wait = [&] { e.frames(40); };
    CHECK(e.start("tune"));
    wait();
    CHECK(e.row(5).substr(5, 13) == "C-4 01 .. ..." && e.row(29).find("Opened TUNE.SNG") != std::string::npos);
    e.key(0x2B); // (Tab: the instrument page)
    CHECK(e.row(0).find("TUNE.SNG ") != std::string::npos && e.row(2).find("Instrument 1 of 2") != std::string::npos);
    // Instrument 2 saved as BELL.INS.
    e.key(0x4E); // PgDn
    e.key(0x1A, true);
    CHECK(e.row(29).find("Save the instrument as (.INS): _") != std::string::npos);
    e.text("BELL");
    e.key(kEnter);
    wait();
    std::vector<uint8_t> bell = e.file("/BELL.INS");
    CHECK(bell.size() == 52 && std::string(bell.begin(), bell.begin() + 4) == "PSI1");
    CHECK(std::equal(bell.begin() + 4, bell.begin() + 36, song.ins[1].begin()));
    // Into instrument 1, opened.
    e.key(0x4B); // PgUp
    e.key(0x12, true);
    e.text("BELL.INS");
    e.key(kEnter);
    wait();
    CHECK(e.row(29).find("Opened BELL.INS") != std::string::npos && e.row(0).find("TUNE.SNG*") != std::string::npos);
    // A third instrument, and the song saved as OUT.SNG.
    e.key(0x11, true);
    e.key(0x04, true);
    CHECK(e.row(29).find("Save the song as: TUNE.SNG_") != std::string::npos);
    for (int i = 0; i < 8; ++i) e.key(0x2A);
    e.text("OUT");
    e.key(kEnter);
    wait();
    for (int i = 0; i < 20 && e.row(29).find("Saved") == std::string::npos; ++i) wait();
    CHECK(e.row(29).find("Saved OUT.SNG") != std::string::npos && e.row(0).find("OUT.SNG ") != std::string::npos);
    std::vector<uint8_t> out = e.file("/OUT.SNG");
    std::vector<uint8_t> was(old.begin(), old.end());
    CHECK(out.size() == was.size() + 32 + 3 * 16);
    if (out.size() != was.size() + 32 + 3 * 16) return;
    CHECK(std::equal(out.begin(), out.begin() + 9, was.begin()) && out[9] == 3);
    CHECK(std::equal(out.begin() + 16, out.begin() + 82, was.begin() + 16)); // (title to the orders)
    size_t patstart = 80 + 2 + 8 + 2 * 32;
    CHECK(be24(out, 83) == be24(was, 83) + 32 && be24(out, 87) == be24(was, 87) + 32);
    CHECK(std::equal(out.begin() + 90, out.begin() + 122, song.ins[1].begin())); // (BELL, into 1)
    CHECK(std::equal(out.begin() + 122, out.begin() + 154, song.ins[1].begin()));
    CHECK(std::equal(was.begin() + patstart, was.end(), out.begin() + patstart + 32));
    CHECK(be24(out, 13) == static_cast<int>(was.size() + 32));
    CHECK(std::string(out.end() - 16, out.end()).substr(0, 5) == "Piano");
    // Back to instrument 1 (^Left twice: PgUp without an Fn key).
    e.key(kLeft, true);
    e.key(kLeft, true);
    CHECK(e.row(2).find("Instrument 1 of 3") != std::string::npos);
    e.key(kRight, true);
    CHECK(e.row(2).find("Instrument 2 of 3") != std::string::npos);
    e.key(kLeft, true);
    // Space: the song plays (Timer 2 started), with the instruments as they are now; Space
    // again stops it.
    size_t mark = e.log.size();
    e.key(0x2C);
    e.frames(30);
    CHECK(e.row(29).find("playing") != std::string::npos);
    CHECK(writes_to(e.log, mark, 0x04).size() > 10 && writes_to(e.log, mark, 0x20).size() >= 1);
    CHECK(writes_to(e.log, mark, 0x20)[0] == 0x22); // (instrument 1 is BELL now)
    // A change while it plays is heard at once, on the song's track playing that instrument
    // (track 0, half a second in: C-4 on instrument 1): its first operator's attack, 14.
    mark = e.log.size();
    e.key(kMinus);
    V att = writes_to(e.log, mark, 0x60);
    CHECK(std::find(att.begin(), att.end(), 0xE2) != att.end());
    CHECK(e.row(29).find("playing") != std::string::npos);
    e.key(0x2C);
    CHECK(e.row(29).find("playing") == std::string::npos);
    // Backspace: silence, whatever is sounding (the song too): every operator all the way down.
    e.key(0x2C);
    e.frames(20);
    mark = e.log.size();
    e.key(0x2A);
    CHECK(e.row(29).find("All notes off") != std::string::npos);
    CHECK(e.row(29).find("playing") == std::string::npos);
    CHECK(writes_to(e.log, mark, 0x43).size() >= 1 && writes_to(e.log, mark, 0x43)[0] == 0x3F);
    CHECK(e.opl3.reg(0x104) == 0x3F);
    // Esc, with a change: asked; N: nothing. Esc again, Y: back to the shell.
    e.key(kMinus);
    e.key(kEsc);
    CHECK(e.row(29).find("quit anyway?") != std::string::npos);
    e.key(0x11);
    CHECK(e.row(29).find("quit anyway?") == std::string::npos && e.row(0).find("SONGKIT") != std::string::npos);
    e.key(kEsc);
    e.key(0x1C);
    e.frames(30);
    CHECK(e.v.input_ctrl() == 0);
    CHECK(e.s.bus.bank_register(1) == 1);
}

// The pattern page: notes, a key let go, a volume and an effect typed into cells, each
// packed into the song at once (saved, as the format has it); new patterns and orders, a
// setting or two (the tracks change with rhythm mode and the 4-op pairs); a note put in
// while the song plays, and heard when the song gets to it; rows in and out; the mouse.
TEST(songkit_editor_edits_patterns) {
    Editor e;
    if (!e.ok) return;
    auto wait = [&] { e.frames(40); };
    auto be24 = [](const std::vector<uint8_t>& f, size_t at) { return f[at] << 16 | f[at + 1] << 8 | f[at + 2]; };
    constexpr uint8_t kTab = 0x2B, kSpace = 0x2C, kIns = 0x49, kDel = 0x4C, kHome = 0x4A;
    CHECK(e.start());
    // Record off to start with: ^E (E) on.
    CHECK(e.row(29).find("[ ] Record") != std::string::npos);
    e.key(0x08, true);
    CHECK(e.row(29).find("[x] Record") != std::string::npos);
    // Z: C-4 with instrument 1, heard (track 0: channel 0), on down a row; 1: the key let go.
    size_t mark = e.log.size();
    e.key(kZ, false, false, true);
    CHECK(writes_to(e.log, mark, 0xA0) == V({0x59}) && writes_to(e.log, mark, 0xB0).back() == 0x31);
    e.up(kZ);
    CHECK(writes_to(e.log, mark, 0xB0).back() == 0x11);
    e.key(0x1E);
    // The volume's first digit: 3 (30); the effect: A (A00).
    for (int i = 0; i < 3; ++i) e.key(kRight);
    e.key(0x20);
    e.key(kRight);
    e.key(kRight);
    e.key(0x04);
    CHECK(e.row(5).substr(2, 17) == "00 C-4 01 .. ... ");
    CHECK(e.row(6).substr(5, 13) == "=== .. .. ...");
    CHECK(e.row(7).substr(5, 13) == "... .. 30 ...");
    CHECK(e.row(8).substr(5, 13) == "... .. .. A00");
    CHECK(e.lit(9) == 15 && e.row(0).find("(a new song)*") != std::string::npos);
    // Saved: the pattern packed as the format has it.
    e.key(0x16, true);
    e.text("PAT");
    e.key(kEnter);
    for (int i = 0; i < 20 && e.row(29).find("Saved") == std::string::npos; ++i) wait();
    std::vector<uint8_t> f = e.file("/PAT.SNG");
    CHECK(f.size() > 100);
    if (f.size() < 100) return;
    CHECK(f[9] == 1 && f[10] == 1 && f[11] == 1 && f[81] == 64);
    size_t at = static_cast<size_t>(be24(f, 82)), end = static_cast<size_t>(be24(f, 13));
    const V packed = {0x20, 0x31, 0x01, 0x1F, 0x20, 0x7F, 0x00, 0x1F, 0x40, 0x31, 0x1F, 0x80, 0x41, 0x00, 0x1E, 60};
    CHECK(at == 80 + 1 + 4 + 32 && end == at + packed.size());
    CHECK(end <= f.size() && V(f.begin() + static_cast<long>(at), f.begin() + static_cast<long>(end)) == packed);
    // ^N: a new pattern (01), played by a new order after this one, and shown; ^Up: back.
    e.key(0x11, true);
    CHECK(e.row(3).find(">00 01 ") != std::string::npos && e.row(29).find("Pat 01/02") != std::string::npos);
    CHECK(e.row(5).substr(5, 13) == "... .. .. ...");
    e.key(kUp, true);
    CHECK(e.row(29).find("Pat 00/02") != std::string::npos && e.row(5).substr(5, 3) == "C-4");
    // Alt+Insert: this order again; Alt+Delete: out again; + and -: the order's pattern.
    e.v.key(0xE2, true);
    e.frames(2);
    e.key(kIns);
    CHECK(e.row(3).find(">00 00 01 ") != std::string::npos);
    e.key(kDel);
    e.v.key(0xE2, false);
    e.frames(2);
    CHECK(e.row(3).find(">00 01 ") != std::string::npos && e.row(29).find("Pat 01/02") != std::string::npos);
    e.key(kMinus);
    CHECK(e.row(3).find(">00 00 ") != std::string::npos && e.row(5).substr(5, 3) == "C-4");
    e.key(kPlus);
    CHECK(e.row(3).find(">00 01 ") != std::string::npos);
    e.key(kUp, true);
    // The settings: up from the first row; speed 7; rhythm mode; channels 0 and 3 a 4-op pair
    // (track 3 gone, track 0 marked 4-op).
    e.key(kHome);
    e.key(kUp);
    CHECK(e.lit(1) == 8);
    e.key(kRight);
    e.key(kRight);
    e.key(kPlus);
    CHECK(e.row(2).find("Speed 7 ") != std::string::npos);
    for (int i = 0; i < 4; ++i) e.key(kRight);
    e.key(kPlus);
    CHECK(e.row(2).find("Rhythm yes") != std::string::npos);
    e.key(kRight);
    e.key(kPlus);
    CHECK(e.row(4).substr(5, 10) == "[ ] 0 4-op" && e.row(4).substr(51, 2) == "4 ");
    CHECK(e.opl3.reg(0x104) == 0x01 && (e.opl3.reg(0xBD) & 0x20) != 0);
    // Down to the grid, row 8 of track 1 (from the effect column, where the cursor was);
    // Space plays the song, and E-4 put in there is heard when the song gets there (the song
    // moved along under the player, which keeps its place).
    e.key(kDown);
    for (int i = 0; i < 8; ++i) e.key(kDown);
    for (int i = 0; i < 3; ++i) e.key(kRight);
    CHECK(e.lit(13) == 19);
    e.key(kC);
    CHECK(e.row(13).substr(19, 13) == "E-4 01 .. ...");
    e.key(kSpace);
    mark = e.log.size();
    e.frames(70);
    V b1 = writes_to(e.log, mark, 0xB1);
    CHECK(std::find(b1.begin(), b1.end(), 0x31) != b1.end());
    bool lit = false;
    for (int r = 5; r < 29; ++r) lit = lit || e.bg(r, 2) == 22;
    CHECK(lit);
    e.key(kSpace);
    // Insert: a blank row in track 0 at the top, C-4 a row down; Shift+Delete: back up.
    e.key(kHome);
    for (int i = 0; i < 8; ++i) e.key(kLeft);
    e.key(kIns);
    CHECK(e.row(5).substr(5, 3) == "..." && e.row(6).substr(5, 3) == "C-4");
    e.key(kDel, false, true);
    CHECK(e.row(5).substr(5, 3) == "C-4" && e.row(6).substr(5, 3) == "===");
    // A click: row 5 of the third track shown.
    e.v.mouse_to(33 * 8 + 4, 10 * 16 + 8, 0);
    e.frames();
    e.v.mouse_to(33 * 8 + 4, 10 * 16 + 8, 1);
    e.frames();
    e.v.mouse_to(33 * 8 + 4, 10 * 16 + 8, 0);
    e.frames();
    CHECK(e.lit(10) == 33);
    if (std::getenv("SONGKIT_SHOW")) e.show();
}

// A song across two RAM pages: its first pattern edited (all that comes after it, 17000
// bytes and the second pattern, moved along over the pages' edge), its second one (in the
// second page) too; saved, every byte where it should be.
TEST(songkit_editor_edits_a_song_across_pages) {
    Song song;
    song.ins = {kPiano};
    song.orders = {0, 1};
    Pattern p0, p1;
    p0.rows = 16;
    p0.put(0, 0, {N("C-4"), 1});
    p1.rows = 16;
    p1.put(0, 0, {N("G-4"), 1});
    song.pats = {p0, p1};
    song.pad = {0, 17000};
    std::string old = song.bytes();
    Editor e({disk_file("TUNE.SNG", old)});
    if (!e.ok) return;
    auto be24 = [](const std::vector<uint8_t>& f, size_t at) { return f[at] << 16 | f[at + 1] << 8 | f[at + 2]; };
    CHECK(e.start("tune"));
    e.frames(40);
    e.key(0x08, true); // ^E: Record on
    // Pattern 0: D-4 at row 1 (X), a volume at row 2.
    e.key(kDown);
    e.key(kX);
    for (int i = 0; i < 3; ++i) e.key(kRight);
    e.key(0x1F); // 2: volume 20 (stored one more)
    p0.put(1, 0, {N("D-4"), 1}).put(2, 0, {0, 0, 0x21});
    // Pattern 1 (the next order): A-4 at row 3, and what was at row 0 cleared.
    e.key(kDown, true);
    CHECK(e.row(29).find("Pat 01/02") != std::string::npos && e.row(5).substr(5, 6) == "G-4 01");
    for (int i = 0; i < 3; ++i) e.key(kLeft);
    e.key(0x4A); // Home
    e.key(0x4C); // Delete
    e.key(kDown);
    e.key(kDown);
    e.key(0x10); // M: B-4
    Pattern p1b;
    p1b.rows = 16;
    p1b.put(3, 0, {N("B-4"), 1});
    song.pats = {p0, p1b};
    // ^A: saved as OUT.SNG.
    e.key(0x04, true);
    for (int i = 0; i < 8; ++i) e.key(0x2A);
    e.text("OUT");
    e.key(kEnter);
    for (int i = 0; i < 20 && e.row(29).find("Saved") == std::string::npos; ++i) e.frames(40);
    std::vector<uint8_t> out = e.file("/OUT.SNG");
    std::string w = song.bytes();
    std::vector<uint8_t> want(w.begin(), w.end());
    CHECK(out.size() == want.size() + 16);
    if (out.size() != want.size() + 16) return;
    CHECK(std::equal(want.begin(), want.begin() + 13, out.begin()));
    CHECK(std::equal(want.begin() + 16, want.end(), out.begin() + 16)); // (but the names' place)
    CHECK(be24(out, 13) == static_cast<int>(want.size()));
    if (std::getenv("SONGKIT_SHOW")) e.show();
}

// Following the song as it plays (on to start with): the cursor on the row playing, kept in
// the middle of those shown (the grid's layer scrolled), on into the next order's pattern.
TEST(songkit_editor_follows_the_song) {
    Song song;
    song.ins = {kPiano};
    song.orders = {0, 1};
    song.loop = 0;
    Pattern p0, p1;
    p0.rows = 32;
    p1.rows = 32;
    for (int r = 0; r < 32; r += 4) {
        p0.put(r, 0, {N("C-4"), 1});
        p1.put(r, 1, {N("G-4"), 1});
    }
    song.pats = {p0, p1};
    Editor e({disk_file("TUNE.SNG", song.bytes())});
    if (!e.ok) return;
    CHECK(e.start("tune"));
    e.frames(40);
    auto var = [&](const char* n) { return e.s.bus.read_cpu(kit_sym(n)); };
    auto hex2 = [](int v) {
        char b[3];
        std::snprintf(b, sizeof b, "%02X", v);
        return std::string(b);
    };
    e.key(0x2C); // Space
    e.frames(72); // (1.2 s: row 12 or so)
    int row = var("PLROW");
    CHECK(row >= 9 && row <= 14 && var("CROW") == row && var("PLORD") == 0);
    CHECK(e.row(5 + 11).substr(2, 2) == hex2(row) && e.bg(5 + 11, 2) == 22);
    CHECK(e.row(5 + 11 - (row % 4)).substr(5, 3) == "C-4");
    // On into order 1: its pattern, followed.
    e.frames(150);
    row = var("PLROW");
    CHECK(var("PLORD") == 1 && var("CURORD") == 1 && var("CROW") == row);
    CHECK(e.row(29).find("Pat 01/02") != std::string::npos);
    CHECK(e.row(5 + 11).substr(2, 2) == hex2(row));
    CHECK(e.row(5 + 11 - (row % 4)).substr(19, 3) == "G-4");
    // The help, as it plays: the song goes on under it, and is followed again after.
    e.key(0x3A);
    e.frames(40);
    CHECK(e.row(29).find("Any key") != std::string::npos);
    e.key(0x29);
    e.frames(6);
    row = var("PLROW");
    CHECK(var("CROW") == row && e.row(5 + 11).substr(2, 2) == hex2(row) && e.row(29).find("F1: help") != std::string::npos);
    // The notes kept their time through it all, the next pattern's drawing too: a key down
    // every 4 rows (0.4 s), on track 0 then track 1, within a tick (1/60 s).
    std::vector<uint64_t> on;
    for (auto& w : e.log)
        if ((w.reg == 0xB0 || w.reg == 0xB1) && (w.value & 0x20)) on.push_back(w.cycle);
    double worst = 0;
    for (size_t i = 1; i < on.size(); ++i) {
        double gap = (on[i] - on[i - 1]) / static_cast<double>(kHz);
        worst = std::max(worst, std::abs(gap - 0.4));
    }
    std::printf("  %zu notes, the furthest from 0.4 s apart by %.4f s\n", on.size(), worst);
    CHECK(on.size() >= 8 && worst < 1.0 / 60);
    if (std::getenv("SONGKIT_SHOW")) e.show();
    e.key(0x2C);
}

// Playing in the editor: the song (with no loop) goes back to its start rather than ending;
// Loop pattern (^P) plays the order playing again and again; another order chosen as it plays
// is played from its start; a track muted (^M, or a click on its head) isn't heard; Record
// (^E) off, the keys only play; on, as the song plays, a note goes in the row playing, and
// letting its key go puts its end in.
TEST(songkit_editor_loops_records_and_mutes) {
    Song song;
    song.ins = {kPiano};
    song.orders = {0, 1};
    song.speed = 3; // (20 rows a second: each 16-row pattern 0.8 s)
    Pattern p0, p1;
    p0.rows = 16;
    p1.rows = 16;
    for (int r = 0; r < 16; r += 4) {
        p0.put(r, 0, {N("C-4"), 1});
        p1.put(r, 1, {N("G-4"), 1});
    }
    song.pats = {p0, p1};
    Editor e({disk_file("TUNE.SNG", song.bytes())});
    if (!e.ok) return;
    CHECK(e.start("tune"));
    e.frames(40);
    auto var = [&](const char* n) { return e.s.bus.read_cpu(kit_sym(n)); };
    auto cell = [&](int row, int trk) {
        size_t page = var("PBPG");
        return e.s.bus.phys_ram() + page * 16384 + row * 100 + trk * 5;
    };
    auto keyed = [&](size_t from, uint16_t reg) {
        int n = 0;
        for (size_t i = from; i < e.log.size(); ++i) n += e.log[i].reg == reg && (e.log[i].value & 0x20);
        return n;
    };
    constexpr uint8_t kSpace = 0x2C, kCtlE = 0x08, kCtlP = 0x13, kCtlM = 0x10, kDel = 0x4C, kHome = 0x4A;
    e.key(kHome); // (the message that the song was opened gone: the status line)
    CHECK(e.row(29).find("[ ] Record") != std::string::npos && e.row(29).find("[ ] Loop pattern") != std::string::npos);
    // The song has no loop; in the editor it goes back to its start (2 s on: order 0 again).
    e.key(kSpace);
    e.frames(120);
    CHECK(var("SK_PLAYING") == 1 && var("SONGON") == 1 && var("SK_ORD") == 0);
    // ^P: order 0 again and again; ^P again: on to order 1.
    e.key(kCtlP, true);
    CHECK(e.row(29).find("[x] Loop pattern") != std::string::npos);
    bool stayed = true;
    for (int i = 0; i < 12; ++i) {
        e.frames(6);
        stayed = stayed && var("SK_ORD") == 0;
    }
    CHECK(stayed);
    e.key(kCtlP, true);
    bool on = false;
    for (int i = 0; i < 60 && !on; ++i) {
        e.frames(2);
        on = var("SK_ORD") == 1;
    }
    CHECK(on && var("CURORD") == 1);
    // ^Up as it plays: order 0, from its start.
    e.key(kUp, true);
    CHECK(var("SK_ORD") == 0 && var("SK_ROW") <= 3 && var("CURORD") == 0);
    // ^M: track 0 muted (its head says so): none of its notes keyed on as order 0 plays
    // round (Loop pattern), until it's heard again.
    e.key(kCtlP, true);
    e.key(kCtlM, true);
    CHECK(e.row(4).substr(5, 5) == "[M] 0");
    size_t mark = e.log.size();
    e.frames(60);
    CHECK(keyed(mark, 0xB0) == 0);
    e.key(kCtlM, true);
    CHECK(e.row(4).substr(5, 5) == "[ ] 0");
    mark = e.log.size();
    e.frames(60);
    CHECK(keyed(mark, 0xB0) >= 3);
    // A click on track 1's head mutes it.
    e.v.mouse_to(21 * 8 + 4, 4 * 16 + 8, 0);
    e.frames();
    e.v.mouse_to(21 * 8 + 4, 4 * 16 + 8, 1);
    e.frames();
    e.v.mouse_to(21 * 8 + 4, 4 * 16 + 8, 0);
    e.frames();
    CHECK(e.row(4).substr(19, 5) == "[M] 1");
    // Stopped, Record off (as a song opened starts): a note is heard but doesn't go in, the
    // cursor stays; Delete, plainly an edit, still clears.
    e.key(kSpace);
    e.key(kHome);
    CHECK(e.row(29).find("[ ] Record") != std::string::npos);
    e.key(kDown);
    mark = e.log.size();
    e.key(kZ);
    CHECK(var("CROW") == 1 && cell(1, 0)[0] == 0 && keyed(mark, 0xB0) == 1);
    e.key(kUp);
    e.key(kDel);
    CHECK(cell(0, 0)[0] == 0 && var("CROW") == 1);
    // ^E: Record on. On track 2, as order 0 plays round: Z held goes in the row playing;
    // let go a few rows on, its end goes in there.
    e.key(kCtlE, true);
    for (int i = 0; i < 16; ++i) e.key(kRight);
    CHECK(var("CTRK") == 2 && var("CCOL") == 0);
    e.key(kSpace);
    e.frames(20);
    e.key(kZ, false, false, true);
    int r0 = var("RROW");
    CHECK(var("RKEY") == kZ && cell(r0, 2)[0] == N("C-4") && cell(r0, 2)[1] == 1);
    e.frames(15);
    e.up(kZ);
    int r1 = -1;
    for (int r = 0; r < 16; ++r)
        if (cell(r, 2)[0] == OFF) r1 = r;
    std::printf("  the note in at row %d, its end at row %d\n", r0, r1);
    CHECK(var("RKEY") == 0 && r1 > r0 && r1 <= r0 + 8);
    e.key(kSpace);
    if (std::getenv("SONGKIT_SHOW")) e.show();
}

// SONGKIT's code in overlays: SONGKIT.COM's body is its core (bank 3, at $C000), and after it
// in the file come the overlays (EXE_MORE), each read into a page of its own as it starts;
// OV_EDIT is the one in bank 2 as the pages are edited, and the help's own (OV_HELP) comes
// and goes with F1. Quitting gives every page back, bank 2 its own again. A SONGKIT.COM cut
// short says it is damaged, and leaves nothing behind.
TEST(songkit_editor_keeps_its_code_in_overlays) {
    std::string bin = host_file(std::string(REPO_DIR) + "/gamekit/build/songkit.bin");
    Editor e({disk_file("SKSHORT.COM", bin.substr(0, bin.size() - 100))});
    if (!e.ok) return;
    auto var = [&](const char* n) { return e.s.bus.read_cpu(kit_sym(n)); };
    auto shell = [&](const std::string& cmd) {
        e.s.received.clear();
        for (char ch : cmd) e.s.send_byte(static_cast<uint8_t>(ch));
        e.s.send_byte('\r');
        e.s.wait_for("/> ", 400000000);
        return e.s.received;
    };
    std::string mem = shell("MEM");
    CHECK(mem.find("KB free") != std::string::npos);
    // The file: the header (10 bytes, EXE_MORE), the core, then OV_EDIT, OV_FILE, OV_HELP,
    // OV_BLOCK.
    auto be16 = [&](size_t at) { return static_cast<uint8_t>(bin[at]) << 8 | static_cast<uint8_t>(bin[at + 1]); };
    CHECK(be16(0) == 0x5058 && be16(2) == 0xC000 && be16(6) == 1);
    size_t core = be16(8);
    uint16_t len[4] = {static_cast<uint16_t>(kit_sym("EDITEND") - 0x8000),
                       static_cast<uint16_t>(kit_sym("FILEEND") - 0x8000),
                       static_cast<uint16_t>(kit_sym("HELPEND") - 0x8000),
                       static_cast<uint16_t>(kit_sym("BLOCKEND") - 0x8000)};
    CHECK(core == static_cast<size_t>(kit_sym("COREEND") - 0xC000));
    CHECK(bin.size() == 10 + core + len[0] + len[1] + len[2] + len[3]);
    CHECK(e.start());
    // Each overlay in its page, as the file has it; OV_EDIT in bank 2, the core in bank 3.
    CHECK(var("NOVPG") == 4);
    size_t at = 10 + core;
    for (int i = 0; i < 4; ++i) {
        size_t page = e.s.bus.read_cpu(static_cast<uint16_t>(kit_sym("OVPG") + i));
        CHECK(page > 3 && std::memcmp(e.s.bus.phys_ram() + page * 16384, bin.data() + at, len[i]) == 0);
        at += len[i];
    }
    uint8_t edit = e.s.bus.read_cpu(kit_sym("OVPG"));
    CHECK(var("CUROV") == 0 && e.s.bus.bank_register(2) == edit && e.s.bus.bank_register(3) == 3);
    // F1: the help (from its overlay); a key: the page again, OV_EDIT in bank 2.
    e.key(0x3A);
    CHECK(e.row(2).find("A song plays") != std::string::npos);
    CHECK(var("CUROV") == 0 && e.s.bus.bank_register(2) == edit);
    e.key(0x29);
    CHECK(e.row(2).find("Speed 6") != std::string::npos);
    // ^S: a question from OV_FILE, typed into, answered there.
    e.key(0x16, true);
    CHECK(e.row(29).find("Save the song as: ") != std::string::npos);
    e.text("OVL");
    CHECK(e.row(29).find("Save the song as: OVL_") != std::string::npos);
    e.key(0x28);
    e.frames(30);
    CHECK(e.row(29).find("Saved") != std::string::npos && var("CUROV") == 0);
    // Esc: back to the shell, every page given back, bank 2 its own again.
    e.key(0x29);
    e.frames(60);
    CHECK(e.v.input_ctrl() == 0 && e.s.bus.bank_register(2) == 2 && e.s.bus.bank_register(1) == 1);
    CHECK(shell("MEM") == mem);
    // Cut short: it says so, and gives back the pages it took.
    std::string bad = shell("SKSHORT");
    CHECK(bad.find("SONGKIT.COM is damaged") != std::string::npos);
    CHECK(shell("MEM") == mem);
}

// Blocks: Shift and the cursor's keys select one (shown in purple); ^C copies it, and ^V
// pastes it at the cursor -- the block then what it went into; ^X cuts it; Delete clears it;
// Esc lets it go (and doesn't quit). A paste past the pattern's end, or its last track, is
// cut short; Record off makes no difference (the note column only plays). A drag of the mouse
// selects one too. The orders' ^R and ^X are Alt+Insert and Alt+Delete now.
TEST(songkit_editor_copies_and_pastes_blocks) {
    Song song;
    song.ins = {kPiano};
    song.orders = {0, 1};
    Pattern p0, p1;
    p0.rows = 16;
    p1.rows = 16;
    for (int r = 0; r < 16; r += 4) {
        p0.put(r, 0, {N("C-4"), 1});
        p0.put(r, 1, {N("G-4"), 1, 0x21});
    }
    song.pats = {p0, p1};
    Editor e({disk_file("TUNE.SNG", song.bytes())});
    if (!e.ok) return;
    CHECK(e.start("tune"));
    e.frames(40);
    auto var = [&](const char* n) { return e.s.bus.read_cpu(kit_sym(n)); };
    auto trk = [&](int t) { return e.s.bus.read_cpu(static_cast<uint16_t>(kit_sym("TLIST") + t)); };
    auto cell = [&](int row, int t) {
        size_t page = var("PBPG");
        return e.s.bus.phys_ram() + page * 16384 + row * 100 + trk(t) * 5;
    };
    auto box = [&](int r0, int r1, int t0, int t1) {
        return var("SELON") == 1 && var("SBR0") == r0 && var("SBR1") == r1 && var("SBT0") == t0 &&
               var("SBT1") == t1;
    };
    constexpr uint8_t kC = 0x06, kV = 0x19, kCtlE = 0x08, kDel = 0x4C, kHome = 0x4A, kEnd = 0x4D, kIns = 0x49;
    constexpr uint8_t kSel = 54;
    e.key(kHome);
    e.key(kCtlE, true); // Record on
    // Shift+Down x3, Shift+Right: rows 0-3 of tracks 0 and 1, in purple.
    for (int i = 0; i < 3; ++i) e.key(kDown, false, true);
    e.key(kRight, false, true);
    CHECK(box(0, 3, 0, 1) && var("CROW") == 3 && var("CTRK") == 1);
    CHECK(e.bg(5, 6) == kSel && e.bg(8, 23) == kSel && e.bg(9, 6) != kSel && e.bg(5, 34) != kSel); // (not the cursor's field)
    // ^C: copied, said so; the block stays.
    e.key(kC, true);
    CHECK(e.row(29).find("Copied: 4 rows, 2 tracks") != std::string::npos && var("SELON") == 1);
    CHECK(var("CBROWS") == 4 && var("CBTRKS") == 2);
    // Down (no Shift): the block let go; to row 6, track 2; ^V: pasted there.
    e.key(kDown);
    CHECK(var("SELON") == 0 && e.bg(5, 6) != kSel);
    e.key(kDown);
    e.key(kDown);
    for (int i = 0; i < 8; ++i) e.key(kRight);
    CHECK(var("CROW") == 6 && var("CTRK") == 2 && var("CCOL") == 0);
    e.key(kV, true);
    CHECK(e.row(29).find("Pasted: 4 rows, 2 tracks") != std::string::npos);
    CHECK(cell(6, 2)[0] == N("C-4") && cell(6, 2)[1] == 1 && cell(6, 3)[0] == N("G-4") && cell(6, 3)[2] == 0x21);
    CHECK(cell(7, 2)[0] == 0 && cell(10, 2)[0] == 0 && cell(6, 4)[0] == 0);
    CHECK(box(6, 9, 2, 3) && var("CROW") == 6 && var("CTRK") == 2 && var("CHANGED") == 1);
    CHECK(e.row(11).substr(33, 3) == "C-4" && e.bg(11, 37) == kSel);
    // ^X: cut (not an order out any more); Esc: the block let go, not quitting.
    e.key(0x1B, true);
    CHECK(e.row(29).find("Cut: 4 rows, 2 tracks") != std::string::npos && var("NORD") == 2);
    CHECK(cell(6, 2)[0] == 0 && cell(6, 3)[0] == 0 && e.row(11).substr(33, 3) == "...");
    e.key(0x29);
    CHECK(var("SELON") == 0 && e.row(29).find("quit") == std::string::npos && e.row(0).find("SONGKIT") != std::string::npos);
    // A drag of the mouse, from row 0 of track 0 to row 2 of track 1: a block.
    e.v.mouse_to(6 * 8 + 4, 5 * 16 + 8, 0);
    e.frames();
    e.v.mouse_to(6 * 8 + 4, 5 * 16 + 8, 1);
    e.frames();
    e.v.mouse_to(20 * 8 + 4, 7 * 16 + 8, 1);
    e.frames();
    CHECK(box(0, 2, 0, 1) && var("CROW") == 2 && var("CTRK") == 1 && e.bg(7, 23) == kSel);
    e.v.mouse_to(20 * 8 + 4, 7 * 16 + 8, 0);
    e.frames();
    CHECK(var("DRAG") == 0 && box(0, 2, 0, 1));
    // The last row of the last track: ^V cut short to one cell (what was cut: C-4 first).
    e.key(kEnd);
    for (int i = 0; i < 300 && var("CTRK") + 1 < var("NTL"); ++i) e.key(kRight);
    int last = var("NTL") - 1;
    CHECK(var("CROW") == 15 && var("CTRK") == last);
    e.key(kV, true);
    CHECK(e.row(29).find("Pasted: 1 row, 1 track") != std::string::npos && cell(15, last)[0] == N("C-4"));
    // Record off (the note column only plays): a block is still copied, pasted, cut, cleared.
    e.key(kCtlE, true);
    e.key(kUp);
    e.key(kV, true);
    CHECK(e.row(29).find("Pasted: 2 rows, 1 track") != std::string::npos && cell(14, last)[0] == N("C-4"));
    CHECK(cell(15, last)[0] == 0 && box(14, 15, last, last));
    e.key(kC, true);
    CHECK(e.row(29).find("Copied: 2 rows, 1 track") != std::string::npos);
    e.key(0x1B, true);
    CHECK(e.row(29).find("Cut: 2 rows, 1 track") != std::string::npos && cell(14, last)[0] == 0);
    e.key(kV, true);
    CHECK(cell(14, last)[0] == N("C-4") && box(14, 15, last, last));
    e.key(kDel);
    CHECK(cell(14, last)[0] == 0 && var("SELON") == 1 && var("RECORD") == 0);
    // Alt+Insert: this order again; Alt+Delete: out.
    auto alt = [&](uint8_t usage) {
        e.v.key(0xE2, true);
        e.frames(2);
        e.key(usage);
        e.v.key(0xE2, false);
        e.frames(2);
    };
    alt(kIns);
    CHECK(var("NORD") == 3 && e.row(3).find("00 00 01") != std::string::npos);
    alt(kDel);
    CHECK(var("NORD") == 2);
    if (std::getenv("SONGKIT_SHOW")) e.show();
}
