/* osl.c - Minix OS layer for BBC BASIC 68k.
 *
 * Replaces the CP/M patch (CMOS.Z80) and the distribution module
 * (DIST.Z80): console, line editor, ESCape, files, *commands and time.
 * Called through the register glue in minix.s, which maps the Z80-style
 * interface of each routine onto these functions.  Compiled by the ACK
 * (minix68k: int is 16 bits, long 32).
 *
 * No stdio and no malloc: the memory above the end of .bss is BASIC's.
 *
 * With -DBARE the same layer runs on a bare rosco_m68k: bare/bare.c makes
 * the POSIX calls (console, RAM files); there is no shell, so *commands
 * that are not BASIC's are "Bad command", and *DIR lists the RAM files.
 */
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/times.h>
#include <sys/wait.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <termios.h>
#include <unistd.h>

int rename(const char *_old, const char *_new);	/* (in <stdio.h>) */

#define BEL	7
#define BS	8
#define LF	10
#define CR	13
#define ESC	27
#define DEL	127

/* os_flags, as the CP/M FLAGS byte */
#define F_EXEC	0x01		/* *EXEC active */
#define F_SPOOL	0x02		/* *SPOOL active */
#define F_EDIT	0x08		/* EDIT: capture output into the line */
#define F_OVR	0x10		/* overwrite (not insert) in the editor */
#define F_NOESC	0x40		/* *ESC OFF */
#define F_ESC	0x80		/* ESCape pressed */

#define NCHAN	7		/* user channels 1-7, as on CP/M */
#define CH_EXEC	8
#define CH_SPOOL 9
#define BUFSZ	512

/* the glue (minix.s) and the interpreter */
void oserror(int code, char *msg);	/* EXTERR: does not return */
extern char accs[];			/* string accumulator */
extern long curlin;			/* current line (0 = immediate) */
extern long autono;			/* AUTO flag and number */
extern char vermsg[];			/* version message, CR LF terminated */

long os_gettime(void);
void os_bye(void);
void os_bput(int ch, int b);

unsigned char os_flags;
unsigned char os_inkey;			/* key read ahead by getkey (after ESC) */

static int istty;			/* stdin is a terminal */
static struct termios oldtio, rawtio, runtio;
static int rawmode;			/* setmode's mode; -1: set it again */
static unsigned char optval;		/* *OPT */
static int column;			/* for POS */
static char *edptr;			/* EDIT capture pointer */
static char *edbuf;			/* EDIT capture buffer */
static char *edend;			/* EDIT capture limit: the first line */
static long toffset;			/* TIME offset (centiseconds) */
static int hz = 60;

static char obuf[128];			/* console output buffer */
static int olen;

struct chan {
	int fd;			/* -1: closed */
	long bstart;		/* file offset of buf[0] */
	int blen;		/* valid bytes in buf */
	int bpos;		/* current position in buf */
	int dirty;
	long size;		/* file size when last checked/written */
	char buf[BUFSZ];
};
static struct chan chans[CH_SPOOL + 1];

/*==================================================== console ======*/

static void flush(void)
{
	int i = 0, n;

	while (i < olen) {		/* (ESCape can interrupt the write) */
		n = write(1, obuf + i, olen - i);
		if (n > 0)
			i += n;
		else if (n < 0 && errno == EINTR)
			continue;
		else
			break;
	}
	olen = 0;
}

/* Terminal mode: 0 cooked (as found), 1 raw blocking, 2 raw polling,
 * 3 raw with VTIME = tenths of a second, 4 running a program.
 * Mode 4 is raw but lets the terminal driver watch for ESCape: ESC is the
 * interrupt character (ISIG, VINTR; not with *ESC OFF), whose SIGINT sets
 * the ESCape flag (sigesc), so the ESCape test needs no system call (see
 * os_poll).  NOFLSH keeps the typeahead and the output; IXON lets ^S/^Q
 * stop and start the output.  The modes that read keys have ISIG off:
 * there ESC is a key as before.
 */
