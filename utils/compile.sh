#!/usr/bin/env bash
cd "$(dirname "$0")" || exit 1
. ../lwtools_env.sh || exit 1

"$LWASM" hexdump.asm --6309 --format=raw --includedir=../bios --output=hexdump.bin --list=hexdump.lst --symbols || exit 1
