#!/usr/bin/env bash
# Assembles basic309/exbasrom309.asm into exbasrom309.s19 and a listing WITH
# a symbol table (exbasrom309.lst) -- simulator/tests/test_basic309_token_audit
# reads the symbols from that listing, so always build through this script.
cd "$(dirname "$0")" || exit 1
. ../lwtools_env.sh || exit 1

"$LWASM" exbasrom309.asm --6309 --format=srec --output=exbasrom309.s19 --list=exbasrom309.lst --symbols
