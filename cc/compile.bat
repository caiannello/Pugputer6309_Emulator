@echo off
rem CC's programs (cc\*.asm -> cc\*.bin, with listings): CPP.COM (the
rem preprocessor) and CC1.COM (the compiler proper). They include pa_util.asm,
rem pa_heap.asm and pa_strm.asm from asmlink\. The library is cc\lib's (its own
rem compile script).
call "%~dp0..\lwtools_env.bat" || exit /b 1
pushd "%~dp0" || exit /b 1
for %%P in (cpp cc1) do (
    %LWASM% %%P.asm --6309 --format=raw --includedir=..\bios --includedir=..\asmlink --output=%%P.bin --list=%%P.lst --symbols || (popd & exit /b 1)
)
popd
