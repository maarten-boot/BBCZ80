#
! eval.s - BBC BASIC 68k: expression evaluation (from EVAL.Z80).
!
! (C) Copyright R.T. Russell 1981-2025 (Z80 original); 68000 translation
! for Minix on the rosco_m68k.  See CONVENTIONS.md and PHASE4.md.
!
! THE NAME BBC BASIC IS USED WITH THE PERMISSION OF THE BRITISH
! BROADCASTING CORPORATION AND IS NOT TRANSFERRABLE TO A FORKED OR
! DERIVED WORK.
!
! Registers: a4 = IY (text pointer), a5 = IX, d4.b = A, d6.b = A' (the
! expression type: bit 7 set for a string).  Numbers in d0.l/d1.b
! (HLH'L'/C), second operand d2.l/d3.b.  A string result is in ACCS with
! a2 = end (the Z80 DE, E = length).  All registers but a4 (and sp) are
! destroyed unless stated.
!
!BINARY FLOATING POINT REPRESENTATION:
! 32 BIT SIGN-MAGNITUDE NORMALIZED MANTISSA
! 8 BIT EXCESS-128 SIGNED EXPONENT
! SIGN BIT REPLACES MANTISSA MSB (IMPLIED "1")
! MANTISSA=0 & EXPONENT=0 IMPLIES VALUE IS ZERO.
!
!BINARY INTEGER REPRESENTATION:
! 32 BIT 2'S-COMPLEMENT SIGNED INTEGER
! "EXPONENT" BYTE = 0 (WHEN PRESENT)

#include "bbc.h"

	.sect	.text
	.sect	.rom
	.sect	.data
	.sect	.bss

	.define	EXPR, EXPRN, EXPRI, EXPRS, ITEMI, CONS, LOADS, VAL0, SFIX
	.define	STR, HEXSTR, LOAD4, LOADN, DLOAD5, TEST, ZERO, COMMA, BRAKET
	.define	DECODE, PUSHS, POPS, SEARCH, SCP, LETARR, ITEM, LOAD5, DLOADN
	.define	LDLE4, STLE4, LDDESC, STDESC

	.extern	EXTERR
	.extern	MUL16, ERROR, SYNTAX, CHANEL, CHNL, STOREN, STORE4, STORE5
	.extern	STACCS, CHECK, USR, VAR, FN, XEQ, NXT, X14OR5, MODIFY, MODIFS
	.extern	TERMQ, GETVAR, LEXAN2, RANGE, GETTOP
	.extern	STAVAR, PAGE, LOMEM, HIMEM, RANDOM, COUNT, LISTON, PC, ERL
	.extern	ERR, ACCS, ERRTXT, KEYWDS, KEYWDL, FREE, BUFFER
	.extern	OSRDCH, OSOPEN, OSBGET, OSSTAT, GETCSR, GETIME, GETIMS, GETEXT
	.extern	GETPTR, OSKEY
	.extern	POINT, ADVAL, TINTFN, MODEFN, WIDFN
	.extern	FPP

FUNTOK	= 0x8D		! 1st FUNCTION TOKEN
TMOD	= 0x83
TLEN	= 0xA9
TTO	= 0xB8
TDIM	= 0xDE
TEND	= 0xE0
TMODE	= 0xEB
TREPORT	= 0xF6
TWIDTH	= 0xFE
TTINT	= 0x0A
TBY	= 0x0F

CR	= 0x0D
LF	= 0x0A
AND	= 0x80
DIV	= 0x81
EOR	= 0x82
MOD	= 0x83
OR	= 0x84

	.sect	.rom
	.align	4
