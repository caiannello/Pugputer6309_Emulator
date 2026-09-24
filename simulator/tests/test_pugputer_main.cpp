#include <cstdio>
#include <string>

#include "test_framework.hpp"

// Usage: pugputer_tests [name-substring ...]
// With arguments, only the tests whose name contains one of them are run --
// handy for the slow disk-backed ones (the full suite takes a few minutes).
int main(int argc, char** argv) {
    int failed_tests = 0;
    size_t ran = 0;
    for (const auto& t : testfw::registry()) {
        if (argc > 1) {
            bool wanted = false;
            for (int i = 1; i < argc; ++i)
                if (t.name.find(argv[i]) != std::string::npos) wanted = true;
            if (!wanted) continue;
        }
        ++ran;
        int before = testfw::g_failures;
        t.fn();
        if (testfw::g_failures != before) {
            std::printf("FAIL %s\n", t.name.c_str());
            ++failed_tests;
        } else {
            std::printf("PASS %s\n", t.name.c_str());
        }
        std::fflush(stdout);
    }
    std::printf("\n%d checks, %d failures, %d/%zu tests failed\n",
                testfw::g_checks, testfw::g_failures, failed_tests, ran);
    return testfw::g_failures == 0 ? 0 : 1;
}
