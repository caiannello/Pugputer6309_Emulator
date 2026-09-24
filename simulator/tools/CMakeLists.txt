# uart_demo uses <conio.h> for non-blocking console keyboard input in its
# console-bridge mode, which is Windows/MSVC-specific -- matching this
# project's current Windows-first scope. A cross-platform console input
# path can be added later without touching pugputer_system itself.
add_executable(cycle_bench cycle_bench.cpp)
target_link_libraries(cycle_bench PRIVATE pugputer_system)

set(PUGBIOS_S19_DEFAULT "${CMAKE_CURRENT_SOURCE_DIR}/../../bios/pugbios.s19")
set(EXBASROM309_S19_DEFAULT "${CMAKE_CURRENT_SOURCE_DIR}/../../basic309/exbasrom309.s19")
set(DOS_BIN_DEFAULT "${CMAKE_CURRENT_SOURCE_DIR}/../../dos/dos.bin")
set(DISK_IMG_DEFAULT "${CMAKE_CURRENT_SOURCE_DIR}/../../basic309/disk.img")

# mkdiskimg is plain, cross-platform file I/O -- no conio.h/Windows
# dependency -- so unlike the tools below, it isn't gated on WIN32.
add_executable(mkdiskimg mkdiskimg.cpp)
target_link_libraries(mkdiskimg PRIVATE pugputer_system)
target_compile_definitions(mkdiskimg PRIVATE
    DOS_BIN_DEFAULT="${DOS_BIN_DEFAULT}"
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

    set(DISK_IMG_SDBOOT_DEFAULT "${CMAKE_CURRENT_SOURCE_DIR}/../../basic309/disk.img")
    add_executable(basic309_sdboot_demo basic309_sdboot_demo.cpp)
    target_link_libraries(basic309_sdboot_demo PRIVATE pugputer_system)
    target_compile_definitions(basic309_sdboot_demo PRIVATE
        PUGBIOS_S19_DEFAULT="${PUGBIOS_S19_DEFAULT}"
        DISK_IMG_DEFAULT="${DISK_IMG_SDBOOT_DEFAULT}"
    )
endif()
