// A small independent FAT16 reader for tests: parses a disk image file straight
// off the host filesystem, sharing no code with dos/dos.asm, so it can check what
// DOS actually left on the disk (directory structure, "." and ".." entries,
// cluster chains, free-cluster counts). Read-only. Reload after DOS has written.
#pragma once

#include <cstdint>
#include <cstdio>
#include <fstream>
#include <iterator>
#include <string>
#include <vector>

struct Fat16Volume {
    struct Entry {
        std::string name; // "NAME.EXT" / "NAME" / "." / ".."
        uint8_t attr = 0;
        uint16_t cluster = 0;
        uint32_t size = 0;
        bool is_dir() const { return (attr & 0x10) != 0; }
    };

    std::vector<uint8_t> img;
    uint32_t sec_per_clus = 0, reserved = 0, nfats = 0, sec_per_fat = 0, root_entries = 0, total_sectors = 0;
    uint32_t fat_lba = 0, root_lba = 0, data_lba = 0, clusters = 0;

    bool load(const char* path) {
        std::ifstream f(path, std::ios::binary | std::ios::ate);
        if (!f) return false;
        img.resize(static_cast<size_t>(f.tellg()));
        f.seekg(0);
        f.read(reinterpret_cast<char*>(img.data()), static_cast<std::streamsize>(img.size()));
        return parse();
    }
    // The same for an image already in memory (the crash tests build many).
    bool load_bytes(std::vector<uint8_t> bytes) {
        img = std::move(bytes);
        return parse();
    }
    bool parse() {
        if (img.size() < 512 || img[510] != 0x55 || img[511] != 0xAA) return false;
        if (u16(11) != 512) return false;
        sec_per_clus = img[13];
        reserved = u16(14);
        nfats = img[16];
        root_entries = u16(17);
        total_sectors = u16(19) ? u16(19) : u32(32); // the 32-bit field when the 16-bit one is 0
        sec_per_fat = u16(22);
        fat_lba = reserved;
        root_lba = reserved + nfats * sec_per_fat;
        data_lba = root_lba + root_entries / 16;
        clusters = (total_sectors - data_lba) / sec_per_clus;
        return true;
    }

    uint16_t u16(size_t off) const { return static_cast<uint16_t>(img[off] | (img[off + 1] << 8)); }
    uint32_t u32(size_t off) const { return u16(off) | (static_cast<uint32_t>(u16(off + 2)) << 16); }
    uint16_t fat(uint32_t cluster, int copy = 0) const {
        return u16((static_cast<size_t>(fat_lba) + copy * sec_per_fat) * 512 + cluster * 2);
    }
    uint32_t cluster_lba(uint32_t c) const { return data_lba + (c - 2) * sec_per_clus; }

    // The clusters of a chain, in order (a cycle or a wild link ends it early).
    std::vector<uint16_t> chain(uint16_t first) const {
        std::vector<uint16_t> out;
        for (uint16_t c = first; c >= 2 && c < 0xFFF8 && out.size() <= clusters; c = fat(c)) out.push_back(c);
        return out;
    }

    // Number of free clusters (FAT entry 0) among the volume's data clusters.
    uint32_t free_clusters() const {
        uint32_t n = 0;
        for (uint32_t c = 2; c < clusters + 2; ++c)
            if (fat(c) == 0) ++n;
        return n;
    }
    // Whether the two FAT copies agree (DOS is expected to keep them in sync).
    bool fats_match() const {
        for (uint32_t c = 0; c < clusters + 2 && nfats > 1; ++c)
            if (fat(c, 0) != fat(c, 1)) return false;
        return true;
    }

    static std::string dotted(const uint8_t* e) {
        std::string base(reinterpret_cast<const char*>(e), 8), ext(reinterpret_cast<const char*>(e + 8), 3);
        while (!base.empty() && base.back() == ' ') base.pop_back();
        while (!ext.empty() && ext.back() == ' ') ext.pop_back();
        return ext.empty() ? base : base + "." + ext;
    }

    // Live entries of the directory whose first cluster is `dir` (0 = the root).
    std::vector<Entry> entries(uint16_t dir) const {
        std::vector<uint32_t> sectors;
        if (dir == 0) {
            for (uint32_t i = 0; i < root_entries / 16; ++i) sectors.push_back(root_lba + i);
        } else {
            for (uint16_t c : chain(dir))
                for (uint32_t i = 0; i < sec_per_clus; ++i) sectors.push_back(cluster_lba(c) + i);
        }
        std::vector<Entry> out;
        for (uint32_t lba : sectors) {
            for (int i = 0; i < 16; ++i) {
                const uint8_t* e = &img[static_cast<size_t>(lba) * 512 + i * 32];
                if (e[0] == 0) return out; // no more entries
                if (e[0] == 0xE5 || (e[11] & 0x08)) continue;
                Entry en;
                en.name = dotted(e);
                en.attr = e[11];
                en.cluster = static_cast<uint16_t>(e[26] | (e[27] << 8));
                en.size = e[28] | (e[29] << 8) | (e[30] << 16) | (static_cast<uint32_t>(e[31]) << 24);
                out.push_back(en);
            }
        }
        return out;
    }

    // Resolves an absolute "/A/B/C" path to its entry; false if any part is missing.
    bool find(const std::string& path, Entry& out) const {
        uint16_t dir = 0;
        size_t i = 0;
        bool have = false;
        while (i < path.size()) {
            while (i < path.size() && path[i] == '/') ++i;
            if (i >= path.size()) break;
            size_t j = path.find('/', i);
            std::string part = path.substr(i, j == std::string::npos ? std::string::npos : j - i);
            i = j == std::string::npos ? path.size() : j;
            bool found = false;
            for (const Entry& e : entries(dir)) {
                if (e.name == part) {
                    out = e;
                    found = true;
                    break;
                }
            }
            if (!found) return false;
            have = true;
            dir = out.cluster;
        }
        if (!have) {
            out = Entry{};
            out.name = "/";
            out.attr = 0x10;
        }
        return true;
    }

    // A file's contents by following its chain, cut to its size.
    std::vector<uint8_t> read(const Entry& e) const {
        std::vector<uint8_t> out;
        for (uint16_t c : chain(e.cluster))
            for (uint32_t s = 0; s < sec_per_clus; ++s) {
                const uint8_t* p = &img[(static_cast<size_t>(cluster_lba(c)) + s) * 512];
                out.insert(out.end(), p, p + 512);
            }
        if (out.size() > e.size) out.resize(e.size);
        return out;
    }
};
