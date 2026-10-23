/* fat.c - files on the SD card for BBC BASIC on a bare rosco_m68k: the
 * card's FAT16 or FAT32 file system (the first FAT partition of its MBR,
 * or a card without a partition table), through the firmware's SD routines
 * (start.s bare_sdinit/sdread/sdwrite).  Used by bare.c behind the POSIX
 * file calls.
 *
 * Names are 8.3, upper case on the card, matched without regard to case;
 * long names (VFAT) are skipped when reading a directory and removed with
 * the file they belong to.  Paths: "a/b/NAME.EXT", from the root with a
 * leading "/", else from the current directory (fat_chdir).
 *
 * One sector buffer, written through: what is written is on the card at
 * once, but for an open file's size and first cluster in its directory
 * entry, which fat_close writes.  The buffer only lasts within a call:
 * every entry point forgets it, so a card changed from outside between
 * calls (the web page writes into its image) is read afresh, and an old
 * copy of a sector is never written back over such a change.
 * Compiled by the ACK: int is 16 bits, so sectors, clusters and sizes are
 * longs.
 */
#include <sys/types.h>
#include <errno.h>
#include <fcntl.h>
#include <string.h>
#include <unistd.h>

extern int errno;

long bare_sdinit(char *card);
long bare_sdread(char *card, long block, char *buf);
long bare_sdwrite(char *card, long block, char *buf);

#define NFH	8			/* open files on the card */
#define EOC32	0x0FFFFFF8L
#define EOC16	0xFFF8L
#define ATTR_DIR 0x10
#define ATTR_LFN 0x0F
#define ATTR_VOL 0x08

static long card[8];			/* the firmware's SDCard structure */
static unsigned char sec[512];
static long secno = -1;			/* the sector in sec, -1: none */

static int fat32, spc, nfats;
static long part, fatlba, fatsz, rootlba, rootsecs, datalba, rootcl;
static long nclusters, fsinfo, hint = 2;
static long freecount = -1;		/* FAT32 FSInfo free count, -1: unknown */
static int fsinfo_dirty;
static long cwd;			/* current directory: first cluster, 0
					 * = the root */

/* (unsigned: the ACK's int is 16 bits, and a 16-bit sector count such as
 * 0xF800 must not come out negative)
 */
static unsigned le16(unsigned char *p)
{
	return p[0] | ((unsigned) p[1] << 8);
}

static long le32(unsigned char *p)
{
	return (long) p[0] | (long) p[1] << 8 | (long) p[2] << 16
	    | (long) p[3] << 24;
}

static void put16(unsigned char *p, long v)
{
	p[0] = (unsigned char) v;
	p[1] = (unsigned char) (v >> 8);
}

static void put32(unsigned char *p, long v)
{
	put16(p, v);
	put16(p + 2, v >> 16);
}

static int getsec(long n)
{
	if (n == secno)
		return 1;
	secno = -1;
	if (!bare_sdread((char *) card, n, (char *) sec))
		return 0;
	secno = n;
	return 1;
}

static int putsec(void)
{
	return secno >= 0 && bare_sdwrite((char *) card, secno, (char *) sec) != 0;
}

/*==================================================== the volume =====*/

