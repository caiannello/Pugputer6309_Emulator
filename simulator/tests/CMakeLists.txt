# lwasm and lwlink (William Astle's lwtools) are only used by the tests that compare against
# them, which are skipped without them. Same search order as lwtools_env.bat /
# lwtools_env.sh at the repository root: the LWTOOLS environment variable's folder, then
# lwtools/win_bin (Windows) or lwtools/linux_bin (elsewhere); a folder may hold lwasm and
# lwlink side by side, or be an lwtools source tree built with make (lwasm/lwasm,
# lwlink/lwlink); then the PATH.
set(LWASM_EXE "LWASM_EXE-NOTFOUND")
set(LWLINK_EXE "LWLINK_EXE-NOTFOUND")
set(_LW_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../..")
if(WIN32)
    set(_LW_BIN "${_LW_ROOT}/lwtools/win_bin")
else()
    set(_LW_BIN "${_LW_ROOT}/lwtools/linux_bin")
endif()
foreach(_dir "$ENV{LWTOOLS}" "${_LW_BIN}")
    foreach(_sub "" "/lwasm")
        foreach(_ext ".exe" "")
            if(NOT LWASM_EXE AND _dir AND EXISTS "${_dir}${_sub}/lwasm${_ext}"
               AND NOT IS_DIRECTORY "${_dir}${_sub}/lwasm${_ext}")
                set(LWASM_EXE "${_dir}${_sub}/lwasm${_ext}")
                # lwlink sits next to lwasm (PUGLINK is compared with it), or in the source tree's lwlink/.
                if(_sub STREQUAL "")
                    set(_LWLINK_CANDIDATE "${_dir}/lwlink${_ext}")
                else()
                    set(_LWLINK_CANDIDATE "${_dir}/lwlink/lwlink${_ext}")
                endif()
                if(EXISTS "${_LWLINK_CANDIDATE}")
                    set(LWLINK_EXE "${_LWLINK_CANDIDATE}")
                endif()
            endif()
        endforeach()
    endforeach()
endforeach()
if(NOT LWASM_EXE)
    find_program(_LWASM_ON_PATH lwasm)
    find_program(_LWLINK_ON_PATH lwlink)
    if(_LWASM_ON_PATH)
        set(LWASM_EXE "${_LWASM_ON_PATH}")
        if(_LWLINK_ON_PATH)
            set(LWLINK_EXE "${_LWLINK_ON_PATH}")
        endif()
    endif()
endif()

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
    message(STATUS "lwasm not found; golden assembly tests will be skipped")
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
set(EDIT_BIN "${CMAKE_CURRENT_SOURCE_DIR}/../../edit/edit.bin")
set(EDIT_LST "${CMAKE_CURRENT_SOURCE_DIR}/../../edit/edit.lst")
set(PUGASM_BIN "${CMAKE_CURRENT_SOURCE_DIR}/../../pugasm/pugasm.bin")
set(PUGLINK_BIN "${CMAKE_CURRENT_SOURCE_DIR}/../../pugasm/puglink.bin")
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
    if(EXISTS "${EDIT_BIN}")
        list(APPEND PUGPUTER_TEST_SOURCES test_edit.cpp)
    endif()
    if(EXISTS "${PUGASM_BIN}" AND EXISTS "${PUGLINK_BIN}")
        list(APPEND PUGPUTER_TEST_SOURCES test_pugasm.cpp)
    endif()
    list(APPEND PUGPUTER_TEST_SOURCES test_demo_programs.cpp)
    list(APPEND PUGPUTER_TEST_SOURCES test_bios_audit.cpp)
    list(APPEND PUGPUTER_TEST_SOURCES test_basic309_seqfiles.cpp)
    list(APPEND PUGPUTER_TEST_SOURCES test_basic309_randomfiles.cpp)
    list(APPEND PUGPUTER_TEST_SOURCES test_basic309_dirs.cpp)
    list(APPEND PUGPUTER_TEST_SOURCES test_basic309_errors.cpp)
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
    DEMO_DIR="${CMAKE_CURRENT_SOURCE_DIR}/../../demo/programs"
    BIOS_DEFINES_PATH="${BIOS_DEFINES}"
    DOS_LST_PATH="${DOS_LST}"
    DOS_BIN_PATH="${DOS_BIN}"
    SHELL_BIN_PATH="${SHELL_BIN}"
    EDIT_BIN_PATH="${EDIT_BIN}"
    EDIT_LST_PATH="${EDIT_LST}"
    PUGASM_BIN_PATH="${PUGASM_BIN}"
    PUGLINK_BIN_PATH="${PUGLINK_BIN}"
    LWLINK_EXE_PATH="${LWLINK_EXE}"
    REPO_DIR="${CMAKE_CURRENT_SOURCE_DIR}/../.."
)

add_test(NAME pugputer_tests COMMAND pugputer_tests)
