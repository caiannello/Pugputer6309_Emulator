#!/usr/bin/env python3
"""Writes demo/programs/ASM/VIDEO/VIDGFX.ASM: the program below, with its drawing-command
lists and palettes computed here (panel geometry, the labels' characters, the tunnel's rings,
the spinner's eight frames). Edit this, not the .ASM, and run it again:

    python3 vidcard/tools/make_vidgfx.py
"""
import math
import os

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '..', '..', 'demo', 'programs', 'ASM', 'VIDEO', 'VIDGFX.ASM')

C = dict(NOP=0, TARGET=1, COLOR=2, PLOT=3, LINE=4, RECT=5, FILLRECT=6, CIRCLE=7, DISC=8, CLEAR=9,
         COPY=10, FILL=11, BLIT=12, TRIANGLE=13, FONT=14, CHAR=15)


def rgb565(r, g, b):
    return (int(r) >> 3) << 11 | (int(g) >> 2) << 5 | int(b) >> 3


class Cmds:
    """A list of drawing commands, written out as FCB/FDB lines."""

    def __init__(self):
        self.lines = []

    def op(self, name, *words, bytes_after=(), comment=None):
        # the opcode, then 16-bit words, then single bytes
        parts = ['            FCB  C_%s' % name]
        if words:
            parts.append('            FDB  ' + ','.join(str(w) for w in words))
        if bytes_after:
            parts.append('            FCB  ' + ','.join(str(b) for b in bytes_after))
        if comment:
            parts[0] += ' ' * max(1, 36 - len(parts[0])) + '; ' + comment
        self.lines.extend(parts)

    def target(self, addr, stride, w, h, bpp, comment=None):
        self.lines.append('            FCB  C_TARGET,$%02X,$%02X,$%02X' % (addr >> 16, (addr >> 8) & 255, addr & 255)
                          + ('' if not comment else ' ' * 4 + '; ' + comment))
        self.lines.append('            FDB  %d,%d,%d' % (stride, w, h))
        self.lines.append('            FCB  %d' % bpp)

    def color(self, c):
        self.lines.append('            FCB  C_COLOR,%d' % c)

    def a24(self, name, *addrs_and_rest):
        pass

    def raw(self, *vals):
        self.lines.append('            FCB  ' + ','.join(str(v) for v in vals))

    def text(self, x, y, s):
        for i, ch in enumerate(s):
            self.op('CHAR', x + 8 * i, y, bytes_after=(ord(ch),))

    def out(self):
        return '\n'.join(self.lines) + '\n'


def b3(a):
    return '$%02X,$%02X,$%02X' % (a >> 16, (a >> 8) & 255, a & 255)


# ---------------------------------------------------------------- page 1
BITMAP1 = 0x000000   # 640x480, 4 bits a pixel: 320 bytes a row
STAMP = 0x800000     # in the PSRAM: a 16x16 stamp, 4 bits a pixel
PX = [4 + c * 159 for c in range(4)]
PY = [22 + r * 221 for r in range(2)]
PW, PH = 155, 215

