10 REM Conway's Game of Life on a vt100 screen
20 W%=60:H%=20:S%=W%+2:Z%=S%*(H%+2)
30 DIM cur% Z%,nxt% Z%
40 R=RND(-TIME)
50 FOR I%=0 TO Z%:cur%?I%=0:nxt%?I%=0:NEXT
60 FOR Y%=1 TO H%:FOR X%=1 TO W%:cur%?(Y%*S%+X%)=-(RND(1)<0.3):NEXT:NEXT
70 CLS
80 FOR gen%=1 TO 100
90   PRINT TAB(0,0);"Conway's Life - generation ";gen%;"  (Escape stops)"
100  FOR Y%=1 TO H%
110    r$=""
120    FOR X%=1 TO W%
130      IF cur%?(Y%*S%+X%) THEN r$=r$+"O" ELSE r$=r$+" "
140    NEXT
150    PRINT TAB(0,Y%);"|";r$;"|"
160  NEXT
170  FOR Y%=1 TO H%
180    FOR X%=1 TO W%
190      p%=cur%+Y%*S%+X%
200      n%=?(p%-S%-1)+?(p%-S%)+?(p%-S%+1)+?(p%-1)+?(p%+1)+?(p%+S%-1)+?(p%+S%)+?(p%+S%+1)
210      IF n%=3 OR (?p% AND n%=2) THEN nxt%?(p%-cur%)=1 ELSE nxt%?(p%-cur%)=0
220    NEXT
230  NEXT
240  t%=cur%:cur%=nxt%:nxt%=t%
250 NEXT
260 PRINT TAB(0,H%+1);"Type CHAIN ""menu"" for the menu, or LIST to see the program."
