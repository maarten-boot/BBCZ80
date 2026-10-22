#!/usr/bin/env python3
"""Make the bare-metal demo: build/bare/bbc68k-bare and its .tar.gz, and
with --docker the container image bbc68k-bare.

	mkbaredemo.py [-r R68K_DIR] [--docker] [--test]

As mkdemo.py, but with bare BBC BASIC (build/bare/demo/ROSCODE1.BIN, make
bare) instead of Minix: r68k (-O2, static), its firmware, ROSCODE1.BIN,
demo/demo-bare.sh as demo.sh, demo/README-bare.txt as README.txt, and
card.img.gz, an empty FAT16 SD card (as the web page's, web/pre.js) that
demo.sh unpacks into the card directory the first time.  In the image the
card directory is the volume /card (BBC_CARD).
--test boots the demo and checks the asm demo and the card; with --docker
it runs the image twice with one card, to see a file saved in the first
run in the second.
"""

import argparse
import fcntl
import gzip
import os
import pty
import re
import select
import shutil
import struct
import subprocess
import sys
import tarfile
import tempfile
import termios
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import mkdemo			# noqa: E402  (the r68k build, licences, docker)

SRC = os.path.dirname(HERE)
TOP = os.path.dirname(SRC)
WORK = os.path.join(TOP, 'build', 'bare')
NAME = 'bbc68k-bare'
IMAGE = 'docker.io/library/bbc68k-bare:latest'	# (docker load: bbc68k-bare)
CARD = 32 << 20
PART = 2048