static void setmode(int m, int tenths)
{
	if (!istty || (m == rawmode && m != 3))
		return;
	if (m == 0) {
		tcsetattr(0, TCSANOW, &oldtio);
	} else if (m == 4) {
		runtio = rawtio;
		runtio.c_lflag |= ISIG | NOFLSH;
		runtio.c_iflag |= IXON;
		runtio.c_cc[VINTR] = (os_flags & F_NOESC) ? _POSIX_VDISABLE : ESC;
		runtio.c_cc[VQUIT] = _POSIX_VDISABLE;
		runtio.c_cc[VSUSP] = _POSIX_VDISABLE;
		runtio.c_cc[VMIN] = 1;
		runtio.c_cc[VTIME] = 0;
		tcsetattr(0, TCSANOW, &runtio);
	} else {
		rawtio.c_cc[VMIN] = (m == 1) ? 1 : 0;
		rawtio.c_cc[VTIME] = (m == 3) ? tenths : 0;
		tcsetattr(0, TCSANOW, &rawtio);
	}
	rawmode = m;
}

/* Read one byte from the keyboard: wait (mode 1), poll (mode 2) or wait
 * up to tenths/10 s (mode 3).  -1 if none, -2 at end of input.
 */
static int readkey(int m, int tenths)
{
	unsigned char c;
	int n;

	flush();
	setmode(m, tenths);
	n = read(0, (char *) &c, 1);
	if (n == 1)
		return c;
	if (n == 0 && (!istty || m == 1))
		return -2;
	return -1;
}

static void setesc(void)
{
	if (!(os_flags & F_NOESC))
		os_flags |= F_ESC;
}

/* SIGINT: ESC while a program runs (setmode 4) */
static void sigesc(int sig)
{
	setesc();
}

/* out - send a character to the console (and the *SPOOL file) */
static void out(int c)
{
	if (os_flags & F_EDIT) {		/* EDIT: capture the line */
		if (c >= ' ' && edptr < edend)
			*edptr++ = c;
		else if (c == LF)		/* (EDIT, EDIT m,n: the first) */
			edend = edptr;
		return;
	}
	obuf[olen++] = c;
	if (olen >= sizeof(obuf) || c == LF)
		flush();
	if (c == CR)
		column = 0;
	else if (c == BS) {
		if (column > 0)
			column--;
	} else if (c >= ' ' && c != DEL)
		column++;
	if (os_flags & F_SPOOL) {
		os_flags &= ~F_SPOOL;		/* (no recursion on errors) */
		os_bput(CH_SPOOL, c);
		os_flags |= F_SPOOL;
	}
}

/* os_poll - TEST (every 20th TRAP): flush the output and, on a terminal,
 * leave it in mode 4, where ESC raises SIGINT and sigesc sets the ESCape
 * flag that TRAP tests.  (Reading the keyboard here, as the CP/M version
 * does, took a system call each time: about 40% of the time of a loop.)
 */
void os_poll(void)
{
	flush();
	setmode(4, 0);
}

void os_wrch(int c)
{
	out(c & 0xff);
}

/* getkey - read a key, up to cs centiseconds (cs < 0: wait for ever).
 * vt100 cursor keys come as ESC [ x (or ESC O x) and are mapped to the editor's
 * control keys.  Returns the character, -1 on time-out.
 */
static int getkey(long cs)
{
	int c, c2, c3;
	long end;

	if (os_inkey != 0) {
		c = os_inkey;
		os_inkey = 0;
		return c;
	}
	if (cs < 0)
		c = readkey(1, 0);
	else if (cs == 0)
		c = readkey(2, 0);
	else {
		end = os_gettime() + cs;
		do {
			long left = end - os_gettime();
			if (left <= 0) {
				c = -1;
				break;
			}
			left = (left + 9) / 10;
			c = readkey(3, left > 255 ? 255 : (int) left);
		} while (c == -1 && istty);
	}
	if (c == -2) {				/* end of input: as *BYE */
		os_bye();
	}
	if (c != ESC || !istty)
		return c;
	c2 = readkey(3, 1);			/* cursor key? ESC [ x, or */
	if (c2 != '[' && c2 != 'O') {		/* ESC O x (application mode) */
		if (c2 >= 0)
			os_inkey = c2;
		return ESC;
	}
	c3 = readkey(3, 1);
	switch (c3) {
	case 'A': return 'G' & 0x1f;		/* up: start of line */
	case 'B': return 'O' & 0x1f;		/* down: end of line */
	case 'C': return 'L' & 0x1f;		/* right */
	case 'D': return 'J' & 0x1f;		/* left */
	case 'H': return 'F' & 0x1f;		/* home */
	case 'F': return 'N' & 0x1f;		/* end */
	case '3': readkey(3, 1); return 'R' & 0x1f; /* delete */
	case '2': readkey(3, 1); return 'Q' & 0x1f; /* insert */
	}
	return ESC;
}

