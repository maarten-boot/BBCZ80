#
! minix.s - Minix OS layer glue for BBC BASIC 68k.
!
! The interpreter calls the OS routines with the Z80 register interface
! mapped as in CONVENTIONS.md (A = d4.b, HL = a3 or d7, DE = a2 or d6,
! BC = d5, 32-bit values in d0); this glue saves what must survive and
! calls the C implementation in osl.c.  ACK C calling convention: int
! arguments are words, pointers and longs are longs, pushed right to left;
! d0-d2/a0-a1 are not preserved by C.
!
! Interface (in -> out; every routine preserves all registers it does not
! name as outputs, but NOT the condition codes unless stated):
!   OSINIT   -> a3 = PAGE, a2 = HIMEM, CCR Z clear if auto-run (name in ACCS)
!   OSRDCH   -> d4.b = character
!   OSWRCH   d4.b = character
!   OSLINE   a3 = buffer (256) -> buffer CR terminated, d4.b = 0;
!            ESCape -> ESCAPE
!   OSKEY    d7.l = time limit (centiseconds) -> CCR C set and d4.b =
!            character, or C clear on time-out
!   OSLOAD   a3 = name (CR term.), a2 = address, d5.l = max size
!            -> CCR C clear if no room
!   OSSAVE   a3 = name, a2 = start, d5.l = length
!   OSOPEN   a3 = name, d4.b = 0 OPENOUT / 1 OPENIN / 2 OPENUP
!            -> d4.b = channel (0 if not opened)
!   OSSHUT   d6.b = channel (0 = all)
!   OSBGET   d6.b = channel -> d4.b = byte, CCR C set if last byte
!   OSBPUT   d6.b = channel, d4.b = byte
!   OSSTAT   d6.b = channel -> CCR Z set (and d4.b = 0) at end of file
!   GETEXT   d6.b = channel -> d0.l = size
!   GETPTR   d6.b = channel -> d0.l = pointer
!   PUTPTR   d4.b = channel, d0.l = pointer
!   OSCLI    a3 = command (CR terminated)
!   PROMPT   (prints '>')
!   RESET    (*OPT 0)
!   TRAP     test ESCape (keyboard sampled every 20th call); flags lost
!   LTRAP    test ESCape; flags lost
!   OSCALL   (no-op)
!   GETIME   -> d0.l = TIME (centiseconds);  PUTIME  d0.l = TIME
!   CLRSCN;  PUTCSR d6.w = x, d7.w = y;  GETCSR -> d6.w = x, d7.w = y
!   BYE      (exit to Minix)
! Errors from the C side go through oserror() to the interpreter's
! EXTERR: d4.b = error number, (sp) = address of the NUL terminated
! message (as after "jsr EXTERR; .asciz ...").

#include "bbc.h"

	.sect	.text
	.sect	.rom
	.sect	.data
	.sect	.bss

	.define	_main, OSINIT, OSRDCH, OSWRCH, OSLINE, OSKEY, OSLOAD, OSSAVE
	.define	OSOPEN, OSSHUT, OSBGET, OSBPUT, OSSTAT, GETEXT, GETPTR
	.define	PUTPTR, OSCLI, PROMPT, RESET, TRAP, LTRAP, OSCALL, GETIME
	.define	PUTIME, CLRSCN, PUTCSR, GETCSR, BYE, _oserror
	.extern	START, EXTERR, ESCAPE, _end
	.extern	_os_init, _os_rdch, _os_wrch, _os_line, _os_key, _os_load
	.extern	_os_save, _os_open, _os_shut, _os_bget, _os_bput, _os_eof
	.extern	_os_ext, _os_ptr, _os_setptr, _os_cli, _os_poll, _os_gettime
	.extern	_os_settime, _os_cls, _os_putcsr, _os_getcsr, _os_bye
	.extern	_os_flags

F_ESC	= 0x80

! C scratch registers, saved around every call into osl.c
#define	SAVEC	movem.l d1-d2/a0-a1,-(sp)
#define	RESTC	movem.l (sp)+,d1-d2/a0-a1

	.sect	.text

