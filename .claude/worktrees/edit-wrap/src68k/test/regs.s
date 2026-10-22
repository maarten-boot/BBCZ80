.sect .text
.sect .rom
.sect .data
.sect .bss
.extern _callee
.sect .text
.align 4
_callee:
!Local -2 into d7
!Local -14 into a5
!Local -10 into a4
link	a6,#-26
tst.b -40(sp)
movem.l d7/a5/a4,(sp)
move.l 10(a6),-6(a6)
move.l 14(a6),a4
move.w 8(a6),d0
ext.l d0
move.l 14(a6),a5
add.l d0,a5
clr.w d7
I1_6:
cmp.w 8(a6),d7
bge I1_3
move.b (a4)+,d0
move.w d7,d1
ext.w d0
ext.l d0
move.l d0,-(sp)
ext.l d1
move.l d1,-(sp)
jsr .mli
add.l d1,-6(a6)
move.b -(a5),d0
ext.w d0
ext.l d0
eor.l d0,-6(a6)
add.w #1,d7
bra I1_6
I1_3:
move.l -6(a6),_g
move.l -6(a6),d0
movem.l -26(a6),d7/a5/a4
unlk a6
rts
.extern _g
.sect .bss
.comm _g,4
.sect .text
