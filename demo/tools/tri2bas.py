#!/usr/bin/env python3
"""Makes a BASIC program that draws a picture of flat-colored triangles on the video card.

    python tri2bas.py picture.json PROGRAM.BAS

picture.json: {"width": w, "height": h, "vertices": [[x, y], ...],
               "triangles": [{"v": [i, j, k], "color": [r, g, b]}, ...]}
(as /BASIC/GXBEE.BAS was made, from smbee_tri1000.json, and /BASIC/GXTRUCKS.BAS, from
smtrucks_tri512.json). The picture is at most 256 pixels wide and 240 tall; the program shows
it centered in SCREEN 1 (320x240, 256 colors).

- The colors are quantized to at most 255 (palette entries 1-255; 0 is transparent): k-means,
  each color weighted by its triangles' area.
- Each triangle is grown by half a pixel along its edges before its corners are rounded to
  pixels. Meshes like this one have T-junctions (a corner on another triangle's edge): exact,
  they meet; rounded, cracks open along those edges, and the backdrop shows through.
- The numbers are in DATA strings, two letters each (A-P: the 16s, then the 1s): as decimal
  numbers the 1000-triangle picture doesn't fit in BASIC's memory.
"""
import json
import math
import random
import sys


def d2(a, b):
    return (a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2 + (a[2] - b[2]) ** 2


def quantize(cols, weights, k):
    """k-means++ seeding, then Lloyd's iterations: (palette, each color's entry in it)."""
    k = min(k, len(set(cols)))
    random.seed(1)
    cent = [cols[max(range(len(cols)), key=lambda i: weights[i])]]
    dist = [d2(c, cent[0]) for c in cols]
    while len(cent) < k:
        r = random.random() * sum(dd * w for dd, w in zip(dist, weights))
        for i, (dd, w) in enumerate(zip(dist, weights)):
            r -= dd * w
            if r <= 0:
                break
        cent.append(cols[i])
        dist = [min(dd, d2(c, cols[i])) for dd, c in zip(dist, cols)]
    cent = [tuple(map(float, c)) for c in cent]
    for _ in range(30):
        lab = [min(range(k), key=lambda j: d2(c, cent[j])) for c in cols]
        acc = [[0.0, 0.0, 0.0, 0.0] for _ in range(k)]
        for c, w, l in zip(cols, weights, lab):
            a = acc[l]
            a[0] += c[0] * w; a[1] += c[1] * w; a[2] += c[2] * w; a[3] += w
        new = [(a[0] / a[3], a[1] / a[3], a[2] / a[3]) if a[3] else cent[j] for j, a in enumerate(acc)]
        if new == cent:
            break
        cent = new
    used = sorted(set(lab))
    entry = {j: i + 1 for i, j in enumerate(used)}
    err = sum(d2(c, cent[l]) * w for c, w, l in zip(cols, weights, lab)) / sum(weights)
    print(f'{len(used)} colors, rms error {err ** 0.5:.2f}', file=sys.stderr)
    return [tuple(int(round(v)) for v in cent[j]) for j in used], [entry[l] for l in lab]


def grow(p, w, h, g=0.5, cap=2.0):
    """Triangle p with each edge pushed out by g pixels (each corner along its bisector, at
    most cap), its corners rounded to pixels within the picture (0 to w-1, h-1)."""
    out = []
    for i in range(3):
        x, y = p[i]
        a, b = p[i - 1], p[(i + 1) % 3]
        u = (a[0] - x, a[1] - y)
        v = (b[0] - x, b[1] - y)
        lu = math.hypot(*u) or 1
        lv = math.hypot(*v) or 1
        u = (u[0] / lu, u[1] / lu)
        v = (v[0] / lv, v[1] / lv)
        bx, by = -(u[0] + v[0]), -(u[1] + v[1]) # outward, between the two edges
        lb = math.hypot(bx, by)
        if lb < 1e-9:
            out.append((x, y))
            continue
        s = math.sin(math.acos(max(-1, min(1, u[0] * v[0] + u[1] * v[1]))) / 2) or 1e-9
        m = min(g / s, cap)
        out.append((x + bx / lb * m, y + by / lb * m))
    return [(min(w - 1, max(0, round(x))), min(h - 1, max(0, round(y)))) for x, y in out]


def enc(nums):
    return ''.join(chr(65 + (n >> 4)) + chr(65 + (n & 15)) for n in nums)


def main():
    src, out = sys.argv[1], sys.argv[2]
    d = json.load(open(src))
    w, h = d['width'], d['height']
    if w > 256 or h > 240:
        sys.exit('the picture must be at most 256x240')
    verts, tris = d['vertices'], d['triangles']

    def area(t):
        (ax, ay), (bx, by), (cx, cy) = (verts[i] for i in t['v'])
        return abs((bx - ax) * (cy - ay) - (cx - ax) * (by - ay)) / 2 + 1

    pal, entries = quantize([tuple(t['color']) for t in tris], [area(t) for t in tris], 255)
    xo, yo = (320 - w) // 2, (240 - h) // 2
    xs, ys = (f'V+{xo}' if xo else 'V'), (f'V+{yo}' if yo else 'V')
    prog = {
        10: f"REM A PICTURE MADE OF {len(tris)} FLAT-COLORED TRIANGLES, ON THE VIDEO CARD AT",
        20: f"REM 320X240 IN {len(pal)} COLORS (MADE BY DEMO/TOOLS/TRI2BAS.PY)",
        30: "V=0:J=0:GOTO 100",
        40: "REM V: THE NEXT NUMBER IN S$, AT J: TWO LETTERS, A-P, THE 16S THEN THE 1S",
        50: "V=ASC(MID$(S$,J,1))*16+ASC(MID$(S$,J+1,1))-1105:J=J+2:RETURN",
        100: "REM THE COLORS, FROM 1 ON: RED, GREEN, BLUE. A \".\" ENDS THEM",
        110: "SCREEN 1:GCLS:I=0",
        120: "READ S$:IF S$=\".\" THEN 150",
        130: "J=1",
        140: "GOSUB 50:R=V:GOSUB 50:G=V:GOSUB 50:I=I+1:PALETTE I,R,G,V:IF J<LEN(S$) THEN 140",
        145: "GOTO 120",
        150: f"REM THE TRIANGLES: X,Y THREE TIMES (THE PICTURE IS {w}X{h}: IT'S MOVED TO",
        155: "REM THE MIDDLE OF THE SCREEN), THEN THE COLOR",
        160: "READ S$:IF S$=\".\" THEN 200",
        170: "J=1",
        180: f"GOSUB 50:A={xs}:GOSUB 50:B={ys}:GOSUB 50:C={xs}:GOSUB 50:D={ys}:GOSUB 50:E={xs}:"
             f"GOSUB 50:F={ys}:GOSUB 50:TRIANGLE (A,B)-(C,D)-(E,F),V:IF J<LEN(S$) THEN 180",
        190: "GOTO 160",
        200: "PRINT \"PRESS ANY KEY TO QUIT\"",
        210: "IF INKEY$=\"\" THEN 210",
        220: "SCREEN 0:END",
    }
    n = 1000
    pdat = [v for c in pal for v in c]
    for i in range(0, len(pdat), 60): # 20 colors a line
        prog[n] = 'DATA ' + enc(pdat[i:i + 60])
        n += 10
    prog[n] = 'DATA .'
    tdat = []
    for t, e in zip(tris, entries):
        for x, y in grow([verts[i] for i in t['v']], w, h):
            tdat += [x, y]
        tdat.append(e)
    n = max(n + 10, 2000)
    for i in range(0, len(tdat), 7 * 8): # 8 triangles a line
        prog[n] = 'DATA ' + enc(tdat[i:i + 56])
        n += 10
    prog[n] = 'DATA .'
    with open(out, 'w', newline='\n') as f:
        for k in sorted(prog):
            f.write(f'{k} {prog[k]}\n')


if __name__ == '__main__':
    main()
