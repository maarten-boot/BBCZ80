#!/bin/sh
# getack.sh: the ACK (Amsterdam Compiler Kit) for minix68k that builds BBC
# BASIC, and the Minix C library compiled with it.
#
#	tools/getack.sh		(make does it when build/ack is missing)
#
# Fetches the release ACK_TAG of github.com/maarten-boot/ack (a Linux
# x86-64 build, checked against ACK_SHA256) and unpacks it as
# build/ack/dist; then compiles the Minix C library (crtso.o, emrts.o,
# libc.a) with it into build/ack/minixlib, from the sources of the Minix
# tree (MINIX, default ../minix-st-2.0.4 next to this repository; only
# read: its src/rosco/ack/lib/Makefile, src/lib, src/rosco/lib, include).
# Nothing is done when build/ack/VERSION already names ACK_TAG.
# ACK_TARBALL=file uses a downloaded release file instead (same checksum).
# tools/acc and tools/acc-minix compile with the result.  A host program.

set -e

ACK_TAG=minix68k-20261031
ACK_SHA256=c38855b6031592592d219c756f5397902e82f965e18ef31df1d40ca468a5a62b

here=$(cd "$(dirname "$0")" && pwd)
top=$(cd "$here/../.." && pwd)
MINIX=$(cd "${MINIX:-$top/../minix-st-2.0.4}" && pwd)
b=$top/build/ack
name=ack-$ACK_TAG-linux-x86_64

if [ "$(cat "$b/VERSION" 2>/dev/null)" = "$ACK_TAG" ]; then
	touch "$b/VERSION"		# (newer than this script, for make)
	exit 0
fi
rm -rf "$b"
mkdir -p "$b"
tgz=${ACK_TARBALL:-$b/$name.tar.gz}
if [ -z "$ACK_TARBALL" ]; then
	curl -sfL --retry 3 -o "$tgz" \
	    "https://github.com/maarten-boot/ack/releases/download/$ACK_TAG/$name.tar.gz"
fi
echo "$ACK_SHA256  $tgz" | sha256sum -c --quiet
tar xzf "$tgz" -C "$b"
mv "$b/$name" "$b/dist"
rm -f "$b/$name.tar.gz"

# the Minix C library, as the Minix tree's src/rosco/ack/lib builds it, with
# its Makefile run here: its relative paths given as variables, its
# <minix/config.h> copied in (-o: not remade from a relative path)
l=$b/minixlib
mkdir -p "$l/inc/minix"
cp "$MINIX/src/rosco/ack/lib/emrts.s" "$l/"
cp "$MINIX/src/rosco/include/minix/config.h" "$l/inc/minix/"
defs="-D__ACK__ -D__minix=1 -D__m68000=1 -D_MINIX -D_POSIX_SOURCE"
make -s -C "$l" -f "$MINIX/src/rosco/ack/lib/Makefile" -o inc/minix/config.h \
    -j"$(nproc)" ACC="$here/acc" AAL="$b/dist/bin/aal" \
    l="$MINIX/src/lib" i="$MINIX/include" rl="$MINIX/src/rosco/lib" \
    CFLAGS="-O $defs -Iinc -I$MINIX/include -I$MINIX/src"
echo "$ACK_TAG" > "$b/VERSION"
echo "getack: $ACK_TAG in $b"
