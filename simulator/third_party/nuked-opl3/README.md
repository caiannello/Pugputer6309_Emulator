# Nuked OPL3

`opl3.c` and `opl3.h` are **Nuked OPL3** 1.8 by Nuke.YKT, a cycle-accurate emulator of the Yamaha
YMF262 (OPL3), unmodified, from <https://github.com/nukeykt/Nuked-OPL3> (commit
`765ec962e473aeb767e4cba74ffdc8f588ffbfe8`). They are licensed under the GNU Lesser General Public
License, version 2.1 or later (`LICENSE`); the rest of this project is MIT-licensed. The emulator
uses them through `../../src/pugputer/opl3_device.cpp` (the YMF262 at `$FFE0`-`$FFE3`).
