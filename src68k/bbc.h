! bbc.h - shared definitions for BBC BASIC 68k (cpp, see CONVENTIONS.md).
! A file that includes this must have a lone '#' on its first line.

! 68000 only: the ACK assembler (maarten-boot/ack) takes 68010 instructions
! unless told otherwise; with this it rejects them ("68010 instruction")
.68000

! Condition codes for "move.w #n,ccr"
CC_X	= 16
CC_N	= 8
CC_Z	= 4
CC_V	= 2
CC_C	= 1

! Status returns (Z80 "CP A" and "OR A : SCF")
#define	SETGOOD	move.w #CC_Z,ccr
#define	SETBAD	move.w #CC_C,ccr
