#!/usr/bin/env python3
"""The line editor on a line longer than the console is wide.

	editcheck.py PROGRAM

Runs BBC BASIC as a PC program (tools/mkhost.py, src68k/host) in a pty 40
columns wide and follows its output on a model of a vt100 screen (an xterm:
a line wraps when a character goes past the last column, and a BS at the
left edge stays there).  It edits a line of two rows with the cursor keys
(EDIT, up to the start, right, left across the wrap) and checks what is on
the screen, where the cursor is and what BASIC keeps.  Plain EDIT edits the
first line only (not all of them, joined).
"""

import fcntl
import os
import re
import struct
import sys
import termios

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ttycheck import Tty

W, H = 40, 24
UP, DOWN, RIGHT, LEFT = '\x1b[A', '\x1b[B', '\x1b[C', '\x1b[D'


class Screen:
    """Enough of a vt100 for BASIC's output."""

    def __init__(self):
        self.rows = [[' '] * W for _ in range(H)]
        self.r = self.c = 0
        self.pending = False		# after the last column
        self.esc = None

    def lf(self):
        self.r += 1
        if self.r == H:
            self.rows = self.rows[1:] + [[' '] * W]
            self.r = H - 1

    def feed(self, data):
        for ch in data.decode('latin-1'):
            if self.esc is not None:
                self.esc += ch
                if self.esc == '[' or (self.esc.startswith('[') and not ch.isalpha()
                                       and ch not in '@`~'):
                    continue
                self.csi(self.esc)
                self.esc = None
            elif ch == '\x1b':
                self.esc = ''
            elif ch == '\r':
                self.c, self.pending = 0, False
            elif ch == '\n':
                self.lf()
            elif ch == '\b':
                self.c, self.pending = max(self.c - 1, 0), False
            elif ch >= ' ':
                if self.pending:
                    self.c, self.pending = 0, False
                    self.lf()
                self.rows[self.r][self.c] = ch
                if self.c == W - 1:
                    self.pending = True
                else:
                    self.c += 1

    def csi(self, s):
        if not s.startswith('['):
            return
        f, args = s[-1], [int(a) if a.isdigit() else 0 for a in s[1:-1].split(';')]
        n = args[0] or 1
        self.pending = False
        if f == 'A':
            self.r = max(self.r - n, 0)
        elif f == 'B':
            self.r = min(self.r + n, H - 1)
        elif f == 'C':
            self.c = min(self.c + n, W - 1)
        elif f == 'D':
            self.c = max(self.c - n, 0)
        elif f == 'G':
            self.c = min(n, W) - 1
        elif f in 'Hf':
            self.r = (args[0] or 1) - 1
            self.c = ((args[1] if len(args) > 1 else 0) or 1) - 1
        elif f == 'J' and args[0] == 2:
            self.rows = [[' '] * W for _ in range(H)]
        elif f == 'K':
            self.rows[self.r][self.c:] = [' '] * (W - self.c)

    def text(self, r, n):
        """n characters from the start of row r on."""
        return ''.join(''.join(row) for row in self.rows[r:])[:n]


def main():
    t = Tty(None, sys.argv[1])
    fcntl.ioctl(t.fd, termios.TIOCSWINSZ, struct.pack('HHHH', H, W, 0, 0))
    scr = Screen()
    failed = 0

    def check(name, ok, detail=''):
        nonlocal failed
        print('%s  %s' % ('ok  ' if ok else 'FAIL', name))
        if not ok and detail:
            print('      ' + detail)
        failed += not ok

    def settle():
        t.read(0.3)
        scr.feed(t.buf)
        t.buf = b''

    def editing(name, line, i):
        """line on the screen after the prompt, the cursor at line[i]"""
        settle()
        pos = i			# (EDIT writes the line over the prompt)
        r = scr.r - pos // W + (1 if scr.pending else 0)
        shown = scr.text(r, len(line))
        at = (scr.r - r) * W + scr.c + (1 if scr.pending else 0)
        check(name, shown == line and at == pos,
              'screen %r, cursor at %d (want %d)' % (shown, at, pos))

    try:
        t.until(r'BASIC prompt\) \? ', 60)
        t.send('\r')
        t.until(r'\n>')
        t.cmd('NEW')
        text = 'PRINT "' + 'abcdefghij' * 5 + '"'
        t.send('10 ' + text + '\r')
        t.until(r'\n>')
        listed = '   10 ' + text		# (LIST's form of the line)
        settle()

        t.send('EDIT 10\r')
        editing('EDIT: the line on two rows, the cursor at the start', listed, 0)
        t.send(DOWN)
        editing('down: to the end', listed, len(listed))
        t.send(UP)
        editing('up: to the start of the line', listed, 0)
        t.send(RIGHT * 12)
        editing('right: along the first row', listed, 12)
        t.send('X')
        listed = listed[:12] + 'X' + listed[12:]
        editing('insert on the first row', listed, 13)
        t.send(RIGHT * 40)
        editing('right: across the wrap', listed, 53)
        t.send(LEFT * 20)
        editing('left: back across the wrap', listed, 33)
        t.send(DOWN)
        editing('down: to the end', listed, len(listed))
        t.send(LEFT * (len(listed) - W + 1))
        editing('left: to the last column of the first row', listed, W - 1)
        t.send('Y')
        listed = listed[:W - 1] + 'Y' + listed[W - 1:]
        editing('insert in the last column', listed, W)
        t.send('\r')
        t.until(r'\n>')
        out = t.cmd('LIST')
        want = '   10 ' + text[:6] + 'X' + text[6:32] + 'Y' + text[32:]
        check('the edited line kept', want in out, repr(out))
        settle()

        t.cmd('NEW')
        t.send('10 A=1\r20 B=2\r')
        t.until(r'B=2\r*\n>')
        t.send('EDIT\r')
        settle()
        t.send('\r')
        t.until(r'\n>')
        out = t.cmd('LIST')
        check('plain EDIT: the first line only', out.split() == ['10', 'A=1', '20', 'B=2', '>'],
              repr(out))
        t.send('*BYE\r')
        t.read(1)
    finally:
        t.close()
    print('%d failed' % failed if failed else 'all ok')
    sys.exit(1 if failed else 0)


if __name__ == '__main__':
    main()
