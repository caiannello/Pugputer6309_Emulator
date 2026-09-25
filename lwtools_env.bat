@echo off
rem Finds the LWTOOLS cross-assembler/linker (William Astle's lwtools -- see README.md,
rem "Building from source") and sets LWDIR to the folder holding lwasm.exe and lwlink.exe.
rem Looked for, in order: the folder named by the LWTOOLS environment variable, then
rem lwtools\win_bin under this repository's root (the Windows binaries' home; the Linux
rem ones live in lwtools\linux_bin, for lwtools_env.sh). Every build script calls this one.
set "LWDIR="
if defined LWTOOLS if exist "%LWTOOLS%\lwasm.exe" set "LWDIR=%LWTOOLS%"
if not defined LWDIR if exist "%~dp0lwtools\win_bin\lwasm.exe" set "LWDIR=%~dp0lwtools\win_bin"
if not defined LWDIR (
    echo ERROR: lwtools was not found. Put lwasm.exe and lwlink.exe ^(and the DLLs that come with
    echo        them^) in "%~dp0lwtools\win_bin" ^(see README.md^), or set the LWTOOLS environment
    echo        variable to the folder that holds them.
    exit /b 1
)
set "LWASM=%LWDIR%\lwasm.exe"
set "LWLINK=%LWDIR%\lwlink.exe"
set "SRECCAT=%LWDIR%\srec_cat.exe"
exit /b 0
