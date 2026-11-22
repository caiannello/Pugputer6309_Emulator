"""mod2sng: an Amiga module (.MOD: ProTracker, NoiseTracker, Soundtracker; 4 to 8 channels) made
a SONGKIT song (.SNG), its samples played by The Fat Man's 2-op and 4-op patches
(banks/FATMAN2.WOP, FATMAN4.WOP) -- or, where none comes close, by voices made for them.

    python mod2sng.py song.mod [OUT.SNG] [options]        (--help lists them)

Like midi2sng it listens: every sound it considers is played by SONGPLAY on the emulated
Pugputer (the test suite's songkit_song_to_wav: the real player and Nuked OPL3) and heard
against the module's own sound (a log-mel spectrogram's distance, dB).

1. The module is played as ProTracker plays it, tick by tick -- each channel's sample,
   period and volume, its effects, Bxx/Dxx/E6x/EEx -- and that is what the song is made
   from: the orders it plays are the song's orders (a pattern the same as another kept once),
   and the loop is where it comes back to.
2. Each sample is heard: its pitch (and the chord, if it is one), at the notes and lengths
   the song plays it. Every patch of both banks is played so and heard against it; the
   closest few again an octave (or a drum's few notes) either way.
3. A chord sample is tried as its notes on tracks of their own; a sample no patch comes
   close to (a voice, say) as sines at its loudest harmonics, each with its own envelope.
4. The best of each is refined: its envelopes, and its modulators' levels, a step at a time,
   kept where it is heard to be closer. Its loudness against the others is the module's.
5. Each module channel gets the tracks its samples need (4-op ones where they are 4-op);
   the cells say what the module did: notes and volumes, slides and vibrato in 32nds of a
   semitone (from the periods the module's slides went through), volume slides in steps,
   arpeggios, note delays and cuts, speed and tempo; a sample that ends lets its key go.

Needs numpy and the emulator's test program (build_all builds it).
"""
import argparse
import math
import os
import re
import shutil
import struct
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import midi2sng as m2s  # noqa: E402  (the banks, the renders, the song file)

np = m2s.np
say = m2s.say
STEP = m2s.STEP
INF = float("inf")

PAL = 3546894.6              # Paula's clock / 2: a period's samples a second
C2 = 428                     # ProTracker's C-2
PT_PERIODS = [856, 808, 762, 720, 678, 640, 604, 570, 538, 508, 480, 453,
              428, 404, 381, 360, 339, 320, 302, 285, 269, 254, 240, 226,
              214, 202, 190, 180, 170, 160, 151, 143, 135, 127, 120, 113]
PT_NAMES = ["C-", "C#", "D-", "D#", "E-", "F-", "F#", "G-", "G#", "A-", "A#", "B-"]
SINE = [0, 24, 49, 74, 97, 120, 141, 161, 180, 197, 212, 224, 235, 244, 250, 253,
        255, 253, 250, 244, 235, 224, 212, 197, 180, 161, 141, 120, 97, 74, 49, 24]
OP4_TRACKS = [0, 9, 1, 10, 2, 11]
OP4_BITS = {0: 0x01, 9: 0x08, 1: 0x02, 10: 0x10, 2: 0x04, 11: 0x20}
PARTNER = {0: 3, 1: 4, 2: 5, 9: 12, 10: 13, 11: 14}
TEST_TRACKS = [0, 9, 1, 10]  # a test's layers (4-op channels play 2-op instruments too)
MULTS = [0.5, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 15]
MULT_CODE = {0.5: 0, 1: 1, 2: 2, 3: 3, 4: 4, 5: 5, 6: 6, 7: 7, 8: 8, 9: 9, 10: 10, 12: 12, 15: 15}
SILENT = bytes([0, 0, 0, 0x00, 0x3F, 0xFF, 0x0F, 0, 0x00, 0x3F, 0xFF, 0x0F, 0] + [0] * 19)


