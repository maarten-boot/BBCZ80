#!/usr/bin/env python3
"""Compare the 68k FPP (src68k/math.s, test/mathtest under Minix in r68k)
bit for bit with the Z80 original (bin/cpm/BBCBASIC.COM under RunCPM).

	mathcheck.py [-n N] [-s SEED] [-o OPS] [-k]

N random vectors per operation (default 200), from SEED (default 1), for
the operations OPS (comma separated names or numbers, default all that
BASIC can express).  The Z80 side evaluates each vector as a BASIC
expression on variables whose 5 bytes are poked raw, so FPP sees exactly
the same operands.  Prints the mismatches and a summary; exit status 1 if
any.  -k keeps the work files in build/mathcheck.
"""

import argparse
import os
import random
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
# BBC_EMU=mame: the MAME rosco-emulator (runmame.py) instead of r68k
MAME = os.environ.get('BBC_EMU') == 'mame'
RUNNER = 'runmame.py' if MAME else 'runminix.py'
TOP = os.path.dirname(os.path.dirname(HERE))
WORK = os.path.join(TOP, 'build', 'mathcheck')

# op number: (name, BASIC statement computing C from A and B)
OPS = {
    0: ('AND', 'C=A AND B'), 1: ('DIV', 'C=A DIV B'), 2: ('EOR', 'C=A EOR B'),
    3: ('MOD', 'C=A MOD B'), 4: ('OR', 'C=A OR B'), 5: ('LE', 'C=A<=B'),
    6: ('NE', 'C=A<>B'), 7: ('GE', 'C=A>=B'), 8: ('LT', 'C=A<B'),
    9: ('EQ', 'C=A=B'), 10: ('MUL', 'C=A*B'), 11: ('ADD', 'C=A+B'),
    12: ('GT', 'C=A>B'), 13: ('SUB', 'C=A-B'), 14: ('POW', 'C=A^B'),
    15: ('DIVIDE', 'C=A/B'), 16: ('ABS', 'C=ABS(A)'), 17: ('ACS', 'C=ACS(A)'),
    18: ('ASN', 'C=ASN(A)'), 19: ('ATN', 'C=ATN(A)'), 20: ('COS', 'C=COS(A)'),
    21: ('DEG', 'C=DEG(A)'), 22: ('EXP', 'C=EXP(A)'), 23: ('INT', 'C=INT(A)'),
    24: ('LN', 'C=LN(A)'), 25: ('LOG', 'C=LOG(A)'), 26: ('NOT', 'C=NOT(A)'),
    27: ('RAD', 'C=RAD(A)'), 28: ('SGN', 'C=SGN(A)'), 29: ('SIN', 'C=SIN(A)'),
    30: ('SQR', 'C=SQR(A)'), 31: ('TAN', 'C=TAN(A)'), 35: ('PI', 'C=PI'),
    36: ('VAL', 'C=VAL(MID$(L$,4))'),
    37: ('STR', '@%=!^B:S$=STR$(A):@%=&90A'),
    44: ('SHL', 'C=A<<B'), 46: ('SAR', 'C=A>>B'), 47: ('SHR', 'C=A>>>B'),
}
BYNAME = {v[0]: k for k, v in OPS.items()}


def fl(r, lo, hi, sign=None):
    """Random float with exponent byte in [lo, hi]."""
    m = r.getrandbits(31)
    if sign is None:
        sign = r.random() < 0.5
    return (m | (0x80000000 if sign else 0), r.randint(lo, hi))


def it(r, bits=32):
    v = r.getrandbits(bits)
    if r.random() < 0.5:
        v = -v
    return (v & 0xFFFFFFFF, 0)


def num(r, kind):
    """A random operand of a broad kind."""
    if kind == 'int':
        return it(r, r.choice([4, 8, 16, 31, 32]))
    if kind == 'float':
        return fl(r, 0x60, 0xA0)
    if kind == 'wide':
        return fl(r, 1, 255)
    if kind == 'pos':
        return fl(r, 0x50, 0xB0, False)
    if kind == 'unit':
        return fl(r, 0x60, 0x7F)
    if kind == 'trig':
        return fl(r, 0x60, 0x90)
    if kind == 'exp':
        return fl(r, 0x60, 0x87)
    if kind == 'intf':
        return fl(r, 0x80, 0x9F)
    if kind == 'small':
        return (r.randint(-12, 12) & 0xFFFFFFFF, 0)
    if kind == 'shift':
        return (r.choice([0, 1, 7, 31, 32, 33, 255, 256, r.getrandbits(32)]), 0)
    if kind == 'zero':
        return (0, 0)
    raise ValueError(kind)


