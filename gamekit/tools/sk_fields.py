"""Makes the field table in sk_inst.asm (between its BEGIN FIELDS and END FIELDS lines):
SONGKIT's instrument page, a field each for every setting, with where it is on the screen
and its neighbors for the arrow keys, worked out from where they are.

  python gamekit/tools/sk_fields.py      (rewrites gamekit/sk_inst.asm in place)
"""
import os

KINDS = ["NUM", "YN", "WAVE", "OPS", "ALG", "NOTE", "FINE", "PAN", "PLAY", "NAME"]
OPCOL = [17, 25, 33, 41]   # the operators' columns
fields = []                # (row, col, width, kind, byte, shift, mask, op)


def f(row, col, width, kind, byte=0, shift=0, mask=0, op=0xFF):
    fields.append((row, col, width, KINDS.index(kind), byte, shift, mask, op))


f(2, 30, 16, "NAME")
f(4, 17, 1, "OPS", 0, 0, 1)
f(4, 41, 18, "ALG")
f(4, 70, 1, "NUM", 1, 1, 7)          # feedback
f(5, 17, 3, "YN", 0, 1, 1)           # a fixed note
f(5, 41, 4, "NOTE")
f(5, 70, 3, "FINE")
f(6, 17, 3, "PAN")
f(6, 41, 9, "PLAY")
# Each operator's: (its register: 0 $20, 1 $40, 2 $60, 3 $80, 4 $E0), shift, mask, kind
OPROWS = [(2, 4, 15, "NUM"),  # attack
          (2, 0, 15, "NUM"),  # decay
          (3, 4, 15, "NUM"),  # sustain level
          (3, 0, 15, "NUM"),  # release
          (1, 0, 63, "NUM"),  # level
          (0, 0, 15, "NUM"),  # multiple
          (4, 0, 7, "WAVE"),  # waveform
          (1, 6, 3, "NUM"),   # key scale level
          (0, 4, 1, "YN"),    # key scale rate
          (0, 5, 1, "YN"),    # sustained
          (0, 6, 1, "YN"),    # vibrato
          (0, 7, 1, "YN")]    # tremolo
for i, (reg, sh, mask, kind) in enumerate(OPROWS):
    for op in range(4):
        f(9 + i, OPCOL[op], 6, kind, 3 + 5 * op + reg, sh, mask, op)


def neighbor(i, drow, dcol):
    r, c = fields[i][0], fields[i][1]
    if dcol:
        same = [j for j, g in enumerate(fields) if g[0] == r and (g[1] - c) * dcol > 0]
        return min(same, key=lambda j: abs(fields[j][1] - c)) if same else i
    rows = sorted({g[0] for g in fields if (g[0] - r) * drow > 0}, key=lambda x: abs(x - r))
    if not rows:
        return i
    cand = [j for j, g in enumerate(fields) if g[0] == rows[0]]
    return min(cand, key=lambda j: abs(fields[j][1] - c))


lines = ["; Each field (FSIZE bytes): its row, column, width, kind (K_), the instrument's",
         "; byte, shift and mask, its operator ($FF: none), then the fields up, down,",
         "; left and right of it. Made by tools/sk_fields.py.",
         f"NFIELDS     equ  {len(fields)}",
         "FIELDS"]
for i, g in enumerate(fields):
    nb = [neighbor(i, -1, 0), neighbor(i, 1, 0), neighbor(i, 0, -1), neighbor(i, 0, 1)]
    lines.append("            FCB  " + ",".join(str(v) for v in list(g) + nb))
p = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "sk_inst.asm")
s = open(p, newline="").read()
a = s.index("; BEGIN FIELDS\n") + len("; BEGIN FIELDS\n")
b = s.index("; END FIELDS")
open(p, "w", newline="").write(s[:a] + "\n".join(lines) + "\n" + s[b:])
print(f"{len(fields)} fields")
