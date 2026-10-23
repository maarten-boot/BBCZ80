//
// Host files for bare BBC BASIC (src68k/host): the files of the folder the
// program was started in, instead of an SD card.
//
// Bare BASIC (bare/bare.c, start.s bare_host) asks with an ILLEGAL
// instruction: d6 = HOST_MAGIC, d7 = the operation, arguments in d1-d3,
// the result in d0 (>= 0, or a negative Minix errno).  r68k's main.cpp is
// compiled with its illegal_instruction_handler renamed r68k_illegal; this
// one handles these calls and gives it the rest (its firmware traps).
//
//	PROBE			-> HOST_MAGIC (there are host files)
//	OPEN	path flags	-> handle (flags: Minix O_*)
//	CLOSE	h
//	READ	h buf n		-> bytes read
//	WRITE	h buf n		-> bytes written
//	SEEK	h pos		-> pos
//	SIZE	h		-> size
//	UNLINK	path;  RENAME old new;  MKDIR path;  RMDIR path;  CHDIR path
//	EXISTS	path		-> 0 no, 1 a file, 2 a directory
//	DIRENT	i buf		-> size of the i-th entry of the current
//				   directory (its name and a NUL to buf, then
//				   a byte 1 if it is a directory), -1 after the
//				   last
//	EXIT	code		(the program ends: *BYE)
//
// Paths are relative to the current directory, "/..." to the root (the
// starting folder); they cannot go above the root.
//
// Deleting a file that one of BASIC's channels has open works as on POSIX
// systems: Windows refuses it, so the file is then only marked, counts as
// gone at once, and is removed when its last channel is closed (or the
// program ends, r68k_hostfs_end).  A name is looked for
// as it is, else without regard to case (BASIC tries .bbc and .BBC; on
// Windows case never matters).
//
#include <cerrno>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <algorithm>
#include <filesystem>
#include <string>
#include <system_error>
#include <vector>

#include "musashi/m68k.h"

namespace fs = std::filesystem;

extern "C" {
    int r68k_illegal(int opcode);
    void r68k_host_exit(int code);
}

static constexpr std::uint32_t HOST_MAGIC = 0x42424348;	// "BBCH"
enum { PROBE = 1, OPEN, CLOSE, READ, WRITE, SEEK, SIZE, UNLINK, RENAME,
       MKDIR, RMDIR, CHDIR, EXISTS, DIRENT, EXIT, ARG };

// Minix errno and open flags
enum { M_ENOENT = 2, M_EIO = 5, M_EBADF = 9, M_EACCES = 13, M_EEXIST = 17,
       M_ENOTDIR = 20, M_EISDIR = 21, M_EINVAL = 22, M_EMFILE = 24,
       M_ENOSPC = 28, M_ENOTEMPTY = 39 };
static constexpr int M_O_ACCMODE = 3, M_O_RDONLY = 0, M_O_CREAT = 0100,
                     M_O_TRUNC = 01000;

static fs::path root, cwd;		// cwd: relative to root
static std::string autorun;		// the program named on the command line
static constexpr int NFILE = 16;
static std::FILE *files[NFILE];
static long pos[NFILE];
static fs::path paths[NFILE];			// (for deleting open files)
static std::vector<fs::path> doomed;		// deleted while open
static std::vector<std::pair<std::string, bool>> listing;	// (DIRENT)

static std::string cstring(std::uint32_t a)
{
    std::string s;
    for (int i = 0; i < 1024; i++) {
        char c = (char) m68k_read_memory_8(a + i);
        if (!c)
            break;
        s += c;
    }
    return s;
}

static bool same_name(const std::string &a, const std::string &b)
{
    return a.size() == b.size() && std::equal(a.begin(), a.end(), b.begin(),
        [](char x, char y) { return std::tolower((unsigned char) x) == std::tolower((unsigned char) y); });
}

// a path of BASIC's -> the host path, or empty if it would leave the root
static fs::path host_path(const std::string &p)
{
    fs::path rel = p.size() && p[0] == '/' ? fs::path(p.substr(1)) : cwd / p;
    rel = rel.lexically_normal();
    if (rel.empty() || rel == ".")
        return root;
    if (rel.begin()->string() == "..")
        return fs::path();
    fs::path full = root / rel, dir = full.parent_path();
    std::error_code ec;
    if (std::find(doomed.begin(), doomed.end(), full) != doomed.end())
        return full;			// (deleted; not another case of it)
    if (!fs::exists(full, ec) && fs::is_directory(dir, ec)) {
        for (auto &e : fs::directory_iterator(dir, ec))
            if (same_name(e.path().filename().string(), full.filename().string()))
                return e.path();
    }
    return full;
}