def operands(r, op):
    name = OPS[op][0]
    pick = r.random()
    if name in ('ADD', 'SUB', 'MUL', 'DIVIDE', 'LE', 'NE', 'GE', 'LT', 'EQ',
                'GT'):
        if pick < 0.3:
            return num(r, 'int'), num(r, 'int')
        if pick < 0.4:
            a = num(r, 'float')
            return a, (a if r.random() < 0.5 else num(r, 'int'))
        if pick < 0.5:
            a = num(r, 'float')
            return a, (a[0] ^ 0x80000000, a[1])
        if pick < 0.6:
            return num(r, 'wide'), num(r, 'wide')
        if pick < 0.65:
            return num(r, 'zero'), num(r, r.choice(['int', 'float']))
        if pick < 0.7:
            return num(r, r.choice(['int', 'float'])), num(r, 'zero')
        a = num(r, 'float')
        b = fl(r, max(1, a[1] - 40), min(255, a[1] + 40))
        return a, b
    if name in ('AND', 'OR', 'EOR', 'DIV', 'MOD'):
        if pick < 0.6:
            return num(r, 'int'), num(r, 'int')
        if pick < 0.7:
            return num(r, 'int'), num(r, 'small')
        return num(r, 'intf'), num(r, r.choice(['intf', 'int']))
    if name in ('SHL', 'SAR', 'SHR'):
        return num(r, r.choice(['int', 'int', 'intf'])), num(r, 'shift')
    if name == 'POW':
        if pick < 0.3:
            return num(r, 'small'), num(r, 'small')
        if pick < 0.6:
            return fl(r, 0x78, 0x88, False), num(r, 'small')
        if pick < 0.8:
            return fl(r, 0x70, 0x90, False), fl(r, 0x70, 0x84)
        return num(r, 'float'), num(r, r.choice(['small', 'float']))
    z = (0, 0)
    if name in ('ACS', 'ASN'):
        return (num(r, 'unit') if pick < 0.9 else num(r, 'float')), z
    if name in ('SIN', 'COS', 'TAN'):
        return (num(r, 'trig') if pick < 0.9 else num(r, 'wide')), z
    if name == 'EXP':
        return (num(r, 'exp') if pick < 0.9 else num(r, 'float')), z
    if name in ('LN', 'LOG', 'SQR'):
        return (num(r, 'pos') if pick < 0.9 else
                num(r, r.choice(['float', 'int', 'zero']))), z
    if name == 'PI':
        return z, z
    if name == 'STR':
        f = r.choice([0, 1, 2]) << 16 | r.randint(0, 12) << 8 | 0x01000000
        return num(r, r.choice(['int', 'float', 'wide', 'zero'])), (f, 0)
    return num(r, r.choice(['int', 'float', 'wide', 'zero'])), z


def valstring(r):
    """A random string for VAL."""
    k = r.random()
    if k < 0.3:
        s = str(r.randint(-10**r.randint(1, 12), 10**r.randint(1, 12)))
    elif k < 0.6:
        s = repr(r.uniform(-1, 1) * 10 ** r.randint(-40, 40))
        s = s.replace('e', 'E').replace('+', '')
    elif k < 0.8:
        s = '%.*f' % (r.randint(0, 12), r.uniform(-1e6, 1e6))
    else:
        s = r.choice(['', ' ', '  12', '+3.', '.5', '-.25E2', '1E', 'E5',
                      '1.2.3', '2147483647', '2147483648', '-2147483648',
                      '4294967296', '99999999999999999999', '1E38', '1E39',
                      '1E-38', '1E-39', '1E-45', '0.0', '-0', '12AB',
                      '1E+5', '1E-5', '1E100', '0000000000123', '1E123',
                      '3.14159265358979323846', '1E-2000'])
    return s[:60]


def vectors(ops, n, seed):
    r = random.Random(seed)
    out = []
    for op in ops:
        for _ in range(n if op != 35 else 1):
            if op == 36:
                out.append((op, valstring(r)))
                continue
            (m1, e1), (m2, e2) = operands(r, op)
            out.append((op, m1, e1, m2, e2))
    return out


def fmt(v):
    if v[0] == 36:
        return '24 ' + v[1]
    return '%02X %08X %02X %08X %02X' % v


BASIC = [
    '100 A=0:B=0:C=0:N%=0:F%=OPENIN "VEC.TXT":O%=OPENOUT "REF.TXT"',
    '200 ON ERROR BPUT#O%,STR$N%+" E"+STR$ERR:GOTO 900',
    '300 IF EOF#F% GOTO 1000',
    '400 L$=GET$#F%:IF LEN(L$)<3 GOTO 300',
    '500 N%=N%+1:K%=EVAL("&"+LEFT$(L$,2)):IF K%=36 GOTO 700',
    '550 P%=^A:!P%=EVAL("&"+MID$(L$,4,8)):'
    'P%?4=EVAL("&"+MID$(L$,13,2))',
    '600 P%=^B:!P%=EVAL("&"+MID$(L$,16,8)):P%?4=EVAL("&"+MID$(L$,25,2))',
    '700 CASE K% OF',
    # 701... WHEN lines
    '800 ENDCASE:IF K%=37 BPUT#O%,STR$N%+" "+CHR$34+S$+CHR$34:GOTO 900',
    '850 P%=^C:BPUT#O%,STR$N%+" "+RIGHT$("0000000"+STR$~!P%,8)+" "+'
    'RIGHT$("0"+STR$~P%?4,2)',
    '900 GOTO 300',
    '1000 CLOSE#F%:CLOSE#O%:PRINT "DONE"',
]


