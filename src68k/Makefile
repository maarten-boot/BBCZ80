# Makefile for BBC BASIC 68k (ACK, Minix on the rosco_m68k).
#
#	make		build bbcbasic and the tests
#	make check	run the tests under Minix in r68k (tools/runminix.py)
#	make install	put bbcbasic on the SD card root of the Minix tree:
#			$(MINIX)/src/rosco/rootfs/local/bbcbasic, listed in
#			rootfs/sdproto as /usr/bin/bbcbasic (then make sdcard
#			there).  The RAM root image has no room for it.
#	make clean
#
# MINIX is the minix-st-2.0.4 checkout, branch rosco-m68k, with the ACK
# built (src/rosco/ack: make host lib).  See CONVENTIONS.md.

MINIX	= ../../minix-st-2.0.4
ACK	= $(MINIX)/src/rosco/ack
AS	= $(ACK)/acc
LD	= $(ACK)/acc-minix

TESTS	= test/hello test/utiltest test/mathtest test/osmon
OSOBJ	= minix.o osl.o data.o hook.o

BASOBJ	= main.o exec.o exec2.o eval.o asmb.o math.o $(OSOBJ)

all:	$(TESTS) bbcbasic

# the interpreter (main.s is generated from main.s.in by tools/mkmain.py)
bbcbasic:	$(BASOBJ)
	$(LD) -S 64k -o $@ $(BASOBJ)

main.s:	main.s.in tools/mkmain.py ../src/MAIN.Z80
	python3 tools/mkmain.py

%.o:	%.s bbc.h
	$(AS) -c -o $@ $<

osl.o:	osl.c
	$(LD) -c -o $@ osl.c

test/osmon:	test/osmon.o $(OSOBJ)
	$(LD) -S 64k -o $@ test/osmon.o $(OSOBJ)

test/hello:	test/hello.o
	$(LD) -o $@ test/hello.o

test/utiltest:	test/utiltest.o util.o
	$(LD) -o $@ test/utiltest.o util.o

test/mathtest:	test/mathtest.c test/fppglue.o math.o
	$(LD) -S 16k -o $@ test/mathtest.c test/fppglue.o math.o

check:	$(TESTS)
	python3 tools/runminix.py -m $(MINIX) \
		-f /usr/bin/hello=test/hello -f /usr/bin/utiltest=test/utiltest \
		'hello' 'utiltest; echo utiltest=$$?'

# the OS layer: test/osmon on scripted input (1MB: *commands give No room;
# R68K_RAM=2M make oscheck to run them)
oscheck:	test/osmon
	python3 tools/runminix.py -m $(MINIX) -f /usr/bin/osmon=test/osmon \
		-f /usr/osmon.in=test/osmon.in 'osmon < /usr/osmon.in'

# the interpreter against the Z80 original (RunCPM): test/bas/*.in
bascheck:	bbcbasic
	python3 tools/bascheck.py

ROSCO	= $(MINIX)/src/rosco
PROTOLINE = f /usr/bin/bbcbasic	755 ../rootfs/local/bbcbasic

install:	bbcbasic
	mkdir -p $(ROSCO)/rootfs/local
	cp bbcbasic $(ROSCO)/rootfs/local/bbcbasic
	grep -q '^f /usr/bin/bbcbasic' $(ROSCO)/rootfs/sdproto || \
		printf '\n# BBC BASIC (src68k in BBCZ80, make install)\n%s\n' \
		'$(PROTOLINE)' >> $(ROSCO)/rootfs/sdproto

# the 68000 inline assembler against the ACK assembler
asmcheck:	bbcbasic
	python3 tools/asmcheck.py

# all of it on the MAME rosco-emulator (podman image localhost/rosco-emulator,
# build/mame/image-115200.bin: see tools/mamebench.py, runmame.py)
mamecheck:	bbcbasic test/mathtest
	BBC_EMU=mame python3 tools/bascheck.py -t 600
	BBC_EMU=mame python3 tools/asmcheck.py
	BBC_EMU=mame python3 tools/mathcheck.py -n 400

clean:
	rm -f *.o test/*.o $(TESTS) bbcbasic test/cpu020

# the stand-alone demo: build/demo/bbc68k-demo.tar.gz (demo/README.txt);
# booted and run once by --test
demo:	bbcbasic
	python3 tools/mkdemo.py --test

# the web version: build/web/bbc68k.html, one page that works offline
# (web/README.md), with bare BBC BASIC; webminix: the Minix demo in it
# (build/web/bbc68k-minix.html).  Needs emcc.
web:	bare
	python3 tools/mkweb.py --test

webminix:	demo
	python3 tools/mkweb.py --minix --test

# BBC BASIC on a bare rosco_m68k, no Minix (bare/, tools/mkbare.py):
# build/bare/ROSCODE1.BIN, and with the demo programs build/bare/demo/;
# barecheck runs the BASIC tests on it
bare:	$(BASOBJ)
	python3 tools/mkbare.py
	python3 tools/mkbare.py --demo

barecheck:	$(BASOBJ)
	BBC_EMU=bare python3 tools/bascheck.py
	python3 tools/mkbare.py
	python3 tools/fatcheck.py

# the keyboard at a terminal (ESCape, typeahead, ^S/^Q, the editor) on the
# demo (tools/ttycheck.py)
ttycheck:	demo
	python3 tools/ttycheck.py

.PHONY:	all check oscheck bascheck asmcheck mamecheck install demo web webminix ttycheck bare barecheck clean
