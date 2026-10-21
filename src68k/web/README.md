# BBC BASIC 68000 in the browser

`make web` (in `src68k`) builds `build/web/bbc68k.html`: one self-contained
page, about 1.9 MB.
* **What runs:** the stand-alone demo (`make demo`). That is Minix 2.0.4 on
  an emulated rosco_m68k, which boots straight into BBC BASIC and its demo
  menu.
* **Nothing else needed:** no server and no internet. The page can be
  opened as a file, or put on any web server as it is.

## How it is made

| Part | What it is |
|---|---|
| r68k | the rosco_m68k emulator, compiled to WebAssembly by Emscripten (`emcc`), from r68k's tracked sources (`../r68k`) |
| `r68k-web.patch` | `machine/Duart.cpp` for the page; native builds are unchanged (`#ifdef __EMSCRIPTEN__`). Channel A's output is collected for `Module.r68kOutput`, keys come in through `r68k_key()` |
| `webmain.cpp` | `main()` for the page. It sets up the machine as `main.cpp` does (`main.cpp` is still compiled, with its `main` renamed, for its trap handlers), then runs the CPU in frames (`emscripten_set_main_loop`) instead of an endless loop |
| `pre.js` | the SD card: `rosco_sd.bin` in memory, which r68k's firmware traps read and write, and `r68kSdWrite()`/`r68kSdRead()` for the page |
| `loader.js` | uploads and downloads through the SD card; also turns a program file into keystrokes |
| `app.js`, `page.html` | the terminal (xterm.js 5.5.0, inlined), the toolbar and the help |
| `tools/mkweb.py` | builds it all. The ROM and the demo's `ROSCODE1.BIN` are embedded, and everything is inlined (`-sSINGLE_FILE`). It takes BASIC's keyword table from `main.s` and downloads xterm.js once to `build/web/vendor` (checked by SHA-256) |

### Design points

* **Wasm setjmp and exceptions.** Musashi calls `setjmp` in
  `m68k_execute` (bus errors). Emscripten's default emulation sends every
  opcode dispatch through JavaScript, which made it 6× slower, so the
  build uses wasm setjmp and exceptions:
  `-fwasm-exceptions -sSUPPORT_LONGJMP=wasm`. These can't be combined
  with Asyncify, which is why there is a frame loop instead of a sleep in
  `poll()`.
* **Frames.**
  * A frame runs 10,000-cycle steps for up to 12 ms; the next one
    follows at once (`EM_TIMING_SETIMMEDIATE`).
  * When Minix is idle (its idle task is `bra.s *`, 60FE, and the DUART
    has nothing pending), the frame ends and the next one comes with the
    timer interrupt. About 3% CPU when idle.
* **Keys are paced in real time,** one per millisecond. Minix moves input
  out of the line's 256-byte buffer on clock ticks, and the clock runs in
  real time however fast the CPU runs. Pacing by CPU cycles overran the
  buffer with pasted text. (Programs are not typed in; they are uploaded,
  see below.)
* **Missed timer ticks are made up** (up to 10), so `TIME` keeps step
  with real time.
* **Speed.** The page's "10 MHz" setting limits the CPU to 10,000 cycles
  per millisecond. At full speed the page runs about 20× faster than
  that, in Chrome or Node.

### Loading programs

**Load program** (or dropping files on the screen) uploads files through
the emulated SD card (`loader.js` `upload`):
1. The page writes each file into the card image (`/dev/c0d0`, no file
   system), at a fresh place each time, so Minix's block cache never
   holds old data for it.
2. It types `*dd if=/dev/c0d0 bs=SIZE skip=K count=1 >NAME` lines. Each
   part of the file (up to 16 KB) lies at a multiple of its size, so one
   `dd` reads it exactly. `dd` is in the demo's root for this.
3. For one file, it then types `LOAD "NAME"`. A text listing is NEWed
   and read in with `*EXEC NAME`, so BASIC tokenises it at full speed; a
   listing without line numbers is numbered 10, 20, … first.

Several files are only copied, for CHAIN or LOAD. A file takes 0.1–0.4 s
whatever its size; typing a program in took 3–12 s.

The lines are typed one at a time, each after the `>` prompt is back.
Keys typed while a `*` command runs reach the terminal in cooked mode,
where Return becomes LF, which BASIC's editor takes as cursor left.

* **Tokenised `.bbc`:** BBC BASIC for Z80, CP/M, 68000, Windows or SDL.
* **What gets converted:** only a single program. Several files, or one
  that is not a program (not tokenised, `.bas`, `.txt` or without an
  extension), are copied byte for byte (data files for OPENIN).
* **Not supported:** BBC Micro (Acorn) files.
* **`detokenise` / `keys`:** `loader.js` can also list a `.bbc` back as
  text (with the interpreter's keyword table; line numbers after GOTO
  etc. decoded) and make keystrokes of it.

### Downloading files

**Download** (a file name and the button, or Return) copies a file from
BASIC's directory to the computer:
1. `*wc -c NAME` finds it and its size. A name without an extension is
   also tried as `NAME.bbc` and `NAME.BBC`: SAVE adds `.bbc` if that
   file exists, else `.BBC`.
2. `*dd if=NAME of=/dev/c0d0 bs=16384 seek=K; sync` copies it to a fresh
   place on the card. `sync` takes it out of Minix's cache; the frame
   loop flushes r68k's stream of the card (`ifs`) to the image.
3. The page reads the bytes (`r68kSdRead`) and saves them with a download
   link.

For a program's output, use `*SPOOL out.txt` … `*SPOOL` and download
`out.txt`.

## Tests

`make web` runs `tools/mkweb.py --test`:
* **`test.js` (Node):**
  * boot and the asm demo from the menu;
  * five of the upstream test programs (`tests/*.BBC`), uploaded, run
    and compared with their bascheck references (`test/bas/u_*.ref`);
  * a listing read in by `*EXEC`;
  * two files uploaded together and CHAINed;
  * downloads: a SAVEd program (the loaded file up to its end), a
    40,000-byte binary file uploaded and downloaded unchanged, `*SPOOL`
    output, and a missing file.
* **`browsertest.py` (headless Chromium, through the DevTools protocol):**
  * key events and Escape stopping `life`;
  * Load program with one file and with two;
  * Download of a SAVEd program: the file Chromium saves;
  * the speed setting: at 10 MHz, 20000 empty FOR loops take 3.9 s, as on
    the MAME rosco_m68k (3.7 s).

  It runs when `chromium` and the Python `websockets` module are there.

## Hosting

Copy `bbc68k.html` anywhere; it needs no other files.
* **Licences:** the page carries the licences of BBC BASIC, r68k and the
  firmware, Musashi, Minix and xterm.js, under "Licences" at the bottom.
* **Browsers:** it needs a browser with WebAssembly exception handling:
  Chrome/Edge 95+, Firefox 100+, Safari 15.2+.
