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
