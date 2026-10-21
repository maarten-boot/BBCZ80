/* bare.c - BBC BASIC 68k on a bare rosco_m68k: the little "kernel" under
 * osl.c (compiled with -DBARE) instead of Minix.
 *
 * osl.c talks POSIX: read/write on the console with termios modes, a
 * SIGINT for ESCape, times(), and files through open/read/write/lseek.
 * Here those calls are made with the machine alone:
 *   console	channel A of the XR68C681 DUART, as the firmware set it up;
 *		received characters come in by interrupt into a buffer, so
 *		typeahead is kept while a program runs;
 *   termios	the modes osl.c uses: VMIN/VTIME for reads, ISIG with VINTR
 *		(ESC while a program runs: the "SIGINT" handler is called
 *		from the interrupt), IXON (^S/^Q stop and start the output);
 *		no canonical mode (osl.c does not use it here);
 *   time	the DUART counter/timer, HZ interrupts a second;
 *   files	a RAM file store: up to NFILE files in 512-byte blocks in
 *		the top part of the memory (bare_init), one directory, names
 *		of up to NAMELEN characters, case sensitive.  It survives
 *		exit() (*BYE starts BASIC again), not a reset.
 * The firmware is left alone otherwise (its System Data Block gives the
 * memory size).  start.s does the start-up and the interrupt entry.
 * Compiled by the ACK: int is 16 bits.
 */
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/times.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <string.h>
#include <termios.h>
#include <unistd.h>

int errno;

/* start.s */
void bare_restart(void);
void bare_isr(void);
void bare_idle(void);
long bare_getvbr(void);
int bare_ints(int on);

/* the files a build brings along (seeds.c, made by tools/mkbare.py) */
struct seed {
	char *name;
	char *data;
	long size;
};
extern struct seed bare_seeds[];	/* name 0 ends it */
extern char *bare_autorun;		/* CHAINed at the start, or 0 */

int bare_argc;
char *bare_argv[3];

/*==================================================== the hardware ===*/

#define DU(n)	(*(volatile unsigned char *) (0xF00001L + 2 * (n)))
#define DU_SRA	1		/* R: status A */
#define DU_CRA	2		/* W: command A */
#define DU_RHRA	3		/* R: receive A */
#define DU_THRA	3		/* W: transmit A */
#define DU_ACR	4		/* W: auxiliary control */
#define DU_ISR	5		/* R: interrupt status */
#define DU_IMR	5		/* W: interrupt mask */
#define DU_CTUR	6		/* W: counter preset, upper */
#define DU_CTLR	7		/* W: counter preset, lower */
#define DU_IVR	12		/* RW: interrupt vector */
#define DU_START 14		/* R: start the counter */
#define DU_STOP	15		/* R: in timer mode: clear its interrupt */

#define SR_RXRDY 0x01
#define SR_TXRDY 0x04
#define SR_ERRS	0xF0
#define ISR_RXRDYA 0x02
#define ISR_CTR	0x08
#define CR_RSTERR 0x40

#define ACR_VAL	0xF0		/* baud rate set 2 (as the firmware), timer
				 * mode, crystal / 16 */
#define HZ	60		/* osl.c's times() rate */
#define TIMER	(3686400L / 16 / 2 / HZ)
#define VECTOR	0x45		/* the DUART's interrupt vector */

#define SDB_MAGIC	(*(long *) 0x400L)
#define SDB_UPTICKS	(*(long *) 0x40CL)
#define SDB_MEMSIZE	(*(long *) 0x414L)

static volatile long ticks;
static volatile unsigned char sink;	/* reads that are commands: the ACK
					 * drops "(void) DU(n)" */
long bare_vbr;			/* where the vectors are */

/*==================================================== console ========*/

#define RXSIZE	1024
static volatile unsigned char rx[RXSIZE];
static volatile int rxhead, rxtail;	/* in at head (interrupt), out at tail */
static volatile int stopped;		/* ^S: output stopped */
static struct termios tio;
static void (*sigint)(int);

/* a received character: signals and flow control, else the buffer */
static void tty_rx(int c)
{
	int h;

	if ((tio.c_lflag & ISIG) && tio.c_cc[VINTR] != _POSIX_VDISABLE
	    && c == tio.c_cc[VINTR]) {
		if (!(tio.c_lflag & NOFLSH))
			rxtail = rxhead;
		if (sigint)
			(*sigint)(SIGINT);
		return;
	}
	if (tio.c_iflag & IXON) {
		if (c == tio.c_cc[VSTOP]) {
			stopped = 1;
			return;
		}
		if (c == tio.c_cc[VSTART]) {
			stopped = 0;
			return;
		}
	}
	if ((tio.c_iflag & ICRNL) && c == '\r')
		c = '\n';
	h = (rxhead + 1) % RXSIZE;
	if (h != rxtail) {			/* (full: dropped) */
		rx[rxhead] = c;
		rxhead = h;
	}
}

