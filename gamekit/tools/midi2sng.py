"""midi2sng: a Standard MIDI File made a SONGKIT song (.SNG), for the OPL3 with The Fat Man's
General MIDI patches -- his 4-op ones (banks/FATMAN4.WOP) where they matter most, his 2-op ones
(banks/FATMAN2.WOP) where the song needs more voices than 4-op channels leave.

    python midi2sng.py song.mid [OUT.SNG] [options]        (--help lists them)

It is slow on purpose: it listens. Each way of arranging the song is played with SONGPLAY on
the emulated Pugputer (the test suite's songkit_song_to_wav, the real player and Nuked OPL3)
and heard against the song as it would be with unlimited channels, every note on its 4-op
patch. The arrangement that comes closest is written.

How a song is arranged:

1. The MIDI's notes, with its tempo map, sustain pedal, volume and expression, pan, pitch bend
   (and its range), program changes; channel 10 (and GM2/XG drum banks) the percussion bank's.
2. A grid: the rows a beat that fit the most notes on rows (EDx places the rest, to a tick of
   a few ms); ticks a row and a second from the OPL3 timer's steps, again where the tempo
   changes (Fxx). Patterns are whole bars, about 64 rows; patterns the same are kept once.
3. Each instrument the song uses is played on its own, 2-op and 4-op, at the pitches and
   lengths the song plays it: how much its 4-op patch differs from its 2-op one (dB, the two
   at the same loudness) is what 4-op is worth for it, and their loudness difference evens
   out the 2-op notes' volume.
4. For each number of 4-op pairs (0-6: 18 tracks down to 12), the notes the tracks can't hold
   are cut where it costs least (a min-cost flow: onsets, loud notes, the top and bottom
   voices and drums kept first; long notes shortened before short ones are dropped); then of
   the notes kept, those worth most in 4-op get the 4-op tracks (another flow); then tracks.
5. Each of those played and heard (a log-mel spectrogram's distance, dB); the best one's
   instrument weights then searched further (each top instrument's 4-op worth up and down).

Needs numpy, and the emulator's test program built (build_all builds it) -- or --no-render,
which arranges from the banks alone, quickly and less well.
"""
import argparse
import bisect
import heapq
import math
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor

try:
    import numpy as np
except ImportError:  # (only --no-render works without it)
    np = None

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, "..", ".."))
BANK4 = os.path.join(REPO, "gamekit", "banks", "FATMAN4.WOP")
BANK2 = os.path.join(REPO, "gamekit", "banks", "FATMAN2.WOP")

STEP = 320e-6                      # the OPL3's Timer 2 step: a tick is a whole number of them
OP4_TRACKS = [0, 9, 1, 10, 2, 11]  # the 4-op tracks, in the order the pairs are turned on
OP4_BITS = [0x01, 0x08, 0x02, 0x10, 0x04, 0x20]
PARTNER = {0: 3, 1: 4, 2: 5, 9: 12, 10: 13, 11: 14}
MARKER_TRACK = 17                  # (never in a 4-op pair) the renders' marker note
MAX_S = 16                         # ticks a row at most: EDx reaches every one
INF = float("inf")


def player_steps(rate):
    """Timer 2 steps a tick for Fxx's (or the header's) ticks a second, as SKRATE does it."""
    q, r = divmod(3125, rate)
    return q + (1 if 2 * r >= rate else 0)


MAX_RATE = 127                     # ticks of 8 ms or more: fine enough to place the notes, and
                                   # time for the player on the machine with 18 tracks busy (the
                                   # player takes 32-255; before its SKRATE fix, 128 up played
                                   # far too slowly)
RATE_FOR = {}                      # steps a tick -> the rate byte that gives it
for _r in range(32, MAX_RATE + 1):
    _n = player_steps(_r)
    if _n not in RATE_FOR or abs(3125 / _r - _n) < abs(3125 / RATE_FOR[_n] - _n):
        RATE_FOR[_n] = _r


def say(*a):
    print(*a, flush=True)


# ---- The Fat Man's banks ------------------------------------------------------------------------
class Patch:
    def __init__(self, name, ins, four, kon, koff, src):
        self.name, self.ins, self.four, self.src = name, ins, four, src
        self.kon = kon / 1000 if kon and kon < 40000 else INF   # sounds this long, key held
        self.koff = (koff or 300) / 1000                          # and this long, let go


def wopl_patch(r, perc, prog, fname):
    """A WOPL instrument as SONGKIT's 32 bytes, as its bank page makes it (BKCONV)."""
    ins = bytearray(32)
    flags = r[39]
    ins[1] = r[40] & 0x0F
    ins[3:8] = r[47:52]            # modulator 1, carrier 1 (WOPL lists the carrier first)
    ins[8:13] = r[42:47]
    four = bool(flags & 1) and not flags & 2
    if four:
        ins[0] = 1
        ins[2] = r[41] & 1
        ins[13:18] = r[57:62]
        ins[18:23] = r[52:57]
    koff = struct.unpack(">h", r[32:34])[0]
    key = (r[38] or prog) if perc else (r[38] if flags & 0x40 else None)
    if key is not None:
        ins[23] = max(1, min(96, (key & 0x7F) + koff - 11))
        ins[0] |= 2
    else:
        ins[23] = max(-48, min(48, koff)) & 0xFF
    name = r[:32].split(b"\0")[0].decode("latin-1").strip() or "Program %d" % prog
    kon, koffms = struct.unpack(">HH", r[62:66]) if len(r) >= 66 else (None, None)
    src = fname.encode()[:12].ljust(12, b"\0") + bytes([0x80 if perc else 0, prog, (flags >> 1) & 1, 0])
    return Patch(name, bytes(ins), four, kon, koffms, src)


def read_wopl(path):
    """{("m", program) or ("p", key): Patch}: the first melodic and percussion banks."""
    d = open(path, "rb").read()
    if d[:11] != b"WOPL3-BANK\0":
        sys.exit("%s: not a WOPL bank" % path)
    ver = struct.unpack("<H", d[11:13])[0]
    mb, pb = struct.unpack(">HH", d[13:17])
    size = 66 if ver >= 3 else 62
    base = 19 + (34 * (mb + pb) if ver >= 2 else 0)
    fname = os.path.basename(path).upper()
    out = {}
    for k, perc in ((0, False), (mb, True)):
        if (perc and not pb) or (not perc and not mb):
            continue
        for p in range(128):
            at = base + (k * 128 + p) * size
            r = d[at:at + size]
            if len(r) == size and not r[39] & 4:
                out[("p" if perc else "m", p)] = wopl_patch(r, perc, p, fname)
    return out, d[17]


# ---- The MIDI file -----------------------------------------------------------------------------
OFF, ON, CC, PROG, BEND, TEMPO, TSIG = range(7)


class Midi:
    pass


def read_midi(path):
    d = open(path, "rb").read()
    if d[:4] == b"RIFF" and d[8:12] == b"RMID":          # (a MIDI in a RIFF)
        i = 12
        while i + 8 <= len(d) and d[i:i + 4] != b"data":
            i += 8 + struct.unpack("<I", d[i + 4:i + 8])[0]
        d = d[i + 8:]
    if d[:4] != b"MThd":
        sys.exit("%s: not a MIDI file" % path)
    hlen = struct.unpack(">I", d[4:8])[0]
    fmt, ntrk, div = struct.unpack(">HHH", d[8:14])
    m = Midi()
    m.title = m.author = ""
    m.smpte = bool(div & 0x8000)
    if m.smpte:                                            # frames a second x ticks a frame
        fps = 256 - (div >> 8)
        m.ppq = (29.97 if fps == 29 else fps) * (div & 0xFF) / 2  # (as if 120 bpm)
    else:
        m.ppq = div
    ev = []
    pos = 8 + hlen
    for ti in range(ntrk):
        while pos + 8 <= len(d) and d[pos:pos + 4] != b"MTrk":
            pos += 8 + struct.unpack(">I", d[pos + 4:pos + 8])[0]
        if pos + 8 > len(d):
            break
        ln = struct.unpack(">I", d[pos + 4:pos + 8])[0]
        t = d[pos + 8:pos + 8 + ln]
        pos += 8 + ln
        i, tick, run, seq = 0, 0, 0, 0
        try:
            while i < len(t):
                v = 0
                while True:
                    b = t[i]
                    i += 1
                    v = v << 7 | (b & 0x7F)
                    if not b & 0x80:
                        break
                tick += v
                if t[i] & 0x80:
                    st = t[i]
                    i += 1
                    if st < 0xF0:
                        run = st
                else:
                    st = run
                seq += 1
                if st == 0xFF:
                    typ = t[i]
                    i += 1
                    n = 0
                    while True:
                        b = t[i]
                        i += 1
                        n = n << 7 | (b & 0x7F)
                        if not b & 0x80:
                            break
                    body = t[i:i + n]
                    i += n
                    if typ == 0x2F:
                        break
                    if typ == 0x51 and n == 3:
                        ev.append((tick, 0, ti, seq, TEMPO, 0, int.from_bytes(body, "big"), 0))
                    elif typ == 0x58 and n >= 2:
                        ev.append((tick, 0, ti, seq, TSIG, 0, body[0], body[1]))
                    elif typ == 0x03 and not m.title and ti == 0:
                        m.title = body.decode("latin-1").strip()
                    elif typ == 0x02 and not m.author:
                        m.author = body.decode("latin-1").strip()
                elif st in (0xF0, 0xF7):
                    n = 0
                    while True:
                        b = t[i]
                        i += 1
                        n = n << 7 | (b & 0x7F)
                        if not b & 0x80:
                            break
                    i += n
                elif st >= 0xF0:                           # (system messages: none in files)
                    continue
                else:
                    k, ch = st & 0xF0, st & 0x0F
                    if k in (0xC0, 0xD0):
                        a = t[i]
                        i += 1
                        if k == 0xC0:
                            ev.append((tick, 1, ti, seq, PROG, ch, a, 0))
                        continue
                    a, b = t[i], t[i + 1]
                    i += 2
                    if k == 0x90 and b:
                        ev.append((tick, 1, ti, seq, ON, ch, a, b))
                    elif k in (0x80, 0x90):
                        ev.append((tick, 0, ti, seq, OFF, ch, a, 0))
                    elif k == 0xB0:
                        ev.append((tick, 1, ti, seq, CC, ch, a, b))
                    elif k == 0xE0:
                        ev.append((tick, 1, ti, seq, BEND, ch, a | b << 7, 0))
        except IndexError:
            say("  (track %d ends early)" % ti)
    ev.sort()
    m.events = ev
    m.fmt = fmt
    return m


