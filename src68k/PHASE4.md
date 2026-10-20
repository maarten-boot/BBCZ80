# Phase 4 design notes: interpreter data layouts and internal interfaces

Working notes for translating MAIN, EVAL and EXEC. CONVENTIONS.md holds the
general rules; this file fixes what changes because pointers are 32 bits,
plus the register contracts of the internal routines as they get
translated. **Update it whenever a layout or contract is decided.**

## 1. Unchanged from the Z80 (BASIC-visible, binary compatible)

* **Program text** (and therefore `.BBC` files), per line:

  ```
  [length][line number LE 2][tokens ...][CR]
  ```

  * The length includes the 4 bytes of overhead.
  * The program ends with a 0 length byte, followed by `FF FF`.
  * Line numbers inside a line (after GOTO etc.) are TLINO (&8D) plus 3
    encoded bytes (ENCODE/DECODE).
* **Tokens** and the keyword table.
* **Numbers in memory:**
  * integer: 4 bytes LE;
  * float: 4-byte LE mantissa plus an exponent byte;
  * byte variable: 1 byte.
* **Static variables** `@%` and `A%`–`Z%`: STAVAR + 4*n, LE.
* **@% format bytes:** +0 field width, +1 digits, +2 format, +3 STR$ flag.
* **Array blocks:**

  ```
  [number of dimensions][dimension sizes, 2 bytes LE each][elements]
  ```

  * The sizes are the DIM bounds + 1, as on the Z80; at most 65535 per
    dimension.
  * Elements are 1, 4 or 5 bytes, or a 6-byte string descriptor (see §2).

## 2. Widened to 32-bit pointers (all little-endian, byte-wise access)

| Structure | Z80 | 68k |
|---|---|---|
| Chain link (variables, FN, PROC) | 2 | **4** |
| Chain heads DYNVAR[54], FNPTR, PROPTR | 2 each | **4** each (`data.s`) |
| Variable node | `[link 2][name][0][value]` | `[link 4][name][0][value]` |
| Array variable value (pointer to the array block; 0 = not DIMmed, 1 = LOCAL array not yet DIMmed) | 2 | **4** |
| String descriptor (string variable value, string array element) | `[len][alloc][addr 2]` = 4 | `[len][alloc][addr 4]` = **6** |
| FN/PROC entry value (address of the DEF text) | 2 | **4** |

So the value sizes in CREATE (LOC9) are:
* byte 1, integer 4, float 5;
* string **6**;
* array pointer **4**.

The "×n" element-size routine (Z80 `X14OR5`) gives 1, 4, 5 or 6
(string). It is called `XELSIZ` in the 68k code.

## 3. Interpreter-private (big-endian, aligned; see data.s)

* PAGE, LOMEM, FREE, HIMEM, LIBASE, ERRTRP, ONERSP, ERRTXT, DATPTR and
  CURLIN are longs.
* ERL is a word. TRACEN and AUTONO are longs (on the Z80, 2-byte
  "flag and number" fields).

## 4. Stack frames (68k layouts, decided as the statements are translated)

* The markers are code addresses, as on the Z80: the `bsr XEQ` return
  address (FORCHK, REPCHK, GOSCHK, WHICHK, PROCHK, FNCHK, LOCCHK, ARRCHK,
  RETCHK).
* A marker is a long on the stack; text pointers and variable pointers are
  longs.
* Numbers on the stack: mantissa .l plus exponent/type .w (as PUSH5 in
  math.s).
* The markers are pushed with `pea LABEL` where the Z80 had `CALL LABEL`
  followed by `LABEL:`. ACK assembles a `bsr` to the next instruction as a
  `nop` (CONVENTIONS §9).
* **RESLOC and the loop terminators examine the top of the stack, so a
  caller must not save registers on the stack around them.** Use statics
  instead, as EXIT and RESDEL do.

Byte offsets from sp; the total frame size is in brackets:

| Frame | Layout |
|---|---|
| FOR | 0 FORCHK, 4 variable, 8 text, 12 step mantissa .l, 16 step exponent, 17 compare op, 18 limit mantissa .l, 22 limit exponent, 23 type (24) |
| REPEAT | 0 REPCHK, 4 text after REPEAT (8) |
| WHILE | 0 WHICHK, 4 text at the condition (8) |
| GOSUB | 0 GOSCHK, 4 text after GOSUB (8) |
| PROC/FN | 0 PROCHK/FNCHK, 4 slot: the return text pointer; on entry its low byte is TON for ON PROC (8) |
| LOCAL | 0 LOCCHK, 4 VARPTR, 8 type, 9 exponent or string length, 10 payload: number .l, array pointer .l, string (padded to even), type 2: a long, type 3: two longs. Type bit 4 set: do not restore. |
| RETURN | 0 RETCHK, 4 count .w, 6 one 12-byte entry per RETURN parameter: formal VARPTR .l, formal type .w, actual VARPTR .l, actual type .w |
| ARRCHK (DIM LOCAL) | 0 ARRCHK, 4 flags .w (bit 7 = string array), 6 descriptor size .l, 10 data size .l, 14 total reserved .l (rounded to even), 18 the block |
| ON ERROR LOCAL | a type-3 LOCAL frame holding ONERSP and ERRTRP |
| ARGUE items | formal VARPTR .l, value, then the word type << 8 \| exponent (strings: the PUSHS frame), above a 0xFF00 marker word |

