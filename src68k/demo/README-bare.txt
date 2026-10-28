BBC BASIC for the 68000 - bare-metal demo
=========================================

R.T. Russell's BBC BASIC (Z80) v5, ported to 68000 assembly language,
running straight on an emulated rosco_m68k (68010) board with its
firmware - no operating system.

Start it with

    ./demo.sh

in a terminal (Linux x86-64; nothing else is needed, no internet), or
with Docker (Linux, Mac, Windows):

    docker load -i bbc68k-bare-image.tar.gz
    docker run -it --rm -v bbc68k-card:/card bbc68k-bare

(-it is needed: it is a terminal program.  -v keeps the SD card, and so
your files, in the Docker volume bbc68k-card; without it they go with
the container.)  BBC BASIC starts at once at its > prompt; CHAIN "menu"
starts the menu of demo programs (they are in the RAM store).

Keys
----
    Escape          BBC BASIC's Escape: stops a running program
    Ctrl-S/Ctrl-Q   stop and start the output
    Ctrl-]          quits the emulator

Files
-----
The SD card (card/rosco_sd.bin next to demo.sh, or the Docker volume) has
a FAT16 file system: SAVE, LOAD, CHAIN, OPENOUT/OPENIN, *SPOOL and *EXEC
use it, with 8.3 names and directories (*MKDIR, *CD, *RMDIR).  Files not
on the card are also looked for in a RAM store, where the demo programs
are.  The card file can be mounted on Linux (offset 2048 sectors) to
copy files on and off:

    sudo mount -o loop,offset=1048576 card/rosco_sd.bin /mnt

In BBC BASIC
------------
    CHAIN "menu"     the menu of demo programs
    *DIR             the files: on the card, then in the RAM store
    *ERA name   *REN new=old   *TYPE name
    *BYE             starts BBC BASIC again (the files stay)
Other * commands are "Bad command": there is no operating system.

The emulator runs as fast as your PC allows, much faster than a real
10 MHz rosco_m68k.  The same BBC BASIC (ROSCODE1.BIN) boots on a real
rosco_m68k from the FAT partition of its SD card.

Contents and licences
---------------------
    demo.sh                the start script
    r68k                   the rosco_m68k emulator (Ross Bamford and
                           contributors, LICENSE-r68k.md), with the
                           Musashi 68000 core (LICENSE-musashi.txt)
    firmware/rosco_m68k.rom  the firmware (LICENSE-r68k.md)
    ROSCODE1.BIN           BBC BASIC (LICENCE-bbcbasic.txt) with the
                           demo programs
    card.img.gz            an empty 256 MB FAT16 SD card, the first card
