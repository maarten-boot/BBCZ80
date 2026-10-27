#!/usr/bin/env python3
"""Files on the SD card for bare BBC BASIC (bare/fat.c): FAT16 and FAT32.

	fatcheck.py [-k]

For each card (FAT16 made by the Minix tree's mkfat.py, with a program on
it; FAT16 made by mkfs.fat, small enough for a 16-bit sector count, as the
web page's; FAT32 made by mkfs.fat), bare BBC BASIC (build/bare/ROSCODE1.BIN, make
bare) runs in r68k with the card as rosco_sd.bin, and BASIC lines are typed
at its prompt: programs loaded, run and saved, a text file and a binary
file of many clusters written and read back, a gap written past the end,
*MKDIR, *CD, paths, *REN, *ERA, *RMDIR, and *BYE (the files stay).  Then
fsck.fat must find the file system clean, and the files on it are listed.
-k keeps the cards in build/bare/fat.
"""

import argparse
import os
import pty
import re
import select
import shutil
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.dirname(HERE)
TOP = os.path.dirname(SRC)
MINIX = os.environ.get('MINIX', os.path.join(os.path.dirname(TOP), 'minix-st-2.0.4'))
TOOLS = os.path.join(MINIX, 'src', 'rosco', 'tools')
WORK = os.path.join(TOP, 'build', 'bare', 'fat')
PART = 2048			# the partition's first sector


def sbin(name):
    for d in ('', '/usr/sbin', '/sbin'):
        f = os.path.join(d, name) if d else shutil.which(name)
        if f and os.path.exists(f):
            return f
    sys.exit('fatcheck: no %s (dosfstools)' % name)


class Basic:
    def __init__(self, img, card_dir):
        r68k = os.path.join(TOP, 'build', 'demo', 'bbc68k-demo', 'r68k')
        if not os.path.exists(r68k):
            r68k = os.path.join(os.path.dirname(TOP), 'r68k', 'r68k')
        self.fd, slave = pty.openpty()
        sin = os.open(os.ttyname(slave), os.O_RDWR)
        self.p = subprocess.Popen([r68k, '-d', img], cwd=card_dir, stdin=sin, stdout=slave,
                                  stderr=subprocess.DEVNULL, env=dict(os.environ, R68K_RAM='5M'))
        os.close(slave)
        os.close(sin)
        self.buf = b''
        self.until(rb'\n>', 30)

    def until(self, pattern, secs):
        end = time.time() + secs
        while True:
            m = re.search(pattern, self.buf)
            if m:
                out, self.buf = self.buf[:m.end()], self.buf[m.end():]
                return out.decode('latin-1').replace('\r', '')
            r, _, _ = select.select([self.fd], [], [], max(0, end - time.time()))
            if not r:
                raise TimeoutError(self.buf.decode('latin-1')[-500:])
            self.buf += os.read(self.fd, 65536)

    def line(self, text, secs=60):
        """type a line at the prompt; its output"""
        for c in (text + '\r').encode('latin-1'):
            os.write(self.fd, bytes([c]))
        return self.until(rb'(^|\n)>', secs)

    def close(self):
        self.p.kill()
        self.p.wait()


def make_card(kind, d):
    fat = os.path.join(d, 'fat.img')
    for f in (fat, os.path.join(d, 'rosco_sd.bin')):
        if os.path.exists(f):
            os.remove(f)
    if kind == 'FAT16':
        subprocess.run([sys.executable, os.path.join(TOOLS, 'mkfat.py'), '-s', '65536',
                        '-o', str(PART), fat, os.path.join(TOP, 'tests', 'FORTEST.BBC')],
                       check=True, stdout=subprocess.DEVNULL)
        ptype = '06'
    elif kind == 'FAT16b':
        subprocess.run([sbin('mkfs.fat'), '-F', '16', '-s', '1', '-h', str(PART), '-C', fat,
                        str(30 * 1024)], check=True, stdout=subprocess.DEVNULL)
        ptype = '06'
    else:
        subprocess.run([sbin('mkfs.fat'), '-F', '32', '-s', '1', '-h', str(PART), '-C', fat,
                        str(40 * 1024)], check=True, stdout=subprocess.DEVNULL)
        ptype = '0c'
    subprocess.run([sys.executable, os.path.join(TOOLS, 'mksd.py'), os.path.join(d, 'rosco_sd.bin'),
                    '%s:%s' % (ptype, fat)], check=True, stdout=subprocess.DEVNULL)


def fsck(d):
    """fsck.fat on the partition: (clean, listing)"""
    card = os.path.join(d, 'rosco_sd.bin')
    part = os.path.join(d, 'part.img')
    with open(card, 'rb') as f, open(part, 'wb') as g:
        f.seek(PART * 512)
        shutil.copyfileobj(f, g)
    r = subprocess.run([sbin('fsck.fat'), '-n', '-l', part], capture_output=True, text=True)
    # (mkfat.py's cards have a label in the boot sector only; fsck says so)
    problems = [l for l in r.stdout.split('\n')[1:] if l.strip()
                and not l.startswith('Checking file ')
                and 'no volume label in root' not in l
                and 'Auto-removing label' not in l
                and not l.startswith('Leaving filesystem')
                and not re.search(r': \d+ files, ', l)]
    return not problems, r.stdout


