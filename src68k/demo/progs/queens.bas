10 REM Eight queens: all solutions, with a recursive function
20 N%=8:DIM col%(N%),up%(2*N%),down%(2*N%)
30 T%=TIME:shown%=0
40 S%=FNplace(1):PRINT "Solutions: ";S%
50 PRINT "Time: ";FNsecs(TIME-T%)
60 PRINT "Type CHAIN ""menu"" for the menu, or LIST to see the program."
70 END
100 REM the number of ways to complete the board from row R%
110 DEF FNplace(R%)
120 LOCAL C%,K%
130 IF R%>N% THEN PROCshow:=1
140 FOR C%=1 TO N%
150   IF col%(C%)=0 AND up%(R%+C%)=0 AND down%(R%-C%+N%)=0 THEN col%(C%)=R%:up%(R%+C%)=1:down%(R%-C%+N%)=1:K%=K%+FNplace(R%+1):col%(C%)=0:up%(R%+C%)=0:down%(R%-C%+N%)=0
160 NEXT
170 =K%
200 DEF PROCshow
210 LOCAL X%,Y%
220 shown%=shown%+1:IF shown%>1 THEN ENDPROC
230 PRINT "The first solution:"
240 FOR Y%=1 TO N%:FOR X%=1 TO N%
250   IF col%(X%)=Y% THEN PRINT " Q"; ELSE PRINT " .";
260 NEXT:PRINT:NEXT
270 ENDPROC
280 DEF FNsecs(t%)=STR$(t% DIV 100)+"."+RIGHT$("0"+STR$(t% MOD 100),2)+" s"
