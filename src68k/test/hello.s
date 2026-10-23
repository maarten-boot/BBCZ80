! Phase 0 test: a Minix program in ACK 68000 assembly that calls libc.
! Built with acc-minix (crtso.o calls _main).
	.sect	.text
	.sect	.rom
	.sect	.data
	.sect	.bss

	.define	_main
	.extern	_write

	.sect	.text
_main:
	move.w	#msglen,-(sp)		! unsigned nbytes (16-bit int)
	pea	msg			! char *buf
	move.w	#1,-(sp)		! int fd
	jsr	_write
	add.l	#8,sp
	clr.w	d0			! return 0
	rts

	.sect	.data
msg:
	.data1	'h','e','l','l','o',' ','f','r','o','m',' ','6','8','k',012
msglen	= . - msg
