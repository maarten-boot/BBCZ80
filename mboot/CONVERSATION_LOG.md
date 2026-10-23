# Conversation Log — BBCZ80 repository

Running log of the Claude Code session in `/home/mboot/vibe/BBCZ80-s-8250`.
New entries are appended at the bottom.

---

## Entry 1 — 2026-10-20

### User request
> inspect the current directory and all its files describe what you find. create a new
> branch and create a running log of the conversation in a mboot directory.

### Actions taken
1. Listed every file in the repo (28 files, excluding `.git`) and read the docs,
   build scripts, source-file headers and git history.
2. Created branch `mboot/conversation-log` from `master` (at `410e7fb`).
3. Created this log at `mboot/CONVERSATION_LOG.md` (not committed yet).

### Findings

**What it is:** the source of **BBC BASIC (Z80) v5.00** by Richard T. Russell — an
interpreter for the BBC BASIC language written in Z80 assembly. It is largely
compatible with Acorn's ARM BASIC V, plus extensions from BBC BASIC for Windows /
SDL 2.0 (EXIT, the `^` address-of operator, `&` byte variables/arrays).
Licensed under a zlib-style licence (`licence.txt`); the name "BBC BASIC" is used
with BBC permission and is not transferable to forks.

**Layout**

| Path | Contents |
|------|----------|
| `README.md` | Overview; links an architecture diagram (generic core / CP/M / Acorn editions) |
| `WHATSNEW.TXT` | Feature list for v5.00 (Jan 2025): WHILE, multi-line IF, CASE, whole-array ops, `+=` etc., bit shifts, SWAP, graphics hooks, … Notes the PUT token changed `&CE` → `&0E`. |
| `licence.txt` | zlib-style licence, © 2024 R.T. Russell |
| `src/` | 11 Z80 assembly modules, ~15,100 lines |
| `bin/cpm/` | Prebuilt `BBCBASIC.COM` (18,944 B) + `MAKE.SUB` build script |
| `bin/acorn/` | Prebuilt `BBCBASIC.COM` (19,200 B) for Acorn Z80 Tube + `MAKE.SUB` |
| `tests/` | 9 tokenized BBC BASIC test programs (binary, not plain text) |
| `.gitignore` | Generic C/C++ template (objects, exes, `*.hex`, `build/`) |

**Source modules (`src/`)**

| Module | Lines | Role |
|--------|------:|------|
| `MAIN.Z80` | 2235 | Commands & common routines (generic core) |
| `EXEC.Z80` | 3293 | Statement execution (generic core) |
| `EVAL.Z80` | 2591 | Expression evaluation (generic core) |
| `ASMB.Z80` | 1009 | Built-in Z80 assembler (generic core) |
| `MATH.Z80` | 2255 | Floating-point package: 32-bit mantissa, 8-bit excess-128 exponent |
| `DATA.Z80` | 68 | RAM / workspace definitions |
| `DIST.Z80` | 227 | CP/M distribution/patch stub at 100H (must fit in 256 bytes) |
| `CMOS.Z80` | 1500 | OS layer for plain CP/M 2.2/3.0 |
| `HOOK.Z80` | 67 | Stubs for graphics/sound statements (CP/M edition) |
| `AMOS.Z80` | 1118 | OS layer for the Acorn Z80 Second Processor (Tube) |
| `ACORN.Z80` | 755 | Acorn graphics/sound support via OSWORD/OSBYTE |

**Editions / build** (CP/M `SUBMIT` scripts using `z80asm`, `link`, `hexbin`):
- CP/M: `dist, main, exec, eval, asmb, math, hook, cmos` + `data` at `4B00h` → `bbcbasic.com`
- Acorn Tube: `main, exec, eval, asmb, math, acorn, amos` + `data` at `4C00h` → `bbctube.com`

The generic core (MAIN/EXEC/EVAL/ASMB/MATH) just fits in 16 KB, so it could live in ROM.

**Tests:** `ALLTESTS.BBC` writes an `EXEC.$$$` file that CHAINs each test
(ARRAYTST, BYREFTST, ERRORTST, EXITTEST, FILETEST, INT32TST, FORTEST, SLICETST).
They must be run inside BBC BASIC on a CP/M system/emulator.

**History:** 17 commits, all by Richard Russell, 2024-05-27 → 2025-03-16. Latest:
"Moved shifts to avoid Z88 functions". Working tree was clean on `master`.

---

## Entry 2 — 2026-10-20

### User request
> the idea is to translate this to 68000 assembler so we can make it compile with
> the amsterdam compiler kit 68000 it will initially target the current minix
> running on the rosco-68k in the branch:
> https://github.com/maarten-boot/minix-st-2.0.4/tree/rosco-m68k

### Actions taken
1. Shallow-cloned the `rosco-m68k` branch (head `841f10b`, 2026-10-18) into the
   session scratchpad for reference. Read `ROSCO_M68K_PORT_SPEC.md`, the latest part
   of `ROSCO_M68K_CONVERSATION_LOG.md`, `src/rosco/Makefile`, `src/rosco/ack/*`, and
   the m68000 libc runtime (`ncrtso.s`, `setjmp.s`, syscall stubs).
2. Checked for a local ACK: `/home/mboot/DEV/ack` is at the same commit
   (`7afa32a0`), but it was built only for linux/linux386, with no minix68k
   platform.
3. Inspected the Z80 register conventions (MATH: mantissa `HLH'L'` + exponent C;
   heavy `EXX`/IX/IY use).
4. Wrote `mboot/PORT_PLAN.md`: target summary, module-by-module strategy, register
   map, open decisions D1–D4, and phases 0–6.

### Key findings
- The Minix branch already has a **host cross ACK for minix68k** (16-bit int):
  `src/rosco/ack/build-ack.sh`, `acc`, and `acc-minix` (which links with crtso + the
  Minix libc). The BASIC port can be a normal Minix user program in ACK assembly
  that calls libc.
- Target CPU is a 68010: `move sr` is privileged in user mode, and there is no FPU.
- Replace CMOS/DIST/HOOK with a new `MINIX.s` OS layer. AMOS/ACORN are not needed.
  ASMB (Z80 assembler) has to be replaced or stubbed.
- Main design questions: pointer width (D1), byte order of BASIC-visible memory
  (D2), and the inline assembler (D3). Recommendations are in the plan.

---

### Decisions (user answers, 2026-10-20)
- **D1 Memory:** 32-bit pointers throughout.
- **D2 Byte order:** keep BASIC-visible memory little-endian (byte-swapping
  loads/stores), so existing `.BBC` files load unchanged.
- **D3 Inline assembler:** report "Not supported" first; add a 68000 assembler later.

Recorded in `mboot/PORT_PLAN.md` §4.

---

## Entry 3 — 2026-10-20

### User request
> clone it to /home/mboot/vibe/minix-st-2.0.4

### Actions taken
1. Cloned the `rosco-m68k` branch to `/home/mboot/vibe/minix-st-2.0.4` (`841f10b`).
2. Built the minix68k ACK (`build-ack.sh` with `ACK_URL=/home/mboot/DEV/ack`).
   Lua posix wasn't needed. Then built the ACK libc (`crtso.o`, `emrts.o`,
   `libc.a`).
3. The first `make` of the system failed: the container could not write to the
   mount (rootless podman). The fix is `PODMAN_USERNS=keep-id`, with no change to
   `xrun`. After that the system image and r68k built.
4. Phase 0:
   * wrote `src68k/test/hello.s` (ACK assembly calling `_write`);
   * compiled a C sample to see ACK's register-saving convention;
   * wrote `src68k/tools/runminix.py` (makes a custom root image, boots r68k,
     logs in, runs commands).
   * Result: `hello from 68k`, `rc=0`. The first attempt with a 1000-block
     root image did not fit in RAM; it is auto-sized now.
5. Added `build/` and the test outputs to `.gitignore`. Added the phase 0 results
   to `PORT_PLAN.md` §7.

### Notes
- Under r68k the kernel detects a 68020; the real board is a 68010. Avoid
  68020-only instructions by rule.
- About 330 KB is available to user programs.

---

## Entry 4 — 2026-10-20

### User request
> yes commit it and start phase 1; a quick emulator for rosco-m68k is available
> at: https://github.com/maarten-boot/r68k/tree/rosco-minix-duart

Mid-turn addition:
> for full tests we can use:
> https://github.com/maarten-boot/rosco-emulator/tree/rosco-m68k-ram-bios

### Actions taken
1. Committed the setup work as `3da67f5`.
2. Cloned r68k (`rosco-minix-duart`, `a3d2f10`) to `/home/mboot/vibe/r68k`. Its
   source is identical to the patched r68k that the Minix tree builds.
