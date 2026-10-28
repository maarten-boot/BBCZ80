#!/usr/bin/env python3
"""BBC BASIC at a terminal: the keyboard handling that the file-driven
tests (bascheck) cannot reach.

	ttycheck.py [DEMO_DIR | --exe PROGRAM]

Runs the stand-alone demo (DEMO_DIR, default build/demo/bbc68k-demo, make
demo) in a pty: r68k, Minix and BBC BASIC on the console (or a directory
with r68k, its firmware and bare BBC BASIC's demo image), and types:
* ESCape stopping a running loop, and a GET;
* typeahead during a run, read by GET$ afterwards;
* *ESC OFF: INKEY sees ESC (27), and *ESC ON again;
* ^S/^Q stopping and starting the output of a running program;
* the line editor: a cursor key, ESCape abandoning a line;
* ESCape still working after a *command (the shell);
* *BYE back to the demo's shell (the script survived the ESCape signals),
  and BBC BASIC run from that interactive shell, which must survive too;
  on bare BBC BASIC, *BYE starts BASIC again.
It also prints the time of 20000 empty FOR loops.  --exe runs BBC BASIC as
a PC program (tools/mkhost.py, src68k/host) instead, in a new folder;
*BYE then ends it.
"""

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


class Tty:
    def __init__(self, demo, exe=None):
        self.fd, slave = pty.openpty()
        # (r68k makes its standard input non-blocking: a separate open)
        sin = os.open(os.ttyname(slave), os.O_RDWR)
        if exe:
            import tempfile
            self.dir = tempfile.mkdtemp(dir=os.path.dirname(os.path.abspath(exe)))
            cmd, cwd = [os.path.abspath(exe)], self.dir
        else:
            cmd, cwd = ['./r68k', '-d', 'ROSCODE1.BIN'], demo
        self.p = subprocess.Popen(cmd, cwd=cwd,
                                  stdin=sin, stdout=slave, stderr=subprocess.DEVNULL,
                                  env=dict(os.environ, R68K_RAM='5M' if exe else '2M'))
        os.close(slave)
        os.close(sin)
        self.buf = self.all = b''

    def read(self, secs):
        end = time.time() + secs
        while True:
            r, _, _ = select.select([self.fd], [], [], max(0, end - time.time()))
            if r:
                try:
                    b = os.read(self.fd, 65536)
                except OSError:		# (EIO: the program has ended)
                    return
                self.buf += b
                self.all += b
            if time.time() >= end:
                return

    def until(self, pattern, secs=30):
        end = time.time() + secs
        while True:
            m = re.search(pattern.encode(), self.buf)
            if m:
                text = self.buf[:m.end()].decode('latin-1')
                self.buf = self.buf[m.end():]
                return text
            if time.time() > end:
                raise TimeoutError('%r; output:\n%s' % (pattern, self.buf.decode('latin-1')[-800:]))
            self.read(0.05)

    def send(self, text):
        for c in text.encode('latin-1'):
            os.write(self.fd, bytes([c]))
            self.read(0.003)

    def prog(self, lines):
        """NEW, the lines, RUN; returns when RUN has been echoed."""
        self.send('NEW\r')
        self.until(r'NEW\r*\n>')
        for l in lines:
            self.send(l + '\r')
            self.until(re.escape(l) + r'\r*\n>')
        self.send('RUN\r')
        self.until(r'RUN\r*\n')

    def cmd(self, line):
        """A line at the > prompt; its output up to the next prompt."""
        self.send(line + '\r')
        self.until(re.escape(line) + r'\r*\n')
        return self.until(r'(?:^|\n)>')

    def close(self):
        self.p.kill()
        self.p.wait()
        if getattr(self, 'dir', None):
            shutil.rmtree(self.dir, ignore_errors=True)


