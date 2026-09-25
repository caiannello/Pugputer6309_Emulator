#!/usr/bin/env bash
# check_build_dir.sh <folder>: deletes a CMake build folder that was configured for another
# copy of the project (after the project is moved or copied, CMake refuses to use it), so the
# next configure starts fresh. Does nothing if the folder is missing or belongs here.
# (The Linux counterpart of check_build_dir.bat.)
DIR=$1
SRC=$(cd "$(dirname "$0")" && pwd)/simulator
[ -f "$DIR/CMakeCache.txt" ] || exit 0
grep -qxF "CMAKE_HOME_DIRECTORY:INTERNAL=$SRC" "$DIR/CMakeCache.txt" && exit 0
echo "$DIR was configured for another copy of the project; deleting it."
rm -rf "$DIR" || exit 1
