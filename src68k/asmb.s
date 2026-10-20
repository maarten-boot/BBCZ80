#
! asmb.s - BBC BASIC 68k: the 68000 inline assembler ([ ... ]).
!
! (C) Copyright R.T. Russell 1981-2025 (Z80 original: the language
! independent control section); the 68000 translation section is new.
! See CONVENTIONS.md and PHASE4.md.
!
! THE NAME BBC BASIC IS USED WITH THE PERMISSION OF THE BRITISH
! BROADCASTING CORPORATION AND IS NOT TRANSFERRABLE TO A FORKED OR
! DERIVED WORK.
!
! Syntax: Motorola, case-insensitive (see ASSEMBLER.md):
!   [.label] [mnemonic[.size] [operand[,operand]]] [; or \ comment]
! statements separated by ':', the block ends at ']'.  Operands are
! BASIC expressions; $hex is accepted as well as &hex.  Addressing modes:
!   Dn  An  (An)  (An)+  -(An)  d(An)  d(An,Xn[.W|.L])  addr[.W|.L]
!   d(PC)  d(PC,Xn)  #data, and (d,An) (d,An,Xn) (d,PC) (d,PC,Xn)
! For d(PC) forms and branches the expression is the target address.
! Absolute addresses are long unless .W is given (the size must not
! change between the passes); branches are .W unless .S (or .B) is
! given.  OPT as the Z80 version: bit 0 list, bit 1 report errors (an
! unknown variable is P% while it is clear), bit 2 assemble at O%.
! Directives: DC.B/.W/.L list (strings in DC.B), DS.B/.W/.L count,
! EQUB EQUW EQUD EQUS, ALIGN (or EVEN), OPT.

#include "bbc.h"

	.sect	.text
	.sect	.rom
	.sect	.data
	.sect	.bss

	.define	ASSEM

	.extern	EXPRI, EXPR, VAR, STOREN, ERROR, OUT, CRLF, TABIT
	.extern	LDLE4, STLE4, LISTON, COUNT, PC, OC, ACCS, KEYWDS, KEYWDL

CR	= 0x0D
BSLASH	= 0x5C
TDEF	= 0xDD

! operand record (op1, op2): 16 bytes
O_IDX	= 0		! addressing mode index 0-11 (see EAFLD)
O_REG	= 1		! register number 0-7
O_XREG	= 2		! index register 0-15 (D0-D7, A0-A7)
O_XL	= 3		! index register is .L
O_VAL	= 4		! value (displacement, address or data)
O_KIND	= 8		! K_EA, K_LIST, K_SR, K_CCR, K_USP
O_MASK	= 10		! register list (bit n = Dn, bit 8+n = An)

K_EA	= 0
K_LIST	= 1
K_SR	= 2
K_CCR	= 3
K_USP	= 4

! addressing mode index sets (bit n = index n allowed)
M_ALL	= 0xFFF
M_DATA	= 0xFFD
M_CTRL	= 0x7E4
M_ALT	= 0x1FF
M_DALT	= 0x1FD
M_MALT	= 0x1FC
M_CALT	= 0x1E4

! classes (MNTAB); from C_DC on: directives, no operation word
C_NONE	= 0
C_IMM16	= 1
C_TRAP	= 2
C_BCC	= 3
C_DBCC	= 4
C_SCC	= 5
C_MOVE	= 6
C_MOVEA	= 7
C_MOVEQ	= 8
C_ADDSUB = 9
C_LOGIC	= 10
C_EOR	= 11
C_CMP	= 12
C_CMPM	= 13
C_QUICK	= 14
C_XOP	= 15
C_UNARY	= 16
C_EAONLY = 17
C_EXT	= 18
C_SWAP	= 19
C_SHIFT	= 20
C_BIT	= 21
C_LEA	= 22
C_LINK	= 23
C_UNLK	= 24
C_EXG	= 25
C_MULDIV = 26
C_MOVEM	= 27
C_MOVEP	= 28
C_DC	= 29
C_DS	= 30
C_EQU	= 31
C_ALIGN	= 32
C_OPT	= 33

	.sect	.text

! ASSEM - assemble statements up to ']' or the end of the line.
!   Inputs:  a4 = the text after '[' (or the next line)
!   Outputs: d4.b = the delimiter (']' or CR), a4 past it; carry set if
!            syntax error.
ASSEM:	bsr	SKIPSP
	add.l	#1,a4
	cmp.b	#':',d4
	beq	ASSEM
	cmp.b	#']',d4
	beq	ASSEM9
	cmp.b	#CR,d4
	beq	ASSEM9
	sub.l	#1,a4
	move.l	sp,asmsp		! (for ASMBAD)
	move.l	a4,asmstm
	lea	PC,a0
	bsr	LDLE4
	move.l	d0,asmpc		! P%
	btst	#6,LISTON		! OPT 4: the code goes to O%
	beq	1f
	lea	OC,a0
	bsr	LDLE4
1:	move.l	d0,asmdst
	move.l	d0,a5			! the code pointer
	bsr	ASMB			! one statement
	bsr	SKIPSP
	bsr	ISTERM
	bne	ASMBAD
2:	move.b	(a4),d4			! skip a comment up to : or CR
	cmp.b	#':',d4
	beq	3f
	cmp.b	#CR,d4
	beq	3f
	add.l	#1,a4
	bra	2b
3:	move.l	a5,d6
	sub.l	asmdst,d6		! number of bytes
	move.l	asmpc,d0
	add.l	d6,d0
	lea	PC,a0
	bsr	STLE4			! UPDATE PC
	btst	#6,LISTON
	beq	4f
	lea	OC,a0
	bsr	LDLE4
	add.l	d6,d0
	bsr	STLE4			! UPDATE OC
4:	btst	#4,LISTON
	beq	ASSEM
	bsr	LISTIT
	bra	ASSEM
ASSEM9:	move.w	#0,ccr			! NC
	rts

! ASMBAD - syntax error: return from ASSEM with carry set
ASMBAD:	move.l	asmsp,sp
	move.w	#CC_C,ccr
	rts

! LISTIT - list a statement: address, code bytes, source text
LISTIT:	move.l	asmpc,d0
	bsr	HEX8
	move.b	#' ',d4
	bsr	OUT
	move.l	asmdst,a3
	move.l	a5,d6
	sub.l	a3,d6
	beq	2f
1:	cmp.b	#27,COUNT
	bcs	3f
	move.b	#9,d4
	bsr	TABIT			! NEXT LINE
3:	move.b	(a3)+,d4
	bsr	HEX2
	move.b	#' ',d4
	bsr	OUT
	sub.l	#1,d6
	bne	1b
2:	move.b	#28,d4
	bsr	TABIT
	move.l	asmstm,a3
4:	cmp.l	a4,a3
	bcc	5f
	move.b	(a3)+,d4
	bsr	OUT
	bra	4b
5:	bra	CRLF

HEX8:	move.w	#7,d6
1:	rol.l	#4,d0
	move.b	d0,d4
	bsr	HEXOUT
	dbra	d6,1b
	rts
HEX2:	move.b	d4,-(sp)
	lsr.b	#4,d4
	bsr	HEXOUT
	move.b	(sp)+,d4
HEXOUT:	and.b	#0x0F,d4
	add.b	#'0',d4
	cmp.b	#'9'+1,d4
	bcs	1f
	add.b	#'A'-'9'-1,d4
1:	bra	OUT

! ASMB - assemble one statement: [.label] [instruction]
ASMB:	bsr	SKIPSP
	cmp.b	#'.',d4
	bne	ASMB1
	add.l	#1,a4			! LABEL
	move.l	a5,-(sp)
	bsr	VAR
	tst.b	d4
	bmi	ASMBAD			! (a string)
	btst	#5,LISTON		! (first pass only)
	bne	1f
	move.b	(a5),d0
	or.b	1(a5),d0
	or.b	2(a5),d0
	or.b	3(a5),d0
	beq	1f
	move.b	#3,d4
	bra	ERROR			! "Multiple label"
1:	move.l	asmpc,d0
	clr.b	d1
	bsr	STOREN
	move.l	(sp)+,a5
ASMB1:	bsr	SKIPSP
	bsr	ISTERM
	bne	1f
	rts
1:	bsr	GETMN			! the mnemonic
	bsr	FINDMN
	bne	ASMBAD
	move.b	d0,mclass
	move.b	d1,mparam
	move.w	d2,mopw
	cmp.b	#C_DC,d0
	bcc	2f			! directive: no operation word
	add.l	#2,a5			! (the operation word comes last)
	bsr	OPNDS
2:	clr.w	d0
	move.b	mclass,d0
	lsl.w	#2,d0
	lea	HANDLR,a0
	move.l	0(a0,d0.w),a0
	clr.l	d5
	move.w	mopw,d5			! the operation word, being built
	jmp	(a0)

! OPNDS - parse up to two operands into op1, op2 (nops = count)
OPNDS:	clr.b	nops
	bsr	SKIPSP
	bsr	ISTERM
	beq	9f
	lea	op1,a3
	bsr	PARSOP
	move.b	#1,nops
	bsr	SKIPSP
	cmp.b	#',',d4
	bne	9f
	add.l	#1,a4
	lea	op2,a3
	bsr	PARSOP
	move.b	#2,nops
9:	rts

! GETMN - read the mnemonic at a4 into mtext (upper case, NUL
! terminated), expanding BASIC keywords that the tokeniser made of it.
! tokpos/toklen: where the text of the last token is (toklen 0: none).
GETMN:	lea	mtext,a1
	clr.w	d2			! length
	clr.w	toklen
