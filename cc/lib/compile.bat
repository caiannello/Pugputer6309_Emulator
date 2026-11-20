@echo off
rem The C library's objects (cc\lib\*.o, with listings): crt0.o, and the members
rem of libc.a, which libc.rsp lists in order (it is AR's response file: on the
rem Pugputer, "AR @libc.rsp" makes libc.a from them). mkdiskimg puts them on the
rem disk as /LIB/CRT0.O and /LIB/LIBC.A, with CC.SCR. The same for libpug.a (the
rem Pugputer's own: video, input, sound), from libpug.rsp, as /LIB/LIBPUG.A.
call "%~dp0..\..\lwtools_env.bat" || exit /b 1
pushd "%~dp0" || exit /b 1
for %%M in (crt0) do (
    %LWASM% %%M.asm --6309 --format=obj --includedir=..\..\bios --output=%%M.o --list=%%M.lst --symbols || (popd & exit /b 1)
)
for /f "skip=1" %%O in (libc.rsp) do (
    %LWASM% %%~nO.asm --6309 --format=obj --includedir=..\..\bios --output=%%~nO.o --list=%%~nO.lst --symbols || (popd & exit /b 1)
)
for /f "skip=1" %%O in (libpug.rsp) do (
    %LWASM% %%~nO.asm --6309 --format=obj --includedir=..\..\bios --includedir=..\..\vidcard --includedir=..\..\gamekit --output=%%~nO.o --list=%%~nO.lst --symbols || (popd & exit /b 1)
)
popd