def card():
    """An empty SD card: an MBR with one FAT16 partition from PART (as
    web/pre.js formats the page's card)."""
    img = bytearray(CARD)
    total = CARD // 512 - PART
    spc = 1
    while total // spc > 65524:
        spc *= 2
    rsv, nfats, rootents = 1, 2, 512
    rootsecs = rootents * 32 // 512
    fatsz = -(-((total - rsv - rootsecs) // spc + 2) * 2 // 512)
    img[446 + 4] = 0x06
    struct.pack_into('<II', img, 446 + 8, PART, total)
    img[510:512] = b'\x55\xaa'
    b = PART * 512
    img[b:b + 11] = b'\xeb\x3c\x90BBC68K  '
    struct.pack_into('<HBHBHHBHHHI', img, b + 11, 512, spc, rsv, nfats, rootents,
                     total if total < 65536 else 0, 0xF8, fatsz, 63, 255, PART)
    if total >= 65536:
        struct.pack_into('<I', img, b + 32, total)
    img[b + 36] = 0x80
    img[b + 38] = 0x29
    struct.pack_into('<I', img, b + 39, 0x6802B5C)
    img[b + 43:b + 62] = b'BBC BASIC  FAT16   '
    img[b + 510:b + 512] = b'\x55\xaa'
    for k in range(nfats):
        o = b + (rsv + k * fatsz) * 512
        img[o:o + 4] = b'\xf8\xff\xff\xff'
    return bytes(img)


def controlling_tty():
    """(in the child, after setsid) make standard input its terminal:
    demo.sh opens /dev/tty"""
    fcntl.ioctl(0, termios.TIOCSCTTY, 0)


def test(out):
    """Boot it (a fresh card), run the asm demo, save on the card, check
    *DIR; then boot again and see the file."""
    ok = True
    with tempfile.TemporaryDirectory() as cd:
        for run in (1, 2):
            fd, slave = pty.openpty()
            sin = os.open(os.ttyname(slave), os.O_RDWR)
            p = subprocess.Popen([os.path.join(out, 'demo.sh')], stdin=sin, stdout=slave,
                                 stderr=slave, env=dict(os.environ, BBC_CARD=cd),
                                 start_new_session=True, preexec_fn=controlling_tty)
            os.close(slave)
            os.close(sin)
            buf = b''

            def until(pat, secs=60):
                nonlocal buf
                end = time.time() + secs
                while not re.search(pat, buf):
                    r, _, _ = select.select([fd], [], [], max(0, end - time.time()))
                    if not r:
                        raise TimeoutError(pat)
                    buf += os.read(fd, 65536)
                m = re.search(pat, buf)
                text, buf = buf[:m.end()], buf[m.end():]
                return text.decode('latin-1')

            def send(s):
                for c in s.encode():
                    os.write(fd, bytes([c]))
                    time.sleep(0.003)
            try:
                until(rb'Return: BASIC prompt\) \? ')
                if run == 1:
                    send('5\r')
                    good = 'HELLO FROM THE 68000!' in until(rb'for the menu[^\n]*\n>')
                    print('%s  asm demo' % ('ok  ' if good else 'FAIL'))
                    ok = ok and good
                    send('SAVE "KEEPME"\r')
                    until(rb'\n>')
                    send('*DIR\r')
                    good = 'SD card:' in (t := until(rb'free[^\n]*\n>')) and 'KEEPME.BBC' in t
                    print('%s  SAVE "KEEPME" on the SD card' % ('ok  ' if good else 'FAIL'))
                else:
                    send('\r*DIR\r')
                    good = 'KEEPME.BBC' in until(rb'free[^\n]*\n>')
                    print('%s  the card kept KEEPME.BBC for the next start' % ('ok  ' if good else 'FAIL'))
                ok = ok and good
                send('\x1d')
                p.wait(timeout=10)
            except (TimeoutError, subprocess.TimeoutExpired) as e:
                print('FAIL  timeout %s: %s' % (e, buf.decode('latin-1')[-300:]))
                ok = False
            finally:
                if p.poll() is None:
                    p.kill()
                    p.wait()
                os.close(fd)
    print('mkbaredemo --test: %s' % ('ok' if ok else 'FAILED'))
    return ok


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('-r', default=os.path.join(os.path.dirname(TOP), 'r68k'))
    ap.add_argument('--docker', action='store_true')
    ap.add_argument('--test', action='store_true')
    a = ap.parse_args()
    r68k = os.path.abspath(a.r)
    image = os.path.join(WORK, 'demo', 'ROSCODE1.BIN')
    if not os.path.exists(image):
        sys.exit('mkbaredemo: no %s (make bare first)' % image)
    out = os.path.join(WORK, NAME)
    if os.path.exists(out):
        shutil.rmtree(out)
    os.makedirs(os.path.join(out, 'firmware'))
    mkdemo.build_r68k(r68k, out, WORK)
    shutil.copy(image, os.path.join(out, 'ROSCODE1.BIN'))
    shutil.copy(os.path.join(SRC, 'demo', 'demo-bare.sh'), os.path.join(out, 'demo.sh'))
    os.chmod(os.path.join(out, 'demo.sh'), 0o755)
    shutil.copy(os.path.join(SRC, 'demo', 'README-bare.txt'), os.path.join(out, 'README.txt'))
    with gzip.open(os.path.join(out, 'card.img.gz'), 'wb', 9) as f:
        f.write(card())
    mkdemo.licences(r68k, out)
    tgz = os.path.join(WORK, NAME + '.tar.gz')
    with tarfile.open(tgz, 'w:gz') as t:
        t.add(out, NAME)
    print('%s: %d bytes' % (tgz, os.path.getsize(tgz)))
    if a.test and not test(out):
        return 1
    if a.docker:
        vol = 'bbc68k-bare-test-%d' % os.getpid()
        runs = [(['-v', vol + ':/card'],
                 [(rb'Return: BASIC prompt\) \?', '5\r'),
                  (rb'for the menu[^\n]*\n>', 'SAVE "INBOX"\r'),
                  (rb'SAVE "INBOX"\r*\n>', '\x1d')],
                 'HELLO FROM THE 68000!'),
                (['-v', vol + ':/card'],
                 [(rb'Return: BASIC prompt\) \?', '\r*DIR\r'),
                  (rb'free[^\n]*\n>', '\x1d')],
                 'INBOX.BBC')]
        tool = os.environ.get('DOCKER', 'podman')
        try:
            ok = mkdemo.docker(r68k, out, a.test, NAME, IMAGE,
                               '\nENV BBC_CARD=/card\nVOLUME /card\n', runs, WORK)
        finally:
            if a.test:
                subprocess.run([tool, 'volume', 'rm', '-f', vol],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if not ok:
            return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