/* find the file system; 1 if there is one */
int fat_mount(void)
{
	unsigned char *p;
	long tot, rsv;
	int i, rootents;

	memset(card, 0, sizeof(card));
	if (bare_sdinit((char *) card) != 0)
		return 0;
	secno = -1;
	part = -1;
	if (!getsec(0L) || sec[510] != 0x55 || sec[511] != 0xAA)
		return 0;
	if ((sec[0] == 0xEB || sec[0] == 0xE9) && le16(sec + 11) == 512)
		part = 0;			/* no partition table */
	else
		for (i = 0; i < 4; i++) {
			p = sec + 446 + 16 * i;
			if (p[4] == 0x04 || p[4] == 0x06 || p[4] == 0x0E
			    || p[4] == 0x0B || p[4] == 0x0C) {
				part = le32(p + 8);
				break;
			}
		}
	if (part < 0 || !getsec(part) || le16(sec + 11) != 512)
		return 0;
	spc = sec[13];
	rsv = le16(sec + 14);
	nfats = sec[16];
	rootents = le16(sec + 17);
	tot = le16(sec + 19) ? (long) le16(sec + 19) : le32(sec + 32);
	fatsz = le16(sec + 22) ? (long) le16(sec + 22) : le32(sec + 36);
	if (spc == 0 || nfats == 0)
		return 0;
	fatlba = part + rsv;
	rootlba = fatlba + nfats * fatsz;
	rootsecs = ((long) rootents * 32 + 511) / 512;
	datalba = rootlba + rootsecs;
	nclusters = (tot - (datalba - part)) / spc;
	if (nclusters < 4085)
		return 0;			/* FAT12: not supported */
	fat32 = nclusters >= 65525L;
	rootcl = fat32 ? le32(sec + 44) : 0;
	fsinfo = fat32 ? part + le16(sec + 48) : 0;
	freecount = -1;
	hint = 2;
	fsinfo_dirty = 0;
	if (fat32 && getsec(fsinfo) && le32(sec) == 0x41615252L
	    && le32(sec + 484) == 0x61417272L) {
		long c = le32(sec + 488), h = le32(sec + 492);
		if (c >= 0 && c <= nclusters)
			freecount = c;
		if (h >= 2 && h < nclusters + 2)
			hint = h;
	}
	cwd = 0;
	return 1;
}

static long cl2lba(long cl)
{
	return datalba + (cl - 2) * spc;
}

static long fat_get(long cl)
{
	long off = fat32 ? cl * 4 : cl * 2;

	if (!getsec(fatlba + off / 512))
		return EOC32;
	if (fat32)
		return le32(sec + (int) (off % 512)) & 0x0FFFFFFFL;
	return (long) (unsigned) le16(sec + (int) (off % 512));
}

static int is_eoc(long v)
{
	return v < 2 || (fat32 ? v >= EOC32 : v >= EOC16);
}

static void fat_set(long cl, long v)
{
	long off = fat32 ? cl * 4 : cl * 2;
	int i;

	for (i = 0; i < nfats; i++) {
		if (!getsec(fatlba + i * fatsz + off / 512))
			continue;
		if (fat32)
			put32(sec + (int) (off % 512),
			    (le32(sec + (int) (off % 512)) & 0xF0000000L) | v);
		else
			put16(sec + (int) (off % 512), v);
		putsec();
	}
}

/* a free cluster, marked as the end of a chain; 0 if the card is full */
static long newcluster(int zero)
{
	long cl, i, n;

	for (n = 0; n < nclusters; n++) {
		cl = 2 + (hint - 2 + n) % nclusters;
		if (fat_get(cl) == 0) {
			fat_set(cl, fat32 ? 0x0FFFFFFFL : 0xFFFFL);
			hint = cl + 1;
			if (freecount > 0)
				freecount--;
			fsinfo_dirty = 1;
			if (zero) {
				memset(sec, 0, 512);
				for (i = 0; i < spc; i++) {
					secno = cl2lba(cl) + i;
					putsec();
				}
			}
			return cl;
		}
	}
	return 0;
}

static void freechain(long cl)
{
	long n;

	while (!is_eoc(cl)) {
		n = fat_get(cl);
		fat_set(cl, 0L);
		if (freecount >= 0)
			freecount++;
		fsinfo_dirty = 1;
		cl = n;
	}
}

/* FAT32: the free count and the next free cluster into FSInfo */
static void fsinfo_sync(void)
{
	if (!fat32 || !fsinfo_dirty || !getsec(fsinfo) || le32(sec) != 0x41615252L)
		return;
	put32(sec + 488, freecount);
	put32(sec + 492, hint);
	putsec();
	fsinfo_dirty = 0;
}

/*==================================================== directories ====*/

/* a place in a directory: walking its entries */
struct dpos {
	long cl;		/* cluster (0: the FAT16 root) */
	long lba;		/* sector */
	int n;			/* sector in the cluster (or in the root) */
	int i;			/* entry in the sector */
};

