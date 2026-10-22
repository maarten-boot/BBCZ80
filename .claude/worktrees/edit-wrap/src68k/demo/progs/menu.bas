10 REM BBC BASIC 68000 demo: menu
20 DIM name$(6),what$(6)
30 FOR I%=1 TO 6:READ name$(I%),what$(I%):NEXT
40 CLS
50 PRINT "BBC BASIC (Z80) v5, ported to the 68000 - demo programs"
60 PRINT "======================================================="
70 PRINT
80 FOR I%=1 TO 6:PRINT ;I%;". ";name$(I%);TAB(14);what$(I%):NEXT
90 PRINT
100 INPUT "Number to run (Return: BASIC prompt) ";C%
110 IF C%<1 OR C%>6 THEN PRINT "Type CHAIN ""menu"" to come back here.":END
120 CHAIN name$(C%)
130 DATA mandel,"The Mandelbrot set in ASCII (floating point)"
140 DATA sieve,"Sieve of Eratosthenes (byte arrays, timing)"
150 DATA hanoi,"Towers of Hanoi (recursive procedures)"
160 DATA life,"Conway's Life (full-screen, TAB(x,y))"
170 DATA asm,"The 68000 inline assembler"
180 DATA queens,"Eight queens (recursive function, arrays)"
