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
| `loader.js` | turns a program file into keystrokes |
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
  buffer with pasted programs.
* **Missed timer ticks are made up** (up to 10), so `TIME` keeps step
  with real time.
* **Speed.** The page's "10 MHz" setting limits the CPU to 10,000 cycles
  per millisecond. At full speed the page runs about 20× faster than
  that, in Chrome or Node.

### Loading programs

**Load program** (or dropping a file on the screen) types a program in at
the `>` prompt, as `NEW` and then its lines.
* **Tokenised `.bbc`** (BBC BASIC for Z80, CP/M, 68000, Windows or SDL)
  is listed back as text with the interpreter's own keyword table. Line
  numbers after GOTO etc. (`&8D` and 3 bytes) are decoded; strings and
  REM/DATA text are left alone.
* **A text listing** is typed as it is, or numbered 10, 20, … when it has
  no line numbers.
* **Not supported:** BBC Micro (Acorn) files.

## Tests

`make web` runs `tools/mkweb.py --test`:
* **`test.js` (Node):** boot, the asm demo from the menu, and five of the
  upstream test programs (`tests/*.BBC`). These are typed in through
  `loader.js`, run, and compared with their bascheck references
  (`test/bas/u_*.ref`).
* **`browsertest.py` (headless Chromium, through the DevTools protocol):**
  key events, Escape stopping `life`, Load program with `FORTEST.BBC`,
  and the speed setting. It runs when `chromium` and the Python
  `websockets` module are there.

## Hosting

Copy `bbc68k.html` anywhere; it needs no other files.
* **Licences:** the page carries the licences of BBC BASIC, r68k and the
  firmware, Musashi, Minix and xterm.js, under "Licences" at the bottom.
* **Browsers:** it needs a browser with WebAssembly exception handling:
  Chrome/Edge 95+, Firefox 100+, Safari 15.2+.
