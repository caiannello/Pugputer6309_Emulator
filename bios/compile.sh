#!/bin/sh
# lwtools: $LWTOOLS if set, else ../lwtools/bin (see README.md, "Building from source")
LWDIR=${LWTOOLS:-../lwtools/bin}
LWASM=$LWDIR/lwasm
LWLINK=$LWDIR/lwlink
SRECCAT=$LWDIR/srec_cat
[ -x "$LWASM" ] || LWASM=$LWASM.exe
[ -x "$LWLINK" ] || LWLINK=$LWLINK.exe
[ -x "$SRECCAT" ] || SRECCAT=$SRECCAT.exe

$LWASM helpers.asm --6309 --format=obj --output=helpers.o --list=helpers.lst || exit 1
$LWASM devio.asm   --6309 --format=obj --output=devio.o   --list=devio.lst   || exit 1
$LWASM serio.asm   --6309 --format=obj --output=serio.o   --list=serio.lst   || exit 1
$LWASM sdcard.asm  --6309 --format=obj --output=sdcard.o  --list=sdcard.lst  || exit 1
$LWASM time.asm    --6309 --format=obj --output=time.o    --list=time.lst    || exit 1
$LWASM loader.asm  --6309 --format=obj --output=loader.o  --list=loader.lst  || exit 1
$LWASM banks.asm   --6309 --format=obj --output=banks.o   --list=banks.lst   || exit 1
$LWASM main.asm    --6309 --format=obj --output=main.o    --list=main.lst    || exit 1

# main.o must be linked LAST -- its bss content (the system stack) must be
# the final thing placed, so EndOfVars ends up as the true end of BIOS RAM.
$LWLINK --format=srec --output=pugbios.s19 --map=pugbios.map --script=linker_script \
    helpers.o devio.o serio.o sdcard.o time.o loader.o banks.o main.o || exit 1

# The Intel-hex copy (for an EPROM programmer) needs SRecord's srec_cat; it is optional.
[ -x "$SRECCAT" ] && $SRECCAT pugbios.s19 -Motorola -o pugbios.hex -Intel
exit 0
