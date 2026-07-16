# Windows Desktop Phase 4: libmpv Player Core (Full Parity) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Native libmpv playback in the Tauri desktop app with full Mac-player feature parity: tracks/delays, external subtitles + styling, Anime4K, seek thumbnails, resume + progress sync, source switching + auto-fallback, episode navigation + Up Next, skip intro, screenshots, PiP mini-mode, fullscreen, hotkeys.

**Architecture:** libmpv renders into a child HWND of the main Tauri window (`wid` embedding, Harbor-proven); WebView2 background is set fully transparent so the React UI draws over the video. A dedicated Rust player thread owns the mpv handle; all control flows through a channel-based command API exposed as Tauri commands, with mpv events re-emitted as a single `mpv://event` Tauri event. The frontend adds an `MpvPlayer` player type to the existing `PlayerShell` dispatch, gated by `isDesktop()` + runtime probe; the web player path is untouched.

**Tech Stack:** libmpv2 (Rust crate v4) + libmpv-2.dll (Windows), windows/webview2-com crates, Tauri 2 events, React 19, existing web modules (`stremio.ts`, `api.ts updateWatchProgress`, `last-stream.ts`, `subtitle-preferences.ts`, `SkipIntroOverlay`, `SourcesPanel`, `LoadCard`, `PlaybackErrorScreen`).

**Spec:** `docs/superpowers/specs/2026-07-16-windows-desktop-app-design.md` (Sections 3.2, 3.3, 5C, D)

**Decisions:** Signing skipped for now (SmartScreen "Run anyway" in VM). Full parity in one phase (user choice). Video playback is **Windows-only**; on macOS dev the probe reports unavailable and the web player is used (matches Windows-only platform decision). Design polish deferred to Phase 2 — this player UI is functional, styled with current Tailwind idioms.

**Working conventions:** npm, work in `moonlit-web/`, branch `windows-desktop-phase-1` (continue on it; rename to `windows-desktop-foundation-player` is NOT needed). Never `git add -A` (tree has unrelated dirty files). Rust player code is `#[cfg(windows)]`-gated; macOS `cargo test` stays green by testing pure logic only.

---

## File Structure

```
moonlit-web/
├── scripts/
│   └── fetch-libmpv.mjs                  NEW: DLL + import-lib + Anime4K shader fetch (Windows-only script)
├── src-tauri/
│   ├── Cargo.toml                        MOD: windows-gated libmpv2/windows/webview2-com deps
│   ├── build.rs                          MOD: link-search for libmpv import lib
│   ├── tauri.windows.conf.json           NEW: bundle libmpv-2.dll + shaders as resources
│   ├── capabilities/default.json         MOD: window/event permissions for player + PiP
│   └── src/
│       ├── lib.rs                        MOD: register player module, transparent webview setup
│       ├── player/
│       │   ├── mod.rs                    NEW: Tauri commands + state (channel to player thread)
│       │   ├── thread.rs                 NEW: player thread owning Mpv (windows-only)
│       │   ├── geometry.rs               NEW: CSS→native px mapping (pure, cross-platform, tested)
│       │   └── embed.rs                  NEW: HWND child positioning/click-through (windows-only)
├── src/
│   ├── lib/platform/
│   │   ├── mpv.ts                        NEW: typed JS bridge (commands + event subscription)
│   │   ├── mpv-subtitle-style.ts         NEW: SubtitlePreferences → mpv properties (pure, tested)
│   │   └── desktop-selection.ts          NEW: desktop stream sort/pick (pure, tested)
│   └── components/player/
│       ├── MpvPlayer.tsx                 NEW: desktop player component (controls, hotkeys, lifecycle)
│       ├── MpvTracksPanel.tsx            NEW: audio/sub tracks + delays + styling (mpv-driven)
│       ├── UpNextPanel.tsx               NEW: episode list / next-episode panel
│       ├── StreamCheckPill.tsx           NEW: "Does this look right?" pill
│       ├── ResumePrompt.tsx              NEW: "Resuming from X:XX / Start over"
│       └── PlayerShell.tsx               MOD: dispatch 'mpv' player type on desktop
└── .github/workflows/windows-desktop.yml MOD: fetch sidecars before build/test
```

---

### Task 1: Sidecar fetch script (libmpv DLL + import lib + Anime4K shaders)

**Files:**
- Create: `moonlit-web/scripts/fetch-libmpv.mjs`
- Modify: `moonlit-web/package.json` (script)
- Modify: `moonlit-web/src-tauri/.gitignore`

- [ ] **Step 1: Create `scripts/fetch-libmpv.mjs`**

```js
// Fetches Windows playback sidecars into src-tauri/: libmpv-2.dll (+ mpv.lib
// import library generated from mpv.def) and Anime4K GLSL shaders.
// Windows-only artifacts; safe to run on any OS (shaders always fetched,
// DLL steps skipped off-Windows unless FORCE_DLL=1).
import { mkdirSync, writeFileSync, existsSync, renameSync, readdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execSync } from 'node:child_process';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const libmpvDir = join(root, 'src-tauri', 'libmpv');
const shadersDir = join(root, 'src-tauri', 'shaders');

async function download(url, dest) {
  console.log(`↓ ${url}`);
  const res = await fetch(url, { redirect: 'follow' });
  if (!res.ok) throw new Error(`${res.status} ${res.statusText} for ${url}`);
  writeFileSync(dest, Buffer.from(await res.arrayBuffer()));
  console.log(`  → ${dest}`);
}

// ── Anime4K shaders (all platforms; tiny text files) ────────────────────────
const SHADERS = [
  'Restore/Anime4K_Clamp_Highlights.glsl',
  'Restore/Anime4K_Restore_CNN_M.glsl',
  'Upscale+Denoise/Anime4K_Upscale_Denoise_CNN_x2_M.glsl',
];
mkdirSync(shadersDir, { recursive: true });
for (const s of SHADERS) {
  const name = s.split('/').pop();
  const dest = join(shadersDir, name);
  if (existsSync(dest)) { console.log(`✓ ${name} (cached)`); continue; }
  await download(`https://raw.githubusercontent.com/bloc97/Anime4K/master/glsl/${s}`, dest);
}

// ── libmpv DLL + import lib (Windows only) ───────────────────────────────────
if (process.platform !== 'win32' && process.env.FORCE_DLL !== '1') {
  console.log('Non-Windows: skipping libmpv DLL fetch (video playback is Windows-only).');
  process.exit(0);
}
mkdirSync(libmpvDir, { recursive: true });

if (existsSync(join(libmpvDir, 'libmpv-2.dll')) && existsSync(join(libmpvDir, 'mpv.lib'))) {
  console.log('✓ libmpv-2.dll + mpv.lib (cached)');
  process.exit(0);
}

// Resolve mpv-dev asset from shinchiro/mpv-winbuild-cmake (override with MPV_DEV_URL)
let devUrl = process.env.MPV_DEV_URL;
if (!devUrl) {
  const rel = await (await fetch(
    'https://api.github.com/repos/shinchiro/mpv-winbuild-cmake/releases/latest',
    { headers: { 'User-Agent': 'moonlit-desktop-setup' } },
  )).json();
  const asset = (rel.assets ?? []).find(
    (a) => a.name.startsWith('mpv-dev-x86_64-2') && a.name.endsWith('.7z'),
  );
  if (!asset) throw new Error('No mpv-dev-x86_64 asset found in latest release');
  devUrl = asset.browser_download_url;
}
const archive = join(libmpvDir, 'mpv-dev.7z');
await download(devUrl, archive);

// Extract (7z.exe present on GitHub runners and most dev boxes; else install 7-Zip)
execSync(`7z x -y -o"${libmpvDir}" "${archive}" libmpv-2.dll mpv.def`, { stdio: 'inherit' });

// Generate MSVC import library from the .def
// Prefer llvm-dlltool (ships with LLVM on GitHub runners), fall back to VS lib.exe.
const def = join(libmpvDir, 'mpv.def');
const lib = join(libmpvDir, 'mpv.lib');
try {
  execSync(`llvm-dlltool -m i386:x86-64 -d "${def}" -D libmpv-2.dll -l "${lib}"`, { stdio: 'inherit' });
} catch {
  execSync(`lib /def:"${def}" /machine:x64 /out:"${lib}"`, { stdio: 'inherit' });
}
console.log('✓ sidecars ready:', readdirSync(libmpvDir).join(', '));
```

- [ ] **Step 2: Add npm script** — in `moonlit-web/package.json` scripts:

```json
"setup:desktop": "node scripts/fetch-libmpv.mjs"
```

- [ ] **Step 3: Ignore fetched artifacts** — append to `moonlit-web/src-tauri/.gitignore`:

```
/libmpv
/shaders
```

- [ ] **Step 4: Verify on macOS (shaders only)**

Run (in `moonlit-web/`): `npm run setup:desktop`
Expected: 3 `.glsl` files land in `src-tauri/shaders/`, DLL step skipped with message.

- [ ] **Step 5: Commit**

```bash
git add scripts/fetch-libmpv.mjs package.json src-tauri/.gitignore
git commit -m "feat(desktop): sidecar fetch script for libmpv DLL, import lib, and Anime4K shaders"
```

---

### Task 2: Cargo dependencies, build script, Windows bundle config

**Files:**
- Modify: `moonlit-web/src-tauri/Cargo.toml`
- Modify: `moonlit-web/src-tauri/build.rs`
- Create: `moonlit-web/src-tauri/tauri.windows.conf.json`

- [ ] **Step 1: Add windows-gated deps** — in `Cargo.toml`, extend `[dependencies]` with:

```toml
parking_lot = "0.12"
```

and add below the existing target-specific block:

```toml
[target.'cfg(windows)'.dependencies]
libmpv2 = "4"
webview2-com = "0.34"
windows = { version = "0.60", features = [
  "Win32_Foundation",
  "Win32_UI_WindowsAndMessaging",
  "Win32_UI_Shell",
  "Win32_Graphics_Gdi",
] }
```

Note: pin `webview2-com`/`windows` versions to whatever `tauri` 2.x already pulls (check `cargo tree | grep -E 'windows |webview2-com'` and match, to avoid duplicate windows-rs versions). Adjust the two version numbers accordingly — this is expected and fine.

- [ ] **Step 2: Extend `build.rs`**

```rust
fn main() {
    #[cfg(windows)]
    {
        let manifest = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let libmpv = manifest.join("libmpv");
        if libmpv.join("mpv.lib").exists() {
            println!("cargo:rustc-link-search=native={}", libmpv.display());
        } else {
            println!("cargo:warning=src-tauri/libmpv/mpv.lib missing — run `npm run setup:desktop`");
        }
    }
    tauri_build::build()
}
```

- [ ] **Step 3: Create `tauri.windows.conf.json`** (platform-specific merge file; Tauri picks it up automatically)

```json
{
  "bundle": {
    "resources": {
      "libmpv/libmpv-2.dll": "libmpv-2.dll",
      "shaders/": "shaders/"
    }
  }
}
```

- [ ] **Step 4: Verify macOS build unaffected**

Run (in `src-tauri/`): `cargo check`
Expected: compiles (windows deps not resolved on mac).

- [ ] **Step 5: Commit**

```bash
git add src-tauri/Cargo.toml src-tauri/Cargo.lock src-tauri/build.rs src-tauri/tauri.windows.conf.json
git commit -m "feat(desktop): windows-gated libmpv2 deps, link search, and DLL/shader bundling"
```

---

### Task 3: Geometry mapping (pure Rust, TDD, cross-platform)

**Files:**
- Create: `moonlit-web/src-tauri/src/player/geometry.rs`
- Create: `moonlit-web/src-tauri/src/player/mod.rs` (module skeleton)
- Modify: `moonlit-web/src-tauri/src/lib.rs`

- [ ] **Step 1: Create `src/player/geometry.rs`** (tests included — TDD in-file like Task 6 of Phase 1)

```rust
use serde::Deserialize;

