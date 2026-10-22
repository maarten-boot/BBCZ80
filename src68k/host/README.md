# BBC BASIC as a program on the PC

`make host` (`tools/mkhost.py`) builds bare BBC BASIC with its demo
programs, inside an emulated rosco_m68k, as one program:

| Program | Platform | Size |
|---|---|---|
| `build/host/windows/bbc68k.exe` | Windows 10/11, 64-bit | 1.8 MB, needs only Windows' own DLLs |
| `build/host/linux/bbc68k` | Linux x86-64, static | 2.7 MB |

Start it in a console (`bbc68k.exe`, or by double-clicking). BBC BASIC
starts at once with the demo menu.

## Files

BBC BASIC's files are the files of the folder the program was started
in. There is no SD card and no image.
* Load, save, `CHAIN`, `OPENIN`/`OPENOUT`, `*SPOOL`, `*EXEC`, `*DIR`,
  `*CD`, `*MKDIR`, `*RMDIR`, `*ERA` and `*REN new=old` work on them,
  with long names and subdirectories.
* A name is matched without regard to case when it is not there as
  typed. `SAVE "prog"` writes `prog.BBC`, and `CHAIN "prog"` finds it.
* Paths cannot leave the starting folder.
* The demo programs are in a RAM store inside the program. A name not in
  the folder is looked for there; `*DIR` lists the folder, then the
  store.

## Console

* **Keys:** Escape stops a program, ^S/^Q stop and start the output, and
  the cursor keys edit the line. Ctrl-] quits, and so does `*BYE`.
* **Output:** vt100 (CLS and `TAB(x,y)`); the Windows console is put in
  that mode.
* **Scripts:** with input from a pipe or a file the program reads it as
  typed keys. It ends when the input is used up and BASIC is waiting with
  no output for 0.3 s, or at `*BYE`:
  ```
  bbc68k.exe < test.txt > out.txt
  ```
  The first key goes to the demo menu (Return gives the prompt).

## How it is made

* **r68k:** its tracked sources, with `web/r68k-web.patch` (Duart.cpp's
  console path, `R68K_HOSTED`), plus:
  * `hostmain.cpp`: `main()`. It writes the firmware out to a temporary
    file for `AddressDecoder`, puts BASIC at 0x40000, and has an input
    thread (console keys or pipe bytes) and a loop that sleeps while the
    machine is idle (STOP).
  * `hostfs.cpp`: the host files. Bare BASIC asks with an `ILLEGAL`
    instruction (d6 = "BBCH", d7 = the operation, d1–d3, result in d0;
    `bare/start.s` `bare_host`). `main.cpp`'s `illegal_instruction_handler`
    is renamed and gets the other traps.
  * `compat/`: the POSIX headers `main.cpp` and `Memory.h` include, for
    the MinGW build (r68k's own terminal code is not used).
* **Bare BASIC finds the host** at start-up with a probe call, made with
  the illegal instruction vector pointing at a return. On a real
  rosco_m68k, in r68k or in the web page there is no host, and the SD
  card or the RAM store is used as before.
* **Windows:** if a delete fails because one of BASIC's channels has the
  file open, the file is removed when the channel is closed, as on Linux
  (FILETEST relies on it).

## Tests

* **`BBC_EMU=host` / `BBC_EMU=hostwin tools/bascheck.py`:** the BASIC
  tests with the Linux program, or `bbc68k.exe` under Wine; each test in
  a new folder with its files, through a pipe.
* **`tools/hostcheck.py`:** files on the host, both programs, checked from
  the host byte by byte.
* **`tools/ttycheck.py --exe build/host/linux/bbc68k`:** the keyboard in a
  pty.
* **Console keys, `host/keytest.cpp` (in `hostcheck.py`):** it puts key
  events into `bbc68k.exe`'s console as a Windows keyboard does (Left and
  Home with no character) and checks the line editor's result.
* **Cursor keys on Windows:** the program maps the key codes to vt100
  sequences itself. The console's own VT input mode is not used: on
  Windows it made the arrows do nothing (reported by the user). BASIC's
  editor also takes the `ESC O x` form of the cursor keys.
* **Lines longer than the console (`tools/editcheck.py`):** the console
  wraps them, but a BS (the editor's cursor left) at the left edge stays
  there, so on Windows EDIT of a long line went wrong (reported by the
  user: Up did nothing, Right then wrote over the text). The program
  follows the cursor's column and turns such a BS into "up a row, last
  column" (`wrap_bs` in `hostmain.cpp`). editcheck edits a two-row line
  with the cursor keys in a 40-column pty and checks the screen.
* **Under Wine in a pty,** a lone ESC (Escape, and the ESC of a cursor
  key's sequence) is lost by Wine's console layer, so the console keys
  are tested with `keytest` instead.
