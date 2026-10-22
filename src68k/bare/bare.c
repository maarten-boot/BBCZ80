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
long bare_host(int op, long a, long b, long c);
void bare_nohost(void);

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

/* *BYE, and anything else that ends the program: BASIC again, or as a
 * program on a PC (bare_host) the end of the program
 */
static int host;

void exit(int st)
{
	if (host)
		bare_host(15, (long) st, 0L, 0L);		/* (H_EXIT) */
	bare_restart();
}

void _exit(int st)
{
	exit(st);
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

/* Files are in one of three places:
 *   HOST	the files of the PC, when BASIC runs as a program there
 *		(src68k/host; bare_host, found by bare_init);
 *   SD		the SD card (fat.c), if it has a FAT file system;
 *   RAM	the RAM store above.
 * The first that is there is the primary device: a new file goes there,
 * and a file is looked for there, then in the RAM store (where the demo
 * programs are).  "host:", "sd:" and "ram:" in front of a name say which.
 * File descriptors: the store's 3 .., the card's SDFD + its handle, the
 * host's HOSTFD + its handle.
 */
#define D_HOST	1
#define D_SD	2
#define D_RAM	3
#define SDFD	32
#define HOSTFD	48
#define NHOST	16

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

#define HOST_MAGIC	0x42424348L
#define H_PROBE	1
#define H_OPEN	2
#define H_CLOSE	3
#define H_READ	4
#define H_WRITE	5
#define H_SEEK	6
#define H_SIZE	7
#define H_UNLINK 8
#define H_RENAME 9
#define H_MKDIR	10
#define H_RMDIR	11
#define H_CHDIR	12
#define H_EXISTS 13
#define H_DIRENT 14
#define H_EXIT	15

static int sd;			/* the card has a FAT file system */
static int sdflags[8];		/* open flags of the card's files */
static int hostflags[NHOST];
static long hostpos[NHOST];

/* "host:" -> D_HOST, "sd:" -> D_SD, "ram:" -> D_RAM, else 0; *name past it */
static int device(const char **name)
{
	static struct { char *pre; int dev; } p[] = {
		{ "host:", D_HOST }, { "sd:", D_SD }, { "ram:", D_RAM }, { 0, 0 }
	};
	int i, k;

	for (i = 0; p[i].pre; i++) {
		for (k = 0; p[i].pre[k]; k++) {
			int c = (*name)[k];
			if (c >= 'A' && c <= 'Z')
				c += 32;
			if (c != p[i].pre[k])
				break;
		}
		if (p[i].pre[k] == 0) {
			*name += k;
			return p[i].dev;
		}
	}
	return 0;
}

static int primary(void)
{
	return host ? D_HOST : sd ? D_SD : D_RAM;
}

/* a host call's result: < 0 is a Minix errno */
static long hres(long r)
{
	if (r < 0) {
		errno = (int) -r;
		return -1;
	}
	return r;
}

static int dev_open(int dev, const char *name, int flags)
{
	long k;

	switch (dev) {
	case D_HOST:
		if (!host || (k = hres(bare_host(H_OPEN, (long) name, (long) flags, 0L))) < 0) {
			if (!host)
				errno = ENOENT;
			return -1;
		}
		hostflags[k] = flags;
		hostpos[k] = 0;
		return HOSTFD + (int) k;
	case D_SD:
		if (!sd) {
			errno = ENOENT;
			return -1;
		}
		if ((k = fat_open(name, flags)) < 0)
			return -1;
		sdflags[k] = flags;
		return SDFD + (int) k;
	}
	return ram_open(name, flags);
}

static int dev_exists(int dev, const char *name)
{
	switch (dev) {
	case D_HOST:
		return host && bare_host(H_EXISTS, (long) name, 0L, 0L) == 1;
	case D_SD:
		return sd && fat_exists(name);
	}
	return ram_access(name) == 0;
}

int open(const char *name, int flags, ...)
{
	int dev = device(&name), p = primary(), fd;

	if (dev)
		return dev_open(dev, name, flags);
	if (p == D_RAM)
		return ram_open(name, flags);
	/* a new file (OPENOUT, SAVE) goes to the primary device; one that is
	 * only in the store stays there; a name the card cannot take
	 * (EINVAL: not 8.3) goes to the store
	 */
	if ((flags & O_CREAT) && !(flags & O_TRUNC) && !dev_exists(p, name)
	    && ram_access(name) == 0)
		return ram_open(name, flags);
	if ((fd = dev_open(p, name, flags)) >= 0
	    || (errno != ENOENT && errno != EINVAL))
		return fd;
	return ram_open(name, flags);
}

#define IS_SD(fd)	((fd) >= SDFD && (fd) < SDFD + 8)
#define IS_HOST(fd)	((fd) >= HOSTFD && (fd) < HOSTFD + NHOST)

int close(int fd)
{
	if (IS_SD(fd))
		return fat_close(fd - SDFD);
	if (IS_HOST(fd))
		return (int) hres(bare_host(H_CLOSE, (long) (fd - HOSTFD), 0L, 0L));
	return ram_close(fd);
}

ssize_t read(int fd, void *buf, size_t n)
{
	long r;

	if (fd == 0)
		return con_read(buf, (int) n);
	if (IS_SD(fd))
		return fat_read(fd - SDFD, buf, (int) n);
	if (IS_HOST(fd)) {
		r = hres(bare_host(H_READ, (long) (fd - HOSTFD), (long) buf, (long) n));
		if (r > 0)
			hostpos[fd - HOSTFD] += r;
		return (ssize_t) r;
	}
	return ram_read(fd, buf, (int) n);
}

ssize_t write(int fd, const void *buf, size_t n)
{
	long r;

	if (fd == 1 || fd == 2) {
		con_write(buf, (int) n);
		return n;
	}
	if (IS_SD(fd) || IS_HOST(fd)) {
		int fl = IS_SD(fd) ? sdflags[fd - SDFD] : hostflags[fd - HOSTFD];
		if ((fl & O_ACCMODE) == O_RDONLY) {
			errno = EBADF;
			return -1;
		}
	}
	if (IS_SD(fd))
		return fat_write(fd - SDFD, buf, (int) n);
	if (IS_HOST(fd)) {
		r = hres(bare_host(H_WRITE, (long) (fd - HOSTFD), (long) buf, (long) n));
		if (r > 0)
			hostpos[fd - HOSTFD] += r;
		return (ssize_t) r;
	}
	return ram_write(fd, buf, (int) n);
}

off_t lseek(int fd, off_t off, int whence)
{
	long pos, cur, size;

	if (!IS_SD(fd) && !IS_HOST(fd))
		return ram_lseek(fd, off, whence);
	if (IS_SD(fd)) {
		cur = fat_tell(fd - SDFD);
		size = fat_size(fd - SDFD);
	} else {
		cur = hostpos[fd - HOSTFD];
		size = whence == SEEK_END
		    ? bare_host(H_SIZE, (long) (fd - HOSTFD), 0L, 0L) : 0L;
	}
	pos = whence == SEEK_SET ? off : whence == SEEK_CUR ? cur + off : size + off;
	if (pos < 0) {
		errno = EINVAL;
		return -1;
	}
	if (IS_SD(fd))
		return fat_lseek(fd - SDFD, pos);
	hostpos[fd - HOSTFD] = pos;
	return hres(bare_host(H_SEEK, (long) (fd - HOSTFD), pos, 0L));
}

int fstat(int fd, struct stat *st)
{
	if (IS_SD(fd) || IS_HOST(fd)) {
		memset(st, 0, sizeof(*st));
		st->st_mode = S_IFREG | 0666;
		st->st_size = IS_SD(fd) ? fat_size(fd - SDFD)
		    : bare_host(H_SIZE, (long) (fd - HOSTFD), 0L, 0L);
		return 0;
	}
	return ram_fstat(fd, st);
}

int access(const char *name, int mode)
{
	int dev = device(&name);

	if (dev ? dev_exists(dev, name)
	    : dev_exists(primary(), name) || ram_access(name) == 0)
		return 0;
	errno = ENOENT;
	return -1;
}

int unlink(const char *name)
{
	int dev = device(&name), p = dev ? dev : primary();

	if (p == D_HOST && dev_exists(p, name))
		return (int) hres(bare_host(H_UNLINK, (long) name, 0L, 0L));
	if (p == D_SD && dev_exists(p, name))
		return fat_unlink(name);
	if (dev && dev != D_RAM) {
		errno = ENOENT;
		return -1;
	}
	return ram_unlink(name);
}

int rename(const char *old, const char *new)
{
	int dev = device(&old), p = dev ? dev : primary();

	device(&new);
	if (p == D_HOST && dev_exists(p, old))
		return (int) hres(bare_host(H_RENAME, (long) old, (long) new, 0L));
	if (p == D_SD && dev_exists(p, old))
		return fat_rename(old, new);
	if (dev && dev != D_RAM) {
		errno = ENOENT;
		return -1;
	}
	return ram_rename(old, new);
}

/* *DIR: the primary device's current directory, then the RAM store */
static void dirline(char *name, long size, int isdir)
{
	char line[64 + 16];
	int n;

	strncpy(line, name, 63);
	line[63] = 0;
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
	char name[66];
	int i, nfree = 0, any = 0;
	long size;

	if (host) {
		con_write("Files:\r\n", 8);
		for (i = 0; (size = bare_host(H_DIRENT, (long) i, (long) name, 0L)) >= 0; i++)
			dirline(name, size, name[strlen(name) + 1]);
	} else if (sd) {
		con_write("SD card:\r\n", 10);
		fat_list(dirline);
	}
	for (i = 0; i < NFILE; i++)
		if (files[i].name[0])
			any = 1;
	if ((host || sd) && !any)
		return;
	if (host || sd)
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
	int dev = device(&name), p = dev ? dev : primary();

	if (p == D_HOST && host)
		return (int) hres(bare_host(H_MKDIR, (long) name, 0L, 0L));
	if (p == D_SD && sd)
		return fat_mkdir(name);
	errno = EINVAL;			/* (the RAM store has one directory) */
	return -1;
}

int rmdir(const char *name)
{
	int dev = device(&name), p = dev ? dev : primary();

	if (p == D_HOST && host)
		return (int) hres(bare_host(H_RMDIR, (long) name, 0L, 0L));
	if (p == D_SD && sd)
		return fat_rmdir(name);
	errno = ENOENT;
	return -1;
}

int chdir(const char *name)
{
	int dev = device(&name), p = dev ? dev : primary();

	if (p == D_HOST && host)
		return (int) hres(bare_host(H_CHDIR, (long) name, 0L, 0L));
	if (p == D_SD && sd)
		return fat_chdir(name);
	if (strcmp(name, "/") == 0 || strcmp(name, ".") == 0)
		return 0;
	errno = ENOENT;
	return -1;
}

/*==================================================== start ==========*/

static long *vbr0(void)
{
	return (long *) bare_getvbr();
}

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

	/* host files (BASIC as a program on a PC), asked for with the
	 * illegal instruction vector at bare_nohost; the SD card, if it has
	 * a FAT file system and there are no host files
	 */
	{
		long old = vbr0()[4];
		vbr0()[4] = (long) bare_nohost;
		host = bare_host(H_PROBE, 0L, 0L, 0L) == HOST_MAGIC;
		vbr0()[4] = old;
	}
	sd = host ? 0 : fat_mount();

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
