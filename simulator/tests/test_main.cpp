#include <cstdio>

#include "test_framework.hpp"

int main() {
    int failed_tests = 0;
    for (const auto& t : testfw::registry()) {
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
                testfw::g_checks, testfw::g_failures, failed_tests, testfw::registry().size());
    return testfw::g_failures == 0 ? 0 : 1;
}
