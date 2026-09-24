@echo off
set LWDIR=..\lwtools-4.20\bin
set LWASM=%LWDIR%\lwasm.exe

%LWASM% shell.asm --6309 --format=raw --includedir=..\bios --output=shell.bin --list=shell.lst --symbols || exit /b 1
