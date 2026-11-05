#include <cstdio>
#include <cstring>

#include "test_framework.hpp"

// pugputer_tests [text]: only the tests whose names contain `text` (all of them without it).
int main(int argc, char** argv) {
    int failed_tests = 0;
    size_t ran = 0;
    for (const auto& t : testfw::registry()) {
        if (argc > 1 && std::strstr(t.name.c_str(), argv[1]) == nullptr) continue;
        ++ran;
        int before = testfw::g_failures;
        t.fn();
        if (testfw::g_failures != before) {
            std::printf("FAIL %s\n", t.name.c_str());
            ++failed_tests;
        } else {
            std::printf("PASS %s\n", t.name.c_str());
        }
    }
    std::printf("\n%d checks, %d failures, %d/%zu tests failed\n",
                testfw::g_checks, testfw::g_failures, failed_tests, ran);
    return testfw::g_failures == 0 ? 0 : 1;
}
