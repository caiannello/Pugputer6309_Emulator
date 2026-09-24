@echo off
rem Finds the LWTOOLS cross-assembler/linker (William Astle's lwtools -- see README.md,
rem "Building from source") and sets LWDIR to the folder holding lwasm.exe and lwlink.exe.
rem Looked for, in order: the folder named by the LWTOOLS environment variable, then
rem   lwtools\bin  lwtools  lwtools-4.20\bin  lwtools-4.25-win64  lwtools-4.20
rem under this repository's root. Every build script calls this one.
set "LWDIR="
if defined LWTOOLS if exist "%LWTOOLS%\lwasm.exe" set "LWDIR=%LWTOOLS%"
if not defined LWDIR for %%D in (lwtools\bin lwtools lwtools-4.20\bin lwtools-4.25-win64 lwtools-4.20) do (
    if not defined LWDIR if exist "%~dp0%%D\lwasm.exe" set "LWDIR=%~dp0%%D"
)
if not defined LWDIR (
    echo ERROR: lwtools was not found. Put lwasm.exe and lwlink.exe in "%~dp0lwtools" ^(see README.md^)
    echo        or set the LWTOOLS environment variable to the folder that holds them.
    exit /b 1
)
set "LWASM=%LWDIR%\lwasm.exe"
set "LWLINK=%LWDIR%\lwlink.exe"
set "SRECCAT=%LWDIR%\srec_cat.exe"
exit /b 0
