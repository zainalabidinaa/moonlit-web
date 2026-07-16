# React + TypeScript + Vite

This template provides a minimal setup to get React working in Vite with HMR and some ESLint rules.

Currently, two official plugins are available:

- [@vitejs/plugin-react](https://github.com/vitejs/vite-plugin-react/blob/main/packages/plugin-react) uses [Oxc](https://oxc.rs)
- [@vitejs/plugin-react-swc](https://github.com/vitejs/vite-plugin-react/blob/main/packages/plugin-react-swc) uses [SWC](https://swc.rs/)

## React Compiler

The React Compiler is not enabled on this template because of its impact on dev & build performances. To add it, see [this documentation](https://react.dev/learn/react-compiler/installation).

## Expanding the ESLint configuration

If you are developing a production application, we recommend updating the configuration to enable type-aware lint rules:

```js
export default defineConfig([
  globalIgnores(['dist']),
  {
    files: ['**/*.{ts,tsx}'],
    extends: [
      // Other configs...

      // Remove tseslint.configs.recommended and replace with this
      tseslint.configs.recommendedTypeChecked,
      // Alternatively, use this for stricter rules
      tseslint.configs.strictTypeChecked,
      // Optionally, add this for stylistic rules
      tseslint.configs.stylisticTypeChecked,

      // Other configs...
    ],
    languageOptions: {
      parserOptions: {
        project: ['./tsconfig.node.json', './tsconfig.app.json'],
        tsconfigRootDir: import.meta.dirname,
      },
      // other options...
    },
  },
])
```

You can also install [eslint-plugin-react-x](https://github.com/Rel1cx/eslint-react/tree/main/packages/plugins/eslint-plugin-react-x) and [eslint-plugin-react-dom](https://github.com/Rel1cx/eslint-react/tree/main/packages/plugins/eslint-plugin-react-dom) for React-specific lint rules:

```js
// eslint.config.js
import reactX from 'eslint-plugin-react-x'
import reactDom from 'eslint-plugin-react-dom'

export default defineConfig([
  globalIgnores(['dist']),
  {
    files: ['**/*.{ts,tsx}'],
    extends: [
      // Other configs...
      // Enable lint rules for React
      reactX.configs['recommended-typescript'],
      // Enable lint rules for React DOM
      reactDom.configs.recommended,
    ],
    languageOptions: {
      parserOptions: {
        project: ['./tsconfig.node.json', './tsconfig.app.json'],
        tsconfigRootDir: import.meta.dirname,
      },
      // other options...
    },
  },
])

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
- **CI:** `.github/workflows/windows-desktop.yml` (repo root) builds an NSIS
  installer artifact per push/PR — install that in the VM for release-build
  testing.
- **Video/codec validation:** real x64 hardware only. ARM VMs do not represent
  GPU/codec behavior (HEVC, DTS, HDR).

### Commands
- `npm run tauri dev` — run the desktop shell (starts Vite automatically)
- `npm run tauri build` — production bundle (NSIS on Windows)
- `cargo test --manifest-path src-tauri/Cargo.toml` — Rust tests
- `npm run typecheck` — TypeScript project check (also used in CI)
```
