#
! utiltest.s - check the util.s helpers at odd addresses.
! Exit status 0 = all passed, otherwise the number of the failed check.

#include "../bbc.h"

	.sect	.text
	.sect	.rom
	.sect	.data
	.sect	.bss

	.define	_main
	.extern	LDLE4, STLE4, LDLE2, STLE2

	.sect	.text
_main:
	movem.l	d3-d7/a2-a5,-(sp)
	lea	buf+1,a0		! odd address
	move.l	#0x12345678,d0
	jsr	STLE4
	move.w	#1,d7
	cmp.l	#0x12345678,d0		! value kept
	bne	fail
	move.w	#2,d7
	lea	buf,a1			! bytes 78 56 34 12 at buf+1
	cmp.b	#0x78,1(a1)
	bne	fail
	cmp.b	#0x12,4(a1)
	bne	fail
	move.w	#3,d7
	clr.l	d0
	jsr	LDLE4
	cmp.l	#0x12345678,d0
	bne	fail
	move.w	#4,d7
	lea	buf+7,a0
	move.w	#0xbeef,d0
	jsr	STLE2
	cmp.b	#0xef,(a0)
	bne	fail
	cmp.b	#0xbe,1(a0)
	bne	fail
	move.w	#5,d7
	move.l	#0xffff0000,d0
	jsr	LDLE2
	cmp.l	#0xffffbeef,d0		! upper word unchanged
	bne	fail
	move.w	#6,d7
	SETGOOD
	bne	fail
	bcs	fail
	SETBAD
	beq	fail
	bcc	fail
	clr.w	d7
fail:
	move.w	d7,d0
	movem.l	(sp)+,d3-d7/a2-a5
	rts

	.sect	.bss
buf:
	.space	16
