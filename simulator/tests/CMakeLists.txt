set(LWASM_EXE "${CMAKE_CURRENT_SOURCE_DIR}/../../lwtools-4.20/bin/lwasm.exe")

set(HD6309_TEST_SOURCES
    test_main.cpp
    test_addressing.cpp
    test_alu.cpp
    test_stack_transfer.cpp
    test_native6309.cpp
    test_branches_jumps.cpp
    test_interrupts.cpp
)

if(EXISTS "${LWASM_EXE}")
    list(APPEND HD6309_TEST_SOURCES test_asm_golden.cpp)
    set(HD6309_HAVE_LWASM 1)
else()
    set(HD6309_HAVE_LWASM 0)
    message(STATUS "lwasm.exe not found at ${LWASM_EXE}; golden assembly tests will be skipped")
endif()

add_executable(hd6309_tests ${HD6309_TEST_SOURCES})
target_link_libraries(hd6309_tests PRIVATE hd6309_static)
target_compile_definitions(hd6309_tests PRIVATE
    HD6309_HAVE_LWASM=${HD6309_HAVE_LWASM}
    LWASM_EXE_PATH="${LWASM_EXE}"
    HD6309_TEST_ASM_DIR="${CMAKE_CURRENT_SOURCE_DIR}/test_asm"
    HD6309_TEST_BUILD_DIR="${CMAKE_CURRENT_BINARY_DIR}/asm_out"
)

add_test(NAME hd6309_tests COMMAND hd6309_tests)

set(PUGPUTER_TEST_SOURCES
    test_pugputer_main.cpp
    test_uart.cpp
    test_system_bus.cpp
    test_banking.cpp
    test_srec_loader.cpp
    test_rom_device.cpp
    test_sdcard_device.cpp
    test_fat16_image.cpp
)

if(EXISTS "${LWASM_EXE}")
    list(APPEND PUGPUTER_TEST_SOURCES test_uart_golden.cpp)
    set(PUGPUTER_HAVE_LWASM 1)
else()
    set(PUGPUTER_HAVE_LWASM 0)
endif()

set(PUGBIOS_S19 "${CMAKE_CURRENT_SOURCE_DIR}/../../bios/pugbios.s19")
set(EXBASROM309_S19 "${CMAKE_CURRENT_SOURCE_DIR}/../../basic309/exbasrom309.s19")
set(EXBASROM309_LST "${CMAKE_CURRENT_SOURCE_DIR}/../../basic309/exbasrom309.lst")
if(EXISTS "${PUGBIOS_S19}" AND EXISTS "${EXBASROM309_S19}")
    list(APPEND PUGPUTER_TEST_SOURCES test_basic309_golden.cpp)
    list(APPEND PUGPUTER_TEST_SOURCES test_basic309_interp_regression.cpp)
    list(APPEND PUGPUTER_TEST_SOURCES test_basic309_token_audit.cpp)
    set(PUGPUTER_HAVE_BASIC309 1)
else()
    set(PUGPUTER_HAVE_BASIC309 0)
    message(STATUS "bios/pugbios.s19 and/or basic309/exbasrom309.s19 not found; the BIOS+BASIC309 integration test will be skipped")
endif()

set(DISK_IMG "${CMAKE_CURRENT_SOURCE_DIR}/../../basic309/disk.img")
set(PUGBIOS_MAP "${CMAKE_CURRENT_SOURCE_DIR}/../../bios/pugbios.map")
set(BIOS_DEFINES "${CMAKE_CURRENT_SOURCE_DIR}/../../bios/defines.d")
set(DOS_LST "${CMAKE_CURRENT_SOURCE_DIR}/../../dos/dos.lst")
set(DOS_BIN "${CMAKE_CURRENT_SOURCE_DIR}/../../dos/dos.bin")
set(SHELL_BIN "${CMAKE_CURRENT_SOURCE_DIR}/../../shell/shell.bin")
if(EXISTS "${PUGBIOS_S19}" AND EXISTS "${DISK_IMG}")
    list(APPEND PUGPUTER_TEST_SOURCES test_basic309_sdboot_golden.cpp)
    set(PUGPUTER_HAVE_SDBOOT 1)
else()
    set(PUGPUTER_HAVE_SDBOOT 0)
    message(STATUS "bios/pugbios.s19 and/or basic309/disk.img not found; the SD-boot integration test will be skipped")
endif()

if(EXISTS "${LWASM_EXE}" AND EXISTS "${PUGBIOS_S19}" AND EXISTS "${DISK_IMG}")
    list(APPEND PUGPUTER_TEST_SOURCES test_dos_file_api.cpp)
endif()

if(EXISTS "${PUGBIOS_S19}" AND EXISTS "${DISK_IMG}")
    list(APPEND PUGPUTER_TEST_SOURCES test_basic309_load_save_golden.cpp)
    list(APPEND PUGPUTER_TEST_SOURCES test_basic309_files_kill_name.cpp)
    list(APPEND PUGPUTER_TEST_SOURCES test_dos_stream_api.cpp)
    list(APPEND PUGPUTER_TEST_SOURCES test_dos_dirs.cpp)
    list(APPEND PUGPUTER_TEST_SOURCES test_bios_banks.cpp)
    list(APPEND PUGPUTER_TEST_SOURCES test_dos_model.cpp)
    list(APPEND PUGPUTER_TEST_SOURCES test_dos_bigfiles.cpp)
    list(APPEND PUGPUTER_TEST_SOURCES test_dos_crash.cpp)
    list(APPEND PUGPUTER_TEST_SOURCES test_shell.cpp)
    list(APPEND PUGPUTER_TEST_SOURCES test_basic309_seqfiles.cpp)
    list(APPEND PUGPUTER_TEST_SOURCES test_basic309_randomfiles.cpp)
    list(APPEND PUGPUTER_TEST_SOURCES test_basic309_dirs.cpp)
endif()

add_executable(pugputer_tests ${PUGPUTER_TEST_SOURCES})
target_link_libraries(pugputer_tests PRIVATE pugputer_system)
target_compile_definitions(pugputer_tests PRIVATE
    PUGPUTER_HAVE_LWASM=${PUGPUTER_HAVE_LWASM}
    LWASM_EXE_PATH="${LWASM_EXE}"
    PUGPUTER_TEST_ASM_DIR="${CMAKE_CURRENT_SOURCE_DIR}/test_asm"
    PUGPUTER_TEST_BUILD_DIR="${CMAKE_CURRENT_BINARY_DIR}/asm_out"
    PUGPUTER_HAVE_BASIC309=${PUGPUTER_HAVE_BASIC309}
    PUGBIOS_S19_PATH="${PUGBIOS_S19}"
    EXBASROM309_S19_PATH="${EXBASROM309_S19}"
    EXBASROM309_LST_PATH="${EXBASROM309_LST}"
    PUGPUTER_HAVE_SDBOOT=${PUGPUTER_HAVE_SDBOOT}
    DISK_IMG_PATH="${DISK_IMG}"
    PUGBIOS_MAP_PATH="${PUGBIOS_MAP}"
    BIOS_DEFINES_PATH="${BIOS_DEFINES}"
    DOS_LST_PATH="${DOS_LST}"
    DOS_BIN_PATH="${DOS_BIN}"
    SHELL_BIN_PATH="${SHELL_BIN}"
)

add_test(NAME pugputer_tests COMMAND pugputer_tests)
