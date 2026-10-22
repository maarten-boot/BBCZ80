//
// r68k's main() for a web page (BBCZ80 src68k/web): the machine of
// "R68K_RAM=2M r68k -d ROSCODE1.BIN" (r68k's main.cpp, which is compiled
// with its main renamed, for its trap and trace handlers), run by the
// browser in frames (emscripten_set_main_loop) instead of an endless loop.
//
// A frame runs the CPU in steps of 10000 cycles, each followed by a DUART
// poll (as main.cpp does), for up to SLICE_MS, and the next frame follows
// at once (EM_TIMING_SETIMMEDIATE: the page stays responsive between
// frames).  A frame ends early when the machine is idle: Minix's idle task
// is a branch to itself (60FE), bare BBC BASIC waits with STOP (4E72, just
// before the PC), and the DUART has nothing pending; the next frame then
// comes with the timer interrupt (EM_TIMING_SETTIMEOUT).
// r68k_speed(mhz) holds the speed down to mhz (0: as fast as possible),
// with frames every LIMIT_MS.  Each frame also flushes the SD card's
// stream (main.cpp's ifs), so that the page sees what Minix wrote to the
// card (pre.js r68kSdRead) by the time it sees the output that follows.
//

#include <emscripten.h>
#include <fstream>
#include "musashi/m68k.h"
#include "AddressDecoder.h"

using rosco::m68k::emu::AddressDecoder;
using rosco::m68k::emu::Duart;

#define DUART_IRQ	4

static constexpr unsigned int RAM_SIZE = 2 << 20;
static constexpr double SLICE_MS = 12;
static constexpr int STEP = 10000;		// cycles between DUART polls
static constexpr int LIMIT_MS = 10;

extern "C" {
    extern AddressDecoder* __mem;
    extern Duart* __duart;
    extern bool r68k_duart_idle;
    extern double r68k_duart_wait;
    void r68k_flush();
    extern std::fstream ifs;		// the SD card (main.cpp)
}

static double mhz;		// 0: as fast as possible
static double credit;		// steps the speed limit allows
static double last;		// time of the last frame

extern "C" EMSCRIPTEN_KEEPALIVE void r68k_speed(double m) {
    mhz = m;
    credit = 0;
}

static void frame() {
    double start = emscripten_get_now();
    double ms = start - last;
    int wait = mhz > 0 ? LIMIT_MS : 0;		// ms to the next frame

    last = start;
    if (mhz > 0) {
        credit += (ms > 100 ? 100 : ms) * mhz * 1000 / STEP;
        if (credit > 10 * mhz) credit = 10 * mhz;	// (at most 100 ms behind)
    }
    for (int n = 0; ; n++) {
        if (mhz > 0) {
            if (credit < 1) break;
            credit -= 1;
        }
        m68k_execute(STEP);
        __duart->poll();
        unsigned int pc = m68k_get_reg(NULL, M68K_REG_PC);
        if (r68k_duart_idle && (m68k_read_memory_16(pc) == 0x60FE
                || m68k_read_memory_16(pc - 4) == 0x4E72)) {
            if (mhz > 0) credit = 0;		// (idle time is not owed)
            wait = r68k_duart_wait < 1 ? 1 : (int)r68k_duart_wait;
            break;
        }
        if ((n & 7) == 7 && emscripten_get_now() - start > SLICE_MS) break;
    }
    ifs.flush();
    r68k_flush();
    if (wait)
        emscripten_set_main_loop_timing(EM_TIMING_SETTIMEOUT, wait);
    else
        emscripten_set_main_loop_timing(EM_TIMING_SETIMMEDIATE, 1);
}

int main() {
    __mem = new AddressDecoder(0x40000, RAM_SIZE, "/firmware/rosco_m68k.rom");
    __mem->LoadMemoryFile(0x40000, "/ROSCODE1.BIN");
    __duart = new Duart([](bool asserted) {
        m68k_set_irq(asserted ? DUART_IRQ : 0);
    });
    __mem->setDuart(__duart);

    m68k_set_cpu_type(M68K_CPU_TYPE_68010);
    m68k_init();
    m68k_pulse_reset();

    last = emscripten_get_now();
    emscripten_set_main_loop(frame, 0, false);
    return 0;
}