static void dstart(struct dpos *d, long dircl)
{
	if (dircl == 0 && fat32)
		dircl = rootcl;
	d->cl = dircl;
	d->n = 0;
	d->i = -1;
	d->lba = dircl ? cl2lba(dircl) : rootlba;
}

/* the next entry: a pointer into sec, or 0 at the end; grow: add a
 * cluster to a full directory (not the FAT16 root)
 */
static unsigned char *dnext(struct dpos *d, int grow)
{
	if (++d->i == 16) {
		d->i = 0;
		d->n++;
		if (d->cl == 0) {
			if (d->n >= rootsecs)
				return 0;
			d->lba++;
		} else if (d->n < spc) {
			d->lba++;
		} else {
			long nx = fat_get(d->cl);
			if (is_eoc(nx)) {
				if (!grow || (nx = newcluster(1)) == 0)
					return 0;
				fat_set(d->cl, nx);
			}
			d->cl = nx;
			d->n = 0;
			d->lba = cl2lba(nx);
		}
	}
	if (!getsec(d->lba))
		return 0;
	return sec + 32 * d->i;
}

static long ent_cluster(unsigned char *e)
{
	return (long) (unsigned) le16(e + 26)
	    | (fat32 ? (long) (unsigned) le16(e + 20) << 16 : 0L);
}

/* name -> the 11 characters of an 8.3 entry; 0 if it is not 8.3 */
static int name83(const char *s, char *n)
{
	int i = 0, c;

	memset(n, ' ', 11);
	if (strcmp(s, ".") == 0 || strcmp(s, "..") == 0) {
		memcpy(n, s, strlen(s));
		return 1;
	}
	for (; *s && *s != '.'; s++) {
		if (i == 8)
			return 0;
		c = *s;
		n[i++] = c >= 'a' && c <= 'z' ? c - 32 : c;
	}
	if (i == 0)
		return 0;
	if (*s == '.') {
		s++;
		for (i = 8; *s; s++) {
			if (i == 11 || *s == '.')
				return 0;
			c = *s;
			n[i++] = c >= 'a' && c <= 'z' ? c - 32 : c;
		}
	}
	for (i = 0; i < 11; i++) {
		c = (unsigned char) n[i];
		if (c < 0x20 || strchr("\"*+,/:;<=>?[\\]|", c))
			return 0;
	}
	return 1;
}

/* the entry of a found file */
struct found {
	long lba;		/* where its entry is */
	int i;
	long cl;		/* its first cluster */
	long size;
	int attr;
	int nlfn;		/* long name entries before it */
	long lfnlba[20];
	int lfni[20];
};

/* look for name (8.3, 11 characters) in the directory dircl */
static int dfind(long dircl, char *n, struct found *f)
{
	struct dpos d;
	unsigned char *e;

	f->nlfn = 0;
	dstart(&d, dircl);
	while ((e = dnext(&d, 0)) != 0 && e[0] != 0) {
		if (e[0] == 0xE5) {
			f->nlfn = 0;
			continue;
		}
		if (e[11] == ATTR_LFN) {
			if (f->nlfn < 20) {
				f->lfnlba[f->nlfn] = d.lba;
				f->lfni[f->nlfn++] = d.i;
			}
			continue;
		}
		if (!(e[11] & ATTR_VOL) && memcmp(e, n, 11) == 0) {
			f->lba = d.lba;
			f->i = d.i;
			f->cl = ent_cluster(e);
			f->size = le32(e + 28);
			f->attr = e[11];
			return 1;
		}
		f->nlfn = 0;
	}
	return 0;
}

/* path -> the directory it is in and the 8.3 name of its last part */
static int walk(const char *path, long *dircl, char *n)
{
	char part[64];
	struct found f;
	const char *s;
	int k;

	*dircl = *path == '/' ? 0L : cwd;
	while (*path == '/')
		path++;
	for (;;) {
		s = strchr(path, '/');
		k = s ? s - path : strlen(path);
		if (k == 0 || k > 63) {
			errno = ENOENT;
			return 0;
		}
		memcpy(part, path, k);
		part[k] = 0;
		if (!name83(part, n)) {
			errno = EINVAL;
			return 0;
		}
		if (!s)
			return 1;
		if (!dfind(*dircl, n, &f) || !(f.attr & ATTR_DIR)) {
			errno = ENOENT;
			return 0;
		}
		*dircl = f.cl == rootcl && fat32 ? 0L : f.cl;
		path = s + 1;
		while (*path == '/')
			path++;
		if (*path == 0) {		/* "dir/": the directory */
			errno = EISDIR;
			return 0;
		}
	}
}

