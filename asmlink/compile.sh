#!/usr/bin/env bash
cd "$(dirname "$0")" || exit 1
. ../lwtools_env.sh || exit 1

"$LWASM" asm.asm --6309 --format=raw --includedir=../bios --output=asm.bin --list=asm.lst --symbols || exit 1
"$LWASM" link.asm --6309 --format=raw --includedir=../bios --output=link.bin --list=link.lst --symbols || exit 1
