@echo off
call "%~dp0..\lwtools_env.bat" || exit /b 1

%LWASM% helpers.asm --6309 --format=obj --output=helpers.o --list=helpers.lst || exit /b 1
%LWASM% devio.asm   --6309 --format=obj --output=devio.o   --list=devio.lst   || exit /b 1
%LWASM% serio.asm   --6309 --format=obj --output=serio.o   --list=serio.lst   || exit /b 1
%LWASM% sdcard.asm  --6309 --format=obj --output=sdcard.o  --list=sdcard.lst  || exit /b 1
%LWASM% time.asm    --6309 --format=obj --output=time.o    --list=time.lst    || exit /b 1
%LWASM% loader.asm  --6309 --format=obj --output=loader.o  --list=loader.lst  || exit /b 1
%LWASM% banks.asm   --6309 --format=obj --output=banks.o   --list=banks.lst   || exit /b 1
%LWASM% main.asm    --6309 --format=obj --output=main.o    --list=main.lst    || exit /b 1

rem main.o must be linked LAST -- see compile.sh for why.
%LWLINK% --format=srec --output=pugbios.s19 --map=pugbios.map --script=linker_script helpers.o devio.o serio.o sdcard.o time.o loader.o banks.o main.o || exit /b 1

rem The Intel-hex copy (for an EPROM programmer) needs SRecord's srec_cat; it is optional.
if exist "%SRECCAT%" %SRECCAT% pugbios.s19 -Motorola -o pugbios.hex -Intel
exit /b 0
