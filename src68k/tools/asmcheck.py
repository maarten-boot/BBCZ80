#!/usr/bin/env python3
"""Check the 68000 inline assembler of the 68k BBC BASIC against ACK.

	asmcheck.py [-k]

Each instruction below is assembled by BASIC ([OPT 2: ... ] in bbcbasic
under Minix in r68k, tools/runminix.py) and by the ACK assembler (acc -c,
the text section of the object file); the bytes must be the same.  An
entry is "motorola" or ("motorola", "ack form") where ACK spells it
differently (it has no ADDI/ADDQ/CMPA... mnemonics: it picks the form
itself), or ("motorola", None, "hex") with the expected bytes where ACK
can't be used (68010, directives).  PC-relative forms and branches are
tested in test/bas (they depend on P%).
"""

import argparse
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.dirname(HERE)
TOP = os.path.dirname(SRC)
MINIX = os.environ.get('MINIX', os.path.join(os.path.dirname(TOP),
                                             'minix-st-2.0.4'))
ACC = os.path.join(MINIX, 'src', 'rosco', 'ack', 'acc')
WORK = os.path.join(TOP, 'build', 'asm')

INSNS = [
    # MOVE and friends
    'move.b d1,d2', 'move.w a1,d3', 'move.l (a0),(a1)',
    'move.l (a0)+,-(a1)', 'move.w 8(a0),-16(a1)',
    'move.l 2(a0,d1.w),4(a2,a3.l)', 'move.l 0x123456,0x234567',
    'move.b #0x12,d0', 'move.w #0x1234,(a0)', 'move.l #0x12345678,8(a6)',
    'move.l a0,d0', ('movea.l d0,a1', 'move.l d0,a1'), 'move.l d0,a1',
    ('movea.w (a0),a2', 'move.w (a0),a2'), 'move.w d0,ccr',
    'move.w (a0),sr', 'move.w sr,d0', 'move.l usp,a0', 'move.l a1,usp',
    ('moveq #100,d3', 'move.l #100,d3'), ('moveq #-100,d7', 'move.l #-100,d7'),
    ('move.w ccr,d0', None, '42c0'),
    ('move.l $123456,d0', 'move.l 0x123456,d0'),
    ('move.w #&ABCD,d1', 'move.w #0xABCD,d1'),
    ('move.l (8,a0),d0', 'move.l 8(a0),d0'),
    ('move.l (4,a1,d2.l),d0', 'move.l 4(a1,d2.l),d0'),
    ('move.l (a1,d2.w),d0', 'move.l 0(a1,d2.w),d0'),
    ('move.w $1234.w,d0', None, '30381234'),
    ('move.w (-2).w,d0', None, '3038fffe'),
    # ADD SUB
    'add.b d0,d1', 'add.w (a0),d2', 'add.l d3,(a4)', 'add.l d0,8(a6)',
    ('adda.w d0,a1', 'add.w d0,a1'), 'add.l d0,a1',
    ('adda.l #0x10000,a0', 'add.l #0x10000,a0'),
    ('addi.w #1000,d0', 'add.w #1000,d0'), 'add.l #100000,(a0)',
    'sub.l d0,d1', ('suba.l a0,a1', 'sub.l a0,a1'),
    ('subi.b #100,d0', 'sub.b #100,d0'), 'sub.w 4(a6),d7',
    # AND OR EOR
    'and.w d0,d1', 'and.l (a0),d0', 'and.b d0,(a0)',
    ('andi.w #0xff00,d0', 'and.w #0xff00,d0'), 'or.l d0,d1',
    ('ori.b #0x80,(a0)', 'or.b #0x80,(a0)'), 'eor.w d0,d1',
    ('eori.l #0x55555555,d0', 'eor.l #0x55555555,d0'),
    ('andi #0xfe,ccr', None, '023c00fe'), ('ori #0x700,sr', None, '007c0700'),
    ('eori #1,ccr', None, '0a3c0001'), ('and.b #0x1f,ccr', None, '023c001f'),
    # CMP
    'cmp.b d0,d1', 'cmp.w (a0),d1', ('cmpa.l a0,a1', 'cmp.l a0,a1'),
    'cmp.l a0,a1', ('cmpi.w #1000,d0', 'cmp.w #1000,d0'),
    ('cmpm.b (a0)+,(a1)+', None, 'b308'), ('cmp.l (a2)+,(a3)+', None, 'b78a'),
    # quick, X, BCD
    ('addq.l #1,d0', 'add.l #1,d0'), ('subq.w #8,a0', 'sub.w #8,a0'),
    ('addq.b #3,(a1)', 'add.b #3,(a1)'),
    'addx.l d0,d1', 'addx.b -(a0),-(a1)', 'subx.w d2,d3',
    'abcd d0,d1', 'sbcd -(a0),-(a1)',
    # one operand
    'clr.l d0', 'clr.b (a0)+', 'neg.w d1', 'negx.l (a0)', 'not.b d0',
    'tst.l 4(a6)', 'tas (a0)', 'nbcd d0', 'pea 8(a6)', 'jmp (a0)',
    'jsr 0x123456', 'jsr 4(a0,d1.w)', 'ext.w d0', 'ext.l d1', 'swap d2',
    ('EXT.W D0', None, '4880'), ('EXT.L D3', None, '48c3'),
    # shifts
    'asl.l #3,d0', 'asr.w d1,d2', 'lsl.b #8,d3', 'lsr.l d0,d1', 'rol.w #1,d0',
    'ror.l #4,d5', 'roxl.b #2,d1', 'roxr.w d0,d1', ('asl.w (a0)', None, 'e1d0'),
    ('lsr.w 4(a6)', None, 'e2ee0004'), ('lsl.l d0', None, 'e388'),
    # bits
    'btst #3,d0', 'btst d1,(a0)', 'bchg #7,(a0)', 'bclr d0,d1', 'bset #31,d2',
    # misc
    'lea 8(a6),a0', 'lea 0(a0,d0.l),a1', 'link a6,#-8', 'unlk a6',
    'exg d0,d1', ('exg a0,a1', None, 'c149'), 'exg d0,a1', ('exg a1,d0', None, 'c189'),
    'mulu d0,d1', 'muls (a0),d2', 'divu #10,d3', 'divs 8(a6),d4', 'chk d0,d1',
    'movem.l d0-d7/a0-a6,-(sp)', 'movem.l (sp)+,d0-d7/a0-a6',
    'movem.w d0/a0,(a1)', 'movem.w 8(a6),d0-d1',
    ('movem.l d3,-(sp)', None, '48e71000'),
    'movep.w d0,8(a0)', 'movep.l 4(a1),d2',
    'nop', 'rts', 'rte', 'rtr', 'reset', 'trapv', ('illegal', None, '4afc'),
    'trap #15', 'stop #0x2700', ('rtd #8', None, '4e740008'),
    'seq d0', 'sne (a0)', 'st d1', 'sf d2', 'shi 4(a6)', ('shs d3', None, '54c3'),
    # upper case (BASIC keywords inside: tokenised)
    ('MOVE.L D0,D1', 'move.l d0,d1'), ('AND.W D0,D1', 'and.w d0,d1'),
    ('EOR.L D0,D1', 'eor.l d0,d1'), ('NOT.W D0', 'not.w d0'),
    ('ORI.B #1,D0', 'or.b #1,d0'), ('DIVU D0,D1', 'divu d0,d1'),
    ('SWAP D3', 'swap d3'), ('MOVEM.L D0-D1,-(SP)', 'movem.l d0-d1,-(sp)'),
    ('ANDI.B #1,D0', 'and.b #1,d0'), ('EORI.W #1,D0', 'eor.w #1,d0'),
    ('MOVEA.L D0,A1', 'move.l d0,a1'), ('MOVEP.W D0,8(A0)', 'movep.w d0,8(a0)'),
    ('EXT.L D2', None, '48c2'), ('LEA 8(A6),A0', 'lea 8(a6),a0'),
    ('CLR.L -(SP)', 'clr.l -(sp)'), ('TST.B (A0)+', 'tst.b (a0)+'),
    # directives
    ('dc.b 1,2,"ab",-1', None, '01026162ff'), ('dc.w 0x1234,5', None, '12340005'),
    ('dc.l 0x12345678', None, '12345678'), ('ds.w 2', None, '00000000'),
    ('equd 0x01020304', None, '01020304'), ('equs "xyz"', None, '78797a'),
    ('equb 255', None, 'ff'), ('equw &BEEF', None, 'beef'),
]


