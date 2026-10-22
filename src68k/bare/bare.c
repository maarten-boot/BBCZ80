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
 *   files	on the SD card's FAT file system (fat.c), if it has one,
 *		and in a RAM file store: up to NFILE files in 512-byte
 *		blocks in the top part of the memory (bare_init), one
 *		directory, names of up to NAMELEN characters, case
 *		sensitive, kept by exit() (*BYE starts BASIC again), not by
 *		a reset.  See "the devices" for which is used.
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

/* v right-aligned in w characters at p */
static void fmtnum(char *p, long v, int w)
{
	int i;

	for (i = w - 1; i >= 0; i--) {
		p[i] = (v || i == w - 1) ? '0' + (int) (v % 10) : ' ';
		v /= 10;
	}
}

static int ram_open(const char *name, int flags)
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

static int ram_close(int fd)
{
	struct fd *d = getfd(fd);

	if (d == 0)
		return -1;
	d->file = -1;
	return 0;
}

static int ram_read(int fd, void *buf, int n)
{
	struct fd *d;
	struct rfile *f;
	char *p = buf;
	int got = 0;

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

static int ram_write(int fd, const void *buf, int n)
{
	struct fd *d;
	struct rfile *f;
	const char *p = buf;
	int put = 0;

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

static long ram_lseek(int fd, long off, int whence)
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

static int ram_fstat(int fd, struct stat *st)
{
	struct fd *d = getfd(fd);

	if (d == 0)
		return -1;
	memset(st, 0, sizeof(*st));
	st->st_mode = S_IFREG | 0666;
	st->st_size = files[d->file].size;
	return 0;
}

static int ram_access(const char *name)
{
	if (lookup(name))
		return 0;
	errno = ENOENT;
	return -1;
}

static int ram_unlink(const char *name)
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

static int ram_rename(const char *old, const char *new)
{
	struct rfile *f = lookup(old), *g;

	while (new[0] == '.' && new[1] == '/')
		new += 2;
	if (f == 0 || strlen(new) > NAMELEN || new[0] == 0 || strchr(new, '/')) {
		errno = ENOENT;
		return -1;
	}
	if ((g = lookup(new)) != 0 && g != f)
		ram_unlink(new);
	strcpy(f->name, new);
	return 0;
}

/*==================================================== the devices ====*/

/* Files are on the SD card (fat.c, if it has a FAT file system at the
 * start) or in the RAM store.  "sd:name" and "ram:name" say which;
 * otherwise a file is looked for on the card, then in the store, and a
 * new one goes on the card if there is one.  File descriptors: the
 * store's 3 .., the card's SDFD + its handle.
 */
#define SDFD	32

int fat_mount(void);
int fat_open(const char *path, int flags);
int fat_close(int k);
int fat_read(int k, char *buf, int n);
int fat_write(int k, const char *buf, int n);
long fat_lseek(int k, long pos);
long fat_tell(int k);
long fat_size(int k);
int fat_exists(const char *path);
int fat_unlink(const char *path);
int fat_rename(const char *old, const char *new);
int fat_chdir(const char *path);
int fat_mkdir(const char *path);
int fat_rmdir(const char *path);
void fat_list(void (*emit)(char *, long, int));

static int sd;			/* the card has a FAT file system */
static int sdflags[8];		/* open flags of the card's files */

/* "sd:" -> 1, "ram:" -> 2, else 0; *name past it */
static int device(const char **name)
{
	const char *n = *name;

	if ((n[0] == 's' || n[0] == 'S') && (n[1] == 'd' || n[1] == 'D')
	    && n[2] == ':') {
		*name = n + 3;
		return 1;
	}
	if ((n[0] == 'r' || n[0] == 'R') && (n[1] == 'a' || n[1] == 'A')
	    && (n[2] == 'm' || n[2] == 'M') && n[3] == ':') {
		*name = n + 4;
		return 2;
	}
	return 0;
}

static int sd_open(const char *name, int flags)
{
	int k;

	if (!sd) {
		errno = ENOENT;
		return -1;
	}
	if ((k = fat_open(name, flags)) < 0)
		return -1;
	sdflags[k] = flags;
	return SDFD + k;
}

int open(const char *name, int flags, ...)
{
	int dev = device(&name), fd;

	if (dev == 1)
		return sd_open(name, flags);
	if (dev == 2 || !sd)
		return ram_open(name, flags);
	/* a new file (OPENOUT, SAVE) goes on the card, unless the name is
	 * not 8.3 (EINVAL): then in the store
	 */
	if ((flags & O_CREAT) && !(flags & O_TRUNC) && !fat_exists(name)
	    && ram_access(name) == 0)
		return ram_open(name, flags);
	if ((fd = sd_open(name, flags)) >= 0
	    || (errno != ENOENT && errno != EINVAL))
		return fd;
	return ram_open(name, flags);
}

int close(int fd)
{
	if (fd >= SDFD && fd < SDFD + 8)
		return fat_close(fd - SDFD);
	return ram_close(fd);
}

ssize_t read(int fd, void *buf, size_t n)
{
	if (fd == 0)
		return con_read(buf, (int) n);
	if (fd >= SDFD && fd < SDFD + 8)
		return fat_read(fd - SDFD, buf, (int) n);
	return ram_read(fd, buf, (int) n);
}

ssize_t write(int fd, const void *buf, size_t n)
{
	if (fd == 1 || fd == 2) {
		con_write(buf, (int) n);
		return n;
	}
	if (fd >= SDFD && fd < SDFD + 8) {
		if ((sdflags[fd - SDFD] & O_ACCMODE) == O_RDONLY) {
			errno = EBADF;
			return -1;
		}
		return fat_write(fd - SDFD, buf, (int) n);
	}
	return ram_write(fd, buf, (int) n);
}

off_t lseek(int fd, off_t off, int whence)
{
	int k = fd - SDFD;
	long pos;

	if (k < 0 || k >= 8)
		return ram_lseek(fd, off, whence);
	pos = whence == SEEK_SET ? off : whence == SEEK_CUR ? fat_tell(k) + off
	    : fat_size(k) + off;
	if (pos < 0) {
		errno = EINVAL;
		return -1;
	}
	return fat_lseek(k, pos);
}

int fstat(int fd, struct stat *st)
{
	if (fd >= SDFD && fd < SDFD + 8) {
		memset(st, 0, sizeof(*st));
		st->st_mode = S_IFREG | 0666;
		st->st_size = fat_size(fd - SDFD);
		return 0;
	}
	return ram_fstat(fd, st);
}

int access(const char *name, int mode)
{
	int dev = device(&name);

	if (dev != 2 && sd && fat_exists(name))
		return 0;
	if (dev != 1 && ram_access(name) == 0)
		return 0;
	errno = ENOENT;
	return -1;
}

int unlink(const char *name)
{
	int dev = device(&name);

	if (dev != 2 && sd && fat_exists(name))
		return fat_unlink(name);
	if (dev == 1) {
		errno = ENOENT;
		return -1;
	}
	return ram_unlink(name);
}

int rename(const char *old, const char *new)
{
	int dev = device(&old);

	device(&new);
	if (dev != 2 && sd && fat_exists(old))
		return fat_rename(old, new);
	if (dev == 1) {
		errno = ENOENT;
		return -1;
	}
	return ram_rename(old, new);
}

/* *DIR: the card's current directory, then the RAM store */
static void dirline(char *name, long size, int isdir)
{
	char line[NAMELEN + 16];
	int n;

	strcpy(line, name);
	for (n = strlen(line); n < NAMELEN + 1; n++)
		line[n] = ' ';
	if (isdir)
		strcpy(line + n, "    <DIR>");
	else
		fmtnum(line + n, size, 9);
	strcpy(line + n + 9, "\r\n");
	con_write(line, strlen(line));
}

void bare_dir(void)
{
	int i, nfree = 0, any = 0;

	if (sd) {
		con_write("SD card:\r\n", 10);
		fat_list(dirline);
	}
	for (i = 0; i < NFILE; i++)
		if (files[i].name[0])
			any = 1;
	if (sd && !any)
		return;
	if (sd)
		con_write("RAM:\r\n", 6);
	for (i = 0; i < NFILE; i++)
		if (files[i].name[0])
			dirline(files[i].name, files[i].size, 0);
	for (i = 0; i < nblocks; i++)
		if (next[i] == FREE)
			nfree++;
	dirline("free", (long) nfree * BLK, 0);
}

int mkdir(const char *name, Mode_t mode)
{
	device(&name);
	if (sd)
		return fat_mkdir(name);
	errno = EINVAL;			/* (the RAM store has one directory) */
	return -1;
}

int rmdir(const char *name)
{
	device(&name);
	if (sd)
		return fat_rmdir(name);
	errno = ENOENT;
	return -1;
}

int chdir(const char *name)
{
	device(&name);
	if (sd)
		return fat_chdir(name);
	if (strcmp(name, "/") == 0 || strcmp(name, ".") == 0)
		return 0;
	errno = ENOENT;
	return -1;
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
			int fd = ram_open(s->name, O_RDWR | O_CREAT | O_TRUNC);
			long k;
			for (k = 0; k < s->size; k += 16384)
				ram_write(fd, s->data + k,
				    (int) (s->size - k > 16384 ? 16384 : s->size - k));
			ram_close(fd);
		}
	}

	/* the SD card, if it has a FAT file system */
	sd = fat_mount();

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
