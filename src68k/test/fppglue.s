#
! fppglue.s - call FPP from C (test/mathtest.c).
!
!	callfpp(op, m1, e1, m2, e2)  int op, e1, e2; long m1, m2;
!
! Results in the C globals fp_m (mantissa), fp_e (exponent), fp_a (A) and
! fp_err (1 on error, then fp_a is the error number).

#include "../bbc.h"

	.sect	.text
	.sect	.rom
	.sect	.data
	.sect	.bss

	.define	_callfpp
	.extern	FPP, _fp_m, _fp_e, _fp_a, _fp_err

	.sect	.text
_callfpp:
	link	a6,#0
	movem.l	d3-d7/a2-a5,-(sp)
	move.w	8(a6),d4		! op
	move.l	10(a6),d0		! m1
	move.w	14(a6),d1		! e1
	move.l	16(a6),d2		! m2
	move.w	20(a6),d3		! e2
	jsr	FPP
	scs	d7
	move.l	d0,_fp_m
	and.w	#0xff,d1
	move.w	d1,_fp_e
	and.w	#0xff,d4
	move.w	d4,_fp_a
	and.w	#1,d7
	move.w	d7,_fp_err
	movem.l	(sp)+,d3-d7/a2-a5
	unlk	a6
	rts

! callfpp2(op, m1, e1, a2, a5)  int op, e1; long m1; char *a2, *a5;
!   as callfpp, with a2 (STR output) and a5 (@% for STR, the string for
!   VAL) set; a2 after the call in fp_ptr.
	.define	_callfpp2
	.extern	_fp_ptr
_callfpp2:
	link	a6,#0
	movem.l	d3-d7/a2-a5,-(sp)
	move.w	8(a6),d4		! op
	move.l	10(a6),d0		! m1
	move.w	14(a6),d1		! e1
	move.l	16(a6),a2
	move.l	20(a6),a5
	jsr	FPP
	scs	d7
	move.l	d0,_fp_m
	and.w	#0xff,d1
	move.w	d1,_fp_e
	and.w	#0xff,d4
	move.w	d4,_fp_a
	and.w	#1,d7
	move.w	d7,_fp_err
	move.l	a2,_fp_ptr
	movem.l	(sp)+,d3-d7/a2-a5
	unlk	a6
	rts
