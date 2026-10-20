#include "bbc.h"
! ASMB - the inline assembler (BBC BASIC [ ... ]).
! Phase 4 stub: any assembler text gives the error "Not supported"
! (decision D3: a 68000 assembler comes later).
!   Inputs:  a4 = text after [ (or the next assembler line)
!   Outputs: (never returns)

	.define	ASSEM
	.extern	EXTERR

	.sect	.text

ASSEM:	move.b	#0xFF,d4		! (error number 255, as an EXTERR)
	jsr	EXTERR
	.asciz	"Not supported"
	.align	2
