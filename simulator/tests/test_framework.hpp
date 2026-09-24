// Minimal header-only test framework: no external dependency to fetch,
// just self-registering test functions plus CHECK macros.
#pragma once

#include <cstdio>
#include <string>
#include <vector>

namespace testfw {

struct TestCase {
    std::string name;
    void (*fn)();
};

inline std::vector<TestCase>& registry() {
    static std::vector<TestCase> r;
    return r;
}

struct Registrar {
    Registrar(const char* name, void (*fn)()) { registry().push_back({ name, fn }); }
};

inline int g_checks = 0;
inline int g_failures = 0;

} // namespace testfw

#define HD6309_TEST_CONCAT_(a, b) a##b
#define HD6309_TEST_CONCAT(a, b) HD6309_TEST_CONCAT_(a, b)

#define TEST(name)                                                                   \
    static void HD6309_TEST_CONCAT(test_fn_, name)();                                \
    static testfw::Registrar HD6309_TEST_CONCAT(test_reg_, name)(                     \
        #name, &HD6309_TEST_CONCAT(test_fn_, name));                                  \
    static void HD6309_TEST_CONCAT(test_fn_, name)()

#define CHECK(cond)                                                                   \
    do {                                                                              \
        ++testfw::g_checks;                                                           \
        if (!(cond)) {                                                                \
            ++testfw::g_failures;                                                     \
            std::fprintf(stderr, "  CHECK failed: %s (%s:%d)\n", #cond, __FILE__, __LINE__); \
        }                                                                             \
    } while (0)

#define CHECK_EQ_HEX(a, b)                                                            \
    do {                                                                              \
        ++testfw::g_checks;                                                           \
        auto va_ = (a);                                                               \
        auto vb_ = (b);                                                               \
        if (!(va_ == vb_)) {                                                          \
            ++testfw::g_failures;                                                     \
            std::fprintf(stderr, "  CHECK_EQ failed: %s (0x%llX) != %s (0x%llX) (%s:%d)\n", \
                          #a, static_cast<unsigned long long>(va_), #b,               \
                          static_cast<unsigned long long>(vb_), __FILE__, __LINE__);  \
        }                                                                             \
    } while (0)
