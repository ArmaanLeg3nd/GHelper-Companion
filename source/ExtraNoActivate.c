#define WIN32_LEAN_AND_MEAN
#include <windows.h>
static DWORD started = 0;

/* Installed only on GHelper's UI thread, only around creation of Extra.
   No memory patching, remote thread creation, keyboard or mouse hooks. */
static BOOL IsExtra(HWND hwnd) {
    WCHAR title[128];
    if (!hwnd) return FALSE;
    if (GetPropW(hwnd, L"GHServiceHelper.Extra")) return TRUE;
    GetWindowTextW(hwnd, title, 128);
    return lstrcmpW(title, L"Extra Settings") == 0;
}

__declspec(dllexport) LRESULT CALLBACK ExtraCbtProc(int code, WPARAM w, LPARAM l) {
    HWND hwnd = (HWND)w;
    if (code < 0) return CallNextHookEx(NULL, code, w, l);
    if (code == HCBT_CREATEWND) {
        CBT_CREATEWNDW *c = (CBT_CREATEWNDW*)l;
        if (c && c->lpcs && c->lpcs->lpszName &&
            (ULONG_PTR)c->lpcs->lpszName > 0xffff &&
            lstrcmpW(c->lpcs->lpszName, L"Extra Settings") == 0) {
            started = GetTickCount();
            SetPropW(hwnd, L"GHServiceHelper.Extra", (HANDLE)1);
            c->lpcs->dwExStyle |= WS_EX_NOACTIVATE;
            c->lpcs->x = -32000;
            c->lpcs->y = -32000;
        }
    }
    if (started && (DWORD)(GetTickCount() - started) > 90000)
        return CallNextHookEx(NULL, code, w, l);
    if (code == HCBT_ACTIVATE && IsExtra(hwnd)) return 1;
    if (code == HCBT_SETFOCUS && IsExtra(GetAncestor(hwnd, GA_ROOT))) return 1;
    if (code == HCBT_MOVESIZE && IsExtra(hwnd)) {
        RECT *r = (RECT*)l;
        int width = r->right - r->left, height = r->bottom - r->top;
        r->left = -32000; r->top = -32000;
        r->right = r->left + width; r->bottom = r->top + height;
    }
    return CallNextHookEx(NULL, code, w, l);
}

BOOL WINAPI DllMain(HINSTANCE module, DWORD reason, LPVOID reserved) {
    return TRUE;
}
