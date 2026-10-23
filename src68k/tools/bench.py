#!/usr/bin/env python3
"""Benchmarks of the 68k BBC BASIC: 68000 cycles and where they go.

	bench.py [-l LABEL] [-n TOP] [BENCH ...]

Each BENCH (default test/bench/*.bas) is a BASIC program that writes 1
to the byte at &FFFFF0 before its timed part and 2 after it.  All of
them run in one boot of Minix under the profiling r68k: build/r68kprof,
a copy of r68k with mboot/patches/r68k-0002-cycle-profiler.patch applied
(it counts the cycles per instruction address), R68K_RAM=2M.  To make it:
	mkdir -p build/r68kprof && (cd ../r68k && git ls-files | tar cf - -T -)
	    | tar xf - -C build/r68kprof && cd build/r68kprof &&
	    patch -p1 < ../../mboot/patches/r68k-0002-cycle-profiler.patch &&
	    make r68k  The addresses are mapped to
bbcbasic's routines with the symbols of an unconverted link (ack.out,
anm); bbcbasic's load address is ^@% minus STAVAR.  The report gives per
benchmark the cycles, the instructions, the share outside bbcbasic (the
kernel: clock interrupts) and the TOP routines; with -l LABEL it is also
saved as build/prof/LABEL.txt (cycles per benchmark, for comparisons).
"""

import argparse
import glob
import os
import re
import subprocess
import sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.dirname(HERE)
TOP = os.path.dirname(SRC)
MINIX = os.environ.get('MINIX', os.path.join(os.path.dirname(TOP),
                                             'minix-st-2.0.4'))
ACK = os.path.join(MINIX, 'src', 'rosco', 'ack')
STAGE = os.path.join(ACK, 'ack', '.obj', 'staging')
PROF = os.path.join(TOP, 'build', 'prof')
EMU = os.path.join(TOP, 'build', 'r68kprof', 'r68k')
OBJS = ('data.o main.o exec.o exec2.o eval.o asmb.o math.o minix.o osl.o '
        'hook.o').split()			# data.o first: see the Makefile


def symbols():
    """Text symbols of bbcbasic: sorted [(address, name)], and STAVAR."""
    out = os.path.join(PROF, 'bbcbasic.out')
    lib = os.path.join(ACK, 'lib')
    plat = os.path.join(STAGE, 'share', 'ack', 'minix68k')
    subprocess.run([os.path.join(ACK, 'acc'), '-c.out', '-o', out,
                    os.path.join(lib, 'crtso.o'), os.path.join(lib, 'emrts.o')]
                   + [os.path.join(SRC, o) for o in OBJS] +
                   [os.path.join(lib, 'libc.a'), os.path.join(plat, 'libem.a'),
                    os.path.join(plat, 'libend.a')], check=True)
    env = dict(os.environ, ACKDIR=STAGE)
    lines = subprocess.run([os.path.join(STAGE, 'bin', 'anm'), '-n', out],
                           capture_output=True, text=True, env=env,
                           check=True).stdout.split('\n')
    text, stavar = {}, None
    for l in lines:
        w = l.split()
        if len(w) != 4:
            continue
        v, sect, name = int(w[0], 16), w[1], w[3]
        if name == 'STAVAR':
            stavar = v
        if sect == '0' and not name.startswith('.'):
            text.setdefault(v, name)
    return sorted(text.items()), stavar


def find(syms, off):
    lo, hi = 0, len(syms) - 1
    if off < syms[0][0]:
        return '?'
    while lo < hi:
        mid = (lo + hi + 1) // 2
        if syms[mid][0] <= off:
            lo = mid
        else:
            hi = mid - 1
    return syms[lo][1]


def run(benches):
    os.makedirs(PROF, exist_ok=True)
    pfile = os.path.join(PROF, 'run.prof')
    if os.path.exists(pfile):
        os.remove(pfile)
    args = [sys.executable, os.path.join(HERE, 'runminix.py'), '-t', '600',
            '-e', EMU, '-f', '/usr/bin/bbcbasic=' + os.path.join(SRC,
                                                                'bbcbasic')]
    cmds = []
    for i, b in enumerate(benches):
        inp = os.path.join(PROF, 'b%d.in' % i)
        with open(b) as f, open(inp, 'w') as g:
            g.write(f.read().rstrip('\n') + '\nRUN\nPRINT ~^@%\n*BYE\n')
        args += ['-f', '/usr/b%d.in=%s' % (i, inp)]
        cmds.append('bbcbasic < /usr/b%d.in' % i)
    env = dict(os.environ, R68K_RAM='2M', R68K_PROF=pfile)
    out = subprocess.run(args + cmds, capture_output=True, env=env
                         ).stdout.decode('latin-1').replace('\r', '')
    with open(os.path.join(PROF, 'run.out'), 'w') as f:
        f.write(out)
    bases = [int(m, 16) for m in re.findall(r'\n>PRINT ~\^@%\n *([0-9A-F]+)',
                                            out)]
    runs, cur = [], None
    with open(pfile) as f:
        for l in f:
            if l.startswith('#'):
                w = l.split()
                cur = {'cycles': int(w[4]), 'insns': int(w[6]), 'pc': {}}
                runs.append(cur)
            else:
                pc, c, n = l.split()
                cur['pc'][int(pc, 16)] = (int(c), int(n))
    return runs, bases, out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('-l', default='')
    ap.add_argument('-n', type=int, default=12)
    ap.add_argument('benches', nargs='*')
    a = ap.parse_args()
    benches = a.benches or sorted(glob.glob(os.path.join(SRC, 'test', 'bench',
                                                         '*.bas')))
    if not os.path.exists(EMU):
        sys.exit('bench: build the profiling r68k first (build/r68kprof)')
    syms, stavar = symbols()
    size = max(v for v, _ in syms) + 0x1000
    runs, bases, out = run(benches)
    if len(runs) != len(benches) or len(bases) != len(benches):
        sys.exit('bench: %d benchmarks, %d profiles, %d bases; see '
                 'build/prof/run.out' % (len(benches), len(runs), len(bases)))
    report = []
    total = 0
    for b, r, base in zip(benches, runs, bases):
        base -= stavar
        per = defaultdict(int)
        other = 0
        for pc, (c, n) in r['pc'].items():
            off = pc - base
            if 0 <= off < size:
                per[find(syms, off)] += c
            else:
                other += c
        name = os.path.basename(b)[:-4]
        total += r['cycles']
        report.append('%-10s %11d cycles %10d instructions  %.1f cycles/insn'
                      '  outside bbcbasic %.1f%%' %
                      (name, r['cycles'], r['insns'],
                       r['cycles'] / max(r['insns'], 1),
                       100.0 * other / max(r['cycles'], 1)))
        for f, c in sorted(per.items(), key=lambda x: -x[1])[:a.n]:
            report.append('    %-12s %5.1f%%' % (f, 100.0 * c / r['cycles']))
    report.append('%-10s %11d cycles' % ('total', total))
    text = '\n'.join(report)
    print(text)
    if a.l:
        with open(os.path.join(PROF, a.l + '.txt'), 'w') as f:
            f.write(text + '\n')


main()
