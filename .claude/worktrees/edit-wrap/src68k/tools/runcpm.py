#!/usr/bin/env python3
"""Run the original Z80 BBC BASIC (bin/cpm/BBCBASIC.COM) under RunCPM as the
reference for the 68k port: type BASIC lines at the '>' prompt and print what
comes back.

	runcpm.py [-r RUNCPM] [-t SECS] FILE|-

Each line of FILE (or stdin) is typed at the BASIC prompt; a line that does
not start with a line number runs immediately, so a program can be entered
and then RUN.  The output (without the echoed input) goes to stdout.  The
CP/M drive is build/cpm/A/0 in this repository.  RUNCPM defaults to
../RunCPM/RunCPM/RunCPM next to this repository, or $RUNCPM (built with
make -f Makefile.posix CCP=INTERNAL).
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
TOP = os.path.dirname(os.path.dirname(HERE))


class Term:
    def __init__(self, argv, cwd):
        self.fd, slave = pty.openpty()
        self.proc = subprocess.Popen(argv, cwd=cwd, stdin=slave, stdout=slave,
                                     stderr=slave)
        os.close(slave)
        self.buf = b''

    def until(self, pattern, timeout):
        """Read until the regex matches; return the text before the match."""
        end = time.time() + timeout
        rx = re.compile(pattern)
        while True:
            m = rx.search(self.buf)
            if m:
                out, self.buf = self.buf[:m.start()], self.buf[m.end():]
                return out
            left = end - time.time()
            if left <= 0:
                raise TimeoutError(pattern)
            r, _, _ = select.select([self.fd], [], [], left)
            if r:
                try:
                    self.buf += os.read(self.fd, 4096)
                except OSError:
                    raise EOFError

    def send(self, text):
        for c in text.encode('latin-1'):
            os.write(self.fd, bytes([c]))
            time.sleep(0.001)

    def close(self):
        self.proc.kill()
        self.proc.wait()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('-r', default=os.environ.get(
        'RUNCPM', os.path.join(os.path.dirname(TOP), 'RunCPM', 'RunCPM', 'RunCPM')))
    ap.add_argument('-t', type=float, default=60)
    ap.add_argument('file')
    a = ap.parse_args()
    lines = (sys.stdin if a.file == '-' else open(a.file)).read().splitlines()

    work = os.path.join(TOP, 'build', 'cpm')
    os.makedirs(os.path.join(work, 'A', '0'), exist_ok=True)
    shutil.copy(os.path.join(TOP, 'bin', 'cpm', 'BBCBASIC.COM'),
                os.path.join(work, 'A', '0', 'BBCBASIC.COM'))
    t = Term([os.path.abspath(a.r)], work)
    try:
        t.until(rb'A0>', 30)
        t.send('BBCBASIC\r')
        t.until(rb'\n>', 30)
        for line in lines:
            t.send(line + '\r')
            t.until(re.escape(line.encode('latin-1')) + rb'\r*\n', 10)
            out = t.until(rb'(^|\n)>', a.t)
            out = out.decode('latin-1').replace('\r', '')
            sys.stdout.write(out + '\n' if out else '')
        sys.stdout.flush()
    finally:
        t.close()
    return 0


if __name__ == '__main__':
    sys.exit(main())