def sng_name(n):
    return "%s%d" % (PT_NAMES[(n - 1) % 12], (n - 1) // 12)


# ---- The module ---------------------------------------------------------------------------------
class Sample:
    pass


class Mod:
    pass


def read_mod(path):
    d = open(path, "rb").read()
    tag = d[1080:1084]
    known = {b"M.K.": 4, b"M!K!": 4, b"M&K!": 4, b"FLT4": 4, b"4CHN": 4, b"N.T.": 4,
             b"6CHN": 6, b"8CHN": 8, b"FLT8": 8, b"CD81": 8, b"OKTA": 8, b"OCTA": 8}
    nch = known.get(tag)
    if nch is None and tag[2:] in (b"CH", b"CN") and tag[:2].isdigit():
        nch = int(tag[:2])
    if nch is None and tag[1:] == b"CHN" and tag[:1].isdigit():
        nch = int(tag[:1])
    nsmp = 31 if nch else 15
    nch = nch or 4
    m = Mod()
    m.nch = nch
    m.title = d[:20].split(b"\0")[0].decode("latin-1").strip()
    m.samples = [None]
    for i in range(nsmp):
        o = 20 + 30 * i
        s = Sample()
        s.num = i + 1
        s.name = d[o:o + 22].split(b"\0")[0].decode("latin-1").strip()
        ln, ft, vol, ls, ll = struct.unpack(">HBBHH", d[o + 22:o + 30])
        s.len, s.ft, s.vol = ln * 2, (ft & 15) - (16 if ft & 8 else 0), min(vol, 64)
        s.ls, s.ll = ls * 2, ll * 2
        if nsmp == 15:              # (Soundtracker's loop start is in bytes)
            s.ls = ls
        m.samples.append(s)
    hdr = 20 + 30 * nsmp
    songlen = max(1, min(128, d[hdr]))
    m.restart = d[hdr + 1]
    allorders = list(d[hdr + 2:hdr + 130])
    m.orders = allorders[:songlen]
    at = hdr + 130 + (4 if nsmp == 31 else 0)
    npat = max(allorders) + 1
    psize = 64 * 4 * nch
    m.pats = []
    for p in range(npat):
        rows = []
        for r in range(64):
            row = []
            for c in range(nch):
                b = d[at + p * psize + (r * nch + c) * 4:at + p * psize + (r * nch + c) * 4 + 4]
                if len(b) < 4:
                    b = bytes(4)
                row.append((((b[0] & 0x0F) << 8) | b[1], (b[0] & 0xF0) | (b[2] >> 4), b[2] & 0x0F, b[3]))
            rows.append(row)
        m.pats.append(rows)
    at += npat * psize
    for s in m.samples[1:]:
        raw = d[at:at + s.len]
        at += s.len
        s.data = np.frombuffer(raw, np.int8).astype(np.float32) / 128 if raw else np.zeros(0, np.float32)
        s.len = len(s.data)
        s.loops = s.ll > 2 and s.ls + 2 < s.len
        if s.loops:
            s.ll = min(s.ll, s.len - s.ls)
            s.le = s.ls + s.ll
        else:
            s.le = s.len
    return m


# ---- Playing it, as ProTracker does ----------------------------------------------------------------
def rate_for_bpm(bpm):
    """The SONGKIT rate (ticks a second) nearest a tempo's ticks (2.5 s / bpm), and its tick."""
    want = 2.5 / bpm
    best = min(m2s.RATE_FOR.items(), key=lambda kv: abs(kv[0] * STEP - want))
    return best[1], best[0]


class ChRow:
    """A channel's row: the cell, the effect as it acted, and each tick's sound."""
    __slots__ = ("cell", "fx", "par", "trig", "smp", "base", "out", "vol", "alive", "target", "pan",
                 "offset", "vib")


class Row:
    __slots__ = ("order", "prow", "speed", "bpm", "tick", "ch", "cont")


class ChState:
    def __init__(self):
        self.inst = 0          # the sample the next note plays
        self.smp = 0           # the sample playing
        self.per = 0           # its period (no arpeggio or vibrato)
        self.vol = 0
        self.ft = 0
        self.target = 0
        self.pspeed = 0
        self.vspeed = self.vdepth = self.vpos = 0
        self.tspeed = self.tdepth = self.tpos = 0
        self.offset = 0
        self.loop_row = self.loop_cnt = 0
        self.pos = 0.0
        self.alive = False
        self.pan = 0


def ft_period(per, ft):
    return per * 2 ** (-ft / 96.0) if ft else float(per)


def simulate(mod, opts):
    """The module played: [Row], the rows where the song's orders start, the loop (a row, or
    None)."""
    nch = mod.nch
    chs = [ChState() for _ in range(nch)]
    for c in range(nch):
        chs[c].pan = (0, 2, 2, 0)[c % 4] if opts.amiga_pan else 0   # (0 both, 1 left... see below)
    speed, bpm = 6, 125
    rows, starts = [], []
    seen = {}
    o, r = 0, 0
    loop = None
    new = True
    stats = {"offset": 0, "retrig": 0, "tremolo": 0}
    guard = 0
    while guard < 30000:
        guard += 1
        if o >= len(mod.orders):
            if opts.no_loop:
                break
            lo = mod.restart if mod.restart < len(mod.orders) else 0
            key = ("order", lo)
            loop = seen.get(key)
            break
        key = (o, r, tuple((c.loop_row, c.loop_cnt) for c in chs))
        if key in seen:
            loop = seen[key]
            break
        seen[key] = len(rows)
        if r == 0 and ("order", o) not in seen:
            seen[("order", o)] = len(rows)
        if new:
            starts.append(len(rows))
            new = False
        pat = mod.orders[o]
        cells = mod.pats[pat][r] if pat < len(mod.pats) else [(0, 0, 0, 0)] * nch
        stop = False
        for per, smp, fx, par in cells:
            if fx == 0xF:
                if par == 0:
                    stop = True
                elif par < 32:
                    speed = par
                else:
                    bpm = par
        jump = brk = None
        delay = 0
        loopjump = None
        recs = []
        for c, (per, smp, fx, par) in enumerate(cells):
            ch = chs[c]
            rec = ChRow()
            rec.cell = (per, smp, fx, par)
            rec.trig = {}
            rec.offset = 0
            if smp and smp < len(mod.samples) and mod.samples[smp]:
                ch.inst = smp
                ch.vol = mod.samples[smp].vol
                ch.ft = mod.samples[smp].ft
            ex = par >> 4 if fx == 0xE else None
            ey = par & 15
            # memories
            if fx == 3 and par:
                ch.pspeed = par
            if fx == 4:
                if par >> 4:
                    ch.vspeed = par >> 4
                if par & 15:
                    ch.vdepth = par & 15
            if fx == 7:
                if par >> 4:
                    ch.tspeed = par >> 4
                if par & 15:
                    ch.tdepth = par & 15
            if fx == 9 and par:
                ch.offset = par * 256
            if ex == 5:
                ch.ft = ey - 16 if ey & 8 else ey
            if per:
                p = ft_period(per, ch.ft)
                if fx in (3, 5):
                    ch.target = p
                elif ex == 0xD and 0 < ey < speed:
                    rec.trig[ey] = 0
                    ch.delayed = p
                elif ex == 0xD and ey >= speed:
                    pass                        # (a delay past the row: no note at all)
                else:
                    off = ch.offset if fx == 9 else 0
                    if fx == 9:
                        stats["offset"] += 1
                    rec.trig[0] = off
                    rec.offset = off
                    ch.per = p
                    ch.smp = ch.inst
                    ch.pos = float(off)
                    ch.alive = ch.smp and off < (mod.samples[ch.smp].len if mod.samples[ch.smp] else 0)
                    ch.vpos = ch.tpos = 0
            if fx == 0xC:
                ch.vol = min(par, 64)
            elif fx == 0xB:
                jump = par
            elif fx == 0xD:
                brk = (par >> 4) * 10 + (par & 15)
                if brk > 63:
                    brk = 0
            elif fx == 8:
                ch.pan = 1 if par < 0x40 else (2 if par > 0xC0 else 0)
            elif ex == 1 and ch.per:
                ch.per = max(113.0, ch.per - ey)
            elif ex == 2 and ch.per:
                ch.per = min(856.0, ch.per + ey)
            elif ex == 0xA:
                ch.vol = min(64, ch.vol + ey)
            elif ex == 0xB:
                ch.vol = max(0, ch.vol - ey)
            elif ex == 0xC and ey == 0:
                ch.vol = 0
            elif ex == 0xE:
                delay = max(delay, ey)
            elif ex == 6:
                if ey == 0:
                    ch.loop_row = r
                else:
                    if ch.loop_cnt == 0:
                        ch.loop_cnt = ey
                    else:
                        ch.loop_cnt -= 1
                    if ch.loop_cnt:
                        loopjump = ch.loop_row
            elif ex == 9 and ey:
                stats["retrig"] += 1
            if fx == 7:
                stats["tremolo"] += 1
            rec.fx, rec.par = fx, par
            rec.target = ch.target
            rec.vib = (ch.vspeed, ch.vdepth)
            recs.append(rec)
        rate, steps = rate_for_bpm(bpm)
        tick = steps * STEP
        for rep in range(1 + delay):
            row = Row()
            row.order, row.prow, row.speed, row.bpm, row.tick = o, r, speed, bpm, tick
            row.cont = rep > 0
            row.ch = []
            for c in range(nch):
                ch = chs[c]
                src = recs[c]
                if rep:
                    rec = ChRow()
                    rec.cell = (0, 0, 0, 0)
                    rec.fx, rec.par, rec.trig, rec.target, rec.offset = src.fx, src.par, {}, src.target, 0
                    rec.vib = src.vib
                else:
                    rec = src
                per, smp, fx, par = src.cell
                ex = par >> 4 if fx == 0xE else None
                ey = par & 15
                rec.base, rec.out, rec.vol, rec.alive = [], [], [], []
                for t in range(speed):
                    if t > 0 or rep > 0:
                        if t and ex == 0xD and ey == t and not rep and t in rec.trig:
                            ch.per = ch.delayed
                            ch.smp = ch.inst
                            ch.pos = 0.0
                            ch.alive = bool(ch.smp)
                            ch.vpos = ch.tpos = 0
                        if t and ex == 9 and ey and t % ey == 0:
                            rec.trig[t] = 0
                            ch.pos = 0.0
                            ch.alive = bool(ch.smp)
                        if t and ex == 0xC and ey == t:
                            ch.vol = 0
                        if t:
                            if fx == 1 and ch.per:
                                ch.per = max(113.0, ch.per - par)
                            elif fx == 2 and ch.per:
                                ch.per = min(856.0, ch.per + par)
                            elif fx in (3, 5) and ch.target and ch.per:
                                if ch.per < ch.target:
                                    ch.per = min(ch.target, ch.per + ch.pspeed)
                                elif ch.per > ch.target:
                                    ch.per = max(ch.target, ch.per - ch.pspeed)
                            if fx in (5, 6, 0xA):
                                if par >> 4:
                                    ch.vol = min(64, ch.vol + (par >> 4))
                                else:
                                    ch.vol = max(0, ch.vol - (par & 15))
                    out = ch.per
                    vol = ch.vol
                    if fx == 0 and par and ch.per:
                        k = (0, par >> 4, par & 15)[t % 3]
                        out = ch.per * 2 ** (-k / 12)
                    elif fx in (4, 6) and ch.per and (t or rep):
                        dlt = SINE[ch.vpos & 31] * ch.vdepth / 128
                        out = ch.per + (-dlt if ch.vpos & 32 else dlt)
                        ch.vpos = (ch.vpos + ch.vspeed) & 63
                    elif fx == 7 and (t or rep):
                        dlt = SINE[ch.tpos & 31] * ch.tdepth / 64
                        vol = int(max(0, min(64, vol + (-dlt if ch.tpos & 32 else dlt))))
                        ch.tpos = (ch.tpos + ch.tspeed) & 63
                    rec.base.append(ch.per)
                    rec.out.append(out)
                    rec.vol.append(vol)
                    rec.alive.append(bool(ch.alive))
                    if ch.alive and out:
                        s = mod.samples[ch.smp]
                        ch.pos += PAL / out * tick
                        if not s.loops and ch.pos >= s.len:
                            ch.alive = False
                rec.smp = ch.smp
                rec.pan = ch.pan
                row.ch.append(rec)
            rows.append(row)
        if stop:
            break
        if loopjump is not None:
            r = loopjump
        elif jump is not None or brk is not None:
            if jump is not None:
                o = jump
            else:
                o += 1
            r = brk if brk is not None else 0
            new = True
        else:
            r += 1
            if r >= 64:
                r = 0
                o += 1
                new = True
    return rows, starts, loop, stats


def note_events(mod, rows):
    """Each note played: (sample, period, volume, seconds it sounds, its row, channel)."""
    nch = mod.nch
    ev = []
    cur = [None] * nch          # [sample, period, vol, start time, row, channel, last sounding time]
    t = 0.0
    for ri, row in enumerate(rows):
        for c, rec in enumerate(row.ch):
            for k in range(row.speed):
                tt = t + k * row.tick
                if k in rec.trig:
                    if cur[c]:
                        ev.append(cur[c])
                    cur[c] = [rec.smp, rec.base[k], rec.vol[k], tt, ri, c, tt]
                if cur[c] and rec.alive[k] and rec.vol[k] > 0:
                    cur[c][6] = tt + row.tick
        t += row.speed * row.tick
    for c in range(nch):
        if cur[c]:
            ev.append(cur[c])
    return [(e[0], e[1], e[2], max(e[6] - e[3], 0.02), e[4], e[5]) for e in ev if e[0]]


# ---- The module's sound ----------------------------------------------------------------------------
def sample_stream(s, n):
    """A sample as it plays from its start, through its loop: n frames (0s after a one-shot)."""
    if s.len == 0:
        return np.zeros(n, np.float32)
    if not s.loops:
        out = np.zeros(n, np.float32)
        m = min(n, s.len)
        out[:m] = s.data[:m]
        return out
    head = s.data[:s.le]
    if n <= len(head):
        return head[:n].copy()
    reps = int(math.ceil((n - len(head)) / s.ll))
    return np.concatenate([head] + [s.data[s.ls:s.le]] * reps)[:n]


def play_span(s, pos, inc, n):
    """n output frames of sample s from position pos, inc frames a frame: (frames, new pos, alive)."""
    idx = pos + inc * np.arange(n, dtype=np.float64)
    if s.loops:
        over = idx >= s.le
        if over.any():
            idx[over] = s.ls + np.mod(idx[over] - s.ls, s.ll)
        i0 = idx.astype(np.int64)
        f = (idx - i0).astype(np.float32)
        i1 = i0 + 1
        i1[i1 >= s.le] = s.ls
        y = s.data[i0] * (1 - f) + s.data[i1] * f
        np_ = pos + inc * n
        if np_ >= s.le:
            np_ = s.ls + math.fmod(np_ - s.ls, s.ll)
        return y, np_, True
    ok = idx < s.len - 1
    y = np.zeros(n, np.float32)
    if ok.any():
        ii = idx[ok]
        i0 = ii.astype(np.int64)
        f = (ii - i0).astype(np.float32)
        y[ok] = s.data[i0] * (1 - f) + s.data[i0 + 1] * f
    np_ = pos + inc * n
    return y, np_, np_ < s.len


def render_mod(mod, rows, rate, pan=False):
    """The module as Paula would play it (linear interpolation, no filter): (n, 2) floats."""
    total = sum(r.speed * r.tick for r in rows)
    out = np.zeros((int(total * rate) + rate, 2), np.float32)
    nch = mod.nch
    pos = [0.0] * nch
    alive = [False] * nch
    smp = [0] * nch
    t = 0.0
    for row in rows:
        for k in range(row.speed):
            a = int(round(t * rate))
            b = int(round((t + row.tick) * rate))
            t += row.tick
            n = b - a
            for c, rec in enumerate(row.ch):
                if k in rec.trig:
                    pos[c] = float(rec.trig[k])
                    smp[c] = rec.smp
                    alive[c] = True
                s = mod.samples[smp[c]] if smp[c] else None
                per, vol = rec.out[k], rec.vol[k]
                if not s or not alive[c] or not per or not vol or n <= 0:
                    if s and alive[c] and per and n > 0:
                        _, pos[c], alive[c] = play_span(s, pos[c], PAL / per / rate, 1)
                        pos[c] += PAL / per / rate * (n - 1)
                    continue
                y, pos[c], alive[c] = play_span(s, pos[c], PAL / per / rate, n)
                y *= vol / 64.0
                p = rec.pan
                if p == 0 or not pan:
                    out[a:b, 0] += y * 0.5
                    out[a:b, 1] += y * 0.5
                else:
                    out[a:b, 0 if p == 1 else 1] += y
    return out[:int(total * rate)]


def render_note(s, period, seconds, rate):
    n = int(seconds * rate)
    y, _, _ = play_span(s, 0.0, PAL / period / rate, n)
    return y


# ---- A sample's pitch ---------------------------------------------------------------------------------
BPS = 96                     # bands a octave (eighths of a semitone)
F_LO = 25.0


def log_spectrum(x, rate):
    """Peak magnitude in each 1/8-semitone band from F_LO up, of a long window of x; and the
    spectrum itself (magnitudes, their frequencies)."""
    nfft = 1 << 17
    w = np.hanning(len(x)).astype(np.float32)
    mag = np.abs(np.fft.rfft(x * w, nfft))
    hz = np.arange(len(mag)) * rate / nfft
    nb = int(BPS * math.log2(min(rate / 2, 12000) / F_LO))
    band = np.floor(BPS * np.log2(np.maximum(hz, 1e-9) / F_LO)).astype(np.int64)
    ok = (band >= 0) & (band < nb)
    L = np.zeros(nb, np.float64)
    np.maximum.at(L, band[ok], mag[ok])
    # (bands narrower than a bin, low down: filled from their neighbours)
    for i in range(1, nb):
        if L[i] == 0:
            L[i] = L[i - 1] * 0.999
    return L, mag, hz


def refine_hz(f, mag, hz):
    """A tone's frequency from its first harmonics' peaks (each one's centroid, within a third
    of a semitone), the louder weighing more."""
    top = mag.max()
    num = den = 0.0
    for h in (1, 2, 3, 4):
        lo, hi = f * h * 2 ** (-1 / 36), f * h * 2 ** (1 / 36)
        sel = (hz >= lo) & (hz <= hi)
        if not sel.any():
            continue
        m = mag[sel]
        if m.max() < top * 0.03:
            continue
        p = m ** 2
        fc = float(np.sum(hz[sel] * p) / np.sum(p)) / h
        w = float(m.max()) / h
        num += fc * w
        den += w
    return num / den if den else f


def salience(L, harmonics=12):
    nb = len(L)
    win = np.maximum.reduce([np.roll(L, k) for k in (-2, -1, 0, 1, 2)])
    win[:2] = L[:2]
    win[-2:] = L[-2:]
    S = np.zeros(nb)
    for h in range(1, harmonics + 1):
        off = int(round(BPS * math.log2(h)))
        w = 0.86 ** (h - 1)
        S[:nb - off] += w * win[off:]
    return S


def analyse_pitch(s):
    """(Hz at C-2, [(interval semitones, weight)], harmonicity): its pitch -- a tone must be
    there itself, not only its harmonics (a fifth's two notes are the harmonics of a note an
    octave below them both) -- and, a chord, its other notes."""
    rate = PAL / C2
    n = int(rate * 1.2)
    x = sample_stream(s, n)
    a = min(int(0.03 * rate), max(0, s.len // 10)) if not s.loops else int(0.03 * rate)
    b = min(len(x), a + 8192) if s.loops else min(s.len, a + 8192)
    seg = x[a:b]
    if len(seg) < 512 or not np.any(seg):
        return None, [], 0.0
    L, mag, hz = log_spectrum(seg, rate)
    lo = int(BPS * math.log2(30 / F_LO))
    hi = int(BPS * math.log2(1500 / F_LO))
    tones, js = [], []
    Lw = L.copy()
    top = L.max()
    for k in range(5):
        S = salience(Lw)
        own = np.maximum.reduce([np.roll(Lw, d) for d in (-2, -1, 0, 1, 2)])
        S[own < 0.1 * top] = 0
        j = lo + int(np.argmax(S[lo:hi]))
        sal = S[j]
        if sal <= 0:
            break
        f = refine_hz(F_LO * 2 ** (j / BPS), mag, hz)
        if k == 0:
            first = sal
            f1 = f
        elif sal < 0.3 * first:
            break
        iv = 12 * math.log2(f / f1)
        # (a chord's notes are in tune with each other: anything else is a drum's partials)
        if abs(iv - round(iv)) < 0.35 and all(abs(round(iv) - t) >= 1.5 for t, _ in tones) \
                and abs(iv) <= 24:
            tones.append((float(round(iv)), sal / first))
            js.append(j)
        for h in range(1, 31):
            c = j + int(round(BPS * math.log2(h)))
            if c < len(Lw):
                Lw[max(0, c - 5):c + 6] = 0
    # how much of it is its note's harmonics, and its chord's
    e_all = max(float(np.sum(L[lo:] ** 2)), 1e-12)
    near = np.zeros(len(L), bool)
    hs = []
    for j in js:
        for h in range(1, 17):
            c = j + int(round(BPS * math.log2(h)))
            if c < len(L):
                near[max(0, c - 4):c + 5] = True
        hs.append(float(np.sum(L[lo:][near[lo:]] ** 2)) / e_all)
    return f1, tones, hs[0] if hs else 0.0, hs[-1] if hs else 0.0


# ---- Instruments ----------------------------------------------------------------------------------------
def carriers(ins):
    """The operators heard (0-3) of a SONGKIT instrument."""
    if ins[0] & 1:
        return {(0, 0): [3], (0, 1): [1, 3], (1, 0): [0, 3], (1, 1): [0, 2, 3]}[(ins[1] & 1, ins[2] & 1)]
    return [0, 1] if ins[1] & 1 else [1]


def opb(op):
    return 3 + 5 * op


class Layer:
    """One track's part of a sound: an instrument, an interval (semitones from the sample's
    pitch, or a drum's notes from its own), and how much quieter (dB) than the sound's loudest."""

    def __init__(self, ins, kind, iv=0.0, att=0.0, src=None, name="", fixed=None, koff=0,
                 delay=0.0, hold=None):
        self.ins = bytearray(ins)
        self.kind = kind          # "m": pitched as the sample; "p": a drum, its note its own
        self.iv, self.att, self.src, self.name = iv, att, src, name
        self.fixed, self.koff = fixed, koff
        self.delay, self.hold = delay, hold   # (seconds: it starts this long after the note,
                                              # and its key is let go this long after that)

    def copy(self):
        return Layer(self.ins, self.kind, self.iv, self.att, self.src, self.name, self.fixed, self.koff,
                     self.delay, self.hold)

    def four(self):
        return bool(self.ins[0] & 1)


class Sound:
    def __init__(self, layers, label):
        self.layers, self.label = layers, label
        self.score = INF
        self.gain = 0.0

    def copy(self):
        s = Sound([l.copy() for l in self.layers], self.label)
        s.score, s.gain = self.score, self.gain
        return s

    def key(self):
        return tuple((bytes(l.ins), l.kind, round(l.iv, 3), round(l.att, 2), l.fixed, l.delay, l.hold)
                     for l in self.layers)


def from_patch(p, kind, iv=0.0):
    ins = bytearray(p.ins)
    if ins[0] & 2:
        fixed = ins[23]
        ins[0] &= ~2 & 0xFF
        return Layer(ins, "p" if kind == "p" else "m", iv, 0.0, p.src, p.name, fixed=fixed, koff=0)
    koff = ins[23] - 256 if ins[23] > 127 else ins[23]
    return Layer(ins, "m", iv, 0.0, p.src, p.name, koff=koff)


class Info:
    """What is known of a sample: how it is played, and its pitch."""


def layer_bytes(layer, info, extra_att=0.0):
    """The layer's 32 bytes for this sample: its transpose and fine tune so that the song's
    note sounds the sample's pitch, its carriers quieter by its attenuation."""
    ins = bytearray(layer.ins)
    t = info.tune
    if layer.kind == "p" and layer.fixed is not None:
        xp = layer.fixed + int(round(layer.iv)) - info.nref
        fine = 0
    else:
        want = t + layer.iv
        xp = layer.koff + int(round(want))
        fine = int(round(32 * (want - round(want))))
    xp -= info.shift
    xp = max(-48, min(48, xp))
    ins[23] = xp & 0xFF
    ins[24] = fine & 0xFF
    steps = int(round((layer.att + extra_att) / 0.75))
    if steps:
        for op in carriers(ins):
            b = opb(op) + 1
            ins[b] = (ins[b] & 0xC0) | min(63, (ins[b] & 0x3F) + steps)
    return bytes(ins)


# ---- Hearing ---------------------------------------------------------------------------------------------
def features(y, rate):
    return m2s.logmel(np.ascontiguousarray(y, np.float32), rate, hop=256, nfft=2048)


FLOOR_DB = 40                 # how far below a sample's loudest a difference is still heard
METRIC = "loud"
MAX_GAIN = 36                 # a patch this much quieter than its sample is near silent: not one


def loud_gain(T, C):
    """The difference of C from T as loudness (each band's power to the 0.3, Stevens' law: a
    quiet band's difference counts for little), at C's best gain: (percent of T's, gain dB)."""
    n = min(len(T), len(C))
    if n == 0:
        return INF, 0.0
    PT = 10 ** (T[:n] / 10)
    PC = 10 ** (C[:n] / 10)
    NT = PT ** 0.3
    NC = PC ** 0.3
    st = float(NT.sum())
    sc = float(NC.sum())
    if sc <= 1e-12 or st <= 1e-12:
        return INF, 0.0
    k0 = st / sc
    best = (INF, 0.0)
    for f in (0.6, 0.7, 0.8, 0.9, 1.0, 1.1, 1.25, 1.4, 1.6):
        k = k0 * f
        d = float(np.abs(NT - k * NC).sum()) / st * 100
        if d < best[0]:
            best = (d, 10 * math.log10(k) / 0.3)
    if best[1] > MAX_GAIN:
        return INF, best[1]
    return best


def dist_gain(T, C, floor_db=None):
    """The distance (dB) of C from T at C's best gain, and that gain (dB)."""
    if METRIC == "loud" and floor_db is None:
        return loud_gain(T, C)
    floor_db = FLOOR_DB if floor_db is None else floor_db
    n = min(len(T), len(C))
    if n == 0:
        return INF, 0.0
    T, C = T[:n], C[:n]
    floor = T.max() - floor_db
    pt = float(np.sum(10 ** (T / 10)))
    pc = float(np.sum(10 ** (C / 10)))
    if pc <= 1e-9:
        return INF, 0.0
    g0 = 10 * math.log10(pt / pc)
    best = (INF, g0)
    A = np.maximum(T, floor)
    for dg in (-9, -6, -4, -2.5, -1, 0, 1, 2.5, 4, 6, 9):
        g = g0 + dg
        B = np.maximum(C + g, floor)
        act = (A > floor) | (B > floor)
        if not act.any():
            continue
        d = float(np.abs(A - B)[act].mean())
        if d < best[0]:
            best = (d, g)
    return best


class Shim:
    """What midi2sng's song-file and render helpers ask of a song."""

    def __init__(self, segs, deep):
        self.grid = type("G", (), {})()
        self.grid.segs = segs
        self.deep = deep
        self.rate = 48000


class Insts:
    def __init__(self):
        self.items = []

    def add(self, ins, name, src=None):
        self.items.append((bytes(ins), name, src))
        return len(self.items)

    add_raw = add


TEST_STEPS = 31               # the tests' rows: a tick of 31 steps (9.92 ms) each, rate 100
TEST_ROW = TEST_STEPS * STEP
TEST_GAP = 12


class Test:
    def __init__(self, info, sound, k):
        self.info, self.sound, self.k = info, sound, k
        tp = info.tests[k]
        self.note, self.win, self.koff = tp["note"], tp["win"], tp["koff"]


class Bench:
    """Sounds played on the emulated Pugputer, a few dozen to a song, several songs at once."""

    def __init__(self, rnd, deep):
        self.rnd = rnd
        self.shim = Shim([(0, 1, TEST_STEPS)], deep)
        self.rate = 48000
        self.cache = {}
        self.played = 0
        self.cal = None

    def play(self, jobs):
        """[(note, rows heard, [(32 bytes, row its note starts, row its key goes or None)])] ->
        each one's sound (mono, its rows)."""
        chunks, cur, secs, ni = [], [], 0.0, 0
        for j in jobs:
            need = len(j[2])
            if cur and (secs > 40 or ni + need > 240):
                chunks.append(cur)
                cur, secs, ni = [], 0.0, 0
            cur.append(j)
            secs += (j[1] + TEST_GAP) * TEST_ROW
            ni += need
        if cur:
            chunks.append(cur)
        built = []
        for ch in chunks:
            insts = Insts()
            sil = insts.add(SILENT, "silent")
            cells = {}
            row = 0
            at = []
            for note, win, layers in ch:
                for li, (ins, r0, r1) in enumerate(layers):
                    tr = TEST_TRACKS[li]
                    ii = insts.add(ins, "t")
                    if r0 < win:
                        cells[(row + r0, tr)] = [note, ii, 64, 0, 0]
                        if r1 is not None and r0 < r1 < win:
                            cells[(row + r1, tr)] = [0x7F, 0, 0, 0, 0]
                    cells[(row + win, tr)] = [0x7F, sil, 0, 0, 0]
                at.append((row, win))
                row += win + TEST_GAP
            rows = row + 2
            ranges = [(r, min(rows, r + 255)) for r in range(0, rows, 255)]
            lead = m2s.leadin(self.shim, insts)
            data = m2s.song_bytes(self.shim, cells, rows, 0x3F, insts, ranges, "test", "", None, lead)
            built.append((data, rows, lead[0], at))
        out = []
        if built:
            outs = self.rnd.many([(d, rows * TEST_ROW + 2) for d, rows, _, _ in built])
            self.played += len(built)
            for (data, rows, lr, at), o in zip(built, outs):
                y = m2s.song_audio(self.shim, o, lr, rows * TEST_ROW).mean(axis=1)
                self.rate = self.shim.rate
                for row, win in at:
                    a = int(round(row * TEST_ROW * self.rate))
                    b = int(round((row + win) * TEST_ROW * self.rate))
                    out.append(y[a:b])
        return out

    def job(self, t):
        layers = []
        for layer in t.sound.layers:
            r0 = int(round(layer.delay / TEST_ROW))
            r1 = t.koff
            if layer.hold is not None:
                h = r0 + int(round(layer.hold / TEST_ROW))
                r1 = h if r1 is None else min(r1, h)
            layers.append((layer_bytes(layer, t.info), r0, r1))
        return (t.note, t.win, layers)

    def hear(self, tests):
        """[Test] -> each one's (distance, gain) from its sample at that note."""
        uniq = {}
        for t in tests:
            key = (id(t.info), t.k, t.sound.key())
            if key not in self.cache:
                uniq.setdefault(key, t)
        todo = list(uniq.items())
        ys = self.play([self.job(t) for _, t in todo])
        for (key, t), y in zip(todo, ys):
            self.cache[key] = dist_gain(t.info.target[t.k], features(y, self.rate))
        return [self.cache[(id(t.info), t.k, t.sound.key())] for t in tests]

    def score(self, pairs):
        """[(info, sound)] -> each sound's score (mean distance over its sample's tests), gain."""
        tests = []
        for info, snd in pairs:
            for k in range(len(info.tests)):
                tests.append(Test(info, snd, k))
        res = self.hear(tests)
        i = 0
        out = []
        for info, snd in pairs:
            n = len(info.tests)
            rs = res[i:i + n]
            i += n
            d = sum(r[0] for r in rs) / n
            g = sum(r[1] for r in rs) / n
            snd.score, snd.gain = d, g
            out.append((d, g))
        return out

    def calibrate(self):
        """The chip's envelopes as they are heard: a sine's level (dB, a frame of ENV_HOP)
        as its attack rate takes it up from silence, and as each decay rate takes it down."""
        if self.cal:
            return self.cal
        note = 50
        win = int(round(4.0 / TEST_ROW))

        def sine(ar, dr, sl, egt, rr=15):
            ins = bytearray(32)
            ins[1] = 0x01
            ins[3:8] = bytes([0, 63, 0xFF, 0x0F, 0])
            ins[8:13] = bytes([(egt << 5) | 1, 0, (ar << 4) | dr, (sl << 4) | rr, 0])
            return bytes(ins)

        jobs = [(note, win, [(sine(ar, 0, 0, 1), 0, None)]) for ar in range(1, 16)]
        jobs += [(note, win, [(sine(15, dr, 15, 0), 0, None)]) for dr in range(1, 16)]
        ys = self.play(jobs)
        hop = int(self.rate * ENV_HOP)
        att = {}
        for ar, y in zip(range(1, 16), ys[:15]):
            e = env_db(y, self.rate, hop)
            att[ar] = e - e.max()
        slope = {0: 0.0}
        for dr, y in zip(range(1, 16), ys[15:]):
            e = env_db(y, self.rate, hop)
            e = e - e.max()
            # dB a second, from where it is 3 dB down to where it is 40 down (or the end)
            a = next((i for i in range(len(e)) if e[i] < -3), len(e) - 1)
            b = next((i for i in range(a, len(e)) if e[i] < -40), len(e) - 1)
            slope[dr] = (e[a] - e[b]) / max(ENV_HOP, (b - a) * ENV_HOP) if b > a else 2000.0
        for dr in range(9, 16):           # (faster than a frame can tell: each twice the last)
            slope[dr] = slope[dr - 1] * 2
        self.cal = (att, slope)
        return self.cal


ENV_HOP = 0.01


# ---- Each sample: how it is played, what it is ---------------------------------------------------------
def sample_infos(mod, rows, notes, rate):
    infos = {}
    for smp in sorted(set(n[0] for n in notes)):
        s = mod.samples[smp]
        if not s or s.len < 4:
            continue
        ns = [n for n in notes if n[0] == smp]
        info = Info()
        info.s = s
        info.num = smp
        info.count = len(ns)
        info.presence = sum((n[2] / 64.0) * min(n[3], 2.0) for n in ns)
        info.chans = sorted(set(n[5] for n in ns))
        info.hz, info.tones, h1, hc = analyse_pitch(s)
        info.harm = hc
        keys = set(int(round(12 * math.log2(C2 / n[1]))) for n in ns)
        # (a drum is played at a note or two; a sample played at many is an instrument)
        info.pitched = info.hz is not None and (h1 > 0.55 or (len(info.tones) >= 2 and hc > 0.8) or
                                                (len(keys) >= 4 and h1 > 0.2))
        if not info.pitched:
            info.tones = []
        if info.pitched:
            S = 58 + 12 * math.log2(info.hz / 440)       # its pitch at C-2, SONGKIT's semitones
            info.tune = S - round(S)
            info.S = S
        else:
            info.S = 37.0                                 # (a drum: C-2 shown as C-3)
            info.tune = 0.0
        pers = sorted(n[1] for n in ns)

        def pnote(p, S=info.S, tune=info.tune):     # (this sample's, not the loop's last)
            return int(round(S + 12 * math.log2(C2 / p) - tune))

        notes_n = [pnote(p) for p in pers]
        lo, hi = min(notes_n), max(notes_n)
        shift = 0
        while lo + shift < 1:
            shift += 12
        while hi + shift > 96 and lo + shift - 12 >= 1:
            shift -= 12
        info.shift = shift
        info.pnote = lambda p, f=pnote, sh=shift: max(1, min(96, f(p) + sh))
        common = max(set(pers), key=pers.count)
        info.nref = info.pnote(common)
        # the tests: one note (two if it plays over more than a fifth), its usual length
        spread = 12 * math.log2(pers[-1] / pers[0]) if pers[0] > 0 else 0
        picks = [pers[len(pers) // 2]] if spread <= 7 else [pers[int(0.8 * (len(pers) - 1))],
                                                            pers[int(0.2 * (len(pers) - 1))]]
        info.tests, info.target = [], []
        for p in picks:
            near = [n for n in ns if abs(12 * math.log2(n[1] / p)) < 3.5] or ns
            ds = sorted(n[3] for n in near)
            dur = ds[len(ds) // 2]
            sec_len = (s.len / (PAL / p)) if not s.loops else INF
            win = max(0.12, min(dur, 6.0))
            koff = sec_len if sec_len < win else None
            wr = int(math.ceil(win / TEST_ROW))
            kr = int(round(koff / TEST_ROW)) if koff is not None else None
            info.tests.append({"period": p, "note": info.pnote(p), "win": wr, "koff": kr,
                               "secs": wr * TEST_ROW})
            info.target.append(features(render_note(s, p, wr * TEST_ROW, rate), rate))
        info.sound = None
        infos[smp] = info
    return infos


# ---- Finding each sample's sound -------------------------------------------------------------------------
def bank_candidates(sg, info, variants=False, only=None):
    """Each patch as a sound for the sample: a melodic one at the sample's pitch (or a drum's
    notes, a drum); a drum's at its own note, and (a pitched sample) at the sample's. With
    variants: an octave either way (a drum's patch, a fourth and an octave)."""
    out = []
    for bank, b4 in ((sg.bank4, True), (sg.bank2, False)):
        for ik, p in bank.items():
            ways = []
            if p.ins[0] & 2:
                ways.append(("p", (-12, -5, 5, 12) if variants else (0,)))
                if info.pitched:
                    ways.append(("as", (-12, 12) if variants else (0,)))
            else:
                ways.append(("m", ((-12, 12) if info.pitched else (-24, -12, 12, 24)) if variants else (0,)))
            for way, ivs in ways:
                if only is not None and (ik, b4, way) not in only:
                    continue
                for iv in ivs:
                    lay = from_patch(p, "p", iv)
                    if way == "as":
                        lay.fixed, lay.kind = None, "m"
                    elif way == "m":
                        lay.kind = "m"
                    out.append((Sound([lay], "%s %s%s%s" % (
                        p.name, "4op" if b4 else "2op", " (at its note)" if way == "p" else "",
                        " %+d" % iv if iv else "")), (ik, b4, way)))
    return out


def chord_sounds(info, base):
    """A chord sample as its notes, each on a track of its own, the patch of `base`."""
    if len(info.tones) < 2:
        return []
    out = []
    lay0 = base.layers[0]
    tones = sorted(info.tones, key=lambda t: -t[1])
    for n in range(2, len(tones) + 1):
        for weighted in (True, False):
            ls = []
            for iv, w in tones[:n]:
                l = lay0.copy()
                l.iv = lay0.iv + iv
                l.att = -20 * math.log10(max(w, 0.05)) if weighted else 0.0
                ls.append(l)
            out.append(Sound(ls, "%s x%d%s" % (base.label, n, "" if weighted else " even")))
    return out


def env_db(x, rate, hop):
    n = len(x) // hop
    if n == 0:
        return np.zeros(1)
    e = np.sqrt(np.mean(x[:n * hop].reshape(n, hop) ** 2, axis=1))
    return 20 * np.log10(e + 1e-7)


def env_model(cal, n, ar, dr, sl, egt, rr, koff):
    """An operator's level (dB from its top, a frame of ENV_HOP) as the chip makes it: its
    attack as heard, then its decay to its sustain level -- held there, or (not sustained) on
    down at its release rate -- and from its key-off, its release."""
    att, slope = cal
    a = att[ar]
    ta = next((i for i in range(len(a)) if a[i] >= -0.5), len(a))
    ta = min(ta, n)
    out = np.empty(n)
    out[:ta] = a[:ta]
    t = np.arange(n - ta) * ENV_HOP
    d = -slope[dr] * t
    floor = -3.0 * sl if sl < 15 else -96.0
    if egt:
        d = np.maximum(d, floor)
    elif slope[dr] > 0:
        reach = -floor / slope[dr]
        d = np.where(t < reach, d, floor - slope[rr] * (t - reach))
    out[ta:] = d
    if koff is not None and koff < n:
        out[koff:] = out[koff] - slope[rr] * np.arange(n - koff) * ENV_HOP
    return np.maximum(out, -96.0)


def fit_envelope(cal, e, koff):
    """(attack, decay, sustain level, release, sustained) for an operator, the closest the
    chip's envelopes come to e (dB a frame of ENV_HOP; its key let go at frame koff, or not),
    as heard: frames within 40 dB of its top."""
    e = e - e.max()
    n = len(e)
    att, slope = cal
    p = int(np.argmax(e))
    # (the attacks that get near the top about when e does)
    ars = []
    for ar in range(1, 16):
        a = att[ar]
        t3 = next((i for i in range(len(a)) if a[i] >= -3), len(a))
        ars.append((abs(t3 - p), ar))
    ars = [ar for _, ar in sorted(ars)[:4]]
    best = None
    w = e > -40
    for ar in ars:
        for egt in (0, 1):
            for dr in range(0, 16):
                for sl in (range(0, 15) if egt else (15,)):
                    for rr in ((6, 8, 10, 12) if koff is not None else (10,)):
                        m = env_model(cal, n, ar, dr, sl, egt, rr, koff)
                        act = w | (m > -40)
                        err = float(np.abs(np.maximum(m, -40) - np.maximum(e, -40))[act].mean())
                        if best is None or err < best[0]:
                            best = (err, ar, dr, sl, rr, egt)
    return best[1:]


def pitch_track(x, rate, f0, hop):
    """The pitch of each frame (semitones from f0, within 15 either way) and its level (dB),
    from the harmonics' magnitudes."""
    nfft = 4096
    if len(x) < nfft:
        x = np.concatenate([x, np.zeros(nfft - len(x), np.float32)])
    win = np.hanning(nfft).astype(np.float32)
    fr = np.lib.stride_tricks.sliding_window_view(x, nfft)[::hop]
    mag = np.abs(np.fft.rfft(fr * win, axis=1))
    binhz = rate / nfft
    # McLeod's normalized square difference: the first period whose match is near the best
    # (a voice's octave errors are what harmonic sums make)
    W = 2048
    sub = fr[:, :W].astype(np.float64)
    sub = sub - sub.mean(axis=1, keepdims=True)
    F = np.fft.rfft(sub, 2 * W, axis=1)
    r = np.fft.irfft(np.abs(F) ** 2, axis=1)[:, :W]
    sq = sub ** 2
    cs = np.cumsum(sq, axis=1)
    tot = cs[:, -1:]
    mden = np.empty_like(r)
    mden[:, 0] = 2 * tot[:, 0]
    # m(t) = sum x[j]^2 for j < W - t, plus sum x[j]^2 for j >= t
    left = cs[:, ::-1]                    # left[:, t] = sum of the first W - t
    right = tot - np.concatenate([np.zeros((len(sub), 1)), cs[:, :-1]], axis=1)
    mden = left + right
    nsdf = 2 * r / np.maximum(mden, 1e-12)
    lo = max(2, int(rate / (f0 * 2 ** (15 / 12))))
    hi = min(W - 2, int(rate / (f0 * 2 ** (-15 / 12))) + 1)
    st = np.zeros(len(sub))
    for i in range(len(sub)):
        d = nsdf[i, lo:hi]
        peaks = [k for k in range(1, len(d) - 1) if d[k] > 0 and d[k] >= d[k - 1] and d[k] > d[k + 1]]
        if not peaks:
            continue
        best = max(d[k] for k in peaks)
        k = next(k for k in peaks if d[k] >= 0.9 * best)
        a, b, c = d[k - 1], d[k], d[k + 1]
        off = 0.5 * (a - c) / (a - 2 * b + c) if (a - 2 * b + c) else 0.0
        tau = lo + k + off
        st[i] = 12 * math.log2(rate / tau / f0)
    lvl = 20 * np.log10(np.sqrt(np.mean(fr ** 2, axis=1)) + 1e-7)
    return st, lvl, mag, binhz


def phases(st, lvl, min_frames):
    """The voices in a note: [(first frame, last + 1, semitones)] -- the pitches its loud frames
    gather at (3 semitones apart or more, each a sixth of them or more), each from when it is
    heard (a third of the frames about then) to when it last is. They may overlap: a voice
    coming in under another."""
    n = len(st)
    loud = lvl > lvl.max() - 30
    vals = st[loud]
    if len(vals) < min_frames:
        return [(0, n, float(np.median(st)) if n else 0.0)]
    centers = []
    hist = {}
    for v in vals:
        hist[int(round(v))] = hist.get(int(round(v)), 0) + 1
    for b, c in sorted(hist.items(), key=lambda t: -t[1]):
        near = sum(hist.get(b + d, 0) for d in (-1, 0, 1))
        if near < len(vals) / 6:
            break
        if all(abs(b - x) >= 3 for x in centers):
            centers.append(b)
        if len(centers) == 3:
            break
    if len(centers) <= 1:
        return [(0, n, float(np.median(vals)))]
    lab = np.array([min(range(len(centers)), key=lambda k: abs(v - centers[k])) for v in st])
    out = []
    half = min_frames // 2
    for k, c in enumerate(centers):
        mine = (lab == k) & loud
        share = np.convolve(mine.astype(float), np.ones(min_frames) / min_frames, "same")
        on = np.flatnonzero(share >= 0.3)
        if len(on) == 0:
            continue
        a, b = max(0, on[0] - half), min(n, on[-1] + half + 1)
        if b - a < min_frames:
            continue
        out.append((a, b, float(np.median(st[mine]))))
    out.sort()
    if not out:
        return [(0, n, float(np.median(vals)))]
    out[0] = (0,) + out[0][1:]
    # (the one heard to the end: held to the note's own end)
    last = max(range(len(out)), key=lambda k: out[k][1])
    out = [(a, n if k == last or b > n - min_frames else b, s) for k, (a, b, s) in enumerate(out)]
    return out


def additive_sounds(info, rate, cal):
    """Sines at the sample's loudest harmonics (as the operators' multiples allow), each with
    the chip's envelope closest to its own: two to a 2-op channel (both operators heard), or
    three to a 4-op one. A sample whose pitch moves (a voice) is its parts, each its own
    channels, started and let go when the part is."""
    if not info.pitched:
        return []
    tp = info.tests[0]
    p = tp["period"]
    x = render_note(info.s, p, tp["secs"], rate)
    f0 = info.hz * C2 / p
    hop = int(round(rate * ENV_HOP))
    st, lvl, mag, binhz = pitch_track(x, rate, f0, hop)
    parts_t = phases(st, lvl, int(0.3 / ENV_HOP))
    koff = None if tp["koff"] is None else int(round(tp["koff"] * TEST_ROW / ENV_HOP))
    n = len(st)
    plans = []                    # each part: its frames, its pitch, its harmonics by energy
    top = 1e-12
    for a, b, stp in parts_t:
        f = f0 * 2 ** (stp / 12)
        hs = []
        for m in MULTS:
            fm = f * m
            if fm > min(rate / 2 - 500, 14000) or fm < 20:
                continue
            bi = int(round(fm / binhz))
            w = max(1, int(fm * 0.03 / binhz))
            amp = mag[:, max(0, bi - w):bi + w + 1].max(axis=1) / 1024.0
            env = 20 * np.log10(amp + 1e-7)
            en = float(np.sum(amp[a:b] ** 2))
            hs.append((en, m, env))
            top = max(top, en)
        hs.sort(key=lambda t: -t[0])
        plans.append((a, b, stp, hs))
    out = []
    silent = bytes([0, 63, 0xFF, 0x0F, 0])

    def op(m, env, a, b, last, lvl_db):
        e = env[a:]
        ko = None
        if not last:
            ko = b - a
        elif koff is not None:
            ko = max(0, koff - a)
        ar, dr, sl, rr, egt = fit_envelope(cal, e, ko)
        tl = max(0, min(63, int(round(lvl_db / 0.75))))
        return bytes([(egt << 5) | MULT_CODE[m], tl, (ar << 4) | dr, (sl << 4) | rr, 0])

    for per_part in (2, 4):
        if per_part * len(plans) > 2 * len(TEST_TRACKS):
            continue
        layers = []
        for k, (a, b, stp, hs) in enumerate(plans):
            last = b >= n
            use = hs[:per_part]
            for c in range(0, len(use), 2):
                ins = bytearray(32)
                ins[1] = 0x01
                ops = [op(m, env, a, b, last, 10 * math.log10(top / max(en, 1e-12))) for en, m, env in use[c:c + 2]]
                if len(ops) == 1:
                    ops.append(silent)
                ins[3:8], ins[8:13] = ops[0], ops[1]
                layers.append(Layer(ins, "m", stp, 0.0, None, "sines", delay=a * ENV_HOP,
                                    hold=None if last else (b - a) * ENV_HOP))
        if layers and len(layers) <= len(TEST_TRACKS):
            out.append(Sound(layers, "sines x%d%s" % (per_part, (" in %d parts" % len(plans)) if len(plans) > 1 else "")))
    if len(plans) <= len(TEST_TRACKS):      # three to a 4-op channel, a part each
        layers = []
        for k, (a, b, stp, hs) in enumerate(plans):
            last = b >= n
            use = hs[:3]
            ops = [op(m, env, a, b, last, 10 * math.log10(top / max(en, 1e-12))) for en, m, env in use]
            while len(ops) < 3:
                ops.append(silent)
            ins = bytearray(32)
            ins[0], ins[1], ins[2] = 1, 0x01, 0x01
            ins[3:8] = ops[0]
            ins[8:13] = silent            # (op 2 would modulate op 3: silent)
            ins[13:18], ins[18:23] = ops[1], ops[2]
            layers.append(Layer(ins, "m", stp, 0.0, None, "sines", delay=a * ENV_HOP,
                                hold=None if last else (b - a) * ENV_HOP))
        out.append(Sound(layers, "sines 4op x3%s" % ((" in %d parts" % len(plans)) if len(plans) > 1 else "")))
    return out


def variants(snd):
    """Each one-step change to a sound's envelopes, its modulators' levels, its feedback, and
    (several layers) each layer's level."""
    out = []
    cur = {"o": None}

    def mk(li, fn, label):
        s = snd.copy()
        l = s.layers[li]
        if fn(l) is False:
            return
        s.label = snd.label
        out.append((s, (li, cur["o"], label)))     # (what it changed: layer, operator, field)

    for li, lay in enumerate(snd.layers):
        nops = 4 if lay.four() else 2
        car = carriers(lay.ins)
        for o in range(nops):
            cur["o"] = o
            b = opb(o)
            if (lay.ins[b + 1] & 0x3F) == 63 and o not in car:
                continue                      # (a silent modulator stays so)

            def nib(off, hi, d, b=b):
                def f(l):
                    v = l.ins[b + off]
                    x = (v >> 4) if hi else (v & 15)
                    nx = x + d
                    if not 0 <= nx <= 15:
                        return False
                    l.ins[b + off] = ((nx << 4) | (v & 15)) if hi else ((v & 0xF0) | nx)
                return f

            for d in (-1, 1):
                mk(li, nib(2, True, d), "AR")
                mk(li, nib(2, False, d), "DR")
                mk(li, nib(3, True, d), "SL")
            for d in (-2, 2):
                mk(li, nib(3, False, d), "RR")

            def eg(l, b=b):
                l.ins[b] ^= 0x20
            mk(li, eg, "EG")
            if o not in car or len(car) > 1 or len(snd.layers) > 1:
                for d in (-4, -2, 2, 4):
                    def tl(l, d=d, b=b):
                        v = l.ins[b + 1] & 0x3F
                        nv = v + d
                        if not 0 <= nv <= 63:
                            return False
                        l.ins[b + 1] = (l.ins[b + 1] & 0xC0) | nv
                    mk(li, tl, "TL")
        cur["o"] = None
        for d in (-1, 1):
            def fb(l, d=d):
                v = (l.ins[1] >> 1) & 7
                nv = v + d
                if not 0 <= nv <= 7:
                    return False
                l.ins[1] = (l.ins[1] & 0xF1) | (nv << 1)
            mk(li, fb, "FB")
        if len(snd.layers) > 1:
            for d in (-3, 3):
                def la(l, d=d):
                    if l.att + d < 0:
                        return False
                    l.att += d
                mk(li, la, "level")
        if lay.delay > 0:
            for d in (-0.15, 0.15):
                def dl(l, d=d):
                    if l.delay + d <= 0:
                        return False
                    l.delay += d
                    if l.hold is not None:
                        l.hold = max(0.05, l.hold - d)
                mk(li, dl, "start")
        if lay.hold is not None:
            for d in (-0.2, 0.2):
                def hd(l, d=d):
                    if l.hold + d <= 0.05:
                        return False
                    l.hold += d
                mk(li, hd, "hold")
    return out


def find_sounds(sg, bench, infos, opts):
    """Each sample's candidates, heard: info.ranked (closest first)."""
    rate = bench.rate
    items = sorted(infos.values(), key=lambda i: -i.presence)
    # 1. every patch, at the sample's pitch; then the closest an octave (or a drum's notes) off
    say("Hearing every patch against each of %d samples..." % len(items))
    cands = {}
    pairs = []
    for info in items:
        cands[info.num] = bank_candidates(sg, info)
        pairs += [(info, s) for s, _ in cands[info.num]]
    bench.score(pairs)
    singles = {}
    more_all = []
    for info in items:
        ranked = sorted(cands[info.num], key=lambda c: c[0].score)
        two = [c for c in ranked if not c[0].layers[0].four()][:4]
        keep = ranked[:10] + [c for c in two if c not in ranked[:10]]
        top = set(k for _, k in keep)
        more = bank_candidates(sg, info, variants=True, only=top)
        more_all += [(info, s) for s, _ in more]
        singles[info.num] = [s for s, _ in keep] + [s for s, _ in more]
    bench.score(more_all)
    # 2. chords (from the closest 4-op and 2-op patches), and sines
    tries = []
    for info in items:
        b = sorted(singles[info.num], key=lambda s: s.score)
        if opts.layers and len(info.tones) >= 2:
            bases = [s for s in b if s.layers[0].four()][:2] + [s for s in b if not s.layers[0].four()][:2]
            for base in bases:
                tries += [(info, s) for s in chord_sounds(info, base)]
        if opts.additive and info.pitched:
            adds = additive_sounds(info, rate, bench.calibrate())
            tries += [(info, s) for s in adds]
            # and the closest patch under them (a voice's breath, a scream's noise: what sines
            # can't make), as loud or 6 dB quieter
            for s in adds:
                if s.label.startswith("sines 4op") or len(s.layers) > 2:
                    continue
                for att in (0.0, 6.0):
                    base = b[0].layers[0].copy()
                    base.att = att
                    tries.append((info, Sound([base] + [l.copy() for l in s.layers],
                                              "%s%s + %s" % (b[0].label, " -6 dB" if att else "", s.label))))
    if tries:
        say("Trying %d layered sounds (chords, sines)..." % len(tries))
        bench.score(tries)
    for info in items:
        own = [s for i, s in tries if i is info]
        info.ranked = sorted(singles[info.num] + own, key=lambda s: s.score)
        info.single = min(singles[info.num], key=lambda s: s.score)
        if opts.verbose:
            say("  %2d %s:" % (info.num, info.s.name))
            seen = set()
            for s in info.ranked:
                if s.label in seen:
                    continue
                seen.add(s.label)
                say("       %6.1f%%  %s" % (s.score, s.label))
                if len(seen) >= 8:
                    break
            for s in own:
                if s.label not in seen:
                    say("       %6.1f%%  %s" % (s.score, s.label))


def contenders(info, opts):
    """The sounds worth refining before one is chosen: the closest of each kind -- with 4-op
    tracks, 2-op only, a chord, sines (if within 3 dB of the closest)."""
    kinds = {}
    for s in info.ranked:
        lab = s.label
        k = ("sines" if lab.startswith("sines") else "under" if "+ sines" in lab else
             "chord" if len(s.layers) > 1 else "one", any(l.four() for l in s.layers))
        if k not in kinds:
            kinds[k] = s
    best = info.ranked[0].score
    out = [s for k, s in kinds.items() if k[0] not in ("sines", "under") or s.score < best * 1.25]
    return out


def refine(bench, pairs, opts, what="sounds"):
    """[(info, sound)] each refined a step at a time: each round its closest change kept. After
    the first, only the fields whose changes came closer last time are tried again (all of
    them once more when none of those does); a sound none of whose changes come closer is
    done."""
    cur = list(pairs)
    focus = [None] * len(cur)             # the fields worth trying again (None: all)
    done = [False] * len(cur)
    for rnd in range(opts.refine):
        trial, owner = [], []
        for k, (info, snd) in enumerate(cur):
            if done[k]:
                continue
            for v, f in variants(snd):
                if focus[k] is None or f in focus[k]:
                    trial.append((info, v, f))
                    owner.append(k)
        if not trial:
            break
        bench.score([(i, v) for i, v, _ in trial])
        better = 0
        for k, (info, snd) in enumerate(cur):
            if done[k]:
                continue
            mine = [(t[1], t[2]) for t, o in zip(trial, owner) if o == k]
            if not mine:
                done[k] = True
                continue
            v, f = min(mine, key=lambda t: t[0].score)
            if v.score < snd.score - 0.1:
                cur[k] = (info, v)
                better += 1
                focus[k] = set(ff for vv, ff in mine if vv.score < snd.score - 0.1)
            elif focus[k] is not None:
                focus[k] = None               # (a round of everything before giving up)
            else:
                done[k] = True
        say("  refining, round %d: %d of %d %s closer (%d tried)" % (rnd + 1, better, len(cur), what,
                                                                      len(trial)))
        if all(done):
            break
    return cur


# ---- Tracks --------------------------------------------------------------------------------------------
def needs(mod, infos, pick):
    """Each channel's track slots (True: 4-op) for the sounds picked."""
    slots = []
    for c in range(mod.nch):
        used = [pick[i.num] for i in infos.values() if c in i.chans]
        n = max([len(s.layers) for s in used] + [1])
        slots.append([any(j < len(s.layers) and s.layers[j].four() for s in used) for j in range(n)])
    return slots


def excess(slots, spare=1):
    n4 = sum(sum(s) for s in slots)
    n2 = sum(len(s) for s in slots) - n4
    return max(0, n4 - 6) * 4 + max(0, 2 * n4 + n2 + spare - 18)


def choose(mod, infos, opts):
    """A sound for each sample, the song's tracks enough for them all: each its closest (a
    layer more costing --layer-cost), then -- where they don't fit -- whichever changes cost
    least (how far it is heard to be, by how much the sample is heard) for the tracks given."""
    def eff(s):
        return s.score + opts.layer_cost * (len(s.layers) - 1)

    def load(p):
        """How far over the tracks the sounds are -- and, to get there a sample at a time when
        two share a channel's track, how many 4-op layers and layers they have."""
        ex = excess(needs(mod, infos, p))
        if not ex:
            return 0
        return ex * 1000 + sum(3 * sum(l.four() for l in s.layers) + len(s.layers) for s in p.values())

    for info in infos.values():         # (--sines: these samples' sines, closest or not)
        if info.num in opts.sines:
            own = [s for s in info.ranked if "sines" in s.label]
            if own:
                info.ranked = own
            else:
                say("  (sample %d has no sines: it isn't pitched)" % info.num)
    pick = {i.num: min(i.ranked, key=eff) for i in infos.values()}
    ld = load(pick)
    while ld > 0:
        best = None
        for info in infos.values():
            cur = pick[info.num]
            for alt in info.ranked:
                if alt is cur:
                    continue
                trial = dict(pick)
                trial[info.num] = alt
                nl = load(trial)
                if nl >= ld:
                    continue
                cost = info.presence * max(0.0, eff(alt) - eff(cur)) / (ld - nl)
                if best is None or cost < best[0]:
                    best = (cost, info, alt, nl)
        if best is None:
            break
        _, info, alt, ld = best
        pick[info.num] = alt
    # then back to closer sounds wherever the tracks still have room (the sample heard most first)
    changed = True
    while changed and ld == 0:
        changed = False
        for info in sorted(infos.values(), key=lambda i: -i.presence):
            cur = pick[info.num]
            for alt in sorted(info.ranked, key=eff):
                if eff(alt) >= eff(cur):
                    break
                trial = dict(pick)
                trial[info.num] = alt
                if load(trial) == 0:
                    pick[info.num] = alt
                    changed = True
                    break
    for info in infos.values():
        best = min(info.ranked, key=eff)
        if pick[info.num] is not best:
            say("  (%s: %s, for the tracks)" % (info.s.name, pick[info.num].label))
    for info in infos.values():
        info.sound = pick[info.num].copy()


def allocate(mod, infos, opts):
    """Each module channel's tracks: [[track for each layer slot]], the 4-op pairs' bits, the
    tracks left over."""
    slots = needs(mod, infos, {i.num: i.sound for i in infos.values()})
    while excess(slots, 0) > 0:          # (none of the sounds fitted: the least of them goes)
        n4 = sum(sum(s) for s in slots)
        c = max(range(mod.nch), key=lambda c: (len(slots[c]), sum(slots[c])))
        if n4 > 6:
            j = max(j for j, f in enumerate(slots[c]) if f) if any(slots[c]) else None
            c4 = [c2 for c2 in range(mod.nch) if any(slots[c2])]
            c = max(c4, key=lambda c2: sum(slots[c2]))
            j = max(j for j, f in enumerate(slots[c]) if f)
            slots[c][j] = False
            say("  (a 2-op track for channel %d's layer %d)" % (c + 1, j + 1))
        else:
            slots[c].pop()
            say("  (channel %d: %d tracks)" % (c + 1, len(slots[c])))
    t4 = iter(OP4_TRACKS)
    used4 = []
    tracks = [[None] * len(s) for s in slots]
    for c in range(mod.nch):
        for j, f in enumerate(slots[c]):
            if f:
                t = next(t4)
                tracks[c][j] = t
                used4.append(t)
    free2 = [t for t in range(18) if t not in used4 and t not in [PARTNER[x] for x in used4]]
    for c in range(mod.nch):
        for j, f in enumerate(slots[c]):
            if not f:
                tracks[c][j] = free2.pop(0)
    bits = 0
    for t in used4:
        bits |= OP4_BITS[t]
    return tracks, bits, free2


# ---- The song's cells ---------------------------------------------------------------------------------------
def vol_steps(v):
    if v <= 0:
        return 0
    return max(0, min(63, 63 + int(round(20 * math.log10(v / 64.0) / 0.75))))


class Song:
    pass


def make_instruments(infos, opts, pan_used, vmax):
    """The song's instruments: {(sample, layer, pan): number}, the list. Each sound as loud
    against the others as its sample is (as near as its patch can be), and all of them as loud
    as the song's loudest note lets them be (--gain more): what an instrument can't do of that
    with its carriers, its notes' volumes do (info.voff, in steps)."""
    insts = Insts()
    index = {}
    gains = [i.sound.gain for i in infos.values() if i.sound]
    top = max(gains) if gains else 0.0
    if gains:
        top = min(top, sorted(gains)[len(gains) // 2] + 9)
    att = {n: max(0.0, top - i.sound.gain) + i.extra_att for n, i in infos.items() if i.sound}
    loud = max([20 * math.log10(max(vmax.get(n, 64), 1) / 64.0) - a for n, a in att.items()] + [-60])
    boost = -loud + opts.gain
    for num in sorted(infos):
        info = infos[num]
        info.voff = 0
        if not info.sound:
            continue
        a = att[num] - boost
        info.voff = max(0, int(round(-a / 0.75)))
        a = max(0.0, a)
        for li, lay in enumerate(info.sound.layers):
            for pan in sorted(pan_used.get(num, {0})):
                ins = bytearray(layer_bytes(lay, info, a))
                ins[25] = (0, 0x10, 0x20)[pan]
                nm = "" if opts.names == "patch" else re.sub(r"^st-\d+:", "", info.s.name).strip()
                nm = nm or lay.name or "sample %d" % num
                suffix = ("" if len(info.sound.layers) == 1 else ".%d" % (li + 1)) + ("", "L", "R")[pan]
                nm = nm[:16 - len(suffix)] + suffix
                src = lay.src if lay.src and not opts.no_sources else None
                index[(num, li, pan)] = insts.add(ins, nm, src)
    return insts, index


def make_cells(mod, rows, infos, tracks, index, spare):
    """{(row, track): [note, instrument, volume, effect, parameter]} for the rows played: each
    module channel's cell, on each of its tracks (the instrument there its layer's)."""
    cells = {}
    nch = mod.nch
    stats = {"slides": 0, "volume slides left to the next row": 0, "key-offs": 0}

    def vsx(info, v):
        return 0 if v <= 0 else min(63, vol_steps(v) + info.voff)

    def cell(r, t):
        c = cells.get((r, t))
        if c is None:
            c = cells[(r, t)] = [0, 0, 0, 0, 0]
        return c

    st = [dict(inst=None, C=None, vol=None, nl=0, playing=False, alive=False, koff=False, pan=0,
               lit=0, n=0, events=[]) for _ in range(nch)]
    speed0, bpm0 = rows[0].speed, rows[0].bpm
    cur_speed, cur_rate = speed0, rate_for_bpm(bpm0)[0]
    starts = [0.0]
    for row in rows:
        starts.append(starts[-1] + row.speed * row.tick)
    for ri, row in enumerate(rows):
        sp = row.speed
        ctl = []
        if sp != cur_speed:
            ctl.append((ord("F"), sp))
            cur_speed = sp
        rt = rate_for_bpm(row.bpm)[0]
        if rt != cur_rate:
            ctl.append((ord("F"), rt))
            cur_rate = rt
        for c, rec in enumerate(row.ch):
            s = st[c]
            trig = min(rec.trig) if rec.trig else None
            per = rec.cell[0]
            mfx, mpar = rec.fx, rec.par
            ex = mpar >> 4 if mfx == 0xE else None
            out = {}
            new = infos.get(rec.smp) if trig is not None else None
            if trig is not None and new and new.sound:
                n = new.pnote(rec.base[trig])
                out["note"] = n
                out["vol"] = vsx(new, rec.vol[trig])
                s.update(inst=rec.smp, nl=len(new.sound.layers), playing=True, C=(n - 1) * 32,
                         vol=out["vol"], pan=rec.pan, alive=True, koff=False, n=n)
                if trig:
                    out["fx"] = (ord("E"), 0xD0 | trig)
                # a sound's layers that start later, or are let go sooner, than its note
                t0 = starts[ri] + trig * row.tick
                s["events"] = []
                for j, lay in enumerate(new.sound.layers):
                    if lay.delay > 0:
                        s["events"].append((t0 + lay.delay, j, "on"))
                    if lay.hold is not None:
                        s["events"].append((t0 + lay.delay + lay.hold, j, "off"))
            elif trig is not None:
                if s["playing"]:                     # (an empty sample: the channel let go)
                    out["note"] = 0x7F
                s.update(playing=False, alive=False, koff=False, events=[])
            info = infos.get(s["inst"]) if s["inst"] else None
            if s["playing"] and info and "fx" not in out:
                k0 = trig or 0
                ticks = sp - 1

                def q(p):
                    return 32 * (info.S + 12 * math.log2(C2 / p) - info.tune + info.shift - 1)

                # the pitch
                if mfx == 0 and mpar:
                    out["fx"] = (ord("0"), mpar)
                elif mfx in (4, 6) and rec.vib[1] and rec.base[0]:
                    P = rec.base[0]
                    dev = 32 * 12 * math.log2(P / max(1.0, P - 1.99 * rec.vib[1]))
                    y = max(1, min(15, int(round(dev / 3.97))))
                    out["fx"] = (ord("4"), (min(15, rec.vib[0]) << 4) | y)
                elif s["C"] is not None and rec.base[-1]:
                    dlt = q(rec.base[-1]) - s["C"]
                    sliding = mfx in (1, 2, 3, 5) or ex in (1, 2)
                    if mfx in (3, 5) and rec.target and ticks > 0 and (abs(dlt) >= 1 or per):
                        tn = info.pnote(rec.target)
                        tq = (tn - 1) * 32
                        if per and trig is None:
                            out["note_porta"] = tn
                        if abs(dlt) >= 1:
                            r = max(1, min(255, int(round(abs(dlt) / ticks))))
                            out["fx"] = (ord("3"), r)
                            step = r * ticks
                            s["C"] = tq if abs(tq - s["C"]) <= step else s["C"] + (step if tq > s["C"] else -step)
                            stats["slides"] += 1
                    elif sliding and abs(dlt) >= 1 or abs(dlt) >= 6:
                        if ticks > 0 and mfx in (1, 2) and abs(dlt) >= ticks / 2:
                            r = max(1, min(255, int(round(abs(dlt) / ticks))))
                            out["fx"] = (ord("1") if dlt > 0 else ord("2"), r)
                            s["C"] += (r if dlt > 0 else -r) * ticks
                            stats["slides"] += 1
                        else:
                            d = max(-15, min(15, int(round(dlt))))
                            if d:
                                out["fx"] = (ord("E"), (0x10 if d > 0 else 0x20) | abs(d))
                                s["C"] += d
                # the volume: at the row's start, the column; through it, Axy (or ECx)
                v0 = vsx(info, rec.vol[k0])
                if v0 != s["vol"] and "vol" not in out:
                    out["vol"] = v0
                    s["vol"] = v0
                ve = vsx(info, rec.vol[-1])
                if ve != s["vol"]:
                    if ex == 0xC and rec.vol[-1] == 0 and "fx" not in out:
                        out["fx"] = (ord("E"), mpar)
                        s["vol"] = 0
                    elif "fx" in out or ticks - k0 <= 0:
                        stats["volume slides left to the next row"] += 1
                    else:
                        d = ve - s["vol"]
                        pt = max(1, min(15, int(round(abs(d) / (ticks - k0)))))
                        out["fx"] = (ord("A"), (pt << 4) if d > 0 else pt)
                        s["vol"] = max(0, min(63, s["vol"] + (pt if d > 0 else -pt) * (ticks - k0)))
                # the sample's end: its key let go (then, or at the next row's start)
                if s["koff"] and "note" not in out:
                    out["note"] = 0x7F
                    s.update(koff=False, alive=False)
                    stats["key-offs"] += 1
                elif s["alive"]:
                    end = next((k for k in range(k0, sp) if not rec.alive[k]), None)
                    if end is not None and "note" not in out:
                        if end == 0:
                            out["note"] = 0x7F
                            s["alive"] = False
                            stats["key-offs"] += 1
                        elif "fx" not in out and "vol" not in out:
                            out["note"] = 0x7F
                            out["fx"] = (ord("E"), 0xD0 | end)
                            s["alive"] = False
                            stats["key-offs"] += 1
                        else:
                            s["koff"] = True
                            s["alive"] = False
            trks = tracks[c]
            if out:
                # to the channel's tracks
                nl = s["nl"] if s["inst"] else len(trks)
                lit = s["lit"]
                lays = info.sound.layers if info and info.sound else []
                for j, t in enumerate(trks):
                    if j >= nl:
                        if j < lit and "note" in out:   # (a sound of more tracks before: let go)
                            c2 = cell(ri, t)
                            c2[0], c2[1] = 0x7F, 0
                        continue
                    c2 = cell(ri, t)
                    if "note" in out:
                        if trig is not None and out["note"] != 0x7F and j < len(lays) and lays[j].delay > 0:
                            if j < lit:             # (a layer that starts later: let go now)
                                c2[0], c2[1] = 0x7F, 0
                        else:
                            c2[0] = out["note"]
                            c2[1] = index.get((s["inst"], j, s["pan"]), 0) if out["note"] != 0x7F else 0
                    elif "note_porta" in out:
                        c2[0], c2[1] = out["note_porta"], 0
                    if "vol" in out:
                        c2[2] = out["vol"] + 1
                    if "fx" in out:
                        c2[3], c2[4] = out["fx"]
                if "note" in out:
                    s["lit"] = nl if out["note"] != 0x7F else 0
            # the layers that start, or are let go, in this row
            if s["events"]:
                end = starts[ri + 1]
                due = [e for e in s["events"] if e[0] < end]
                s["events"] = [e for e in s["events"] if e[0] >= end]
                for tm, j, kind in due:
                    if j >= len(trks) or not s["playing"] or not s["alive"]:
                        continue
                    k = max(0, min(row.speed - 1, int((tm - starts[ri]) / row.tick + 0.5)))
                    c2 = cell(ri, trks[j])
                    if kind == "on":
                        c2[0] = s["n"]
                        c2[1] = index.get((s["inst"], j, s["pan"]), 0)
                        c2[2] = (s["vol"] or 0) + 1
                    elif c2[0] == 0:
                        c2[0], c2[1] = 0x7F, 0
                    else:
                        continue
                    if k and not c2[3]:
                        c2[3], c2[4] = ord("E"), 0xD0 | k
                    s["lit"] = max(s["lit"], j + 1)
        # speed and tempo, on a track with its effect free (one of no channel's first)
        for fx, par in ctl:
            for t in spare + [t for tr in tracks for t in tr]:
                c2 = cells.get((ri, t))
                if c2 is None or not c2[3]:
                    c2 = cell(ri, t)
                    c2[3], c2[4] = fx, par
                    break
    return cells, stats, (speed0, rate_for_bpm(bpm0))


# ---- The song file ------------------------------------------------------------------------------------------
def segments(rows, starts, loop):
    """(first row, last row + 1) for each of the song's orders: the module's, split where the
    loop comes back to and where an order runs past 128 rows."""
    st = sorted(set(starts + ([loop] if loop is not None else [])))
    out = []
    for i, a in enumerate(st):
        b = st[i + 1] if i + 1 < len(st) else len(rows)
        while b - a > 128:
            out.append((a, a + 64))
            a += 64
        if b > a:
            out.append((a, b))
    lo = None
    if loop is not None:
        lo = next(i for i, (a, b) in enumerate(out) if a == loop)
    return out, lo


def build_song(sg, cells, nrows, bits, insts, ranges, loop, lead=False):
    shim = Shim([(0, sg.speed0, sg.steps0)], sg.deep)
    ld = m2s.leadin(shim, insts) if lead else None
    data = m2s.song_bytes(shim, cells, nrows, bits, insts, ranges, sg.title, sg.author,
                          None if lead else loop, ld)
    if lead:
        insts.items.pop()
    return data, (ld[0] if ld else 0), shim


def dos_name(path):
    stem = re.sub(r"[^A-Za-z0-9]", "", os.path.splitext(os.path.basename(path))[0]).upper()
    return (stem[:8] or "SONG") + ".SNG"


def assemble(sg, mod, rows, infos, opts):
    pan_used, vmax = {}, {}
    for row in rows:
        for rec in row.ch:
            if rec.smp:
                if rec.trig:
                    pan_used.setdefault(rec.smp, set()).add(rec.pan)
                vmax[rec.smp] = max(vmax.get(rec.smp, 0), max(rec.vol))
    tracks, bits, spare = allocate(mod, infos, opts)
    insts, index = make_instruments(infos, opts, pan_used, vmax)
    cells, stats, (sp0, (rt0, st0)) = make_cells(mod, rows, infos, tracks, index, spare)
    sg.speed0, sg.steps0 = sp0, st0
    return cells, bits, insts, tracks, stats


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0],
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("mod")
    ap.add_argument("out", nargs="?", help="the .SNG to write (default: the module's name, 8.3, here)")
    ap.add_argument("--title", help="the song's title (default: the module's)")
    ap.add_argument("--author", default="", help="its author")
    ap.add_argument("--refine", type=int, default=12, help="rounds of refining each sound (default 12)")
    ap.add_argument("--no-layers", dest="layers", action="store_false", help="no chord sounds")
    ap.add_argument("--no-additive", dest="additive", action="store_false", help="no sines")
    ap.add_argument("--layer-cost", type=float, default=1.5,
                    help="how much closer (points: percent of the sample's loudness) each extra "
                         "track must make a sound (default 1.5)")
    ap.add_argument("--sines", default="",
                    help="samples (numbers, 1,5,...) played as sines even if a patch is heard closer")
    ap.add_argument("--gain", type=float, default=0.0,
                    help="dB louder than the loudest note at full volume (default 0)")
    ap.add_argument("--amiga-pan", action="store_true",
                    help="the Amiga's channels hard left and right (L R R L); default both sides")
    ap.add_argument("--no-loop", action="store_true", help="the song ends, not back to its loop")
    ap.add_argument("--no-sources", action="store_true", help="no bank sources in the file")
    ap.add_argument("--names", choices=("sample", "patch"), default="sample",
                    help="name the instruments after the samples (default) or their patches (a "
                         "module whose sample names are its greetings)")
    ap.add_argument("--analyse", action="store_true", help="only say what each sample is, and stop")
    ap.add_argument("--verbose", action="store_true", help="each sample's closest sounds")
    ap.add_argument("--wav", help="also write the song's render here")
    ap.add_argument("--mod-wav", help="and the module's own sound here")
    ap.add_argument("--emulator", help="the test program (default: the newest one built)")
    ap.add_argument("--jobs", type=int, default=max(1, min(16, (os.cpu_count() or 2) // 2)),
                    help="renders at once")
    opts = ap.parse_args()
    opts.sines = set(int(x) for x in opts.sines.split(",") if x.strip())
    t0 = time.time()
    if np is None:
        sys.exit("numpy is needed (pip install numpy)")

    mod = read_mod(opts.mod)
    sg = Song()
    sg.bank4, f4 = m2s.read_wopl(m2s.BANK4)
    sg.bank2, _ = m2s.read_wopl(m2s.BANK2)
    sg.deep = ((f4 & 1) << 7) | ((f4 & 2) << 5)
    sg.title = opts.title if opts.title is not None else (mod.title or os.path.splitext(os.path.basename(opts.mod))[0])
    sg.author = opts.author
    rows, starts, loop, mstats = simulate(mod, opts)
    if not rows:
        sys.exit("Nothing to play in %s" % opts.mod)
    notes = note_events(mod, rows)
    secs = sum(r.speed * r.tick for r in rows)
    say("%s: \"%s\", %d channels, %d orders played (%d rows, %.0f s)%s" % (
        os.path.basename(opts.mod), mod.title, mod.nch, len(starts), len(rows), secs,
        "" if loop is None else ", looping back to row %d" % loop))
    for k, v in mstats.items():
        if v:
            say("  (%d %s effects: SONGKIT has none like them, left out)" % (v, {
                "offset": "sample offset (9xx)", "retrig": "retrigger (E9x)",
                "tremolo": "tremolo (7xy)"}[k]))
    infos = sample_infos(mod, rows, notes, 48000)
    for num in sorted(infos):
        i = infos[num]
        tones = " + ".join("%+.0f" % t for t, _ in i.tones[1:])
        say("  %2d %-22s %4d notes  %s%s" % (
            num, i.s.name, i.count,
            ("pitched, %s %+3.0f cents at C-2" % (sng_name(int(round(i.S))), 100 * i.tune)) if i.pitched else "a drum",
            (", a chord: " + tones) if tones and i.pitched else ""))
    if opts.analyse:
        return
    exe = m2s.find_emulator(opts.emulator)
    if not exe:
        sys.exit("The emulator's test program isn't built (build_all builds it)")
    work = tempfile.mkdtemp(prefix="mod2sng_")
    try:
        rnd = m2s.Renderer(exe, work, opts.jobs)
        bench = Bench(rnd, sg.deep)
        find_sounds(sg, bench, infos, opts)
        pairs = [(i, s) for i in infos.values() for s in contenders(i, opts)]
        say("Refining the closest %d sounds of each kind..." % len(pairs))
        for info, s in refine(bench, pairs, opts):
            info.ranked.append(s)
        for i in infos.values():
            i.ranked.sort(key=lambda s: s.score)
        choose(mod, infos, opts)
        for i in infos.values():
            i.extra_att = 0.0
        say("Sounds (how far from the sample: the difference, as a percent of its loudness;"
            " the closest bank patch alone, as it was):")
        for num in sorted(infos):
            i = infos[num]
            s = i.sound
            say("  %2d %-22s %-34s %5.1f%%  (%s %.1f%%)" % (
                num, i.s.name, s.label[:34], s.score, i.single.label[:28], i.single.score))
        cells, bits, insts, tracks, stats = assemble(sg, mod, rows, infos, opts)
        ranges, lo = segments(rows, starts, loop)
        if opts.no_loop:
            lo = None
        data, _, _ = build_song(sg, cells, len(rows), bits, insts, ranges, lo)
        out = opts.out or dos_name(opts.mod)
        base = os.path.basename(out)
        if not re.fullmatch(r"[A-Za-z0-9_\-]{1,8}(\.[A-Za-z0-9_\-]{1,3})?", base):
            say("  (%s isn't an 8.3 name: the Pugputer's disk wants one)" % base)
        with open(out, "wb") as f:
            f.write(data)
        say("Wrote %s: %d bytes, %d instruments, %d orders, %d 4-op pairs; the channels' tracks %s"
            " (%d renders, %.0f s)" % (
                out, len(data), len(insts.items), len(ranges), bin(bits).count("1"),
                "  ".join(",".join(str(t) for t in tr) for tr in tracks), rnd.count, time.time() - t0))
        say("  " + ", ".join("%d %s" % (v, k) for k, v in stats.items()))
        if opts.wav or opts.mod_wav:
            ref = render_mod(mod, rows, bench.rate, opts.amiga_pan)
            if opts.mod_wav:
                m2s.write_wav(opts.mod_wav, bench.rate, ref * 0.5 / max(1e-6, np.abs(ref).max()))
            dataL, lr, shim = build_song(sg, cells, len(rows), bits, insts, ranges, None, lead=True)
            y = m2s.song_audio(shim, rnd.render(dataL, secs + 2), lr, secs)
            if opts.wav:
                m2s.write_wav(opts.wav, shim.rate, y)
            A = features(ref.mean(axis=1), bench.rate)
            B = features(y.mean(axis=1), shim.rate)
            d, g = loud_gain(A, B)
            say("The song against the module: %.1f%% (peak %.1f dBFS)" % (
                d, 20 * math.log10(max(1e-9, float(np.abs(y).max())))))
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    main()
