@echo off
call "%~dp0..\lwtools_env.bat" || exit /b 1

%LWASM% asm.asm --6309 --format=raw --includedir=..\bios --output=asm.bin --list=asm.lst --symbols || exit /b 1
%LWASM% link.asm --6309 --format=raw --includedir=..\bios --output=link.bin --list=link.lst --symbols || exit /b 1
%LWASM% ar.asm --6309 --format=raw --includedir=..ios --output=ar.bin --list=ar.lst --symbols || exit /b 1