def run_ref(vecs):
    """Run the vectors on the Z80 BBC BASIC; return the result lines."""
    cpm = os.path.join(TOP, 'build', 'cpm', 'A', '0')
    os.makedirs(cpm, exist_ok=True)
    with open(os.path.join(cpm, 'VEC.TXT'), 'w') as f:
        for v in vecs:
            f.write(fmt(v) + '\n')
    ref = os.path.join(cpm, 'REF.TXT')
    if os.path.exists(ref):
        os.remove(ref)
    k = BASIC.index('700 CASE K% OF') + 1
    src = BASIC[:k]
    for i, op in enumerate(sorted({v[0] for v in vecs})):
        src.append('%d WHEN %d:%s' % (701 + i, op, OPS[op][1]))
    src += BASIC[k:] + ['RUN']
    p = subprocess.run([sys.executable, os.path.join(HERE, 'runcpm.py'),
                        '-t', '3600', '-'], input='\n'.join(src) + '\n',
                       capture_output=True, text=True)
    if 'DONE' not in p.stdout:
        sys.exit('mathcheck: Z80 run failed:\n' + p.stdout + p.stderr)
    with open(ref, 'rb') as f:
        data = f.read().decode('latin-1').replace('\0', '')
    res, dup = {}, []
    for l in re.split(r'[\r\n]', data):
        w = l.split(None, 1)
        if len(w) == 2 and w[0].isdigit():
            i = int(w[0]) - 1
            if i in res:
                dup.append((i, res[i], w[1]))
            res[i] = w[1]
    for i, first, second in dup:
        print('Z80: vector %d gave two results: %s, then %s' % (i, first, second))
    return [res.get(i, '?') for i in range(len(vecs))]


def run_68k(vecs, batch=500):
    if MAME:
        batch = 20000				# (no RAM root image limit)
    """Run the vectors on the 68k FPP under Minix, in batches (the input
    file goes into the root file system, which must fit in 1MB of RAM)."""
    src68k = os.path.dirname(HERE)
    subprocess.run(['make', '-s', '-C', src68k, 'test/mathtest'], check=True)
    res = []
    for i in range(0, len(vecs), batch):
        vec = os.path.join(WORK, 'vec.txt')
        with open(vec, 'w') as f:
            for v in vecs[i:i + batch]:
                f.write(fmt(v) + '\n')
        p = subprocess.run([sys.executable, os.path.join(HERE, RUNNER),
                            '-t', '3600',
                            '-f', '/usr/bin/mathtest=' + os.path.join(src68k, 'test', 'mathtest'),
                            '-f', '/usr/vec.txt=' + vec,
                            'mathtest < /usr/vec.txt'], capture_output=True, text=True)
        out = p.stdout.replace('\r', '')
        if 'BEGIN\n' not in out or '\nEND' not in out:
            sys.exit('mathcheck: 68k run failed:\n' + out[-2000:] + p.stderr)
        body = out[out.index('BEGIN\n') + 6:out.index('\nEND')]
        res += [l.strip() for l in body.split('\n') if l.strip()]
    return res


def norm68k(line):
    """68k "mmmmmmmm ee aa" or "Enn" -> comparable with the Z80 output."""
    if line.startswith('E') or line.startswith('"'):
        return line
    m, e, _a = line.split()
    return '%08X %02X' % (int(m, 16), int(e, 16))


def normz80(line):
    if line.startswith('"'):
        return '"' + line.strip('"').rstrip() + '"'
    if line.startswith('E') or line == '?':
        return line
    m, e = line.split()
    return '%08X %02X' % (int(m, 16), int(e, 16))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('-n', type=int, default=200)
    ap.add_argument('-s', type=int, default=1)
    ap.add_argument('-o', default='')
    ap.add_argument('-k', action='store_true')
    a = ap.parse_args()
    if a.o:
        ops = [int(x) if x.isdigit() else BYNAME[x.upper()] for x in a.o.split(',')]
    else:
        ops = sorted(OPS)
    os.makedirs(WORK, exist_ok=True)
    vecs = vectors(ops, a.n, a.s)
    ref = run_ref(vecs)
    got = run_68k(vecs)
    if len(ref) != len(vecs) or len(got) != len(vecs):
        sys.exit('mathcheck: %d vectors, %d Z80 results, %d 68k results'
                 % (len(vecs), len(ref), len(got)))
    bad = {}
    for v, r, g in zip(vecs, ref, got):
        if normz80(r) != norm68k(g):
            bad.setdefault(v[0], []).append((v, r, g))
    for op in ops:
        n = sum(1 for v in vecs if v[0] == op)
        b = bad.get(op, [])
        print('%-7s %4d vectors  %4d mismatches' % (OPS[op][0], n, len(b)))
        for v, r, g in b[:5]:
            print('    %s   z80 %-14s 68k %s' % (fmt(v), normz80(r), norm68k(g)))
    total = sum(len(b) for b in bad.values())
    print('total: %d vectors, %d mismatches' % (len(vecs), total))
    return 1 if total else 0


if __name__ == '__main__':
    sys.exit(main())