def ack_bytes(text):
    src = os.path.join(WORK, 'a.s')
    obj = os.path.join(WORK, 'a.o')
    with open(src, 'w') as f:
        f.write('.sect .text\n.sect .rom\n.sect .data\n.sect .bss\n'
                '.sect .text\n\t%s\n' % text)
    r = subprocess.run([ACC, '-c', '-o', obj, src], capture_output=True,
                       text=True)
    if r.returncode:
        return 'ACK error: ' + (r.stdout + r.stderr).strip()
    with open(obj, 'rb') as f:
        b = f.read()
    foff, flen = int.from_bytes(b[28:32], 'little'), \
        int.from_bytes(b[32:36], 'little')
    return b[foff:foff + flen].hex()


def basic_prog(items):
    lines = ['10 DIM C% 64',
             '20 ON ERROR PRINT ;(ERL-100)/10;" ERR ";REPORT$:GOTO (ERL+10)']
    for i, (m, _, _) in enumerate(items):
        m = m.replace('0x', '&')
        lines.append('%d P%%=C%%:[OPT 2:%s:]:PROCh(%d)' % (100 + 10 * i, m, i))
    n = 100 + 10 * len(items)
    lines.append('%d END' % n)
    lines.append('%d DEF PROCh(i%%):LOCAL a%%:PRINT ;i%%;' % (n + 10))
    lines.append('%d FOR a%%=C%% TO P%%-1:PRINT " ";RIGHT$("0"+STR$~?a%%,2);'
                 ':NEXT:PRINT:ENDPROC' % (n + 20))
    return '\n'.join(lines) + '\nRUN\n*BYE\n'


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('-k', action='store_true')
    a = ap.parse_args()
    os.makedirs(WORK, exist_ok=True)
    items = []
    for e in INSNS:
        if isinstance(e, str):
            e = (e, e)
        m, ack = e[0], e[1]
        exp = e[2] if len(e) > 2 else ack_bytes(ack)
        items.append((m, ack, exp))
    prog = os.path.join(WORK, 'asm.in')
    with open(prog, 'w') as f:
        f.write(basic_prog(items))
    out = subprocess.run(
        [sys.executable, os.path.join(HERE, 'runminix.py'), '-t', '120',
         '-f', '/usr/bin/bbcbasic=' + os.path.join(SRC, 'bbcbasic'),
         '-f', '/usr/asm.in=' + prog, 'bbcbasic < /usr/asm.in'],
        capture_output=True).stdout.decode('latin-1').replace('\r', '')
    if a.k:
        with open(os.path.join(WORK, 'asm.out'), 'w') as f:
            f.write(out)
    got = {}
    for l in out.split('\n'):
        m = re.match(r'(\d+)( ERR .*|( [0-9A-F]{2})*)$', l)
        if m:
            got[int(m.group(1))] = m.group(2).replace(' ', '').lower() \
                if 'ERR' not in m.group(2) else m.group(2).strip()
    bad = 0
    for i, (m, ack, exp) in enumerate(items):
        g = got.get(i, '(no output)')
        if g != exp:
            bad += 1
            print('FAIL %-32s 68k %-24s expected %s' % (m, g, exp))
    print('%d of %d failed' % (bad, len(items)))
    sys.exit(1 if bad else 0)


main()
