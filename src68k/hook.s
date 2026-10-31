#
! hook.s - hooks for graphics, sound and other machine-specific
! statements and functions (from HOOK.Z80): there is no such hardware on
! the rosco_m68k Classic, so all of them give the error "Sorry".
.68000				! 68000 only (see bbc.h)

	.sect	.text
	.sect	.rom
	.sect	.data
	.sect	.bss

	.define	CLG, COLOUR, DRAW, ENVEL, GCOL, MODE, MOVE, PLOT, SOUND
	.define	PUTIMS, CIRCLE, ELLIPS, FILL, MOUSE, ORIGIN, RECTAN, LINE
	.define	TINT, WAIT, SYS, CSRON, CSROFF, ADVAL, POINT, GETIMS, TINTFN
	.define	MODEFN, WIDFN
	.extern	EXTERR

	.sect	.text
CLG:
COLOUR:
DRAW:
ENVEL:
GCOL:
MODE:
MOVE:
PLOT:
SOUND:
ADVAL:
POINT:
GETIMS:
PUTIMS:
CIRCLE:
ELLIPS:
FILL:
MOUSE:
ORIGIN:
RECTAN:
LINE:
TINT:
TINTFN:
MODEFN:
WIDFN:
WAIT:
SYS:
CSRON:
CSROFF:
	clr.b	d4
	jsr	EXTERR
	.asciz	"Sorry"
	.align	2
