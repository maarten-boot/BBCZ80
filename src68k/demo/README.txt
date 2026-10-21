BBC BASIC for the 68000 - demo
==============================

R.T. Russell's BBC BASIC (Z80) v5, ported to 68000 assembly language,
running under Minix 2.0.4 on an emulated rosco_m68k (68010) board.

Start it with

    ./demo.sh

in a terminal (Linux x86-64; nothing else is needed, no internet).  Minix
boots in a few seconds and BBC BASIC starts with a menu of demo programs.

With Docker (Linux, Mac, Windows), from the image file:

    docker load -i bbc68k-demo-image.tar.gz
    docker run -it --rm bbc68k-demo

(-it is needed: the demo is a terminal program.)

Keys
----
    Escape      BBC BASIC's Escape: stops a running program
    Ctrl-]      quits the emulator (back to your own shell)

In BBC BASIC
------------
    CHAIN "menu"        the menu of demo programs
    LIST                the program in memory
    RUN                 run it again
    *DIR                the files (the demo programs are *.bbc)
    *BYE                leave BBC BASIC (to the Minix shell; "exit" in
                        the shell brings the demo back)

The demo programs:
    mandel   the Mandelbrot set in ASCII (floating point)
    sieve    the sieve of Eratosthenes (byte arrays, timing)
    hanoi    the Towers of Hanoi (recursive procedures)
    life     Conway's Life (full screen, TAB(x,y))
    asm      the 68000 inline assembler (Motorola syntax): assembles
             two routines, lists them and calls them with USR and CALL
    queens   the eight queens (recursive function, arrays)

Notes
-----
* The file system is a RAM disk: everything starts afresh at each boot,
  and saved programs are lost when the emulator stops.
* The emulator runs as fast as your PC allows, much faster than a real
  10 MHz rosco_m68k, so the times the programs print are not the times of
  the real board.

Contents and licences
---------------------
    demo.sh                the start script
    r68k                   the rosco_m68k emulator (Ross Bamford and
                           contributors, LICENSE-r68k.md), with the
                           Musashi 68000 core (Karl Stenerud,
                           LICENSE-musashi.txt); statically linked
    firmware/rosco_m68k.rom  the rosco_m68k firmware (LICENSE-r68k.md)
    ROSCODE1.BIN           the Minix 2.0.4 kernel and its RAM disk root
                           file system (LICENSE-minix.txt), with BBC BASIC
                           (LICENCE-bbcbasic.txt) as /usr/bin/bbcbasic and
                           the demo programs in /usr/demo
