#!/usr/bin/env python3
"""Makes SWAMP's pictures (demo/programs/ASM/VIDEO/SWAMP.ASM): turns a picture of
three painted bands into a TILEKIT project, 16x16 tiles in 256 colors at 320x240.
(The picture SWAMP's were made from isn't in the repository; demo/swamp/ has the
result.)

    python make_swamp.py swamp_layers.png OUTDIR      (needs Pillow and numpy)

Writes SWAMP.TKT, SWAMP1-3.TLS and SWAMP1-3.MAP (demo/swamp/ has them as made
by this), and preview.png, preview_seam.png (scrolled so the wrap seams show) and
parallax.gif, to look at.

The source is pixel art drawn at 4x: 1024x1024, three bands (sky, bayou, ground)
stacked, each with a caption in its top-left corner. Reduced to its real pixels
the strips are 256 wide.

Layout (screen rows, 320x240; each layer's map is 32x32 cells = 512x512 pixels,
holding its 256-pixel-wide strip twice across, so it wraps seamlessly):
  layer 1 sky:    the art at 56-141; above it, its top rows mirrored back and forth
  layer 2 bayou:  the art at 98-213, its sky see-through
  layer 3 ground: the art at 188-239, its background see-through; grass top ~211
Palette: 0 see-through, 1-239 the scenery, 240-255 left for sprites.
"""
from PIL import Image
import numpy as np
from collections import deque
import struct, os, sys

if len(sys.argv) != 3:
    sys.exit(__doc__)
SRC, OUT = sys.argv[1], sys.argv[2]
NAME = 'SWAMP'
os.makedirs(OUT, exist_ok=True)
W = 256
SKY_Y, BAYOU_Y, GROUND_Y = 56, 98, 188
FOLD = {'sky': 28, 'bayou': 24}   # seam-fix width at the right edge, per strip
NRES = 16            # palette entries kept free at the end (240-255) for sprites

# ---- the real pixels: the median of each 4x4 block; the bands between the divider lines
src = np.asarray(Image.open(SRC).convert('RGB'))
assert src.shape == (1024, 1024, 3), 'expected the 1024x1024 three-band picture'
nat = np.median(src.reshape(256, 4, 256, 4, 3).transpose(0, 2, 1, 3, 4).reshape(256, 256, 16, 3),
                axis=2).astype(np.uint8)
sky, bayou, ground = nat[0:86].copy(), nat[87:203].copy(), nat[204:256].copy()

def flood(ok):
    """what is reachable from the top row through pixels that are ok (wrapping across)"""
    H, Wd = ok.shape
    m = np.zeros_like(ok); q = deque()
    for x in range(Wd):
        if ok[0, x]: m[0, x] = True; q.append((0, x))
    while q:
        y, x = q.popleft()
        for dy, dx in ((1,0),(-1,0),(0,1),(0,-1)):
            yy, xx = y+dy, (x+dx) % Wd
            if 0 <= yy < H and not m[yy, xx] and ok[yy, xx]:
                m[yy, xx] = True; q.append((yy, xx))
    return m

# ---- bayou: its sky, by flood fill from the top against the sky's gradient (fitted
# on a clear patch, columns 128-140) -- never below the water line (row 62)
b = bayou.astype(float)
coef = [np.polyfit(np.arange(37), np.median(b[0:37, 128:141], axis=1)[:, c], 2) for c in range(3)]
skyrow = np.array([[np.polyval(coef[c], min(r, 40)) for c in range(3)] for r in range(len(b))])
ok = np.sqrt(((b - skyrow[:, None, :])**2).sum(2)) < 22
ok[0:10, 0:60] = True                    # the caption box
ok[62:] = False
mb = flood(ok)

# ---- ground: its flat dark background
g = ground.astype(float)
ok = np.sqrt(((g - np.median(g[8:12], axis=(0, 1)))**2).sum(2)) < 30
ok[0:8, 0:60] = True                     # the caption
mg = flood(ok)

# ---- sky: cover the caption with the same rows from a plain stretch of sky
sky[0:10, 0:62] = sky[0:10, 130:192]