/* a new entry for n in dircl: where it is (sec holds it) */
static unsigned char *dnew(long dircl, char *n, struct found *f)
{
	struct dpos d;
	unsigned char *e;

	dstart(&d, dircl);
	while ((e = dnext(&d, 1)) != 0) {
		if (e[0] == 0 || e[0] == 0xE5) {
			memset(e, 0, 32);
			memcpy(e, n, 11);
			e[11] = 0x20;			/* archive */
			put16(e + 24, 0x0021L);		/* 1980-01-01 */
			put16(e + 18, 0x0021L);
			f->lba = d.lba;
			f->i = d.i;
			f->cl = 0;
			f->size = 0;
			f->attr = 0x20;
			f->nlfn = 0;
			putsec();
			return e;
		}
	}
	errno = ENOSPC;
	return 0;
}

/*==================================================== files ==========*/

static struct fh {
	int used, flags, dirty;
	long lba;		/* its directory entry */
	int i;
	long first, size, pos;
	long cur, curn;		/* a cluster of it and its number in the
				 * chain, for going on from there */
} fh[NFH];

/* the cluster that holds cluster number n of the file; alloc: add */
static long clusterof(struct fh *h, long n, int alloc)
{
	long cl, k, nx;

	if (h->first == 0) {
		if (!alloc || (h->first = newcluster(0)) == 0)
			return 0;
		h->dirty = 1;
	}
	if (h->cur && n >= h->curn) {
		cl = h->cur;
		k = h->curn;
	} else {
		cl = h->first;
		k = 0;
	}
	for (; k < n; k++) {
		nx = fat_get(cl);
		if (is_eoc(nx)) {
			if (!alloc || (nx = newcluster(0)) == 0)
				return 0;
			fat_set(cl, nx);
		}
		cl = nx;
	}
	h->cur = cl;
	h->curn = n;
	return cl;
}

static int entry_update(struct fh *h)
{
	unsigned char *e;

	if (!getsec(h->lba))
		return 0;
	e = sec + 32 * h->i;
	put16(e + 26, h->first);
	if (fat32)
		put16(e + 20, h->first >> 16);
	put32(e + 28, h->size);
	h->dirty = 0;
	return putsec();
}

int fat_open(const char *path, int flags)
{
	char n[11];
	long dircl;
	struct found f;
	struct fh *h;
	int k;

	secno = -1;				/* (the card may have changed) */
	for (k = 0; k < NFH && fh[k].used; k++)
		;
	if (k == NFH) {
		errno = EMFILE;
		return -1;
	}
	if (!walk(path, &dircl, n))
		return -1;
	if (!dfind(dircl, n, &f)) {
		if (!(flags & O_CREAT)) {
			errno = ENOENT;
			return -1;
		}
		if (!dnew(dircl, n, &f))
			return -1;
	} else if (f.attr & ATTR_DIR) {
		errno = EISDIR;
		return -1;
	}
	h = &fh[k];
	memset(h, 0, sizeof(*h));
	h->used = 1;
	h->flags = flags;
	h->lba = f.lba;
	h->i = f.i;
	h->first = f.cl;
	h->size = f.size;
	if ((flags & O_TRUNC) && (f.cl || f.size)) {
		freechain(f.cl);
		h->first = 0;
		h->size = 0;
		entry_update(h);
		fsinfo_sync();
	}
	return k;
}

int fat_close(int k)
{
	int ok = 1;

	secno = -1;

	if (fh[k].dirty)
		ok = entry_update(&fh[k]);
	fsinfo_sync();
	fh[k].used = 0;
	return ok ? 0 : -1;
}

long fat_size(int k)
{
	return fh[k].size;
}

