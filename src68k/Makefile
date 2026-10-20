# Makefile for BBC BASIC 68k (ACK, Minix on the rosco_m68k).
#
#	make		build the tests (and later bbcbasic)
#	make check	run the tests under Minix in r68k (tools/runminix.py)
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

clean:
	rm -f *.o test/*.o $(TESTS) bbcbasic test/cpu020

.PHONY:	all check oscheck bascheck clean