/* os_key - OSKEY: key within cs centiseconds; -1 on time-out.  Sets the
 * ESCape flag for ESC.
 */
int os_key(long cs)
{
	int c;

	if (cs < 0)
		return -1;			/* INKEY(-n): not supported */
	c = getkey(cs);
	if (c == ESC)
		setesc();
	return c;
}

static int exec_in(void);

/* os_rdch - OSRDCH: read from the input stream (keyboard or *EXEC) */
int os_rdch(void)
{
	int c;

	if (os_flags & F_EXEC)
		return exec_in();
	c = getkey(-1L);
	if (c == ESC)
		setesc();
	return c;
}

/*==================================================== editor =======*/

/* os_line - OSLINE: read/edit a line into buf (256 bytes), CR terminated.
 * The CP/M editor: control keys (DIST.Z80 table) ^G/^O start/end
 * (repeating left/right), ^F/^N start/end, ^J/^L left/right, BS/DEL
 * delete left, ^U clear left, ^X clear right, ^R delete right, ^Q
 * insert/overwrite, ^P printer toggle; vt100 cursor keys work too.
 * Returns 1 if ESCape ended the line.
 */
static int keyget(void)
{
	int c;

	if (os_flags & F_EXEC)
		return exec_in();
	c = getkey(-1L);
	if (c == ESC)
		setesc();
	if (c == DEL)
		c = BS;
	return c;
}

/* redraw - print from p to the CR, then clr spaces (to wipe what the
 * line used to occupy), and move the cursor back to p
 */
static void redraw(char *p, int clr)
{
	int n = 0;

	while (*p != CR) {
		out(*p++);
		n++;
	}
	while (clr-- > 0) {
		out(' ');
		n++;
	}
	while (n-- > 0)
		out(BS);
}

int os_line(char *buf)
{
	int i = 0, c, k, n;

	if ((os_flags & F_EDIT) && edptr != NULL) {
		os_flags &= ~F_EDIT;
		*edptr = CR;
		if (edptr != buf) {
			out(CR);
			redraw(buf, 1);
		}
	} else {
		os_flags &= ~F_EDIT;
		buf[0] = CR;
	}
	if (!istty && !(os_flags & F_EXEC)) {	/* piped input: plain lines */
		n = 0;
		for (;;) {
			c = getkey(-1L);
			if (c == LF || c == CR)
				break;
			if (n < 255)
				buf[n++] = c;
		}
		buf[n] = CR;
		for (k = 0; k < n; k++)
			out(buf[k]);
		out(CR);
		out(LF);
		return 0;
	}
	for (;;) {
		c = keyget();
		if (os_flags & F_ESC)
			c = CR;
		k = c;
		switch (k) {
		case 'P' & 0x1f:			/* printer toggle */
			continue;
		case 'G' & 0x1f:			/* to start (repeat) */
		case 'F' & 0x1f:
			while (i > 0) {
				out(BS);
				i--;
			}
			continue;
		case 'O' & 0x1f:			/* to end (repeat) */
		case 'N' & 0x1f:
			while (buf[i] != CR)
				out(buf[i++]);
			continue;
		case 'U' & 0x1f:			/* clear left */
			n = i;
			while (i > 0) {
				out(BS);
				i--;
			}
			memmove(buf, buf + n, strchr(buf + n, CR) - buf - n + 1);
			redraw(buf, n);
			continue;
		case 'X' & 0x1f:			/* clear right */
			n = strchr(buf + i, CR) - (buf + i);
			buf[i] = CR;
			redraw(buf + i, n);
			continue;
		case BS:				/* delete left */
		case 'J' & 0x1f:			/* left */
			if (i == 0)
				continue;
			out(BS);
			i--;
			if (k == ('J' & 0x1f))
				continue;
			/* fall through: delete right */
		case 'R' & 0x1f:			/* delete right */
			if (buf[i] == CR)
				continue;
			memmove(buf + i, buf + i + 1,
			    strchr(buf + i, CR) - (buf + i));
			redraw(buf + i, 1);
			continue;
		case 'L' & 0x1f:			/* right */
			if (buf[i] != CR)
				out(buf[i++]);
			continue;
		case 'Q' & 0x1f:			/* insert / overwrite */
			os_flags ^= F_OVR;
			continue;
		}
		if (k == CR)
			break;
		if (k < ' ')
			continue;
		/* printing character */
		n = strchr(buf, CR) - buf;		/* line length */
		if ((os_flags & F_OVR) || buf[i] == CR) {
			if (buf[i] == CR) {
				if (n >= 255) {
					out(BEL);
					continue;
				}
				buf[i + 1] = CR;
			}
			buf[i] = k;
			out(buf[i++]);
		} else {
			if (n >= 255) {
				out(BEL);
				continue;
			}
			memmove(buf + i + 1, buf + i, n - i + 1);
			buf[i] = k;
			out(buf[i++]);
			redraw(buf + i, 0);
		}
	}
	while (buf[i] != CR)			/* write rest of line */
		out(buf[i++]);
	out(CR);
	if (os_flags & F_ESC)
		return 1;
	out(LF);
	edbuf = edptr = buf;
	edend = buf + 255;
	/* EDIT n (immediate mode only) -> LIST n, capturing the output */
	if (curlin == 0 && autono == 0) {
		static char edit[] = "EDIT";
		for (k = 0; k < 4; k++) {
			if (buf[k] == '.' && k > 0)
				break;
			if ((buf[k] & 0xdf) != edit[k])
				return 0;
		}
		memcpy(buf, "LIST", k);
		os_flags |= F_EDIT;
	}
	return 0;
}

