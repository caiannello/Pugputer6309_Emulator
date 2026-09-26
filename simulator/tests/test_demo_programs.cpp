// The demo programs shipped on the binary release's disk (demo/programs): each must LOAD and
// RUN without an error, with the output it advertises. The disk is built here (mkdiskimg's
// contents plus the demo folder, subfolders and all) so the test doesn't depend on the shared
// disk.img. BASIC starts in /BASIC, where they are, so they load by bare name.
#include <filesystem>
#include <fstream>
#include <iterator>
#include <string>
#include <vector>

#include "basic309_file_helpers.hpp"
#include "disk_images.hpp"
#include "test_framework.hpp"

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
}
