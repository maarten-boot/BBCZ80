#!/bin/sh
# mamebare.sh [IMAGE]: the benchmarks (test/bench/*.bas) on bare BBC BASIC
# in MAME, the rosco-emulator with the real firmware (a 10 MHz 68010, 5 MB),
# each timed with TIME in centiseconds of the emulated clock.  For timing
# claims: r68k's cycle counts (bareprof.py) only show where the time goes.
# IMAGE: a ROSCODE1.BIN (default build/bare/ROSCODE1.BIN, make bare); it
# goes on the FAT partition of a card made with the Minix tree's mkfat.py
# and mksd.py in build/mamebare.  Runs mamesession.py in the docker image
# rosco-emulator:local.  Prints one "name centiseconds" line per benchmark.
set -e
SRC=$(cd "$(dirname "$0")/.." && pwd)
TOP=$(dirname "$SRC")
MINIX=${MINIX:-$(dirname "$TOP")/minix-st-2.0.4}
T=$MINIX/src/rosco/tools
IMG=${1:-$TOP/build/bare/ROSCODE1.BIN}
W=$TOP/build/mamebare
rm -rf "$W"
mkdir -p "$W"
chmod 777 "$W"			# (the container's user writes the log)
cp "$IMG" "$W/ROSCODE1.BIN"
python3 "$T/mkfat.py" -s 65536 -o 2048 "$W/fat.img" "$W/ROSCODE1.BIN" >/dev/null
python3 "$T/mksd.py" "$W/rosco_sd.bin" "06:$W/fat.img" >/dev/null
# each ?&FFFFF0=1 / =2 pair (bench.py's markers) becomes TB%=TIME / a print
{ echo 'expect >	300'
  for b in "$SRC"/test/bench/*.bas; do
	sed -e 's/?&FFFFF0=1/TB%=TIME/' \
	    -e "s/?&FFFFF0=2/TB%=TIME-TB%:PRINT \"BENCH $(basename "$b" .bas) \";TB%/" "$b" |
	while IFS= read -r l; do printf 'send %s\nexpect >\t120\n' "$l"; done
	printf 'send RUN\nexpect >\t600\nsend NEW\nexpect >\t60\n'
  done; } > "$W/session.txt"
chmod 666 "$W"/*
docker run --rm -e SDL_VIDEODRIVER=dummy -v "$W:/work" -v "$T:/tools:ro" \
	--entrypoint python3 rosco-emulator:local /tools/mamesession.py -a '-ram 5m' \
	/opt/rosco /work/rosco_sd.bin /work/session.log /work/session.txt >/dev/null 2>&1
tr -d '\r' < "$W/session.log" | sed -n 's/^BENCH //p'
