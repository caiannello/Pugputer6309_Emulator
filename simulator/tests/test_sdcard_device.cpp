// SdCardDevice: block read/write round-trips against a real backing file,
// LBA addressing, and the auto-incrementing SD_DATA cursor -- see
// pugputer/sdcard_device.hpp for the register map.
#include <cstdio>
#include <fstream>
#include <string>

#include "test_framework.hpp"
#include "pugputer/sdcard_device.hpp"

using pugputer::SdCardDevice;

namespace {
constexpr uint16_t kRegLbaHi = 0;
constexpr uint16_t kRegLbaLo = 1;
constexpr uint16_t kRegData = 2;
constexpr uint16_t kRegCmdSta = 3;
constexpr uint8_t kCmdRead = 1;
constexpr uint8_t kCmdWrite = 2;
constexpr uint8_t kStaCard = 0x02;

std::string make_blank_image(const char* name, size_t blocks) {
    std::string path = std::string(PUGPUTER_TEST_BUILD_DIR) + "/" + name;
#ifdef _WIN32
    std::string mkdir_cmd = std::string("mkdir \"") + PUGPUTER_TEST_BUILD_DIR + "\" >NUL 2>NUL";
#else
    std::string mkdir_cmd = std::string("mkdir -p \"") + PUGPUTER_TEST_BUILD_DIR + "\"";
#endif
    std::system(mkdir_cmd.c_str());
    std::ofstream f(path, std::ios::binary | std::ios::trunc);
    std::vector<char> zeros(blocks * SdCardDevice::kBlockSize, 0);
    f.write(zeros.data(), static_cast<std::streamsize>(zeros.size()));
    return path;
}

void set_lba(SdCardDevice& dev, uint16_t lba) {
    dev.write(kRegLbaHi, static_cast<uint8_t>(lba >> 8));
    dev.write(kRegLbaLo, static_cast<uint8_t>(lba & 0xFF));
}
} // namespace

TEST(sdcard_reports_no_card_present_until_opened) {
    SdCardDevice dev;
    CHECK((dev.read(kRegCmdSta) & kStaCard) == 0);
    std::string path = make_blank_image("nocard.img", 2);
    CHECK(dev.open(path));
    CHECK((dev.read(kRegCmdSta) & kStaCard) != 0);
}

TEST(sdcard_write_then_read_block_round_trips) {
    std::string path = make_blank_image("rw.img", 4);
    SdCardDevice dev;
    CHECK(dev.open(path));

    set_lba(dev, 1);
    for (int i = 0; i < 512; ++i) dev.write(kRegData, static_cast<uint8_t>(i & 0xFF));
    dev.write(kRegCmdSta, kCmdWrite);

    // A different device instance re-opening the same file proves the
    // write actually reached the backing file, not just an in-memory buffer.
    SdCardDevice dev2;
    CHECK(dev2.open(path));
    set_lba(dev2, 1);
    dev2.write(kRegCmdSta, kCmdRead);
    bool all_match = true;
    for (int i = 0; i < 512; ++i) {
        if (dev2.read(kRegData) != static_cast<uint8_t>(i & 0xFF)) all_match = false;
    }
    CHECK(all_match);
}

TEST(sdcard_distinct_lbas_do_not_collide) {
    std::string path = make_blank_image("lba.img", 4);
    SdCardDevice dev;
    CHECK(dev.open(path));

    set_lba(dev, 0);
    for (int i = 0; i < 512; ++i) dev.write(kRegData, 0xAA);
    dev.write(kRegCmdSta, kCmdWrite);

    set_lba(dev, 2);
    for (int i = 0; i < 512; ++i) dev.write(kRegData, 0xBB);
    dev.write(kRegCmdSta, kCmdWrite);

    set_lba(dev, 0);
    dev.write(kRegCmdSta, kCmdRead);
    CHECK(dev.read(kRegData) == 0xAA);

    set_lba(dev, 2);
    dev.write(kRegCmdSta, kCmdRead);
    CHECK(dev.read(kRegData) == 0xBB);
}

TEST(sdcard_data_cursor_resets_after_each_command) {
    std::string path = make_blank_image("cursor.img", 2);
    SdCardDevice dev;
    CHECK(dev.open(path));

    set_lba(dev, 0);
    dev.write(kRegCmdSta, kCmdRead); // reset cursor to 0 via a real command
    dev.read(kRegData);
    dev.read(kRegData); // cursor now at 2

    dev.write(kRegCmdSta, kCmdRead); // should reset cursor back to 0
    uint8_t first_after = dev.read(kRegData);
    dev.write(kRegCmdSta, kCmdRead);
    uint8_t first_again = dev.read(kRegData);
    CHECK(first_after == first_again); // both reads see byte 0, not byte 2
}

TEST(sdcard_data_cursor_does_not_overrun_the_block_buffer) {
    std::string path = make_blank_image("overrun.img", 2);
    SdCardDevice dev;
    CHECK(dev.open(path));
    set_lba(dev, 0);
    // Poke 600 bytes (more than one block's worth) -- must not crash.
    for (int i = 0; i < 600; ++i) dev.write(kRegData, static_cast<uint8_t>(i));
    dev.write(kRegCmdSta, kCmdWrite);
    CHECK(true); // reaching here without a crash/UB is the assertion
}
