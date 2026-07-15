# Windows Desktop Phase 1: Foundation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Boot the existing moonlit-web React app inside a frameless Tauri 2 desktop shell with custom window controls, `moonlit://` deep links, platform detection, and Windows CI producing an NSIS installer artifact.

**Architecture:** Tauri 2 Rust shell added at `moonlit-web/src-tauri/`; the existing Vite/React app is the frontend. Desktop-only behavior is gated by an `isDesktop()` capability module so the Vercel web deploy is unaffected. CI runs on `windows-latest`.

**Tech Stack:** Tauri 2 (Rust), tauri-plugin-deep-link, tauri-plugin-single-instance, React 19 + TS + Vite 6 (existing), vitest, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-07-16-windows-desktop-app-design.md` (Section 3, Phase 1)

**Plan series:** This is plan 1 of 6. Plans for Phases 2–6 (Design System, Screen Rebuild, Player Core, Feature Ports, Ship) are written just-in-time as each phase begins.

**Working conventions:** npm (repo uses package-lock.json). All frontend commands run in `moonlit-web/`. Dev machine is macOS — `tauri dev` produces a mac shell for iteration; Windows verification happens in the ARM VM and CI.

---

### Task 1: Toolchain + green baseline

**Files:** none created; verification only.

- [ ] **Step 1: Install Rust toolchain (skip if `cargo --version` works)**

Run: `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y && source "$HOME/.cargo/env" && cargo --version`
Expected: `cargo 1.x.x`

- [ ] **Step 2: Verify frontend baseline is green**

Run (in `moonlit-web/`): `npm ci && npx vitest run`
Expected: all existing tests PASS. If any fail, STOP and report — do not proceed on a red baseline.

- [ ] **Step 3: Verify production build works**

Run (in `moonlit-web/`): `npm run build`
Expected: `dist/` produced, exit 0.

---

### Task 2: Tauri npm dependencies + scripts

**Files:**
- Modify: `moonlit-web/package.json`

- [ ] **Step 1: Install Tauri packages**

Run (in `moonlit-web/`):
```bash
npm install @tauri-apps/api@^2 @tauri-apps/plugin-deep-link@^2
npm install -D @tauri-apps/cli@^2
```

- [ ] **Step 2: Add scripts**

In `moonlit-web/package.json`, add to `"scripts"`:
```json
"tauri": "tauri",
"typecheck": "tsc -b"
```

- [ ] **Step 3: Verify**

Run: `npx tauri --version` → prints `tauri-cli 2.x.x`. Run: `npm run typecheck` → exit 0.

- [ ] **Step 4: Commit**

```bash
git add package.json package-lock.json
git commit -m "chore(desktop): add Tauri 2 CLI, API, and deep-link plugin deps"
```

---

### Task 3: Scaffold src-tauri shell

**Files:**
- Create: `moonlit-web/src-tauri/Cargo.toml`
- Create: `moonlit-web/src-tauri/build.rs`
- Create: `moonlit-web/src-tauri/src/main.rs`
- Create: `moonlit-web/src-tauri/src/lib.rs`
- Create: `moonlit-web/src-tauri/tauri.conf.json`
- Create: `moonlit-web/src-tauri/capabilities/default.json`
- Create: `moonlit-web/src-tauri/.gitignore`

- [ ] **Step 1: Create `moonlit-web/src-tauri/Cargo.toml`**

```toml
[package]
name = "moonlit-desktop"
version = "0.1.0"
edition = "2021"

[lib]
name = "moonlit_desktop_lib"
crate-type = ["staticlib", "cdylib", "rlib"]

[build-dependencies]
tauri-build = { version = "2", features = [] }

[dependencies]
tauri = { version = "2", features = [] }
tauri-plugin-deep-link = "2"
serde = { version = "1", features = ["derive"] }
serde_json = "1"
url = "2"