/*==================================================== files ========*/

/* getname - copy a CR (or NUL) terminated name, skipping spaces and
 * an optional pair of quotes; returns the end of the name in s.  An
 * empty name, or one with the wildcards ? or *, is a "Bad name" (as on
 * CP/M); a missing closing quote is a "Bad string".
 */
static char *getname(char *s, char *name)
{
	int n = 0, q = 0;

	while (*s == ' ')
		s++;
	if (*s == '"') {
		q = 1;
		s++;
	}
	while (*s != CR && *s != 0 &&
	    (q ? *s != '"' : *s != ' ' && *s != '=')) {
		if (*s == '?' || *s == '*')
			n = -1;
		if (n >= 0 && n < 127)
			name[n++] = *s;
		s++;
	}
	if (q) {
		if (*s != '"')
			oserror(253, "Bad string");
		s++;
	}
	if (n <= 0)
		oserror(204, "Bad name");
	name[n] = 0;
	return s;
}

static int hasext(char *name)
{
	char *p = strrchr(name, '/');

	return strchr(p ? p : name, '.') != NULL;
}

/* bbcname - the file name BASIC means: a name without '.' gets .bbc if
 * that file exists, else .BBC (the CP/M default extension).
 */
static void bbcname(char *name, char *full)
{
	strcpy(full, name);
	if (!hasext(name)) {
		strcat(full, ".bbc");
		if (access(full, 0) != 0) {
			strcpy(full, name);
			strcat(full, ".BBC");
		}
	}
}

/* openfile - open a file for BASIC (see bbcname); mode 0 OPENOUT
 * (create), 1 OPENIN, 2 OPENUP.  Returns the fd or -1.
 */
static int openfile(char *name, int mode)
{
	char full[140];
	int fd;

	bbcname(name, full);
	if (mode == 0)
		fd = open(full, O_RDWR | O_CREAT | O_TRUNC, 0666);
	else if (mode == 1)
		fd = open(full, O_RDONLY);
	else
		fd = open(full, O_RDWR);
	return fd;
}

static struct chan *find(int ch)
{
	if (ch < 1 || ch > CH_SPOOL || chans[ch].fd < 0)
		oserror(222, "Invalid channel");
	return &chans[ch];
}

static void cflush(struct chan *c)
{
	if (c->dirty) {
		lseek(c->fd, c->bstart, SEEK_SET);
		if (write(c->fd, c->buf, c->blen) != c->blen) {
			c->dirty = 0;
			oserror(198, "Disk full");
		}
		c->dirty = 0;
		if (c->bstart + c->blen > c->size)
			c->size = c->bstart + c->blen;
	}
}

/* cload - make the buffer hold the file from offset pos on */
static void cload(struct chan *c, long pos)
{
	int n;

	cflush(c);
	c->bstart = pos;
	c->bpos = 0;
	lseek(c->fd, pos, SEEK_SET);
	n = read(c->fd, c->buf, BUFSZ);
	c->blen = n > 0 ? n : 0;
}

