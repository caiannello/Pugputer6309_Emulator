#!/usr/bin/env bash
# CC's programs (cc/*.asm -> cc/*.bin, with listings): CC.COM (the driver),
# CPP.COM (the preprocessor) and CC1.COM (the compiler proper). They include pa_util.asm,
# pa_heap.asm and pa_strm.asm from asmlink/, and CC1 lib/fpcore.asm. The library is cc/lib's (its own
# compile script).
cd "$(dirname "$0")" || exit 1
. ../lwtools_env.sh || exit 1

for P in cc cpp cc1; do
    "$LWASM" $P.asm --6309 --format=raw --includedir=../bios --includedir=../asmlink --includedir=lib \
        --output=$P.bin --list=$P.lst --symbols || exit 1
done
