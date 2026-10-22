//
// r68k's main() for BBC BASIC as a program on the host (src68k/host): one
// executable (Windows, or Linux) with the rosco_m68k firmware and bare BBC
// BASIC built in (images.h, made by tools/mkhost.py).  BASIC's files are
// the host's (hostfs.cpp), its console is the program's.
//
// The machine is set up as in "R68K_RAM=4M r68k -d ROSCODE1.BIN" (r68k's
// main.cpp is compiled with its main renamed, for its trap handlers).  The
// DUART (r68k-web.patch, R68K_HOSTED) takes keys from r68k_key() and hands
// its output to r68k_host_output().
// * Input: a thread reads the console (raw keys; on Windows arrow keys etc.
//   become vt100 sequences, as BASIC's editor wants them) or, if standard
//   input is a pipe or a file, its bytes.  Ctrl-] at the console quits.
//   Keys go to the machine once it has first been idle (BASIC waits for
//   input): typed earlier, the firmware's start would lose them.
// * Output: vt100 (the Windows console is put in that mode).
// * The CPU runs in steps of 10000 cycles with a DUART poll after each, as
//   in main.cpp; when the machine is idle (bare BASIC waits with STOP,
//   4E72 just before the PC) the program sleeps until the timer interrupt
//   or a key.
// * With piped input the program ends when the input is used up, the
//   machine is idle and nothing has been written for IDLE_EXIT_MS (a
//   script has run; the timer wakes the CPU 60 times a second, so idle
//   alone is never long).  *BYE ends it (hostfs).
//
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <filesystem>
#include <fstream>
#include <mutex>
#include <string>
#include <thread>

#ifdef _WIN32
#include <windows.h>
#include <fcntl.h>
#include <io.h>
#else
#include <termios.h>
#include <unistd.h>
#endif

#include "musashi/m68k.h"
#include "AddressDecoder.h"
#include "images.h"		// rom_image[], basic_image[] (mkhost.py)

using rosco::m68k::emu::AddressDecoder;
using rosco::m68k::emu::Duart;

#define DUART_IRQ	4
static constexpr int STEP = 10000;		// cycles between DUART polls
static constexpr int IDLE_EXIT_MS = 300;	// (piped input used up)
static constexpr int QUIT_KEY = 0x1D;		// Ctrl-]

extern "C" {
    extern AddressDecoder* __mem;
    extern Duart* __duart;
    extern bool r68k_duart_idle;
    extern double r68k_duart_wait;
    void r68k_flush();
    void r68k_key(int c);
    int r68k_pending();
    void r68k_hostfs_init();
    void r68k_hostfs_end();
}

/*==================================================== the console ====*/

static std::mutex mu;
static std::condition_variable cv;
static std::deque<unsigned char> keys;
static std::atomic<bool> input_end{false};
static bool console;			// standard input is a terminal

static void put_keys(const char *s, size_t n)
{
    {
        std::lock_guard<std::mutex> l(mu);
        for (size_t i = 0; i < n; i++)
            keys.push_back((unsigned char) s[i]);
    }
    cv.notify_one();
}

static void restore_console();

static void quit(int code)
{
    r68k_hostfs_end();
    r68k_flush();
    std::fflush(stdout);
    restore_console();
    std::_Exit(code);
}

static std::chrono::steady_clock::time_point last_output;

extern "C" void r68k_host_output(const char *data, size_t n)
{
    std::fwrite(data, 1, n, stdout);
    last_output = std::chrono::steady_clock::now();
}

extern "C" void r68k_host_exit(int code)
{
    quit(code);
}

#ifdef _WIN32
static HANDLE hin, hout;
static DWORD inmode, outmode;

static void restore_console()
{
    if (console) {
        SetConsoleMode(hin, inmode);
        SetConsoleMode(hout, outmode);
    }
}

// a key (KEY_EVENT) -> the bytes BASIC gets; vt100 for the cursor keys
static void console_key(const KEY_EVENT_RECORD &k)
{
    static const struct { WORD vk; const char *seq; } map[] = {
        { VK_UP, "\x1b[A" }, { VK_DOWN, "\x1b[B" }, { VK_RIGHT, "\x1b[C" },
        { VK_LEFT, "\x1b[D" }, { VK_HOME, "\x1b[H" }, { VK_END, "\x1b[F" },
        { VK_DELETE, "\x1b[3~" }, { VK_INSERT, "\x1b[2~" },
    };
    if (!k.bKeyDown)
        return;
    for (WORD r = 0; r < (k.wRepeatCount ? k.wRepeatCount : 1); r++) {
        WCHAR c = k.uChar.UnicodeChar;
        if (c == QUIT_KEY)
            quit(0);
        if (c) {
            char b = c < 256 ? (char) c : '?';
            put_keys(&b, 1);
            continue;
        }
        for (auto &m : map)
            if (m.vk == k.wVirtualKeyCode)
                put_keys(m.seq, std::strlen(m.seq));
    }
}

static void reader()
{
    if (console) {
        INPUT_RECORD rec[32];
        DWORD n;
        while (ReadConsoleInputW(hin, rec, 32, &n))
            for (DWORD i = 0; i < n; i++)
                if (rec[i].EventType == KEY_EVENT)
                    console_key(rec[i].Event.KeyEvent);
    } else {
        char b[256];
        DWORD n;
        while (ReadFile(hin, b, sizeof b, &n, nullptr) && n)
            put_keys(b, n);
    }
    input_end = true;
    cv.notify_one();
}