static bool is_doomed(const fs::path &p)
{
    return std::find(doomed.begin(), doomed.end(), p) != doomed.end();
}

static bool present(const fs::path &p)
{
    std::error_code ec;
    return fs::exists(p, ec) && !is_doomed(p);
}

// close handle h; a file deleted while open goes with its last handle
static void close_handle(int h)
{
    std::fclose(files[h]);
    files[h] = nullptr;
    fs::path p = paths[h];
    if (!is_doomed(p))
        return;
    for (int k = 0; k < NFILE; k++)
        if (files[k] && paths[k] == p)
            return;
    std::error_code ec;
    fs::remove(p, ec);
    doomed.erase(std::remove(doomed.begin(), doomed.end(), p), doomed.end());
}

static int errno_of(std::error_code ec)
{
    switch (ec.value()) {
    case ENOENT: return -M_ENOENT;
    case EEXIST: return -M_EEXIST;
    case EACCES: return -M_EACCES;
    case ENOTDIR: return -M_ENOTDIR;
    case EISDIR: return -M_EISDIR;
    case ENOTEMPTY: return -M_ENOTEMPTY;
    case ENOSPC: return -M_ENOSPC;
    default: return -M_EIO;
    }
}

static long op_open(const std::string &p, int flags)
{
    fs::path f = host_path(p);
    std::error_code ec;
    int k;

    if (f.empty() || f == root)
        return -M_EINVAL;
    for (k = 0; k < NFILE && files[k]; k++)
        ;
    if (k == NFILE)
        return -M_EMFILE;
    if (fs::is_directory(f, ec))
        return -M_EISDIR;
    bool there = present(f);
    const char *mode;
    if ((flags & M_O_TRUNC) || ((flags & M_O_CREAT) && !there))
        mode = "w+b";
    else if (!there)
        return -M_ENOENT;
    else
        mode = (flags & M_O_ACCMODE) == M_O_RDONLY ? "rb" : "r+b";
    files[k] = std::fopen(f.string().c_str(), mode);
    if (!files[k])
        return errno == ENOENT ? -M_ENOENT : -M_EACCES;
    pos[k] = 0;
    paths[k] = f;
    doomed.erase(std::remove(doomed.begin(), doomed.end(), f), doomed.end());
    return k;
}

static bool valid(long h)
{
    return h >= 0 && h < NFILE && files[h];
}

static long op_rw(long h, std::uint32_t buf, long n, bool wr)
{
    if (!valid(h))
        return -M_EBADF;
    std::FILE *f = files[h];
    std::vector<unsigned char> b((size_t) n);
    std::fseek(f, 0, SEEK_END);
    long size = std::ftell(f);
    if (wr && pos[h] > size) {			// (a gap: zeros)
        std::vector<char> z((size_t) (pos[h] - size), 0);
        std::fwrite(z.data(), 1, z.size(), f);
    }
    std::fseek(f, pos[h], SEEK_SET);
    size_t done;
    if (wr) {
        for (long i = 0; i < n; i++)
            b[i] = m68k_read_memory_8(buf + i);
        done = std::fwrite(b.data(), 1, (size_t) n, f);
        std::fflush(f);
        if (done == 0 && n > 0)
            return -M_ENOSPC;
    } else {
        done = std::fread(b.data(), 1, (size_t) n, f);
        for (size_t i = 0; i < done; i++)
            m68k_write_memory_8(buf + i, b[i]);
    }
    pos[h] += (long) done;
    return (long) done;
}

static long op_dirent(long i, std::uint32_t buf)
{
    std::error_code ec;

    if (i == 0) {
        listing.clear();
        for (auto &e : fs::directory_iterator(root / cwd, ec))
            if (!is_doomed(e.path()))
                listing.push_back({e.path().filename().string(), e.is_directory(ec)});
        std::sort(listing.begin(), listing.end(),
                  [](auto &a, auto &b) { return a.first < b.first; });
    }
    if (i < 0 || i >= (long) listing.size())
        return -1;
    const std::string &n = listing[i].first;
    size_t k = std::min(n.size(), (size_t) 63);
    for (size_t j = 0; j < k; j++)
        m68k_write_memory_8(buf + j, n[j]);
    m68k_write_memory_8(buf + k, 0);
    m68k_write_memory_8(buf + k + 1, listing[i].second ? 1 : 0);
    if (listing[i].second)
        return 0;
    auto sz = fs::file_size(root / cwd / n, ec);
    return ec ? 0 : (long) sz;
}