3. Testing whether 68020 instructions trap uncovered an **r68k bug**: the
   illegal-instruction callback always returned 1, so every illegal opcode
   (even `illegal`) was skipped silently. That is also why Minix reported a
   68020. Fixed it in `main.cpp` (return 0 unless d7/d6 hold the firmware
   magic), copied the ROM from the Minix build, and rebuilt. Now `illegal` and
   `extb` give SIGILL, and the boot banner shows a 68010. Not committed in the
   r68k repo.
4. Added `-e`/`$R68K` to `runminix.py`; it prefers `../r68k/r68k`.
5. Cloned the MAME rosco-emulator (`rosco-m68k-ram-bios`) to
   `/home/mboot/vibe/rosco-emulator`. It can't be built yet: the dev packages
   are missing and need sudo (apt command given to the user).
6. Probed the ACK assembler and recorded its dialect in `src68k/CONVENTIONS.md`.
7. Wrote phase 1: `CONVENTIONS.md`, `Makefile`, `bbc.h`, `util.s` (little-endian
   unaligned helpers) and `test/utiltest.s`. `make check` gives `hello from 68k`
   and `utiltest=0`.

---

## Entry 5 — 2026-10-20

### User request
> yes commit and push the r68k fix, then start phase 2; can you also write a
> patch so that i can apply in to my copy on my host linux

Mid-turn side question:
> as a side question can we extract a syntax file in ebnf from the original code ?

### Actions taken
1. **r68k:** committed the fix as `2d92829` on `rosco-minix-duart` in
   `/home/mboot/vibe/r68k`. The **push failed**: there are no GitHub
   credentials on this host (gh is not logged in; the SSH key is not
   accepted). Wrote `mboot/patches/r68k-0001-illegal-instruction-trap.patch`
   (`git format-patch`) and checked that `git am` applies it cleanly to
   `a3d2f10`.
2. **Reference oracle:** built RunCPM (`/home/mboot/vibe/RunCPM`,
   `make -f Makefile.posix CCP=INTERNAL`) and wrote `src68k/tools/runcpm.py`
   to drive the original Z80 `BBCBASIC.COM`. Findings: BASIC parses only
   uppercase hex; CP/M files are padded with NULs; output lines end in
   `\r\r\n`.
3. **Phase 2 — MATH translated** (`src68k/math.s`), with the test driver
   `test/mathtest.c` + `test/fppglue.s` and the comparison tool
   `tools/mathcheck.py`.
   * The first draft got a self-review against the Z80, which found five
     bugs before any test ran (FDIV bias, SQR counter, ICP0 borrow, octant
     byte, VAL IX).
   * The comparison then found LN (exponent lost across ZERO) and ATN/IPOW
     (68k `move` clobbering flags). All are fixed.
   * Harness problems on the way: the root image overflowed 1 MB of RAM
     (now batches of 500); the oracle variable `O%` clashed with the file
     handle; lowercase hex.
   * Result: all 39 BASIC-expressible operations match the Z80 bit for bit
     over thousands of random vectors.
4. **EBNF side question:** yes, it can be extracted. The grammar is
   implicit in the keyword table (MAIN), the EXPR0–EXPR5/ITEM precedence
   chain (EVAL) and the statement handlers (EXEC). A background agent is
   writing `mboot/BBCBASIC.ebnf`, with a source reference per rule.

---

### Follow-up (same entry)
- `mboot/BBCBASIC.ebnf` (1072 lines, about 190 rules) was written by the
  background agent. Contents:
  * the token table with byte values (138 spellings);
  * 9 immediate commands and 82 statements;
  * the expression precedence;
  * about 66 functions and pseudo-variables;
  * the inline assembler;
  * `src: FILE:LABEL` references throughout.
- Spot-checked against the real Z80 BASIC under RunCPM; all four confirmed:
  * `-2^2` gives 4;
  * `5<<<2` gives 20 (`<<<` = `<<`);
  * `=>`, `=<` and `><` are accepted;
  * `CLS PRINT "X"` runs without a colon.
- Open or ambiguous items are listed in the file: SYS and TINT are not
  implemented in this source, LOCAL ERROR is a no-op, the READ `:` edge case,
  and the assembler's LD (nn) forms.
- Phase 2 committed as `557a113`.

## Entry 6 — 2026-10-20

### User request
> ok i messed up ; my code transfer tool erased all code and branh you created
> we will have to sync up again

### Actions taken
1. Inspected the workspace. `BBCZ80-s-8250` had been re-cloned: `master`
   only, reflog showing just the clone. A stale remote-tracking ref
   `agent-s-8250/mboot/conversation-log` was still present at `d27fd77`,
   with all objects local. Only ignored build products were left in
   `src68k/`.
2. Recreated `mboot/conversation-log` from that ref (`git checkout -b`). No
   work was lost: all four commits are back (`3da67f5`, `0e82421`,
   `557a113`, `d27fd77`).
3. The sibling repos are intact: `minix-st-2.0.4` (ACK + libc built),
   `r68k` (fix `2d92829`, not pushed), `rosco-emulator` and `RunCPM`.
4. `make clean && make && make check` passes (`hello from 68k`,
   `utiltest=0`).

---

## Entry 7 — 2026-10-20

### User request
> yes, continue with phase 3

### Decisions (asked; user answers)
- OS layer: **C + asm glue** (the interpreter stays assembly).
- Unknown `*` commands: **passed to the shell**.
- Extension: **.BBC like CP/M, but also allow lowercase .bbc**. Implemented
  as: an existing `name.bbc` is used, otherwise `name.BBC`.

### Actions taken
1. Read CMOS.Z80, DIST.Z80 and HOOK.Z80: the routine contracts, error
   numbers, the `*` command table and the console editor. Mapped which OS
   symbols MAIN/EXEC/EVAL import.
2. Wrote `src68k/data.s`, `osl.c`, `minix.s` and `hook.s`, plus the test
   monitor `test/osmon.s` with `make oscheck`.
