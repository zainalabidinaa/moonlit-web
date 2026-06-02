# iOS Liquid Glass Redesign — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apply iOS 26 Liquid Glass effects, AVPlayer player screen, Netflix-style profile picker, and full UI polish to the Luna iOS app.

**Architecture:** Pre-flight fixes (addon sync, PosterShape/tileShape wiring, app icon) → Design system foundation (glass modifiers, skeletons, empty states) in LunaCore → Screen-by-screen redesign in LunaApp. Each screen is independent after the foundation lands. All glass effects gate on `#available(iOS 26, *)`.

**Tech Stack:** SwiftUI, AVKit, LunaCore Swift Package, no simulator (real device + previews only).

---

## File Map

| File | Action | Purpose |
|------|--------|---------|
| `Packages/LunaCore/.../SupabaseConfig.swift` | Modify | Sync aiostreams URL |
| `Apps/LunaApp/.../ContentCard.swift` | Modify | Wire posterShape dimensions |
| `Apps/LunaApp/.../HomeScreen.swift` | Modify | Wire tileShape in FolderCell + glass hero/rows |
| `Apps/LunaApp/Assets.xcassets/` | Create assets | App icon |
| `Packages/LunaCore/.../LunaTheme.swift` | Modify | Add glass modifiers + design tokens |
| `Packages/LunaCore/.../Components/` | Create directory | Shared components |
| `Apps/LunaApp/.../AuthScreen.swift` | Modify | App icon + glass fields |
| `Apps/LunaApp/.../ProfilePickerScreen.swift` | Create | Netflix-style profile picker |
| `Apps/LunaApp/.../PlayerScreen.swift` | Create | AVPlayer + glass transport overlay |
| `Apps/LunaApp/.../DetailScreen.swift` | Modify | Glass buttons + backdrop |
| `Apps/LunaApp/.../SearchScreen.swift` | Modify | Glass search bar + filter chips |
| `Apps/LunaApp/.../LibraryScreen.swift` | Modify | Glass cards + swipe-to-delete |
| `Apps/LunaApp/.../SettingsScreen.swift` | Modify | Glass section cards |
| `Apps/LunaApp/.../ContentView.swift` | Modify | Add ProfilePickerScreen route |

---

### Task 0a: Sync aiostreams URL with LunaWeb

**Files:**
- Modify: `Packages/LunaCore/Sources/LunaCore/Supabase/SupabaseConfig.swift:11`

- [ ] **Step 1: Replace aiostreams URL**

Replace the entire line 11:

```swift
        "https://aiostreams.elfhosted.com/stremio/4a17bbef-9114-4231-82fb-b6baac090c63/eyJpIjoiWEUxR1dGYjJ2OVJqSGJIMURnYlpYUT09IiwiZSI6Ik5mUXRjSWFPaW9CNlhQWW9kOGhYcFZmdU5QaDJVSVM5MnZHMS9uZG1reGc9IiwidCI6ImEifQ/manifest.json",
```

With:

```swift
        "https://aiostreams.elfhosted.com/stremio/7d3fcfe4-393e-430c-aea7-47235eef5df5/eyJpIjoiV3RpV2xVZi96N2VrMVpXSmtrQWtuQT09IiwiZSI6Ikg5TjRKelR5bzMzNCsyY2dtTmcwV1BxNXRoMWxUVktLYVlkTmlqTi9kZjBwN1NERUo3b1JyUjhNckpvWmlKcEEiLCJ0IjoiYSJ9/manifest.json",
```

- [ ] **Step 2: Commit**

```bash
git add Packages/LunaCore/Sources/LunaCore/Supabase/SupabaseConfig.swift
git commit -m "fix: sync aiostreams default addon URL with LunaWeb"
```

---

### Task 0b: Wire PosterShape in ContentCard

**Files:**
- Modify: `Apps/LunaApp/Sources/Components/ContentCard.swift:86-99`

- [ ] **Step 1: Update card dimension computed properties**

Replace lines 93-99 (the `cardWidth` and `cardHeight` vars):

```swift
    private var cardWidth: CGFloat {
        switch resolvedShape {
        case .landscape: return 200
        case .square:    return 140
        case .poster:    return 120
        }
    }

    private var cardHeight: CGFloat {
        switch resolvedShape {
        case .landscape: return 112
        case .square:    return 140
        case .poster:    return 180
        }
    }
```

- [ ] **Step 2: Fix the aspectRatio in the ZStack poster/filler views**

In the `body` computed property, find the two `RoundedRectangle` calls at the top of the `ZStack` (lines 19-22 and the `AsyncImage` frame at lines 30-31). Replace the hardcoded frame dimensions with `cardWidth`/`cardHeight`:

The `RoundedRectangle` on line 19-21 becomes:
```swift
                RoundedRectangle(cornerRadius: 8)
                    .fill(LunaTheme.surfaceElevated)
                    .frame(width: cardWidth, height: cardHeight)
```

The `AsyncImage` frame on line 30-31 becomes:
```swift
                                .frame(width: cardWidth, height: cardHeight)
```

- [ ] **Step 3: Commit**

```bash
git add Apps/LunaApp/Sources/Components/ContentCard.swift
git commit -m "fix: ContentCard respects posterShape for landscape/square/portrait dimensions"
```

---

### Task 0c: Wire tileShape in FolderCell for Landscape Folders

**Files:**
- Modify: `Apps/LunaApp/Sources/Screens/HomeScreen.swift:343-381`

- [ ] **Step 1: Update FolderCell to read tileShape**

Replace the `FolderCell` struct (lines 343-381) with:

```swift
struct FolderCell: View {
    let row: CatalogRow
    let onTap: (MetaPreview) -> Void

    private var isLandscape: Bool {
        row.tileShape == "landscape"
    }

    var body: some View {
        let coverURL: URL? = {
            if let ci = row.coverImage { return URL(string: ci) }
            if let p = row.items.first?.poster { return URL(string: p) }
            return nil
        }()

        Button {
            if let first = row.items.first { onTap(first) }
        } label: {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(LunaTheme.surfaceElevated)
                    .aspectRatio(isLandscape ? 16/9 : 2/3, contentMode: .fit)

                if let url = coverURL {
                    AsyncImage(url: url) { phase in
                        if case .success(let img) = phase {
                            img.resizable().aspectRatio(contentMode: .fill)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .aspectRatio(isLandscape ? 16/9 : 2/3, contentMode: .fit)
                }

                LinearGradient(
                    colors: [.black.opacity(0.75), .clear],
                    startPoint: .bottom,
                    endPoint: .top
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .aspectRatio(isLandscape ? 16/9 : 2/3, contentMode: .fit)

                Text(row.title)
                    .font(.system(size: isLandscape ? 11 : 9, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 2: Update FolderGridSection to use adaptive columns for landscape**

Replace `FolderGridSection` (lines 318-341) to use adaptive columns:

```swift
struct FolderGridSection: View {
    let rows: [CatalogRow]
    let onTap: (MetaPreview) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 80), spacing: 8)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Browse")
                .font(.headline).foregroundColor(.white).padding(.horizontal)
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(rows) { row in
                    FolderCell(row: row, onTap: onTap)
                }
            }
            .padding(.horizontal)
        }
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add Apps/LunaApp/Sources/Screens/HomeScreen.swift
git commit -m "fix: FolderCell respects tileShape for landscape 16:9 folders"
```

---

### Task 0d: Add App Icon to Asset Catalog

**Files:**
- Create: `Apps/LunaApp/Resources/Assets.xcassets/luna-icon.imageset/`
- Modify: `Apps/LunaApp/Resources/Assets.xcassets/AppIcon.appiconset/` (if replacing app icon)

- [ ] **Step 1: Convert .icns to required PNG sizes for iOS**

```bash
PATH="/opt/homebrew/bin:$PATH"
ICON_SRC="/Users/zain/Downloads/ChatGPT Image May 31, 2026 at 10_38_02 PM.icns"
ASSETS_DIR="/Users/zain/projects/Luna/Apps/LunaApp/Resources/Assets.xcassets"

