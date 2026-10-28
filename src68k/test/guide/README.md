# Programming guide tests

Tests from part 2 of the RISC OS BBC BASIC Reference Manual, the
programming chapters, and its appendix A (numeric implementation) and B
(minimum abbreviations): `NNx-topic.in`, NN being the chapter. Each runs
the chapter's example programs, made runnable, then small checks of the
rules the chapter states. Left out: screen modes, graphics, sprites,
teletext, sound, VDU control and the editor (chapters 15-22, 25, 26).

| Chapter | Tests |
|---|---|
| 3 Command mode | `03a` |
| 4 Simple programming | `04a`-`04c`: entering, LIST/RENUMBER/DELETE, SAVE/LOAD |
| 5 Variables, 6 Numeric variables | `05a`, `06a`, `06b`: names, assignment, operator priority |
| 7 Bases | `07a`-`07c`: hex and binary, shifts, logical operators |
| 8 Strings | `08a`, `08b` |
| 9 Arrays | `09a`-`09c`: DIM, whole-array operations, matrix multiply |
| 10 Output, 11 Input | `10a`, `11a`-`11c` (no keyboard: READ/DATA and files) |
| 12 Control statements | `12a`-`12i`: IF, FOR, REPEAT, WHILE, CASE, GOTO/GOSUB, ON |
| 13 Procedures and functions | `13a`-`13h` |
| 14 Data and command files | `14a`-`14c`: files, PRINT# format, *EXEC |
| 23 Memory | `23a`, `23b`: `?`, `!`, `|`, `$` |
| 24 Errors and debugging | `24a`-`24d`: ON ERROR, ERROR, ON ERROR LOCAL, TRACE |
| A (28) Numbers | `28a`, `28b`: ranges, precision, storage |
| B (29) Abbreviations | `29a` |

The format, the expected output (BBC BASIC (Z80) 5.4 under RunCPM) and
what another BBC BASIC will see differ are as for the keyword tests: see
`../kw/README.md`. Where the Z80 version differs from the manual, a
`REM (...)` line in the test says so; for example `L.` is `LINE` in a
program line (BASIC V: `LIST`), error 22 is "Log range", and `LOCAL
ERROR` is accepted but does nothing.
