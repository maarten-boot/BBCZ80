# What the Agon (eZ80) BBC BASIC can teach the 68k port

Review of 2026-10-23, after log entry 51. No code was changed; this is a list of
suggestions and plans.

* **Agon port:** <https://github.com/maarten-boot/agon-bbc-basic> (fork of
  <https://github.com/AgonPlatform/agon-bbc-basic>), at 2998edd. It is BBC
  BASIC (Z80) v5 in eZ80 ADL mode, so pointers and addresses are 24 bits. Its
  core comes from Dean Netherton's eZ80 port
  (<https://codeberg.org/envenomator/eZ80-for-rc-basic>, branch `agon`).
  Local clone: `../00__LATER/agon-bbc-basic`.
* **Why it matters here:** the Agon widened the same Z80 code from 16 to 24
  bits that this port widened to 32 bits. Its issue list is a list of the bugs
  that such a widening produces. Ten of its 40 issues were filed by
  R.T. Russell, probably from the same testing set he is applying to this
  port.
* **Upstream:** rtrussell/BBCZ80 is still at 410e7fb, the base of this port, so
  there is nothing newer from Russell to bring in.

Abbreviations below: **A#n** is Agon issue n
(`https://github.com/AgonPlatform/agon-bbc-basic/issues/n`), and a hash is an
Agon commit (`https://github.com/maarten-boot/agon-bbc-basic/commit/<hash>`).

## How it was checked

1. **Every core issue's repro program** was run on our Linux build
   (`build/host/linux/bbc68k`, at 8cdfce1) and on the Z80 original (RunCPM).
2. **The Agon conformance suite** (`tests/conformance/`, levels 1 to 5, 496
   tests) was run on both. The only change was the Agon-only `50 MODE 0`
   turned into a REM.
3. **The Agon's width fixes** (AUTO, SAVE/LOAD length, huge programs, LOCAL
   DIM, FNEND) were checked against our source and tested, including a
   228003-byte program saved and loaded again.
4. **Its 24-bit array work** was mapped onto our source.

## Priority 1: port bugs found (the Z80 does not have them)

These would show up in Russell's testing. Each has a repro program, and each
needs a test in `src68k/test/bas/`; the Z80 gives the reference for all of
them.

### 1.1 A whole-array assignment inside a loop, PROC or FN breaks it

```
10 DIM a%(3)
20 FOR I%=1 TO 3
30 a%()=I%
40 NEXT                 68k: "Not in a FOR loop at line 40"   Z80: fine
```
The same happens to `a%()=1,2,3` and `a%()=b%()*2`, inside REPEAT, WHILE, PROC
or FN: the `NEXT`, `UNTIL` or `ENDPROC` does not find its frame.

* **Cause:** in `LETARR` (`src68k/eval.s:1860-1890`), `move.l sp,d7` measures
  the temporary area while the element count is still pushed. The count is
  popped after that, so the `move.l (sp)+,sp` at the end leaves sp 4 bytes too
  low. At top level that goes unnoticed, which is why `t05arr` (top-level only)
  passes.
* **Fix:** compute the area from sp after the pop (or push `a0+4`).
* **Test:** whole-array assignment (single value, list and expression) inside
  FOR, REPEAT, WHILE, PROC and FN, followed by the loop end.
* Found by the conformance suite (`l1_core.bas:7020`, `l2_edge.bas:5050`).

### 1.2 `SUMLEN` returns garbage in the upper 16 bits

```
DIM s$(2):s$()="ab","cde","":PRINT SUMLEN(s$())     68k: 983045   Z80: 5
```
* **Cause:** `src68k/eval.s:1091` `clr.w d7` before a loop that does
  `add.l d7,d0`; it must be `clr.l d7`.
* Found by the conformance suite (`l1_core.bas:7200`, `l2_edge.bas:5230`).

### 1.3 LOAD (and CHAIN) of a program that does not fit hangs

```
LOAD "junk"      (a 4 MB file)       68k: hangs   Z80: "No room"
```
With a file that just fits, the result is a hang or "Bad program".

* **Cause:** `LOAD0` (`src68k/main.s:1102-1104`) lets the file fill memory up
  to `sp-256`. `os_load` (`src68k/osl.c:723`) is C code running on that same
  stack (`char fname[128]`, the `read()` frames), so the data overwrites the
  frames that are reading it.
* **Fix:**
  * `os_load` gets the file size first (lseek to the end, or fstat) and
    returns "no room" before reading anything;
  * the margin in LOAD0 grows to cover OSLOAD's own stack (for example
    1024).
* **Same area:** A#37 (still open on the Agon), bd3e373.
* **Platforms:** tested on the Linux build. The bare build uses the same
  `os_load`; Minix has its own OSLOAD path, to be checked.

### 1.4 Small array issues (inherited from the Z80, worse on the 68k)

