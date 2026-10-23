#
! exec2.s - BBC BASIC 68k: statement execution, part 2 (from EXEC.Z80):
! FN/PROC, LOCAL, argument passing, assignment, string storage, DIM and
! the subroutines.
!
! (C) Copyright R.T. Russell 1981-2025 (Z80 original); 68000 translation
! for Minix on the rosco_m68k.  See CONVENTIONS.md and PHASE4.md.
!
! THE NAME BBC BASIC IS USED WITH THE PERMISSION OF THE BRITISH
! BROADCASTING CORPORATION AND IS NOT TRANSFERRABLE TO A FORKED OR
! DERIVED WORK.
!
! Stack frames (sp upwards):
!   PROC/FN: 0 PROCHK/FNCHK, 4 slot: the text pointer to return to (on
!            entry its low byte holds TON for ON PROC)               (8)
!   LOCAL:   0 LOCCHK, 4 VARPTR, 8 type (byte), 9 exponent or string
!            length (byte), 10 payload: numeric mantissa .l, array
!            pointer .l, string bytes (padded to even), type 2: a long,
!            type 3: two longs (restored raw); type bit 4 set: do not
!            restore
!   RETURN:  0 RETCHK, 4 count .w, 6 table: per RETURN parameter 12
!            bytes: formal VARPTR .l, formal type .w, actual VARPTR .l,
!            actual type .w
!   ARRCHK:  0 ARRCHK, 4 flags .w (bit 7 string array), 6 descriptor
!            size .l, 10 data size .l, 14 total size reserved .l (the
!            block rounded to even), 18 the array block (DIM LOCAL)
!   ARGUE stack items: formal VARPTR .l, value, then the word
!            type << 8 | exponent (or the PUSHS frame word for strings);
!            the bottom marker word is &FF00.

#include "bbc.h"

	.sect	.text
	.sect	.rom
	.sect	.data
	.sect	.bss

	.define	FN, PROC, LOCAL, ENDPRO, FNEND, DIM, ASSIGN, MODIFY, MODIFS
	.define	STOREN, STORE4, STORE5, STACCS, STORES, CHECK, RESLOC, TERMQ
	.define	SPAN, EQUALS, FORMAT, SPACES, PTEXT, FETCHS, LINES, DSRCH
	.define	NSCAN, NSCAN1, WSRCH, QUOTE, CHANEL, CHNL, LOCCHK, X14OR5
	.define	MUL32, TABIT

	.extern	END
	.extern	ERROR, CLOOP, CRLF, OUTCHR, EXTERR, NXT, NLIST, PUTCSR
	.extern	GETVAR, PUTVAR, GETDEF, LOCATE, CREATE, VAR, XEQ, SYNTAX
	.extern	EXPR, EXPRN, EXPRI, EXPRS, ITEMI, CONS, LOADS, LOADN, SFIX
	.extern	FPP, COMMA, BRAKET, PUSHS, POPS, ZERO, LDLE4, STLE4, LDDESC
	.extern	STDESC
	.extern	ACCS, BUFFER, PAGE, FREE, COUNT, CURLIN, DATPTR, ERRTRP

CR	= 0x0D
TTAB	= 0x8A
TSPC	= 0x89
TELSE	= 0x8B
TDATA	= 0xDC
TDEF	= 0xDD
TERROR	= 0x85
TLOCAL	= 0xEA
TON	= 0xEE
TRETURN	= 0xF8
TREM	= 0xF4
TEXIT	= 0x10

	.sect	.text

! =  (end of FN): FNEND
FNEND:	bsr	EXPR			! FUNCTION RESULT
	move.l	d0,fnval		! (kept while the stack is unwound)
	move.b	d1,fnexp
	move.l	a2,fnend
	move.b	d6,fntype
FNEND2:	move.l	(sp),d7			! marker
	cmp.l	#FNCHK,d7
	beq	FNEND3
	clr.b	d4
	bsr	RESLOC
	bne	FNEND2
	move.b	#7,d4
	bra	ERROR			! "No FN"
FNEND3:	add.l	#4,sp
	move.l	(sp)+,a4		! the text after the FN call
	move.l	a4,CURLIN		! IN CASE OF ERROR
	move.l	fnval,d0
	move.b	fnexp,d1
	move.l	fnend,a2
	move.b	fntype,d4		! type
	move.b	d4,d6
	rts				! (to the expression evaluator)

! FNname: N.B. ENTERED WITH d4 <> TON
FN:	move.l	d4,-(sp)		! MAKE SPACE ON STACK
	bsr	PROC1
FNCHK:

! PROCname: N.B. ENTERED WITH d4.b = ON PROC FLAG
PROC:	and.l	#0xFF,d4
	move.l	d4,-(sp)		! MAKE SPACE ON STACK
	pea	PROC1	! marker (pea: CONVENTIONS 9)
PROCHK:
PROC1:	bsr	CHECK
	sub.l	#1,a4			! (at the FN/PROC token)
	move.l	a4,-(sp)
	bsr	GETDEF
	move.l	(sp)+,a1		! (movea: flags kept)
	beq	PROC4
	bcc	1f
	move.b	#30,d4
	bra	ERROR			! "Bad call"
1:	move.l	a1,-(sp)		! find all the DEFs
	move.l	PAGE,a3
PROC2:	move.b	#TDEF,d4
	bsr	LSRCH			! LOOK FOR "DEF"
	bcs	PROC3
	move.l	a3,a4
	add.l	#1,a4			! SKIP DEF
	bsr	NXT
	bsr	GETDEF
	move.l	a4,a2
	bcs	PROC6			! (not FN or PROC)
	beq	2f
	bsr	CREATE
2:	move.l	a4,d0
	move.l	a3,a0
	bsr	STLE4			! SAVE ADDRESS
	move.l	a4,a2
PROC6:	cmp.b	#CR,(a2)+		! SKIP TO END OF LINE
	bne	PROC6
	move.l	a2,a3
	bra	PROC2
PROC3:	move.l	(sp)+,a4		! RESTORE TEXT POINTER
	bsr	GETDEF
	beq	PROC4
	move.b	#29,d4
	bra	ERROR			! "No such FN/PROC"

