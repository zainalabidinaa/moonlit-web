/// Windows: make the WebView2 transparent and position mpv's child window
/// behind it using `wid` embedding (Harbor-proven pattern).
use tauri::{AppHandle, Manager};
use windows::Win32::Foundation::{BOOL, HWND, LPARAM, LRESULT, WPARAM};
use windows::Win32::UI::Shell::{DefSubclassProc, SetWindowSubclass};
use windows::Win32::UI::WindowsAndMessaging::{
    EnumChildWindows, GetClientRect, SetWindowLongW, SetWindowPos, GWL_EXSTYLE, GetWindowLongW,
    HWND_BOTTOM, SWP_NOACTIVATE, SWP_SHOWWINDOW, WM_NCHITTEST, WS_EX_TRANSPARENT,
};

use super::geometry::{map_css_geometry, CssGeometry};

const HTTRANSPARENT: isize = -1;
const MPC_SUBCLASS_ID: usize = 0x4D4E; // decorative

pub fn main_hwnd(app: &AppHandle) -> Option<isize> {
    let window = app.get_webview_window("main")?;
    window.hwnd().ok().map(|h| h.0 as isize)
}

/// Make the WebView2 background fully transparent so the mpv child HWND
/// (positioned at HWND_BOTTOM) is visible behind the React UI.
pub fn make_webview_transparent(app: &AppHandle) {
    if let Some(window) = app.get_webview_window("main") {
        let _ = window.with_webview(|webview| unsafe {
            use webview2_com::Microsoft::Web::WebView2::Win32::{
                ICoreWebView2Controller2, COREWEBVIEW2_COLOR,
            };
            use windows::core::Interface;
            let controller = webview.controller();
            if let Ok(c2) = controller.cast::<ICoreWebView2Controller2>() {
                let _ = c2.SetDefaultBackgroundColor(COREWEBVIEW2_COLOR { A: 0, R: 0, G: 0, B: 0 });
            }
        });
    }
}

unsafe extern "system" fn subclass_proc(
    hwnd: HWND,
    msg: u32,
    wparam: WPARAM,
    lparam: LPARAM,
    _id: usize,
    _data: usize,
) -> LRESULT {
    if msg == WM_NCHITTEST {
        return LRESULT(HTTRANSPARENT);
    }
    unsafe { DefSubclassProc(hwnd, msg, wparam, lparam) }
}

struct EnumState {
    found: Vec<HWND>,
}

unsafe extern "system" fn enum_proc(hwnd: HWND, lparam: LPARAM) -> BOOL {
    let state = unsafe { &mut *(lparam.0 as *mut EnumState) };
    let mut buf = [0u16; 64];
    let n = unsafe { windows::Win32::UI::WindowsAndMessaging::GetClassNameW(hwnd, &mut buf) };
    if n > 0 {
        let class = String::from_utf16_lossy(&buf[..n as usize]);
        if class == "mpv" || class.starts_with("mpv ") {
            state.found.push(hwnd);
        }
    }
    BOOL(1)
}

/// Find mpv's child HWND under the main window, push it to the bottom z-order,
/// make it click-through, and size it from CSS geometry.
pub fn position_mpv_child(app: &AppHandle, css: CssGeometry) -> Result<(), String> {
    let parent = HWND(main_hwnd(app).ok_or("no main window")? as *mut _);
    let mut state = EnumState { found: vec![] };
    unsafe {
        let _ = EnumChildWindows(None, Some(enum_proc), LPARAM(&mut state as *mut _ as isize));
    }
    let target = state.found.into_iter().find(|_| true).ok_or("mpv child window not found")?;

    let mut client = windows::Win32::Foundation::RECT::default();
    unsafe { GetClientRect(parent, &mut client) }.map_err(|e| e.to_string())?;
    let rect = map_css_geometry(
        css,
        (client.right - client.left) as f64,
        (client.bottom - client.top) as f64,
    )
    .ok_or("degenerate geometry")?;

    unsafe {
        let ex = GetWindowLongW(target, GWL_EXSTYLE);
        SetWindowLongW(target, GWL_EXSTYLE, ex | WS_EX_TRANSPARENT.0 as i32);
        let _ = SetWindowSubclass(target, Some(subclass_proc), MPC_SUBCLASS_ID, 0);
        SetWindowPos(
            target,
            HWND_BOTTOM,
            rect.x,
            rect.y,
            rect.w,
            rect.h,
            SWP_NOACTIVATE | SWP_SHOWWINDOW,
        )
        .map_err(|e| e.to_string())?;
    }
    Ok(())
}
