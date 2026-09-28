// SleepGuard: 指定時間だけ Windows のスリープ（と画面オフ）を止める常駐ツール
//
// 仕組みは SetThreadExecutionState。電源プランには触れないので、プロセスが
// 終われば（落ちても）元の挙動に戻る。
//
// コマンドライン（指定するとダイアログを出さずに開始する。検証用）:
//   SleepGuard.exe -s <秒>        秒で指定
//   SleepGuard.exe -m <分>        分で指定
//   SleepGuard.exe ... -nodisplay  画面は消えてよい（スリープだけ止める）
#include <windows.h>
#include <shellapi.h>
#include <commctrl.h>
#include <wchar.h>
#include <stdlib.h>
#include "resource.h"

#define APP_TITLE     L"スリープ防止"
#define MAX_SECONDS   (540 * 60)          // 最長 9 時間
#define WM_TRAY       (WM_APP + 1)
#define TIMER_TICK    1
#define TICK_MS       1000                // 終了判定は 1 秒刻み
#define REASSERT_SEC  15                  // 実行状態の再アサート間隔

static HINSTANCE g_inst;
static HICON     g_iconLarge, g_iconSmall;
static HWND      g_wnd;
static NOTIFYICONDATAW g_nid;
static UINT      g_msgTaskbarCreated;

static ULONGLONG g_endTick;               // 終了予定（GetTickCount64 基準）
static SYSTEMTIME g_endLocal;             // 表示用の終了予定時刻
static LONGLONG  g_totalSec;
static BOOL      g_keepDisplay = TRUE;
static ULONGLONG g_lastAssert;

// ---- 実行状態 ----

static void apply_state(void) {
    EXECUTION_STATE f = ES_CONTINUOUS | ES_SYSTEM_REQUIRED;
    if (g_keepDisplay) f |= ES_DISPLAY_REQUIRED;
    SetThreadExecutionState(f);
    g_lastAssert = GetTickCount64();
}

static void release_state(void) {
    SetThreadExecutionState(ES_CONTINUOUS);
}

// ---- 表示用の文字列 ----

static void format_duration(LONGLONG sec, wchar_t *buf, size_t n) {
    if (sec < 60)             swprintf(buf, n, L"%lld 秒", sec);
    else if (sec % 3600 == 0) swprintf(buf, n, L"%lld 時間", sec / 3600);
    else if (sec % 60 == 0)   swprintf(buf, n, L"%lld 分", sec / 60);
    else                      swprintf(buf, n, L"%lld 分 %lld 秒", sec / 60, sec % 60);
}

static LONGLONG remaining_sec(void) {
    ULONGLONG now = GetTickCount64();
    return now >= g_endTick ? 0 : (LONGLONG)((g_endTick - now + 999) / 1000);
}

static void update_tip(void) {
    LONGLONG r = remaining_sec();
    if (r >= 60) swprintf(g_nid.szTip, ARRAYSIZE(g_nid.szTip), L"スリープ防止中: あと %lld 分（%02d:%02d まで）",
                          (r + 59) / 60, g_endLocal.wHour, g_endLocal.wMinute);
    else         swprintf(g_nid.szTip, ARRAYSIZE(g_nid.szTip), L"スリープ防止中: あと %lld 秒", r);
    g_nid.uFlags = NIF_TIP | NIF_SHOWTIP;
    Shell_NotifyIconW(NIM_MODIFY, &g_nid);
}

// ---- タスクトレイ ----

static void tray_add(void) {
    ZeroMemory(&g_nid, sizeof g_nid);
    g_nid.cbSize = sizeof g_nid;
    g_nid.hWnd = g_wnd;
    g_nid.uID = 1;
    g_nid.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP | NIF_SHOWTIP;
    g_nid.uCallbackMessage = WM_TRAY;
    g_nid.hIcon = g_iconSmall;
    wcscpy(g_nid.szTip, APP_TITLE);
    Shell_NotifyIconW(NIM_ADD, &g_nid);
    g_nid.uVersion = NOTIFYICON_VERSION_4;
    Shell_NotifyIconW(NIM_SETVERSION, &g_nid);
    update_tip();
}

static void tray_balloon(void) {
    wchar_t dur[64];
    format_duration(g_totalSec, dur, ARRAYSIZE(dur));
    g_nid.uFlags = NIF_INFO;
    g_nid.dwInfoFlags = NIIF_INFO;
    wcscpy(g_nid.szInfoTitle, L"スリープ防止を開始しました");
    swprintf(g_nid.szInfo, ARRAYSIZE(g_nid.szInfo),
             L"%ls（%02d:%02d:%02d まで）%ls します。\nタスクトレイのアイコンから途中解除もできます。",
             dur, g_endLocal.wHour, g_endLocal.wMinute, g_endLocal.wSecond,
             g_keepDisplay ? L"スリープ＋画面オフを防止" : L"スリープのみ防止（画面は消えます）");
    Shell_NotifyIconW(NIM_MODIFY, &g_nid);
}