/// CSS-pixel geometry of the video area reported by the WebView,
/// plus the CSS viewport size for scale derivation.
#[derive(Debug, Clone, Copy, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct CssGeometry {
    pub css_left: f64,
    pub css_top: f64,
    pub css_width: f64,
    pub css_height: f64,
    pub css_view_w: f64,
    pub css_view_h: f64,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct NativeRect {
    pub x: i32,
    pub y: i32,
    pub w: i32,
    pub h: i32,
}

/// Map CSS geometry to native pixels given the native client size.
/// Returns None when the viewport is degenerate (avoids div-by-zero).
pub fn map_css_geometry(css: CssGeometry, native_w: f64, native_h: f64) -> Option<NativeRect> {
    if css.css_view_w <= 0.0 || css.css_view_h <= 0.0 || native_w <= 0.0 || native_h <= 0.0 {
        return None;
    }
    let sx = native_w / css.css_view_w;
    let sy = native_h / css.css_view_h;
    Some(NativeRect {
        x: (css.css_left * sx).round() as i32,
        y: (css.css_top * sy).round() as i32,
        w: (css.css_width * sx).round().max(1.0) as i32,
        h: (css.css_height * sy).round().max(1.0) as i32,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn css(l: f64, t: f64, w: f64, h: f64, vw: f64, vh: f64) -> CssGeometry {
        CssGeometry { css_left: l, css_top: t, css_width: w, css_height: h, css_view_w: vw, css_view_h: vh }
    }

    #[test]
    fn maps_1x_scale_identity() {
        let r = map_css_geometry(css(0.0, 0.0, 1280.0, 720.0, 1280.0, 720.0), 1280.0, 720.0).unwrap();
        assert_eq!(r, NativeRect { x: 0, y: 0, w: 1280, h: 720 });
    }

    #[test]
    fn maps_150_percent_dpi() {
        let r = map_css_geometry(css(100.0, 50.0, 800.0, 450.0, 1280.0, 720.0), 1920.0, 1080.0).unwrap();
        assert_eq!(r, NativeRect { x: 150, y: 75, w: 1200, h: 675 });
    }

    #[test]
    fn rejects_degenerate_viewport() {
        assert!(map_css_geometry(css(0.0, 0.0, 100.0, 100.0, 0.0, 0.0), 1920.0, 1080.0).is_none());
    }

    #[test]
    fn clamps_to_min_1px() {
        let r = map_css_geometry(css(0.0, 0.0, 0.2, 0.2, 1280.0, 720.0), 1280.0, 720.0).unwrap();
        assert_eq!((r.w, r.h), (1, 1));
    }
}
```

- [ ] **Step 2: Create `src/player/mod.rs`**

```rust
pub mod geometry;
```

- [ ] **Step 3: Wire into `src/lib.rs`** — add below `pub mod deeplink;`:

```rust
pub mod player;
```

- [ ] **Step 4: Run tests**

Run (in `src-tauri/`): `cargo test`
Expected: 7 passed (3 deeplink + 4 geometry).

- [ ] **Step 5: Commit**

```bash
git add src-tauri/src/player src-tauri/src/lib.rs
git commit -m "feat(desktop): CSS-to-native geometry mapping for the mpv surface"
```

---

### Task 4: Player thread (Rust, Windows) — mpv lifecycle + event pump

**Files:**
- Create: `moonlit-web/src-tauri/src/player/thread.rs`
- Modify: `moonlit-web/src-tauri/src/player/mod.rs`

The player thread **owns** the `Mpv` handle (no Send/Sync gymnastics). Commands arrive over an mpsc channel; the loop alternates `try_recv` and `wait_event(0.05)`; mpv events/properties are emitted to JS as `mpv://event`.

- [ ] **Step 1: Create `src/player/thread.rs`** (entire file is `#[cfg(windows)]` via mod gating in Step 2)

```rust
use serde_json::{json, Value};
use std::sync::mpsc::{Receiver, Sender};
use tauri::{AppHandle, Emitter};

#[derive(Debug)]
pub enum Cmd {
    Start(StartArgs),
    Stop,
    SetProp(String, Value),
    GetProp(String, Sender<Result<Value, String>>),
    Command(Vec<String>),
    SubAdd { url: String, title: Option<String>, lang: Option<String>, select: bool },
    Screenshot { path: Option<String>, reply: Sender<Result<String, String>> },
    Shutdown,
}

#[derive(Debug, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct StartArgs {
    pub url: String,
    pub start_at_sec: Option<f64>,
    pub headers: Option<std::collections::HashMap<String, String>>,
    pub wid: i64,
}

const OBSERVED: &[(&str, libmpv2::Format)] = &[
    ("time-pos", libmpv2::Format::Double),
    ("duration", libmpv2::Format::Double),
    ("pause", libmpv2::Format::Flag),
    ("eof-reached", libmpv2::Format::Flag),
    ("mute", libmpv2::Format::Flag),
    ("volume", libmpv2::Format::Double),
    ("speed", libmpv2::Format::Double),
    ("track-list", libmpv2::Format::String),
    ("sub-delay", libmpv2::Format::Double),
    ("audio-delay", libmpv2::Format::Double),
    ("demuxer-cache-time", libmpv2::Format::Double),
    ("video-params/aspect", libmpv2::Format::Double),
    ("paused-for-cache", libmpv2::Format::Flag),
];

fn emit(app: &AppHandle, payload: Value) {
    let _ = app.emit("mpv://event", payload);
}

/// Force C numeric locale — libmpv asserts on comma-decimal locales.
fn force_c_numeric_locale() {
    unsafe {
        libc_locale();
    }
    #[inline]
    unsafe fn libc_locale() {
        unsafe extern "C" {
            fn setlocale(category: i32, locale: *const std::ffi::c_char) -> *mut std::ffi::c_char;
        }
        const LC_NUMERIC: i32 = 4; // msvcrt
        unsafe { setlocale(LC_NUMERIC, c"C".as_ptr()) };
    }
}

pub fn run(app: AppHandle, rx: Receiver<Cmd>) {
    let mut mpv: Option<libmpv2::Mpv> = None;

    loop {
        // Drain pending commands (non-blocking)
        while let Ok(cmd) = rx.try_recv() {
            match cmd {
                Cmd::Shutdown => {
                    drop(mpv.take());
                    return;
                }
                Cmd::Start(args) => {
                    drop(mpv.take()); // tear down previous instance
                    force_c_numeric_locale();
                    match create_mpv(&args) {
                        Ok(m) => {
                            for (name, fmt) in OBSERVED {
                                let _ = m.observe_property(name, *fmt, 0);
                            }
                            let cmd_load = if let Some(pos) = args.start_at_sec {
                                format!("loadfile \"{}\" replace start={}", args.url, pos)
                            } else {
                                format!("loadfile \"{}\" replace", args.url)
                            };
                            if let Err(e) = m.command("loadfile", &[&args.url, "replace"]) {
                                emit(&app, json!({"event":"error","message": format!("loadfile: {e}")}));
                            } else if let Some(pos) = args.start_at_sec {
                                // applied when file loads
                                let _ = m.set_property("start", pos.to_string());
                                let _ = cmd_load; // start passed via property for robustness
                            }
                            mpv = Some(m);
                            emit(&app, json!({"event":"started"}));
                        }
                        Err(e) => emit(&app, json!({"event":"error","message": e})),
                    }
                }
                Cmd::Stop => {
                    if let Some(m) = &mpv {
                        let _ = m.command("stop", &[]);
                    }
                    drop(mpv.take());
                    emit(&app, json!({"event":"stopped"}));
                }
                Cmd::SetProp(name, value) => {
                    if let Some(m) = &mpv {
                        let r = match &value {
                            Value::Bool(b) => m.set_property(&name, *b),
                            Value::Number(n) if n.is_f64() || n.is_i64() => {
                                m.set_property(&name, n.as_f64().unwrap_or_default())
                            }
                            Value::String(s) => m.set_property(&name, s.as_str()),
                            _ => Err(libmpv2::Error::InvalidUtf8),
                        };
                        if let Err(e) = r {
                            emit(&app, json!({"event":"log","level":"warn","text":format!("set {name}: {e}")}));
                        }
                    }
                }
                Cmd::GetProp(name, reply) => {
                    let out = mpv
                        .as_ref()
                        .ok_or_else(|| "no player".to_string())
                        .and_then(|m| {
                            m.get_property::<String>(&name).map(Value::String).or_else(|_| {
                                m.get_property::<f64>(&name)
                                    .map(|v| json!(v))
                                    .map_err(|e| e.to_string())
                            })
                        });
                    let _ = reply.send(out);
                }
                Cmd::Command(parts) => {
                    if let (Some(m), Some((head, tail))) = (&mpv, parts.split_first()) {
                        let refs: Vec<&str> = tail.iter().map(String::as_str).collect();
                        if let Err(e) = m.command(head, &refs) {
                            emit(&app, json!({"event":"log","level":"warn","text":format!("cmd {head}: {e}")}));
                        }
                    }
                }
                Cmd::SubAdd { url, title, lang, select } => {
                    if let Some(m) = &mpv {
                        let mode = if select { "select" } else { "auto" };
                        let title = title.unwrap_or_else(|| "External".into());
                        let lang = lang.unwrap_or_else(|| "und".into());
                        let _ = m.command("sub-add", &[&url, mode, &title, &lang]);
                    }
                }
                Cmd::Screenshot { path, reply } => {
                    let out = mpv.as_ref().ok_or_else(|| "no player".to_string()).and_then(|m| {
                        match &path {
                            Some(p) => m
                                .command("screenshot-to-file", &[p, "video"])
                                .map(|_| p.clone())
                                .map_err(|e| e.to_string()),
                            None => Err("path required".into()),
                        }
                    });
                    let _ = reply.send(out);
                }
            }
        }

        // Pump mpv events
        if let Some(m) = &mut mpv {
            match m.event_context_mut().wait_event(0.05) {
                Some(Ok(ev)) => forward_event(&app, ev),
                Some(Err(e)) => emit(&app, json!({"event":"log","level":"warn","text": e.to_string()})),
                None => {}
            }
        } else {
            std::thread::sleep(std::time::Duration::from_millis(50));
        }
    }
}

fn create_mpv(args: &StartArgs) -> Result<libmpv2::Mpv, String> {
    libmpv2::Mpv::with_initializer(|init| {
        init.set_property("wid", args.wid)?;
        init.set_property("vo", "gpu-next")?;
        init.set_property("gpu-api", "d3d11")?;
        init.set_property("hwdec", "auto-safe")?;
        init.set_property("force-window", "immediate")?;
        init.set_property("keep-open", "yes")?;
        init.set_property("idle", "yes")?;
        init.set_property("input-default-bindings", "no")?;
        init.set_property("osc", "no")?;
        init.set_property("osd-level", 0i64)?;
        init.set_property("terminal", "no")?;
        init.set_property("audio-client-name", "Moonlit")?;
        init.set_property("user-agent", "Moonlit Desktop")?;
        init.set_property("screenshot-format", "png")?;
        if let Some(headers) = &args.headers {
            let fields: Vec<String> = headers.iter().map(|(k, v)| format!("{k}: {v}")).collect();
            if !fields.is_empty() {
                init.set_property("http-header-fields", fields.join(","))?;
            }
        }
        Ok(())
    })
    .map_err(|e| format!("mpv init: {e}"))
}

fn forward_event(app: &AppHandle, ev: libmpv2::events::Event) {
    use libmpv2::events::Event as E;
    match ev {
        E::PropertyChange { name, change, .. } => {
            let data = property_value_to_json(change);
            emit(app, json!({"event":"property-change","name": name, "data": data}));
        }
        E::EndFile(reason) => emit(app, json!({"event":"end-file","reason": format!("{reason:?}")})),
        E::FileLoaded => emit(app, json!({"event":"file-loaded"})),
        E::PlaybackRestart => emit(app, json!({"event":"playback-restart"})),
        E::Seek => emit(app, json!({"event":"seek"})),
        E::Shutdown => emit(app, json!({"event":"shutdown"})),
        _ => {}
    }
}

fn property_value_to_json(v: libmpv2::events::PropertyData) -> Value {
    use libmpv2::events::PropertyData as P;
    match v {
        P::Double(d) => json!(d),
        P::Flag(b) => json!(b),
        P::Str(s) => serde_json::from_str::<Value>(s).unwrap_or_else(|_| json!(s)),
        P::Int64(i) => json!(i),
        _ => Value::Null,
    }
}
```

Implementation note for the subagent: `libmpv2` v4 API names may differ slightly (`SetData`/`PropertyData` enum variants, `observe_property` signature, `with_initializer` availability). **Compile against the real crate docs (docs.rs/libmpv2/4) and adapt mechanically** — the required behavior (init props incl. `wid`, observed property list, event forwarding as specified JSON shapes) is the contract; exact crate calls may be adjusted. The JSON event contract MUST NOT change (frontend depends on it — Task 7).

- [ ] **Step 2: Gate the module** — `src/player/mod.rs` becomes:

```rust
pub mod geometry;

#[cfg(windows)]
pub mod thread;
#[cfg(windows)]
pub mod embed;
```

(`embed.rs` arrives in Task 5 — create an empty `pub(crate) fn _placeholder() {}` file now so it compiles, or add the mod line in Task 5 instead; choose the latter: only add `pub mod thread;` now.)

- [ ] **Step 3: Verify cross-platform**

Run (in `src-tauri/`): `cargo check && cargo test`
Expected on macOS: compiles (thread.rs excluded), 7 tests pass.

- [ ] **Step 4: Commit**

```bash
git add src-tauri/src/player
git commit -m "feat(desktop): mpv player thread with channel command API and event forwarding (windows)"
```

---

### Task 5: HWND embedding + transparent WebView2 + Tauri commands

**Files:**
- Create: `moonlit-web/src-tauri/src/player/embed.rs`
- Modify: `moonlit-web/src-tauri/src/player/mod.rs`
- Modify: `moonlit-web/src-tauri/src/lib.rs`
- Modify: `moonlit-web/src-tauri/capabilities/default.json`

- [ ] **Step 1: Create `src/player/embed.rs`** (Windows-only)

```rust
use tauri::{AppHandle, Manager};
use windows::Win32::Foundation::{BOOL, HWND, LPARAM, LRESULT, WPARAM};
use windows::Win32::Graphics::Gdi::HRGN;
use windows::Win32::UI::Shell::{DefSubclassProc, SetWindowSubclass};
use windows::Win32::UI::WindowsAndMessaging::{
    EnumChildWindows, GetClassNameW, GetClientRect, SetWindowLongW, SetWindowPos, GWL_EXSTYLE,
    GetWindowLongW, HWND_BOTTOM, SWP_NOACTIVATE, SWP_SHOWWINDOW, WM_NCHITTEST, WS_EX_TRANSPARENT,
};

use super::geometry::{map_css_geometry, CssGeometry};

const HTTRANSPARENT: i32 = -1;

pub fn main_hwnd(app: &AppHandle) -> Option<isize> {
    let window = app.get_webview_window("main")?;
    window.hwnd().ok().map(|h| h.0 as isize)
}

/// Make the WebView2 layer transparent so the mpv child window shows through.
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
    hwnd: HWND, msg: u32, wparam: WPARAM, lparam: LPARAM, _id: usize, _data: usize,
) -> LRESULT {
    if msg == WM_NCHITTEST {
        return LRESULT(HTTRANSPARENT as isize);
    }
    unsafe { DefSubclassProc(hwnd, msg, wparam, lparam) }
}

struct EnumState {
    found: Vec<HWND>,
}

unsafe extern "system" fn enum_proc(hwnd: HWND, lparam: LPARAM) -> BOOL {
    let state = unsafe { &mut *(lparam.0 as *mut EnumState) };
    let mut buf = [0u16; 64];
    let n = unsafe { GetClassNameW(hwnd, &mut buf) } as usize;
    let class = String::from_utf16_lossy(&buf[..n]);
    if class == "mpv" || class.starts_with("mpv ") {
        state.found.push(hwnd);
    }
    BOOL(1)
}

/// Find mpv's child HWND under the main window, push it to the bottom of the
/// z-order, make it click-through, and size it to the mapped CSS geometry.
pub fn position_mpv_child(app: &AppHandle, css: CssGeometry) -> Result<(), String> {
    let parent = HWND(main_hwnd(app).ok_or("no main window")? as *mut _);
    let mut state = EnumState { found: vec![] };
    unsafe {
        let _ = EnumChildWindows(Some(parent), Some(enum_proc), LPARAM(&mut state as *mut _ as isize));
    }
    let Some(&target) = state.found.first() else {
        return Err("mpv child window not found".into());
    };

    let mut client = windows::Win32::Foundation::RECT::default();
    unsafe { GetClientRect(parent, &mut client) }.map_err(|e| e.to_string())?;
    let rect = map_css_geometry(css, (client.right - client.left) as f64, (client.bottom - client.top) as f64)
        .ok_or("degenerate geometry")?;

    unsafe {
        let ex = GetWindowLongW(target, GWL_EXSTYLE);
        SetWindowLongW(target, GWL_EXSTYLE, ex | WS_EX_TRANSPARENT.0 as i32);
        let _ = SetWindowSubclass(target, Some(subclass_proc), 0xM00N as usize & 0xFFFF, 0);
        SetWindowPos(
            target, Some(HWND_BOTTOM), rect.x, rect.y, rect.w, rect.h,
            SWP_NOACTIVATE | SWP_SHOWWINDOW,
        )
        .map_err(|e| e.to_string())?;
    }
    let _ = HRGN::default(); // keep Gdi feature import used
    Ok(())
}
```

(Subagent note: `0xM00N` is obviously invalid — use `0x4D4Eusize` as the subclass id. windows-rs API shapes (BOOL vs bool, HWND field access, `SetWindowPos` Option param) vary by crate version — adapt to the version resolved in Task 2; behavior is the contract: enumerate child windows by class "mpv", WS_EX_TRANSPARENT + NCHITTEST→HTTRANSPARENT subclass, HWND_BOTTOM, SetWindowPos to mapped rect.)

- [ ] **Step 2: Tauri commands** — replace `src/player/mod.rs` content:

```rust
pub mod geometry;

#[cfg(windows)]
pub mod embed;
#[cfg(windows)]
pub mod thread;

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
```

- [ ] **Step 3: Register in `src/lib.rs`** — replace `run()` with:

```rust
pub mod deeplink;
pub mod player;

pub fn run() {
    let mut builder = tauri::Builder::default();

    #[cfg(desktop)]
    {
        builder = builder.plugin(tauri_plugin_single_instance::init(|app, _args, _cwd| {
            use tauri::Manager;
            if let Some(window) = app.get_webview_window("main") {
                let _ = window.set_focus();
            }
        }));
    }

    #[cfg(windows)]
    {
        builder = builder.setup(|app| {
            let (tx, rx) = std::sync::mpsc::channel();
            let handle = app.handle().clone();
            std::thread::Builder::new()
                .name("mpv-player".into())
                .spawn(move || player::thread::run(handle, rx))
                .expect("spawn player thread");
            use tauri::Manager;
            app.manage(player::PlayerState(parking_lot::Mutex::new(Some(tx))));
            Ok(())
        });
    }

    let builder = {
        #[cfg(windows)]
        {
            builder.invoke_handler(tauri::generate_handler![
                player::mpv_probe,
                player::mpv_start,
                player::mpv_stop,
                player::mpv_set_property,
                player::mpv_get_property,
                player::mpv_command,
                player::mpv_sub_add,
                player::mpv_screenshot,
                player::mpv_set_geometry,
                player::shader_dir,
            ])
        }
        #[cfg(not(windows))]
        {
            builder.invoke_handler(tauri::generate_handler![
                player::mpv_probe,
                player::mpv_start,
                player::mpv_stop,
            ])
        }
    };

    builder
        .plugin(tauri_plugin_deep_link::init())
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
```

- [ ] **Step 4: Capabilities** — in `capabilities/default.json`, extend permissions with:

```json
    "core:event:default",
    "core:window:allow-set-fullscreen",
    "core:window:allow-is-fullscreen",
    "core:window:allow-set-size",
    "core:window:allow-set-position",
    "core:window:allow-set-always-on-top",
    "core:window:allow-inner-size",
    "core:window:allow-outer-position"
```

- [ ] **Step 5: Verify (macOS: compile + tests; Windows verification lands in CI Task 13)**

Run (in `src-tauri/`): `cargo check && cargo test` — compiles, 7 tests pass.
Run (in `moonlit-web/`): `npm run tauri dev` — app still boots (stub commands on mac).

- [ ] **Step 6: Commit**

```bash
git add src-tauri/src src-tauri/capabilities/default.json
git commit -m "feat(desktop): mpv embedding, transparent webview, and player command surface"
```

---

### Task 6: JS bridge — `src/lib/platform/mpv.ts` (TDD for pure parts)

**Files:**
- Create: `moonlit-web/src/lib/platform/mpv.ts`
- Test: `moonlit-web/src/lib/platform/mpv.test.ts`

- [ ] **Step 1: Failing tests first** (`mpv.test.ts`)

```ts
import { describe, it, expect } from 'vitest';
import { reduceMpvEvent, initialMpvState, parseTrackList } from './mpv';

describe('reduceMpvEvent', () => {
  it('updates position and duration from property-change events', () => {
    let s = initialMpvState();
    s = reduceMpvEvent(s, { event: 'property-change', name: 'time-pos', data: 42.5 });
    s = reduceMpvEvent(s, { event: 'property-change', name: 'duration', data: 3600 });
    expect(s.position).toBe(42.5);
    expect(s.duration).toBe(3600);
  });

  it('tracks pause, mute, volume, speed', () => {
    let s = initialMpvState();
    s = reduceMpvEvent(s, { event: 'property-change', name: 'pause', data: true });
    s = reduceMpvEvent(s, { event: 'property-change', name: 'mute', data: true });
    s = reduceMpvEvent(s, { event: 'property-change', name: 'volume', data: 55 });
    s = reduceMpvEvent(s, { event: 'property-change', name: 'speed', data: 1.5 });
    expect(s).toMatchObject({ paused: true, muted: true, volume: 55, speed: 1.5 });
  });

  it('marks loaded on file-loaded and ended on end-file eof', () => {
    let s = reduceMpvEvent(initialMpvState(), { event: 'file-loaded' });
    expect(s.loaded).toBe(true);
    s = reduceMpvEvent(s, { event: 'end-file', reason: 'Eof' });
    expect(s.ended).toBe(true);
    expect(s.error).toBeNull();
  });

  it('captures end-file error reason as error', () => {
    const s = reduceMpvEvent(initialMpvState(), { event: 'end-file', reason: 'Error' });
    expect(s.error).toBe('Playback failed');
  });
});

describe('parseTrackList', () => {
  const raw = [
    { id: 1, type: 'video', selected: true, codec: 'hevc' },
    { id: 1, type: 'audio', selected: true, lang: 'eng', title: 'English 5.1', codec: 'eac3', 'demux-channel-count': 6 },
    { id: 2, type: 'audio', selected: false, lang: 'jpn', codec: 'aac' },
    { id: 1, type: 'sub', selected: false, lang: 'eng', title: 'Full', external: false },
  ];
  it('splits audio and subtitle tracks with selection state', () => {
    const t = parseTrackList(raw);
    expect(t.audio).toHaveLength(2);
    expect(t.subs).toHaveLength(1);
    expect(t.audio[0]).toMatchObject({ id: 1, lang: 'eng', selected: true });
    expect(t.audio[0].label).toContain('English 5.1');
  });
  it('handles non-array input gracefully', () => {
    expect(parseTrackList(null)).toEqual({ audio: [], subs: [] });
  });
});
```

- [ ] **Step 2: Run to verify failure** — `npx vitest run src/lib/platform` → FAIL (module missing).

- [ ] **Step 3: Implement `mpv.ts`**

```ts
import { isDesktop } from './index';

// ── Types ────────────────────────────────────────────────────────────────────
export interface MpvEvent {
  event: string;
  name?: string;
  data?: unknown;
  reason?: string;
  message?: string;
  level?: string;
  text?: string;
}

export interface MpvTrack {
  id: number;
  lang?: string;
  label: string;
  selected: boolean;
  external?: boolean;
}

export interface MpvState {
  position: number;
  duration: number;
  paused: boolean;
  muted: boolean;
  volume: number;
  speed: number;
  buffering: boolean;
  cacheTime: number;
  loaded: boolean;
  ended: boolean;
  error: string | null;
  subDelay: number;
  audioDelay: number;
  aspect: number | null;
  tracks: { audio: MpvTrack[]; subs: MpvTrack[] };
}

export function initialMpvState(): MpvState {
  return {
    position: 0, duration: 0, paused: false, muted: false, volume: 100, speed: 1,
    buffering: false, cacheTime: 0, loaded: false, ended: false, error: null,
    subDelay: 0, audioDelay: 0, aspect: null, tracks: { audio: [], subs: [] },
  };
}

// ── Pure reducers (tested) ───────────────────────────────────────────────────
export function parseTrackList(raw: unknown): MpvState['tracks'] {
  if (!Array.isArray(raw)) return { audio: [], subs: [] };
  const toTrack = (t: Record<string, unknown>): MpvTrack => {
    const lang = typeof t.lang === 'string' ? t.lang : undefined;
    const title = typeof t.title === 'string' ? t.title : undefined;
    const codec = typeof t.codec === 'string' ? t.codec : undefined;
    const parts = [title ?? lang ?? `Track ${t.id}`, codec?.toUpperCase()].filter(Boolean);
    return {
      id: Number(t.id),
      lang,
      label: parts.join(' · '),
      selected: t.selected === true,
      external: t.external === true,
    };
  };
  const items = raw as Record<string, unknown>[];
  return {
    audio: items.filter((t) => t.type === 'audio').map(toTrack),
    subs: items.filter((t) => t.type === 'sub').map(toTrack),
  };
}

export function reduceMpvEvent(state: MpvState, ev: MpvEvent): MpvState {
  switch (ev.event) {
    case 'property-change': {
      const d = ev.data;
      switch (ev.name) {
        case 'time-pos': return typeof d === 'number' ? { ...state, position: d } : state;
        case 'duration': return typeof d === 'number' ? { ...state, duration: d } : state;
        case 'pause': return { ...state, paused: d === true };
        case 'mute': return { ...state, muted: d === true };
        case 'volume': return typeof d === 'number' ? { ...state, volume: d } : state;
        case 'speed': return typeof d === 'number' ? { ...state, speed: d } : state;
        case 'sub-delay': return typeof d === 'number' ? { ...state, subDelay: d } : state;
        case 'audio-delay': return typeof d === 'number' ? { ...state, audioDelay: d } : state;
        case 'demuxer-cache-time': return typeof d === 'number' ? { ...state, cacheTime: d } : state;
        case 'paused-for-cache': return { ...state, buffering: d === true };
        case 'video-params/aspect': return typeof d === 'number' ? { ...state, aspect: d } : state;
        case 'track-list': return { ...state, tracks: parseTrackList(d) };
        case 'eof-reached': return d === true ? { ...state, ended: true } : state;
        default: return state;
      }
    }
    case 'file-loaded': return { ...state, loaded: true, ended: false, error: null };
    case 'end-file':
      if (ev.reason && /error/i.test(ev.reason)) return { ...state, error: 'Playback failed' };
      return { ...state, ended: true };
    case 'error': return { ...state, error: ev.message ?? 'Playback failed' };
    default: return state;
  }
}

// ── Command bridge (thin adapters, exercised at runtime) ─────────────────────
async function invoke<T>(cmd: string, args?: Record<string, unknown>): Promise<T> {
  const { invoke } = await import('@tauri-apps/api/core');
  return invoke<T>(cmd, args);
}

export const mpv = {
  probe: () => invoke<{ available: boolean; reason: string | null }>('mpv_probe'),
  start: (payload: { url: string; startAtSec?: number; headers?: Record<string, string> }) =>
    invoke<void>('mpv_start', { payload }),
  stop: () => invoke<void>('mpv_stop'),
  setProp: (name: string, value: unknown) => invoke<void>('mpv_set_property', { name, value }),
  getProp: <T = unknown>(name: string) => invoke<T>('mpv_get_property', { name }),
  command: (parts: string[]) => invoke<void>('mpv_command', { parts }),
  subAdd: (url: string, opts?: { title?: string; lang?: string; select?: boolean }) =>
    invoke<void>('mpv_sub_add', { url, ...opts }),
  screenshot: (path: string) => invoke<string>('mpv_screenshot', { path }),
  setGeometry: (css: {
    cssLeft: number; cssTop: number; cssWidth: number; cssHeight: number;
    cssViewW: number; cssViewH: number;
  }) => invoke<void>('mpv_set_geometry', { css }),
  shaderDir: () => invoke<string>('shader_dir'),
};

export async function onMpvEvent(handler: (ev: MpvEvent) => void): Promise<() => void> {
  if (!isDesktop()) return () => {};
  const { listen } = await import('@tauri-apps/api/event');
  return listen<MpvEvent>('mpv://event', (e) => handler(e.payload));
}

let probeCache: Promise<boolean> | null = null;
export function mpvAvailable(): Promise<boolean> {
  if (!isDesktop()) return Promise.resolve(false);
  probeCache ??= mpv.probe().then((p) => p.available).catch(() => false);
  return probeCache;
}
```

- [ ] **Step 4: Verify** — `npx vitest run src/lib/platform` → all pass; `npm run typecheck` → exit 0.

- [ ] **Step 5: Commit**

```bash
git add src/lib/platform/mpv.ts src/lib/platform/mpv.test.ts
git commit -m "feat(desktop): typed mpv bridge with tested event reducer and track parsing"
```

---

### Task 7: Subtitle styling map (TDD)

**Files:**
- Create: `moonlit-web/src/lib/platform/mpv-subtitle-style.ts`
- Test: `moonlit-web/src/lib/platform/mpv-subtitle-style.test.ts`

- [ ] **Step 1: Failing test**

```ts
import { describe, it, expect } from 'vitest';
import { subtitlePrefsToMpvProps } from './mpv-subtitle-style';

describe('subtitlePrefsToMpvProps', () => {
  it('maps defaults to mpv properties', () => {
    const props = subtitlePrefsToMpvProps({ size: 'medium', color: 'white', backgroundOpacity: 70, position: 'low' });
    expect(props['sub-font-size']).toBe(38);
    expect(props['sub-color']).toBe('#FFFFFF');
    expect(props['sub-back-color']).toBe('#000000B3'); // 70% alpha ≈ B3
    expect(props['sub-pos']).toBe(98);
  });
  it('maps size/color/position variants', () => {
    const props = subtitlePrefsToMpvProps({ size: 'xlarge', color: 'yellow', backgroundOpacity: 0, position: 'high' });
    expect(props['sub-font-size']).toBe(55);
    expect(props['sub-color']).toBe('#FFD54A');
    expect(props['sub-back-color']).toBe('#00000000');
    expect(props['sub-pos']).toBe(60);
  });
});
```

- [ ] **Step 2: Run** — fails (module missing).

- [ ] **Step 3: Implement**

```ts
import type { SubtitlePreferences } from '@/lib/subtitle-preferences';

const SIZE_PT: Record<SubtitlePreferences['size'], number> = {
  small: 30, medium: 38, large: 46, xlarge: 55,
};
const COLOR_HEX: Record<SubtitlePreferences['color'], string> = {
  white: '#FFFFFF', yellow: '#FFD54A', cyan: '#4AD8FF', green: '#4AFF6A',
};
const POSITION_PCT: Record<SubtitlePreferences['position'], number> = {
  low: 98, medium: 80, high: 60,
};

/** Map web SubtitlePreferences to mpv sub-* properties. */
export function subtitlePrefsToMpvProps(p: SubtitlePreferences): Record<string, string | number> {
  const alpha = Math.round((p.backgroundOpacity / 100) * 255)
    .toString(16).padStart(2, '0').toUpperCase();
  return {
    'sub-font-size': SIZE_PT[p.size],
    'sub-color': COLOR_HEX[p.color],
    'sub-back-color': `#000000${alpha}`,
    'sub-pos': POSITION_PCT[p.position],
    'sub-border-size': 1.5,
    'sub-border-color': '#000000',
  };
}
```

- [ ] **Step 4: Verify + commit**

`npx vitest run src/lib/platform` → pass.
```bash
git add src/lib/platform/mpv-subtitle-style.ts src/lib/platform/mpv-subtitle-style.test.ts
git commit -m "feat(desktop): subtitle preference to mpv property mapping"
```

---

### Task 8: Desktop stream selection (TDD)

**Files:**
- Create: `moonlit-web/src/lib/platform/desktop-selection.ts`
- Test: `moonlit-web/src/lib/platform/desktop-selection.test.ts`

Desktop bypasses browser-codec scoring: mpv plays HEVC/DTS/MKV natively. Only exclude infoHash-only streams (no torrent engine) and honor last-stream + 4K preference.

- [ ] **Step 1: Failing tests**

```ts
import { describe, it, expect } from 'vitest';
import { sortStreamsForDesktop, pickDesktopStream } from './desktop-selection';
import type { StreamItem } from '@/lib/types';

