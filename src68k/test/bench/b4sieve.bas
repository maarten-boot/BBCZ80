10 REM sieve of Eratosthenes (byte array)
20 S%=2000:DIM F% S%
30 ?&FFFFF0=1
40 C%=0:FOR I%=0 TO S%:F%?I%=1:NEXT
50 FOR I%=2 TO S%:IF F%?I% THEN C%+=1:FOR K%=I%+I% TO S% STEP I%:F%?K%=0:NEXT
60 NEXT
70 ?&FFFFF0=2
80 PRINT C%
