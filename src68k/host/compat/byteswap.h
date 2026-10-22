/* byteswap.h for the Windows build of r68k (src68k/host): the glibc
 * names on the compiler's built-ins */
#ifndef R68K_COMPAT_BYTESWAP_H
#define R68K_COMPAT_BYTESWAP_H
#define bswap_16(x) __builtin_bswap16(x)
#define bswap_32(x) __builtin_bswap32(x)
#define bswap_64(x) __builtin_bswap64(x)
#endif