const s = (over: Partial<StreamItem>): StreamItem => ({ name: 'x', ...over });

describe('sortStreamsForDesktop', () => {
  it('excludes torrent/infohash-only streams', () => {
    const out = sortStreamsForDesktop([s({ infoHash: 'abc' }), s({ url: 'http://a/1.mkv' })], false);
    expect(out).toHaveLength(1);
    expect(out[0].url).toBe('http://a/1.mkv');
  });
  it('ranks 4K first when prefer4K, else 1080p first', () => {
    const streams = [
      s({ url: 'http://a/1080.mkv', title: '1080p BluRay' }),
      s({ url: 'http://a/2160.mkv', title: '4K 2160p REMUX' }),
    ];
    expect(sortStreamsForDesktop(streams, true)[0].url).toContain('2160');
    expect(sortStreamsForDesktop(streams, false)[0].url).toContain('1080');
  });
});

describe('pickDesktopStream', () => {
  it('prefers the last-played url when present', () => {
    const streams = [s({ url: 'http://a/1' }), s({ url: 'http://a/2' })];
    expect(pickDesktopStream(streams, 'http://a/2')?.url).toBe('http://a/2');
  });
  it('falls back to first sorted stream', () => {
    const streams = [s({ url: 'http://a/1' })];
    expect(pickDesktopStream(streams, null)?.url).toBe('http://a/1');
  });
});
```

- [ ] **Step 2: Run** — fails.

- [ ] **Step 3: Implement**

```ts
import type { StreamItem } from '@/lib/types';
import { getStreamUrl } from '@/lib/player-utils';

