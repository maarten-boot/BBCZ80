#!/usr/bin/env python3
"""Boot Minix on the rosco_m68k in r68k with extra files in the root file
system, log in on the console, run commands and print the transcript.

	runminix.py [-m MINIX] [-e R68K] [-f MINIXPATH=HOSTFILE ...] [-t SECS]
		[cmd ...]

MINIX is the minix-st-2.0.4 checkout (rosco-m68k branch, already built:
make in src/rosco and emu/build-r68k.sh); default ../minix-st-2.0.4 next to
this repository, or $MINIX.  Each -f puts HOSTFILE into the root file
system as MINIXPATH (mode 755, parent directories are created).  The
commands run one after another at the shell prompt; -t is the time limit
for each of them (default 30 s).  A command "@PATTERN@TEXT" sends TEXT and
waits for PATTERN (a regular expression) instead of the shell prompt, for
interactive programs; TEXT takes Python escapes (\x1b, \r ...) and is
sent with a CR unless it ends in \\c.  The work files (root.img, ROSCODE1.BIN)
go to build/minix in this repository.  The Minix tree is not changed.
R68K is the emulator: $R68K, else ../r68k/r68k next to this repository
(maarten-boot/r68k, branch rosco-minix-duart, with illegal instructions
trapping), else the one built in the Minix tree.
"""

import argparse
import codecs
import os
import re
import pty
import select
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
TOP = os.path.dirname(os.path.dirname(HERE))
PROMPT = b'# '


def make_root(rosco, work, extra):
    """Write work/root.img: rootfs/proto with absolute host paths, plus the
    extra files."""
    boot = os.path.join(rosco, 'boot')
    lines = []
    with open(os.path.join(rosco, 'rootfs', 'proto')) as f:
        for line in f:
            w = line.split()
            if len(w) == 4 and w[0] == 'f' and not os.path.isabs(w[3]):
                w[3] = os.path.normpath(os.path.join(boot, w[3]))
                line = ' '.join(w) + '\n'
            lines.append(line)
    have = {l.split()[1] for l in lines if l.split() and l.split()[0] == 'd'}
    for path, host in extra:
        parts = path.strip('/').split('/')[:-1]
        for i in range(1, len(parts) + 1):
            d = '/' + '/'.join(parts[:i])
            if d not in have:
                lines.append('d %s 755\n' % d)
                have.add(d)
        lines.append('f %s 755 %s\n' % (path, os.path.abspath(host)))
    proto = os.path.join(work, 'proto')
    with open(proto, 'w') as f:
        f.writelines(lines)
    subprocess.run([sys.executable, os.path.join(rosco, 'tools', 'mkfs.py'),
                    'root.img', proto], cwd=work, check=True,
                   stdout=subprocess.DEVNULL)
    subprocess.run([os.path.join(rosco, 'loader', 'mkrosco'), '-x', 'root.img',
                    '-o', 'ROSCODE1.BIN',
                    os.path.join(rosco, 'loader', 'loader.bin'),
                    os.path.join(boot, 'image.bin')], cwd=work, check=True,
                   stdout=subprocess.DEVNULL)


class Console:
    def __init__(self, r68k, image):
        self.fd, slave = pty.openpty()
        self.proc = subprocess.Popen([r68k, '-d', image], stdin=slave,
                                     stdout=slave, stderr=subprocess.DEVNULL)
        os.close(slave)
        self.out = b''

    def expect(self, text, timeout, regex=False):
        end = time.time() + timeout
        find = (lambda: re.search(text, self.out)) if regex else \
            (lambda: text in self.out)
        while not find():
            left = end - time.time()
            if left <= 0:
                return False
            r, _, _ = select.select([self.fd], [], [], left)
            if r:
                try:
                    data = os.read(self.fd, 4096)
                except OSError:
                    return False
                sys.stdout.buffer.write(data)
                sys.stdout.flush()
                self.out += data
        if regex:
            self.out = self.out[re.search(text, self.out).end():]
        else:
            self.out = self.out[self.out.index(text) + len(text):]
        return True

    def send(self, text):
        for c in text.encode():
            os.write(self.fd, bytes([c]))
            time.sleep(0.005)

    def close(self):
        self.proc.kill()
        self.proc.wait()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('-m', default=os.environ.get(
        'MINIX', os.path.join(os.path.dirname(TOP), 'minix-st-2.0.4')))
    ap.add_argument('-e', default=os.environ.get('R68K'))
    ap.add_argument('-f', action='append', default=[])
    ap.add_argument('-t', type=float, default=30)
    ap.add_argument('cmd', nargs='*')
    a = ap.parse_args()
    rosco = os.path.join(os.path.abspath(a.m), 'src', 'rosco')
    work = os.path.join(TOP, 'build', 'minix')
    os.makedirs(work, exist_ok=True)
    make_root(rosco, work, [x.split('=', 1) for x in a.f])
    r68k = a.e
    if not r68k:
        r68k = os.path.join(os.path.dirname(TOP), 'r68k', 'r68k')
        if not os.path.exists(r68k):
            r68k = os.path.join(rosco, 'emu', 'r68k', 'r68k')
    con = Console(r68k,
                  os.path.join(work, 'ROSCODE1.BIN'))
    ok = False
    try:
        if not con.expect(b'login: ', 120):
            print('\nrunminix: no login prompt', file=sys.stderr)
            return 1
        con.send('root\r')
        if not con.expect(PROMPT, 30):
            print('\nrunminix: no shell prompt', file=sys.stderr)
            return 1
        for c in a.cmd:
            m = re.match(r'@(.*?)@(.*)$', c, re.S)
            if m:
                text = m.group(2)
                nocr = text.endswith('\\c')
                if nocr:
                    text = text[:-2]
                text = codecs.decode(text.encode('latin-1'), 'unicode_escape')
                if not nocr:
                    text += '\r'
                con.send(text)
                ok = con.expect(m.group(1).encode('latin-1'), a.t, True)
            else:
                con.send(c + '\r')
                ok = con.expect(PROMPT, a.t)
            if not ok:
                print('\nrunminix: timeout on: %s' % c, file=sys.stderr)
                return 1
        ok = True
    finally:
        con.close()
        print()
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
