#!/bin/sh
# Start the bare BBC BASIC demo: BBC BASIC straight on an emulated
# rosco_m68k (r68k), no operating system.  Ctrl-] quits the emulator.
# The SD card is $BBC_CARD/rosco_sd.bin (default: the card directory next
# to this script): made from card.img.gz (an empty FAT16 card) the first
# time, kept afterwards, so files saved on it stay.
here=$(cd "$(dirname "$0")" && pwd)
card=${BBC_CARD:-$here/card}
if [ ! -t 0 ]; then
	echo "demo.sh: needs a terminal (with docker: docker run -it)" >&2
	exit 1
fi
mkdir -p "$card" || exit 1
if [ ! -f "$card/rosco_sd.bin" ]; then
	gunzip -c "$here/card.img.gz" > "$card/rosco_sd.bin" || exit 1
	echo "A new SD card: $card/rosco_sd.bin"
fi
cd "$card" || exit 1
saved=$(stty -g)
trap 'stty "$saved"; echo' EXIT
trap 'exit 0' INT TERM
stty intr '^]'
echo "Starting BBC BASIC on the emulated rosco_m68k (Ctrl-] quits) ..."
# (r68k makes its standard input non-blocking: a separate open of the
# terminal keeps that from the shell)
R68K_RAM=2M "$here/r68k" -d "$here/ROSCODE1.BIN" </dev/tty
