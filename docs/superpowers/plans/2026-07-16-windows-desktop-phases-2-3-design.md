# Windows Desktop Phases 2+3: Mac Design Parity — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans. Steps use checkbox syntax.

**Goal:** Bring moonlit-web (desktop + web) to full Mac-app design parity: white/gold accent system, Montserrat branding, glass vocabulary, spring motion, artwork-derived color engine, and screen-by-screen rebuild.

**Authoritative reference:** `docs/superpowers/specs/2026-07-16-windows-desktop-app-design.md` Appendix B (exact Mac values captured from code inspection) and Section 4.

**Branch:** `windows-desktop-phase-1`. Verification for every task: `npx vitest run` green, `npm run typecheck` exit 0, `npm run build` green (Vercel target must not break).

---

## Phase 2 — Design System

### Task 2.1: Tokens
- `tailwind.config.js` + `index.css`: replace orange accent — moonlit.accent → `#FFFFFF` semantics (white accent); add `gold: #D4AF37` (ratings/badges/selected pills ONLY); bg `#0D0D0D`, surface `#1A1A1A`, elevated `#242424`, outline `rgba(255,255,255,0.08)`; text tiers white 1.0/0.70/0.50
- Radius tokens: `rounded-ml-sm` 6 / `rounded-ml-ctl` 10 / `rounded-ml-card` 14 / `rounded-ml-lg` 18
- Shadows: `shadow-ml-lift` (black 0.40 r16 y10), `shadow-ml-panel` (black 0.80 r30 y14), `shadow-ml-glass` (black 0.30 r12 y4)
- Player palette: `player-canvas #111213`, `player-surface #191B1C`, `player-elevated #252628`, `player-raised #323335`, `player-edge rgba(60,61,63,0.55)`, `player-ink #F4F5F7`, `player-ink-muted #A3A5A6`
- 16 Oklch genre gradient CSS custom properties (from spec: Action oklch(0.40 0.18 25)→oklch(0.18 0.10 20), etc.)
- Grep-sweep: replace `moonlit-accent` usages (orange) with white-accent styles; `text-yellow-400` rating badges → gold

### Task 2.2: Typography
- Self-host Montserrat-ExtraBold woff2 in `public/fonts/`, `@font-face` with `font-display: swap`; `font-brand` utility (tracking 2)
- Type scale utilities: display-lg 40 / title-lg 28 / title-md 22 / title-sm 18 / body-lg 16 / body-md 14 / body-sm 13 / label-lg 14sb / label-md 12sb / label-sm 11sb / label-xs 10b, with md/lg/xl multipliers 1.05/1.1/1.15
- `font-mono tabular-nums` for player timecodes (already in MpvPlayer — keep)

### Task 2.3: Glass vocabulary (index.css @layer components)
- `.glass-card` r18 blur-xl bg-white/5 stroke white/10 1px
- `.glass-dark-card` r18 blur-xl bg-black/40 stroke white/16 0.8px
- `.glass-capsule` capsule blur-xl bg-white/10 stroke white/16 0.8px
- `.glass-liquid-capsule` capsule blur-[30px] saturate-[1.8] bg-black/28 stroke white/12 0.5px shadow-ml-glass
- `.glass-circle`, `.glass-icon-btn` (46px circle)
- Keep `.glass`/`.glass-dark` as aliases during migration

### Task 2.4: Motion
- `npm i framer-motion`
- `src/lib/design/motion.ts`: spring presets as framer transition objects — tileHover {stiffness/damping from response .30/damping .78}, heroStep (.42/.82), heroAuto (.50/.82), nav (.30/.75), libraryToggle (.25/.60), panel (.40/.85). Conversion: stiffness = (2π/response)², damping = 4π·dampingFraction/response (mass 1)
- Export `EASE` constants: crossfade .35, ambient .9, pill .15/.18

### Task 2.5: Artwork color engine (TDD)
- `src/lib/design/color-extract.ts` — pure math: 16³ histogram dominant color w/ chroma² weighting, brightness/sat filters (0.10–0.92, ≥0.12), boost sat×1.7 (0.70–1.0) bright×1.25 (0.60–0.95) for halos; dual-color left/right avg40/max60 + boost sat×3.0 bright×1.5 clamp (0.70–1.0, 0.45–0.80) for ambient. Tests with pixel fixtures
- `src/lib/design/artwork-color.ts` — canvas downsample (~36px halo / 40px ambient), cache per URL, `useTileHalo(url)` + `useAmbientColors(url)` hooks (browser + desktop both work; no worker if main-thread cost is fine at 40px — measure)

### Task 2.6: Core components
- `MediaCardHalo` wrapper: 2-layer radial glow behind card (blur 30 opacity .66 / blur 60 opacity .30, artwork color), spring scale 1.04, border white/0.14 hover : white/0.05, r14, `shadow-ml-lift` on hover
- `RatingBadge`: gold capsule (black/45 fill, gold/28 stroke, "IMDb" + star + score)
- `StrokeSpinner` (SVG ring, 25% arc, white track 0.14, 0.7s linear)
- `ShimmerCard` (white/10 + 1.5s gradient sweep) + `LoadingView` (spinner + 25 witty captions)
- `CategoryPills` (gold selected / white-8 idle) + genre rail with trailing fade mask
- Row header component (21px bold + 32px circular chevron white/10)

## Phase 3 — Screen rebuild (impact order)

### Task 3.1: Sidebar → PillNavBar
- "MOONLIT" wordmark (Montserrat, 14px black, tracking 2), `.glass-liquid-capsule` bar, active tab = white/10 capsule + white/12 stroke (NOT orange), inactive white/65, spring nav transitions, inline expanding search field, profile avatar 30px, Ctrl+1–8 shortcuts (desktop)

### Task 3.2: HomeHero
- Ambient washes from `useAmbientColors` (two radial gradients, ease .9s), 4-stop fade mask (0.92/0.88/0.35/0), genre label (12px bold tracking-2), logo art 330×120 shadow, white Watch Now capsule + dark-glass More Info, chevrons (32px dark-glass circles), animated capsule page dots (28px active/8px idle), 60s auto-advance, .35s crossfade. Keep parallax.

### Task 3.3: Cards + rows
- MediaRow/FolderTile/CollectionRow/Continue-watching → MediaCardHalo + springs + RatingBadge + row headers; `overflow: visible` + px padding so halos don't clip

### Task 3.4: Detail (browse.tsx) — FusionAmbient wash (intensity .55), gold ratings, glass buttons, springs

### Task 3.5: Player chrome — MpvPlayer + panels (MpvTracksPanel, UpNextPanel, speed popup) + web Player panels → opaque `player-elevated #252628` + `player-edge` border + `shadow-ml-panel` (replace `#141414` + blur)

### Task 3.6: Long tail — search, library, collections, settings, admin, auth/profiles/onboarding, watch route: token/glass/spring/spinner sweep; kill remaining orange

Acceptance: Appendix B gap table rows all addressed; no `#FF8A35` grep hits; screenshots side-by-side vs Mac.
