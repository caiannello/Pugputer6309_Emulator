"""Looks for 6309 code that trusts LDQ's or MULD's flags the way a real HD6309 doesn't keep them.

A real HD6309 sets Z after LDQ (every mode) and MULD from bits 31-16 of Q only (the A:B half),
and LDQ leaves V as it was (6809Decoder wiki, "Undocumented 6309 Behaviours"). The emulator
does the same now. Code written against the old emulator could still test Z right after an
LDQ: it works there only for values of $10000 or more. This lists every LDQ or MULD followed,
within a few instructions and with nothing between that sets the flags again, by a conditional
branch or a save of CC.

    python simulator/tools/check_ldq_flags.py [folder ...]    (default: the repository)

It prints nothing when nothing is found. Test D and W yourself instead: LDD x / ORD x+2 / BEQ;
or LDW x / BMI / BNE, then LDW x+2 / BEQ, when the sign matters too.
"""
import os
import re
import sys

SKIP = ('build', 'third_party', '.git', 'dist', 'lwtools', 'node_modules')
LOAD = re.compile(r'^\S*\s+(LDQ|MULD)\b', re.I)
USES = re.compile(r'\bL?B(EQ|NE|LE|GT|HI|LS|VS|VC|MI|PL|LT|GE)\b|PSHS\s+.*CC|TFR\s+CC|EXG\s+CC', re.I)
SETS = re.compile(r'^\S*\s+(LD[ABDEFWXYUSQ]|ST[ABDEFWXYUSQ]|TST|CMP|ADD|SUB|AND|OR|EOR|BIT|INC|DEC|CLR|'
                  r'COM|NEG|LS|AS|RO|ADC|SBC|SEX|DAA|MUL|DIV|LEA[XY]|TIM|AIM|OIM|EIM|JSR|BSR|LBSR|RTS|'
                  r'JMP|L?BRA)', re.I)   # (prefixes: SUBW, ADCD, CMPR, ORD... set the flags too)


def code(line):
    c = line.split(';')[0]
    return '' if c.lstrip().startswith('*') else c


def scan(root):
    found = 0
    for d, dirs, files in os.walk(root):
        dirs[:] = [x for x in dirs if not x.startswith(SKIP)]
        for f in files:
            if not f.lower().endswith(('.asm', '.d', '.inc', '.s', '.template')):
                continue
            p = os.path.join(d, f)
            lines = open(p, encoding='latin-1').read().splitlines()
            for i, line in enumerate(lines):
                if not LOAD.match(code(line)):
                    continue
                for j in range(i + 1, min(i + 6, len(lines))):
                    c = code(lines[j])
                    if not c.strip():
                        continue
                    if USES.search(c) and not re.match(r'^\S*\s+L?B(RA|SR)\b', c, re.I):
                        print('%s:%d: %s  ->  %d: %s' % (p, i + 1, line.strip()[:50], j + 1, c.strip()[:40]))
                        found += 1
                        break
                    if SETS.match(c):
                        break
    return found


if __name__ == '__main__':
    roots = sys.argv[1:] or [os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..')]
    sys.exit(1 if sum(scan(r) for r in roots) else 0)