p1 = Cmds()
p1.target(BITMAP1, 320, 640, 480, 4, 'the bitmap')
p1.lines.append('            FCB  C_FONT,' + b3(0x03F000) + ',16          ; the card\'s font, for CHAR')
p1.color(0)
p1.op('CLEAR')
names = ['PLOT', 'LINE', 'RECT', 'FILLRECT', 'CIRCLE', 'DISC', 'TRIANGLE', 'BLIT COPY FILL']
for i, name in enumerate(names):
    x, y = PX[i % 4], PY[i // 4]
    p1.color(1)
    p1.op('RECT', x, y, PW, PH, comment='panel %d: %s' % (i, name))
    p1.text(x + 6, y + 4, name)
# LINE: a fan from the bottom left corner to the top and right edges
x, y = PX[1], PY[0]
k = 0
for t in range(0, PW - 12, 7):
    p1.color(2 + k % 6)
    k += 1
    p1.op('LINE', x + 4, y + PH - 5, x + 8 + t, y + 24)
for t in range(0, PH - 34, 7):
    p1.color(2 + k % 6)
    k += 1
    p1.op('LINE', x + 4, y + PH - 5, x + PW - 5, y + 24 + t)
# RECT: nested
x, y = PX[2], PY[0]
for i in range(14):
    p1.color(2 + i % 6)
    p1.op('RECT', x + 8 + 5 * i, y + 26 + 6 * i, PW - 16 - 10 * i, PH - 34 - 12 * i)
# FILLRECT: bars
x, y = PX[3], PY[0]
for i, h in enumerate([60, 120, 90, 170, 40, 140, 100, 150]):
    p1.color(2 + i % 6)
    p1.op('FILLRECT', x + 8 + i * 18, y + PH - 8 - h, 14, h)
# CIRCLE: rings in the cycling colors (8-15)
x, y = PX[0], PY[1]
for i, r in enumerate(range(4, 76, 4)):
    p1.color(8 + i % 8)
    p1.op('CIRCLE', x + PW // 2, y + 118, r)
# DISC: bubbles
x, y = PX[1], PY[1]
for i, (dx, dy, r) in enumerate([(40, 60, 30), (100, 70, 38), (70, 120, 26), (30, 160, 22), (110, 160, 34),
                                 (60, 190, 14), (130, 110, 12), (20, 100, 10), (90, 30, 8), (125, 35, 6)]):
    p1.color(2 + i % 6)
    p1.op('DISC', x + dx, y + dy + 8, r)
    p1.color(1)
    p1.op('DISC', x + dx - r // 3, y + dy + 8 - r // 3, max(1, r // 6))
# TRIANGLE: a pinwheel
x, y = PX[2] + PW // 2, PY[1] + 120
for i in range(12):
    a0 = 2 * math.pi * i / 12
    a1 = a0 + 2 * math.pi / 24
    p1.color(2 + i % 6)
    p1.op('TRIANGLE', x, y, round(x + 70 * math.cos(a0)), round(y + 70 * math.sin(a0)),
          round(x + 70 * math.cos(a1)), round(y + 70 * math.sin(a1)))
# BLIT, COPY, FILL: a stamp drawn in the PSRAM and stamped out; stripes filled straight into
# the bitmap's bytes; rows of the bubbles copied under them.
x, y = PX[3], PY[1]
p1.target(STAMP, 8, 16, 16, 4, 'the stamp, in the PSRAM')
p1.color(0)
p1.op('CLEAR')
p1.color(4)
p1.op('DISC', 7, 7, 7)
p1.color(3)
p1.op('CIRCLE', 7, 7, 7)
p1.color(1)
p1.op('DISC', 5, 5, 1)
p1.target(BITMAP1, 320, 640, 480, 4, 'the bitmap again')
for row in range(3):
    for col in range(8):
        p1.lines.append('            FCB  C_BLIT,' + b3(STAMP))
        p1.lines.append('            FDB  8,16,16,%d,%d' % (x + 8 + col * 17, y + 26 + row * 18))
        p1.lines.append('            FCB  1              ; (0 is transparent)')
for row in range(12):   # FILL: bytes of two pixels, colors 5 and 6, then 6 and 5
    addr = BITMAP1 + (y + 84 + row) * 320 + (x + 8) // 2
    p1.lines.append('            FCB  C_FILL,%s,$00,$00,%d,$%02X' % (b3(addr), 70, 0x56 if row % 2 == 0 else 0x65))
src_x, src_y = PX[1] + 8, PY[1] + 40   # COPY: 100 rows of the bubbles, 70 bytes (140 pixels) each
for row in range(100):
    src = BITMAP1 + (src_y + row) * 320 + src_x // 2
    dst = BITMAP1 + (y + 104 + row) * 320 + (x + 8) // 2
    if y + 104 + row >= y + PH - 4:
        break
    p1.lines.append('            FCB  C_COPY,%s,%s,$00,$00,%d' % (b3(src), b3(dst), 70))

PAL1 = [(16, (0, 0, 60)), (17, (255, 255, 255)), (18, (230, 40, 40)), (19, (250, 150, 30)), (20, (250, 230, 40)),
        (21, (60, 200, 60)), (22, (40, 200, 230)), (23, (140, 90, 250))]
RAMP8 = []   # the cycling colors 8-15 (entries 24-31): a ring of hues, twice over
for i in range(8):
    h = i / 8
    r = 128 + 127 * math.cos(2 * math.pi * h)
    g = 128 + 127 * math.cos(2 * math.pi * (h - 1 / 3))
    b = 128 + 127 * math.cos(2 * math.pi * (h - 2 / 3))
    RAMP8.append(rgb565(r, g, b))

# ---------------------------------------------------------------- page 2
TUNNEL = 0x000000    # 320x240, 8 bits a pixel
SPINA = 0x014000     # the spinner's two buffers: 80x64, 2 bits a pixel, 20 bytes a row
SPINB = 0x014800
WORDS = 0x018000     # 640x480, 1 bit a pixel, 80 bytes a row
FRAMES = 0x800000    # the spinner's 8 frames, in the PSRAM (1280 bytes each)
p2 = Cmds()
p2.target(TUNNEL, 320, 320, 240, 8, 'the tunnel: rings in colors 32-95')
for i, r in enumerate(range(110, 1, -2)):
    p2.color(32 + i % 64)
    p2.op('DISC', 160, 120, r)
p2.target(WORDS, 80, 640, 480, 1, 'the words, 1 bit a pixel')
p2.color(1)
p2.op('RECT', 2, 2, 636, 476)
p2.op('RECT', 5, 5, 630, 470)
p2.text(24, 14, 'BITMAPS OF 8, 2 AND 1 BITS A PIXEL, RASTER INTERRUPTS, THE PSRAM')
p2.text(24, 440, 'THE SPINNER: 8 FRAMES IN THE PSRAM, COPIED IN.    A KEY: BACK TO THE SHELL')
for f in range(8):
    p2.target(FRAMES + f * 1280, 20, 80, 64, 2, 'spinner frame %d' % f)
    p2.color(0)
    p2.op('CLEAR')
    p2.color(1)
    p2.op('DISC', 40, 32, 30)
    p2.color(2)
    for blade in range(3):
        a = math.radians(f * 15 + blade * 120)
        p2.op('TRIANGLE', 40, 32, round(40 + 28 * math.cos(a - 0.25)), round(32 + 28 * math.sin(a - 0.25)),
              round(40 + 28 * math.cos(a + 0.25)), round(32 + 28 * math.sin(a + 0.25)))
    p2.color(3)
    p2.op('DISC', 40, 32, 6)
RAMP64 = []
for i in range(64):
    h = i / 64
    r = 128 + 127 * math.cos(2 * math.pi * h)
    g = 128 + 127 * math.cos(2 * math.pi * (h - 1 / 3))
    b = 128 + 127 * math.cos(2 * math.pi * (h - 2 / 3))
    RAMP64.append(rgb565(r, g, b))
BARS = []   # entries 128-159: two copper bars, bright in their middles
for i in range(32):
    t = math.sin(math.pi * (i % 16) / 16)
    BARS.append(rgb565(40 + 215 * t, 20 + 120 * t, 60 + 60 * t) if i < 16 else rgb565(20 + 60 * t, 40 + 200 * t, 80 + 175 * t))
PAL2 = [(113, (60, 40, 110)), (114, (250, 220, 90)), (115, (255, 255, 255)), (241, (255, 255, 255))]


def fdb_list(vals, per=8):
    out = []
    for i in range(0, len(vals), per):
        out.append('            FDB  ' + ','.join('$%04X' % v for v in vals[i:i + per]))
    return '\n'.join(out) + '\n'


def pal_list(entries):
    return ''.join('            FCB  %d\n            FDB  $%04X\n' % (n, rgb565(*c)) for n, c in entries)


SOURCE = open(os.path.join(HERE, 'vidgfx.template')).read()
SOURCE = SOURCE.replace('@@PAGE1@@\n', p1.out()).replace('@@PAGE2@@\n', p2.out())
SOURCE = SOURCE.replace('@@PAL1@@\n', pal_list(PAL1)).replace('@@PAL2@@\n', pal_list(PAL2))
SOURCE = SOURCE.replace('@@RAMP8@@\n', fdb_list(RAMP8 + RAMP8)).replace('@@RAMP64@@\n', fdb_list(RAMP64 + RAMP64))
SOURCE = SOURCE.replace('@@BARS@@\n', fdb_list(BARS))
assert '@@' not in SOURCE
with open(OUT, 'w', newline='\n') as f:
    f.write(SOURCE)
print('wrote', os.path.normpath(OUT))
