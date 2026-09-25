@echo off
call "%~dp0..\lwtools_env.bat" || exit /b 1

%LWASM% edit.asm --6309 --format=raw --includedir=..\bios --output=edit.bin --list=edit.lst --symbols || exit /b 1
