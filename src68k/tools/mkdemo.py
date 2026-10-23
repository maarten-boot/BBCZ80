#!/usr/bin/env python3
"""Make the stand-alone demo: build/demo/bbc68k-demo and its .tar.gz.

	mkdemo.py [-m MINIX] [-r R68K_DIR] [--docker] [--test]
	mkdemo.py --progs

The demo (demo/README.txt) is r68k, linked statically, its firmware and a
ROSCODE1.BIN whose RAM disk root is the Minix tree's rootfs/proto with
demo/etc/ttytab (the console runs demo/etc/demo, BBC BASIC with the menu,
instead of getty), bbcbasic and the programs of demo/progs.  The programs
are tokenised by the Z80 BBC BASIC under RunCPM (runcpm.py, SAVE) and
stored as /usr/demo/NAME.bbc, with the text as NAME.bas.  R68K_DIR is the
r68k checkout (default ../r68k next to this repository); its tracked sources
are built with -O2 in build/demo/r68k-src, the firmware is taken as built.
--test boots the demo and runs each program from the menu.
--progs only tokenises the programs into build/demo/progs (for mkbare.py
--demo, e.g. in the GitHub Action), with nothing of Minix or r68k.

--docker also builds the container image bbc68k-demo (demo/Dockerfile;
$DOCKER, default podman) from build/demo/docker and saves it as
build/demo/bbc68k-demo-image.tar.gz (docker load -i ...); with --test the
container is started once, runs the asm demo and is quit with Ctrl-].
"""

import argparse
import os
import pty
import re
import select
import shutil
import subprocess
import sys
import tarfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.dirname(HERE)
TOP = os.path.dirname(SRC)
DEMO = os.path.join(SRC, 'demo')
WORK = os.path.join(TOP, 'build', 'demo')
NAME = 'bbc68k-demo'
IMAGE = 'docker.io/library/bbc68k-demo:latest'	# (docker load: bbc68k-demo)


def tokenise(progs, out):
    """Save each demo program from the Z80 BBC BASIC; the files end with
    the program (CP/M pads them to 128 bytes)."""
    cpm = os.path.join(TOP, 'build', 'cpm', 'A', '0')
    for name in progs:
        text = open(os.path.join(DEMO, 'progs', name + '.bas')).read()
        cmds = os.path.join(WORK, 'tok.in')
        with open(cmds, 'w') as f:
            f.write('NEW\n' + text.rstrip('\n') + '\nSAVE "%s"\n' % name.upper())
        bbc = os.path.join(cpm, name.upper() + '.BBC')
        if os.path.exists(bbc):
            os.remove(bbc)
        r = subprocess.run([sys.executable, os.path.join(HERE, 'runcpm.py'),
                            cmds], capture_output=True, text=True)
        if r.returncode or r.stdout.strip():
            sys.exit('mkdemo: %s: %s%s' % (name, r.stdout, r.stderr))
        data = open(bbc, 'rb').read()
        i = 0
        while data[i]:				# line length; 0 = the end
            i += data[i]
        if data[i:i + 3] != b'\0\xff\xff':
            sys.exit('mkdemo: %s: no end of program' % name)
        with open(os.path.join(out, name + '.bbc'), 'wb') as f:
            f.write(data[:i + 3])


