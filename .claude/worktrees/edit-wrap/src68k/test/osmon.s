#
! osmon.s - test monitor for the Minix OS layer (minix.s, osl.c).
!
! Stands in for the interpreter: START, EXTERR, ESCAPE, CHECK and the
! version message, and calls the OS routines with the interpreter's
! register interface.  Commands (one per line, read with OSLINE):
!	*cmd		OSCLI
!	O name		OPENOUT, BPUT "Hello, 68k!" LF, show PTR# EXT#, CLOSE#
!	U name		OPENUP, PTR# = 7, BPUT "X", CLOSE#
!	I name		OPENIN, BGET# to EOF# (shows the bytes), CLOSE#
!	S name		OSSAVE "SAVED" LF
!	L name		OSLOAD into a 16-byte area (shows it, or "no room")
!	T  P		show TIME / TIME = 0
!	K		OSKEY with 2 s limit
!	X		PUTCSR 5,2 then GETCSR
!	E		loop on TRAP until ESCape
!	H		show PAGE, HIMEM, ACCS and the auto-run flag
!	Q		BYE

#include "../bbc.h"

	.sect	.text
	.sect	.rom
	.sect	.data
	.sect	.bss

	.define	START, EXTERR, ESCAPE, CHECK, _vermsg
	.extern	OSINIT, OSRDCH, OSWRCH, OSLINE, OSKEY, OSLOAD, OSSAVE
	.extern	OSOPEN, OSSHUT, OSBGET, OSBPUT, OSSTAT, GETEXT, GETPTR
	.extern	PUTPTR, OSCLI, PROMPT, TRAP, GETIME, PUTIME, PUTCSR, GETCSR
	.extern	BYE, ACCS, BUFFER

CR	= 13
LF	= 10

	.sect	.text
START:	bsr	OSINIT
	sne	d7
	move.l	a3,page
	move.l	a2,himem
	move.b	d7,auto
	move.l	a2,sp			! the stack starts at HIMEM
	move.l	sp,mainsp
	lea	banner,a0
	bsr	pstr

LOOP:	move.l	mainsp,sp
	bsr	PROMPT
	lea	BUFFER,a3
	bsr	OSLINE
	lea	BUFFER,a3
	move.b	(a3),d0
	cmp.b	#'*',d0
	beq	CLI
	and.b	#0xdf,d0		! upper case
	lea	2(a3),a3		! argument
	cmp.b	#'O',d0
	beq	COUT
	cmp.b	#'U',d0
	beq	CUP
	cmp.b	#'I',d0
	beq	CIN
	cmp.b	#'S',d0
	beq	CSAVE
	cmp.b	#'L',d0
	beq	CLOAD
	cmp.b	#'T',d0
	beq	CTIME
	cmp.b	#'P',d0
	beq	CPUT
	cmp.b	#'K',d0
	beq	CKEY
	cmp.b	#'X',d0
	beq	CCSR
	cmp.b	#'E',d0
	beq	CESC
	cmp.b	#'H',d0
	beq	CHIM
	cmp.b	#'Q',d0
	beq	BYE
	cmp.b	#CR,d0
	beq	LOOP
	lea	what,a0
	bsr	pstr
	bra	LOOP

CLI:	bsr	OSCLI
	bra	LOOP

COUT:	clr.b	d4			! OPENOUT
	bsr	OSOPEN
	bsr	showch
	move.b	d4,d6
	lea	hello,a0
1:	move.b	(a0)+,d4
	beq	2f
	bsr	OSBPUT
	bra	1b
2:	bsr	showpe
	bsr	OSSHUT
	bra	LOOP

CUP:	move.b	#2,d4			! OPENUP
	bsr	OSOPEN
	bsr	showch
	move.b	d4,d6
	move.l	#7,d0
	bsr	PUTPTR
	move.b	#'X',d4
	bsr	OSBPUT
	bsr	showpe
	bsr	OSSHUT
	bra	LOOP

CIN:	move.b	#1,d4			! OPENIN
	bsr	OSOPEN
	bsr	showch
	move.b	d4,d6
1:	bsr	OSSTAT
	beq	2f			! EOF#
	bsr	OSBGET
	scs	d5
	bsr	pchar
	tst.b	d5
	beq	1b
	lea	last,a0			! (carry: last byte)
	bsr	pstr
	bra	1b
2:	lea	eofmsg,a0
	bsr	pstr
	bsr	showpe
	bsr	OSSHUT
	bra	LOOP

CSAVE:	lea	saved,a2
	move.l	#6,d5
	bsr	OSSAVE
	bra	LOOP

CLOAD:	lea	area,a2
	move.l	#16,d5
	bsr	OSLOAD
	bcs	1f
	lea	noroom,a0
	bsr	pstr
	bra	LOOP
1:	lea	area,a0
	move.w	#15,d1
