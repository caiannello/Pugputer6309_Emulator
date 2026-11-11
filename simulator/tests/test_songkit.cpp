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
#include "test_framework.hpp"

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
