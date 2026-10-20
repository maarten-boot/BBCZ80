#!/usr/bin/env python3
"""Differential test of the 68k BBC BASIC against the Z80 original.

	bascheck.py [-k] [-n] [-t SECS] [TEST ...]

Each TEST is a file of lines typed at the BASIC prompt (default: all of
test/bas/*.in).  The Z80 reference output comes from bin/cpm/BBCBASIC.COM
under RunCPM (tools/runcpm.py) and is cached as test/bas/NAME.ref (delete it
to regenerate), or is NAME.exp if there is one (written by hand, for
68k-only features such as the 68000 assembler).  The 68k output comes from bbcbasic under Minix in r68k
(tools/runminix.py), all tests in one boot, as "bbcbasic < test".  The
68k transcript has the prompt and echoed input ('>' lines), which are
dropped before comparing.  -t is the time limit per test (default 60 s).
A test line "#file PATH" (PATH relative to the test file) is not typed:
the file is copied, under its own name, to the CP/M drive and to the
directory in which the 68k test runs (/usr/bas).  The machine has 2 MB
(R68K_RAM, unless set): with 1 MB the root image has little room.  The
tests are split over several boots, each with at most BUDGET bytes of
#file files.
-k keeps the 68k outputs as build/bas/NAME.out; -n only prints them (no
Z80 reference, for 68k-only things such as the assembler).
Exit status 1 if any test differs.
"""

import argparse
import difflib
import glob
import os
import re
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.dirname(HERE)
TOP = os.path.dirname(SRC)


WORK = os.path.join(TOP, 'build', 'bas')
BUDGET = 65536


def parse(test):
    """(typed lines, [host paths of #file files])"""
    lines, files = [], []
    with open(test, 'rb') as f:
        for l in f.read().decode('latin-1').split('\n'):
            if l.startswith('#file '):
                files.append(os.path.normpath(os.path.join(
                    os.path.dirname(test), l[6:].strip())))
            else:
                lines.append(l)
    while lines and lines[-1] == '':
        lines.pop()
    return lines, files


def reference(test):
    exp = test[:-3] + '.exp'
    if os.path.exists(exp):
        ref = exp
    else:
        ref = test[:-3] + '.ref'
    if not os.path.exists(ref):
        lines, files = parse(test)
        drive = os.path.join(TOP, 'build', 'cpm', 'A', '0')
        os.makedirs(drive, exist_ok=True)
        for p in files:
            shutil.copy(p, os.path.join(drive, os.path.basename(p)))
        os.makedirs(WORK, exist_ok=True)
        inp = os.path.join(WORK, os.path.basename(test) + '.cpm')
        with open(inp, 'w', encoding='latin-1') as f:
            f.write('\n'.join(lines) + '\n')
        out = subprocess.run([sys.executable, os.path.join(HERE, 'runcpm.py'),
                              inp], capture_output=True, check=True).stdout
        with open(ref, 'wb') as f:
            f.write(out)
    with open(ref, 'rb') as f:
        return f.read().decode('latin-1').replace('\r', '').split('\n')


def run68k(tests, secs):
    os.makedirs(WORK, exist_ok=True)
    args = [sys.executable, os.path.join(HERE, 'runminix.py'), '-t', str(secs),
            '-f', '/usr/bin/bbcbasic=' + os.path.join(SRC, 'bbcbasic')]
    cmds = ['mkdir -p /usr/bas; cd /usr/bas']
    have = set()
    for i, t in enumerate(tests):
        lines, files = parse(t)
        inp = os.path.join(WORK, os.path.basename(t))
        with open(inp, 'w', encoding='latin-1') as g:
            g.write('\n'.join(lines) + '\n*BYE\n')
        args += ['-f', '/usr/t%d.in=%s' % (i, inp)]
        for p in files:
            name = os.path.basename(p)
            if name not in have:
                have.add(name)
                args += ['-f', '/usr/bas/%s=%s' % (name, p)]
        cmds.append('echo ==T%d==; bbcbasic < /usr/t%d.in' % (i, i))
    env = dict(os.environ)
    env.setdefault('R68K_RAM', '2M')
    out = subprocess.run(args + cmds, capture_output=True, env=env).stdout
    text = out.decode('latin-1').replace('\r', '')
    res = {}
    for i, t in enumerate(tests):
        m = re.search(r'\n==T%d==\n(.*?)(?=\n# |\Z)' % i, text, re.S)
        res[t] = m.group(1) if m else ('(no output)\n' +
                                       '\n'.join(text.split('\n')[-12:]))
    return res


def groups(tests):
    """Split the tests into boots by the size of their #file files."""
    out, cur, size = [], [], 0
    for t in tests:
        n = sum(os.path.getsize(p) for p in parse(t)[1])
        if cur and size + n > BUDGET:
            out.append(cur)
            cur, size = [], 0
        cur.append(t)
        size += n
    if cur:
        out.append(cur)
    return out


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
    ap.add_argument('-n', action='store_true')
    ap.add_argument('-t', type=int, default=60)
    ap.add_argument('tests', nargs='*')
    a = ap.parse_args()
    tests = a.tests or sorted(glob.glob(os.path.join(SRC, 'test', 'bas',
                                                     '*.in')))
    refs = {} if a.n else {t: reference(t) for t in tests}
    got = {}
    for g in groups(tests):
        got.update(run68k(g, a.t))
    bad = 0
    for t in tests:
        g = clean68k(got[t])
        if a.n:
            print('\n'.join(g))
            continue
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
