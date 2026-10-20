#!/usr/bin/env python3
"""Differential test of the 68k BBC BASIC against the Z80 original.

	bascheck.py [-k] [-t SECS] [TEST ...]

Each TEST is a file of lines typed at the BASIC prompt (default: all of
test/bas/*.in).  The Z80 reference output comes from bin/cpm/BBCBASIC.COM
under RunCPM (tools/runcpm.py) and is cached as test/bas/NAME.ref (delete it
to regenerate).  The 68k output comes from bbcbasic under Minix in r68k
(tools/runminix.py), all tests in one boot, as "bbcbasic < test".  The
68k transcript has the prompt and echoed input ('>' lines), which are
dropped before comparing.  -t is the time limit per test (default 60 s).
-k keeps the 68k outputs as build/bas/NAME.out.
Exit status 1 if any test differs.
"""

import argparse
import difflib
import glob
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.dirname(HERE)
TOP = os.path.dirname(SRC)


def reference(test):
    ref = test[:-3] + '.ref'
    if not os.path.exists(ref):
        out = subprocess.run([sys.executable, os.path.join(HERE, 'runcpm.py'),
                              test], capture_output=True, check=True).stdout
        with open(ref, 'wb') as f:
            f.write(out)
    with open(ref, 'rb') as f:
        return f.read().decode('latin-1').replace('\r', '').split('\n')


def run68k(tests, secs):
    work = os.path.join(TOP, 'build', 'bas')
    os.makedirs(work, exist_ok=True)
    args = [sys.executable, os.path.join(HERE, 'runminix.py'), '-t', str(secs),
            '-f', '/usr/bin/bbcbasic=' + os.path.join(SRC, 'bbcbasic')]
    cmds = []
    for i, t in enumerate(tests):
        inp = os.path.join(work, os.path.basename(t))
        with open(t, 'rb') as f, open(inp, 'wb') as g:
            g.write(f.read().rstrip(b'\n') + b'\n*BYE\n')
        args += ['-f', '/usr/t%d.in=%s' % (i, inp)]
        cmds.append('echo ==T%d==; bbcbasic < /usr/t%d.in' % (i, i))
    out = subprocess.run(args + cmds, capture_output=True).stdout
    text = out.decode('latin-1').replace('\r', '')
    res = {}
    for i, t in enumerate(tests):
        m = re.search(r'\n==T%d==\n(.*?)(?=\n# |\Z)' % i, text, re.S)
        res[t] = m.group(1) if m else '(no output)\n' + text[-2000:]
    return res


def clean68k(text):
    lines = text.split('\n')
    # drop the banner (2 lines), the prompt/echo lines and the final *BYE
    if lines and lines[0].startswith('BBC BASIC'):
        lines = lines[2:]
    out = []
    for l in lines:
        if l.startswith('>'):
            continue
        out.append(l)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('-k', action='store_true')
    ap.add_argument('-t', type=int, default=60)
    ap.add_argument('tests', nargs='*')
    a = ap.parse_args()
    tests = a.tests or sorted(glob.glob(os.path.join(SRC, 'test', 'bas',
                                                     '*.in')))
    refs = {t: reference(t) for t in tests}
    got = run68k(tests, a.t)
    bad = 0
    for t in tests:
        g = clean68k(got[t])
        if a.k:
            with open(os.path.join(TOP, 'build', 'bas',
                                   os.path.basename(t)[:-3] + '.out'),
                      'w') as f:
                f.write('\n'.join(g))
        r = [l for l in refs[t]]
        while r and r[-1] == '':
            r.pop()
        while g and g[-1] == '':
            g.pop()
        name = os.path.basename(t)
        if r == g:
            print('ok   ', name)
        else:
            bad += 1
            print('FAIL ', name)
            for l in difflib.unified_diff(r, g, 'z80', '68k', lineterm='',
                                          n=1):
                print('     ', l)
    print('%d of %d failed' % (bad, len(tests)))
    sys.exit(1 if bad else 0)


main()
