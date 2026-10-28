#!/usr/bin/env python3
"""Differential test of the 68k BBC BASIC against the Z80 original.

	bascheck.py [-k] [-n] [-t SECS] [TEST ...]

Each TEST is a file of lines typed at the BASIC prompt (default: all of
test/bas/*.in and test/kw/*.in, the keyword tests).  A line "#file PATH"
puts that file beside the test; a line "#typed" marks a test that needs
each line typed after the prompt (INKEY), which BBC_EMU=host/hostwin
skip.  The Z80 reference output comes from bin/cpm/BBCBASIC.COM
under RunCPM (tools/runcpm.py) and is cached as NAME.ref beside it (delete it
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
BBC_EMU=bare tests BBC BASIC on a bare rosco_m68k (tools/mkbare.py): an
image per group with the #file files in its RAM store, in r68k on a pty
($R68K, else the r68k next to this repository, else the demo's); the lines are typed at the >
prompt, each after the prompt is back, and *BYE ends a test (BASIC starts
again with the files kept).  The machine has 5 MB (R68K_RAM, unless set):
the rosco_m68k with its 4 MB expansion.
BBC_EMU=host and BBC_EMU=hostwin test BBC BASIC as a program on the PC
(tools/mkhost.py): build/host/linux/bbc68k, or build/host/windows/
bbc68k.exe under Wine; each test in a new folder with its #file files (the
program's files), its lines piped in after a Return for the demo menu and
NEW (the menu program goes), and
*BYE (which ends the program) at the end.
-k keeps the 68k outputs as build/bas/NAME.out; -n only prints them (no
Z80 reference, for 68k-only things such as the assembler).
Exit status 1 if any test differs.
"""

import argparse
import difflib
import glob
import os
import pty
import re
import select
import shutil
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
# BBC_EMU=mame: the MAME rosco-emulator (runmame.py) instead of r68k
MAME = os.environ.get('BBC_EMU') == 'mame'
BARE = os.environ.get('BBC_EMU') == 'bare'
HOSTED = os.environ.get('BBC_EMU') in ('host', 'hostwin')
RUNNER = 'runmame.py' if MAME else 'runminix.py'
SRC = os.path.dirname(HERE)
TOP = os.path.dirname(SRC)


WORK = os.path.join(TOP, 'build', 'bas')
BUDGET = 65536


def parse(test):
    """(typed lines, [host paths of #file files]); a "#typed" line is not
    typed (see typed)"""
    lines, files = [], []
    with open(test, 'rb') as f:
        for l in f.read().decode('latin-1').split('\n'):
            if l.startswith('#file '):
                files.append(os.path.normpath(os.path.join(
                    os.path.dirname(test), l[6:].strip())))
            elif l.rstrip() != '#typed':
                lines.append(l)
    while lines and lines[-1] == '':
        lines.pop()
    return lines, files


