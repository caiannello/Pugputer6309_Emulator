// Motorola S-record (.s19/.s28/.s37) loader. Applies every S1/S2/S3 data
// record's bytes directly into a caller-supplied memory buffer (typically
// SystemBus::ram()); S0 (header), S5/S6 (record count) and S7/S8/S9 (end
// of file, with an execution-start address this loader ignores -- a
// 6809-family reset vector comes from $FFFE in ROM, not from the S19
// file's end record) are parsed and checksum-validated but produce no
// writes. Every record's checksum is verified; a mismatch is reported as
// an error rather than silently loading corrupt data.
#pragma once

#include <cstddef>
#include <cstdint>
#include <string>

namespace pugputer {

struct SrecLoadResult {
    bool ok = false;
    std::string error; // set when ok == false
    bool any_data = false;
    uint32_t min_addr = 0; // valid only if any_data
    uint32_t max_addr = 0; // inclusive; valid only if any_data
};

// Loads `path` into mem[0..mem_size). Any data record whose address range
// falls outside [0, mem_size) is reported as an error (rather than
// silently truncated or wrapped).
SrecLoadResult load_srec_file(const std::string& path, uint8_t* mem, size_t mem_size);

} // namespace pugputer
