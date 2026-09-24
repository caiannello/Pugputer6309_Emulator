#include "pugputer/srec_loader.hpp"

#include <cstdio>
#include <fstream>
#include <vector>

namespace pugputer {

namespace {

bool hex_nibble(char c, unsigned& out) {
    if (c >= '0' && c <= '9') { out = static_cast<unsigned>(c - '0'); return true; }
    if (c >= 'A' && c <= 'F') { out = static_cast<unsigned>(c - 'A' + 10); return true; }
    if (c >= 'a' && c <= 'f') { out = static_cast<unsigned>(c - 'a' + 10); return true; }
    return false;
}

bool hex_byte(const std::string& s, size_t pos, uint8_t& out) {
    if (pos + 1 >= s.size()) return false;
    unsigned hi, lo;
    if (!hex_nibble(s[pos], hi) || !hex_nibble(s[pos + 1], lo)) return false;
    out = static_cast<uint8_t>((hi << 4) | lo);
    return true;
}

std::string rstrip(std::string s) {
    while (!s.empty() && (s.back() == '\r' || s.back() == '\n' || s.back() == ' ' || s.back() == '\t')) s.pop_back();
    return s;
}

std::string err_at(const std::string& path, int line_no, const std::string& msg) {
    return path + ":" + std::to_string(line_no) + ": " + msg;
}

} // namespace

SrecLoadResult load_srec_file(const std::string& path, uint8_t* mem, size_t mem_size) {
    SrecLoadResult result;
    std::ifstream f(path);
    if (!f) {
        result.error = "could not open '" + path + "'";
        return result;
    }

    std::string line;
    int line_no = 0;
    while (std::getline(f, line)) {
        ++line_no;
        line = rstrip(line);
        if (line.empty()) continue;
        if (line[0] != 'S' && line[0] != 's') {
            result.error = err_at(path, line_no, "expected a line starting with 'S'");
            return result;
        }
        if (line.size() < 4) {
            result.error = err_at(path, line_no, "record too short");
            return result;
        }
        char type = line[1];

        uint8_t byte_count;
        if (!hex_byte(line, 2, byte_count)) {
            result.error = err_at(path, line_no, "malformed byte count field");
            return result;
        }

        unsigned addr_bytes;
        bool is_data = false;
        switch (type) {
            case '0': addr_bytes = 2; break;
            case '1': addr_bytes = 2; is_data = true; break;
            case '2': addr_bytes = 3; is_data = true; break;
            case '3': addr_bytes = 4; is_data = true; break;
            case '5': addr_bytes = 2; break;
            case '6': addr_bytes = 3; break;
            case '7': addr_bytes = 4; break;
            case '8': addr_bytes = 3; break;
            case '9': addr_bytes = 2; break;
            default: {
                std::string t(1, type);
                result.error = err_at(path, line_no, "unknown record type 'S" + t + "'");
                return result;
            }
        }

        // Expected line length (excluding any trailing whitespace already
        // stripped): "Sx" + 2-hex-char count field + byte_count*2 hex chars.
        size_t expected_len = 4 + static_cast<size_t>(byte_count) * 2;
        if (line.size() < expected_len) {
            result.error = err_at(path, line_no, "record shorter than its byte count declares");
            return result;
        }
        if (byte_count < addr_bytes + 1) {
            result.error = err_at(path, line_no, "byte count too small for this record type");
            return result;
        }

        // Checksum: one's complement of the low 8 bits of the sum of every
        // byte except the checksum byte itself (byte-count field, address
        // bytes, data bytes).
        unsigned sum = byte_count;
        uint32_t address = 0;
        size_t pos = 4;
        for (unsigned i = 0; i < addr_bytes; ++i) {
            uint8_t b;
            if (!hex_byte(line, pos, b)) {
                result.error = err_at(path, line_no, "malformed address field");
                return result;
            }
            address = (address << 8) | b;
            sum += b;
            pos += 2;
        }

        unsigned data_len = static_cast<unsigned>(byte_count) - addr_bytes - 1;
        std::vector<uint8_t> data(data_len);
        for (unsigned i = 0; i < data_len; ++i) {
            uint8_t b;
            if (!hex_byte(line, pos, b)) {
                result.error = err_at(path, line_no, "malformed data field");
                return result;
            }
            data[i] = b;
            sum += b;
            pos += 2;
        }

        uint8_t checksum;
        if (!hex_byte(line, pos, checksum)) {
            result.error = err_at(path, line_no, "malformed checksum field");
            return result;
        }
        uint8_t expected_checksum = static_cast<uint8_t>(~sum & 0xFFu);
        if (checksum != expected_checksum) {
            char buf[64];
            std::snprintf(buf, sizeof(buf), "checksum mismatch (got $%02X, expected $%02X)", checksum, expected_checksum);
            result.error = err_at(path, line_no, buf);
            return result;
        }

        if (is_data && data_len > 0) {
            if (address + data_len > mem_size) {
                char buf[96];
                std::snprintf(buf, sizeof(buf), "data record at $%04X extends past the end of the target memory (%zu bytes)",
                              address, mem_size);
                result.error = err_at(path, line_no, buf);
                return result;
            }
            for (unsigned i = 0; i < data_len; ++i) mem[address + i] = data[i];

            uint32_t end = address + data_len - 1;
            if (!result.any_data) {
                result.any_data = true;
                result.min_addr = address;
                result.max_addr = end;
            } else {
                if (address < result.min_addr) result.min_addr = address;
                if (end > result.max_addr) result.max_addr = end;
            }
        }
        // S0/S5/S6/S7/S8/S9: checksum-validated above; no data applied.
    }

    result.ok = true;
    return result;
}

} // namespace pugputer
