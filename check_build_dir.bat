@echo off
rem check_build_dir.bat <folder>: deletes a CMake build folder that was configured for another
rem copy of the project (after the project is moved or copied, CMake refuses to use it), so the
rem next configure starts fresh. Does nothing if the folder is missing or belongs here.
setlocal
set DIR=%~1
set SRC=%~dp0simulator
set SRC=%SRC:\=/%
if not exist "%DIR%\CMakeCache.txt" exit /b 0
findstr /i /c:"CMAKE_HOME_DIRECTORY:INTERNAL=%SRC%" "%DIR%\CMakeCache.txt" >nul && exit /b 0
echo %DIR% was configured for another copy of the project; deleting it.
rmdir /s /q "%DIR%" || exit /b 1
endlocal
