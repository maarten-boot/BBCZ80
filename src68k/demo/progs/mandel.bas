10 REM The Mandelbrot set in ASCII
20 C$=".,:;-=+*#%@"
30 T%=TIME
40 FOR R%=0 TO 22
50   Y=-1.1+R%*0.1:L$=""
60   FOR C%=0 TO 71
70     X=-2.1+C%*0.042:A=0:B=0:I%=0
80     REPEAT
90       T=A*A-B*B+X:B=2*A*B+Y:A=T:I%=I%+1
100    UNTIL I%=40 OR A*A+B*B>4
110    IF I%=40 THEN L$=L$+" " ELSE L$=L$+MID$(C$,I% MOD 11+1,1)
120  NEXT
130  PRINT L$
140 NEXT
150 PRINT "Time: ";FNsecs(TIME-T%)
160 PRINT "Type CHAIN ""menu"" for the menu, or LIST to see the program."
170 END
180 DEF FNsecs(t%)=STR$(t% DIV 100)+"."+RIGHT$("0"+STR$(t% MOD 100),2)+" s"
