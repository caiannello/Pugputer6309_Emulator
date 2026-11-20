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
    {"asmlink/ar.asm", "ASM/ASMLINK/AR.ASM"},
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
    {"bios/defines.d", "ASM/CC/DEFINES.D"},
    {"cc/cpp.asm", "ASM/CC/CPP.ASM"},
    {"cc/cc.asm", "ASM/CC/CC.ASM"},
    {"cc/cc1.asm", "ASM/CC/CC1.ASM"},
    {"cc/cc1_lex.asm", "ASM/CC/CC1_LEX.ASM"},
    {"cc/cc1_sym.asm", "ASM/CC/CC1_SYM.ASM"},
    {"cc/cc1_decl.asm", "ASM/CC/CC1_DECL.ASM"},
    {"cc/cc1_stmt.asm", "ASM/CC/CC1_STMT.ASM"},
    {"cc/cc1_expr.asm", "ASM/CC/CC1_EXPR.ASM"},
    {"cc/cc1_gen.asm", "ASM/CC/CC1_GEN.ASM"},
    {"cc/cc1_long.asm", "ASM/CC/CC1_LONG.ASM"},
    {"cc/cc1_flt.asm", "ASM/CC/CC1_FLT.ASM"},
    {"cc/lib/fpcore.asm", "ASM/CC/FPCORE.ASM"},
    {"asmlink/pa_util.asm", "ASM/CC/PA_UTIL.ASM"},
    {"asmlink/pa_heap.asm", "ASM/CC/PA_HEAP.ASM"},
    {"asmlink/pa_strm.asm", "ASM/CC/PA_STRM.ASM"},
    {"cc/lib/crt0.asm", "ASM/LIBC/CRT0.ASM"},
    {"cc/lib/strlen.asm", "ASM/LIBC/STRLEN.ASM"},
    {"cc/lib/strcpy.asm", "ASM/LIBC/STRCPY.ASM"},
    {"cc/lib/strncpy.asm", "ASM/LIBC/STRNCPY.ASM"},
    {"cc/lib/strcat.asm", "ASM/LIBC/STRCAT.ASM"},
    {"cc/lib/strcmp.asm", "ASM/LIBC/STRCMP.ASM"},
    {"cc/lib/strncmp.asm", "ASM/LIBC/STRNCMP.ASM"},
    {"cc/lib/strchr.asm", "ASM/LIBC/STRCHR.ASM"},
    {"cc/lib/strrchr.asm", "ASM/LIBC/STRRCHR.ASM"},
    {"cc/lib/strstr.asm", "ASM/LIBC/STRSTR.ASM"},
    {"cc/lib/memcpy.asm", "ASM/LIBC/MEMCPY.ASM"},
    {"cc/lib/memmove.asm", "ASM/LIBC/MEMMOVE.ASM"},
    {"cc/lib/memset.asm", "ASM/LIBC/MEMSET.ASM"},
    {"cc/lib/memcmp.asm", "ASM/LIBC/MEMCMP.ASM"},
    {"cc/lib/ctype.asm", "ASM/LIBC/CTYPE.ASM"},
    {"cc/lib/atoi.asm", "ASM/LIBC/ATOI.ASM"},
    {"cc/lib/atol.asm", "ASM/LIBC/ATOL.ASM"},
    {"cc/lib/abs.asm", "ASM/LIBC/ABS.ASM"},
    {"cc/lib/rand.asm", "ASM/LIBC/RAND.ASM"},
    {"cc/lib/malloc.asm", "ASM/LIBC/MALLOC.ASM"},
    {"cc/lib/stdio.asm", "ASM/LIBC/STDIO.ASM"},
    {"cc/lib/fileio.asm", "ASM/LIBC/FILEIO.ASM"},
    {"cc/lib/printf.asm", "ASM/LIBC/PRINTF.ASM"},
    {"cc/lib/arith.asm", "ASM/LIBC/ARITH.ASM"},
    {"cc/lib/larith.asm", "ASM/LIBC/LARITH.ASM"},
    {"cc/lib/scanf.asm", "ASM/LIBC/SCANF.ASM"},
    {"cc/lib/mexp.asm", "ASM/LIBC/MEXP.ASM"},
    {"cc/lib/mtrig.asm", "ASM/LIBC/MTRIG.ASM"},
    {"cc/lib/matan.asm", "ASM/LIBC/MATAN.ASM"},
    {"cc/lib/msqrt.asm", "ASM/LIBC/MSQRT.ASM"},
    {"cc/lib/mbasic.asm", "ASM/LIBC/MBASIC.ASM"},
    {"cc/lib/fmath.d", "ASM/LIBC/FMATH.D"},
    {"cc/lib/fltio.asm", "ASM/LIBC/FLTIO.ASM"},
    {"cc/lib/strtod.asm", "ASM/LIBC/STRTOD.ASM"},
    {"cc/lib/float.asm", "ASM/LIBC/FLOAT.ASM"},
    {"cc/lib/fpcore.asm", "ASM/LIBC/FPCORE.ASM"},
    {"cc/lib/scopy.asm", "ASM/LIBC/SCOPY.ASM"},
    {"cc/lib/spawn.asm", "ASM/LIBC/SPAWN.ASM"},
    {"cc/lib/farcall.asm", "ASM/LIBC/FARCALL.ASM"},
    {"cc/lib/pugbank.asm", "ASM/LIBC/PUGBANK.ASM"},
    {"cc/lib/pugvid.asm", "ASM/LIBC/PUGVID.ASM"},
    {"cc/lib/pugin.asm", "ASM/LIBC/PUGIN.ASM"},
    {"cc/lib/pugsnd.asm", "ASM/LIBC/PUGSND.ASM"},
    {"cc/lib/libpug.rsp", "ASM/LIBC/LIBPUG.RSP"},
    {"vidcard/vidcard.d", "ASM/LIBC/VIDCARD.D"},
    {"gamekit/sk_play.asm", "ASM/LIBC/SK_PLAY.ASM"},
    {"cc/lib/libc.d", "ASM/LIBC/LIBC.D"},
    {"cc/lib/libc.rsp", "ASM/LIBC/LIBC.RSP"},
    {"cc/lib/cc.scr", "ASM/LIBC/CC.SCR"},
    {"bios/defines.d", "ASM/LIBC/DEFINES.D"},
    // The video card: its include file, beside DEFINES.D and beside the demo that uses it
    // (demo/programs/ASM/VIDEO), and its description.
    {"vidcard/vidcard.d", "ASM/VIDCARD.D"},
    {"vidcard/vidcard.d", "ASM/VIDEO/VIDCARD.D"},
    {"vidcard/README.md", "ASM/VIDEO/VIDCARD.TXT"},
    // SONGKIT's player, beside SWAMP (which plays its music with it) as in GAMEKIT.
    {"gamekit/sk_play.asm", "ASM/VIDEO/SK_PLAY.ASM"},
    // The game kit's editors (TILEKIT, SONGKIT) and SONGKIT's player (SONGPLAY, and
    // sk_play.asm for games), with the include files they need beside them.
    {"gamekit/tilekit.asm", "ASM/GAMEKIT/TILEKIT.ASM"},
    {"gamekit/tk_draw.asm", "ASM/GAMEKIT/TK_DRAW.ASM"},
    {"gamekit/tk_file.asm", "ASM/GAMEKIT/TK_FILE.ASM"},
    {"gamekit/tk_map.asm", "ASM/GAMEKIT/TK_MAP.ASM"},
    {"gamekit/tk_src.asm", "ASM/GAMEKIT/TK_SRC.ASM"},
    {"gamekit/tk_ini.asm", "ASM/GAMEKIT/TK_INI.ASM"},
    {"gamekit/tk_layer.asm", "ASM/GAMEKIT/TK_LAYER.ASM"},
    {"gamekit/tk_ldlg.asm", "ASM/GAMEKIT/TK_LDLG.ASM"},
    {"gamekit/tk_proj.asm", "ASM/GAMEKIT/TK_PROJ.ASM"},
    {"gamekit/gk_ui.asm", "ASM/GAMEKIT/GK_UI.ASM"},
    {"gamekit/songplay.asm", "ASM/GAMEKIT/SONGPLAY.ASM"},
    {"gamekit/songkit.asm", "ASM/GAMEKIT/SONGKIT.ASM"},
    {"gamekit/sk_core.asm", "ASM/GAMEKIT/SK_CORE.ASM"},
    {"gamekit/sk_ui.asm", "ASM/GAMEKIT/SK_UI.ASM"},
    {"gamekit/sk_help.asm", "ASM/GAMEKIT/SK_HELP.ASM"},
    {"gamekit/sk_block.asm", "ASM/GAMEKIT/SK_BLOCK.ASM"},
    {"gamekit/sk_bank.asm", "ASM/GAMEKIT/SK_BANK.ASM"},
    {"gamekit/sk_inst.asm", "ASM/GAMEKIT/SK_INST.ASM"},
    {"gamekit/sk_file.asm", "ASM/GAMEKIT/SK_FILE.ASM"},
    {"gamekit/sk_pat.asm", "ASM/GAMEKIT/SK_PAT.ASM"},
    {"gamekit/sk_play.asm", "ASM/GAMEKIT/SK_PLAY.ASM"},
    {"bios/defines.d", "ASM/GAMEKIT/DEFINES.D"},
    {"vidcard/vidcard.d", "ASM/GAMEKIT/VIDCARD.D"},
    {"gamekit/README.md", "ASM/GAMEKIT/README.TXT"},
};

