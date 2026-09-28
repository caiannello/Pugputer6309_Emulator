#!/usr/bin/env bash
# Assembles the music demos (programs/ASM/VGM) into build/: raw images that load at $4000,
# which mkdiskimg --sources puts on the release disk as /DEMO/*.COM (it adds the program
# header, as ASM -f com does). (The Linux counterpart of compile.bat.)
cd "$(dirname "$0")" || exit 1
. ../lwtools_env.sh || exit 1
mkdir -p build

"$LWASM" programs/ASM/VGM/VGMONKEY.ASM --6309 --format=raw --output=build/vgmonkey.bin || exit 1
"$LWASM" programs/ASM/VGM/VGXWINGF.ASM --6309 --format=raw --output=build/vgxwingf.bin || exit 1
