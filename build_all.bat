@echo off
rem Builds everything from source: the BIOS, DOS, shell, editor and BASIC (with lwtools -- see README.md),
rem the emulator, the tools and the tests (with CMake and Visual Studio 2022), the disk image
rem basic309\disk.img, and then runs the test suite.
rem
rem   build_all.bat            build everything and run the tests
rem   build_all.bat notests    build everything, don't run the tests
rem   build_all.bat Debug      use the Debug configuration (default: Release)
setlocal
set ROOT=%~dp0
set CONFIG=Release
set RUNTESTS=1
for %%A in (%*) do (
    if /i "%%A"=="notests" set RUNTESTS=0
    if /i "%%A"=="Debug" set CONFIG=Debug
)

call "%ROOT%lwtools_env.bat" || exit /b 1
where cmake >nul 2>nul || (echo ERROR: cmake was not found on the PATH. See README.md, "Building from source". & exit /b 1)

echo === Assembling the BIOS, DOS, shell, editor, assembler and BASIC ===
for %%D in (bios dos shell edit pugasm) do (
    pushd "%ROOT%%%D" || exit /b 1
    call .\compile.bat || (popd & exit /b 1)
    popd
)
pushd "%ROOT%basic309" || exit /b 1
call .\build_basic.bat || (popd & exit /b 1)
popd

echo === Building the emulator and tools ===
call "%ROOT%check_build_dir.bat" "%ROOT%simulator\build" || exit /b 1
cmake -S "%ROOT%simulator" -B "%ROOT%simulator\build" -A x64 || exit /b 1
cmake --build "%ROOT%simulator\build" --config %CONFIG% --target mkdiskimg basic309_sdboot_demo || exit /b 1

echo === Making the disk image ===
"%ROOT%simulator\build\tools\%CONFIG%\mkdiskimg.exe" || exit /b 1

echo === Building the tests ===
rem (Configured again now that the ROM and disk images exist: the tests that need them are
rem  only included when the files are there.)
cmake -S "%ROOT%simulator" -B "%ROOT%simulator\build" -A x64 >nul || exit /b 1
cmake --build "%ROOT%simulator\build" --config %CONFIG% || exit /b 1

if "%RUNTESTS%"=="1" (
    echo === Running the tests ^(under a minute in Release, several minutes in Debug^) ===
    ctest --test-dir "%ROOT%simulator\build" -C %CONFIG% --output-on-failure || exit /b 1
)
echo.
echo Built. Run:  simulator\build\tools\%CONFIG%\basic309_sdboot_demo.exe
endlocal
