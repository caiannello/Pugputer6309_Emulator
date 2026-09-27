#!/usr/bin/env bash
# Rebuilds BIOS, dos.asm, the shell, the editor, ASM, LINK and basic309, then regenerates
# basic309/disk.img from scratch (just /CMD: SHELL.COM, EDIT.COM, ASM.COM, LINK.COM and BASIC.COM,
# no other files) -- run this any time you want a clean slate between test sessions, or after
# editing bios/, dos/, shell/, edit/, asmlink/ or basic309/.
# (The Linux counterpart of reinit_disk.bat.)
set -e
ROOT=$(cd "$(dirname "$0")" && pwd)
MKDISKIMG=$ROOT/simulator/build/tools/mkdiskimg
if [ ! -x "$MKDISKIMG" ]; then
    echo 'ERROR: mkdiskimg is not built yet -- see README.md, "Building from source".' >&2
    exit 1
fi

echo "Rebuilding BIOS..."
"$ROOT/bios/compile.sh"
echo "Rebuilding dos.asm..."
"$ROOT/dos/compile.sh"
echo "Rebuilding shell..."
"$ROOT/shell/compile.sh"
echo "Rebuilding the editor..."
"$ROOT/edit/compile.sh"
echo "Rebuilding the assembler and linker..."
"$ROOT/asmlink/compile.sh"
echo "Rebuilding basic309..."
"$ROOT/basic309/build_basic.sh"

echo "Regenerating disk.img (/CMD: SHELL.COM, EDIT.COM, ASM.COM, LINK.COM and BASIC.COM only, clean slate)..."
"$MKDISKIMG"

echo "Done."
