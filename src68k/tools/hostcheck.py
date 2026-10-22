#!/usr/bin/env python3
"""Host files for BBC BASIC as a PC program (src68k/host): the files of the
folder it runs in.

	hostcheck.py [linux] [windows]

For each program (build/host/linux/bbc68k; build/host/windows/bbc68k.exe
under Wine), in a new folder with one file in it: BASIC lines piped in
(programs saved, CHAINed in another case, a long name, a text file and a
binary file of 100000 bytes, a gap past the end, *MKDIR, *CD, paths,
*REN, *ERA, *RMDIR, the file that was there read, a path out of the
folder refused, *DIR), then the folder checked from here, byte by byte.
"""

import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
TOP = os.path.dirname(os.path.dirname(HERE))

SCRIPT = [
    '', 'NEW',
    '10 PRINT "saved on the host"', 'SAVE "PROG"', 'NEW', 'CHAIN "prog"',
    'SAVE "LongFileName.bbc"',
    'F%=OPENOUT "DATA.TXT":FOR I%=1 TO 3000:PRINT#F%,"line "+STR$I%:NEXT:CLOSE#F%',
    'F%=OPENOUT "BIG.BIN":FOR I%=0 TO 99999:BPUT#F%,I% MOD 251:NEXT:CLOSE#F%',
    'F%=OPENIN "BIG.BIN":E%=0:FOR I%=0 TO 99999:E%-=(BGET#F%<>(I% MOD 251)):NEXT:PRINT "errors ";E%;" size ";EXT#F%:CLOSE#F%',
    'F%=OPENUP "BIG.BIN":PTR#F%=110000:BPUT#F%,7:CLOSE#F%',
    '*MKDIR SUB', '*CD SUB', 'SAVE "INSUB"', '*CD ..', 'NEW', 'LOAD "SUB/INSUB"',
    'LIST', '*RMDIR SUB', '*ERA SUB/INSUB.BBC', '*RMDIR SUB',
    '*REN PROG2.BBC=PROG.BBC',
    'F%=OPENIN "there.txt":PRINT "there ";EXT#F%;" ";CHR$BGET#F%:CLOSE#F%',
    'F%=OPENOUT "../outside.txt"',
    '*DIR', '*BYE',
]


def run(kind):
    exe = os.path.join(TOP, 'build', 'host', kind, 'bbc68k.exe' if kind == 'windows' else 'bbc68k')
    failed = 0

    def check(name, ok):
        nonlocal failed
        print('%s  %s' % ('ok  ' if ok else 'FAIL', name))
        failed += not ok

    print('%s:' % kind)
    base = tempfile.mkdtemp(dir=os.path.join(TOP, 'build', 'host'))
    d = os.path.join(base, 'files')
    os.mkdir(d)
    with open(os.path.join(d, 'there.txt'), 'wb') as f:
        f.write(b'X from the host\n')
    inp = '\r'.join(SCRIPT).encode('latin-1') + b'\r'
    out = subprocess.run((['wine'] if kind == 'windows' else []) + [exe], input=inp, cwd=d,
                         capture_output=True, timeout=300).stdout.decode('latin-1').replace('\r', '')
    files = {n.lower(): n for n in os.listdir(d)}

    check('CHAIN "prog" ran PROG.BBC', 'saved on the host' in out)
    check('a long name: LongFileName.bbc', 'LongFileName.bbc' in os.listdir(d))
    data = open(os.path.join(d, files.get('data.txt', 'x')), 'rb').read() if 'data.txt' in files else b''
    want = b''.join(b'line %d\r' % i for i in range(1, 3001))
    check('DATA.TXT: 3000 lines, as on the host (%d bytes)' % len(data), data == want)
    big = open(os.path.join(d, files['big.bin']), 'rb').read() if 'big.bin' in files else b''
    pat = bytes(i % 251 for i in range(100000))
    check('BIG.BIN read back by BASIC', re.search(r'errors 0 size *100000', out) is not None)
    check('BIG.BIN on the host: the bytes, a gap of zeros, 7 at 110000',
          len(big) == 110001 and big[:100000] == pat and big[100000:110000] == bytes(10000)
          and big[110000] == 7)
    check('*MKDIR, *CD, SAVE in it, LOAD "SUB/INSUB"', 'saved on the host' in out.split('LOAD "SUB/INSUB"')[-1])
    check('*RMDIR of a full directory is refused', 'not empty' in out)
    check('*ERA, *RMDIR: SUB is gone', 'sub' not in files)
    check('*REN: PROG2.BBC, no PROG.BBC', 'prog2.bbc' in files and 'prog.bbc' not in files)
    check('a file that was there: read', re.search(r'there *16 X', out) is not None)
    check('"../outside.txt" refused, nothing written outside',
          not os.path.exists(os.path.join(base, 'outside.txt')))
    check('*DIR lists the folder', 'Files:' in out and 'there.txt' in out and 'BIG.BIN' in out)
    if failed:
        print(out[-1500:])
    return failed


def main():
    kinds = sys.argv[1:] or ['linux', 'windows']
    failed = sum(run(k) for k in kinds)
    print('all ok' if not failed else '%d failed' % failed)
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
