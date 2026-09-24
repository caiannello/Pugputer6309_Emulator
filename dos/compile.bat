@echo off
set LWDIR=..\lwtools-4.20\bin
set LWASM=%LWDIR%\lwasm.exe

%LWASM% dos.asm --6309 --format=raw --includedir=..\bios --output=dos.bin --list=dos.lst --symbols || exit /b 1
