/* signal.h for MinGW: Windows' own, plus the POSIX signal numbers r68k
 * uses only as values (exit(128 + SIGBUS) after an unhandled bus or
 * address error; signal(SIGHUP, ...) in its own terminal setup, which
 * the PC program does not use).  The Linux numbers.
 */
#include_next <signal.h>
#ifndef SIGHUP
#define SIGHUP	1
#endif
#ifndef SIGBUS
#define SIGBUS	7
#endif
#ifndef SIGUSR1
#define SIGUSR1	10
#endif
