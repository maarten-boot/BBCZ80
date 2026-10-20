10 REM procedures, functions, recursion, LOCAL
20 ?&FFFFF0=1
30 PRINT FNfib(13):FOR I%=1 TO 100:PROCp(I%,2):NEXT
40 ?&FFFFF0=2
50 PRINT T%
60 END
70 DEF FNfib(n%):IF n%<2 THEN =n% ELSE =FNfib(n%-1)+FNfib(n%-2)
80 DEF PROCp(a%,b%):LOCAL c%:c%=a%*b%:T%+=c%:ENDPROC