long fat_lseek(int k, long pos)
{
	fh[k].pos = pos;
	return pos;
}

long fat_tell(int k)
{
	return fh[k].pos;
}

int fat_read(int k, char *buf, int n)
{
	struct fh *h = &fh[k];
	long csize = (long) spc * 512, cl;
	int got = 0, off, m;

	secno = -1;

	while (got < n && h->pos < h->size) {
		cl = clusterof(h, h->pos / csize, 0);
		if (cl == 0 || !getsec(cl2lba(cl) + (h->pos % csize) / 512))
			break;
		off = (int) (h->pos % 512);
		m = 512 - off;
		if (m > n - got)
			m = n - got;
		if ((long) m > h->size - h->pos)
			m = (int) (h->size - h->pos);
		memcpy(buf + got, sec + off, m);
		got += m;
		h->pos += m;
	}
	return got;
}

static int wr(struct fh *h, const char *buf, int n)
{
	long csize = (long) spc * 512, cl, lba;
	int put = 0, off, m;

	while (put < n) {
		cl = clusterof(h, h->pos / csize, 1);
		if (cl == 0) {
			errno = ENOSPC;
			break;
		}
		lba = cl2lba(cl) + (h->pos % csize) / 512;
		off = (int) (h->pos % 512);
		m = 512 - off;
		if (m > n - put)
			m = n - put;
		if (m < 512 && (h->pos - off < h->size)) {
			if (!getsec(lba))
				break;
		} else {
			secno = lba;			/* (new: no need to read) */
			memset(sec, 0, 512);
		}
		if (buf)
			memcpy(sec + off, buf + put, m);
		else
			memset(sec + off, 0, m);
		if (!putsec())
			break;
		put += m;
		h->pos += m;
		if (h->pos > h->size) {
			h->size = h->pos;
			h->dirty = 1;
		}
	}
	return put;
}

int fat_write(int k, const char *buf, int n)
{
	struct fh *h = &fh[k];
	long pos = h->pos;

	secno = -1;

	if (pos > h->size) {			/* (a gap: zeros) */
		h->pos = h->size;
		while (h->pos < pos)
			if (wr(h, (char *) 0, (int) (pos - h->pos > 512 ? 512
			    : pos - h->pos)) <= 0)
				return -1;
	}
	n = wr(h, buf, n);
	return n > 0 || errno != ENOSPC ? n : -1;
}

int fat_exists(const char *path)
{
	char n[11];
	long dircl;
	struct found f;

	secno = -1;
	return walk(path, &dircl, n) && dfind(dircl, n, &f);
}

int fat_unlink(const char *path)
{
	char n[11];
	long dircl;
	struct found f;
	int i;

	secno = -1;
	if (!walk(path, &dircl, n) || !dfind(dircl, n, &f)) {
		errno = ENOENT;
		return -1;
	}
	if (f.attr & ATTR_DIR) {
		errno = EISDIR;
		return -1;
	}
	freechain(f.cl);
	for (i = 0; i < f.nlfn; i++)
		if (getsec(f.lfnlba[i])) {
			sec[32 * f.lfni[i]] = 0xE5;
			putsec();
		}
	if (!getsec(f.lba))
		return -1;
	sec[32 * f.i] = 0xE5;
	if (!putsec())
		return -1;
	fsinfo_sync();
	return 0;
}

int fat_rename(const char *old, const char *new)
{
	char n[11], m[11];
	long d1, d2;
	struct found f, g;

	secno = -1;
	if (!walk(old, &d1, n) || !dfind(d1, n, &f)) {
		errno = ENOENT;
		return -1;
	}
	if (!walk(new, &d2, m) || d2 != d1) {
		errno = EXDEV;
		return -1;
	}
	if (dfind(d2, m, &g) && (g.lba != f.lba || g.i != f.i))
		fat_unlink(new);
	if (!getsec(f.lba))
		return -1;
	memcpy(sec + 32 * f.i, m, 11);
	return putsec() ? 0 : -1;
}

