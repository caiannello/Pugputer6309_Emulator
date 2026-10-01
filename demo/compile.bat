@echo off
rem Assembles the demos (programs\ASM\VGM, programs\ASM\VIDEO) into build\: raw images that load at $4000,
rem which mkdiskimg --sources puts on the release disk as /DEMO/*.COM (it adds the program
rem header, as ASM -f com does).
call "%~dp0..\lwtools_env.bat" || exit /b 1
if not exist build mkdir build

%LWASM% programs\ASM\VGM\VGMONKEY.ASM --6309 --format=raw --output=build\vgmonkey.bin || exit /b 1
%LWASM% programs\ASM\VGM\VGXWINGF.ASM --6309 --format=raw --output=build\vgxwingf.bin || exit /b 1
%LWASM% programs\ASM\VGM\VGMPLAY.ASM --6309 --format=raw --output=build\vgmplay.bin || exit /b 1
%LWASM% programs\ASM\VIDEO\VIDDEMO.ASM --6309 --format=raw --includedir=..\vidcard --output=build\viddemo.bin || exit /b 1
%LWASM% programs\ASM\VIDEO\VIDTEXT.ASM --6309 --format=raw --includedir=..\vidcard --includedir=programs\ASM\VIDEO --output=build\vidtext.bin || exit /b 1
%LWASM% programs\ASM\VIDEO\VIDTILES.ASM --6309 --format=raw --includedir=..\vidcard --includedir=programs\ASM\VIDEO --output=build\vidtiles.bin || exit /b 1
%LWASM% programs\ASM\VIDEO\VIDGFX.ASM --6309 --format=raw --includedir=..\vidcard --includedir=programs\ASM\VIDEO --output=build\vidgfx.bin || exit /b 1
