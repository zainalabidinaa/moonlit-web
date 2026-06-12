# Cinematic Background — Design Spec
_Date: 2026-06-12_

## Context

Luna's home screen shows a visible line between the hero carousel and the content rows below it. The line is caused by the hero's bottom gradient never reaching full opacity (terminates at `background.opacity(0.86)`), so when the view is clipped at its hard 620pt boundary, 14% of the image bleeds through and creates a luminance jump.

Frame-by-frame analysis of Fusion Media Center confirms the "seamless" look comes from two things: (1) a very long, gradual gradient that terminates fully opaque at `LunaTheme.background`, and (2) a blurred copy of the hero image sitting behind the gradient stack to create atmospheric depth at the top of the screen.

## Goal

- Eliminate the visible line between hero and content rows
- Add a blurred backdrop layer behind the gradient for atmospheric depth (matches Fusion)
- Keep changes surgical: two files, no new components

---

## Design

### Layer stack (bottom → top)

```
1. LunaTheme.background           — base, always present
2. Blurred hero image             — NEW, top 58% of screen, behind gradients
3. Radial gradient (ambient tint) — existing, unchanged
4. Radial gradient (accent edge)  — existing, unchanged
5. Linear gradient (fade to base) — existing, unchanged
6. ParallaxHero (sharp art)       — sits above background in ScrollView
```

### Change 1 — `ParallaxHero.swift` gradient (2 lines)

Current gradient bottom stops:
```swift
.init(color: LunaTheme.background.opacity(0.24), location: 0.78),
.init(color: LunaTheme.background.opacity(0.86), location: 1.0),
```

New — more gradual fade, fully opaque terminal:
```swift
.init(color: LunaTheme.background.opacity(0.24), location: 0.62),
.init(color: LunaTheme.background,               location: 1.0),
```

Moving the 0.24 stop from 0.78 → 0.62 starts the visible fade earlier, matching Fusion's longer
gradient profile. Changing the terminal to 1.0 opacity means zero image bleeding at the `.clipped()` boundary — no line.

### Change 2 — `FusionAmbientBackground` blurred backdrop (new layer + new param)

Add `heroBackdropURL: URL?` parameter. When enabled and URL is present, render a blurred
image layer at the bottom of the ZStack (below the radial gradients):

```swift
if isEnabled, let url = heroBackdropURL {
    CachedAsyncImage(url: url) { phase in
        if case .success(let image) = phase {
            image
                .resizable()
                .scaledToFill()
                .blur(radius: 32)
                .saturation(0.85)
                .brightness(-0.12)
                .scaleEffect(1.08)
                .opacity(0.72)
        }
    }
    .id(url)
    .transition(.opacity)
    .frame(maxWidth: .infinity, alignment: .top)
    .frame(height: screenHeight * 0.58)
    .clipped()
    .ignoresSafeArea(edges: .top)
    .animation(.easeInOut(duration: 0.6), value: url)
}
```

`scaleEffect(1.08)` prevents blur from exposing hard edges at the layer boundary.
`opacity(0.72)` keeps it atmospheric rather than dominant — it informs the gradients, not replaces them.

### Change 3 — `HomeScreen` passes hero URL to `FusionAmbientBackground`

Compute the backdrop URL from the current hero item (same banner-first, poster-fallback logic as the hero):

```swift
let heroURL = featuredItems[safe: heroIndex]
    .flatMap { ($0.banner ?? $0.poster).flatMap(URL.init) }

FusionAmbientBackground(
    ambientColor: ambientColor,
    heroBackdropURL: heroURL,
    isEnabled: cinematicModeEnabled,
    screenHeight: geo.size.height
)
```

---

## Files Changed

| File | Change |
|------|--------|
| `Sources/Components/ParallaxHero.swift` | 2 gradient stop values |
| `Sources/Screens/HomeScreen.swift` | `FusionAmbientBackground` new param + backdrop layer logic |

No new files. No new components. No changes to LunaCore.

---

## Verification

1. Build and run on device or simulator (iPhone Pro size)
2. With cinematic mode **OFF**: hero should still look correct, no line, gradient fades cleanly
3. With cinematic mode **ON**: top area should show blurred art tinted to the hero image
4. Scroll between several hero items — confirm background crossfades smoothly (~0.6s)
5. Scroll down through the rows — confirm no visible line at the hero boundary
6. Test with a very bright/saturated poster (e.g. Super Mario Galaxy) and a dark poster (e.g. Obsession) — both should fade cleanly without the background feeling painted
7. Confirm no performance regression: the blurred layer uses `CachedAsyncImage` so the image is already in cache from the hero above it
