#
! exec.s - BBC BASIC 68k: statement execution, part 1 (from EXEC.Z80):
! the dispatcher and the statements.  Part 2 (exec2.s) has FN/PROC, LOCAL,
! assignment, DIM and the subroutines.
!
! (C) Copyright R.T. Russell 1981-2025 (Z80 original); 68000 translation
! for Minix on the rosco_m68k.  See CONVENTIONS.md and PHASE4.md.
!
! THE NAME BBC BASIC IS USED WITH THE PERMISSION OF THE BRITISH
! BROADCASTING CORPORATION AND IS NOT TRANSFERRABLE TO A FORKED OR
! DERIVED WORK.
!
! Registers: a4 = IY (text pointer), a5 = IX, d4.b = A, d6.b = A'
! (expression type); numbers d0/d1 (and d2/d3).  Statements end by
! jumping to XEQ.
!
! Stack frames (sp upwards; the marker is the return address of the
! "bsr XEQ" that starts the body):
!   FOR:    0 FORCHK, 4 variable, 8 text, 12 step mantissa, 16 step exp,
!           17 compare op (FPP 8 or 12), 18 limit mantissa, 22 limit exp,
!           23 type                                         (24 bytes)
!   REPEAT: 0 REPCHK, 4 text after REPEAT                   (8)
!   WHILE:  0 WHICHK, 4 text at the WHILE condition         (8)
!   GOSUB:  0 GOSCHK, 4 text after GOSUB                    (8)
! (FN, PROC, LOCAL: see exec2.s)

#include "bbc.h"

	.sect	.text
	.sect	.rom
	.sect	.data
	.sect	.bss

	.define	XEQ, RUN0, CHAIN0, ESCAPE, SYNTAX, VAR, XEQ0, NOSUCH, BADUSE
	.define	MISMAT, ERROR0E, FORCHK, REPCHK, WHICHK, GOSCHK, EXTRAS, IF1
	.define	GOTO1, SPANX, END, USR

	.extern	ASSEM, ERROR, REPORT, WARM, CLOOP, SAYLN, LOAD0, CRLF, PBCDL
	.extern	TELL, FINDL, SETLIN, CLEAR, GETVAR, PUTVAR, GETDEF, LOCATE
	.extern	CREATE, OUTCHR, EXTERR, BYE, NXT, NLIST, CSRON, CSROFF
	.extern	OSWRCH, OSLINE, OSSHUT, OSBPUT, OSBGET, CLRSCN, PUTCSR, PUTIME
	.extern	PUTIMS, PUTPTR, OSCALL, OSCLI, TRAP, GETIME
	.extern	SOUND, CLG, DRAW, ENVEL, GCOL, MODE, MOVE, PLOT, COLOUR
	.extern	CIRCLE, ELLIPS, FILL, MOUSE, ORIGIN, RECTAN, LINE, WAIT, TINT
	.extern	SYS
	.extern	STR, HEXSTR, EXPR, EXPRN, EXPRI, EXPRS, ITEMI, CONS, LOADS
	.extern	VAL0, SFIX, TEST, LOAD4, LOADN, DLOAD5, FPP, COMMA, BRAKET
	.extern	PUSHS, POPS, ZERO, SCP, LETARR, LDLE4, STLE4, LDDESC
	.extern	ACCS, PAGE, LOMEM, HIMEM, FREE, BUFFER, ERRTRP, ONERSP
	.extern	CURLIN, COUNT, WIDTH, STAVAR, DATPTR, RANDOM, TRACEN, LISTON
	.extern	PC, OC
	! exec2.s:
	.extern	FN, PROC, LOCAL, ENDPRO, FNEND, DIM, ASSIGN, MODIFY, MODIFS
	.extern	STOREN, STORE4, STORE5, STACCS, CHECK, RESLOC, TERMQ, SPAN
	.extern	EQUALS, FORMAT, SPACES, PTEXT, FETCHS, LINES, DSRCH, NSCAN
	.extern	NSCAN1, WSRCH, QUOTE, CHANEL, CHNL, LOCCHK
	.extern	X14OR5, MUL16

LF	= 0x0A
CR	= 0x0D
TAND	= 0x80
TOR	= 0x84
TERROR	= 0x85
TLINE	= 0x86
TOFF	= 0x87
TSTEP	= 0x88
TSPC	= 0x89
TTAB	= 0x8A
TELSE	= 0x8B
TTHEN	= 0x8C
TLINO	= 0x8D
TTO	= 0xB8
TCMD	= 0xC0
TWHILE	= 0xC7
TWHEN	= 0xC9
TOF	= 0xCA
TENDCASE = 0xCB
TOTHERWISE = 0xCC
TENDIF	= 0xCD
TENDWHILE = 0xCE
TCALL	= 0xD6
TDATA	= 0xDC
TDEF	= 0xDD
TFOR	= 0xE3
TGOSUB	= 0xE4
TGOTO	= 0xE5
TLOCAL	= 0xEA
TNEXT	= 0xED
TON	= 0xEE
TPROC	= 0xF2
TREM	= 0xF4
TREPEAT	= 0xF5
TRETURN	= 0xF8
TSTOP	= 0xFA
TUNTIL	= 0xFD
TEXIT	= 0x10

	.sect	.rom
	.align	4
! Statement table: tokens &C0-&FF, then &00-&10
CMDTAB:	.data4	LEFTSL, MIDSL, RITESL
	.data4	SYNTAX			! STR$
	.data4	SYNTAX			! STRING$
	.data4	SYNTAX			! EOF
	.data4	SYNTAX			! SUM
	.data4	WHILE, CASE
	.data4	SYNTAX			! WHEN
	.data4	SYNTAX			! OF
	.data4	XEQ			! ENDCASE
	.data4	SYNTAX			! OTHERWISE
	.data4	XEQ			! ENDIF
	.data4	ENDWHI			! ENDWHILE
	.data4	PTR, PAGEV, TIMEV, LOMEMV, HIMEMV, SOUND, BPUT, CALL, CHAIN
	.data4	CLR, CLOSE, CLG, CLS
	.data4	REM			! DATA
	.data4	REM			! DEF
	.data4	DIM, DRAW, END, ENDPRO, ENVEL, FOR, GOSUB, GOTO, GCOL, IF
	.data4	INPUT, LET, LOCAL, MODE, MOVE, NEXT, ON, VDU, PLOT, PRINT
	.data4	PROC, READ, REM, REPEAT, REPOR, RESTOR, RETURN, RUN, STOP
	.data4	COLOUR, TRACE, UNTIL, WIDTHV
	.data4	CLI			! OSCLI
	.data4	REM			! NUL
	.data4	CIRCLE, ELLIPS, FILL, MOUSE, ORIGIN
	.data4	BYE			! QUIT
	.data4	RECTAN, SWAP, SYS, TINT, WAIT
	.data4	SYNTAX			! INSTALL
	.data4	REM			! CR
	.data4	PUT			! Token changed
	.data4	SYNTAX			! BY
	.data4	EXIT
CMDEND:
	.sect	.text