3. Debugging along the way:
   * a cpp line continuation (`\` in a comment) hid ONERSP;
   * a byte mask of `~0x80` was "too big";
   * monitor print bugs;
   * `*REN` names;
   * double CRs: OPOST was still on in raw mode, and `*TYPE` added CRs
     to CR LF files.
4. **Shell commands printed nothing:** `system()` returned 127. Probes
   showed fork works but `execve("/bin/sh")` in the child fails with
   **ENOMEM** on 1 MB (about 330 KB available); with `R68K_RAM=2M` all
   works. Replaced `system()` with my own fork/exec so this gives "No room".
5. **Lone ESC delayed:** found in `kernel/roscons.c`, which holds a lone
   ESC back to recognise the ESC O P/Q/R/S debug keys. Reported to the
   user; not changed (it is the user's kernel).
6. Added `runminix.py` `@PATTERN@TEXT` steps for interactive tests. An
   unanchored prompt pattern caused a race; use `\n>$`.
7. Documented the OS interface in CONVENTIONS §8 and the plan in
   PORT_PLAN §10.

---

## Entry 8 — 2026-10-20

### User request
> yes, start phase 4

### Actions taken
1. Translated MAIN (`main.s.in`, generated `main.s` with the Z80 keyword
   and error tables), EVAL (`eval.s`) and EXEC (`exec.s` and `exec2.s`).
   Wrote an `asmb.s` stub ("Not supported"). Added `make bbcbasic`.
2. **First milestone:** under Minix in r68k, `bbcbasic` starts and the
   following work:
   * the banner;
   * `PRINT 2+2`;
   * entering, listing and running a program;
   * `*BYE`.
3. Wrote `tools/bascheck.py` (`make bascheck`), a differential test
   against the original BBCBASIC.COM under RunCPM, with 9 test suites in
   `src68k/test/bas/`.
4. Fixed the bugs the tests found (PORT_PLAN §11). The most notable:
   * **an ACK assembler bug:** `bsr` to the next instruction becomes a
     `nop`, which broke every frame marker;
   * **the lexer left mode:** a Z80 `DEC C` side effect.
5. Result: **all 9 suites give the same output as the Z80**; MATH
   STR/VAL are still bit-exact.
6. Extended the suites to 20, including the 8 upstream test programs in
   `tests/` (ARRAYTST, BYREFTST, ERRORTST, EXITTEST, FILETEST, FORTEST,
   INT32TST, SLICETST). Fixed:
   * EXIT and RESTORE around RESLOC;
   * `NEXT ,`;
   * the LOCAL array frame size;
   * three osl.c file details.
   **All 20 match the Z80.** The tests that assume 4-byte string
   descriptors are adapted, because descriptors are 6 bytes here
   (decision D1).

## Entry 9 — 2026-10-20

### User message
> i will check the licence with the owner, it will probabely need to be
> hosted on his site; the rest i will do later

### Notes
- **Licence and name:** the user will ask the owner (R.T. Russell). The
  68k port will probably be hosted on his site. Until then the banner
  stays "BBC BASIC (Z80) Version 5.00".
- **Deferred by the user:**
  * the lone-ESC choice;
  * the memory size (`-S`);
  * the next step (68000 assembler or larger programs);
  * pushing the commits and the r68k fix.

## Entry 10 — 2026-10-20

### User request
> ok continue

### Decisions (asked; user answers)
- Assembler syntax: **Motorola**.
- Install into the Minix tree: **a make target only** (not run).

### Actions taken
1. Ran the unmodified ALLTESTS with 2 MB: 6 of 8 complete, the other 2
   stop where expected. Phase 5 is done.
2. Added `make install`, which targets the SD card root; I did not run it.
3. Wrote the 68000 inline assembler (`asmb.s`, with
   `src68k/ASSEMBLER.md`) and `tools/asmcheck.py`, which uses the ACK
   assembler as the reference.
   * All 162 test instructions match.
   * Bugs found and fixed along the way:
     * the register list range;
     * the AND/OR stack word;
     * REGAT clobbering a1;
     * the tokeniser turning upper-case mnemonics into keywords or
       abbreviations.
4. Made DIM blocks word-aligned for code.
5. bascheck: `.exp` files for 68k-only tests, `-n` for probing, and 2 MB
   by default.
6. All 21 differential suites pass. Details in PORT_PLAN §12.

## Entry 11 — 2026-10-20

### User question
> what is the speed pass ?

### Answer (summary)
The optional phase 6 item: measure first, then speed up hot paths without
changing behaviour, rechecked with bascheck and the bit-exact mathcheck.
Explained only; no work was done.

## Entry 12 — 2026-10-20

### User request
> yes, start with the benchmarks

### Actions taken
1. Found that r68k's clock follows the host's wall clock, so BASIC TIME
   would measure the host. Built a cycle-profiling r68k out of tree
   (`build/r68kprof`; patch in `mboot/patches/r68k-0002-cycle-profiler.patch`).
   The user's r68k is unchanged.
2. Wrote 7 benchmark programs (`src68k/test/bench/`) and
   `src68k/tools/bench.py`. It reports the cycles per benchmark and the
   hot routines, mapped through the ACK symbols.
3. Baseline (`mboot/bench-baseline.txt`, PORT_PLAN §13): 247 M cycles in
   total. The results match the Z80. The hot spots:
   * interpreter dispatch, 22%;
   * variable lookup, 9%;
   * little-endian byte access, 8%;
   * bit-serial division in the FPP, 8%.
   No code was changed yet; the candidate list goes to the user.

## Entry 13 — 2026-10-20

### User request
> yes, start with 1 and 2

### Actions taken
1. **Little-endian access:** faster helpers, inlined at the three hot
   sites. -3.0%.
2. **FPP:**
   * DIVU fast path for integer DIV/MOD;
   * multi-bit FIX;
   * FLOAT/FLO48 in 16/8-bit steps;
   * FDIV mantissa division with Knuth D. Prototyped in Python against
     a simulation of the bit loop (1 M cases), then written in 68000.
3. Everything is bit-exact:
   * mathcheck: 14801 + 7500 vectors;
   * the new suite t13num against the Z80;
   * all 22 suites and asmcheck.
4. **Total:** 247.5 M → 223.2 M cycles (-9.8%). The integer, float,
   variable and GOTO benchmarks are 12-18% faster. PORT_PLAN §14.

## Entry 14 — 2026-10-20

### User request
> lets do 4 first

### Actions taken
1. Variable lookup:
   * table-driven name-end check and TYPE;
   * a quicker GETVAR start;
   * one save per lookup instead of one per node;
   * CMPM name compare;
   * even-aligned nodes, so the little-endian link is read with one
     `move.l` and a byte swap.
2. b6vars -5.9%, b5proc -5.5%; total -1.9%, -11.6% since the baseline.
3. All 22 suites and asmcheck pass. PORT_PLAN §15.

## Entry 15 — 2026-10-20

### User request
> ok now do 3

### Actions taken
1. Interpreter core:
   * FPP entry;
   * inline integer + - and comparisons in DOIT;
   * a cheaper CHECK, and CHECK/NXT inline in ITEM;
   * NXT inline in EXPR5A/XEQ1;
   * a fast CON for short integers;
   * the false-IF scan by table;
   * the STR digit step by DIVU (Python model against the bit loop);
   * MOVBLK block copy for the string stack and LOADS.
2. New Z80-comparison suites: t14core and t15copy. All 24 suites,
   mathcheck and asmcheck pass.
3. Item 3: -18.5%. Speed pass so far: 247.5 M → 178.4 M cycles (-27.9%).
   PORT_PLAN §16.

## Entry 16 — 2026-10-20

### User requests
> run it in the MAME rosco emulator to check real speed
> how long will the MAME build take? ... a special stripped down version
> for the future
> ok, wait for the build and run the benchmarks

### Actions taken
1. **Built the rosco-emulator with podman** from its Dockerfile, in about
   16 minutes and without sudo. Explained where the build time goes (the
   MAME core, bundled libraries, the optional terminal and ATA devices)
   and the options for a lighter build:
   * cache the exported binary;
   * trim the slot devices in rosco.lua;
   * switch off MIDI and audio;
   * a headless variant.
2. **SD card:**
   * built the 115200-baud boot image in the Minix tree with the
     documented make variable;
   * saved it and restored the tree to the default;
   * made the SD card in `build/mame` with the tree's tools.
3. **Wrote `tools/mamebench.py`** and ran the benchmarks on the emulated
   68010 at 10 MHz, both before the speed pass and now.
4. **Results:**
   * the speed pass gains 20-35% in real time;
   * r68k's cycle figures agree with MAME within 3-7% (MAME is a little
     faster).

   PORT_PLAN §17.

## Entry 17 — 2026-10-20

### User requests
> how far is the build now?

(It had finished; the benchmarks had already run.)

> try the shell commands from BASIC on the SD card

### Actions taken
Ran two console sessions in MAME, kept as `src68k/test/mame`:
* `*` shell commands, pipes, OSCLI, error cases and piped stdin;
* an interactive `*sh` subshell, then INPUT.

All work on the SD-card system. The terminal mode is restored after each
command.

## Entry 18 — 2026-10-20

### User request
> run the full test suite on MAME too

### Actions taken
1. Wrote `tools/runmame.py`, a runminix.py-compatible runner for the MAME
   rosco-emulator. The harnesses select it with `BBC_EMU=mame`; added
   `make mamecheck`.
2. **On MAME** (68010, 1 MB, SD root):
   * bascheck: 24 of 24 suites match the Z80;
   * asmcheck: 162 of 162;
   * mathcheck: 14801 vectors bit-exact.

   All three run in about 2 minutes.

## Entry 19 — 2026-10-20

### User question
> could the original z80 also benefit from the optimisations we just made?

### Answer (summary)
Partly. About half of the gains are 68000-specific:
* hardware DIVU/MULU;
* longword copies;
* faster access to little-endian values;
* undoing overheads that the translation itself added.

On the Z80 these either don't exist or are already cheap there (LDIR, a
short CHECK). The algorithmic ones would carry over:
* byte-step shifts in FIX/FLOAT;
* an integer fast path for + - and the comparisons;
* a fast parse of short constants;
* table scans for a false IF and for name characters;
* a byte-wise divide by 10 for STR$.

They cost bytes of the scarce 64 KB, and the gain is unmeasured. It
could be measured with a cycle-counting Z80 emulator (RunCPM does not
count T-states). Explained only; no work was done.

## Entry 20 — 2026-10-20

### User message
> no need just curiosity.

No work was done (the Z80 cycle measurement was not wanted).

## Entry 21 — 2026-10-20

### User request
> make a patch bundle so i can push from my host

### Actions taken
Made `/home/mboot/vibe/push-bundle-2026-10-20/` and a `.tar.gz` of it:
* full git bundles of BBCZ80 `mboot/conversation-log` (25 commits on
  origin/master) and r68k `rosco-minix-duart` (1 commit);
* format-patch series of both;
* a README with the push commands.

Checked: the bundles clone, and the patch series reproduce the same
trees.

## Entry 22 — 2026-10-21

### User question
> i have a request to demonstrate the bbc basic interpreter. how can we
> make a easy stand alone demo environment?

### Answer (no work done yet)
Options, lightest first:
* **r68k tarball (recommended):** r68k is an interactive console
  emulator already (raw terminal on stdin/stdout). A demo needs only
  the r68k binary (~1 MB, static link for portability),
  `firmware/rosco_m68k.rom` and a ROSCODE1.BIN with the root file system
  as a RAM disk (~0.8 MB, made by `mkrosco -x root.img`). That is about
  2 MB in total, it boots in seconds and starts fresh every time. Add
  demo programs and a start script that boots straight into BBC BASIC.
  Note: r68k is not throttled, so it runs faster than a real 10 MHz board.
* **Container of the same (for Mac/Windows):** the tarball in a small
  image, run with `docker run -it`.
* **MAME rosco-emulator image:** about 400 MB plus a 43 MB SD card. It
  shows real 10 MHz timing and the real firmware, but boots slowly.
* **Real rosco_m68k board:** write `rosco_sd.bin` to an SD card.
* **Browser (future):** r68k compiled to WASM with xterm.js; the most
  convenient for an audience, but the most work.

## Entry 23 — 2026-10-21

### User question
> how feasable is the browser option, just explain first)

### Answer (explanation only, no work done)
Feasible: about 1–2 days of work. r68k's host dependencies are small and
in a few places:
* the DUART transmit (`std::cout.put`) and receive (`read(STDIN)`) in
  `machine/Duart.cpp`;
* the termios setup and the endless `while (1)` loop in `main.cpp`;
* loading the ROM and ROSCODE1.BIN from files.

The plan:
* Compile Musashi and r68k with Emscripten.
* Replace the loop with `emscripten_set_main_loop`, giving each frame a
  slice of CPU time.
* Wire the DUART to xterm.js: output through an EM_JS call, input
  through an exported C function.
* Embed the ROM and the boot image (`--preload-file`, or `SINGLE_FILE`
  for one HTML file).
* Pace paste input in JS.
* Throttling to 10 MHz is optional.

The result is static files of a few MB that can be hosted anywhere,
e.g. on R.T. Russell's site.

## Entry 24 — 2026-10-21

### User requests
> ok, start with the r68k tarball

Mid-turn questions:
> could that be hosted on a local pc and run without internet ?
> can the web hosted comp running bbc basic load external bbc basic files ?
> or should we also make a docker image available

Answered:
* yes, everything runs offline;
* loading files in the web version: see the reply;
* Docker: recommended, see the reply.

### Actions taken
* **`src68k/demo/`:**
  * `demo.sh`;
  * `README.txt`;
  * `etc/demo`: the console runs BBC BASIC with the menu, without a
    login; `*BYE` drops to a shell, and `exit` brings the demo back;
  * `etc/ttytab`: the console only; a getty on tty00 would show on the
    same r68k output;
  * six programs (mandel, sieve, hanoi, life, asm, queens) and a menu.
* **`tools/mkdemo.py`** (`make demo`) builds
  `build/demo/bbc68k-demo.tar.gz`, about 1.2 MB:
  * the programs are tokenised by the Z80 BBC BASIC under RunCPM and
    saved as `/usr/demo/*.bbc` (the texts are also there as `*.bas`);
  * the RAM-disk root is in ROSCODE1.BIN;
  * r68k is built from its tracked sources with -O2 and linked
    statically. The checkout's own build has no -O; -O2 is about 14×
    faster;
  * the firmware and the licence files are included;
  * `--test` boots the demo, runs every program from the menu and sends
    a lone Escape during life.
* **Test harness fix:** r68k makes its stdin O_NONBLOCK. With stdin and
  stdout on the same pty open file, output was lost once the pty was
  full. `demo.sh` and the test give r68k its own open of the tty as
  stdin.
* **Lone ESC (the user chose the kernel fix):** in the Minix tree,
  `kernel/roscons.c` now times out a held-back ESC (or ESC O) after 3
  ticks:
  * `kb_timer` wakes the TTY task;
  * `rs_read` (`roscrs232.c`) calls `cons_esc_timeout` after the
    buffered characters.

  Checks:
  * PF1 (ESC O P) still dumps the process table;
  * Escape stops life;
  * bascheck passes (0 of 24 failed).

  The kernel was rebuilt (`boot/image.bin`). The Minix change is not
  committed, and `build/mame/image-115200.bin` was not rebuilt.

## Entry 25 — 2026-10-21

### User request
> yes, make the docker image

Mid-turn question:
> the bbc basic has a tests directory did you try runneng those ?

Answered: yes. All 8 upstream programs in `tests/` are in bascheck as
`u_*.in`. They pass on r68k and MAME, again with the new kernel.

### Actions taken
* **`src68k/demo/Dockerfile`:**
  * an Alpine stage builds r68k from its sources (-O2, static), so the
    image builds natively per platform;
  * a busybox stage holds the demo;
  * the entrypoint is `demo.sh`.
* **`mkdemo.py --docker`** (`$DOCKER`, default podman):
  * assembles `build/demo/docker`;
  * builds `docker.io/library/bbc68k-demo:latest`, 7 MB;
  * saves it as `build/demo/bbc68k-demo-image.tar.gz`, 3 MB;
  * with `--test`, starts the container in a pty, runs the asm demo
    and quits with Ctrl-]. Passed.
* **`demo.sh`** now refuses to start without a terminal (`docker run -it`
  is needed). The README has the Docker commands.
* **arm64:** not tested; this host has no qemu binfmt.

## Entry 26 — 2026-10-21

### User requests
> yes, commit the kernel fix and rebuild the MAME image

Mid-turn:
> make me a patch also for the kernel fix

### Actions taken
* **MAME image:** rebuilt `build/mame/image-115200.bin` with the fix
  (`make CONSBAUD=115200`), then rebuilt the tree's default 38400 image.
* **Tested on MAME** with a scratch copy of `mamesession.py` that has a
  `sendraw` step:
  * PF1 (ESC O P) prints the process table;
  * a lone ESC during `REPEAT ... UNTIL FALSE` gives "Escape at line 10";
  * bascheck t14core passes.
* **Minix tree:** committed `107f0d0` "rosco_m68k: pass a lone ESC on
  after a timeout" on `rosco-m68k`, 1 ahead of origin. The commit also
  updates the port spec's `roscons.c` row and adds a log entry to
  `ROSCO_M68K_CONVERSATION_LOG.md`.
* **Patch:** `mboot/patches/minix-0001-lone-esc-timeout.patch`, also in
  `/home/mboot/vibe/push-bundle-2026-10-21/` with a git bundle. `git am`
  on `origin/rosco-m68k` gives the same tree as the commit.

## Entry 27 — 2026-10-21

### User request
> now start on the browser version

### Actions taken
* **`src68k/web/`** (see its README.md), built by `make web`
  (`tools/mkweb.py --test`):
  * `r68k-web.patch`: Duart.cpp under `#ifdef __EMSCRIPTEN__`;
  * `webmain.cpp`: a frame loop replaces main();
  * `loader.js`: `.bbc` detokeniser and text listings;
  * `page.html`, `app.js`: xterm.js 5.5.0 inlined, Load program, drag
    and drop, Stop typing, a Full speed / 10 MHz switch, Reset, Help,
    licences;
  * `test.js` (Node) and `browsertest.py` (headless Chromium over CDP).
* **Result:** `build/web/bbc68k.html`, 1.9 MB, one file, works offline
  and from file://.
* **Tests, all ok:**
  * Node: boot (0.9 s), the asm demo, and BYREFTST, EXITTEST, FORTEST,
    INT32TST and SLICETST typed in through the loader and run, output
    identical to the bascheck references;
  * Chromium: key events, Escape, Load program (FORTEST), speed setting.
* **Problems found and fixed:**
  * **Startup:** C++ exceptions were not enabled; under Node, argv[0]
    (the ROM path) was the host script; the non-MODULARIZE `Module`
    global was shadowed in CommonJS.
  * **6× slower than native:** Emscripten's JavaScript setjmp emulation
    (Musashi sets a bus-error jmp_buf in `m68k_execute`) wrapped every
    opcode dispatch in invoke_*. Fixed with `-fwasm-exceptions
    -sSUPPORT_LONGJMP=wasm`. That rules out Asyncify, hence the frame
    loop, with SETIMMEDIATE frames and a timeout while idle. Now about
    3× native; 3% CPU when idle.
  * **Pasted programs lost characters:** the kernel's rs buffer (256)
    filled up. Keys were paced per CPU step, but when idle the CPU spins
    at an enormous emulated speed, while Minix drains input only on
    (real-time) clock ticks. Found by sampling `icount` in `rs_lines`
    (kernel.map/nm): web 256, native 54. Keys are now paced at 1 ms of
    real time.
* **Speed (20000 empty FOR loops):**
  * the web build's 10 MHz setting gives 6.50 s, exact at 9.98 MHz, but
    MAME gives 3.67 s;
  * the cycle profiler gives 38.2M cycles = 3.82 s.
  * **Cause:** with a terminal for input (istty), BASIC checks for
    Escape every 20th TRAP. Each check is a Minix `read()` system call,
    about 27K cycles, and they took ~40% of the time (PC histogram:
    sys_call, interrupt, phys_copy). The benchmarks and MAME read from a
    file and never poll. A real board used interactively pays the same
    cost.
  * **Possible port improvements (not done; for the user):**
    * poll less often;
    * or let the tty deliver ESC as SIGINT (VINTR=ESC with ISIG) while
      a program runs.
* Not done yet: a hosted copy, multi-file (non-SINGLE_FILE) variant,
  saving programs from the page.

## Entry 28 — 2026-10-21

### User request
> fix the escape polling, option 2; the demo will be for Mr Russel mainly
> to test the basic implementation, downloading is less important
> currently , efficient uploading is more urgent in this test.

### Actions taken
* **ESCape by signal** (`osl.c`, see PORT_PLAN §18):
  * terminal mode 4 while a program runs: ISIG with VINTR=ESC (off with
    `*ESC OFF`), NOFLSH, IXON;
  * a SIGINT handler (`sigaction`) sets the flag; `os_poll` only flushes
    and keeps mode 4;
  * `flush()` retries after EINTR.
* **Scripts:** the SIGINT reaches the whole foreground process group, so
  `demo/etc/demo` ignores it around bbcbasic (`trap '' 2`).
* **Kernel bug found** (Minix tree `3b61801`): `do_sigreturn` lost the
  interrupted code's condition codes. BASIC failed about one run in four;
  after the fix 20 of 20 pass. MAME image rebuilt. Patch copy:
  `mboot/patches/minix-0002-sigreturn-ccr.patch`.
* **Speed** (20000 empty loops at a terminal): 10 MHz web 6.5 → 3.9 s;
  MAME interactive 3.70 s (with input from a file it was 3.67).
  Demo (r68k): the BASIC loop 0.72 → 0.49 s.
* **`tools/ttycheck.py`** (`make ttycheck`): eleven checks on a pty, all
  ok.
* **Uploading** (web page):
  * Load program writes files to an emulated SD card (`web/pre.js`:
    `rosco_sd.bin` in memory, through r68k's firmware SD traps);
  * typed `*dd` lines copy them into BASIC's directory (`dd` added to the
    demo image), one line at a time after the prompt (typeahead during a
    *command gets ICRNL: Return becomes LF = cursor left);
  * one file is LOADed, or NEW + `*EXEC` for a listing; several files are
    copied for CHAIN;
  * 0.1–0.4 s per file (typing took 3–12 s);
  * tested in Node (upstream tests, a listing, two files + CHAIN) and
    Chromium (one and two files through the file input).
* **All tests pass:** bascheck 24/24, demo test, Node web test, browser
  test, ttycheck, the container image test, and on MAME (three bascheck
  suites, ESC, the speed).

## Entry 29 — 2026-10-21

### User request
> make a tarball of the web page so I can send it

### Actions taken
Made `/home/mboot/vibe/bbc68k-web-2026-10-21.tar.gz` (606 KB, sha256
8c315831…a9f5): `bbc68k-web/bbc68k.html` (the tested page, fd97f14) and a
README.txt for the recipient (how to open it, Load program, keys,
browsers, speed, what is not there yet).

## Entry 30 — 2026-10-21

### User request
> add downloading of files from the page

### Actions taken
* **Download** (a name field and a button) copies a file from BASIC's
  directory through the SD card:
  * `*wc -c` finds the file and its size (a name without an extension
    also as `.bbc`/`.BBC`; SAVE writes `.BBC` for a new file);
  * `*dd … of=/dev/c0d0 seek=K; sync` copies it to a fresh place;
  * the page reads it (`pre.js` `r68kSdRead`) and saves it as a browser
    download.
* **webmain.cpp:** flushes r68k's card stream (main.cpp `ifs`) every
  frame, before the output.
* **Uploads:** only a single program is converted (`.bas`/`.txt`/no
  extension listings, or tokenised). Other files, and several at once,
  are copied byte for byte (data files for OPENIN).
* **Tests:**
  * Node: SAVE + download (equal to the loaded file up to its end); a
    40000-byte binary up and down (identical); `*SPOOL` output; a
    missing file;
  * Chromium: SAVE "mine" + the Download button; the file saved by the
    browser checked.
  * All ok.
* **Send tarball rebuilt:** `/home/mboot/vibe/bbc68k-web-2026-10-21.tar.gz`
  (sha256 2bb60591…ed4c), its README describes Download.

## Entry 31 — 2026-10-21

### User report
> uploading files fives me: [the *dd line typed into the demo menu's
> INPUT, then LOAD: File not found]

### Actions taken
* **Cause:** the upload began while the demo menu waited at its INPUT,
  so the `*dd` line went to INPUT rather than BASIC's > prompt.
* **Fix:** `app.js` `toPrompt`: before an upload or download the page
  looks at the end of the output. At the > prompt it goes on; elsewhere
  it presses Escape and waits for the prompt (5 s); at the Minix shell
  (#) it asks for `bbcbasic`. Help texts and the tarball README updated.
* **Browser test:** a new first step loads at the menu's INPUT. Two
  waits matched stale text (the status "loaded", the screen's "Escape at
  line") and made the test flaky; the status is now cleared before each
  action and the screen before life. 6 of 6 runs ok. Escape during life
  in Node: 10 of 10.
* **Send tarball rebuilt:** `/home/mboot/vibe/bbc68k-web-2026-10-21.tar.gz`
  (sha256 8de81ff1…2a09).

### User question (mid-turn)
> regarding the demo, if we leave out minix and only demo the bbc-basic
> would that be possible? can we fake a system it is running on ? a bare
> bones 68k system?

Answered: yes. A bare-metal OS layer in place of osl.c/minix.s on the
rosco_m68k firmware, keeping BASIC unchanged; see the reply. Not started.

## Entry 32 — 2026-10-21

### User request
> yes , we should also thing about a step after that for people who would
> like to run it like that: if we can read and write files to the sd
> filesystem using the built in firmware.

Mid-turn: the user's upload of ARRAYTST.BBC stopped at line 160. That is
expected: 6-byte string descriptors (D1). The test suite patches those
lines with DESC%. Explained; a "Known differences" section was added to
the tarball README (sha256 335b3ab8…).

### Actions taken
Step 1, BBC BASIC on a bare rosco_m68k (PORT_PLAN §19): `bare/start.s`,
`bare/bare.c`, `osl.c -DBARE`, `tools/mkbare.py`, `make bare`,
`make barecheck` (bascheck's `BBC_EMU=bare` mode).
* 24 of 24 tests ok on bare BASIC in r68k.
* Boots on MAME's real firmware from the SD card; TIME, ESCape and
  `*DIR` checked.
* Found: the ACK drops `(void)` reads of volatile registers.

Planned next:
* the web page on bare BASIC;
* step 2: FAT files on the SD card through the firmware's SD routines.

## Entry 33 — 2026-10-22

### User request
> ok continue

### Actions taken
Step 2 and the web page on bare BASIC (PORT_PLAN §20):
* **`bare/fat.c`:** FAT16/FAT32 on the SD card through the firmware;
  stores dispatched in `bare.c` (card first, then RAM; `sd:`/`ram:`).
* **New commands:** `*MKDIR`, `*RMDIR` (`osl.c`).
* **Tests:**
  * `tools/fatcheck.py`: three cards, all ok, fsck clean;
  * MAME with the real firmware: files on the boot card, fsck clean.
* **Web page:** bare BBC BASIC by default; `pre.js` formats the card,
  and `web/fat.js` puts uploads on it and takes downloads off it.
  `make webminix` keeps the Minix page.
* **`webmain.cpp`:** STOP counts as idle (it had used a full core).
* **Bugs found:**
  * ACK `int` sign in `le16`;
  * stale-sector risk (the cache now lasts one call);
  * browser-test case of the 8.3 download name.
* **Send tarball:** `/home/mboot/vibe/bbc68k-web-2026-10-22.tar.gz`
  (400 KB, sha256 2869f623…): the bare page, a rewritten README, and
  `rosco/ROSCODE1.BIN` for a real board.

## Entry 34 — 2026-10-22

### User request
> make a docker image of the bare version too

Mid-turn question:
> i was thinking that perhaps we could mane a windows exe of the demo.
> normal stdin and stdout should work and perhaps we could read and write
> files directly from the windows host instead of simulating a sd card.
> would that be feasable ?

Answered: yes. A Windows r68k (MinGW, Win32 console instead of termios)
and host files through an emulator trap in place of the SD card; see the
reply. Not started.

### Actions taken
* **`tools/mkbaredemo.py`:** builds `build/bare/bbc68k-bare.tar.gz`
  (1.0 MB): r68k (-O2, static), the firmware, bare BASIC with the demos,
  `demo/demo-bare.sh` as `demo.sh`, `demo/README-bare.txt`, and
  `card.img.gz` (an empty FAT16 card as the web page's, unpacked into
  the card directory the first time, `BBC_CARD`).
* **`--docker`:** builds the image `bbc68k-bare` (saved as
  `build/bare/bbc68k-bare-image.tar.gz`, 2.9 MB), with `/card` as a
  volume.
* **`mkdemo.py`:** `docker()` generalised (image, extra Dockerfile
  lines, test runs); `build_r68k()` and `licences()` factored out.
* **Tests:**
  * native: asm demo, SAVE on the card, the file kept for the next start;
  * container: two runs with one volume, the file from the first seen by
    `*DIR` in the second.
  * All ok.

## Entry 35 — 2026-10-22

### User messages
> i installed mingw, pleas check if any thing you need is still missing.
> wind is installed, verify forst if you need more
> when you can take a break so i can restart you (a new claude version
> arrived)

### Findings (Windows exe, not started)
Test programs are in `build/win/t`.
* **MinGW-w64 GCC 14:** use `x86_64-w64-mingw32-g++-posix` (std::thread,
  for r68k's main.cpp).
  * C++20, `<filesystem>`, `<chrono>`, the console API with
    ENABLE_VIRTUAL_TERMINAL_PROCESSING, and `-static` all work.
  * The .exe needs only KERNEL32.dll and msvcrt.dll.
* **Wine runs the 64-bit .exe.** The "wine32 missing" message only
  concerns 32-bit programs.
  * In a pty, Wine's console passes keys and Return, but a lone ESC is
    taken as the start of an escape sequence (ESC Z arrived as Z). A real
    Windows console gives ESC.
  * Wine's console output puts cursor hide/show codes around each
    character (strip CSI codes in tests).
* **Piped stdin under Wine:** GetConsoleMode fails and GetFileType = 3
  (pipe), as expected. The test with PeekNamedPipe/ReadFile printed no
  bytes yet; to look into (perhaps PeekNamedPipe on Wine's pipe, or the
  shell pipe timing).

### Plan (agreed in outline)
* **r68k for Windows:**
  * Win32 console input (ReadConsoleInput; arrows etc. to vt100
    sequences; VT input mode where there is one) instead of
    termios/select;
  * VT output;
  * piped stdin/stdout for scripted runs and tests;
  * the ROM and bare BASIC built into one static .exe.
* **Host files:** an emulator trap for open/read/write/seek/close/
  unlink/rename/dir/chdir, used by bare.c as a third device (the default
  when present). Files are those of the folder the .exe runs in.
* **Tests:** the BASIC suite and the fatcheck checks against a host
  folder, under Wine through pipes.

## Entry 36 — 2026-10-22

### User request
> ok resume

### Actions taken
The Windows exe (PORT_PLAN §21): `host/` (`hostmain.cpp`, `hostfs.cpp`,
`compat/`), `tools/mkhost.py`, `tools/hostcheck.py`, bascheck's
host/hostwin modes, `ttycheck --exe`, `make host` / `make hostcheck`.
* **Problems found and fixed:**
  * keys typed before BASIC was up were lost (now held until it is idle);
  * the end-of-input test (60 Hz ticks wake the CPU);
  * the tests' demo menu program in memory (NEW);
  * Windows refusing to delete open files (FILETEST).
* **Result:** all suites pass on the Windows exe under Wine and on the
  Linux program.
* **Package:** `/home/mboot/vibe/bbc68k-windows-2026-10-22.zip` (649 KB,
  sha256 67d663b0…): `bbc68k.exe` and a Windows README.
* **Still to check on real Windows:** Escape and the cursor keys at the
  console (Wine in a pty loses a lone ESC).

## Entry 37 — 2026-10-22

### User report
> i tested it on windows, esc works, i see no arrows doing anything . i
> send the zip to mr Russel for his testign set to apply.

Mid-turn:
> ok in the editor let me see if i can test something.

### Actions taken
* **Cause (likely):** the console's VT input mode
  (ENABLE_VIRTUAL_TERMINAL_INPUT, untestable under Wine) delivered the
  arrows in a form the editor did not take (e.g. ESC O x).
* **Fixes:**
  * `hostmain.cpp` no longer uses VT input; `console_key` maps the key
    codes (arrows, Home/End, Insert/Delete) to vt100 itself;
  * `osl.c`'s editor also accepts ESC O x.
* **Tests:**
  * `host/keytest.cpp` injects real Windows key events (WriteConsoleInput,
    Left/Home with no character) into bbc68k.exe's console under Wine:
    Left and Home work. It is now part of `hostcheck.py`;
  * `ttycheck` has an ESC O D case;
  * all ok, and bascheck host/hostwin 24/24 each.
* **New zip:** `/home/mboot/vibe/bbc68k-windows-2026-10-22b.zip`
  (sha256 ec66f752…).

## 38. Status check

* **User:** "status ?"
* Nothing in progress: the cursor-key fix is committed (c5ae923), the
  tree is clean, and the new zip awaits the user's Windows test. A stale
  background waiter (its pgrep matched its own command line) was stopped;
  the last demo container test had passed.

## Entry 39 — 2026-10-22

### User report
> in both the old image today (22) and the 22b image the arrows do not
> work right when i do LIST all lines are properly alined but when i enter
> EDIT all appears on one line and e.g. right arrow erases the text, down
> arrow works, up arrow does nothing so that is why right arrow seems to
> erase the text it is already on a different line, left arrow also works

### Cause
* **The line is wider than the console.** The editor moves left with
  BS, and a BS at the console's left edge stays put. Up (to the start)
  and EDIT's redraw both stopped at column 0 of the last row, so Right
  then retyped the start of the line over that row.
* **Plain `EDIT`** is `LIST` with the output captured into the line,
  which joined the whole program into one line (as on CP/M).

### Actions taken (branch mboot/edit-wrap)
* **`host/hostmain.cpp`:** `wrap_bs` tracks the cursor column against
  the console width (Windows: GetConsoleScreenBufferInfo; Linux:
  TIOCGWINSZ) and turns a BS at the left edge into ESC[A ESC[wG. After
  the last column, Windows checks where the cursor really is (the
  classic console wraps at once, Windows Terminal waits); Linux assumes
  xterm's delayed wrap.
* **`osl.c`:** EDIT captures the first listed line only.
* **`tools/editcheck.py`** (in `make hostcheck`): a 40-column pty with a
  vt100 screen model; it edits a two-row line with the cursor keys.
  * The new build passes 12/12; the old build fails all 12 (the bug is
    reproduced).
* **Other checks:**
  * bascheck host/hostwin/bare 24/24 each;
  * hostcheck (Wine keytest) and ttycheck --exe all ok.
  * The Windows side of `wrap_bs` cannot be tested under Wine in a pty.
* **Found on the way:** `src68k/test/bas/a01asm.exp` is ignored by
  `.gitignore` (`*.exp`) and was never committed. A fresh checkout's
  bascheck fails a01asm. It is now added with `git add -f`.
* **New zip:** `/home/mboot/vibe/bbc68k-windows-2026-10-22c.zip`
  (sha256 9531f876…).

## 40. Continue

* **User:** "continue"
* Nothing new to build. The EDIT-wrap fix (entry 39) is committed on
  branch `mboot/edit-wrap` (a24e76b), one commit ahead of
  `mboot/conversation-log`; editcheck still passes 12/12.
* Waiting for the user's Windows test of
  `bbc68k-windows-2026-10-22c.zip` (sha256 9531f876…, checked).

## 41. Windows test of zip c

* **User:** "looks like its working no arrow key now deletes anything,
  changing the line + return keeps the infor on LIST. naturally *EDIT
  will not work"
* **Result:** the EDIT-wrap fix (a24e76b) works on real Windows: the
  cursor keys move across the wrapped line, and the edited line is kept.
* `*EDIT` (a star command for an external editor) is not provided by
  the port, as expected.
* `mboot/edit-wrap` is ready to be fast-forwarded into
  `mboot/conversation-log` when the user wants.

## 42. Fast-forward

* **User:** "do the fast-forward merge"
* `mboot/conversation-log` fast-forwarded to `mboot/edit-wrap`
  (fc470f3 → 3c271eb): the EDIT-wrap fix, editcheck.py, a01asm.exp and
  log entries 39–41. Not pushed.

## 43. Lockdown before moving hosts

* **User:** "ok we are currently on a remote host and some of the code
  you have access to in ../* is not yet on the new target host where we
  are going to move you or out of sync. prepare for a lockdown here and
  then i will transfer you to another host and we can investigate what
  next steps we have to do to synchronize the repositories."
* **Snapshot of `/home/mboot/vibe` (nothing pushed):**
  * BBCZ80 `mboot/conversation-log`: the whole port on origin/master
    (410e7fb), not pushed. `mboot/edit-wrap` is merged into it. This
    entry is on `mboot/lockdown`, one commit ahead; fast-forward
    `mboot/conversation-log` to it. The remote-tracking refs
    `agent-s-8250/*` (a remote with no URL) are ancestors and need
    nothing.
  * minix-st-2.0.4 `rosco-m68k`: 2 commits ahead of origin (107f0d0,
    3b61801).
  * r68k `rosco-minix-duart`: 1 commit ahead of origin (2d92829).
  * rosco-emulator, RunCPM: same as origin.
  * Build outputs (git-ignored) are not carried over; rebuild them on the
    new host.
* **Lockdown kit:** `/home/mboot/vibe/lockdown-2026-10-22/` (and a
  `.tar.gz` of it): full git bundles of BBCZ80, minix and r68k,
  `MANIFEST.txt` (exact heads, remotes, ahead counts, artifact sha256s),
  `verify.sh` to compare a host's repos with the manifest, the release
  zips and tarballs, and a copy of Claude's project memory.

## 44. Recovery on the new host

* **User:** "inspect the current directory, dont change anything we are
  recovering from a lockdown and need to compare whith what is already
  on this host"; later "BBCZ80, option a, show me the merge first" and
  "ok, merge, and add entry 44".
* **Host:** vibe-u26; the repos are in
  `/net/192.168.122.1/home/mboot/share-local/DEV/github.com/maarten-boot/68k/`
  (not `~/vibe`), the kit in `lockdown-2026-10-22/` beside them. Kit
  checksums and all three bundles verified.
* **Compared with MANIFEST.txt:**
  * BBCZ80: `master` and `mboot/edit-wrap` the same. `mboot/conversation-log`
    had diverged: this host had "sync" (b9c213d) and "cleanup" (0113871),
    already on origin, with the content of entries 36–42 but not their
    history; `mboot/lockdown` was missing.
  * r68k `rosco-minix-duart`: 1 behind (2d92829).
  * minix-st-2.0.4 `rosco-m68k`: 54 newer commits here, the 2 lockdown
    commits (107f0d0, 3b61801) not here. Left alone: another session is
    working in that tree.
  * rosco-emulator: the same. RunCPM: no clone; fetch from GitHub when
    needed.
* **Done:**
  * r68k fast-forwarded to 2d92829 from the bundle (not pushed).
  * Global git identity set (Maarten Boot, GitHub noreply address); the
    two host commits above are authored "Your Name" and stay as pushed.
  * BBCZ80: `mboot/lockdown` restored from the bundle and merged into
    `mboot/conversation-log` (45393c5). The only conflict was this log
    (entry 43 taken from the lockdown); `src68k/test/bas/a01asm.exp` is
    tracked again; `.gitignore` keeps `.claude/worktrees/`. Not pushed.
* **Open:** Claude project memory from the kit not installed yet (paths
  still name `/home/mboot/vibe`); an uncommitted edit in rosco-emulator
  `src/osd/modules/debugger/none.cpp`; the minix commits; build outputs
  to rebuild here.

## 45. Memory, pushes and the MAME debugscript fix

* **User:** "BBCZ80 with pointer in parent, b, content ok"; "reverify i
  pushed some stuff in both"; "show me the rosco-emulator edit"; "a,
  commit it"; "add entry 45 now".
* **Claude project memory** installed for this repo's path
  (`~/.claude/projects/-net-...-68k-BBCZ80/memory/`): the port note with
  the new paths and current status, the podman keep-id note marked as
  old-host only (on vibe-u26 `docker` is real Docker), and a new
  lockdown-recovery note. The parent `68k` project memory got a pointer
  to it; its existing index line (rebuild-images-at-end) was overwritten
  by mistake and restored word for word.
* **Pushes by the user, verified on GitHub (https ls-remote):** BBCZ80
  `mboot/conversation-log` at fed9a96, r68k `rosco-minix-duart` at
  2d92829. Claude's shell has no SSH key for GitHub, so the user pushes.
* **rosco-emulator:** the uncommitted `src/osd/modules/debugger/none.cpp`
  change from the minix session of 2026-10-18 (run the `-debugscript`
  before the null debugger resumes, so headless breakpoints with actions
  work) committed as f283c47 on `rosco-m68k-ram-bios`. Not pushed; MAME
  not rebuilt.
* **Still open:** the 2 minix lockdown commits (another session works in
  that tree), RunCPM on demand, build outputs to rebuild here.

## 46. Inspection, and GitHub issue #1 from R.T. Russell

* **User:** "inspect the current folder it is a project moved here from
  another remote agent"; "inspect the issue found by mr Russel:
  https://github.com/maarten-boot/BBCZ80/issues/1 and make a note to
  address it later"; "add entry 46 now".
* **Inspection (nothing changed):** `mboot/conversation-log` clean and
  equal to origin (b6000f6). r68k, rosco-emulator and ack equal to
  their origins. minix-st-2.0.4 still lacks the lockdown commits
  107f0d0 and 3b61801; it has 2 modified files and 2 untracked dirs
  from the other session (left alone). `../r68k/r68k` is still not
  built. The `agent-s-8250/*` and `lockdown/*` remote-tracking refs
  are stale (their remotes are gone).
* **Issue #1, "Assembler macro not working":**
  ```
  10 DIM P% 20
  20 [OPT FN1("test")
  30 ]
  40 END
  60 DEF FN1(A$)
  70 [OPT 2
  80 dc.b A$
  90 ]
  100 = 2
  ```
  gives `Not in a FN at line 100` on the 68k port (reproduced with
  `build/host/linux/bbc68k`). The Z80 BBCBASIC.COM under RunCPM (with
  `DEFM A$`) runs it fine, so it is a port bug.
  * It fails when the FN body has any `[...]` (even `[OPT 2:]`, no
    parameters) and the FN is called from an operand inside an outer
    `[...]` (`OPT` or `dc.b`). An FN without `[...]` under `OPT` works,
    and so does `A%=FN1` with `[...]` inside.
  * At `=` (FNEND, `exec2.s`) the top of the stack is no longer FNCHK
    after the nested assembler block. Reading ASM, ASSEM, ASMB, H_OPT
    and XEQ did not show what is left there; the next step is to trace
    sp across the inner `[`..`]`.
  * Second bug: the assembler state in `asmb.s` is global (asmsp,
    asmstm, asmpc, asmdst, mclass/mopw/op1, LISTON), where the Z80
    keeps IX/IY on the stack. The nested block clobbers the outer one:
    an outer `OPT 2` statement gets listed, with empty source text.
    Save and restore that state around the nested call, and add a test
    to `src68k/test/bas`.
* **Not fixed:** the user asked for a note only. Claude project memory
  has `issue1-opt-fn-nested-asm.md` with the repro and these findings.
  Nothing posted on the issue.

## 47. GitHub issue #1 traced and fixed (assembler macros)

* **User:** "ok status?"; "yes, start the issue #1 trace"; "yes,
  implement the fix"; "yes, commit it and add entry 47; after that do a
  crosscheck".
* **Status:** all repos as at entry 46; the issue had one comment, the
  user's "Investigating" post with the entry 46 findings.
* **Trace:** no rebuild needed. A probe assembled in BASIC
  (`[move.l sp,d0:rts]`, called with `USR`) showed the stack depth at
  each point: the line after the FN's inner `]` ran twice, the second
  time at top-level depth, so the `=` found no FN. Varying the inner
  block (`[]`, `[nop:]`, `[OPT 0:]`) showed that only an inner assembler
  *expression* breaks it, and the outer listing showed the inner's
  source text.
* **Cause:** `EXPRA`/`EXPRV` in `asmb.s` copied the operand to a global
  buffer (`abuf`) and kept a4/a5 in globals (`eend`, `esva5`). The FN's
  own `OPT 2` overwrote them, the outer block's text pointer came back
  inside the FN body, read the FN's `]` as its own, and ran on in the
  FN at top level.
* **Fix (b5e639e):**
  * `EXPRX` (EXPRA and EXPRV): the operand copy is on the stack, and so
    are the assembler state `asmsp..asmend` and CURLIN while BASIC runs.
  * ASSEM re-reads P% after each statement, as the Z80 does: a macro's
    code stays and P% ends after it.
  * Restoring CURLIN fixes the line number of an error after a macro
    (`Syntax error at line 20`, as the Z80; it had none before).
  * New test `test/bas/a02macro` (the issue program, two macros in one
    block, recursion 5 deep, an operand across a nested macro, the error
    line); `ASSEMBLER.md` gets a Macros section (its example run);
    `asmcheck.py` gets `BBC_EMU=host`.
  * `.gitignore`: `!src68k/test/bas/*.exp`, since the global `*.exp`
    (linker files) also hid the test expectations.
* **Checked against the Z80 (RunCPM):** a macro in a non-OPT operand
  (`LD HL,FNk(5)`) gives stray bytes there too; the inner `]` setting
  OPT 3 is Z80 behaviour, kept.
* **Tests (Linux PC build):** bascheck 25 of 25, asmcheck 162 of 162.
  Not run: Minix (the minix tree's rootfs has no `/bin/sh` now; the
  other session's work, left alone), bare, the Windows exe (no MinGW on
  vibe-u26, so `bbc68k.exe` is the old one).
* **Host setup:** `../r68k/firmware/rosco_m68k.rom` copied from
  `build/r68kprof` (gitignored build output) so `mkhost.py` runs.
* **Crosscheck (same turn, after f2e44f2):**
  * An independent review of b5e639e (a fresh agent given the commit,
    not the reasoning) found the stack offsets, the state block (120
    bytes, 60 words), the registers, the error paths and the P% re-read
    correct, and one defect: COPYX's `$hex` path wrote a DEF token as 3
    bytes and went back without the bound check. Typed input cannot
    reach it (the 255-character line limit); a stored line can. Built
    in memory (225 X's poked into DEF tokens), it hung the old build:
    the overflow now lands on the evaluator address. Fixed in 42fe3fa
    (bound check in the hex loop), the case added to `a02macro`.
  * Differential against the Z80 (RunCPM, the same program with
    DEFB/DEFM against dc.b): issue program, two macros among data,
    recursion 6 deep with data before and after, two passes with a label
    set in a macro, OPT 4 with O%, and a syntax error inside the macro:
    the same output. One difference unrelated to macros: `dc.b 999` is
    Out of range on the 68k, while the Z80 `DEFB 999` keeps the low byte
    (as before; ASSEMBLER.md does not say so).
  * After the fix: bascheck 25 of 25, asmcheck 162 of 162 (host).

## 48. Push verified; draft reply for issue #1

* **User:** "reverify i pushed"; "add entry 48 now".
* **Verified on GitHub (https ls-remote):** `mboot/conversation-log` at
  28e6b1e, the same as here (b5e639e, f2e44f2, 42fe3fa, 28e6b1e are
  up). `master` unchanged at 410e7fb, so the fix is not on master yet.
* **Draft reply for issue #1** given to the user to paste (not posted
  by Claude): fixed on `mboot/conversation-log` (b5e639e, 42fe3fa); the
  cause (one global copy of the operand text, overwritten by the
  macro's own assembler); the fix (operand copy and assembler state on
  the stack, P% re-read as in the Z80, the error line after a macro);
  checked against BBCBASIC.COM under RunCPM; the test `a02macro` and the
  Macros section of `ASSEMBLER.md`. Suggested to drop the "fixed on
  branch" wording if the issue should close only when master has it.
* **Claude project memory:** the issue note now says fixed, committed
  and pushed.
* **Still open:** merge to master; the Windows exe (no MinGW here),
  Minix and bare runs of the new test; the 2 minix lockdown commits;
  `ASSEMBLER.md` could say that `dc.b` checks the range (the Z80 `DEFB`
  keeps the low byte).

## 49. A fresh Windows exe

* **User:** "reverify i pushed"; "ok can you build me a fresh standalone
  windows .exe"; mid-turn "installing mingw and wine"; "add entry 49
  now".
* **Push verified:** `mboot/conversation-log` on GitHub at a1daff4
  (entry 48); `master` still 410e7fb.
* **Build:** vibe-u26 had no MinGW and Claude's shell has no sudo, so
  the exe was cross-compiled in a throwaway Docker image `bbc68k-mingw`
  (ubuntu:24.04 with g++-mingw-w64-x86-64-posix, GCC 13, plus gcc for
  musashi's m68kmake, python3, git, patch, make), running
  `tools/mkhost.py --windows` as uid 1000 on the tree mounted at its own
  path. Bare BBC BASIC rebuilt first (`mkbare.py`, `--demo`) from the
  current source (b5e639e + 42fe3fa).
* **Result:** `build/host/windows/bbc68k.exe`, 1768960 bytes, PE32+
  x86-64 console; it imports only KERNEL32, msvcrt and WS2_32
  (standalone). The only compiler warning is EXCEPTION_ILLEGAL_INSTRUCTION
  defined twice (MinGW headers), harmless.
* **Tests (Wine, installed by the user meanwhile):**
  `BBC_EMU=hostwin bascheck` 25 of 25 (with `a02macro`), `hostcheck.py`
  all ok for both PC programs (files, folders, paths refused outside the
  folder, `*DIR`, the Windows console keys). Not tried on real Windows.
* **Host setup now:** MinGW-w64 and Wine installed on vibe-u26, so
  `make host` / `make hostcheck` work here directly. The Docker image
  `bbc68k-mingw` is no longer needed and can be removed.

## 50. Windows zip, bare tests, merge to master

* **User:** "reverify i pushed; and where can i find the exe now ?";
  "yes, make the zip with a README"; "ok status"; "r68k has been built,
  the minix tree is currently engaged so off limits for change. we will
  wait on the confirmation before closing the issue."; "ok merged with
  my master"; "add entry 50 now".
* **Push verified:** `mboot/conversation-log` at 8cdfce1 (entry 49).
* **Zip:** `68k/bbc68k-windows-2026-10-23.zip` next to the repos (634
  KB, sha256 ef0ad0ab…), laid out as zip c: `bbc68k-windows/bbc68k.exe`
  (sha256 d5d9e873…, the exe tested under Wine; the user had renamed the
  build output to `bbc68k-261023-1042.exe`, same hash) and `README.txt`
  (zip c's, plus a version line, macros work as in the Z80, the dc.b
  range difference, and "Changes since 2026-10-22c").
  * Checked for the README: with OPT 2, `dc.b 999`, `dc.w 70000` and
    `equb 999` are Out of range; with OPT 0, `dc.b 999` keeps the low
    byte (231), as the Z80.
* **Status:** the minix session redid the two lockdown fixes (62de4f6
  lone ESC, f0a8cd6 sigreturn condition codes, 6b658ed test and images),
  so the lockdown recovery is complete. Minix still boots to `rosco
  login:` with no `/bin/sh` in its rootfs; the minix tree is engaged by
  the other session and off limits for changes.
* **Bare rosco_m68k (r68k built by the user):** `make barecheck` all ok:
  `BBC_EMU=bare` bascheck 25 of 25 (with `a02macro`), fatcheck on FAT12,
  FAT16 and FAT32 (fsck clean). The fix is now tested on Linux, Windows
  (Wine) and bare; Minix waits for the minix tree.
* **Merge:** the user merged `mboot/conversation-log` into master on
  GitHub (PR #2, 4150025, a merge of 410e7fb and 8cdfce1; its tree is
  the same as 8cdfce1). The local `master` here is still 410e7fb.
* **Issue #1:** open, with the user's three comments; it stays open
  until R.T. Russell confirms the fix.
* **Still open:** Minix run of the new test; the local master
  fast-forward (offered); remove the `bbc68k-mingw` Docker image; a
  sentence in `ASSEMBLER.md` on the dc.b range check.

## 51. Status after the merge

* **User:** "reverify i pushed"; "ok status"; "add entry 51 now; then
  look at https://github.com/maarten-boot/agon-bbc-basic ... see if you
  can find improvements suggestions from that implementation. Dont
  change the current code in this tree just write additional
  suggestions and plans with references where needed."
* **Push verified:** `mboot/conversation-log` at 92eb386 (entry 50);
  GitHub master at 4150025 (PR #2, closed), without entry 50.
* **Status:** issue #1 open with the user's 3 comments, no reply from
  R.T. Russell yet; the fix tested on Linux, Windows (Wine) and bare,
  Minix waits for the minix tree (6b658ed, 3 files being changed by
  the other session). r68k has one uncommitted `.gitignore` line
  (`tmp/`), not Claude's. rosco-emulator and ack clean.
* **Next (this turn):** a study of the Agon (eZ80, 24-bit) BBC BASIC for
  ideas for this port, written as a separate plan; no code changes.
