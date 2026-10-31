#!/usr/bin/env python3
"""Where bare BBC BASIC spends its 68000 cycles: interpreter, C, library.

	bareprof.py [-l LABEL] [-n TOP] [BENCH ...]

Each BENCH (default test/bench/*.bas) is a BASIC program that writes 1
to the byte at &FFFFF0 before its timed part and 2 after it; after them
come three of its own: console output, and a file written and read back
in the RAM store and on the SD card.  All run in one boot of the bare
image (tools/mkbare.py, in build/prof/bare) under the profiling r68k,
build/r68kprof (see bench.py; make it from r68k with
mboot/patches/r68k-0002-cycle-profiler.patch, and copy r68k's
firmware/rosco_m68k.rom into it), R68K_RAM=5M, with a FAT16 card made by
the Minix tree's mkfat.py.  The cycles are split by the objects of the
link: the interpreter (the .s files), C (osl.c, bare.c, fat.c) and the
ACK library; for each benchmark the TOP routines follow (from 0.5%).  With -l LABEL the report is also saved as build/prof/LABEL.txt.
"""

import argparse
import bisect
import glob
import os
import pty
import re
import select
import subprocess
import sys
import time
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.dirname(HERE)
TOP = os.path.dirname(SRC)
MINIX = os.path.abspath(os.environ.get('MINIX', os.path.join(os.path.dirname(TOP),
                                                             'minix-st-2.0.4')))
STAGE = os.path.join(TOP, 'build', 'ack', 'dist')	# the ACK (tools/getack.sh)
PROF = os.path.join(TOP, 'build', 'prof')
WORK = os.path.join(PROF, 'bare')
EMU = os.path.join(TOP, 'build', 'r68kprof', 'r68k')
OBJS = 'data.o main.o exec.o exec2.o eval.o asmb.o math.o minix.o hook.o'.split()
GROUPS = ('interp', 'C', 'lib', 'start')

OWN = r'''
10 REM console
20 ?&FFFFF0=1
30 FOR I%=1 TO 300:PRINT "line ";I%;" of some text for the console":NEXT
40 ?&FFFFF0=2
RUN
NEW
'''
FILE = r'''
10 REM %s
20 ?&FFFFF0=1
30 F%%=OPENOUT "%s:PROF":FOR I%%=1 TO 2000:PRINT#F%%,I%%,"abc":BPUT#F%%,65:NEXT:CLOSE#F%%
40 F%%=OPENIN "%s:PROF":REPEAT:INPUT#F%%,A,A$:B%%=BGET#F%%:UNTIL EOF#F%%:CLOSE#F%%
50 ?&FFFFF0=2
RUN
NEW
'''


def anm(path):
    """the text symbols of an ACK object or a.out: [(value, name)]"""
    out = subprocess.run([os.path.join(STAGE, 'bin', 'anm'), '-n', path],
                         env=dict(os.environ, ACKDIR=STAGE), capture_output=True,
                         text=True, check=True).stdout
    syms = []
    for l in out.split('\n'):
        w = l.split()
        if len(w) == 4 and w[1] == '0' and w[3] != '(NULL)':
            syms.append((int(w[0], 16), w[3]))
    return syms


def layout():
    """[(start, group)] of the link, and its symbols [(address, name)]"""
    syms = sorted(anm(os.path.join(WORK, 'bbcbasic.out')))
    where = dict((n, v) for v, n in syms)
    objs = [('start', os.path.join(WORK, 'start.o'))]
    objs += [('interp', os.path.join(SRC, o)) for o in OBJS]
    objs += [('C', os.path.join(WORK, o)) for o in ('osl.o', 'bare.o', 'fat.o', 'seeds.o')]
    objs.append(('lib', os.path.join(TOP, 'build', 'ack', 'minixlib', 'emrts.o')))	# and the libraries
    parts = []
    for group, path in objs:
        for v, n in anm(path):
            if n in where:			# the object's place in the link
                parts.append((where[n] - v, group))
                break
    return sorted(parts), syms


def card():
    fat = os.path.join(WORK, 'fat.img')
    for f in (fat, os.path.join(WORK, 'rosco_sd.bin')):
        if os.path.exists(f):
            os.remove(f)
    tools = os.path.join(MINIX, 'src', 'rosco', 'tools')
    subprocess.run([sys.executable, os.path.join(tools, 'mkfat.py'), '-s', '65536',
                    '-o', '2048', fat, os.path.join(TOP, 'tests', 'FORTEST.BBC')],
                   check=True, stdout=subprocess.DEVNULL)
    subprocess.run([sys.executable, os.path.join(tools, 'mksd.py'),
                    os.path.join(WORK, 'rosco_sd.bin'), '06:' + fat],
                   check=True, stdout=subprocess.DEVNULL)


