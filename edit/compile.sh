#!/usr/bin/env bash
cd "$(dirname "$0")" || exit 1
. ../lwtools_env.sh || exit 1

"$LWASM" edit.asm --6309 --format=raw --includedir=../bios --output=edit.bin --list=edit.lst --symbols || exit 1
