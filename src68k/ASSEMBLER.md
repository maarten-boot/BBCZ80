# The 68000 inline assembler

The 68k port replaces the Z80 assembler of BBC BASIC (`[ ... ]`) with a
68000 assembler in Motorola syntax (`asmb.s`). The control part works as
in the Z80 version: P%, O%, OPT, labels and two-pass assembly.

```
10 DIM code% 100
20 FOR pass% = 0 TO 2 STEP 2
30   P% = code%
40   [OPT pass%
50   .sum   moveq #0,d0      ; d0 = 1 + 2 + ... + d1
60   .loop  add.l d1,d0
70          subq.l #1,d1
80          bne loop
90          rts
100  ]
110 NEXT
120 B% = 100 : PRINT USR(sum)
```

## Statements

`[.label] [mnemonic[.size] [operand[,operand]]] [comment]`

* **Separators:** statements are separated by `:` and the block ends at `]`.
* **Comments:** a comment starts with `;` or `\` and runs to the next `:`
  or the end of the line.
* **Case:** mnemonics and register names may be upper or lower case.
* **Labels:** `.name` sets the BASIC variable `name` to P%.
* **Lower case is recommended.** In upper case, BASIC's tokeniser turns
  keywords (MOVE, AND, OR, EOR, NOT, DIV, SWAP, EXT...) and abbreviations
  (`ORI.` = `ORIGIN`, `M.` = `MID$(`) into tokens. The assembler expands
  these again, so `MOVEM.L`, `ORI.B` and `EXT.W` do work, but a lower case
  mnemonic is never tokenised.
* **Operands** are BASIC expressions:
  * `&hex` and Motorola `$hex` are both accepted, hex digits in either case;
  * `%binary`;
  * variables, FN calls and so on.

## Addressing modes

| Mode | Syntax |
|---|---|
| Data / address register | `d0`-`d7`, `a0`-`a7` (`sp` = `a7`) |
| Indirect, post-increment, pre-decrement | `(a0)`, `(a0)+`, `-(a0)` |
| Displacement | `d(a0)` or `(d,a0)` |
| Index | `d(a0,d1.w)` or `(d,a0,d1.l)`; `(a0,d1)` has d = 0 |
| Absolute | `addr` (long), `addr.w` or `(addr).w` (short) |
| PC relative | `label(pc)`, `label(pc,d0.w)`, `(label,pc)` |
| Immediate | `#expr` |
| Special | `sr`, `ccr`, `usp`, register lists `d0-d3/a0/a5-a6` |

* **PC-relative operands and branches:** the expression is the target
  address, not the displacement.
* **Sizes must not change between the passes,** because a forward label is
  only known on the second pass. So:
  * absolute addresses are always long unless `.w` is given;
  * `Bcc`/`BRA`/`BSR` are always `.w` unless `.s` (or `.b`) is given.

## Instructions

* **The whole 68000 instruction set:**
  * MOVE, MOVEA, MOVEQ, MOVEM, MOVEP; MOVE to/from SR and CCR, MOVE USP;
  * ADD(A/I/Q/X), SUB(A/I/Q/X), CMP(A/I/M), AND(I), OR(I), EOR(I) (also
    to CCR/SR);
  * MULU/S, DIVU/S, CHK, ABCD, SBCD, NBCD;
  * CLR, NEG(X), NOT, TST, TAS, EXT, SWAP, EXG;
  * the shifts and rotates (register, immediate, memory);
  * BTST/BCHG/BCLR/BSET;
  * LEA, PEA, JMP, JSR, LINK, UNLK;
  * Bcc/BRA/BSR, DBcc/DBRA, Scc (HS/LO accepted);
  * TRAP, TRAPV, RTS, RTE, RTR, NOP, RESET, STOP, ILLEGAL.
* **From the 68010:** RTD and `MOVE CCR,<ea>`.
* **Generic forms** are encoded as Motorola assemblers do:
  * `add #n,<ea>` gives ADDI, `add <ea>,an` gives ADDA, and the same for
    SUB, CMP, AND, OR, EOR;
  * `move <ea>,an` gives MOVEA.

  Quick forms (MOVEQ, ADDQ, SUBQ) are only used when written.
* **The default size is `.w`.**

## Directives

| Directive | Effect |
|---|---|
| `dc.b`/`dc.w`/`dc.l list` | Data; strings are allowed in `dc.b` |
| `ds.b`/`ds.w`/`ds.l n` | Reserves n items (zeroed) |
| `equb`, `equw`, `equd`, `equs` | One byte, word, long or string (as in BBC BASIC) |
| `align` / `even` | Pads P% to an even address |
| `opt n` | As in BASIC |

## OPT

These are the bits of the Z80 version:

* **Bit 0:** list. The listing shows the address, the code bytes and the
  source.
* **Bit 1:** report errors. While it is clear, an unknown variable has the
  value of P% (for the first pass) and range errors are not reported.
* **Bit 2:** store the code at O% while P% gives the addresses.

## Macros

As in the Z80 version, an FN can assemble code of its own: called as
`OPT FNname(...)`, it works as a macro. The code goes at P%, and the FN
returns the OPT value to go on with:

```
20 [OPT pass%
30 OPT FNsave("hello")
40 rts
50 ]
...
100 DEF FNsave(s$)
110 [OPT pass%
120 dc.b s$,0
130 ]
140 =pass%
```

The `]` in the FN sets OPT to 3, as any `]` does, so the FN's result is
what puts OPT back. An FN that assembles code is for `OPT` only. In another
operand (`dc.b`, `move.l #FN...`) the statement's own bytes go where the
FN's code went.

## Errors

| Error | Cause |
|---|---|
| Syntax error | An unknown mnemonic, or an operand that the instruction does not allow |
| Out of range (1) | A branch, displacement or immediate value that does not fit |
| Multiple label (3) | A label that is already set, on the first pass (OPT bit 1 clear) |

## Running code

* `CALL addr` and `USR(addr)` enter the code with d0-d7 = A%-H% and a0 =
  the CALL parameter block. USR returns d0.
* **The parameter block** of `CALL addr,var,var...` is in BASIC's string
  input buffer, as in the Z80 version (which passes it in IX). Its address
  is not fixed (it is not at a set distance below PAGE, nor page-aligned),
  so code must take it from a0:

  | Offset | Contents |
  |---|---|
  | 0 | the number of parameters |
  | 1 + 5n | parameter n's type: 0 byte (`?`), 4 integer (`X%`, `!`), 5 real, 128 a `$addr` string, 129 a string variable |
  | 2 + 5n | its address, 4 bytes little-endian (the Z80: 2 bytes) |

  The addresses are at odd offsets, so read them a byte at a time. The
  address of the first parameter:
  ```
  move.b 5(a0),d3 : lsl.l #8,d3 : move.b 4(a0),d3 : lsl.l #8,d3
  move.b 3(a0),d3 : lsl.l #8,d3 : move.b 2(a0),d3 : move.l d3,a1
  ```
  The variable itself is little-endian too, like all memory BASIC sees.
* Code must be at an even address. `DIM name size` blocks are word-aligned
  on this port, while the Z80 version does not align them.

## Tests

* `make asmcheck` compares about 160 instructions with the ACK assembler.
* `test/bas/a01asm.in` covers the two-pass behaviour, O%, the listing,
  errors, and running code.