def make_root(rosco, files):
    """WORK/root.img: rootfs/proto (with the demo ttytab) and the files
    [(minix path, mode, host path)]."""
    boot = os.path.join(rosco, 'boot')
    lines, have = [], set()
    for line in open(os.path.join(rosco, 'rootfs', 'proto')):
        w = line.split()
        if len(w) == 4 and w[0] == 'f':
            if w[1] == '/etc/ttytab':
                w[3] = os.path.join(DEMO, 'etc', 'ttytab')
            elif not os.path.isabs(w[3]):
                w[3] = os.path.normpath(os.path.join(boot, w[3]))
            line = ' '.join(w) + '\n'
        elif len(w) > 1 and w[0] == 'd':
            have.add(w[1])
        lines.append(line)
    for path, mode, host in files:
        d = os.path.dirname(path)
        if d not in have:
            lines.append('d %s 755\n' % d)
            have.add(d)
        lines.append('f %s %s %s\n' % (path, mode, host))
    with open(os.path.join(WORK, 'proto'), 'w') as f:
        f.writelines(lines)
    subprocess.run([sys.executable, os.path.join(rosco, 'tools', 'mkfs.py'),
                    'root.img', 'proto'], cwd=WORK, check=True,
                   stdout=subprocess.DEVNULL)


def test(out):
    """Boot the demo, run every program from the menu, print the output."""
    fd, slave = pty.openpty()
    # (as demo.sh: r68k makes its standard input non-blocking, which must
    # not reach its standard output, or output is lost when the pty is full)
    sin = os.open(os.ttyname(slave), os.O_RDWR)
    p = subprocess.Popen(['./r68k', '-d', 'ROSCODE1.BIN'], cwd=out,
                         stdin=sin, stdout=slave, stderr=subprocess.DEVNULL,
                         env=dict(os.environ, R68K_RAM='2M'))
    os.close(slave)
    os.close(sin)
    buf = [b'']

    def until(pat, secs):
        end = time.time() + secs
        while not re.search(pat, buf[0]):
            r, _, _ = select.select([fd], [], [], max(0, end - time.time()))
            if not r:
                raise TimeoutError(pat)
            buf[0] += os.read(fd, 4096)
        m = re.search(pat, buf[0])
        text, buf[0] = buf[0][:m.end()], buf[0][m.end():]
        return text.decode('latin-1')

    def send(s):
        for c in s.encode():
            os.write(fd, bytes([c]))
            time.sleep(0.002)

    ok = True
    try:
        sys.stdout.write(until(rb'Return: BASIC prompt\) \?', 60))
        for n, inp in ((1, ''), (2, '\r'), (3, '\r'), (4, ''), (5, ''),
                       (6, '')):
            send('%d\r' % n)
            if inp:
                until(rb'\?', 30)
                send(inp)
            if n == 4:
                try:
                    until(rb'generation 20 ', 60)
                except TimeoutError:
                    pass
                send('\x1b')			# (Escape: Life runs 100 generations)
                text = until(rb'\n>', 600)
                sys.stdout.write(text)
                ok = ok and 'Escape at line' in text
                send('CHAIN "menu"\r')
            else:
                text = until(rb'for the menu[^\n]*\n>', 600)
                sys.stdout.write(text)
                ok = ok and 'rror' not in text
                send('CHAIN "menu"\r')
            sys.stdout.write(until(rb'Return: BASIC prompt\) \?', 60)[-200:])
        send('\r*BYE\r')
        sys.stdout.write(until(rb'# ', 30))
        send('exit\r')
        sys.stdout.write(until(rb'Return: BASIC prompt\) \?', 60)[-80:])
    except TimeoutError as e:
        print('\nmkdemo --test: timeout waiting for %r; output:\n%s'
              % (e, buf[0].decode('latin-1')))
        ok = False
    finally:
        p.kill()
        p.wait()
    print('\nmkdemo --test: %s' % ('ok' if ok else 'FAILED'))
    return ok