* **`DIM(C%(),1)` sign-extends:** after `DIM C%(65535)` (65536 wraps to 0
  elements) it prints **-1**, where the Z80 prints 65535. The cause is the
  `sub.l #1,d0` after a 16-bit load at `src68k/eval.s:790`; `sub.w` would
  match the Z80.
* **`SUM()` over that 0-element array hangs:** the loops count down with
  `sub.l #1,d2 / bne` from 0 (4 billion iterations). The Z80 misbehaves too.
* **Both disappear with 32-bit array sizes (2.1).** Until then, `DIM` could
  refuse a dimension that wraps to 0.

### 1.5 `INKEY(-n)` returns TRUE

`PRINT INKEY(-99)` gives **-1**, so `IF INKEY(-99) THEN fire` always fires.
`src68k/osl.c:275` returns -1 for "not supported", and BASIC passes that on as
TRUE. The CP/M Z80 waits instead.

* **Minimal fix:** return 0 (key not pressed) for negative arguments.
* **Better:** see 3.3.

## Priority 2: 32-bit arrays (A#33, A#35)

Our port keeps the Z80's 16-bit array limits, although it has megabytes of
memory:
* `DIM A%(70000)` silently makes 4465 elements, and `A%(70000)` is
  `A%(4464)`;
* `DIM B%(300,300)` and `DIM a%(16383)` (64 KB of data) give "DIM space".