/* the DUART interrupt (start.s bare_isr) */
void bare_irq(void)
{
	unsigned char isr = DU(DU_ISR), sr;

	if (isr & ISR_CTR) {
		sink = DU(DU_STOP);
		ticks++;
		SDB_UPTICKS++;
	}
	while ((sr = DU(DU_SRA)) & SR_RXRDY) {
		int c = DU(DU_RHRA);
		if (sr & SR_ERRS) {
			DU(DU_CRA) = CR_RSTERR;
			continue;
		}
		tty_rx(c);
	}
}

static int con_read(char *buf, int n)
{
	int vmin = tio.c_cc[VMIN], got = 0;
	long end = ticks + (long) tio.c_cc[VTIME] * HZ / 10;

	if (!(tio.c_lflag & ICANON) && vmin == 0) {
		while (rxtail == rxhead && tio.c_cc[VTIME] && ticks < end)
			bare_idle();
	} else {
		while (rxtail == rxhead)
			bare_idle();
	}
	while (got < n && rxtail != rxhead) {
		buf[got++] = rx[rxtail];
		rxtail = (rxtail + 1) % RXSIZE;
	}
	return got;
}

static void con_write(const char *buf, int n)
{
	while (n-- > 0) {
		while (stopped)
			bare_idle();
		while (!(DU(DU_SRA) & SR_TXRDY))
			;
		DU(DU_THRA) = *buf++;
	}
}

int tcgetattr(int fd, struct termios *t)
{
	*t = tio;
	return 0;
}

int tcsetattr(int fd, int act, const struct termios *t)
{
	tio = *t;
	if (!(tio.c_iflag & IXON))
		stopped = 0;
	return 0;
}

int isatty(int fd)
{
	return fd >= 0 && fd <= 2;
}

int sigaction(int sig, const struct sigaction *act, struct sigaction *old)
{
	if (old)
		old->sa_handler = sig == SIGINT && sigint ? sigint : SIG_DFL;
	if (act && sig == SIGINT)
		sigint = act->sa_handler == SIG_DFL || act->sa_handler == SIG_IGN
		    ? 0 : act->sa_handler;
	return 0;
}

__sighandler_t signal(int sig, __sighandler_t h)
{
	return SIG_DFL;
}

int sigemptyset(sigset_t *s)
{
	*s = 0;
	return 0;
}

clock_t times(struct tms *t)
{
	t->tms_utime = t->tms_stime = t->tms_cutime = t->tms_cstime = 0;
	return ticks;
}

/* *BYE, and anything else that ends the program: BASIC again */
void exit(int st)
{
	bare_restart();
}

void _exit(int st)
{
	bare_restart();
}

pid_t fork(void)
{
	errno = ENOMEM;
	return -1;
}

/*==================================================== RAM files ======*/

#define BLK	512
#define NFILE	128
#define NAMELEN	31
#define NFD	16		/* file descriptors 3 .. 3 + NFD - 1 */
#define FREE	(-2)
#define LAST	(-1)

struct rfile {
	char name[NAMELEN + 1];		/* "" if the slot is free */
	int first;			/* first block, LAST if none */
	long size;
};

static struct rfile files[NFILE];	/* (in the .bss: kept by exit) */
static int *next;			/* next block of each, or FREE/LAST */
static char *blocks;
static int nblocks;
static long poolsize;

static struct fd {
	int file;			/* -1: closed */
	int flags;
	long pos;
} fds[NFD];

static struct rfile *lookup(const char *name)
{
	int i;

	while (name[0] == '.' && name[1] == '/')
		name += 2;
	for (i = 0; i < NFILE; i++)
		if (files[i].name[0] && strcmp(files[i].name, name) == 0)
			return &files[i];
	return 0;
}

static void freechain(int b)
{
	while (b != LAST && b != FREE) {
		int n = next[b];
		next[b] = FREE;
		b = n;
	}
}

static int newblock(void)
{
	int b;

	for (b = 0; b < nblocks; b++)
		if (next[b] == FREE) {
			next[b] = LAST;
			memset(blocks + (long) b * BLK, 0, BLK);
			return b;
		}
	return -1;
}

/* the block that holds byte pos of f; alloc: make it */
static int blockof(struct rfile *f, long pos, int alloc)
{
	int i, b, n = (int) (pos / BLK), prev = LAST;

	b = f->first;
	for (i = 0; ; i++) {
		if (b == LAST) {
			if (!alloc || (b = newblock()) < 0)
				return -1;
			if (prev == LAST)
				f->first = b;
			else
				next[prev] = b;
		}
		if (i == n)
			return b;
		prev = b;
		b = next[b];
	}
}

