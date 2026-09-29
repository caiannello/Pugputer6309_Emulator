// Where BASIC.COM lives (basic309/exbasrom309.asm): loaded at BASIC_LOAD, started at
// BASIC_ENTRY ($C000, which never moves), up to $EFFF. BASIC_LOAD moves down when BASIC
// needs more room below $C000; this is the one place the host side says where it is.
#pragma once

#include <cstdint>

namespace pugputer {

constexpr uint16_t kBasicLoad = 0xB400;                     // BASIC_LOAD
constexpr uint16_t kBasicEntry = 0xC000;                    // BASIC_ENTRY: JMP RESVEC
constexpr uint32_t kBasicImageSize = 0xF000u - kBasicLoad;   // BASIC_LOAD..$EFFF
constexpr uint32_t kBasicComSize = kBasicImageSize + 8;      // with its program header

} // namespace pugputer
