BBC BASIC for the 68000 - Linux program
=======================================
@VERSION@

R.T. Russell's BBC BASIC (Z80) v5, ported to 68000 assembly language,
running on an emulated rosco_m68k (68010) inside this one program.

bbc68k is a static executable: it runs on any 64-bit x86 Linux, with
no libraries to install.  Unpack it, put it in a folder with your BBC
BASIC files (or on your PATH) and start it from a terminal in that
folder:

    tar xzf bbc68k-linux.tar.gz
    cd bbc68k-linux
    ./bbc68k

BBC BASIC starts at once at its > prompt.  The demo programs are built
in: CHAIN "menu" starts their menu.

    ./bbc68k myprog         CHAINs myprog instead; with a directory in
                            the name, that directory is BASIC's

Scripts
-------
    ./bbc68k < test.txt > out.txt
types test.txt in and ends when the input is used up and BASIC is waiting.