static void tray_menu(void) {
    HMENU m = CreatePopupMenu();
    wchar_t s[64];
    swprintf(s, ARRAYSIZE(s), L"終了予定: %02d:%02d:%02d", g_endLocal.wHour, g_endLocal.wMinute, g_endLocal.wSecond);
    AppendMenuW(m, MF_STRING | MF_GRAYED, IDM_STATUS, s);
    AppendMenuW(m, MF_SEPARATOR, 0, NULL);
    AppendMenuW(m, MF_STRING | (g_keepDisplay ? MF_CHECKED : 0), IDM_DISPLAY, L"ディスプレイも消さない");
    AppendMenuW(m, MF_STRING, IDM_STOP, L"今すぐ解除して終了");
    POINT pt; GetCursorPos(&pt);
    SetForegroundWindow(g_wnd);   // これが無いとメニュー外クリックで閉じない
    TrackPopupMenu(m, TPM_RIGHTBUTTON, pt.x, pt.y, 0, g_wnd, NULL);
    PostMessageW(g_wnd, WM_NULL, 0, 0);
    DestroyMenu(m);
}

static LRESULT CALLBACK wnd_proc(HWND w, UINT msg, WPARAM wp, LPARAM lp) {
    switch (msg) {
    case WM_TIMER:
        if (GetTickCount64() >= g_endTick) { DestroyWindow(w); return 0; }
        if (GetTickCount64() - g_lastAssert >= REASSERT_SEC * 1000ULL) {
            apply_state();   // 他のアプリに横から解除されても復帰させる
            update_tip();
        } else if (remaining_sec() < 60) {
            update_tip();    // 最後の 1 分は秒単位で出す
        }
        return 0;
    case WM_TRAY:
        switch (LOWORD(lp)) {
        case WM_LBUTTONDBLCLK: DestroyWindow(w); break;
        case WM_CONTEXTMENU:
        case WM_RBUTTONUP:     tray_menu(); break;
        }
        return 0;
    case WM_COMMAND:
        switch (LOWORD(wp)) {
        case IDM_DISPLAY: g_keepDisplay = !g_keepDisplay; apply_state(); break;
        case IDM_STOP:    DestroyWindow(w); break;
        }
        return 0;
    case WM_ENDSESSION:
        if (wp) { release_state(); Shell_NotifyIconW(NIM_DELETE, &g_nid); }
        return 0;
    case WM_DESTROY:
        KillTimer(w, TIMER_TICK);
        release_state();
        Shell_NotifyIconW(NIM_DELETE, &g_nid);
        PostQuitMessage(0);
        return 0;
    }
    if (msg == g_msgTaskbarCreated && msg != 0) { tray_add(); return 0; }  // エクスプローラ再起動
    return DefWindowProcW(w, msg, wp, lp);
}

// ---- 時間選択ダイアログ ----

static const LONGLONG k_presetSec[] = {
    5, 60, 30 * 60, 60 * 60, 2 * 3600, 4 * 3600, MAX_SECONDS,
};

static void sync_custom(HWND d) {
    BOOL on = IsDlgButtonChecked(d, IDC_RB_CUSTOM) == BST_CHECKED;
    EnableWindow(GetDlgItem(d, IDC_CUSTOM_EDIT), on);
    if (on) SetFocus(GetDlgItem(d, IDC_CUSTOM_EDIT));
}

