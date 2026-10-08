// The sources of the programs in /CMD, as the demo disk carries them in /ASM so that
// they can be rebuilt (and changed) on the Pugputer with ASM: each file's path in the
// repository and its path on the disk. mkdiskimg --sources adds them; test_asmlink.cpp
// rebuilds the programs from them. It also adds the demo programs, ready to run.
#pragma once

#include <cstdint>

namespace pugputer {

struct DemoSource {
    const char* repo; // relative to the repository's root
    const char* disk;
};

inline constexpr DemoSource kDemoSources[] = {
    {"demo/sources/README.TXT", "ASM/README.TXT"},
    {"bios/defines.d", "ASM/DEFINES.D"},
    {"shell/shell.asm", "ASM/SHELL.ASM"},
    {"edit/edit.asm", "ASM/EDIT.ASM"},
    {"utils/hexdump.asm", "ASM/HEXDUMP.ASM"},
    {"utils/move.asm", "ASM/MOVE.ASM"},
    {"basic309/exbasrom309.asm", "ASM/BASIC.ASM"},
    {"demo/sources/BASICCOM.ASM", "ASM/BASICCOM.ASM"},
    {"bios/defines.d", "ASM/ASMLINK/DEFINES.D"},
    {"asmlink/asm.asm", "ASM/ASMLINK/ASM.ASM"},
    {"asmlink/link.asm", "ASM/ASMLINK/LINK.ASM"},
    {"asmlink/pa_util.asm", "ASM/ASMLINK/PA_UTIL.ASM"},
    {"asmlink/pa_heap.asm", "ASM/ASMLINK/PA_HEAP.ASM"},
    {"asmlink/pa_io.asm", "ASM/ASMLINK/PA_IO.ASM"},
    {"asmlink/pa_strm.asm", "ASM/ASMLINK/PA_STRM.ASM"},
    {"asmlink/pa_sym.asm", "ASM/ASMLINK/PA_SYM.ASM"},
    {"asmlink/pa_expr.asm", "ASM/ASMLINK/PA_EXPR.ASM"},
    {"asmlink/pa_line.asm", "ASM/ASMLINK/PA_LINE.ASM"},
    {"asmlink/pa_insn.asm", "ASM/ASMLINK/PA_INSN.ASM"},
    {"asmlink/pa_dir.asm", "ASM/ASMLINK/PA_DIR.ASM"},
    {"asmlink/pa_out.asm", "ASM/ASMLINK/PA_OUT.ASM"},
    {"asmlink/pa_obj.asm", "ASM/ASMLINK/PA_OBJ.ASM"},
    {"asmlink/pa_itab.asm", "ASM/ASMLINK/PA_ITAB.ASM"},
    // The video card: its include file, beside DEFINES.D and beside the demo that uses it
    // (demo/programs/ASM/VIDEO), and its description.
    {"vidcard/vidcard.d", "ASM/VIDCARD.D"},
    {"vidcard/vidcard.d", "ASM/VIDEO/VIDCARD.D"},
    {"vidcard/README.md", "ASM/VIDEO/VIDCARD.TXT"},
    // The game kit's editors (TILEKIT), with the include files they need beside them.
    {"gamekit/tilekit.asm", "ASM/GAMEKIT/TILEKIT.ASM"},
    {"gamekit/tk_draw.asm", "ASM/GAMEKIT/TK_DRAW.ASM"},
    {"gamekit/tk_file.asm", "ASM/GAMEKIT/TK_FILE.ASM"},
    {"gamekit/tk_map.asm", "ASM/GAMEKIT/TK_MAP.ASM"},
    {"gamekit/tk_src.asm", "ASM/GAMEKIT/TK_SRC.ASM"},
    {"gamekit/tk_ini.asm", "ASM/GAMEKIT/TK_INI.ASM"},
    {"gamekit/gk_ui.asm", "ASM/GAMEKIT/GK_UI.ASM"},
    {"bios/defines.d", "ASM/GAMEKIT/DEFINES.D"},
    {"vidcard/vidcard.d", "ASM/GAMEKIT/VIDCARD.D"},
    {"gamekit/README.md", "ASM/GAMEKIT/README.TXT"},
};

// The demo programs in /DEMO: raw images (demo/compile.bat or .sh assembles them from
// demo/programs/ASM/VGM and VIDEO), each given the program header ASM -f com would give it.
struct DemoProgram {
    const char* repo; // the raw image, relative to the repository's root
    const char* disk;
    uint16_t load;    // load and entry address
};

inline constexpr DemoProgram kDemoPrograms[] = {
    {"demo/build/vgmonkey.bin", "DEMO/VGMONKEY.COM", 0x4000},
    {"demo/build/vgxwingf.bin", "DEMO/VGXWINGF.COM", 0x4000},
    {"demo/build/vgmplay.bin", "DEMO/VGMPLAY/VGMPLAY.COM", 0x4000},
    {"demo/build/viddemo.bin", "DEMO/VIDDEMO.COM", 0x4000},
    {"demo/build/vidtext.bin", "DEMO/VIDTEXT.COM", 0x4000},
    {"demo/build/vidtiles.bin", "DEMO/VIDTILES.COM", 0x4000},
    {"demo/build/vidgfx.bin", "DEMO/VIDGFX.COM", 0x4000},
    {"demo/build/vidmouse.bin", "DEMO/VIDMOUSE.COM", 0x4000},
};

// Files the demo programs use, copied to /DEMO as they are: the songs VGMPLAY plays.
inline constexpr DemoSource kDemoFiles[] = {
    {"demo/vgm/HAL9000.VGM", "DEMO/VGMPLAY/HAL9000.VGM"},
    {"demo/vgm/JFK.VGM", "DEMO/VGMPLAY/JFK.VGM"},
    {"demo/vgm/WILHELM.VGM", "DEMO/VGMPLAY/WILHELM.VGM"},
};

} // namespace pugputer
