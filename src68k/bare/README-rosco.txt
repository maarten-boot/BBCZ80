BBC BASIC for the 68000 - for a real rosco_m68k
==============================================
@VERSION@

R.T. Russell's BBC BASIC (Z80) v5, ported to 68000 assembly language,
running straight on a rosco_m68k (no operating system), with its console
on the serial port (DUART channel A) at the firmware's speed.

Two copies of the same program:

    ROSCODE1.BIN    copy it to the first (FAT) partition of the SD card:
                    the firmware loads and starts it at power-on
    BBCBASIC.BIN    the same, for a card that boots a menu instead
                    (sdfat_menu as ROSCODE1.BIN lists the .BIN files of
                    the card; choose BBCBASIC.BIN there)

Both are loaded at &40000, the firmware's load address.
Tested on a rosco_m68k Classic (68010, 10 MHz, 5 MB, its ROM's console
at 38400), and in MAME with firmware 2.42 and 2.50, both directly and
from sdfat_menu.  BASIC keeps the serial port as the firmware set it.

Memory
------
BASIC uses the memory the firmware reports: on the board alone (1 MB)
about 0.5 MB for programs and variables, with the 4 MB expansion (5 MB)
about 3.6 MB.  A quarter of the memory above BASIC is a RAM store for
files (one directory, up to 128 files; it survives *BYE, not a reset).

Files
-----
* The SD card: FAT16 or FAT32 (the first FAT partition, or a card with no
  partition table).  8.3 names, matched in any case; subdirectories with
  "/": SUB/PROG.BBC; *MKDIR, *CD, *RMDIR.  Writes go to the card at once.
* The RAM store, then: a file is looked for on the card first; "sd:" or
  "ram:" in front of a name chooses.
* *DIR lists the card's current directory, then the RAM store;
  *DIR B* or *DIR *.BAS list the matching files (no extension: .BBC).

Commands and keys
-----------------
BBC BASIC's * commands: *DIR, *CD, *MKDIR, *RMDIR, *ERA (also with a
pattern), *REN new=old, *TYPE, *SPOOL, *EXEC, *LOAD, *SAVE, *ESC, *OPT,
*HELP.  *BYE starts BBC BASIC again.  Escape stops a running program;
^S/^Q stop and start the output.

A bus error or an address error (in machine code, or ? ! $ where there
is no memory) is BASIC's error 8, "Address out of range" or "Odd
address", which ON ERROR can trap.

The inline assembler is a 68000 one: see ASSEMBLER.md in the repository,
https://github.com/maarten-boot/BBCZ80 (src68k).