Russell filed exactly this against the Agon (A#33) and asked for either the
fix or a "DIM space" error.

**What the Agon did** (9348651, 5dcd02e, 09a749a, 691e2e3, 18f193d):
* **Header:** 1 byte for the number of dimensions, then 3 bytes per dimension
  (bound + 1); the element count is always recomputed.
* **Arithmetic:** MUL24 with overflow check; 24-bit bounds checks in subscripts
  (MAIN.Z80 GETV3), ARRLEN, DIM() and the dot product.
* **Loop counters:** whole-array loops test all 24 bits.
* **Null array pointer test:** extended to 24 bits (A#40). Ours is already
  right (`cmp.l #1` at exec2.s:1208, eval.s:600, main.s:1442).

**Our 16-bit places:**

| Routine | Location | 16-bit part |
|---|---|---|
| DIM | exec2.s:1221-1231 | 2-byte bound, `MUL16` on `d2.w` |
| X14OR5 | exec2.s:1133 | carry above 0xFFFF bytes |
| MUL16 | exec2.s:1143 | 16x16 multiply |
| ARRLEN | eval.s:572-580 | 2-byte dimensions |
| GETV3 (subscripts) | main.s:1453-1478 | `add.w`, `cmp.w` bound check, `and.l #0xFFFF` |
| DIMFUN | eval.s:785-790 | 2-byte dimension |
| ITEMA3 (string array copy) | eval.s:2019 | `mulu #6,d2` on `d2.w` |
| ARRDOT (dot product) | eval.s:2084-2119 | dimensions at -2/-1 |

The element loops of SUM, SUMLEN, MOD, LETARR and EXPRA, LOCAL arrays and SWAP
are already 32-bit.

**Plan:**
1. **Header format:** widen each dimension to 4 bytes (LE). That breaks
   programs that peek an array header with `^`/`!`, as the Agon's change did.
   Arrays are never saved, so files are not affected. Document the new layout
   in CONVENTIONS.md.
2. **MUL32:** an unsigned 32x32 multiply with overflow. The 68000 has only
   16-bit `mulu`, so use three `mulu`, with a fast path when both operands fit
   in 16 bits, because subscripts are speed-critical (check with
   `tools/bench.py`).
3. **Change the routines in the table:** 4-byte reads, MUL32 and `.l`
   arithmetic, with unsigned `cmp.l` bounds checks. Negative or huge subscripts
   then give "Subscript" instead of aliasing.
4. **Keep small arrays identical to the Z80:** t05arr, t11misc and
   u_arraytst must still match their `.ref`.
5. **Tests:** a hand-written `a03bigarr.in/.exp`, because the Z80 cannot run
   these:
   * `DIM A%(70000)` with its bounds: `DIM()`, `A%(70000)` and `A%(4464)`
     distinct, `A%(70001)` giving "Subscript";
   * `B%(300,300)`;
   * whole-array `=`, `+=`, `SUM`, `SUMLEN`, `MOD` and copying over more than
     65536 elements, also for string arrays;
   * a LOCAL big array, and SWAP;
   * a dot product with K > 65535;
   * `DIM X%(&7FFFFFFE)` giving "DIM space".

## Priority 3: features worth taking over

### 3.1 Start a program from the command line

The Agon autoloads or CHAINs a file named on its command line. Our PC program
takes no arguments (`host/hostmain.cpp:338`, `int main()`).

* **Suggestion:** `bbc68k prog` (or dropping a `.BBC` on `bbc68k.exe`) CHAINs
  it instead of starting the demo menu.
* **Scripts:** this would also let a script run a program without the
  "first key goes to the menu" rule.

### 3.2 Text programs: LOAD/SAVE by extension

The Agon loads and saves `.BAS`, `.TXT` and `.ASC` as plain text, and `.BBC`
tokenised. Our port only reads text through `*EXEC`; a 2000-line text program
worked that way, but slowly and with every line echoed.

* **Suggestion:** a text LOAD/SAVE in `osl.c`. For SAVE, the Agon's A#19
  (wrong indent register, fcc49c4) is the bug to avoid.

### 3.3 Negative INKEY

The Agon implements `INKEY(-n)` with RISC OS key numbers. A PC console cannot
see a key that is held down, so the realistic version is:
* `INKEY(-256)`: a platform number, which BBC programs use to tell machines
  apart;
* everything else: FALSE (1.5).

### 3.4 `TIME$`

The Agon (and the Acorn layer, `src/ACORN.Z80:92` GETIMS) returns the date and
time. Ours says "Sorry", as the CP/M Z80 does.

* **PC builds:** the host clock is right there.
* **rosco_m68k:** the board has no RTC, so "Sorry" stays there.
* **Format:** `Wed,23 Oct 2026.10:45:00`, as Russell's other versions.

### 3.5 AUTO with a step over 255

Our AUTO cuts the step to a byte silently, as the Z80 does
(`src68k/main.s:939`, `move.b d5,INCREM`). The Agon added an error for it
(56c304d, A#17). A "Silly" for a step above 255 costs one compare.

### 3.6 The conformance suite as a test

`tests/conformance/alltests.bas` found bugs 1.1 and 1.2 that our 25
differential tests missed. With the three array PROCs disabled, the 68k passes
496 of 496.

* **Plan:** add the level files (minus `MODE 0`) to `src68k/test/bas`, with
  `.exp` files taken from the 68k once 1.1 and 1.2 are fixed. Most levels also
  fit the CP/M Z80, so they can be `.ref` differential tests like the rest.
  The exceptions are the file levels (CP/M's 128-byte records change
  `EXT#`/`EOF#`) and the large arrays.

### 3.7 Huge programs as a test

The Agon has `tests/hugegen.bas` and `huge*.bas` (20000 to 50000 lines).
SAVE/LOAD of a 228003-byte program works on our port.

* **Plan:** a test that makes such a program in memory, SAVEs, LOADs and
  RUNs it, and LISTs a line above 65535 bytes from PAGE. This guards the
  32-bit program length, and 1.3 once it is fixed.

## Checked and not needed

| Agon issue | Our result |
|---|---|
| A#4 CASE TRUE, A#28 CASE with strings | same as the Z80 |
| A#9 `?` indirection | same as the Z80 |
| A#11 odd negative powers | same as the Z80 |
| A#12 PAGE on a page boundary | PAGE = &54200 |
| A#13 several LOCAL DIMs | same as the Z80 |
| A#16 RESTORE/GOTO/GOSUB above line 32767 | same as the Z80 |
| A#18 OLD | same as the Z80 |
| A#20 SAVE/LOAD length | 228003-byte round trip correct |
| A#22/#23 `=`, NEXT, UNTIL, ENDPROC, ENDWHILE out of context | the right error |
| A#24 NEW in a program | Mistake, as the Z80 |
| A#25 LIST IF | same as the Z80 |
| A#26 RESTORE DATA | "DATA not LOCAL", as the Z80 |
| A#30 DELETE | same as the Z80 |
| A#32 OPENUP | 0 for a missing file, PTR# = 0 |
| A#34 RESTORE LOCAL | no freeze |
| A#36 huge text input | No room per line, BASIC goes on |
| A#38 ON ERROR LOCAL in WHILE | no hang |
| A#39 GET$# BY with CHR$(128) | 128 bytes |
| HIMEM/stack placement (290048f) | not applicable: our stack is at HIMEM |
| MLT multiply speed-ups | not applicable: we already use `mulu` (exec2.s:1144, math.s) |

The Agon-only items do not apply: VDU/VDP, MOUSE, ADVAL joysticks, SOUND,
`*FX`, the MOS sysvars and the line selector `*<linenum>`.

## Suggested order

1. **1.1, 1.2 and 1.3 with their tests.** They are small fixes, and 1.1 is
   the one most likely to be hit by real programs. Then a new Windows zip.
2. **1.5 (INKEY minimal) and 1.4 (DIM wrap check).**
3. **3.6:** the conformance levels as tests.
4. **Priority 2,** 32-bit arrays, as its own branch with `a03bigarr`.
5. **3.1 to 3.5 and 3.7,** as wanted.

Scratch material from this review (repro programs, the suite's outputs) is in
the session scratchpad. It is not kept. The repro programs above are complete.
