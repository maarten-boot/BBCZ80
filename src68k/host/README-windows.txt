BBC BASIC for the 68000 - Windows program
=========================================
@VERSION@

R.T. Russell's BBC BASIC (Z80) v5, ported to 68000 assembly language,
running on an emulated rosco_m68k (68010) inside this one program.

Put bbc68k.exe in a folder with your BBC BASIC files and start it there
(double-click it, or run it from a Command Prompt or PowerShell in that
folder).  BBC BASIC starts at once with a menu of demo programs; Return
at the menu gives the > prompt.  Windows 10 or 11, 64-bit.

    bbc68k.exe myprog       CHAINs myprog instead (as does dropping a
                            .BBC or .BAS file on bbc68k.exe); with a folder
                            in the name, that folder is BASIC's

Scripts
-------
    bbc68k.exe < test.txt > out.txt
types test.txt in (its first line goes to the demo menu: start it with
an empty line) and ends when the input is used up and BASIC is waiting.

