# uart_demo and basic309_demo use <conio.h> for non-blocking console keyboard
# input, which is Windows/MSVC-specific, so they are only built there.
# basic309_sdboot_demo (the emulator the releases ship) runs everywhere.
add_executable(cycle_bench cycle_bench.cpp)
target_link_libraries(cycle_bench PRIVATE pugputer_system)

set(PUGBIOS_S19_DEFAULT "${CMAKE_CURRENT_SOURCE_DIR}/../../bios/pugbios.s19")
set(EXBASROM309_S19_DEFAULT "${CMAKE_CURRENT_SOURCE_DIR}/../../basic309/exbasrom309.s19")
set(DOS_BIN_DEFAULT "${CMAKE_CURRENT_SOURCE_DIR}/../../dos/dos.bin")
set(SHELL_BIN_DEFAULT "${CMAKE_CURRENT_SOURCE_DIR}/../../shell/shell.bin")
set(EDIT_BIN_DEFAULT "${CMAKE_CURRENT_SOURCE_DIR}/../../edit/edit.bin")
set(ASM_BIN_DEFAULT "${CMAKE_CURRENT_SOURCE_DIR}/../../asmlink/asm.bin")
set(LINK_BIN_DEFAULT "${CMAKE_CURRENT_SOURCE_DIR}/../../asmlink/link.bin")
set(HEXDUMP_BIN_DEFAULT "${CMAKE_CURRENT_SOURCE_DIR}/../../utils/hexdump.bin")
set(MOVE_BIN_DEFAULT "${CMAKE_CURRENT_SOURCE_DIR}/../../utils/move.bin")
set(DISK_IMG_DEFAULT "${CMAKE_CURRENT_SOURCE_DIR}/../../basic309/disk.img")

# mkdiskimg is plain, cross-platform file I/O -- no conio.h/Windows
# dependency -- so unlike the tools below, it isn't gated on WIN32.
add_executable(mkdiskimg mkdiskimg.cpp)
target_link_libraries(mkdiskimg PRIVATE pugputer_system)
target_compile_definitions(mkdiskimg PRIVATE
    DOS_BIN_DEFAULT="${DOS_BIN_DEFAULT}"
    SHELL_BIN_DEFAULT="${SHELL_BIN_DEFAULT}"
    EDIT_BIN_DEFAULT="${EDIT_BIN_DEFAULT}"
    ASM_BIN_DEFAULT="${ASM_BIN_DEFAULT}"
    LINK_BIN_DEFAULT="${LINK_BIN_DEFAULT}"
    HEXDUMP_BIN_DEFAULT="${HEXDUMP_BIN_DEFAULT}"
    MOVE_BIN_DEFAULT="${MOVE_BIN_DEFAULT}"
    EXBASROM309_S19_DEFAULT="${EXBASROM309_S19_DEFAULT}"
    DISK_IMG_DEFAULT="${DISK_IMG_DEFAULT}"
)

if(WIN32)
    add_executable(uart_demo uart_demo.cpp)
    target_link_libraries(uart_demo PRIVATE pugputer_system)

    add_executable(basic309_demo basic309_demo.cpp)
    target_link_libraries(basic309_demo PRIVATE pugputer_system)
    target_compile_definitions(basic309_demo PRIVATE
        PUGBIOS_S19_DEFAULT="${PUGBIOS_S19_DEFAULT}"
        EXBASROM309_S19_DEFAULT="${EXBASROM309_S19_DEFAULT}"
    )
endif()

# The emulator itself: has its own console code for both Windows and POSIX terminals.
set(DISK_IMG_SDBOOT_DEFAULT "${CMAKE_CURRENT_SOURCE_DIR}/../../basic309/disk.img")
add_executable(basic309_sdboot_demo basic309_sdboot_demo.cpp audio_out.cpp video_out.cpp)
target_link_libraries(basic309_sdboot_demo PRIVATE pugputer_system)
if(WIN32)
    # waveOut for the OPL3's sound, GDI for the video card's window
    target_link_libraries(basic309_sdboot_demo PRIVATE winmm gdi32 user32)
else()
    find_package(Threads REQUIRED)
    target_link_libraries(basic309_sdboot_demo PRIVATE Threads::Threads)
    # The video card's window is another program, pugputer-video, which needs SDL2 (on Ubuntu:
    # sudo apt install libsdl2-dev). Without it everything else is built all the same, and the
    # emulator runs with no window. It is never linked statically (see PUGPUTER_STATIC_EXE).
    find_package(SDL2 QUIET)
    if(SDL2_FOUND)
        add_executable(pugputer-video pugputer_video.cpp)
        target_link_libraries(pugputer-video PRIVATE Threads::Threads)
        if(TARGET SDL2::SDL2)
            target_link_libraries(pugputer-video PRIVATE SDL2::SDL2)
        else()
            string(STRIP "${SDL2_LIBRARIES}" SDL2_LIBS_STRIPPED)
            target_include_directories(pugputer-video PRIVATE ${SDL2_INCLUDE_DIRS})
            target_link_libraries(pugputer-video PRIVATE ${SDL2_LIBS_STRIPPED})
        endif()
        message(STATUS "SDL2 found: building pugputer-video, the video card's window")
    else()
        message(STATUS "SDL2 not found (sudo apt install libsdl2-dev): no video window for the emulator")
    endif()
endif()
# The Linux release links the emulator and mkdiskimg fully statically, so they run on any
# x86-64 Linux (make_release.sh turns this on).
option(PUGPUTER_STATIC_EXE "Link the emulator and mkdiskimg fully statically (Linux release)" OFF)
if(PUGPUTER_STATIC_EXE AND NOT WIN32)
    target_link_options(basic309_sdboot_demo PRIVATE -static)
    target_link_options(mkdiskimg PRIVATE -static)
endif()
target_compile_definitions(basic309_sdboot_demo PRIVATE
    PUGBIOS_S19_DEFAULT="${PUGBIOS_S19_DEFAULT}"
    DISK_IMG_DEFAULT="${DISK_IMG_SDBOOT_DEFAULT}"
)

# pugrun: runs shell commands on an emulated Pugputer from a host script (see pugrun.cpp).
add_executable(pugrun pugrun.cpp)
target_link_libraries(pugrun PRIVATE pugputer_system)
target_include_directories(pugrun PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/../tests)
target_compile_definitions(pugrun PRIVATE
    PUGBIOS_S19_DEFAULT="${PUGBIOS_S19_DEFAULT}"
    DOS_BIN_DEFAULT="${DOS_BIN_DEFAULT}"
    SHELL_BIN_DEFAULT="${SHELL_BIN_DEFAULT}"
)