def run(lines):
    """type the lines at bare BASIC's prompt; the profile's runs"""
    pfile = os.path.join(PROF, 'bare.prof')
    if os.path.exists(pfile):
        os.remove(pfile)
    fd, slave = pty.openpty()
    sin = os.open(os.ttyname(slave), os.O_RDWR)
    p = subprocess.Popen([EMU, '-d', os.path.join(WORK, 'ROSCODE1.BIN')], stdin=sin,
                         stdout=slave, stderr=subprocess.DEVNULL, cwd=WORK,
                         env=dict(os.environ, R68K_RAM='5M', R68K_PROF=pfile))
    os.close(slave)
    os.close(sin)
    buf = [b'']

    def until(pattern, limit):
        end = time.time() + limit
        while True:
            m = re.search(pattern, buf[0])
            if m:
                out, buf[0] = buf[0][:m.end()], buf[0][m.end():]
                return out
            r, _, _ = select.select([fd], [], [], max(0, end - time.time()))
            if not r:
                raise TimeoutError
            buf[0] += os.read(fd, 65536)

    out = b''
    try:
        until(rb'\n>', 30)
        for l in lines:
            for c in (l + '\r').encode('latin-1'):
                os.write(fd, bytes([c]))
            out += until(rb'(^|\n)>', 600)
    except TimeoutError:
        out += buf[0] + b'\n(timeout)'
    finally:
        p.kill()
        p.wait()
    with open(os.path.join(PROF, 'bare.out'), 'wb') as f:
        f.write(out)
    runs, cur = [], None
    if os.path.exists(pfile):
        for l in open(pfile):
            if l.startswith('#'):
                cur = {'cycles': int(l.split()[4]), 'pc': {}}
                runs.append(cur)
            else:
                pc, c, n = l.split()
                cur['pc'][int(pc, 16)] = int(c)
    return runs


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('-l', default='')
    ap.add_argument('-n', type=int, default=6)
    ap.add_argument('benches', nargs='*')
    a = ap.parse_args()
    if not os.path.exists(EMU):
        sys.exit('bareprof: build the profiling r68k first (build/r68kprof)')
    benches = a.benches or sorted(glob.glob(os.path.join(SRC, 'test', 'bench', '*.bas')))
    os.makedirs(WORK, exist_ok=True)
    subprocess.run([sys.executable, os.path.join(HERE, 'mkbare.py'), '-w', WORK],
                   check=True)
    card()
    lines, names = [], []
    for b in benches:
        lines += open(b).read().split('\n') + ['RUN', 'NEW']
        names.append(os.path.basename(b)[:-4])
    lines += OWN.split('\n')
    names.append('console')
    for store in ('ram', 'sd'):
        lines += (FILE % (store, store, store)).split('\n')
        names.append(store + 'file')
    lines = [l for l in lines if l.strip()]
    runs = run(lines)
    if len(runs) != len(names):
        sys.exit('bareprof: %d programs, %d profiles; see build/prof/bare.out'
                 % (len(names), len(runs)))
    parts, syms = layout()
    starts = [s for s, _ in parts]
    addrs = [v for v, _ in syms]
    end = syms[-1][0] + 0x1000
    report = ['%-10s %11s %7s %7s %7s %7s %7s' % (('', 'cycles') + GROUPS + ('other',))]
    for name, r in zip(names, runs):
        per, fn = defaultdict(int), defaultdict(int)
        for pc, c in r['pc'].items():
            i = bisect.bisect_right(starts, pc) - 1
            if i < 0 or pc > end:
                per['other'] += c		# the firmware
                continue
            group = parts[i][1]
            per[group] += c
            fn[(group, syms[bisect.bisect_right(addrs, pc) - 1][1])] += c
        t = max(r['cycles'], 1)
        report.append('%-10s %11d' % (name, r['cycles']) + ''.join(
            ' %6.1f%%' % (100.0 * per[g] / t) for g in GROUPS + ('other',)))
        for (group, f), c in sorted(fn.items(), key=lambda x: -x[1])[:a.n]:
            if c * 200 >= t:			# from 0.5%
                report.append('    %-6s %-14s %5.1f%%' % (group, f, 100.0 * c / t))
    text = '\n'.join(report)
    print(text)
    if a.l:
        with open(os.path.join(PROF, a.l + '.txt'), 'w') as f:
            f.write(text + '\n')


main()