def main():
    exe = sys.argv[2] if len(sys.argv) > 2 and sys.argv[1] == '--exe' else None
    demo = sys.argv[1] if len(sys.argv) > 1 and not exe else os.path.join(TOP, 'build', 'demo', 'bbc68k-demo')
    t = Tty(demo, exe)
    failed = 0

    def check(name, ok):
        nonlocal failed
        print('%s  %s' % ('ok  ' if ok else 'FAIL', name))
        failed += not ok
        if not ok and os.environ.get('TTYCHECK_LOG'):
            with open(os.environ['TTYCHECK_LOG'], 'wb') as f:
                f.write(t.all)

    try:
        t.until(r'\n>', 60)

        t.prog(['10 REPEAT:I%=I%+1:UNTIL FALSE'])
        t.read(0.5)
        t.send('\x1b')
        check('ESCape stops a running loop', 'Escape at line 10' in t.until(r'\n>'))

        t.prog(['10 A=GET'])
        t.read(0.5)
        t.send('\x1b')
        check('ESCape at GET', 'Escape at line 10' in t.until(r'\n>'))

        t.prog(['10 FOR I%=1 TO 100000:NEXT:A$=GET$:PRINT "key ";A$'])
        t.send('x')
        check('typeahead during a run is kept (GET$)', 'key x' in t.until(r'\n>'))

        t.cmd('*ESC OFF')
        t.prog(['10 REPEAT K%=INKEY(1):UNTIL K%=27:PRINT "got ";K%'])
        t.read(0.5)
        t.send('\x1b')
        check('*ESC OFF: INKEY reads ESC', 'got 27' in t.until(r'\n>'))
        t.cmd('*ESC ON')
        t.prog(['10 REPEAT:UNTIL FALSE'])
        t.read(0.5)
        t.send('\x1b')
        check('*ESC ON again: ESCape stops the loop', 'Escape at line 10' in t.until(r'\n>'))

        t.prog(['10 FOR I%=1 TO 2000:PRINT I%:NEXT'])
        t.send('\x13')
        t.read(0.5)
        n1 = len(t.buf)
        t.read(1.0)
        n2 = len(t.buf)
        t.send('\x11')
        text = t.until(r'\n>', 60)
        check('^S stops the output (%d, %d bytes), ^Q starts it again' % (n1, n2),
              n1 == n2 and n1 < 20000 and '2000' in text)

        t.send('PRINT 12\x1b[D3\r')
        check('line editor: cursor left, insert', re.search(r'\n +132\r', t.until(r' +\d+\r*\n>')) is not None)
        t.send('PRINT 45\x1bOD6\r')	# (ESC O x: application mode keys)
        check('line editor: ESC O D (cursor left) too',
              re.search(r'\n +465\r', t.until(r' +\d+\r*\n>')) is not None)
        t.send('PRINT 5\x1b')
        t.read(0.5)
        t.send('PRINT 6\r')
        text = t.until(r'\n +6\r*\n>')
        check('line editor: ESCape abandons the line',
              'Escape' in text and not re.search(r'\n +5\r', text))

        t.cmd('*echo from the shell')
        t.prog(['10 REPEAT:UNTIL FALSE'])
        t.read(0.5)
        t.send('\x1b')
        check('ESCape after a *command', 'Escape at line 10' in t.until(r'\n>'))

        t.send('T%=TIME:FOR I%=1 TO 20000:NEXT:PRINT "loop ";TIME-T%\r')
        print('      20000 empty FOR loops: %s cs' % re.search(r'loop (\d+)', t.until(r'loop \d+')).group(1))

        t.send('*BYE\r')
        if exe:				# a PC program: *BYE ends it
            try:
                t.p.wait(timeout=10)
                check('*BYE ends the program', True)
            except subprocess.TimeoutExpired:
                check('*BYE ends the program', False)
            raise StopIteration
        text = t.until(r'(# |Copyright[^\n]*\n>)')
        if text.endswith('# '):		# Minix: the demo's shell
            check('*BYE: back to the demo shell', 'You have left BBC BASIC' in text)
            t.send('bbcbasic\r')
            t.until(r'\n>')
            t.prog(['10 REPEAT:UNTIL FALSE'])
            t.read(0.5)
            t.send('\x1b')
            t.until('Escape at line 10')
            t.send('*BYE\r')
            t.until('# ')
            t.send('echo shell alive\r')
            check('an interactive shell survives the ESCape signal',
                  'shell alive' in t.until(r'shell alive\r*\n# '))
        else:				# bare BBC BASIC: it starts again
            check('*BYE: BBC BASIC starts again (bare)', 'BBC BASIC' in text)
    except StopIteration:
        pass
    except TimeoutError as e:
        print('FAIL  timeout waiting for %s' % e)
        failed += 1
    finally:
        t.close()
    print('%s' % ('all ok' if not failed else '%d failed' % failed))
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
