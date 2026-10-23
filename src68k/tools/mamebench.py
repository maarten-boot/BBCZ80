#!/usr/bin/env python3
"""Run the benchmarks on the MAME rosco-emulator (real hardware timing).

	mamebench.py [-b OLDBIN] [-k PROFILE]

The rosco-emulator (github.com/solderdemon/rosco-emulator, as the podman
image rosco-emulator built from its Dockerfile) emulates the rosco_m68k
Classic V2 with the 68010 and the real firmware.  An SD card image is made
in build/mame from the Minix tree's tools and proto files plus, as
/usr/bin/bbcbasic, this tree's interpreter and, with -b, OLDBIN as
/usr/bin/bbcold (e.g. a build of an earlier commit).  The kernel must
have the 115200 baud console of the emulator: build/mame/image-115200.bin
(make CONSBAUD=115200 boot/image.bin in the Minix tree, saved).  The
benchmarks (test/bench/*.bas) time themselves with TIME (emulated time:
the Minix clock runs off the emulated DUART timer) instead of the
profiler marks.  The times are compared with the r68k cycle counts of
build/prof/PROFILE.txt (bench.py -l) at 10 MHz.
"""

import argparse
import glob
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.dirname(HERE)
TOP = os.path.dirname(SRC)
MINIX = os.environ.get('MINIX', os.path.join(os.path.dirname(TOP),
                                             'minix-st-2.0.4'))
ROSCO = os.path.join(MINIX, 'src', 'rosco')
WORK = os.path.join(TOP, 'build', 'mame')


def sh(args, **kw):
    subprocess.run(args, check=True, **kw)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('-b', default='')
    ap.add_argument('-k', default='')
    a = ap.parse_args()
    files = os.path.join(WORK, 'files')
    os.makedirs(files, exist_ok=True)
    benches = sorted(glob.glob(os.path.join(SRC, 'test', 'bench', '*.bas')))
    proto = ['d /usr/bench 755',
             'f /usr/bin/bbcbasic 755 ' + os.path.join(SRC, 'bbcbasic')]
    bins = ['bbcbasic']
    if a.b:
        proto.append('f /usr/bin/bbcold 755 ' + os.path.abspath(a.b))
        bins.insert(0, 'bbcold')
    names = []
    for b in benches:
        name = os.path.basename(b)[:-4]
        names.append(name)
        text = open(b).read()
        text = text.replace('?&FFFFF0=1', 'W%=TIME')
        text = text.replace('?&FFFFF0=2', 'W%=TIME-W%:PRINT "TIME ";W%')
        p = os.path.join(files, name + '.in')
        with open(p, 'w') as f:
            f.write(text.rstrip('\n') + '\nRUN\n*BYE\n')
        proto.append('f /usr/bench/%s.in 644 %s' % (name, p))
    pfile = os.path.join(WORK, 'bench.proto')
    with open(pfile, 'w') as f:
        f.write('\n'.join(proto) + '\n')
    # the card: FAT (ROSCODE1.BIN without root image), Minix root
    rcode = os.path.join(WORK, 'ROSCODE1.BIN')
    sh([os.path.join(ROSCO, 'loader', 'mkrosco'), '-o', rcode,
        os.path.join(ROSCO, 'loader', 'loader.bin'),
        os.path.join(WORK, 'image-115200.bin')])
    fat = os.path.join(WORK, 'sdfat.img')
    root = os.path.join(WORK, 'sdroot.img')
    for f in (fat, root):
        if os.path.exists(f):
            os.remove(f)
    sh([sys.executable, os.path.join(ROSCO, 'tools', 'mkfat.py'), '-o', '2048',
        fat, rcode])
    # sdproto without the files that are not built (e.g. the test suite)
    boot = os.path.join(ROSCO, 'boot')
    sdp = os.path.join(WORK, 'sdproto')
    keep, drop = [], 0
    for l in open(os.path.join(ROSCO, 'rootfs', 'sdproto')):
        w = l.split()
        if len(w) == 4 and w[0] == 'f' and not os.path.exists(
                os.path.join(boot, w[3])):
            drop += 1
            continue
        keep.append(l)
    with open(sdp, 'w') as f:
        f.writelines(keep)
    if drop:
        print('sdproto: %d files not built, left out' % drop)
    sh([sys.executable, '../tools/mkfs.py', '-b', '32768', '-i', '4096', root,
        '../rootfs/proto', sdp, pfile],
       cwd=os.path.join(ROSCO, 'boot'), stdout=subprocess.DEVNULL)
    card = os.path.join(WORK, 'rosco_sd.bin')
    if os.path.exists(card):
        os.remove(card)
    sh([sys.executable, os.path.join(ROSCO, 'tools', 'mksd.py'), card,
        '06:' + fat, '81:' + root])
    # the session
    lines = ['expect login:\t600', 'send root', 'expect # \t120']
    for b in bins:
        for n in names:
            lines += ['send echo ==%s %s==; %s < /usr/bench/%s.in' % (b, n, b, n),
                      'expect *BYE\t3000', 'expect # \t600']
    with open(os.path.join(WORK, 'session.txt'), 'w') as f:
        f.write('\n'.join(lines) + '\n')
    log = os.path.join(WORK, 'session.log')
    sh(['podman', 'run', '--rm', '--userns=keep-id', '-e', 'SDL_VIDEODRIVER=dummy',
        '-v', WORK + ':/work', '-v', os.path.join(ROSCO, 'tools') + ':/tools:ro',
        '--entrypoint', 'python3', 'localhost/rosco-emulator', '/tools/mamesession.py',
        '/opt/rosco', '/work/rosco_sd.bin', '/work/session.log',
        '/work/session.txt'])
    out = open(log, 'rb').read().decode('latin-1').replace('\r', '')
    m = re.search(r'(\d+) *MHz', out)
    print('firmware: %s' % (m.group(0) if m else '(no CPU speed line)'))
    times = {}
    for b, n, t in re.findall(r'\n==(\S+) (\S+)==\n.*?\nTIME *(\d+)', out, re.S):
        times[(b, n)] = int(t)
    cyc = {}
    if a.k:
        for l in open(os.path.join(TOP, 'build', 'prof', a.k + '.txt')):
            w = l.split()
            if len(w) > 2 and w[2] == 'cycles' and w[0] != 'total':
                cyc[w[0]] = int(w[1])
    head = '%-10s' % 'bench' + ''.join('%12s' % (b + ' s') for b in bins)
    if a.k:
        head += '%14s' % 'r68k@10MHz s'
    if a.b:
        head += '%9s' % 'gain'
    print(head)
    for n in names:
        row = '%-10s' % n
        for b in bins:
            t = times.get((b, n))
            row += '%12s' % ('%.2f' % (t / 100) if t is not None else '-')
        if a.k:
            row += '%14s' % ('%.2f' % (cyc[n] / 1e7) if n in cyc else '-')
        if a.b and (bins[0], n) in times and (bins[1], n) in times:
            row += '%8.1f%%' % (100.0 * (times[(bins[1], n)] / times[(bins[0], n)]
                                          - 1))
        print(row)


main()
