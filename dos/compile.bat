@echo off
call "%~dp0..\lwtools_env.bat" || exit /b 1

%LWASM% dos.asm --6309 --format=raw --includedir=..\bios --output=dos.bin --list=dos.lst --symbols || exit /b 1