class TempoMap:
    def __init__(self, m):
        self.ppq = m.ppq
        tempos = [] if m.smpte else [(e[0], e[6]) for e in m.events if e[4] == TEMPO and e[6] > 0]
        if not tempos or tempos[0][0] > 0:
            tempos.insert(0, (0, 500000))
        ticks, usecs = [], []
        for tk, us in tempos:
            if ticks and ticks[-1] == tk:
                usecs[-1] = us
            else:
                ticks.append(tk)
                usecs.append(us)
        self.ticks, self.usecs = ticks, usecs
        self.secs = [0.0]
        for i in range(1, len(ticks)):
            self.secs.append(self.secs[-1] + (ticks[i] - ticks[i - 1]) * usecs[i - 1] / 1e6 / self.ppq)

    def sec(self, tick):
        i = bisect.bisect_right(self.ticks, tick) - 1
        return self.secs[i] + (tick - self.ticks[i]) * self.usecs[i] / 1e6 / self.ppq

    def tick(self, sec):
        i = bisect.bisect_right(self.secs, sec) - 1
        return self.ticks[i] + (sec - self.secs[i]) * 1e6 * self.ppq / self.usecs[i]

    def spb(self, tick):
        return self.usecs[bisect.bisect_right(self.ticks, tick) - 1] / 1e6


class Note:
    __slots__ = ("ch", "key", "vel", "on", "off", "prog", "drum", "pan")


class Timeline:
    """A channel's controller, as it changes: its value at a tick."""

    def __init__(self, v0):
        self.t, self.v = [0], [v0]

    def set(self, tick, v):
        if self.t[-1] == tick:
            self.v[-1] = v
        elif self.v[-1] != v:
            self.t.append(tick)
            self.v.append(v)

    def at(self, tick):
        return self.v[bisect.bisect_right(self.t, tick) - 1]

    def changes(self, t0, t1):
        return bisect.bisect_right(self.t, t0) < bisect.bisect_left(self.t, t1)


def midi_notes(m, drum_channels):
    """The notes, each channel's volume (CC 7, CC 11) and bend (semitones) as they go."""
    notes = []
    prog = [0] * 16
    msb = [0] * 16
    cc7, cc11, pan = [100] * 16, [127] * 16, [64] * 16
    sus = [False] * 16
    rng = [2.0] * 16
    rpn = [(127, 127)] * 16
    bendv = [8192] * 16
    vol = [Timeline((100, 127)) for _ in range(16)]
    bend = [Timeline(0.0) for _ in range(16)]
    held = [dict() for _ in range(16)]      # key -> Note
    sustained = [[] for _ in range(16)]
    last = 0

    def end(n, tick):
        n.off = tick
        notes.append(n)

    for tick, _, _, _, kind, ch, a, b in m.events:
        last = max(last, tick)
        if kind == ON:
            if a in held[ch]:
                end(held[ch].pop(a), tick)
            for s in [s for s in sustained[ch] if s.key == a]:
                sustained[ch].remove(s)
                end(s, tick)
            n = Note()
            n.ch, n.key, n.vel, n.on, n.prog = ch, a, b, tick, prog[ch]
            n.drum = (ch in drum_channels and msb[ch] != 121) or msb[ch] in (120, 127)
            n.pan = pan[ch]
            held[ch][a] = n
        elif kind == OFF:
            n = held[ch].pop(a, None)
            if n:
                if sus[ch]:
                    sustained[ch].append(n)
                else:
                    end(n, tick)
        elif kind == PROG:
            prog[ch] = a
        elif kind == BEND:
            bendv[ch] = a
            bend[ch].set(tick, (a - 8192) / 8192 * rng[ch])
        elif kind == CC:
            if a == 0:
                msb[ch] = b
            elif a == 7:
                cc7[ch] = b
                vol[ch].set(tick, (cc7[ch], cc11[ch]))
            elif a == 11:
                cc11[ch] = b
                vol[ch].set(tick, (cc7[ch], cc11[ch]))
            elif a == 10:
                pan[ch] = b
            elif a == 64:
                sus[ch] = b >= 64
                if not sus[ch]:
                    for s in sustained[ch]:
                        end(s, tick)
                    sustained[ch] = []
            elif a == 101:
                rpn[ch] = (b, rpn[ch][1])
            elif a == 100:
                rpn[ch] = (rpn[ch][0], b)
            elif a == 6 and rpn[ch] == (0, 0):
                rng[ch] = b + (rng[ch] % 1)
            elif a == 38 and rpn[ch] == (0, 0):
                rng[ch] = int(rng[ch]) + b / 100
            elif a in (120, 123):
                for n in list(held[ch].values()) + sustained[ch]:
                    end(n, tick)
                held[ch], sustained[ch] = {}, []
            elif a == 121:
                cc11[ch] = 127
                vol[ch].set(tick, (cc7[ch], cc11[ch]))
                bendv[ch] = 8192
                bend[ch].set(tick, 0.0)
                sus[ch] = False
                for s in sustained[ch]:
                    end(s, tick)
                sustained[ch] = []
    for ch in range(16):
        for n in list(held[ch].values()) + sustained[ch]:
            end(n, last)
    notes.sort(key=lambda n: (n.on, n.ch, -n.key))
    return notes, vol, bend


def time_signatures(m):
    ts = [(e[0], e[6], e[7]) for e in m.events if e[4] == TSIG]
    if not ts or ts[0][0] > 0:
        ts.insert(0, (0, 4, 2))
    return ts


# ---- The grid ----------------------------------------------------------------------------------
def best_sn(rowdur, prev_s):
    """Ticks a row (S) and Timer 2 steps a tick (n) for rows this long: close to it (a tempo a
    percent off is only a song a percent longer), ticks of 8 ms or less (they place the notes
    between rows), the ticks a row kept if they can be."""
    best = None
    for s in range(2, MAX_S + 1):
        for n in RATE_FOR:
            err = abs(s * n * STEP - rowdur) / rowdur
            score = (err * 200 + (100 if err > 0.02 else 0) + max(0.0, math.log2(n * STEP / 0.008)) * 4
                     + (1.5 if prev_s and s != prev_s else 0))
            if best is None or score < best[0]:
                best = (score, s, n)
    return best[1], best[2]


