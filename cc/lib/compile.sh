#!/bin/sh
# The C library's objects (cc/lib/*.o, with listings): crt0.o, and the members
# of libc.a, which libc.rsp lists in order (it is AR's response file: on the
# Pugputer, "AR @libc.rsp" makes libc.a from them). mkdiskimg puts them on the
# disk as /LIB/CRT0.O and /LIB/LIBC.A, with CC.SCR.
cd "$(dirname "$0")" || exit 1
. ../../lwtools_env.sh || exit 1
for o in crt0.o $(grep '\.o$' libc.rsp | tr -d '\r'); do
    m="${o%.o}"
    "$LWASM" "$m.asm" --6309 --format=obj --includedir=../../bios --output="$m.o" --list="$m.lst" --symbols || exit 1
done
