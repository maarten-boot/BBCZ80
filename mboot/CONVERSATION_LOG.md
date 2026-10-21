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
