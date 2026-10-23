10 REM Towers of Hanoi with a recursive procedure
20 INPUT "Number of discs (Return: 4) ";N%
30 IF N%<1 OR N%>16 THEN N%=4
40 M%=0:T%=TIME
50 PROChanoi(N%,1,3,2)
60 PRINT ;M%;" moves (2^";N%;"-1 = ";2^N%-1;")"
70 PRINT "Time: ";FNsecs(TIME-T%)
80 PRINT "Type CHAIN ""menu"" for the menu, or LIST to see the program."
90 END
100 REM move D% discs from peg F% to peg T%, using peg V%
110 DEF PROChanoi(D%,F%,T%,V%)
120 IF D%=0 THEN ENDPROC
130 PROChanoi(D%-1,F%,V%,T%)
140 M%=M%+1
150 IF N%<=5 THEN PRINT "Move disc ";D%;" from peg ";F%;" to peg ";T%
160 PROChanoi(D%-1,V%,T%,F%)
170 ENDPROC
180 DEF FNsecs(t%)=STR$(t% DIV 100)+"."+RIGHT$("0"+STR$(t% MOD 100),2)+" s"