! _main - called by crtso: main(argc, argv, envp).  Keep argc/argv and
! the stack pointer (HIMEM), then start the interpreter.
_main:
	move.w	4(sp),argc
	move.l	6(sp),argv
	move.l	sp,d0
	and.w	#0xfffc,d0
	move.l	d0,initsp
	jmp	START

OSINIT:	movem.l	d0-d2/a0-a1,-(sp)
	move.l	argv,-(sp)
	move.w	argc,-(sp)
	jsr	_os_init
	add.l	#6,sp
	move.w	d0,d1			! auto-run?
	move.l	#_end,d0		! PAGE = end of .bss, page aligned
	add.l	#255,d0
	clr.b	d0
	move.l	d0,a3
	move.l	initsp,a2		! HIMEM
	tst.w	d1
	movem.l	(sp)+,d0-d2/a0-a1	! (movem: flags unchanged)
	beq	1f
	move.w	#0,ccr			! NZ: auto-run
	rts
1:	move.w	#CC_Z,ccr
	rts

OSRDCH:	movem.l	d0-d2/a0-a1,-(sp)
	jsr	_os_rdch
	move.b	d0,d4
	movem.l	(sp)+,d0-d2/a0-a1
	rts

OSWRCH:	movem.l	d0-d2/a0-a1,-(sp)
	clr.w	-(sp)
	move.b	d4,1(sp)
	jsr	_os_wrch
	add.l	#2,sp
	movem.l	(sp)+,d0-d2/a0-a1
	rts

PROMPT:	move.w	d4,-(sp)
	move.b	#'>',d4
	bsr	OSWRCH
	move.w	(sp)+,d4
	rts

OSLINE:	movem.l	d0-d2/a0-a1,-(sp)
	move.l	a3,-(sp)
	jsr	_os_line
	add.l	#4,sp
	tst.w	d0
	movem.l	(sp)+,d0-d2/a0-a1
	bne	ABORT
	clr.b	d4
	rts

OSKEY:	movem.l	d0-d2/a0-a1,-(sp)
	move.l	d7,-(sp)
	jsr	_os_key
	add.l	#4,sp
	move.b	d0,d4
	tst.w	d0
	movem.l	(sp)+,d0-d2/a0-a1
	bmi	1f
	move.w	#CC_C,ccr		! character
	rts
1:	move.w	#0,ccr			! time-out
	rts

OSLOAD:	movem.l	d0-d2/a0-a1,-(sp)
	move.l	d5,-(sp)
	move.l	a2,-(sp)
	move.l	a3,-(sp)
	jsr	_os_load
	add.l	#12,sp
	tst.w	d0
	movem.l	(sp)+,d0-d2/a0-a1
	beq	1f
	move.w	#CC_C,ccr		! loaded
	rts
1:	move.w	#0,ccr			! no room
	rts

OSSAVE:	movem.l	d0-d2/a0-a1,-(sp)
	move.l	d5,-(sp)
	move.l	a2,-(sp)
	move.l	a3,-(sp)
	jsr	_os_save
	add.l	#12,sp
	movem.l	(sp)+,d0-d2/a0-a1
	rts

OSOPEN:	movem.l	d0-d2/a0-a1,-(sp)
	clr.w	-(sp)
	move.b	d4,1(sp)
	move.l	a3,-(sp)
	jsr	_os_open
	add.l	#6,sp
	move.b	d0,d4
	movem.l	(sp)+,d0-d2/a0-a1
	rts

OSSHUT:	movem.l	d0-d2/a0-a1,-(sp)
	clr.w	-(sp)
	move.b	d6,1(sp)
	jsr	_os_shut
	add.l	#2,sp
	movem.l	(sp)+,d0-d2/a0-a1
	rts

OSBGET:	movem.l	d0-d2/a0-a1,-(sp)
	clr.w	-(sp)
	move.b	d6,1(sp)
	jsr	_os_bget
	add.l	#2,sp
	move.b	d0,d4
	btst	#8,d0
	movem.l	(sp)+,d0-d2/a0-a1
	beq	1f
	move.w	#CC_C,ccr		! last byte
	rts
1:	move.w	#0,ccr
	rts

