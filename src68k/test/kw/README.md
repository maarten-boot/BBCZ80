# Keyword tests

One test per keyword of the RISC OS BBC BASIC Reference Manual (BASIC V/VI),
chapter 27, Keywords: `NAME.in` for the manual's entry `NAME` (`$` written
`_STRING`, `#` written `_HASH`: `MID_STRING.in`, `BGET_HASH.in`). Each test
runs the entry's examples, made into small programs that print their
results, then the entry's syntax forms, edge cases and errors. 130 entries
apply; graphics, sound, the window manager, ARM code and RISC OS calls
(`SYS`) are left out (`tools/getriscos.py`, SKIPKW).

## Format

A test is the lines typed at the `>` prompt, one per line: immediate
statements, or a program (numbered lines, `RUN`, then `NEW`). Errors that
are part of the test are trapped (`ON ERROR PRINT ERR;" ";REPORT$`) so the
run goes on. Two extra lines may appear, which are not typed:

* `#file PATH`: the file goes beside the test before it runs;
* `#typed`: the test needs each line typed after the prompt (`INKEY`
  would read lines typed ahead as keys).

The expected output, with the prompt and echoed lines left out, is

* `NAME.ref`: the output of R.T. Russell's BBC BASIC (Z80) version 5.4
  (`bin/cpm/BBCBASIC.COM`) under RunCPM, or
* `NAME.exp`, written by hand where the Z80 version cannot give it:
  `CALL` and `USR` (68000 machine code), `POS` (always 0 under CP/M),
  `CLS` (nothing under CP/M), `QUIT` (ends BASIC: no prompt to wait for).

`tools/bascheck.py` runs them (with `test/bas`) and shows a diff for each
one that differs.

## Using them for another BBC BASIC

The expected output is the Z80 version's, so a BASIC V implementation
(RISC OS, BBC BASIC for SDL, Brandy) will differ where the Z80 version
does. The tests avoid what differs only by the machine: no keyboard input,
no `TIME` or `RND` values, no addresses (only relations such as
`HIMEM>TOP`), no `POS`/`VPOS` values, and file lengths printed in 128-byte
records (CP/M). Where the Z80 version's behaviour differs from the
manual, the test says so in a `REM (...)` line; among them:

* `LEFT$(A$)=` and `RIGHT$(A$)=` without a count change all but one
  character (BASIC V: up to the length of the new string);
* `OLD` keeps the line number 1000 (BASIC V: 1000 MOD 256);
* `RESTORE +1` reads the next line, as `+0` does;
* `RESTORE line` needs the line to exist ("No such line");
* `LISTO` has bits 0 and 1 only;
* `PRINT#` writes the Z80 version's byte format (a string is its
  characters and CR, a number 5 bytes);
* `DIV 0` and `MOD 0` give no error;
* `ADVAL`, `BY`, `ON`/`OFF` (the cursor), the `WIDTH` function and
  `TIME$` give "Sorry", error 0, which cannot be trapped;
* no `ERROR EXT`, `QUIT` as a function, `@%="G10.3"`, one-argument
  `LEFT$`/`RIGHT$`, `TRACE PROC`/`STEP`, `EXT#f=`.

For such a BASIC, generate its own `.ref` files from these tests and
compare them with ours: the differences are the list above, or bugs.

The examples are the manual's; the manual's text itself is not in this
repository (`tools/getriscos.py` fetches it to `build/riscos/`).
