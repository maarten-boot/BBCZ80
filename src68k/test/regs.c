long g;
int callee(a, b, p) int a; long b; char *p;
{
	register int i; register long s; register char *q; register char *r;
	s = b; q = p; r = p + a;
	for (i = 0; i < a; i++) { s += *q++ * (long)i; s ^= *--r; }
	g = s;
	return (int)s;
}
