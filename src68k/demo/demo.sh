#!/bin/sh
# Start the BBC BASIC 68000 demo: Minix 2.0.4 on an emulated rosco_m68k
# (r68k), straight into BBC BASIC.  Ctrl-] quits the emulator.
cd "$(dirname "$0")" || exit 1
if [ ! -t 0 ]; then
	echo "demo.sh: needs a terminal (with docker: docker run -it)" >&2
	exit 1
fi
saved=$(stty -g)
trap 'stty "$saved"; echo' EXIT
trap 'exit 0' INT TERM
stty intr '^]'
echo "Booting Minix on the emulated rosco_m68k (Ctrl-] quits) ..."
# (r68k makes its standard input non-blocking: a separate open of the
# terminal keeps that from the shell)
R68K_RAM=2M ./r68k -d ROSCODE1.BIN </dev/tty
