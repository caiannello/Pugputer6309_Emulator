#!/usr/bin/env bash
# Puts the demo disk back the way it came.
HERE=$(dirname "$0")
echo "This puts the demo disk back the way it came, deleting any files you saved on it."
read -r -p "Continue (Y/N)? " OK
case "$OK" in
    [Yy]) cp "$HERE/disk-original.img" "$HERE/disk.img" && echo "Done." ;;
    *) exit 1 ;;
esac
