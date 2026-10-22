/* termios.h for the Windows build of r68k (src68k/host): enough for
 * r68k's main.cpp to compile.  Its terminal code (init_term, check_char,
 * read_char) is not used there: hostmain.cpp does the console.
 */
#ifndef R68K_COMPAT_TERMIOS_H
#define R68K_COMPAT_TERMIOS_H
typedef unsigned int tcflag_t;
struct termios {
	tcflag_t c_iflag, c_oflag, c_cflag, c_lflag;
	unsigned char c_cc[32];
};
#define ICANON	0x0002
#define ECHO	0x0008
#define ICRNL	0x0100
#define INLCR	0x0040
#define TCSANOW	0
static inline int tcgetattr(int fd, struct termios *t) { (void) fd; (void) t; return -1; }
static inline int tcsetattr(int fd, int a, const struct termios *t) { (void) fd; (void) a; (void) t; return -1; }
#define F_GETFL	3
#define F_SETFL	4
#define O_NONBLOCK 04000
static inline int fcntl(int fd, int cmd, ...) { (void) fd; (void) cmd; return 0; }
#ifndef SIGUSR1
#define SIGUSR1	10
#endif
#endif