static long cext(struct chan *c)
{
	long e = c->size;

	if (c->blen > 0 && c->bstart + c->blen > e)	/* (an empty buffer
						 * past the end adds nothing) */
		e = c->bstart + c->blen;
	return e;
}

static void cinit(int ch, int fd)
{
	struct chan *c = &chans[ch];
	struct stat st;

	c->fd = fd;
	fstat(fd, &st);
	c->size = st.st_size;
	c->dirty = 0;
	c->bpos = 0;
	c->blen = 0;
	c->bstart = 0;
	cload(c, 0L);
}

static void cclose(int ch)
{
	struct chan *c = &chans[ch];

	if (c->fd < 0)
		return;
	cflush(c);
	close(c->fd);
	c->fd = -1;
}

/* os_open - OSOPEN: type 0 OPENOUT, 1 OPENIN, 2 OPENUP; channel or 0 */
int os_open(char *name, int type)
{
	char fname[128];
	int ch, fd;

	getname(name, fname);
	for (ch = 1; ch <= NCHAN; ch++)
		if (chans[ch].fd < 0)
			break;
	if (ch > NCHAN)
		oserror(192, "Too many open files");
	fd = openfile(fname, type);
	if (fd < 0)
		return 0;
	cinit(ch, fd);
	return ch;
}

/* os_shut - OSSHUT: close a channel; 0 closes 1-7 */
void os_shut(int ch)
{
	if (ch == 0) {
		for (ch = 1; ch <= NCHAN; ch++)
			cclose(ch);
		return;
	}
	find(ch);
	cclose(ch);
}

/* os_bget - OSBGET: byte, + 0x100 if it was the last byte of the file
 * (reading past the end gives 0, as the CP/M fill)
 */
int os_bget(int ch)
{
	struct chan *c = find(ch);
	int b;

	if (c->bpos >= BUFSZ)
		cload(c, c->bstart + c->bpos);
	if (c->bpos < c->blen)
		b = (unsigned char) c->buf[c->bpos];
	else
		b = 0;
	c->bpos++;
	if (c->bstart + c->bpos >= cext(c))
		b |= 0x100;
	return b;
}

/* os_bput - OSBPUT */
void os_bput(int ch, int b)
{
	struct chan *c = find(ch);

	if (c->bpos >= BUFSZ)
		cload(c, c->bstart + c->bpos);
	if (c->bpos > c->blen)			/* after reading past the end */
		memset(c->buf + c->blen, 0, c->bpos - c->blen);
	c->buf[c->bpos++] = b;
	c->dirty = 1;
	if (c->bpos > c->blen)
		c->blen = c->bpos;
}

/* os_eof - OSSTAT: 1 at end of file */
int os_eof(int ch)
{
	struct chan *c = find(ch);

	return c->bstart + c->bpos >= cext(c);
}

long os_ext(int ch)
{
	return cext(find(ch));
}

long os_ptr(int ch)
{
	struct chan *c = find(ch);

	return c->bstart + c->bpos;
}

void os_setptr(int ch, long p)
{
	struct chan *c = find(ch);

	if (p < 0)
		p = 0;
	if (p >= c->bstart && p <= c->bstart + c->blen && p - c->bstart < BUFSZ)
		c->bpos = (int) (p - c->bstart);
	else
		cload(c, p);
}

/* os_load - OSLOAD: load a file to addr; 0 if it is bigger than max */
int os_load(char *name, char *addr, long max)
{
	char fname[128];
	int fd, n, ok = 1;
	long total = 0;

	getname(name, fname);
	fd = openfile(fname, 1);
	if (fd < 0)
		oserror(214, "File not found");
	/* no room: read nothing (the data would run into this stack) */
	if (lseek(fd, 0L, SEEK_END) > max) {
		close(fd);
		return 0;
	}
	lseek(fd, 0L, SEEK_SET);
	for (;;) {
		long chunk = max - total;
		if (chunk <= 0) {
			char c;
			if (read(fd, &c, 1) == 1)
				ok = 0;			/* no room */
			break;
		}
		if (chunk > 16384)
			chunk = 16384;
		n = read(fd, addr + total, (int) chunk);
		if (n <= 0)
			break;
		total += n;
	}
	close(fd);
	return ok;
}

