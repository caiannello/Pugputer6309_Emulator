@echo off
call "%~dp0..\lwtools_env.bat" || exit /b 1

%LWASM% shell.asm --6309 --format=raw --includedir=..\bios --output=shell.bin --list=shell.lst --symbols || exit /b 1