[target.'cfg(any(target_os = "macos", target_os = "windows", target_os = "linux"))'.dependencies]
tauri-plugin-single-instance = { version = "2", features = ["deep-link"] }
```

- [ ] **Step 2: Create `moonlit-web/src-tauri/build.rs`**

```rust
fn main() {
    tauri_build::build()
}
```

- [ ] **Step 3: Create `moonlit-web/src-tauri/src/main.rs`**

```rust
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    moonlit_desktop_lib::run();
}
```

- [ ] **Step 4: Create `moonlit-web/src-tauri/src/lib.rs`**

```rust
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

    builder
        .plugin(tauri_plugin_deep_link::init())
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
```

Note: single-instance MUST be the first registered plugin (Tauri requirement); the `deep-link` feature on it forwards second-instance URLs to the deep-link plugin automatically.

- [ ] **Step 5: Create `moonlit-web/src-tauri/tauri.conf.json`**

```json
{
  "$schema": "https://schema.tauri.app/config/2",
  "productName": "Moonlit",
  "version": "0.1.0",
  "identifier": "app.moonlit.desktop",
  "build": {
    "beforeDevCommand": "npm run dev",
    "devUrl": "http://localhost:5173",
    "beforeBuildCommand": "npm run build",
    "frontendDist": "../dist"
  },
  "app": {
    "windows": [
      {
        "label": "main",
        "title": "Moonlit",
        "width": 1200,
        "height": 800,
        "minWidth": 900,
        "minHeight": 600,
        "decorations": false,
        "transparent": false
      }
    ],
    "security": {
      "csp": null
    }
  },
  "bundle": {
    "active": true,
    "targets": ["nsis"],
    "icon": [
      "icons/32x32.png",
      "icons/128x128.png",
      "icons/128x128@2x.png",
      "icons/icon.icns",
      "icons/icon.ico"
    ]
  },
  "plugins": {
    "deep-link": {
      "desktop": {
        "schemes": ["moonlit"]
      }
    }
  }
}
```

(`transparent` stays `false` in Phase 1; the transparent-WebView2-over-mpv work is Phase 4.)

- [ ] **Step 6: Create `moonlit-web/src-tauri/capabilities/default.json`**

```json
{
  "$schema": "../gen/schemas/desktop-schema.json",
  "identifier": "default",
  "description": "Main window capability",
  "windows": ["main"],
  "permissions": [
    "core:default",
    "core:window:allow-minimize",
    "core:window:allow-toggle-maximize",
    "core:window:allow-close",
    "core:window:allow-start-dragging",
    "deep-link:default"
  ]
}
```

- [ ] **Step 7: Create `moonlit-web/src-tauri/.gitignore`**

```
/target
/gen/schemas
```

- [ ] **Step 8: Generate app icons**

Run (in `moonlit-web/`): `npx tauri icon public/moonlit-icon.png`
Expected: `src-tauri/icons/` populated (32x32.png, 128x128.png, icon.ico, icon.icns, etc.)

- [ ] **Step 9: Verify Rust compiles**

Run (in `moonlit-web/src-tauri/`): `cargo check`
Expected: `Finished` with no errors (first run downloads crates, takes minutes).

- [ ] **Step 10: Verify shell boots on macOS**

Run (in `moonlit-web/`): `npm run tauri dev`
Expected: a frameless 1200×800 window opens showing the moonlit-web landing page. Close it after confirming.

- [ ] **Step 11: Commit**

```bash
git add src-tauri
git commit -m "feat(desktop): scaffold Tauri 2 shell with frameless window and moonlit:// scheme"
```

---

### Task 4: Platform detection module

**Files:**
- Create: `moonlit-web/src/lib/platform/index.ts`
- Test: `moonlit-web/src/lib/platform/index.test.ts`

- [ ] **Step 1: Write the failing test** (`src/lib/platform/index.test.ts`)

```ts
import { describe, it, expect, afterEach } from 'vitest';
import { isDesktop } from './index';