1:	move.b	(a4),d4
	cmp.b	#' ',d4
	beq	5f
	bsr	ISTERM
	beq	5f
	cmp.b	#'#',d4
	beq	5f
	add.l	#1,a4
	cmp.b	#0x20,d4
	bcs	2f
	tst.b	d4
	bpl	3f
2:	lea	KEYWDS,a0		! a token: find its text
	move.w	#KEYWDL-1,d1
6:	cmp.b	(a0)+,d4
	beq	7f
	dbra	d1,6b
	bra	ASMBAD
7:	move.w	d2,tokpos
4:	move.b	(a0)+,d0
	cmp.b	#' '+1,d0
	bcs	8f
	tst.b	d0
	bmi	8f
	bsr	MNPUT
	bra	4b
8:	move.w	d2,d0
	sub.w	tokpos,d0
	move.w	d0,toklen
	bra	1b
3:	move.b	d4,d0
	bsr	MNPUT
	bra	1b
5:	clr.b	(a1)
	move.w	d2,mtlen
	rts
MNPUT:	cmp.w	#15,d2
	bcc	ASMBAD
	cmp.b	#'a',d0
	bcs	1f
	cmp.b	#'z'+1,d0
	bcc	1f
	sub.b	#'a'-'A',d0
1:	move.b	d0,(a1)+
	add.w	#1,d2
	rts

! SPLIT - mnemonic text at a1 into mname (8 bytes, NUL padded) and
!   msize (0, 1 B, 2 W, 4 L, 8 S); NZ if malformed.
SPLIT:	clr.l	mname
	clr.l	mname+4
	clr.b	msize
	lea	mname,a0
	move.w	#8,d2
1:	move.b	(a1)+,d0
	beq	4f
	cmp.b	#'.',d0
	beq	2f
	sub.w	#1,d2
	bmi	9f			! too long
	move.b	d0,(a0)+
	bra	1b
2:	move.b	(a1)+,d0		! size suffix
	tst.b	(a1)
	bne	9f
	lea	SIZES,a0
	clr.w	d1
3:	move.b	(a0)+,d1
	beq	9f
	cmp.b	(a0)+,d0
	bne	3b
	move.b	d1,msize
4:	tst.b	mname
	beq	9f
	move.w	#CC_Z,ccr
	rts
9:	move.w	#0,ccr
	rts

! FINDMN - the mnemonic as read, else (when the tokeniser took "XYZ."
! for an abbreviated keyword) the last token's text cut to 1-n letters
! followed by '.' and the size letter: d0-d2 as LOOKUP; NZ if unknown.
FINDMN:	lea	mtext,a1
	bsr	SPLIT
	bne	1f
	bsr	LOOKUP
	beq	9f
1:	move.w	toklen,d3		! a token, then one letter?
	beq	8f
	move.w	tokpos,d4
	add.w	d3,d4
	add.w	#1,d4
	cmp.w	mtlen,d4
	bne	8f
2:	lea	mtext,a0		! mtext[0 .. tokpos+d3) '.' size
	lea	mtry,a1
	move.w	tokpos,d4
	add.w	d3,d4
	sub.w	#1,d4
3:	move.b	(a0)+,(a1)+
	dbra	d4,3b
	move.b	#'.',(a1)+
	move.w	mtlen,d4
	lea	mtext,a0
	move.b	-1(a0,d4.w),(a1)+
	clr.b	(a1)
	lea	mtry,a1
	move.w	d3,-(sp)
	bsr	SPLIT
	bne	4f
	bsr	LOOKUP
4:	movem.w	(sp)+,d3		! (flags kept)
	beq	9f
	sub.w	#1,d3
	bne	2b
8:	move.w	#0,ccr			! NZ
9:	rts

! LOOKUP - find mname: d0.b = class, d1.b = param, d2.w = operation word;
!   NZ if unknown.
LOOKUP:	lea	MNTAB,a0
	move.l	mname,d6
	move.l	mname+4,d7
1:	tst.b	(a0)
	beq	CCMN			! not in the table
	cmp.l	(a0),d6
	bne	2f
	cmp.l	4(a0),d7
	beq	3f
2:	add.l	#12,a0
	bra	1b
3:	move.b	8(a0),d0
	move.b	9(a0),d1
	move.w	10(a0),d2
	move.w	#CC_Z,ccr
	rts
! Bcc, BRA, BSR, DBcc, DBRA, Scc
CCMN:	lea	mname,a0
	clr.b	d1
	cmp.b	#'B',(a0)
	bne	3f
	cmp.l	#0x42524100,d6		! BRA
	beq	1f
	move.w	#0x100,d2
	cmp.l	#0x42535200,d6		! BSR
	beq	2f
	lea	1(a0),a1
	bsr	CCODE
	bne	9f
	cmp.b	#2,d0
	bcs	9f			! (BT, BF)
	tst.b	2(a1)
	bne	9f
	move.w	d0,d2
	lsl.w	#8,d2
	bra	2f
1:	clr.w	d2
2:	or.w	#0x6000,d2
	move.b	#C_BCC,d0
	move.w	#CC_Z,ccr
	rts
3:	cmp.b	#'D',(a0)
	bne	5f
	cmp.b	#'B',1(a0)
	bne	9f
	move.w	#0x100,d2
	cmp.l	#0x44425241,d6		! DBRA
	bne	4f
	tst.l	d7
	beq	6f
4:	lea	2(a0),a1
	bsr	CCODE
	bne	9f
	move.w	d0,d2
	lsl.w	#8,d2
6:	or.w	#0x50C8,d2
	move.b	#C_DBCC,d0
	move.w	#CC_Z,ccr
	rts
5:	cmp.b	#'S',(a0)
	bne	9f
	lea	1(a0),a1
	bsr	CCODE
	bne	9f
	move.w	d0,d2
	lsl.w	#8,d2
	or.w	#0x50C0,d2
	move.b	#C_SCC,d0
	move.w	#CC_Z,ccr
	rts
9:	move.w	#0,ccr			! NZ
	rts

! CCODE - condition at a1 (1 or 2 letters, then NUL): d0.w = code, Z
CCODE:	lea	CCTAB,a2
	clr.w	d0
1:	move.b	(a2)+,d3
	beq	9f
	move.b	(a2)+,d4
	move.b	(a2)+,d0
	cmp.b	(a1),d3
	bne	1b
	cmp.b	#' ',d4
	bne	2f
	tst.b	1(a1)
	bne	1b
	bra	3f
2:	cmp.b	1(a1),d4
	bne	1b
	tst.b	2(a1)
	bne	1b
3:	move.w	#CC_Z,ccr
	rts
9:	move.w	#0,ccr
	rts

! ----------------------------------------------------------------------
! Operands

! PARSOP - parse an operand at a4 into the record at a3
PARSOP:	move.l	a3,curop
	clr.l	(a3)
	clr.l	4(a3)
	clr.l	8(a3)
	clr.l	12(a3)
	bsr	SKIPSP
	cmp.b	#'#',d4			! #data
	bne	1f
	add.l	#1,a4
	bsr	EXPRA
	move.l	curop,a3
	move.l	d0,O_VAL(a3)
	move.b	#11,O_IDX(a3)
	rts
1:	cmp.b	#'-',d4			! -(An)
	bne	2f
	cmp.b	#'(',1(a4)
	bne	2f
	lea	2(a4),a0
	bsr	SKIPA0
	bsr	REGAT
	bne	2f
	cmp.b	#8,d0
	bcs	2f
	cmp.b	#16,d0
	bcc	2f
	bsr	SKIPA0
	cmp.b	#')',(a0)+
	bne	2f
	move.l	a0,a4
	move.b	#4,O_IDX(a3)
	and.b	#7,d0
	move.b	d0,O_REG(a3)
	rts
2:	move.l	a4,a0			! a register (or a list)
	bsr	REGAT
	bne	4f
	move.l	a0,a4
	cmp.b	#16,d0
	bcs	3f
	beq	ASMBAD			! PC alone
	sub.b	#15,d0			! SR 2, CCR 3, USP 4
	move.b	d0,O_KIND(a3)
	rts
3:	bsr	SKIPSP
	cmp.b	#'-',d4
	beq	REGLST
	cmp.b	#'/',d4
	beq	REGLST
	move.b	d0,d1
	and.b	#7,d1
	move.b	d1,O_REG(a3)
	lsr.b	#3,d0
	move.b	d0,O_IDX(a3)		! 0 Dn, 1 An
	rts
4:	cmp.b	#'(',d4
	bne	EXPOP
	lea	1(a4),a0
	bsr	SKIPA0
	bsr	REGAT
	bne	NEWSTY
	cmp.b	#8,d0			! (An) (An)+ (An,Xn)
	bcs	ASMBAD
	cmp.b	#16,d0
	bcc	ASMBAD
	and.b	#7,d0
	move.b	d0,O_REG(a3)
	bsr	SKIPA0
	move.b	(a0)+,d4
	cmp.b	#',',d4
	beq	5f
	cmp.b	#')',d4
	bne	ASMBAD
	move.l	a0,a4
	move.b	#2,O_IDX(a3)
	cmp.b	#'+',(a4)
	bne	6f
	add.l	#1,a4
	move.b	#3,O_IDX(a3)
6:	rts
5:	move.l	a0,a4			! (An,Xn): d8 = 0
	bsr	XNPAR
	bsr	CLOSEP
	move.b	#6,O_IDX(a3)
	rts

! (d,An...) or an expression starting with '('
NEWSTY:	lea	1(a4),a0		! a ',' before the matching ')'?
	clr.w	d2
	clr.b	d3