2:	move.b	(a0)+,d4
	bsr	pchar
	dbra	d1,2b
	bsr	crlf
	bra	LOOP

CTIME:	bsr	GETIME
	bsr	phex
	bsr	crlf
	bra	LOOP

CPUT:	clr.l	d0
	bsr	PUTIME
	bra	LOOP

CKEY:	move.l	#200,d7
	bsr	OSKEY
	bcc	1f
	move.b	d4,d0
	and.l	#0xff,d0
	bsr	phex
	bsr	crlf
	bra	LOOP
1:	lea	tout,a0
	bsr	pstr
	bra	LOOP

CCSR:	move.w	#5,d6
	move.w	#2,d7
	bsr	PUTCSR
	bsr	GETCSR
	move.w	d6,d0
	and.l	#0xffff,d0
	bsr	phex
	bsr	crlf
	bra	LOOP

CESC:	move.l	#0,d1
1:	bsr	TRAP
	add.l	#1,d1
	bra	1b

CHIM:	move.l	page,d0
	bsr	phex
	move.l	himem,d0
	bsr	phex
	move.l	#ACCS,d0
	bsr	phex
	move.b	auto,d0
	and.l	#0xff,d0
	bsr	phex
	bsr	crlf
	bra	LOOP

! showch - "ch=" d4; showpe - " PTR=", " EXT=" of channel d6
showch:	move.l	d4,-(sp)
	lea	chmsg,a0
	bsr	pstr
	move.l	(sp),d0
	and.l	#0xff,d0
	bsr	phex
	bsr	crlf
	move.l	(sp)+,d4
	tst.b	d4
	bne	1f
	lea	notopen,a0
	bsr	pstr
	bra	LOOP
1:	rts

showpe:	lea	ptrmsg,a0
	bsr	pstr
	bsr	GETPTR
	bsr	phex
	lea	extmsg,a0
	bsr	pstr
	bsr	GETEXT
	bsr	phex
	bra	crlf

! EXTERR - d4.b = error number, (sp) = message
EXTERR:	move.l	(sp)+,a1
	move.b	d4,d0
	and.l	#0xff,d0
	lea	errmsg,a0
	bsr	pstr
	bsr	phex
	move.l	a1,a0
	bsr	pstr
	bsr	crlf
	bra	LOOP

ESCAPE:	lea	escmsg,a0
	bsr	pstr
	bra	LOOP

CHECK:	rts

! output helpers (OSWRCH)
pstr:	move.b	(a0)+,d4
	beq	1f
	bsr	OSWRCH
	bra	pstr
1:	rts

crlf:	move.b	#CR,d4
	bsr	OSWRCH
	move.b	#LF,d4
	bra	OSWRCH

pchar:	cmp.b	#' ',d4			! printable, else <hex>
	bcs	1f
	cmp.b	#127,d4
	bcc	1f
	bra	OSWRCH
1:	movem.l	d0/d2,-(sp)
	move.b	d4,d0			! <hh>
	move.b	#'<',d4
	bsr	OSWRCH
	move.w	#1,d2
	ror.l	#8,d0
	bsr	1f
	movem.l	(sp)+,d0/d2
	move.b	#'>',d4
	bra	OSWRCH
1:	rol.l	#4,d0			! d2+1 hex digits from the top of d0
	move.b	d0,d4
	and.b	#15,d4
	add.b	#'0',d4
	cmp.b	#'9'+1,d4
	bcs	2f
	add.b	#7,d4
2:	bsr	OSWRCH
	dbra	d2,1b
	rts

phex:	move.w	#7,d2			! d0.l as 8 hex digits and a space
1:	rol.l	#4,d0
	move.b	d0,d4
	and.b	#15,d4
	add.b	#'0',d4
	cmp.b	#'9'+1,d4
	bcs	2f
	add.b	#7,d4
2:	bsr	OSWRCH
	dbra	d2,1b
	move.b	#' ',d4
	bra	OSWRCH

	.sect	.rom
banner:	.asciz	"OS monitor\r\n"
what:	.asciz	"?\r\n"
hello:	.asciz	"Hello, 68k!\n"
saved:	.ascii	"SAVED\n"
chmsg:	.asciz	"ch="
notopen: .asciz	"not opened\r\n"
ptrmsg:	.asciz	"PTR="
extmsg:	.asciz	"EXT="
eofmsg:	.asciz	"<EOF>\r\n"
last:	.asciz	"<last>"
noroom:	.asciz	"no room\r\n"
tout:	.asciz	"timeout\r\n"
errmsg:	.asciz	"ERR "
escmsg:	.asciz	"\r\nEscape\r\n"
_vermsg: .ascii	"OS monitor version 1"
	.data1	CR, LF

	.sect	.bss
	.align	4
mainsp:	.space	4
page:	.space	4
himem:	.space	4
area:	.space	16
auto:	.space	2
