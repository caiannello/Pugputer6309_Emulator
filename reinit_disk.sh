#!/usr/bin/env bash
# Rebuilds BIOS, dos.asm, the shell, the editor, ASM, LINK, the utilities, the demos and basic309, then
# regenerates basic309/disk.img from scratch (/CMD: SHELL.COM, EDIT.COM, ASM.COM, LINK.COM, HEXDUMP.COM, MOVE.COM, TILEKIT.COM and BASIC.COM,
# and /DEMO: SWAMP.COM and its pictures -- no other files, apart from local/disk/ if there is one) -- run this any time you want a clean slate between test sessions, or after
# editing bios/, dos/, shell/, edit/, asmlink/, utils/, gamekit/ or basic309/.
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
echo "Rebuilding the utilities..."
"$ROOT/utils/compile.sh"
echo "Rebuilding the game kit..."
"$ROOT/gamekit/compile.sh"
echo "Rebuilding the demos..."
"$ROOT/demo/compile.sh"
echo "Rebuilding basic309..."
"$ROOT/basic309/build_basic.sh"

echo "Regenerating disk.img (/CMD: SHELL.COM, EDIT.COM, ASM.COM, LINK.COM, HEXDUMP.COM, MOVE.COM, TILEKIT.COM and BASIC.COM; /DEMO/SWAMP.COM; clean slate)..."
# local/disk/ (not in the repository, see .gitignore): experiments to try on the disk, copied
# to its root as they are -- local/disk/SWAMP/X.BAS becomes /SWAMP/X.BAS
LOCALDISK=()
if [ -d "$ROOT/local/disk" ]; then
    echo "Adding local/disk/ to the disk..."
    LOCALDISK=(--add-dir "$ROOT/local/disk")
fi
"$MKDISKIMG" --demo SWAMP "${LOCALDISK[@]}"

echo "Done."
