/* mathtest - run FPP (math.s) on test vectors.
 *
 * stdin: one vector per line (tools/mathcheck.py), in hex:
 *	"op m1 e1 m2 e2"	operation op on m1/e1 and m2/e2
 *	"25 m1 e1 fmt 00"	STR$ of m1/e1 with @% = fmt
 *	"24 string"		VAL of the string
 * stdout: "mmmmmmmm ee aa" per vector, "Enn" on an error (nn = error
 * number, decimal), or "\"string\"" for STR$, between the lines BEGIN and
 * END.
 */
#include <stdio.h>
#include <string.h>

long fp_m;
int fp_e, fp_a, fp_err;
char *fp_ptr;

int callfpp(), callfpp2();

int main()
{
	char line[100], out[64];
	unsigned char fmt[4];
	unsigned op, e1, e2;
	long m1, m2;
	char *p;

	printf("BEGIN\n");
	while (fgets(line, sizeof(line), stdin) != NULL) {
		if ((p = strchr(line, '\n')) != NULL)
			*p = 0;
		if (strncmp(line, "24 ", 3) == 0) {
			callfpp2(0x24, 0L, 0, out, line + 3);
		} else {
			if (sscanf(line, "%x %lx %x %lx %x",
			    &op, &m1, &e1, &m2, &e2) != 5)
				continue;
			if (op == 0x25) {
				fmt[0] = m2; fmt[1] = m2 >> 8;
				fmt[2] = m2 >> 16; fmt[3] = m2 >> 24;
				callfpp2(op, m1, e1, out, (char *) fmt);
				if (!fp_err) {
					*fp_ptr = 0;
					printf("\"%s\"\n", out);
					continue;
				}
			} else
				callfpp(op, m1, e1, m2, e2);
		}
		if (fp_err)
			printf("E%d\n", fp_a);
		else
			printf("%08lx %02x %02x\n", fp_m, fp_e, fp_a);
	}
	printf("END\n");
	return 0;
}
