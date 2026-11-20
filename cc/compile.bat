@echo off
rem CC's programs (cc\*.asm -> cc\*.bin, with listings): CC.COM (the driver),
rem CPP.COM (the preprocessor) and CC1.COM (the compiler proper). They include pa_util.asm,
rem pa_heap.asm and pa_strm.asm from asmlink\, and CC1 lib\fpcore.asm. The library is cc\lib's (its own
rem compile script).
call "%~dp0..\lwtools_env.bat" || exit /b 1
pushd "%~dp0" || exit /b 1
for %%P in (cc cpp cc1) do (
    %LWASM% %%P.asm --6309 --format=raw --includedir=..\bios --includedir=..\asmlink --includedir=lib --output=%%P.bin --list=%%P.lst --symbols || (popd & exit /b 1)
)
popd
