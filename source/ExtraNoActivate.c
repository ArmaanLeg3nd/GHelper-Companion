#define WIN32_LEAN_AND_MEAN
#include <windows.h>
/* Thread-scoped CBT hook. Install with SetWindowsHookExW.
   DWM cloaking survives WinForms positioning and style changes. */
typedef HRESULT (WINAPI *DwmSetAttribute)(HWND, DWORD, LPCVOID, DWORD);
static DwmSetAttribute setAttribute = NULL;
static HMODULE dwm = NULL;
static HWND extra = NULL, owner = NULL;
static DWORD started = 0;
static BOOL cloaking = FALSE;
static BOOL Cloak(HWND hwnd, BOOL enabled) {
    if (!dwm) {
        dwm = LoadLibraryExW(L"dwmapi.dll", NULL, 0x00000800);
        if (dwm) setAttribute = (DwmSetAttribute)GetProcAddress(dwm, "DwmSetWindowAttribute");
    }
    return setAttribute && setAttribute(hwnd, 13, &enabled, sizeof(enabled)) >= 0;
}
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
        if (c && c->lpcs && (ULONG_PTR)c->lpcs->lpszName > 0xffff &&
            lstrcmpW(c->lpcs->lpszName, L"Extra Settings") == 0) {
            started = GetTickCount(); extra = hwnd; owner = c->lpcs->hwndParent;
            SetPropW(hwnd, L"GHServiceHelper.Extra", (HANDLE)1);
            if (Cloak(hwnd, TRUE)) SetPropW(hwnd, L"GHServiceHelper.CloakedAtCreate", (HANDLE)1);
            c->lpcs->dwExStyle |= WS_EX_NOACTIVATE;
        }
    }
    if (started && (DWORD)(GetTickCount() - started) > 90000) {
        if (extra && IsWindow(extra)) Cloak(extra, FALSE);
        extra = owner = NULL;
        return CallNextHookEx(NULL, code, w, l);
    }
    if (code == HCBT_ACTIVATE && (IsExtra(hwnd) || (owner && hwnd == owner))) return 1;
    if (code == HCBT_SETFOCUS) {
        HWND root = GetAncestor(hwnd, GA_ROOT);
        if (IsExtra(root) || (owner && root == owner)) return 1;
    }
    return CallNextHookEx(NULL, code, w, l);
}
/* HCBT_CREATEWND precedes a valid DWM window. Cloak after WM_NCCREATE or
   WM_CREATE returns, while WS_VISIBLE is still false, before first display. */
__declspec(dllexport) LRESULT CALLBACK ExtraCallWndRetProc(int code, WPARAM w, LPARAM l) {
    if (code >= 0 && l) {
        CWPRETSTRUCT *m = (CWPRETSTRUCT*)l;
        if (!cloaking && (m->message == WM_NCCREATE || m->message == WM_CREATE) &&
            started && (DWORD)(GetTickCount() - started) <= 90000 && IsExtra(m->hwnd) &&
            !IsWindowVisible(m->hwnd) && !GetPropW(m->hwnd, L"GHServiceHelper.CloakedBeforeShow")) {
            cloaking = TRUE;
            if (Cloak(m->hwnd, TRUE))
                SetPropW(m->hwnd, L"GHServiceHelper.CloakedBeforeShow", (HANDLE)(ULONG_PTR)(m->message + 1));
            cloaking = FALSE;
        }
    }
    return CallNextHookEx(NULL, code, w, l);
}
BOOL WINAPI DllMain(HINSTANCE module, DWORD reason, LPVOID reserved) { return TRUE; }