! PROC4: a3 = the entry (address of the DEF text after the name).
! Registers kept through SAVLOC: a0 = the slot, a1 = the formal list,
! a2 = the call site, d6 = the RETURN count.
PROC4:	move.l	a3,a0
	bsr	LDLE4
	lea	4(sp),a0		! the slot (above the marker)
	move.l	a4,a2			! the call site
	move.l	d0,a4			! the DEF text
	exg	a2,a4
	bsr	NXT			! ALLOW SPACE BEFORE (
	exg	a2,a4
	cmp.b	#'(',d4			! ARGUMENTS?
	bne	PROC5
	bsr	NXT			! ALLOW SPACE BEFORE (
	cmp.b	#'(',d4
	bne	SYNTAX			! "Syntax error"
	move.l	a4,a1			! the formal list
	clr.w	d6			! RETURN count
	bsr	SAVLOC			! SAVE DUMMY VARIABLES
	tst.w	d6
	beq	RETCHK			! NO RETURNS
	move.w	d6,d7			! reserve the RETURN table
	mulu	#12,d7
	sub.l	d7,sp
	move.w	d6,-(sp)		! PUSH RETURN COUNT
	pea	RETCHK			! PUSH MARKER (pea: CONVENTIONS 9)
RETCHK:	bsr	BRAKET			! CLOSING BRACKET (of the formals)
	move.l	a1,a4			! the formal list again
	lea	6(sp),a5		! the RETURN table (if any)
	move.l	a0,-(sp)
	bsr	ARGUE			! TRANSFER ARGUMENTS
	move.l	(sp)+,a0
! If any of the dummy arguments is the same as a passed-by-reference
! variable, then it must not be restored on exit (it would overwrite the
! wanted returned values), therefore search the saved values on the
! stack and if a match is found set bit 4 of the type.  On exit from the
! FN/PROC this will prevent the dummies from being restored.
	cmp.l	#RETCHK,(sp)
	bne	PROC5			! No RETURNs
	move.w	4(sp),d6		! RETURN count
	lea	6(sp),a3		! the table
	move.w	d6,d7
	mulu	#12,d7
	lea	0(a3,d7.l),a1		! the first SAVLOC frame
PROC7:	cmp.l	#LOCCHK,(a1)
	bne	PROC5
	move.l	4(a1),d0		! SAVLOC VARPTR
	move.l	a3,a5			! Scan RETURNs table for it
	move.w	d6,d7
	sub.w	#1,d7
1:	cmp.l	6(a5),d0		! actual VARPTR
	beq	2f
	add.l	#12,a5
	dbra	d7,1b
	bra	3f
2:	bset	#4,8(a1)		! Flag don't restore
3:	bsr	FRSIZE			! Increment past stacked data
	add.l	d7,a1
	bra	PROC7

! PROC5: a0 = the slot, a2 = the text after the call, a4 = the body
PROC5:	move.b	3(a0),d4		! WAS IT "ON PROC" ?
	move.l	a2,(a0)			! SAVE "RETURN ADDRESS"
	cmp.b	#TON,d4
	bne	XEQ
	movem.l	a0/a4,-(sp)
	move.l	a2,a4
	bsr	SPAN			! SKIP REST OF ON LIST
	move.l	a4,a2
	movem.l	(sp)+,a0/a4
	move.l	a2,(a0)
	bra	XEQ

! FRSIZE - d7.l = size of the LOCAL frame at a1
FRSIZE:	clr.l	d7
	move.b	8(a1),d0		! type
	btst	#6,d0
	bne	1f			! array: pointer
	btst	#7,d0
	bne	2f			! string
	and.b	#0x0F,d0
	cmp.b	#3,d0
	beq	3f
1:	move.l	#14,d7			! numeric, array, type 2
	rts
2:	move.b	9(a1),d7		! string: length, padded
	add.w	#1,d7
	and.w	#0xFFFE,d7
	add.l	#10,d7
	rts
3:	move.l	#18,d7			! type 3
	rts

LOCERR:	add.l	#1,a4
	bra	XEQ

! LOCAL DATA
LOCDAT:	add.l	#1,a4
	move.l	DATPTR,-(sp)
	move.w	#0x0200,-(sp)		! type 2: a long, restored raw
	pea	DATPTR
	pea	LOCCHK
	bra	XEQ

! LOCAL var[,var...]
LOCAL:	cmp.b	#TERROR,d4
	beq	LOCERR
	cmp.b	#TDATA,d4
	beq	LOCDAT
	move.l	(sp),d7
	cmp.l	#FNCHK,d7
	beq	LOCAL1
	cmp.l	#PROCHK,d7
	beq	LOCAL1
	cmp.l	#LOCCHK,d7
	beq	LOCAL1
	cmp.l	#ARRCHK,d7
	beq	LOCAL1
	cmp.l	#RETCHK,d7
	beq	LOCAL1
	move.b	#12,d4
	bra	ERROR			! "Not LOCAL"
LOCAL1:	move.l	a4,a1			! (preserved by SAVLOC)
	sub.l	#1,a4
	bsr	SAVLOC
	move.l	a1,a4
LOCAL2:	bsr	GETVAR
	bne	SYNTAX
	btst	#6,d4			! ARRAY?
	bne	LOCAL4
	move.b	d4,d7
	move.w	d7,-(sp)
	bsr	ZERO
	move.w	(sp)+,d4
	tst.b	d4
	bmi	1f
	bsr	STOREN			! ZERO
	bra	LOCAL3
1:	lea	ACCS,a2
	bsr	STACCS			! (null string)
LOCAL3:	bsr	NLIST
	bra	LOCAL2
LOCAL4:	move.b	#1,(a5)			! FLAG LOCAL ARRAY
	clr.b	1(a5)
	clr.b	2(a5)
	clr.b	3(a5)
	bra	LOCAL3

! ENDPROC
ENDPRO:	move.l	(sp),d7
	cmp.l	#PROCHK,d7		! PROC MARKER
	beq	ENDPR1
	clr.b	d4
	bsr	RESLOC
	bne	ENDPRO
	move.b	#13,d4
	bra	ERROR			! "No PROC"
ENDPR1:	add.l	#4,sp
	move.l	(sp)+,a4
	bra	XEQ

! ASSIGN - Assign a numeric value to a variable.
!   Outputs: Z      - OK, numeric scalar (stored; a5 = VARPTR, d4 = type)
!            NZ, NC - string or array: d5.w = type << 8 | operator,
!                     a3 = a5 = VARPTR; bit 14 of d5 (bit 6 of the type)
!                     set for an array
!            NZ, C  - illegal / invalid
ASSIGN:	bsr	GETVAR			! VARIABLE
	bcs	9f			! ILLEGAL VARIABLE
	beq	1f
	bsr	PUTVAR
1:	move.b	d4,d3			! Type
	bsr	NXT
	add.l	#1,a4
	move.b	d4,d5			! Operator (or =)
	cmp.b	#'=',d4
	beq	2f
	bsr	EQUALS
2:	move.b	d3,d7
	lsl.w	#8,d7
	move.b	d5,d7
	move.w	d7,d5			! type << 8 | operator
	move.b	d3,d7
	and.b	#0xC0,d7
	beq	3f
	move.w	#0,ccr			! String or array: NZ, NC
	rts
3:	movem.l	d5/a3,-(sp)
	bsr	EXPRN
	movem.l	(sp)+,d5/a5
	bsr	MODIFY
	move.w	#CC_Z,ccr
	rts
9:	move.w	#CC_C,ccr		! (NZ, C)
	rts

! MODIFY - Update numeric variable according to operator:
!   Inputs: d5.w = type << 8 | operator, d0/d1 = value, a5 = VARPTR
!   Outputs: d4.b = type
!   Destroys: Everything except a4, a5, sp
MODIFY:	cmp.b	#'=',d5
	beq	STORE0			! Simple assignment
	move.w	d5,-(sp)
	move.l	d0,d2			! value as second operand
	move.b	d1,d3
	move.w	d5,d4
	lsr.w	#8,d4			! type
	bsr	LOADN
	move.w	(sp),d4
	and.b	#15,d4			! operator
	bsr	FPP
	bcs	ERROR
	move.w	(sp)+,d5
STORE0:	move.w	d5,d4
	lsr.w	#8,d4			! Type
! STOREN - store a number: d4.b = type, d0/d1 = value, a5 = VARPTR
STOREN:	cmp.b	#5,d4
	beq	STORE5
	tst.b	d1
	beq	1f
	move.w	d4,-(sp)
	bsr	SFIX			! CONVERT TO INTEGER
	move.w	(sp)+,d4
1:	cmp.b	#4,d4
	beq	STORE4
	move.b	d0,(a5)			! STORE1: byte
	rts

STORE5:	move.b	d1,4(a5)
STORE4:	move.l	a5,a0			! (STLE4 inline)
	move.l	d0,-(sp)
	move.b	3(sp),(a5)
	move.b	2(sp),1(a5)
	move.b	1(sp),2(a5)
	move.b	(sp),3(a5)
	add.l	#4,sp
	rts

! MODIFS - Update string variable according to operator:
!   Inputs: d5.w = type << 8 | operator (= or +),
!           string in the accumulator (a2 = end), a5 = VARPTR
!   Destroys: Everything except sp, a4
MODIFS:	move.w	d5,d4
	lsr.w	#8,d4			! Type
	cmp.b	#'+',d5
	bne	STACCS
	movem.l	d4/a4/a5,-(sp)
	bsr	PUSHS			! the added string
	move.w	(sp)+,d5		! (frame word: d5.b = its length)
	move.b	d5,d3
	clr.w	d2
	move.b	d5,d2
	add.w	#1,d2
	and.w	#0xFFFE,d2		! its size on the stack
	move.l	0(sp,d2.w),d4		! (the saved d4)
	move.l	8(sp,d2.w),a5		! (the saved a5)
	movem.l	d2-d3,-(sp)
	bsr	LOADS			! the old value
	movem.l	(sp)+,d2-d3
	move.l	a2,d7
	sub.l	#ACCS,d7
	clr.w	d6
	move.b	d3,d6
	add.w	d6,d7
	cmp.w	#255,d7
	bls	1f
	move.b	#19,d4
	bra	ERROR			! String too long
1:	tst.b	d3
	beq	MODFS1			! Zero length
	move.l	sp,a0			! append it from the stack
	sub.w	#1,d6
2:	move.b	(a0)+,(a2)+
	dbra	d6,2b
MODFS1:	add.w	d2,sp			! drop it
	movem.l	(sp)+,d4/a4/a5
! STACCS - store the string accumulator: d4.b = type, a2 = end, a5 = VARPTR
STACCS:	lea	ACCS,a3
	move.l	a2,d5
	sub.l	a3,d5			! length
! STORES - store a string: d4.b = type (bit 0 set: dynamic, descriptor at
!   a5; clear: fixed, CR terminated at a5), a3 = source, d5.b = length
!   Destroys: d2, d3, d5, d6, d7, a0, a3
STORES:	btst	#0,d4
	beq	STORS3			! FIXED STRING
	move.l	a3,-(sp)		! source
	move.b	d5,d3			! new length
	bsr	LDDESC			! d5 = len, d6 = alloc, a0 = address
	cmp.b	d3,d6
	bcc	STORS1			! ENOUGH ROOM
	move.l	a0,d7			! IS STRING LAST?
	clr.l	d2
	move.b	d6,d2
	add.l	d2,d7
	cmp.l	FREE,d7
	bne	1f
	move.b	d3,d6			! yes: extend it in place
	bra	STORS0
1:	move.l	FREE,a0			! DESTINATION: the top of the heap
	tst.b	d6
	beq	2f
	move.b	d3,d7			! V5 optimisation: alloc = 2^k - 1
3:	move.b	d7,d2			! (the next 2^k - 1 >= length)
	sub.b	#1,d2
	and.b	d2,d7
	bne	3b
	add.b	d2,d2
	add.b	#1,d2
	move.b	d2,d6
	bra	STORS0
2:	move.b	d3,d6			! (was 0: exactly the length)
STORS0:	move.b	d3,d5
	bsr	STDESC
	move.l	(sp)+,a3
	clr.w	d7			! copy alloc bytes (as the Z80)
	move.b	d6,d7
	beq	9f
	sub.w	#1,d7
4:	move.b	(a3)+,(a0)+
	dbra	d7,4b
	move.l	a0,FREE			! (the new allocation)
	bra	CHECK
9:	rts

STORS1:	move.b	d3,d5			! replace in place
	bsr	STDESC
	move.l	(sp)+,a3
	clr.w	d7
	move.b	d3,d7
	beq	9f			! NULL STRING
	sub.w	#1,d7
1:	move.b	(a3)+,(a0)+
	dbra	d7,1b
9:	rts

STORS3:	move.l	a5,a0			! FIXED STRING
	clr.w	d7
	move.b	d5,d7
	beq	2f
	sub.w	#1,d7
1:	move.b	(a3)+,(a0)+
	dbra	d7,1b
2:	move.b	#CR,(a0)
	rts

! CHECK - error "No room" if FREE + 256 >= sp; preserves everything
CHECK:	move.l	a0,-(sp)
	move.l	FREE,a0
	lea	256+4(a0),a0
	cmp.l	a0,sp
	move.l	(sp)+,a0		! (movea: flags kept)
	bls	1f
	rts
1:	clr.b	d4
	bra	ERROR			! "No room"

! ARGUE: TRANSFER FN OR PROC ARGUMENTS FROM THE CALLING STATEMENT TO THE
! DUMMY VARIABLES VIA THE STACK.  IT MUST BE DONE THIS WAY TO MAKE
! PROCFRED(A,B)    DEF PROCFRED(B,A)     WORK.
! The items are pushed below ARGUE's return address and popped (UNSTAK)
! before it returns, as on the Z80.
!   Inputs:  a2 addresses the parameter list (at '(')
!            a4 addresses the dummy variable list (at '(')
!            a5 addresses the RETURNed parameter table
!   Outputs: a2, a4 updated
!   Destroys: Everything
ARGUE:	move.w	#0xFF00,-(sp)		! PUT MARKER ON STACK
ARGUE1:	add.l	#1,a4			! BUMP PAST ( OR ,
	add.l	#1,a2
	clr.b	d3
	bsr	NXT
	cmp.b	#TRETURN,d4
	bne	ARGUE9
	add.l	#1,a4			! SKIP 'RETURN'
	bsr	NXT
	move.b	#1,d3			! FLAG 'RETURN'
ARGUE9:	movem.l	d3/a2/a5,-(sp)
	bsr	GETVAR			! FORMAL PARAMETER
	bcs	ARGERR
	beq	1f
	bsr	PUTVAR
1:	movem.l	(sp)+,d3/a2/a5
	move.l	a3,-(sp)		! VARPTR
	tst.b	d3
	beq	ARGUE0
! SAVRET - SAVE 'RETURNed' PARAMETER INFO in the table (a5): the formal
! VARPTR and type, the actual VARPTR and type (the actual parameter is
! found as a variable, then also evaluated as a value below)
	movem.l	d4/a2-a5,-(sp)
	move.l	a2,a4
	bsr	NXT
	bsr	VAR
	move.l	a3,d0
	move.w	d4,d1
	movem.l	(sp)+,d4/a2-a5
	move.l	a3,(a5)			! Formal VARPTR
	move.w	d4,4(a5)
	move.l	d0,6(a5)		! Actual VARPTR
	move.w	d1,10(a5)
	add.l	#12,a5
ARGUE0:	exg	a2,a4			! a4 = the actual list
	btst	#6,d4			! ARRAY?
	bne	ARGUE3
	tst.b	d4			! TYPE
	bmi	ARGUE2			! STRING
	movem.l	d4/a2/a5,-(sp)
	bsr	EXPRN			! ACTUAL PARAMETER
	movem.l	(sp)+,d4/a2/a5
	exg	a2,a4			! a4 = the formal list again
	move.l	d0,-(sp)		! value
	lsl.w	#8,d4
	move.b	d1,d4
	move.w	d4,-(sp)		! type << 8 | exponent
	bra	ARGUE4

ARGUE2:	movem.l	d4/a2/a5,-(sp)
	bsr	EXPRS
	move.l	a2,d7			! the string end
	movem.l	(sp)+,d4/a2/a5
	exg	a2,a4			! a4 = the formal list, a2 = the actual
	move.l	a2,argtmp
	move.l	a5,argtm2
	move.l	d7,a2
	bsr	PUSHS			! (d4 = type in the frame word)
	move.l	argtmp,a2
	move.l	argtm2,a5
	bra	ARGUE4

ARGUE3:	movem.l	d4/a2/a5,-(sp)
	bsr	NXT
	bsr	GETVAR			! the actual array
	bcs	ARGERR
	move.l	a5,a0
	bsr	LDLE4			! its pointer
	bsr	NXT			! (d4: before the formal type is back)
	movem.l	(sp)+,d4/a2/a5
	exg	a2,a4
	move.l	d0,-(sp)		! STACK ARRAY POINTER
	lsl.w	#8,d4
	move.w	d4,-(sp)		! STACK TYPE
ARGUE4:	bsr	NXT
	cmp.b	#',',d4
	bne	ARGUE5
	cmp.b	#',',(a2)
	beq	ARGUE1			! ANOTHER
ARGERR:	move.b	#31,d4
	bra	ERROR			! "Bad arguments"

ARGUE5:	bsr	BRAKET
	cmp.b	#')',(a2)
	bne	ARGERR
	add.l	#1,a2
	move.l	a2,argtmp
	bsr	UNSTK1			! (the items are below this call)
	move.l	argtmp,a2
	rts

! UNSTK1 - store the stacked values into their variables, up to the
! &FF00 marker word; they are just above the return address of this call.
UNSTK1:	move.l	(sp)+,unsret		! (our return)
1:	move.w	(sp)+,d5		! type << 8 | exponent / length
	cmp.w	#0xFF00,d5
	beq	9f			! MARKER POPPED
	move.w	d5,d4
	lsr.w	#8,d4			! type
	btst	#6,d4			! ARRAY
	bne	3f
	tst.b	d4
	bmi	2f			! STRING
	move.l	(sp)+,d0		! value
	move.b	d5,d1
	move.l	(sp)+,a5
	bsr	STOREN			! WRITE TO DUMMY
	bra	1b
2:	move.b	d4,unstyp
	bsr	POPS			! (d5.b = length)
	move.b	unstyp,d4
	move.l	(sp)+,a5
	bsr	STACCS
	bra	1b
3:	move.l	(sp)+,d0		! ARRAY POINTER
	move.l	(sp)+,a0
	bsr	STLE4
	bra	1b
9:	move.l	unsret,-(sp)
	rts

! RETXFR - Restore RETURNed parameters, via the stack to ensure that
!  PROCFRED(A,B)    DEF PROCFRED(RETURN B,RETURN A)  works.
!   a5 = the table, d6.w = count
RETXFR:	move.w	#0xFF00,-(sp)		! PUT MARKER ON STACK
RETXF1:	move.l	6(a5),-(sp)		! Actual parameter (destination)
	move.l	(a5),a3			! Formal parameter (source)
	move.w	4(a5),d4		! its type
	btst	#6,d4			! ARRAY?
	bne	RETXF3
	tst.b	d4
	bmi	RETXF2			! STRING
	movem.l	d6/a5,-(sp)
	move.l	a3,a5
	bsr	LOADN
	movem.l	(sp)+,d6/a5
	move.l	d0,-(sp)		! STACK VALUE
	move.w	10(a5),d4		! actual TYPE
	lsl.w	#8,d4
	move.b	d1,d4
	move.w	d4,-(sp)		! TYPE & EXPONENT
	bra	RETXF4
RETXF3:	move.l	a3,a0
	bsr	LDLE4
	move.l	d0,-(sp)		! STACK ARRAY POINTER
	move.w	10(a5),d4
	lsl.w	#8,d4
	move.w	d4,-(sp)
	bra	RETXF4
RETXF2:	movem.l	d6/a5,-(sp)
	move.l	a3,a5
	bsr	LOADS
	movem.l	(sp)+,d6/a5
	move.w	10(a5),d4		! (actual type in the frame)
	move.l	a5,argtm2
	move.w	d6,argtm3
	bsr	PUSHS
	move.l	argtm2,a5
	move.w	argtm3,d6
RETXF4:	bsr	CHECK			! CHECK ROOM
	add.l	#12,a5
	sub.w	#1,d6
	bne	RETXF1
	bsr	UNSTK1			! (the items are below this call)
	rts

! RESRET - Restore 'RETURNed' parameters (the RETCHK frame: the marker
! is already popped, (sp) = count, then the table)
RESRET:	move.w	(sp)+,d6		! RETURN COUNT
	move.l	sp,a5			! ADDRESS PARAMETER LIST
	move.w	d6,d7
	mulu	#12,d7
	add.l	sp,d7			! the stack after the table
	move.l	d7,rstend
	lea	ACCS,a0			! save ACCS (a FN result)
	lea	BUFFER,a1
	move.w	#255,d7
1:	move.b	(a0)+,(a1)+
	dbra	d7,1b
	bsr	RETXFR			! TRANSFER VIA STACK
	lea	BUFFER,a0
	lea	ACCS,a1
	move.w	#255,d7
2:	move.b	(a0)+,(a1)+
	dbra	d7,2b
	move.l	rstend,sp		! drop the table
	move.b	#1,resflg		! Flag something restored
	bra	RESLO1

! Restore LOCAL array or memory block (ARRCHK frame, marker popped):
RESARR:	move.w	(sp)+,d5		! flags
	move.l	(sp)+,d6		! descriptor size
	move.l	(sp)+,d7		! data size
	move.l	(sp)+,d2		! total reserved
	btst	#7,d5			! String array?
	beq	1f
	move.l	sp,a0
	add.l	d6,a0			! the descriptors
	move.l	a0,a1
	add.l	d7,a1			! the end of the array
	move.l	d2,-(sp)
	bsr	FREESA			! Free string array
	move.l	(sp)+,d2
1:	add.l	d2,sp
	move.b	#1,resflg		! Flag something restored
	bra	RESLO1

! RESLOC - Restore local variables/arrays or DATA/ERROR status from stack
!   Inputs:  d4.b = 0 if everything OK, bit 0 set if DATPTR, bit 1 set
!            if ERRTRP (bit 0 and 1 together: 3 = only those two)
!   Outputs: Z if nothing was restored, NZ if something was restored
!   Destroys: everything but a4
RESLOC:	move.l	(sp)+,resret		! Return address
	clr.b	resflg			! To flag nothing was restored
	move.b	d4,resmod
RESLO1:	move.l	(sp)+,d7		! Marker ?
	cmp.l	#LOCCHK,d7
	beq	RESLO2			! Something to restore
	tst.b	resmod
	bne	RESLO8
	cmp.l	#RETCHK,d7
	beq	RESRET
	cmp.l	#ARRCHK,d7
	beq	RESARR
RESLO8:	move.l	d7,-(sp)		! Put back marker
	move.l	resret,-(sp)
	tst.b	resflg
	rts

RESLO2:	move.l	(sp),a5			! Variable pointer
	tst.b	resmod
	beq	RESLO3			! Everything allowed
	btst	#0,resmod
	beq	RESLO6
	cmp.l	#DATPTR,a5		! test for DATPTR
	beq	RESLO3
RESLO6:	btst	#1,resmod
	beq	RESLO7
	cmp.l	#ERRTRP,a5		! test for ERRTRP
	beq	RESLO3
RESLO7:	move.l	#LOCCHK,-(sp)		! Put back marker
	move.l	resret,-(sp)
	tst.b	resflg
	rts

RESLO3:	move.l	(sp)+,a5		! VARPTR
	move.w	(sp)+,d5		! Type / exponent
	move.w	d5,d4
	lsr.w	#8,d4
	move.b	#1,resflg
	btst	#6,d4
	bne	RESLO4			! Array?
	btst	#7,d4
	bne	RESLO5			! String?
	move.b	d4,d7
	and.b	#0x0F,d7
	cmp.b	#2,d7
	beq	RESLOR			! raw long(s)
	cmp.b	#3,d7
	beq	RESLOR
	move.l	(sp)+,d0
	btst	#4,d4
	bne	RESLO1			! (don't restore)
	move.b	d5,d1
	and.b	#0xEF,d4
	bsr	STOREN			! Numeric
	bra	RESLO1

RESLO4:	move.l	(sp)+,d0
	btst	#4,d4
	bne	RESLO1
	move.l	a5,a0			! Array
	bsr	STLE4
	bra	RESLO1

RESLOR:	move.l	(sp)+,(a5)+		! raw: type 2 one long, 3 two longs
	cmp.b	#3,d7
	bne	RESLO1
	move.l	(sp)+,(a5)
	bra	RESLO1

RESLO5:	clr.w	d2			! String on the stack
	move.b	d5,d2
	add.w	#1,d2
	and.w	#0xFFFE,d2		! its size
	btst	#4,d4
	bne	1f			! (don't restore)
	move.l	sp,a3			! source
	and.b	#0xEF,d4
	move.w	d2,-(sp)
	bsr	STORES			! String (d5.b = length)
	move.w	(sp)+,d2
1:	add.w	d2,sp			! drop it
	bra	RESLO1

! SAVLOC: SUBROUTINE TO STACK LOCAL PARAMETERS OF A FUNCTION OR
! PROCEDURE.  THERE IS A LOT OF STACK MANIPULATION - CARE!!
! The frames are pushed below SAVLOC's own return address, which is kept
! in a6; around the calls inside, a6 and the caller's registers are
! pushed and popped again before the next frame is pushed.
!   Inputs:  a4 is parameters pointer (at the '(' or before the first)
!   Outputs: a4 updated, d6.w incremented for each RETURN
!   Preserves: a0, a1, a2 (the caller's state)
SAVLOC:	move.l	(sp)+,a6		! RETURN ADDRESS
SAVLO1:	add.l	#1,a4			! BUMP PAST ( OR ,
	bsr	NXT
	cmp.b	#TRETURN,d4
	bne	SAVLO6
	add.w	#1,d6			! RETURN counter
	add.l	#1,a4			! Bump past RETURN
	bsr	NXT
SAVLO6:	movem.l	d6/a0-a2/a6,-(sp)
	bsr	VAR			! DUMMY VARIABLE
	movem.l	(sp)+,d6/a0-a2/a6
	btst	#6,d4			! ARRAY?
	bne	SAVLO3
	tst.b	d4			! TYPE
	bmi	SAVLO2			! STRING
	movem.l	d4/d6/a0/a5,-(sp)
	bsr	LOADN
	movem.l	(sp)+,d4/d6/a0/a5
	move.l	d0,-(sp)		! value
	lsl.w	#8,d4
	move.b	d1,d4
	move.w	d4,-(sp)		! type << 8 | exponent
	bra	SAVLO4

SAVLO3:	movem.l	a0,-(sp)		! ARRAY POINTER
	move.l	a5,a0
	bsr	LDLE4
	movem.l	(sp)+,a0
	move.l	d0,-(sp)		! SAVE TO STACK
	lsl.w	#8,d4
	move.w	d4,-(sp)		! SAVE TYPE
	bra	SAVLO4

SAVLO2:	movem.l	d4/d6/a0-a2/a5-a6,-(sp)	! STRING
	bsr	LOADS
	move.l	a2,d5
	movem.l	(sp)+,d4/d6/a0-a2/a5-a6
	bsr	CHECK
	sub.l	#ACCS,d5		! length
	move.w	d5,d7
	add.w	#1,d7
	and.w	#0xFFFE,d7
	sub.w	d7,sp
	movem.l	a0-a1,-(sp)		! (copy it below these)
	lea	8(sp),a1
	lea	ACCS,a0
	move.w	d5,d7
	beq	1f
	sub.w	#1,d7
2:	move.b	(a0)+,(a1)+		! SAVE STRING ON STACK
	dbra	d7,2b
1:	movem.l	(sp)+,a0-a1
	lsl.w	#8,d4
	move.b	d5,d4
	move.w	d4,-(sp)		! type << 8 | length
SAVLO4:	move.l	a5,-(sp)		! VARPTR
	pea	SAVLO5	! marker (pea: CONVENTIONS 9)
LOCCHK:
SAVLO5:	bsr	CHECK
	bsr	NXT
	cmp.b	#',',d4			! MORE?
	beq	SAVLO1
	jmp	(a6)			! "RETURN"

! TERMQ - d4.b = next character, Z if a statement terminator
TERMQ:	bsr	NXT
	cmp.b	#TELSE,d4
	bcc	1f
	cmp.b	#':',d4			! ASSEMBLER SEPARATOR
	bcc	1f
	cmp.b	#CR,d4
1:	rts

! SPAN - skip to the end of the statement
SPAN:	bsr	TERMQ
	bne	1f
	rts
1:	add.l	#1,a4
	cmp.b	#'"',d4
	bne	SPAN
	bsr	QUOTE
	bra	SPAN

EQUALS:	bsr	NXT
	add.l	#1,a4
	cmp.b	#'=',d4
	bne	1f
	rts
1:	move.b	#4,d4
	bra	ERROR			! "Mistake"

! FORMAT - SPC, TAB, ' in PRINT and INPUT: Z if one was done
FORMAT:	cmp.b	#TTAB,d4
	beq	DOTAB
	cmp.b	#TSPC,d4
	beq	DOSPC
	cmp.b	#0x27,d4		! '
	beq	1f
	rts
1:	bsr	CRLF
	move.w	#CC_Z,ccr
	rts

DOTAB:	movem.l	d3/d5,-(sp)
	bsr	EXPRI
	movem.l	(sp)+,d3/d5
	cmp.b	#',',(a4)
	beq	DOTAB1
	bsr	BRAKET
	move.b	d0,d4
TABIT:	cmp.b	COUNT,d4
	bne	1f
	move.w	#CC_Z,ccr
	rts
1:	bcc	2f
	bsr	CRLF
2:	sub.b	COUNT,d4
	bra	SPACES
DOTAB1:	add.l	#1,a4
	movem.l	d0/d3/d5,-(sp)
	bsr	EXPRI
	move.l	d0,d7			! y
	movem.l	(sp)+,d0/d3/d5
	move.l	d0,d6			! x
	bsr	BRAKET
	bsr	PUTCSR
	move.w	#CC_Z,ccr
	rts

DOSPC:	movem.l	d3/d5,-(sp)
	bsr	ITEMI
	movem.l	(sp)+,d3/d5
	move.b	d0,d4
! SPACES - print d4.b spaces; returns Z
SPACES:	tst.b	d4
	beq	2f
	move.w	d4,-(sp)
	move.w	d4,d7
	and.w	#0xFF,d7
	sub.w	#1,d7
	move.b	#' ',d4
1:	bsr	OUTCHR
	dbra	d7,1b
	move.w	(sp)+,d4
2:	move.w	#CC_Z,ccr
	rts

! PTEXT - print the string accumulator (up to a2)
PTEXT:	lea	ACCS,a3
1:	cmp.l	a2,a3
	bcc	2f
	move.b	(a3)+,d4
	bsr	OUTCHR
	bra	1b
2:	rts

! FETCHS - extract an item (quoted, or up to a comma) from the text at
!   a3 into the string accumulator; a3 updated.  d4, d5 preserved.
FETCHS:	movem.l	d4-d5/a4,-(sp)
	move.l	a3,a4
	bsr	XTRACT
	bsr	NXT
	move.l	a4,a3
	movem.l	(sp)+,d4-d5/a4
	rts

! LINES - the rest of the line at a3 to the string accumulator
LINES:	lea	ACCS,a2
1:	move.b	(a3),d7
	move.b	d7,(a2)
	cmp.b	#CR,d7
	beq	2f
	add.l	#1,a3
	add.l	#1,a2
	bra	1b
2:	rts

XTRACT:	bsr	NXT
	add.l	#1,a4
	cmp.b	#'"',d4
	beq	CONS
	sub.l	#1,a4
	lea	ACCS,a2
1:	move.b	(a4),d4
	move.b	d4,(a2)
	cmp.b	#',',d4
	beq	2f
	cmp.b	#CR,d4
	beq	2f
	add.l	#1,a4
	add.l	#1,a2
	bra	1b
2:	rts

! DSRCH - find the next line starting with DATA
! LSRCH - find the next line starting with token d4.b
!   Inputs:  a3 = a program line
!   Outputs: NC: a3 at the token; C: not found (a3 at the end CR...)
DSRCH:	move.b	#TDATA,d4
LSRCH:	clr.l	d7
SRCH1:	move.b	(a3),d7
	beq	SRCH2			! FAIL
	cmp.b	3(a3),d4
	beq	1f
	add.l	d7,a3
	bra	SRCH1
1:	add.l	#3,a3
	move.w	#0,ccr
	rts
SRCH2:	sub.l	#1,a3			! POINT TO CR
	move.w	#CC_C,ccr
	rts

! NSCAN - scan for token at start of line, with nesting of inner
! structures.  Alternative entry at NSCAN1 with d7.b = level (CASE).
!   Inputs: d5.w = B << 8 | C: tokens to find (start of line)
!           d6.w = D << 8 | E: E = token to nest (end of line),
!                  D = token to unnest (start of line)
!           a4 = start search area (line length byte)
!   Outputs: NZ if not found; Z if found, a4 points to byte after token
NSCAN:	clr.b	d7			! nest level
NSCAN1:	tst.b	(a4)			! line length: zero = end of prog
	beq	NSCAN6
	move.b	3(a4),d4		! initial token
	move.w	d5,d0
	lsr.w	#8,d0
	cmp.b	d0,d4			! test value reqd
	beq	NSCAN3			! found (1)
	cmp.b	d5,d4
	beq	NSCAN3			! found (2)
NSCAN7:	move.w	d6,d0
	lsr.w	#8,d0
	cmp.b	d0,d4			! unnest?
	beq	NSCAN5
NSCAN2:	clr.l	d0
	move.b	(a4),d0
	add.l	d0,a4			! go to next line
	cmp.b	-2(a4),d6		! nest?
	bne	NSCAN1
	cmp.b	#5,d0			! empty line ?
	bcs	NSCAN1
	add.b	#1,d7			! increment nest level
	bra	NSCAN1

NSCAN3:	tst.b	d7
	bne	NSCAN7
NSCAN4:	add.l	#4,a4
	move.w	#CC_Z,ccr
	rts

NSCAN5:	sub.b	#1,d7			! decrement nest level
	bpl	NSCAN2
	bra	NSCAN4

NSCAN6:	move.w	#0,ccr			! NZ
	rts

! WSRCH - search for token, with nesting of inner structures
!   Inputs:  d5.w = B << 8 | C: B = token to find or unnest (anywhere),
!            C = token to nest (anywhere), ignored after EXIT
!            d6.b = ordinal (1 = find first token, 2 = second)
!            a4 = address to start looking
!   Outputs: a4 points to byte after that found; if not found abort to
!            END
WSRCH:	move.b	(a4)+,d4
	cmp.b	#'"',d4
	bne	1f
	bsr	QUOTE
1:	cmp.b	#TREM,d4
	beq	WSRCHM
	cmp.b	#TEXIT,d4
	beq	WSRCHE
	move.w	d5,d0
	lsr.w	#8,d0
	cmp.b	d0,d4
	beq	WSRCHX
	cmp.b	d5,d4
	beq	WSRCHP
	cmp.b	#CR,d4
	bne	WSRCH
WSRCH1:	move.b	(a4)+,d4		! Line length
	beq	WSEND
	add.l	#2,a4			! Skip line number
	cmp.b	#TDATA,(a4)
	bne	WSRCH
WSRCHM:	cmp.b	#CR,(a4)+		! Skip to end of line
	bne	WSRCHM
	bra	WSRCH1
WSRCHP:	add.b	#1,d6
	bra	WSRCH
WSRCHX:	sub.b	#1,d6
	bne	WSRCH
	rts
WSRCHE:	bsr	NXT
	add.l	#1,a4
	bra	WSRCH
WSEND:	jmp	END

! QUOTE - skip quoted string; d4.b = '"' after it
QUOTE:	move.b	(a4)+,d4
	cmp.b	#CR,d4
	beq	MISQUO
	cmp.b	#'"',d4
	bne	QUOTE
	rts
MISQUO:	move.b	#9,d4
	bra	ERROR			! "Missing quote"

! X14OR5 - multiply by the element size of a type
!   Inputs:  d2.l = number of elements, d4.b = type
!            (1 -> 1, 5 -> 5, string (bit 7) -> 6, else 4)
!   Outputs: d2.l = d2 * size, carry set if d2 is over &FFFFFFF (the Z80:
!            if the product is over &FFFF; DIM3 checks the memory)
!   Destroys: nothing else
X14OR5:	cmp.l	#0x0FFFFFFF,d2
	bhi	4f
	cmp.b	#1,d4
	beq	3f
	move.l	d2,-(sp)
	add.l	d2,d2
	add.l	d2,d2			! * 4
	tst.b	d4
	bpl	1f
	add.l	(sp),d2			! string: * 6
	add.l	(sp),d2
	bra	2f
1:	cmp.b	#5,d4
	bne	2f
	add.l	(sp),d2			! * 5
2:	add.l	#4,sp
3:	move.w	#0,ccr
	rts
4:	move.w	#CC_C,ccr
	rts

! MUL32 - 32-bit unsigned multiply (arrays; the Z80 has MUL16)
!   Inputs:  d0.l = number to be multiplied, d5.l = multiplier
!   Outputs: d0.l = d0 * d5, carry set if it does not fit in 32 bits
!   Destroys: nothing else
MUL32:	movem.l	d6-d7,-(sp)
	move.l	d0,d6
	swap	d6			! d6.w = high word of d0
	move.l	d5,d7
	swap	d7			! d7.w = high word of d5
	tst.w	d6
	beq	1f
	tst.w	d7
	bne	9f			! both over 16 bits: too big
	mulu	d5,d6			! high(d0) * low(d5)
	bra	2f
1:	mulu	d0,d7			! low(d0) * high(d5)
	move.l	d7,d6
2:	cmp.l	#0xFFFF,d6
	bhi	9f
	swap	d6			! the cross product << 16
	mulu	d5,d0			! low(d0) * low(d5)
	add.l	d6,d0
	bcs	9f
	movem.l	(sp)+,d6-d7
	move.w	#0,ccr
	rts
9:	movem.l	(sp)+,d6-d7
	move.w	#CC_C,ccr
	rts

! CHANEL - #channel: d6.b = channel
CHANEL:	bsr	NXT
	cmp.b	#'#',d4
	beq	CHNL
	move.b	#45,d4
	bra	ERROR			! "Missing #"
CHNL:	add.l	#1,a4			! SKIP '#'
	bsr	ITEMI
	move.b	d0,d6
	rts

! FREESA - Free members of a string array if adjacent to the top of heap
!   Inputs:  a0 = the first descriptor, a1 = the end of the array
!   Repeats until nothing more can be freed (freeing one may make the next
!   one adjacent).
!   Destroys: d0, d2, d3, d7, a3
FREESA:	clr.b	d3			! nothing freed yet
	move.l	a1,a3
1:	cmp.l	a0,a3
	bls	3f
	sub.l	#6,a3			! a descriptor (from the end)
	move.b	5(a3),d0		! its address (LE)
	lsl.l	#8,d0
	move.b	4(a3),d0
	lsl.l	#8,d0
	move.b	3(a3),d0
	lsl.l	#8,d0
	move.b	2(a3),d0
	clr.l	d2
	move.b	1(a3),d2		! allocated length
	move.l	d0,d7
	add.l	d2,d7
	cmp.l	FREE,d7
	bne	1b
	move.l	d0,FREE			! free it
	move.b	#1,d3
	bra	1b
3:	tst.b	d3
	bne	FREESA
	rts

! DIM var(dim1[,dim2[,...]])[,var(...]
! DIM var expr[,var expr...]
DIM:	move.l	a4,-(sp)
	cmp.b	#'!',d4
	beq	DIM4
	bsr	LOCATE			! VARIABLE
	bcs	BADDIM
	beq	1f
	bsr	CREATE
1:	cmp.b	#'(',(a4)
	bne	DIM4
	move.l	a3,a5			! the array pointer slot
	move.l	a5,a0
	bsr	LDLE4
	cmp.l	#1,d0
	bhi	DIM4			! (already DIMmed)
	add.l	#4,sp			! LEVEL STACK
	move.l	a5,dimvar
	move.b	d3,dimtyp		! type
	move.l	FREE,a5			! build the descriptor at FREE
	move.l	a5,dimdsc
	move.l	#1,d2			! number of elements
	clr.b	d3			! DIMENSION COUNTER
DIM1:	add.l	#1,a4
	movem.l	d2-d3/a5,-(sp)
	bsr	EXPRI			! DIMENSION SIZE
	movem.l	(sp)+,d2-d3/a5
	tst.l	d0
	bmi	BADDIM
	add.l	#1,d0
	lea	1(a5),a0
	bsr	STLE4			! SAVE SIZE (4 bytes LE; the Z80: 2)
	add.l	#4,a5
	move.l	d2,d5
	bsr	MUL32			! d0 = size * elements
	bcs	NOROOM			! TOO LARGE
	move.l	d0,d2
	add.b	#1,d3			! DIMENSION COUNTER
	cmp.b	#',',(a4)		! ANOTHER
	beq	DIM1
	add.l	#1,a5
	bsr	BRAKET			! CLOSING BRACKET
	move.b	dimtyp,d4		! RESTORE TYPE
	bsr	X14OR5			! d2 = elements * size
	bcs	NOROOM
	move.l	dimdsc,a3
	move.b	d3,(a3)			! NO. OF DIMENSIONS
	move.l	a5,a3			! where to allocate (after it)
	move.l	dimvar,a5
	move.l	a5,a0
	bsr	LDLE4
	move.b	dimtyp,d4
	and.b	#0x80,d4
	or.b	d0,d4			! FLAGS: bit 7 string, bit 0 LOCAL
! DIM3: d4.b = flags (bit 7 = string, bit 0 = LOCAL), d2 = amount to
! allocate, a3 = where to allocate (if not LOCAL; a3 - FREE is the size
! of the 'descriptor'), a5 = where to store the pointer
DIM3:	move.l	a3,d7
	add.l	#256,d7			! Safety margin
	add.l	d2,d7
	bcs	NOROOM
	cmp.l	sp,d7
	bcc	NOROOM
	move.l	a3,d6
	sub.l	FREE,d6			! d6 = descriptor size
	move.l	FREE,a3			! the block (heap)
	btst	#0,d4
	beq	ARRCHK0			! NOT LOCAL
	move.l	sp,d7			! LOCAL: on the stack
	sub.l	d2,d7
	sub.l	d6,d7
	and.b	#0xFE,d7		! (even)
	move.l	d7,a3
	cmp.l	sp,d7
	beq	ARRCHK0			! RESERVE NOTHING (the pointer = sp)
	move.l	sp,d5
	sub.l	a3,d5			! total reserved (with the rounding)
	move.l	a3,sp
	move.l	d5,-(sp)		! total reserved
	move.l	d2,-(sp)		! data size
	move.l	d6,-(sp)		! descriptor size
	move.w	d4,-(sp)		! flags
	pea	ARRCHK0			! push the marker (pea: CONVENTIONS 9)
ARRCHK:
ARRCHK0: move.l	a3,d0			! SAVE POINTER
	move.l	a5,a0
	bsr	STLE4
	tst.l	d6
	beq	DIM2
	move.l	FREE,a0			! COPY DESCRIPTOR
1:	move.b	(a0)+,(a3)+
	sub.l	#1,d6
	bne	1b
DIM2:	tst.l	d2
	beq	DIM5
1:	clr.b	(a3)+			! INITIALISE ARRAY
	sub.l	#1,d2
	bne	1b
DIM5:	cmp.l	sp,a3
	bcc	DIM7			! LOCAL
	move.l	a3,FREE
DIM7:	bsr	NLIST			! ANOTHER VARIABLE?
	bra	DIM

BADDIM:	move.b	#10,d4			! "Bad DIM"
	bra	ERROR
NOROOM:	move.b	#11,d4			! "DIM space"
	bra	ERROR

DIM4:	move.l	(sp)+,a4
	bsr	VAR
	tst.b	d4
	beq	BADDIM
	bmi	BADDIM
	btst	#6,d4
	bne	BADDIM
	cmp.b	#4,d4			! (not a byte variable: the address is
	bcs	BADDIM			!  32 bits; the Z80 wrote 2 bytes)
	move.b	d4,d3			! TYPE
	bsr	NXT
	clr.b	d7			! PRESET TO NOT LOCAL
	cmp.b	#TLOCAL,d4
	bne	DIM8
	add.l	#1,a4
	move.b	#1,d7			! FLAG LOCAL
DIM8:	move.w	d7,-(sp)
	move.b	d3,d4			! TYPE
	clr.l	d0
	clr.b	d1
	bsr	STOREN			! RESERVED AREA
	move.l	a5,-(sp)
	bsr	EXPRI
	move.l	(sp)+,a5
	move.l	d0,d2
	add.l	#1,d2
	move.l	FREE,d0			! (68k: the block starts at an even
	add.l	#1,d0			!  address, so that it can hold code)
	and.b	#0xFE,d0
	move.l	d0,FREE
	move.l	d0,a3
	move.w	(sp)+,d4		! LOCAL FLAG
	bra	DIM3

	.sect	.bss
	.align	4
fnval:	.space	4
fnend:	.space	4
unsret:	.space	4
argtmp:	.space	4
argtm2:	.space	4
resret:	.space	4
rstend:	.space	4
dimvar:	.space	4
dimdsc:	.space	4
fnexp:	.space	1
fntype:	.space	1
resflg:	.space	1
resmod:	.space	1
dimtyp:	.space	2
unstyp:	.space	2
argtm3:	.space	2
