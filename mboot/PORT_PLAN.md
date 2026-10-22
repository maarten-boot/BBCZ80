# PLAN: BBC BASIC (Z80) v5 → 68000 assembly for Minix on the rosco_m68k

Status: plan agreed (D1–D3 decided), 2026-10-20. Nothing in `src/` has been changed.

---

## 1. Goal

Translate the BBC BASIC (Z80) v5.00 interpreter (`src/*.Z80`, ~15,100 lines) into
68000 assembly that assembles with the **Amsterdam Compiler Kit (ACK)**, and run it
as an ordinary user program on **Minix-ST 2.0.4 on the rosco_m68k**
(<https://github.com/maarten-boot/minix-st-2.0.4/tree/rosco-m68k>).

## 2. The target, as found in the rosco-m68k branch

* **CPU:** MC68010 @ 10 MHz, no MMU or FPU, 1 MB RAM. On a 68010,
  `move sr,<ea>` is privileged in user mode. Use `move ccr` instead.
* **OS:** Minix 2.0.4 (Atari ST port) with a DUART serial console. Programs are
  relocatable. MM relocates them at exec time (GEMDOS-style), and
  "shadowing" provides fork() without an MMU.
* **Compiler:** the branch already builds a **host cross ACK** for the
  `minix68k` platform (m68k2, **16-bit int**):
  * `src/rosco/ack/build-ack.sh` builds davidgiven/ack at `7afa32a0` with
    `ack-minix68k.patch`.
  * `src/rosco/ack/acc` runs `ack -mminix68k`.
  * `src/rosco/ack/acc-minix` compiles and links with the Minix libc:
    `crtso.o emrts.o <objs> libc.a libem.a libend.a`. Its `-S` option sets the
    stack size.
  * The same ACK is also built as a native `cc` on the target.
  * The local `/home/mboot/DEV/ack` is at the same commit, but it was built
    only for `linux`/`linux386`, so it cannot be used as it is.
* **Assembler syntax (ACK `as`):** Motorola mnemonics (`move.l`, `movem.l`),
  `!` comments, `.sect .text/.rom/.data/.bss`, `.define` (export),
  `.extern`, `.data1/.data2/.data4`, `.space`, `.align`, `.comm`, and
  numeric local labels (`1f`/`1b`). C symbols get a leading `_`
  (`_main`, `_write`).
* **C calling convention (ACK m68k2):** arguments are pushed right to left;
  `int` is 2 bytes and `long`/pointers are 4. The caller pops the arguments.
  Results come back in `d0` (a long in `d0`, `d0:d1` for 8 bytes). Assume
  that only `d0-d2/a0-a1` may be clobbered. **To verify** against ncg output
  before relying on it.
* **Test environments:** r68k with the DUART patch (`make run`), MAME
  rosco-emulator (`make runmame`, scripted with `tools/mamesession.py`), and
  the real board.

## 3. What the Z80 code looks like

| Module | Lines | Port strategy |
|---|---:|---|
| MAIN | 2235 | Translate (generic core) |
| EXEC | 3293 | Translate (generic core) |
| EVAL | 2591 | Translate (generic core) |
| MATH | 2255 | Translate. The 40-bit float (32-bit mantissa + 8-bit exponent) maps directly onto 68k data registers |
| ASMB | 1009 | Z80 assembler: **replace** (see decision D3) |
| DATA | 68 | Translate as `.bss` |
| CMOS + DIST + HOOK | 1794 | **Replace** with a new `MINIX.s` OS layer that calls libc |
| AMOS + ACORN | 1873 | Not needed (Acorn Tube edition) |

The code makes heavy use of Z80 idioms: the shadow register set (`EXX`, 156×
in MATH), IX/IY as pointers (about 600 uses), and flags as boolean return
values (`CP A` = Z/NC "good return"). Numbers live in register groups:

* integer: `HLH'L'` (32-bit), with C = 0 as the "exponent";
* float: `HLH'L'` mantissa plus C exponent; the second operand is in
  `DED'E'` + B.

### Proposed register mapping (to finalise in phase 1)

| Z80 | 68000 | Note |
|---|---|---|
| `HLH'L'` + C (accumulator) | `d0.l` mantissa, `d1.b` exponent | One register replaces each 32-bit pair group |
| `DED'E'` + B (2nd operand) | `d2.l` mantissa, `d3.b` exponent | |
| A | `d4.b` | |
| BC / DE / HL used as pointers | `a1` / `a2` / `a3` (plus `d5`/`d6` for counts) | |
| IY (program text pointer) | `a4` | |
| IX (variable/stack-frame pointer) | `a5` | |
| SP | `sp` (`a7`) | BASIC stack = the process stack |
| flags as results | CCR | Keep the Z/C conventions; on 68k Z and C are set by `cmp`/`tst`/`sub` the same way. Watch out: 68k `move` and `add` to address registers set the flags differently from Z80 `LD` and `INC rr` |
| (new) | `a6` | Kept free for C calls (ACK frame pointer) |

## 4. Decisions

**Decided 2026-10-20:** D1 = (a) 32-bit pointers; D2 = keep BASIC-visible memory
little-endian; D3 = stub first, 68000 assembler in a later phase.

* **D1. Memory model.** Z80 BASIC stores 16-bit pointers inside its data
  structures: line links, variable chains, PAGE/LOMEM/HIMEM, and the FN/PROC
  stack frames.
  * (a) **32-bit pointers throughout.** Recommended. User-visible addresses
    (`^`, `!`, `DIM`, `END`) are real addresses, and the workspace can grow
    past 64 KB. Integers are already 32-bit, so BASIC programs see no change.
    The cost is that every structure that stores a pointer must be widened.
  * (b) Keep a 64 KB workspace addressed as base register + 16-bit offset.
    This is a more mechanical translation, but it limits memory and makes
    `^` addresses relative.
* **D2. Byte order.** BBC BASIC defines `!` (32-bit indirection) and the
  stored integer/float formats as **little-endian**, and the program file
  format has little-endian line numbers. The 68k is big-endian.
  * Recommended: keep memory formats little-endian wherever BASIC can see them
    (`!`, `]`/`|` variable storage, program files), using `ror.w #8` / `swap`
    in the load/store routines. Tokenized `.BBC` files, including `tests/*`,
    then load unchanged, and program behaviour matches other BBC BASICs.
* **D3. Inline assembler.** ASMB.Z80 assembles Z80 code, which is useless on a
  68k. Options:
  * (a) Initially report "Not supported" for `[`…`]`. Recommended.
  * (b) Later, write a 68000 assembler (as BBC BASIC for Windows and BBCSDL
    have their own CPU assemblers).

  `CALL`/`USR` become calls to 68k machine code in either case.
* **D4. OS layer (`MINIX.s`)**, built on libc:
  * console: `read`/`write` on fd 0/1, with termios raw mode for `GET`/`INKEY`;
  * files: `open`/`close`/`read`/`write`/`lseek`, with `PTR#`, `EXT#` and
    `EOF#` emulated using a small buffer per channel;
  * `TIME`: `times()`/`time()`;
  * `*` commands: `*BYE`, `*DIR`, plus `system()` for anything else;
  * `ESCAPE`: Ctrl-C via a SIGINT handler that sets a flag polled by the
    interpreter;
  * the graphics and sound hooks (HOOK.Z80) stay as "Not implemented" errors.

## 5. Phases

0. **Toolchain.** Build the minix68k ACK (`src/rosco/ack/build-ack.sh` in the
   Minix checkout). Assemble and link a "hello" in ACK assembly that calls
   `_write`, and run it under r68k/MAME. Confirm the register-preservation
   convention.
1. **Conventions.** Settle the register map and pointer width, and write
   macros/idioms for the common Z80 patterns (EXX groups, `DJNZ`, flag
   returns). Set up the source layout as `src68k/*.s` plus a Makefile using
   `acc-minix`.
2. **MATH.** Self-contained, so it can be tested on its own. Write a small C
   test driver that calls the FPP entry and compares the results with known
   values, including values taken from running the Z80 build in a CP/M
   emulator.
3. **MINIX.s OS layer**, plus the DATA module.
4. **MAIN + EVAL + EXEC**, in that order. First milestone: the `>` prompt,
   `PRINT 2+2`, `LIST`/`RUN` of a typed-in program.
5. **Files and the tests.** `LOAD`/`SAVE`/`CHAIN`, then run `tests/ALLTESTS.BBC`.
6. Optional: the 68000 inline assembler, a speed pass, and an install into the
   rosco root file system (`rootfs/proto`).

## 6. Risks

* Flag semantics differ subtly between the Z80 and the 68k (Z80 `INC`/`DEC`
  of 16-bit registers do not set flags; 68k `addq` to an address register
  doesn't either, but to a data register it does). A mechanical
  line-by-line translation will contain bugs, so translate routine by routine
  and test as we go.
* ACK `as` quirks: limited expression syntax, and branch-size selection.
* The 16-bit-int C ABI when calling libc: pass `int` arguments as words.
* The stack: Z80 BASIC keeps its own stack below HIMEM. The Minix stack size
  is fixed at link time (`acc-minix -S`), so give it enough.

## 7. Phase 0 results (2026-10-20): done

* The Minix checkout is at `/home/mboot/vibe/minix-st-2.0.4` (branch
  `rosco-m68k`, `841f10b`). The following were built there, and none of its
  files were changed:
  * the ACK for minix68k (`src/rosco/ack/build-ack.sh`, cloned from the local
    `/home/mboot/DEV/ack`);
  * the ACK libc (`make -C src/rosco/ack/lib`);
  * the system image (`make` in `src/rosco`);
  * r68k (`src/rosco/emu/build-r68k.sh`).
* **Podman:** `docker` on this host is rootless podman, and `xrun`'s `-u uid:gid`
  cannot write to the mounted tree. Set `PODMAN_USERNS=keep-id` in the
  environment for any build that uses `xrun`.
* **ACK C ABI confirmed** from the `ncg` output:
  * a C function saves and restores the register variables it uses
    (`movem.l d7/a5/a4`, taken from d3–d7 and a2–a5);
  * d0–d2/a0–a1 are scratch, and a6 is the frame pointer (`link`/`unlk`);
  * results come back in d0;
  * `int` arguments are words; the caller pops the arguments;
  * 32-bit multiply/divide go through EM helpers (`.mli` etc., arguments on the
    stack).

  So the interpreter may keep its state in d3–d7/a2–a5 across libc calls.
* `src68k/test/hello.s` is ACK assembly that calls `_write`. It is linked with
  `acc-minix` into a 776-byte Minix a.out.
* `src68k/tools/runminix.py` builds a root image (the stock proto plus `-f`
  files) and `ROSCODE1.BIN` in `build/minix`, boots r68k, logs in as root,
  and runs commands. Result: `hello from 68k`, `rc=0`.
* **Caution:**
  * Under r68k the kernel detects a **68020**, but the board is a 68010. The
    emulator will not catch 68020-only instructions (`mul.l`/`div.l`,
    `extb.l`, scaled indexing, bit fields), so avoid them by rule.
  * Minix reports `Available = 330K` for user programs, which is the memory
    budget for BASIC's code, its workspace and its stack.

## 8. Phase 1 results (2026-10-20): done

* `src68k/CONVENTIONS.md` covers:
  * the ACK dialect, as probed (quick forms and branch sizes are chosen
    automatically; `[ ]` groups expressions; cpp runs only when line 1 is `#`;
    function-like macros cannot contain immediates);
  * the register map (a4 = IY, a5 = IX, d4.b = A, d0.l/d1.b = accumulator,
    d2.l/d3.b = second operand);
  * the flag rules (no saving of CCR; `move.w #n,ccr` for status returns);
  * the memory rules (32-bit pointers; little-endian, byte-wise access to
    BASIC data);
  * the C ABI and the run-time layout.
* `src68k/Makefile` (`make`, `make check`), `bbc.h`, and `util.s` (`LDLE4`,
  `STLE4`, `LDLE2`, `STLE2`), with `test/utiltest.s` passing at odd
  addresses on r68k.
* **r68k bug found and fixed locally** (`/home/mboot/vibe/r68k`,
  `main.cpp`, not committed):
  * the illegal-instruction callback returned "handled" for every illegal
    opcode, not just the firmware-trap magic, so illegal instructions were
    skipped silently;
  * the Minix CPU probe (`movec cacr`) therefore reported a 68020;
  * after the fix the kernel reports a 68010, and `illegal`/`extb` raise
    SIGILL;
  * `runminix.py` uses `../r68k/r68k` when it exists (`-e` or `$R68K`
    override this).
* MAME rosco-emulator (`maarten-boot/rosco-emulator`, branch
  `rosco-m68k-ram-bios`) is cloned to `/home/mboot/vibe/rosco-emulator`. It is
  not built yet: SDL2, GL, ALSA, PulseAudio, Xinerama, Xi and Qt6 dev packages
  are missing, and installing them needs sudo.
* **Next:** phase 2, MATH (`math.s`) with a test driver.

## 9. Phase 2 (MATH), 2026-10-20

* `src68k/math.s` is the complete translation of MATH.Z80, about 1,500
  lines:
  * FPP dispatch;
  * integer and float arithmetic, compares and shifts;
  * ABS, SGN, INT, NOT, SQR, SIN, COS, TAN, ATN, ASN, ACS, EXP, LN, LOG,
    DEG, RAD and PI;
  * integer and float powers;
  * STR$ and VAL with POWR10, CON and GETEXP.
* **Method:** each routine is rewritten for 32-bit registers, but makes
  exactly the same truncation, guard-bit and rounding decisions as the Z80.
  * The primitives (the DIVA/DIVB restoring division and the SQRA/SQRB
    square root) are transliterated.
  * Z80 quirks are kept:
    * the carry-in to ICP0 from FPOW, which decrements HL;
    * the sticky A' in FIX;
    * the STR digit stack of (A, flags) entries.
* **Reference:** the Z80 BBC BASIC itself. `src68k/tools/runcpm.py` drives
  `bin/cpm/BBCBASIC.COM` under RunCPM (built in `/home/mboot/vibe/RunCPM`).
  `src68k/tools/mathcheck.py` does the comparison:
  * it generates random operands per operation and pokes their raw 5 bytes
    into BASIC variables;
  * it evaluates each one there (`C=A+B`, `C=SIN(A)`, `STR$`, `VAL` …);
  * it runs the same vectors through `test/mathtest` (C driver + FPP)
    under Minix in r68k, in batches of 500, because the root image must fit
    in 1 MB;
  * it compares the results bit for bit.
* **Result:** all 39 operations BASIC can express match: 0 mismatches in
  7,401 vectors with seed 2 and again with seed 7. FIX, FLOAT, TEST,
  COMPARE, ZERO, FONE and TRUE have no BASIC syntax, and are covered only
  through the other operations.
* **Bugs found by the comparison:**
  * LN lost its exponent across ZERO; the Z80 keeps it in A'.
  * In ATN and in IPOW, a 68k `move` between the flag-setting instruction
    and the branch destroyed the flags, where a Z80 `LD` keeps them.
    CONVENTIONS §3.3 warns about exactly this.

## 10. Phase 3 (OS layer), 2026-10-20

**Decisions (user):**
* The OS layer is written in **C behind an assembly glue**. The
  interpreter itself stays assembly.
* Unknown `*` commands go to `/bin/sh`.
* A name without `.` gets `.BBC`; an existing `.bbc` file is used instead.

**Files:** `data.s` (DATA, 32-bit pointers), `osl.c`, `minix.s`,
`hook.s`, and the test monitor `test/osmon.s` (`make oscheck`).

**Implemented:**
* **Console:** raw termios with OPOST off, buffered output, and the CP/M
  line editor (control keys plus vt100 cursor keys, insert/overwrite,
  EDIT n → LIST capture).
* **ESCape:** `*ESC ON/OFF`; TRAP samples the keyboard every 20th call;
  piped (non-tty) input is read as plain lines. (Since §18 ESC raises a
  SIGINT instead, and TRAP only flushes the output.)
* **Files:** channels 1–7 with a 512-byte buffer each, exact
  PTR#/EXT#/EOF#, and the last-byte carry on BGET#. LOAD and SAVE.
* **Commands:**
  * `*SPOOL` and `*EXEC`;
  * `*BYE`, `*QUIT`, `*CD`, `*DIR`/`*.`, `*ERA`/`*ERASE`,
    `*REN`/`*RENAME` (new=old), `*TYPE`, `*ESC`, `*OPT`, `*HELP`,
    `*LOAD`, `*SAVE`, `*RESET`, with `.` abbreviations;
  * anything else runs in the shell.
* **Time and cursor:** TIME from `times()`; CLS and TAB(x,y) as vt100;
  POS is tracked.

**Tested on r68k** (scripted and through a real tty): files, LOAD/SAVE,
errors, `*` commands, SPOOL/EXEC, the editor keys, ESCape (in OSLINE and
in a TRAP loop, and `*ESC OFF`), OSKEY timeout and keys, TIME and cursor.

**Findings:**
* **Memory:** with 1 MB, Minix leaves about 330 KB. A forked BASIC needs a
  second full copy, and then there is no hole for `/bin/sh`: `*` shell
  commands give "No room" unless BASIC is small. With 2 MB
  (`R68K_RAM=2M`) they work. The fork/exec is done in `osl.c` (not
  `system()`) so that ENOMEM is reported.
* **Lone ESC:** the rosco console driver (`kernel/roscons.c`, debug keys
  ESC O P/Q/R/S) holds back a lone ESC until the next key arrives, so
  BASIC's ESCape only takes effect at the next keypress on the console.
  To be decided: a kernel change (release the ESC after a short timeout),
  or an extra escape key in BASIC. (Done in §18: the kernel timeout.)
* **Alignment:** `.align 256` is not honoured in `.bss`.

## 11. Phase 4 (MAIN, EVAL, EXEC), 2026-10-20: first milestone reached

**Sources:**
* `main.s.in`: `main.s` is generated by `tools/mkmain.py`, which takes the
  keyword and error tables from MAIN.Z80.
* `eval.s`, `exec.s`, `exec2.s` (EXEC part 2: FN/PROC, LOCAL, arguments,
  assignment, string storage, DIM).
* `asmb.s`: a stub; the assembler gives "Not supported".
* `make bbcbasic` links these with math/data and the OS layer (about
  36 KB).
* PHASE4.md holds the layouts and register contracts.

**Test harness:** `tools/bascheck.py` (`make bascheck`). Each
`test/bas/*.in` is typed into the original BBCBASIC.COM under RunCPM
(cached as `.ref`) and into `bbcbasic < file` under Minix in r68k. The
outputs are compared line for line. 9 suites cover:
* statements, loops, FN/PROC (recursion, RETURN parameters, array
  parameters, LOCAL);
* arrays (whole-array operations, dot product, indirection);
* errors (ON ERROR, ON ERROR LOCAL, EVAL);
* number formatting (@%) and string functions;
* the commands RENUM, DELETE, LISTO, NEW/OLD, LIST ranges and CLEAR.

**All 9 match the Z80.** MATH STR/VAL are still bit-exact after the STR
change for 32-bit pointers.

**Bugs found by the tests:**
* **ACK assembler:** a `bsr` to the next instruction is assembled as a
  `nop`. Frame markers (WHICHK, PROCHK, RETCHK, LOCCHK, ARRCHK) use
  `pea LABEL` instead (CONVENTIONS §9).
* **Flags clobbered by `move`:**
  * before a conditional branch: GOTO1, ITEMA, RESDEL, LEFT$/RIGHT$
    assignment;
  * BINDIG returned its carry inverted.
* **Lexer left mode:** the Z80 `DEC C` ends left mode after the first
  item, so a later `*` was taken as a star command and tokenising stopped.
* **Register clobbers:**
  * STDESC clobbered a0;
  * NXT clobbered the type in ARGUE (array parameters);
  * INSTR lost its start offset;
  * `DIM()` left a high word set.
* **Stack discipline:**
  * POPS callers pushed d0 on top of the string;
  * UNSTK1/RETXFR popped one return address too many;
  * the ENDWHILE frame offset was wrong.

**Later the same day: 20 suites, all matching.**
* New suites: t10 (files, SAVE/LOAD/CHAIN), t11 (CASE, EXIT, DIM LOCAL,
  string heap, TRACE, deep recursion, shifts), t12 (errors inside
  PROC/FN, RETURN strings, LOCAL string arrays, DIM space).
* The 8 upstream test programs in `tests/` run unchanged (`#file`
  directive in bascheck), with two adaptations:
  * ERRORTST: the two inline-assembler lines are deleted;
  * ARRAYTST: the string descriptor size comes from `DESC%`, since it is
    6 bytes here (decision D1).
* Fixes:
  * EXIT and RESTORE DATA/ERROR saved registers on the stack around
    RESLOC, which works on the top of the stack;
  * `NEXT ,`;
  * the LOCAL array frame now keeps the size reserved (rounded to even);
  * osl.c: EXT after reading past the end, "Bad name" for wildcards,
    "Bad string" for a missing quote.
* Known platform differences (not bugs):
  * EXT and EOF are exact on Minix, rounded to 128-byte records on CP/M;
  * channel numbers differ.
* The root image only has about 8 KB spare on 1 MB, so bascheck splits
  the `#file` tests over several boots.

**Next:**
* INPUT and other interactive tests through a tty;
* interactive tests through a tty;
* larger real programs.

## 12. Phases 5 and 6, 2026-10-20

**Phase 5 (files and the tests) is done.** The unmodified
`CHAIN "ALLTESTS"` runs all 8 programs through `*EXEC`. 6 complete; the
other 2 stop where expected:
* ARRAYTST assumes 4-byte string descriptors;
* ERRORTST line 1020 tests a Z80 `JR` range error.

**Phase 6:**
* **`make install`** (decision: a target only, not run). It copies
  `bbcbasic` to `rootfs/local/` in the Minix tree and adds it to
  `rootfs/sdproto` as `/usr/bin/bbcbasic`; then run `make sdcard` there.
  The 1 MB RAM root image has no room for it.
* **The 68000 inline assembler** (decision: Motorola syntax). `asmb.s`
  replaces the stub; the user documentation is `src68k/ASSEMBLER.md`.
  * The control section follows the Z80 one (P%, O%, OPT bits,
    `.labels`, the listing).
  * The encoder is new: the full 68000 set plus RTD and
    `MOVE CCR,<ea>`; all addressing modes in the classic and the
    `(d,An,Xn)` forms; DC/DS/EQUx/ALIGN.
  * Expressions are copied to a buffer before evaluation, so that
    `label(a6)` is not read as an array. The copy also turns `$hex` into
    `&hex`.
  * Upper-case mnemonics that the tokeniser turned into keywords or
    abbreviations (`MOVEM.` → `MID$(`, `ORI.` → `ORIGIN`) are expanded
    and retried.
  * `make asmcheck`: 162 instructions, all byte-identical to the ACK
    assembler, or checked by hand where ACK can't be used (68010
    instructions, memory shifts, directives).
  * `test/bas/a01asm.in`: two passes, O%, the listing, the errors and
    running code with USR/CALL. It has a hand-checked `.exp` (bascheck
    uses NAME.exp instead of the RunCPM reference when there is one).
* **Port changes:**
  * `DIM name size` blocks start at an even address, so they can hold
    68000 code; the Z80 version does not align them.
  * bascheck now runs with 2 MB (R68K_RAM), because the larger binary
    left no room in the 1 MB root image for the test files.
* **Result: all 21 suites pass**; ERRORTST now only deletes line 1020.

## 13. Speed pass, step 1: benchmarks (2026-10-20)

**Tools:**
* **Profiling emulator:** `build/r68kprof` is r68k with
  `mboot/patches/r68k-0002-cycle-profiler.patch`, built out of tree; your
  r68k is unchanged. It counts the 68000 cycles (Musashi's figures for
  the 68010) per instruction address. A BASIC program writes `?&FFFFF0=1`
  to start the measurement and `=2` to stop it.
* **`tools/bench.py`** runs `src68k/test/bench/*.bas` in one boot. It maps
  the addresses to routines using the symbols of the unconverted link
  (anm), with the load address `^@%` minus STAVAR.
* **Baseline:** `mboot/bench-baseline.txt`. All benchmark results equal
  the Z80's.

| Benchmark | Cycles | At 10 MHz |
|---|---|---|
| b1int: 5000 × `A%=A%+I%*3-(I% DIV 7)` | 81.4 M | 8.1 s |
| b2float: 300 × SIN, SQR, EXP | 20.1 M | 2.0 s |
| b3str: 300 × concatenation, MID$, INSTR, STR$ | 27.3 M | 2.7 s |
| b4sieve: 2000-entry byte sieve | 67.5 M | 6.7 s |
| b5proc: FNfib(13) + 100 PROC calls | 17.6 M | 1.8 s |
| b6vars: 500 × named-variable expression | 28.0 M | 2.8 s |
| b7goto: 300 × GOSUB/GOTO | 5.5 M | 0.55 s |

On average 10 cycles per instruction; under 0.5% is spent outside
bbcbasic (clock interrupts).

**Where the time goes (all benchmarks):**

| Share | Routines |
|---|---|
| 22% | Statement/expression dispatch: NXT, ITEM, DISPAT, XEQ1, EXPRn |
| 9% | Variable lookup: GETVAR, LOCATE, LOCn, TYPE (walking name chains) |
| 8% | Little-endian byte access: LDLE4/STLE4/LDLE4A |
| 8% | Bit-serial division in the FPP: DIVA, DIVB, DIV2 (an integer `DIV 7` costs about 10% of b1) |
| 3% | CHECK |
| 2% each | Number to string (STR22/23), string stack, decimal constant parsing (CON/NUMBER) |

Within b2float, the bit-by-bit shift loops (DIV2 in FIX, FLOAT) are about
15%.

**Candidate changes, by expected gain and risk:**
1. **LE access:** inline LDLE4/STLE4 at the hot uses, with faster code
   for even addresses.
2. **FPP integer division and shift loops:** DIVU-based division, and
   multi-bit shifts instead of one bit per loop. These must stay
   bit-exact (mathcheck).
3. **NXT/ITEM/XEQ dispatch tightening;** CHECK only where needed.
4. **Variable lookup:** compare names as words; a faster TYPE.

## 14. Speed pass, steps 1 and 2 (2026-10-20)

**Little-endian access:**
* LDLE4/LDLE4A build the value with `lsl.w #8` + `swap` instead of three
  `lsl.l #8`.
* STLE4/STLE4A copy the bytes from a stacked copy of the register, which
  stays intact; NEXT, for example, needs d0 after STOREN.
* All of these are inlined in LOAD4, STORE4 and the LOCATE chain walk.

**FPP:**
* **IMOD (DIV, MOD):** divisors of 1-65535 take two DIVUs; the result is
  exact, as the 33-step loop. 0 and larger divisors keep the loop, so the
  Z80 quirks stay: `1 DIV 0` = -1, `1 MOD 0` = 1.
* **FIX** shifts the n bits at once. It gives the same d0, d5 and d7.w;
  of d6 only bit 7 is kept, the only bit that the callers (INT, FPOW)
  test.
* **FLOAT/FLO48** normalise in 16- and 8-bit steps while the exponent
  stays above the step, then use the old bit loop. This gives the same
  result.
* **FDIV:** the mantissa division (FDIVQ) is two 16-bit digits (Knuth D:
  a DIVU estimate, at most two corrections). A Python model of the
  68000 code matched a simulation of the DIVA/DIVB loop on 1 M cases.

**Checks:**
* mathcheck: 14801 vectors (all operations) plus 7500 (the division
  users), bit-exact.
* The new suite `t13num` covers DIV/MOD/INT/conversion/division edge
  cases against the Z80.
* All 22 suites and asmcheck pass.

**Result:** 247.5 M → 223.2 M cycles, -9.8% (`mboot/bench-step2.txt`).

| Benchmark | Baseline | Now | Change |
|---|---|---|---|
| b1int | 81.4 M | 69.5 M | -14.6% |
| b2float | 20.1 M | 16.5 M | -17.9% |
| b3str | 27.3 M | 26.2 M | -4.3% |
| b4sieve | 67.5 M | 65.1 M | -3.5% |
| b5proc | 17.6 M | 16.8 M | -5.1% |
| b6vars | 28.0 M | 24.3 M | -13.1% |
| b7goto | 5.5 M | 4.8 M | -12.4% |

What remains is mostly the interpreter itself (item 3): NXT, ITEM,
DISPAT, CHECK, CON (constants are parsed on every execution), GETVAR and
LOCATE.

## 15. Speed pass, item 4: variable lookup (2026-10-20)

* **Tables instead of compare chains:** RANGE/RANGE1 at the end of a
  name, and TYPE, use two 256-byte tables, NAMTAB and TYPTAB, generated
  from the original compare rules.
* **GETVAR** checks for the indirection characters `! ? | $` with one
  test for the usual name case.
* **The chain walk:**
  * the name pointer is saved once per lookup instead of once per node;
  * the names are compared with CMPM.
* **Even nodes:** CREATE starts every node at an even address (at most
  one byte per variable). The little-endian link is then read as one long
  and byte-reversed, instead of four byte moves. The chain heads in
  data.s are 4-byte aligned. The layout of a node is unchanged.

**Result:**
* b6vars 24.3 M → 22.9 M (-5.9%), b5proc 16.8 M → 15.8 M (-5.5%);
* total 223.2 M → 218.9 M (-1.9%; `mboot/bench-step4.txt`);
* the lookup itself is about 15% faster.

What remains is the fixed cost per lookup (GETVAR → LOCATE → TYPE →
GETVZ, about 20% of b6vars). Getting much more would need caching
variable addresses (a change of the program format), so it is not done.

All 22 suites and asmcheck pass.

**Since the baseline:** 247.5 M → 218.9 M cycles (-11.6%).

## 16. Speed pass, item 3: the interpreter core (2026-10-20)

**Changes:**
* **FPP entry:** tests VAL (op 36) in a register, without the extra stack
  word.
* **DOIT:** integer `+ -` and the six comparisons are done inline. Their
  results equal IADD, ISUB and ICP1 (a signed compare); overflow goes to
  FPP.
* **CHECK** uses `lea`, and restores with a `movea`, which keeps the
  flags.
* **ITEM** has the room check (FREE + 268 against its own sp, the same
  test as CHECK's) and NXT's fast path inline. NXT is also inline in
  EXPR5A and XEQ1.
* **CON:** up to 9 digits not followed by `.` or `E` are an integer
  without FPP. That is the same result as VAL.
* **IF:** the false-IF scan (IFNOT) skips bytes by a 256-byte table
  (stopping at `"`, CR, REM, ELSE and THEN).
* **STR:** the digit step (STR22) is two DIVUs by 10 for 1-32 steps.
  A Python model of the 68000 code matched the Z80 bit loop for every
  step count, both values of the carry and 1.28 M inputs.
* **MOVBLK:** a block copy for LOADS, PUSHS and POPS. It copies
  longwords when source and destination have the same alignment,
  otherwise 4 bytes per loop.

**Checks:**
* new suites t14core (constants, integer overflow, comparisons, IF
  scanning) and t15copy (string copies of every length 0-255 and
  alignment), both against the Z80;
* all 24 suites pass;
* mathcheck bit-exact (11101 vectors, plus 1000 for STR);
* asmcheck passes.

**Result:**
* 218.9 M → 178.4 M cycles (-18.5%; `mboot/bench-step3.txt`);
* by benchmark: b1int -18.8%, b3str -30.7%, b4sieve -18.4%, b5proc
  -15.1%, b6vars -16.3%, b7goto -16.1%.

**Speed pass total:** 247.5 M → 178.4 M cycles (-27.9%).

The profile is now flat: ITEM's dispatch is 7.3% and the LE variable
load 4.8%. Further gains would be small.

## 17. Real-speed check on the MAME rosco-emulator (2026-10-20)

**Emulator:** the rosco-emulator (MAME 0.289, rosco_m68k_010: MC68010 at
10 MHz, the real firmware, SD card over SPI). Built from its Dockerfile
with podman as `localhost/rosco-emulator` in about 16 minutes, without
sudo.

**Runner:** `tools/mamebench.py`.
* It builds an SD card in `build/mame` with the Minix tree's tools:
  * FAT with ROSCODE1.BIN;
  * a Minix root from proto + sdproto, minus the unbuilt test-suite
    files, plus the interpreters and the benchmarks.
* The kernel has the 115200 baud console that the emulator needs. It was
  built in the Minix tree with `make CONSBAUD=115200 boot/image.bin`,
  saved as `build/mame/image-115200.bin`, and the tree was then put back
  to the default 38400.
* The benchmarks time themselves with TIME. The Minix clock runs off the
  emulated DUART timer, so this is emulated real time.
* The session runs with mamesession.py inside the container
  (`SDL_VIDEODRIVER=dummy`).

**Results:** bbcold = the build before the speed pass (`a014d3a`, from a
git worktree); bbcbasic = now. Both give the same results.

| Benchmark | Before (s) | Now (s) | r68k cycles at 10 MHz (s) | Gain |
|---|---|---|---|---|
| b1int | 7.76 | 5.44 | 5.60 | -29.9% |
| b2float | 1.85 | 1.44 | 1.54 | -22.2% |
| b3str | 2.60 | 1.70 | 1.79 | -34.6% |
| b4sieve | 6.33 | 5.03 | 5.26 | -20.5% |
| b5proc | 1.64 | 1.28 | 1.34 | -22.0% |
| b6vars | 2.62 | 1.80 | 1.92 | -31.3% |
| b7goto | 0.53 | 0.38 | 0.40 | -28.3% |

* MAME's cycle-accurate 68000/68010 core runs 3-7% faster than the
  r68k/Musashi cycle counts predict. So the profiler's figures are a
  little pessimistic but consistent, and fine for comparisons.
* The speed pass gains 20-35% in real time.
* With the root on the SD card, Minix reports 732 KB available, against
  285 KB with the 1 MB RAM-disk root of the r68k runs.

**Shell commands from BASIC (`src68k/test/mame`):** on the SD-card
system (732 KB free) the `*` commands that reach the shell work. Tested:
* `*ls`, `*pwd`, `*cd` then `*pwd` (cd is done by BASIC);
* pipes (`*echo ... | wc -c`);
* `OSCLI` with a string;
* `*date`;
* error messages from unknown and failing commands (`*ERA` of a missing
  file still gives the BASIC error "File not found");
* an interactive `*sh` subshell;
* piped stdin (`printf ... | bbcbasic`).

After each command BASIC's raw-mode line input (and INPUT) works
normally. The "No room" seen under r68k was only the 1 MB RAM-disk root.

**The full test suite on MAME:** `tools/runmame.py` is a drop-in for
runminix.py.
* It builds an SD card with the `-f` files and runs the commands in one
  MAME session. The end of each command is detected with an
  `echo ==D""ONEn==` marker, which is removed from the transcript.
* bascheck, asmcheck and mathcheck use it with `BBC_EMU=mame`.
  `make mamecheck` runs all three.
* On MAME, bascheck runs all suites in one boot and mathcheck runs one
  batch, because the SD root has no 1 MB image limit.

**Results on the emulated rosco_m68k** (68010, 1 MB, root on the SD
card):
* bascheck: 24 of 24 suites match the Z80 (42 s);
* asmcheck: 162 of 162;
* mathcheck: 14801 vectors bit-exact (47 s).

## 18. Demo, web version and ESCape by signal (2026-10-21)

**Stand-alone demo** (`make demo`, `demo/`, `tools/mkdemo.py`):
* r68k (-O2, static), its ROM and a ROSCODE1.BIN whose RAM-disk root
  boots into BBC BASIC with a menu of six demo programs;
* also as a container image (`mkdemo.py --docker`).

**Web version** (`make web`, `web/README.md`): one self-contained page
(1.9 MB) with r68k compiled to WebAssembly.
* **Load program** copies files through an emulated SD card: the page
  writes the card image, and typed `*dd` commands copy the bytes into
  BASIC's directory. One file is LOADed (or read in with `*EXEC` for a
  listing). Each file takes 0.1–0.4 s; typing a program in took 3–12 s.

**Kernel (Minix tree):**
* `roscons.c`: a lone ESC is passed on after 3 ticks.
* `system.c` `do_sigreturn` (68000): the interrupted code's condition
  codes are restored; before, they were those of the sigreturn call.
  Found because BASIC failed about one run in four with ESCape by
  signal: a signal between a compare and its branch.

**ESCape by signal** (`osl.c`):
* **Old cost:** with a terminal for input, the CP/M-style poll in TRAP
  (a `read()` every 20th TRAP) took about 40% of the time of a loop on
  Minix. With it, 20000 empty FOR loops took 6.5 s at 10 MHz, against
  3.7 s on MAME with input from a file.
* **Mode 4 ("running"):** raw, but ISIG with VINTR = ESC (disabled by
  `*ESC OFF`), NOFLSH, and IXON (^S/^Q). `sigesc` sets the flag;
  `os_poll` only flushes and keeps mode 4. The key-reading modes have
  ISIG off, so ESC is a key there as before.
* **Result:** 3.9 s at 10 MHz. On the demo: the BASIC loop 0.72 → 0.49 s,
  sieve 2.83 → 1.98 s.
* **Consequence:** the SIGINT goes to the whole foreground process
  group. A shell script that runs bbcbasic must ignore it
  (`trap '' 2`, as `demo/etc/demo` does); interactive shells survive.
* **Test:** `tools/ttycheck.py` (`make ttycheck`) checks it on a pty:
  * ESCape in a loop and at GET;
  * typeahead;
  * `*ESC OFF` with INKEY;
  * ^S/^Q;
  * the editor keys;
  * after a `*` command;
  * `*BYE` to the shell;
  * an interactive shell.

## 19. BBC BASIC on a bare rosco_m68k (2026-10-21)

No Minix: `make bare` (`tools/mkbare.py`) builds `build/bare/ROSCODE1.BIN`,
46 KB. The firmware loads it at 0x40000 from the SD card's FAT partition
(or r68k from the command line) and starts it.

* **Build:**
  * the same interpreter objects and `minix.s` glue;
  * `osl.c` with `-DBARE`: no shell (`*` commands that are not BASIC's are
    "Bad command"), and `*DIR` lists the RAM store;
  * `bare/bare.c` and `bare/start.s`;
  * linked by the ACK's `em_led -b0:0x40000`, then `aslod` (flat binary).
* **`bare/bare.c`:** the POSIX calls osl.c makes, done on the bare machine.
  * Console: DUART channel A as the firmware left it. Received
    characters come in by interrupt (vector 0x45 at the VBR) into a
    1 KB buffer.
  * The termios modes osl.c uses: VMIN/VTIME, ISIG with VINTR=ESC
    calling the SIGINT handler from the interrupt, IXON.
  * TIME: the DUART timer at 60 Hz.
  * Files: a RAM store in 512-byte blocks, a quarter of the memory above
    the program, one directory, up to 128 files. It survives `*BYE`
    (BASIC starts again), not a reset.
  * Idle waits use STOP.
* **`--demo`:** the demo programs come in the store and `menu` runs at
  the start (57 KB).
* **ACK pitfall:** `(void) DU(n)` (a read of a volatile register for its
  side effect) is dropped by the ACK. The counter was never started;
  such reads now go to a volatile variable.
* **Tests:**
  * `make barecheck` (`BBC_EMU=bare bascheck`: the `#file` files in the
    store, lines typed at the prompt, `*BYE` between tests): 24 of 24 ok;
  * MAME with the real firmware: boot from the SD card, TIME (20000
    empty loops 3.65 s, as Minix with input from a file: 3.67), ESCape,
    `*DIR`.
* **Next:**
  * the web page on it, with uploads/downloads;
  * step 2: files on the SD card's FAT file system through the
    firmware's SD routines, behind the same calls in `bare.c`.

## 20. Step 2: files on the SD card; the web page on bare BASIC (2026-10-22)

**`bare/fat.c`:** FAT16/FAT32 through the firmware's SD routines
(`start.s` calls the EFP entries as the Minix kernel does).
* The first FAT partition of the MBR, or a card without a partition
  table.
* 8.3 names (any case in, upper case on the card); long-name entries
  skipped, and removed with their file.
* Paths, `*CD`, and new `*MKDIR`/`*RMDIR` (in `osl.c`: mkdir/rmdir, so
  for Minix too).
* Both FATs updated; FAT32 FSInfo kept (free count, next free).
* One sector buffer, written through, that lasts only within a call.
* **Which store** (`bare.c`): a file is looked for on the card, then in
  the RAM store; new files go on the card (in the store if not 8.3);
  `sd:` and `ram:` choose.
* **Tests:**
  * `tools/fatcheck.py` (in `make barecheck`), three cards (mkfat.py
    FAT16, a small FAT16 and a FAT32 from mkfs.fat): programs, a
    3000-line file, a 100000-byte file, a gap, directories, *REN/*ERA,
    *BYE; fsck.fat clean;
  * MAME with the real firmware: the same against the boot card;
    fsck.fat clean.
* **ACK pitfall:** `le16()` returning `int` made a 16-bit sector count of
  0xF800 negative; it now returns `unsigned`.

**The web page** now runs bare BBC BASIC (`make web`; the Minix one is
`make webminix`).
* **The card:** `pre.js` formats the card FAT16 (32 MB).
* **`web/fat.js`:** puts uploads on the card and takes downloads off it;
  only `LOAD`/`*EXEC` is typed, nothing for downloads.
* **Idle:** `webmain.cpp` treats STOP (bare BASIC's idle) as idle, as
  `bra.s *`; idle CPU 3.6%.
* **Result:** the page is 1.4 MB (1.9 with Minix); boot to the menu
  0.8 s.
* **Tests:** Node and Chromium, both variants, all ok; `ttycheck` ok on
  bare BASIC too (`*BYE` restarts BASIC).

## 21. BBC BASIC as a PC program: Windows .exe and Linux (2026-10-22)

`make host` (`tools/mkhost.py`, `host/README.md`):
`build/host/windows/bbc68k.exe` (MinGW-w64, static, 1.8 MB) and
`build/host/linux/bbc68k`. Each is r68k with the firmware and bare BBC
BASIC (with the demos) built in.
* **Console:** `R68K_HOSTED` in `r68k-web.patch` (the web build's DUART
  path, output to `r68k_host_output`). `host/hostmain.cpp`: an input
  thread (console keys, Windows cursor keys as vt100, or pipe bytes); it
  sleeps while idle (STOP). Keys are held until BASIC is first idle.
  Ctrl-] quits; piped input ends the program when used up and quiet.
* **Host files:** `host/hostfs.cpp`, the folder the program started in.
  * BASIC asks with ILLEGAL: d6 = "BBCH", d7 = op (`start.s`
    `bare_host`).
  * `bare.c` finds the host with a probe (vector 4 at `bare_nohost`),
    then uses its files as the primary device (`host:` prefix).
  * `*BYE` ends the program.
  * Windows cannot delete an open file; that is emulated (removed at the
    last close).
* **MinGW:** `host/compat` (`byteswap.h`, `termios.h`, `sys/select.h`)
  and `-lws2_32` let r68k's sources build unchanged.
* **Tests:**
  * `BBC_EMU=host` and `BBC_EMU=hostwin` (Wine) bascheck: 24/24 each;
  * `tools/hostcheck.py` (both, the folder checked byte by byte): ok;
  * `ttycheck --exe` (Linux, pty): ok;
  * Wine in a pty: menu, typing, Ctrl-] ok. Wine's console loses a lone
    ESC, so Escape and the cursor keys are for checking on real Windows.
* **Also rechecked after the shared changes:** the web page (Node,
  Chromium), the bare suite without a host (24/24), and MAME with the
  real firmware (the probe is harmless; SD card files ok).