/* os_save - OSSAVE */
void os_save(char *name, char *addr, long len)
{
	char fname[128];
	int fd, n;

	getname(name, fname);
	fd = openfile(fname, 0);
	if (fd < 0)
		oserror(190, "Directory full");
	while (len > 0) {
		n = len > 16384 ? 16384 : (int) len;
		if (write(fd, addr, n) != n) {
			close(fd);
			oserror(198, "Disk full");
		}
		addr += n;
		len -= n;
	}
	if (close(fd) != 0)
		oserror(200, "Close error");
}

/* *EXEC input */
static int exec_in(void)
{
	int b;

	os_flags &= ~F_EXEC;
	b = os_bget(CH_EXEC);
	os_flags |= F_EXEC;
	if (b & 0x100) {			/* last byte: end *EXEC */
		os_flags &= ~F_EXEC;
		cclose(CH_EXEC);
	}
	b &= 0xff;
	return b == LF ? CR : b;
}

/*==================================================== time, VDU ====*/

long os_gettime(void)
{
	struct tms t;
	long ticks = times(&t);

	/* centiseconds = ticks * 100 / hz, without overflowing */
	return (ticks / hz) * 100 + (ticks % hz) * 100 / hz + toffset;
}

void os_settime(long t)
{
	toffset = 0;
	toffset = t - os_gettime();
}

static void outs(char *s)
{
	while (*s)
		out(*s++);
}

static void outn(int n)
{
	char d[6];
	int i = 0;

	do {
		d[i++] = '0' + n % 10;
		n /= 10;
	} while (n > 0);
	while (i > 0)
		out(d[--i]);
}

void os_cls(void)			/* CLS: vt100 */
{
	outs("\033[2J\033[H");
	column = 0;
}

void os_putcsr(int x, int y)		/* TAB(x,y): vt100 */
{
	out(ESC);
	out('[');
	outn(y + 1);
	out(';');
	outn(x + 1);
	out('H');
	column = x;
}

long os_getcsr(void)			/* POS (low word), VPOS (high) */
{
	return (long) column;
}

/*==================================================== *commands ====*/

static int upper(int c)
{
	c &= 0x7f;
	return (c >= 'a' && c <= 'z') ? c - 32 : c;
}

static char *skipsp(char *s)
{
	while (*s == ' ')
		s++;
	return s;
}

static void badcmd(void)
{
	oserror(254, "Bad command");
}

static long hexarg(char **sp)
{
	char *s = skipsp(*sp);
	long v = 0;
	int c, n = 0;

	for (;;) {
		c = upper(*s);
		if (c >= '0' && c <= '9')
			c -= '0';
		else if (c >= 'A' && c <= 'F')
			c -= 'A' - 10;
		else
			break;
		v = (v << 4) | c;
		s++;
		n++;
	}
	if (n == 0)
		badcmd();
	*sp = s;
	return v;
}

static void endarg(char *s)
{
	if (*skipsp(s) != CR)
		badcmd();
}

/* run a shell command line (CR terminated) with /bin/sh -c.
 * Done here rather than with system() to tell "no memory" apart: without
 * an MMU the fork needs a second copy of BASIC, and then the exec needs a
 * hole for the shell; on a 1MB rosco_m68k that only fits while BASIC is
 * small.
 */
#define NOMEM	125		/* exit status of the child: exec ENOMEM */
extern char **environ;

#ifdef BARE
static void shell(char *s)
{
	badcmd();
}
#else
static void shell(char *s)
{
	char cmd[256];
	char *av[4];
	int n = 0, pid, st, fd;

	while (*s != CR && n < 255)
		cmd[n++] = *s++;
	cmd[n] = 0;
	flush();
	setmode(0, 0);
	column = 0;
	pid = fork();
	if (pid < 0)
		oserror(0, "No room");
	if (pid == 0) {
		for (fd = 3; fd <= 20; fd++)
			close(fd);
		av[0] = "sh";
		av[1] = "-c";
		av[2] = cmd;
		av[3] = NULL;
		execve("/bin/sh", av, environ);
		_exit(errno == ENOMEM ? NOMEM : 127);
	}
	while (waitpid(pid, &st, 0) != pid)
		if (errno != EINTR)
			return;
	if (((st >> 8) & 0xff) == NOMEM)
		oserror(0, "No room");
}
#endif