function resolutionScore(text: string): number {
  if (/2160p|4k|uhd/i.test(text)) return 4;
  if (/1080p/i.test(text)) return 3;
  if (/720p/i.test(text)) return 2;
  return 1;
}

function streamText(s: StreamItem): string {
  return [s.name, s.title, s.description, s.behaviorHints?.filename].filter(Boolean).join(' ');
}

/** Desktop sort: mpv decodes anything, so rank purely on resolution
 *  (honoring the 4K preference) and drop torrent-only entries. */
export function sortStreamsForDesktop(streams: StreamItem[], prefer4K: boolean): StreamItem[] {
  return streams
    .filter((s) => Boolean(getStreamUrl(s)))
    .map((s) => {
      const res = resolutionScore(streamText(s));
      const score = prefer4K ? res : res === 4 ? 2.5 : res;
      return { s, score };
    })
    .sort((a, b) => b.score - a.score)
    .map(({ s }) => s);
}

export function pickDesktopStream(sorted: StreamItem[], lastUrl: string | null): StreamItem | null {
  if (lastUrl) {
    const match = sorted.find((s) => getStreamUrl(s) === lastUrl);
    if (match) return match;
  }
  return sorted[0] ?? null;
}

const PREF_KEY = 'moonlit.desktop.prefer4k';
export function getPrefer4K(): boolean {
  try { return localStorage.getItem(PREF_KEY) === '1'; } catch { return false; }
}
export function setPrefer4K(v: boolean): void {
  try { localStorage.setItem(PREF_KEY, v ? '1' : '0'); } catch { /* ignore */ }
}
```

- [ ] **Step 4: Verify + commit**

```bash
npx vitest run src/lib/platform && npm run typecheck
git add src/lib/platform/desktop-selection.ts src/lib/platform/desktop-selection.test.ts
git commit -m "feat(desktop): desktop stream ranking with 4K preference and last-source pickup"
```

---

### Task 9: MpvPlayer component — core playback, controls, hotkeys, progress sync

**Files:**
- Create: `moonlit-web/src/components/player/MpvPlayer.tsx`
- Create: `moonlit-web/src/components/player/ResumePrompt.tsx`
- Create: `moonlit-web/src/components/player/StreamCheckPill.tsx`

This is the largest UI task. Contract with PlayerShell (Task 10): same props as web `Player` (`PlayerProps` in `Player.tsx:36-49`).

- [ ] **Step 1: Create `ResumePrompt.tsx`**

```tsx
import { useEffect, useState } from 'react';

