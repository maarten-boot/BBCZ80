# BBC BASIC 68k: conventions

Rules for translating `src/*.Z80` into ACK 68000 assembly (`src68k/*.s`). This
is phase 1 of `mboot/PORT_PLAN.md`. Every item marked *(probed)* was checked
with the minix68k ACK on 2026-10-20.

## 1. Target and tools

* **CPU:** the code must run on a **68000/68010**:
  * no 68020 instructions;
  * no `move sr` (privileged on a 68010; the kernel can emulate it, but
    slowly);
  * no `move ccr,<ea>` (the assembler rejects it as "68010 instruction").
* **Assembler:** ACK `as` for minix68k, run by
  `../minix-st-2.0.4/src/rosco/ack/acc` (assemble) and `acc-minix` (link with
  crtso and libc). It assembles for the 68000 only, so 68020 mnemonics are
  rejected *(probed)*.
* **Test:** `src68k/tools/runminix.py` boots Minix in r68k and runs commands.
  Use the r68k from `maarten-boot/r68k` (branch `rosco-minix-duart`, cloned
  at `../r68k`) with the illegal-instruction fix, so that a bad opcode
  raises SIGILL instead of being skipped.

## 2. ACK assembler dialect *(probed)*

| Topic | Rule |
|---|---|
| Sections | Every file starts with `.sect .text` / `.rom` / `.data` / `.bss` in that order, then switches as needed |
| Symbols | `.define sym` exports, `.extern sym` imports. C symbols take a leading `_` (`_write`) |
| Comments | `!` to the end of the line |
| Statements | `;` separates statements on one line |
| Local labels | `1:` … `bra 1f` / `bra 1b` |
| Constants | `X = 5`; hex `0x7f`; characters `'A'` |
| Grouping | **`[ ]`, not `( )`**: `#[X<<8]\|3`, `.data2 [X+1]*2` |
| Data | `.data1`, `.data2`, `.data4`, `.ascii "…"`, `.asciz "…"`, `.space n`, `.align n`, `.comm sym,n` |
| Quick forms | Chosen automatically: write `move.l #1,d0` (gives `moveq`), `add.l #1,d0` (gives `addq`), `sub`, … The mnemonics `moveq`/`addq`/`subq` do not exist |
| Branches | Write `bra`/`bcc` with no size; the assembler chooses short or word. The 68000 range is ±32 KB ("too big" beyond that): use `jmp`/`jsr` |
| `cmpm` | Written `cmp.b (a0)+,(a1)+` |
| Indexed | `0(a0,d0.w)` (the displacement is required: `(a0,d0.w)` is a syntax error); `lab(pc,d0.w)`; `lab(pc)` |
| Shift by 8 | `ror.w #8,d0` / `lsl.l #8,d0` (shift counts are 1–8) |
| cpp | Runs **only if the file's first character is `#`**. Put a lone `#` on line 1. `#include` and object-like `#define` work. **Function-like macros cannot contain immediates**, because `#` is the stringize operator. Use subroutines, or object-like macros with fixed registers |

## 3. Register mapping

The Z80 code reuses its registers for many roles, so the mapping is fixed at
**interfaces** (entry and exit of documented routines). Inside a routine the
translator may choose freely. Each translated routine keeps the Z80 header
comment ("Inputs / Outputs / Destroys") rewritten in 68k register names.

### 3.1 Fixed roles

| Z80 | 68k | Role |
|---|---|---|
| IY | **a4** | program text pointer (PTR into the BASIC line). Persistent |
| SP | **sp** | the BASIC stack (also the C stack; see §6) |
| IX | **a5** | variable / parameter / FPP-frame pointer |
| A | **d4.b** | the "A" register: character, type byte, op-code, error number |
| HL as pointer | **a3** | |
| DE as pointer | **a2** | |
| BC as pointer | **a1** | |
| BC / DE / HL as counters or 16-bit values | d5.w / d6.w / d7.w | When they are not addresses |

### 3.2 Numeric accumulators (MATH, EVAL)

