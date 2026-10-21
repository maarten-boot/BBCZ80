10 REM Sieve of Eratosthenes
20 INPUT "Primes up to (Return: 50000) ";N%
30 IF N%<2 OR N%>200000 THEN N%=50000
40 DIM F% N%
50 FOR I%=0 TO N%:F%?I%=0:NEXT
60 T%=TIME:C%=0:L%=SQR(N%)
70 FOR I%=2 TO N%
80   IF F%?I%=0 THEN C%=C%+1:IF I%<=L% THEN PROCmark(I%)
90 NEXT
100 T%=TIME-T%
110 PRINT "There are ";C%;" primes up to ";N%
120 PRINT "The last ones are:";
130 K%=0:I%=N%
140 REPEAT
150   IF F%?I%=0 THEN PRINT " ";I%;:K%=K%+1
160   I%=I%-1
170 UNTIL K%=5 OR I%<2
180 PRINT
190 PRINT "Time: ";FNsecs(T%)
200 PRINT "Type CHAIN ""menu"" for the menu, or LIST to see the program."
210 END
220 DEF PROCmark(P%)
230 LOCAL J%
240 FOR J%=P%*P% TO N% STEP P%:F%?J%=1:NEXT
250 ENDPROC
260 DEF FNsecs(t%)=STR$(t% DIV 100)+"."+RIGHT$("0"+STR$(t% MOD 100),2)+" s"
