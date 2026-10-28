// keytest.exe EXE: a test of bbc68k.exe's console keys (tools/hostcheck.py,
// under Wine).  It starts EXE on its own console and puts key events into
// that console as a Windows keyboard does (WriteConsoleInput: the cursor
// keys with no character): "PRINT 12" Left "3" Return (132),
// "PRINT 99" Home "X" Return (Mistake), then Ctrl-].
// (In a terminal Wine's console loses the ESC of the terminal's cursor key
// sequences, so typing them does not test this.)
#include <windows.h>
#include <stdio.h>
static HANDLE in;
static void key(WORD vk, WCHAR ch) {
    INPUT_RECORD r[2] = {};
    for (int i = 0; i < 2; i++) {
        r[i].EventType = KEY_EVENT;
        r[i].Event.KeyEvent.bKeyDown = i == 0;
        r[i].Event.KeyEvent.wRepeatCount = 1;
        r[i].Event.KeyEvent.wVirtualKeyCode = vk;
        r[i].Event.KeyEvent.uChar.UnicodeChar = ch;
    }
    DWORD n;
    WriteConsoleInputW(in, r, 2, &n);
    Sleep(30);
}
static void text(const char *s) { for (; *s; s++) key(0, (WCHAR) *s); }
int main(int argc, char **argv) {
    in = CreateFileA("CONIN$", GENERIC_READ | GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_EXISTING, 0, NULL);
    STARTUPINFOA si = { sizeof si };
    PROCESS_INFORMATION pi;
    if (argc < 2) return 2;
    char *cmd = argv[1];
    if (!CreateProcessA(NULL, cmd, NULL, NULL, TRUE, 0, NULL, NULL, &si, &pi)) { printf("no child\n"); return 1; }
    Sleep(4000);
    text("PRINT 12"); key(VK_LEFT, 0); text("3"); key(VK_RETURN, '\r'); Sleep(500);
    text("PRINT 99"); key(VK_HOME, 0); text("X"); key(VK_RETURN, '\r'); Sleep(500);
    key(0, 0x1D);
    WaitForSingleObject(pi.hProcess, 10000);
    return 0;
}