static struct fd *getfd(int fd)
{
	if (fd < 3 || fd >= 3 + NFD || fds[fd - 3].file < 0) {
		errno = EBADF;
		return 0;
	}
	return &fds[fd - 3];
}

int open(const char *name, int flags, ...)
{
	struct rfile *f;
	int i;

	while (name[0] == '.' && name[1] == '/')
		name += 2;
	if (strlen(name) > NAMELEN || name[0] == 0 || strchr(name, '/')) {
		errno = ENOENT;
		return -1;
	}
	f = lookup(name);
	if (f == 0) {
		if (!(flags & O_CREAT)) {
			errno = ENOENT;
			return -1;
		}
		for (i = 0; i < NFILE && files[i].name[0]; i++)
			;
		if (i == NFILE) {
			errno = ENFILE;
			return -1;
		}
		f = &files[i];
		strcpy(f->name, name);
		f->first = LAST;
		f->size = 0;
	} else if (flags & O_TRUNC) {
		freechain(f->first);
		f->first = LAST;
		f->size = 0;
	}
	for (i = 0; i < NFD && fds[i].file >= 0; i++)
		;
	if (i == NFD) {
		errno = EMFILE;
		return -1;
	}
	fds[i].file = f - files;
	fds[i].flags = flags;
	fds[i].pos = 0;
	return i + 3;
}

int close(int fd)
{
	struct fd *d = getfd(fd);

	if (d == 0)
		return -1;
	d->file = -1;
	return 0;
}

ssize_t read(int fd, void *buf, size_t n)
{
	struct fd *d;
	struct rfile *f;
	char *p = buf;
	int got = 0;

	if (fd == 0)
		return con_read(buf, (int) n);
	if ((d = getfd(fd)) == 0)
		return -1;
	f = &files[d->file];
	while (got < (int) n && d->pos < f->size) {
		int off = (int) (d->pos % BLK), b = blockof(f, d->pos, 0);
		long k = BLK - off;
		if (k > (long) n - got)
			k = (long) n - got;
		if (k > f->size - d->pos)
			k = f->size - d->pos;
		memcpy(p + got, blocks + (long) b * BLK + off, (int) k);
		got += (int) k;
		d->pos += k;
	}
	return got;
}

ssize_t write(int fd, const void *buf, size_t n)
{
	struct fd *d;
	struct rfile *f;
	const char *p = buf;
	int put = 0;

	if (fd == 1 || fd == 2) {
		con_write(buf, (int) n);
		return n;
	}
	if ((d = getfd(fd)) == 0)
		return -1;
	if ((d->flags & O_ACCMODE) == O_RDONLY) {
		errno = EBADF;
		return -1;
	}
	f = &files[d->file];
	while (put < (int) n) {
		int off = (int) (d->pos % BLK), b = blockof(f, d->pos, 1);
		int k = BLK - off;
		if (b < 0) {
			if (put == 0) {
				errno = ENOSPC;
				return -1;
			}
			break;
		}
		if (k > (int) n - put)
			k = (int) n - put;
		memcpy(blocks + (long) b * BLK + off, p + put, k);
		put += k;
		d->pos += k;
		if (d->pos > f->size)
			f->size = d->pos;
	}
	return put;
}

off_t lseek(int fd, off_t off, int whence)
{
	struct fd *d = getfd(fd);
	long pos;

	if (d == 0)
		return -1;
	pos = whence == SEEK_SET ? off : whence == SEEK_CUR ? d->pos + off
	    : files[d->file].size + off;
	if (pos < 0) {
		errno = EINVAL;
		return -1;
	}
	d->pos = pos;
	return pos;
}

int fstat(int fd, struct stat *st)
{
	struct fd *d = getfd(fd);

	if (d == 0)
		return -1;
	memset(st, 0, sizeof(*st));
	st->st_mode = S_IFREG | 0666;
	st->st_size = files[d->file].size;
	return 0;
}

int access(const char *name, int mode)
{
	if (lookup(name))
		return 0;
	errno = ENOENT;
	return -1;
}

int unlink(const char *name)
{
	struct rfile *f = lookup(name);

	if (f == 0) {
		errno = ENOENT;
		return -1;
	}
	freechain(f->first);
	f->name[0] = 0;
	return 0;
}

