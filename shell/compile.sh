#!/usr/bin/env bash
cd "$(dirname "$0")" || exit 1
. ../lwtools_env.sh || exit 1

"$LWASM" shell.asm --6309 --format=raw --includedir=../bios --output=shell.bin --list=shell.lst --symbols || exit 1
