#
! math.s - BBC BASIC 68k floating point package (from MATH.Z80).
!
! (C) Copyright R.T. Russell 1986-2025 (Z80 original); 68000 translation
! for Minix on the rosco_m68k.  See CONVENTIONS.md.
!
! The results are bit-for-bit those of the Z80 package: the same
! truncation, guard bits and rounding decisions, checked against the Z80
! BBC BASIC under RunCPM (test/mathtest, tools/mathref.py).
!
! Number format (unchanged from the Z80):
!   float:   32-bit sign-magnitude normalised mantissa (bit 31 = sign,
!            replacing the implied 1) + 8-bit excess-128 exponent;
!            value = (m | 2^31) / 2^31 * 2^(e-128), e = 0 never a float
!   integer: 32-bit two's complement, exponent byte 0
!
! Registers (Z80 equivalents):
!   d0.l = HLH'L'  accumulator mantissa / integer
!   d1.b = C       accumulator exponent
!   d2.l = DED'E'  second operand
!   d3.b = B       second operand exponent
!   d4.b = A       op-code in, error number / result marker out
!   d5.w = B'C'    guard bits below d0 (FADD, FIX, MOD48)
!   d6   = A'      (FIX sticky byte; saved result sign in FMUL/FDIV)
!   d7, a0-a3      scratch
!   a4   = IY      saved stack pointer for error exits (preserved)
!   a5   = IX      @% (STR), string (VAL); preserved by FPP except VAL
!
! FPP - floating point entry:
!   Inputs:  d4.b = operation code, d0/d1 = argument 1, d2/d3 = argument 2
!   Outputs: d0/d1 = result, d4.b = result marker
!            CCR Z, NC if OK; NZ, C and d4.b = error number on error
!   Destroys: d2-d7, a0-a3

#include "bbc.h"

	.sect	.text
	.sect	.rom
	.sect	.data
	.sect	.bss

	.define	FPP

BADOP	= 1		! Bad operation code
DIVBY0	= 18		! Division by zero
TOOBIG	= 20		! Too big
NGROOT	= 21		! Negative root
LOGRNG	= 22		! Log range
ACLOST	= 23		! Accuracy lost
EXPRNG	= 24		! Exp range

NFUNCS	= 48		! DTABLE entries before RTABLE

! PUSH5: push d0/d1 (6 bytes: exponent word, then mantissa)
! POP5:  pop into d2/d3, A = C (as the Z80 POP5)
#define	PUSH5	move.l d0,-(sp); move.w d1,-(sp)
#define	POP5	move.w (sp)+,d3; move.l (sp)+,d2; move.b d1,d4

	.sect	.text

FPP:
	move.l	a5,-(sp)
	move.l	a4,-(sp)
	move.l	sp,a4			! for ERROR
	move.w	d4,-(sp)
	bsr	OP
	cmp.b	#36,1(sp)		! VAL returns IX updated
	bne	1f
	move.l	a5,4(a4)
1:	add.l	#2,sp
	SETGOOD
EXIT:
	move.l	(sp)+,a4		! movea: flags unchanged
	move.l	(sp)+,a5
	rts

BAD:	move.b	#BADOP,d4
! ERROR - error exit from any depth; d4.b = error number
ERROR:	move.l	a4,sp
	SETBAD
	bra	EXIT

! Perform operation or function: d4.b = op-code
OP:	cmp.b	#NFUNCS,d4
	bcc	BAD
	cmp.b	#16,d4
	bcc	DISPAT
	move.b	d3,d7
	or.b	d1,d7			! both integer?
	beq	DISPAT
	add.b	#NFUNCS,d4		! FLOATA: use the RTABLE routine
	move.w	d4,-(sp)
	bsr	FLOAT2			! float both
	move.w	(sp)+,d4
DISPAT:	clr.w	d7
	move.b	d4,d7
	add.b	d4,d4			! A = op-code * 2, as the Z80
	lsl.w	#2,d7
	lea	DTABLE,a0
	move.l	0(a0,d7.w),a0
	jmp	(a0)

	.sect	.rom
	.align	4
DTABLE:	.data4	IAND		! 0  AND (INTEGER)
	.data4	IBDIV		! 1  DIV
	.data4	IEOR		! 2  EOR
	.data4	IMOD		! 3  MOD
	.data4	IOR		! 4  OR
	.data4	ILE		! 5  <=
	.data4	INE		! 6  <>
	.data4	IGE		! 7  >=
	.data4	ILT		! 8  <
	.data4	IEQ		! 9  =
	.data4	IMUL		! 10 *
	.data4	IADD		! 11 +
	.data4	IGT		! 12 >
	.data4	ISUB		! 13 -
	.data4	IPOW		! 14 ^
	.data4	IDIV		! 15 /
	.data4	ABS		! 16 ABS
	.data4	ACS		! 17 ACS
	.data4	ASN		! 18 ASN
	.data4	ATN		! 19 ATN
	.data4	COS		! 20 COS
	.data4	DEG		! 21 DEG
	.data4	EXP		! 22 EXP
	.data4	INT		! 23 INT
	.data4	LN		! 24 LN
	.data4	LOG		! 25 LOG
	.data4	CPL		! 26 NOT
	.data4	RAD		! 27 RAD
	.data4	SGN		! 28 SGN
	.data4	SIN		! 29 SIN
	.data4	SQR		! 30 SQR
	.data4	TAN		! 31 TAN
	.data4	ZERO		! 32 ZERO
	.data4	FONE		! 33 FONE
	.data4	TRUE		! 34 TRUE
	.data4	PI		! 35 PI
	.data4	VAL		! 36 VAL
	.data4	STR		! 37 STR$
	.data4	SFIX		! 38 FIX
	.data4	SFLOAT		! 39 FLOAT
	.data4	FTEST		! 40 TEST
	.data4	FCOMP		! 41 COMPARE
	.data4	BAD		! 42 Reserved for Z88
	.data4	BAD		! 43 Reserved for Z88
	.data4	ISHL		! 44 <<
	.data4	ISHX		! 45 <<<
	.data4	ISAR		! 46 >>
	.data4	ISHR		! 47 >>>
RTABLE:	.data4	FAND		! AND (FLOATING-POINT)
	.data4	FBDIV		! DIV
	.data4	FEOR		! EOR
	.data4	FMOD		! MOD
	.data4	FOR		! OR
	.data4	FLE		! <=
	.data4	FNE		! <>
	.data4	FGE		! >=
	.data4	FLT		! <
	.data4	FEQ		! =
	.data4	FMUL		! *
	.data4	FADD		! +
	.data4	FGT		! >
	.data4	FSUB		! -
	.data4	FPOW		! ^
	.data4	FDIV		! /

	.sect	.text

! ARITHMETIC AND LOGICAL OPERATORS:
! All take two arguments, in d0/d1 & d2/d3.  Output in d0/d1.

FAND:	bsr	FIX2
IAND:	and.l	d2,d0
	rts

FEOR:	bsr	FIX2
IEOR:	eor.l	d2,d0
	rts

FOR:	bsr	FIX2
IOR:	or.l	d2,d0
	rts

! FMOD - Floating-point remainder.
! IMOD - Integer remainder (sign of the dividend).
!   Outputs: d0 = remainder, d2 = |quotient|, d6 = sign of quotient (bit 31)
FMOD:	bsr	FIX2
IMOD:	move.l	d0,d6
	eor.l	d2,d6			! DIV result sign
	move.l	d0,-(sp)		! dividend sign
	bsr	ABS2			! d0 = 0, d2 = |dividend|, d7 = |divisor|
	move.w	#32,d3			! 33 steps, as A = -33
	bsr	DIVA			! d2 = quotient, d0 = remainder
	clr.b	d1			! integer marker
	move.b	#0,d4
	tst.l	(sp)+
	bpl	1f
	bra	NEGATE
