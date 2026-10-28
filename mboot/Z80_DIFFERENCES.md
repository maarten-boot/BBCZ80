# BBC BASIC 68k and the Z80 version: the differences

These are the differences found between this port and the original Z80 BBC
BASIC (`bin/cpm/BBCBASIC.COM`, run under RunCPM 12fc57a). Most were found
while writing the tests from the BBC BASIC for Windows manual (`test/bas/k01`
to `k09`); four were already listed in the README.

Each difference has a test in `src68k/test/diff/`. These tests are not part
of the normal run (`bascheck` takes `test/bas/*.in`). Running one shows the
difference as a diff, the Z80 version's output against ours:

    BBC_EMU=host python3 tools/bascheck.py test/diff/d02pos.in

Three of them (d10, d11, d12) stall the Z80 run, because BASIC waits there or
the prompt does not start a line. For those the Z80 output below was taken by
hand.

## 1. Language: a deliberate difference in this port

| Test | Difference | Z80 | 68k |
|---|---|---|---|
| `d08desc` | **A string descriptor is 6 bytes, not 4**: length, maximum length, and a 4-byte address (the Z80: 2 bytes). Only programs that look at `^S$` see it. In the README. | `3 3 11 78 97 98` | `3 3 16 70 5 0` |
| `d09bigarr` | **Arrays can have more than 64K elements.** The Z80 version wraps a dimension at 65536, so `DIM A%(70000)` is `DIM A%(4464)`. In the README. Also `test/bas/x02bigarr`, `x06bigmem`. | `7 4464` | `7 70000` |
| `d10inkey256` | **`INKEY(-256)` is &44 (68)**, the number of this version, as R.T. Russell suggested. In the README. | waits for a key | `68` |
| `d11auto` | **`AUTO` with a step over 255 is "Silly".** The Z80 version keeps the low byte of the step (300 becomes 44). In the README. | `   10 ` (AUTO starts) | `Silly` |

## 2. A Z80 bug, now fixed there too

`RESTORE DATA` after `LOCAL X` and then `LOCAL DATA` in one PROC gave
"DATA not LOCAL" in the Z80 version; the manual allows it. R.T. Russell
fixed it on 2026-10-27 (BBCZ80 e4ae9ca, version 5.4: in `EXEC.Z80`,
`RESLO7` now goes to `RESLO8`, which sets the result flag), and notes it
is unlikely to matter in practice: leaving a PROC or FN does a RESTORE
DATA anyway. Our `RESLO7` already set the flag. His fix is merged here
(`bin/cpm/BBCBASIC.COM` too), so the test is now an ordinary one:
`test/bas/t18localdata` (was `test/diff/d01localdata`).

**Still open in 5.4** (`d13restoredata`): `RESTORE DATA` with no `LOCAL
DATA` should give "DATA not LOCAL" (54). The Z80 version does nothing,
without an error, when another LOCAL frame is on top: a `LOCAL X`, or an
`ON ERROR LOCAL`. In `RESLOC`, `RESLO2`'s `POP IX` (the variable's
address) overwrites `IX`, the "nothing restored" flag, so `RESLO8` finds
it non-zero. Ours gives the error in both cases.

| Test | Z80 5.4 | 68k |
|---|---|---|
| `d13restoredata` | `PROCa: no error`, `PROCb: no error` | `54 DATA not LOCAL` twice |
| `d14restoreerror` | `PROCa: no error`, `back from PROCa` | `outer: ON ERROR not LOCAL` |

The same cause makes `RESTORE ERROR` silent (`d14restoreerror`): `LOCAL
ERROR` does nothing in the Z80 version (`LOCERR`), so after `LOCAL I` and
`LOCAL ERROR` there is no saved handler, which should be "ON ERROR not
LOCAL" (53); the `LOCAL I` frame on top makes `RESLOC` report success.

## 3. Files and the console: CP/M against a modern file system

These come from CP/M, which counts a file's length in 128-byte records and
does not know the cursor position. The tests in `test/bas` avoid them.

| Test | Difference | Z80 (CP/M) | 68k |
|---|---|---|---|
| `d02pos` | **`POS`**: always 0 under CP/M; ours gives the column. | `abc0` | `abc3` |
| `d03extwrite` | **`EXT#` of a file open for writing**: 0 under CP/M until it is closed, then a multiple of 128. Ours gives the length. | `0 4`, then `128` | `4 4`, then `4` |
| `d04eof128` | **`EOF#` comes at a multiple of 128 bytes** under CP/M: a 1-byte file reads as 128 bytes (the rest is padding). | `128` | `1` |
| `d12type` | **`*TYPE` shows the padding.** Under RunCPM that is 121 NUL bytes after `hello`, and the prompt follows them on the same line. | `hello`, then 121 NULs | `hello` |
| `d05eranone` | **`*ERA` of a file that is not there**: CP/M's delete fails with "Bad command". | `Bad command` | `File not found` |
| `d06oscli` | **Spaces after the `*` in `OSCLI "*  ERA D08"`**: the Z80 version does not skip them; ours does (as BBC BASIC for Windows). | `Bad command`, file still there (`7`) | file deleted (`0`) |
| `d07openout` | **`OPENOUT ""`**: CP/M creates a file with a blank name and returns a channel. | `7` | `Bad name` |

## 4. Found and fixed in this port

| Test | Difference |
|---|---|
| `test/bas/k05star` | **`*ESC` on its own** gave "Bad command". The manual and the Z80 version treat it as `*ESC ON`. Fixed in `osl.c` (commit 3814dc8). |
| `test/kw/BPUT_HASH` | **`BPUT#c,48.9`** (a real value) gave "Invalid channel": SFIX overwrote the channel in d6. Fixed in `exec.s`. |
| `tools/hostcheck.py`, `fatcheck.py` | **`*DIR afsp`, `*ERA afsp`** (from R.T. Russell's feedback) and **`*OPT`** on its own. Fixed in `osl.c` (commit a137c0f). |

## 5. Checked: the same in both

Each of these looked like a difference at first, but the cause was the test
runner, which waits for a `>` at the start of a line:

* **`EXIT FOR I%` with the loops ended by one `NEXT J%,I%`.** Both versions
  end the program silently after `EXIT FOR I%`, with no error and without
  running the rest of the line. It may be a bug in both: the manual's example
  has a separate `NEXT J%` and `NEXT I%`, and with those both work.
* **`ON ERROR` typed at the prompt**, then an error: both print the error and
  carry on.

The Z80 version's limitations that the manual describes are the same in
ours. They are covered in `k09procs`:
* `ENDPROC` or `=` inside a FOR loop gives "Not in a PROC" or "Not in a FN".
* Leaving a FOR with GOTO into an UNTIL gives "Not in a REPEAT loop".

So are its quirks, covered in `k07errors`:
* `10 DIV 0` is -1 and `10 MOD 0` is 10, with no error.
* `FOR ... STEP 0` loops forever.
* `CASE` without `OF` gives error 37 with an empty message.
* Lowercase hex (`&ffff`) is "Bad hex or binary".

## Not compared

* **The assembler** is a 68000 assembler, not the Z80 one (`ASSEMBLER.md`).
  One related difference is in the README: with OPT 2, `dc.b 999` is "Out of
  range", where the Z80's `DEFB 999` keeps the low byte.
* **`INKEY(-n)`, a held key**, is always FALSE here, because the console
  cannot see held keys (README). It cannot be tested with typed input.
* **BBC BASIC for Windows features** that the Z80 version does not have
  either (structures, `PRIVATE`, 64-bit variables and so on) are left out
  of the tests.
