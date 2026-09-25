#!/usr/bin/env bash
# Builds everything from source: the BIOS, DOS, shell, editor and BASIC (with lwtools -- see README.md),
# the emulator, the tools and the tests (with CMake and g++ or clang++), the disk image
# basic309/disk.img, and then runs the test suite.
# (The Linux counterpart of build_all.bat.)
#
#   ./build_all.sh            build everything and run the tests
#   ./build_all.sh notests    build everything, don't run the tests
#   ./build_all.sh Debug      use the Debug configuration (default: Release)
set -e
ROOT=$(cd "$(dirname "$0")" && pwd)
CONFIG=Release
RUNTESTS=1
for A in "$@"; do
    case "${A,,}" in
        notests) RUNTESTS=0 ;;
        debug) CONFIG=Debug ;;
    esac
done
BUILD=$ROOT/simulator/build
JOBS=$(nproc 2>/dev/null || echo 4)

. "$ROOT/lwtools_env.sh"
command -v cmake >/dev/null || { echo 'ERROR: cmake was not found on the PATH. See README.md, "Building from source".' >&2; exit 1; }

echo "=== Assembling the BIOS, DOS, shell, editor, assembler and BASIC ==="
for D in bios dos shell edit pugasm; do
    "$ROOT/$D/compile.sh"
done
"$ROOT/basic309/build_basic.sh"

echo "=== Building the emulator and tools ==="
"$ROOT/check_build_dir.sh" "$BUILD"
cmake -S "$ROOT/simulator" -B "$BUILD" -DCMAKE_BUILD_TYPE=$CONFIG
cmake --build "$BUILD" --parallel "$JOBS" --target mkdiskimg basic309_sdboot_demo

echo "=== Making the disk image ==="
"$BUILD/tools/mkdiskimg"

echo "=== Building the tests ==="
# (Configured again now that the ROM and disk images exist: the tests that need them are
#  only included when the files are there.)
cmake -S "$ROOT/simulator" -B "$BUILD" >/dev/null
cmake --build "$BUILD" --parallel "$JOBS"

if [ "$RUNTESTS" = 1 ]; then
    echo "=== Running the tests (under a minute in Release, several minutes in Debug) ==="
    ctest --test-dir "$BUILD" --output-on-failure
fi
echo
echo "Built. Run:  simulator/build/tools/basic309_sdboot_demo"