export function ResumePrompt({ seconds, onStartOver }: { seconds: number; onStartOver: () => void }) {
  const [visible, setVisible] = useState(true);
  useEffect(() => {
    const t = setTimeout(() => setVisible(false), 8000);
    return () => clearTimeout(t);
  }, []);
  if (!visible || seconds < 10) return null;
  const m = Math.floor(seconds / 60);
  const s = Math.floor(seconds % 60).toString().padStart(2, '0');
  return (
    <div className="absolute bottom-28 left-1/2 -translate-x-1/2 z-20 flex items-center gap-3 rounded-full bg-black/70 border border-white/10 px-4 py-2 text-[13px] text-white/85">
      <span>Resuming from {m}:{s}</span>
      <button
        type="button"
        onClick={() => { setVisible(false); onStartOver(); }}
        className="font-bold text-white hover:underline"
      >
        Start over
      </button>
    </div>
  );
}
```

- [ ] **Step 2: Create `StreamCheckPill.tsx`**

```tsx
import { useEffect, useState } from 'react';

export function StreamCheckPill({ onPickAnother }: { onPickAnother: () => void }) {
  const [phase, setPhase] = useState<'hidden' | 'shown'>('hidden');
  useEffect(() => {
    const show = setTimeout(() => setPhase('shown'), 4000);
    const hide = setTimeout(() => setPhase('hidden'), 13000);
    return () => { clearTimeout(show); clearTimeout(hide); };
  }, []);
  if (phase !== 'shown') return null;
  return (
    <div className="absolute top-20 left-1/2 -translate-x-1/2 z-20 flex items-center gap-3 rounded-full bg-black/70 border border-white/10 px-4 py-2 text-[13px] text-white/85">
      <span>Does this look right?</span>
      <button type="button" onClick={onPickAnother} className="font-bold text-white hover:underline">
        Pick another source
      </button>
    </div>
  );
}
```

- [ ] **Step 3: Create `MpvPlayer.tsx`**

```tsx
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  ArrowLeft, Camera, Captions, ListVideo, Maximize, Minimize, Pause, Play,
  PictureInPicture2, RotateCcw, RotateCw, SkipBack, SkipForward, Volume2, VolumeX,
} from 'lucide-react';
import { mpv, onMpvEvent, initialMpvState, reduceMpvEvent, type MpvState } from '@/lib/platform/mpv';
import { getStreamUrl } from '@/lib/player-utils';
import { updateWatchProgress } from '@/lib/services/api';
import { useAuth } from '@/app/AuthProvider';
import { saveLastStream } from '@/lib/last-stream';
import { loadSubtitlePreferences } from '@/lib/subtitle-preferences';
import { subtitlePrefsToMpvProps } from '@/lib/platform/mpv-subtitle-style';
import type { StreamItem, SubtitleItem } from '@/lib/types';
import { SkipIntroOverlay } from './SkipIntroOverlay';
import { MpvTracksPanel } from './MpvTracksPanel';
import { UpNextPanel } from './UpNextPanel';
import { ResumePrompt } from './ResumePrompt';
import { StreamCheckPill } from './StreamCheckPill';

interface MpvPlayerProps {
  streamUrl: string;
  streams: StreamItem[];
  currentStream: StreamItem;
  title: string;
  mediaLogo?: string;
  mediaId: string;
  mediaType: string;
  startPosition?: number;
  subtitles?: SubtitleItem[];
  onSwitchStream: (stream: StreamItem) => void;
  onOpenSources: () => void;
  onBack: () => void;
}

function fmt(t: number): string {
  if (!Number.isFinite(t) || t < 0) t = 0;
  const h = Math.floor(t / 3600);
  const m = Math.floor((t % 3600) / 60);
  const s = Math.floor(t % 60);
  return h > 0
    ? `${h}:${m.toString().padStart(2, '0')}:${s.toString().padStart(2, '0')}`
    : `${m}:${s.toString().padStart(2, '0')}`;
}

const SPEEDS = [0.25, 0.5, 0.75, 1, 1.25, 1.5, 2];

