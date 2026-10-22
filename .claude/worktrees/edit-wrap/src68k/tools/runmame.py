#!/usr/bin/env python3
"""runminix.py for the MAME rosco-emulator: the same interface, the real
machine (rosco_m68k_010, firmware, SD card).

	runmame.py [-m MINIX] [-f MINIXPATH=HOSTFILE ...] [-t SECS] [cmd ...]

The Minix root is on an SD card made in build/mame/run: the Minix tree's
rootfs/proto and rootfs/sdproto (without the files that are not built) plus
the -f files; the FAT partition has ROSCODE1.BIN of build/mame/
image-115200.bin (a boot image with the emulator's 115200 baud console,
see mamebench.py).  The commands run one after another at the shell
prompt, each with a time limit of -t seconds (default 30), in one session
of mamesession.py in the podman image localhost/rosco-emulator.  The
console transcript goes to stdout, as runminix.py prints it.  Commands of
the "@PATTERN@TEXT" form are not supported.  The harnesses (bascheck,
mathcheck, asmcheck) use this instead of runminix.py when BBC_EMU=mame.
"""

import argparse
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TOP = os.path.dirname(os.path.dirname(HERE))
MAMEDIR = os.path.join(TOP, 'build', 'mame')
WORK = os.path.join(MAMEDIR, 'run')
IMAGE = 'localhost/rosco-emulator'


def card(rosco, files):
    """Make WORK/rosco_sd.bin with the extra files."""
    boot = os.path.join(rosco, 'boot')
    os.makedirs(WORK, exist_ok=True)
    rcode = os.path.join(WORK, 'ROSCODE1.BIN')
    subprocess.run([os.path.join(rosco, 'loader', 'mkrosco'), '-o', rcode,
                    os.path.join(rosco, 'loader', 'loader.bin'),
                    os.path.join(MAMEDIR, 'image-115200.bin')],
                   check=True, stdout=subprocess.DEVNULL)
    have = set()
    sdp = []
    for name in ('proto', 'sdproto'):
        for l in open(os.path.join(rosco, 'rootfs', name)):
            w = l.split()
            if len(w) == 4 and w[0] == 'f' and not os.path.exists(
                    os.path.join(boot, w[3])):
                continue
            if w and w[0] == 'd':
                have.add(w[1])
            if name == 'sdproto':
                sdp.append(l)
    extra = []
    for path, host in files:
        d = os.path.dirname(path)
        parts = []
        while d not in ('', '/') and d not in have:
            parts.append(d)
            have.add(d)
            d = os.path.dirname(d)
        extra += ['d %s 755' % p for p in reversed(parts)]
        extra.append('f %s 755 %s' % (path, os.path.abspath(host)))
    with open(os.path.join(WORK, 'sdproto'), 'w') as f:
        f.writelines(sdp)
    with open(os.path.join(WORK, 'extra.proto'), 'w') as f:
        f.write('\n'.join(extra) + '\n')
    fat = os.path.join(WORK, 'sdfat.img')
    root = os.path.join(WORK, 'sdroot.img')
    sd = os.path.join(WORK, 'rosco_sd.bin')
    for f in (fat, root, sd):
        if os.path.exists(f):
            os.remove(f)
    subprocess.run([sys.executable, os.path.join(rosco, 'tools', 'mkfat.py'),
                    '-o', '2048', fat, rcode], check=True,
                   stdout=subprocess.DEVNULL)
    subprocess.run([sys.executable, '../tools/mkfs.py', '-b', '32768', '-i',
                    '4096', root, '../rootfs/proto',
                    os.path.join(WORK, 'sdproto'),
                    os.path.join(WORK, 'extra.proto')],
                   cwd=boot, check=True, stdout=subprocess.DEVNULL)
    subprocess.run([sys.executable, os.path.join(rosco, 'tools', 'mksd.py'),
                    sd, '06:' + fat, '81:' + root], check=True,
                   stdout=subprocess.DEVNULL)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('-m', default=os.environ.get(
        'MINIX', os.path.join(os.path.dirname(TOP), 'minix-st-2.0.4')))
    ap.add_argument('-e', default=None)		# (runminix.py's, ignored)
    ap.add_argument('-f', action='append', default=[])
    ap.add_argument('-t', type=float, default=30)
    ap.add_argument('cmd', nargs='*')
    a = ap.parse_args()
    rosco = os.path.join(os.path.abspath(a.m), 'src', 'rosco')
    card(rosco, [x.split('=', 1) for x in a.f])
    lines = ['expect login:\t900', 'send root', 'expect # \t120']
    for i, c in enumerate(a.cmd):
        if c.startswith('@'):
            sys.exit('runmame: "@PATTERN@TEXT" commands are not supported')
        # the marker's quotes keep the echoed command line from matching
        lines += ['send %s; echo ==D""ONE%d==' % (c, i),
                  'expect ==DONE%d==\t%g' % (i, a.t)]
    with open(os.path.join(WORK, 'session.txt'), 'w') as f:
        f.write('\n'.join(lines) + '\n')
    log = os.path.join(WORK, 'session.log')
    if os.path.exists(log):
        os.remove(log)
    subprocess.run(['podman', 'run', '--rm', '--userns=keep-id',
                    '-e', 'SDL_VIDEODRIVER=dummy', '-v', WORK + ':/work',
                    '-v', os.path.join(rosco, 'tools') + ':/tools:ro',
                    '--entrypoint', 'python3', IMAGE, '/tools/mamesession.py',
                    '/opt/rosco', '/work/rosco_sd.bin', '/work/session.log',
                    '/work/session.txt'], check=True)
    out = open(log, 'rb').read().decode('latin-1')
    done = len(re.findall(r'(?m)^==DONE\d+==\r?$', out))
    out = re.sub(r'(?m)^==DONE\d+==\r?\n', '', out)
    out = re.sub(r'; echo ==D""ONE\d+==', '', out)	# (the echoed commands)
    sys.stdout.write(out + '\n')
    if done != len(a.cmd):
        print('\nrunmame: timeout on: %s' % a.cmd[done], file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
