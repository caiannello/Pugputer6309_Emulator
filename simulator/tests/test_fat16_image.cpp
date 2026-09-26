// fat16_image builder: BPB signature/fields are well-formed, and a file's
// bytes round-trip correctly through the root directory + FAT16 cluster
// chain it writes -- verified with a minimal independent reader here
// (deliberately not sharing code with dos/dos.asm's parser, same
// arrangement srec_loader.cpp has with the S-record spec: both sides
// implement the same well-known format, not one calling the other).
#include <cstdio>
#include <fstream>
#include <string>
#include <vector>

#include "fat16_reader.hpp"
#include "test_framework.hpp"
#include "pugputer/fat16_image.hpp"

using pugputer::build_fat16_image;
using pugputer::Fat16File;

namespace {
constexpr size_t kSectorSize = 512;

std::string out_path(const char* name) {
    std::string path = std::string(PUGPUTER_TEST_BUILD_DIR) + "/" + name;
#ifdef _WIN32
    std::string mkdir_cmd = std::string("mkdir \"") + PUGPUTER_TEST_BUILD_DIR + "\" >NUL 2>NUL";
#else
    std::string mkdir_cmd = std::string("mkdir -p \"") + PUGPUTER_TEST_BUILD_DIR + "\"";
#endif
    std::system(mkdir_cmd.c_str());
    return path;
}

std::vector<uint8_t> read_whole_file(const std::string& path) {
    std::ifstream f(path, std::ios::binary);
    return std::vector<uint8_t>((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
}

uint16_t get_le16(const std::vector<uint8_t>& b, size_t off) {
    return static_cast<uint16_t>(b[off] | (b[off + 1] << 8));
}
uint32_t get_le32(const std::vector<uint8_t>& b, size_t off) {
    return static_cast<uint32_t>(b[off]) | (static_cast<uint32_t>(b[off + 1]) << 8) |
           (static_cast<uint32_t>(b[off + 2]) << 16) | (static_cast<uint32_t>(b[off + 3]) << 24);
}

// Minimal independent FAT16 reader: finds `short_name` (e.g. "BASIC   COM",
// 11 bytes, space-padded, no dot) in the root directory and returns its
// full reconstructed byte contents by walking the cluster chain.
std::vector<uint8_t> read_fat16_file(const std::vector<uint8_t>& image, const char short_name[11]) {
    uint16_t reserved = get_le16(image, 0x0E);
    uint8_t num_fats = image[0x10];
    uint16_t root_entry_count = get_le16(image, 0x11);
    uint16_t sec_per_fat = get_le16(image, 0x16);
    uint8_t sec_per_clus = image[0x0D];

    uint32_t fat_lba = reserved;
    uint32_t root_lba = fat_lba + static_cast<uint32_t>(num_fats) * sec_per_fat;
    uint32_t root_dir_sectors = (static_cast<uint32_t>(root_entry_count) * 32 + kSectorSize - 1) / kSectorSize;
    uint32_t data_lba = root_lba + root_dir_sectors;

    size_t root_off = static_cast<size_t>(root_lba) * kSectorSize;
    uint16_t start_cluster = 0;
    uint32_t file_size = 0;
    bool found = false;
    for (uint16_t e = 0; e < root_entry_count; ++e) {
        size_t entry_off = root_off + static_cast<size_t>(e) * 32;
        bool match = true;
        for (int i = 0; i < 11; ++i) {
            if (image[entry_off + i] != static_cast<uint8_t>(short_name[i])) {
                match = false;
                break;
            }
        }
        if (match) {
            start_cluster = get_le16(image, entry_off + 26);
            file_size = get_le32(image, entry_off + 28);
            found = true;
            break;
        }
    }
    if (!found) return {};

    std::vector<uint8_t> out;
    uint16_t cluster = start_cluster;
    while (cluster < 0xFFF8) {
        size_t cluster_lba = data_lba + static_cast<size_t>(cluster - 2) * sec_per_clus;
        size_t off = cluster_lba * kSectorSize;
        for (size_t i = 0; i < static_cast<size_t>(sec_per_clus) * kSectorSize && out.size() < file_size; ++i) {
            out.push_back(image[off + i]);
        }
        size_t fat_entry_off = static_cast<size_t>(fat_lba) * kSectorSize + static_cast<size_t>(cluster) * 2;
        cluster = get_le16(image, fat_entry_off);
    }
    return out;
}
} // namespace

TEST(fat16_image_has_valid_boot_signature_and_fs_type) {
    std::string path = out_path("sig.img");
    std::vector<uint8_t> dos_payload(200, 0xEE);
    auto result = build_fat16_image(path, dos_payload, {});
    CHECK(result.ok);
    if (!result.ok) return;

    std::vector<uint8_t> image = read_whole_file(path);
    CHECK(image[0x1FE] == 0x55);
    CHECK(image[0x1FF] == 0xAA);
    CHECK(std::string(image.begin() + 0x36, image.begin() + 0x36 + 8) == "FAT16   ");
    CHECK(get_le16(image, 0x0B) == 512);
}

TEST(fat16_image_dos_payload_lands_at_lba_1) {
    std::string path = out_path("dospayload.img");
    std::vector<uint8_t> dos_payload = { 0x01, 0x02, 0x03, 0x04 };
    auto result = build_fat16_image(path, dos_payload, {});
    CHECK(result.ok);
    if (!result.ok) return;

    std::vector<uint8_t> image = read_whole_file(path);
    CHECK(image[512] == 0x01);
    CHECK(image[513] == 0x02);
    CHECK(image[514] == 0x03);
    CHECK(image[515] == 0x04);

    // Reserved sector count must cover the boot sector + the payload.
    CHECK(get_le16(image, 0x0E) == 2); // 1 boot sector + 1 sector (4 bytes rounds up)
}

TEST(fat16_image_file_round_trips_through_root_dir_and_cluster_chain) {
    std::string path = out_path("roundtrip.img");
    std::vector<uint8_t> dos_payload(50, 0);
    Fat16File f;
    f.name = "BASIC.COM";
    f.data.resize(5000);
    for (size_t i = 0; i < f.data.size(); ++i) f.data[i] = static_cast<uint8_t>(i * 7 + 3);

    auto result = build_fat16_image(path, dos_payload, { f });
    CHECK(result.ok);
    if (!result.ok) return;

    std::vector<uint8_t> image = read_whole_file(path);
    std::vector<uint8_t> readback = read_fat16_file(image, "BASIC   COM");
    CHECK(readback.size() == f.data.size());
    CHECK(readback == f.data);
}

TEST(fat16_image_multiple_files_do_not_collide) {
    std::string path = out_path("multi.img");
    std::vector<uint8_t> dos_payload(50, 0);
    Fat16File a;
    a.name = "A.TXT";
    a.data = { 'a', 'a', 'a' };
    Fat16File b;
    b.name = "B.TXT";
    b.data = { 'b', 'b', 'b', 'b', 'b' };

    auto result = build_fat16_image(path, dos_payload, { a, b });
    CHECK(result.ok);
    if (!result.ok) return;

    std::vector<uint8_t> image = read_whole_file(path);
    CHECK(read_fat16_file(image, "A       TXT") == a.data);
    CHECK(read_fat16_file(image, "B       TXT") == b.data);
}

TEST(fat16_image_rejects_a_cluster_count_outside_fat16_range) {
    // A tiny disk can't reach the 4085-cluster minimum -- must fail
    // cleanly instead of silently producing a FAT12-range volume.
    std::string path = out_path("toosmall.img");
    std::vector<uint8_t> dos_payload(10, 0);
    auto result = build_fat16_image(path, dos_payload, {}, /*total_sectors=*/100);
    CHECK(!result.ok);
    CHECK(!result.error.empty());
}

TEST(fat16_image_puts_names_with_slashes_in_subdirectories) {
    std::string path = out_path("subdirs.img");
    std::vector<uint8_t> dos_payload(50, 0);
    std::vector<Fat16File> files;
    Fat16File top;
    top.name = "TOP.TXT";
    top.data = {'t'};
    files.push_back(top);
    for (int i = 0; i < 40; ++i) { // more than one cluster's worth of entries (32 per 1KB cluster)
        Fat16File f;
        f.name = "cmd/F" + std::to_string(i) + ".COM"; // (lower case: folded like the file names)
        f.data.assign(static_cast<size_t>(100 + i * 50), static_cast<uint8_t>(i));
        files.push_back(f);
    }
    Fat16File deep;
    deep.name = "A/B/DEEP.DAT";
    deep.data.assign(3000, 0x5A);
    files.push_back(deep);
    auto result = build_fat16_image(path, dos_payload, files);
    CHECK(result.ok);
    if (!result.ok) return;

    Fat16Volume v;
    CHECK(v.load(path.c_str()));
    Fat16Volume::Entry e;
    CHECK(v.find("/TOP.TXT", e) && v.read(e) == top.data);
    CHECK(v.find("/CMD", e) && e.is_dir() && e.size == 0);
    uint16_t cmd_cluster = e.cluster;
    CHECK(v.chain(cmd_cluster).size() == 2); // 42 entries: 2 clusters
    auto cmd = v.entries(cmd_cluster);
    CHECK(cmd.size() == 42);
    CHECK(cmd[0].name == "." && cmd[0].is_dir() && cmd[0].cluster == cmd_cluster);
    CHECK(cmd[1].name == ".." && cmd[1].is_dir() && cmd[1].cluster == 0);
    for (int i = 0; i < 40; ++i) {
        CHECK(v.find("/CMD/F" + std::to_string(i) + ".COM", e) && v.read(e) == files[static_cast<size_t>(i) + 1].data);
    }
    CHECK(v.find("/A/B/DEEP.DAT", e) && v.read(e) == deep.data);
    CHECK(v.find("/A/B", e) && e.is_dir());
    auto b = v.entries(e.cluster);
    CHECK(v.find("/A", e));
    CHECK(b.size() == 3 && b[1].name == ".." && b[1].cluster == e.cluster);
    auto root = v.entries(0);
    CHECK(root.size() == 3 && root[0].name == "TOP.TXT" && root[1].name == "CMD" && root[2].name == "A");
    CHECK(v.fats_match());
}

TEST(fat16_image_rejects_files_that_do_not_fit) {
    std::string path = out_path("toofull.img");
    Fat16File big;
    big.name = "BIG.DAT";
    big.data.assign(9u * 1024 * 1024, 0); // an 8MB volume
    CHECK(!build_fat16_image(path, std::vector<uint8_t>(10, 0), {big}).ok);
}
