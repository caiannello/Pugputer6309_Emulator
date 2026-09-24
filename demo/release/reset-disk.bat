@echo off
echo This puts the demo disk back the way it came, deleting any files you saved on it.
set /p OK=Continue (Y/N)? 
if /i not "%OK%"=="Y" exit /b 1
copy /y "%~dp0disk-original.img" "%~dp0disk.img" >nul && echo Done.
pause