RUN:	bsr	TERMQ
	beq	RUN0
CHAIN:	bsr	EXPRS
	move.b	#CR,(a2)
CHAIN0:	move.l	HIMEM,sp
	bsr	LOAD0
RUN0:	move.l	HIMEM,sp		! PREPARE FOR RUN
	bsr	GETIME			! RANDOMISE (the Z80 used R)
	lea	RANDOM,a0
	rol.l	#8,d0
	move.b	d0,3(a0)
	or.b	#1,3(a0)
	sne	4(a0)			! (0 or &FF, as SBC A,A)
	bsr	CLEAR
	clr.l	ERRTRP
	move.l	PAGE,a3
	bsr	DSRCH			! LOOK FOR "DATA"
	move.l	a3,DATPTR		! SET DATA POINTER
	move.l	PAGE,a4
XEQ0:	bsr	NEWLIN
	move.b	(a4),d4
	cmp.b	#TELSE,d4
	beq	MELSE			! ELSE
	cmp.b	#TWHEN,d4
	beq	WHEN			! WHEN
	cmp.b	#TOTHERWISE,d4
	beq	WHEN
XEQ:	move.l	a4,CURLIN		! ERROR POINTER
	bsr	TRAP			! CHECK KEYBOARD
XEQ1:	move.b	(a4),d4			! (NXT inline)
	cmp.b	#' ',d4
	bne	1f
	bsr	NXT
1:	add.l	#1,a4
	cmp.b	#':',d4			! SEPARATOR
	beq	XEQ1
	cmp.b	#CR,d4
	beq	XEQ0			! NEW PROGRAM LINE
	cmp.b	#0x11,d4		! &11-&7F: IMPLIED LET
	bcs	1f
	tst.b	d4
	bpl	LET0
1:	cmp.b	#TCMD,d4
	bcs	2f
	cmp.b	#0x80,d4
	bcc	3f
2:	tst.b	d4			! &80-&BF: ELSE, ERROR, LINE, OFF
	bmi	EXTRAS
3:	sub.b	#TCMD,d4		! &C0-&FF, &00-&10
	and.w	#0xFF,d4
	lsl.w	#2,d4
	lea	CMDTAB,a0
	move.l	0(a0,d4.w),a0
	bsr	NXT
	jmp	(a0)			! EXECUTE STATEMENT

! END
ENDIM:	cmp.l	PAGE,a4			! IMMEDIATE MODE ?
	bcs	CLOOP
END:	clr.b	d6
	bsr	OSSHUT			! CLOSE ALL FILES
	bra	WARM			! "Ready"

! NEWLIN - start a new program line at a4 (the length byte)
NEWLIN:	move.b	(a4),d4			! LINE LENGTH
	add.l	#3,a4
	tst.b	d4
	beq	ENDIM			! LENGTH=0, EXIT
	move.l	TRACEN,d0
	bne	1f
	rts
1:	clr.l	d2
	move.b	-1(a4),d2		! LINE NUMBER
	lsl.w	#8,d2
	move.b	-2(a4),d2
	cmp.l	d2,d0			! TRACE n: lines up to TRACEN
	bcc	2f
	rts
2:	move.b	#'[',d4			! TRACE
	bsr	OUTCHR
	move.l	d2,d0
	bsr	PBCDL
	move.b	#']',d4
	bsr	OUTCHR
	move.b	#' ',d4
	bra	OUTCHR

! ROUTINES FOR EACH STATEMENT:
!
! OSCLI
CLI:	bsr	EXPRS
	move.b	#CR,(a2)
	lea	ACCS,a3
	bsr	OSCLI
	bra	XEQ

EXTRAS:	cmp.b	#TELSE,d4
	beq	REM			! ELSE
	cmp.b	#TERROR,d4
	beq	THROW			! ERROR
	cmp.b	#TLINE,d4
	beq	LINE			! LINE
	cmp.b	#TOFF,d4
	beq	CSROFF			! OFF
	bra	SYNTAX

! REM, *
EXT:	move.l	a4,a3
	bsr	OSCLI
REM:	cmp.b	#CR,(a4)+		! FIND LINE END
	bne	REM
	bra	XEQ0

! ERROR num,string$
THROW:	bsr	EXPRI
	move.l	d0,-(sp)
	bsr	COMMA
	bsr	EXPRS
	move.l	(sp)+,d0
	clr.b	(a2)
	lea	ACCS,a0			! message to BUFFER
	lea	BUFFER,a1
	move.w	#255,d7
1:	move.b	(a0)+,(a1)+
	dbra	d7,1b
	move.b	d0,d4
	pea	BUFFER
	bra	EXTERR

! SWAP var1,var2
SWAP:	bsr	GETVAR
	bne	SWAPNZ
	move.w	d4,-(sp)
	move.l	a3,-(sp)
	bsr	COMMA
	bsr	NXT
	bsr	GETVAR
SWAPNZ:	bne	NOSUCH
	move.l	(sp)+,a2		! first variable
	move.w	(sp)+,d3		! its type
	cmp.b	d3,d4
	bne	MISMAT
	move.b	d4,d7
	and.b	#0x0F,d7
	beq	MISMAT
	move.w	d4,d1			! numeric: 1, 4 or 5 bytes
	and.w	#0x0F,d1
	move.b	d4,d7
	and.b	#0xC0,d7
	beq	SWAP1
	move.w	#4,d1			! array: the pointer
	btst	#6,d4
	bne	SWAP1
	move.w	#6,d1			! string: the descriptor
SWAP1:	sub.w	#1,d1
1:	move.b	(a3),d7
	move.b	(a2),(a3)+
	move.b	d7,(a2)+
	dbra	d1,1b
	bra	XEQ

! [LET] var = expr
LET0:	cmp.b	#'*',d4
	beq	EXT
	cmp.b	#'=',d4
	beq	FNEND
	cmp.b	#'[',d4
	beq	ASM
	sub.l	#1,a4
LET:	bsr	ASSIGN
	beq	XEQ
	bcs	SYNTAX			! "Syntax error"
	btst	#14,d5			! array? (bit 6 of the type)
	bne	LETARR			! numeric or string array
	movem.l	d5/a3,-(sp)
	bsr	EXPRS
	movem.l	(sp)+,d5/a5
	bsr	MODIFS
	bra	XEQ

! GETSTR - Get string variable
!   Outputs: d3.b = type, Z set if a comma follows
GETSTR:	bsr	GETVAR
	bne	NOSUCH
	move.b	d4,d3
	btst	#7,d4
	beq	MISMAT
	btst	#6,d4
	bne	BADUSE
	btst	#0,d3
	beq	MISMAT
	bsr	NXT
	cmp.b	#',',d4
	rts

! VAR - find a variable, creating it if needed
VAR:	bsr	GETVAR
	bne	1f
	rts
1:	bcc	PUTVAR
NOSUCH:	move.b	#26,d4			! 'No such variable'
	bra	ERROR0E
SYNTAX:	move.b	#16,d4			! "Syntax error"
	bra	ERROR0E
ESCAPE:	move.b	#17,d4			! "Escape"
	bra	ERROR0E