1:	rts

! BDIV - Integer division.
FBDIV:	bsr	FIX2
IBDIV:	bsr	IMOD
	bsr	SWAP
	clr.b	d1
	tst.l	d6
	bmi	NEGATE
	rts

! ISUB - Integer subtraction.
! FSUB - Floating point subtraction with rounding.
ISUB:	sub.l	d2,d0
	bvs	1f
	rts
1:	add.l	d2,d0
	bsr	FLOAT2
FSUB:	bchg	#31,d2			! change sign then add
	bra	FADD

! RSUB - Reverse subtract.
RSUB:	bchg	#31,d0
	bra	FADD

! IADD - Integer addition.
! FADD - Floating point addition with rounding.
IADD:	add.l	d2,d0
	bvs	1f
	rts
1:	sub.l	d2,d0
	bsr	FLOAT2
FADD:	tst.b	d3
	bne	1f
	rts				! arg 2 zero
1:	tst.b	d1
	beq	SWAP			! arg 1 zero
	clr.w	d5			! B'C' = 0
	move.l	d0,d7
	eor.l	d2,d7
	move.l	d7,-(sp)		! XOR signs
	move.b	d3,d4
	cmp.b	d1,d4			! compare exponents
	beq	2f
	bcc	1f
	bsr	SWAP			! make d2/d3 largest
1:	move.b	d3,d4
	bsr	FIX			! align (sets the implied 1)
	bra	3f
2:	bset	#31,d0			! implied 1
3:	move.l	(sp)+,d7
	move.l	d2,d4
	rol.l	#8,d4			! A = sign of larger
	bset	#31,d2			! implied 1
	tst.l	d7
	bmi	FADD3			! signs different
	add.l	d2,d0
	bcc	4f
	bsr	DIV2			! normalise
4:	bset	#31,d0
	bra	FADD4

FADD3:	sub.l	d2,d0
	bcc	5f
	bsr	NEG			! negate d0:d5, complement A
5:	bsr	FLO48
	not.b	d4			! change result sign
FADD4:	cmp.w	#0x8000,d5		! guard bits against a half
	bhi	6f
	bne	7f
	bset	#0,d0			! ODD: round unbiassed
	bra	7f
6:	bsr	ADD1			! round up
	bcc	7f
	bsr	INCC
7:	bclr	#31,d0
	tst.b	d1
	beq	ZERO
	tst.b	d4			! result sign
	bpl	8f
	bset	#31,d0
8:	rts

! IDIV - Integer division.
! FDIV - Floating point division with rounding.
IDIV:	bsr	FLOAT2
FDIV:	tst.b	d3
	bne	1f
	move.b	#DIVBY0,d4
	bra	ERROR			! "Division by zero"
1:	tst.b	d1
	bne	2f
	rts
2:	move.l	d0,d6
	eor.l	d2,d6			! result sign
	bset	#31,d2			! replace implied 1's
	bset	#31,d0
	move.w	d1,-(sp)		! save exponents
	move.w	d3,-(sp)
	move.l	d2,d7			! divisor
	clr.l	d2
	move.w	#31,d3			! 32 steps
	bsr	DIVA			! d2 = quotient, d0 = remainder
	clr.b	d4
	tst.l	d2
	bmi	3f
	clr.w	d3
	move.w	#0,ccr
	bsr	DIVB			! normalise
	move.b	#1,d4			! and inc A
3:	exg	d0,d2			! d0 = quotient, d2 = remainder
	swap	d2			! remainder MSW ...
	move.l	d7,d3
	swap	d3
	lsr.w	#1,d3			! ... against divisor/2 MSW
	cmp.w	d3,d2
	bhi	4f
	bne	5f
	bset	#0,d0			! ODD
	bra	5f
4:	bsr	ADD1			! round up
	scs	d7
	bra	6f
5:	clr.b	d7
6:	move.w	(sp)+,d3		! restore exponents
	move.w	(sp)+,d1
	tst.b	d7
	beq	7f
	bsr	INCC
7:	clr.w	d7			! new exponent C - B - n + 128
	move.b	d1,d7
	clr.w	d2
	move.b	d3,d2
	sub.w	d2,d7
	and.w	#1,d4
	sub.w	d4,d7
	add.w	#128,d7
	bra	CHKOVF

! IMUL - Integer multiplication.
IMUL:	move.l	d0,d6
	eor.l	d2,d6			! result sign
	bsr	ABS2			! d7 = |arg 2|, d2 = |arg 1|
	move.l	d2,d0
	move.l	d7,d2
	bsr	MUL64			! d0:d2 = product
	tst.l	d0
	bne	2f			! too big
	tst.l	d2
	bmi	2f
	move.l	d2,d0
	clr.b	d1			! integer marker
	move.l	d6,d4
	rol.l	#8,d4
	tst.l	d6
	bmi	NEGATE
	rts
2:	move.b	#191,d1			! preset exponent
3:	sub.b	#1,d1
	add.l	d2,d2			! normalise
	addx.l	d0,d0
	bpl	3b
	move.l	d6,d4
	rol.l	#8,d4
	tst.l	d6
	bmi	4f
	bclr	#31,d0			! positive
4:	rts

! FMUL - Floating point multiplication with rounding.
FMUL:	tst.b	d3
	beq	ZERO
	tst.b	d1
	bne	1f
	rts
1:	move.l	d0,d6
	eor.l	d2,d6			! result sign
	bset	#31,d2			! replace implied 1's
	bset	#31,d0
	bsr	MUL64			! d0:d2 = product
	clr.b	d4
	tst.l	d0
	bmi	2f
	add.l	d2,d2			! < 2^63: take bits 62-31
	addx.l	d0,d0
	bra	3f
2:	move.b	#1,d4			! normalised, inc A
3:	swap	d2			! guard: MSW of the low half
	cmp.w	#0x8000,d2
	bhi	4f
	bne	5f
	bset	#0,d0			! ODD
	bra	5f
4:	bsr	ADD1			! round up
	bcc	5f
	bsr	INCC
5:	clr.w	d7			! new exponent C + B + n - 128
	move.b	d1,d7
	clr.w	d2
	move.b	d3,d2
	add.w	d2,d7
	and.w	#1,d4
	add.w	d4,d7
	sub.w	#128,d7
! CHKOVF - d7.w = new exponent: <= 0 underflow, > 255 overflow
CHKOVF:	tst.w	d7
	ble	ZERO			! underflow
	cmp.w	#255,d7
	bgt	OFLOW			! overflow
	move.b	d7,d1
	move.l	d6,d4
	rol.l	#8,d4			! A = sign
	bclr	#31,d0
	tst.l	d6
	bpl	1f
	bset	#31,d0
1:	rts

! MUL64 - unsigned 32 x 32 -> 64 bit multiply.
!   Inputs:  d0, d2
!   Outputs: d0 = high 32 bits, d2 = low 32 bits
!   Destroys: d7, a0-a3 (d1, d3-d6 preserved)
MUL64:	move.l	d1,a0
	move.l	d3,a1
	move.l	d4,a2
	move.l	d0,d7			! a = ah:al
	move.w	d7,d1
	mulu	d2,d1			! al*bl
	move.l	d7,d3
	swap	d3
	mulu	d2,d3			! ah*bl
	swap	d2
	move.w	d7,d4
	mulu	d2,d4			! al*bh
	swap	d7
	mulu	d7,d2			! ah*bh
	add.l	d4,d3			! middle sum
	bcc	1f
	add.l	#0x10000,d2
