10 REM GOSUB / GOTO through a longer program
20 ?&FFFFF0=1
30 N%=0:FOR I%=1 TO 300:GOSUB 1000:IF I% MOD 3 GOTO 40
40 NEXT:GOTO 2000
1000 N%=N%+1:RETURN
1010 REM padding lines
1020 REM padding lines
1030 REM padding lines
1040 REM padding lines
1050 REM padding lines
2000 ?&FFFFF0=2
2010 PRINT N%