def typed(test):
    """A "#typed" line: the test needs each line typed after the prompt
    (INKEY would read lines typed ahead as keys), so the PC programs,
    which get all the lines at once, skip it."""
    with open(test, 'rb') as f:
        return b'#typed' in f.read().split(b'\n')


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
    args = [sys.executable, os.path.join(HERE, RUNNER), '-t', str(secs),
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
        m = re.search(r'\n==T%d==\n(.*?)(?==minix=# |\Z)' % i, text, re.S)
        res[t] = m.group(1) if m else ('(no output)\n' +
                                       '\n'.join(text.split('\n')[-12:]))
    return res


def run_bare(tests, secs):
    """The tests on bare BBC BASIC (see the module text)."""
    os.makedirs(WORK, exist_ok=True)
    files = {}
    for t in tests:
        for p in parse(t)[1]:
            files[os.path.basename(p)] = p
    img = os.path.join(WORK, 'bare.bin')
    args = [sys.executable, os.path.join(HERE, 'mkbare.py'),
            '-w', os.path.join(WORK, 'bareobj'), '-o', img]
    for p in files.values():
        args += ['-f', p]
    os.makedirs(os.path.join(WORK, 'bareobj'), exist_ok=True)
    subprocess.run(args, check=True)
    # (the r68k checkout first: the demo's copy may be older, without
    # address and bus errors)
    r68k = os.environ.get('R68K') or os.path.join(os.path.dirname(TOP), 'r68k', 'r68k')
    if not os.path.exists(r68k):
        r68k = os.path.join(TOP, 'build', 'demo', 'bbc68k-demo', 'r68k')
    fd, slave = pty.openpty()
    sin = os.open(os.ttyname(slave), os.O_RDWR)
    p = subprocess.Popen([r68k, '-d', img], stdin=sin, stdout=slave,
                         stderr=subprocess.DEVNULL,
                         env=dict(os.environ, R68K_RAM=os.environ.get('R68K_RAM', '5M')))
    os.close(slave)
    os.close(sin)
    buf = [b'']

    def until(pattern, limit):
        end = time.time() + limit
        rx = re.compile(pattern)
        while True:
            m = rx.search(buf[0])
            if m:
                out, buf[0] = buf[0][:m.end()], buf[0][m.end():]
                return out
            left = end - time.time()
            if left <= 0:
                raise TimeoutError
            r, _, _ = select.select([fd], [], [], left)
            if r:
                buf[0] += os.read(fd, 65536)

    res = {}
    try:
        until(rb'\n>', 30)
        for t in tests:
            out = b''
            try:
                for line in parse(t)[0]:
                    for c in (line + '\r').encode('latin-1'):
                        os.write(fd, bytes([c]))
                    out += until(rb'(^|\n)>', secs)
                    # *EXEC: a prompt for each line of the file, so the
                    # rest until the output is quiet for a second
                    while line.lstrip(' *').upper().startswith('EXEC'):
                        try:
                            out += until(rb'(^|\n)>', 1)
                        except TimeoutError:
                            break
                res[t] = out.decode('latin-1').replace('\r', '')
            except TimeoutError:
                res[t] = (out + buf[0]).decode('latin-1').replace('\r', '') + '\n(timeout)'
                buf[0] = b''
            os.write(fd, b'*BYE\r')
            until(rb'BBC BASIC[^\n]*\n[^\n]*\n>', 30)
    except TimeoutError:
        for t in tests:
            res.setdefault(t, '(no output: BASIC did not come back)')
    finally:
        p.kill()
        p.wait()
    # (the first prompt was taken: as the Minix transcript, each line of
    # the test after a '>')
    return {t: '>' + r for t, r in res.items()}


def run_host(tests, secs):
    """The tests on BBC BASIC as a PC program (see the module text)."""
    import tempfile
    win = os.environ.get('BBC_EMU') == 'hostwin'
    exe = os.path.join(TOP, 'build', 'host', 'windows' if win else 'linux',
                       'bbc68k.exe' if win else 'bbc68k')
    res = {}
    for t in tests:
        if typed(t):
            res[t] = None			# (skipped: see typed)
            continue
        lines, files = parse(t)
        with tempfile.TemporaryDirectory(dir=os.path.join(TOP, 'build', 'host')) as d:
            for p in files:
                shutil.copy(p, os.path.join(d, os.path.basename(p)))
            inp = ('\rNEW\r' + '\r'.join(lines) + '\r*BYE\r').encode('latin-1')
            try:
                out = subprocess.run((['wine'] if win else []) + [exe], input=inp, cwd=d,
                                     capture_output=True, timeout=secs + 30).stdout
            except subprocess.TimeoutExpired as e:
                out = (e.stdout or b'') + b'\n(timeout)'
        text = out.decode('latin-1').replace('\r', '')
        # past the demo menu: its "Type CHAIN" line ends what is not ours
        k = text.find('Type CHAIN "menu" to come back here.\n')
        text = text[k + 37:] if k >= 0 else '(no menu)\n' + text
        res[t] = text
    return res


def groups(tests):
    """Split the tests into boots by the size of their #file files."""
    out, cur, size = [], [], 0
    for t in tests:
        n = sum(os.path.getsize(p) for p in parse(t)[1])
        if cur and size + n > BUDGET and not MAME:
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
    for i, l in enumerate(lines):
        if l.startswith('>'):
            continue
        # (the banner again: QUIT or *BYE restarts bare BASIC)
        if l.startswith('BBC BASIC (') and i + 1 < len(lines) and \
                lines[i + 1].startswith('(C) Copyright'):
            continue
        if l.startswith('(C) Copyright') and i > 0 and lines[i - 1].startswith('BBC BASIC ('):
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
    tests = a.tests or sorted(glob.glob(os.path.join(SRC, 'test', 'bas', '*.in'))
                              + glob.glob(os.path.join(SRC, 'test', 'kw', '*.in')))
    refs = {} if a.n else {t: reference(t) for t in tests}
    got = {}
    for g in groups(tests):
        got.update(run_host(g, a.t) if HOSTED else run_bare(g, a.t) if BARE
                   else run68k(g, a.t))
    bad = skipped = 0
    for t in tests:
        if got[t] is None:
            skipped += 1
            print('skip ', os.path.basename(t), '(#typed: not on the PC program)')
            continue
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
    print('%d of %d failed' % (bad, len(tests) - skipped)
          + (', %d skipped' % skipped if skipped else ''))
    sys.exit(1 if bad else 0)


main()
