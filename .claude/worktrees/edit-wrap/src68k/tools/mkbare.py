#!/usr/bin/env python3
"""Build BBC BASIC 68k for a bare rosco_m68k (no Minix): build/bare.

	mkbare.py [-m MINIX] [--demo] [-f FILE ...] [-w WORK] [-o OUT]

The interpreter's objects (make bbcbasic) with osl.c compiled -DBARE and
bare/bare.c (console, timer, RAM files) and bare/fat.c (files on the SD
card) under it, bare/start.s first,
linked by the ACK's em_led at 0x40000, where the firmware loads
ROSCODE1.BIN and starts it; aslod makes the flat binary of it.
--demo builds in the demo programs (demo/progs, tokenised as mkdemo.py
does) as files in the RAM store, and runs CHAIN "menu" at the start;
-f FILE puts FILE (a host path) in the store under its own name.  WORK is
the directory for the objects (default build/bare, build/bare/demo).
The result is build/bare/ROSCODE1.BIN (with --demo build/bare/demo/
ROSCODE1.BIN), or OUT.
"""

import argparse
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.dirname(HERE)
TOP = os.path.dirname(SRC)
OBJS = 'main.o exec.o exec2.o eval.o asmb.o math.o minix.o data.o hook.o'.split()
LOAD = 0x40000


def seeds(path, files, autorun):
    """seeds.c: the files the image brings along (bare.c bare_seeds)."""
    out = ['/* made by tools/mkbare.py: files in the RAM store at the start */',
           'struct seed { char *name; char *data; long size; };']
    for i, (name, data) in enumerate(files):
        rows = [', '.join('%d' % b for b in data[j:j + 20])
                for j in range(0, len(data), 20)]
        out.append('static char d%d[] = {\n\t%s\n};' % (i, ',\n\t'.join(rows) or '0'))
    out.append('struct seed bare_seeds[] = {')
    for i, (name, data) in enumerate(files):
        out.append('\t{ "%s", d%d, %dL },' % (name, i, len(data)))
    out.append('\t{ 0, 0, 0L }\n};')
    out.append('char *bare_autorun = %s;' % ('"%s"' % autorun if autorun else '0'))
    with open(path, 'w') as f:
        f.write('\n'.join(out) + '\n')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('-m', default=os.environ.get(
        'MINIX', os.path.join(os.path.dirname(TOP), 'minix-st-2.0.4')))
    ap.add_argument('--demo', action='store_true')
    ap.add_argument('-f', action='append', default=[])
    ap.add_argument('-w', default='')
    ap.add_argument('-o', default='')
    a = ap.parse_args()
    ack = os.path.join(os.path.abspath(a.m), 'src', 'rosco', 'ack')
    stage = os.path.join(ack, 'ack', '.obj', 'staging')
    plat = os.path.join(stage, 'share', 'ack', 'minix68k')
    work = a.w or os.path.join(TOP, 'build', 'bare', 'demo' if a.demo else '')
    os.makedirs(work, exist_ok=True)

    subprocess.run(['make', '-s'] + OBJS, cwd=SRC, check=True)
    acc = os.path.join(ack, 'acc-minix')

    def cc(src, obj, *flags):
        subprocess.run([acc, '-c', '-DBARE'] + list(flags) + ['-o', obj, src],
                       cwd=SRC, check=True)
        return obj

    files = []
    if a.demo:
        progs = os.path.join(TOP, 'build', 'demo', 'progs')
        if not os.path.isdir(progs):
            sys.exit('mkbare: no %s (make demo first)' % progs)
        for f in sorted(os.listdir(progs)):
            files.append((f, open(os.path.join(progs, f), 'rb').read()))
        for f in sorted(os.listdir(os.path.join(SRC, 'demo', 'progs'))):
            files.append((f, open(os.path.join(SRC, 'demo', 'progs', f), 'rb').read()))
    for f in a.f:
        files.append((os.path.basename(f), open(f, 'rb').read()))
    seeds(os.path.join(work, 'seeds.c'), files, 'menu' if a.demo else None)

    objs = [cc('bare/start.s', os.path.join(work, 'start.o'))]
    objs += [os.path.join(SRC, o) for o in OBJS]
    objs.append(cc('osl.c', os.path.join(work, 'osl.o')))
    objs.append(cc('bare/bare.c', os.path.join(work, 'bare.o')))
    objs.append(cc('bare/fat.c', os.path.join(work, 'fat.o')))
    objs.append(cc(os.path.join(work, 'seeds.c'), os.path.join(work, 'seeds.o')))
    out = os.path.join(work, 'bbcbasic.out')
    env = dict(os.environ, ACKDIR=stage)
    subprocess.run([os.path.join(stage, 'lib', 'ack', 'em_led'),
                    '-a0:4', '-a1:4', '-a2:4', '-a3:4', '-b0:0x%x' % LOAD,
                    '-o', out] + objs +
                   [os.path.join(ack, 'lib', 'emrts.o'), os.path.join(ack, 'lib', 'libc.a'),
                    os.path.join(plat, 'libem.a'), os.path.join(plat, 'libend.a')],
                   check=True, env=env)
    binf = a.o or os.path.join(work, 'ROSCODE1.BIN')
    subprocess.run([os.path.join(stage, 'bin', 'aslod'), out, binf], check=True, env=env)
    print('%s: %d bytes' % (binf, os.path.getsize(binf)), file=sys.stderr)


if __name__ == '__main__':
    main()