def run(kind, img, d, check):
    make_card(kind, d)
    b = Basic(img, d)
    try:
        out = b.line('*DIR')
        check('*DIR shows the card', 'SD card:' in out and (kind != 'FAT16' or 'FORTEST.BBC' in out))
        if kind == 'FAT16':
            b.line('LOAD "FORTEST"')
            check('LOAD "FORTEST" from the card and RUN',
                  'FOR...NEXT tests completed.' in b.line('RUN', 120))
        b.line('NEW')
        b.line('10 PRINT "saved on the card"')
        b.line('SAVE "PROG"')
        b.line('NEW')
        check('SAVE, CHAIN (any case)', 'saved on the card' in b.line('CHAIN "prog"'))
        out = b.line('*DIR')
        check('SAVE "PROG" makes PROG.BBC', 'PROG.BBC' in out)

        b.line('F%=OPENOUT "DATA.TXT":FOR I%=1 TO 3000:PRINT#F%,"line "+STR$I%:NEXT:CLOSE#F%', 120)
        out = b.line('F%=OPENIN "DATA.TXT":N%=0:S%=0:REPEAT INPUT#F%,A$:N%+=1:S%+=VAL MID$(A$,6):UNTIL EOF#F%:PRINT N%;" ";S%;" ";EXT#F%:CLOSE#F%', 120)
        check('3000 lines written and read back (%s)' % out.split('\n')[1].strip(),
              re.search(r'3000 4501500 *\d+', out) is not None)

        b.line('F%=OPENOUT "BIG.BIN":FOR I%=0 TO 99999:BPUT#F%,I% MOD 251:NEXT:CLOSE#F%', 300)
        out = b.line('F%=OPENIN "BIG.BIN":E%=0:FOR I%=0 TO 99999:E%-=(BGET#F%<>(I% MOD 251)):NEXT:PRINT "errors ";E%;" size ";EXT#F%:CLOSE#F%', 300)
        check('100000-byte binary file, %d clusters at least' % (100000 // 32768 + 1),
              'errors 0 size 100000' in out.replace('  ', ' '))

        b.line('F%=OPENUP "BIG.BIN":PTR#F%=110000:BPUT#F%,7:CLOSE#F%')
        out = b.line('F%=OPENIN "BIG.BIN":PTR#F%=105000:PRINT "gap ";BGET#F%;" end ";EXT#F%:CLOSE#F%')
        check('a write past the end leaves zeros in the gap', 'gap 0 end 110001' in out.replace('  ', ' '))

        b.line('*MKDIR SUB')
        b.line('*CD SUB')
        b.line('SAVE "INSUB"')
        out = b.line('*DIR')
        check('*MKDIR, *CD, SAVE in it', 'INSUB.BBC' in out and 'PROG.BBC' not in out)
        b.line('*CD ..')
        b.line('NEW')
        b.line('LOAD "SUB/INSUB"')
        out = b.line('LIST')
        check('*CD .., LOAD "SUB/INSUB"', 'saved on the card' in out)
        out = b.line('*RMDIR SUB')
        check('*RMDIR of a full directory is refused', 'not empty' in out)
        b.line('*ERA SUB/INSUB.BBC')
        b.line('*RMDIR SUB')
        b.line('*REN PROG2.BBC=PROG.BBC')
        out = b.line('*DIR')
        check('*ERA, *RMDIR, *REN', 'SUB' not in out and 'PROG2.BBC' in out and 'PROG.BBC' not in out)

        b.line('*BYE')
        out = b.line('*DIR')
        check('*BYE: the files are still there', 'PROG2.BBC' in out and 'DATA.TXT' in out)
    except TimeoutError as e:
        check('no timeout (%s)' % str(e)[-200:].replace('\n', ' | '), False)
    finally:
        b.close()
    ok, listing = fsck(d)
    check('fsck.fat: the file system is clean', ok)
    names = sorted(set(re.findall(r'^Checking file /(\S+)', listing, re.M)))
    print('      on the card: %s' % ' '.join(names))
    check('the host sees the files', all(n in names for n in ('DATA.TXT', 'BIG.BIN', 'PROG2.BBC')))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('-k', action='store_true')
    a = ap.parse_args()
    img = os.path.join(TOP, 'build', 'bare', 'ROSCODE1.BIN')
    failed = [0]

    def check(name, ok):
        print('%s  %s' % ('ok  ' if ok else 'FAIL', name))
        failed[0] += not ok

    for kind in ('FAT16', 'FAT16b', 'FAT32'):
        print('%s:' % kind)
        d = os.path.join(WORK, kind)
        os.makedirs(d, exist_ok=True)
        run(kind, img, d, check)
        if not a.k:
            shutil.rmtree(d, ignore_errors=True)
    print('all ok' if not failed[0] else '%d failed' % failed[0])
    return 1 if failed[0] else 0


if __name__ == '__main__':
    sys.exit(main())