def islands(mask, maxsize, rowlimit):
    """see-through: small opaque specks entirely surrounded by sky"""
    H, Wd = mask.shape
    seen = np.zeros_like(mask)
    for y in range(rowlimit):
        for x in range(Wd):
            if mask[y, x] or seen[y, x]:
                continue
            comp = [(y, x)]; seen[y, x] = True; q = deque(comp); touches = False
            while q:
                cy, cx = q.popleft()
                for dy, dx in ((1,0),(-1,0),(0,1),(0,-1)):
                    yy, xx = cy+dy, (cx+dx) % Wd
                    if not (0 <= yy < H): continue
                    if yy >= rowlimit: touches = True; continue
                    if not mask[yy, xx] and not seen[yy, xx]:
                        seen[yy, xx] = True; comp.append((yy, xx)); q.append((yy, xx))
            if not touches and len(comp) <= maxsize:
                for cy, cx in comp: mask[cy, cx] = True
    return mask
mb = islands(mb.copy(), 8, 44)

def round_crowns(mask, cutrow, rng):
    """Crowns sliced flat by the band's top edge (or the caption box): carve each
    flat run into a ragged dome, deeper toward its ends."""
    H, Wd = mask.shape
    first = np.array([np.argmax(~mask[:, x]) if (~mask[:, x]).any() else H for x in range(Wd)])
    cut = np.array([first[x] == cutrow[x] for x in range(Wd)])
    x = 0
    while x < Wd:
        if not cut[x]: x += 1; continue
        x0 = x
        while x < Wd and cut[x]: x += 1
        x1 = x - 1; w = x1 - x0 + 1; xc = (x0 + x1) / 2; D = min(16, max(3, w // 2))
        for xx in range(x0, x1 + 1):
            u = abs(xx - xc) / (w / 2 + 0.5)
            d = int(round(D * u * u + rng.integers(-1, 2))) if w > 2 else D
            mask[cutrow[xx]:cutrow[xx] + max(0, d), xx] = True
    return mask
cutrow = np.zeros(W, int); cutrow[0:60] = 10      # the caption box ended at row 10
mb = round_crowns(mb, cutrow, np.random.default_rng(7))

# ---- compose each layer as RGBA, 256 wide x 256 tall, at its screen rows
def rgba(rgb, mask=None):
    a = np.full(rgb.shape[:2] + (1,), 255, np.uint8)
    if mask is not None: a[mask] = 0
    return np.concatenate([rgb, a], axis=2)
def fold_seam(s, k):
    """Make the strip wrap: its last k columns become a mirror of its first k
    (so column 255 meets column 0 as a fold), joined to the original along the
    vertical path where the two differ least."""
    H, Wd, _ = s.shape
    a = s[:, Wd-k:].astype(float)                # what is there
    m = s[:, k-1::-1].astype(float)              # the mirror: m[:, k-1] = s[:, 0]
    cost = np.sqrt(((a - m)**2).sum(2))
    cost[:, 0] += 1e6                            # leave at least one column of each
    acc = cost.copy(); back = np.zeros((H, k), int)
    for y in range(1, H):
        for x in range(k):
            lo, hi = max(0, x-1), min(k, x+2)
            j = lo + int(np.argmin(acc[y-1, lo:hi])); back[y, x] = j
            acc[y, x] += acc[y-1, j]
    x = int(np.argmin(acc[-1])); out = s.copy()
    for y in range(H-1, -1, -1):
        out[y, Wd-k+x:] = s[y, k-1-x::-1] if k-1-x >= 0 else out[y, Wd-k+x:]
        x = back[y, x]
    return out

L = [np.zeros((256, W, 4), np.uint8) for _ in range(3)]
s = fold_seam(rgba(sky), FOLD['sky'])
top = s[0:16].copy(); top[:, 182:232] = s[0:16, 120:170]     # no moon in the fill above
for y in range(SKY_Y):                   # above the art: its top rows, mirrored back and forth
    t = (SKY_Y - 1 - y) % 32; blk = (SKY_Y - 1 - y) // 16
    L[0][y] = np.roll(top[t if t < 16 else 31 - t], 80 * blk, axis=0)   # each copy shifted 5 tiles
L[0][SKY_Y:SKY_Y+86] = s
for y in range(SKY_Y+86, (SKY_Y+86+15)//16*16):
    L[0][y] = s[85]                      # pad the last tile row (hidden behind the bayou)
L[1][BAYOU_Y:BAYOU_Y+116] = fold_seam(rgba(bayou, mb), FOLD['bayou'])
L[2][GROUND_Y:GROUND_Y+52] = rgba(ground, mg)

# ---- one palette for all three: k-means in OKLab, 239 colors + 0 (see-through)
def oklab(c):
    c = c / 255.0
    lin = np.where(c <= 0.04045, c/12.92, ((c+0.055)/1.055)**2.4)
    M1 = np.array([[0.4122214708,0.5363325363,0.0514459929],
                   [0.2119034982,0.6806995451,0.1073969566],
                   [0.0883024619,0.2817188376,0.6299787005]])
    M2 = np.array([[0.2104542553,0.7936177850,-0.0040720468],
                   [1.9779984951,-2.4285922050,0.4505937099],
                   [0.0259040371,0.7827717662,-0.8086757660]])
    return np.cbrt(lin @ M1.T) @ M2.T
pix = np.concatenate([l[l[..., 3] == 255][:, :3] for l in L])
uniq, cnt = np.unique(pix, axis=0, return_counts=True)
X = oklab(uniq.astype(float)); w = cnt.astype(float)
K = 255 - NRES
rng = np.random.default_rng(1)
# k-means++ seeding (weighted)
cent = [X[np.argmax(w)]]
d2 = ((X - cent[0])**2).sum(1)
for _ in range(K-1):
    p = d2 * w; i = rng.choice(len(X), p=p/p.sum()); cent.append(X[i])
    d2 = np.minimum(d2, ((X - X[i])**2).sum(1))
C = np.array(cent)
def nearest(X, C):
    best = np.empty(len(X), int)
    for a in range(0, len(X), 4096):
        best[a:a+4096] = ((X[a:a+4096, None, :] - C[None])**2).sum(2).argmin(1)
    return best
for it in range(25):
    lab = nearest(X, C)
    for k in range(K):
        m = lab == k
        if m.any(): C[k] = (X[m] * w[m, None]).sum(0) / w[m].sum()
# each center's color: the weighted mean RGB of its members, snapped to RGB565
lab = nearest(X, C)
pal = np.zeros((256, 3), int)
for k in range(K):
    m = lab == k
    pal[k] = (uniq[m] * w[m, None]).sum(0) / w[m].sum() if m.any() else 0
def to565(c):
    r, g_, b = int(c[0]), int(c[1]), int(c[2])
    return ((r * 31 + 127) // 255) << 11 | ((g_ * 63 + 127) // 255) << 5 | ((b * 31 + 127) // 255)
def from565(v):
    r, g_, b = v >> 11, (v >> 5) & 63, v & 31
    return ((r * 255 + 15) // 31, (g_ * 255 + 31) // 63, (b * 255 + 15) // 31)
scen = np.array([from565(to565(c)) for c in pal[:K]])
# order by lightness, so TILEKIT's palette reads dark to light
order = np.argsort(oklab(scen.astype(float))[:, 0])
scen = scen[order]
# sprite colors (240-255): a small set for the swamp creature
sprite = ['101810','1E3A1E','2E5A2A','3F7A34','5A9E3E','86C25A','B8E07A','4A3A28',
          '7A5A38','A88050','E8D8A0','FFFFFF','FFE040','E04020','202040','000000']
palette = [(0, 0, 0)] + [tuple(int(v) for v in c) for c in scen] + \
          [from565(to565((int(h[0:2],16), int(h[2:4],16), int(h[4:6],16)))) for h in sprite]
assert len(palette) == 256
PL = oklab(np.array(palette[1:K+1], float))

# ---- every pixel to its palette index (0 where see-through)
idx = []
for l in L:
    o = np.zeros(l.shape[:2], np.uint8)
    op = l[..., 3] == 255
    o[op] = nearest(oklab(l[op][:, :3].astype(float)), PL) + 1
    idx.append(o)

# ---- tiles (16x16), deduplicated with flips; tile 0 blank; map 32x32
TS = 16; MW = MH = 32
def build(ix):
    tiles = [np.zeros((TS, TS), np.uint8)]
    seen = {tiles[0].tobytes(): (0, 0)}
    cells = np.zeros((256 // TS, W // TS), np.uint16)
    for ty in range(256 // TS):
        for tx in range(W // TS):
            t = ix[ty*TS:(ty+1)*TS, tx*TS:(tx+1)*TS]
            hit = None
            for fl, v in ((0, t), (1, t[:, ::-1]), (2, t[::-1, :]), (3, t[::-1, ::-1])):
                if v.tobytes() in seen:
                    hit = (seen[v.tobytes()][0], fl); break
            if hit is None:
                seen[t.tobytes()] = (len(tiles), 0); hit = (len(tiles), 0); tiles.append(t.copy())
            cells[ty, tx] = hit[0] | (hit[1] << 10)
    m = np.zeros((MH, MW), np.uint16)
    m[0:256 // TS, 0:16] = cells; m[0:256 // TS, 16:32] = cells   # the strip twice across
    return tiles, m

pal565 = b''.join(struct.pack('>H', to565(c)) for c in palette)
names = []
for n, ix in enumerate(idx, 1):
    tiles, m = build(ix)
    tls, mp = f'{NAME}{n}.TLS', f'{NAME}{n}.MAP'
    hdr = b'PTS1' + bytes([TS, 8, 0, 0]) + struct.pack('>H', len(tiles)) + bytes(6)
    open(os.path.join(OUT, tls), 'wb').write(hdr + pal565 + b''.join(t.tobytes() for t in tiles))
    mh = b'PTM1' + struct.pack('>HH', MW, MH) + tls.encode().ljust(40, b'\0')
    open(os.path.join(OUT, mp), 'wb').write(mh + m.astype('>u2').tobytes())
    room = 48 * 1024 - MW * MH * 2
    print(f'layer {n}: {len(tiles)} tiles ({len(tiles)*256} bytes, room for {room // 256})')
    names.append((tls, mp, tiles, m))

with open(os.path.join(OUT, f'{NAME}.TKT'), 'w', newline='\r\n') as f:
    f.write('; TILEKIT project\n[PROJECT]\nORDER 1 2 3\nEDIT 3\n')
    for n, (tls, mp, _, _) in enumerate(names, 1):
        f.write(f'[LAYER{n}]\nTILES {tls}\nMAP {mp}\nSCREEN 320\nSHOW YES\n')
    f.write('[PALETTE]\n')
    for r in range(16):
        f.write(' '.join('%02X%02X%02X' % palette[r*16+i] for i in range(16)) + '\n')

# ---- render from the files' data the way the card does: 320x240, layers back to front
P = np.array(palette, np.uint8)
def layer_img(tiles, m):
    T = np.stack(tiles)
    img = np.zeros((MH*TS, MW*TS), np.uint8)
    for y in range(MH):
        for x in range(MW):
            c = int(m[y, x]); t = T[c & 1023]
            if c & 1024: t = t[:, ::-1]
            if c & 2048: t = t[::-1, :]
            img[y*TS:(y+1)*TS, x*TS:(x+1)*TS] = t
    return img
LI = [layer_img(t, m) for _, _, t, m in names]
def frame_idx(scrolls, back=0):
    out = np.full((240, 320), back, np.uint8)
    for li, sx in zip(LI, scrolls):
        v = np.roll(li, -(sx % 512), axis=1)[0:240, 0:320]
        out = np.where(v != 0, v, out)
    return out
Image.fromarray(P[frame_idx((0, 0, 0))]).resize((960, 720), Image.NEAREST).save(os.path.join(OUT, 'preview.png'))
Image.fromarray(P[frame_idx((256 - 40,) * 3)]).resize((960, 720), Image.NEAREST).save(os.path.join(OUT, 'preview_seam.png'))
# parallax: sky 1, bayou 2, ground 4 pixels a frame; 256 frames make a whole loop
frames = []
for f in range(256):
    im = Image.fromarray(frame_idx((f, 2 * f, 4 * f)), 'P'); im.putpalette(P.flatten().tolist()); frames.append(im)
frames[0].save(os.path.join(OUT, 'parallax.gif'), save_all=True, append_images=frames[1:], duration=33, loop=0)
print('ok')
