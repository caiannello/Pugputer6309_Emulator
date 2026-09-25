@echo off
rem Rebuilds BIOS, dos.asm, the shell, the editor, pugasm, puglink and basic309, then regenerates
rem basic309\disk.img from scratch (just SHELL.COM, EDIT.COM, PUGASM.COM, PUGLINK.COM and BASIC.COM,
rem no other files) -- run this
rem any time you want a clean slate between test sessions, or after editing bios/,
rem dos/, shell/, edit/, pugasm/ or basic309/.
setlocal
set ROOT=%~dp0
set MKDISKIMG=%ROOT%simulator\build\tools\Release\mkdiskimg.exe
if not exist "%MKDISKIMG%" set MKDISKIMG=%ROOT%simulator\build\tools\Debug\mkdiskimg.exe
if not exist "%MKDISKIMG%" (
    echo ERROR: mkdiskimg.exe is not built yet -- see README.md, "Building from source".
    exit /b 1
)

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

echo Rebuilding the editor...
pushd "%ROOT%edit" || exit /b 1
call "%ROOT%edit\compile.bat"
if errorlevel 1 (popd & exit /b 1)
popd

echo Rebuilding the assembler and linker...
pushd "%ROOT%pugasm" || exit /b 1
call "%ROOT%pugasm\compile.bat"
if errorlevel 1 (popd & exit /b 1)
popd

echo Rebuilding basic309...
call "%ROOT%basic309\build_basic.bat"
if errorlevel 1 exit /b 1

echo Regenerating disk.img (SHELL.COM, EDIT.COM, PUGASM.COM, PUGLINK.COM and BASIC.COM only, clean slate)...
"%MKDISKIMG%" || exit /b 1

echo Done.
endlocal