static void cmd_bye(char *s)	{ os_bye(); }

static void cmd_cd(char *s)
{
	char name[128];

	s = getname(s, name);
	endarg(s);
	if (chdir(name) != 0)
		oserror(214, "File not found");
}

#ifdef BARE
void bare_dir(void);

static void cmd_dir(char *s)
{
	flush();
	bare_dir();
	column = 0;
}
#else
static void cmd_dir(char *s)
{
	char cmd[140];

	strcpy(cmd, "ls -C ");
	strcat(cmd, skipsp(s));
	shell(cmd);
}
#endif

static void cmd_mkdir(char *s)
{
	char name[128];

	s = getname(s, name);
	endarg(s);
	if (mkdir(name, 0777) != 0) {
		if (errno == EEXIST)
			oserror(196, "File exists");
		oserror(204, "Bad name");
	}
}

static void cmd_rmdir(char *s)
{
	char name[128];

	s = getname(s, name);
	endarg(s);
	if (rmdir(name) != 0)
		oserror(214, errno == ENOENT ? "File not found" : "Directory not empty");
}

static void cmd_era(char *s)
{
	char name[128], full[140];

	s = getname(s, name);
	endarg(s);
	bbcname(name, full);
	if (unlink(full) != 0)
		oserror(214, "File not found");
}

static void cmd_esc(char *s)
{
	s = skipsp(s);
	if (upper(s[0]) == 'O' && upper(s[1]) == 'N')
		os_flags &= ~F_NOESC;
	else if (upper(s[0]) == 'O' && upper(s[1]) == 'F'
	    && upper(s[2]) == 'F')
		os_flags |= F_NOESC;
	else {
		if (upper(s[0]) == 'O')		/* *ESC O n, as CP/M */
			s++;
		if (hexarg(&s))
			os_flags |= F_NOESC;
		else
			os_flags &= ~F_NOESC;
	}
	if (rawmode == 4)			/* (VINTR depends on it) */
		rawmode = -1;
}

static void spoolexec(char *s, int ch, int flag)
{
	char name[128];
	int fd;

	os_flags &= ~(F_EXEC | F_SPOOL);
	cclose(CH_EXEC);
	cclose(CH_SPOOL);
	if (*skipsp(s) == CR)
		return;				/* just shut */
	getname(s, name);
	fd = openfile(name, flag == F_EXEC ? 1 : 0);
	if (fd < 0)
		oserror(214, "File not found");
	cinit(ch, fd);
	os_flags |= flag;
}

static void cmd_exec(char *s)	{ spoolexec(s, CH_EXEC, F_EXEC); }
static void cmd_spool(char *s)	{ spoolexec(s, CH_SPOOL, F_SPOOL); }

static void cmd_help(char *s)
{
	char *p = vermsg;

	while (*p != CR)
		out(*p++);
	out(CR);
	out(LF);
}

static void cmd_opt(char *s)
{
	optval = (unsigned char) (hexarg(&s) & 3);
}

static void cmd_ren(char *s)		/* *REN new=old, as CP/M */
{
	char new[128], old[128], fnew[140], fold[140];

	s = getname(s, new);
	s = skipsp(s);
	if (*s != '=')
		badcmd();
	s = getname(s + 1, old);
	endarg(s);
	bbcname(new, fnew);
	bbcname(old, fold);
	if (access(fnew, 0) == 0)
		oserror(196, "File exists");
	if (rename(fold, fnew) != 0)
		oserror(214, "File not found");
}

static void cmd_reset(char *s)	{ }

/* *SAVE name start end, *SAVE name start +length; *LOAD name addr */
static void cmd_save(char *s)
{
	char name[128];
	long start, end;
	int plus;

	s = getname(s, name);
	start = hexarg(&s);
	s = skipsp(s);
	plus = (*s == '+');
	if (plus)
		s++;
	end = hexarg(&s);
	endarg(s);
	if (!plus)
		end -= start;
	name[strlen(name) + 1] = 0;
	name[strlen(name)] = CR;
	os_save(name, (char *) start, end);
}

static void cmd_load(char *s)
{
	char name[128];
	long addr;

	s = getname(s, name);
	addr = hexarg(&s);
	endarg(s);
	name[strlen(name) + 1] = 0;
	name[strlen(name)] = CR;
	os_load(name, (char *) addr, 0x7fffffffL);
}