// SONGKIT's instrument banks, on every disk (as the programs in /CMD are): /BANKS, the
// folder its bank page looks in first -- The Fat Man's General MIDI banks (MIT; their
// notice in README.TXT beside them, and in NOTICE.md).
inline constexpr DemoSource kToolFiles[] = {
    {"gamekit/banks/README.TXT", "BANKS/README.TXT"},
    {"gamekit/banks/FATMAN2.WOP", "BANKS/FATMAN2.WOP"},
    {"gamekit/banks/FATMAN4.WOP", "BANKS/FATMAN4.WOP"},
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
    {"demo/build/vidpad.bin", "DEMO/VIDPAD.COM", 0x4000},
    {"demo/build/padmap.bin", "CMD/PADMAP.COM", 0x4000}, // (a utility, so on the PATH with the others)
    {"demo/build/mandel.bin", "DEMO/MANDEL.COM", 0x4000},
    {"demo/build/swamp.bin", "DEMO/SWAMP.COM", 0x4000},
};

// Files the demo programs use, copied to /DEMO as they are: the songs VGMPLAY plays, and
// SWAMP's pictures (a TILEKIT project: TILEKIT SWAMP.TKT opens it) and music (Old Joe
// Clark, a SONGKIT song: SONGKIT SWAMP.SNG opens it); and SWAMPFLY.C, the swamp in C
// (CC swampfly.c, there, makes SWAMPFLY.COM).
inline constexpr DemoSource kDemoFiles[] = {
    {"demo/vgm/HAL9000.VGM", "DEMO/VGMPLAY/HAL9000.VGM"},
    {"demo/vgm/JFK.VGM", "DEMO/VGMPLAY/JFK.VGM"},
    {"demo/vgm/WILHELM.VGM", "DEMO/VGMPLAY/WILHELM.VGM"},
    {"demo/swamp/SWAMP.TKT", "DEMO/SWAMP.TKT"},
    {"demo/swamp/SWAMP1.TLS", "DEMO/SWAMP1.TLS"},
    {"demo/swamp/SWAMP1.MAP", "DEMO/SWAMP1.MAP"},
    {"demo/swamp/SWAMP2.TLS", "DEMO/SWAMP2.TLS"},
    {"demo/swamp/SWAMP2.MAP", "DEMO/SWAMP2.MAP"},
    {"demo/swamp/SWAMP3.TLS", "DEMO/SWAMP3.TLS"},
    {"demo/swamp/SWAMP3.MAP", "DEMO/SWAMP3.MAP"},
    {"demo/swamp/SWAMP.SNG", "DEMO/SWAMP.SNG"},
    {"demo/programs/C/SWAMPFLY.C", "DEMO/SWAMPFLY.C"},
};

} // namespace pugputer
