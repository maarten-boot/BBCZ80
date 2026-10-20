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

TESTS	= test/hello test/utiltest

all:	$(TESTS)

%.o:	%.s bbc.h
	$(AS) -c -o $@ $<

test/hello:	test/hello.o
	$(LD) -o $@ test/hello.o

test/utiltest:	test/utiltest.o util.o
	$(LD) -o $@ test/utiltest.o util.o

check:	$(TESTS)
	python3 tools/runminix.py -m $(MINIX) \
		-f /usr/bin/hello=test/hello -f /usr/bin/utiltest=test/utiltest \
		'hello' 'utiltest; echo utiltest=$$?'

clean:
	rm -f *.o test/*.o $(TESTS) test/cpu020

.PHONY:	all check clean
