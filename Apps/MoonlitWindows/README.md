# Moonlit for Windows

Tauri 2 desktop app built from the macOS Moonlit app specification — same screens,
same design system, same data layer.

## Dev

```bash
# macOS: shell iteration (no video)
npm run tauri dev

# Windows: full experience
npm run setup:desktop   # fetch libmpv + shaders (one-time)
npm run tauri dev

# Production build
npm run tauri build     # produces .exe (NSIS installer)
```

## Project layout

```
src/
  shell/          Navigation (state-driven, no router), pill nav bar, overlay stack
  screens/        All 16 screens matching the Mac app's SwiftUI equivalents
  components/     Shared component library (MediaCard, MediaRow, GenreTile, etc.)
  lib/            Data layer (stremio, api, services, platform, design tokens)
  app/            AuthProvider, PlayerProvider
src-tauri/        Rust shell (libmpv player, window, deep links, HTTP client)
```

## Scripts

- `npm run tauri dev` — desktop dev shell (starts Vite)
- `npm run tauri build` — NSIS installer (Windows)
- `npm run setup:desktop` — fetch libmpv DLL + Anime4K shaders
- `npm run typecheck` — full TS project check
- `cargo test --manifest-path src-tauri/Cargo.toml` — Rust tests