static INT_PTR CALLBACK dlg_proc(HWND d, UINT msg, WPARAM wp, LPARAM lp) {
    (void)lp;
    switch (msg) {
    case WM_INITDIALOG:
        SendMessageW(d, WM_SETICON, ICON_BIG, (LPARAM)g_iconLarge);
        SendMessageW(d, WM_SETICON, ICON_SMALL, (LPARAM)g_iconSmall);
        CheckRadioButton(d, IDC_RB_FIRST, IDC_RB_LAST, IDC_RB_1H);  // 既定: 1時間
        CheckDlgButton(d, IDC_DISPLAY, BST_CHECKED);
        SendDlgItemMessageW(d, IDC_CUSTOM_EDIT, EM_SETLIMITTEXT, 3, 0);
        sync_custom(d);
        SetWindowPos(d, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE);
        return TRUE;
    case WM_COMMAND: {
        int id = LOWORD(wp);
        if (id >= IDC_RB_FIRST && id <= IDC_RB_LAST && HIWORD(wp) == BN_CLICKED) { sync_custom(d); return TRUE; }
        if (id == IDOK) {
            LONGLONG sec = 0;
            for (int i = IDC_RB_FIRST; i < IDC_RB_CUSTOM; i++)
                if (IsDlgButtonChecked(d, i) == BST_CHECKED) sec = k_presetSec[i - IDC_RB_FIRST];
            if (IsDlgButtonChecked(d, IDC_RB_CUSTOM) == BST_CHECKED) {
                BOOL ok = FALSE;
                UINT v = GetDlgItemInt(d, IDC_CUSTOM_EDIT, &ok, FALSE);
                if (!ok || v == 0) {
                    MessageBoxW(d, L"有効な分数を入力してください（1～540分）", L"エラー", MB_ICONWARNING);
                    SetFocus(GetDlgItem(d, IDC_CUSTOM_EDIT));
                    return TRUE;
                }
                sec = (LONGLONG)(v > 540 ? 540 : v) * 60;
            }
            g_keepDisplay = IsDlgButtonChecked(d, IDC_DISPLAY) == BST_CHECKED;
            EndDialog(d, (INT_PTR)sec);
            return TRUE;
        }
        if (id == IDCANCEL) { EndDialog(d, 0); return TRUE; }
        break;
    }
    }
    return FALSE;
}

// ---- コマンドライン ----

static LONGLONG parse_args(void) {
    int argc; LONGLONG sec = 0;
    wchar_t **argv = CommandLineToArgvW(GetCommandLineW(), &argc);
    if (!argv) return 0;
    for (int i = 1; i < argc; i++) {
        const wchar_t *a = argv[i];
        if (*a == L'/' || *a == L'-') a++;
        if (!_wcsicmp(a, L"s") && i + 1 < argc)      sec = _wtoi64(argv[++i]);
        else if (!_wcsicmp(a, L"m") && i + 1 < argc) sec = _wtoi64(argv[++i]) * 60;
        else if (!_wcsicmp(a, L"nodisplay"))         g_keepDisplay = FALSE;
    }
    LocalFree(argv);
    if (sec > MAX_SECONDS) sec = MAX_SECONDS;
    return sec > 0 ? sec : 0;
}

int WINAPI wWinMain(HINSTANCE inst, HINSTANCE prev, PWSTR cmd, int show) {
    (void)prev; (void)cmd; (void)show;
    g_inst = inst;
    INITCOMMONCONTROLSEX icc = { sizeof icc, ICC_STANDARD_CLASSES };
    InitCommonControlsEx(&icc);
    LoadIconMetric(inst, MAKEINTRESOURCEW(IDI_APP), LIM_LARGE, &g_iconLarge);
    LoadIconMetric(inst, MAKEINTRESOURCEW(IDI_APP), LIM_SMALL, &g_iconSmall);

    g_totalSec = parse_args();
    if (g_totalSec == 0) {
        g_totalSec = DialogBoxParamW(inst, MAKEINTRESOURCEW(IDD_DURATION), NULL, dlg_proc, 0);
        if (g_totalSec <= 0) return 0;
    }

    // 終了予定。判定は GetTickCount64、表示は現地時刻
    g_endTick = GetTickCount64() + (ULONGLONG)g_totalSec * 1000;
    FILETIME ft; GetSystemTimeAsFileTime(&ft);
    ULARGE_INTEGER u = { .LowPart = ft.dwLowDateTime, .HighPart = ft.dwHighDateTime };
    u.QuadPart += (ULONGLONG)g_totalSec * 10000000ULL;
    ft.dwLowDateTime = u.LowPart; ft.dwHighDateTime = u.HighPart;
    SYSTEMTIME st; FileTimeToSystemTime(&ft, &st);
    SystemTimeToTzSpecificLocalTime(NULL, &st, &g_endLocal);

    WNDCLASSW wc = { 0 };
    wc.lpfnWndProc = wnd_proc;
    wc.hInstance = inst;
    wc.lpszClassName = L"SleepGuardTray";
    RegisterClassW(&wc);
    g_msgTaskbarCreated = RegisterWindowMessageW(L"TaskbarCreated");
    // 不可視のトップレベルウィンドウ（メッセージ専用にすると TaskbarCreated が届かない）
    g_wnd = CreateWindowExW(0, wc.lpszClassName, APP_TITLE, 0, 0, 0, 0, 0, NULL, NULL, inst, NULL);

    apply_state();
    tray_add();
    tray_balloon();
    SetTimer(g_wnd, TIMER_TICK, TICK_MS, NULL);

    MSG m;
    while (GetMessageW(&m, NULL, 0, 0) > 0) {
        TranslateMessage(&m);
        DispatchMessageW(&m);
    }
    release_state();
    return 0;
}