1:	move.l	d3,d4
	swap	d4
	clr.w	d4			! middle << 16
	clr.w	d3
	swap	d3			! middle >> 16
	add.l	d4,d1
	addx.l	d3,d2
	move.l	d2,d0
	move.l	d1,d2
	move.l	a0,d1
	move.l	a1,d3
	move.l	a2,d4
	rts

! IPOW - Integer involution.
!   The base is kept in a frame at a5: 0(a5) mantissa, 4(a5) exponent,
!   6(a5) bit counter.
IPOW:	bsr	SWAP			! d0 = power, d2 = base
	move.l	d0,-(sp)		! save sign
	bpl	IPOW0
	bsr	NEGATE
IPOW0:	move.b	d3,d1			! C = base exponent
	move.b	#32,d3			! loop counter
1:	add.l	d0,d0			! find the top bit
	bcs	IPOW2
	sub.b	#1,d3
	bne	1b
	add.l	#4,sp			! power 0:
	move.l	#1,d0			! result = 1
	clr.b	d1
	rts

IPOW2:	move.l	(sp)+,d4		! sign of power
	exg	d0,d2			! d0 = base, d2 = remaining bits
	move.w	d3,-(sp)		! frame: counter,
	move.w	d1,-(sp)		! base exponent,
	move.l	d0,-(sp)		! base mantissa
	move.l	sp,a5
	tst.l	d4
	bpl	IPOW4
	move.l	d2,-(sp)		! negative power: use 1/base
	bsr	SFLOAT
	bsr	RECIP
	move.l	d0,(a5)
	move.b	d1,5(a5)
	move.l	(sp)+,d2
	bra	IPOW4

IPOW3:	add.l	d2,d2			! next bit of the power
	scs	d7
	move.l	d2,-(sp)
	move.w	d7,-(sp)
	bsr	COPY
	move.b	#10,d4
	bsr	OP			! square
	move.w	(sp)+,d7
	move.l	(a5),d2
	move.b	5(a5),d3
	tst.b	d7
	beq	1f
	move.b	#10,d4
	bsr	OP			! multiply by x
1:	move.l	(sp)+,d2
IPOW4:	sub.b	#1,7(a5)
	bne	IPOW3
	add.l	#8,sp			! drop the frame
	rts

FPOW0:	add.l	#6,sp			! drop the power (PUSH5)
	bra	IPOW0

! FPOW - Floating-point involution.
FPOW:	move.l	d2,-(sp)		! save sign of power
	bsr	SWAP			! d0 = power, d2 = base
	PUSH5
	tst.b	d1
	beq	FPOW0			! power 0
	move.b	#1,d7			! carry for LN0 (Z80 "CP C")
	cmp.b	#158,d1
	bhi	FPOW1			! power >= 2^31
	move.b	#159,d4
	bsr	FIX
	tst.b	d6
	bpl	FPOW0			! integer power
	clr.b	d7			! carry from FIX
FPOW1:	bsr	SWAP
	bsr	LN0			! d7.b = carry in for ICP0
	POP5
	add.l	#4,sp			! sign
	bsr	FMUL
	bra	EXP0

! Integer and floating-point compare.  Result is TRUE (-1) or FALSE (0).
FLT:	bsr	FCP1
	bra	1f
ILT:	bsr	ICP1
1:	bcs	TRUE
	bra	ZERO

FGT:	bsr	FCP1
	bra	1f
IGT:	bsr	ICP1
1:	beq	ZERO
	bcs	ZERO
	bra	TRUE

FGE:	bsr	FCP1
	bra	1f
IGE:	bsr	ICP1
1:	bcs	ZERO
	bra	TRUE

FLE:	bsr	FCP1
	bra	1f
ILE:	bsr	ICP1
1:	beq	TRUE
	bcs	TRUE
	bra	ZERO

FNE:	bsr	FCP1
	bra	1f
INE:	bsr	ICP1
1:	beq	ZERO
	bra	TRUE

FEQ:	bsr	FCP1
	bra	1f
IEQ:	bsr	ICP1
1:	bne	ZERO
TRUE:	move.l	#-1,d0
	clr.b	d4
	clr.b	d1
	rts

! Integer shifts:
ISHX:
ISHL:	bsr	SHIFTS
	lsl.l	d7,d0
	rts

ISAR:	bsr	SHIFTS
	asr.l	d7,d0
	rts

ISHR:	bsr	SHIFTS
	lsr.l	d7,d0
	rts

! SHIFTS - shift count in d7.w: d2 if 0-255, else 32; capped at 32
!   (a shift by 32 or more gives the same result as 32 one-bit shifts)
SHIFTS:	bsr	FIX2
	move.l	d2,d7
	cmp.l	#32,d7
	bls	1f
	move.l	#32,d7
1:	rts

! FUNCTIONS:
! Result returned in d0/d1 (floating point), or d0 with C=0 (integer).

! ABS - Absolute value
ABS:	tst.l	d0
	bpl	1f			! positive/zero
	tst.b	d1
	beq	NEGATE			! integer
	bclr	#31,d0
1:	rts

! NOT - Complement integer.
CPL:	bsr	SFIX
	not.l	d0
	clr.b	d4			! numeric marker
	rts

! PI - Return PI (3.141592654)
PI:	move.l	#0x490FDAA2,d0
	move.b	#0x81,d1
	clr.b	d4
	rts

! DEG - Convert radians to degrees
DEG:	bsr	FPI180
	bsr	FMUL
	clr.b	d4
	rts

! RAD - Convert degrees to radians
RAD:	bsr	FPI180
	bsr	FDIV
	clr.b	d4
	rts

! 180/PI
FPI180:	bsr	SFLOAT
	move.l	#0x652EE0D3,d2
	move.b	#0x85,d3
	rts

! SGN - Return -1, 0 or +1
SGN:	bsr	TEST
	or.b	d1,d4
	bne	1f
	rts				! zero
1:	tst.l	d0
	bmi	TRUE			! -1
	bsr	ZERO
	bra	ADD1			! 1

! INT - Floor function
INT:	tst.b	d1
	bne	1f
	rts				! zero/integer
1:	move.b	#159,d4
	move.l	d0,d3
	rol.l	#8,d3			! B7 = sign bit
	bsr	FIX
	move.b	d6,d4
	and.b	d3,d4
	bpl	2f
	bsr	ADD1			! negative non-integer
2:	tst.b	d3
	bpl	3f
	bsr	NEGATE
3:	clr.b	d4
	clr.b	d1
	rts

! SQR - square root
SQR:	bsr	SFLOAT
SQR0:	tst.l	d0
	bpl	1f
	move.b	#NGROOT,d4
	bra	ERROR			! "-ve root"
1:	tst.b	d1
	bne	2f
	rts				! zero
2:	bset	#31,d0			! implied 1
	btst	#0,d1
	bne	3f
	bsr	DIV2			! make exponent odd
3:	move.b	d1,d7
	sub.b	#0x80,d7
	asr.b	#1,d7			! halve exponent
	add.b	#0x80,d7
	move.b	d7,d1
	move.w	d1,-(sp)		! save exponent
	move.l	d0,d2			! radicand
	clr.l	d0			! remainder
	clr.l	d7			! root
	move.b	#-31,d4
	bsr	SQRA			! root
	tst.l	d7
	bmi	4f
	bsr	SQRA			! normalise & inc A
