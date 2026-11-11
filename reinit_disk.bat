@echo off
rem Rebuilds BIOS, dos.asm, the shell, the editor, ASM, LINK, the utilities, the demos and basic309, then
rem regenerates basic309\disk.img from scratch (/CMD: SHELL.COM, EDIT.COM, ASM.COM, LINK.COM, HEXDUMP.COM, MOVE.COM, TILEKIT.COM and BASIC.COM,
rem and /DEMO: SWAMP.COM and its pictures -- no other files, apart from local\disk\ if there is one) -- run this
rem any time you want a clean slate between test sessions, or after editing bios/,
rem dos/, shell/, edit/, asmlink/, utils/ or basic309/.
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
pushd "%ROOT%asmlink" || exit /b 1
call "%ROOT%asmlink\compile.bat"
if errorlevel 1 (popd & exit /b 1)
popd

echo Rebuilding the utilities...
pushd "%ROOT%utils" || exit /b 1
call "%ROOT%utils\compile.bat"
if errorlevel 1 (popd & exit /b 1)
popd

echo Rebuilding the game kit...
pushd "%ROOT%gamekit" || exit /b 1
call "%ROOT%gamekit\compile.bat"
if errorlevel 1 (popd & exit /b 1)
popd

echo Rebuilding the demos...
pushd "%ROOT%demo" || exit /b 1
call "%ROOT%demo\compile.bat"
if errorlevel 1 (popd & exit /b 1)
popd

echo Rebuilding basic309...
call "%ROOT%basic309\build_basic.bat"
if errorlevel 1 exit /b 1

echo Regenerating disk.img (/CMD: SHELL.COM, EDIT.COM, ASM.COM, LINK.COM, HEXDUMP.COM, MOVE.COM, TILEKIT.COM and BASIC.COM; /DEMO/SWAMP.COM; clean slate)...
rem local\disk\ (not in the repository, see .gitignore): experiments to try on the disk, copied
rem to its root as they are -- local\disk\SWAMP\X.BAS becomes /SWAMP/X.BAS
set LOCALDISK=
if exist "%ROOT%local\disk\" (
    echo Adding local\disk\ to the disk...
    set LOCALDISK=--add-dir "%ROOT%local\disk"
)
"%MKDISKIMG%" --demo SWAMP %LOCALDISK% || exit /b 1

echo Done.
endlocal
