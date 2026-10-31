#
! data.s - RAM module for BBC BASIC 68k (from DATA.Z80).
!
! Layout changes against the Z80 (see CONVENTIONS.md section 4):
!  - pointers are 32 bits;
!  - DYNVAR, FNPTR and PROPTR are heads of the variable / FN / PROC
!    chains and are used like the link field of a chain node, so they are
!    little-endian and accessed byte-wise like the links in the heap;
!  - the other pointers and counters are interpreter-private: big-endian,
!    aligned, accessed with move.l / move.w;
!  - STAVAR (@%, A%-Z%) is BASIC-visible: little-endian, 4 bytes each.
! Names with a leading underscore are the same variables for the C part of
! the OS layer (osl.c).
.68000				! 68000 only (see bbc.h)

	.sect	.text
	.sect	.rom
	.sect	.data
	.sect	.bss

	.define	ACCS, BUFFER, STAVAR, OC, PC, DYNVAR, FNPTR, PROPTR
	.define	PAGE, LOMEM, FREE, HIMEM, LIBASE
	.define	TRACEN, AUTONO, ERRTRP, ONERSP, ERRTXT, DATPTR, ERL, CURLIN
	.define	RANDOM, COUNT, WIDTH, ERR, LISTON, INCREM
	.define	_accs, _curlin, _autono, _himem, _free, DATEND

	.sect	.bss
! ACCS, BUFFER & STAVAR: the Z80 put them on 256-byte boundaries; the
! ACK linker does not keep .align 256 in .bss (seen: ACCS at 0x71888),
! so nothing may rely on it.  It does not keep .align 4 either: it
! word-aligns each object's part of .bss.  STAVAR (@%-Z%) must be 4-byte
! aligned, as in all BBC BASICs (GitHub issue 4), so data.o is linked
! first (Makefile, mkbare.py): then ACCS is at the start of .bss, which is
! aligned, and STAVAR = ACCS + 512.  test/bas/x05align checks it.
	.align	4
ACCS:
_accs:	.space	256		! string accumulator
BUFFER:	.space	256		! string input buffer
STAVAR:	.space	27*4		! static variables @%, A%-Z%
OC	= STAVAR+15*4		! code origin (O%)
PC	= STAVAR+16*4		! program counter (P%)
DYNVAR:	.space	54*4		! dynamic variable chain heads (LE)
FNPTR:	.space	4		! dynamic function chain head (LE)
PROPTR:	.space	4		! dynamic procedure chain head (LE)

	.align	4
PAGE:	.space	4		! start of user program
LOMEM:	.space	4		! start of dynamic storage
FREE:
_free:	.space	4		! first free-space byte
HIMEM:
_himem:	.space	4		! first byte above stack
LIBASE:	.space	4		! start of first library

TRACEN:	.space	4		! trace flag (.w) and number (.w)
AUTONO:
_autono: .space	4		! auto flag (.w) and number (.w)
ERRTRP:	.space	4		! ON ERROR statement pointer (with ONERSP:
ONERSP:	.space	4		! ON ERROR LOCAL stack pointer  kept as a pair)
ERRTXT:	.space	4		! error message pointer
DATPTR:	.space	4		! DATA pointer
CURLIN:
_curlin: .space	4		! pointer to current line
ERL:	.space	2		! line number of last error
RANDOM:	.space	5		! random number
COUNT:	.space	1		! print position
WIDTH:	.space	1		! print width
ERR:	.space	1		! error number
LISTON:	.space	1		! LISTO & OPT flag
INCREM:	.space	1		! AUTO increment
	.align	2
DATEND:				! end of the variables (cleared at COLD start)

! There is no USER label: other modules' .bss (the C OS layer, libc) is
! linked after this one, so OSINIT (minix.s) puts PAGE at _end, the end of
! all of .bss, rounded up to 256.
