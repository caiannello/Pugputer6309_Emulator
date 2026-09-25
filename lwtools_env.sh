# Finds the LWTOOLS cross-assembler/linker (William Astle's lwtools -- see README.md,
# "Building from source") and sets LWASM, LWLINK and SRECCAT. Sourced, not run:
#   . "$ROOT/lwtools_env.sh" || exit 1
# Looked for, in order: the folder named by the LWTOOLS environment variable, then
# lwtools/linux_bin under this repository's root (the Linux binaries' home; the Windows
# ones live in lwtools/win_bin, for lwtools_env.bat), then the PATH. The LWTOOLS folder may
# hold lwasm and lwlink side by side, or be an lwtools source tree built with plain `make`
# (lwasm/lwasm and lwlink/lwlink). Every build script sources this one.
# (The Linux counterpart of lwtools_env.bat.)

_lw_root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
LWASM=
LWLINK=
for _lw_dir in "${LWTOOLS:-}" "$_lw_root/lwtools/linux_bin"; do
    [ -n "$_lw_dir" ] || continue
    if [ -f "$_lw_dir/lwasm" ] && [ -x "$_lw_dir/lwasm" ]; then
        LWASM=$_lw_dir/lwasm
        LWLINK=$_lw_dir/lwlink
        break
    elif [ -f "$_lw_dir/lwasm/lwasm" ] && [ -x "$_lw_dir/lwasm/lwasm" ]; then
        LWASM=$_lw_dir/lwasm/lwasm
        LWLINK=$_lw_dir/lwlink/lwlink
        break
    elif [ -f "$_lw_dir/lwasm" ]; then
        echo "ERROR: $_lw_dir/lwasm is not executable (copied without its permissions?):" >&2
        echo "       chmod +x \"$_lw_dir\"/lwasm \"$_lw_dir\"/lwlink" >&2
        return 1 2>/dev/null || exit 1
    fi
done
if [ -z "$LWASM" ] && command -v lwasm >/dev/null 2>&1; then
    LWASM=$(command -v lwasm)
    LWLINK=$(command -v lwlink 2>/dev/null || echo "$(dirname "$LWASM")/lwlink")
fi
unset _lw_dir
if [ -z "$LWASM" ] || [ ! -x "$LWLINK" ]; then
    echo "ERROR: lwtools was not found. Build it (see README.md) and put lwasm and lwlink in" >&2
    echo "       $_lw_root/lwtools/linux_bin, set the LWTOOLS environment variable to the" >&2
    echo "       folder that holds them (or to a built lwtools source tree), or put them on" >&2
    echo "       the PATH." >&2
    unset _lw_root
    return 1 2>/dev/null || exit 1
fi
unset _lw_root

# srec_cat (SRecord, optional): beside lwasm, else on the PATH.
SRECCAT=$(dirname "$LWASM")/srec_cat
[ -x "$SRECCAT" ] || SRECCAT=$(command -v srec_cat 2>/dev/null || true)
export LWASM LWLINK SRECCAT
return 0 2>/dev/null || true
