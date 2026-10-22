#
! util.s - little-endian, unaligned memory access for BBC BASIC 68k.
!
! BASIC-visible data (variables, indirection, program lines, stored
! pointers) is little-endian and byte-packed; a 68000/68010 faults on a word
! or long access at an odd address, so it goes byte by byte through these.
! Interpreter-private data in .bss is big-endian and aligned and does not
! use them.  See CONVENTIONS.md section 4.

#include "bbc.h"

	.sect	.text
	.sect	.rom
	.sect	.data
	.sect	.bss

	.define	LDLE4, STLE4, LDLE2, STLE2

	.sect	.text

! LDLE4 - load a 32-bit little-endian value.
!   Inputs:  a0 = address (any alignment)
!   Outputs: d0.l = value, a0 unchanged
!   Destroys: flags
LDLE4:
	move.b	3(a0),d0
	lsl.l	#8,d0
	move.b	2(a0),d0
	lsl.l	#8,d0
	move.b	1(a0),d0
	lsl.l	#8,d0
	move.b	(a0),d0
	rts

! STLE4 - store a 32-bit value little-endian.
!   Inputs:  a0 = address (any alignment), d0.l = value
!   Outputs: a0, d0 unchanged
!   Destroys: flags
STLE4:
	move.b	d0,(a0)
	ror.l	#8,d0
	move.b	d0,1(a0)
	ror.l	#8,d0
	move.b	d0,2(a0)
	ror.l	#8,d0
	move.b	d0,3(a0)
	ror.l	#8,d0
	rts

! LDLE2 - load a 16-bit little-endian value.
!   Inputs:  a0 = address (any alignment)
!   Outputs: d0.w = value (upper word unchanged), a0 unchanged
!   Destroys: flags
LDLE2:
	move.b	1(a0),d0
	lsl.w	#8,d0
	move.b	(a0),d0
	rts

! STLE2 - store a 16-bit value little-endian.
!   Inputs:  a0 = address (any alignment), d0.w = value
!   Outputs: a0, d0 unchanged
!   Destroys: flags
STLE2:
	move.b	d0,(a0)
	ror.w	#8,d0
	move.b	d0,1(a0)
	ror.w	#8,d0
	rts
