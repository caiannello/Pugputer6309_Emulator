@echo off
rem Builds the Windows x64 binary demo release: dist\Pugputer6309-demo-<version>-win64\ and
rem the zip next to it. Everything is rebuilt from source: the BIOS, DOS, shell and BASIC
rem (needs lwtools -- see README.md), then the emulator in Release configuration with the
rem C++ runtime linked statically (so there are no DLLs to ship), then a disk image holding
rem the shell, BASIC and the demo programs.
rem
rem Needs: lwtools, CMake and Visual Studio 2022 (or its Build Tools) with the C++ workload.
setlocal
set VERSION=0.1.0
set ROOT=%~dp0
set NAME=Pugputer6309-demo-%VERSION%-win64
set OUT=%ROOT%dist\%NAME%
set BUILD=%ROOT%simulator\build-release

call "%ROOT%lwtools_env.bat" || exit /b 1

echo === Assembling the BIOS, DOS, shell and BASIC ===
for %%D in (bios dos shell) do (
    pushd "%ROOT%%%D" || exit /b 1
    call .\compile.bat || (popd & exit /b 1)
    popd
)
pushd "%ROOT%basic309" || exit /b 1
call .\build_basic.bat || (popd & exit /b 1)
popd

echo === Building the emulator (Release, static runtime) ===
cmake -S "%ROOT%simulator" -B "%BUILD%" -A x64 -DHD6309_BUILD_TESTS=OFF -DPUGPUTER_STATIC_RUNTIME=ON || exit /b 1
cmake --build "%BUILD%" --config Release --target basic309_sdboot_demo mkdiskimg || exit /b 1

echo === Assembling %NAME% ===
if exist "%ROOT%dist\%NAME%" rmdir /s /q "%ROOT%dist\%NAME%"
mkdir "%OUT%" || exit /b 1
copy /y "%BUILD%\tools\Release\basic309_sdboot_demo.exe" "%OUT%\pugputer.exe" >nul || exit /b 1
copy /y "%ROOT%bios\pugbios.s19" "%OUT%\pugbios.s19" >nul || exit /b 1
"%BUILD%\tools\Release\mkdiskimg.exe" --out "%OUT%\disk-original.img" --add-dir "%ROOT%demo\programs" || exit /b 1
copy /y "%OUT%\disk-original.img" "%OUT%\disk.img" >nul
copy /y "%ROOT%demo\release\start-console.bat" "%OUT%\" >nul || exit /b 1
copy /y "%ROOT%demo\release\start-com-port.bat" "%OUT%\" >nul || exit /b 1
copy /y "%ROOT%demo\release\reset-disk.bat" "%OUT%\" >nul || exit /b 1
copy /y "%ROOT%demo\release\README.md" "%OUT%\README.md" >nul || exit /b 1
copy /y "%ROOT%LICENSE" "%OUT%\LICENSE.txt" >nul || exit /b 1
copy /y "%ROOT%NOTICE.md" "%OUT%\NOTICE.md" >nul || exit /b 1

echo === Zipping ===
if exist "%ROOT%dist\%NAME%.zip" del "%ROOT%dist\%NAME%.zip"
powershell -NoProfile -Command "Compress-Archive -Path '%OUT%' -DestinationPath '%ROOT%dist\%NAME%.zip'" || exit /b 1
echo.
echo Done: %ROOT%dist\%NAME%.zip
endlocal
