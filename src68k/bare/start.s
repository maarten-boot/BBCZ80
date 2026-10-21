#
! start.s - start-up of BBC BASIC 68k on a bare rosco_m68k (no Minix).
! Linked first, at 0x40000: the firmware loads ROSCODE1.BIN there and
! jumps to its first byte (supervisor mode).  Here instead of Minix's
! crtso: clear the .bss (cold start only), set up the machine (bare.c
! bare_init: DUART, interrupt vector, RAM file store), move the stack to
! the top of BASIC's memory and call _main (minix.s: HIMEM = that stack
! pointer).  exit() comes back to the warm start: BASIC starts again and
! the files in the RAM store are kept.
!
! Also the EM run-time words that ACK's C code and libem.a expect from
! the start-off (EXIT, .trpim, .trppc) and the assembly helpers of bare.c.

	.define	start, _bare_restart, _bare_isr, _bare_idle, _bare_getvbr
	.define	_bare_setsr, _bare_ints, EXIT, .trpim, .trppc
	.extern	_main, _bare_init, _bare_irq, _bare_argc, _bare_argv, __end

	.sect	.text
	.sect	.rom
	.sect	.data
	.sect	.bss
	.sect	.end

	.sect	.text
start:
	move.w	#0x2700,sr		! no interrupts yet
	tst.w	cold
	beq	1f
	lea	begbss,a0		! cold start: clear the .bss
2:	cmp.l	#__end,a0
	bcc	3f
	clr.b	(a0)+
	bra	2b
3:	clr.w	cold
	move.w	#1,-(sp)		! (cold)
	bra	4f
1:	move.l	stack,sp		! warm start (exit)
	move.w	#0,-(sp)
4:	jsr	_bare_init		! -> d0 = the stack (HIMEM)
	move.l	d0,stack
	move.l	d0,sp
	move.l	#0,-(sp)		! main(argc, argv, envp)
	move.l	#_bare_argv,-(sp)
	move.w	_bare_argc,-(sp)
	jsr	_main
EXIT:
_bare_restart:
	move.w	#0x2700,sr
	bra	start

! the DUART interrupt (its vector is set by bare_init): bare_irq() in C
_bare_isr:
	movem.l	d0-d2/a0-a1,-(sp)
	jsr	_bare_irq
	movem.l	(sp)+,d0-d2/a0-a1
	rte

! wait for an interrupt (keeps emulators idle)
_bare_idle:
	stop	#0x2000
	rts

! the 68010's vector base register
_bare_getvbr:
	.data2	0x4E7A, 0x0801		! movec vbr,d0
	rts

! bare_setsr(sr): set the status register (interrupt mask)
_bare_setsr:
	move.w	4(sp),sr
	rts

! bare_ints(on): interrupts on (1) or off (0); returns the old SR
_bare_ints:
	move.w	sr,d0
	tst.w	4(sp)
	beq	1f
	move.w	#0x2000,sr
	rts
1:	move.w	#0x2700,sr
	rts

	.sect	.data
cold:	.data2	1			! the image is fresh: clear the .bss
.trpim:	.data2	0			! EM trap ignore mask
.trppc:	.data4	0			! EM trap handler
stack:	.data4	0

	.sect	.bss
begbss:
