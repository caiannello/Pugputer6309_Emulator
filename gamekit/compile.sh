#!/usr/bin/env bash
# Assembles the game kit into build/: TILEKIT.COM (build/tilekit.bin) and SONGPLAY.COM
# (build/songplay.bin), each with its own program header, which mkdiskimg puts in /CMD. (The Linux counterpart of compile.bat.)
cd "$(dirname "$0")" || exit 1
. ../lwtools_env.sh || exit 1
mkdir -p build

"$LWASM" tilekit.asm --6309 --format=raw --includedir=../bios --includedir=../vidcard --output=build/tilekit.bin --list=build/tilekit.lst --symbols || exit 1
"$LWASM" songplay.asm --6309 --format=raw --includedir=../bios --output=build/songplay.bin --list=build/songplay.lst --symbols || exit 1
