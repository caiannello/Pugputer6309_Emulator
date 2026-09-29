// The video card's demo (demo/programs/ASM/VIDEO/VIDDEMO.ASM) as the demo disk has it: ASM
// assembles it on the machine, byte for byte what the release disk's /DEMO/VIDDEMO.COM is,
// and it runs with the card at $FF80 -- layers, sprites and commands on the picture.
#include <cstdlib>
#include <fstream>
#include <iterator>
#include <string>
#include <vector>

#include "basic309_session.hpp"
#include "disk_images.hpp"
#include "fat16_reader.hpp"
#include "pugputer/video_device.hpp"
#include "test_framework.hpp"
#include "vc.h"

using pugputer::VideoDevice;

namespace {

std::string host_text(const std::string& path) {
    std::ifstream f(path, std::ios::binary);
    return std::string((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
}

pugputer::Fat16File disk_file(const char* name, const std::string& data) {
    pugputer::Fat16File f;
    f.name = name;
    f.data.assign(data.begin(), data.end());
    return f;
}

// The color the card shows for palette entry i.
uint32_t shown(VideoDevice& v, int i) {
    const uint8_t* pal = v.card().cfg + (VC_PAL_BASE - VC_CFG_BASE);
    return vc_rgb888(static_cast<uint16_t>(pal[2 * i] << 8 | pal[2 * i + 1]));
}

uint16_t be16(const uint8_t* p) { return static_cast<uint16_t>(p[0] << 8 | p[1]); }

} // namespace

TEST(vidcard_demo_assembles_on_the_machine_and_draws_its_scene) {
    std::string src = host_text(std::string(DEMO_DIR) + "/ASM/VIDEO/VIDDEMO.ASM");
    std::string inc = host_text(std::string(REPO_DIR) + "/vidcard/vidcard.d");
    std::string asm_com = host_text(ASM_BIN_PATH);
    CHECK(!src.empty() && !inc.empty() && !asm_com.empty());
    std::string img = build_image("vidcard_demo.img", 32768, 4,
                                  {disk_file("VIDDEMO.ASM", src), disk_file("VIDCARD.D", inc), disk_file("ASM.COM", asm_com)});
    Basic309Session s;
    CHECK(s.boot_shell(PUGBIOS_S19_PATH, img.c_str()));
    VideoDevice v;
    v.set_draw_all(true);
    s.bus.map_device("video", VideoDevice::kBase, VideoDevice::kSize, &v, pugputer::IrqLine::IRQ);
    auto type = [&](const std::string& cmd) {
        s.received.clear();
        for (char ch : cmd) s.send_byte(static_cast<uint8_t>(ch));
        s.send_byte('\r');
    };
    auto prompt = [&](uint64_t budget) {
        for (uint64_t spent = 0; spent < budget;) {
            uint64_t got = s.bus.run(20000);
            if (got == 0) return false;
            spent += got;
            const std::string& r = s.received;
            if (r.size() > 4 && r.compare(r.size() - 3, 3, "/> ") == 0) return true;
        }
        return false;
    };
    type("ASM -f com viddemo.asm");
    CHECK(prompt(4000000000ull));
    CHECK(s.received.find("rror") == std::string::npos);
    Fat16Volume vol;
    Fat16Volume::Entry e;
    CHECK(vol.load(img.c_str()) && vol.find("/VIDDEMO.COM", e));
    std::string raw = host_text(std::string(REPO_DIR) + "/demo/build/viddemo.bin");
    std::vector<uint8_t> made = vol.read(e);
    CHECK(!raw.empty() && std::string(made.begin(), made.end()) == std::string("PX\x40\x00\x40\x00\x00\x00", 8) + raw);
    CHECK(!v.active());

    // Run it for a second of the machine's time.
    type("VIDDEMO");
    s.bus.run(3579545);
    CHECK(v.active() && v.frames_drawn() >= 55);
    const vc_card& c = v.card();
    CHECK(c.cfg[VC_DC_CTRL] == 0x0F && c.cfg[VC_SPR_COUNT] == 8);
    // Layer 0, the bitmap: the sky's top band, the sun, the black ground.
    CHECK(v.pixel(0, 0) == shown(v, 17) && v.pixel(639, 19) == shown(v, 17) && v.pixel(0, 20) == shown(v, 18));
    CHECK(v.pixel(320, 200) == shown(v, 214)); // the sun's middle (160,100 in 320x240)
    CHECK(v.pixel(8, 460) == shown(v, 16));
    // Layer 2, the title: white letters on black at row 1, columns 27-52.
    int white = 0;
    for (int y = 16; y < 32; ++y)
        for (int x = 27 * 8; x < 53 * 8; ++x) white += v.pixel(x, y) == shown(v, 231);
    CHECK(white > 200);
    CHECK(v.pixel(27 * 8, 16) == shown(v, 16));
    // Layer 1 scrolls a pixel a frame; the balls move.
    const uint8_t* hs = c.cfg + VC_LAYER0 + VC_LAYER_SIZE + VC_L_HSCROLL;
    const uint8_t* ball = c.vram + VC_RESET_SPR_BASE;
    uint16_t scroll = be16(hs), bx = be16(ball + 2), by = be16(ball + 4);
    CHECK(scroll >= 45 && scroll <= 61); // (less the time it takes to load and set up)
    CHECK(ball[6] == 0xC5 && ball[7] == 0x80);
    s.bus.run(3579545 / 2);
    CHECK(be16(hs) - scroll >= 29 && be16(hs) - scroll <= 31);
    CHECK(be16(ball + 2) != bx && be16(ball + 4) != by);
    // A ball is on the picture where its table entry puts it (doubled: 320x240).
    int bx2 = be16(ball + 2) * 2 + 14, by2 = be16(ball + 4) * 2 + 14;
    CHECK(v.pixel(bx2, by2) == shown(v, 196));
    // VIDCARD_DUMP=file: the picture, 640x480 RGB bytes, to look at.
    if (const char* dump = std::getenv("VIDCARD_DUMP")) {
        std::ofstream f(dump, std::ios::binary);
        for (int i = 0; i < VideoDevice::kWidth * VideoDevice::kHeight; ++i) {
            uint32_t p = v.pixels()[i];
            char rgb[3] = {static_cast<char>(p >> 16), static_cast<char>(p >> 8), static_cast<char>(p)};
            f.write(rgb, 3);
        }
    }
    // A key: the card is reset (the blank text screen) and the shell is back.
    type("x");
    CHECK(prompt(100000000));
    CHECK(c.cfg[VC_DC_CTRL] == 0x01 && c.cfg[VC_DC_BACK] == 0);
}
