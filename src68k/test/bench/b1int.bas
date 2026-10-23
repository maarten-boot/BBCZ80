10 REM integer arithmetic in a FOR loop
20 ?&FFFFF0=1
30 A%=0:FOR I%=1 TO 5000:A%=A%+I%*3-(I% DIV 7):NEXT
40 ?&FFFFF0=2
50 PRINT A%
