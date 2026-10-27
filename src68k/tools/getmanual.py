#!/usr/bin/env python3
"""The parts of R.T. Russell's BBC BASIC for Windows manual that apply to
BBC BASIC on a text console, as plain text, for writing tests.

	getmanual.py [-o DIR]

The chapters are fetched from https://www.bbcbasic.co.uk/bbcwin/manual/
(kept as DIR/html/*.html; delete them to fetch again) and written as
DIR/NN-name.txt (default DIR: build/manual).  Left out: the IDE, graphics,
sound, MODE 7, the x86 assembler, the Windows API, serial ports, the
libraries and the hints, and in the chapters that are kept the sections
on those (SKIP).  The manual is for BBC BASIC for Windows, which has more
than the Z80 version this port follows: a keyword that is not in this
port's table (KEYWDS in main.s) is marked "[not in BBC BASIC Z80/68k]",
and KEYWORDS.txt lists both kinds.  The text is the manual's own (its
copyright is R.T. Russell's): it stays in build/ and is not committed.
"""

import argparse
import html
import html.parser
import os
import re
import subprocess
import sys
import textwrap

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.dirname(HERE)
TOP = os.path.dirname(SRC)
URL = 'https://www.bbcbasic.co.uk/bbcwin/manual/'

# (page, output name)
CHAPTERS = [
    ('bbcwin2', '02-general'),
    ('bbcwin4', '04-keywords-a-eof'),
    ('bbcwin5', '05-keywords-eof-lomem'),
    ('bbcwin6', '06-keywords-mid-print'),
    ('bbcwin7', '07-keywords-print-width'),
    ('bbcwin8', '08-star-commands'),
    ('bbcwin9', '09-files'),
    ('bbcwinb', '11-reference'),
    ('bbcwinc', '12-errors'),
    ('bbcwind', '13-memory'),
]

# sections (anchor names) left out: graphics, sound, mouse, Windows, the
# IDE; in chapter 8 everything before the star commands
SKIP = {
    'bbcwin2': {'winapistructs', 'hardcopy', 'unicode'},
    'bbcwinb': {'ascii'},
    'bbcwinc': {'iderrors'},
}
# keyword sections left out (chapters 4-7): graphics, sound, mouse, Windows
SKIPKW = {'circle', 'clg', 'colour', 'draw', 'ellipse', 'envelope', 'fill',
          'gcol', 'install', 'line', 'mode', 'mouse', 'move', 'off',
          'onclose', 'onmouse', 'onmove', 'onsys', 'ontime', 'origin', 'plot',
          'point', 'rectangle', 'sound', 'sys', 'tint', 'wait'}
FROM = {'bbcwin8': 'opsys'}		# start of what is kept


def fetch(page, d):
    path = os.path.join(d, page + '.html')
    if not os.path.exists(path):
        # (curl: Python's strict certificate check fails behind some
        # proxies that curl accepts)
        subprocess.run(['curl', '-sSf', '-o', path, URL + page + '.html'],
                       check=True)
    with open(path, 'rb') as f:
        return f.read().decode('latin-1')


class Text(html.parser.HTMLParser):
    """HTML to text, in sections: [(anchor, level, heading, text)]."""

    BLOCK = {'p', 'br', 'tr', 'div', 'hr', 'table', 'ul', 'ol', 'dl', 'dd'}

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.sections = [('', 0, '', [])]
        self.head = None		# level while in a heading
        self.htext = []
        self.anchor = ''
        self.pre = 0

    def out(self, s):
        self.sections[-1][3].append(s)

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag in ('h1', 'h2', 'h3', 'h4'):
            self.head, self.htext, self.anchor = int(tag[1]), [], ''
        elif tag == 'a' and 'name' in a and self.head:
            self.anchor = a['name']
        elif tag == 'pre':
            self.pre += 1
            self.out('\n\n')
        elif tag == 'li':
            self.out('\n* ')
        elif tag == 'dt':
            self.out('\n\n')
        elif tag in ('td', 'th'):
            self.out('  ')
        elif tag in self.BLOCK:
            self.out('\n\n' if tag == 'p' else '\n')

    def handle_endtag(self, tag):
        if tag in ('h1', 'h2', 'h3', 'h4') and self.head:
            title = ' '.join(''.join(self.htext).split())
            self.sections.append((self.anchor, self.head, title, []))
            self.head = None
        elif tag == 'pre':
            self.pre -= 1
            self.out('\n\n')
        elif tag in ('table', 'ul', 'ol', 'dl'):
            self.out('\n')

    def handle_data(self, data):
        if self.head:
            self.htext.append(data)
        elif self.pre:			# code: indented by 4
            self.out(re.sub(r'(?m)^(?=.)', '    ', data))
        else:
            self.out(re.sub(r'\s+', ' ', data))


