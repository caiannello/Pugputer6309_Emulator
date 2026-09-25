@echo off
call "%~dp0..\lwtools_env.bat" || exit /b 1

%LWASM% pugasm.asm --6309 --format=raw --includedir=..\bios --output=pugasm.bin --list=pugasm.lst --symbols || exit /b 1
