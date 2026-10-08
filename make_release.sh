#!/usr/bin/env bash
# Builds the Linux x64 binary demo release: dist/Pugputer6309-demo-<version>-linux-x64/ and
# the .tar.gz next to it. Everything is rebuilt from source: the BIOS, DOS, shell, editor and
# BASIC (needs lwtools -- see README.md), then the emulator in Release configuration, linked
# fully statically (so it runs on any x86-64 Linux, with no library versions to match), and
# pugputer-video, its window for the video card (dynamically linked: it needs SDL2, and is
# only built when SDL2's development files are installed -- libsdl2-dev), then a disk image holding the shell, the editor, BASIC, the demo programs and the sources of
# every program in /CMD (in /ASM, for rebuilding them on the Pugputer).
# (The Linux counterpart of make_release.bat, whose VERSION it uses.)
#
# Needs: lwtools, CMake, g++ with the static C and C++ libraries (Ubuntu/Debian: build-essential).
# Only this Linux release is replaced in dist/; a Windows one there (make_release.bat) is
# left alone.
set -e
ROOT=$(cd "$(dirname "$0")" && pwd)
VERSION=$(sed -n 's/^set VERSION=\([^[:space:]]*\).*/\1/p' "$ROOT/make_release.bat" | head -n 1)
[ -n "$VERSION" ] || { echo "ERROR: could not read VERSION from make_release.bat" >&2; exit 1; }
NAME=Pugputer6309-demo-$VERSION-linux-x64
OUT=$ROOT/dist/$NAME
BUILD=$ROOT/simulator/build-release-linux
JOBS=$(nproc 2>/dev/null || echo 4)

. "$ROOT/lwtools_env.sh"

echo "=== Assembling the BIOS, DOS, shell, editor, assembler, utilities, demos and BASIC ==="
for D in bios dos shell edit asmlink utils demo gamekit; do
    "$ROOT/$D/compile.sh"
done
"$ROOT/basic309/build_basic.sh"

echo "=== Building the emulator (Release, static) ==="
"$ROOT/check_build_dir.sh" "$BUILD"
# (CMAKE_EXE_LINKER_FLAGS is cleared explicitly: older versions of this script set it to
# -static, and CMake keeps it in the cache, where it would also make pugputer-video try to
# link SDL2 statically -- which fails. Only the targets PUGPUTER_STATIC_EXE names are static.)
cmake -S "$ROOT/simulator" -B "$BUILD" -DCMAKE_BUILD_TYPE=Release -DHD6309_BUILD_TESTS=OFF \
      -DPUGPUTER_STATIC_EXE=ON -DCMAKE_EXE_LINKER_FLAGS=
cmake --build "$BUILD" --parallel "$JOBS" --target basic309_sdboot_demo mkdiskimg
if cmake --build "$BUILD" --target help | grep -q "pugputer-video"; then
    # SDL2 was found, so the video window must build: a failure here stops the release.
    cmake --build "$BUILD" --parallel "$JOBS" --target pugputer-video
    VIDEO=1
else
    VIDEO=0
    echo "WARNING: no pugputer-video (SDL2 isn't installed: sudo apt install libsdl2-dev);"
    echo "         the release will have no window for the video card."
fi

echo "=== Assembling $NAME ==="
rm -rf "$OUT"
mkdir -p "$OUT"
cp "$BUILD/tools/basic309_sdboot_demo" "$OUT/pugputer"
strip "$OUT/pugputer" 2>/dev/null || true
if [ "$VIDEO" = 1 ]; then
    cp "$BUILD/tools/pugputer-video" "$OUT/pugputer-video"
    strip "$OUT/pugputer-video" 2>/dev/null || true
    chmod +x "$OUT/pugputer-video"
fi
cp "$ROOT/bios/pugbios.s19" "$OUT/pugbios.s19"
"$BUILD/tools/mkdiskimg" --out "$OUT/disk-original.img" --add-dir "$ROOT/demo/programs" --sources "$ROOT"
cp "$OUT/disk-original.img" "$OUT/disk.img"
cp "$ROOT/demo/release/start-console.sh" "$ROOT/demo/release/start-serial.sh" \
   "$ROOT/demo/release/reset-disk.sh" "$OUT/"
chmod +x "$OUT/pugputer" "$OUT"/*.sh
cp "$ROOT/demo/release/README-linux.md" "$OUT/README.md"
cp "$ROOT/LICENSE" "$OUT/LICENSE.txt"
cp "$ROOT/NOTICE.md" "$OUT/NOTICE.md"

echo "=== Archiving ==="
rm -f "$ROOT/dist/$NAME.tar.gz"
tar -C "$ROOT/dist" --owner=0 --group=0 -czf "$ROOT/dist/$NAME.tar.gz" "$NAME"
echo
echo "Done: $ROOT/dist/$NAME.tar.gz"
