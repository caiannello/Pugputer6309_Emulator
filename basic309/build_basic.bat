@echo off
rem Assembles basic309\exbasrom309.asm into exbasrom309.s19 and a listing WITH
rem a symbol table (exbasrom309.lst) -- simulator\tests\test_basic309_token_audit
rem reads the symbols from that listing, so always build through this script.
setlocal
set HERE=%~dp0
set LWASM=%HERE%..\lwtools-4.20\bin\lwasm.exe
pushd "%HERE%" || exit /b 1
"%LWASM%" exbasrom309.asm --6309 --format=srec --output=exbasrom309.s19 --list=exbasrom309.lst --symbols
set RC=%ERRORLEVEL%
popd
exit /b %RC%
