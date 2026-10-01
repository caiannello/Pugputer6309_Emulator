// The demo programs shipped on the binary release's disk (demo/programs): each must LOAD and
// RUN without an error, with the output it advertises. The disk is built here (mkdiskimg's
// contents plus the demo folder, subfolders and all) so the test doesn't depend on the shared
// disk.img. BASIC starts in /BASIC, where they are, so they load by bare name.
#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <string>
#include <vector>

#include "basic309_file_helpers.hpp"
#include "disk_images.hpp"
#include "pugputer/video_device.hpp"
#include "test_framework.hpp"
#include "vc.h"

namespace {

std::string demo_disk() {
    std::vector<pugputer::Fat16File> extra;
    for (const auto& e : std::filesystem::recursive_directory_iterator(DEMO_DIR)) {
        if (!e.is_regular_file()) continue;
        std::ifstream f(e.path(), std::ios::binary);
        pugputer::Fat16File file;
        file.name = std::filesystem::relative(e.path(), DEMO_DIR).generic_string(); // e.g. "BASIC/HELLO.BAS"
        file.data.assign((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
        extra.push_back(std::move(file));
    }
    return build_image("demo_disk.img", 16384, 2, std::move(extra));
}

std::string run_demo(Basic309Session& s, const std::string& name, uint64_t budget = 200000000) {
    std::string load = s.run_line("LOAD \"" + name + "\"");
    if (!load.empty()) return "<<LOAD: " + load + ">>";
    return s.run_line("RUN", budget);
}

} // namespace

TEST(demo_programs_load_and_run_and_print_what_they_should) {
    std::string img = demo_disk();
    CHECK(!img.empty());
    Basic309Session s;
    CHECK(s.boot_disk(PUGBIOS_S19_PATH, img.c_str()));
    CHECK(s.run_line("CHDIR") == "/BASIC\r\n");

    std::string out = run_demo(s, "HELLO");
    CHECK(contains(out, "HELLO FROM THE PUGPUTER 6309!") && contains(out, "COUNTING 5") && !contains(out, "ERROR"));

    out = run_demo(s, "PRIMES");
    CHECK(contains(out, " 2  3  5  7  11  13 ") && contains(out, " 89  97 ") && !contains(out, "ERROR"));

    out = run_demo(s, "SINE");
    CHECK(!contains(out, "ERROR") && contains(out, "*"));

    out = run_demo(s, "MANDEL", 4000000000ull); // thousands of floating-point iterations: a long run
    CHECK(!contains(out, "ERROR") && contains(out, "................,,,,,,====!> 9nv? Z9     & n >^^>8!=,,......."));

    out = run_demo(s, "SEQFILE");
    CHECK(contains(out, "READ: LINE 1") && contains(out, "READ: LINE 5") && !contains(out, "ERROR"));
    CHECK(!contains(s.run_line("FILES"), "DEMO.TXT")); // it cleans up after itself

    out = run_demo(s, "RANDFILE");
    CHECK(contains(out, "GRACE HOPPER") && contains(out, "ADA LOVELACE") && contains(out, "555-0102") && !contains(out, "ERROR"));
    CHECK(!contains(s.run_line("FILES"), "PHONE.DAT"));

    out = run_demo(s, "ERRTRAP");
    CHECK(contains(out, "100 / 2 = 50") && contains(out, "100 /-2 =-50") && contains(out, "CAN'T DIVIDE BY ZERO: ERROR 10 IN LINE 40") &&
          contains(out, "DONE") && !contains(out, "?"));

    out = run_demo(s, "COLORS");
    CHECK(!contains(out, "ERROR") && contains(out, "\x1b[2J\x1b[H") && contains(out, "\x1b[3;6H\x1b[38;5;0;48;5;0m    ") &&
          contains(out, "\x1b[18;66H\x1b[38;5;0;48;5;255m    "));
    // The two 24-bit rows (red to blue, black to white) are a line each, 64 cells: the escape
    // sequences don't count toward the width.
    size_t first = out.find("\x1b[38;2;0;0;0;48;2;0;0;255m ");
    size_t last = out.find("\x1b[38;2;0;0;0;48;2;255;255;255m ");
    CHECK(first != std::string::npos && last != std::string::npos && last > first);
    if (first != std::string::npos && last != std::string::npos && last > first) {
        std::string rows = out.substr(first, last - first);
        CHECK(std::count(rows.begin(), rows.end(), '\n') == 1); // only the one between them
    }
}

// VIDEO.BAS draws on the video card: the scene, then balls that move until a key is pressed.
TEST(demo_program_video_draws_on_the_video_card) {
    std::string img = demo_disk();
    Basic309Session s;
    CHECK(s.boot_disk(PUGBIOS_S19_PATH, img.c_str()));
    pugputer::VideoDevice v;
    v.set_draw_all(true);
    s.bus.map_device("video", pugputer::VideoDevice::kBase, pugputer::VideoDevice::kSize, &v, pugputer::IrqLine::IRQ);
    CHECK(s.run_line("LOAD \"VIDEO\"").empty());
    s.received.clear();
    s.type("RUN");
    s.bus.run(3579545 * 6); // six seconds: drawing, then the balls
    CHECK(!contains(s.received, "ERROR"));
    const vc_card& c = v.card();
    CHECK(c.cfg[VC_DC_CTRL] == 0x0D);
    auto shown = [&](int i) {
        const uint8_t* p = c.cfg + 0x200 + 2 * i;
        return vc_rgb888(static_cast<uint16_t>(p[0] << 8 | p[1]));
    };
    CHECK(v.pixel(8, 460) == shown(16));   // the ground
    CHECK(v.pixel(320, 210) == shown(214)); // the sun (160,105)
    int words = 0; // "PRESS ANY KEY TO QUIT" on the text screen, row 28 (bobbing up to 4 lines)
    for (int y = 440; y < 464; ++y)
        for (int x = 29 * 8; x < 50 * 8; ++x) words += v.pixel(x, y) == shown(7);
    CHECK(words > 150);
    // The balls are sprites 0-5, moving.
    const uint8_t* t = c.vram + VC_RESET_SPR_BASE;
    int x0 = t[2] << 8 | t[3], y0 = t[4] << 8 | t[5];
    CHECK(t[6] == 0xC5 && t[8 * 3 + 6] == 0x45); // balls 3-5 behind the words
    s.bus.run(3579545);
    CHECK((t[2] << 8 | t[3]) != x0 || (t[4] << 8 | t[5]) != y0);
    if (const char* dump = std::getenv("VIDCARD_DUMP")) {
        std::ofstream f(dump, std::ios::binary);
        for (int i = 0; i < 640 * 480; ++i) {
            uint32_t p = v.pixels()[i];
            char rgb[3] = {static_cast<char>(p >> 16), static_cast<char>(p >> 8), static_cast<char>(p)};
            f.write(rgb, 3);
        }
    }
    // A key: SCREEN 0 and OK.
    s.send_byte('x');
    CHECK(s.run_until_ok(200000000));
    CHECK(c.cfg[VC_DC_CTRL] == 0x01);
}

// MANDELGR.BAS: MANDEL.BAS's set in 320x240, colored by how soon each point escapes. The whole
// picture takes over six billion cycles, so this draws its middle rows only (96-143: the top
// half's last 24 and their mirror images), where the set is widest. Even so it takes half a
// minute, so it runs only when PUGPUTER_SLOW_TESTS is set.
TEST(demo_program_mandelgr_draws_the_set) {
    if (!std::getenv("PUGPUTER_SLOW_TESTS")) {
        std::printf("  (skipped: set PUGPUTER_SLOW_TESTS=1 to run it)\n");
        return;
    }
    std::string img = demo_disk();
    Basic309Session s;
    CHECK(s.boot_disk(PUGBIOS_S19_PATH, img.c_str()));
    pugputer::VideoDevice v;
    v.set_draw_all(true);
    s.bus.map_device("video", pugputer::VideoDevice::kBase, pugputer::VideoDevice::kSize, &v, pugputer::IrqLine::IRQ);
    CHECK(s.run_line("LOAD \"MANDELGR\"").empty());
    s.run_line("120 FOR Y=96 TO 119:D=(Y-119.5)*K:E=D*D:G=E/4:W=239-Y:C=L-H");
    s.received.clear();
    s.type("RUN");
    CHECK(s.wait_for("PRESS ANY KEY", 3000000000ull));
    CHECK(!contains(s.received, "ERROR"));
    s.bus.run(3579545 / 30); // a frame or two, so the picture has it all
    const vc_card& c = v.card();
    auto shown = [&](int i) {
        const uint8_t* p = c.cfg + 0x200 + 2 * i;
        return vc_rgb888(static_cast<uint16_t>(p[0] << 8 | p[1]));
    };
    CHECK(shown(1) == vc_rgb888(0x07FF) && shown(24) == vc_rgb888(0xF81F)); // cyan to magenta
    // The picture is doubled to 640x480. Inside the set: black; far outside: cyan.
    CHECK(v.pixel(2 * 256, 240) == 0);     // c = 0: in the big cardioid
    CHECK(v.pixel(2 * 142, 240) == 0);     // c = -1: in the circle left of it
    CHECK(v.pixel(2, 2 * 96) == shown(1)); // c = -2.24-0.18i: out at once
    // Every color, and the same above the axis and below.
    bool used[256] = {};
    int diff = 0;
    for (int y = 96; y < 120; ++y)
        for (int x = 0; x < 320; ++x) {
            used[c.vram[y * 320 + x]] = true;
            diff += c.vram[y * 320 + x] != c.vram[(239 - y) * 320 + x];
        }
    CHECK(diff == 0);
    int colors = 0;
    for (int i = 0; i < 256; ++i) colors += used[i];
    CHECK(colors == 25 && used[24]);
    if (const char* dump = std::getenv("VIDCARD_DUMP")) {
        std::ofstream f(dump, std::ios::binary);
        for (int i = 0; i < 640 * 480; ++i) {
            uint32_t p = v.pixels()[i];
            char rgb[3] = {static_cast<char>(p >> 16), static_cast<char>(p >> 8), static_cast<char>(p)};
            f.write(rgb, 3);
        }
    }
    s.send_byte('x');
    CHECK(s.run_until_ok(200000000));
    CHECK(c.cfg[VC_DC_CTRL] == 0x01);
}

// VIDBEE.BAS: a picture of 1000 flat-colored triangles in 255 colors (made by
// demo/tools/tri2bas.py), its numbers packed in DATA strings to fit in BASIC's memory. The
// triangles leave no pixel of the picture uncovered, and nothing outside it.
TEST(demo_program_vidbee_draws_its_triangles) {
    std::string img = demo_disk();
    Basic309Session s;
    CHECK(s.boot_disk(PUGBIOS_S19_PATH, img.c_str()));
    pugputer::VideoDevice v;
    v.set_draw_all(true);
    s.bus.map_device("video", pugputer::VideoDevice::kBase, pugputer::VideoDevice::kSize, &v, pugputer::IrqLine::IRQ);
    CHECK(s.run_line("LOAD \"VIDBEE\"").empty());
    s.received.clear();
    s.type("RUN");
    CHECK(s.wait_for("PRESS ANY KEY", 400000000)); // (about 68 seconds' worth)
    CHECK(!contains(s.received, "ERROR"));
    const vc_card& c = v.card();
    int inside = 0, outside = 0;
    bool used[256] = {};
    for (int y = 0; y < 240; ++y)
        for (int x = 0; x < 320; ++x) {
            uint8_t p = c.vram[y * 320 + x]; // (SCREEN 1's bitmap, 8 bits a pixel at 0)
            if (x >= 40 && x < 280) {
                inside += p != 0;
                used[p] = true;
            } else {
                outside += p != 0;
            }
        }
    CHECK(inside == 240 * 240 && outside == 0);
    int colors = 0;
    for (int i = 1; i < 256; ++i) colors += used[i];
    CHECK(colors == 255);
    if (const char* dump = std::getenv("VIDCARD_DUMP")) {
        s.bus.run(3579545 / 30); // a frame or two, so the picture has it all
        std::ofstream f(dump, std::ios::binary);
        for (int i = 0; i < 640 * 480; ++i) {
            uint32_t p = v.pixels()[i];
            char rgb[3] = {static_cast<char>(p >> 16), static_cast<char>(p >> 8), static_cast<char>(p)};
            f.write(rgb, 3);
        }
    }
    s.send_byte('x');
    CHECK(s.run_until_ok(200000000));
    CHECK(c.cfg[VC_DC_CTRL] == 0x01);
}
