@echo off
title Pugputer 6309 (COM port)
echo This connects the Pugputer's serial port to a COM port on this PC. You need a
echo virtual serial-port pair (for example com0com): give this program one end, and
echo open a terminal program (PuTTY, Tera Term, ...) on the other end at 19200 baud,
echo 8 data bits, no parity, 1 stop bit. See README.md.
echo.
set /p PORT=Which COM port should the emulator use (for example COM4)? 
if "%PORT%"=="" exit /b 1
"%~dp0pugputer.exe" --com %PORT%
echo.
echo The emulator has stopped.
pause
