@echo off
rem Assembles the game kit into build\: TILEKIT.COM (build\tilekit.bin), SONGKIT.COM
rem (build\songkit.bin) and SONGPLAY.COM (build\songplay.bin), each with its own program header,
rem which mkdiskimg puts in /CMD.
call "%~dp0..\lwtools_env.bat" || exit /b 1
if not exist build mkdir build

%LWASM% tilekit.asm --6309 --format=raw --includedir=..\bios --includedir=..\vidcard --output=build\tilekit.bin --list=build\tilekit.lst --symbols || exit /b 1
%LWASM% songplay.asm --6309 --format=raw --includedir=..\bios --output=build\songplay.bin --list=build\songplay.lst --symbols || exit /b 1
%LWASM% songkit.asm --6309 --format=raw --includedir=..\bios --includedir=..\vidcard --output=build\songkit.bin --list=build\songkit.lst --symbols || exit /b 1
