#!/usr/bin/env bash
cd "$(dirname "$0")" || exit 1
. ../lwtools_env.sh || exit 1

"$LWASM" pugasm.asm --6309 --format=raw --includedir=../bios --output=pugasm.bin --list=pugasm.lst --symbols || exit 1
"$LWASM" puglink.asm --6309 --format=raw --includedir=../bios --output=puglink.bin --list=puglink.lst --symbols || exit 1