static long host_call(int op, std::uint32_t a1, std::uint32_t a2, std::uint32_t a3)
{
    std::error_code ec;
    fs::path p;

    switch (op) {
    case PROBE:
        return HOST_MAGIC;
    case OPEN:
        return op_open(cstring(a1), (int) a2);
    case CLOSE:
        if (!valid(a1))
            return -M_EBADF;
        close_handle((int) a1);
        return 0;
    case READ:
        return op_rw(a1, a2, a3, false);
    case WRITE:
        return op_rw(a1, a2, a3, true);
    case SEEK:
        if (!valid(a1))
            return -M_EBADF;
        pos[a1] = (long) a2;
        return pos[a1];
    case SIZE:
        if (!valid(a1))
            return -M_EBADF;
        std::fseek(files[a1], 0, SEEK_END);
        return std::ftell(files[a1]);
    case UNLINK:
        p = host_path(cstring(a1));
        if (p.empty() || !present(p))
            return -M_ENOENT;
        if (fs::is_directory(p, ec))
            return -M_EISDIR;
        if (fs::remove(p, ec))
            return 0;
        for (int k = 0; k < NFILE; k++)
            if (files[k] && paths[k] == p) {	// (open: Windows)
                doomed.push_back(p);
                return 0;
            }
        return errno_of(ec);
    case RENAME: {
        fs::path q = host_path(cstring(a2));
        p = host_path(cstring(a1));
        if (p.empty() || q.empty() || !present(p))
            return -M_ENOENT;
        fs::rename(p, q, ec);
        return ec ? errno_of(ec) : 0;
    }
    case MKDIR:
        p = host_path(cstring(a1));
        if (p.empty())
            return -M_EINVAL;
        if (fs::exists(p, ec))
            return -M_EEXIST;
        return fs::create_directory(p, ec) ? 0 : errno_of(ec);
    case RMDIR:
        p = host_path(cstring(a1));
        if (p.empty() || !fs::is_directory(p, ec))
            return -M_ENOENT;
        if (!fs::is_empty(p, ec))
            return -M_ENOTEMPTY;
        return fs::remove(p, ec) ? 0 : errno_of(ec);
    case CHDIR:
        p = host_path(cstring(a1));
        if (p.empty() || !fs::is_directory(p, ec))
            return -M_ENOENT;
        cwd = p.lexically_relative(root);
        if (cwd == ".")
            cwd.clear();
        return 0;
    case EXISTS:
        p = host_path(cstring(a1));
        if (p.empty() || !present(p))
            return 0;
        return fs::is_directory(p, ec) ? 2 : 1;
    case DIRENT:
        return op_dirent((long) a1, a2);
    case EXIT:
        r68k_host_exit((int) a1);
        return 0;
    case ARG:				// the program to CHAIN at the start
        if (autorun.empty() || autorun.size() + 1 > a2)
            return 0;
        for (std::size_t i = 0; i <= autorun.size(); i++)
            m68k_write_memory_8(a1 + (std::uint32_t) i, (unsigned char) autorun.c_str()[i]);
        return (long) autorun.size();
    }
    return -M_EINVAL;
}

// the end of the program: close everything (files deleted while open go)
extern "C" void r68k_hostfs_end()
{
    for (int k = 0; k < NFILE; k++)
        if (files[k])
            close_handle(k);
}

extern "C" void r68k_hostfs_arg(const char *name)
{
    autorun = name;
}

extern "C" void r68k_hostfs_init()
{
    std::error_code ec;
    root = fs::current_path(ec);
    cwd.clear();
}

extern "C" int illegal_instruction_handler(int opcode)
{
    if (m68k_get_reg(nullptr, M68K_REG_D6) == HOST_MAGIC) {
        long r = host_call((int) m68k_get_reg(nullptr, M68K_REG_D7),
                           m68k_get_reg(nullptr, M68K_REG_D1),
                           m68k_get_reg(nullptr, M68K_REG_D2),
                           m68k_get_reg(nullptr, M68K_REG_D3));
        m68k_set_reg(M68K_REG_D0, (unsigned int) r);
        return 1;
    }
    return r68k_illegal(opcode);
}
