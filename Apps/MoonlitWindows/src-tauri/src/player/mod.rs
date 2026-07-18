pub mod geometry;

#[cfg(windows)]
pub mod embed;
#[cfg(windows)]
pub mod thread;

#[cfg(windows)]
use serde_json::Value;

#[cfg(windows)]
mod state {
    use super::thread::Cmd;
    use parking_lot::Mutex;
    use std::sync::mpsc::Sender;

    pub struct PlayerState(pub Mutex<Option<Sender<Cmd>>>);

    impl PlayerState {
        pub fn sender(&self) -> Result<Sender<Cmd>, String> {
            self.0.lock().clone().ok_or_else(|| "player thread not running".into())
        }
    }
}
#[cfg(windows)]
pub use state::PlayerState;

#[derive(serde::Serialize)]
pub struct MpvProbe {
    pub available: bool,
    pub reason: Option<String>,
}

#[tauri::command]
pub fn mpv_probe() -> MpvProbe {
    #[cfg(windows)]
    {
        MpvProbe { available: true, reason: None }
    }
    #[cfg(not(windows))]
    {
        MpvProbe { available: false, reason: Some("video playback is Windows-only".into()) }
    }
}

// ── Windows commands ──────────────────────────────────────────────────────────

#[cfg(windows)]
mod win_commands {
    use super::*;
    use crate::player::thread::{Cmd, StartArgs};
    use tauri::{AppHandle, State};

    #[derive(serde::Deserialize)]
    #[serde(rename_all = "camelCase")]
    pub struct StartPayload {
        pub url: String,
        pub start_at_sec: Option<f64>,
        pub headers: Option<std::collections::HashMap<String, String>>,
    }

    #[tauri::command]
    pub fn mpv_start(
        app: AppHandle,
        state: State<'_, super::PlayerState>,
        payload: StartPayload,
    ) -> Result<(), String> {
        super::embed::make_webview_transparent(&app);
        let wid = super::embed::main_hwnd(&app).ok_or("no main window")? as i64;
        state.sender()?
            .send(Cmd::Start(StartArgs {
                url: payload.url,
                start_at_sec: payload.start_at_sec,
                headers: payload.headers,
                wid,
            }))
            .map_err(|e| e.to_string())
    }

    #[tauri::command]
    pub fn mpv_stop(state: State<'_, super::PlayerState>) -> Result<(), String> {
        state.sender()?.send(Cmd::Stop).map_err(|e| e.to_string())
    }

    #[tauri::command]
    pub fn mpv_set_property(
        state: State<'_, super::PlayerState>, name: String, value: Value,
    ) -> Result<(), String> {
        const BLOCKLIST: &[&str] = &["script", "input-", "ytdl-raw"];
        if BLOCKLIST.iter().any(|b| name.starts_with(b)) {
            return Err(format!("property {name} not allowed"));
        }
        state.sender()?.send(Cmd::SetProp(name, value)).map_err(|e| e.to_string())
    }

    #[tauri::command]
    pub fn mpv_get_property(
        state: State<'_, super::PlayerState>, name: String,
    ) -> Result<Value, String> {
        let (tx, rx) = std::sync::mpsc::channel();
        state.sender()?.send(Cmd::GetProp(name, tx)).map_err(|e| e.to_string())?;
        rx.recv_timeout(std::time::Duration::from_secs(2)).map_err(|e| e.to_string())?
    }

    #[tauri::command]
    pub fn mpv_command(state: State<'_, super::PlayerState>, parts: Vec<String>) -> Result<(), String> {
        const WHITELIST: &[&str] = &["seek", "stop", "frame-step", "frame-back-step", "cycle", "sub-reload"];
        match parts.first() {
            Some(head) if WHITELIST.contains(&head.as_str()) => {
                state.sender()?.send(Cmd::Command(parts)).map_err(|e| e.to_string())
            }
            _ => Err("command not allowed".into()),
        }
    }

    #[tauri::command]
    pub fn mpv_sub_add(
        state: State<'_, super::PlayerState>,
        url: String, title: Option<String>, lang: Option<String>, select: Option<bool>,
    ) -> Result<(), String> {
        state.sender()?
            .send(Cmd::SubAdd { url, title, lang, select: select.unwrap_or(true) })
            .map_err(|e| e.to_string())
    }

    #[tauri::command]
    pub fn mpv_screenshot(
        state: State<'_, super::PlayerState>, path: String,
    ) -> Result<String, String> {
        let (tx, rx) = std::sync::mpsc::channel();
        state.sender()?.send(Cmd::Screenshot { path: Some(path), reply: tx }).map_err(|e| e.to_string())?;
        rx.recv_timeout(std::time::Duration::from_secs(5)).map_err(|e| e.to_string())?
    }

    #[tauri::command]
    pub fn mpv_set_geometry(app: AppHandle, css: super::geometry::CssGeometry) -> Result<(), String> {
        super::embed::position_mpv_child(&app, css)
    }

    #[tauri::command]
    pub fn shader_dir(app: AppHandle) -> Result<String, String> {
        use tauri::Manager;
        app.path()
            .resolve("shaders", tauri::path::BaseDirectory::Resource)
            .map(|p| p.to_string_lossy().into_owned())
            .map_err(|e| e.to_string())
    }
}
#[cfg(windows)]
pub use win_commands::*;

#[cfg(not(windows))]
mod stub_commands {
    #[tauri::command]
    pub fn mpv_start() -> Result<(), String> { Err("windows only".into()) }

    #[tauri::command]
    pub fn mpv_stop() -> Result<(), String> { Err("windows only".into()) }
}
#[cfg(not(windows))]
pub use stub_commands::*;