class Grid:
    def __init__(self, tm, r, snap_s):
        self.tm, self.r, self.snap = tm, r, snap_s
        self.ppq = tm.ppq
        segs = []
        prev_s = None
        for tk, us in zip(tm.ticks, tm.usecs):
            row = int(round(tk * r / self.ppq))
            s, n = best_sn(us / 1e6 / r, prev_s)
            if segs and segs[-1][0] == row:
                segs.pop()
            if segs and segs[-1][1:] == (s, n):
                continue
            segs.append((row, s, n))
            prev_s = s
        if segs[0][0] != 0:
            segs[0] = (0,) + segs[0][1:]
        self.segs = segs
        self.seg_rows = [s[0] for s in segs]

    def seg(self, row):
        return self.segs[bisect.bisect_right(self.seg_rows, row) - 1]

    def pos(self, tick):
        return tick * self.r / self.ppq

    def tick_of(self, row):
        return row * self.ppq / self.r

    def place(self, tick):
        """(row, tick in it) for a MIDI tick: on the row if within the snap."""
        p = self.pos(tick)
        row = int(math.floor(p + 1e-9))
        frac = max(0.0, p - row)
        _, s, _ = self.seg(row)
        rowsec = self.tm.spb(tick) / self.r
        if frac * rowsec <= self.snap:
            return row, 0
        if (1 - frac) * rowsec <= self.snap:
            return row + 1, 0
        t = int(round(frac * s))
        if t >= s:
            return row + 1, 0
        return row, t

    def row_at_sec(self, sec):
        return self.pos(self.tm.tick(sec))

    def tempo_fx(self):
        """{row: [(effect, parameter)]}: Fxx where the ticks change."""
        out = {}
        for (r0, s0, n0), (r1, s1, n1) in zip(self.segs, self.segs[1:]):
            fx = []
            if s1 != s0:
                fx.append((ord("F"), s1))
            if n1 != n0:
                fx.append((ord("F"), RATE_FOR[n1]))
            if fx:
                out[r1] = fx
        return out

    def seconds(self, rows):
        """How long the player takes for rows 0 .. rows."""
        total = 0.0
        for i, (r0, s, n) in enumerate(self.segs):
            r1 = self.segs[i + 1][0] if i + 1 < len(self.segs) else rows
            r1 = min(r1, rows)
            if r1 > r0:
                total += (r1 - r0) * s * n * STEP
        return total


