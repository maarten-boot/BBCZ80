# BBC BASIC on a bare rosco_m68k

BBC BASIC 68k without an operating system: the rosco_m68k's firmware loads
it from the SD card and it runs straight on the machine.

## Running it

**On a real rosco_m68k:** copy `build/bare/ROSCODE1.BIN` (`make bare`) to
the FAT partition of the SD card. The firmware loads and starts it, and
BBC BASIC comes up on the serial console at the firmware's speed.

**In r68k:** `R68K_RAM=5M r68k -d build/bare/ROSCODE1.BIN`. A
`rosco_sd.bin` in the current directory is the SD card.

**In MAME:** the rosco-emulator, with `ROSCODE1.BIN` on the card's FAT
partition.

`build/bare/demo/ROSCODE1.BIN` has the demo programs in its RAM store and
starts the menu.

## Memory

BASIC uses the memory the firmware reports. The usual machine is the
board's 1 MB with the 4 MB expansion, 5 MB in all. The RAM store takes
a quarter of the memory above BASIC's code, which leaves about 3.6 MB
for programs and variables. The PC programs and the tests use 5 MB too. On the board alone
(1 MB) BASIC has about 0.5 MB.

## Files

* **The SD card:** if the card has a FAT16 or FAT32 file system (the
  first FAT partition, or a card without a partition table), files are
  on it.
  * Names are 8.3, upper case on the card, matched in any case.
  * Long names are skipped, and removed with their file.
  * Paths: `SUB/PROG.BBC`, `/` for the root, `..`.
  * `*MKDIR`, `*CD`, `*RMDIR`.
  * Writes go to the card at once; a file's size in its directory entry
    when it is closed.
* **The RAM store:** a quarter of the memory above BASIC, one directory,
  up to 128 files. It keeps its files over `*BYE`, not over a reset. The
  demo programs come in it.
* **Which one:**
  * a file is looked for on the card first, then in the store;
  * a new file goes on the card if there is one (in the store if its
    name is not 8.3);
  * `sd:` or `ram:` in front of a name chooses.
* **`*DIR`** lists the card's current directory, then the store.
  `*DIR afsp` lists only the matching files, with `*` and `?` in the
  name and the extension, in any case. As in the manual, a pattern
  without an extension means `.BBC` (`*DIR B*` is `B*.BBC`) and a final
  `.` means no extension; `*DIR *.*` lists them all, as `*DIR` on its
  own does. `*ERA afsp` deletes every match the same way.

## Commands and keys

* **BBC BASIC's own `*` commands work:** `*DIR`, `*CD`, `*MKDIR`,
  `*RMDIR`, `*ERA`, `*REN new=old`, `*TYPE`, `*SPOOL`, `*EXEC`, `*LOAD`,
  `*SAVE`, `*ESC`, `*OPT`, `*HELP`.
* **Anything else** is "Bad command" (there is no shell).
* **`*BYE`** starts BBC BASIC again.
* **Escape** stops a running program; **^S/^Q** stop and start the
  output.

## How it is made

| Part | What it does |
|---|---|
| `start.s` | Start-up at 0x40000, where the firmware loads `ROSCODE1.BIN`: clears the .bss, calls `bare_init`, calls BASIC (`minix.s` `_main`). Also the interrupt entry and the calls into the firmware's SD routines (its EFP table) |
| `bare.c` | The POSIX calls `osl.c` makes (compiled `-DBARE`), done on the machine itself. The console is DUART channel A, with interrupt input into a buffer. The termios modes give Escape as a SIGINT from the interrupt, and ^S/^Q. TIME is the DUART timer at 60 Hz. Files are the RAM store, and the dispatch to the card |
| `fat.c` | FAT16/FAT32 through the firmware's SD routines. One sector buffer, written through, that lasts only within a call (the web page changes its card between calls) |
| `tools/mkbare.py` | Builds it: the interpreter's objects, these, `osl.c -DBARE`; linked by the ACK's `em_led` at 0x40000; `aslod` for the flat binary |

## Tests

* **`make barecheck`:** the BASIC test suite on it (files in the RAM
  store).
* **`tools/fatcheck.py`:** three cards (FAT16 from `mkfat.py`, a small
  FAT16 and a FAT32 from `mkfs.fat`). It checks programs, text and
  binary files over many clusters, a gap past the end, directories,
  `*REN`/`*ERA` and `*BYE`; then `fsck.fat` must find each card clean.
* **MAME with the real firmware:** boots from the card, then loads, runs,
  saves, writes 40 KB, and uses `*MKDIR`/`*CD`.
  The bus and address errors of `test/bas/x07fault` give the same
  output there (5 MB, and the 1 MB board: `?&100000`).
* **`tools/bareprof.py`:** where the cycles go (the interpreter, the C
  files, the library) in the benchmarks, console output and file I/O,
  under the profiling r68k (see `tools/bench.py`).

## ACK pitfalls met here

* **Dropped reads:** `(void) reg` is dropped even for a volatile `reg`, so
  read device registers into a volatile variable.
* **16-bit `int`:** a 16-bit value read as `int` from a byte pair is
  negative from 0x8000 on, so use `unsigned`.
