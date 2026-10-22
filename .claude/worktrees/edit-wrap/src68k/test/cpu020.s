! Does a 68020-only instruction trap?  ACK's as rejects extb, so it is
! encoded by hand.  Exit status 255: extb executed (68020); 0: it was
! skipped; killed by SIGILL: trapped as on a real 68010.
	.sect	.text
	.sect	.rom
	.sect	.data
	.sect	.bss
	.define	_main
	.sect	.text
_main:
	move.l	#0x80,d0
	.data2	0x49c0		! extb.l d0
	swap	d0
	and.w	#0xff,d0
	rts
