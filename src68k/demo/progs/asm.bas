10 REM The 68000 inline assembler (Motorola syntax)
20 DIM code% 100,buf% 100
30 FOR pass%=0 TO 3 STEP 3
40   P%=code%
50   [OPT pass%
60   .sum    moveq #0,d0        ; d0 = 1+2+...+d1, d1 = B%
70   .loop   add.l d1,d0
80           subq.l #1,d1
90           bne loop
100          rts
110  .upper  movea.l d0,a0      ; a0 = A%, a string ending in CR
120  .next   move.b (a0)+,d1
130          cmp.b #13,d1
140          beq done
150          cmp.b #97,d1       ; below "a"?
160          blo next
170          cmp.b #122,d1      ; above "z"?
180          bhi next
190          subi.b #32,-1(a0)  ; to upper case
200          bra next
210  .done   rts
220  ]
230 NEXT
240 PRINT
250 B%=44720
260 T%=TIME:S%=0:FOR I%=1 TO B%:S%=S%+I%:NEXT:T%=TIME-T%
270 PRINT "1+2+...+";B%;" in BASIC:        ";S%;"  (";FNsecs(T%);")"
280 T%=TIME:S%=USR(sum):T%=TIME-T%
290 PRINT "1+2+...+";B%;" in machine code: ";S%;"  (";FNsecs(T%);")"
300 $buf%="Hello from the 68000!":A%=buf%:CALL upper
310 PRINT "CALL upper: ";$buf%
320 PRINT "Type CHAIN ""menu"" for the menu, or LIST to see the program."
330 END
340 DEF FNsecs(t%)=STR$(t% DIV 100)+"."+RIGHT$("0"+STR$(t% MOD 100),2)+" s"