## 5. Buffers

* ACCS (the string accumulator, 256 bytes) and BUFFER (256) are **not
  page-aligned** on the 68k. Z80 code that uses `INC L`/`INC E` wrap-around
  or `E` as a length (because the buffer starts on a page boundary) must use
  an explicit length or end pointer.
* **String result convention:** the string is in ACCS, and **a2 = end
  pointer** (Z80 DE). The length is `a2 - ACCS` (at most 255), computed
  where needed.

## 6. Register contracts of internal routines

As routines are translated, their 68k contract is written in the routine
header in the source. Common mappings:
* IY → a4 (text pointer);
* IX → a5;
* A → d4.b;
* HL used as a pointer → a3, DE → a2, BC → a1;
* numbers HLH'L' / C → d0.l / d1.b, DED'E' / B → d2.l / d3.b;
* line numbers (16-bit) → d0.w with the high word zero, unless noted.

## 7. Cross-module contracts (fixed while writing main.s, 2026-10-20)

Provided by EVAL / EXEC, used by MAIN:

| Routine | Inputs | Outputs | Notes |
|---|---|---|---|
| EXPRI, ITEMI | a4 | d0.l = integer, d1.b = 0, a4 updated | |
| EXPR | a4 | d6.b = type (bit 7 = string), d4.b = next character; number in d0/d1, or string in ACCS with a2 = end | |
| EXPRS | a4 | string in ACCS, a2 = end | |
| EXPRN | a4 | number in d0/d1 | |
| ITEM | a4 | d4.b = type (0x80 = string); value as EXPR | |
| DECODE | a4 at the 3 bytes after TLINO | d0.l = line number, d1.b = 0, a4 += 3 | destroys only d4, d7 |
| LOADN | a5 = variable, d4.b = type | d0/d1 | |
| SFIX | d0/d1 | d0 = integer, d1 = 0 | |
| COMMA, BRAKET | a4 | skip `,` / `)` | error if missing |
| SEARCH | a3 = main string, d5.b = its length, a2 = substring, d3.b = its length, d4.b = start offset | Z if found (a3 = location + 1) | |
| TERMQ | a4 | d4.b = character, Z if `:`, CR or ELSE | |
| MUL16 | d0.w × d5.w | d0.l (upper word 0), C on 16-bit overflow | preserves the rest |
| X14OR5 | d2.l × element size of type d4.b (1→1, 4→4, 5→5, string (bit 7)→6, else 4) | result in d2.l, C if > 0xFFFF | preserves the rest |
| SPACES | d4.b = count | | |
| CHECK | | error 0 "No room" if FREE + 256 >= sp | preserves everything |
| XEQ | a4 = statement text | (never returns) | |
| RUN0, CHAIN0, ESCAPE | | | entry points |
| STOREN | a5 = destination, d4.b = type, d0/d1 = value | | |
| STORE4, STORE5 | a5 = destination, d0/d1 | | |
| STACCS | a5 = destination, d4.b = type (128 / 129), string in ACCS, a2 = end | | |
| MODIFY | a5 = destination, d5.w = type << 8 \| operator, d0/d1 = value | | |
| MODIFS | a5 = destination, d5.w = type << 8 \| operator, string in ACCS, a2 = end | | |
| CHANEL, CHNL | a4 at `#` / after it | d6.b = channel | |
| VAR | a4 | as GETVAR found (creates if needed) | |

Provided by MAIN: see the routine headers in main.s.in (GETVAR, LOCATE,
CREATE, GETDEF, LEXAN2, FINDL, SETLIN, OUTCHR, OUT, TEXT, TELL, CRLF,
PBCDL, SAYLN, CLEAR, GETTOP, LOAD0, LINNUM, RANGE, NXT, NLIST, ERROR,
EXTERR).

### Operand stack (EVAL SAVE / DOIT)

SAVE pushes the first operand: d0.l, then op.w, then exp.w (6 + 2
bytes). DOIT pops it into d0/d1 (the first operand), with the second
operand moved to d2/d3, and calls FPP.

### String stack (PUSHS / POPS)

PUSHS pushes the string, padded to an even length, then the word
(A << 8) | length, so that the word is on top. The caller pops the word
(`move.w (sp)+,d5`), and POPS(d5.b = length) copies the string to ACCS and
drops it (len + 1 & ~1 bytes).
