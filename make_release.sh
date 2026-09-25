#!/usr/bin/env bash
# Builds the Linux x64 binary demo release: dist/Pugputer6309-demo-<version>-linux-x64/ and
# the .tar.gz next to it. Everything is rebuilt from source: the BIOS, DOS, shell, editor and
# BASIC (needs lwtools -- see README.md), then the emulator in Release configuration, linked
# fully statically (so it runs on any x86-64 Linux, with no library versions to match), then
# a disk image holding the shell, the editor, BASIC and the demo programs.
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

echo "=== Assembling the BIOS, DOS, shell, editor, assembler and BASIC ==="
for D in bios dos shell edit pugasm; do
    "$ROOT/$D/compile.sh"
done
"$ROOT/basic309/build_basic.sh"

echo "=== Building the emulator (Release, static) ==="
"$ROOT/check_build_dir.sh" "$BUILD"
cmake -S "$ROOT/simulator" -B "$BUILD" -DCMAKE_BUILD_TYPE=Release -DHD6309_BUILD_TESTS=OFF \
      -DCMAKE_EXE_LINKER_FLAGS=-static
cmake --build "$BUILD" --parallel "$JOBS" --target basic309_sdboot_demo mkdiskimg

echo "=== Assembling $NAME ==="
rm -rf "$OUT"
mkdir -p "$OUT"
cp "$BUILD/tools/basic309_sdboot_demo" "$OUT/pugputer"
strip "$OUT/pugputer" 2>/dev/null || true
cp "$ROOT/bios/pugbios.s19" "$OUT/pugbios.s19"
"$BUILD/tools/mkdiskimg" --out "$OUT/disk-original.img" --add-dir "$ROOT/demo/programs"
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