! TABLE OF ADDRESSES FOR FUNCTIONS:
FUNTBL:	.data4	DECODE		! Line number
	.data4	OPENIN		! OPENIN
	.data4	PTR		! PTR
	.data4	PAGEV		! PAGE
	.data4	TIMEV		! TIME
	.data4	LOMEMV		! LOMEM
	.data4	HIMEMV		! HIMEM
	.data4	ABS		! ABS
	.data4	ACS		! ACS
	.data4	ADVAL		! ADVAL
	.data4	ASC		! ASC
	.data4	ASN		! ASN
	.data4	ATN		! ATN
	.data4	BGET		! BGET
	.data4	COS		! COS
	.data4	COUNTV		! COUNT
	.data4	DEG		! DEG
	.data4	ERLV		! ERL
	.data4	ERRV		! ERR
	.data4	EVAL		! EVAL
	.data4	EXP		! EXP
	.data4	EXT		! EXT
	.data4	ZERO		! FALSE
	.data4	FN		! FN
	.data4	GET		! GET
	.data4	INKEY		! INKEY
	.data4	INSTR		! INSTR(
	.data4	INT		! INT
	.data4	LEN		! LEN
	.data4	LN		! LN
	.data4	LOG		! LOG
	.data4	CPL		! NOT
	.data4	OPENUP		! OPENUP
	.data4	OPENOT		! OPENOUT
	.data4	PI		! PI
	.data4	POINT		! POINT(
	.data4	POS		! POS
	.data4	RAD		! RAD
	.data4	RND		! RND
	.data4	SGN		! SGN
	.data4	SIN		! SIN
	.data4	SQR		! SQR
	.data4	TAN		! TAN
	.data4	TOPV		! TO(P)
	.data4	TRUE		! TRUE
	.data4	USR		! USR
	.data4	VAL		! VAL
	.data4	VPOS		! VPOS
	.data4	CHRS		! CHR$
	.data4	GETS		! GET$
	.data4	INKEYS		! INKEY$
	.data4	LEFTS		! LEFT$(
	.data4	MIDS		! MID$(
	.data4	RIGHTS		! RIGHT$(
	.data4	STRS		! STR$
	.data4	STRING		! STRING$(
	.data4	EOF		! EOF
	.data4	SUM		! SUM
FUNEND:
TCMD	= FUNTOK+[FUNEND-FUNTBL]/4

SOPTBL:	.data4	SLE		! <= (STRING)
	.data4	SNE		! <>
	.data4	SGE		! >=
	.data4	SLT		! <
	.data4	SEQ		! =
	.data4	SGT		! >
	.sect	.text

! EXPR - VARIABLE-TYPE EXPRESSION EVALUATION
! Expression type is returned in d6.b (A'): bit 7 = 0 numeric, 1 string.
! Floating-point or integer result returned in d0/d1
!  (integer result denoted by d1.b = 0).
! String result returned in string accumulator, a2 set.
! d4.b = the next character.
!
! Hierarchy is: (1) Variables, functions, constants, bracketed
! expressions.  (2) ^  (3) * / MOD DIV  (4) + -  (5) = <> <= >= > <
! (6) AND  (7) EOR OR
EXPR:	bsr	EXPR1			! GET FIRST OPERAND
EXPR0A:	cmp.b	#EOR,d4			! CHECK OPERATOR
	beq	EXPR0B
	cmp.b	#OR,d4
	beq	EXPR0B
	rts
EXPR0B:	bsr	SAVE			! SAVE FIRST OPERAND
	bsr	EXPR1			! GET SECOND OPERAND
	bsr	DOIT			! DO OPERATION
	bra	EXPR0A			! CONTINUE

EXPR1:	bsr	EXPR2
EXPR1A:	cmp.b	#AND,d4
	beq	1f
	rts
1:	bsr	SAVE
	bsr	EXPR2
	bsr	DOIT
	bra	EXPR1A

EXPR2:	bsr	EXPR3
	bsr	RELOPQ
	beq	1f
	rts
1:	move.b	d4,d3			! B = first operator character
	add.l	#1,a4			! BUMP OVER OPERATOR
	bsr	NXT
	bsr	RELOPQ			! COMPOUND OPERATOR?
	bne	EXPR2B
	add.l	#1,a4
	cmp.b	d3,d4
	beq	SHIFT			! SHIFT OR ==
	add.b	d3,d4
	move.b	d4,d3
EXPR2B:	move.b	d3,d4
	tst.b	d6
	bmi	EXPR2S
	sub.b	#4,d4
	cmp.b	#'>'-4,d4
	bne	EXPR2C
	add.b	#2,d4
EXPR2C:	and.b	#0x0F,d4
EXPR2D:	bsr	SAVE1
	bsr	EXPR3
	bsr	DOIT			! Must NOT be "bra DOIT"
	rts

SHIFT:	cmp.b	#'=',d4
	beq	EXPR2B			! ==
	bsr	NXT
	bsr	RELOPQ
	bne	SHIFT1
	cmp.b	d3,d4
	bne	SYNTAX
	add.l	#1,a4
	add.b	#1,d3
SHIFT1:	move.b	d3,d4
	sub.b	#16,d4
	bra	EXPR2D

! String comparison: d4.b = the operator characters' sum
EXPR2S:	sub.b	#1,d4
	and.b	#7,d4
	bsr	PUSHS			! SAVE STRING ON STACK
	move.w	d4,-(sp)		! SAVE OPERATOR
	bsr	EXPR3			! SECOND STRING
	tst.b	d6
	bpl	MISMAT
	move.w	(sp)+,d4		! operator
	move.w	(sp)+,d5		! frame: d5.b = LENGTH OF STRING #1
	move.l	a2,d3
	sub.l	#ACCS,d3		! d3 = LENGTH OF STRING #2
	move.l	sp,a2			! string #1
	lea	ACCS,a3			! string #2
	move.w	d5,-(sp)
	bsr	DISPT2			! compare: result in d0/d1
	move.w	(sp)+,d5
	clr.w	d7
	move.b	d5,d7
	add.w	#1,d7
	and.w	#0xFFFE,d7
	add.w	d7,sp			! drop string #1
	clr.b	d4			! NUMERIC MARKER
	clr.b	d1			! INTEGER MARKER
	move.b	d4,d6
	move.b	(a4),d4
	rts

EXPR3:	bsr	EXPR4
EXPR3A:	cmp.b	#'-',d4
	beq	EXPR3B
	cmp.b	#'+',d4
	beq	1f
	rts
1:	tst.b	d6
	bmi	EXPR3S
EXPR3B:	bsr	SAVE
	bsr	EXPR4
	bsr	DOIT
	bra	EXPR3A

! String concatenation
EXPR3S:	add.l	#1,a4			! BUMP PAST '+'
	bsr	PUSHS			! SAVE STRING ON STACK
	bsr	EXPR4			! SECOND STRING
	tst.b	d6
	bpl	MISMAT
	move.l	a2,d3
	sub.l	#ACCS,d3		! d3 = LENGTH OF STRING #2
	move.w	(sp),d5			! d5.b = LENGTH OF STRING #1
	clr.w	d7
	move.b	d5,d7
	beq	EXP3S3
	tst.w	d3
	beq	EXP3S3
	move.w	d7,d2
	add.w	d3,d2
	cmp.w	#255,d2
	bls	1f
	move.b	#19,d4
	bra	ERROR2			! "String too long"
1:	lea	ACCS,a0			! move string #2 up by len #1
	lea	0(a0,d3.w),a0		! source end
	lea	0(a0,d7.w),a1		! destination end
	move.w	d3,d2
	sub.w	#1,d2
2:	move.b	-(a0),-(a1)		! COPY
	dbra	d2,2b
EXP3S3:	add.w	d7,d3			! total length
	move.w	(sp)+,d5
	bsr	POPS			! RESTORE FROM STACK
	lea	ACCS,a2
	add.w	d3,a2
	move.b	#0x80,d6		! FLAG STRING
	move.b	(a4),d4
	bra	EXPR3A

EXPR4:	bsr	EXPR5
EXPR4A:	cmp.b	#'*',d4
	beq	EXPR4B
	cmp.b	#'/',d4
	beq	EXPR4B
	cmp.b	#MOD,d4
	beq	EXPR4B
	cmp.b	#DIV,d4
	beq	EXPR4B
	rts
EXPR4B:	bsr	SAVE
	bsr	EXPR5
	bsr	DOIT
	bra	EXPR4A

! EXPR45 - for ITEMA: start at level 4 for + and -, else level 5
!   d5.b = operator
EXPR45:	cmp.b	#'+',d5
	beq	EXPR4
	cmp.b	#'-',d5
	beq	EXPR4
EXPR5:	bsr	ITEM
	move.b	d4,d6			! TYPE
EXPR5A:	bsr	NXT
	cmp.b	#'^',d4
	beq	1f
	rts
1:	bsr	SAVE
	bsr	ITEM
	move.b	d4,d6
	bsr	DOIT
	bra	EXPR5A

EXPRN:	bsr	EXPR
	tst.b	d6
	bmi	MISMAT
	rts

EXPRI:	bsr	EXPR
	tst.b	d6
	bpl	SFIX
	bra	MISMAT

EXPRS:	bsr	EXPR
	tst.b	d6
	bpl	MISMAT
	rts

BADHEX:	move.b	#28,d4
ERROR2:	bra	ERROR			! "Bad HEX or binary"

ITEMI:	bsr	ITEM
	tst.b	d4
	bpl	SFIX
	bra	MISMAT

ITEMS:	bsr	ITEM
	tst.b	d4
	bpl	MISMAT
	rts

MISMAT:	move.b	#6,d4
	bra	ERROR2			! "Type mismatch"

ITEM1:	bsr	EXPR			! BRACKETED EXPR
	bsr	BRAKET
	move.b	d6,d4
	rts

ITEMN:	bsr	ITEM
	tst.b	d4
	bmi	MISMAT
	rts

! HEX - Get hexadecimal constant.
!   Inputs:  ASCII string at (a4)
!   Outputs: Integer result in d0, d1 = 0, d4 = 0, a4 updated
HEX:	bsr	ZERO
	bsr	HEXDIG
	bcs	BADHEX
HEX1:	add.l	#1,a4
	lsl.l	#4,d0
	and.b	#0x0F,d4
	or.b	d4,d0
	bsr	HEXDIG
	bcc	HEX1
	clr.b	d4
	rts

! BIN - Get binary constant.
BIN:	bsr	ZERO
	bsr	BINDIG
	bcs	BADHEX
BIN1:	add.l	#1,a4
	add.l	d0,d0
	or.b	d4,d0
	bsr	BINDIG
	bcc	BIN1
	clr.b	d4
	rts

! MINUS - Unary minus: numeric result, same type as argument.
MINUS:	bsr	ITEMN
MINUS0:	tst.b	d1
	bne	1f
	neg.l	d0			! ZERO/INTEGER
	clr.b	d4
	rts
1:	bchg	#31,d0			! CHANGE SIGN (FP)
	clr.b	d4			! NUMERIC MARKER
	rts

ADDROF:	bsr	VAR
	move.l	a3,d0
	bra	COUNT1

! ITEM - VARIABLE TYPE NUMERIC OR STRING ITEM.
! Item type is returned in d4.b: bit 7 = 0 numeric, 1 string.
! Numeric item returned in d0/d1.
! String item returned in string accumulator, a2 addresses the byte
! after the last.
ITEM:	bsr	CHECK
	bsr	NXT
	add.l	#1,a4
	cmp.b	#FUNTOK,d4
	bcs	ITEM0
	cmp.b	#TCMD,d4
	bcs	DISPAT			! FUNCTIONS
	bra	EXTRAS			! DIM, END, MODE, REPORT$, WIDTH

ITEM0:	cmp.b	#':',d4
	bcc	ITEM2			! VARIABLES
	cmp.b	#'0',d4
	bcc	CON			! NUMERIC CONSTANT
	cmp.b	#'(',d4
	beq	ITEM1			! EXPRESSION
	cmp.b	#'-',d4
	beq	MINUS			! UNARY MINUS
	cmp.b	#'+',d4
	beq	ITEMN			! UNARY PLUS
	cmp.b	#'.',d4
	beq	CON			! NUMERIC CONSTANT
	cmp.b	#'&',d4
	beq	HEX			! HEX CONSTANT
	cmp.b	#'%',d4
	beq	BIN			! BINARY CONSTANT
	cmp.b	#'"',d4
	beq	CONS			! STRING CONSTANT
	cmp.b	#TTINT,d4
	beq	TINT			! TINT FUNCTION
ITEM2:	cmp.b	#TMOD,d4
	beq	MODFUN			! MOD
	cmp.b	#'^',d4
	beq	ADDROF			! ^ OPERATOR
	sub.l	#1,a4
	bsr	GETVAR			! VARIABLE
	bne	NOSUCH
	btst	#6,d4
	bne	ARRAY
	tst.b	d4
	bmi	LOADS			! STRING VARIABLE
! LOADN - load a numeric variable
!   Inputs:  a5 = variable, d4.b = type (bit 2 clear: byte; bit 0 clear:
!            integer; else float)
!   Outputs: d0/d1
LOADN:	clr.b	d1
	btst	#2,d4
	beq	LOAD1			! BYTE VARIABLE
	btst	#0,d4
	beq	LOAD4			! INTEGER VARIABLE
LOAD5:	move.b	4(a5),d1
LOAD4:	move.l	a5,a0			! (d0 = LE32 at a5: LDLE4 inline)
	move.b	3(a5),d0
	lsl.w	#8,d0
	move.b	2(a5),d0
	swap	d0
	move.b	1(a5),d0
	lsl.w	#8,d0
	move.b	(a5),d0
	rts

LOAD1:	clr.l	d0
	move.b	(a5),d0
	rts

NOSUCH:	bcs	SYNTAX
	btst	#5,LISTON
	beq	NOS1
	move.b	#26,d4
	bra	ERROR0			! "No such variable"
NOS1:	add.l	#1,a4
	bsr	RANGE
	bcc	NOS1
	lea	PC,a5
	clr.b	d1
	clr.b	d4
	bra	LOAD4

! CON - Get unsigned numeric constant from ASCII string.
!   Inputs:  ASCII string at (a4-1)
!   Outputs: Variable-type result in d0/d1, a4 updated, d4 = 0
CON:	sub.l	#1,a4
	move.l	a4,a5
	move.b	#36,d4
	bsr	FPP
	bcs	ERROR0
	move.l	a5,a4
	clr.b	d4
	rts

! CONS - Get string constant from ASCII string.
!   Inputs:  ASCII string at (a4)
!   Outputs: Result in string accumulator, a2 = end, d4 = 0x80, a4 updated
CONS:	lea	ACCS,a2
CONS3:	move.b	(a4)+,d4
	cmp.b	#'"',d4
	beq	CONS2
CONS1:	move.b	d4,(a2)+
	cmp.b	#CR,d4
	bne	CONS3
	move.b	#9,d4
ERROR0:	bra	ERROR			! "Missing """
CONS2:	cmp.b	#'"',(a4)+
	beq	CONS1
	sub.l	#1,a4
	move.b	#0x80,d4		! STRING MARKER
	rts

ARRAY:	move.b	#14,d4			! 'Bad use of array'
	bra	ERROR0

! ARRLEN - Get start address and number of elements of an array
!   Inputs:  a3 addresses array descriptor
!   Outputs: a3 = address of first element
!            d2.l = total number of elements
!            d4 = 0
ARRLEN:	clr.w	d1
	move.b	(a3)+,d1		! Number of dimensions
	beq	ARRAY
	move.l	#1,d2
ARLOOP:	clr.w	d5
	move.b	1(a3),d5
	lsl.w	#8,d5
	move.b	(a3),d5			! size of this dimension
	add.l	#2,a3
	move.l	d0,-(sp)
	move.w	d2,d0
	bsr	MUL16
	move.l	d0,d2
	move.l	(sp)+,d0
	sub.w	#1,d1
	bne	ARLOOP
	clr.b	d4
	rts

! GETARR - get an array variable
!   Outputs: a3 = array block, a5 = variable, d3.b = type and size flags
GETARR:	bsr	NXT
	bsr	GETVAR
	bne	NOSUCH
	btst	#6,d4
	bne	1f
	move.w	#CC_C,ccr
	bra	NOSUCH
1:	and.b	#0x8F,d4
	move.b	d4,d3			! Type + size
GETAR1:	move.l	a5,a0
	bsr	LDLE4			! indirect link
	cmp.l	#1,d0
	bls	ARRAY			! Bad use of array
	move.l	d0,a3
	rts

GETARB:	bsr	NXT
	cmp.b	#'(',d4
	bne	GETARR
	add.l	#1,a4
	bsr	GETARR
	bra	BRAKET

! DLOADN - load a numeric variable into d2/d3 (as LOADN)
DLOADN:	clr.b	d3
	btst	#2,d4
	beq	DLOAD1			! BYTE VARIABLE
	btst	#0,d4
	beq	DLOAD4			! INTEGER VARIABLE
DLOAD5:	move.b	4(a5),d3
DLOAD4:	move.l	d0,-(sp)
	move.l	a5,a0
	bsr	LDLE4
	move.l	d0,d2
	move.l	(sp)+,d0
	rts
DLOAD1:	clr.l	d2
	move.b	(a5),d2
	rts

! LOADS - load a string variable into ACCS
!   Inputs:  a5 = variable, d4.b = type: bit 0 set: dynamic (descriptor),
!            clear: fixed string (CR terminated, at a5)
!   Outputs: ACCS, a2 = end, d4.b = 0x80
LOADS:	lea	ACCS,a2
	btst	#0,d4
	beq	LOADS2			! FIXED STRING
	bsr	LDDESC			! d5.b = length, a0 = address
	move.b	#0x80,d4		! STRING MARKER
	tst.b	d5
	bne	1f
	rts
1:	clr.w	d7
	move.b	d5,d7
	sub.w	#1,d7
2:	move.b	(a0)+,(a2)+
	dbra	d7,2b
	rts

LOADS2:	move.l	a5,a0
	move.w	#255,d7
1:	move.b	(a0)+,d4
	move.b	d4,(a2)+
	cmp.b	#CR,d4
	beq	2f
	dbra	d7,1b
	lea	ACCS,a2			! RETURN NULL STRING
	move.b	#0x80,d4
	rts
2:	sub.l	#1,a2
	move.b	#0x80,d4
	rts

! LDDESC - load a string descriptor at a5: d5.b = length, d6.b =
!   allocated length, a0 = address.  STDESC - store them (preserves
!   everything).
LDDESC:	move.b	(a5),d5
	move.b	1(a5),d6
	move.l	d0,-(sp)
	move.l	a5,a0
	add.l	#2,a0
	bsr	LDLE4
	move.l	d0,a0
	move.l	(sp)+,d0
	rts
STDESC:	move.b	d5,(a5)
	move.b	d6,1(a5)
	movem.l	d0/a0,-(sp)
	move.l	a0,d0
	lea	2(a5),a0
	bsr	STLE4
	movem.l	(sp)+,d0/a0
	rts

! LDLE4 - d0 = 32-bit little-endian at a0;  STLE4 - (a0) = d0 LE
!   (a0, the other registers preserved; any alignment)
LDLE4:	move.b	3(a0),d0
	lsl.w	#8,d0
	move.b	2(a0),d0
	swap	d0
	move.b	1(a0),d0
	lsl.w	#8,d0
	move.b	(a0),d0
	rts
STLE4:	move.l	d0,-(sp)		! (the bytes from the stacked copy)
	move.b	3(sp),(a0)
	move.b	2(sp),1(a0)
	move.b	1(sp),2(a0)
	move.b	(sp),3(a0)
	add.l	#4,sp
	rts

! Version 5 extensions:
EXTRAS:	cmp.b	#TMODE,d4
	beq	MODEFN			! MODE
	cmp.b	#TWIDTH,d4
	beq	WIDFN			! WIDTH
	cmp.b	#TREPORT,d4
	beq	REPORS			! REPORT$
	cmp.b	#TEND,d4
	beq	ENDFUN			! END
	cmp.b	#TDIM,d4
	beq	DIMFUN			! DIM
SYNERR:	bra	SYNTAX			! 'Syntax error'

! END (function)
ENDFUN:	move.l	FREE,d0
	bra	COUNT1

! REPORT$
REPORS:	cmp.b	#'$',(a4)
	bne	SYNERR
	add.l	#1,a4
	move.l	ERRTXT,a3
	lea	ACCS,a2
REPCPY:	move.b	(a3)+,d4
	bne	1f
	move.b	#0x80,d4
	rts
1:	cmp.b	#LF,d4
	beq	2f
	cmp.b	#0x20,d4
	bcs	3f
	tst.b	d4
	bmi	3f
2:	move.b	d4,(a2)+		! character
	bra	REPCPY
3:	lea	KEYWDS,a0		! token: copy the keyword
	move.w	#KEYWDL-1,d1
4:	cmp.b	(a0)+,d4
	beq	5f
	dbra	d1,4b
	move.b	d4,(a2)+		! (unknown token: as is)
	bra	REPCPY
5:	move.b	#0x20,d1
	cmp.b	#0x11,d4
	bcs	6f
	cmp.b	#0x20,d4
	bcs	7f
6:	move.b	#0x21,d1
7:	move.b	(a0)+,d4
	cmp.b	d1,d4
	bcs	REPCPY
	tst.b	d4
	bmi	REPCPY
	move.b	d4,(a2)+
	bra	7b

! DIM(array()[,sub])
DIMFUN:	bsr	NXT
	cmp.b	#'(',d4
	bne	DIMF0
	add.l	#1,a4
	bsr	DIMF0
	bra	BRAKET

DIMF0:	bsr	GETARR
	move.l	a3,-(sp)
	bsr	NXT
	clr.l	d2
	cmp.b	#',',d4
	bne	DIMF1
	add.l	#1,a4
	bsr	EXPRI
	move.l	d0,d2
	tst.b	d2
	beq	BADSUB
DIMF1:	move.l	(sp)+,a3
	clr.l	d0
	move.b	(a3)+,d0		! number of dimensions
	cmp.b	d2,d0
	bcs	BADSUB
	tst.b	d2
	beq	DIMF2
	and.w	#0xFF,d2
	sub.w	#1,d2
	add.w	d2,a3
	add.w	d2,a3
	clr.l	d0
	move.b	1(a3),d0
	lsl.w	#8,d0
	move.b	(a3),d0
	sub.l	#1,d0
DIMF2:	bra	COUNT1

BADSUB:	move.b	#15,d4
	bra	ERROR			! "Bad subscript"

! VARIABLE-TYPE FUNCTIONS:
!
! Result returned in d0/d1 (floating point), d0 with d1 = 0 (integer), or
! in the string accumulator & a2 (string).  All registers destroyed but
! a4, which is updated.  Bit 7 of d4.b indicates type: 0 = numeric,
! 1 = string.
!
! POS, VPOS, EOF, BGET, INKEY, GET, ASC, LEN, LOMEM, HIMEM, PAGE, TOP,
! ERL, ERR, COUNT: results are integer numeric.
TINT:	bsr	TINTFN
	bra	COUNT1
POS:	bsr	GETCSR
	move.w	d6,d0
	bra	COUNT0W
VPOS:	bsr	GETCSR
	move.w	d7,d0
	bra	COUNT0W
EOF:	bsr	CHANEL
	bsr	OSSTAT
	beq	TRUE
	bra	ZERO
BGET:	bsr	CHANEL			! CHANNEL NUMBER
	bsr	OSBGET
	move.b	d4,d0
	bra	COUNT0
INKEY:	bsr	INKEYS
	bra	ASC0
GET:	bsr	NXT
	cmp.b	#'(',d4
	bne	GET0
	bsr	ITEMI			! PORT ADDRESS: no I/O ports
	clr.b	d4
	jsr	EXTERR
	.asciz	"Sorry"
	.align	2
GET0:	bsr	GETS
	bra	ASC1
ASC:	bsr	ITEMS
ASC0:	cmp.l	#ACCS,a2
	beq	TRUE			! NULL STRING
ASC1:	move.b	ACCS,d0
	bra	COUNT0
LEN:	bsr	ITEMS
	move.l	a2,d0
	sub.l	#ACCS,d0
	bra	COUNT1
LOMEMV:	move.l	LOMEM,d0
	bra	COUNT1
HIMEMV:	move.l	HIMEM,d0
	bra	COUNT1
PAGEV:	move.l	PAGE,d0
	bra	COUNT1
TOPV:	move.b	(a4)+,d4		! SKIP "P"
	cmp.b	#'P',d4
	bne	SYNTAX			! "Syntax Error"
	bsr	GETTOP
	move.l	a3,d0
	bra	COUNT1
ERLV:	clr.l	d0
	move.w	ERL,d0
	bra	COUNT1
ERRV:	move.b	ERR,d0
	bra	COUNT0
COUNTV:	move.b	COUNT,d0
COUNT0:	and.l	#0xFF,d0
	bra	COUNT1
COUNT0W: and.l	#0xFFFF,d0
COUNT1:	clr.b	d4			! INTEGER MARKER
	clr.b	d1
	rts

! OPENIN - Open a file for reading.
! OPENOUT - Open a file for writing.
! OPENUP - Open a file for reading or writing.
! Result is integer channel number (0 if error)
OPENOT:	clr.b	d4
	bra	OPEN0
OPENUP:	move.b	#2,d4
	bra	OPEN0
OPENIN:	move.b	#1,d4
OPEN0:	move.w	d4,-(sp)		! SAVE OPEN TYPE
	bsr	ITEMS			! FILENAME
	move.b	#CR,(a2)
	move.w	(sp)+,d4		! RESTORE OPEN TYPE
	lea	ACCS,a3
	bsr	OSOPEN
	move.b	d4,d0
	bra	COUNT0

! EXT - Return length of file.  PTR - Return current file pointer.
EXT:	bsr	CHANEL
	bsr	GETEXT
	bra	COUNT1
PTR:	bsr	CHANEL
	bsr	GETPTR
	bra	COUNT1

! TIME - Return current value of elapsed time.
TIMEV:	cmp.b	#'$',(a4)
	beq	TIMEVS
	bsr	GETIME
	bra	COUNT1

! TIME$ - Return date/time string.
TIMEVS:	add.l	#1,a4			! SKIP $
	bsr	GETIMS
	move.b	#0x80,d4		! MARK STRING
	rts

! String comparison (SCP sets Z/C; the result preset to FALSE):
SLT:	bsr	SCP
	bcs	TRUE
	rts
SGT:	bsr	SCP
	beq	1f
	bcs	1f
	bra	TRUE
1:	rts
SGE:	bsr	SCP
	bcc	TRUE
	rts
SLE:	bsr	SCP
	beq	TRUE
	bcs	TRUE
	rts
SNE:	bsr	SCP
	bne	TRUE
	rts
SEQ:	bsr	SCP
	bne	1f
TRUE:	move.l	#-1,d0
	clr.b	d1
	clr.b	d4
1:	rts

! Functions done by FPP (the op-code in d4.b)
PI:	move.b	#35,d4
	bra	FPP1
ABS:	move.b	#16,d4
	bra	FPPN
CPL:	move.b	#26,d4
	bra	FPPN
DEG:	move.b	#21,d4
	bra	FPPN
RAD:	move.b	#27,d4
	bra	FPPN
SGN:	move.b	#28,d4
	bra	FPPN
INT:	move.b	#23,d4
	bra	FPPN
SQR:	move.b	#30,d4
	bra	FPPN
TAN:	move.b	#31,d4
	bra	FPPN
COS:	move.b	#20,d4
	bra	FPPN
SIN:	move.b	#29,d4
	bra	FPPN
EXP:	move.b	#22,d4
	bra	FPPN
LN:	move.b	#24,d4
	bra	FPPN
LOG:	move.b	#25,d4
	bra	FPPN
ASN:	move.b	#18,d4
	bra	FPPN
ATN:	move.b	#19,d4
	bra	FPPN
ACS:	move.b	#17,d4
FPPN:	move.w	d4,-(sp)
	bsr	ITEMN
	move.w	(sp)+,d4
FPP1:	bsr	FPP
	bcs	ERROR
	clr.b	d4
	rts

! SFIX - Convert to fixed-point notation
SFIX:	move.b	#38,d4
	bra	FPP1

! SFLOAT - Convert to floating-point notation
SFLOAT:	move.b	#39,d4
	bra	FPP1

! VAL - Return numeric value of string.
VAL:	bsr	ITEMS
VAL0:	clr.b	(a2)
	lea	ACCS,a5
	move.b	#36,d4
	bra	FPP1

! EVAL - Pass string to expression evaluator.
! Result is variable type (numeric or string).
EVAL:	bsr	ITEMS
	move.b	#CR,(a2)
	move.l	a4,-(sp)
	lea	ACCS,a2
	lea	ACCS,a4
	clr.b	d5
	bsr	LEXAN2			! TOKENISE
	move.b	d4,(a2)+
	clr.b	d4
	bsr	PUSHS			! PUT ON STACK
	lea	2(sp),a4
	bsr	EXPR
	move.w	(sp)+,d5		! frame: length
	clr.w	d7
	move.b	d5,d7
	add.w	#1,d7
	and.w	#0xFFFE,d7
	add.w	d7,sp			! ADJUST STACK POINTER
	move.l	(sp)+,a4
	move.b	d6,d4
	rts

! RND - Random number function.
!  RND gives random integer 0-&FFFFFFFF
!  RND(-n) seeds random number & returns -n.
!  RND(0) returns last value in RND(1) form.
!  RND(1) returns floating-point 0-0.99999999.
!  RND(n) returns random integer 1-n.
! RANDOM is the 33-bit generator state: 4 bytes LE + a byte holding the
! extra bit in bit 0.
RND:	lea	RANDOM,a5
	bsr	NXT
	cmp.b	#'(',d4
	beq	RND5			! ARGUMENT FOLLOWS
	bsr	LOAD5
	bsr	RND1
	clr.b	d1
	clr.b	d4
	rts

! RND1 - next state: d0/d1 = state (bit 0 of d1 = the 33rd bit)
RND1:	move.b	d1,d7
	and.w	#1,d7			! carry in
	move.w	#31,d2
1:	move.b	d7,d3			! (c, d0) = (d0 << 1 | c)
	add.l	d0,d0
	scs	d7
	and.b	#1,d7
	or.b	d3,d0
	btst	#19,d0
	beq	2f
	eor.b	#1,d7
2:	dbra	d2,1b
	and.b	#0xFE,d1
	or.b	d7,d1			! SAVE CARRY
	bra	STORE5			! STORE NEW NUMBER

RND5:	bsr	ITEMI
	lea	RANDOM,a5
	tst.l	d0			! NEGATIVE?
	bpl	1f
	move.b	#1,d1			! SEED (extra bit 1)
	bsr	STORE5
	clr.b	d1
	clr.b	d4
	rts
1:	move.l	d0,-(sp)		! n
	bsr	LOAD5
	tst.l	(sp)
	beq	2f
	bsr	RND1			! NEXT IF NON-ZERO
2:	swap	d0			! SCRAMBLE: halves exchanged
	move.b	#0x7F,d1
3:	tst.l	d0			! FLOAT
	bmi	4f
	add.l	d0,d0
	sub.b	#1,d1
	bne	3b
4:	bclr	#31,d0			! POSITIVE 0-0.999999
	move.l	(sp)+,d2		! n
	clr.b	d4
	tst.l	d2
	beq	5f			! ZERO ARGUMENT
	cmp.l	#1,d2
	beq	5f			! ARGUMENT=1
	clr.b	d3			! INTEGER MARKER
	move.b	#10,d4
	bsr	FPP			! MULTIPLY
	bcs	ERROR
	bsr	SFIX
	add.l	#1,d0
	clr.b	d4
5:	rts

! SUMLEN(array())
SUMLEN:	add.l	#1,a4			! Skip LEN
	bsr	GETARB
	tst.b	d3
	bpl	MISMAT			! Type mismatch
	bsr	ARRLEN
	clr.l	d0
	clr.w	d7
1:	move.b	(a3),d7
	add.l	d7,d0
	add.l	#6,a3
	sub.l	#1,d2			! Count elements
	bne	1b
	bra	COUNT1

! SUM(array())
SUM:	bsr	NXT
	cmp.b	#TLEN,d4
	beq	SUMLEN
	bsr	GETARB
	tst.b	d3
	bmi	SUMSTR
	move.w	d3,-(sp)
	bsr	ARRLEN
	move.l	a3,a5			! a5 addresses array
	bsr	ZERO
	move.w	(sp)+,d4		! element size
SUMUP:	movem.l	d2/d4,-(sp)
	bsr	DLOADN
	move.b	#11,d4
	bsr	FPP
	bcs	ERROR
	movem.l	(sp)+,d2/d4
	clr.w	d7
	move.b	d4,d7
	and.b	#0x0F,d7
	add.w	d7,a5			! Bump to next element
	sub.l	#1,d2			! Count elements
	bne	SUMUP
	clr.b	d4
	rts

! SUM(string array)
SUMSTR:	bsr	ARRLEN
	move.l	a3,a5			! a5 addresses array
	lea	ACCS,a2
1:	move.b	(a5),d5
	beq	3f
	clr.w	d7
	move.b	d5,d7
	move.l	a2,d0
	sub.l	#ACCS,d0
	add.w	d7,d0
	cmp.w	#255,d0
	bls	2f
	move.b	#19,d4
	bra	ERROR			! "String too long"
2:	move.l	d2,-(sp)
	bsr	LDDESC
	move.l	(sp)+,d2
	sub.w	#1,d7
4:	move.b	(a0)+,(a2)+
	dbra	d7,4b
3:	add.l	#6,a5
	sub.l	#1,d2			! Count elements
	bne	1b
	move.b	#0x80,d4
	rts

! MOD(array())
MODFUN:	bsr	GETARB
	tst.b	d3
	bmi	MISMAT
	move.w	d3,-(sp)
	bsr	ARRLEN
	move.l	a3,a5			! a5 addresses array
	bsr	ZERO
	move.w	(sp)+,d4		! element size (type)
MODUP:	movem.l	d0-d2/d4,-(sp)		! accumulator, count, type
	bsr	LOADN			! element
	move.l	#2,d2			! ^2
	clr.b	d3
	move.b	#14,d4
	bsr	FPP			! Square
	bcs	ERROR
	move.l	d0,d2			! square to the second operand
	move.b	d1,d3
	movem.l	(sp)+,d0-d1		! accumulator
	move.b	#11,d4
	bsr	FPP			! Accumulate
	bcs	ERROR
	movem.l	(sp)+,d2/d4
	clr.w	d7
	move.b	d4,d7
	and.b	#0x0F,d7
	add.w	d7,a5			! Bump to next element
	sub.l	#1,d2			! Count elements
	bne	MODUP
	move.b	#30,d4
	bsr	FPP			! Square root
	clr.b	d4
	rts

! INSTR - String search.  Result is integer numeric.
INSTR:	bsr	EXPRS			! STRING TO SEARCH
	bsr	COMMA
	bsr	PUSHS			! SAVE STRING ON STACK
	bsr	EXPRS			! SUB-STRING
	move.w	(sp),d5			! d5.b = MAIN STRING LENGTH
	move.l	a2,d3
	sub.l	#ACCS,d3		! d3.b = SUB-STRING LENGTH
	bsr	NXT
	cmp.b	#',',d4
	beq	1f
	clr.b	d4			! start offset 0
	bra	INSTR1
1:	add.l	#1,a4			! SKIP COMMA
	movem.l	d3/d5,-(sp)
	bsr	PUSHS			! (sub-string)
	bsr	EXPRI
	move.w	(sp)+,d5
	bsr	POPS			! (d0 preserved)
	movem.l	(sp)+,d3/d5
	move.b	d0,d4
	beq	INSTR1
	sub.b	#1,d4
INSTR1:	lea	2(sp),a3		! main string
	lea	ACCS,a2			! sub-string
	bsr	SEARCH
	bne	1f
	move.l	a3,d0			! position = a3 - start
	sub.l	sp,d0
	sub.l	#2,d0
	bra	2f
1:	clr.l	d0
2:	move.w	(sp)+,d5		! drop the main string
	clr.w	d7
	move.b	d5,d7
	add.w	#1,d7
	and.w	#0xFFFE,d7
	add.w	d7,sp
	bsr	BRAKET
	bra	COUNT1

! SEARCH - Search string for sub-string (as the Z80, quirks included)
!   Inputs:  Main string at a3 length d5.b
!            Sub-string at a2 length d3.b
!            Starting offset d4.b
!   Outputs: NZ - not found
!            Z - found at location a3-1
!            Carry always cleared
!   Destroys: d4, d5, d7, a0, a1
SEARCH:	clr.w	d7
	move.b	d4,d7
	add.w	d7,a3			! NEW START ADDRESS
	sub.b	d5,d4
	bcc	SRCH4
	neg.b	d4
	clr.w	d5
	move.b	d4,d5			! REMAINING LENGTH (>= 1)
SRCH1:	move.b	(a2),d4			! FIND FIRST CHARACTER (CPIR)
1:	sub.w	#1,d5
	cmp.b	(a3)+,d4
	beq	2f
	tst.w	d5
	bne	1b
	bra	SRCH4
2:	move.b	d3,d7			! Bug fix: remaining >= length-1
	sub.b	#1,d7
	cmp.b	d7,d5
	bcs	SRCH4
	tst.b	d7
	beq	SRCH3			! FOUND !
	move.l	a2,a0
	add.l	#1,a0
	move.l	a3,a1
3:	cmp.b	(a0)+,(a1)+
	bne	SRCH1
	sub.b	#1,d7
	bne	3b
SRCH3:	move.w	#CC_Z,ccr
	rts				! FOUND
SRCH4:	move.w	#0,ccr			! NZ, NC
	rts				! NOT FOUND

! CHR$ - Return character with given ASCII value.
CHRS:	bsr	ITEMI
	move.b	d0,d4
	bra	GET1

! GET$ - Return key pressed as string, or read from file
GETS:	bsr	NXT
	cmp.b	#'#',d4
	beq	GET2
	bsr	OSRDCH
GET1:	lea	ACCS,a2
	move.b	d4,(a2)+
	move.b	#0x80,d4
	rts

! GET$#chan [BY n | TO term] (as the Z80: d5.w = BC, d2.b = D count)
GET2:	bsr	CHNL			! File channel -> d6
	bsr	NXT
	move.b	d4,d1			! the qualifier keyword (if any)
	clr.l	d0
	cmp.b	#TBY,d4
	beq	GET3
	cmp.b	#TTO,d4
	bne	GET4
GET3:	add.l	#1,a4
	movem.l	d1/d6,-(sp)
	bsr	ITEMI			! Get BY or TO qualifier
	movem.l	(sp)+,d1/d6
GET4:	lea	ACCS,a2
	move.w	d0,d5			! (TO: B = flags, C = terminator)
	cmp.b	#TTO,d1
	beq	GET5
	move.b	d0,d2			! Maximum count
	move.w	#0x0100,d5		! Default
	cmp.b	#TBY,d1
	beq	GET6
GET5:	clr.b	d2
	bset	#9,d5			! Flag no count
GET6:	bsr	OSBGET
	scs	d7			! EOF
	btst	#9,d5
	beq	GET10
	cmp.b	d5,d4
	beq	GET9			! NUL (or supplied term)
	btst	#15,d5
	bne	GET7
	btst	#8,d5
	beq	GET8
	cmp.b	#LF,d4
	beq	GET9			! LF
GET7:	cmp.b	#CR,d4
	beq	GET9			! CR
GET8:	clr.b	d7			! (OR A: the EOF carry is lost)
GET10:	move.b	d4,(a2)+
	cmp.l	#ACCS+256,a2		! (INC L: wraps in the page)
	bcs	1f
	lea	ACCS,a2
1:	tst.b	d7
	bne	GET9			! EOF
	sub.b	#1,d2
	bne	GET6
GET9:	move.b	#0x80,d4
	rts

! INKEY$ - Wait up to n centiseconds for keypress.
INKEYS:	bsr	ITEMI
	move.l	d0,d7
	bsr	OSKEY
	lea	ACCS,a2
	bcc	1f
	move.b	d4,(a2)+
1:	move.b	#0x80,d4
	rts

! MID$ - Return sub-string.
MIDS:	bsr	EXPRS
	bsr	COMMA
	bsr	PUSHS			! SAVE STRING ON STACK
	bsr	EXPRI
	move.w	(sp)+,d5
	bsr	POPS			! (d0 preserved)
	move.l	a2,d3
	sub.l	#ACCS,d3		! length
	move.b	d0,d4
	beq	MIDS1
	sub.b	#1,d4			! start offset
	clr.w	d7
	move.b	d4,d7
	cmp.b	d3,d4
	bcc	2f
	move.w	d3,d2			! copy the rest down
	sub.w	d7,d2
	lea	ACCS,a0
	add.w	d7,a0
	lea	ACCS,a2
1:	move.b	(a0)+,(a2)+
	sub.w	#1,d2
	bne	1b
	bra	MIDS1
2:	lea	ACCS,a2			! past the end: null string
MIDS1:	bsr	NXT
	cmp.b	#',',d4
	beq	LEFT1
	bsr	BRAKET
	move.b	#0x80,d4
	rts

! LEFT$ - Return left part of string.
LEFTS:	bsr	EXPRS
	bsr	NXT
	cmp.b	#',',d4
	beq	LEFT1
	bsr	BRAKET
	cmp.l	#ACCS,a2
	beq	LEFT3
	sub.l	#1,a2			! all but the last character
	bra	LEFT3

! LEFT1 - truncate to n characters (n after the comma)
!   Outputs: carry clear if the whole string is returned (for RIGHT$),
!            d5.b = the original length
LEFT1:	add.l	#1,a4
	bsr	PUSHS			! SAVE STRING ON STACK
	bsr	EXPRI
	move.w	(sp)+,d5
	bsr	POPS			! (d0 preserved)
	bsr	BRAKET
	move.l	a2,d3
	sub.l	#ACCS,d3
	cmp.b	d3,d0
	bcc	LEFT3			! (NC: all)
	move.b	d3,d5			! FOR RIGHT$
	lea	ACCS,a2
	and.w	#0xFF,d0
	add.w	d0,a2
	move.b	#0x80,d4
	move.w	#CC_C,ccr
	rts
LEFT3:	move.b	#0x80,d4		! STRING MARKER
	move.w	#0,ccr
	rts

! RIGHT$ - Return right part of string.
RIGHTS:	bsr	EXPRS
	bsr	NXT
	cmp.b	#',',d4
	beq	RIGHT0
	bsr	BRAKET
	cmp.l	#ACCS,a2
	beq	LEFT3
	move.l	a2,d7			! the last character only
	sub.l	#ACCS+1,d7
	lea	ACCS,a0
	move.b	0(a0,d7.w),(a0)
	lea	ACCS+1,a2
	move.b	#0x80,d4
	rts

RIGHT0:	bsr	LEFT1
	bcc	1f			! the whole string
	move.l	a2,d0
	sub.l	#ACCS,d0		! n
	beq	1f
	clr.w	d7
	move.b	d5,d7
	sub.w	d0,d7			! from offset len-n
	lea	ACCS,a0
	add.w	d7,a0
	lea	ACCS,a2
2:	move.b	(a0)+,(a2)+
	sub.w	#1,d0
	bne	2b
1:	move.b	#0x80,d4
	rts

! STRING$ - Return n concatenations of a string.
STRING:	bsr	EXPRI
	bsr	COMMA
	move.w	d0,-(sp)
	bsr	EXPRS
	bsr	BRAKET
	move.w	(sp)+,d0
	tst.b	d0
	bne	1f
	lea	ACCS,a2			! N=0
	bra	3f
1:	sub.b	#1,d0
	beq	3f
	move.l	a2,d3
	sub.l	#ACCS,d3		! length
	beq	3f			! NULL STRING
2:	lea	ACCS,a0
	move.w	d3,d2
4:	move.b	(a0)+,(a2)+
	cmp.l	#ACCS+256,a2
	bcs	5f
	move.b	#19,d4
	bra	ERROR			! "String too long"
5:	sub.w	#1,d2
	bne	4b
	sub.b	#1,d0
	bne	2b
3:	move.b	#0x80,d4
	rts

! SUBROUTINES
!
! TEST - Test d0 for zero: Z set & d4 = 0 if zero
TEST:	tst.l	d0
	sne	d4
	rts

! DECODE - Decode line number in pseudo-binary.
!   Inputs:  a4 = Text pointer (after TLINO).
!   Outputs: d0.l = line number, d1.b = 0, a4 += 3
!   Destroys: d4, d7
DECODE:	move.b	(a4)+,d4
	move.b	d4,d7
	lsl.b	#2,d7
	and.b	#0xC0,d7
	move.b	(a4)+,d0
	eor.b	d7,d0			! L
	move.b	d4,d7
	lsl.b	#4,d7
	and.b	#0xC0,d7
	move.b	(a4)+,d4
	eor.b	d4,d7			! H
	and.l	#0xFF,d0
	lsl.w	#8,d7
	or.w	d7,d0
	clr.b	d1
	clr.b	d4
	rts

! HEXSTR - convert numeric value to HEX string.
!   Inputs:  d0/d1 = integer or floating-point number
!   Outputs: String in string accumulator, a2 = end.
HEXSTS:	add.l	#1,a4			! SKIP TILDE
	bsr	ITEMN
	bsr	HEXSTR
	move.b	#0x80,d4
	rts

HEXSTR:	bsr	SFIX
	lea	ACCS,a2
	move.w	#7,d2			! 8 digits
	clr.b	d5			! no digit yet
1:	rol.l	#4,d0
	move.b	d0,d4
	and.b	#0x0F,d4
	tst.w	d2
	beq	2f			! (the last digit always)
	tst.b	d5
	bne	2f
	tst.b	d4
	beq	3f			! leading zero
2:	move.b	#1,d5
	add.b	#'0',d4
	cmp.b	#'9'+1,d4
	bcs	4f
	add.b	#7,d4
4:	move.b	d4,(a2)+
3:	dbra	d2,1b
	rts

! STR$ - convert numeric value to ASCII string (G9 format unless the
! STR$ flag, byte 3 of @%, is set).
STRS:	bsr	NXT
	cmp.b	#'~',d4
	beq	HEXSTS
	bsr	ITEMN
	lea	G9-1,a5			! G9 FORMAT
	tst.b	STAVAR+3
	beq	STR0
STR:	lea	STAVAR,a5
STR0:	lea	ACCS,a2
	move.b	#37,d4
	bsr	FPP
	bcs	ERROR
	btst	#0,2(a5)		! E format: pad the exponent
	beq	2f			! with spaces to 4 characters
	move.b	d1,d7			! (d1 = position of the 'E')
	add.b	#4,d7
1:	move.l	a2,d6
	sub.l	#ACCS,d6
	cmp.b	d7,d6
	beq	2f
	move.b	#' ',(a2)+		! TRAILING SPACE
	bra	1b
2:	move.b	#0x80,d4		! STRING MARKER
	rts

	.sect	.rom
	.data1	0
G9:	.data1	9, 0
	.align	2
	.sect	.text

! SCP - STRING COMPARE
! Compare string (a2) length d5.b with string (a3) length d3.b.
! Result preset to false (d0 = 0), flags Z and C as the Z80.
SCP:	bsr	SCP0
	scs	d7
	seq	d2
	bsr	ZERO
	tst.b	d2
	beq	1f
	move.w	#CC_Z,ccr
	rts
1:	tst.b	d7
	beq	2f
	move.w	#CC_C,ccr
	rts
2:	move.w	#0,ccr
	rts

ZERO:	clr.l	d0
	clr.b	d1
	clr.b	d4
	rts

! SCP0: B = d5 (length of (a2)), C = d3 (length of (a3))
SCP0:	add.b	#1,d5
	add.b	#1,d3
SCP1:	sub.b	#1,d5
	beq	SCP2
	sub.b	#1,d3
	beq	SCP3
	move.b	(a2)+,d7
	cmp.b	(a3)+,d7
	beq	SCP1
	rts				! NZ, C as the compare
SCP2:	sub.b	#1,d3
	bne	1f
	move.w	#CC_Z,ccr		! equal
	rts
1:	move.w	#CC_C,ccr		! (a2) shorter
	rts
SCP3:	move.w	#0,ccr			! (a3) shorter
	rts

! PUSHS - SAVE STRING ON STACK.
!   Inputs:  String in string accumulator, a2 = end.
!            d4.b - saved on stack (in the frame word).
!   Outputs: on the stack: the string padded to an even length, and on
!            top the word (d4 << 8) | length.
!   Destroys: d5, d7, a0, a1
PUSHS:	bsr	CHECK
	move.l	(sp)+,a1		! RETURN ADDRESS
	move.l	a2,d5
	sub.l	#ACCS,d5		! length
	move.w	d5,d7
	add.w	#1,d7
	and.w	#0xFFFE,d7
	sub.w	d7,sp
	lea	ACCS,a0
	move.l	sp,a2
	tst.w	d5
	beq	1f
	move.w	d5,d7
	sub.w	#1,d7
2:	move.b	(a0)+,(a2)+		! COPY TO STACK
	dbra	d7,2b
1:	move.b	d4,-(sp)		! frame word: d4.b, length
	move.b	d5,1(sp)
	move.l	a0,a2
	bsr	CHECK
	jmp	(a1)			! "RETURN"

! POPS - RESTORE STRING FROM STACK.
!   Inputs:  d5.b = string length (the frame word already popped).
!   Outputs: String in string accumulator, a2 = end.
!   Destroys: d7, a0, a1
POPS:	move.l	(sp)+,a1		! RETURN ADDRESS
	lea	ACCS,a2
	move.l	sp,a0
	clr.w	d7
	move.b	d5,d7
	beq	POPS1			! ZERO LENGTH
	sub.w	#1,d7
1:	move.b	(a0)+,(a2)+		! COPY FROM STACK
	dbra	d7,1b
POPS1:	clr.w	d7
	move.b	d5,d7
	add.w	#1,d7
	and.w	#0xFFFE,d7
	add.w	d7,sp
	jmp	(a1)			! "RETURN"

! BINDIG - d4.b = value of the binary digit at (a4), NC; C if none
BINDIG:	move.b	(a4),d4
	sub.b	#'0',d4
	bcs	1f
	cmp.b	#2,d4
	bcc	2f
	move.w	#0,ccr			! NC: digit
	rts
2:	move.w	#CC_C,ccr
1:	rts

HEXDIG:	move.b	(a4),d4
	cmp.b	#'0',d4
	bcs	2f
	cmp.b	#'9'+1,d4
	bcs	1f
	cmp.b	#'A',d4
	bcs	2f
	sub.b	#'A'-10,d4
	cmp.b	#16,d4
	bcc	2f
1:	move.w	#0,ccr
	rts
2:	move.w	#CC_C,ccr
	rts

! RELOPQ - Z if d4.b is < = or >; C if below '<'
RELOPQ:	cmp.b	#'>',d4
	bcc	1f
	cmp.b	#'=',d4
	bcc	1f
	cmp.b	#'<',d4
1:	rts

! SAVE - save the first operand of a binary operator (d4.b = operator
! character; SAVE1: d4.b = FPP op-code)
SAVE:	add.l	#1,a4
	and.b	#0x0F,d4
SAVE1:	tst.b	d6
	bmi	MISMAT
	move.l	(sp)+,a0
	move.l	d0,-(sp)
	move.w	d4,-(sp)		! operator
	move.w	d1,-(sp)		! exponent
	jmp	(a0)

! DOIT - pop the first operand and the operator, do the operation
DOIT:	tst.b	d6
	bmi	MISMAT
	move.l	(sp)+,a0		! RETURN ADDRESS
	move.l	d0,d2			! second operand
	move.b	d1,d3
	move.w	(sp)+,d1
	move.w	(sp)+,d4		! OPERATOR
	move.l	(sp)+,d0
	move.l	a0,-(sp)
	bsr	FPP
	bcs	ERROR1
	clr.b	d6			! TYPE
	move.b	(a4),d4
	rts

COMMA:	bsr	NXT
	add.l	#1,a4
	cmp.b	#',',d4
	bne	1f
	rts
1:	move.b	#5,d4
	bra	ERROR1			! "Missing ,"

BRAKET:	bsr	NXT
	add.l	#1,a4
	cmp.b	#')',d4
	bne	1f
	rts
1:	move.b	#27,d4
ERROR1:	bra	ERROR			! "Missing )"

! DISPT2 - string comparison d4.b (0-5) via SOPTBL
DISPT2:	lea	SOPTBL,a0
	bra	DISPT0

! DISPAT - function token d4.b via FUNTBL
DISPAT:	lea	FUNTBL,a0
	sub.b	#FUNTOK,d4
DISPT0:	and.w	#0xFF,d4
	lsl.w	#2,d4
	move.l	0(a0,d4.w),a0
	jmp	(a0)			! OFF TO ROUTINE

! STOREA - store the element on the temporary stack (a3) to the
! destination array element (a5), according to the operator.
!   d5.w = type << 8 | operator
!   Outputs: d7.l = element size
STOREA:	movem.l	d5/a3/a5,-(sp)
	move.w	d5,d4
	lsr.w	#8,d4			! type
	move.l	a3,a5
	tst.b	d4
	bmi	STORA1
	bsr	LOADN
	move.l	8(sp),a5
	bsr	MODIFY
	movem.l	(sp)+,d5/a3/a5
	clr.l	d7
	move.w	d5,d7
	lsr.w	#8,d7
	rts

STORA1:	bsr	LOADS
	move.l	8(sp),a5
	move.l	(sp),d5
	bsr	MODIFS
	movem.l	(sp)+,d5/a3/a5
	move.l	#6,d7
	rts

! Assign to whole array:
!  array1() = array expression
!  array1() = n1,n2,n3,n4...
!  array1() = n (n copied into all elements)
!   Inputs: d5.w = type << 8 | opcode (type 65, 68, 69, 193)
!           a3 = a5 = VARPTR, a4 = text pointer
LETARR:	bclr	#14,d5			! Lose array marker
	move.w	d5,-(sp)		! Save type & opcode
	bsr	GETAR1			! Get and check indirect link
	bsr	ARRLEN			! d2 = elements, a3 addresses first
	move.w	(sp)+,d5
	move.l	d2,-(sp)		! number of elements
	move.w	d5,d4
	lsr.w	#8,d4			! type
	bsr	X14OR5			! d2 = size in bytes
	move.l	a3,a5			! first element
	add.l	#1,d2
	and.b	#0xFE,d2		! (even)
! (sp) = number of elements, d2 = size in bytes, d5 = type & opcode,
! a5 = address of first element.  Allocate space on stack and zero it:
	move.l	sp,d7
	sub.l	d2,d7
	bcs	1f
	move.l	FREE,d0
	add.l	#256,d0			! Safety margin
	cmp.l	d0,d7
	bcc	2f
1:	clr.b	d4
	bra	ERROR1			! 'No room'
2:	move.l	(sp)+,d0		! number of elements
	move.l	d7,sp
	move.l	sp,a0
3:	clr.b	(a0)+			! Clear allocated stack
	sub.l	#1,d2
	bne	3b
	move.l	d0,d2			! elements
	move.l	sp,a3			! temporary space
	move.l	a0,-(sp)		! where sp must go back to
	bsr	EXPRA
	move.l	(sp)+,sp		! Update stack pointer
	bra	XEQ

! EXPRA - Evaluate array expression, strictly left-to-right;
! Note: String array arithmetic (concatenation) is not supported because
! it would require a way of recovering freed string space.
!   Inputs: d2.l = number of elements
!           d5.w = type & opcode
!           a3 = address of temporary stack space
!           a5 = address of first element of array
EXPRA:	move.b	#'=',d4
	sub.l	#1,a4
EXPRA1:	add.l	#1,a4
	movem.l	d2/d5/a3/a5,-(sp)
	move.b	d4,d5			! Operator
	bsr	ITEMA
	movem.l	(sp)+,d2/d5/a3/a5
	bsr	NXT
	cmp.b	#',',d4			! List?
	beq	EXPRA3
	bsr	TERMQ
	bne	EXPRA1
! Update destination array from stack:
EXPRA2:	move.l	d2,-(sp)
	bsr	STOREA			! (a5) <- (a3)
	add.l	d7,a3
	add.l	d7,a5
	move.l	(sp)+,d2
	sub.l	#1,d2
	bne	EXPRA2
	rts

! Update destination array from list (n.b. not transferred via stack):
EXPRA3:	move.l	d2,-(sp)
	bsr	STOREA			! (a5) <- (a3)
EXPRA4:	add.l	#1,a4			! Bump past comma
	add.l	d7,a3
	add.l	d7,a5
	move.l	(sp)+,d2
	sub.l	#1,d2
	bne	1f
	rts
1:	movem.l	d2/d5/a3/a5,-(sp)
	btst	#15,d5
	bne	EXPRA5
	bsr	EXPRN
	move.l	12(sp),a5
	move.l	4(sp),d5
	bsr	MODIFY
	bra	EXPRA6
EXPRA5:	bsr	EXPRS
	move.l	12(sp),a5
	move.l	4(sp),d5
	bsr	MODIFS
EXPRA6:	movem.l	(sp)+,d2/d5/a3/a5
	move.l	#6,d7
	btst	#15,d5
	bne	EXPRA7
	clr.l	d7
	move.w	d5,d7
	lsr.w	#8,d7
EXPRA7:	bsr	NXT
	cmp.b	#',',d4
	bne	1f
	move.l	d2,-(sp)
	bra	EXPRA4
1:	rts				! (remaining elements unchanged)

! ITEMA: evaluate and operate on array item
!   Inputs: d5.w = type << 8 | operator ('=' for first item)
!           d2.l = number of elements
!           a3 = pointer to destination on stack
!           a4 = text pointer
!   Outputs: a4 updated
ITEMA:	bsr	NXT
	movem.l	d2/d5/a3/a4,-(sp)	! In case normal expression
	cmp.b	#'-',d4
	bne	ITEMA1			! Not unary minus
	cmp.b	#'=',d5
	bne	ITEMA1			! Not unary minus
	add.l	#1,a4			! Bump past '-'
	bsr	NXT
	move.b	#'-',d5			! Unary minus
ITEMA1:	move.w	d5,-(sp)		! Type and operator
	bsr	GETVAR
	movem.w	(sp)+,d5		! (movem: flags kept)
	bne	ITEMA4			! Non-array expression
	btst	#6,d4
	beq	ITEMA4			! Not a whole array
	bclr	#6,d4
	move.w	d5,d7
	lsr.w	#8,d7
	cmp.b	d7,d4
	bne	MISMAT			! 'Type mismatch'
	move.w	d5,-(sp)
	bsr	GETAR1
	bsr	ARRLEN			! d2 = elements, a3 = source
	move.w	(sp)+,d5
	move.l	a3,a5			! Pointer to source
	bsr	NXT
	cmp.b	#'.',d4
	beq	ARRDOT			! Dot product
	cmp.l	(sp),d2			! Same number of elements?
	bne	MISMAT			! 'Type mismatch'
	move.l	8(sp),a3		! Pointer to destination
	add.l	#16,sp			! (the saved values)
	btst	#15,d5
	bne	ITEMA3
! Process numeric array item:
ITEMA2:	movem.l	d2/d5/a3/a5,-(sp)
	move.w	d5,d4
	lsr.w	#8,d4
	bsr	LOADN			! source element
	move.l	8(sp),a5		! destination
	bsr	MODIFY
	movem.l	(sp)+,d2/d5/a3/a5
	clr.l	d7
	move.w	d5,d7
	lsr.w	#8,d7
	add.l	d7,a5
	add.l	d7,a3
	sub.l	#1,d2
	bne	ITEMA2
	rts

! Process string array item (just copy descriptors):
ITEMA3:	mulu	#6,d2
1:	move.b	(a5)+,(a3)+
	sub.l	#1,d2
	bne	1b
	rts

! Process numeric non-array item:
ITEMA4:	movem.l	(sp)+,d2/d5/a3/a4	! original operator, text pointer
	btst	#15,d5
	bne	ITEMA5
	movem.l	d2/d5/a3,-(sp)
	bsr	EXPR45			! (should be EXP345)
	movem.l	(sp)+,d2/d5/a5
ITEMA7:	movem.l	d0-d2/d5/a5,-(sp)
	bsr	MODIFY
	movem.l	(sp)+,d0-d2/d5/a5
	clr.l	d7
	move.w	d5,d7
	lsr.w	#8,d7
	add.l	d7,a5
	sub.l	#1,d2
	bne	ITEMA7			! Copy into every element!
	rts

! Process string non-array item:
ITEMA5:	movem.l	d2/a3,-(sp)
	bsr	EXPRS
	move.l	a2,d5
	sub.l	#ACCS,d5		! length
	lea	ACCS,a0
	lea	BUFFER,a1
	move.w	d5,d7
	beq	2f
	sub.w	#1,d7
1:	move.b	(a0)+,(a1)+
	dbra	d7,1b
2:	movem.l	(sp)+,d2/a5
	lea	BUFFER,a0
	clr.b	d6
ITEMA6:	bsr	STDESC			! descriptor: length d5, at BUFFER
	add.l	#6,a5
	sub.l	#1,d2
	bne	ITEMA6			! Copy into every element!
	rts

! Array dot-product:  dest() = src1() . src2()
! dest(n) = SUM(k) src1(row, k) * src2(k, col), row = n DIV C2,
! col = n MOD C2, where K = the last dimension of src1 and C2 = the last
! dimension of src2 (1 if src2 is one-dimensional); accumulated with FPP
! in the order of the Z80 code.
!   d5.w = type & operator, d2 = elements of src1, a5 = src1 data;
!   (sp): the values saved by ITEMA (d2 = destination elements, d5,
!   a3 = destination, a4)
ARRDOT:	add.l	#1,a4			! Bump past dot
	btst	#15,d5
	bne	MISMAT			! 'Type mismatch'
	move.l	(sp),dotn		! elements in destination
	move.l	8(sp),dotdst		! destination data
	add.l	#16,sp
	move.w	d5,d4
	lsr.w	#8,d4
	move.b	d4,dottyp
	and.w	#0x0F,d4
	move.w	d4,dotsiz		! element size
	move.l	a5,dots1		! src1 data
	clr.l	d7			! K = last dimension of src1
	move.b	-1(a5),d7
	lsl.w	#8,d7
	move.b	-2(a5),d7
	move.l	d7,dotk
	bsr	GETARR			! src2: a3 = block
	move.b	(a3),d6			! its number of dimensions
	bsr	ARRLEN
	move.l	a3,dots2		! src2 data
	move.l	#1,d7			! C2
	cmp.b	#1,d6
	beq	1f
	move.b	-1(a3),d7
	lsl.w	#8,d7
	move.b	-2(a3),d7
1:	move.l	d7,dotc2
	clr.l	dotrow
	clr.l	dotcol
OUTER:	tst.l	dotn
	beq	9f
	bsr	ZERO			! Zero accumulator
	clr.l	dotkk
INNER:	move.l	dotkk,d7
	cmp.l	dotk,d7
	bcc	5f
	movem.l	d0-d1,-(sp)		! Save accumulator
	move.l	dotrow,d2		! src1(row, k)
	mulu	dotk+2,d2
	add.l	dotkk,d2
	mulu	dotsiz,d2
	move.l	dots1,a5
	add.l	d2,a5
	move.b	dottyp,d4
	bsr	LOADN
	move.l	dotkk,d2		! src2(k, col)
	mulu	dotc2+2,d2
	add.l	dotcol,d2
	mulu	dotsiz,d2
	move.l	dots2,a5
	add.l	d2,a5
	move.b	dottyp,d4
	bsr	DLOADN
	move.b	#10,d4
	bsr	FPP			! Multiply
	bcs	ERROR
	move.l	d0,d2
	move.b	d1,d3
	movem.l	(sp)+,d0-d1		! accumulator
	move.b	#11,d4
	bsr	FPP			! Accumulate
	bcs	ERROR
	add.l	#1,dotkk
	bra	INNER
5:	move.l	dotdst,a5		! Save to destination
	move.b	dottyp,d4
	bsr	STOREN
	clr.l	d7
	move.w	dotsiz,d7
	add.l	d7,dotdst
	add.l	#1,dotcol		! next column / row
	move.l	dotcol,d7
	cmp.l	dotc2,d7
	bcs	6f
	clr.l	dotcol
	add.l	#1,dotrow
6:	sub.l	#1,dotn
	bra	OUTER
9:	rts

	.sect	.bss
	.align	4
dotn:	.space	4			! ARRDOT state
dotdst:	.space	4
dots1:	.space	4
dots2:	.space	4
dotk:	.space	4
dotc2:	.space	4
dotrow:	.space	4
dotcol:	.space	4
dotkk:	.space	4
dotsiz:	.space	2
dottyp:	.space	2