1:	move.b	(a0)+,d4
	cmp.b	#CR,d4
	beq	EXPOP
	cmp.b	#'"',d4
	bne	2f
	eor.b	#1,d3
2:	tst.b	d3
	bne	1b
	cmp.b	#'(',d4
	bne	3f
	add.w	#1,d2
3:	cmp.b	#')',d4
	bne	4f
	sub.w	#1,d2
	bcs	EXPOP			! no comma
4:	cmp.b	#',',d4
	bne	1b
	tst.w	d2
	bne	1b
	add.l	#1,a4			! (d,An...): the displacement
	bsr	EXPRA
	move.l	curop,a3
	move.l	d0,O_VAL(a3)
	bsr	SKIPSP
	cmp.b	#',',d4
	bne	ASMBAD
	add.l	#1,a4
	bsr	SKIPSP
	bra	BASREG

! EXPOP - expression, then (An...) / (PC...) / .W / .L or nothing
EXPOP:	bsr	EXPRA
	move.l	curop,a3
	move.l	d0,O_VAL(a3)
	move.b	#8,O_IDX(a3)		! absolute long
	move.b	(a4),d4
	cmp.b	#'.',d4
	bne	1f
	move.b	1(a4),d4
	and.b	#0xDF,d4
	add.l	#2,a4
	cmp.b	#'L',d4
	beq	2f
	cmp.b	#'W',d4
	bne	ASMBAD
	move.b	#7,O_IDX(a3)
2:	rts
1:	cmp.b	#'(',d4
	bne	2b
	add.l	#1,a4
	bsr	SKIPSP
! BASREG - An or PC [,Xn] then ')': d(An) d(An,Xn) d(PC) d(PC,Xn)
BASREG:	move.l	a4,a0
	bsr	REGAT
	bne	ASMBAD
	move.l	a0,a4
	move.b	#5,d1
	cmp.b	#16,d0
	beq	1f
	cmp.b	#8,d0
	bcs	ASMBAD
	cmp.b	#16,d0
	bcc	ASMBAD
	and.b	#7,d0
	move.b	d0,O_REG(a3)
	bra	2f
1:	move.b	#9,d1			! PC
2:	move.b	d1,O_IDX(a3)
	bsr	SKIPSP
	cmp.b	#',',d4
	bne	CLOSEP
	add.l	#1,a4
	bsr	XNPAR
	add.b	#1,O_IDX(a3)		! 6 or 10
! CLOSEP - expect ')'
CLOSEP:	bsr	SKIPSP
	cmp.b	#')',d4
	bne	ASMBAD
	add.l	#1,a4
	rts

! XNPAR - index register Xn[.W|.L] into the record at a3
XNPAR:	bsr	SKIPSP
	move.l	a4,a0
	bsr	REGAT
	bne	ASMBAD
	cmp.b	#16,d0
	bcc	ASMBAD
	move.b	d0,O_XREG(a3)
	move.l	a0,a4
	cmp.b	#'.',(a4)
	bne	1f
	move.b	1(a4),d4
	and.b	#0xDF,d4
	add.l	#2,a4
	cmp.b	#'W',d4
	beq	1f
	cmp.b	#'L',d4
	bne	ASMBAD
	move.b	#1,O_XL(a3)
1:	rts

! REGLST - register list: the first register (code d0) is parsed
REGLST:	clr.l	d3			! the mask
1:	move.b	d0,d2			! from
	bsr	SKIPSP
	cmp.b	#'-',d4
	bne	2f
	add.l	#1,a4
	bsr	SKIPSP
	move.l	a4,a0
	bsr	REGAT
	bne	ASMBAD
	move.l	a0,a4
	cmp.b	#16,d0
	bcc	ASMBAD
	cmp.b	d2,d0
	bcs	ASMBAD
	bra	3f
2:	move.b	d2,d0			! to
3:	bset	d2,d3
	add.b	#1,d2
	cmp.b	d0,d2
	bls	3b
	bsr	SKIPSP
	cmp.b	#'/',d4
	bne	4f
	add.l	#1,a4
	bsr	SKIPSP
	move.l	a4,a0
	bsr	REGAT
	bne	ASMBAD
	move.l	a0,a4
	cmp.b	#16,d0
	bcc	ASMBAD
	bra	1b
4:	move.b	#K_LIST,O_KIND(a3)
	move.w	d3,O_MASK(a3)
	rts

! REGAT - register name at a0: Z and d0.b = 0-7 Dn, 8-15 An (SP = A7),
!   16 PC, 17 SR, 18 CCR, 19 USP; a0 past it.  NZ if none.
!   Destroys: d1 (a1 preserved: COPYX)
REGAT:	move.l	a1,-(sp)
	bsr	REGAT0
	movem.l	(sp)+,a1		! (movem: flags kept)
	rts
REGAT0:	move.l	a0,-(sp)
	move.b	(a0)+,d1
	and.b	#0xDF,d1
	cmp.b	#'D',d1
	beq	1f
	cmp.b	#'A',d1
	bne	3f
1:	move.b	(a0)+,d0
	sub.b	#'0',d0
	cmp.b	#8,d0
	bcc	8f
	cmp.b	#'A',d1
	bne	REGEND
	add.b	#8,d0
	bra	REGEND
3:	lea	REGNMS,a1
4:	move.b	(a1)+,d0		! code, then 3 letters (NUL padded)
	beq	8f
	move.l	(sp),a0
	add.l	#1,a0
	cmp.b	(a1)+,d1
	bne	6f
	move.b	(a0)+,d1		! 2nd letter
	and.b	#0xDF,d1
	cmp.b	(a1)+,d1
	bne	7f
	tst.b	(a1)
	beq	5f
	move.b	(a0)+,d1		! 3rd letter
	and.b	#0xDF,d1
	cmp.b	(a1),d1
	bne	7f
5:	add.l	#1,a1
	bra	REGEND
6:	add.l	#1,a1
7:	add.l	#1,a1
	move.l	(sp),a0
	move.b	(a0),d1
	and.b	#0xDF,d1
	bra	4b
REGEND:	move.b	(a0),d1			! not followed by a name character
	bsr	IDCH
	beq	8f
	add.l	#4,sp
	move.w	#CC_Z,ccr
	rts
8:	move.l	(sp)+,a0
	move.w	#0,ccr			! NZ
	rts

