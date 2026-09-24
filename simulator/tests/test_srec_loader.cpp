// Motorola S-record loader: correct byte placement + address-range
// reporting, checksum validation catching corruption, and out-of-bounds
// data records being rejected rather than silently truncated/wrapped.
#include <cstdio>
#include <fstream>
#include <string>
#include <vector>

#include "test_framework.hpp"
#include "pugputer/srec_loader.hpp"

using pugputer::load_srec_file;
using pugputer::SrecLoadResult;

namespace {

std::string write_fixture(const char* name, const std::vector<std::string>& lines) {
    std::string path = std::string(PUGPUTER_TEST_BUILD_DIR) + "/" + name;
#ifdef _WIN32
    std::string mkdir_cmd = std::string("mkdir \"") + PUGPUTER_TEST_BUILD_DIR + "\" >NUL 2>NUL";
#else
    std::string mkdir_cmd = std::string("mkdir -p \"") + PUGPUTER_TEST_BUILD_DIR + "\"";
#endif
    std::system(mkdir_cmd.c_str());
    std::ofstream f(path);
    for (const auto& l : lines) f << l << "\n";
    return path;
}

} // namespace

// S1 record: address $1000, data {$11,$22}. byte_count=5 (2 addr + 2 data + 1
// checksum), sum=$05+$10+$00+$11+$22=$48, checksum=~$48&$FF=$B7.
// S9 end-of-file record, address $0000: byte_count=3, sum=3, checksum=$FC.
constexpr const char* kValidS1 = "S10510001122B7";
constexpr const char* kValidS9 = "S9030000FC";

TEST(loads_data_record_into_memory_and_reports_address_range) {
    std::string path = write_fixture("valid.s19", { kValidS1, kValidS9 });
    std::vector<uint8_t> mem(65536, 0xCC);
    SrecLoadResult r = load_srec_file(path, mem.data(), mem.size());
    CHECK(r.ok);
    CHECK(r.error.empty());
    CHECK(mem[0x1000] == 0x11);
    CHECK(mem[0x1001] == 0x22);
    CHECK(mem[0x0FFF] == 0xCC); // untouched neighbor
    CHECK(r.any_data);
    CHECK(r.min_addr == 0x1000);
    CHECK(r.max_addr == 0x1001);
}

TEST(checksum_mismatch_is_rejected) {
    std::string corrupted = "S10510001122B8"; // last byte flipped from B7 to B8
    std::string path = write_fixture("bad_checksum.s19", { corrupted });
    std::vector<uint8_t> mem(65536, 0);
    SrecLoadResult r = load_srec_file(path, mem.data(), mem.size());
    CHECK(!r.ok);
    CHECK(r.error.find("checksum") != std::string::npos);
    CHECK(mem[0x1000] == 0); // rejected before any write
}

TEST(out_of_bounds_data_record_is_rejected_not_wrapped) {
    std::string path = write_fixture("oob.s19", { kValidS1 }); // targets $1000-$1001
    std::vector<uint8_t> mem(0x100, 0xAA); // only 256 bytes -- $1000 is out of range
    SrecLoadResult r = load_srec_file(path, mem.data(), mem.size());
    CHECK(!r.ok);
    CHECK(r.error.find("past the end") != std::string::npos);
}

TEST(missing_file_reports_an_error) {
    std::vector<uint8_t> mem(256, 0);
    SrecLoadResult r = load_srec_file(std::string(PUGPUTER_TEST_BUILD_DIR) + "/does_not_exist.s19", mem.data(),
                                       mem.size());
    CHECK(!r.ok);
    CHECK(!r.error.empty());
}

TEST(multiple_records_track_combined_min_max_address) {
    // A second S1 record at $2000: byte_count=3 (2 addr+0 data+1 checksum)...
    // use 1 data byte instead so it's a meaningful record: address $2000, data {$AA}.
    // byte_count = 2+1+1=4, sum=4+0x20+0x00+0xAA=4+32+0+170=206=0xCE, checksum=~0xCE&0xFF=0x31.
    std::string second = "S1042000AA31";
    std::string path = write_fixture("multi.s19", { kValidS1, second, kValidS9 });
    std::vector<uint8_t> mem(65536, 0);
    SrecLoadResult r = load_srec_file(path, mem.data(), mem.size());
    CHECK(r.ok);
    CHECK(mem[0x2000] == 0xAA);
    CHECK(r.min_addr == 0x1000);
    CHECK(r.max_addr == 0x2000);
}