| Z80 | 68k | Meaning |
|---|---|---|
| `HLH'L'` | **d0.l** | Accumulator mantissa or integer: H = bits 31–24 … L' = bits 7–0 |
| C | **d1.b** | Accumulator exponent; 0 = integer |
| `DED'E'` | **d2.l** | Second operand, mantissa or integer |
| B | **d3.b** | Second operand exponent |
| `BC'` | d5.w (or as the routine needs) | Extra precision / guard bits in MATH |

* The numeric format is unchanged from the Z80: a 32-bit sign-magnitude
  normalised mantissa with the sign in bit 31 replacing the implied 1, and an
  8-bit excess-128 exponent; integer = 32-bit two's complement with exponent 0.
* `EXX` used only to reach the other half of a 32-bit number disappears
  (`d0.l` holds all of it). `EXX` used to keep a second set of registers must
  be translated case by case.

### 3.3 Flags

* Z, C, N and V keep their Z80 meaning wherever a routine returns status in
  flags (for example FPP: good = Z and NC; error = NZ and C with the error
  number in d4.b).
* 68k `cmp`/`sub` set C on a borrow, as Z80 `CP`/`SUB` do.
  * Z80 `RET PO`/`PE` after an `ADC`/`SBC` overflow check maps to `bvc`/`bvs`.
  * Z80 `P`/`M` maps to `bpl`/`bmi`.
* Set the flags explicitly with `move.w #n,ccr` (legal on a 68000;
  X=16 N=8 Z=4 V=2 C=1):
  * Z and NC: `move.w #4,ccr`;
  * NZ and C: `move.w #1,ccr`.
* **Saving the flags** (`PUSH AF`, `EX AF,AF'`) is not possible cheaply. Keep
  the needed condition in a register instead (`scs d7`, `seq d7`), or
  recompute it. Write a comment wherever this happens.
* Differences that cause bugs:
  * 68k `move` and `clr` change N/Z and clear V/C, but Z80 `LD` changes no
    flags.
  * 68k `addq`/`subq` to an **address** register change no flags, but to a
    **data** register they do, unlike Z80 `INC rr`/`DEC rr`.
  * Z80 `INC r`/`DEC r` (8-bit) leave C alone; 68k `addq.b` changes C and X.
  * Z80 `AND`/`OR`/`XOR` clear C; so do 68k `and`/`or`/`eor`.

## 4. Memory

* **Pointers are 32 bits** (decision D1). Every structure that held a 16-bit
  pointer gets a 4-byte field:
  * the variable-chain links;
  * `PAGE`, `LOMEM`, `FREE`, `HIMEM`, `LIBASE`;
  * `DATPTR`, `ERRTRP`, `CURLIN`;
  * the FN/PROC stack frames;
  * the `DYNVAR` heads (54 × 4).

  Record each changed layout in the module header.
* **BASIC-visible data is little-endian** (decision D2):
  * integer variables (4 bytes);
  * floats (4-byte mantissa + exponent byte);
  * `!`, `?` and `$` indirection;
  * the line number in program lines;
  * string descriptors;
  * the stored pointers above.
* **Alignment:** the 68000/68010 raises an address error on word or long
  access to an odd address. BASIC data is byte-packed, so **every access to
  BASIC-visible multi-byte data goes byte by byte** through the helpers in
  `util.s` (planned):

  | Helper | Effect |
  |---|---|
  | `LDLE4` | `d0.l` ← (a0), little-endian |
  | `STLE4` | (a0) ← `d0.l` |
  | `LDLE2`, `STLE2` | 16-bit versions |
  | `LOAD5` / `STORE5` | mantissa + exponent, as in the Z80 code |

  Interpreter-private globals in `.bss`/`.data` are big-endian, aligned, and
  accessed with normal `move.l`/`move.w`.
* `ACCS`, `BUFFER` and `STAVAR` were page-aligned so that the Z80 could use E
  as the string length. On the 68k a string result is
  `ACCS` + length, with the end pointer in **a2** and the length in **d6.w**.
  Keep `.align 256` anyway; it is cheap and keeps any leftover low-byte
  tricks valid.

## 5. Calling C (only from `minix.s`)

* ACK m68k2 ABI *(probed)*:
  * arguments are pushed right to left;
  * `int` and `unsigned` are **2 bytes** (`move.w`); `long` and pointers are 4;
  * the caller pops the arguments;
  * the result is in `d0` (`.w` for int, `.l` for long and pointers);
  * d0–d2/a0–a1 may be clobbered; d3–d7/a2–a6 are preserved.