def build_r68k(r68k, out, work):
    """out/r68k: r68k's tracked sources (git ls-files) built in
    work/r68k-src, optimised, linked statically; and its firmware
    """
    rsrc = os.path.join(work, 'r68k-src')
    if os.path.exists(rsrc):
        shutil.rmtree(rsrc)
    os.makedirs(rsrc)
    for f in subprocess.run(['git', 'ls-files'], cwd=r68k, check=True,
                            capture_output=True, text=True).stdout.split():
        os.makedirs(os.path.dirname(os.path.join(rsrc, f)), exist_ok=True)
        shutil.copy(os.path.join(r68k, f), os.path.join(rsrc, f))
    subprocess.run(['make', 'r68k', 'CXX=g++ -static',
                    'CXXFLAGS=-O2 -Iinclude', 'CFLAGS=-O2'], cwd=rsrc,
                   check=True, stdout=subprocess.DEVNULL)
    subprocess.run(['strip', '-o', os.path.join(out, 'r68k'),
                    os.path.join(rsrc, 'r68k')], check=True)
    shutil.copy(os.path.join(r68k, 'firmware', 'rosco_m68k.rom'),
                os.path.join(out, 'firmware'))


def licences(r68k, out, minix=None):
    """the licence files of the parts (minix: the Minix LICENSE, if in)"""
    shutil.copy(os.path.join(r68k, 'LICENSE.md'),
                os.path.join(out, 'LICENSE-r68k.md'))
    text = open(os.path.join(r68k, 'musashi', 'readme.txt'),
                encoding='latin-1').read()
    with open(os.path.join(out, 'LICENSE-musashi.txt'), 'w') as f:
        f.write(text[text.index('LICENSE AND COPYRIGHT'):].split('\n\n\n')[0]
                + '\n')
    if minix:
        shutil.copy(minix, os.path.join(out, 'LICENSE-minix.txt'))
    shutil.copy(os.path.join(TOP, 'licence.txt'),
                os.path.join(out, 'LICENCE-bbcbasic.txt'))


def docker(r68k, out, test, name=NAME, image=IMAGE, extra='', runs=None,
           work=WORK):
    """Build the image (demo/Dockerfile, plus the lines extra) and save it
    as WORK/NAME-image.tar.gz; with test, run it: runs is a list of
    ([docker run options], [(output regex, keys) ...], text the output
    must have); by default the asm demo from the menu.  Returns ok.
    """
    tool = os.environ.get('DOCKER', 'podman')
    ctx = os.path.join(work, 'docker')
    if os.path.exists(ctx):
        shutil.rmtree(ctx)
    for f in subprocess.run(['git', 'ls-files'], cwd=r68k, check=True,
                            capture_output=True, text=True).stdout.split():
        os.makedirs(os.path.dirname(os.path.join(ctx, 'r68k', f)),
                    exist_ok=True)
        shutil.copy(os.path.join(r68k, f), os.path.join(ctx, 'r68k', f))
    shutil.copytree(out, os.path.join(ctx, 'demo'),
                    ignore=shutil.ignore_patterns('r68k'))
    with open(os.path.join(DEMO, 'Dockerfile')) as f, \
            open(os.path.join(ctx, 'Dockerfile'), 'w') as g:
        g.write(f.read() + extra)
    subprocess.run([tool, 'build', '-t', image, ctx], check=True)
    tgz = os.path.join(work, name + '-image.tar.gz')
    with open(tgz, 'wb') as f:
        save = subprocess.Popen([tool, 'save', image], stdout=subprocess.PIPE)
        subprocess.run(['gzip', '-9'], stdin=save.stdout, stdout=f, check=True)
        if save.wait():
            sys.exit('mkdemo: %s save failed' % tool)
    print('%s: %d bytes' % (tgz, os.path.getsize(tgz)))
    if not test:
        return True
    if runs is None:
        runs = [([], [(rb'Return: BASIC prompt\) \?', '5\r'),
                      (rb'for the menu[^\n]*\n>', '\x1d')],
                 'HELLO FROM THE 68000!')]
    ok = True
    for args, steps, want in runs:
        ok = run_container(tool, image, args, list(steps), want) and ok
    print('mkdemo --test (%s image %s): %s' % (tool, image, 'ok' if ok else 'FAILED'))
    return ok