BADUSE:	move.b	#14,d4			! 'Bad use of array'
	bra	ERROR0E
MISMAT:	move.b	#6,d4			! 'Type mismatch'
ERROR0E: bra	ERROR

ASM0:	bsr	NEWLIN
ASM:	move.l	a4,CURLIN
	bsr	TRAP
	bsr	ASSEM
	bcs	SYNTAX
	cmp.b	#CR,d4
	beq	ASM0
	move.b	LISTON,d4
	and.b	#0x0F,d4
	or.b	#0x30,d4
	move.b	d4,LISTON
	bra	XEQ

! PRINT list...
! PRINT #channel,list...
!   d3.b = B (PRINTF: bit 0 no CR at the end, bit 1 hex),
!   d5.b = C (PRINTS: field width)
PRINT:	cmp.b	#'#',d4
	bne	PRINT0
	bsr	CHNL			! CHANNEL NO. -> d6
PRNTN1:	bsr	NLIST
	move.w	d6,-(sp)
	bsr	EXPR			! ITEM TO PRINT
	move.w	(sp)+,d7		! (d6 is the type now)
	tst.b	d6
	bmi	PRNTN2			! STRING
	move.b	d7,d6			! channel
	move.b	d0,d4			! the number, LS byte first
	bsr	OSBPUT
	lsr.l	#8,d0
	move.b	d0,d4
	bsr	OSBPUT
	lsr.l	#8,d0
	move.b	d0,d4
	bsr	OSBPUT
	lsr.l	#8,d0
	move.b	d0,d4
	bsr	OSBPUT
	move.b	d1,d4			! exponent
	bsr	OSBPUT
	bra	PRNTN1
PRNTN2:	move.b	d7,d6			! channel
	lea	ACCS,a3
1:	cmp.l	a2,a3
	bcc	2f
	move.b	(a3)+,d4
	bsr	OSBPUT
	bra	1b
2:	move.b	#CR,d4
	bsr	OSBPUT
	bra	PRNTN1

PRINT6:	move.b	#2,d3			! ~ : hex
	bra	PRINTC
PRINT8:	move.b	#1,d3			! ; : no CR, width 0
	clr.b	d5
	bra	PRINTC
PRINT9:	move.b	STAVAR,d7		! , : next field
	beq	PRINT0
	move.b	COUNT,d4
	beq	PRINT0
1:	sub.b	d7,d4
	beq	PRINT0
	bcc	1b
	neg.b	d4
	bsr	SPACES
PRINT0:	move.b	STAVAR,d5		! PRINTS
	clr.b	d3			! PRINTF
PRINTC:	bsr	TERMQ
	beq	PRINT4
	bclr	#0,d3
	add.l	#1,a4
	cmp.b	#'~',d4
	beq	PRINT6
	cmp.b	#';',d4
	beq	PRINT8
	cmp.b	#',',d4
	beq	PRINT9
	bsr	FORMAT			! SPC, TAB, '
	beq	PRINTC
	sub.l	#1,a4
	movem.w	d3/d5,-(sp)		! (sp) = B, 2(sp) = C
	bsr	EXPR			! VARIABLE TYPE
	tst.b	d6
	bmi	PRINT3			! STRING
	btst	#1,1(sp)		! hex?
	bne	1f
	bsr	STR			! DECIMAL
	bra	2f
1:	bsr	HEXSTR			! HEX
2:	move.l	a2,d7
	sub.l	#ACCS,d7		! length
	move.b	3(sp),d4		! field width
	sub.b	d7,d4
	bcs	PRINT3
	bsr	SPACES			! RIGHT JUSTIFY
PRINT3:	movem.w	(sp)+,d3/d5
	bsr	PTEXT			! PRINT
	bra	PRINTC
PRINT4:	btst	#0,d3
	bne	XEQ
	bsr	CRLF
	bra	XEQ

! ON ERROR [LOCAL] statement / OFF
ONERR:	add.l	#1,a4			! SKIP "ERROR"
	bsr	NXT
	clr.l	d0			! FLAG NOT LOCAL
	cmp.b	#TLOCAL,d4
	bne	ONERR1
	add.l	#1,a4			! SKIP "LOCAL"
	move.l	ONERSP,-(sp)		! a LOCAL frame restoring ERRTRP and
	move.l	ERRTRP,-(sp)		! ONERSP (type 3: 8 raw bytes)
	move.w	#0x0300,-(sp)
	pea	ERRTRP
	pea	LOCCHK
	move.l	sp,d0
	bsr	NXT
ONERR1:	move.l	d0,ONERSP
	move.l	a4,ERRTRP
	cmp.b	#TOFF,d4
	bne	REM
	add.l	#1,a4			! SKIP "OFF"
	clr.l	ONERSP
	clr.l	ERRTRP
	bra	XEQ

! ON expr GOTO line[,line...] [ELSE statement]
! ON expr GOSUB line[,line...] [ELSE statement]
! ON expr PROCone [,PROCtwo..] [ELSE PROCotherwise]
! ON ERROR [LOCAL] statement [:statement...]
! ON ERROR [LOCAL] OFF
ON:	bsr	TERMQ
	beq	CSRON
	cmp.b	#TERROR,d4
	beq	ONERR			! "ON ERROR"
	bsr	EXPRI
	move.b	(a4)+,d4
	move.b	#',',d5			! E = SEPARATOR
	cmp.b	#TGOTO,d4
	beq	ON1
	cmp.b	#TGOSUB,d4
	beq	ON1
	move.b	#TPROC,d5
	cmp.b	d5,d4
	beq	ON1
	move.b	#39,d4
	bra	ERROR2			! "ON syntax"
ON1:	move.b	d4,d3			! D = GOTO / GOSUB / PROC
	cmp.l	#0xFF,d0		! ON INDEX: 1-255
	bhi	ON4			! OUT OF RANGE
	tst.b	d0
	beq	ON4
	sub.b	#1,d0
	beq	ON3			! INDEX=1
ON2:	bsr	TERMQ
	beq	ON4			! OUT OF RANGE
	add.l	#1,a4			! SKIP DELIMITER
	cmp.b	#'"',d4
	beq	ON5
	cmp.b	d5,d4
	bne	ON2
	sub.b	#1,d0
	bne	ON2
ON3:	cmp.b	#TPROC,d5
	beq	ONPROC
	move.w	d3,-(sp)
	bsr	ITEMI			! LINE NUMBER
	move.w	(sp)+,d3
	cmp.b	#TGOTO,d3
	beq	GOTO2
	move.l	d0,-(sp)
	bsr	SPAN			! SKIP REST OF LIST
	move.l	(sp)+,d0
	bra	GOSUB1

ON5:	bsr	QUOTE
	add.l	#1,a4
	bra	ON2

ON4:	move.b	(a4)+,d4
	cmp.b	#TELSE,d4
	beq	IF1			! ELSE CLAUSE
	cmp.b	#CR,d4
	bne	ON4
	move.b	#40,d4			! 'ON range'
	bra	ERROR2