static void cmd_type(char *s)
{
	char name[128];
	int fd, n, i, prev;
	char b[128];

	s = getname(s, name);
	endarg(s);
	fd = openfile(name, 1);
	if (fd < 0)
		oserror(214, "File not found");
	prev = 0;
	while ((n = read(fd, b, sizeof(b))) > 0) {
		for (i = 0; i < n; i++) {
			if (b[i] == LF && prev != CR)	/* Unix text: add CR */
				out(CR);
			out(b[i]);
			prev = b[i];
		}
		os_poll();
		if (os_flags & F_ESC)
			break;
	}
	close(fd);
}

static struct {
	char *name;			/* in order; abbreviations take the */
	void (*fn)(char *);		/* first match, as the CP/M table */
} comds[] = {
	{ "BYE", cmd_bye }, { "CD", cmd_cd }, { "DIR", cmd_dir },
	{ "ERASE", cmd_era }, { "ERA", cmd_era }, { "ESC", cmd_esc },
	{ "EXEC", cmd_exec }, { "HELP", cmd_help }, { "LOAD", cmd_load },
	{ "MKDIR", cmd_mkdir }, { "OPT", cmd_opt }, { "QUIT", cmd_bye },
	{ "RENAME", cmd_ren }, { "REN", cmd_ren }, { "RESET", cmd_reset },
	{ "RMDIR", cmd_rmdir }, { "SAVE", cmd_save },
	{ "SPOOL", cmd_spool }, { "TYPE", cmd_type }, { NULL, NULL }
};

/* os_cli - OSCLI: a *command, CR terminated */
void os_cli(char *s)
{
	int i, k;
	char *p;

	s = skipsp(s);
	if (*s == '*')
		s = skipsp(s + 1);
	if (*s == CR || *s == '|')
		return;
	if (*s == '.') {			/* *. = *DIR */
		cmd_dir(s + 1);
		return;
	}
	for (i = 0; comds[i].name != NULL; i++) {
		p = comds[i].name;
		for (k = 0; p[k] != 0; k++) {
			if (s[k] == '.' && k > 0)
				break;
			if (upper(s[k]) != p[k])
				break;
		}
		if (s[k] == '.' && k > 0) {		/* abbreviated */
			comds[i].fn(s + k + 1);
			return;
		}
		if (p[k] == 0 && !((s[k] >= 'A' && s[k] <= 'Z') ||
		    (s[k] >= 'a' && s[k] <= 'z'))) {
			comds[i].fn(s + k);
			return;
		}
	}
	shell(s);				/* not ours: the shell's */
}

/*==================================================== start, stop ==*/

static void sigquit(int sig)
{
	os_bye();
}

/* os_init - OSINIT: set up the terminal; argv[1] (if any) is copied to
 * the string accumulator for an automatic CHAIN.  Returns 1 for that.
 */
int os_init(int argc, char **argv)
{
	int ch;
	struct sigaction sa;

	for (ch = 0; ch <= CH_SPOOL; ch++)
		chans[ch].fd = -1;
	os_flags = 0;
	optval = 0;
	toffset = 0;
	istty = isatty(0);
	if (istty) {
		tcgetattr(0, &oldtio);
		rawtio = oldtio;
		rawtio.c_iflag &= ~(ICRNL | IXON);
		rawtio.c_lflag &= ~(ICANON | ECHO | ISIG);
		rawtio.c_oflag &= ~OPOST;		/* BASIC sends CR LF */
		rawmode = 0;
		setmode(1, 0);
		sa.sa_handler = sigesc;		/* ESC in mode 4 */
		sigemptyset(&sa.sa_mask);
		sa.sa_flags = 0;
		sigaction(SIGINT, &sa, (struct sigaction *) 0);
	}
	signal(SIGTERM, sigquit);
	signal(SIGHUP, sigquit);
	if (argc > 1) {
		strncpy(accs, argv[1], 250);
		accs[250] = 0;
		accs[strlen(accs)] = CR;
		return 1;
	}
	accs[0] = CR;
	return 0;
}

/* os_bye - BYE: close everything, restore the terminal, exit */
void os_bye(void)
{
	int ch;

	for (ch = 1; ch <= CH_SPOOL; ch++)
		cclose(ch);
	flush();
	setmode(0, 0);
	exit(0);
}