def run_container(tool, image, args, steps, want):
    """docker run -it ARGS IMAGE in a pty, typing keys when the output
    matches; ok if all steps were taken, it ended well and want is in
    the output
    """
    pid, fd = pty.fork()
    if pid == 0:
        os.execvp(tool, [tool, 'run', '-it', '--rm'] + args + [image])
    buf = b''
    end = time.time() + 120
    try:
        while time.time() < end:
            r, _, _ = select.select([fd], [], [], 1)
            if r:
                try:
                    buf += os.read(fd, 4096)
                except OSError:
                    break			# (the container has ended)
            if steps and re.search(steps[0][0], buf):
                for c in steps.pop(0)[1].encode():
                    os.write(fd, bytes([c]))
                    time.sleep(0.005)
    finally:
        _, status = os.waitpid(pid, 0) if not steps else (0, -1)
    text = buf.decode('latin-1')
    print(text[-600:])
    return not steps and status == 0 and want in text


def make_progs():
    """build/demo/progs: the demo programs tokenised; their names"""
    progdir = os.path.join(WORK, 'progs')
    os.makedirs(progdir, exist_ok=True)
    progs = sorted(f[:-4] for f in os.listdir(os.path.join(DEMO, 'progs'))
                   if f.endswith('.bas'))
    tokenise(progs, progdir)
    return progs


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('-m', default=os.environ.get(
        'MINIX', os.path.join(os.path.dirname(TOP), 'minix-st-2.0.4')))
    ap.add_argument('-r', default=os.path.join(os.path.dirname(TOP), 'r68k'))
    ap.add_argument('--docker', action='store_true')
    ap.add_argument('--test', action='store_true')
    ap.add_argument('--progs', action='store_true')
    a = ap.parse_args()
    if a.progs:
        make_progs()
        return 0
    rosco = os.path.join(os.path.abspath(a.m), 'src', 'rosco')
    r68k = os.path.abspath(a.r)
    out = os.path.join(WORK, NAME)
    if os.path.exists(out):
        shutil.rmtree(out)
    os.makedirs(os.path.join(out, 'firmware'))
    progs = make_progs()
    progdir = os.path.join(WORK, 'progs')
    files = [('/etc/demo', 644, os.path.join(DEMO, 'etc', 'demo')),
             ('/usr/bin/bbcbasic', 755, os.path.join(SRC, 'bbcbasic')),
             # for the web page's uploads from its SD card (web/loader.js)
             ('/bin/dd', 755, os.path.join(rosco, 'cmds', 'bin', 'dd'))]
    for n in progs:
        files.append(('/usr/demo/%s.bbc' % n, 644,
                      os.path.join(progdir, n + '.bbc')))
        files.append(('/usr/demo/%s.bas' % n, 644,
                      os.path.join(DEMO, 'progs', n + '.bas')))
    make_root(rosco, files)
    subprocess.run([os.path.join(rosco, 'loader', 'mkrosco'), '-x', 'root.img',
                    '-o', os.path.join(out, 'ROSCODE1.BIN'),
                    os.path.join(rosco, 'loader', 'loader.bin'),
                    os.path.join(rosco, 'boot', 'image.bin')], cwd=WORK,
                   check=True, stdout=subprocess.DEVNULL)

    build_r68k(r68k, out, WORK)
    shutil.copy(os.path.join(DEMO, 'demo.sh'), out)
    os.chmod(os.path.join(out, 'demo.sh'), 0o755)
    shutil.copy(os.path.join(DEMO, 'README.txt'), out)
    licences(r68k, out, os.path.join(os.path.abspath(a.m), 'src', 'LICENSE'))

    tgz = os.path.join(WORK, NAME + '.tar.gz')
    with tarfile.open(tgz, 'w:gz') as t:
        t.add(out, NAME)
    print('%s: %d bytes' % (tgz, os.path.getsize(tgz)))
    if a.test and not test(out):
        return 1
    if a.docker and not docker(r68k, out, a.test):
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
