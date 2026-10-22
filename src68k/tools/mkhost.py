#!/usr/bin/env python3
"""Build BBC BASIC as a program for the PC: build/host/windows/bbc68k.exe
(MinGW-w64) and build/host/linux/bbc68k.

	mkhost.py [-r R68K_DIR] [--windows] [--linux]

One static executable each (src68k/host/README.md): r68k (its tracked
sources, R68K_DIR, default ../r68k next to this repository) with
web/r68k-web.patch (Duart.cpp: the console, R68K_HOSTED),
host/hostmain.cpp in place of main() (main.cpp compiled with main and
illegal_instruction_handler renamed) and host/hostfs.cpp (the host's
files for BASIC), and built in: the firmware (R68K_DIR/firmware) and bare
BBC BASIC with the demo programs (build/bare/demo/ROSCODE1.BIN, make bare)
as images.h.  For Windows, host/compat has the POSIX headers r68k wants.
Without --windows or --linux both are made.
"""

import argparse
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.dirname(HERE)
TOP = os.path.dirname(SRC)
HOST = os.path.join(SRC, 'host')
WORK = os.path.join(TOP, 'build', 'host')
TARGETS = {
    'linux': {'cc': 'gcc', 'cxx': 'g++', 'out': 'bbc68k', 'flags': [],
              'ldflags': ['-static', '-pthread']},
    'windows': {'cc': 'x86_64-w64-mingw32-gcc-posix', 'cxx': 'x86_64-w64-mingw32-g++-posix',
                'out': 'bbc68k.exe', 'flags': ['-I' + os.path.join(HOST, 'compat')],
                'ldflags': ['-static', '-lws2_32']},
}
CSRC = ['musashi/m68kcpu.c', 'musashi/m68kdasm.c', 'musashi/m68kops.c',
        'musashi/softfloat/softfloat.c']
CXXSRC = ['machine/AddressDecoder.cpp', 'machine/Duart.cpp', 'machine/Memory.cpp',
          'rosco_m68k_glue/cpuglue.cpp', 'rosco_m68k_glue/memoryglue.cpp']


def sources(r68k):
    """r68k's tracked sources with the patch, and m68kops.c generated."""
    src = os.path.join(WORK, 'r68k-src')
    if os.path.exists(src):
        shutil.rmtree(src)
    for f in subprocess.run(['git', 'ls-files'], cwd=r68k, check=True,
                            capture_output=True, text=True).stdout.split():
        os.makedirs(os.path.dirname(os.path.join(src, f)), exist_ok=True)
        shutil.copy(os.path.join(r68k, f), os.path.join(src, f))
    subprocess.run(['patch', '-s', '-p1', '-i', os.path.join(SRC, 'web', 'r68k-web.patch')],
                   cwd=src, check=True)
    subprocess.run(['make', '-C', 'musashi', 'm68kops.c'], cwd=src, check=True,
                   stdout=subprocess.DEVNULL)
    return src


def images(r68k, path):
    """images.h: the firmware and BBC BASIC as C arrays."""
    def array(name, data):
        rows = [','.join(str(b) for b in data[i:i + 24]) for i in range(0, len(data), 24)]
        return 'static const unsigned char %s[] = {\n%s\n};\n' % (name, ',\n'.join(rows))
    basic = os.path.join(TOP, 'build', 'bare', 'demo', 'ROSCODE1.BIN')
    if not os.path.exists(basic):
        sys.exit('mkhost: no %s (make bare first)' % basic)
    with open(path, 'w') as f:
        f.write('/* made by tools/mkhost.py: the rosco_m68k firmware and bare BBC BASIC */\n')
        f.write(array('rom_image', open(os.path.join(r68k, 'firmware', 'rosco_m68k.rom'), 'rb').read()))
        f.write(array('basic_image', open(basic, 'rb').read()))


def build(target, src):
    t = TARGETS[target]
    out = os.path.join(WORK, target)
    obj = os.path.join(out, 'obj')
    os.makedirs(obj, exist_ok=True)
    cflags = ['-O2'] + t['flags']
    cxxflags = cflags + ['-std=c++20', '-DR68K_HOSTED', '-I' + os.path.join(src, 'include'),
                         '-I' + src, '-I' + WORK]
    jobs = [[t['cc']] + cflags + ['-c', os.path.join(src, f)] for f in CSRC]
    jobs += [[t['cxx']] + cxxflags + ['-c', os.path.join(src, f)] for f in CXXSRC]
    jobs.append([t['cxx']] + cxxflags + ['-Dmain=r68k_native_main',
                 '-Dillegal_instruction_handler=r68k_illegal', '-c', os.path.join(src, 'main.cpp')])
    jobs += [[t['cxx']] + cxxflags + ['-c', os.path.join(HOST, f)]
             for f in ('hostfs.cpp', 'hostmain.cpp')]
    procs, objs = [], []
    for j in jobs:
        o = os.path.join(obj, os.path.splitext(os.path.basename(j[-1]))[0] + '.o')
        objs.append(o)
        procs.append(subprocess.Popen(j + ['-o', o]))
    if any(p.wait() for p in procs):
        sys.exit('mkhost: compiling for %s failed' % target)
    exe = os.path.join(out, t['out'])
    subprocess.run([t['cxx']] + objs + t['ldflags'] + ['-o', exe], check=True)
    strip = t['cxx'].replace('g++-posix', 'strip').replace('g++', 'strip')
    subprocess.run([strip, exe], check=True)
    print('%s: %d bytes' % (exe, os.path.getsize(exe)))
    return exe


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('-r', default=os.path.join(os.path.dirname(TOP), 'r68k'))
    ap.add_argument('--windows', action='store_true')
    ap.add_argument('--linux', action='store_true')
    a = ap.parse_args()
    r68k = os.path.abspath(a.r)
    targets = [t for t in ('linux', 'windows') if getattr(a, t)] or ['linux', 'windows']
    os.makedirs(WORK, exist_ok=True)
    src = sources(r68k)
    images(r68k, os.path.join(WORK, 'images.h'))
    for t in targets:
        build(t, src)


if __name__ == '__main__':
    main()