4:	bsr	SQRB
	clr.w	d3
	move.w	#0,ccr			! clear carry
	bsr	DIVB
	add.b	#1,d4			! (the Z80 DIVB increments A)
	move.l	d7,d0
	btst	#0,d2			! LSB to carry
	beq	5f
	bsr	ADD1			! round up
	scs	d7
	bra	6f
5:	clr.b	d7
6:	move.w	(sp)+,d1		! restore exponent
	tst.b	d7
	beq	7f
	bsr	INCC
7:	btst	#0,d4
	beq	8f
	sub.b	#1,d1
8:	bclr	#31,d0			! positive
	clr.b	d4
	rts

! TAN - Tangent function
TAN:	bsr	SFLOAT
	PUSH5
	bsr	COS0
	POP5
	PUSH5
	bsr	SWAP
	bsr	SIN0
	POP5
	bsr	FDIV
	clr.b	d4			! numeric marker
	rts

! COS - Cosine function
COS:	bsr	SFLOAT
COS0:	bsr	SCALE
	swap	d2
	add.b	#2,d2			! octant + 2
	move.b	d2,d4
	swap	d2
	bra	SIN1

! SIN - Sine function
SIN:	bsr	SFLOAT
SIN0:	move.l	d0,-(sp)		! H7 = sign
	bsr	SCALE
	move.l	(sp)+,d4
	rol.l	#3,d4
	and.b	#4,d4
	move.l	d2,d7
	swap	d7
	eor.b	d7,d4			! octant (E = quotient)
SIN1:	move.w	d4,-(sp)		! octant
	bclr	#31,d0
	btst	#0,d4
	beq	1f
	bsr	PIBY4
	bsr	RSUB			! X = (PI/4) - X
	bra	2f
1:	bsr	PIBY4
2:	move.w	(sp),d4
	and.b	#3,d4
	beq	3f			! 0 and 3 (even parity): sine
	cmp.b	#3,d4
	bne	SIN2			! 1 and 2: cosine approximation
3:	PUSH5				! save X
	bsr	SQUARE			! push X*X
	lea	SINTAB,a0
	bsr	POLY
	add.l	#6,sp
	POP5
	bsr	FMUL
	bra	SIN3

SIN2:	bsr	SQUARE			! push X*X
	lea	COSTAB,a0
	bsr	POLY
	add.l	#6,sp
SIN3:	move.w	(sp)+,d4
	and.b	#4,d4
	beq	1f
	tst.b	d1
	beq	1f			! zero
	bset	#31,d0			! make negative
1:	rts

	.sect	.rom
SINTAB:	.data4	0x3611A8B7
	.data2	0x6D		! a(8)
	.data4	0xD005DE26
	.data2	0x73		! a(6)
	.data4	0x088880C0
	.data2	0x79		! a(4)
	.data4	0xAAAAAA9D
	.data2	0x7D		! a(2)
	.data4	0
	.data2	0x80		! a(0)
COSTAB:	.data4	0x4C78D571
	.data2	0x70		! b(8)
	.data4	0xB60394AF
	.data2	0x76		! b(6)
	.data4	0x2AAA9CC8
	.data2	0x7B		! b(4)
	.data4	0xFFFFFFDD
	.data2	0x7E		! b(2)
	.data4	0
	.data2	0x80		! b(0)
	.sect	.text

! Floating-point one:
FONE:	clr.l	d0
	move.b	#0x80,d1
	rts

DONE:	clr.l	d2
	move.b	#0x80,d3
	rts

PIBY4:	move.l	#0x490FDAA2,d2
	move.b	#0x7F,d3
	rts

! EXP - Exponential function
EXP:	bsr	SFLOAT
EXP0:	bsr	LN2			! LN(2)
	sub.b	#1,d2
	move.w	#0xD1CF,d5		! 0.6931471805599453
	move.l	d0,-(sp)		! H7 = sign
	bsr	MOD48			! "modulus"
	move.l	(sp)+,d4
	rol.l	#8,d4			! A = sign byte
	move.l	d2,d7
	swap	d7			! E = quotient
	tst.b	d7
	bpl	EXP1
	tst.b	d4
	bmi	ZERO
	move.b	#EXPRNG,d4
	bra	ERROR			! "Exp range"

EXP1:	and.b	#0x80,d4
	or.b	d7,d4
	move.w	d4,-(sp)		! integer part
	bclr	#31,d0
	PUSH5				! push X*LN(2)
	lea	EXPTAB,a0
	bsr	POLY
	add.l	#6,sp
	move.w	(sp)+,d4
	tst.b	d4
	bmi	1f
	move.w	d4,-(sp)
	bsr	RECIP			! X = 1/X
	move.w	(sp)+,d4
	bra	EXP4
1:	and.b	#0x7F,d4
	neg.b	d4
EXP4:	ext.w	d4			! new exponent C + k
	clr.w	d7
	move.b	d1,d7
	add.w	d4,d7
	tst.w	d7
	ble	ZERO			! underflow
	cmp.w	#255,d7
	bgt	OFLOW			! overflow
	move.b	d7,d1
	clr.b	d4			! numeric marker
	rts

	.sect	.rom
EXPTAB:	.data4	0x942E4072
	.data2	0x73		! a(7)
	.data4	0x2E4F6F65
	.data2	0x76		! a(6)
	.data4	0x88026D37
	.data2	0x79		! a(5)
	.data4	0x2AA0E512
	.data2	0x7B		! a(4)
	.data4	0xAAAA4F14
	.data2	0x7D		! a(3)
	.data4	0x7FFFFD56
	.data2	0x7E		! a(2)
	.data4	0xFFFFFFFE
	.data2	0x7F		! a(1)
	.data4	0
	.data2	0x80		! a(0)
	.sect	.text

RECIP:	bsr	DONE
RDIV:	bsr	SWAP
	bra	FDIV			! reciprocal

LN2:	move.l	#0x317217F8,d2		! LN(2)
	move.b	#0x7F,d3
	rts

! LN - Natural log.
LN:	bsr	SFLOAT
	clr.b	d7			! carry in for ICP0
! LN0 - d7.b = the Z80 carry flag on entry (used by ICP0)
LN0:	tst.l	d0
	bmi	1f
	tst.b	d1
	bne	2f
1:	move.b	#LOGRNG,d4
	bra	ERROR			! "Log range"
2:	move.l	#0x3504F333,d2		! SQR(2) 1.41421356237
	bsr	ICP0			! mantissa > SQR(2)?
	scs	d7
	move.b	d1,d4			! exponent
	move.b	#0x80,d1		! 1 <= X < 2
	tst.b	d7
	bne	LN4
	sub.b	#1,d1
	add.b	#1,d4