export function MpvPlayer(props: MpvPlayerProps) {
  const { currentProfile } = useAuth();
  const [state, setState] = useState<MpvState>(initialMpvState);
  const stateRef = useRef(state);
  stateRef.current = state;

  const [controlsVisible, setControlsVisible] = useState(true);
  const [panel, setPanel] = useState<null | 'tracks' | 'speed' | 'upnext'>(null);
  const [isFullscreen, setIsFullscreen] = useState(false);
  const [isPip, setIsPip] = useState(false);
  const hideTimer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const triedFallback = useRef(new Set<string>());

  // ── Lifecycle: start/stop mpv with the stream URL ──────────────────────────
  useEffect(() => {
    let unlisten: (() => void) | undefined;
    let cancelled = false;
    (async () => {
      unlisten = await onMpvEvent((ev) => {
        if (!cancelled) setState((s) => reduceMpvEvent(s, ev));
      });
      const headers = props.currentStream.behaviorHints?.proxyHeaders?.request;
      await mpv.start({ url: props.streamUrl, startAtSec: props.startPosition, headers });
      // Geometry: video fills the window; the overlay is full-viewport.
      const sync = () =>
        mpv.setGeometry({
          cssLeft: 0, cssTop: 0,
          cssWidth: window.innerWidth, cssHeight: window.innerHeight,
          cssViewW: window.innerWidth, cssViewH: window.innerHeight,
        }).catch(() => {});
      // mpv child window appears shortly after start; retry a few times.
      const retries = [200, 600, 1500, 3000].map((ms) => setTimeout(sync, ms));
      window.addEventListener('resize', sync);
      (sync as unknown as { cleanup?: () => void }).cleanup = () => {
        retries.forEach(clearTimeout);
        window.removeEventListener('resize', sync);
      };
    })();
    return () => {
      cancelled = true;
      unlisten?.();
      mpv.stop().catch(() => {});
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [props.streamUrl]);

  // ── Apply subtitle appearance + load external subs after file loads ────────
  useEffect(() => {
    if (!state.loaded) return;
    const prefs = subtitlePrefsToMpvProps(loadSubtitlePreferences());
    for (const [k, v] of Object.entries(prefs)) mpv.setProp(k, v).catch(() => {});
    saveLastStream(props.mediaId, {
      url: props.streamUrl,
      addonName: props.currentStream.addonName,
      streamTitle: props.currentStream.title,
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [state.loaded]);

  // ── Progress sync every 10s and on unmount/end ─────────────────────────────
  const report = useCallback(
    (completed: boolean) => {
      const s = stateRef.current;
      if (!currentProfile || s.duration <= 0) return;
      updateWatchProgress(
        currentProfile.id, props.mediaId, props.mediaType,
        s.position, s.duration, completed, props.title,
      ).catch(() => {});
    },
    [currentProfile, props.mediaId, props.mediaType, props.title],
  );
  useEffect(() => {
    const t = setInterval(() => report(false), 10_000);
    return () => { clearInterval(t); report(false); };
  }, [report]);
  useEffect(() => {
    if (state.ended) report(true);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [state.ended]);

  // ── Auto-fallback to next source on error ──────────────────────────────────
  useEffect(() => {
    if (!state.error) return;
    triedFallback.current.add(props.streamUrl);
    const next = props.streams.find((s) => {
      const u = getStreamUrl(s);
      return u && !triedFallback.current.has(u);
    });
    if (next) props.onSwitchStream(next);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [state.error]);

  // ── Controls auto-hide ─────────────────────────────────────────────────────
  const poke = useCallback(() => {
    setControlsVisible(true);
    clearTimeout(hideTimer.current);
    hideTimer.current = setTimeout(() => setControlsVisible(false), 3500);
  }, []);
  useEffect(() => { poke(); return () => clearTimeout(hideTimer.current); }, [poke]);

  // ── Actions ────────────────────────────────────────────────────────────────
  const togglePause = () => mpv.setProp('pause', !stateRef.current.paused);
  const seekBy = (d: number) => mpv.command(['seek', String(d), 'relative']);
  const seekTo = (t: number) => mpv.command(['seek', String(t), 'absolute']);
  const setVolume = (v: number) => mpv.setProp('volume', Math.max(0, Math.min(130, v)));
  const toggleMute = () => mpv.setProp('mute', !stateRef.current.muted);
  const cycleSubs = () => mpv.command(['cycle', 'sid']);
  const toggleFullscreen = async () => {
    const { getCurrentWindow } = await import('@tauri-apps/api/window');
    const w = getCurrentWindow();
    const fs = await w.isFullscreen();
    await w.setFullscreen(!fs);
    setIsFullscreen(!fs);
  };
  const togglePip = async () => {
    const { getCurrentWindow, LogicalSize, LogicalPosition } = await import('@tauri-apps/api/window');
    const w = getCurrentWindow();
    if (!isPip) {
      await w.setAlwaysOnTop(true);
      await w.setSize(new LogicalSize(480, 270));
      await w.setPosition(new LogicalPosition(window.screen.availWidth - 500, window.screen.availHeight - 320));
    } else {
      await w.setAlwaysOnTop(false);
      await w.setSize(new LogicalSize(1200, 800));
    }
    setIsPip(!isPip);
  };
  const takeScreenshot = async () => {
    const name = `Moonlit ${new Date().toISOString().replace(/[:.]/g, '-')}.png`;
    const { join, pictureDir } = await import('@tauri-apps/api/path');
    const dir = await join(await pictureDir(), 'Moonlit Screenshots');
    // mpv creates the file; ensure dir via screenshot path convention
    await mpv.setProp('screenshot-directory', dir).catch(() => {});
    await mpv.screenshot(await join(dir, name)).catch(() => {});
  };

  // ── Hotkeys: Space ←→ ↑↓ F M C ─────────────────────────────────────────────
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if ((e.target as HTMLElement)?.tagName === 'INPUT') return;
      switch (e.key) {
        case ' ': e.preventDefault(); togglePause(); break;
        case 'ArrowLeft': seekBy(-5); break;
        case 'ArrowRight': seekBy(5); break;
        case 'ArrowUp': setVolume(stateRef.current.volume + 5); break;
        case 'ArrowDown': setVolume(stateRef.current.volume - 5); break;
        case 'f': case 'F': toggleFullscreen(); break;
        case 'm': case 'M': toggleMute(); break;
        case 'c': case 'C': cycleSubs(); break;
        default: return;
      }
      poke();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const progress = state.duration > 0 ? (state.position / state.duration) * 100 : 0;
  const buffered = state.duration > 0 ? (Math.max(state.cacheTime, state.position) / state.duration) * 100 : 0;
  const imdbBase = useMemo(() => props.mediaId.split(':')[0], [props.mediaId]);

  return (
    <div className="absolute inset-0 bg-transparent" onMouseMove={poke} onClick={poke}>
      {/* Video renders in the native mpv HWND behind the transparent WebView */}

      {!state.loaded && !state.error && (
        <div className="absolute inset-0 z-10 flex items-center justify-center bg-black">
          <div className="text-white/70 text-sm animate-pulse">Loading stream…</div>
        </div>
      )}

      {state.loaded && props.startPosition != null && props.startPosition >= 10 && (
        <ResumePrompt seconds={props.startPosition} onStartOver={() => seekTo(0)} />
      )}
      {state.loaded && <StreamCheckPill onPickAnother={props.onOpenSources} />}
      {state.loaded && (
        <SkipIntroOverlay
          imdbId={imdbBase}
          mediaId={props.mediaId}
          currentTime={state.position}
          onSkip={(to: number) => seekTo(to)}
        />
      )}

      {/* Chrome */}
      <div
        className={`absolute inset-x-0 top-0 z-20 flex items-center justify-between px-4 py-3 transition-opacity duration-200 ${controlsVisible ? 'opacity-100' : 'opacity-0 pointer-events-none'}`}
        style={{ background: 'linear-gradient(to bottom, rgba(0,0,0,0.75), transparent)' }}
      >
        <button type="button" onClick={props.onBack} className="flex items-center gap-2 text-white/85 hover:text-white">
          <ArrowLeft size={20} aria-hidden /> <span className="text-[13px] font-semibold">Back</span>
        </button>
        <div className="text-[13px] font-semibold text-white/85 truncate max-w-[50%]">{props.title}</div>
        <div className="flex items-center gap-1">
          <IconBtn label="Screenshot" onClick={takeScreenshot}><Camera size={17} aria-hidden /></IconBtn>
          <IconBtn label="Picture in picture" onClick={togglePip}><PictureInPicture2 size={17} aria-hidden /></IconBtn>
          <IconBtn label="Sources" onClick={props.onOpenSources}><ListVideo size={17} aria-hidden /></IconBtn>
        </div>
      </div>

      <div
        className={`absolute inset-x-0 bottom-0 z-20 px-5 pb-4 pt-10 transition-opacity duration-200 ${controlsVisible ? 'opacity-100' : 'opacity-0 pointer-events-none'}`}
        style={{ background: 'linear-gradient(to top, rgba(0,0,0,0.8), transparent)' }}
      >
        {/* Scrubber */}
        <div
          className="group relative h-4 flex items-center cursor-pointer"
          onClick={(e) => {
            const r = (e.currentTarget as HTMLElement).getBoundingClientRect();
            seekTo(((e.clientX - r.left) / r.width) * stateRef.current.duration);
          }}
        >
          <div className="relative w-full h-1 group-hover:h-[5px] rounded-full bg-white/20 transition-all">
            <div className="absolute inset-y-0 left-0 rounded-full bg-white/30" style={{ width: `${buffered}%` }} />
            <div className="absolute inset-y-0 left-0 rounded-full bg-white" style={{ width: `${progress}%` }} />
          </div>
        </div>

        <div className="mt-2 flex items-center gap-4">
          <IconBtn label="Skip back 15 seconds" onClick={() => seekBy(-15)}><RotateCcw size={20} aria-hidden /></IconBtn>
          <IconBtn label={state.paused ? 'Play' : 'Pause'} onClick={togglePause} big>
            {state.paused ? <Play size={26} aria-hidden /> : <Pause size={26} aria-hidden />}
          </IconBtn>
          <IconBtn label="Skip forward 15 seconds" onClick={() => seekBy(15)}><RotateCw size={20} aria-hidden /></IconBtn>

          <span className="font-mono text-[12px] text-white/70 tabular-nums">
            {fmt(state.position)} / {fmt(state.duration)}
          </span>

          <div className="ml-auto flex items-center gap-2">
            <IconBtn label={state.muted ? 'Unmute' : 'Mute'} onClick={toggleMute}>
              {state.muted ? <VolumeX size={18} aria-hidden /> : <Volume2 size={18} aria-hidden />}
            </IconBtn>
            <input
              type="range" min={0} max={130} value={Math.round(state.volume)}
              onChange={(e) => setVolume(Number(e.target.value))}
              className="w-24 accent-white" aria-label="Volume"
            />
            <button
              type="button"
              onClick={() => setPanel(panel === 'speed' ? null : 'speed')}
              className="rounded-md bg-white/10 px-2 py-1 text-[12px] font-semibold text-white/85 hover:bg-white/15"
            >
              {state.speed.toFixed(2).replace(/0$/, '')}x
            </button>
            <IconBtn label="Audio and subtitles" onClick={() => setPanel(panel === 'tracks' ? null : 'tracks')}>
              <Captions size={18} aria-hidden />
            </IconBtn>
            {props.mediaType === 'series' && (
              <>
                <IconBtn label="Previous episode" onClick={() => window.dispatchEvent(new CustomEvent('moonlit:episode-nav', { detail: -1 }))}><SkipBack size={18} aria-hidden /></IconBtn>
                <IconBtn label="Up next" onClick={() => setPanel(panel === 'upnext' ? null : 'upnext')}><SkipForward size={18} aria-hidden /></IconBtn>
              </>
            )}
            <IconBtn label={isFullscreen ? 'Exit fullscreen' : 'Fullscreen'} onClick={toggleFullscreen}>
              {isFullscreen ? <Minimize size={18} aria-hidden /> : <Maximize size={18} aria-hidden />}
            </IconBtn>
          </div>
        </div>
      </div>

      {panel === 'speed' && (
        <div className="absolute bottom-20 right-6 z-30 rounded-2xl bg-[#141414] border border-white/10 p-2">
          {SPEEDS.map((sp) => (
            <button
              key={sp} type="button"
              onClick={() => { mpv.setProp('speed', sp); setPanel(null); }}
              className={`block w-full rounded-lg px-4 py-1.5 text-left text-[13px] ${state.speed === sp ? 'bg-white text-black font-bold' : 'text-white/80 hover:bg-white/10'}`}
            >
              {sp}x
            </button>
          ))}
        </div>
      )}

      {panel === 'tracks' && (
        <MpvTracksPanel
          state={state}
          externalSubtitles={props.subtitles ?? []}
          onClose={() => setPanel(null)}
        />
      )}

      {panel === 'upnext' && (
        <UpNextPanel
          mediaId={props.mediaId}
          mediaType={props.mediaType}
          onClose={() => setPanel(null)}
        />
      )}

      {state.error && !props.streams.some((s) => { const u = getStreamUrl(s); return u && !triedFallback.current.has(u); }) && (
        <div className="absolute inset-0 z-30 flex flex-col items-center justify-center gap-4 bg-black">
          <div className="text-white text-lg font-bold">Playback failed</div>
          <div className="text-white/60 text-sm">All sources were tried.</div>
          <div className="flex gap-3">
            <button type="button" onClick={props.onOpenSources} className="rounded-full bg-white px-5 py-2 text-[13px] font-bold text-black">Choose source</button>
            <button type="button" onClick={props.onBack} className="rounded-full bg-white/10 px-5 py-2 text-[13px] font-bold text-white">Back</button>
          </div>
        </div>
      )}
    </div>
  );
}

function IconBtn({ label, onClick, children, big }: {
  label: string; onClick: () => void; children: React.ReactNode; big?: boolean;
}) {
  return (
    <button
      type="button" aria-label={label} onClick={onClick}
      className={`${big ? 'w-12 h-12' : 'w-9 h-9'} rounded-full flex items-center justify-center text-white/85 hover:text-white hover:bg-white/10 focus-visible:ring-2 focus-visible:ring-white/50 focus-visible:outline-none`}
    >
      {children}
    </button>
  );
}
```

Note for implementer: `SkipIntroOverlay` props — read `src/components/player/SkipIntroOverlay.tsx` first and adapt the usage to its ACTUAL prop interface (research says it takes intro timestamps from publicmeta with fallback skip; wire `currentTime` + a seek callback per its real API). Same for `updateWatchProgress` arity — match `src/lib/services/api.ts:95` exactly. If `LoadCard` fits better than the inline loading div, reuse it.

- [ ] **Step 4: Verify** — `npx vitest run && npm run typecheck` (MpvTracksPanel/UpNextPanel don't exist yet — create minimal placeholder files in this task if needed for typecheck, then they're fully implemented in Tasks 11/12; OR implement Tasks 9, 11, 12 before running typecheck and commit together. Prefer: create the two components as minimal stubs here, replaced in their tasks).

Minimal stubs:

```tsx
// MpvTracksPanel.tsx (stub — fully implemented in Task 11)
import type { MpvState } from '@/lib/platform/mpv';
import type { SubtitleItem } from '@/lib/types';
export function MpvTracksPanel(_: { state: MpvState; externalSubtitles: SubtitleItem[]; onClose: () => void }) {
  return null;
}
```

```tsx
// UpNextPanel.tsx (stub — fully implemented in Task 12)
export function UpNextPanel(_: { mediaId: string; mediaType: string; onClose: () => void }) {
  return null;
}
```

- [ ] **Step 5: Commit**

```bash
git add src/components/player/MpvPlayer.tsx src/components/player/ResumePrompt.tsx src/components/player/StreamCheckPill.tsx src/components/player/MpvTracksPanel.tsx src/components/player/UpNextPanel.tsx
git commit -m "feat(desktop): MpvPlayer core with controls, hotkeys, progress sync, and auto-fallback"
```

---

### Task 10: PlayerShell dispatch + transparent overlay for mpv

**Files:**
- Modify: `moonlit-web/src/components/player/PlayerShell.tsx`
- Modify: `moonlit-web/src/components/PlayerOverlay.tsx`
- Modify: `moonlit-web/src/components/player/PlayerShell.stream.ts` (if PlayerType union lives there)
- Test: extend `moonlit-web/src/components/player/PlayerShell.stream.test.ts`

- [ ] **Step 1: Failing test** — add to `PlayerShell.stream.test.ts`:

```ts
import { shouldUseMpv } from './PlayerShell.stream';

describe('shouldUseMpv', () => {
  it('uses mpv when desktop probe is available', () => {
    expect(shouldUseMpv(true)).toBe(true);
    expect(shouldUseMpv(false)).toBe(false);
  });
});
```

- [ ] **Step 2: Implement** — in `PlayerShell.stream.ts`:
  - extend `export type PlayerType = 'vidstack' | 'mediabunny' | 'webcodecs' | 'mpv';`
  - add `export function shouldUseMpv(mpvAvailable: boolean): boolean { return mpvAvailable; }`

- [ ] **Step 3: Wire dispatch in `PlayerShell.tsx`** (read the file first; integrate following its existing phase state machine):
  - On mount, `mpvAvailable()` (from `@/lib/platform/mpv`) → state `useMpv`.
  - When `useMpv`: skip `sortStreamsForBrowserPlayback` + preflight; use `sortStreamsForDesktop(streams, getPrefer4K())` + `pickDesktopStream(sorted, getLastStream(mediaId)?.url ?? null)` from `@/lib/platform/desktop-selection`; use the raw stream URL (`getStreamUrl`) — no proxy, no remux (mpv fetches directly, no CORS).
  - Dispatch `playerType === 'mpv'` → render `<MpvPlayer …/>` with the same data the vidstack branch gets, plus `onOpenSources` opening the existing SourcesPanel path, and `onSwitchStream={switchStream}` from the player context.
  - Keep subtitle fetch (`fetchSubtitlesFromAll`) — pass RAW subtitle URLs to MpvPlayer (strip the `/api/stremio/vtt?url=` proxy wrapper if PlayerShell adds it; mpv reads SRT natively).

- [ ] **Step 4: Transparent overlay** — in `PlayerOverlay.tsx`: when active player type is mpv, the overlay container class must be `bg-transparent` instead of `bg-black` (video is behind the WebView). Read the file; thread a `transparent` flag from PlayerShell via context or prop. Also suppress the LoadingCard 'video element' assumptions — gate `onVideoReady` on MpvPlayer's `file-loaded` (have MpvPlayer call an optional `onReady?: () => void` prop when `state.loaded` flips true; add that prop and call it).

- [ ] **Step 5: Verify + commit**

```bash
npx vitest run && npm run typecheck
git add src/components/player src/components/PlayerOverlay.tsx
git commit -m "feat(desktop): dispatch mpv player type on desktop with transparent overlay"
```

---

### Task 11: MpvTracksPanel — audio/sub selection, delays, external subs, styling

**Files:**
- Replace stub: `moonlit-web/src/components/player/MpvTracksPanel.tsx`

- [ ] **Step 1: Implement the panel** (full replacement of the stub)

```tsx
import { useState } from 'react';
import { X } from 'lucide-react';
import { mpv, type MpvState } from '@/lib/platform/mpv';
import type { SubtitleItem } from '@/lib/types';
import {
  loadSubtitlePreferences, saveSubtitlePreferences, type SubtitlePreferences,
} from '@/lib/subtitle-preferences';
import { subtitlePrefsToMpvProps } from '@/lib/platform/mpv-subtitle-style';

export function MpvTracksPanel({ state, externalSubtitles, onClose }: {
  state: MpvState;
  externalSubtitles: SubtitleItem[];
  onClose: () => void;
}) {
  const [tab, setTab] = useState<'audio' | 'subtitles'>('subtitles');
  const [prefs, setPrefs] = useState<SubtitlePreferences>(loadSubtitlePreferences);
  const [addedExternal, setAddedExternal] = useState<Set<string>>(new Set());

  const applyPrefs = (next: SubtitlePreferences) => {
    setPrefs(next);
    saveSubtitlePreferences(next);
    for (const [k, v] of Object.entries(subtitlePrefsToMpvProps(next))) {
      mpv.setProp(k, v).catch(() => {});
    }
  };

  const selectAudio = (id: number) => mpv.setProp('aid', id);
  const selectSub = (id: number | 'no') => mpv.setProp('sid', id === 'no' ? 'no' : id);
  const addExternal = (sub: SubtitleItem) => {
    mpv.subAdd(sub.url, { title: sub.name ?? sub.lang, lang: sub.lang, select: true }).catch(() => {});
    setAddedExternal((s) => new Set(s).add(sub.url));
  };

  const Row = ({ selected, label, onClick }: { selected: boolean; label: string; onClick: () => void }) => (
    <button
      type="button" onClick={onClick}
      className={`flex w-full items-center gap-3 rounded-lg px-3 py-2 text-left text-[13px] ${selected ? 'bg-white/15 text-white font-semibold' : 'text-white/75 hover:bg-white/8'}`}
    >
      <span className={`h-3.5 w-3.5 rounded-full border ${selected ? 'border-white bg-white' : 'border-white/40'}`} />
      <span className="truncate">{label}</span>
    </button>
  );

  const DelaySlider = ({ label, value, prop }: { label: string; value: number; prop: 'sub-delay' | 'audio-delay' }) => (
    <div className="px-3 py-2">
      <div className="flex justify-between text-[11px] text-white/50">
        <span>{label}</span><span>{value.toFixed(1)}s</span>
      </div>
      <input
        type="range" min={-10} max={10} step={0.1} value={value}
        onChange={(e) => mpv.setProp(prop, Number(e.target.value))}
        className="w-full accent-white" aria-label={label}
      />
    </div>
  );

  return (
    <div className="absolute bottom-20 right-6 z-30 w-[340px] max-h-[70vh] overflow-y-auto rounded-2xl bg-[#141414] border border-white/10 p-3">
      <div className="flex items-center justify-between pb-2">
        <div className="flex rounded-xl bg-white/[0.07] p-1">
          {(['subtitles', 'audio'] as const).map((t) => (
            <button
              key={t} type="button" onClick={() => setTab(t)}
              className={`rounded-lg px-3 py-1 text-[12px] font-semibold capitalize ${tab === t ? 'bg-white text-black' : 'text-white/60'}`}
            >
              {t}
            </button>
          ))}
        </div>
        <button type="button" aria-label="Close" onClick={onClose} className="text-white/60 hover:text-white"><X size={16} aria-hidden /></button>
      </div>

      {tab === 'audio' && (
        <>
          {state.tracks.audio.map((t) => (
            <Row key={t.id} selected={t.selected} label={t.label} onClick={() => selectAudio(t.id)} />
          ))}
          {state.tracks.audio.length === 0 && <div className="px-3 py-2 text-[12px] text-white/40">No audio tracks</div>}
          <DelaySlider label="Audio sync" value={state.audioDelay} prop="audio-delay" />
        </>
      )}

      {tab === 'subtitles' && (
        <>
          <Row selected={!state.tracks.subs.some((s) => s.selected)} label="Off" onClick={() => selectSub('no')} />
          {state.tracks.subs.map((t) => (
            <Row key={t.id} selected={t.selected} label={`${t.label}${t.external ? ' · ext' : ''}`} onClick={() => selectSub(t.id)} />
          ))}
          {externalSubtitles.filter((s) => !addedExternal.has(s.url)).length > 0 && (
            <div className="mt-2 border-t border-white/10 pt-2">
              <div className="px-3 pb-1 text-[11px] font-bold uppercase tracking-wider text-white/40">From addons</div>
              {externalSubtitles.filter((s) => !addedExternal.has(s.url)).slice(0, 20).map((s) => (
                <Row key={s.id + s.url} selected={false} label={`${s.lang}${s.name ? ` · ${s.name}` : ''}`} onClick={() => addExternal(s)} />
              ))}
            </div>
          )}
          <DelaySlider label="Subtitle sync" value={state.subDelay} prop="sub-delay" />

          <div className="mt-2 border-t border-white/10 pt-2 px-3 space-y-2">
            <div className="text-[11px] font-bold uppercase tracking-wider text-white/40">Appearance</div>
            <div className="flex gap-1">
              {(['small', 'medium', 'large', 'xlarge'] as const).map((size) => (
                <button key={size} type="button" onClick={() => applyPrefs({ ...prefs, size })}
                  className={`rounded-md px-2 py-1 text-[11px] ${prefs.size === size ? 'bg-white text-black font-bold' : 'bg-white/10 text-white/70'}`}>
                  {size === 'small' ? 'S' : size === 'medium' ? 'M' : size === 'large' ? 'L' : 'XL'}
                </button>
              ))}
            </div>
            <div className="flex gap-1">
              {(['white', 'yellow', 'cyan', 'green'] as const).map((color) => (
                <button key={color} type="button" aria-label={`Subtitle color ${color}`} onClick={() => applyPrefs({ ...prefs, color })}
                  className={`h-6 w-6 rounded-full border-2 ${prefs.color === color ? 'border-white' : 'border-transparent'}`}
                  style={{ background: color === 'white' ? '#FFF' : color === 'yellow' ? '#FFD54A' : color === 'cyan' ? '#4AD8FF' : '#4AFF6A' }} />
              ))}
            </div>
            <div>
              <div className="flex justify-between text-[11px] text-white/50">
                <span>Background</span><span>{prefs.backgroundOpacity}%</span>
              </div>
              <input type="range" min={0} max={100} value={prefs.backgroundOpacity}
                onChange={(e) => applyPrefs({ ...prefs, backgroundOpacity: Number(e.target.value) })}
                className="w-full accent-white" aria-label="Subtitle background opacity" />
            </div>
            <div className="flex gap-1">
              {(['low', 'medium', 'high'] as const).map((position) => (
                <button key={position} type="button" onClick={() => applyPrefs({ ...prefs, position })}
                  className={`rounded-md px-2 py-1 text-[11px] capitalize ${prefs.position === position ? 'bg-white text-black font-bold' : 'bg-white/10 text-white/70'}`}>
                  {position}
                </button>
              ))}
            </div>
          </div>
        </>
      )}
    </div>
  );
}
```

- [ ] **Step 2: Verify + commit**

```bash
npx vitest run && npm run typecheck
git add src/components/player/MpvTracksPanel.tsx
git commit -m "feat(desktop): mpv tracks panel with delays, external subs, and styling"
```

---

### Task 12: Episode navigation — UpNextPanel + prev/next + auto-advance

**Files:**
- Replace stub: `moonlit-web/src/components/player/UpNextPanel.tsx`
- Modify: `moonlit-web/src/components/player/MpvPlayer.tsx` (episode nav events + auto-advance countdown)

- [ ] **Step 1: Implement `UpNextPanel.tsx`**

```tsx
import { useEffect, useState } from 'react';
import { X } from 'lucide-react';
import { usePlayer } from '@/app/PlayerProvider';
import { fetchMeta } from '@/lib/stremio';
import { getInstalledAddons } from '@/lib/services/api';
import { useAuth } from '@/app/AuthProvider';
import type { MetaDetail } from '@/lib/types';

interface EpisodeRef { id: string; season: number; episode: number; title?: string; thumbnail?: string; overview?: string }

export function parseEpisodeId(mediaId: string): { imdb: string; season: number; episode: number } | null {
  const m = mediaId.match(/^(tt\d+):(\d+):(\d+)$/);
  return m ? { imdb: m[1], season: Number(m[2]), episode: Number(m[3]) } : null;
}

export function findAdjacent(videos: EpisodeRef[], season: number, episode: number, dir: 1 | -1): EpisodeRef | null {
  const ordered = [...videos].sort((a, b) => a.season - b.season || a.episode - b.episode);
  const idx = ordered.findIndex((v) => v.season === season && v.episode === episode);
  if (idx === -1) return null;
  return ordered[idx + dir] ?? null;
}

export function UpNextPanel({ mediaId, mediaType, onClose }: {
  mediaId: string; mediaType: string; onClose: () => void;
}) {
  const { open } = usePlayer();
  const { currentProfile } = useAuth();
  const [meta, setMeta] = useState<MetaDetail | null>(null);
  const [season, setSeason] = useState<number>(parseEpisodeId(mediaId)?.season ?? 1);
  const cur = parseEpisodeId(mediaId);

  useEffect(() => {
    (async () => {
      if (!cur || !currentProfile) return;
      const addons = await getInstalledAddons(currentProfile.id);
      for (const addon of addons) {
        if (!addon.transportUrl) continue;
        const m = await fetchMeta(addon.transportUrl.replace(/\/manifest\.json$/, ''), 'series', cur.imdb).catch(() => null);
        if (m?.videos?.length) { setMeta(m); return; }
      }
    })();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [mediaId]);

  const episodes: EpisodeRef[] = (meta?.videos ?? [])
    .map((v) => ({
      id: v.id, season: v.season ?? 0, episode: v.episode ?? 0,
      title: v.title ?? v.name, thumbnail: v.thumbnail, overview: v.overview,
    }))
    .filter((v) => v.season > 0);
  const seasons = [...new Set(episodes.map((e) => e.season))].sort((a, b) => a - b);

  const playEpisode = (ep: EpisodeRef) => {
    onClose();
    open({
      type: mediaType, id: `${cur?.imdb}:${ep.season}:${ep.episode}`,
      metadata: {
        mediaId: `${cur?.imdb}:${ep.season}:${ep.episode}`, mediaType,
        title: ep.title ?? `S${ep.season} E${ep.episode}`, poster: ep.thumbnail,
      },
    });
  };

  return (
    <div className="absolute inset-y-0 right-0 z-30 w-[380px] overflow-y-auto bg-[#141414]/95 backdrop-blur border-l border-white/10 p-4">
      <div className="flex items-center justify-between pb-3">
        <div className="text-[14px] font-bold text-white">Up Next</div>
        <button type="button" aria-label="Close" onClick={onClose} className="text-white/60 hover:text-white"><X size={16} aria-hidden /></button>
      </div>
      {seasons.length > 1 && (
        <div className="flex gap-1 overflow-x-auto pb-3">
          {seasons.map((sn) => (
            <button key={sn} type="button" onClick={() => setSeason(sn)}
              className={`shrink-0 rounded-full px-3 py-1 text-[12px] font-semibold ${season === sn ? 'bg-white text-black' : 'bg-white/10 text-white/70'}`}>
              Season {sn}
            </button>
          ))}
        </div>
      )}
      {episodes.filter((e) => e.season === season).map((ep) => {
        const isCurrent = cur?.season === ep.season && cur?.episode === ep.episode;
        return (
          <button key={ep.id} type="button" onClick={() => !isCurrent && playEpisode(ep)}
            className={`mb-2 flex w-full gap-3 rounded-xl p-2 text-left ${isCurrent ? 'bg-white/15 ring-1 ring-white/30' : 'hover:bg-white/8'}`}>
            {ep.thumbnail && <img src={ep.thumbnail} alt="" className="h-16 w-28 shrink-0 rounded-lg object-cover" />}
            <div className="min-w-0">
              <div className="truncate text-[13px] font-semibold text-white">E{ep.episode} · {ep.title ?? 'Episode'}</div>
              {ep.overview && <div className="line-clamp-2 text-[11px] text-white/50">{ep.overview}</div>}
            </div>
          </button>
        );
      })}
      {episodes.length === 0 && <div className="text-[12px] text-white/40">No episode data available.</div>}
    </div>
  );
}
```

(Implementer: `getInstalledAddons` — find the real addon-list source in `src/lib/services/api.ts` or wherever settings loads addons; match its actual export name/signature. `MetaDetail.videos` shape — check `src/lib/types.ts`.)

- [ ] **Step 2: Auto-advance + prev/next in MpvPlayer** — add to `MpvPlayer.tsx`:
  - Listen for the `moonlit:episode-nav` CustomEvent; on `detail: -1|1`, parse `mediaId` with `parseEpisodeId`, fetch adjacent via `findAdjacent` (export both from UpNextPanel), relaunch via `usePlayer().open` like `playEpisode`.
  - When `mediaType === 'series'` and `state.duration - state.position <= 30` and not ended, show a small "Next episode" pill (button triggering nav `+1`).
  - On `state.ended` for series: auto-advance to next episode if one exists.

- [ ] **Step 3: Unit tests for the pure helpers** — create `src/components/player/UpNextPanel.test.ts`:

```ts
import { describe, it, expect } from 'vitest';
import { parseEpisodeId, findAdjacent } from './UpNextPanel';

describe('parseEpisodeId', () => {
  it('parses series ids', () => {
    expect(parseEpisodeId('tt123:2:5')).toEqual({ imdb: 'tt123', season: 2, episode: 5 });
  });
  it('rejects movie ids', () => {
    expect(parseEpisodeId('tt123')).toBeNull();
  });
});

describe('findAdjacent', () => {
  const eps = [
    { id: 'a', season: 1, episode: 9 }, { id: 'b', season: 1, episode: 10 },
    { id: 'c', season: 2, episode: 1 },
  ];
  it('crosses season boundaries forward', () => {
    expect(findAdjacent(eps, 1, 10, 1)?.id).toBe('c');
  });
  it('goes backward', () => {
    expect(findAdjacent(eps, 1, 10, -1)?.id).toBe('a');
  });
  it('returns null at the end', () => {
    expect(findAdjacent(eps, 2, 1, 1)).toBeNull();
  });
});
```

- [ ] **Step 4: Verify + commit**

```bash
npx vitest run && npm run typecheck
git add src/components/player/UpNextPanel.tsx src/components/player/UpNextPanel.test.ts src/components/player/MpvPlayer.tsx
git commit -m "feat(desktop): episode navigation, Up Next panel, and auto-advance"
```

---

### Task 13: Anime4K toggle + seek thumbnails

**Files:**
- Modify: `moonlit-web/src/components/player/MpvPlayer.tsx`
- Create: `moonlit-web/src/lib/platform/mpv-thumbnails.ts`

- [ ] **Step 1: Anime4K** — add to MpvPlayer top bar an `IconBtn` (label "Anime4K upscaling", lucide `Sparkles` icon) toggling:

```ts
const [anime4k, setAnime4k] = useState(false);
const toggleAnime4k = async () => {
  if (!anime4k) {
    const dir = await mpv.shaderDir();
    const sep = ';'; // mpv list separator on Windows
    const chain = [
      'Anime4K_Clamp_Highlights.glsl',
      'Anime4K_Restore_CNN_M.glsl',
      'Anime4K_Upscale_Denoise_CNN_x2_M.glsl',
    ].map((f) => `${dir}\\${f}`).join(sep);
    await mpv.setProp('glsl-shaders', chain);
  } else {
    await mpv.setProp('glsl-shaders', '');
  }
  setAnime4k(!anime4k);
};
```

- [ ] **Step 2: Seek thumbnails** — create `mpv-thumbnails.ts` (Mac-style periodic-screenshot approach):

```ts
import { mpv } from './mpv';

/** Periodic screenshot-based seek thumbnails (Mac PlayerThumbnailer approach).
 *  Captures a small PNG every intervalSec into the app temp dir and returns
 *  a time-bucketed lookup. */
export class MpvThumbnailer {
  private cache = new Map<number, string>(); // bucket → asset URL
  private timer: ReturnType<typeof setInterval> | undefined;
  constructor(private bucketSec = 30) {}

  start() {
    this.timer = setInterval(async () => {
      try {
        const pos = await mpv.getProp<number>('time-pos');
        if (typeof pos !== 'number') return;
        const bucket = Math.floor(pos / this.bucketSec);
        if (this.cache.has(bucket)) return;
        const { join, tempDir } = await import('@tauri-apps/api/path');
        const { convertFileSrc } = await import('@tauri-apps/api/core');
        const path = await join(await tempDir(), `moonlit-thumb-${bucket}.png`);
        await mpv.screenshot(path);
        this.cache.set(bucket, convertFileSrc(path));
      } catch { /* best-effort */ }
    }, 15_000);
  }
  stop() { clearInterval(this.timer); }
  nearest(timeSec: number): string | null {
    const bucket = Math.floor(timeSec / this.bucketSec);
    for (const b of [bucket, bucket - 1, bucket + 1]) {
      const hit = this.cache.get(b);
      if (hit) return hit;
    }
    return null;
  }
}
```

- [ ] **Step 3: Wire hover preview** — in MpvPlayer scrubber: instantiate `MpvThumbnailer` in a ref (start on `state.loaded`, stop on unmount); `onMouseMove` over the scrubber computes hover time, shows a positioned `<img>` (w-40 rounded-lg) + `fmt(hoverTime)` label when `nearest()` returns a URL, timestamp-only otherwise.

- [ ] **Step 4: Verify + commit**

```bash
npx vitest run && npm run typecheck
git add src/components/player/MpvPlayer.tsx src/lib/platform/mpv-thumbnails.ts
git commit -m "feat(desktop): Anime4K shader toggle and screenshot-based seek thumbnails"
```

---

### Task 14: Source switching keeps position + 4K preference toggle

**Files:**
- Modify: `moonlit-web/src/components/player/PlayerShell.tsx`
- Modify: `moonlit-web/src/components/player/MpvPlayer.tsx`

- [ ] **Step 1:** In PlayerShell's mpv branch: `registerStreamSwitchHandler` implementation must, before restarting with the new stream: `const pos = await mpv.getProp<number>('time-pos').catch(() => 0)` and relaunch MpvPlayer with `startPosition = pos` (thread through state). The existing SourcesPanel (opened via `onOpenSources`) already calls `switchStream` from context — verify the wiring reaches the handler.

- [ ] **Step 2:** 4K preference: in the SourcesPanel area for desktop (or a small toggle inside MpvPlayer's sources affordance if SourcesPanel is web-shared), add a "Prefer 4K" checkbox bound to `getPrefer4K()/setPrefer4K()` that re-sorts and (on change) picks the new best stream via `switchStream`.

- [ ] **Step 3: Verify + commit**

```bash
npx vitest run && npm run typecheck
git add src/components/player
git commit -m "feat(desktop): position-preserving source switching and 4K preference"
```

---

### Task 15: CI + docs

**Files:**
- Modify: `.github/workflows/windows-desktop.yml`
- Modify: `moonlit-web/README.md`

- [ ] **Step 1: Workflow** — add after "Install dependencies", before "Rust tests":

```yaml
      - name: Fetch desktop sidecars (libmpv + shaders)
        run: npm run setup:desktop

      - name: Add libmpv to PATH for tests
        run: echo "${{ github.workspace }}\moonlit-web\src-tauri\libmpv" | Out-File -FilePath $env:GITHUB_PATH -Append
```

- [ ] **Step 2: README** — extend the Desktop section:

```markdown
### Player (Windows)
Video plays through libmpv embedded beneath the WebView. Before building on
Windows run `npm run setup:desktop` (fetches `libmpv-2.dll`, generates
`mpv.lib`, downloads Anime4K shaders). Requires 7-Zip (`7z`) and LLVM
(`llvm-dlltool`) or VS `lib.exe` on PATH. On macOS the web player is used.
```

- [ ] **Step 3: Push and watch CI**

```bash
git add .github/workflows/windows-desktop.yml README.md
git commit -m "ci(desktop): fetch libmpv sidecars and wire player into Windows build"
git push
gh pr checks --watch
```

Expected: full pipeline green — this is the FIRST time the Rust player code compiles+links on Windows. Budget for a fix loop here (windows-rs/libmpv2 API mismatches surface now). Fix compile errors mechanically per the contracts in Tasks 4-5; commit as `fix(desktop): …`.

- [ ] **Step 4: Commit any fixes; CI green is the task exit.**

---

### Task 16: Manual VM verification checklist (human-in-the-loop)

No code. Download artifact: `gh run download <id> -n moonlit-windows-installer`. Install in Windows 11 ARM VM (SmartScreen: More info → Run anyway). Verify and record:

- [ ] Sign in, browse home, open a title, pick a source → video plays (HEVC MKV if available)
- [ ] Controls: play/pause, seek (click scrubber), ±15s, volume/mute, speed 1.5x
- [ ] Hotkeys: Space, ←/→, ↑/↓, F (fullscreen), M, C
- [ ] Tracks panel: switch audio track, enable embedded sub, add addon sub, delay sliders, styling changes render
- [ ] Resume: quit mid-playback, relaunch → Continue Watching resumes at position; "Start over" works
- [ ] Sources: switch source mid-play → position preserved; kill a stream URL → auto-fallback
- [ ] Series: Up Next panel lists episodes; next-episode pill near the end; auto-advance on finish
- [ ] Skip intro appears on a known show (or fallback skip)
- [ ] Anime4K toggles without crash; screenshot lands in `Pictures\Moonlit Screenshots`
- [ ] PiP mini-mode shrinks + pins on top; restore works
- [ ] Seek hover shows thumbnails after ~1 min of playback
- [ ] UI stays clickable over video (drag strip, panels) — no click-through dead zones

Known risk: ARM VM x64-emulated d3d11 rendering may glitch — note issues but validate codecs on real x64 hardware before ship.

---

## Self-Review Notes

- Spec coverage: Sections 3.2 (embed, bridge, mpv config), 5C (all player features), D substitutions (PiP mini-window, screenshots path, hotkeys) — covered across Tasks 1-14. Window resize-to-aspect is N/A on desktop (player lives in main window overlay) — documented deviation.
- Known adaptation points are explicitly delegated: libmpv2/windows-rs exact API shapes (Tasks 4-5), SkipIntroOverlay/api.ts/addon-list real signatures (Tasks 9, 12). Contracts (JSON event shape, command names, behavior) are fixed.
- Signing: intentionally out of scope (user decision) — unsigned NSIS + SmartScreen click-through.
