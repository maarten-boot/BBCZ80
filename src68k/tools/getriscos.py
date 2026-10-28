#!/usr/bin/env python3
"""The RISC OS BBC BASIC Reference Manual (BASIC V/VI) as plain text, one
file per keyword, for writing the keyword tests (test/kw).

	getriscos.py [-o DIR]

The pages are fetched from https://www.riscos.com/support/developers/
(kept as DIR/html/*.html; delete them to fetch again).  Chapter 27,
Keywords, is split into DIR/keywords/NAME.txt: the description, Syntax,
Argument, Result, Example(s) and Associated keywords of each entry.  The
chapters of part 2 (the programming guide, with many example programs)
go to DIR/NN-name.txt.  DIR/KEYWORDS.txt lists the entries: whether this
port has the keyword (KEYWDS in main.s), whether it is left out here
(graphics, sound, the window manager, ARM: SKIPKW) and how many example
lines it has.  Default DIR: build/riscos.  The text is the manual's own
(its copyright is RISC OS Open's / Castle's): it stays in build/ and is
not committed.
"""

import argparse
import html
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.dirname(HERE)
TOP = os.path.dirname(SRC)
URL = 'https://www.riscos.com/support/developers/bbcbasic/'

# part 2 chapters kept (no screen modes, graphics, sprites, teletext,
# sound, the editor)
CHAPTERS = [
    ('part2/command', '03-command'), ('part2/simple', '04-simple'),
    ('part2/variables', '05-variables'), ('part2/numericvars', '06-numeric'),
    ('part2/bases', '07-bases'), ('part2/stringvars', '08-strings'),
    ('part2/arrays', '09-arrays'), ('part2/outputting', '10-output'),
    ('part2/inputting', '11-input'), ('part2/control', '12-control'),
    ('part2/procedures', '13-procs'), ('part2/datafiles', '14-files'),
    ('part2/accessmemlocs', '23-memory'), ('part2/errorhandling', '24-errors'),
    ('part2/vducontrol', '25-vdu'), ('appendices/numericrep', '28-numeric'),
    ('appendices/minabbreviations', '29-abbreviations'),
    ('appendices/errormessages', '30-errors'),
]
# keyword entries left out: graphics, sound, the window manager, ARM code,
# RISC OS calls (anchor names)
SKIPKW = {'BEAT', 'BEATS', 'CIRCLE', 'CLG', 'COLOUR', 'DRAW', 'ELLIPSE',
          'FILL', 'GCOL', 'LINE', 'MODE', 'MOUSE', 'MOVE', 'ORIGIN', 'PLOT',
          'POINT', 'RECTANGLE', 'SOUND', 'STEREO', 'SYS', 'TEMPO', 'TINT',
          'VOICES', 'WAIT', 'STOREA', 'STSTORE', 'LVBLNK', 'CREATE', 'EXPR',
          'MATCH', 'TOKENADDR', 'FSTA', 'FLDA', 'FADD', 'FSUB', 'FLOAD',
          'FIX', 'FSQRT', 'BBCMasterCompatibleCalls', 'OFF', 'CRUNCH',
          'TEXTLOAD', 'TEXTSAVE', 'TWIN', 'INSTALL', 'LIBRARY', 'LVAR',
          'HELP', 'EDIT', 'APPEND', 'marker_14488'}


def fetch(page, d):
    f = os.path.join(d, page.replace('/', '-') + '.html')
    if not os.path.exists(f):
        # (curl: Python's certificate check fails behind some proxies)
        subprocess.run(['curl', '-s', '-f', '-o', f, URL + page + '.html'], check=True)
    return open(f, encoding='latin-1').read()


def text(h):
    """HTML to plain text: <br> and paragraphs as new lines, images as
    their alt text"""
    h = re.sub(r'<img[^>]*alt="([^"]*)"[^>]*>', lambda m: m.group(1).strip(), h)
    h = re.sub(r'(?i)<br\s*/?>', '\n', h)
    h = re.sub(r'(?i)</p>|</h\d>|<dt>|</li>|</pre>', '\n', h)
    h = re.sub(r'<[^>]+>', '', h)
    h = html.unescape(h).replace('\xa0', ' ')
    lines = [l.rstrip() for l in h.split('\n')]
    out, blank = [], 0
    for l in lines:
        blank = blank + 1 if not l.strip() else 0
        if blank <= 1:
            out.append(l)
    return '\n'.join(out).strip() + '\n'


def entries(page):
    """[(anchor, title, {section: text})] of the keywords chapter"""
    parts = re.split(r'(?is)<hr><h2[^>]*><a name="([^"]+)"></a>(?:<a name="[^"]*"></a>)*(.*?)</h2>',
                     page)
    res = []
    for i in range(1, len(parts) - 2, 3):
        name, title, body = parts[i], text(parts[i + 1]).strip(), parts[i + 2]
        secs = re.split(r'(?is)<h5><a name="[^"]*"></a>(.*?)</h5>', body)
        d = {'': text(secs[0])}
        for k in range(1, len(secs) - 1, 2):
            d[text(secs[k]).strip()] = text(secs[k + 1])
        res.append((name, title, d))
    return res


def our_keywords():
    """the keywords of this port (as getmanual.py)"""
    words, on = set(), False
    with open(os.path.join(SRC, 'main.s'), encoding='latin-1') as f:
        for line in f:
            if line.startswith('KEYWDS:'):
                on = True
            elif line.startswith('CMDTAB'):
                break			# (KEYWDS, then COMNDS: AUTO .. SAVE)
            m = re.search(r'\.ascii\s+"([^"]*)"', line)
            if on and m:
                words.add(m.group(1).rstrip(' ('))
    # LISTO is LIST then O, SUMLEN SUM then LEN (as in the Z80 version)
    return words | {'TIME$', 'REPORT$', 'TOP', 'OPT', 'LISTO', 'SUMLEN'}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('-o', default=os.path.join(TOP, 'build', 'riscos'))
    a = ap.parse_args()
    hd = os.path.join(a.o, 'html')
    kd = os.path.join(a.o, 'keywords')
    os.makedirs(hd, exist_ok=True)
    os.makedirs(kd, exist_ok=True)
    for page, name in CHAPTERS:
        with open(os.path.join(a.o, name + '.txt'), 'w') as f:
            f.write(text(re.sub(r'(?s)^.*?<body[^>]*>', '', fetch(page, hd))))
    ours = our_keywords()
    rows = []
    for name, title, secs in entries(fetch('part3/keywords', hd)):
        out = [title, '', secs.get('', '').strip(), '']
        for k, v in secs.items():
            if k:
                out += [k + ':', v.rstrip(), '']
        fn = re.sub(r'[^A-Za-z0-9_]', '_', name)
        with open(os.path.join(kd, fn + '.txt'), 'w') as f:
            f.write('\n'.join(out).rstrip() + '\n')
        word = title.split()[0].rstrip('#') if title else name
        ex = sum(len([l for l in v.split('\n') if l.strip()])
                 for k, v in secs.items() if k.startswith('Example'))
        state = ('left out' if name in SKIPKW else
                 'ours' if word in ours else 'not in Z80/68k')
        rows.append('%-26s %-16s %-15s %3d example lines' % (fn, word, state, ex))
    with open(os.path.join(a.o, 'KEYWORDS.txt'), 'w') as f:
        f.write('\n'.join(rows) + '\n')
    print('%s: %d keyword entries, %d chapters' % (a.o, len(rows), len(CHAPTERS)),
          file=sys.stderr)


if __name__ == '__main__':
    main()