FORVAR:	move.b	#34,d4			! 'FOR variable'
ERROR2:	bra	ERROR

ONPROC:	move.b	#TON,d4
	bra	PROC

! GOTO line
GOTO:	bsr	ITEMI			! LINE NUMBER
GOTO1:	move.l	d0,-(sp)
	bsr	TERMQ
	movem.l	(sp)+,d0		! (movem: flags kept)
	bne	SYNTAX
GOTO2:	bsr	FINDL
	move.l	a3,a4
	beq	XEQ0
	move.b	#41,d4
	bra	ERROR2			! "No such line"

! GOSUB line
GOSUB:	bsr	ITEMI			! LINE NUMBER
GOSUB1:	move.l	a4,-(sp)		! TEXT POINTER
	bsr	CHECK			! CHECK ROOM
	bsr	GOTO1			! SAVE MARKER
GOSCHK:

! RETURN
RETURN:	move.l	(sp)+,d7		! MARKER
	cmp.l	#GOSCHK,d7
	bne	1f
	move.l	(sp)+,a4
	bra	XEQ
1:	move.b	#38,d4
	bra	ERROR2			! "No GOSUB"

! REPEAT
REPEAT:	move.l	a4,-(sp)
	bsr	CHECK
	bsr	XEQ
REPCHK:

! UNTIL expr
UNTIL:	move.l	(sp),d7
	cmp.l	#REPCHK,d7
	beq	UNTIL1
	move.b	#3,d4
	bsr	RESLOC
	bne	UNTIL
	move.b	#43,d4
	bra	ERROR2			! "Not in a REPEAT loop"
UNTIL1:	bsr	EXPRI
	bsr	TEST
	bne	1f			! TRUE
	move.l	4(sp),a4		! again from the REPEAT
	bra	XEQ
1:	add.l	#8,sp
	bra	XEQ

! FOR var = expr TO expr [STEP expr]
FOR:	bsr	ASSIGN
	bne	FORVAR			! "FOR variable"
	move.w	d4,-(sp)		! SAVE TYPE
	cmp.b	#TTO,(a4)
	beq	1f
	move.b	#36,d4
	bra	ERROR2			! "No TO"
1:	add.l	#1,a4
	move.l	a5,-(sp)
	bsr	EXPRN			! LIMIT
	move.l	(sp)+,a5
	move.w	(sp)+,d7		! TYPE
	move.b	d1,-(sp)		! limit exp (byte 22), type (23)
	move.b	d7,1(sp)
	move.l	d0,-(sp)		! limit mantissa (18)
	move.l	#1,d0			! PRESET STEP
	clr.b	d1
	cmp.b	#TSTEP,(a4)
	bne	FOR1
	add.l	#1,a4
	move.l	a5,-(sp)
	bsr	EXPRN			! STEP
	move.l	(sp)+,a5
FOR1:	move.b	#12,d7			! FPP '>' (positive step)
	tst.l	d0
	bpl	FOR2			! STEP SIGN
	move.b	#8,d7			! FPP '<'
FOR2:	move.b	d1,-(sp)		! step exp (16), compare op (17)
	move.b	d7,1(sp)
	move.l	d0,-(sp)		! step mantissa (12)
	move.l	a4,-(sp)		! SAVE TEXT POINTER (8)
	move.l	a5,-(sp)		! LOOP VARIABLE (4)
	bsr	CHECK
	bsr	XEQ
FORCHK:

! NEXT [var[,var...]]
NEXT:	move.l	(sp),d7			! MARKER
	cmp.l	#FORCHK,d7
	beq	NEXT2
	move.b	#3,d4
	bsr	RESLOC
	bne	NEXT
	move.b	#32,d4
	bra	ERROR3			! "Not in a FOR loop"