int rename(const char *old, const char *new)
{
	struct rfile *f = lookup(old), *g;

	while (new[0] == '.' && new[1] == '/')
		new += 2;
	if (f == 0 || strlen(new) > NAMELEN || new[0] == 0 || strchr(new, '/')) {
		errno = ENOENT;
		return -1;
	}
	if ((g = lookup(new)) != 0 && g != f)
		unlink(new);
	strcpy(f->name, new);
	return 0;
}

int chdir(const char *name)
{
	if (strcmp(name, "/") == 0 || strcmp(name, ".") == 0)
		return 0;
	errno = ENOENT;
	return -1;
}

/* v right-aligned in w characters at p */
static void fmtnum(char *p, long v, int w)
{
	int i;

	for (i = w - 1; i >= 0; i--) {
		p[i] = (v || i == w - 1) ? '0' + (int) (v % 10) : ' ';
		v /= 10;
	}
}

/* *DIR: the files, their sizes and the free space */
void bare_dir(void)
{
	char line[NAMELEN + 16];
	int i, n, nfree = 0;

	for (i = 0; i < NFILE; i++) {
		if (!files[i].name[0])
			continue;
		strcpy(line, files[i].name);
		for (n = strlen(line); n < NAMELEN + 1; n++)
			line[n] = ' ';
		fmtnum(line + n, files[i].size, 9);
		strcpy(line + n + 9, "\r\n");
		con_write(line, strlen(line));
	}
	for (i = 0; i < nblocks; i++)
		if (next[i] == FREE)
			nfree++;
	strcpy(line, "free");
	for (n = 4; n < NAMELEN + 1; n++)
		line[n] = ' ';
	fmtnum(line + n, (long) nfree * BLK, 9);
	strcpy(line + n + 9, "\r\n");
	con_write(line, strlen(line));
}

/*==================================================== start ==========*/

extern char _end[];

/* the machine: at the start (cold, after loading) and after exit();
 * returns the stack pointer for BASIC (its HIMEM)
 */
long bare_init(int cold)
{
	long memtop, pool, *vbr;
	int i;

	bare_ints(0);
	memtop = SDB_MAGIC == 0xB105D47AL && SDB_MEMSIZE >= 0x80000L
	    ? SDB_MEMSIZE : 0x100000L;

	/* the file store: a quarter of the memory above the program */
	poolsize = ((memtop - (long) _end) / 4) & ~(long) (BLK - 1);
	pool = memtop - poolsize;
	nblocks = (int) (poolsize / (BLK + sizeof(int)));
	if ((long) nblocks > 32000L)
		nblocks = 32000;
	next = (int *) pool;
	blocks = (char *) ((pool + (long) nblocks * sizeof(int) + 3) & ~3L);
	for (i = 0; i < NFD; i++)
		fds[i].file = -1;
	if (cold) {
		struct seed *s;
		for (i = 0; i < nblocks; i++)
			next[i] = FREE;
		for (s = bare_seeds; s->name; s++) {
			int fd = open(s->name, O_RDWR | O_CREAT | O_TRUNC, 0666);
			long k;
			for (k = 0; k < s->size; k += 16384)
				write(fd, s->data + k,
				    (size_t) (s->size - k > 16384 ? 16384 : s->size - k));
			close(fd);
		}
	}

	/* the console as found: like a Minix tty, osl.c changes it */
	memset(&tio, 0, sizeof(tio));
	tio.c_iflag = ICRNL | IXON;
	tio.c_lflag = ISIG | ICANON | ECHO;
	tio.c_cc[VINTR] = 0x7F;
	tio.c_cc[VSTART] = 'Q' & 0x1F;
	tio.c_cc[VSTOP] = 'S' & 0x1F;
	tio.c_cc[VMIN] = 1;
	rxhead = rxtail = 0;
	stopped = 0;
	sigint = 0;

	/* the DUART: timer at HZ, interrupts for it and the receiver */
	DU(DU_IMR) = 0;
	vbr = (long *) bare_getvbr();
	vbr[VECTOR] = (long) bare_isr;
	DU(DU_ACR) = ACR_VAL;
	DU(DU_CTUR) = (unsigned char) (TIMER >> 8);
	DU(DU_CTLR) = (unsigned char) (TIMER & 0xFF);
	sink = DU(DU_START);
	DU(DU_IVR) = VECTOR;
	DU(DU_IMR) = ISR_CTR | ISR_RXRDYA;
	bare_ints(1);

	bare_argv[0] = "bbcbasic";
	bare_argv[1] = bare_autorun;
	bare_argv[2] = 0;
	bare_argc = bare_autorun ? 2 : 1;
	return pool & ~3L;
}

/* emrts.o (ACK's run-time) wants these */
char *_brk(char *a)
{
	return a;
}

int _write(int fd, char *buf, int n)
{
	return (int) write(fd, buf, (size_t) n);
}