! IDCH - Z if d1.b can continue a BASIC name (letter, digit, _ ` @ % $ ()
IDCH:	cmp.b	#'0',d1
	bcs	2f
	cmp.b	#'9'+1,d1
	bcs	1f
	cmp.b	#'@',d1
	bcs	2f
	cmp.b	#'Z'+1,d1
	bcs	1f
	cmp.b	#'_',d1
	bcs	2f
	cmp.b	#'z'+1,d1
	bcs	1f
	bra	3f
2:	cmp.b	#'%',d1
	beq	1f
	cmp.b	#'$',d1
	beq	1f
	cmp.b	#'(',d1
	beq	1f
3:	move.w	#0,ccr			! NZ
	rts
1:	move.w	#CC_Z,ccr
	rts

! ----------------------------------------------------------------------
! Expressions

! EXPRA - evaluate the integer expression at a4 (it ends at a ',', a
!   terminator, a closing ')', a '(' that starts a register group or a
!   .W/.L suffix); a4 past it.  Output: d0.l.  Preserves a5.
EXPRA:	bsr	COPYX
	move.l	a4,eend
	move.l	a5,esva5
	lea	abuf,a4
	bsr	EXPRI
	bsr	SKIPSP
	cmp.b	#CR,d4
	bne	ASMBAD
	move.l	eend,a4
	move.l	esva5,a5
	rts

! EXPRV - as EXPRA, any type: d6.b = type (bit 7: string in ACCS, a2 =
!   its end), else the number in d0/d1
EXPRV:	bsr	COPYX
	move.l	a4,eend
	move.l	a5,esva5
	lea	abuf,a4
	bsr	EXPR
	bsr	SKIPSP
	cmp.b	#CR,d4
	bne	ASMBAD
	move.l	eend,a4
	move.l	esva5,a5
	rts

! COPYX - copy the expression at a4 to abuf (CR terminated), a4 to its
!   end.  $hex becomes &hex, and hex digits are made upper case.
COPYX:	lea	abuf,a1
	clr.w	d2			! depth
	clr.b	d3			! in quotes
	move.b	#' ',d5			! previous character
1:	move.b	(a4),d4
	cmp.b	#CR,d4
	beq	9f
	cmp.b	#'"',d4
	bne	2f
	eor.b	#1,d3
	bra	6f
2:	tst.b	d3
	bne	6f
	bsr	ISTERM
	beq	9f
	cmp.b	#'(',d4
	bne	3f
	tst.w	d2
	bne	2f
	move.l	a4,a0			! a register group?
	add.l	#1,a0
	bsr	SKIPA0
	bsr	REGAT
	bne	2f
	cmp.b	#8,d0
	bcs	2f
	cmp.b	#17,d0
	bcc	2f
	bsr	SKIPA0
	cmp.b	#')',(a0)
	beq	9f
	cmp.b	#',',(a0)
	beq	9f
2:	add.w	#1,d2
	bra	6f
3:	cmp.b	#')',d4
	bne	3f
	sub.w	#1,d2
	bcs	9f
	bra	6f
3:	cmp.b	#',',d4
	bne	3f
	tst.w	d2
	beq	9f
	bra	6f
3:	cmp.b	#'.',d4
	bne	3f
	tst.w	d2
	bne	6f
	move.b	1(a4),d1		! .W / .L suffix?
	and.b	#0xDF,d1
	cmp.b	#'W',d1
	beq	4f
	cmp.b	#'L',d1
	bne	6f
4:	move.b	2(a4),d1
	bsr	IDCH
	bne	9f
	bra	6f
3:	cmp.b	#'&',d4			! &hex: copy it upper case
	beq	8f
	cmp.b	#'$',d4
	bne	6f
	move.b	d5,d1			! a name before it: not hex
	bsr	IDCH
	beq	6f
8:
	lea	1(a4),a0		! hex digits, then not a name char
	clr.w	d6
4:	move.b	(a0)+,d1
	cmp.b	#TDEF,d1
	beq	5f
	bsr	HEXQ
	bne	4f
5:	add.w	#1,d6
	bra	4b
4:	tst.w	d6
	beq	6f
	bsr	IDCH
	beq	6f
	move.b	#'&',(a1)+		! copy it as &HEX
	add.l	#1,a4
4:	sub.w	#1,d6
	bmi	1b
	move.b	(a4)+,d1
	cmp.b	#TDEF,d1
	bne	5f
	move.b	#'D',(a1)+
	move.b	#'E',(a1)+
	move.b	#'F',d1
	bra	7f
5:	cmp.b	#'a',d1
	bcs	7f
	sub.b	#'a'-'A',d1
7:	move.b	d1,(a1)+
	move.b	d1,d5
	bra	4b
6:	move.b	d4,(a1)+
	move.b	d4,d5
	add.l	#1,a4
	cmp.l	#abuf+250,a1
	bcs	1b
	bra	ASMBAD
9:	move.b	#CR,(a1)
	rts

! HEXQ - Z if d1.b is a hex digit (either case)
HEXQ:	cmp.b	#'0',d1
	bcs	2f
	cmp.b	#'9'+1,d1
	bcs	1f
	move.b	d1,d0
	and.b	#0xDF,d0
	cmp.b	#'A',d0
	bcs	2f
	cmp.b	#'F'+1,d0
	bcc	2f
1:	move.w	#CC_Z,ccr
	rts
2:	move.w	#0,ccr
	rts

! ----------------------------------------------------------------------
! Small helpers

! SKIPSP - skip spaces at a4: d4.b = the character
SKIPSP:	move.b	(a4),d4
	cmp.b	#' ',d4
	bne	1f
	add.l	#1,a4
	bra	SKIPSP
1:	rts
SKIPA0:	cmp.b	#' ',(a0)
	bne	1f
	add.l	#1,a0
	bra	SKIPA0
1:	rts

! ISTERM - Z if d4.b ends a statement: ':' CR ';' '\'
ISTERM:	cmp.b	#':',d4
	beq	1f
	cmp.b	#CR,d4
	beq	1f
	cmp.b	#';',d4
	beq	1f
	cmp.b	#BSLASH,d4
1:	rts

! EMITW / EMITL - store d0.w / d0.l at a5 (bytewise: P% may be odd)
EMITL:	swap	d0
	bsr	EMITW
	swap	d0
EMITW:	rol.w	#8,d0
	move.b	d0,(a5)+
	rol.w	#8,d0
	move.b	d0,(a5)+
	rts

! PUTOPW - store the operation word d5.w at the start of the code
PUTOPW:	move.l	asmdst,a0
	move.w	d5,d0
	rol.w	#8,d0
	move.b	d0,(a0)+
	rol.w	#8,d0
	move.b	d0,(a0)
	rts

! EXTADR - d0.l = the address (P%) of the next extension word
EXTADR:	move.l	a5,d0
	sub.l	asmdst,d0
	add.l	asmpc,d0
	rts

! RNG8 / RNG16 - range check of d0 as signed 8 / 16 bits ("Out of range"
!   if OPT bit 1 is set)
RNG8:	move.b	d0,d1
	ext.w	d1
	ext.l	d1
	bra	1f
RNG16:	move.w	d0,d1
	ext.l	d1
1:	cmp.l	d0,d1
	bne	RNGERR
	rts
! RNGU16 / RNGU8: also allow the unsigned range
RNGU16:	cmp.l	#0xFFFF,d0
	bls	1f
	bra	RNG16
RNGU8:	cmp.l	#0xFF,d0
	bls	1f
	bra	RNG8
1:	rts
RNGERR:	btst	#5,LISTON
	bne	1f
	rts
1:	move.b	#1,d4
	bra	ERROR			! "Out of range"

! EAFLD - d0.w = the effective address field (mode << 3 | reg) of a3
EAFLD:	clr.w	d0
	move.b	O_IDX(a3),d0
	cmp.b	#7,d0
	bcc	1f
	lsl.w	#3,d0
	or.b	O_REG(a3),d0
	rts
1:	add.b	#0x38-7,d0
	rts

! CHKM - the operand at a3 must be an effective address of a mode in d1
CHKM:	tst.b	O_KIND(a3)
	bne	ASMBAD
	clr.l	d0
	move.b	O_IDX(a3),d0
	btst	d0,d1
	beq	ASMBAD
	rts

! ISIDX - Z if the operand at a3 is an effective address of index d1.b
ISIDX:	tst.b	O_KIND(a3)
	bne	1f
	cmp.b	O_IDX(a3),d1
1:	rts

! EMITEA - the extension words of the operand at a3; d7 = data size
!   (1, 2, 4) for #data.  Preserves d3-d7, a3.
EMITEA:	clr.w	d0
	move.b	O_IDX(a3),d0
	sub.b	#5,d0
	bcs	9f			! no extension
	lsl.w	#2,d0
	lea	EATAB,a0
	move.l	0(a0,d0.w),a0
	move.l	O_VAL(a3),d0
	jmp	(a0)
9:	rts
EADISP:	bsr	RNG16			! d16(An)
	bra	EMITW
EAABSW:	bsr	RNG16			! abs.W
	bra	EMITW
EAPC:	move.l	d0,d2			! d16(PC)
	bsr	EXTADR
	sub.l	d0,d2
	move.l	d2,d0
	bsr	RNG16
	bra	EMITW
EAPCX:	move.l	d0,d2			! d8(PC,Xn)
	bsr	EXTADR
	sub.l	d0,d2
	move.l	d2,d0
EAINDX:	bsr	RNG8			! d8(An,Xn)
	and.w	#0xFF,d0
	clr.w	d1
	move.b	O_XREG(a3),d1
	lsl.w	#8,d1
	lsl.w	#4,d1
	or.w	d1,d0
	tst.b	O_XL(a3)
	beq	1f
	or.w	#0x800,d0
1:	bra	EMITW
EAIMM:	cmp.b	#4,d7			! #data
	beq	EMITL
	cmp.b	#2,d7
	beq	1f
	bsr	RNGU8
	and.w	#0xFF,d0
	bra	EMITW
1:	bsr	RNGU16
	bra	EMITW

! GETSZ - d6 = size field (0 B, 1 W, 2 L), d7 = bytes; default W
GETSZ:	move.b	msize,d7
	bne	1f
	move.b	#2,d7
1:	cmp.b	#8,d7
	beq	ASMBAD
	clr.w	d6
	move.b	d7,d6
	lsr.b	#1,d6
	and.l	#0xFF,d7
	rts

! NEED - nops must be d0.b
NEED:	cmp.b	nops,d0
	bne	ASMBAD
	rts

! ADDEA - d5 |= the effective address field of a3
ADDEA:	bsr	EAFLD
	or.w	d0,d5
	rts

! REGTO9 - d5 |= the register of a3 << 9
REGTO9:	clr.w	d0
	move.b	O_REG(a3),d0
	lsl.w	#8,d0
	add.w	d0,d0
	or.w	d0,d5
	rts

! SZTO6 - d5 |= d6 << 6
SZTO6:	move.w	d6,d0
	lsl.w	#6,d0
	or.w	d0,d5
	rts

! ----------------------------------------------------------------------
! Instruction handlers: d5.w = the operation word from the table,
! op1/op2 parsed, a5 past the operation word.  They finish with PUTOPW.

H_NONE:	move.b	#0,d0
	bsr	NEED
	bra	PUTOPW

H_IMM16: move.b	#1,d0			! STOP #, RTD #
	bsr	NEED
	lea	op1,a3
	move.l	#0x800,d1
	bsr	CHKM
	move.l	#2,d7
	bsr	EMITEA
	bra	PUTOPW

H_TRAP:	move.b	#1,d0
	bsr	NEED
	lea	op1,a3
	move.l	#0x800,d1
	bsr	CHKM
	move.l	O_VAL(a3),d0
	cmp.l	#16,d0
	bcc	ASMBAD
	or.w	d0,d5
	bra	PUTOPW

H_BCC:	move.b	#1,d0
	bsr	NEED
	lea	op1,a3
	move.l	#0x180,d1		! an address
	bsr	CHKM
	move.l	O_VAL(a3),d0
	move.l	asmpc,d1
	add.l	#2,d1
	sub.l	d1,d0			! displacement
	move.b	msize,d1
	cmp.b	#8,d1
	beq	1f
	cmp.b	#1,d1
	beq	1f
	cmp.b	#4,d1
	beq	ASMBAD
	bsr	RNG16			! .W
	bsr	EMITW
	bra	PUTOPW
1:	bsr	RNG8			! .S
	tst.b	d0
	bne	2f
	bsr	RNGERR			! (0 would mean .W)
2:	and.w	#0xFF,d0
	or.w	d0,d5
	bra	PUTOPW

H_DBCC:	move.b	#2,d0
	bsr	NEED
	lea	op1,a3
	move.l	#1,d1
	bsr	CHKM
	clr.w	d0
	move.b	O_REG(a3),d0
	or.w	d0,d5
	lea	op2,a3
	move.l	#0x180,d1
	bsr	CHKM
	move.l	O_VAL(a3),d0
	move.l	asmpc,d1
	add.l	#2,d1
	sub.l	d1,d0
	bsr	RNG16
	bsr	EMITW
	bra	PUTOPW

H_SCC:	move.b	#1,d0
	bsr	NEED
	lea	op1,a3
	move.l	#M_DALT,d1
	bsr	CHKM
	bsr	ADDEA
	move.l	#1,d7
	bsr	EMITEA
	bra	PUTOPW

H_MOVE:	move.b	#2,d0
	bsr	NEED
	lea	op1,a3
	lea	op2,a2
	move.b	O_KIND(a3),d0
	move.b	O_KIND(a2),d1
	cmp.b	#K_USP,d0		! USP,An
	bne	1f
	move.w	#0x4E68,d5
	move.l	a2,a3
	bra	MOVUSP
1:	cmp.b	#K_USP,d1		! An,USP
	bne	2f
	move.w	#0x4E60,d5
MOVUSP:	move.b	#1,d1
	bsr	ISIDX
	bne	ASMBAD
	clr.w	d0
	move.b	O_REG(a3),d0
	or.w	d0,d5
	bra	PUTOPW
2:	move.w	#0x46C0,d5		! <ea>,SR
	cmp.b	#K_SR,d1
	beq	3f
	move.w	#0x44C0,d5		! <ea>,CCR
	cmp.b	#K_CCR,d1
	bne	4f
3:	move.l	#M_DATA,d1
	bsr	CHKM
	bsr	ADDEA
	move.l	#2,d7
	bsr	EMITEA
	bra	PUTOPW
4:	move.w	#0x40C0,d5		! SR,<ea>
	cmp.b	#K_SR,d0
	beq	5f
	move.w	#0x42C0,d5		! CCR,<ea> (68010)
	cmp.b	#K_CCR,d0
	bne	6f
5:	move.l	a2,a3
	move.l	#M_DALT,d1
	bsr	CHKM
	bsr	ADDEA
	move.l	#2,d7
	bsr	EMITEA
	bra	PUTOPW
6:	move.b	#1,d1			! to An: MOVEA
	move.l	a2,a3
	bsr	ISIDX
	beq	H_MOVA0
	bsr	GETSZ
	lea	op1,a3
	bsr	MOVSRC
	clr.w	d5
	move.b	MOVSZ(pc,d6.w),d5
	lsl.w	#8,d5
	lsl.w	#4,d5
	or.w	d0,d5			! (the source field)
	lea	op2,a3
	move.l	#M_DALT,d1
	bsr	CHKM
	bsr	EAFLD			! destination: reg << 9 | mode << 6
	move.w	d0,d1
	and.w	#7,d1
	lsl.w	#8,d1
	add.w	d1,d1
	or.w	d1,d5
	and.w	#0x38,d0
	lsl.w	#3,d0
	or.w	d0,d5
	lea	op1,a3
	bsr	EMITEA
	lea	op2,a3
	bsr	EMITEA
	bra	PUTOPW
MOVSZ:	.data1	1, 3, 2, 0

! MOVSRC - the source operand a3 (any mode; An not .B): d0 = its field
MOVSRC:	move.l	#M_ALL,d1
	bsr	CHKM
	cmp.b	#1,O_IDX(a3)
	bne	1f
	tst.w	d6
	beq	ASMBAD
1:	bra	EAFLD

H_MOVEA: move.b	#2,d0
	bsr	NEED
	lea	op2,a3
	move.b	#1,d1
	bsr	ISIDX
	bne	ASMBAD
H_MOVA0: bsr	GETSZ
	tst.w	d6
	beq	ASMBAD			! no .B
	clr.w	d5
	move.b	MOVSZ(pc,d6.w),d5
	lsl.w	#8,d5
	lsl.w	#4,d5
	or.w	#0x40,d5
	lea	op2,a3
	bsr	REGTO9
	lea	op1,a3
	bsr	MOVSRC
	or.w	d0,d5
	bsr	EMITEA
	bra	PUTOPW

H_MOVEQ: move.b	#2,d0
	bsr	NEED
	lea	op1,a3
	move.l	#0x800,d1
	bsr	CHKM
	move.l	O_VAL(a3),d0
	bsr	RNGU8
	and.w	#0xFF,d0
	or.w	d0,d5
	lea	op2,a3
	move.l	#1,d1
	bsr	CHKM
	bsr	REGTO9
	bra	PUTOPW

! ADD / SUB (mparam 1: ADDA/SUBA, 2: ADDI/SUBI)
H_ADDSUB: move.b #2,d0
	bsr	NEED
	bsr	GETSZ
	lea	op2,a3
	move.b	#1,d1
	bsr	ISIDX
	beq	1f
	cmp.b	#1,mparam
	bne	2f
	bra	ASMBAD
1:	tst.w	d6			! An: ADDA
	beq	ASMBAD
	bsr	REGTO9
	or.w	#0xC0,d5
	cmp.w	#2,d6
	bne	3f
	or.w	#0x100,d5
3:	lea	op1,a3
	bsr	MOVSRC
	or.w	d0,d5
	bsr	EMITEA
	bra	PUTOPW
2:	lea	op1,a3
	move.b	#11,d1
	bsr	ISIDX
	beq	4f
	cmp.b	#2,mparam
	bne	5f
	bra	ASMBAD
4:	move.w	#0x0400,d0		! #: ADDI / SUBI
	cmp.w	#0xD000,d5
	bne	6f
	move.w	#0x0600,d0
6:	move.w	d0,d5
	bra	IMMOP
5:	cmp.b	#2,mparam
	beq	ASMBAD
! DNOP - <ea>,Dn (source mask ALL; An not .B) or Dn,<ea> (memory
!   alterable): d5 = base, d6 = size
DNOP:	move.l	#M_ALL,d4
DNOP0:	lea	op2,a3
	move.b	#0,d1
	bsr	ISIDX
	bne	1f
	bsr	REGTO9			! <ea>,Dn
	bsr	SZTO6
	lea	op1,a3
	move.l	d4,d1
	bsr	CHKM
	cmp.b	#1,O_IDX(a3)
	bne	2f
	tst.w	d6
	beq	ASMBAD
2:	bsr	ADDEA
	bsr	EMITEA
	bra	PUTOPW
1:	lea	op1,a3			! Dn,<ea>
	move.b	#0,d1
	bsr	ISIDX
	bne	ASMBAD
	bsr	REGTO9
	move.w	d6,d0
	add.w	#4,d0
	lsl.w	#6,d0
	or.w	d0,d5
	lea	op2,a3
	move.l	#M_MALT,d1
	bsr	CHKM
	bsr	ADDEA
	bsr	EMITEA
	bra	PUTOPW

! IMMOP - #data,<ea> (data alterable): d5 = the immediate opcode
IMMOP:	bsr	SZTO6
	lea	op2,a3
	move.l	#M_DALT,d1
	bsr	CHKM
	bsr	ADDEA
	lea	op1,a3
	bsr	EMITEA
	lea	op2,a3
	bsr	EMITEA
	bra	PUTOPW

! #data to CCR / SR: d0 = the immediate opcode
TOCCR:	lea	op2,a3
	move.b	O_KIND(a3),d1
	cmp.b	#K_CCR,d1
	beq	1f
	cmp.b	#K_SR,d1
	beq	2f
	rts
1:	or.w	#0x3C,d0
	move.l	#1,d7
	bra	3f
2:	or.w	#0x7C,d0
	move.l	#2,d7
3:	move.w	d0,d5
	lea	op1,a3
	move.l	#0x800,d1
	bsr	CHKM
	bsr	EMITEA
	add.l	#4,sp			! (done)
	bra	PUTOPW

! AND / OR (mparam 2: ANDI/ORI)
H_LOGIC: move.b	#2,d0
	bsr	NEED
	clr.w	d0			! the immediate opcode
	cmp.w	#0xC000,d5
	bne	1f
	move.w	#0x0200,d0
1:	move.w	d0,immop
	bsr	TOCCR			! (may finish the instruction)
	bsr	GETSZ
	move.w	immop,d0
	lea	op1,a3
	move.b	#11,d1
	bsr	ISIDX
	beq	2f
	cmp.b	#2,mparam
	beq	ASMBAD
	move.l	#M_DATA,d4
	bra	DNOP0
2:	move.w	d0,d5
	bra	IMMOP

! EOR (mparam 2: EORI)
H_EOR:	move.b	#2,d0
	bsr	NEED
	move.w	#0x0A00,d0
	bsr	TOCCR
	bsr	GETSZ
	lea	op1,a3
	move.b	#11,d1
	bsr	ISIDX
	bne	1f
	move.w	#0x0A00,d5
	bra	IMMOP
1:	cmp.b	#2,mparam
	beq	ASMBAD
	move.b	#0,d1			! Dn,<ea>
	bsr	ISIDX
	bne	ASMBAD
	bsr	REGTO9
	bsr	SZTO6
	lea	op2,a3
	move.l	#M_DALT,d1
	bsr	CHKM
	bsr	ADDEA
	bsr	EMITEA
	bra	PUTOPW

! CMP (mparam 1: CMPA, 2: CMPI)
H_CMP:	move.b	#2,d0
	bsr	NEED
	bsr	GETSZ
	tst.b	mparam
	bne	1f
	lea	op1,a3			! (Ay)+,(Ax)+: CMPM
	move.b	#3,d1
	bsr	ISIDX
	bne	1f
	lea	op2,a3
	bsr	ISIDX
	beq	CMPM0
1:	lea	op2,a3
	move.b	#1,d1
	bsr	ISIDX
	beq	2f
	cmp.b	#1,mparam
	beq	ASMBAD
	lea	op1,a3
	move.b	#11,d1
	bsr	ISIDX
	beq	3f
	cmp.b	#2,mparam
	beq	ASMBAD
	lea	op2,a3			! <ea>,Dn
	move.b	#0,d1
	bsr	ISIDX
	bne	ASMBAD
	bra	DNOP
3:	move.w	#0x0C00,d5		! CMPI
	bra	IMMOP
2:	tst.w	d6			! CMPA
	beq	ASMBAD
	move.w	#0xB0C0,d5
	cmp.w	#2,d6
	bne	4f
	or.w	#0x100,d5
4:	bsr	REGTO9
	lea	op1,a3
	bsr	MOVSRC
	or.w	d0,d5
	bsr	EMITEA
	bra	PUTOPW

H_CMPM:	move.b	#2,d0
	bsr	NEED
	bsr	GETSZ
	lea	op1,a3
	move.b	#3,d1
	bsr	ISIDX
	bne	ASMBAD
	lea	op2,a3
	bsr	ISIDX
	bne	ASMBAD
CMPM0:	move.w	#0xB108,d5
	bsr	SZTO6
	lea	op2,a3
	bsr	REGTO9
	lea	op1,a3
	clr.w	d0
	move.b	O_REG(a3),d0
	or.w	d0,d5
	bra	PUTOPW

! ADDQ / SUBQ
H_QUICK: move.b	#2,d0
	bsr	NEED
	bsr	GETSZ
	lea	op1,a3
	move.l	#0x800,d1
	bsr	CHKM
	move.l	O_VAL(a3),d0
	sub.l	#1,d0
	cmp.l	#8,d0
	bcc	ASMBAD			! 1-8
	add.w	#1,d0
	and.w	#7,d0
	lsl.w	#8,d0
	add.w	d0,d0
	or.w	d0,d5
	bsr	SZTO6
	lea	op2,a3
	move.l	#M_ALT,d1
	bsr	CHKM
	cmp.b	#1,O_IDX(a3)
	bne	1f
	tst.w	d6
	beq	ASMBAD
1:	bsr	ADDEA
	bsr	EMITEA
	bra	PUTOPW

! ADDX / SUBX (mparam 0), ABCD / SBCD (mparam 1: byte only)
H_XOP:	move.b	#2,d0
	bsr	NEED
	bsr	GETSZ
	tst.b	mparam
	beq	1f
	tst.w	d6
	beq	2f
	cmp.b	#2,d7
	bne	ASMBAD
	tst.b	msize
	bne	ASMBAD
	clr.w	d6
	bra	2f
1:	bsr	SZTO6
2:	lea	op1,a3
	clr.w	d0
	move.b	O_REG(a3),d0
	or.w	d0,d5
	move.b	#0,d1
	bsr	ISIDX
	beq	3f
	move.b	#4,d1
	bsr	ISIDX
	bne	ASMBAD
	or.w	#8,d5			! -(Ay),-(Ax)
3:	lea	op2,a3
	bsr	ISIDX
	bne	ASMBAD
	bsr	REGTO9
	bra	PUTOPW

! CLR NEG NEGX NOT TST
H_UNARY: move.b	#1,d0
	bsr	NEED
	bsr	GETSZ
	bsr	SZTO6
	lea	op1,a3
	move.l	#M_DALT,d1
	bsr	CHKM
	bsr	ADDEA
	bsr	EMITEA
	bra	PUTOPW

! TAS NBCD (mparam 0: data alterable), PEA JMP JSR (1: control)
H_EAONLY: move.b #1,d0
	bsr	NEED
	lea	op1,a3
	move.l	#M_DALT,d1
	tst.b	mparam
	beq	1f
	move.l	#M_CTRL,d1
1:	bsr	CHKM
	bsr	ADDEA
	move.l	#2,d7
	bsr	EMITEA
	bra	PUTOPW

! EXT (mparam: forced size for EXTW / EXTL)
H_EXT:	move.b	#1,d0
	bsr	NEED
	move.b	mparam,d0
	beq	1f
	move.b	d0,msize
1:	bsr	GETSZ
	tst.w	d6
	beq	ASMBAD
	move.w	#0x4880,d5
	cmp.w	#2,d6
	bne	H_SWAP0
	move.w	#0x48C0,d5
	bra	H_SWAP0
H_SWAP:	move.b	#1,d0
	bsr	NEED
H_SWAP0: lea	op1,a3
	move.l	#1,d1
	bsr	CHKM
	clr.w	d0
	move.b	O_REG(a3),d0
	or.w	d0,d5
	bra	PUTOPW

! shifts and rotates: mparam = type (0 AS, 1 LS, 2 ROX, 3 RO) | left << 2
H_SHIFT: clr.w	d4
	move.b	mparam,d4
	move.w	d4,d3
	and.w	#3,d3			! type
	lsr.w	#2,d4			! direction
	lsl.w	#8,d4
	cmp.b	#1,nops
	bne	2f
	lea	op1,a3			! one operand
	move.b	#0,d1
	bsr	ISIDX
	bne	1f
	move.l	#1,O_VAL(a3)		! Dn: as #1,Dn
	move.b	#11,O_IDX(a3)
	move.l	(a3),op2
	move.l	4(a3),op2+4
	move.l	8(a3),op2+8
	move.l	12(a3),op2+12
	move.b	#0,op2+O_IDX
	bra	3f
1:	move.b	msize,d0		! memory: word only
	beq	4f
	cmp.b	#2,d0
	bne	ASMBAD
4:	move.w	#0xE0C0,d5
	or.w	d4,d5
	lsl.w	#8,d3
	add.w	d3,d3
	or.w	d3,d5
	move.l	#M_MALT,d1
	bsr	CHKM
	bsr	ADDEA
	move.l	#2,d7
	bsr	EMITEA
	bra	PUTOPW
2:	move.b	#2,d0
	bsr	NEED
3:	bsr	GETSZ
	move.w	#0xE000,d5
	or.w	d4,d5
	lsl.w	#3,d3
	or.w	d3,d5
	bsr	SZTO6
	lea	op2,a3
	move.b	#0,d1
	bsr	ISIDX
	bne	ASMBAD
	clr.w	d0
	move.b	O_REG(a3),d0
	or.w	d0,d5
	lea	op1,a3
	bsr	ISIDX
	bne	5f
	or.w	#0x20,d5		! Dx,Dy
	bsr	REGTO9
	bra	PUTOPW
5:	move.b	#11,d1			! #n,Dy
	bsr	ISIDX
	bne	ASMBAD
	move.l	O_VAL(a3),d0
	sub.l	#1,d0
	cmp.l	#8,d0
	bcc	ASMBAD
	add.w	#1,d0
	and.w	#7,d0
	lsl.w	#8,d0
	add.w	d0,d0
	or.w	d0,d5
	bra	PUTOPW

! BTST BCHG BCLR BSET (mparam = operation)
H_BIT:	move.b	#2,d0
	bsr	NEED
	clr.w	d0
	move.b	mparam,d0
	lsl.w	#6,d0
	or.w	d0,d5
	move.l	#M_DALT,d4
	tst.b	mparam
	bne	1f
	move.l	#M_DATA,d4		! BTST
1:	lea	op1,a3
	move.b	#0,d1
	bsr	ISIDX
	bne	2f
	or.w	#0x100,d5		! Dn,<ea>
	bsr	REGTO9
	bra	3f
2:	move.b	#11,d1			! #n,<ea>
	bsr	ISIDX
	bne	ASMBAD
	or.w	#0x800,d5
	bclr	#11,d4			! (no #data destination)
	move.l	O_VAL(a3),d0
	and.w	#0xFF,d0
	bsr	EMITW
3:	lea	op2,a3
	move.l	d4,d1
	bsr	CHKM
	bsr	ADDEA
	move.l	#1,d7
	bsr	EMITEA
	bra	PUTOPW

H_LEA:	move.b	#2,d0
	bsr	NEED
	lea	op2,a3
	move.b	#1,d1
	bsr	ISIDX
	bne	ASMBAD
	bsr	REGTO9
	lea	op1,a3
	move.l	#M_CTRL,d1
	bsr	CHKM
	bsr	ADDEA
	bsr	EMITEA
	bra	PUTOPW

H_LINK:	move.b	#2,d0
	bsr	NEED
	lea	op1,a3
	move.l	#2,d1
	bsr	CHKM
	clr.w	d0
	move.b	O_REG(a3),d0
	or.w	d0,d5
	lea	op2,a3
	move.l	#0x800,d1
	bsr	CHKM
	move.l	O_VAL(a3),d0
	bsr	RNG16
	bsr	EMITW
	bra	PUTOPW

H_UNLK:	move.b	#1,d0
	bsr	NEED
	lea	op1,a3
	move.l	#2,d1
	bsr	CHKM
	clr.w	d0
	move.b	O_REG(a3),d0
	or.w	d0,d5
	bra	PUTOPW

H_EXG:	move.b	#2,d0
	bsr	NEED
	lea	op1,a3
	lea	op2,a2
	move.l	#3,d1
	bsr	CHKM
	exg	a2,a3
	bsr	CHKM
	exg	a2,a3
	move.b	O_IDX(a3),d0
	move.b	O_IDX(a2),d1
	move.w	#0xC140,d5		! Dx,Dy
	cmp.b	d0,d1
	bne	1f
	tst.b	d0
	beq	2f
	move.w	#0xC148,d5		! Ax,Ay
	bra	2f
1:	move.w	#0xC188,d5		! Dx,Ay
	tst.b	d0
	beq	2f
	exg	a2,a3
2:	bsr	REGTO9
	clr.w	d0
	move.b	O_REG(a2),d0
	or.w	d0,d5
	bra	PUTOPW

! MULU MULS DIVU DIVS CHK: <ea>,Dn (word)
H_MULDIV: move.b #2,d0
	bsr	NEED
	move.b	msize,d0
	beq	1f
	cmp.b	#2,d0
	bne	ASMBAD
1:	lea	op2,a3
	move.l	#1,d1
	bsr	CHKM
	bsr	REGTO9
	lea	op1,a3
	move.l	#M_DATA,d1
	bsr	CHKM
	bsr	ADDEA
	move.l	#2,d7
	bsr	EMITEA
	bra	PUTOPW

! MOVEM list,<ea> / <ea>,list
H_MOVEM: move.b	#2,d0
	bsr	NEED
	bsr	GETSZ
	tst.w	d6
	beq	ASMBAD
	move.w	#0x4880,d5
	cmp.w	#2,d6
	bne	1f
	or.w	#0x40,d5
1:	lea	op2,a3
	bsr	TOLIST
	beq	3f
	lea	op1,a3			! list,<ea>
	bsr	TOLIST
	bne	ASMBAD
	move.w	O_MASK(a3),d3
	lea	op2,a3
	move.l	#M_CALT+0x10,d1		! (or -(An))
	bsr	CHKM
	cmp.b	#4,O_IDX(a3)
	bne	2f
	clr.w	d0			! -(An): reversed mask
	move.w	#15,d1
4:	lsr.w	#1,d3
	roxl.w	#1,d0
	dbra	d1,4b
	move.w	d0,d3
	bra	2f
3:	or.w	#0x400,d5		! <ea>,list
	move.w	O_MASK(a3),d3
	lea	op1,a3
	move.l	#M_CTRL+0x8,d1		! (or (An)+)
	bsr	CHKM
2:	bsr	ADDEA
	move.w	d3,d0
	bsr	EMITW
	bsr	EMITEA
	bra	PUTOPW

! TOLIST - Z if the operand a3 is a register list (a single Dn/An
!   becomes one)
TOLIST:	cmp.b	#K_LIST,O_KIND(a3)
	beq	2f
	tst.b	O_KIND(a3)
	bne	1f
	move.b	O_IDX(a3),d0
	cmp.b	#2,d0
	bcc	1f
	lsl.b	#3,d0
	add.b	O_REG(a3),d0
	clr.w	d1
	bset	d0,d1
	move.w	d1,O_MASK(a3)
	move.b	#K_LIST,O_KIND(a3)
2:	move.w	#CC_Z,ccr
	rts
1:	move.w	#0,ccr
	rts

! MOVEP Dx,d(Ay) / d(Ay),Dx
H_MOVEP: move.b	#2,d0
	bsr	NEED
	bsr	GETSZ
	tst.w	d6
	beq	ASMBAD
	cmp.w	#2,d6
	bne	1f
	or.w	#0x40,d5
1:	lea	op1,a3
	lea	op2,a2
	move.b	#0,d1
	bsr	ISIDX
	bne	2f
	or.w	#0x80,d5		! register to memory
	exg	a2,a3
2:	move.l	#0x24,d1		! (Ay) or d(Ay)
	bsr	CHKM
	clr.w	d0
	move.b	O_REG(a3),d0
	or.w	d0,d5
	move.l	O_VAL(a3),d0
	bsr	RNG16
	bsr	EMITW
	exg	a2,a3			! the data register
	move.b	#0,d1
	bsr	ISIDX
	bne	ASMBAD
	bsr	REGTO9
	bra	PUTOPW

! ----------------------------------------------------------------------
! Directives: a5 = the code pointer (no operation word)

! DC.B / DC.W / DC.L list (strings in DC.B)
H_DC:	bsr	GETSZ
	move.b	d7,dcsize
1:	bsr	SKIPSP
	bsr	EXPRV
	tst.b	d6
	bpl	2f
	cmp.b	#1,dcsize		! a string: DC.B only
	bne	ASMBAD
	bsr	PUTSTR
	bra	3f
2:	bsr	SFIXA
	move.b	dcsize,d7
	bsr	PUTNUM
3:	bsr	SKIPSP
	cmp.b	#',',d4
	bne	4f
	add.l	#1,a4
	bra	1b
4:	rts

! EQUB EQUW EQUD (mparam size), EQUS (mparam 0): one expression
H_EQU:	bsr	SKIPSP
	bsr	EXPRV
	move.b	mparam,d7
	bne	1f
	tst.b	d6			! EQUS
	bpl	ASMBAD
	bra	PUTSTR
1:	tst.b	d6
	bmi	ASMBAD
	bsr	SFIXA
	move.b	mparam,d7
	bra	PUTNUM

! DS.B / DS.W / DS.L count: reserve (zeroed)
H_DS:	bsr	GETSZ
	move.l	d7,-(sp)
	bsr	SKIPSP
	bsr	EXPRA
	move.l	(sp)+,d7
	tst.l	d0
	bmi	ASMBAD
	cmp.l	#0x10000,d0
	bcc	ASMBAD
	mulu	d7,d0
	bra	2f
1:	clr.b	(a5)+
2:	sub.l	#1,d0
	bpl	1b
	rts

! ALIGN / EVEN - pad to an even P%
H_ALIGN: bsr	EXTADR
	btst	#0,d0
	beq	1f
	clr.b	(a5)+
1:	rts

! OPT n - the assembler options (LISTON high nibble)
H_OPT:	bsr	SKIPSP
	bsr	EXPRA
	lsl.b	#4,d0
	move.b	LISTON,d1
	and.b	#0x0F,d1
	or.b	d0,d1
	move.b	d1,LISTON
	rts

! SFIXA - the number in d0/d1 as an integer in d0
SFIXA:	tst.b	d1
	beq	1f
	.extern	SFIX
	bsr	SFIX
1:	rts

! PUTNUM - store d0 as d7 (1, 2, 4) bytes, big-endian
PUTNUM:	cmp.b	#4,d7
	beq	EMITL
	cmp.b	#2,d7
	beq	1f
	bsr	RNGU8
	move.b	d0,(a5)+
	rts
1:	bsr	RNGU16
	bra	EMITW

! PUTSTR - store the string in ACCS (a2 = end)
PUTSTR:	lea	ACCS,a0
1:	cmp.l	a2,a0
	bcc	2f
	move.b	(a0)+,(a5)+
	bra	1b
2:	rts

! ----------------------------------------------------------------------
! Tables

	.sect	.rom
	.align	2
HANDLR:	.data4	H_NONE, H_IMM16, H_TRAP, H_BCC, H_DBCC, H_SCC, H_MOVE
	.data4	H_MOVEA, H_MOVEQ, H_ADDSUB, H_LOGIC, H_EOR, H_CMP, H_CMPM
	.data4	H_QUICK, H_XOP, H_UNARY, H_EAONLY, H_EXT, H_SWAP, H_SHIFT
	.data4	H_BIT, H_LEA, H_LINK, H_UNLK, H_EXG, H_MULDIV, H_MOVEM
	.data4	H_MOVEP, H_DC, H_DS, H_EQU, H_ALIGN, H_OPT

EATAB:	.data4	EADISP, EAINDX, EAABSW, EMITL, EAPC, EAPCX, EAIMM

! size suffixes: size, letter
SIZES:	.data1	1, 'B', 2, 'W', 4, 'L', 8, 'S', 0

! conditions: 2 letters (' ' = one letter), code
CCTAB:	.ascii	"T "
	.data1	0
	.ascii	"F "
	.data1	1
	.ascii	"HI"
	.data1	2
	.ascii	"LS"
	.data1	3
	.ascii	"CC"
	.data1	4
	.ascii	"HS"
	.data1	4
	.ascii	"CS"
	.data1	5
	.ascii	"LO"
	.data1	5
	.ascii	"NE"
	.data1	6
	.ascii	"EQ"
	.data1	7
	.ascii	"VC"
	.data1	8
	.ascii	"VS"
	.data1	9
	.ascii	"PL"
	.data1	10
	.ascii	"MI"
	.data1	11
	.ascii	"GE"
	.data1	12
	.ascii	"LT"
	.data1	13
	.ascii	"GT"
	.data1	14
	.ascii	"LE"
	.data1	15
	.data1	0

! special register names: code, 3 letters (NUL padded)
REGNMS:	.data1	15, 'S', 'P', 0
	.data1	16, 'P', 'C', 0
	.data1	17, 'S', 'R', 0
	.data1	18, 'C', 'C', 'R'
	.data1	19, 'U', 'S', 'P'
	.data1	0

! mnemonics: name (8 bytes, NUL padded), class, param, operation word
	.align	2
MNTAB:
	.ascii	"NOP"
	.data1	0,0,0,0,0, C_NONE, 0
	.data2	0x4E71
	.ascii	"RTS"
	.data1	0,0,0,0,0, C_NONE, 0
	.data2	0x4E75
	.ascii	"RTE"
	.data1	0,0,0,0,0, C_NONE, 0
	.data2	0x4E73
	.ascii	"RTR"
	.data1	0,0,0,0,0, C_NONE, 0
	.data2	0x4E77
	.ascii	"RESET"
	.data1	0,0,0, C_NONE, 0
	.data2	0x4E70
	.ascii	"TRAPV"
	.data1	0,0,0, C_NONE, 0
	.data2	0x4E76
	.ascii	"ILLEGAL"
	.data1	0, C_NONE, 0
	.data2	0x4AFC
	.ascii	"STOP"
	.data1	0,0,0,0, C_IMM16, 0
	.data2	0x4E72
	.ascii	"RTD"
	.data1	0,0,0,0,0, C_IMM16, 0
	.data2	0x4E74
	.ascii	"TRAP"
	.data1	0,0,0,0, C_TRAP, 0
	.data2	0x4E40
	.ascii	"MOVE"
	.data1	0,0,0,0, C_MOVE, 0
	.data2	0
	.ascii	"MOVEA"
	.data1	0,0,0, C_MOVEA, 0
	.data2	0
	.ascii	"MOVEQ"
	.data1	0,0,0, C_MOVEQ, 0
	.data2	0x7000
	.ascii	"MOVEM"
	.data1	0,0,0, C_MOVEM, 0
	.data2	0x4880
	.ascii	"MOVEP"
	.data1	0,0,0, C_MOVEP, 0
	.data2	0x0108
	.ascii	"ADD"
	.data1	0,0,0,0,0, C_ADDSUB, 0
	.data2	0xD000
	.ascii	"ADDA"
	.data1	0,0,0,0, C_ADDSUB, 1
	.data2	0xD000
	.ascii	"ADDI"
	.data1	0,0,0,0, C_ADDSUB, 2
	.data2	0xD000
	.ascii	"SUB"
	.data1	0,0,0,0,0, C_ADDSUB, 0
	.data2	0x9000
	.ascii	"SUBA"
	.data1	0,0,0,0, C_ADDSUB, 1
	.data2	0x9000
	.ascii	"SUBI"
	.data1	0,0,0,0, C_ADDSUB, 2
	.data2	0x9000
	.ascii	"AND"
	.data1	0,0,0,0,0, C_LOGIC, 0
	.data2	0xC000
	.ascii	"ANDI"
	.data1	0,0,0,0, C_LOGIC, 2
	.data2	0xC000
	.ascii	"OR"
	.data1	0,0,0,0,0,0, C_LOGIC, 0
	.data2	0x8000
	.ascii	"ORI"
	.data1	0,0,0,0,0, C_LOGIC, 2
	.data2	0x8000
	.ascii	"EOR"
	.data1	0,0,0,0,0, C_EOR, 0
	.data2	0xB100
	.ascii	"EORI"
	.data1	0,0,0,0, C_EOR, 2
	.data2	0xB100
	.ascii	"CMP"
	.data1	0,0,0,0,0, C_CMP, 0
	.data2	0xB000
	.ascii	"CMPA"
	.data1	0,0,0,0, C_CMP, 1
	.data2	0xB000
	.ascii	"CMPI"
	.data1	0,0,0,0, C_CMP, 2
	.data2	0xB000
	.ascii	"CMPM"
	.data1	0,0,0,0, C_CMPM, 0
	.data2	0xB108
	.ascii	"ADDQ"
	.data1	0,0,0,0, C_QUICK, 0
	.data2	0x5000
	.ascii	"SUBQ"
	.data1	0,0,0,0, C_QUICK, 0
	.data2	0x5100
	.ascii	"ADDX"
	.data1	0,0,0,0, C_XOP, 0
	.data2	0xD100
	.ascii	"SUBX"
	.data1	0,0,0,0, C_XOP, 0
	.data2	0x9100
	.ascii	"ABCD"
	.data1	0,0,0,0, C_XOP, 1
	.data2	0xC100
	.ascii	"SBCD"
	.data1	0,0,0,0, C_XOP, 1
	.data2	0x8100
	.ascii	"CLR"
	.data1	0,0,0,0,0, C_UNARY, 0
	.data2	0x4200
	.ascii	"NEG"
	.data1	0,0,0,0,0, C_UNARY, 0
	.data2	0x4400
	.ascii	"NEGX"
	.data1	0,0,0,0, C_UNARY, 0
	.data2	0x4000
	.ascii	"NOT"
	.data1	0,0,0,0,0, C_UNARY, 0
	.data2	0x4600
	.ascii	"TST"
	.data1	0,0,0,0,0, C_UNARY, 0
	.data2	0x4A00
	.ascii	"TAS"
	.data1	0,0,0,0,0, C_EAONLY, 0
	.data2	0x4AC0
	.ascii	"NBCD"
	.data1	0,0,0,0, C_EAONLY, 0
	.data2	0x4800
	.ascii	"PEA"
	.data1	0,0,0,0,0, C_EAONLY, 1
	.data2	0x4840
	.ascii	"JMP"
	.data1	0,0,0,0,0, C_EAONLY, 1
	.data2	0x4EC0
	.ascii	"JSR"
	.data1	0,0,0,0,0, C_EAONLY, 1
	.data2	0x4E80
	.ascii	"EXT"
	.data1	0,0,0,0,0, C_EXT, 0
	.data2	0x4880
	.ascii	"EXTW"
	.data1	0,0,0,0, C_EXT, 2
	.data2	0x4880
	.ascii	"EXTL"
	.data1	0,0,0,0, C_EXT, 4
	.data2	0x48C0
	.ascii	"SWAP"
	.data1	0,0,0,0, C_SWAP, 0
	.data2	0x4840
	.ascii	"ASL"
	.data1	0,0,0,0,0, C_SHIFT, 4
	.data2	0
	.ascii	"ASR"
	.data1	0,0,0,0,0, C_SHIFT, 0
	.data2	0
	.ascii	"LSL"
	.data1	0,0,0,0,0, C_SHIFT, 5
	.data2	0
	.ascii	"LSR"
	.data1	0,0,0,0,0, C_SHIFT, 1
	.data2	0
	.ascii	"ROXL"
	.data1	0,0,0,0, C_SHIFT, 6
	.data2	0
	.ascii	"ROXR"
	.data1	0,0,0,0, C_SHIFT, 2
	.data2	0
	.ascii	"ROL"
	.data1	0,0,0,0,0, C_SHIFT, 7
	.data2	0
	.ascii	"ROR"
	.data1	0,0,0,0,0, C_SHIFT, 3
	.data2	0
	.ascii	"BTST"
	.data1	0,0,0,0, C_BIT, 0
	.data2	0
	.ascii	"BCHG"
	.data1	0,0,0,0, C_BIT, 1
	.data2	0
	.ascii	"BCLR"
	.data1	0,0,0,0, C_BIT, 2
	.data2	0
	.ascii	"BSET"
	.data1	0,0,0,0, C_BIT, 3
	.data2	0
	.ascii	"LEA"
	.data1	0,0,0,0,0, C_LEA, 0
	.data2	0x41C0
	.ascii	"LINK"
	.data1	0,0,0,0, C_LINK, 0
	.data2	0x4E50
	.ascii	"UNLK"
	.data1	0,0,0,0, C_UNLK, 0
	.data2	0x4E58
	.ascii	"EXG"
	.data1	0,0,0,0,0, C_EXG, 0
	.data2	0
	.ascii	"MULU"
	.data1	0,0,0,0, C_MULDIV, 0
	.data2	0xC0C0
	.ascii	"MULS"
	.data1	0,0,0,0, C_MULDIV, 0
	.data2	0xC1C0
	.ascii	"DIVU"
	.data1	0,0,0,0, C_MULDIV, 0
	.data2	0x80C0
	.ascii	"DIVS"
	.data1	0,0,0,0, C_MULDIV, 0
	.data2	0x81C0
	.ascii	"CHK"
	.data1	0,0,0,0,0, C_MULDIV, 0
	.data2	0x4180
	.ascii	"DC"
	.data1	0,0,0,0,0,0, C_DC, 0
	.data2	0
	.ascii	"DS"
	.data1	0,0,0,0,0,0, C_DS, 0
	.data2	0
	.ascii	"EQUB"
	.data1	0,0,0,0, C_EQU, 1
	.data2	0
	.ascii	"EQUW"
	.data1	0,0,0,0, C_EQU, 2
	.data2	0
	.ascii	"EQUD"
	.data1	0,0,0,0, C_EQU, 4
	.data2	0
	.ascii	"EQUS"
	.data1	0,0,0,0, C_EQU, 0
	.data2	0
	.ascii	"ALIGN"
	.data1	0,0,0, C_ALIGN, 0
	.data2	0
	.ascii	"EVEN"
	.data1	0,0,0,0, C_ALIGN, 0
	.data2	0
	.ascii	"OPT"
	.data1	0,0,0,0,0, C_OPT, 0
	.data2	0
	.data1	0

	.sect	.bss
	.align	2
asmsp:	.space	4		! sp in ASSEM (for ASMBAD)
asmpc:	.space	4		! P% at the start of the statement
asmdst:	.space	4		! where its code goes (P% or O%)
asmstm:	.space	4		! its source text (for the listing)
curop:	.space	4		! the operand record being parsed
eend:	.space	4		! EXPRA: the end of the expression
esva5:	.space	4		! EXPRA: a5
mname:	.space	8		! mnemonic, NUL padded
op1:	.space	16
op2:	.space	16
mopw:	.space	2
immop:	.space	2		! AND/OR: the immediate opcode
mtext:	.space	16		! mnemonic as read (with the suffix)
mtry:	.space	20		! FINDMN: a candidate
mtlen:	.space	2		! length of mtext
tokpos:	.space	2		! GETMN: the last token's text in mtext
toklen:	.space	2		! (0: no token)
mclass:	.space	1
mparam:	.space	1
msize:	.space	1		! 0, 1 B, 2 W, 4 L, 8 S
nops:	.space	1
dcsize:	.space	1
	.align	2
abuf:	.space	256		! expression copy
