@echo off
rem Assembles the game kit's editors into build\: TILEKIT.COM (build\tilekit.bin, with its own
rem program header), which mkdiskimg puts in /CMD.
call "%~dp0..\lwtools_env.bat" || exit /b 1
if not exist build mkdir build

%LWASM% tilekit.asm --6309 --format=raw --includedir=..\bios --includedir=..\vidcard --output=build\tilekit.bin --list=build\tilekit.lst --symbols || exit /b 1
