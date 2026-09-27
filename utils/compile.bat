@echo off
call "%~dp0..\lwtools_env.bat" || exit /b 1

%LWASM% hexdump.asm --6309 --format=raw --includedir=..\bios --output=hexdump.bin --list=hexdump.lst --symbols || exit /b 1
%LWASM% move.asm --6309 --format=raw --includedir=..\bios --output=move.bin --list=move.lst --symbols || exit /b 1
