Files
-----
BBC BASIC's files are the files of the folder it was started in:
    LOAD "FORTEST"   CHAIN "prog"   SAVE "myprog"   (as myprog.BBC)
    SAVE "myprog.bas"  LOAD "listing.txt"  (.BAS, .TXT, .ASC: plain text)
    F%=OPENIN "data.txt"   F%=OPENOUT "results.txt"
    *DIR   *CD sub   *MKDIR sub   *RMDIR sub   *ERA name   *REN new=old
    *SPOOL out.txt ... *SPOOL      *EXEC listing.bas
    *DIR B*  (B*.BBC)   *DIR *.BAS   *DIR *.*   *DIR NAME.  (no extension)
Long names and subfolders work; a name is matched without regard to
case.  The demo programs (menu, mandel, sieve, hanoi, life, asm, queens)
are built in: CHAIN "menu".

Keys
----
    Esc             BBC BASIC's Escape: stops a running program
    cursor keys     edit the line being typed
    Ctrl-S/Ctrl-Q   stop and start the output
    Ctrl-]          quits (so does *BYE)

Known differences from the Z80 version
--------------------------------------
* String descriptors are 6 bytes, not 4 (pointers are 32 bits): the test
  program ARRAYTST.BBC stops at line 160 unless its lines 160, 1360,
  3170 and 3800 use the real size (DIM T$(1):DESC%=^T$(1)-^T$(0)).
* The inline assembler is for the 68000 (Motorola syntax), not the Z80.
  Macros (OPT FNname(...), an FN that assembles code) work as in the
  Z80 version.
* With OPT 2 (report errors), dc.b/dc.w and the other data directives
  check the range: dc.b 999 is "Out of range", where the Z80's DEFB 999
  keeps the low byte. With OPT 0 both keep it.
* Arrays can be larger than 64K elements (DIM A%(70000), B%(300,300));
  the Z80 version wraps them at 64K. Each dimension takes 4 bytes in the
  array's header (the Z80: 2), which matters only to programs that read
  that header through ^A%().
* INKEY(-n) (a held key) is always FALSE: the console cannot see it.
  INKEY(-256) is &44 (68), the number of this version.
* AUTO with a step over 255 gives "Silly" (the Z80 version keeps the low
  byte of the step).
* No graphics or sound; BBC Micro (Acorn) .bbc files are not understood.

Changes since 2026-10-27 (GitHub Actions run 5)
-----------------------------------------------
* *DIR takes a pattern, as in the manual: *DIR B*, *DIR *.BAS, *DIR *.*
  (without an extension it means .BBC files; *DIR alone lists all).
* *ERA takes a pattern too: *ERA *.TMP deletes every match (as the Z80
  version does).
* *OPT on its own is *OPT 0 (gave "Bad command").
* *HELP and the start-up line say "BBC BASIC (68k)" (was "(Z80)").
* BPUT# with a value that is not a whole number (BPUT#c,48.9) gave
  "Invalid channel"; it writes 48, as in the Z80 version.

Changes since 2026-10-23b
-------------------------
* LOAD, CHAIN and SAVE of a .BAS, .TXT or .ASC file read and write the
  program as plain text (lines without a number get the previous + 1).
* bbc68k NAME starts with that program (on Windows also by drag and
  drop).
* INKEY(-256) is &44 (68), as suggested by R.T. Russell.
* AUTO with a step over 255 gives "Silly".
* The variables @% to Z% are at addresses that are a multiple of 4, so
  68000 code can move.l to and from ^T% (GitHub issue #4).
* Also as a Linux program (bbc68k-linux).
* *ESC on its own (the same as *ESC ON) gave "Bad command".
* The machine has 5 MB, as a rosco_m68k with its 4 MB expansion: about
  3.6 MB for programs and variables (was 2.8 MB).
* PRINT#, INPUT#, BPUT# and BGET# are faster: a loop that writes and
  reads a file takes about 18% less time.
* A bus error or an address error (in machine code, or ? ! $ where there
  is no memory) is BASIC's error 8, "Address out of range" or "Odd
  address", instead of ending the program.

Changes since 2026-10-23
------------------------
Found with the tests and issues of the Agon (eZ80) BBC BASIC:
* A whole-array assignment (a%()=...) inside a FOR, REPEAT or WHILE loop,
  a PROC or a FN broke the loop or PROC ("Not in a FOR loop").
* SUMLEN returned a wrong (very large) value.
* LOAD or CHAIN of a program too large for memory hung; it now says
  "No room".
* INKEY(-n) returned TRUE ("pressed") for every key.
* Arrays larger than 64K elements (see above); array access is also
  faster.

Changes since 2026-10-22c
-------------------------
* Assembler macros: [OPT FN1("test") with an FN that assembles code of
  its own gave "Not in a FN" (GitHub issue #1). The macro's code now
  stays at P%, and P% ends after it.
* An error in an assembler statement after a macro reports its line.
* A very long $hex operand can no longer overrun the assembler's buffer.

The emulator runs as fast as the PC allows (some 20 times a real 10 MHz
rosco_m68k).

Licences: BBC BASIC (c) R.T. Russell (zlib licence); r68k and the
rosco_m68k firmware (c) Ross Bamford and contributors (MIT); Musashi
68000 core (c) Karl Stenerud (MIT).
