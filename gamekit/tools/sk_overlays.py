"""Checks SONGKIT's overlays: that no code reaches into an overlay it isn't in.

SONGKIT's core (songkit.asm up to its variables' end, sk_core.asm, sk_ui.asm, sk_play.asm)
is always there, in bank 3; each overlay (OV_EDIT: sk_inst.asm and sk_pat.asm; OV_FILE:
sk_file.asm; OV_HELP: sk_help.asm; OV_BLOCK: sk_block.asm) is in bank 2 only while it is the one mapped there. So:

- an overlay may use the core's labels, and its own;
- anything else -- the core using an overlay's label, or an overlay another's -- must go
  through a stub, O_name, in songkit.asm (which maps name's overlay and calls it).

The assembler can't tell (every overlay is at $8000, and they all see each other's labels),
so this does: it lists every line that names another region's label, and the stubs no one
uses. With --fix, a call to a routine that has a stub (JSR name, JMP name, a branch, FDB
name) is changed to call the stub; what's left is listed.

  python gamekit/tools/sk_overlays.py [--fix]      (exit status 1 if anything is wrong)
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
KIT = os.path.dirname(HERE)
REGIONS = {
    'sk_core.asm': 'CORE', 'sk_ui.asm': 'CORE', 'sk_play.asm': 'CORE',
    'sk_inst.asm': 'OV_EDIT', 'sk_pat.asm': 'OV_EDIT',
    'sk_file.asm': 'OV_FILE',
    'sk_help.asm': 'OV_HELP',
    'sk_block.asm': 'OV_BLOCK',
}
MAIN = 'songkit.asm'           # all core (its overlays are only its INCLUDEs)
LABEL = re.compile(r'^([A-Za-z_][A-Za-z0-9_]*)')
TOKEN = re.compile(r'[A-Za-z_][A-Za-z0-9_]*')
VALUE = re.compile(r'^\s*(equ|EQU|=|RMB|rmb|SET|set)\b')
CALLS = re.compile(r'^\s*(JSR|JMP|LBSR|BSR|LB[A-Z]{2}|B[A-Z]{2}|FDB)\s', re.I)


def read(name):
    return open(os.path.join(KIT, name), encoding='utf-8').read().split('\n')


def operand(line):
    """The operand of a source line (no label, mnemonic, comment or strings), and
    the mnemonic."""
    code = line.split(';')[0]
    if code.startswith('*'):
        return '', ''
    if code[:1].isspace() or not code:
        parts = code.split(None, 1)
    else:
        parts = code.split(None, 2)[1:]
    if not parts:
        return '', ''
    mnem = parts[0]
    rest = parts[1] if len(parts) > 1 else ''
    rest = re.sub(r'"[^"]*"', '', rest)
    if mnem.upper() in ('FCC', 'FCN', 'FCS', 'INCLUDE', 'ERROR', 'WARNING'):
        rest = ''
    return mnem, rest


def main():
    fix = '--fix' in sys.argv
    files = [MAIN] + list(REGIONS)
    src = {f: read(f) for f in files}
    where = {}                 # label -> (region, file, line), code/data labels only
    for f in files:
        region = REGIONS.get(f, 'CORE')
        for i, line in enumerate(src[f]):
            m = LABEL.match(line)
            if not m or line.startswith(';'):
                continue
            if VALUE.match(line[m.end():]):
                continue       # a value or a variable (the variables are all the core's)
            where.setdefault(m.group(1), (region, f, i + 1))
    stubs = {}                 # name -> its stub's overlay
    m = src[MAIN]
    for i, line in enumerate(m):
        s = LABEL.match(line)
        if s and s.group(1).startswith('O_') and 'JSR  OVCALL' in line:
            stubs[s.group(1)[2:]] = m[i + 1].split()[-1]
    # (the lines that may name the overlays' labels: the stubs, and the lengths)
    exempt = set()
    for i, line in enumerate(m):
        if line.startswith('O_') or line.startswith('OVLEN') or re.match(r'^[A-Z]+END\s+equ', line):
            exempt.add(i)
            if line.startswith('O_'):
                exempt.update((i + 1, i + 2))
    problems = []
    used = set()
    for f in files:
        region = REGIONS.get(f, 'CORE')
        changed = False
        for i, line in enumerate(src[f]):
            if f == MAIN and i in exempt:
                continue
            mnem, rest = operand(line)
            for tok in TOKEN.findall(rest):
                if tok.startswith('O_') and tok[2:] in stubs:
                    used.add(tok[2:])
                if tok not in where:
                    continue
                treg = where[tok][0]
                if treg == 'CORE' or treg == region:
                    continue
                if tok in stubs and CALLS.match(' ' + mnem + ' '):
                    if fix:
                        new = re.sub(r'\b' + tok + r'\b', 'O_' + tok, line, count=1)
                        src[f][i] = line = new
                        changed = True
                        used.add(tok)
                        continue
                problems.append('%s:%d: %s (%s) names %s, in %s%s' % (
                    f, i + 1, region, line.strip(), tok, treg,
                    ' -- its stub: O_' + tok if tok in stubs else ' -- and it has no stub'))
        if changed:
            open(os.path.join(KIT, f), 'w', encoding='utf-8', newline='\n').write('\n'.join(src[f]))
    for name in sorted(set(stubs) - used):
        problems.append('%s: the stub O_%s is not used' % (MAIN, name))
    for name, ov in sorted(stubs.items()):
        if name not in where:
            problems.append('%s: the stub O_%s calls %s, which is nowhere' % (MAIN, name, name))
        elif where[name][0] != ov:
            problems.append('%s: the stub O_%s says %s, but %s is in %s' % (MAIN, name, ov, name, where[name][0]))
    for p in problems:
        print(p)
    print('%d problem%s' % (len(problems), '' if len(problems) == 1 else 's'))
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