OSBPUT:	movem.l	d0-d2/a0-a1,-(sp)
	clr.w	-(sp)
	move.b	d4,1(sp)
	clr.w	-(sp)
	move.b	d6,1(sp)
	jsr	_os_bput
	add.l	#4,sp
	movem.l	(sp)+,d0-d2/a0-a1
	rts

OSSTAT:	movem.l	d0-d2/a0-a1,-(sp)
	clr.w	-(sp)
	move.b	d6,1(sp)
	jsr	_os_eof
	add.l	#2,sp
	tst.w	d0
	movem.l	(sp)+,d0-d2/a0-a1
	beq	1f
	clr.b	d4
	move.w	#CC_Z,ccr		! end of file
	rts
1:	move.w	#0,ccr
	rts

GETEXT:	movem.l	d1-d2/a0-a1,-(sp)
	clr.w	-(sp)
	move.b	d6,1(sp)
	jsr	_os_ext
	add.l	#2,sp
	movem.l	(sp)+,d1-d2/a0-a1
	rts

GETPTR:	movem.l	d1-d2/a0-a1,-(sp)
	clr.w	-(sp)
	move.b	d6,1(sp)
	jsr	_os_ptr
	add.l	#2,sp
	movem.l	(sp)+,d1-d2/a0-a1
	rts

PUTPTR:	movem.l	d0-d2/a0-a1,-(sp)
	move.l	d0,-(sp)
	clr.w	-(sp)
	move.b	d4,1(sp)
	jsr	_os_setptr
	add.l	#6,sp
	movem.l	(sp)+,d0-d2/a0-a1
	rts

OSCLI:	movem.l	d0-d2/a0-a1,-(sp)
	move.l	a3,-(sp)
	jsr	_os_cli
	add.l	#4,sp
	movem.l	(sp)+,d0-d2/a0-a1
	rts

RESET:	rts				! (*OPT is reset by *OPT 0)

OSCALL:	rts

! TRAP - test ESCape; every 20th call sample the keyboard (and flush the
! console output).  LTRAP - test ESCape.
TRAP:	sub.b	#1,trpcnt
	bne	LTRAP
	move.b	#20,trpcnt
	movem.l	d0-d2/a0-a1,-(sp)
	jsr	_os_poll
	movem.l	(sp)+,d0-d2/a0-a1
LTRAP:	tst.b	_os_flags		! escape flag (bit 7)
	bmi	ABORT
	rts
ABORT:	and.b	#0x7f,_os_flags		! acknowledge escape
	jmp	ESCAPE			! and abort

GETIME:	movem.l	d1-d2/a0-a1,-(sp)
	jsr	_os_gettime
	movem.l	(sp)+,d1-d2/a0-a1
	rts

PUTIME:	movem.l	d0-d2/a0-a1,-(sp)
	move.l	d0,-(sp)
	jsr	_os_settime
	add.l	#4,sp
	movem.l	(sp)+,d0-d2/a0-a1
	rts

CLRSCN:	movem.l	d0-d2/a0-a1,-(sp)
	jsr	_os_cls
	movem.l	(sp)+,d0-d2/a0-a1
	rts

PUTCSR:	movem.l	d0-d2/a0-a1,-(sp)
	move.w	d7,-(sp)
	move.w	d6,-(sp)
	jsr	_os_putcsr
	add.l	#4,sp
	movem.l	(sp)+,d0-d2/a0-a1
	rts

GETCSR:	movem.l	d0-d2/a0-a1,-(sp)
	jsr	_os_getcsr
	move.w	d0,d6			! x
	swap	d0
	move.w	d0,d7			! y
	movem.l	(sp)+,d0-d2/a0-a1
	rts

BYE:	jsr	_os_bye			! does not return

! oserror(code, msg) - from C: raise a BASIC error.  Becomes the EXTERR
! entry: d4.b = error number, (sp) = message.
_oserror:
	move.w	4(sp),d4
	move.l	6(sp),(sp)
	jmp	EXTERR

	.sect	.data
trpcnt:	.data1	20
	.align	2

	.sect	.bss
argc:	.space	2
argv:	.space	4
initsp:	.space	4
