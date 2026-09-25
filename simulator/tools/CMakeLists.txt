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
set(PUGASM_BIN_DEFAULT "${CMAKE_CURRENT_SOURCE_DIR}/../../pugasm/pugasm.bin")
set(PUGLINK_BIN_DEFAULT "${CMAKE_CURRENT_SOURCE_DIR}/../../pugasm/puglink.bin")
set(DISK_IMG_DEFAULT "${CMAKE_CURRENT_SOURCE_DIR}/../../basic309/disk.img")

# mkdiskimg is plain, cross-platform file I/O -- no conio.h/Windows
# dependency -- so unlike the tools below, it isn't gated on WIN32.
add_executable(mkdiskimg mkdiskimg.cpp)
target_link_libraries(mkdiskimg PRIVATE pugputer_system)
target_compile_definitions(mkdiskimg PRIVATE
    DOS_BIN_DEFAULT="${DOS_BIN_DEFAULT}"
    SHELL_BIN_DEFAULT="${SHELL_BIN_DEFAULT}"
    EDIT_BIN_DEFAULT="${EDIT_BIN_DEFAULT}"
    PUGASM_BIN_DEFAULT="${PUGASM_BIN_DEFAULT}"
    PUGLINK_BIN_DEFAULT="${PUGLINK_BIN_DEFAULT}"
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
add_executable(basic309_sdboot_demo basic309_sdboot_demo.cpp)
target_link_libraries(basic309_sdboot_demo PRIVATE pugputer_system)
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