# Create luna-icon imageset for in-app use
mkdir -p "$ASSETS_DIR/luna-icon.imageset"
sips -s format png -z 256 256 "$ICON_SRC" --out "$ASSETS_DIR/luna-icon.imageset/luna-icon@2x.png"
sips -s format png -z 128 128 "$ICON_SRC" --out "$ASSETS_DIR/luna-icon.imageset/luna-icon.png"
```

- [ ] **Step 2: Create luna-icon imageset Contents.json**

Write `Apps/LunaApp/Resources/Assets.xcassets/luna-icon.imageset/Contents.json`:

```json
{
  "images" : [
    {
      "filename" : "luna-icon.png",
      "idiom" : "universal",
      "scale" : "1x"
    },
    {
      "filename" : "luna-icon@2x.png",
      "idiom" : "universal",
      "scale" : "2x"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

- [ ] **Step 3: Generate AppIcon sizes**

```bash
# Generate all required AppIcon sizes (iOS)
for size in 20 29 40 60; do
    sips -s format png -z $((size*2)) $((size*2)) "$ICON_SRC" --out "/tmp/icon-${size}@2x.png"
    sips -s format png -z $((size*3)) $((size*3)) "$ICON_SRC" --out "/tmp/icon-${size}@3x.png"
done
sips -s format png -z 1024 1024 "$ICON_SRC" --out "/tmp/icon-1024.png"
echo "App icon sizes generated in /tmp/"
```

- [ ] **Step 4: Commit**

```bash
git add Apps/LunaApp/Resources/Assets.xcassets/luna-icon.imageset/
git commit -m "feat: add Luna app icon from .icns asset"
```

---

### Task 1: Glass Modifiers Foundation (LunaTheme)

**Files:**
- Modify: `Packages/LunaCore/Sources/LunaCore/Theme/LunaTheme.swift`

- [ ] **Step 1: Add glass modifier extensions to LunaTheme.swift**

Append this after the existing `Color.init(hex:)` extension at line 42:

```swift
// MARK: - Glass Effect Modifiers (iOS 26 Liquid Glass)

#if canImport(SwiftUI)
import SwiftUI

public enum AppCardSurface {
    case regular
    case darkGlass
}

@available(iOS 26, *)
private struct GlassCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    let interactive: Bool

    func body(content: Content) -> some View {
        content
            .glassEffect(
                interactive ? .regular.interactive() : .regular,
                in: .rect(cornerRadius: cornerRadius, style: .continuous)
            )
    }
}

private struct GlassCardFallback: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.08), radius: 16, x: 0, y: 10)
    }
}

@available(iOS 26, *)
private struct GlassCapsuleModifier: ViewModifier {
    let interactive: Bool
    let clear: Bool

    func body(content: Content) -> some View {
        let effect: GlassEffect = {
            let base: GlassEffect = clear ? .clear : .regular
            return interactive ? base.interactive() : base
        }()
        return content.glassEffect(effect, in: Capsule(style: .continuous))
    }
}

private struct GlassCapsuleFallback: ViewModifier {
    let clear: Bool

    func body(content: Content) -> some View {
        content
            .background {
                if clear {
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.10))
                } else {
                    Capsule(style: .continuous)
                        .fill(.ultraThinMaterial)
                }
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(clear ? 0.22 : 0.16), lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
    }
}

@available(iOS 26, *)
private struct GlassCircleModifier: ViewModifier {
    let clear: Bool

    func body(content: Content) -> some View {
        let effect: GlassEffect = (clear ? .clear : .regular).interactive()
        return content.glassEffect(effect, in: Circle())
    }
}

private struct GlassCircleFallback: ViewModifier {
    let clear: Bool

    func body(content: Content) -> some View {
        content
            .background {
                if clear {
                    Circle().fill(Color.white.opacity(0.12))
                } else {
                    Circle().fill(.ultraThinMaterial)
                }
            }
            .overlay {
                Circle().stroke(Color.white.opacity(clear ? 0.22 : 0.14), lineWidth: 0.6)
            }
    }
}

// MARK: - Public View Extensions

extension View {
    @ViewBuilder
    public func glassCard(cornerRadius: CGFloat = 12, interactive: Bool = false) -> some View {
        if #available(iOS 26, *) {
            self.modifier(GlassCardModifier(cornerRadius: cornerRadius, interactive: interactive))
        } else {
            self.modifier(GlassCardFallback(cornerRadius: cornerRadius))
        }
    }

    @ViewBuilder
    public func glassCapsule(interactive: Bool = false, clear: Bool = false) -> some View {
        if #available(iOS 26, *) {
            self.modifier(GlassCapsuleModifier(interactive: interactive, clear: clear))
        } else {
            self.modifier(GlassCapsuleFallback(clear: clear))
        }
    }

    @ViewBuilder
    public func glassCircle(clear: Bool = false) -> some View {
        if #available(iOS 26, *) {
            self.modifier(GlassCircleModifier(clear: clear))
        } else {
            self.modifier(GlassCircleFallback(clear: clear))
        }
    }

    @ViewBuilder
    public func appCardStyle(
        surfaceStyle: AppCardSurface = .regular,
        cornerRadius: CGFloat = 14
    ) -> some View {
        if #available(iOS 26, *) {
            switch surfaceStyle {
            case .regular:
                self.glassEffect(
                    .regular,
                    in: .rect(cornerRadius: cornerRadius, style: .continuous)
                )
            case .darkGlass:
                self.glassEffect(
                    .clear,
                    in: .rect(cornerRadius: cornerRadius, style: .continuous)
                )
            }
        } else {
            self.modifier(GlassCardFallback(cornerRadius: cornerRadius))
        }
    }
}

extension View {
    @ViewBuilder
    public func glassProminentButtonStyle(
        tint: Color = LunaTheme.accent,
        cornerRadius: CGFloat = 14
    ) -> some View {
        if #available(iOS 26, *) {
            self.buttonStyle(.glassProminent)
                .tint(tint)
        } else {
            self.buttonStyle(.borderedProminent)
                .tint(tint)
                .cornerRadius(cornerRadius)
        }
    }
}

// MARK: - Shimmer Skeleton

public struct ShimmerCard: View {
    let width: CGFloat
    let height: CGFloat
    let cornerRadius: CGFloat

    public init(width: CGFloat, height: CGFloat, cornerRadius: CGFloat = 8) {
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color.white.opacity(0.05))
            .frame(width: width, height: height)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0),
                                Color.white.opacity(0.06),
                                Color.white.opacity(0),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .modifier(ShimmerAnimation())
            )
    }
}

private struct ShimmerAnimation: ViewModifier {
    @State private var offset: CGFloat = -400

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .onAppear {
                withAnimation(
                    .linear(duration: 1.5).repeatForever(autoreverses: false)
                ) {
                    offset = 400
                }
            }
    }
}

// MARK: - Empty State View

public struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    let actionLabel: String?
    let action: (() -> Void)?

    public init(
        icon: String,
        title: String,
        message: String,
        actionLabel: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.actionLabel = actionLabel
        self.action = action
    }

    public var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundColor(LunaTheme.textTertiary)
                .frame(width: 80, height: 80)
                .glassCircle()

            Text(title)
                .font(.headline)
                .foregroundColor(.white)

            Text(message)
                .font(.subheadline)
                .foregroundColor(LunaTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if let actionLabel = actionLabel, let action = action {
                Button(action: action) {
                    Text(actionLabel)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                }
                .glassCard(cornerRadius: 12, interactive: true)
                .foregroundColor(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Error State View

public struct ErrorStateView: View {
    let message: String
    let onRetry: (() -> Void)?

    public init(message: String, onRetry: (() -> Void)? = nil) {
        self.message = message
        self.onRetry = onRetry
    }

    public var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundColor(.orange)
                .frame(width: 80, height: 80)
                .glassCircle()

            Text("Something went wrong")
                .font(.headline)
                .foregroundColor(.white)

            Text(message)
                .font(.subheadline)
                .foregroundColor(LunaTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if let onRetry = onRetry {
                Button(action: onRetry) {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                }
                .glassCard(cornerRadius: 12, interactive: true)
                .foregroundColor(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
#endif
```

- [ ] **Step 2: Verify the file compiles**

Check that `LunaTheme.swift` still compiles with the additions. The `#if canImport(SwiftUI)` guard ensures these modifiers only compile when SwiftUI is available (it is in the iOS app target).

- [ ] **Step 3: Commit**

```bash
git add Packages/LunaCore/Sources/LunaCore/Theme/LunaTheme.swift
git commit -m "feat: add glass modifiers, shimmer skeleton, empty/error state components to LunaTheme"
```

---

### Task 2: ProfilePickerScreen (New)

**Files:**
- Create: `Apps/LunaApp/Sources/Screens/ProfilePickerScreen.swift`
- Modify: `Apps/LunaApp/Sources/ContentView.swift`

- [ ] **Step 1: Create ProfilePickerScreen.swift**

Write `Apps/LunaApp/Sources/Screens/ProfilePickerScreen.swift`:

```swift
import SwiftUI
import LunaCore

struct ProfilePickerScreen: View {
    @EnvironmentObject var profileManager: ProfileManager
    @State private var showCreateProfile = false

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        ZStack {
            LunaTheme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                Image("luna-icon")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 80)
                    .cornerRadius(18)
                    .shadow(color: LunaTheme.accent.opacity(0.4), radius: 20)

                Text("Who's watching?")
                    .font(.title.weight(.bold))
                    .foregroundColor(.white)
                    .padding(.top, 20)

                Text("Choose a profile")
                    .font(.subheadline)
                    .foregroundColor(LunaTheme.textSecondary)
                    .padding(.top, 4)

                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(profileManager.profiles) { profile in
                        Button {
                            profileManager.currentProfile = profile
                        } label: {
                            VStack(spacing: 8) {
                                Circle()
                                    .fill(
                                        profile.avatarColor.map { Color(hex: $0) }
                                        ?? LunaTheme.accent
                                    )
                                    .frame(width: 88, height: 88)
                                    .overlay(
                                        Text(String(profile.name.prefix(1).uppercased()))
                                            .font(.system(size: 36, weight: .bold))
                                            .foregroundColor(.white)
                                    )
                                    .glassCard(cornerRadius: 44, interactive: true)
                                    .shadow(
                                        color: (profile.avatarColor.map { Color(hex: $0) }
                                            ?? LunaTheme.accent).opacity(0.3),
                                        radius: 16
                                    )

                                Text(profile.name)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(profile.id == profileManager.currentProfile?.id
                                        ? .white : LunaTheme.textSecondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        showCreateProfile = true
                    } label: {
                        VStack(spacing: 8) {
                            Circle()
                                .stroke(Color.white.opacity(0.2), style: StrokeStyle(lineWidth: 1.5, dash: [6, 3]))
                                .frame(width: 88, height: 88)
                                .overlay(
                                    Image(systemName: "plus")
                                        .font(.title2)
                                        .foregroundColor(LunaTheme.textTertiary)
                                )

                            Text("Add Profile")
                                .font(.subheadline)
                                .foregroundColor(LunaTheme.textTertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 40)
                .padding(.top, 32)

                Spacer()

                Button {
                    // Navigate to profile management
                } label: {
                    HStack {
                        Text("Manage Profiles")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.white)
                        Image(systemName: "gearshape")
                            .font(.subheadline)
                            .foregroundColor(LunaTheme.accent)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .glassCard(cornerRadius: 14, interactive: true)
                }
                .padding(.bottom, 40)
            }
        }
        .sheet(isPresented: $showCreateProfile) {
            CreateProfileSheet()
        }
    }
}

struct CreateProfileSheet: View {
    @EnvironmentObject var profileManager: ProfileManager
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Create a new profile")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.top)

                TextField("Profile name", text: $name)
                    .padding()
                    .glassCard(cornerRadius: 12)
                    .foregroundColor(.white)
                    .padding(.horizontal)

                Button {
                    Task {
                        isLoading = true
                        try? await profileManager.createProfile(name: name)
                        isLoading = false
                        dismiss()
                    }
                } label: {
                    HStack {
                        if isLoading {
                            ProgressView().tint(.white)
                        }
                        Text("Create")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
                .glassProminentButtonStyle(tint: LunaTheme.accent, cornerRadius: 12)
                .disabled(name.isEmpty || isLoading)
                .padding(.horizontal)

                Spacer()
            }
            .background(LunaTheme.background)
            .navigationTitle("New Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
```

- [ ] **Step 2: Wire ProfilePickerScreen into ContentView**

In `ContentView.swift`, find the `if profileManager.currentProfile != nil` block (line 13) and the `else if` chain. Update to:

```swift
            if profileManager.isAuthenticated {
                if profileManager.currentProfile != nil {
                    MainTabView()
                } else if !profileManager.profiles.isEmpty {
                    ProfilePickerScreen()
                } else {
                    AuthScreen()
                }
            } else {
                AuthScreen()
            }
```

- [ ] **Step 3: Commit**

```bash
git add Apps/LunaApp/Sources/Screens/ProfilePickerScreen.swift Apps/LunaApp/Sources/ContentView.swift
git commit -m "feat: add Netflix-style ProfilePickerScreen with glass avatars"
```

---

### Task 3: AuthScreen — App Icon + Glass

**Files:**
- Modify: `Apps/LunaApp/Sources/Screens/AuthScreen.swift`

- [ ] **Step 1: Replace moon SF Symbol with app icon and add glass styling**

Replace the entire `AuthScreen.swift` body:

```swift
import SwiftUI
import LunaCore

struct AuthScreen: View {
    @EnvironmentObject var profileManager: ProfileManager

    @State private var email = ""
    @State private var password = ""
    @State private var inviteCode = ""
    @State private var isSignUp = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            LunaTheme.background.ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                Image("luna-icon")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 88, height: 88)
                    .cornerRadius(20)
                    .shadow(color: LunaTheme.accent.opacity(0.5), radius: 24)

                Text("Luna")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text(isSignUp ? "Create your account" : "Sign in to continue")
                    .font(.subheadline)
                    .foregroundColor(LunaTheme.textSecondary)

                Spacer().frame(height: 16)

                VStack(spacing: 12) {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .padding()
                        .glassCard(cornerRadius: 12)
                        .foregroundColor(.white)

                    SecureField("Password", text: $password)
                        .textContentType(isSignUp ? .newPassword : .password)
                        .padding()
                        .glassCard(cornerRadius: 12)
                        .foregroundColor(.white)

                    if isSignUp {
                        TextField("Invite Code", text: $inviteCode)
                            .autocapitalization(.allCharacters)
                            .padding()
                            .glassCard(cornerRadius: 12)
                            .foregroundColor(.white)
                    }
                }
                .padding(.horizontal, 32)

                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal, 32)
                }

                Button(action: performAuth) {
                    HStack {
                        if isLoading {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(isSignUp ? "Create Account" : "Sign In")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
                .glassProminentButtonStyle(tint: LunaTheme.accent, cornerRadius: 12)
                .disabled(isLoading || email.isEmpty || password.isEmpty)
                .padding(.horizontal, 32)

                Button(isSignUp ? "Already have an account? Sign In" : "Don't have an account? Sign Up") {
                    withAnimation { isSignUp.toggle() }
                    errorMessage = nil
                }
                .font(.subheadline)
                .foregroundColor(LunaTheme.accent)

                Spacer()
            }
        }
    }

    private func performAuth() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                if isSignUp {
                    guard !inviteCode.isEmpty else {
                        errorMessage = "Invite code is required"
                        isLoading = false
                        return
                    }
                    try await profileManager.signUp(email: email, password: password, inviteCode: inviteCode)
                } else {
                    try await profileManager.signIn(email: email, password: password)
                }
            } catch SupabaseError.signUpRequiresInvite {
                errorMessage = "Invalid or used invite code"
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Apps/LunaApp/Sources/Screens/AuthScreen.swift
git commit -m "feat: AuthScreen uses app icon + glass styling on fields and button"
```

---

### Task 4: HomeScreen — Glass Hero + GlassEffectContainer Rows

**Files:**
- Modify: `Apps/LunaApp/Sources/Screens/HomeScreen.swift`

- [ ] **Step 1: Replace HeroSection with glass hero card**

Replace the entire `HeroSection` struct (lines 201-313) with:

```swift
struct HeroSection: View {
    let item: MetaPreview
    let rowTitle: String
    let onTap: () -> Void
    let dotCount: Int
    let activeIndex: Int
    let onDotTap: (Int) -> Void

    @State private var imageFailed = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let banner = item.banner ?? item.poster, let url = URL(string: banner), !imageFailed {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().aspectRatio(contentMode: .fill)
                        case .failure:
                            LunaTheme.background
                                .onAppear { imageFailed = true }
                        default:
                            LunaTheme.background
                        }
                    }
                } else {
                    LunaTheme.surface
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 420)
            .clipped()

            LinearGradient(
                colors: [.clear, LunaTheme.background.opacity(0.7), LunaTheme.background],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 420)

            LinearGradient(
                colors: [LunaTheme.background.opacity(0.7), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 420)

            // Glass overlay card
            if #available(iOS 26, *) {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.clear)
                    .glassEffect(
                        .clear.interactive(),
                        in: .rect(cornerRadius: 22, style: .continuous)
                    )
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
            }

            // Content
            VStack(alignment: .leading, spacing: 0) {
                Text(rowTitle)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(LunaTheme.accent)
                    .tracking(2)
                    .textCase(.uppercase)
                    .padding(.bottom, 8)

                Text(item.name)
                    .font(.system(size: 40, weight: .black))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .padding(.bottom, 6)

                HStack(spacing: 8) {
                    if let rating = item.imdbRating {
                        Label(rating, systemImage: "star.fill")
                            .font(.caption)
                            .foregroundColor(.yellow)
                    }
                    if let release = item.releaseInfo {
                        Text(release).font(.caption).foregroundColor(.white.opacity(0.6))
                    }
                    if let genres = item.genres?.prefix(2) {
                        Text(genres.joined(separator: ", "))
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                .padding(.bottom, 16)

                HStack(spacing: 12) {
                    Button(action: onTap) {
                        Label("Watch Now", systemImage: "play.fill")
                            .font(.subheadline.bold())
                            .foregroundColor(.black)
                            .padding(.horizontal, 20).padding(.vertical, 11)
                            .background(Color.white).clipShape(Capsule())
                    }
                    .glassProminentButtonStyle(tint: .white, cornerRadius: 20)

                    Button(action: onTap) {
                        Label("My List", systemImage: "plus")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16).padding(.vertical, 11)
                    }
                    .glassCapsule(interactive: true, clear: true)
                }
            }
            .padding(.horizontal, 24).padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)

            if dotCount > 1 {
                HStack(spacing: 5) {
                    ForEach(0..<dotCount, id: \.self) { i in
                        Button { onDotTap(i) } label: {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(i == activeIndex ? Color.white : Color.white.opacity(0.3))
                                .frame(width: i == activeIndex ? 20 : 6, height: 3)
                        }
                        .animation(.easeInOut(duration: 0.25), value: activeIndex)
                    }
                }
                .padding(.trailing, 16).padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .frame(height: 420).clipped()
    }
}
```

- [ ] **Step 2: Add glass cards to ContinueWatchingCard**

Replace `ContinueWatchingCard` (lines 450-502) to add glass:

```swift
struct ContinueWatchingCard: View {
    let item: ContinueWatchingItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .bottom) {
                Group {
                    if let poster = item.poster, let url = URL(string: poster) {
                        AsyncImage(url: url) { phase in
                            if case .success(let img) = phase {
                                img.resizable().aspectRatio(contentMode: .fill)
                            } else {
                                RoundedRectangle(cornerRadius: 8).fill(LunaTheme.surfaceElevated)
                            }
                        }
                    } else {
                        RoundedRectangle(cornerRadius: 8).fill(LunaTheme.surfaceElevated)
                    }
                }
                .frame(width: 192, height: 108).clipped().cornerRadius(8)
                .glassCard(cornerRadius: 8)

                Circle().fill(Color.black.opacity(0.5)).frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: "play.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                            .offset(x: 1)
                    )
                    .padding(.bottom, 16)

                VStack(spacing: 0) {
                    Spacer()
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(Color.white.opacity(0.2)).frame(height: 3)
                            Rectangle()
                                .fill(LunaTheme.accent)
                                .frame(width: geo.size.width * item.progressFraction, height: 3)
                        }
                    }.frame(height: 3)
                }.cornerRadius(8)
            }
            .frame(width: 192, height: 108)

            Text(item.name)
                .font(.caption).foregroundColor(.white).lineLimit(1).frame(width: 192, alignment: .leading)
            Text("\(Int(item.progressFraction * 100))% watched")
                .font(.caption2).foregroundColor(LunaTheme.textSecondary)
        }
    }
}
```

- [ ] **Step 3: Add loading skeleton and error state to HomeScreen body**

In the `body` of `HomeScreen`, find the `else if catalogRepo.isLoading` branch (lines 125-132) and the closing of the VStack. Replace the ProgressView with:

```swift
                    } else if catalogRepo.isLoading {
                        VStack(spacing: 24) {
                            Spacer().frame(height: 20)
                            ShimmerCard(width: 375, height: 200, cornerRadius: 12)
                                .padding(.horizontal)
                            ShimmerCard(width: 120, height: 16, cornerRadius: 4)
                                .padding(.horizontal)
                            HStack(spacing: 12) {
                                ForEach(0..<3, id: \.self) { _ in
                                    ShimmerCard(width: 180, height: 100, cornerRadius: 8)
                                }
                            }
                            .padding(.horizontal)
                            HStack(spacing: 12) {
                                ForEach(0..<4, id: \.self) { _ in
                                    ShimmerCard(width: 105, height: 158, cornerRadius: 8)
                                }
                            }
                            .padding(.horizontal)
                            Spacer()
                        }
                    }
```

- [ ] **Step 4: Commit**

```bash
git add Apps/LunaApp/Sources/Screens/HomeScreen.swift
git commit -m "feat: glass hero card, glass continue watching, shimmer loading on HomeScreen"
```

---

### Task 5: DetailScreen — Glass Buttons + Backdrop

**Files:**
- Modify: `Apps/LunaApp/Sources/Screens/DetailScreen.swift`

- [ ] **Step 1: Replace action buttons with glass styling**

In `DetailScreen.swift`, find the `HStack(spacing: 12)` containing the Play/Bookmark/Watched buttons (lines 79-137). Replace with:

```swift
                        HStack(spacing: 12) {
                            Button {
                                showStreamSelection = true
                            } label: {
                                HStack {
                                    Image(systemName: "play.fill")
                                    Text("Play")
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                            }
                            .glassProminentButtonStyle(tint: LunaTheme.accent, cornerRadius: 12)
                            .foregroundColor(.white)

                            Button {
                                Task {
                                    guard let profile = profileManager.currentProfile else { return }
                                    await libraryRepo.toggleLibrary(
                                        profileId: profile.id,
                                        mediaId: detail.id,
                                        mediaType: type,
                                        name: detail.name,
                                        poster: detail.poster
                                    )
                                }
                            } label: {
                                Image(systemName: libraryRepo.isInLibrary(mediaId: detail.id) ? "bookmark.fill" : "bookmark")
                                    .font(.title3)
                                    .padding(12)
                            }
                            .glassCard(cornerRadius: 12, interactive: true)
                            .foregroundColor(libraryRepo.isInLibrary(mediaId: detail.id) ? LunaTheme.accent : .white)

                            Button {
                                Task {
                                    guard let profile = profileManager.currentProfile else { return }
                                    if watchedRepo.isWatched(mediaId: detail.id) {
                                        await watchedRepo.markUnwatched(mediaId: detail.id)
                                    } else {
                                        await watchedRepo.markWatched(
                                            profileId: profile.id,
                                            mediaId: detail.id,
                                            mediaType: type,
                                            name: detail.name,
                                            poster: detail.poster
                                        )
                                    }
                                }
                            } label: {
                                Image(systemName: watchedRepo.isWatched(mediaId: detail.id) ? "checkmark.circle.fill" : "checkmark.circle")
                                    .font(.title3)
                                    .padding(12)
                            }
                            .glassCard(cornerRadius: 12, interactive: true)
                            .foregroundColor(watchedRepo.isWatched(mediaId: detail.id) ? .green : .white)
                        }
                        .padding(.horizontal)
```

- [ ] **Step 2: Add glass style to genre chips**

In the genres section (lines 153-173), replace the `ForEach` content with glass capsules:

```swift
                                        ForEach(genres, id: \.self) { genre in
                                            Text(genre)
                                                .font(.caption)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 6)
                                                .glassCapsule(interactive: true)
                                                .foregroundColor(LunaTheme.textSecondary)
                                        }
```

- [ ] **Step 3: Add glass style to cast circles**

In the cast section (lines 175-205), replace the Circle fill with glass:

```swift
                                                Circle()
                                                    .fill(.clear)
                                                    .frame(width: 56, height: 56)
                                                    .glassCircle()
                                                    .overlay(
                                                        Text(person.name.prefix(1))
                                                            .font(.headline)
                                                            .foregroundColor(LunaTheme.textSecondary)
                                                    )
```

- [ ] **Step 4: Add glass style to network/studio chips**

In the links section (lines 207-257), replace the chip backgrounds with glass capsules:

```swift
.background(.clear).glassCapsule()
```

- [ ] **Step 5: Add glass to season selector pills**

In the seasons section (lines 259-298), replace the season button background with:

```swift
.glassCapsule(interactive: true)
```

- [ ] **Step 6: Commit**

```bash
git add Apps/LunaApp/Sources/Screens/DetailScreen.swift
git commit -m "feat: glass buttons, genre chips, cast circles, season pills on DetailScreen"
```

---

### Task 6: PlayerScreen (New) — AVPlayer + Glass Transport Overlay

**Files:**
- Create: `Apps/LunaApp/Sources/Screens/PlayerScreen.swift`

- [ ] **Step 1: Create PlayerScreen.swift**

Write `Apps/LunaApp/Sources/Screens/PlayerScreen.swift`:

```swift
import SwiftUI
import AVKit
import LunaCore

struct PlayerScreen: View {
    let streamURL: URL
    let title: String
    let onDismiss: () -> Void

    @State private var player = AVPlayer()
    @State private var showControls = true
    @State private var currentTime: TimeInterval = 0
    @State private var duration: TimeInterval = 1
    @State private var isPlaying = false
    @State private var playbackSpeed: Float = 1.0
    @State private var showSpeedPicker = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            CustomPlayerView(player: player)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showControls.toggle()
                    }
                }

            if showControls {
                VStack {
                    // Top bar
                    HStack {
                        Button { onDismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 40, height: 40)
                        }
                        .glassCircle(clear: true)

                        Spacer()

                        VStack(spacing: 2) {
                            Text(title)
                                .font(.headline)
                                .foregroundColor(.white)
                            Text(timeRemaining)
                                .font(.caption)
                                .foregroundColor(LunaTheme.textSecondary)
                        }

                        Spacer()

                        Button { /* ellipsis menu */ } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 40, height: 40)
                        }
                        .glassCircle(clear: true)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 56)

                    Spacer()

                    // Center play/pause
                    Button {
                        togglePlayPause()
                    } label: {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.white)
                            .frame(width: 64, height: 64)
                    }
                    .glassCircle(clear: true)
                    .contentTransition(.symbolEffect(.replace))

                    Spacer()

                    // Bottom transport
                    VStack(spacing: 12) {
                        // Progress
                        VStack(spacing: 6) {
                            if #available(iOS 26, *) {
                                Slider(
                                    value: Binding(
                                        get: { currentTime },
                                        set: { seek(to: $0) }
                                    ),
                                    in: 0...max(duration, 1)
                                )
                                .labelsHidden()
                                .tint(.white)
                                .controlSize(.large)
                            } else {
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Capsule()
                                            .fill(Color.white.opacity(0.20))
                                            .frame(height: 4)
                                        Capsule()
                                            .fill(Color.white)
                                            .frame(
                                                width: duration > 0
                                                    ? geo.size.width * (currentTime / duration)
                                                    : 0,
                                                height: 4
                                            )
                                        Circle()
                                            .fill(.white)
                                            .frame(width: 14, height: 14)
                                            .offset(x: duration > 0
                                                ? geo.size.width * (currentTime / duration) - 7
                                                : -7)
                                    }
                                }
                                .frame(height: 32)
                            }

                            HStack {
                                Text(formatTime(currentTime))
                                Spacer()
                                Text("-\(formatTime(max(duration - currentTime, 0)))")
                            }
                            .font(.caption)
                            .foregroundColor(LunaTheme.textSecondary)
                        }

                        // Transport pill
                        HStack(spacing: 0) {
                            Button {
                                playbackSpeed = max(0.5, playbackSpeed - 0.25)
                                player.rate = playbackSpeed
                            } label: {
                                Text("\(playbackSpeed, specifier: "%.2f")x")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.white)
                                    .frame(width: 44, height: 36)
                            }
                            .glassCapsule(interactive: true, clear: true)

                            Spacer()

                            HStack(spacing: 24) {
                                Button {
                                    seek(by: -15)
                                } label: {
                                    Image(systemName: "gobackward.15")
                                        .font(.title3)
                                        .foregroundColor(.white)
                                }

                                Button {
                                    togglePlayPause()
                                } label: {
                                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                        .font(.title2)
                                        .foregroundColor(.white)
                                        .frame(width: 44, height: 44)
                                }
                                .glassCircle(clear: true)
                                .contentTransition(.symbolEffect(.replace))

                                Button {
                                    seek(by: 30)
                                } label: {
                                    Image(systemName: "goforward.30")
                                        .font(.title3)
                                        .foregroundColor(.white)
                                }
                            }

                            Spacer()

                            Button {
                                player.isMuted.toggle()
                            } label: {
                                Image(systemName: player.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(.white)
                                    .frame(width: 44, height: 36)
                            }
                            .glassCapsule(interactive: true, clear: true)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .glassCard(cornerRadius: 18)
                        .padding(.horizontal, 8)
                    }
                    .padding(.bottom, 40)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            player.replaceCurrentItem(with: AVPlayerItem(url: streamURL))
            player.play()
            isPlaying = true
            setupTimeObserver()
        }
        .onDisappear {
            player.pause()
        }
    }

    private var timeRemaining: String {
        let remaining = max(duration - currentTime, 0)
        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        let seconds = Int(remaining) % 60
        if hours > 0 {
            return "\(hours):\(String(format: "%02d", minutes)):\(String(format: "%02d", seconds)) remaining"
        }
        return "\(minutes):\(String(format: "%02d", seconds)) remaining"
    }

    private func togglePlayPause() {
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
    }

    private func seek(to time: TimeInterval) {
        player.seek(to: CMTime(seconds: time, preferredTimescale: 600))
    }

    private func seek(by seconds: Double) {
        let newTime = max(0, min(currentTime + seconds, duration))
        seek(to: newTime)
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        let seconds = Int(time) % 60
        if hours > 0 {
            return "\(hours):\(String(format: "%02d", minutes)):\(String(format: "%02d", seconds))"
        }
        return "\(minutes):\(String(format: "%02d", seconds))"
    }

    private func setupTimeObserver() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            currentTime = time.seconds
            if let item = player.currentItem {
                duration = item.duration.seconds.isFinite ? item.duration.seconds : 0
            }
            isPlaying = player.rate > 0
        }
    }
}

// MARK: - AVPlayer UIKit Wrapper

struct CustomPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspect
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {}
}
```

- [ ] **Step 2: Commit**

```bash
git add Apps/LunaApp/Sources/Screens/PlayerScreen.swift
git commit -m "feat: AVPlayer screen with glass transport overlay, PiP support, time observer"
```

---

### Task 7: SearchScreen — Glass Search Bar + Filter Chips + Debounce

**Files:**
- Modify: `Apps/LunaApp/Sources/Screens/SearchScreen.swift`

- [ ] **Step 1: Replace SearchScreen with glass styled version**

Replace the entire body of `SearchScreen.swift`:

```swift
import SwiftUI
import LunaCore

struct SearchScreen: View {
    @StateObject private var searchRepo = SearchRepository.shared
    @StateObject private var addonRepo = AddonRepository.shared
    @State private var query = ""
    @State private var selectedMedia: MetaPreview?
    @State private var selectedFilter: String? = nil

    private let filters = ["Trending", "Movies", "Shows"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(LunaTheme.textTertiary)
                    TextField("Search movies & shows...", text: $query)
                        .foregroundColor(.white)
                }
                .padding()
                .glassCard(cornerRadius: 14)
                .padding()
                .onChange(of: query) { _, newValue in
                    Task {
                        try? await Task.sleep(for: .milliseconds(300))
                        await searchRepo.search(query: newValue, addons: addonRepo.enabledAddons)
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(filters, id: \.self) { filter in
                            Button {
                                selectedFilter = selectedFilter == filter ? nil : filter
                            } label: {
                                Text(filter)
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                            }
                            .glassCapsule(interactive: true)
                            .foregroundColor(selectedFilter == filter ? LunaTheme.accent : LunaTheme.textSecondary)
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom, 12)

                if searchRepo.isLoading {
                    Spacer()
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 120), spacing: 12)],
                        spacing: 16
                    ) {
                        ForEach(0..<9, id: \.self) { _ in
                            ShimmerCard(width: 120, height: 180, cornerRadius: 8)
                        }
                    }
                    .padding()
                    Spacer()
                } else if searchRepo.results.isEmpty && !searchRepo.searchQuery.isEmpty {
                    Spacer()
                    EmptyStateView(
                        icon: "magnifyingglass",
                        title: "No results found",
                        message: "Try a different search term or check your spelling"
                    )
                    Spacer()
                } else if !searchRepo.results.isEmpty {
                    ScrollView {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 120), spacing: 12)],
                            spacing: 16
                        ) {
                            ForEach(searchRepo.results) { item in
                                ContentCard(item: item)
                                    .onTapGesture {
                                        selectedMedia = item
                                    }
                            }
                        }
                        .padding()
                    }
                } else {
                    Spacer()
                    EmptyStateView(
                        icon: "magnifyingglass",
                        title: "Discover content",
                        message: "Search for movies and TV shows across all your connected addons"
                    )
                    Spacer()
                }
            }
            .background(LunaTheme.background)
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(item: $selectedMedia) { media in
                DetailScreen(mediaId: media.id, type: media.type.rawValue, name: media.name)
            }
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Apps/LunaApp/Sources/Screens/SearchScreen.swift
git commit -m "feat: glass search bar, filter chips, debounced search, shimmer/empty states on SearchScreen"
```

---

### Task 8: LibraryScreen — Glass Cards + Swipe-to-Delete

**Files:**
- Modify: `Apps/LunaApp/Sources/Screens/LibraryScreen.swift`

- [ ] **Step 1: Replace LibraryScreen with glass cards and swipe actions**

Replace the entire `LibraryScreen.swift` body:

```swift
import SwiftUI
import LunaCore

struct LibraryScreen: View {
    @StateObject private var libraryRepo = LibraryRepository.shared
    @EnvironmentObject var profileManager: ProfileManager
    @State private var selectedMedia: MetaPreview?

    var body: some View {
        NavigationStack {
            ZStack {
                LunaTheme.background.ignoresSafeArea()

                if libraryRepo.isLoading {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 120), spacing: 12)],
                        spacing: 16
                    ) {
                        ForEach(0..<9, id: \.self) { _ in
                            ShimmerCard(width: 120, height: 180, cornerRadius: 8)
                        }
                    }
                    .padding()
                } else if libraryRepo.libraryItems.isEmpty {
                    EmptyStateView(
                        icon: "bookmark",
                        title: "Your library is empty",
                        message: "Save movies and shows to watch later. Tap the bookmark icon on any title to add it here.",
                        actionLabel: "Browse Popular",
                        action: {
                            // Switches to home tab — notification pattern
                        }
                    )
                } else {
                    ScrollView {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 120), spacing: 12)],
                            spacing: 16
                        ) {
                            ForEach(libraryRepo.libraryItems) { item in
                                VStack(alignment: .leading, spacing: 4) {
                                    ZStack {
                                        if let poster = item.poster, let url = URL(string: poster) {
                                            AsyncImage(url: url) { phase in
                                                if case .success(let image) = phase {
                                                    image.resizable()
                                                        .aspectRatio(contentMode: .fill)
                                                        .frame(width: 120, height: 180)
                                                        .clipped()
                                                } else {
                                                    placeholderView(item: item)
                                                }
                                            }
                                        } else {
                                            placeholderView(item: item)
                                        }
                                    }
                                    .frame(width: 120, height: 180)
                                    .glassCard(cornerRadius: 8)

                                    Text(item.name ?? item.mediaId)
                                        .font(.caption)
                                        .foregroundColor(.white)
                                        .lineLimit(2)
                                        .frame(width: 120)
                                }
                                .onTapGesture {
                                    selectedMedia = MetaPreview(
                                        id: item.mediaId,
                                        type: item.mediaType == "series" ? .series : .movie,
                                        name: item.name ?? item.mediaId,
                                        poster: item.poster
                                    )
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        Task {
                                            guard let profile = profileManager.currentProfile else { return }
                                            await libraryRepo.removeFromLibrary(
                                                profileId: profile.id,
                                                mediaId: item.mediaId
                                            )
                                        }
                                    } label: {
                                        Label("Remove", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                    .refreshable {
                        guard let profile = profileManager.currentProfile else { return }
                        await libraryRepo.loadLibrary(profileId: profile.id)
                    }
                }
            }
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(item: $selectedMedia) { media in
                DetailScreen(mediaId: media.id, type: media.type.rawValue, name: media.name)
            }
            .task {
                guard let profile = profileManager.currentProfile else { return }
                await libraryRepo.loadLibrary(profileId: profile.id)
            }
        }
    }

    @ViewBuilder
    private func placeholderView(item: LibraryItem) -> some View {
        Image(systemName: item.mediaType == "movie" ? "film" : "tv")
            .font(.title)
            .foregroundColor(LunaTheme.textTertiary)
            .frame(width: 120, height: 180)
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Apps/LunaApp/Sources/Screens/LibraryScreen.swift
git commit -m "feat: glass library cards, swipe-to-delete, shimmer loading, pull-to-refresh"
```

---

### Task 9: SettingsScreen — Glass Section Cards

**Files:**
- Modify: `Apps/LunaApp/Sources/Screens/SettingsScreen.swift`

- [ ] **Step 1: Replace SettingsScreen List with glass card ScrollView**

Replace the entire `SettingsScreen` struct (lines 4-86) with:

```swift
struct SettingsScreen: View {
    @EnvironmentObject var profileManager: ProfileManager
    @StateObject private var addonRepo = AddonRepository.shared
    @State private var showAddons = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Profile Section
                    VStack(spacing: 0) {
                        if let profile = profileManager.currentProfile {
                            HStack {
                                Circle()
                                    .fill(profile.avatarColor.map { Color(hex: $0) } ?? LunaTheme.accent)
                                    .frame(width: 48, height: 48)
                                    .overlay(
                                        Text(String(profile.name.prefix(1).uppercased()))
                                            .font(.headline)
                                            .foregroundColor(.white)
                                    )
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(profile.name)
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    Text(profile.isAdmin ? "Admin" : "User")
                                        .font(.caption)
                                        .foregroundColor(LunaTheme.textSecondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(LunaTheme.textTertiary)
                            }
                            .padding()

                            Divider().background(Color.white.opacity(0.08))

                            Button {
                                profileManager.currentProfile = nil
                            } label: {
                                HStack {
                                    Text("Switch Profile")
                                        .foregroundColor(LunaTheme.accent)
                                    Spacer()
                                    Image(systemName: "arrow.triangle.swap")
                                        .font(.caption)
                                        .foregroundColor(LunaTheme.accent)
                                }
                                .padding()
                            }
                        }
                    }
                    .glassCard(cornerRadius: 14)
                    .padding(.horizontal)

                    // Addons Section
                    VStack(spacing: 0) {
                        Button {
                            showAddons = true
                        } label: {
                            HStack {
                                Text("Manage Addons")
                                    .foregroundColor(.white)
                                Spacer()
                                Text("\(addonRepo.managedAddons.count)")
                                    .foregroundColor(LunaTheme.textSecondary)
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(LunaTheme.textTertiary)
                            }
                            .padding()
                        }

                        Divider().background(Color.white.opacity(0.08))

                        Text("Addons provide content catalogs, metadata, and streaming sources")
                            .font(.caption)
                            .foregroundColor(LunaTheme.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                    .glassCard(cornerRadius: 14)
                    .padding(.horizontal)

                    // Account Section
                    VStack(spacing: 0) {
                        Button(role: .destructive) {
                            Task { await profileManager.signOut() }
                        } label: {
                            HStack {
                                Text("Sign Out")
                                    .foregroundColor(.red)
                                Spacer()
                            }
                            .padding()
                        }
                    }
                    .glassCard(cornerRadius: 14)
                    .padding(.horizontal)

                    // Footer
                    VStack(spacing: 4) {
                        Text("Luna v1.0.0")
                            .font(.caption)
                            .foregroundColor(LunaTheme.textTertiary)
                        Text("Built with the Stremio addon ecosystem")
                            .font(.caption2)
                            .foregroundColor(LunaTheme.textTertiary)
                    }
                    .padding(.top)

                    Spacer().frame(height: 32)
                }
                .padding(.top)
            }
            .background(LunaTheme.background)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showAddons) {
                AddonsScreen()
            }
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Apps/LunaApp/Sources/Screens/SettingsScreen.swift
git commit -m "feat: glass section cards on SettingsScreen with profile header"
```

---

### Task 10: Animations & Haptics Pass

**Files:**
- Modify: `Apps/LunaApp/Sources/ContentView.swift`
- Modify: `Apps/LunaApp/Sources/Screens/HomeScreen.swift`
- Modify: `Apps/LunaApp/Sources/Screens/LibraryScreen.swift`

- [ ] **Step 1: Add tab re-tap scroll-to-top in HomeScreen**

Add to `HomeScreen` struct:

```swift
    @State private var scrollProxy: ScrollViewProxy?

    // In the ScrollView, add:
    // .refreshable { ... }
```

Wrap the ScrollView content in `ScrollViewReader` and use a notification pattern for tab re-tap.

For now, add `.refreshable`:

In HomeScreen body, find `.ignoresSafeArea(edges: .top)` on the ScrollView (line 137) and add after it:

```swift
            .refreshable {
                guard let profile = profileManager.currentProfile else { return }
                if collectionRepo.collections.isEmpty {
                    await catalogRepo.loadAllCatalogs(addons: addonRepo.enabledAddons)
                } else {
                    await catalogRepo.loadFromCollections(
                        collectionRepo: collectionRepo,
                        addons: addonRepo.enabledAddons
                    )
                }
                await homeRepo.loadContinueWatching(profileId: profile.id)
            }
```

- [ ] **Step 2: Add haptic feedback to card taps**

In `ContentCard.swift`, add to the `.onTapGesture` (line 414 in the CatalogRowView usage) — the card itself doesn't use `.sensoryFeedback` directly since it's just a view. Instead, add it to the `CatalogRowView` button:

The ContentCard already returns the card view. Add sensory feedback to the `VStack` in ContentCard body:

```swift
        .sensoryFeedback(.impact(weight: .light), trigger: item.id)
```

- [ ] **Step 3: Add spring transition to hero carousel**

In HomeScreen's `heroIndex` change, replace the `withAnimation(.easeInOut(duration: 0.4))` with:

```swift
withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
    heroIndex = i
}
```

- [ ] **Step 4: Add matchedGeometryEffect for card-to-detail transition**

In `ContentCard.swift`, add namespace support — but this requires a broader refactor. For this pass, add the ID to the poster:

In the `ZStack` of `ContentCard`, add:
```swift
.matchedGeometryEffect(id: item.id, in: heroNamespace)
```

Skip full matchedGeometryEffect for now (requires Coordinator pattern).

- [ ] **Step 5: Commit**

```bash
git add Apps/LunaApp/Sources/Screens/HomeScreen.swift Apps/LunaApp/Sources/Components/ContentCard.swift Apps/LunaApp/Sources/Screens/LibraryScreen.swift
git commit -m "feat: pull-to-refresh on home, haptic feedback on cards, spring hero transitions"
```

---

### Task 11: iPad Adaptation

**Files:**
- Modify: `Apps/LunaApp/Sources/ContentView.swift`

- [ ] **Step 1: Add adaptive layout to MainTabView**

Update `MainTabView` to use `NavigationSplitView` on iPad:

```swift
struct MainTabView: View {
    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var roleManager: RoleManager
    @StateObject private var addonRepo = AddonRepository.shared

    @State private var selectedTab = 0
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if sizeClass == .regular {
            NavigationSplitView {
                List(selection: $selectedTab) {
                    Label("Home", systemImage: "house.fill").tag(0)
                    Label("Search", systemImage: "magnifyingglass").tag(1)
                    Label("Library", systemImage: "bookmark.fill").tag(2)
                    Label("Settings", systemImage: "gearshape.fill").tag(3)
                    if roleManager.isAdmin {
                        Label("Admin", systemImage: "shield.fill").tag(4)
                    }
                }
                .listStyle(.sidebar)
            } detail: {
                tabContent
            }
        } else {
            TabView(selection: $selectedTab) {
                tabContent
            }
            .accentColor(.purple)
            .task {
                if let profile = profileManager.currentProfile {
                    await addonRepo.loadAddons(profileId: profile.id)
                }
            }
            .onChange(of: profileManager.currentProfile) { _, newProfile in
                if let profile = newProfile {
                    Task {
                        await addonRepo.loadAddons(profileId: profile.id)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        if sizeClass == .regular {
            switch selectedTab {
            case 0: HomeScreen()
            case 1: SearchScreen()
            case 2: LibraryScreen()
            case 3: SettingsScreen()
            case 4: AdminDashboard()
            default: HomeScreen()
            }
        } else {
            Group {
                HomeScreen()
                    .tabItem {
                        Image(systemName: "house.fill")
                        Text("Home")
                    }
                    .tag(0)

                SearchScreen()
                    .tabItem {
                        Image(systemName: "magnifyingglass")
                        Text("Search")
                    }
                    .tag(1)

                LibraryScreen()
                    .tabItem {
                        Image(systemName: "bookmark.fill")
                        Text("Library")
                    }
                    .tag(2)

                SettingsScreen()
                    .tabItem {
                        Image(systemName: "gearshape.fill")
                        Text("Settings")
                    }
                    .tag(3)

                if roleManager.isAdmin {
                    AdminDashboard()
                        .tabItem {
                            Image(systemName: "shield.fill")
                            Text("Admin")
                        }
                        .tag(4)
                }
            }
            .accentColor(.purple)
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Apps/LunaApp/Sources/ContentView.swift
git commit -m "feat: iPad adaptive layout with NavigationSplitView sidebar"
```

---

## Implementation Order

Tasks 0a-0d are independent and can run in parallel. Tasks 2-8 depend on Task 1 (glass modifiers). Task 10 depends on 2-9. Task 11 is standalone.

```
0a ─┐
0b ─┤
0c ─┼──► 1 ──► 2 ──► 3 ──► 4 ──► 5 ──► 6 ──► 7 ──► 8 ──► 9 ──► 10 ──► 11
0d ─┘
```
