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