def choose_rows_per_beat(notes, tm, ts, want=None):
    if want:
        return want
    ppq = tm.ppq
    onsets = [n.on for n in notes]
    if not onsets:
        return 4
    tol = max(0.5, ppq * 0.012)
    spbs = sorted(tm.spb(t) for t in onsets)
    spb_med = spbs[len(spbs) // 2]
    spb_max = max(tm.usecs) / 1e6
    bar_q = max(num * 4 / (2 ** den) for _, num, den in ts)   # the longest bar, in beats
    # How many more notes are on a grid's rows than would be by chance: the most is the grid
    # the song was written on. (Unquantized, none is: rows of about 0.1 s, EDx the rest.)
    excess = {}
    for r in (1, 2, 3, 4, 6, 8, 12, 16, 24, 32):
        if spb_max / r > MAX_S * 97 * STEP or bar_q * r > 128 or spb_med / r > 0.16:
            continue
        step = ppq / r
        on = sum(1 for t in onsets if abs(t / step - round(t / step)) * step <= tol)
        excess[r] = on / len(onsets) - min(1.0, (2 * tol + 1) / step)
    if not excess:
        return 4
    top = max(excess.values())
    if top < 0.25:
        return min(excess, key=lambda r: abs(math.log(spb_med / r / 0.1)))
    return min(r for r, e in excess.items() if e >= top - 0.02)


# ---- Voices ------------------------------------------------------------------------------------
class Voice:
    __slots__ = ("n", "ik", "a", "ta", "off", "toff", "occ", "rel", "amp", "vol", "pan", "role",
                 "kon", "koff", "dur", "nv", "keep", "track", "mode", "end", "w4")


def vol_steps(vel, cc7, cc11, gain):
    db = gain
    for v in (vel, cc7, cc11):
        db += 40 * math.log10(v / 127) if v > 0 else -200
    return max(0, min(63, 63 + int(round(db / 0.75))))


class Song:
    """The MIDI, read, and what arranging it needs."""


def make_voices(sg, opts):
    tm, grid = sg.tm, sg.grid
    voices = []
    skipped = {}
    for n in sg.notes:
        ik = ("p", n.key) if n.drum else ("m", n.prog)
        p4, p2 = sg.bank4.get(ik), sg.bank2.get(ik)
        if not p4 and not p2:
            skipped[ik] = skipped.get(ik, 0) + 1
            continue
        ps = [p for p in (p4, p2) if p]
        kon = max(p.kon for p in ps)
        koff = max(p.koff for p in ps)
        on_s = tm.sec(n.on)
        off_s = tm.sec(n.off)
        if n.drum:              # (General MIDI's drums play out, whatever their note-offs say)
            off_s = on_s + max(off_s - on_s, min(kon, 2.5) if kon < INF else 1.0)
        v = Voice()
        v.n, v.ik, v.kon, v.koff = n, ik, kon, koff
        v.a, v.ta = grid.place(n.on)
        v.off, v.toff = grid.place(tm.tick(off_s))
        if v.off <= v.a:
            v.off, v.toff = v.a + 1, 0
        occ_s = min(off_s, on_s + 1.25 * kon)
        if occ_s < off_s:
            r, t = grid.place(tm.tick(occ_s))
            v.occ = max(v.a + 1, min(v.off, r + (1 if t else 0)))
        else:
            v.occ = v.off
        v.rel = max(v.off + 1, int(math.ceil(grid.row_at_sec(off_s + koff))))
        v.vol = vol_steps(n.vel, *sg.vol[n.ch].at(n.on), opts.gain)
        v.amp = 10 ** ((v.vol - 63) * 0.75 / 20)
        v.pan = 0 if abs(n.pan - 64) < opts.pan_width else (1 if n.pan < 64 else 2)
        v.dur = min(off_s - on_s, kon)
        if n.drum:
            v.nv = max(1, min(96, n.key - 11))
        else:
            v.nv = n.key - 11
            while v.nv < 1:
                v.nv += 12
            while v.nv > 96:
                v.nv -= 12
        voices.append(v)
    voices.sort(key=lambda v: (v.a, v.ta, -v.n.key))
    # Who matters most if some must go: the top and bottom voices, drums; a note alone in its
    # channel more than one of a chord (the others mask it); a note doubled at the same pitch
    # least.
    active = []                       # (end, voice) by end
    chord = {}
    for v in voices:
        chord[(v.n.ch, v.a)] = chord.get((v.n.ch, v.a), 0) + 1
    for v in voices:
        while active and active[0][0] <= v.a:
            heapq.heappop(active)
        mel = [w for _, _, w in active if not w.n.drum]
        role = 1.0
        if v.n.drum:
            role = 2.0
        else:
            keys = [w.n.key for w in mel]
            if any(k == v.n.key for k in keys):
                role = 0.3
            elif not keys or v.n.key > max(keys):
                role = 1.5
            elif v.n.key < min(keys):
                role = 1.3
        v.role = role if v.n.drum else role / math.sqrt(chord[(v.n.ch, v.a)])  # (drums: each its own)
        heapq.heappush(active, (v.occ, id(v), v))
    return voices, skipped


def polyphony(voices, end_of):
    ev = []
    for v in voices:
        ev.append((v.a, 1))
        ev.append((end_of(v), -1))
    ev.sort()
    cur, peak, hist = 0, 0, {}
    last = None
    for t, d in ev:
        if last is not None and t > last:
            hist[cur] = hist.get(cur, 0) + (t - last)
        cur += d
        peak = max(peak, cur)
        last = t
    return peak, hist


# ---- Choosing notes: max-weight subsets of intervals, at most cap at a time ----------------------
def select(iv, cap):
    """iv: [(a, b, w)], a < b, w > 0 -> [bool]: the subset of most weight with at most cap of
    them overlapping anywhere (a min-cost flow, cap units along time)."""
    n = len(iv)
    keep = [False] * n
    if cap <= 0 or not n:
        return keep
    order = sorted(range(n), key=lambda i: iv[i][0])
    clusters, cur, cur_end = [], [], None
    for i in order:
        if cur and iv[i][0] >= cur_end:
            clusters.append(cur)
            cur = []
        if not cur:
            cur_end = iv[i][1]
        cur.append(i)
        cur_end = max(cur_end, iv[i][1])
    if cur:
        clusters.append(cur)
    for cl in clusters:
        ev = sorted([(iv[i][1], -1) for i in cl] + [(iv[i][0], 1) for i in cl])
        c = mx = 0
        for _, d in ev:
            c += d
            mx = max(mx, c)
        if mx <= cap:
            for i in cl:
                keep[i] = True
        else:
            for i in _flow([iv[i] for i in cl], cap):
                keep[cl[i]] = True
    return keep


def _flow(iv, cap):
    pts = sorted(set([a for a, _, _ in iv] + [b for _, b, _ in iv]))
    idx = {p: i for i, p in enumerate(pts)}
    m = len(pts)
    to, cp, cost, head, nxt = [], [], [], [-1] * m, []

    def edge(u, v, c, w):
        for x, y, cc, ww in ((u, v, c, w), (v, u, 0, -w)):
            to.append(y)
            cp.append(cc)
            cost.append(ww)
            nxt.append(head[x])
            head[x] = len(to) - 1

    for i in range(m - 1):
        edge(i, i + 1, cap, 0)
    first_iv = len(to)
    for a, b, w in iv:
        edge(idx[a], idx[b], 1, -w)
    pot = [INF] * m                  # potentials: shortest paths in the DAG (all edges forward)
    pot[0] = 0.0
    for u in range(m):
        if pot[u] == INF:
            continue
        e = head[u]
        while e != -1:
            if cp[e] > 0 and to[e] > u and pot[u] + cost[e] < pot[to[e]]:
                pot[to[e]] = pot[u] + cost[e]
            e = nxt[e]
    for _ in range(cap):
        dist = [INF] * m
        prev = [-1] * m
        dist[0] = 0.0
        pq = [(0.0, 0)]
        while pq:
            d, u = heapq.heappop(pq)
            if d > dist[u]:
                continue
            e = head[u]
            pu = pot[u]
            while e != -1:
                if cp[e] > 0:
                    v = to[e]
                    nd = d + cost[e] + pu - pot[v]
                    if nd < dist[v] - 1e-12:
                        dist[v] = nd
                        prev[v] = e
                        heapq.heappush(pq, (nd, v))
                e = nxt[e]
        if dist[m - 1] == INF:
            break
        real = dist[m - 1] + pot[m - 1] - pot[0]
        if real > -1e-9:
            break
        v = m - 1
        while v != 0:
            e = prev[v]
            cp[e] -= 1
            cp[e ^ 1] += 1
            v = to[e ^ 1]
        for i in range(m):
            if dist[i] < INF:
                pot[i] += dist[i]
    return [k for k in range(len(iv)) if cp[first_iv + 2 * k] == 0]


# ---- Arranging: which notes, on which tracks, 2-op or 4-op ---------------------------------------
class Params:
    def __init__(self, k, mult=None, chmult=None):
        self.k = k
        self.mult = dict(mult or {})
        self.chmult = dict(chmult or {})

    def key(self):
        return (self.k, tuple(sorted((k, v) for k, v in self.mult.items() if v != 1.0)),
                tuple(sorted((k, v) for k, v in self.chmult.items() if v != 1.0)))

    def describe(self, sg):
        parts = ["%d 4-op pair%s" % (self.k, "" if self.k == 1 else "s")]
        for ik, f in sorted(self.mult.items()):
            if f != 1.0:
                parts.append("%s 4-op x%g" % (sg.name(ik), f))
        for ch, f in sorted(self.chmult.items()):
            if f != 1.0:
                parts.append("ch %d kept x%g" % (ch + 1, f))
        return ", ".join(parts)


def stage_keep(sg, cap, chmult):
    """Which notes (and how much of each) the tracks hold: [row the voice is kept to, or None]."""
    segs, owner = [], []
    sec_row = sg.grid.tm.spb(0) / sg.grid.r
    for vi, v in enumerate(sg.voices):
        w0 = v.amp ** 0.6 * v.role * chmult.get(v.n.ch, 1.0)   # (loudness, not amplitude)
        a, e = v.a, v.occ
        L = sg.grid.r
        s, j = a, 0
        while s < e:
            b = min(e, s + L)
            secs = (b - s) * sec_row
            if j == 0:
                w = w0 * (2.0 + min(secs, 0.5))
            else:
                t_mid = ((s + b) / 2 - a) * sec_row
                decay = 10 ** (-2 * t_mid / v.kon) if v.kon < INF else 1.0
                w = w0 * secs * 0.5 * decay
            segs.append((s, b, max(w, 1e-9)))
            owner.append((vi, j))
            s = b
            j += 1
            if j >= 4:
                L *= 2
    keep = select(segs, cap)
    out = [None] * len(sg.voices)
    nxt = [0] * len(sg.voices)                # the next segment each voice is to keep
    for (vi, j), (s, b, _), k in zip(owner, segs, keep):
        if j == nxt[vi] and k:
            out[vi] = b
            nxt[vi] = j + 1
        else:
            nxt[vi] = -1
    return out


def worth4(sg, v, end, mult):
    """What a note on a 4-op track is worth."""
    p4, p2 = sg.bank4.get(v.ik), sg.bank2.get(v.ik)
    if not p4 or not p4.four:
        return 0.0
    if not p2:
        return 1e6
    d = sg.benefit.get(v.ik, 1.0) * mult.get(v.ik, 1.0)
    if d <= 0:
        return 0.0
    secs = (end - v.a) * sg.grid.tm.spb(sg.grid.tick_of(v.a)) / sg.grid.r
    return d * v.amp * (min(secs, v.kon) + 0.3 * v.koff)


def arrange(sg, prm, cache):
    """The voices on tracks: [(voice, track, mode, end row)], the pairs' bits, stats."""
    k = prm.k
    cap = 18 - k
    ck = (cap, tuple(sorted(prm.chmult.items())))
    if ck not in cache:
        cache[ck] = stage_keep(sg, cap, prm.chmult)
    kept = cache[ck]
    vs = [(v, e) for v, e in zip(sg.voices, kept) if e is not None]
    stats = {"notes": len(sg.voices), "dropped": len(sg.voices) - len(vs),
             "shortened": sum(1 for v, e in vs if e < v.occ)}
    # The 4-op tracks: to the notes worth most there.
    iv, ix = [], []
    for i, (v, e) in enumerate(vs):
        w = worth4(sg, v, e, prm.mult)
        if w > 0:
            iv.append((v.a, e, w))
            ix.append(i)
    four = set(ix[j] for j, kk in enumerate(select(iv, k)) if kk)
    t4 = OP4_TRACKS[:k]
    t2 = [t for t in range(18) if t not in t4 and t not in [PARTNER[x] for x in t4]]
    last = {t: None for t in t4 + t2}         # the track's last (voice, end)
    on4 = {t: [] for t in t4}                 # the 4-op tracks' notes' (start, end)
    out = []

    def pick(cands, v, a):
        best = None
        for t in cands:
            lv = last[t]
            pen = 0.0
            if lv is not None:
                pv, pe = lv
                if a < pv.rel:
                    pen = pv.amp * (pv.rel - a) / max(1, pv.rel - pe)
                if pv.n.ch == v.n.ch:
                    pen -= 0.05 * v.amp
                    if pv.n.key == v.n.key and pe == a:
                        pen -= 0.2 * v.amp
                age = pe
            else:
                age = -1
            sc = (pen, age)
            if best is None or sc < best[0]:
                best = (sc, t)
        return best[1]

    for i, (v, e) in enumerate(vs):
        if i not in four:
            continue
        free = [t for t in t4 if last[t] is None or last[t][1] <= v.a]
        t = pick(free, v, v.a)               # (always one: at most k overlap)
        last[t] = (v, e)
        on4[t].append((v.a, e))
        out.append([v, t, 4, e])
    starts4 = {t: [s for s, _ in on4[t]] for t in t4}
    stats["four"] = len(out)
    last = {t: None for t in t4 + t2}
    frag = 0
    for i, (v, e) in enumerate(vs):
        if i in four:
            continue
        free = [t for t in t2 if last[t] is None or last[t][1] <= v.a]
        mode = 2 if sg.bank2.get(v.ik) else 4
        if not free or mode == 4:
            # a 4-op track between its 4-op notes
            best = None
            for t in t4:
                if last[t] is not None and last[t][1] > v.a:
                    continue
                j = bisect.bisect_left(starts4[t], v.a)
                if j > 0 and on4[t][j - 1][1] > v.a:
                    continue
                room = starts4[t][j] if j < len(starts4[t]) else INF
                if best is None or room > best[0]:
                    best = (room, t)
            if best is not None and (best[0] >= e or not free):
                if best[0] < e:
                    if best[0] <= v.a:
                        frag += 1
                        continue
                    e = best[0]
                    frag += 1
                t = best[1]
                last[t] = (v, e)
                out.append([v, t, mode, e])
                continue
            if not free or mode == 4:      # (a 4-op patch with no 2-op one: 4-op tracks only)
                frag += 1
                continue
        t = pick(free, v, v.a)
        last[t] = (v, e)
        out.append([v, t, mode, e])
    stats["squeezed"] = frag
    bits = 0
    for b in OP4_BITS[:k]:
        bits |= b
    return out, bits, stats


def arrange_ideal(sg):
    """Every note on a 4-op track of its own while it sounds (its release too): as many songs
    of six 4-op tracks as that takes."""
    last = []
    placed = []
    for v in sg.voices:
        best = None
        for t, (pv, pe) in enumerate(last):
            if pe <= v.a:
                sc = (0 if pv.n.ch == v.n.ch else 1, pe)
                if best is None or sc < best[0]:
                    best = (sc, t)
        if best is None:
            last.append(None)
            t = len(last) - 1
        else:
            t = best[1]
        last[t] = (v, max(v.rel, v.off + 1))
        placed.append((v, t))
    songs = []
    for g in range((len(last) + 5) // 6):
        out = []
        for v, t in placed:
            if t // 6 == g:
                mode = 4 if sg.bank4.get(v.ik) else 2
                out.append([v, OP4_TRACKS[t % 6], mode, v.off])
        songs.append(out)
    return songs


# ---- Cells ---------------------------------------------------------------------------------------
class Instruments:
    def __init__(self, sg):
        self.sg = sg
        self.index = {}
        self.items = []               # (32 bytes, name, source)

    def get(self, ik, mode, pan):
        key = (ik, mode, pan)
        if key not in self.index:
            p = (self.sg.bank4 if mode == 4 else self.sg.bank2)[ik]
            ins = bytearray(p.ins)
            ins[25] = (0, 0x10, 0x20)[pan]
            name = "%s %dop%s" % (p.name[:11].rstrip(), mode, ("", "L", "R")[pan])
            self.items.append((bytes(ins), name, p.src))
            self.index[key] = len(self.items)
        return self.index[key]

    def add_raw(self, ins, name):
        self.items.append((ins, name, None))
        return len(self.items)


def make_cells(sg, placed, valid_tracks, insts, comp=True):
    """{(row, track): [note, instrument, volume, effect, parameter]}."""
    cells = {}
    grid = sg.grid

    def cell(row, tr):
        c = cells.get((row, tr))
        if c is None:
            c = cells[(row, tr)] = [0, 0, 0, 0, 0]
        return c

    # Tempo first, on tracks with nothing playing there.
    busy = {}
    for v, t, mode, e in placed:
        busy.setdefault(t, []).append((v.a, max(e, v.off)))
    for t in busy:
        busy[t].sort()
    for row, fxs in sorted(grid.tempo_fx().items()):
        def idle(t):
            for s, e in busy.get(t, ()):
                if s <= row < e:
                    return False
            return True
        order = sorted(valid_tracks, key=lambda t: (not idle(t), t in busy, -t))
        for (fx, par), t in zip(fxs, order):
            c = cell(row, t)
            c[3], c[4] = fx, par
    by_track = {}
    for p in placed:
        by_track.setdefault(p[1], []).append(p)
    for t, lst in by_track.items():
        lst.sort(key=lambda p: (p[0].a, p[0].ta))
        for i, (v, _, mode, e) in enumerate(lst):
            nxt = lst[i + 1][0].a if i + 1 < len(lst) else INF
            n = v.n
            ins = insts.get(v.ik, mode, v.pan)
            cvol = sg.comp.get(v.ik, 0) if comp and mode == 2 and sg.bank4.get(v.ik) else 0
            vol = max(0, min(63, v.vol + cvol))
            c = cell(v.a, t)
            ta = v.ta if not c[3] else 0
            nv = v.nv
            bend_tl = sg.bend[n.ch]
            cur = 0
            want0 = 0
            if not n.drum:
                b = bend_tl.at(n.on)
                if b:
                    nb = int(round(b))
                    nv2 = nv + nb
                    if 1 <= nv2 <= 96:
                        nv = nv2
                        cur = nb * 32
                    want0 = int(round(b * 32))
            c[0], c[1], c[2] = nv, ins, vol + 1
            if ta:
                c[3], c[4] = ord("E"), 0xD0 | ta
            elif want0 != cur and not c[3]:
                d = max(-15, min(15, want0 - cur))
                c[3], c[4] = ord("E"), (0x10 if d > 0 else 0x20) | abs(d)
                cur += d
            # where it ends: its key let go, unless the next note on the track comes first
            if e < v.occ:
                kr, kt = e, 0
            else:
                kr, kt = v.off, v.toff
            stop = min(kr, nxt)
            tk_end = grid.tick_of(stop)
            vol_tl = sg.vol[n.ch]
            do_vol = vol_tl.changes(n.on, tk_end)
            do_bend = not n.drum and (bend_tl.changes(n.on, tk_end) or want0 != cur)
            if do_vol or do_bend:
                cv = vol
                for row in range(v.a + 1, stop):
                    tk = grid.tick_of(row)
                    if do_vol:
                        nvv = max(0, min(63, vol_steps(n.vel, *vol_tl.at(tk), sg.opts.gain) + cvol))
                        if nvv != cv:
                            cell(row, t)[2] = nvv + 1
                            cv = nvv
                    if do_bend:
                        # A bend that ramps through the row: a slide (1xx, 2xx) across it, to
                        # be there by the next row; one that jumps: 3FF to its semitone (there
                        # in a tick), and the rest of it -- or a small change -- E1x, E2x.
                        s = grid.seg(row)[1]
                        now = int(round(bend_tl.at(tk) * 32))
                        then = int(round(bend_tl.at(grid.tick_of(row + 1)) * 32))
                        mid = int(round(bend_tl.at(grid.tick_of(row + 0.5)) * 32))
                        c2 = cells.get((row, t))
                        if c2 is not None and (c2[3] or c2[0]):
                            continue
                        ramp = abs(then - now) >= s - 1 and \
                            abs((mid - now) - (then - now) / 2) <= abs(then - now) / 4
                        if ramp and then != cur:
                            d = then - cur
                            xx = max(1, min(255, int(round(abs(d) / (s - 1)))))
                            c2 = cell(row, t)
                            c2[3], c2[4] = ord("1") if d > 0 else ord("2"), xx
                            cur += (1 if d > 0 else -1) * xx * (s - 1)
                        elif abs(now - cur) > 15 and 1 <= v.nv + int(round(now / 32)) <= 96:
                            c2 = cell(row, t)
                            c2[0], c2[3], c2[4] = v.nv + int(round(now / 32)), ord("3"), 0xFF
                            cur = int(round(now / 32)) * 32
                        elif now != cur:
                            d = max(-15, min(15, now - cur))
                            c2 = cell(row, t)
                            c2[3], c2[4] = ord("E"), (0x10 if d > 0 else 0x20) | abs(d)
                            cur += d
            if kr < nxt:
                c = cell(kr, t)
                c[0], c[1] = 0x7F, 0
                if kt and not c[3]:
                    c[3], c[4] = ord("E"), 0xD0 | kt
    return cells


# ---- The song file ---------------------------------------------------------------------------------
def pack_rows(cells, r0, r1):
    out = bytearray()
    rows = {}
    for (row, t), c in cells.items():
        if r0 <= row < r1:
            rows.setdefault(row - r0, []).append((t, c))
    r, n = 0, r1 - r0
    while r < n:
        for t, (note, ins, vol, fx, par) in sorted(rows.get(r, ())):
            b = t | (0x20 if note or ins else 0) | (0x40 if vol else 0) | (0x80 if fx else 0)
            out.append(b)
            if b & 0x20:
                out += bytes([note, ins])
            if b & 0x40:
                out.append(vol)
            if b & 0x80:
                out += bytes([fx, par])
        k = 0
        while r + 1 + k < n and k < 255 and (r + 1 + k) not in rows:
            k += 1
        if k:
            out += bytes([0x1E, k])
            r += k
        else:
            out.append(0x1F)
        r += 1
    return bytes(out)


def pattern_ranges(sg, rows, target):
    """Patterns of whole bars, about `target` rows each (128 at most)."""
    bars = []
    ts = sg.ts
    for i, (tk, num, den) in enumerate(ts):
        start = sg.grid.pos(tk)
        end = sg.grid.pos(ts[i + 1][0]) if i + 1 < len(ts) else rows
        bar = num * 4 / (2 ** den) * sg.grid.r
        x = start
        while x < end - 1e-6:
            bars.append(int(round(x)))
            x += bar
    bounds = sorted(set([0] + [b for b in bars if 0 < b < rows] + [rows]))
    out, s, prev = [], 0, 0
    for b in bounds[1:]:
        if b - s > 128 and prev > s:       # (b doesn't fit: the pattern ends at the last bar)
            out.append((s, prev))
            s = prev
        while b - s > 128:                 # (a bar longer than a pattern)
            out.append((s, s + 128))
            s += 128
        if b - s >= target:                # long enough: ends at whichever bar is nearer
            if prev > s and target - (prev - s) < (b - s) - target:
                out.append((s, prev))
                s = prev
            else:
                out.append((s, b))
                s = b
        prev = b
    if s < rows:
        out.append((s, rows))
    return out


def song_bytes(sg, cells, rows, bits, insts, ranges, title, author, loop, leadin=None):
    """A .SNG: its header, orders, pattern table, instruments, patterns, names, sources."""
    pats, orders, seen = [], [], {}
    if leadin:
        lrows, lcells = leadin
        pats.append((lrows, pack_rows(lcells, 0, lrows)))
        orders.append(0)
    for r0, r1 in ranges:
        data = pack_rows(cells, r0, r1)
        key = (r1 - r0, data)
        if key not in seen:
            seen[key] = len(pats)
            pats.append(key)
        orders.append(seen[key])
    if len(pats) > 255 or len(orders) > 255:
        return None
    _, s0, n0 = sg.grid.segs[0]
    h = bytearray(b"PSG1")
    h += bytes([0, bits, sg.deep, RATE_FOR[n0], s0, len(insts.items), len(pats), len(orders),
                loop if loop is not None else 0xFF, 0, 0, 0])
    h += title.encode("ascii", "replace")[:31].ljust(32, b"\0")
    h += author.encode("ascii", "replace")[:31].ljust(32, b"\0")
    h += bytes(orders)
    table = len(h)
    h += bytes(4 * len(pats))
    for ins, _, _ in insts.items:
        h += ins
    for i, (nrows, data) in enumerate(pats):
        at = len(h)
        h[table + 4 * i:table + 4 * i + 4] = bytes([nrows, at >> 16, (at >> 8) & 255, at & 255])
        h += data
    names = len(h)
    h[13:16] = bytes([names >> 16, (names >> 8) & 255, names & 255])
    for _, name, _ in insts.items:
        h += name.encode("ascii", "replace")[:16].ljust(16, b"\0")
    if any(src for _, _, src in insts.items):
        h += b"PSS1"
        for _, _, src in insts.items:
            h += src or bytes(16)
    return bytes(h)


MARKER = bytes([0, 0x00, 0, 0x20, 0x3F, 0xF0, 0x0F, 0x00, 0x20, 0x00, 0xF0, 0x0F, 0x00] + [0] * 19)


def leadin(sg, insts):
    """The renders' first pattern: a marker note to find the song's start by."""
    rowsec = sg.grid.segs[0][1] * sg.grid.segs[0][2] * STEP
    rows = max(4, int(math.ceil(0.5 / rowsec)))
    ins = insts.add_raw(MARKER, "marker")
    return rows, {(0, MARKER_TRACK): [49, ins, 64, 0, 0], (1, MARKER_TRACK): [0x7F, 0, 0, 0, 0]}


def build(sg, placed, bits, tracks_ok, lead, comp=True):
    insts = Instruments(sg)
    cells = make_cells(sg, placed, tracks_ok, insts, comp)
    rows = max([r for r, _ in cells] + [0]) + 1 + sg.tail_rows
    ranges = None
    for target in (sg.opts.pattern_rows, 128):
        ranges = pattern_ranges(sg, rows, target)
        lead_in = leadin(sg, insts) if lead else None
        data = song_bytes(sg, cells, rows, bits, insts, ranges, sg.title, sg.author,
                          sg.opts.loop, lead_in)
        if lead:
            insts.items.pop()     # (the marker: again, the next time round)
        if data is not None:
            break
        say("  (more than 255 patterns or orders: longer patterns)")
    if data is None:
        sys.exit("The song is too long for 255 orders of 128 rows.")
    if lead:
        lead_rows = lead_in[0]
    else:
        lead_rows = 0
    return data, rows, lead_rows, len(insts.items) + (1 if lead else 0)


# ---- Rendering: SONGPLAY on the emulated machine ------------------------------------------------
def find_emulator(given):
    if given:
        return given
    cands = []
    for b in ("build", "build-release", "build-release-linux", "build-linux"):
        for c in ("Release", "RelWithDebInfo", "Debug", ""):
            for exe in ("pugputer_tests.exe", "pugputer_tests"):
                p = os.path.join(REPO, "simulator", b, "tests", c, exe)
                if os.path.isfile(p):
                    cands.append(p)
    if not cands:
        return None
    return max(cands, key=os.path.getmtime)


class Renderer:
    def __init__(self, exe, workdir, jobs):
        self.exe, self.dir = exe, workdir
        with open(exe, "rb") as f:
            self.parallel = b"SONGKIT_IMG" in f.read()
        self.jobs = jobs if self.parallel else 1
        self.n = 0
        self.count = 0

    def render(self, data, seconds):
        """The song played: (rate, float32 samples, n x 2)."""
        self.n += 1
        tag = "m2s_%d_%d" % (os.getpid(), self.n)
        sng = os.path.join(self.dir, tag + ".sng")
        wav = os.path.join(self.dir, tag + ".wav")
        with open(sng, "wb") as f:
            f.write(data)
        env = dict(os.environ)
        env.update(SONGKIT_SONG=sng, SONGKIT_WAV=wav, SONGKIT_SECONDS="%.1f" % (seconds + 10))
        if self.parallel:
            env["SONGKIT_IMG"] = tag + ".img"
        r = subprocess.run([self.exe, "songkit_song_to_wav"], cwd=REPO, env=env,
                           capture_output=True, text=True, timeout=max(600, seconds * 4))
        if not os.path.isfile(wav):
            sys.exit("The render failed:\n" + r.stdout[-2000:] + r.stderr[-2000:])
        out = read_wav(wav)
        os.remove(sng)
        os.remove(wav)
        self.count += 1
        return out

    def many(self, jobs):
        """[(data, seconds)] rendered, several at once."""
        with ThreadPoolExecutor(max_workers=self.jobs) as ex:
            return list(ex.map(lambda j: self.render(*j), jobs))


def read_wav(path):
    d = open(path, "rb").read()
    i, rate, nch = 12, 49716, 2
    while i + 8 <= len(d):
        cid, ln = d[i:i + 4], struct.unpack("<I", d[i + 4:i + 8])[0]
        if cid == b"fmt ":
            nch = struct.unpack("<H", d[i + 10:i + 12])[0]
            rate = struct.unpack("<I", d[i + 12:i + 16])[0]
        elif cid == b"data":
            x = np.frombuffer(d[i + 8:i + 8 + ln], "<i2").astype(np.float32) / 32768
            return rate, x.reshape(-1, nch)
        i += 8 + ln + (ln & 1)
    return rate, np.zeros((0, 2), np.float32)


def write_wav(path, rate, x):
    pcm = (np.clip(x, -1, 1) * 32767).astype("<i2").tobytes()
    with open(path, "wb") as f:
        f.write(b"RIFF" + struct.pack("<I", 36 + len(pcm)) + b"WAVEfmt ")
        f.write(struct.pack("<IHHIIHH", 16, 1, 2, rate, rate * 4, 4, 16))
        f.write(b"data" + struct.pack("<I", len(pcm)) + pcm)


def song_audio(sg, rendered, lead_rows, seconds):
    """The song's own samples, from its first row: found from the marker note."""
    rate, x = rendered
    sg.rate = rate                       # (the emulator's, not the chip's 49716)
    loud = np.abs(x).max(axis=1)
    hit = np.flatnonzero(loud > 0.004)
    if not len(hit):
        sys.exit("The render is silent: is the emulator's SONGPLAY built?")
    s = sg.grid.segs[0]
    start = int(hit[0] + round(lead_rows * s[1] * s[2] * STEP * rate))
    n = int(seconds * rate)
    y = x[start:start + n]
    if len(y) < n:
        y = np.concatenate([y, np.zeros((n - len(y), 2), np.float32)])
    return y


# ---- Listening: log-mel spectrograms -----------------------------------------------------------------
_FB = {}


def mel_bank(rate, nfft=2048, nb=64, fmin=30.0, fmax=16000.0):
    key = (rate, nfft, nb)
    if key in _FB:
        return _FB[key]
    mel = lambda f: 2595 * np.log10(1 + f / 700)
    imel = lambda m: 700 * (10 ** (m / 2595) - 1)
    pts = imel(np.linspace(mel(fmin), mel(min(fmax, rate / 2)), nb + 2))
    bins = np.fft.rfftfreq(nfft, 1 / rate)
    fb = np.zeros((nb, len(bins)), np.float32)
    for i in range(nb):
        lo, c, hi = pts[i], pts[i + 1], pts[i + 2]
        fb[i] = np.maximum(0, np.minimum((bins - lo) / (c - lo), (hi - bins) / (hi - c)))
    _FB[key] = fb
    return fb


def logmel(x, rate, hop=512, nfft=2048):
    if len(x) < nfft:
        x = np.concatenate([x, np.zeros(nfft - len(x), np.float32)])
    fb = mel_bank(rate, nfft)
    win = np.hanning(nfft).astype(np.float32)
    fr = np.lib.stride_tricks.sliding_window_view(x, nfft)[::hop]
    out = np.empty((len(fr), fb.shape[0]), np.float32)
    for c in range(0, len(fr), 2048):
        p = np.abs(np.fft.rfft(fr[c:c + 2048] * win, axis=1)) ** 2
        out[c:c + len(p)] = 10 * np.log10(p.astype(np.float32) @ fb.T + 1e-10)
    return out


def distance(ref, cand, floor_db=70):
    n = min(len(ref), len(cand))
    a, b = ref[:n], cand[:n]
    floor = ref.max() - floor_db
    a = np.maximum(a, floor)
    b = np.maximum(b, floor)
    act = (a > floor) | (b > floor)
    if not act.any():
        return 0.0
    return float(np.abs(a - b)[act].mean())


def stereo_mel(sg, y):
    return [logmel(np.ascontiguousarray(y[:, c]), sg.rate) for c in (0, 1)]


# ---- Each instrument, 2-op and 4-op, on its own ---------------------------------------------------
def analyse(sg, rnd):
    """sg.benefit[ik]: dB the 2-op patch differs from the 4-op one (at the same loudness);
    sg.comp[ik]: volume steps that even the 2-op patch's loudness out to the 4-op one's."""
    rowsec = 6 * 26 * STEP
    use = {}
    for v in sg.voices:
        use.setdefault(v.ik, []).append(v)
    tests = []
    for ik, vs in use.items():
        p4, p2 = sg.bank4.get(ik), sg.bank2.get(ik)
        if not (p4 and p2 and p4.four):
            continue
        keys = sorted(v.nv for v in vs)
        if ik[0] == "p":
            pitches = [keys[0]]
        else:
            pitches = sorted(set(keys[int(f * (len(keys) - 1))] for f in (0.2, 0.5, 0.8)))
        durs = sorted(min(v.dur, 4.0) for v in vs)
        hold = max(3, min(40, int(round(durs[len(durs) // 2] / rowsec))))
        rel = max(6, min(40, int(round(max(p4.koff, p2.koff) / rowsec)) + 4))
        for nv in pitches:
            tests.append((ik, nv, hold, rel))
    if not tests:
        return
    say("Listening to %d instruments, 2-op and 4-op (%d notes each)..." % (
        len(set(t[0] for t in tests)), len(tests)))
    # One song: the 4-op patch on track 0 (a 4-op channel), then the 2-op one on track 6.
    jobs = []
    chunk = []
    rows_max = 240 * 64
    for t in tests:
        chunk.append(t)
        if sum(2 * (h + r) for _, _, h, r in chunk) > rows_max:
            jobs.append(chunk)
            chunk = []
    if chunk:
        jobs.append(chunk)
    saved = sg.grid
    sg.grid = FixedGrid(saved.tm)
    built = []
    for chunk in jobs:
        insts = Instruments(sg)
        cells, row, at = {}, 0, []
        for ik, nv, hold, rel in chunk:
            for mode, tr in ((4, 0), (2, 6)):
                ins = insts.get(ik, mode, 0)
                cells[(row, tr)] = [nv, ins, 64, 0, 0]
                cells[(row + hold, tr)] = [0x7F, 0, 0, 0, 0]
                at.append((ik, mode, row, hold + rel))
                row += hold + rel
        rows = row + 4
        ranges = [(r, min(rows, r + 64)) for r in range(0, rows, 64)]
        lead = leadin(sg, insts)
        data = song_bytes(sg, cells, rows, 0x01, insts, ranges, "analysis", "", None, lead)
        built.append((data, rows, lead[0], at))
    outs = rnd.many([(d, sg.grid.seconds(rows) + 2) for d, rows, _, _ in built])
    res = {}
    for (data, rows, lr, at), out in zip(built, outs):
        y = song_audio(sg, out, lr, sg.grid.seconds(rows)).mean(axis=1)
        for i in range(0, len(at), 2):
            (ik, _, r4, n4), (_, _, r2, n2) = at[i], at[i + 1]
            a = logmel(y[int(r4 * rowsec * sg.rate):int((r4 + n4) * rowsec * sg.rate)], sg.rate)
            b = logmel(y[int(r2 * rowsec * sg.rate):int((r2 + n2) * rowsec * sg.rate)], sg.rate)
            la = 10 * np.log10(np.mean(10 ** (a / 10)) + 1e-12)
            lb = 10 * np.log10(np.mean(10 ** (b / 10)) + 1e-12)
            n = min(len(a), len(b))
            d = distance(a[:n], b[:n] + (la - lb), 60)
            res.setdefault(ik, []).append((d, la - lb))
    sg.grid = saved
    for ik, rs in res.items():
        sg.benefit[ik] = sum(d for d, _ in rs) / len(rs)
        sg.comp[ik] = int(round(sum(g for _, g in rs) / len(rs) / 0.75))


class FixedGrid:
    """The analysis song's grid: 6 ticks of 26 steps a row (about 50 ms)."""

    def __init__(self, tm):
        self.tm = tm
        self.segs = [(0, 6, 26)]
        self.r = 4

    def seconds(self, rows):
        return rows * 6 * 26 * STEP


# ---- The search -------------------------------------------------------------------------------------
class Result:
    def __init__(self, prm, score, stats):
        self.prm, self.score, self.stats = prm, score, stats


def candidate(sg, prm, cache):
    placed, bits, stats = arrange(sg, prm, cache)
    t4 = OP4_TRACKS[:prm.k]
    ok = [t for t in range(18) if t not in [PARTNER[x] for x in t4]]
    data, rows, lead_rows, _ = build(sg, placed, bits, ok, True)
    return data, rows, lead_rows, stats


def search(sg, rnd):
    say("Playing the song as it would be with unlimited channels, all 4-op...")
    ideal = arrange_ideal(sg)
    jobs, metas = [], []
    for placed in ideal:
        data, rows, lr, _ = build(sg, placed, 0x3F, [6, 7, 8, 15, 16, 17], True, comp=False)
        jobs.append((data, sg.grid.seconds(rows) + 2))
        metas.append((rows, lr))
    sg.song_rows = max(m[0] for m in metas)
    sg.song_secs = sg.grid.seconds(sg.song_rows)
    outs = rnd.many(jobs)
    y = None
    for out, (rows, lr) in zip(outs, metas):
        part = song_audio(sg, out, lr, sg.song_secs)
        y = part if y is None else y + part
    sg.ideal_audio = y
    sg.ideal = stereo_mel(sg, y)
    say("  %d voices at most: %d song%s of six 4-op tracks" % (
        sg.peak_ideal, len(ideal), "" if len(ideal) == 1 else "s"))

    cache = {}
    done = {}

    def evaluate(prms):
        prms = [p for p in prms if p.key() not in done]
        uniq = {}
        for p in prms:
            uniq.setdefault(p.key(), p)
        prms = list(uniq.values())[:max(0, sg.opts.renders - len(done))]
        if not prms:
            return []
        built = [candidate(sg, p, cache) for p in prms]
        outs = rnd.many([(d, sg.song_secs + 2) for d, _, _, _ in built])
        res = []
        for p, (d, rows, lr, st), out in zip(prms, built, outs):
            yy = song_audio(sg, out, lr, sg.song_secs)
            m = stereo_mel(sg, yy)
            sc = (distance(sg.ideal[0], m[0]) + distance(sg.ideal[1], m[1])) / 2
            r = Result(p, sc, st)
            done[p.key()] = r
            res.append(r)
        return res

    ks = [sg.opts.pairs] if sg.opts.pairs is not None else list(range(7))
    say("Trying %s..." % ", ".join("%d 4-op pairs" % k for k in ks))
    res = evaluate([Params(k) for k in ks])
    for r in sorted(res, key=lambda r: r.prm.k):
        st = r.stats
        say("  %d pairs (%2d tracks): %.3f dB off   4-op notes %4d/%d  dropped %d  shortened %d  "
            "squeezed %d" % (r.prm.k, 18 - r.prm.k, r.score, st["four"], st["notes"],
                             st["dropped"], st["shortened"], st["squeezed"]))
    best = min(res, key=lambda r: r.score)
    # Then the instruments' worth in 4-op, and (if notes are cut) the channels', searched.
    presence = {}
    for v in sg.voices:
        presence[v.ik] = presence.get(v.ik, 0) + v.amp * v.dur
    tops = [ik for ik in sorted(presence, key=lambda i: -presence[i])
            if sg.bank4.get(ik) and sg.bank2.get(ik)][:12]
    rounds = 0
    while len(done) < sg.opts.renders and best.prm.k > 0 and rounds < 8:
        rounds += 1
        trials = []
        for ik in tops:
            f = best.prm.mult.get(ik, 1.0)
            for nf in (f * 4, f / 4 if f > 0.3 else 0.0):
                p = Params(best.prm.k, best.prm.mult, best.prm.chmult)
                p.mult[ik] = nf
                trials.append(p)
        if best.stats["dropped"] + best.stats["shortened"]:
            chp = {}
            for v in sg.voices:
                chp[v.n.ch] = chp.get(v.n.ch, 0) + v.amp * v.dur
            for ch in sorted(chp, key=lambda c: -chp[c])[:6]:
                p = Params(best.prm.k, best.prm.mult, best.prm.chmult)
                p.chmult[ch] = best.prm.chmult.get(ch, 1.0) * 2
                trials.append(p)
        for dk in (-1, 1):
            if 0 <= best.prm.k + dk <= 6 and sg.opts.pairs is None:
                trials.append(Params(best.prm.k + dk, best.prm.mult, best.prm.chmult))
        res = evaluate(trials)
        if not res:
            break
        better = sorted([r for r in res if r.score < best.score - 1e-3], key=lambda r: r.score)
        say("  round %d: %d tried, %d better (%.3f dB -> %s)" % (
            rounds, len(res), len(better), best.score,
            "%.3f" % better[0].score if better else "--"))
        if not better:
            break
        top = better[0]
        if len(better) > 1:               # all of the better changes at once
            p = Params(best.prm.k, best.prm.mult, best.prm.chmult)
            for r in better:
                if r.prm.k != best.prm.k:
                    continue
                for ik, f in r.prm.mult.items():
                    if f != best.prm.mult.get(ik, 1.0):
                        p.mult[ik] = f
                for ch, f in r.prm.chmult.items():
                    if f != best.prm.chmult.get(ch, 1.0):
                        p.chmult[ch] = f
            both = evaluate([p])
            if both and both[0].score < top.score:
                top = both[0]
        best = top
    return best, cache


# ---- Main ----------------------------------------------------------------------------------------------
def dos_name(path):
    stem = re.sub(r"[^A-Za-z0-9]", "", os.path.splitext(os.path.basename(path))[0]).upper()
    return (stem[:8] or "SONG") + ".SNG"


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0],
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("midi")
    ap.add_argument("out", nargs="?", help="the .SNG to write (default: the MIDI's name, 8.3, here)")
    ap.add_argument("--title", help="the song's title (default: the MIDI's, or its file name)")
    ap.add_argument("--author", help="its author (default: the MIDI's copyright text)")
    ap.add_argument("--pairs", type=int, choices=range(7), help="this many 4-op pairs, not the best found")
    ap.add_argument("--renders", type=int, default=60,
                    help="arrangements played at most in the search (default 60)")
    ap.add_argument("--no-render", action="store_true",
                    help="arrange from the banks alone: fast, nothing played, not as good")
    ap.add_argument("--rows-per-beat", type=int, help="the grid (default: chosen from the notes)")
    ap.add_argument("--pattern-rows", type=int, default=64, help="about how long a pattern is (default 64)")
    ap.add_argument("--snap-ms", type=float, default=6.0,
                    help="notes this close to a row go on it, not after it (EDx) (default 6)")
    ap.add_argument("--gain", type=float, default=0.0, help="dB added to every note (default 0)")
    ap.add_argument("--pan-width", type=int, default=48,
                    help="MIDI pan this far from the middle (64) goes hard left or right (default 48)")
    ap.add_argument("--drums", default="10", help="the percussion channels, 1-16 (default 10)")
    ap.add_argument("--loop", type=int, help="the order to go back to at the end (default: none)")
    ap.add_argument("--wav", help="also write the chosen song's render here")
    ap.add_argument("--ideal-wav", help="and the all-4-op, unlimited-channel render here")
    ap.add_argument("--emulator", help="the test program (default: the newest one built)")
    ap.add_argument("--jobs", type=int, default=max(1, min(12, (os.cpu_count() or 2) // 2)),
                    help="renders at once")
    opts = ap.parse_args()
    t0 = time.time()

    sg = Song()
    sg.opts = opts
    sg.bank4, f4 = read_wopl(BANK4)
    sg.bank2, f2 = read_wopl(BANK2)
    sg.deep = ((f4 & 1) << 7) | ((f4 & 2) << 5)      # the bank's deep tremolo and vibrato
    sg.name = lambda ik: (sg.bank4.get(ik) or sg.bank2.get(ik)).name if (
        sg.bank4.get(ik) or sg.bank2.get(ik)) else str(ik)
    m = read_midi(opts.midi)
    sg.tm = TempoMap(m)
    sg.ts = time_signatures(m)
    drums = set(int(c) - 1 for c in opts.drums.split(",") if c.strip())
    sg.notes, sg.vol, sg.bend = midi_notes(m, drums)
    if not sg.notes:
        sys.exit("No notes in %s" % opts.midi)
    sg.title = opts.title if opts.title is not None else (m.title or os.path.splitext(os.path.basename(opts.midi))[0])
    sg.author = opts.author if opts.author is not None else m.author
    r = choose_rows_per_beat(sg.notes, sg.tm, sg.ts, opts.rows_per_beat)
    sg.grid = Grid(sg.tm, r, opts.snap_ms / 1000)
    sg.voices, skipped = make_voices(sg, opts)
    sg.benefit, sg.comp = {}, {}
    tail = max([v.koff for v in sg.voices] + [0.3])
    sg.tail_rows = int(math.ceil(min(2.0, tail + 0.3) / (sg.tm.spb(sg.notes[-1].on) / r)))
    s0 = sg.grid.segs[0]
    say("%s: %d notes, %d channels, %.0f s; %d rows a beat, %d ticks of %.2f ms a row%s" % (
        os.path.basename(opts.midi), len(sg.voices), len(set(v.n.ch for v in sg.voices)),
        sg.tm.sec(max(n.off for n in sg.notes)), r, s0[1], s0[2] * STEP * 1000,
        "" if len(sg.grid.segs) == 1 else " (%d tempo changes)" % (len(sg.grid.segs) - 1)))
    for ik, n in sorted(skipped.items()):
        say("  %d notes left out: %s %d is blank in both banks" % (
            n, "drum" if ik[0] == "p" else "program", ik[1]))
    peak, hist = polyphony(sg.voices, lambda v: v.occ)
    sg.peak_ideal, _ = polyphony(sg.voices, lambda v: max(v.rel, v.off + 1))
    total = sum(hist.values()) or 1
    over = lambda c: sum(t for p, t in hist.items() if p > c) / total * 100
    say("  notes at once: %d at most; more than 12 %.1f%% of the time, more than 18 %.1f%%" % (
        peak, over(12), over(18)))

    out = opts.out or dos_name(opts.midi)
    base = os.path.basename(out)
    if not re.fullmatch(r"[A-Za-z0-9_\-]{1,8}(\.[A-Za-z0-9_\-]{1,3})?", base):
        say("  (%s isn't an 8.3 name: the Pugputer's disk wants one)" % base)

    if opts.no_render:
        for ik in set(v.ik for v in sg.voices):
            sg.benefit[ik] = 1.0
        k = opts.pairs
        if k is None:
            k = max([k for k in range(7) if over(18 - k) < 0.5] or [0])
        best = Result(Params(k), None, None)
        cache = {}
    else:
        if np is None:
            sys.exit("numpy is needed to listen (pip install numpy), or use --no-render")
        exe = find_emulator(opts.emulator)
        if not exe:
            sys.exit("The emulator's test program isn't built (build_all builds it); or --no-render")
        work = tempfile.mkdtemp(prefix="midi2sng_")
        try:
            rnd = Renderer(exe, work, opts.jobs)
            if not rnd.parallel:
                say("  (this test program is older than midi2sng: it renders one song at a time, and"
                    " loses time over long silences -- build_all rebuilds it)")
            sg.rate = 49716
            analyse(sg, rnd)
            for ik in sorted(sg.benefit, key=lambda i: -sg.benefit[i]):
                say("  %-16s 4-op differs by %5.2f dB; 2-op %+d volume steps" % (
                    sg.name(ik), sg.benefit[ik], sg.comp[ik]))
            best, cache = search(sg, rnd)
            say("Best: %s -- %.3f dB from the ideal (%d songs played)" % (
                best.prm.describe(sg), best.score, rnd.count))
            if opts.wav or opts.ideal_wav:
                if opts.ideal_wav:
                    write_wav(opts.ideal_wav, sg.rate, sg.ideal_audio)
                if opts.wav:
                    data, rows, lr, _ = candidate(sg, best.prm, cache)
                    y = song_audio(sg, rnd.render(data, sg.song_secs + 2), lr, sg.song_secs)
                    write_wav(opts.wav, sg.rate, y)
        finally:
            shutil.rmtree(work, ignore_errors=True)

    placed, bits, stats = arrange(sg, best.prm, cache)
    t4 = OP4_TRACKS[:best.prm.k]
    ok = [t for t in range(18) if t not in [PARTNER[x] for x in t4]]
    data, rows, _, ninst = build(sg, placed, bits, ok, False)
    with open(out, "wb") as f:
        f.write(data)
    used = {}
    for v, t, mode, e in placed:
        u = used.setdefault(v.ik, [0, 0])
        u[0 if mode == 4 else 1] += 1
    say("Wrote %s: %d bytes, %d instruments, %d rows, %d 4-op pairs; %d of %d notes 4-op, "
        "%d dropped, %d shortened (%.0f s)" % (
            out, len(data), ninst, rows, best.prm.k, stats["four"], stats["notes"],
            stats["dropped"] + stats["squeezed"], stats["shortened"], time.time() - t0))
    for ik in sorted(used, key=lambda i: -(used[i][0] + used[i][1])):
        say("  %-16s %4d 4-op, %4d 2-op" % (sg.name(ik), used[ik][0], used[ik][1]))


if __name__ == "__main__":
    main()
