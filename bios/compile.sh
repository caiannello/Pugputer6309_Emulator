#!/bin/sh
LWDIR=../lwtools-4.20/bin
LWASM=$LWDIR/lwasm.exe
LWLINK=$LWDIR/lwlink.exe
SRECCAT=$LWDIR/srec_cat.exe

$LWASM helpers.asm --6309 --format=obj --output=helpers.o --list=helpers.lst || exit 1
$LWASM devio.asm   --6309 --format=obj --output=devio.o   --list=devio.lst   || exit 1
$LWASM serio.asm   --6309 --format=obj --output=serio.o   --list=serio.lst   || exit 1
$LWASM sdcard.asm  --6309 --format=obj --output=sdcard.o  --list=sdcard.lst  || exit 1
$LWASM time.asm    --6309 --format=obj --output=time.o    --list=time.lst    || exit 1
$LWASM loader.asm  --6309 --format=obj --output=loader.o  --list=loader.lst  || exit 1
$LWASM main.asm    --6309 --format=obj --output=main.o    --list=main.lst    || exit 1

# main.o must be linked LAST -- its bss content (the system stack) must be
# the final thing placed, so EndOfVars ends up as the true end of BIOS RAM.
$LWLINK --format=srec --output=pugbios.s19 --map=pugbios.map --script=linker_script \
    helpers.o devio.o serio.o sdcard.o time.o loader.o main.o || exit 1

$SRECCAT pugbios.s19 -Motorola -o pugbios.hex -Intel