* Only `minix.s` calls libc. Its routines save d0–d2/a0–a1 themselves where
  the interpreter expects them preserved. The rest of the interpreter never
  calls C directly.
* No stdio and no malloc: use `read`/`write`/`open`/`close`/`lseek`/`ioctl`/
  `tcgetattr`/`tcsetattr`/`time`/`times`/`signal`/`_exit`.

## 6. Memory layout at run time (to verify in phase 3)

```
text | data | bss (ACCS, BUFFER, STAVAR, …) | PAGE … LOMEM … FREE → ... ← sp  HIMEM | (top)
```

* Link with `acc-minix -S <stack>` so that the gap between `_end` and the
  initial `sp` is BASIC's workspace (as on CP/M, where the TPA lies between
  the program and BDOS).
  * `PAGE` = `_end` rounded up;
  * `HIMEM` = initial `sp` minus a margin for crtso, signals and libc
    calls;
  * the BASIC stack grows down from there, as on the Z80.
* Signal delivery pushes a frame onto the user stack, so keep at least 512
  bytes of margin below HIMEM's stack use. Check in phase 3 that the Minix
  kernel does not object to user `sp` values within the segment.

## 7. Source layout

| File | From | Notes |
|---|---|---|
| `src68k/main.s` | MAIN.Z80 | |
| `src68k/exec.s` | EXEC.Z80 | |
| `src68k/eval.s` | EVAL.Z80 | |
| `src68k/math.s` | MATH.Z80 | |
| `src68k/asmb.s` | (stub) | `[` → "Not supported" (decision D3) |
| `src68k/data.s` | DATA.Z80 | |
| `src68k/minix.s` | replaces CMOS / DIST / HOOK | OS layer |
| `src68k/util.s` | (new) | little-endian / unaligned helpers |
| `src68k/bbc.h` | (new) | shared constants and macros (cpp) |
| `src68k/test/` | | stand-alone tests (`hello.s`, `cpu020.s`, later `mathtest`) |

Each `.s` keeps the Z80 routine names and order, so that the two sources can be
read side by side. Keep the original Z80 line as a trailing comment where the
translation is not obvious.

## 8. OS layer interface (phase 3)

The OS layer is `minix.s` (register glue, the TRAP/LTRAP hot path and the
`_main` entry), `osl.c` (the implementation, in C via ACK) and `hook.s`
(graphics and sound hooks: all give "Sorry"). `minix.s` has the full
table of interfaces at its top. In short:

* **Register mapping:**
  * character or type in d4.b;
  * channel in d6.b, except PUTPTR, which takes it in d4.b;
  * file and command names CR-terminated in a3;
  * memory address in a2, length in d5.l;
  * 32-bit values (TIME, PTR#, EXT#) in d0.l;
  * the OSKEY time limit in d7.l.
* **Status:** returned in CCR:
  * OSKEY: C set means a character was read;
  * OSLOAD: C clear means no room;
  * OSBGET: C set means the last byte was read;
  * OSSTAT: Z set means end of file.
* **Preserved:** every routine preserves all registers it doesn't name as
  outputs, but **not CCR**. A 68010 cannot save CCR cheaply, so callers
  must not carry flags across an OS call; the Z80 OSWRCH preserved F.
* **EXTERR contract** (used by the OS layer, and by the interpreter
  translation): d4.b = error number, (sp) = address of the NUL-terminated
  message, as after `jsr EXTERR` followed by `.asciz "..."` and
  `.align 2`.
* **Memory map:**
  * `OSINIT` returns PAGE = `_end` rounded up to 256 and HIMEM = the stack
    pointer at `_main`;
  * the gap between them comes from `acc-minix -S` (chmem);
  * DATA (`data.s`) is ordinary `.bss`;
  * `.align 256` is **not** honoured in `.bss`, so nothing may rely on a
    page-aligned ACCS.
* **C side:** the interpreter variables it needs have `_` aliases in
  `data.s` (`_accs`, `_curlin`, `_autono`, `_himem`, `_free`). The
  interpreter must also provide `_vermsg` (CR LF terminated) next to
  VERMSG.
