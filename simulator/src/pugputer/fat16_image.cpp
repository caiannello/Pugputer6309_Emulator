#include "pugputer/fat16_image.hpp"

#include <algorithm>
#include <cctype>
#include <fstream>

namespace pugputer {

namespace {
constexpr size_t kSectorSize = 512;

void put_le16(std::vector<uint8_t>& buf, size_t off, uint16_t v) {
    buf[off] = static_cast<uint8_t>(v & 0xFF);
    buf[off + 1] = static_cast<uint8_t>(v >> 8);
}
void put_le32(std::vector<uint8_t>& buf, size_t off, uint32_t v) {
    buf[off] = static_cast<uint8_t>(v & 0xFF);
    buf[off + 1] = static_cast<uint8_t>((v >> 8) & 0xFF);
    buf[off + 2] = static_cast<uint8_t>((v >> 16) & 0xFF);
    buf[off + 3] = static_cast<uint8_t>((v >> 24) & 0xFF);
}

// 8.3 short name: "BASIC.COM" -> "BASIC   COM" (11 bytes, space-padded,
// uppercased, no dot -- the on-disk directory entry format).
void put_short_name(std::vector<uint8_t>& buf, size_t off, const std::string& name) {
    for (int i = 0; i < 11; ++i) buf[off + i] = ' ';
    size_t dot = name.find('.');
    std::string base = dot == std::string::npos ? name : name.substr(0, dot);
    std::string ext = dot == std::string::npos ? "" : name.substr(dot + 1);
    for (size_t i = 0; i < base.size() && i < 8; ++i)
        buf[off + i] = static_cast<uint8_t>(std::toupper(static_cast<unsigned char>(base[i])));
    for (size_t i = 0; i < ext.size() && i < 3; ++i)
        buf[off + 8 + i] = static_cast<uint8_t>(std::toupper(static_cast<unsigned char>(ext[i])));
}

void set_fat16_entry(std::vector<uint8_t>& fat, uint16_t cluster, uint16_t value) {
    put_le16(fat, static_cast<size_t>(cluster) * 2, value);
}
} // namespace

Fat16BuildResult build_fat16_image(const std::string& path, const std::vector<uint8_t>& dos_payload,
                                    const std::vector<Fat16File>& files, uint32_t total_sectors,
                                    uint8_t sectors_per_cluster, uint16_t root_entry_count, uint8_t num_fats) {
    Fat16BuildResult result;

    uint16_t reserved_sectors =
        static_cast<uint16_t>(1 + (dos_payload.size() + kSectorSize - 1) / kSectorSize);

    uint32_t root_dir_sectors = (static_cast<uint32_t>(root_entry_count) * 32 + kSectorSize - 1) / kSectorSize;

    // Microsoft's standard FAT-size formula (fatgen103): given a target
    // total sector count, solve for how many sectors each FAT needs.
    uint32_t tmp1 = total_sectors - (reserved_sectors + root_dir_sectors);
    uint32_t tmp2 = (256u * sectors_per_cluster) + num_fats;
    uint32_t sectors_per_fat = (tmp1 + tmp2 - 1) / tmp2;

    uint32_t fat_lba = reserved_sectors;
    uint32_t root_lba = fat_lba + num_fats * sectors_per_fat;
    uint32_t data_lba = root_lba + root_dir_sectors;
    uint32_t data_sectors = total_sectors - data_lba;
    uint32_t total_clusters = data_sectors / sectors_per_cluster;

    if (total_clusters < 4085 || total_clusters > 65524) {
        result.error = "resulting cluster count (" + std::to_string(total_clusters) +
                        ") is outside FAT16's valid range (4085-65524); adjust total_sectors/sectors_per_cluster";
        return result;
    }
    std::vector<uint8_t> image(static_cast<size_t>(total_sectors) * kSectorSize, 0);

    // --- Boot sector (BPB) ---
    image[0] = 0xEB;
    image[1] = 0x3C;
    image[2] = 0x90;
    const char* oem = "PUGPUTR ";
    for (int i = 0; i < 8; ++i) image[3 + i] = static_cast<uint8_t>(oem[i]);
    put_le16(image, 0x0B, static_cast<uint16_t>(kSectorSize));
    image[0x0D] = sectors_per_cluster;
    put_le16(image, 0x0E, reserved_sectors);
    image[0x10] = num_fats;
    put_le16(image, 0x11, root_entry_count);
    put_le16(image, 0x13, total_sectors <= 0xFFFF ? static_cast<uint16_t>(total_sectors) : 0);
    image[0x15] = 0xF8; // media descriptor: fixed disk
    put_le16(image, 0x16, static_cast<uint16_t>(sectors_per_fat));
    put_le16(image, 0x18, 0); // sectors/track -- unused, cosmetic only
    put_le16(image, 0x1A, 0); // heads -- unused, cosmetic only
    put_le32(image, 0x1C, 0); // hidden sectors
    put_le32(image, 0x20, total_sectors > 0xFFFF ? total_sectors : 0);
    image[0x24] = 0x80; // drive number
    image[0x25] = 0;
    image[0x26] = 0x29; // extended boot signature
    put_le32(image, 0x27, 0x00000000); // volume ID
    const char* label = "PUGPUTER   ";
    for (int i = 0; i < 11; ++i) image[0x2B + i] = static_cast<uint8_t>(label[i]);
    const char* fstype = "FAT16   ";
    for (int i = 0; i < 8; ++i) image[0x36 + i] = static_cast<uint8_t>(fstype[i]);
    // 0x3E-0x1FD (448 bytes): boot code region, left zero -- this BIOS
    // doesn't execute it (see bios/sdcard.asm's file header).
    image[0x1FE] = 0x55;
    image[0x1FF] = 0xAA;

    // --- DOS payload, LBA 1 onward ---
    for (size_t i = 0; i < dos_payload.size(); ++i) {
        image[kSectorSize + i] = dos_payload[i];
    }

    // --- FAT(s) ---
    std::vector<uint8_t> fat(static_cast<size_t>(sectors_per_fat) * kSectorSize, 0);
    set_fat16_entry(fat, 0, 0xFF00 | image[0x15]);
    set_fat16_entry(fat, 1, 0xFFFF);

    // --- Root directory + file data/cluster chains ---
    std::vector<uint8_t> root_dir(root_dir_sectors * kSectorSize, 0);
    uint16_t next_cluster = 2;
    for (size_t fi = 0; fi < files.size(); ++fi) {
        const Fat16File& f = files[fi];
        size_t entry_off = fi * 32;
        put_short_name(root_dir, entry_off, f.name);
        root_dir[entry_off + 11] = 0x20; // ARCHIVE attribute
        uint16_t start_cluster = next_cluster;
        put_le16(root_dir, entry_off + 26, start_cluster);
        put_le32(root_dir, entry_off + 28, static_cast<uint32_t>(f.data.size()));

        size_t bytes_per_cluster = static_cast<size_t>(sectors_per_cluster) * kSectorSize;
        size_t clusters_needed = f.data.empty() ? 0 : (f.data.size() + bytes_per_cluster - 1) / bytes_per_cluster;
        for (size_t c = 0; c < clusters_needed; ++c) {
            uint16_t cluster = static_cast<uint16_t>(next_cluster + c);
            uint16_t next = (c + 1 < clusters_needed) ? static_cast<uint16_t>(cluster + 1) : 0xFFFF;
            set_fat16_entry(fat, cluster, next);

            size_t cluster_lba = data_lba + static_cast<size_t>(cluster - 2) * sectors_per_cluster;
            size_t src_off = c * bytes_per_cluster;
            size_t n = std::min(bytes_per_cluster, f.data.size() - src_off);
            for (size_t i = 0; i < n; ++i) {
                image[cluster_lba * kSectorSize + i] = f.data[src_off + i];
            }
        }
        next_cluster = static_cast<uint16_t>(next_cluster + clusters_needed);
    }

    for (uint32_t copy = 0; copy < num_fats; ++copy) {
        size_t off = (fat_lba + copy * sectors_per_fat) * kSectorSize;
        for (size_t i = 0; i < fat.size(); ++i) image[off + i] = fat[i];
    }
    for (size_t i = 0; i < root_dir.size(); ++i) image[root_lba * kSectorSize + i] = root_dir[i];

    std::ofstream out(path, std::ios::binary | std::ios::trunc);
    if (!out) {
        result.error = "failed to open '" + path + "' for writing";
        return result;
    }
    out.write(reinterpret_cast<const char*>(image.data()), static_cast<std::streamsize>(image.size()));
    if (!out) {
        result.error = "write to '" + path + "' failed";
        return result;
    }

    result.ok = true;
    return result;
}

} // namespace pugputer
