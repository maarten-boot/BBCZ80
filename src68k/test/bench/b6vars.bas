10 REM variable lookup, IF, REPEAT, arrays
20 alpha=1:beta=2:gamma=3:delta=4:epsilon=5:zeta=6:eta=7:theta=8
30 DIM arr(100)
40 ?&FFFFF0=1
50 i=0:REPEAT i=i+1:arr(i MOD 100)=alpha+beta*gamma-delta/epsilon
60 IF zeta>eta THEN theta=theta+1 ELSE theta=theta-1
70 UNTIL i>=500
80 ?&FFFFF0=2
90 PRINT theta;arr(5)