static void setup_console()
{
    hin = GetStdHandle(STD_INPUT_HANDLE);
    hout = GetStdHandle(STD_OUTPUT_HANDLE);
    _setmode(_fileno(stdout), _O_BINARY);
    console = GetConsoleMode(hin, &inmode) != 0;
    if (console) {
        // raw keys; the console's vt100 input where it has it (Windows 10),
        // else console_key's mapping of the cursor keys
        DWORD m = inmode & ~(ENABLE_LINE_INPUT | ENABLE_ECHO_INPUT
                             | ENABLE_PROCESSED_INPUT);
        if (!SetConsoleMode(hin, m | ENABLE_VIRTUAL_TERMINAL_INPUT))
            SetConsoleMode(hin, m);
    }
    if (GetConsoleMode(hout, &outmode))
        SetConsoleMode(hout, outmode | ENABLE_PROCESSED_OUTPUT
                       | ENABLE_VIRTUAL_TERMINAL_PROCESSING);
}
#else
static struct termios saved;

static void restore_console()
{
    if (console)
        tcsetattr(0, TCSANOW, &saved);
}

static void reader()
{
    char b[256];
    ssize_t n;
    while ((n = read(0, b, sizeof b)) > 0) {
        if (console)
            for (ssize_t i = 0; i < n; i++)
                if (b[i] == QUIT_KEY)
                    quit(0);
        put_keys(b, (size_t) n);
    }
    input_end = true;
    cv.notify_one();
}

static void setup_console()
{
    console = isatty(0) && tcgetattr(0, &saved) == 0;
    if (console) {
        struct termios t = saved;
        t.c_lflag &= ~(ICANON | ECHO | ISIG | IEXTEN);
        t.c_iflag &= ~(ICRNL | INLCR | IXON);
        t.c_cc[VMIN] = 1;
        t.c_cc[VTIME] = 0;
        tcsetattr(0, TCSANOW, &t);
    }
}
#endif

/*==================================================== the machine ====*/

static unsigned int ram_size()
{
    const char *e = std::getenv("R68K_RAM");
    unsigned long n = 4ul << 20;
    if (e && *e) {
        char *end;
        n = std::strtoul(e, &end, 0);
        if (*end == 'M' || *end == 'm')
            n <<= 20;
        else if (*end == 'K' || *end == 'k')
            n <<= 10;
    }
    if (n < 0x80000 || n > 0xE00000 || (n & 0x7FFFF))
        n = 4ul << 20;
    return (unsigned int) n;
}

int main()
{
    // the ROM: AddressDecoder reads it from a file
    std::error_code ec;
    auto rom = std::filesystem::temp_directory_path(ec) /
               ("bbc68k-rom-" + std::to_string((unsigned long)
                   std::chrono::steady_clock::now().time_since_epoch().count()) + ".bin");
    {
        std::ofstream f(rom, std::ios::binary);
        f.write((const char *) rom_image, sizeof rom_image);
    }
    __mem = new AddressDecoder(0x40000, ram_size(), rom.string().c_str());
    std::filesystem::remove(rom, ec);
    for (size_t i = 0; i < sizeof basic_image; i++)
        __mem->write8(0x40000 + (std::uint32_t) i, basic_image[i]);
    __duart = new Duart([](bool asserted) {
        m68k_set_irq(asserted ? DUART_IRQ : 0);
    });
    __mem->setDuart(__duart);
    r68k_hostfs_init();

    setup_console();
    std::thread(reader).detach();

    m68k_set_cpu_type(M68K_CPU_TYPE_68010);
    m68k_init();
    m68k_pulse_reset();

    auto last_flush = std::chrono::steady_clock::now();
    last_output = last_flush;
    bool started = false;		// (idle once: BASIC is there)
    for (;;) {
        if (started) {
            std::lock_guard<std::mutex> l(mu);
            while (!keys.empty()) {
                r68k_key(keys.front());
                keys.pop_front();
            }
        }
        m68k_execute(STEP);
        __duart->poll();
        auto now = std::chrono::steady_clock::now();
        unsigned int pc = m68k_get_reg(nullptr, M68K_REG_PC);
        bool idle = r68k_duart_idle && (m68k_read_memory_16(pc - 4) == 0x4E72
                                        || m68k_read_memory_16(pc) == 0x60FE);
        if (idle || now - last_flush > std::chrono::milliseconds(15)) {
            r68k_flush();
            std::fflush(stdout);
            last_flush = now;
        }
        if (!idle)
            continue;
        started = true;
        if (!console && input_end && r68k_pending() == 0
            && now - last_output > std::chrono::milliseconds(IDLE_EXIT_MS)) {
            std::unique_lock<std::mutex> l(mu);
            if (keys.empty())
                quit(0);
        }
        double ms = r68k_duart_wait < 1 ? 1 : r68k_duart_wait > 20 ? 20 : r68k_duart_wait;
        std::unique_lock<std::mutex> l(mu);
        cv.wait_for(l, std::chrono::microseconds((long) (ms * 1000)),
                    [] { return !keys.empty(); });
    }
}
