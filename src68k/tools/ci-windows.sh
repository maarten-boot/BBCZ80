#!/bin/sh
# ci-windows.sh - BBC BASIC as a Windows program (bbc68k.exe: bare BBC BASIC
# in an emulated rosco_m68k), built from fresh checkouts and tested.  The
# GitHub Action (.github/workflows/windows-exe.yml) runs it; it runs the
# same way by hand in a clean Ubuntu.
#
#	src68k/tools/ci-windows.sh ["VERSION LINE"]
#
# One folder W holds the checkouts, as on the development host:
#	W/BBCZ80		this repository
#	W/minix-st-2.0.4	maarten-boot/minix-st-2.0.4: the ACK build
#				(src/rosco/ack) and the C library it compiles
#	W/r68k			maarten-boot/r68k: the emulator and its firmware
#	W/RunCPM		cloned here if missing: the Z80 BBC BASIC under
#				RunCPM tokenises the demo programs
# Needs gcc, g++, make, flex, bison, ninja, lua5.4 with lua-posix, python3,
# git, zip, x86_64-w64-mingw32-g++-posix, and docker for the ROM (the
# roscopeco/rosco_m68k image has m68k-elf-gcc and vasm).
# Result: W/BBCZ80/build/dist/bbc68k-windows/ (bbc68k.exe, README.txt) and
# its .zip.

set -e
SRC=$(cd "$(dirname "$0")/.." && pwd)
TOP=$(dirname "$SRC")
W=$(dirname "$TOP")
VERSION=${1:-"Version $(date -u '+%Y-%m-%d %H:%M') (commit $(git -C "$TOP" rev-parse --short HEAD))"}
RUNCPM_REV=12fc57a1784b8fc97dae30eb5dffedccf098bbd5	# 2026-10-23

echo "== ACK for minix68k and the Minix C library"
ack=$W/minix-st-2.0.4/src/rosco/ack
[ -x "$ack/ack/.obj/staging/bin/ack" ] || (cd "$ack" && ./build-ack.sh)
make -C "$ack" lib

echo "== the rosco_m68k ROM"
if [ ! -f "$W/r68k/firmware/rosco_m68k.rom" ]; then
	# as minix-st-2.0.4/src/rosco/xrun, with W mounted
	docker run --rm -u "$(id -u):$(id -g)" --group-add 1001 \
		-v "$W:$W" -w "$W/r68k/firmware" --entrypoint /usr/bin/env \
		roscopeco/rosco_m68k PATH=/home/linuxbrew/.linuxbrew/bin:/usr/bin:/bin \
		make rosco_m68k.rom
fi

echo "== RunCPM"
if [ ! -x "$W/RunCPM/RunCPM/RunCPM" ]; then
	[ -d "$W/RunCPM/.git" ] ||
		git clone -q https://github.com/MockbaTheBorg/RunCPM.git "$W/RunCPM"
	git -C "$W/RunCPM" checkout -q $RUNCPM_REV
	make -C "$W/RunCPM/RunCPM" -f Makefile.posix CCP=INTERNAL
fi
export RUNCPM="$W/RunCPM/RunCPM/RunCPM"

echo "== bare BBC BASIC with the demo programs"
cd "$SRC"
python3 tools/mkdemo.py --progs
python3 tools/mkbare.py --demo

echo "== the PC programs"
python3 tools/mkhost.py -r "$W/r68k"

echo "== tests: the Linux program against the Z80 references"
BBC_EMU=host python3 tools/bascheck.py -t 300
BBC_EMU=host python3 tools/asmcheck.py

echo "== the zip"
dist=$TOP/build/dist
rm -rf "$dist"
mkdir -p "$dist/bbc68k-windows"
cp "$TOP/build/host/windows/bbc68k.exe" "$dist/bbc68k-windows/"
sed "s|@VERSION@|$VERSION|" "$SRC/host/README-windows.txt" > "$dist/bbc68k-windows/README.txt"
(cd "$dist" && zip -q -9 -r bbc68k-windows.zip bbc68k-windows)
ls -l "$dist/bbc68k-windows" "$dist/bbc68k-windows.zip"
sha256sum "$dist/bbc68k-windows/bbc68k.exe" "$dist/bbc68k-windows.zip"