NEXT2:	bsr	TERMQ
	move.l	4(sp),a3		! the FOR variable
	beq	NEXT0			! (no name: this one)
	bsr	GETVAR			! VARIABLE
	beq	NEXT0
	bcc	NEXT1			! (not found: can't match)
	move.l	4(sp),a3		! (illegal, e.g. NEXT ,: as no name)
NEXT0:	cmp.l	4(sp),a3
	bne	NEXT1
	move.l	a3,a5
	move.l	12(sp),d2		! STEP
	move.b	16(sp),d3
	move.b	23(sp),d4		! TYPE
	bsr	LOADN			! LOOP VARIABLE
	move.w	d4,-(sp)
	move.b	#11,d4			! '+'
	bsr	FPP			! ADD STEP
	bcs	ERROR3
	move.w	(sp)+,d4		! RESTORE TYPE
	move.l	4(sp),a5
	bsr	STOREN			! UPDATE VARIABLE
	move.l	18(sp),d2		! LIMIT
	move.b	22(sp),d3
	move.b	17(sp),d4		! compare op
	bsr	FPP			! TEST AGAINST LIMIT
	bcs	ERROR3
	tst.l	d0
	beq	LOOP			! KEEP LOOPING (FALSE)
	add.l	#24,sp			! "POP" THE FOR FRAME
	bsr	NLIST
	bra	NEXT

LOOP:	move.l	8(sp),a4		! the loop body
	bra	XEQ

NEXT1:	add.l	#24,sp			! "POP" THE INNER FRAME
	move.l	(sp),d7
	cmp.l	#FORCHK,d7
	beq	NEXT0
	move.b	#33,d4
ERROR3:	bra	ERROR			! "Can't match FOR"

! INPUT #channel,var,var...
INPUTN:	bsr	CHNL			! d6 = CHANNEL NUMBER
INPN1:	bsr	NLIST
	move.w	d6,-(sp)
	bsr	VAR
	move.w	(sp)+,d6
	move.w	d4,-(sp)		! SAVE TYPE
	move.l	a5,-(sp)		! VARPTR
	tst.b	d4
	bmi	INPN2			! STRING
	bsr	OSBGET			! 5 bytes: LS first, exponent last
	move.b	d4,d0
	ror.l	#8,d0
	bsr	OSBGET
	move.b	d4,d0
	ror.l	#8,d0
	bsr	OSBGET
	move.b	d4,d0
	ror.l	#8,d0
	bsr	OSBGET
	move.b	d4,d0
	ror.l	#8,d0
	bsr	OSBGET
	move.b	d4,d1
	move.l	(sp)+,a5
	move.w	(sp)+,d4		! RESTORE TYPE
	move.w	d6,-(sp)		! SAVE CHANNEL
	bsr	STOREN
	move.w	(sp)+,d6
	bra	INPN1
INPN2:	lea	ACCS,a2
1:	bsr	OSBGET
	cmp.b	#CR,d4
	beq	2f
	move.b	d4,(a2)+
	cmp.l	#ACCS+256,a2
	bcs	1b
	lea	ACCS,a2			! (as the Z80 INC L wrap)
	bra	1b
2:	move.l	(sp)+,a5
	move.w	(sp)+,d4
	move.w	d6,-(sp)
	bsr	STACCS
	move.w	(sp)+,d6
	bra	INPN1

! INPUT ['][SPC(x)][TAB(x[,y])]["prompt",]var[,var...]
! INPUT LINE [SPC(x)][TAB(x[,y])]["prompt",]var[,var...]
!   d5.b = C: bit 7 INPUT LINE, bit 0 no prompt; a3 = buffer pointer
INPUT:	cmp.b	#'#',d4
	beq	INPUTN
	clr.b	d5			! FLAG PROMPT
	cmp.b	#TLINE,d4
	bne	INPUT0
	add.l	#1,a4			! SKIP "LINE"
	move.b	#0x80,d5
INPUT0:	lea	BUFFER,a3
	move.b	#CR,(a3)		! INITIALISE EMPTY
INPUT1:	bsr	TERMQ
	beq	XEQ			! DONE
	add.l	#1,a4
	cmp.b	#',',d4
	beq	INPUT3			! SKIP COMMA
	cmp.b	#';',d4
	beq	INPUT3
	move.l	a3,-(sp)		! SAVE BUFFER POINTER
	cmp.b	#'"',d4
	bne	INPUT6
	move.w	d5,-(sp)
	bsr	CONS
	move.w	(sp)+,d5
	bsr	PTEXT			! PRINT PROMPT
	bra	INPUT9
INPUT6:	bsr	FORMAT			! SPC, TAB, '
	bne	INPUT2
INPUT9:	move.l	(sp)+,a3
	bset	#0,d5			! FLAG NO PROMPT
	bra	INPUT0
INPUT2:	sub.l	#1,a4
	move.w	d5,-(sp)
	bsr	VAR
	move.w	(sp)+,d5
	move.l	(sp)+,a3		! buffer pointer
	move.w	d4,-(sp)		! SAVE TYPE
	move.l	a5,-(sp)		! VARPTR
	cmp.b	#CR,(a3)+		! BUFFER EMPTY?
	bne	1f
	bsr	REFILL
1:	btst	#7,d5
	beq	2f
	bsr	LINES			! INPUT LINE: the whole line
	bra	3f
2:	bsr	FETCHS			! an item up to a comma
3:	move.l	(sp)+,a5
	move.w	(sp)+,d4		! RESTORE TYPE
	move.w	d5,-(sp)
	move.l	a3,-(sp)
	tst.b	d4
	bmi	INPUT4			! STRING
	move.w	d4,-(sp)
	move.l	a5,-(sp)
	bsr	VAL0
	move.l	(sp)+,a5
	move.w	(sp)+,d4
	bsr	STOREN
	bra	INPUT5
INPUT4:	bsr	STACCS
INPUT5:	move.l	(sp)+,a3
	move.w	(sp)+,d5
INPUT3:	bclr	#0,d5
	bra	INPUT1

! REFILL - read a new input line into BUFFER: a3 = BUFFER
REFILL:	btst	#0,d5
	bne	REFIL0			! NO PROMPT
	move.b	#'?',d4
	bsr	OUTCHR			! PROMPT
	move.b	#' ',d4
	bsr	OUTCHR
REFIL0:	lea	BUFFER,a3
	movem.l	d5/a3/a5,-(sp)
	bsr	OSLINE
	movem.l	(sp)+,d5/a3/a5
	clr.b	COUNT
	rts

! READ var[,var...]
READ:	cmp.b	#'#',d4
	beq	INPUTN
	move.l	DATPTR,a3
READ0:	move.b	(a3),d4
	cmp.b	#':',d4
	bne	1f
	clr.b	d1			! (the Z80 B: undefined; 256)
	bsr	REFIL1
	move.b	(a3),d4
1:	add.l	#1,a3			! SKIP COMMA OR "DATA"
	cmp.b	#CR,d4			! END OF DATA STMT?
	bne	2f
	bsr	GETDAT
2:	move.l	a3,-(sp)
	bsr	VAR
	move.l	(sp)+,a3
	tst.b	d4
	bmi	READ1			! STRING
	move.l	a4,-(sp)		! (the DATA text becomes a4)
	move.l	a3,a4
	move.w	d4,-(sp)		! SAVE TYPE
	move.l	a5,-(sp)
	bsr	EXPRN
	move.l	(sp)+,a5
	move.w	(sp)+,d4
	bsr	STOREN
	move.l	a4,a3
	move.l	(sp)+,a4
	bra	READ2
READ1:	move.w	d4,-(sp)
	move.l	a5,-(sp)
	bsr	FETCHS			! (a3 = the DATA text)
	move.l	(sp)+,a5
	move.w	(sp)+,d4
	move.l	a3,-(sp)
	bsr	STACCS
	move.l	(sp)+,a3
READ2:	move.l	a3,DATPTR
	bsr	NLIST
	bra	READ0

! REFIL1 - skip to CR, at most d1.b characters (Z80 B)
REFIL1:	cmp.b	#CR,(a3)
	beq	1f
	add.l	#1,a3
	sub.b	#1,d1
	bne	REFIL1
1:	rts

GETDAT:	bsr	DSRCH
	add.l	#1,a3
	bcs	1f
	rts
1:	move.b	#42,d4
	bra	ERROR4			! "Out of DATA"

! IF expr statement
! IF expr THEN statement [ELSE statement]
! IF expr THEN line [ELSE line]
! IF expr THEN
IF:	bsr	EXPRI
	bsr	TEST
	beq	IFNOT			! FALSE
	cmp.b	#TTHEN,(a4)
	bne	XEQ
IF0:	add.l	#1,a4			! SKIP "THEN"
	cmp.b	#';',(a4)
	beq	IF0
IF1:	bsr	NXT
	cmp.b	#TLINO,d4
	bne	XEQ			! STATEMENT FOLLOWS
	bra	GOTO			! LINE NO. FOLLOWS

IFELSE:	move.b	(a4)+,d4
	cmp.b	#';',d4
	bne	IFNEXT
	bra	IFTHEN

IF2:	bsr	QUOTE			! SKIP STRING
IFNOT:	lea	IFTAB,a0		! (68k: skip uninteresting bytes by table)
	clr.w	d4
1:	move.b	(a4)+,d4
	tst.b	0(a0,d4.w)
	beq	1b
IFNEXT:	cmp.b	#'"',d4
	beq	IF2			! QUOTED STRING
	cmp.b	#TREM,d4
	beq	REM			! REM
	cmp.b	#CR,d4
	beq	XEQ0			! END OF LINE
	cmp.b	#TELSE,d4
	beq	IF1			! ELSE CLAUSE
	cmp.b	#TTHEN,d4
	bne	IFNOT			! TRY FOR END AGAIN
IFTHEN:	cmp.b	#CR,(a4)
	bne	IFELSE
	move.w	#TELSE,d5		! B, C = tokens to find
	move.w	#TENDIF*256+TTHEN,d6	! D = unnest, E = nest
	add.l	#1,a4
	bsr	NSCAN
	beq	XEQ1
NENDIF:	move.b	#49,d4
ERROR4:	bra	ERROR			! "Missing ENDIF"

! ELSE (multi-line)
MELSE:	sub.l	#3,a4
	move.w	#TENDIF,d5
	move.w	#TENDIF*256+TTHEN,d6
	bsr	NSCAN
	bne	NENDIF
	bra	XEQ

! WHEN and OTHERWISE:
WHEN:	sub.l	#3,a4
	move.w	#TENDCASE,d5
	move.w	#TENDCASE*256+TOF,d6
	bsr	NSCAN
	beq	XEQ
	move.b	#47,d4
	bra	ERROR4			! "Missing ENDCASE"

! CASE expr OF
!   d3.b (B): bit 0 = string; d5.b (C) = string length (on the stack)
CASE:	bsr	EXPR			! String or numeric
	clr.b	d3			! Flag numeric
	tst.b	d6
	bpl	CASE6			! numeric
	bsr	PUSHS			! put string on stack
	move.w	(sp)+,d5		! C = length (the string stays)
	move.b	#1,d3			! Flag string
CASE6:	move.b	(a4)+,d4
	cmp.b	#TOF,d4
	beq	1f
	move.b	#37,d4
	bra	ERROR4			! "Missing OF"
1:	move.b	(a4)+,d4		! Address line-length byte
	cmp.b	#CR,d4
	beq	CASE1
	move.b	#48,d4
	bra	ERROR4			! "OF not last"
CASE1:	clr.b	d4			! Level
CASE0:	movem.l	d0-d1/d3/d5,-(sp)	! the value, type, length
	move.b	d4,d7			! L = level
	move.w	#TOTHERWISE*256+TWHEN,d5
	move.w	#TENDCASE*256+TOF,d6
	bsr	NSCAN1
	movem.l	(sp)+,d0-d1/d3/d5	! (flags kept)
	beq	1f
	move.b	#47,d4
	bra	ERROR			! Missing ENDCASE
1:	move.b	-1(a4),d4
	cmp.b	#TENDCASE,d4
	beq	CASE9
	cmp.b	#TOTHERWISE,d4
	beq	CASE9
CASE4:	btst	#0,d3			! Numeric or string?
	bne	CASE3
	movem.l	d0-d1/d3/d5,-(sp)
	bsr	EXPRN
	move.l	(sp),d2			! the CASE value
	move.b	7(sp),d3		! (its exponent: low byte of d1)
	move.b	#9,d4			! '='
	bsr	FPP			! In case integer vs float
	tst.l	d0			! NZ if equal
	movem.l	(sp)+,d0-d1/d3/d5	! (flags kept)
	bne	CASE5			! Match found
CASE2:	move.b	(a4)+,d4
	cmp.b	#',',d4
	beq	CASE4			! Not found, try another
1:	cmp.b	#CR,(a4)+		! Find CR
	bne	1b
	move.b	-2(a4),d4		! Last token in previous line
	cmp.b	#TOF,d4			! CASE statement in WHEN line
	bne	CASE1
	move.b	#1,d4
	bra	CASE0

! Finished, level stack if string:
CASE9:	btst	#0,d3
	beq	XEQ
	clr.w	d7
	move.b	d5,d7
	add.w	#1,d7
	and.w	#0xFFFE,d7
	add.w	d7,sp
	bra	XEQ

! Matched, so skip any more expressions:
CASE5:	bsr	NXT
	cmp.b	#',',d4
	bne	CASE9			! End of list
	add.l	#1,a4
	movem.l	d3/d5,-(sp)
	bsr	EXPR			! Evaluate but discard
	movem.l	(sp)+,d3/d5
	bra	CASE5

! String compare:
CASE3:	movem.l	d3/d5,-(sp)
	bsr	EXPRS
	movem.l	(sp)+,d3/d5
	move.l	a2,d7			! (a3, d3) = the WHEN string ...
	sub.l	#ACCS,d7
	movem.l	d3/d5,-(sp)
	move.b	d7,d3			! ... in ACCS
	lea	ACCS,a3
	lea	8(sp),a2		! the CASE string on the stack
	bsr	SCP			! String compare
	movem.l	(sp)+,d3/d5		! (flags kept)
	beq	CASE5
	bra	CASE2

! WHILE
WHILE:	move.l	a4,-(sp)		! Save current position
	bsr	CHECK
	pea	WHICHK			! Push marker (pea: CONVENTIONS 9)
WHICHK:	bsr	EXPRI
	bsr	TEST
	bne	XEQ
	add.l	#8,sp			! Pop marker, level stack
	move.w	#TENDWHILE*256+TWHILE,d5 ! B = find, C = nest
	move.b	#1,d6			! D = ordinal
	bsr	WSRCH
	bra	XEQ

! ENDWHILE
ENDWHI:	move.l	(sp),d7			! Marker
	cmp.l	#WHICHK,d7
	beq	ENDWH1
	move.b	#3,d4
	bsr	RESLOC
	bne	ENDWHI
	move.b	#46,d4
	bra	ERROR5			! "Not in a WHILE loop"
ENDWH1:	move.l	a4,-(sp)		! after the ENDWHILE
	move.l	8(sp),a4		! the condition (frame: WHICHK, text)
	bsr	EXPRI
	bsr	TEST
	beq	1f
	add.l	#4,sp			! TRUE: go on after the condition
	bra	XEQ
1:	move.l	(sp)+,a4		! FALSE: after the ENDWHILE
	add.l	#8,sp			! Junk marker and pointer
	bra	XEQ

! CLS
CLS:	bsr	CLRSCN
	clr.b	COUNT
	bra	XEQ

! STOP
STOP:	bsr	TELL
	.data1	CR, LF, TSTOP, 0
	.align	2
	bsr	SETLIN			! FIND CURRENT LINE
	bsr	SAYLN
	bsr	CRLF
	bra	CLOOP

! REPORT
REPOR:	bsr	REPORT
	bra	XEQ

! CLEAR
CLR:	bsr	CLEAR
	move.l	PAGE,a3
	bra	RESTR1

! RESTORE DATA / ERROR / LOCAL:  d3.b = B (1 DATA, 2 ERROR, 0 LOCAL),
! d5.b = C = error code if nothing restored
! (RESLOC works on the frames at the top of the stack, so nothing may
! be saved on the stack around it: the registers go to statics.)
RESDEL:	add.l	#1,a4			! Skip DATA / ERROR / LOCAL
	move.b	d5,rescod
	move.b	d3,d4
	bsr	RESLOC
	bne	XEQ
	move.b	rescod,d5
	move.b	d5,d4
	bra	ERROR5
NOLINE:	move.b	#41,d4			! 'No such line'
ERROR5:	bra	ERROR

! RESTORE [line | +n | DATA | ERROR | LOCAL]
RESTOR:	move.b	#2,d3
	move.b	#53,d5			! 'ON ERROR not LOCAL'
	cmp.b	#TERROR,d4
	beq	RESDEL
	move.b	#1,d3
	move.b	#54,d5			! 'DATA not LOCAL'
	cmp.b	#TDATA,d4
	beq	RESDEL
	clr.b	d3
	move.b	#12,d5			! 'Not in a FN or PROC'
	cmp.b	#TLOCAL,d4
	beq	RESDEL
	cmp.b	#'+',d4
	beq	RESREL
	move.l	PAGE,a3
	bsr	TERMQ
	beq	RESTR1
	bsr	ITEMI
	bsr	FINDL			! SEARCH FOR LINE
	bne	NOLINE
RESTR1:	bsr	DSRCH
	move.l	a3,DATPTR
	bra	XEQ

RESREL:	bsr	EXPRI
	move.l	a4,a3
1:	cmp.b	#CR,(a3)+		! FIND LINE END
	bne	1b
	sub.b	#1,d0
	beq	RESTR1
	bmi	RESTR1
2:	clr.l	d7
	move.b	(a3),d7
	beq	NOLINE
	add.l	d7,a3
	sub.b	#1,d0
	bne	2b
	bra	RESTR1

! PTR#channel=expr  PAGE=expr  TIME=expr  LOMEM=expr  HIMEM=expr
PTR:	bsr	CHANEL
	bsr	EQUALS
	move.w	d6,-(sp)
	bsr	EXPRI
	move.w	(sp)+,d4		! channel
	bsr	PUTPTR
	bra	XEQ

PAGEV:	bsr	EQUALS
	bsr	EXPRI
	clr.b	d0			! (page aligned)
	move.l	d0,PAGE
	bra	XEQ

TIMEV:	cmp.b	#'$',d4
	beq	TIMEVS
	bsr	EQUALS
	bsr	EXPRI
	bsr	PUTIME
	bra	XEQ

TIMEVS:	add.l	#1,a4			! SKIP '$'
	bsr	EQUALS
	bsr	EXPRS
	bsr	PUTIMS
	bra	XEQ

LOMEMV:	bsr	EQUALS
	bsr	EXPRI
	bsr	CLEAR
	move.l	d0,LOMEM
	move.l	d0,FREE
	bra	XEQ

HIMEMV:	bsr	EQUALS
	bsr	EXPRI
	move.l	FREE,d7
	add.l	#256,d7
	cmp.l	d7,d0
	bcc	1f
	clr.b	d4
	bra	ERROR			! "No room"
1:	move.l	HIMEM,d7
	move.l	d0,HIMEM
	cmp.l	sp,d7			! stack at HIMEM: move it
	bne	XEQ
	move.l	d0,sp			! LOAD STACK POINTER
	bra	XEQ

! WIDTH expr
WIDTHV:	bsr	EXPRI
	move.b	d0,WIDTH
	bra	XEQ

! TRACE ON / OFF / line
TRACE:	add.l	#1,a4
	clr.l	d0
	cmp.b	#TON,d4
	beq	TRACE0
	cmp.b	#TOFF,d4
	beq	TRACE1
	sub.l	#1,a4
	bsr	EXPRI
	and.l	#0xFFFF,d0
TRACE0:	sub.l	#1,d0			! (ON: &FFFF... all lines)
	and.l	#0xFFFF,d0
TRACE1:	move.l	d0,TRACEN
	bra	XEQ

! VDU expr,expr;....[|]
VDU:	bsr	EXPRI
	move.b	d0,d4
	bsr	OSWRCH
	move.b	(a4),d7
	cmp.b	#'|',d7
	beq	VDU4
	cmp.b	#',',d7
	beq	VDU2
	cmp.b	#';',d7
	bne	VDU3
	move.w	d0,d4			! the high byte too
	lsr.w	#8,d4
	bsr	OSWRCH
VDU2:	add.l	#1,a4
VDU3:	bsr	TERMQ
	bne	VDU
	bra	XEQ
VDU4:	add.l	#1,a4
	clr.b	d4			! 9 zero bytes
	move.w	#8,d7
1:	bsr	OSWRCH
	dbra	d7,1b
	bra	VDU3

! CLOSE channel number
CLOSE:	bsr	CHANEL
	bsr	OSSHUT
	bra	XEQ

! BPUT #channel,byte
! BPUT #channel,string[;]
BPUT:	bsr	CHANEL			! CHANNEL NUMBER
	move.w	d6,-(sp)
	bsr	COMMA
	bsr	EXPR
	move.w	(sp)+,d7
	tst.b	d6
	bmi	BPUTS
	move.b	d7,d6
	bsr	SFIX
	move.b	d0,d4
	bsr	OSBPUT
	bra	XEQ
BPUTS:	move.b	d7,d6
	lea	ACCS,a3
1:	cmp.l	a2,a3
	bcc	2f
	move.b	(a3)+,d4
	bsr	OSBPUT
	bra	1b
2:	bsr	NXT
	cmp.b	#';',d4
	beq	3f
	move.b	#LF,d4
	bsr	OSBPUT
	bra	XEQ
3:	add.l	#1,a4
	bra	XEQ

! CALL address[,var[,var...]]
! USR(address)
! 68000 code is called with d0-d7 = A%-H% and a0 = the parameter block
! (CALL): [count] then per parameter [type][address 4 bytes LE].  USR
! returns d0.  (The Z80 loaded its registers from A%, B%, ... instead.)
CALL:	bsr	EXPRI			! ADDRESS
	move.l	d0,-(sp)		! SAVE IT
	clr.b	d3			! PARAMETER COUNTER
	lea	BUFFER+1,a2		! VECTOR
CALL1:	bsr	NXT
	cmp.b	#',',d4
	bne	CALL2
	add.l	#1,a4
	add.b	#1,d3
	bsr	NXT
	movem.l	d3/a2,-(sp)
	bsr	VAR
	movem.l	(sp)+,d3/a2
	move.b	d4,(a2)+		! PARAMETER TYPE
	move.l	a3,d0
	move.l	a2,a0
	bsr	STLE4			! PARAMETER ADDRESS
	add.l	#4,a2
	bra	CALL1
CALL2:	move.b	d3,BUFFER		! PARAMETER COUNT
	move.l	(sp)+,d0		! RESTORE ADDRESS
	bsr	USR1
	bra	XEQ

USR:	bsr	ITEMI
USR1:	move.l	a4,-(sp)
	move.l	d0,a1
	lea	STAVAR+4,a0		! A%-H% (little-endian)
	bsr	LDLE4
	move.l	d0,d7			! (A%, kept for d0)
	add.l	#4,a0
	bsr	LDLE4
	move.l	d0,d1
	add.l	#4,a0
	bsr	LDLE4
	move.l	d0,d2
	add.l	#4,a0
	bsr	LDLE4
	move.l	d0,d3
	add.l	#4,a0
	bsr	LDLE4
	move.l	d0,d4
	add.l	#4,a0
	bsr	LDLE4
	move.l	d0,d5
	add.l	#4,a0
	bsr	LDLE4
	move.l	d0,d6
	add.l	#4,a0
	bsr	LDLE4
	exg	d0,d7
	lea	BUFFER,a0
	jsr	(a1)			! OFF TO USER ROUTINE
	move.l	(sp)+,a4
	clr.b	d1
	clr.b	d4
	rts

! LEFT$(A$[,N]) = string
! MID$(A$,N[,M]) = string
! RIGHT$(A$[,N]) = string
!   d2.b = L (first character to modify), d3.b = H (last)
LEFTSL:	bsr	GETSTR
	seq	d7			! (Z: a comma follows)
	move.w	#0xFF00,d0		! Default all but last
	tst.b	d7
	beq	MIDSL1
	bra	MIDSL0

RITESL:	bsr	GETSTR
	seq	d7			! (Z: a comma follows)
	move.w	#0xFFFF,d0		! Default last char only
	tst.b	d7
	beq	MIDSL1
	bra	MIDSL0

MIDSL:	bsr	GETSTR
	beq	1f
	move.b	#5,d4
	bra	ERROR			! 'Missing comma'
1:	add.l	#1,a4
	move.l	a5,-(sp)
	bsr	EXPRI
	move.l	(sp)+,a5
	move.w	d0,-(sp)
	bsr	NXT
	move.w	(sp)+,d0
	sub.b	#1,d0			! L
	and.w	#0xFF,d0
	or.w	#254*256,d0		! H: Default rest of string
	cmp.b	#',',d4
	bne	MIDSL1
MIDSL0:	add.l	#1,a4
	move.w	d0,-(sp)
	move.l	a5,-(sp)
	bsr	EXPRI
	move.l	(sp)+,a5
	move.w	d0,d7			! count
	move.w	(sp)+,d0		! H:L
	tst.b	d7
	beq	MIDSL2			! Zero length
	sub.b	#1,d7
	add.b	d0,d7			! H = L + count - 1
	scs	d6			! (overflow)
	lsl.w	#8,d7
	move.b	d0,d7
	move.w	d7,d0
	tst.b	d6
	beq	MIDSL1
	cmp.b	#0xFF,d0		! RIGHT$ (L = 255): keep it
	beq	MIDSL1
	and.w	#0xFF,d0
	or.w	#254*256,d0
	bra	MIDSL1
MIDSL2:	move.w	#1,d0
MIDSL1:	move.w	d0,-(sp)
	bsr	BRAKET
	bsr	EQUALS
	move.l	a5,-(sp)
	bsr	EXPRS
	move.l	(sp)+,a5
	move.w	(sp)+,d0
! Source string at ACCS, length C (d5); destination string length B
! (d3), address a0; L = first character to modify 0-254, H = last
! IF L=255 THEN modify rightmost H + 2 chars
! ELSE IF H=255 modify all but last character
! ELSE IF L > H do nothing
	move.l	a2,d5
	sub.l	#ACCS,d5		! C
	move.l	d0,-(sp)
	bsr	LDDESC			! d5 = B, a0 = destination
	move.b	d5,d3			! B
	move.l	(sp)+,d0
	move.l	a2,d5
	sub.l	#ACCS,d5		! C
	move.b	d0,d2			! L
	move.w	d0,d7
	lsr.w	#8,d7			! H
	cmp.b	#0xFF,d2
	bne	SUBSL1
	add.b	#2,d7
	cmp.b	d7,d5
	bcc	SUBSL0
	move.b	d5,d7
SUBSL0:	move.b	d3,d2
	sub.b	d7,d2
	bcc	SUBSL5
	clr.b	d2
	bra	SUBSL5
SUBSL1:	cmp.b	#0xFF,d7
	bne	SUBSL2
	move.b	d3,d7
	sub.b	#2,d7
	bcs	SUBSL9
SUBSL2:	cmp.b	d3,d2
	bcc	SUBSL9
	cmp.b	d3,d7
	bcs	SUBSL3
SUBSL5:	move.b	d3,d7
	sub.b	#1,d7
SUBSL3:	sub.b	d2,d7			! H - L
	bcs	SUBSL9
	add.b	#1,d7
	cmp.b	d5,d7
	bcs	SUBSL4
	move.b	d5,d7
SUBSL4:	tst.b	d7
	beq	SUBSL9
	and.w	#0xFF,d2
	add.w	d2,a0
	lea	ACCS,a1
	and.w	#0xFF,d7
	sub.w	#1,d7
1:	move.b	(a1)+,(a0)+
	dbra	d7,1b
SUBSL9:	bra	XEQ

! EXIT FOR [var] / EXIT REPEAT / EXIT WHILE
!   d1.b = E = the loop token, d2.b = D = level for WSRCH, a1 = the
!   variable of EXIT FOR var (0 = any)
EXIT:	add.l	#1,a4			! Skip FOR/REPEAT/WHILE
	move.b	d4,d1
	move.l	#0,a1
	cmp.b	#TFOR,d4
	bne	EXIT0
	bsr	TERMQ
	beq	1f
	bsr	GETVAR
	move.l	a3,a1
1:	move.b	#TFOR,d1
EXIT0:	move.b	#1,d2			! Level for WSRCH
EXIT1:	move.l	(sp)+,d7		! Marker
	cmp.l	#FORCHK,d7
	beq	EXIT4
	cmp.l	#REPCHK,d7
	beq	EXIT6
	cmp.l	#WHICHK,d7
	beq	EXIT7
	move.l	d7,-(sp)		! Put back marker
	movem.l	d1-d2/a1,exitrg		! (not on the stack: see RESDEL)
	move.b	#3,d4
	bsr	RESLOC
	movem.l	exitrg,d1-d2/a1		! (flags kept)
	bne	EXIT1
	move.b	#44,d4
	bra	ERROR			! 'Bad EXIT'

EXIT4:	move.l	(sp)+,a0		! VARPTR
	add.l	#16,sp			! Pop FOR record
	cmp.b	#TFOR,d1
	bne	EXIT1
	cmp.l	#0,a1
	beq	1f
	cmp.l	a1,a0
	beq	1f
	add.b	#1,d2			! Count nested FOR loops
	bra	EXIT1
1:	move.w	#TNEXT*256+TFOR,d5
	bra	EXIT8

EXIT6:	add.l	#4,sp			! Text pointer
	cmp.b	#TREPEAT,d1
	bne	EXIT1
	move.w	#TUNTIL*256+TREPEAT,d5
	bra	EXIT8

EXIT7:	add.l	#4,sp			! Text pointer
	cmp.b	#TWHILE,d1
	bne	EXIT1
	move.w	#TENDWHILE*256+TWHILE,d5
EXIT8:	move.b	d2,d6			! D
	bsr	WSRCH
	bsr	SPAN			! Skip UNTIL expression
	bra	XEQ

! PUT port,data: no I/O ports
PUT:	clr.b	d4
	jsr	EXTERR
	.asciz	"Sorry"
	.align	2

! SPANX - (for exec2.s) skip to the end of the statement
SPANX:	bra	SPAN

	.sect	.bss
exitrg:	.space	12			! EXIT: d1, d2, a1 around RESLOC
rescod:	.space	2			! RESDEL: the error code

	.sect	.rom
! IFTAB - the bytes IFNOT stops at: " CR REM ELSE THEN
IFTAB:
	.data1	0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0
	.data1	0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
	.data1	0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
	.data1	0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
	.data1	0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
	.data1	0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
	.data1	0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
	.data1	0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
	.data1	0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0
	.data1	0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
	.data1	0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
	.data1	0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
	.data1	0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
	.data1	0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
	.data1	0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
	.data1	0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