LN4:	move.w	d4,-(sp)		! save exponent
	bsr	RATIO			! X = (X-1)/(X+1)
	PUSH5
	bsr	SQUARE			! push X*X
	lea	LNTAB,a0
	bsr	POLY
	add.l	#6,sp
	POP5
	bsr	FMUL
	move.w	(sp)+,d7		! exponent
	PUSH5
	bsr	ZERO
	move.b	d7,d4			! (kept in A' on the Z80)
	sub.b	#0x80,d4
	beq	LN3
	scs	d7			! negative
	bcc	LN1
	neg.b	d4
LN1:	move.b	d4,d0
	ror.l	#8,d0			! H = |exponent|
	move.b	#0x87,d1
	move.b	d7,-(sp)
	bsr	FLOAT
	bclr	#31,d0
	bsr	LN2
	bsr	FMUL
	move.b	(sp)+,d7
	tst.b	d7
	beq	LN3
	bset	#31,d0
LN3:	POP5
	bsr	FADD
	clr.b	d4
	rts

	.sect	.rom
LNTAB:	.data4	0x74FBCC48
	.data2	0x7D		! a(9)
	.data4	0x11FFAEAF
	.data2	0x7E		! a(7)
	.data4	0x4CCDD98C
	.data2	0x7E		! a(5)
	.data4	0x2AAAA9E3
	.data2	0x7F		! a(3)
	.data4	0
	.data2	0x81		! a(1)
	.sect	.text

! LOG - base-10 logarithm.
LOG:	bsr	LN
	move.l	#0x5E5BD8A9,d2		! LOG(e)
	move.b	#0x7E,d3
	bsr	FMUL
	clr.b	d4
	rts

! ASN - Arc-sine
ASN:	bsr	SFLOAT
	PUSH5
	bsr	COPY
	bsr	FMUL
	bsr	DONE
	bsr	RSUB
	bsr	SQR0
	POP5
	tst.b	d1
	bne	1f
	move.l	d2,-(sp)		! sign of X
	move.b	#2,d4
	bra	ACS1
1:	bsr	RDIV
	bra	ATN0

! ATN - arc-tangent
ATN:	bsr	SFLOAT
ATN0:	move.l	d0,-(sp)		! save sign
	bclr	#31,d0
	move.l	#0x5413CCD0,d2		! TAN(PI/8)=SQR(2)-1
	move.b	#0x7E,d3
	bsr	FCP0			! compare
	scs	d7
	move.b	#0,d4			! (the Z80 LD keeps the flags)
	tst.b	d7
	bne	ATN2
	move.l	#0x1A82799A,d2		! TAN(3*PI/8)=SQR(2)+1
	move.b	#0x81,d3
	bsr	FCP0			! compare
	bcs	ATN1
	bsr	RECIP			! X = 1/X
	move.b	#2,d4
	bra	ATN2
ATN1:	bsr	RATIO			! X = (X-1)/(X+1)
	move.b	#1,d4
ATN2:	move.w	d4,-(sp)		! save flag
	PUSH5
	bsr	SQUARE			! push X*X
	lea	ATNTAB,a0
	bsr	POLY
	add.l	#6,sp
	POP5
	bsr	FMUL
	move.w	(sp)+,d4
ACS1:	bsr	PIBY4			! PI/4
	btst	#0,d4
	beq	1f
	move.w	d4,-(sp)
	bsr	FADD
	move.w	(sp)+,d4
1:	add.b	#1,d3			! PI/2
	btst	#1,d4
	beq	2f
	bsr	RSUB
2:	tst.l	(sp)+
	bpl	3f
	bset	#31,d0			! make negative
3:	clr.b	d4
	rts

	.sect	.rom
ATNTAB:	.data4	0x37D8F335
	.data2	0x7B		! a(13)
	.data4	0xAAB96B91
	.data2	0x7C		! a(11)
	.data4	0x619741DE
	.data2	0x7C		! a(9)
	.data4	0x92379D7B
	.data2	0x7D		! a(7)
	.data4	0x4CCC2A5A
	.data2	0x7D		! a(5)
	.data4	0xAAAAA95C
	.data2	0x7E		! a(3)
	.data4	0
	.data2	0x80		! a(1)
	.sect	.text

! ACS - Arc cosine = PI/2 - ASN.
ACS:	bsr	ASN
	clr.l	-(sp)			! positive
	move.b	#2,d4
	bra	ACS1

! VAL - Return numeric value of string.
!   Input:   ASCII string at (a5)
!   Outputs: variable-type result in d0/d1, a5 past the number
VAL:	bsr	SIGNQ
	move.w	d4,-(sp)
	bsr	CON
	move.w	(sp)+,d7
	clr.b	d4			! numeric marker
	cmp.b	#'-',d7
	bne	1f
	tst.b	d1
	beq	NEGATE			! zero/integer
	bchg	#31,d0			! change sign (FP)
1:	rts

! STR - convert numeric value to ASCII string.
!   Inputs:  d0/d1 = integer or floating-point number
!            a2 = address at which to store string
!            a5 = address of @% format control (LE bytes: +1 digits,
!                 +2 format 0 G, 1 E, 2 F)
!   Outputs: string stored, a2 = end of the string
!
! The decimal digits are generated least significant first and pushed on
! the stack, as on the Z80, as words (A << 8) | carry; the Z80 code reads
! the Z and S flags of those entries, which follow from A.
!
! First normalise for decimal output:
STR:	bsr	SFLOAT
	clr.b	d3			! B = default pt. position
	tst.l	d0
	bpl	STR10
	bclr	#31,d0
	move.b	#'-',(a2)+		! store sign
STR10:	clr.b	d4
	tst.b	d1
	beq	STR2			! zero
	move.l	a2,-(sp)		! save text pointer
STR11:	move.w	d4,-(sp)		! save decimal counter
	move.b	d1,d4			! binary exponent
	cmp.b	#161,d4
	bcc	STR14
	cmp.b	#155,d4
	bcc	STR15
	not.b	d4
	cmp.b	#225,d4
	bcs	STR13
	move.b	#-8,d4
STR13:	add.b	#28,d4
	bsr	POWR10
	move.w	d4,-(sp)
	bsr	FMUL
	move.w	(sp)+,d7
	move.w	(sp)+,d4
	sub.b	d7,d4
	bra	STR11
STR14:	sub.b	#32,d4
	bsr	POWR10
	move.w	d4,-(sp)
	bsr	FDIV
	move.w	(sp)+,d7
	move.w	(sp)+,d4
	add.b	d7,d4
	bra	STR11
STR15:	move.b	#9,d4
	bsr	POWR10			! 10^9
	bsr	FCP0
	scs	d6			! < 10^9
	move.w	(sp)+,d3		! B = decimal counter
	bset	#31,d0			! implied 1
	clr.b	d4
	tst.b	d6
	beq	1f
	sub.b	#1,d3			! X10B: x10, dec B
	add.b	#1,d1
	move.l	d0,d2			! X5
	add.b	#2,d1
	lsr.l	#2,d0
	add.l	d2,d0
	scs	d4
	and.b	#1,d4			! carry into A (the 33rd bit)
1:	move.l	(sp)+,a2		! restore text pointer
	and.b	#0x7F,d1

! At this point decimal normalisation has been done, now convert to
! decimal digits:
!	d4:d0 = number in normalised integer form (A:HLH'L')
!	d3.b  = decimal place adjustment (B)
!	d1.b  = binary place adjustment (C, 29-33)
STR2:	add.b	#1,d1
	move.b	d4,d2			! save A
	move.b	d3,d4
	btst	#1,2(a5)
	bne	STR20
	clr.b	d4
	tst.b	1(a5)
	beq	STR21
	move.b	#-10,d4
STR20:	add.b	1(a5),d4		! sig. fig. count
	bmi	STR21
	clr.b	d4
STR21:	clr.w	d7
	move.b	d4,d7
	lsl.w	#8,d7
	move.w	d7,-(sp)		! (A, carry 0)
	move.b	d2,d4			! restore A
STR22:	add.l	d0,d0			! RL A:HLH'L'
	addx.b	d4,d4
	cmp.b	#10,d4
	bcs	STR23
	sub.b	#10,d4
	bset	#0,d0			! set result bit
STR23:	sub.b	#1,d1
	bne	STR22			! 32 times
	move.b	d4,d1			! remainder
	and.l	#0x3FFFFFFF,d0		! clear out junk
	move.w	(sp)+,d7		! POP AF
	move.w	d7,d4
	lsr.w	#8,d4
	tst.b	d4
	bpl	STR24
	add.b	#1,d4			! counting up the sig. figs
	bne	STR26
	cmp.b	#4,d1			! round up?
	shi	d7
	and.b	#1,d7
	clr.b	d4
	bra	STR26
STR24:	move.w	d7,-(sp)		! PUSH AF
	and.b	#1,d7			! carry in
	move.b	d1,d4
	add.b	#'0',d4
	add.b	d7,d4			! ADC A,'0'
	cmp.b	#'0',d4
	bne	1f
	clr.b	d7			! "0": no carry
	bra	STR25			! suppress zero
1:	cmp.b	#'9'+1,d4
	bne	2f
	move.b	#1,d7			! "9" + carry: carry on
	bra	STR25
2:	clr.b	d7
	bra	STR26
STR25:	tst.b	(sp)			! top entry A = 0 (Z flag set)?
	beq	STR27			! yes: trailing zero, suppress
	move.b	#'0',d4
! STR26 - push (A, carry): d4.b = A, d7.b bit 0 = carry
STR26:	and.w	#1,d7
	move.w	d4,d6
	lsl.w	#8,d6
	or.w	d6,d7
	move.w	d7,-(sp)		! put on stack + carry
STR27:	add.b	#1,d3
	move.b	#32,d1
	clr.b	d4
	tst.l	d0			! is HLH'L' zero?
	bne	STR22
	btst	#0,1(sp)		! carry pending in the top entry?
	bne	STR22

! At this point, the decimal character string is stored on the stack.
! Trailing zeroes are suppressed and may need to be replaced.
! d3.b (B) holds decimal point position.  Now format number and store as
! ASCII string at a2.  D = d6, E = d7, C = d1.
STR3:	move.b	#-1,d1			! flag "E"
	move.b	#1,d6
	move.b	1(a5),d7		! f2
	btst	#0,2(a5)
	bne	STR34			! E mode
	btst	#1,2(a5)
	beq	STR31
	move.b	d3,d4			! F mode
	tst.b	d4
	beq	STR30
	bmi	STR30
	move.b	d3,d6
STR30:	move.b	d6,d4
	add.b	1(a5),d4
	move.b	d4,d7
	cmp.b	#11,d4
	bcs	STR32
STR31:	move.b	d3,d4			! G mode
	move.b	#1,d6
	move.b	#1,d7
	tst.b	d4
	bmi	STR34
	beq	STR32
	move.b	1(a5),d4
	bne	STR3A
	move.b	#10,d4
STR3A:	cmp.b	d3,d4
	bcs	STR34
	move.b	d3,d6
	move.b	d3,d7
STR32:	move.b	d3,d4
	add.b	#129,d4
	move.b	d4,d1
STR34:	bset	#7,d6
	sub.b	#1,d7
STR35:	cmp.b	d1,d6
	bcc	STR33
STR36:	move.w	(sp)+,d4		! POP AF
	lsr.w	#8,d4
	tst.b	d4
	beq	STR37
	bpl	STR38
STR37:	clr.w	-(sp)			! push it back (only A is used)
	move.b	d4,(sp)
	tst.b	d7
	bmi	STR4
STR33:	move.b	#'0',d4
STR38:	sub.b	#1,d6
	bvc	STR39
	move.b	#'.',(a2)+
STR39:	move.b	d4,(a2)+
	sub.b	#1,d7
	bpl	STR35
	bra	STR36

STR4:	add.l	#2,sp
STR40:	add.b	#1,d1
	bne	STR44
	move.b	#'E',(a2)+		! exponent
	move.b	d3,d4
	sub.b	#1,d4
	bpl	STR41
	move.b	#'-',(a2)+
	neg.b	d4
STR41:	move.b	#'0',(a2)
	tst.b	d4
	beq	STR47
	move.b	d4,d3
	move.b	#':',d4
	cmp.b	#10,d3
	bcs	STR42
	add.l	#1,a2
	move.b	#'0',(a2)
STR42:	add.b	#1,(a2)
	cmp.b	(a2),d4
	bne	STR43
	move.b	#'0',(a2)
	add.b	#1,-1(a2)
STR43:	sub.b	#1,d3
	bne	STR42
STR47:	add.l	#1,a2
STR44:	rts

! CON - Get unsigned numeric constant from ASCII string.
!   Inputs:  ASCII string at (a5)
!   Outputs: variable-type result in d0/d1, a5 updated (points to the
!            delimiter), d4.b = 0
CON:	bsr	ZERO			! initialise to zero
	bsr	NUMBER			! get integer part
	clr.b	d3			! decimal places counter
	cmp.b	#'.',d4
	bne	1f
	bsr	NUMBIX			! get fraction part
1:	cmp.b	#'E',d4
	bne	2f
	clr.b	d4
	bsr	GETEXP			! get exponent
	bra	3f
2:	clr.b	d4
3:	tst.l	d0
	bmi	CON0			! integer overflow
	tst.b	d4
	bne	CON0			! exponent non-zero
	tst.b	d3
	bne	CON0			! decimal point
	tst.b	d1
	bne	CON0
	rts				! integer
CON0:	sub.b	d3,d4
	add.b	d1,d4
	move.b	#159,d1
	bsr	FLOAT
	bclr	#31,d0			! ditch implied 1
	tst.b	d4
	bne	1f
	rts				! done
1:	bmi	CON2			! negative exponent
	bsr	POWR10
	bsr	FMUL			! scale
	clr.b	d4
	rts
CON2:	cmp.b	#-38,d4
	bcs	CON3			! can't scale in one go
	neg.b	d4
	bsr	POWR10
	bsr	FDIV			! scale
	clr.b	d4
	rts
CON3:	move.w	d4,-(sp)
	move.b	#38,d4
	bsr	POWR10
	bsr	FDIV
	move.w	(sp)+,d4
	add.b	#38,d4
	bra	CON2

! GETEXP - Get decimal exponent from string
!   Inputs:  ASCII string at (a5), pointing at 'E'; d4.b = initial value
!   Outputs: d4.b = new exponent, a5 updated
!   Destroys: d6, d7
GETEXP:	move.b	d4,d6			! initial value
	move.b	#2,d7			! 2 digits max
	add.l	#1,a5			! bump past 'E'
	bsr	SIGNQ
	move.w	d4,-(sp)		! save exponent sign
GETEX1:	bsr	DIGITQ
	bcs	GETEX2
	move.b	d6,d4			! B = B*10
	add.b	d4,d4
	add.b	d4,d4
	add.b	d6,d4
	add.b	d4,d4
	move.b	d4,d6
	move.b	(a5)+,d4		! get back digit
	and.b	#0x0F,d4
	add.b	d4,d6			! add in digit
	sub.b	#1,d7
	bpl	GETEX1
	move.b	#100,d6			! force overflow
	bra	GETEX1
GETEX2:	move.w	(sp)+,d7		! sign
	move.b	d6,d4
	cmp.b	#'-',d7
	bne	1f
	neg.b	d4			! negate exponent
1:	rts

! NUMBER - Get unsigned integer from string.
!   Inputs:  string at (a5); d1.b = truncated digit count (initially 0);
!            d3.b = total digit count; d0 = initial value
!   Outputs: d0 = number (binary integer), d4.b = delimiter, d1, d3, a5
!            updated
!   Destroys: d2, d5
NUMBIX:	add.l	#1,a5
NUMBER:	bsr	DIGITQ
	bcs	9f
	add.b	#1,d3			! increment digit count
	add.l	#1,a5
	bsr	X10			! *10 & copy old value
	bcs	NUMB1			! overflow
	tst.b	d1			! see if truncated
	bne	NUMB1
	and.w	#0x0F,d4
	move.w	d4,d5			! (as the Z80 B'C')
	and.l	#0xFF,d4
	add.l	d4,d0			! add in digit
	bcc	NUMBER
NUMB1:	add.b	#1,d1			! truncation counter
	exg	d0,d2			! restore previous value
	bra	NUMBER
9:	rts

! X10 - unsigned integer * 10
!   Outputs: d2 = initial d0; carry set if overflow, else d0 = result
X10:	move.l	d0,d2
	add.l	d0,d0
	bcs	1f
	add.l	d0,d0
	bcs	1f
	add.l	d2,d0
	bcs	1f
	add.l	d0,d0
1:	rts

! POWR10 - Calculate power of ten.
!   Inputs:  d4.b = power of 10 required (< 128), or
!            d4.b = binary exponent to be exceeded (>= 128)
!   Outputs: d2/d3 = result, d4.b = actual power of ten returned
!            d0/d1 preserved
!   Destroys: d5, d6, d7
POWR10:	move.l	d0,-(sp)
	move.w	d1,-(sp)
	move.b	d4,d6
	add.b	#1,d6			! target
	clr.l	d0			! 1.0
	move.b	#0x80,d1
	clr.b	d4			! count
POWR11:	sub.b	#1,d6
	beq	POWR14			! exit type 1
	bpl	POWR13
	cmp.b	d1,d6
	bcs	POWR14			! exit type 2
	add.b	#1,d6
POWR13:	add.b	#1,d4
	bset	#31,d0
	move.l	d0,d2			! X5: x 1.25 ...
	add.b	#2,d1
	lsr.l	#2,d0
	scs	d7			! (rounding bit)
	add.l	d2,d0
	bcc	POWR12
	lsr.l	#1,d0			! renormalise
	scs	d7
	add.b	#1,d1
POWR12:	tst.b	d7
	beq	1f
	bsr	ADD1			! round up
1:	add.b	#1,d1			! ... x 8
	bmi	POWR11
	bra	OFLOW
POWR14:	move.l	d0,d2
	bclr	#31,d2
	move.b	d1,d3
	move.w	(sp)+,d1
	move.l	(sp)+,d0
	rts

! DIGITQ - d4.b = (a5); carry set if not a digit
DIGITQ:	move.b	(a5),d4
	cmp.b	#'9'+1,d4
	bcc	1f
	cmp.b	#'0',d4
	rts
1:	move.w	#CC_C,ccr
	rts

! SIGNQ - skip spaces; d4.b = the character; a5 past it if + or -
SIGNQ:	move.b	(a5)+,d4
	cmp.b	#' ',d4
	beq	SIGNQ
	cmp.b	#'+',d4
	beq	1f
	cmp.b	#'-',d4
	beq	1f
	sub.l	#1,a5
1:	rts

! FIX - Fix number to specified exponent value.
!   Inputs:  d0/d1 = +ve non-zero number (floated), d4.b = desired exponent
!   Outputs: d0 = fixed number (unsigned), fraction shifted into d5.w,
!            d6.b bit 7 set if any fraction bit was shifted out
FIX:	clr.b	d6
	bset	#31,d0			! implied 1
FIX1:	bsr	DIV2
	cmp.b	d1,d4
	beq	1f
	bcc	FIX1
	bra	OFLOW
1:	rts

! SFIX - Convert to integer if necessary.
! FIX2 - the same for both arguments.
FIX2:	bsr	SWAP
	bsr	SFIX
	bsr	SWAP
SFIX:	tst.b	d1
	bne	1f
	rts				! integer/zero
1:	move.w	d4,-(sp)
	move.l	d0,-(sp)		! sign
	move.b	#159,d4
	bsr	FIX
	clr.b	d1
	move.l	(sp)+,d7
	move.w	(sp)+,d4
	tst.l	d7
	bmi	NEGATE
	rts

! NEGATE - Negate d0
NEGATE:	neg.l	d0
	rts

! NEG - Negate d0:d5 (48 bits); also complements A (used in FADD)
NEG:	neg.w	d5
	negx.l	d0
	not.b	d4
	rts

! SCALE - Trig scaling.
SCALE:	cmp.b	#150,d1
	bls	1f
	move.b	#ACLOST,d4
	bra	ERROR			! "Accuracy lost"
1:	bsr	PIBY4
	move.w	#0x2169,d5		! 3.141592653589793238

! MOD48 - 48-bit floating-point "modulus" (remainder).
!   Inputs:  d0/d1 unsigned floating-point dividend
!            d2:d5.w/d3 unsigned 48-bit FP divisor
!   Outputs: d0/d1 floating point remainder (bit 31 = 1, normalised)
!            d2 bits 23-16 (Z80 E) = quotient (bit 7 is sticky)
MOD48:	bset	#31,d2			! implied 1
	bset	#31,d0
	move.b	d1,d4
	clr.b	d1			! init quotient
	clr.w	d6			! dividend bits below d0
	cmp.b	d3,d4
	bcs	MOD485			! dividend < divisor
MOD481:	sub.w	d5,d6
	subx.l	d2,d0
	bcc	MOD482			! dividend >= divisor
	add.w	d5,d6
	addx.l	d2,d0
	move.w	#0,ccr			! quotient bit 0
	bra	1f
MOD482:	move.w	#CC_X,ccr		! quotient bit 1
1:	addx.b	d1,d1			! quotient
	bcc	MOD483
	bset	#7,d1			! sticky bit
MOD483:	sub.b	#1,d4
	cmp.b	d3,d4
	bcs	MOD484			! dividend < divisor
	add.w	d6,d6			! dividend * 2
	addx.l	d0,d0
	bcc	MOD481			! again
	sub.w	d5,d6			! overflow, so subtract
	subx.l	d2,d0
	bra	MOD482
MOD484:	add.b	#1,d4
MOD485:	swap	d2
	move.b	d1,d2			! E = quotient
	swap	d2
	move.b	d4,d1			! remainder exponent
	move.w	d6,d5
! FLO48 - Float unsigned number (48 bits) in d0:d5/d1
FLO48:	tst.l	d0
	bmi	1f
	add.w	d5,d5
	addx.l	d0,d0
	sub.b	#1,d1
	bne	FLO48
1:	rts

! FLOAT - Float unsigned number in d0/d1
FLOAT:	tst.l	d0
	bmi	1f
	add.l	d0,d0
	sub.b	#1,d1
	bne	FLOAT
1:	rts

! SFLOAT - Convert to floating-point if necessary.
! FLOAT2 - the same for both arguments.
FLOAT2:	bsr	SWAP
	bsr	SFLOAT
	bsr	SWAP
SFLOAT:	tst.b	d1
	bne	1f			! already floating-point
	bsr	TEST
	beq	1f			! zero
	move.l	d0,d4
	rol.l	#8,d4			! A = H
	tst.l	d0
	bpl	2f
	bsr	NEGATE
2:	move.b	#159,d1
	bsr	FLOAT
	tst.b	d4
	bmi	1f			! negative
	bclr	#31,d0
1:	rts

! ADD1 - Round up: carry set if 32-bit overflow.  Sets B'C' = 1.
ADD1:	move.w	#1,d5
	add.l	#1,d0
	rts

! SWAP - Swap arguments; A = old C.
SWAP:	move.b	d1,d4
	move.b	d3,d1
	move.b	d4,d3
! SWAP1 - Swap mantissas.
SWAP1:	exg	d0,d2
	rts

! DIV2 - d0:d5 >> 1, sticky into d6 (A'), C + 1
DIV2:	lsr.l	#1,d0
	roxr.w	#1,d5
	move.w	d5,d7
	lsr.w	#8,d7
	or.b	d7,d6
! INCC - C + 1, "Too big" on overflow
INCC:	add.b	#1,d1
	beq	OFLOW
	rts
OFLOW:	move.b	#TOOBIG,d4
	bra	ERROR			! "Too big"

! FTEST - Test for zero & sign: A = 0 if zero, &40 if +ve, &C0 if -ve
FTEST:	bsr	TEST
	beq	1f
	move.l	d0,d4
	rol.l	#8,d4
	and.b	#0x80,d4
	or.b	#0x40,d4
1:	rts

! TEST - Test d0 for zero: Z set and A = 0 if zero
TEST:	tst.l	d0
	sne	d4
	rts

! FCOMP - Compare two numbers: A = 0 if equal, &40 if L>R, &C0 if L<R
FCOMP:	move.b	d3,d7
	or.b	d1,d7			! both integer?
	bne	FCOMP1
	bsr	ICP1
FCOMP0:	scs	d7
	sne	d6
	bsr	ZERO
	tst.b	d6
	beq	1f			! equal
	move.b	#0x40,d4
	tst.b	d7
	beq	1f
	move.b	#0xC0,d4
1:	rts

FCOMP1:	bsr	FLOAT2			! float both
	bsr	FCP1
	bra	FCOMP0

! ZERO - Return zero.
ZERO:	clr.l	d0
	clr.b	d1
	clr.b	d4
	rts

! FCP0 - compare exponents, then mantissas (unsigned)
FCP0:	cmp.b	d3,d1			! compare exponents
	beq	1f
	rts
1:	clr.b	d7			! (carry clear after an equal compare)
! ICP0 - compare d0 with d2 as the Z80 "SBC HL,DE: ADD HL,DE" pairs:
!   d7.b = carry in (0/1); with a carry in, the MSW of d0 is decremented
!   and the borrow takes part in the comparison (as on the Z80).
!   Outputs: Z, C as the Z80
ICP0:	and.w	#1,d7
	move.l	d0,d6
	swap	d6			! HL
	move.l	d2,d4
	swap	d4			! DE
	sub.w	d7,d6			! HL - carry (d7.b is 0 or 1)
	swap	d0
	move.w	d6,d0			! the Z80 HL ends up decremented
	swap	d0
	cmp.w	d4,d6			! compare MSW (carry included)
	bne	1f
	cmp.w	d2,d0			! compare LSW
1:	rts

! FCP1, ICP1 - signed compare: Z and C according to d0/d1 - d2/d3
FCP1:	move.l	d0,d7
	eor.l	d2,d7
	bpl	1f
	tst.l	d0			! signs differ: C = arg 1 negative, NZ
	bmi	2f
	move.w	#0,ccr
	rts
2:	move.w	#CC_C,ccr
	rts
1:	tst.l	d0
	bpl	FCP0
	bsr	FCP0
	beq	3f
	bcs	4f
	move.w	#CC_C,ccr		! CCF
	rts
4:	move.w	#0,ccr
3:	rts

ICP1:	move.l	d0,d7
	eor.l	d2,d7
	bpl	1f
	tst.l	d0			! signs differ
	bmi	2f
	move.w	#0,ccr
	rts
2:	move.w	#CC_C,ccr
	rts
1:	clr.b	d7
	bra	ICP0

! X2 - Multiply d0 by 2: carry = old bit 31
X2:	add.l	d0,d0
	rts

! D2 - Divide d0 by 2 (logical)
D2C:	add.b	#1,d1
D2:	lsr.l	#1,d0
	rts

! COPY - d2/d3 = d0/d1
COPY:	move.b	d1,d3
COPY0:	move.l	d0,d2
	rts

! SQUARE - push X*X (6 bytes, below the return address on return)
SQUARE:	bsr	COPY
	bsr	FMUL
	move.l	(sp)+,a0
	PUSH5
	jmp	(a0)

! RATIO - Calculate (X-1)/(X+1)
RATIO:	PUSH5				! save X
	bsr	DONE
	bsr	FADD
	POP5				! restore X
	PUSH5				! save X+1
	bsr	SWAP
	bsr	DONE
	bsr	FSUB
	POP5				! restore X+1
	bra	FDIV

! POLY - Evaluate a polynomial.
!   Inputs:  X in d0/d1 and also pushed (PUSH5) just above the return
!            address; a0 = coefficients (.data4 mantissa, .data2 exponent)
!   Outputs: result in d0/d1
!   Terminates on a coefficient >= 1 (exponent bit 7 set).
POLY:	lea	4(sp),a1		! X
	move.l	(a0)+,d2		! first coefficient
	move.w	(a0)+,d3
1:	movem.l	a0/a1,-(sp)
	bsr	FMUL
	movem.l	(sp)+,a0/a1
	move.l	(a0)+,d2		! next coefficient
	move.w	(a0)+,d3
	tst.b	d3
	bmi	FADD
	movem.l	a0/a1,-(sp)
	bsr	FADD
	movem.l	(sp)+,a0/a1
	move.w	(a1),d3			! X
	move.l	2(a1),d2
	bra	1b

! DIVA, DIVB - division primitive (the Z80 restoring loop).
!   d0:d2 / d7: quotient bits shift into d2, remainder in d0.
!   Inputs:  d3.w = steps - 1; DIVA starts with a compare, DIVB with a
!            shift (X = the bit shifted into d0)
!   Destroys: d3
DIVA:	cmp.l	d7,d0
	bcs	2f
	sub.l	d7,d0
1:	move.w	#CC_X,ccr		! result bit 1
	bra	3f
2:	move.w	#0,ccr			! result bit 0
3:	addx.l	d2,d2			! shift result into d2
	dbra	d3,DIVB
	rts
DIVB:	addx.l	d0,d0			! dividend * 2
	bcc	DIVA
	sub.l	d7,d0			! overflow: subtract
	bra	1b

! SQRA, SQRB - square root primitives (the Z80 loop).
!   Root (times 2) in d7 = Z80 BC, remainder in d0 = HL, radicand in
!   d2 = DE (shifted into d0 two bits per step).
!   Inputs:  d4.b = loop counter (normally -31)
SQR1:	sub.l	d7,d0			! remainder - (4*root+1)
	bcc	1f
	add.l	d7,d0			! restore
	sub.l	#1,d7			! root bit 0
	bra	SQR2
1:	add.l	#1,d7			! root bit 1
SQR2:	add.b	#1,d4
	bpl	9f
SQRA:	add.l	d7,d7
	add.l	#1,d7
	add.l	d2,d2			! two bits of radicand in
	addx.l	d0,d0			! (the first carry is lost, as on
	add.l	d2,d2			!  the Z80)
	addx.l	d0,d0
	bcc	SQR1
SQR3:	sub.l	d7,d0
	add.l	#1,d7
	bra	SQR2
9:	rts

SQRB:	add.l	d0,d0
	bcs	SQR3
	add.b	#1,d4
	add.l	#1,d7
	sub.l	d7,d0
	bcc	1f
	add.l	d7,d0
	sub.l	#1,d7
1:	rts

! ABS2 - make both arguments positive for IMUL/IMOD:
!   Outputs: d7 = |arg 2|, d2 = |arg 1|, d0 = 0; B and C swapped
ABS2:	tst.l	d0
	bpl	1f
	bsr	NEGATE
1:	bsr	SWAP
	tst.l	d0
	bpl	2f
	bsr	NEGATE
2:	move.l	d0,d7
	clr.l	d0
	rts
