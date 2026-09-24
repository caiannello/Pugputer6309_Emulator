cmake_minimum_required(VERSION 3.15)
project(hd6309_emulator CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

option(HD6309_BUILD_TESTS "Build the hd6309 emulator test suite" ON)
option(PUGPUTER_BUILD_COM_BRIDGE "Build the Windows COM-port bridge for the UART device" ${WIN32})

if(MSVC)
    add_compile_options(/W4 /permissive-)
else()
    add_compile_options(-Wall -Wextra)
endif()

set(HD6309_SOURCES
    src/hd6309_core.cpp
    src/hd6309_opcodes.cpp
    src/hd6309_api.cpp
)

# Static library: what the test suite and any in-process consumer link
# against directly.
add_library(hd6309_static STATIC ${HD6309_SOURCES})
target_include_directories(hd6309_static PUBLIC include)
target_include_directories(hd6309_static PRIVATE src)
set_target_properties(hd6309_static PROPERTIES OUTPUT_NAME hd6309)

# Shared library: the DLL/.so surface for out-of-process or
# cross-language consumers (matches the public C API in hd6309.h).
add_library(hd6309_shared SHARED ${HD6309_SOURCES})
target_include_directories(hd6309_shared PUBLIC include)
target_include_directories(hd6309_shared PRIVATE src)
target_compile_definitions(hd6309_shared PRIVATE HD6309_BUILD_SHARED)
target_compile_definitions(hd6309_shared INTERFACE HD6309_USE_SHARED)
set_target_properties(hd6309_shared PROPERTIES OUTPUT_NAME hd6309)

set(PUGPUTER_SOURCES
    src/pugputer/system_bus.cpp
    src/pugputer/uart_r65c51.cpp
    src/pugputer/srec_loader.cpp
    src/pugputer/sdcard_device.cpp
    src/pugputer/fat16_image.cpp
)
if(PUGPUTER_BUILD_COM_BRIDGE)
    list(APPEND PUGPUTER_SOURCES src/pugputer/com_port_bridge.cpp)
endif()

# System-level library: SystemBus + IDevice + UartR65C51 (+ the Windows
# COM-port bridge, when enabled), sitting on top of hd6309_static. Static
# only for now -- this is an integration layer consumed in-process, not a
# DLL boundary that needs its own ABI stability yet.
add_library(pugputer_system STATIC ${PUGPUTER_SOURCES})
target_include_directories(pugputer_system PUBLIC include)
target_link_libraries(pugputer_system PUBLIC hd6309_static)
if(PUGPUTER_BUILD_COM_BRIDGE)
    target_compile_definitions(pugputer_system PUBLIC PUGPUTER_HAVE_COM_BRIDGE)
endif()

add_subdirectory(tools)

if(HD6309_BUILD_TESTS)
    enable_testing()
    add_subdirectory(tests)
endif()