def tidy(parts):
    """paragraphs separated by one empty line; code lines keep their indent"""
    out, blank = [], False
    for line in ''.join(parts).split('\n'):
        line = line.rstrip()
        if not line.strip():
            blank = bool(out)
            continue
        if blank:
            out.append('')
            blank = False
        out.append(line if line.startswith('    ')
                   else textwrap.fill(line.strip(), 76))
    return '\n'.join(out)


def our_keywords():
    """The keywords of this port: the strings of KEYWDS in main.s"""
    words, on = set(), False
    with open(os.path.join(SRC, 'main.s'), encoding='latin-1') as f:
        for line in f:
            if line.startswith('KEYWDS:'):
                on = True
            elif line.startswith('KEYWDL'):
                break
            m = re.search(r'\.ascii\s+"([^"]*)"', line)
            if on and m:
                words.add(m.group(1).rstrip(' ('))
    # TIME$ is TIME then $, TOP is TO then P, OPT is the assembler's
    return words | {'TIME$', 'TOP', 'OPT'}


def keyword_names(title):
    """'REPORT/REPORT$' -> ['REPORT', 'REPORT$']; 'ON ERROR' -> ['ON']"""
    names = []
    for t in title.split('/'):
        t = t.strip().split(' ')[0]
        if re.match(r'^[A-Z][A-Z0-9_]*\$?[#(]?$', t):
            names.append(t.rstrip('#('))
    return names


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('-o', default=os.path.join(TOP, 'build', 'manual'))
    a = ap.parse_args()
    hdir = os.path.join(a.o, 'html')
    os.makedirs(hdir, exist_ok=True)
    ours = our_keywords()
    kw_ours, kw_not = [], []
    for page, name in CHAPTERS:
        p = Text()
        p.feed(fetch(page, hdir))
        keywords = page in ('bbcwin4', 'bbcwin5', 'bbcwin6', 'bbcwin7')
        out = ['BBC BASIC for Windows manual, %s.html (R.T. Russell), the parts '
               'for a text console.\n%s%s.html\n' % (page, URL, page)]
        keep = page not in FROM
        skipping = None			# level of a skipped section
        for anchor, level, title, parts in p.sections:
            if not keep and anchor == FROM[page]:
                keep = True
            # (level 0: the text before the first heading; the page's
            # banner is two level-2 headings)
            if not keep or level == 0 or title.startswith('BBC BASIC for '):
                continue
            if skipping is not None and level > skipping:
                continue
            skipping = None
            if anchor in SKIP.get(page, ()) or keywords and anchor in SKIPKW:
                skipping = level
                out.append('\n[%s: left out]\n' % title)
                continue
            mark = ''
            if keywords and level == 2:
                names = keyword_names(title)
                missing = [n for n in names if n not in ours]
                if names:
                    if not missing:
                        kw_ours.append(title)
                    else:
                        kw_not.append(', '.join(missing))
                        mark = '  [%snot in BBC BASIC Z80/68k]' % (
                            '' if len(missing) == len(names)
                            else ', '.join(missing) + ' ')
            under = '=-~'[min(level, 3) - 1]
            head = title + mark
            out.append('\n%s\n%s\n' % (head, under * len(head)))
            body = tidy(parts)
            if body:
                out.append(body + '\n')
        with open(os.path.join(a.o, name + '.txt'), 'w') as f:
            f.write(html.unescape('\n'.join(out)))
        print('%s.txt' % name)
    with open(os.path.join(a.o, 'KEYWORDS.txt'), 'w') as f:
        f.write('Keywords described in the manual (the console ones)\n\n'
                'In BBC BASIC Z80/68k:\n  %s\n\nNot in BBC BASIC Z80/68k '
                '(BBC BASIC for Windows only):\n  %s\n'
                % ('\n  '.join(kw_ours), '\n  '.join(kw_not)))
    print('KEYWORDS.txt: %d keywords in this port, %d not' %
          (len(kw_ours), len(kw_not)))


main()
