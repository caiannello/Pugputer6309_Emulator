@echo off
rem Rebuilds BIOS, dos.asm, the shell and basic309, then regenerates
rem basic309\disk.img from scratch (just SHELL.COM and BASIC.COM, no other files) -- run this any time you
rem want a clean slate between test sessions, or after editing bios/,
rem dos/, or basic309/.
setlocal
set ROOT=%~dp0
set LWASM=%ROOT%lwtools-4.20\bin\lwasm.exe
set MKDISKIMG=%ROOT%simulator\build\tools\Debug\mkdiskimg.exe

echo Rebuilding BIOS...
pushd "%ROOT%bios" || exit /b 1
call "%ROOT%bios\compile.bat"
if errorlevel 1 (popd & exit /b 1)
popd

echo Rebuilding dos.asm...
pushd "%ROOT%dos" || exit /b 1
call "%ROOT%dos\compile.bat"
if errorlevel 1 (popd & exit /b 1)
popd

echo Rebuilding shell...
pushd "%ROOT%shell" || exit /b 1
call "%ROOT%shell\compile.bat"
if errorlevel 1 (popd & exit /b 1)
popd

echo Rebuilding basic309...
call "%ROOT%basic309\build_basic.bat"
if errorlevel 1 exit /b 1

echo Regenerating disk.img (BASIC.COM only, clean slate)...
"%MKDISKIMG%" || exit /b 1

echo Done.
endlocal