int fat_mkdir(const char *path)
{
	char n[11];
	long dircl, cl;
	struct found f;
	unsigned char *e;

	secno = -1;
	if (!walk(path, &dircl, n))
		return -1;
	if (dfind(dircl, n, &f)) {
		errno = EEXIST;
		return -1;
	}
	if ((cl = newcluster(1)) == 0) {
		errno = ENOSPC;
		return -1;
	}
	if ((e = dnew(dircl, n, &f)) == 0) {
		freechain(cl);
		return -1;
	}
	e[11] = ATTR_DIR;
	put16(e + 26, cl);
	if (fat32)
		put16(e + 20, cl >> 16);
	putsec();
	/* "." and ".." (0: the root) */
	if (!getsec(cl2lba(cl)))
		return -1;
	memset(sec, 0, 64);
	memcpy(sec, ".          ", 11);
	memcpy(sec + 32, "..         ", 11);
	sec[11] = sec[32 + 11] = ATTR_DIR;
	put16(sec + 26, cl);
	put16(sec + 32 + 26, dircl == rootcl ? 0L : dircl);
	if (fat32) {
		put16(sec + 20, cl >> 16);
		put16(sec + 32 + 20, (dircl == rootcl ? 0L : dircl) >> 16);
	}
	put16(sec + 24, 0x0021L);
	put16(sec + 32 + 24, 0x0021L);
	if (!putsec())
		return -1;
	fsinfo_sync();
	return 0;
}

int fat_rmdir(const char *path)
{
	char n[11];
	long dircl;
	struct found f;
	struct dpos d;
	unsigned char *e;
	int i;

	secno = -1;
	if (!walk(path, &dircl, n) || !dfind(dircl, n, &f) || !(f.attr & ATTR_DIR)) {
		errno = ENOENT;
		return -1;
	}
	dstart(&d, f.cl);
	while ((e = dnext(&d, 0)) != 0 && e[0] != 0)
		if (e[0] != 0xE5 && e[11] != ATTR_LFN && e[0] != '.') {
			errno = ENOTEMPTY;
			return -1;
		}
	if (f.cl == cwd)
		cwd = 0;
	freechain(f.cl);
	for (i = 0; i < f.nlfn; i++)
		if (getsec(f.lfnlba[i])) {
			sec[32 * f.lfni[i]] = 0xE5;
			putsec();
		}
	if (!getsec(f.lba))
		return -1;
	sec[32 * f.i] = 0xE5;
	if (!putsec())
		return -1;
	fsinfo_sync();
	return 0;
}

int fat_chdir(const char *path)
{
	char n[11];
	long dircl;
	struct found f;

	secno = -1;
	if (strcmp(path, "/") == 0) {
		cwd = 0;
		return 0;
	}
	if (!walk(path, &dircl, n) || !dfind(dircl, n, &f)
	    || !(f.attr & ATTR_DIR)) {
		errno = ENOENT;
		return -1;
	}
	cwd = f.cl == rootcl && fat32 ? 0L : f.cl;
	return 0;
}

/* the current directory: emit(name, size, isdir) for each entry */
void fat_list(void (*emit)(char *, long, int))
{
	struct dpos d;
	unsigned char *e;
	char name[13];
	long lba;
	int i, k, j, attr;
	long size;

	secno = -1;
	dstart(&d, cwd);
	while ((e = dnext(&d, 0)) != 0 && e[0] != 0) {
		if (e[0] == 0xE5 || e[11] == ATTR_LFN || (e[11] & ATTR_VOL)
		    || (e[0] == '.' && e[1] == ' '))
			continue;
		for (k = 0, j = 0; j < 8 && e[j] != ' '; j++)
			name[k++] = e[j];
		if (e[8] != ' ') {
			name[k++] = '.';
			for (j = 8; j < 11 && e[j] != ' '; j++)
				name[k++] = e[j];
		}
		name[k] = 0;
		attr = e[11];
		size = le32(e + 28);
		lba = d.lba;
		i = d.i;
		(*emit)(name, size, (attr & ATTR_DIR) != 0);
		if (!getsec(lba))		/* (emit may use the buffer) */
			return;
		d.lba = lba;
		d.i = i;
	}
}