describe('isDesktop', () => {
  afterEach(() => {
    delete (window as unknown as Record<string, unknown>).__TAURI_INTERNALS__;
  });

  it('returns false in a plain browser', () => {
    expect(isDesktop()).toBe(false);
  });

  it('returns true when Tauri internals are present', () => {
    (window as unknown as Record<string, unknown>).__TAURI_INTERNALS__ = {};
    expect(isDesktop()).toBe(true);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx vitest run src/lib/platform`
Expected: FAIL — cannot resolve `./index`.

- [ ] **Step 3: Write implementation** (`src/lib/platform/index.ts`)

```ts
/** True when running inside the Tauri desktop shell (Windows/macOS dev). */
export function isDesktop(): boolean {
  return typeof window !== 'undefined' && '__TAURI_INTERNALS__' in window;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npx vitest run src/lib/platform`
Expected: 2 PASS.

- [ ] **Step 5: Commit**

```bash
git add src/lib/platform
git commit -m "feat(desktop): isDesktop() platform capability detection"
```

---

### Task 5: Window chrome — drag region + custom window controls

**Files:**
- Create: `moonlit-web/src/components/WindowControls.tsx`
- Modify: `moonlit-web/src/router.tsx` (root route component, lines 55–66)

- [ ] **Step 1: Create `src/components/WindowControls.tsx`**

```tsx
import { isDesktop } from '@/lib/platform';

async function win() {
  const { getCurrentWindow } = await import('@tauri-apps/api/window');
  return getCurrentWindow();
}

/**
 * Desktop-only chrome: a top drag strip plus minimize/maximize/close buttons.
 * Renders nothing in the browser. Styling gets the full Mac-parity treatment
 * in Phase 2; this is functional chrome only.
 */
export function WindowControls() {
  if (!isDesktop()) return null;

  return (
    <>
      <div
        data-tauri-drag-region
        className="fixed top-0 left-0 right-0 h-8 z-[90]"
      />
      <div className="fixed top-2 right-3 z-[100] flex items-center gap-1">
        <button
          aria-label="Minimize"
          onClick={async () => (await win()).minimize()}
          className="w-8 h-8 rounded-lg flex items-center justify-center text-white/60 hover:text-white hover:bg-white/10"
        >
          <svg width="10" height="10" viewBox="0 0 10 10" fill="none">
            <path d="M1 5h8" stroke="currentColor" strokeWidth="1.2" />
          </svg>
        </button>
        <button
          aria-label="Maximize"
          onClick={async () => (await win()).toggleMaximize()}
          className="w-8 h-8 rounded-lg flex items-center justify-center text-white/60 hover:text-white hover:bg-white/10"
        >
          <svg width="10" height="10" viewBox="0 0 10 10" fill="none">
            <rect x="1.5" y="1.5" width="7" height="7" rx="1" stroke="currentColor" strokeWidth="1.2" />
          </svg>
        </button>
        <button
          aria-label="Close"
          onClick={async () => (await win()).close()}
          className="w-8 h-8 rounded-lg flex items-center justify-center text-white/60 hover:text-white hover:bg-red-500/80"
        >
          <svg width="10" height="10" viewBox="0 0 10 10" fill="none">
            <path d="M1.5 1.5l7 7M8.5 1.5l-7 7" stroke="currentColor" strokeWidth="1.2" />
          </svg>
        </button>
      </div>
    </>
  );
}
```

- [ ] **Step 2: Mount in root route** — in `src/router.tsx`, add the import and render inside the root component:

```tsx
import { WindowControls } from '@/components/WindowControls';
```

and change the rootRoute component body to:

```tsx
const rootRoute = createRootRoute({
  component: () => (
    <QueryClientProvider client={queryClient}>
      <AuthProvider>
        <PlayerProvider>
          <WindowControls />
          <Outlet />
          <PlayerOverlay />
        </PlayerProvider>
      </AuthProvider>
    </QueryClientProvider>
  ),
});
```

- [ ] **Step 3: Verify web unaffected**

Run: `npx vitest run && npm run typecheck`
Expected: all PASS (WindowControls returns null under jsdom — no Tauri internals).

- [ ] **Step 4: Verify in shell**

Run: `npm run tauri dev` → window shows min/max/close buttons top-right; top strip drags the window; buttons work.

- [ ] **Step 5: Commit**

```bash
git add src/components/WindowControls.tsx src/router.tsx
git commit -m "feat(desktop): frameless window drag region and custom window controls"
```

---

### Task 6: Deep-link URL parsing (Rust)

**Files:**
- Create: `moonlit-web/src-tauri/src/deeplink.rs`
- Modify: `moonlit-web/src-tauri/src/lib.rs`

Rationale: the shell logs/handles `moonlit://` URLs on arrival; the parse logic is pure and unit-tested. (Frontend consumes URLs via the plugin's JS API — Task 7.)

- [ ] **Step 1: Write the failing test** — create `src/deeplink.rs`:

```rust
use url::Url;

#[derive(Debug, PartialEq)]
pub struct DeepLink {
    pub action: String,
    pub params: Vec<(String, String)>,
}

pub fn parse(raw: &str) -> Option<DeepLink> {
    let url = Url::parse(raw).ok()?;
    if url.scheme() != "moonlit" {
        return None;
    }
    let action = url.host_str()?.to_string();
    let params = url
        .query_pairs()
        .map(|(k, v)| (k.into_owned(), v.into_owned()))
        .collect();
    Some(DeepLink { action, params })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_trakt_callback() {
        let link = parse("moonlit://trakt-callback?code=abc123&state=xyz").unwrap();
        assert_eq!(link.action, "trakt-callback");
        assert_eq!(
            link.params,
            vec![
                ("code".to_string(), "abc123".to_string()),
                ("state".to_string(), "xyz".to_string())
            ]
        );
    }

    #[test]
    fn rejects_other_schemes() {
        assert_eq!(parse("https://example.com/x"), None);
    }

    #[test]
    fn rejects_garbage() {
        assert_eq!(parse("not a url"), None);
    }
}
```

- [ ] **Step 2: Wire the module** — in `src/lib.rs` add at the top:

```rust
pub mod deeplink;
```

- [ ] **Step 3: Run tests**

Run (in `src-tauri/`): `cargo test`
Expected: 3 passed.

- [ ] **Step 4: Commit**

```bash
git add src-tauri/src/deeplink.rs src-tauri/src/lib.rs
git commit -m "feat(desktop): moonlit:// deep-link parsing with tests"
```

---

### Task 7: Deep-link frontend handling

**Files:**
- Create: `moonlit-web/src/lib/platform/deeplink.ts`
- Test: `moonlit-web/src/lib/platform/deeplink.test.ts`

- [ ] **Step 1: Write the failing test** (`src/lib/platform/deeplink.test.ts`)

```ts
import { describe, it, expect } from 'vitest';
import { parseMoonlitUrl } from './deeplink';

describe('parseMoonlitUrl', () => {
  it('parses action and params from a trakt callback', () => {
    const result = parseMoonlitUrl('moonlit://trakt-callback?code=abc123&state=xyz');
    expect(result).toEqual({
      action: 'trakt-callback',
      params: { code: 'abc123', state: 'xyz' },
    });
  });

  it('returns null for non-moonlit schemes', () => {
    expect(parseMoonlitUrl('https://example.com')).toBeNull();
  });

  it('returns null for malformed input', () => {
    expect(parseMoonlitUrl('not a url')).toBeNull();
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx vitest run src/lib/platform`
Expected: FAIL — cannot resolve `./deeplink`.

- [ ] **Step 3: Write implementation** (`src/lib/platform/deeplink.ts`)

```ts
import { isDesktop } from './index';

export interface MoonlitDeepLink {
  action: string;
  params: Record<string, string>;
}

export function parseMoonlitUrl(raw: string): MoonlitDeepLink | null {
  let url: URL;
  try {
    url = new URL(raw);
  } catch {
    return null;
  }
  if (url.protocol !== 'moonlit:') return null;
  // moonlit://action → URL parses the action as host
  const action = url.host || url.pathname.replace(/^\/+/, '');
  if (!action) return null;
  const params: Record<string, string> = {};
  url.searchParams.forEach((value, key) => {
    params[key] = value;
  });
  return { action, params };
}

/**
 * Subscribe to moonlit:// deep links (desktop only; no-op in browser).
 * Returns an unsubscribe function.
 */
export async function onDeepLink(
  handler: (link: MoonlitDeepLink) => void,
): Promise<() => void> {
  if (!isDesktop()) return () => {};
  const { onOpenUrl } = await import('@tauri-apps/plugin-deep-link');
  const unlisten = await onOpenUrl((urls) => {
    for (const raw of urls) {
      const link = parseMoonlitUrl(raw);
      if (link) handler(link);
    }
  });
  return unlisten;
}
```

- [ ] **Step 4: Run tests**

Run: `npx vitest run src/lib/platform`
Expected: all PASS (parse tests; `onDeepLink` is a thin adapter, exercised in Phase 5 Trakt work).

- [ ] **Step 5: Commit**

```bash
git add src/lib/platform/deeplink.ts src/lib/platform/deeplink.test.ts
git commit -m "feat(desktop): deep-link parsing and subscription for the frontend"
```

---

### Task 8: Windows CI workflow

**Files:**
- Create: `.github/workflows/windows-desktop.yml` (repo root)

- [ ] **Step 1: Create the workflow**

```yaml
name: Windows Desktop

on:
  push:
    branches: [main]
    paths:
      - 'moonlit-web/**'
      - '.github/workflows/windows-desktop.yml'
  pull_request:
    paths:
      - 'moonlit-web/**'
      - '.github/workflows/windows-desktop.yml'
  workflow_dispatch:

jobs:
  build:
    runs-on: windows-latest
    defaults:
      run:
        working-directory: moonlit-web
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version: 22
          cache: npm
          cache-dependency-path: moonlit-web/package-lock.json

      - uses: dtolnay/rust-toolchain@stable

      - uses: swatinem/rust-cache@v2
        with:
          workspaces: moonlit-web/src-tauri

      - name: Install dependencies
        run: npm ci

      - name: Typecheck
        run: npm run typecheck

      - name: Frontend tests
        run: npx vitest run

      - name: Rust tests
        run: cargo test --manifest-path src-tauri/Cargo.toml

      - name: Build NSIS installer
        run: npx tauri build

      - name: Upload installer artifact
        uses: actions/upload-artifact@v4
        with:
          name: moonlit-windows-installer
          path: moonlit-web/src-tauri/target/release/bundle/nsis/*.exe
          if-no-files-found: error
```

- [ ] **Step 2: Validate YAML locally**

Run: `npx --yes yaml-lint .github/workflows/windows-desktop.yml` (or open in editor — confirm no syntax errors).

- [ ] **Step 3: Commit and push, then verify CI**

```bash
git add .github/workflows/windows-desktop.yml
git commit -m "ci(desktop): Windows build with tests and NSIS installer artifact"
git push
```

Then: `gh run watch` (or check Actions tab). Expected: all steps green, `moonlit-windows-installer` artifact attached. If the NSIS step fails, read the log — common causes are missing icons (Task 3 Step 8) or capabilities schema errors.

---

### Task 9: Dev-loop documentation

**Files:**
- Modify: `moonlit-web/README.md` (append section)

- [ ] **Step 1: Append desktop section to README**

```markdown
## Desktop (Windows) — Tauri shell

The desktop app lives in `src-tauri/` and wraps this web app. Web deploys to
Vercel are unaffected; desktop-only behavior is gated by `isDesktop()`
(`src/lib/platform`).

### Dev loop
- **macOS (shell iteration):** `npm run tauri dev` — frameless mac window, fine
  for UI/chrome/bridge work. Not valid for video or Windows-specific testing.
- **Windows daily testing:** Windows 11 ARM VM (Parallels/UTM/VMware Fusion) on
  Apple Silicon. Install Node 22 + Rust (rustup) + VS Build Tools in the VM,
  then `npm run tauri dev` from a shared or cloned checkout.
- **CI:** `.github/workflows/windows-desktop.yml` builds an NSIS installer
  artifact per push — install that in the VM for release-build testing.
- **Video/codec validation:** real x64 hardware only. ARM VMs do not represent
  GPU/codec behavior (HEVC, DTS, HDR).

### Commands
- `npm run tauri dev` — run the desktop shell (starts Vite automatically)
- `npm run tauri build` — production bundle (NSIS on Windows)
- `cargo test --manifest-path src-tauri/Cargo.toml` — Rust tests
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs(desktop): dev loop for Tauri shell, Windows VM, and CI"
```

---

## Phase 1 Exit Criteria (verify all before closing)

- [ ] `npm run tauri dev` boots the existing moonlit-web UI in a frameless window with working drag + min/max/close
- [ ] `npx vitest run` and `cargo test --manifest-path src-tauri/Cargo.toml` green
- [ ] Web build (`npm run build`) unaffected; no Tauri code executes in browser (jsdom tests prove null-render)
- [ ] CI green on `windows-latest` with NSIS installer artifact
- [ ] Installer installs and launches in the Windows 11 ARM VM; `moonlit://trakt-callback?code=test` opens/focuses the app (manual VM check)

**Next:** Phase 2 plan — Mac Design System (`docs/superpowers/plans/…-phase-2-design-system.md`), written when Phase 1 exits.
