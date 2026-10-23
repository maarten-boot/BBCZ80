#!/usr/bin/env python3
"""Convert Z80 DEFB/DEFM/DEFW data lines (M80 syntax) to ACK .data1/.ascii.

	z80data.py FILE FIRST LAST

Lines FIRST..LAST of FILE (1-based, inclusive).  Labels are kept, symbolic
DEFB operands (token names like TFN) are passed through, DEFW n becomes two
little-endian bytes, comments are kept as ACK '!' comments.
"""
import re
import sys

def num(tok):
    t = tok.strip()
    m = re.fullmatch(r"([0-9][0-9A-Fa-f]*)H", t)
    if m:
        return int(m.group(1), 16)
    if re.fullmatch(r"-?\d+", t):
        return int(t)
    if re.fullmatch(r"'.'", t):
        return ord(t[1])
    return None

def asc(s):
    return s.replace('\\', '\\\\').replace('"', '\\"')

f, a, b = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
lines = open(f, encoding='latin-1').read().split('\n')[a - 1:b]
for l in lines:
    code, _, com = l.partition(';')
    com = ('\t! ' + com.strip()) if com.strip() else ''
    m = re.match(r'^([A-Z0-9]+):?\s*(.*)$', code) if code[:1] not in ' \t' else None
    label = ''
    rest = code
    if m and code.strip():
        label, rest = m.group(1) + ':', m.group(2)
    rest = rest.strip()
    if not rest:
        if label or com:
            print(label + com)
        continue
    op, _, arg = rest.partition('\t' if '\t' in rest else ' ')
    op = op.upper(); arg = arg.strip()
    if op == 'DEFM':
        s = arg[1:-1].replace("''", "'")
        out = '.ascii\t"%s"' % asc(s)
    elif op == 'DEFB':
        n = num(arg)
        out = '.data1\t%s' % (('0x%02x' % (n & 0xff)) if n is not None else arg)
    elif op == 'DEFW':
        n = num(arg)
        if n is None:
            out = '.data2\t%s' % arg
        else:
            n &= 0xffff
            out = '.data1\t0x%02x,0x%02x' % (n & 0xff, n >> 8)
    elif op == 'EQU':
        out = None
        print('%s\t= %s%s' % (label[:-1], arg.replace('$', '.'), com))
        continue
    else:
        out = '! ' + rest
    print('%s\t%s%s' % (label, out, com))
