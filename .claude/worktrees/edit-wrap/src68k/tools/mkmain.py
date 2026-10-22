#!/usr/bin/env python3
"""Make main.s from main.s.in: fill in the tables converted from MAIN.Z80
(tools/z80data.py).  Run from src68k: python3 tools/mkmain.py"""
import os, subprocess, sys
here = os.path.dirname(os.path.abspath(__file__))
src = os.path.join(here, '..', '..', 'src', 'MAIN.Z80')
def conv(a, b):
    return subprocess.run([sys.executable, os.path.join(here, 'z80data.py'),
                           src, str(a), str(b)], capture_output=True,
                          text=True, check=True).stdout.rstrip('\n')
# line ranges in MAIN.Z80: keywords + commands (316-647), error messages
# and indent tokens (662-832), LEXAN lists (2147-2157)
kw = conv(316, 647).replace('CMDTAB:\t.data2\tAUTO', '')
kw = '\n'.join(l for l in kw.split('\n') if '.data2' not in l)
s = open(os.path.join(here, '..', 'main.s.in')).read()
s = s.replace('@@KEYWORDS@@', kw)
s = s.replace('@@ERRWDS@@', conv(662, 832))
s = s.replace('@@LISTS@@', conv(2147, 2157))
open(os.path.join(here, '..', 'main.s'), 'w').write(s)
