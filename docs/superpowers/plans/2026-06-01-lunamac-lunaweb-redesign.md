# LunaMac Redesign — LunaWeb Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign LunaMac to match LunaWeb's floating pill navbar layout, full feature set, and AVPlayer-based media player.

**Architecture:** Flatten NavigationSplitView into a ZStack-based shell with a floating pill navbar overlay. Port iOS screens to macOS with LunaWeb design patterns. All views consume existing LunaCore services (no data-layer changes). PlayerEngine gets subtitle loading + stream metadata parsing.

**Tech Stack:** SwiftUI 5.9+, macOS 14.0+, AVKit, LunaCore (shared Swift Package)

---

## Phase 1: LunaCore Foundations

### Task 1: Move LunaTheme into LunaCore

**Files:**
- Create: `Packages/LunaCore/Sources/LunaCore/Theme/LunaTheme.swift`
- Modify: `Apps/LunaApp/Sources/Components/LunaTheme.swift` (delete after move)
- Update all iOS file imports from `LunaTheme` to `import LunaCore`

- [ ] **Step 1: Create LunaTheme in LunaCore**

```swift
// Packages/LunaCore/Sources/LunaCore/Theme/LunaTheme.swift
import SwiftUI

public struct LunaTheme {
    public static let primary = Color.purple
    public static let secondary = Color.indigo
    public static let accent = Color(red: 0.8, green: 0.4, blue: 1.0)

    public static let background = Color(red: 0.05, green: 0.05, blue: 0.12)
    public static let surface = Color(red: 0.1, green: 0.1, blue: 0.18)
    public static let surfaceElevated = Color(red: 0.15, green: 0.15, blue: 0.22)

    public static let textPrimary = Color.white
    public static let textSecondary = Color.white.opacity(0.7)
    public static let textTertiary = Color.white.opacity(0.5)
}

public extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = ((int >> 24) & 0xFF, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
```

- [ ] **Step 2: Remove `public` from old LunaTheme so it compiles via LunaCore**

```bash
# Delete the old file, iOS app will use LunaCore's version
rm /Users/zain/projects/Luna/Apps/LunaApp/Sources/Components/LunaTheme.swift
```

- [ ] **Step 3: Verify iOS app still builds**

```bash
cd /Users/zain/projects/Luna && xcodebuild -scheme LunaApp -destination 'platform=iOS Simulator,name=iPhone 15' build 2>&1 | tail -5
```

- [ ] **Step 4: Commit**

```bash
git add Packages/LunaCore/Sources/LunaCore/Theme/ Apps/LunaApp/Sources/Components/LunaTheme.swift
git commit -m "refactor: move LunaTheme into LunaCore shared package"
```

### Task 2: Add StreamMetadata model to LunaCore

**Files:**
- Create: `Packages/LunaCore/Sources/LunaCore/Models/StreamMetadata.swift`

- [ ] **Step 1: Create StreamMetadata model**

```swift
// Packages/LunaCore/Sources/LunaCore/Models/StreamMetadata.swift
import Foundation

public struct StreamMetadata: Codable, Sendable {
    public let resolution: String?
    public let videoCodec: String?
    public let audioCodec: String?
    public let hdr: String?
    public let fileSize: String?
    public let debridSource: String?
    public let releaseGroup: String?

    public init(
        resolution: String? = nil,
        videoCodec: String? = nil,
        audioCodec: String? = nil,
        hdr: String? = nil,
        fileSize: String? = nil,
        debridSource: String? = nil,
        releaseGroup: String? = nil
    ) {
        self.resolution = resolution
        self.videoCodec = videoCodec
        self.audioCodec = audioCodec
        self.hdr = hdr
        self.fileSize = fileSize
        self.debridSource = debridSource
        self.releaseGroup = releaseGroup
    }

    public var resolutionBadgeColor: String {
        guard let res = resolution?.uppercased() else { return "default" }
        if res.contains("4K") || res.contains("2160") { return "yellow" }
        if res.contains("1080") { return "blue" }
        if res.contains("720") { return "green" }
        return "default"
    }
}

public extension StreamItem {
    func parseMetadata() -> StreamMetadata {
        let desc = description ?? ""
        var meta = StreamMetadata()

        let resPatterns = ["4K", "2160p", "1080p", "720p", "480p"]
        for r in resPatterns {
            if desc.localizedCaseInsensitiveContains(r) {
                meta = StreamMetadata(resolution: r, videoCodec: meta.videoCodec,
                    audioCodec: meta.audioCodec, hdr: meta.hdr,
                    fileSize: meta.fileSize, debridSource: meta.debridSource,
                    releaseGroup: meta.releaseGroup)
                break
            }
        }

        let hdrPatterns = ["HDR10", "Dolby Vision", "DV", "HDR10+", "HDR"]
        for h in hdrPatterns {
            if desc.localizedCaseInsensitiveContains(h) {
                meta = StreamMetadata(resolution: meta.resolution, videoCodec: meta.videoCodec,
                    audioCodec: meta.audioCodec, hdr: h == "DV" ? "Dolby Vision" : h,
                    fileSize: meta.fileSize, debridSource: meta.debridSource,
                    releaseGroup: meta.releaseGroup)
                break
            }
        }

        let codecPatterns = ["HEVC", "x265", "H265", "AVC", "x264", "H264", "AV1", "VP9"]
        for c in codecPatterns {
            if desc.localizedCaseInsensitiveContains(c) {
                let codec = c.hasPrefix("x") ? "H.\(c.dropFirst())" : c
                if meta.videoCodec == nil {
                    meta = StreamMetadata(resolution: meta.resolution, videoCodec: codec,
                        audioCodec: meta.audioCodec, hdr: meta.hdr,
                        fileSize: meta.fileSize, debridSource: meta.debridSource,
                        releaseGroup: meta.releaseGroup)
                } else if meta.audioCodec == nil && (c == "AAC" || c == "EAC3" || c == "AC3" || c == "DTS" || c == "FLAC" || c == "OPUS") {
                    meta = StreamMetadata(resolution: meta.resolution, videoCodec: meta.videoCodec,
                        audioCodec: codec, hdr: meta.hdr,
                        fileSize: meta.fileSize, debridSource: meta.debridSource,
                        releaseGroup: meta.releaseGroup)
                }
                break
            }
        }

        let audioPatterns = ["AAC", "EAC3", "AC3", "Dolby Atmos", "DTS-HD", "DTS", "FLAC", "OPUS", "TrueHD", "MP3"]
        for a in audioPatterns {
            if desc.localizedCaseInsensitiveContains(a) {
                if meta.audioCodec == nil {
                    meta = StreamMetadata(resolution: meta.resolution, videoCodec: meta.videoCodec,
                        audioCodec: a, hdr: meta.hdr,
                        fileSize: meta.fileSize, debridSource: meta.debridSource,
                        releaseGroup: meta.releaseGroup)
                }
                break
            }
        }

        let sizePattern = try? NSRegularExpression(pattern: "(\\d+(\\.\\d+)?)\\s*(GB|MB|GiB|MiB)", options: .caseInsensitive)
        if let match = sizePattern?.firstMatch(in: desc, range: NSRange(desc.startIndex..., in: desc)) {
            if let range = Range(match.range, in: desc) {
                meta = StreamMetadata(resolution: meta.resolution, videoCodec: meta.videoCodec,
                    audioCodec: meta.audioCodec, hdr: meta.hdr,
                    fileSize: String(desc[range]), debridSource: meta.debridSource,
                    releaseGroup: meta.releaseGroup)
            }
        }

        let debridPatterns = ["Real-Debrid", "AllDebrid", "Premiumize", "TorBox", "Debrid-Link", "RD+", "AD+", "DL+"]
        for d in debridPatterns {
            if desc.localizedCaseInsensitiveContains(d) {
                meta = StreamMetadata(resolution: meta.resolution, videoCodec: meta.videoCodec,
                    audioCodec: meta.audioCodec, hdr: meta.hdr,
                    fileSize: meta.fileSize, debridSource: d,
                    releaseGroup: meta.releaseGroup)
                break
            }
        }

        return meta
    }
}
```

- [ ] **Step 2: Verify LunaCore compiles**

```bash
cd /Users/zain/projects/Luna && xcodebuild -scheme LunaCore build 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add Packages/LunaCore/Sources/LunaCore/Models/StreamMetadata.swift
git commit -m "feat: add StreamMetadata model with parseMetadata extension on StreamItem"
```

### Task 3: Expand PlayerEngine — subtitle loading + skip adjustments

**Files:**
- Modify: `Packages/LunaCore/Sources/LunaCore/Player/PlayerEngine.swift`

- [ ] **Step 1: Add subtitle loading + 15s skip + published audio/subtitle metadata**

Read current file then apply edits. Add these published properties and methods:

Add inside the class after `@Published public var selectedSubtitle: SubtitleItem?`:
```swift
@Published public var availableAudioTracks: [String] = []
@Published public var selectedAudioTrack: String?
@Published public var isMuted = false
```

Add new methods after `skipBack()`:
```swift
public func skipForward15() {
    seekBy(15)
}

public func skipBack15() {
    seekBy(-15)
}

public func toggleMute() {
    isMuted.toggle()
    player?.isMuted = isMuted
}

public func loadSubtitles(from subtitles: [SubtitleItem]) {
    availableSubtitles = subtitles
    if selectedSubtitle == nil {
        selectedSubtitle = subtitles.first
    }
}

public func cycleSubtitle() {
    guard !availableSubtitles.isEmpty else { return }
    if let current = selectedSubtitle,
       let idx = availableSubtitles.firstIndex(where: { $0.id == current.id }) {
        let next = (idx + 1) % availableSubtitles.count
        selectedSubtitle = availableSubtitles[next]
    } else {
        selectedSubtitle = availableSubtitles.first
    }
}

public func setSubtitle(_ subtitle: SubtitleItem?) {
    selectedSubtitle = subtitle
}
```

Also update the `launch` method to load subtitles from launch metadata. Add after `self.player = player`:
```swift
if let subs = launch.subtitles, !subs.isEmpty {
    self.availableSubtitles = subs
    self.selectedSubtitle = subs.first
}
```

- [ ] **Step 2: Verify LunaCore compiles**

```bash
cd /Users/zain/projects/Luna && xcodebuild -scheme LunaCore build 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add Packages/LunaCore/Sources/LunaCore/Player/PlayerEngine.swift
git commit -m "feat: add subtitle loading, mute toggle, 15s skip to PlayerEngine"
```

---

## Phase 2: macOS App Shell

### Task 4: Update LunaMacApp — borderless window

**Files:**
- Modify: `Apps/LunaMac/Sources/LunaMacApp.swift`

- [ ] **Step 1: Rewrite LunaMacApp for fully borderless window**

```swift
import SwiftUI
import LunaCore

@main
struct LunaMacApp: App {
    @StateObject private var profileManager = ProfileManager.shared
    @StateObject private var roleManager = RoleManager.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            MacContentView()
                .environmentObject(profileManager)
                .environmentObject(roleManager)
                .frame(minWidth: 900, minHeight: 600)
                .background(LunaTheme.background)
                .onAppear {
                    configureWindow()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1200, height: 800)
    }

    private func configureWindow() {
        guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue == nil || $0.identifier?.rawValue == "luna-main" }) else { return }
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor(red: 0.05, green: 0.05, blue: 0.12, alpha: 1.0)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let window = NSApp.windows.first {
            window.identifier = NSUserInterfaceItemIdentifier("luna-main")
        }
    }
}
```

- [ ] **Step 2: Verify macOS app builds**

```bash
cd /Users/zain/projects/Luna && xcodebuild -scheme LunaMac -destination 'platform=macOS' build 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add Apps/LunaMac/Sources/LunaMacApp.swift
git commit -m "feat: fully borderless window with custom traffic light positioning"
```

### Task 5: Create PillNavBar component

**Files:**
- Create: `Apps/LunaMac/Sources/Components/PillNavBar.swift`

- [ ] **Step 1: Create PillNavBar**

```swift
import SwiftUI
import LunaCore

enum MacMainTab: String, CaseIterable {
    case home, search, library, settings, admin

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .search: return "magnifyingglass"
        case .library: return "book.fill"
        case .settings: return "gear"
        case .admin: return "shield.fill"
        }
    }

    var label: String {
        switch self {
        case .home: return "Home"
        case .search: return "Search"
        case .library: return "Library"
        case .settings: return "Settings"
        case .admin: return "Admin"
        }
    }
}

struct PillNavBar: View {
    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var roleManager: RoleManager
    @Binding var selectedTab: MacMainTab

    private var visibleTabs: [MacMainTab] {
        var tabs: [MacMainTab] = [.home, .search, .library, .settings]
        if roleManager.isAdmin { tabs.append(.admin) }
        return tabs
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(visibleTabs, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selectedTab = tab
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 13, weight: .medium))
                        Text(tab.label)
                            .font(.system(size: 13, weight: selectedTab == tab ? .semibold : .medium))
                    }
                    .foregroundColor(selectedTab == tab ? .white : .white.opacity(0.5))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        selectedTab == tab
                            ? Capsule().fill(Color.white.opacity(0.12))
                            : Capsule().fill(Color.clear)
                    )
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    if hovering && selectedTab != tab {
                        // subtle hover feedback is implicit via SwiftUI
                    }
                }
            }

            // Separator
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(width: 1, height: 20)
                .padding(.horizontal, 8)

            // Profile button
            Button {
                profileManager.currentProfile = nil
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(profileManager.currentProfile?.avatarColor.map { Color(hex: $0) } ?? LunaTheme.accent)
                        .frame(width: 24, height: 24)
                        .overlay(
                            Text(String(profileManager.currentProfile?.name.prefix(1) ?? "?"))
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                        )
                    Text(profileManager.currentProfile?.name ?? "Profile")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            GlassMaterialView()
                .clipShape(Capsule())
        )
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 16, y: 4)
    }
}

struct GlassMaterialView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = 999
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
```

- [ ] **Step 2: Commit**

```bash
git add Apps/LunaMac/Sources/Components/PillNavBar.swift
git commit -m "feat: PillNavBar with liquid glass effect for macOS"
```

### Task 6: Refactor MacContentView to router-only

**Files:**
- Rewrite: `Apps/LunaMac/Sources/MacContentView.swift`

- [ ] **Step 1: Rewrite MacContentView as thin router**

```swift
import SwiftUI
import LunaCore

struct MacContentView: View {
    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var roleManager: RoleManager
    @StateObject private var addonRepo = AddonRepository.shared

    var body: some View {
        Group {
            if profileManager.isAuthenticated {
                if profileManager.currentProfile != nil {
                    MacMainView()
                } else if !profileManager.profiles.isEmpty {
                    MacProfilePicker()
                } else {
                    MacCreateProfile()
                }
            } else {
                MacAuthView()
            }
        }
        .onChange(of: profileManager.currentProfile) { _, newProfile in
            roleManager.evaluateRole(profile: newProfile)
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Apps/LunaMac/Sources/MacContentView.swift
git commit -m "refactor: slim MacContentView to auth/router only"
```

### Task 7: Create MacMainView shell

**Files:**
- Create: `Apps/LunaMac/Sources/Screens/MacMainView.swift`

- [ ] **Step 1: Create MacMainView with ZStack pill nav + content**

```swift
import SwiftUI
import LunaCore

struct MacMainView: View {
    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var roleManager: RoleManager
    @StateObject private var addonRepo = AddonRepository.shared
    @State private var selectedTab: MacMainTab = .home

    var body: some View {
        ZStack(alignment: .top) {
            // Content area
            VStack(spacing: 0) {
                switch selectedTab {
                case .home: MacHomeView()
                case .search: MacSearchView()
                case .library: MacLibraryView()
                case .settings: MacSettingsView()
                case .admin: MacAdminView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LunaTheme.background)

            // Floating pill navbar
            VStack {
                PillNavBar(selectedTab: $selectedTab)
                    .padding(.top, 12)
                Spacer()
            }
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Apps/LunaMac/Sources/Screens/MacMainView.swift
git commit -m "feat: MacMainView shell with ZStack pill nav + content routing"
```

---

## Phase 3: Auth & Profile Screens

### Task 8: Create MacAuthView

**Files:**
- Create: `Apps/LunaMac/Sources/Screens/MacAuthView.swift`

- [ ] **Step 1: Create MacAuthView (port from iOS AuthScreen with LunaWeb styling)**

```swift
import SwiftUI
import LunaCore

struct MacAuthView: View {
    @EnvironmentObject var profileManager: ProfileManager
    @State private var email = ""
    @State private var password = ""
    @State private var inviteCode = ""
    @State private var isSignUp = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "moon.stars.fill")
                .font(.system(size: 48))
                .foregroundColor(LunaTheme.accent)

            Text("Luna")
                .font(.system(size: 36, weight: .black, design: .rounded))
                .foregroundColor(.white)

            Text("Sign in to your media hub")
                .font(.subheadline)
                .foregroundColor(LunaTheme.textTertiary)

            VStack(spacing: 12) {
                TextField("Email", text: $email)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(LunaTheme.surface)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                    .frame(width: 320)
                    .foregroundColor(.white)

                SecureField("Password", text: $password)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(LunaTheme.surface)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                    .frame(width: 320)
                    .foregroundColor(.white)

                if isSignUp {
                    TextField("Invite Code", text: $inviteCode)
                        .textFieldStyle(.plain)
                        .padding(10)
                        .background(LunaTheme.surface)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                        .frame(width: 320)
                        .foregroundColor(.white)
                }
            }

            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }

            Button(action: performAuth) {
                HStack(spacing: 8) {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.7)
                            .tint(.white)
                    }
                    Text(isSignUp ? "Create Account" : "Sign In")
                        .fontWeight(.semibold)
                }
                .frame(width: 320, height: 40)
                .background(LunaTheme.accent)
                .foregroundColor(.white)
                .cornerRadius(20)
            }
            .buttonStyle(.plain)
            .disabled(isLoading || email.isEmpty || password.isEmpty)
            .opacity((isLoading || email.isEmpty || password.isEmpty) ? 0.5 : 1)

            Button(isSignUp ? "Have an account? Sign In" : "New to Luna? Create Account") {
                isSignUp.toggle()
                errorMessage = nil
            }
            .buttonStyle(.plain)
            .foregroundColor(LunaTheme.textTertiary)
            .font(.subheadline)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LunaTheme.background)
    }

    private func performAuth() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                if isSignUp {
                    try await profileManager.signUp(email: email, password: password, inviteCode: inviteCode)
                } else {
                    try await profileManager.signIn(email: email, password: password)
                }
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
git add Apps/LunaMac/Sources/Screens/MacAuthView.swift
git commit -m "feat: MacAuthView with LunaWeb-styled auth screen"
```

### Task 9: Create MacProfilePicker + MacCreateProfile

**Files:**
- Create: `Apps/LunaMac/Sources/Screens/MacProfilePicker.swift`

- [ ] **Step 1: Create MacProfilePicker with "Who's watching?" grid**

```swift
import SwiftUI
import LunaCore

struct MacProfilePicker: View {
    @EnvironmentObject var profileManager: ProfileManager
    @State private var showCreate = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "moon.stars.fill")
                .font(.system(size: 48))
                .foregroundColor(LunaTheme.accent)

            Text("Who's watching?")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.white)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 20) {
                ForEach(profileManager.profiles) { profile in
                    Button {
                        profileManager.selectProfile(profile)
                    } label: {
                        VStack(spacing: 8) {
                            Circle()
                                .fill(profile.avatarColor.map { Color(hex: $0) } ?? LunaTheme.accent)
                                .frame(width: 80, height: 80)
                                .overlay(
                                    Text(String(profile.name.prefix(1).uppercased()))
                                        .font(.title)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                )
                            Text(profile.name)
                                .font(.subheadline)
                                .foregroundColor(.white)
                            if profile.isAdmin {
                                Text("Admin")
                                    .font(.caption2)
                                    .foregroundColor(LunaTheme.accent)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                Button { showCreate = true } label: {
                    VStack(spacing: 8) {
                        Circle()
                            .stroke(Color.white.opacity(0.2), lineWidth: 2)
                            .frame(width: 80, height: 80)
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
            .frame(maxWidth: 500)

            Button("Sign Out") {
                Task { await profileManager.signOut() }
            }
            .foregroundColor(LunaTheme.textTertiary)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LunaTheme.background)
        .sheet(isPresented: $showCreate) {
            MacCreateProfile()
        }
    }
}

struct MacCreateProfile: View {
    @EnvironmentObject var profileManager: ProfileManager
    @Environment(\.dismiss) var dismiss
    @State private var name = ""

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "moon.stars.fill")
                .font(.system(size: 56))
                .foregroundColor(LunaTheme.accent)

            Text("Create Profile")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.white)

            TextField("Profile Name", text: $name)
                .textFieldStyle(.plain)
                .padding(10)
                .background(LunaTheme.surface)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1), lineWidth: 1))
                .frame(width: 300)
                .foregroundColor(.white)

            Button("Create Profile") {
                Task {
                    try await profileManager.createProfile(name: name)
                    dismiss()
                }
            }
            .frame(width: 300, height: 40)
            .background(name.isEmpty ? LunaTheme.surface : LunaTheme.accent)
            .foregroundColor(.white)
            .cornerRadius(20)
            .disabled(name.isEmpty)

            Spacer()
        }
        .frame(width: 400, height: 350)
        .background(LunaTheme.background)
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Apps/LunaMac/Sources/Screens/MacProfilePicker.swift
git commit -m "feat: MacProfilePicker + MacCreateProfile with LunaWeb styling"
```

---

## Phase 4: Home Screen Components

### Task 10: Create MediaCard + ContinueWatchingCard

**Files:**
- Create: `Apps/LunaMac/Sources/Components/MediaCard.swift`
- Create: `Apps/LunaMac/Sources/Components/ContinueWatchingCard.swift`

- [ ] **Step 1: Create MediaCard**

```swift
import SwiftUI
import LunaCore

struct MediaCard: View {
    let item: MetaPreview
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .bottom) {
                // Poster image
                Group {
                    if let poster = item.poster, let url = URL(string: poster) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().aspectRatio(contentMode: .fill)
                            default:
                                Rectangle().fill(LunaTheme.surfaceElevated)
                                    .overlay(
                                        Text(item.type == .movie ? "🎬" : "📺")
                                            .font(.title)
                                    )
                            }
                        }
                    } else {
                        Rectangle().fill(LunaTheme.surfaceElevated)
                            .overlay(
                                Text(item.type == .movie ? "🎬" : "📺")
                                    .font(.title)
                            )
                    }
                }
                .frame(width: 180, height: 240)
                .clipped()
                .cornerRadius(10)
                .scaleEffect(isHovering ? 1.05 : 1.0)

                // Hover overlay
                if isHovering {
                    VStack {
                        Spacer()
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.8)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 80)
                    }
                    .cornerRadius(10)

                    // Play button
                    Circle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Image(systemName: "play.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.white)
                                .offset(x: 1)
                        )
                        .padding(.bottom, 20)
                        .transition(.opacity)
                }
            }
            .frame(width: 180, height: 240)
            .animation(.easeInOut(duration: 0.2), value: isHovering)
            .onHover { hovering in
                isHovering = hovering
            }

            Text(item.name)
                .font(.caption)
                .foregroundColor(LunaTheme.textPrimary)
                .lineLimit(2)
                .frame(width: 180, alignment: .leading)

            if let rating = item.imdbRating {
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 8))
                        .foregroundColor(.yellow)
                    Text(rating)
                        .font(.system(size: 11))
                        .foregroundColor(LunaTheme.textTertiary)
                }
            }
        }
    }
}
```

- [ ] **Step 2: Create ContinueWatchingCard**

```swift
import SwiftUI
import LunaCore

struct ContinueWatchingCard: View {
    let item: ContinueWatchingItem
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .bottom) {
                Group {
                    if let poster = item.poster, let url = URL(string: poster) {
                        AsyncImage(url: url) { phase in
                            if case .success(let image) = phase {
                                image.resizable().aspectRatio(contentMode: .fill)
                            } else {
                                Rectangle().fill(LunaTheme.surfaceElevated)
                            }
                        }
                    } else {
                        Rectangle().fill(LunaTheme.surfaceElevated)
                    }
                }
                .frame(width: 200, height: 112)
                .clipped()
                .cornerRadius(8)

                // Progress bar
                VStack(spacing: 0) {
                    Spacer()
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(Color.white.opacity(0.2)).frame(height: 3)
                            Rectangle()
                                .fill(LunaTheme.accent)
                                .frame(width: geo.size.width * item.progressFraction, height: 3)
                        }
                    }
                    .frame(height: 3)
                }
                .cornerRadius(8)

                // Play overlay on hover
                if isHovering {
                    Color.black.opacity(0.4).cornerRadius(8)
                    Circle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Image(systemName: "play.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.white)
                                .offset(x: 1)
                        )
                }
            }
            .frame(width: 200, height: 112)
            .onHover { isHovering = $0 }

            Text(item.name)
                .font(.caption)
                .foregroundColor(.white)
                .lineLimit(1)
                .frame(width: 200, alignment: .leading)

            if let epTitle = item.episodeTitle {
                Text(epTitle)
                    .font(.caption2)
                    .foregroundColor(LunaTheme.textTertiary)
                    .lineLimit(1)
                    .frame(width: 200, alignment: .leading)
            }
        }
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add Apps/LunaMac/Sources/Components/MediaCard.swift Apps/LunaMac/Sources/Components/ContinueWatchingCard.swift
git commit -m "feat: MediaCard and ContinueWatchingCard components"
```

### Task 11: Create MediaRow + HomeHero

**Files:**
- Create: `Apps/LunaMac/Sources/Components/MediaRow.swift`
- Create: `Apps/LunaMac/Sources/Components/HomeHero.swift`

- [ ] **Step 1: Create MediaRow**

```swift
import SwiftUI
import LunaCore

struct MediaRow: View {
    let title: String
    let items: [MetaPreview]
    let onTap: (MetaPreview) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(items) { item in
                        MediaCard(item: item)
                            .onTapGesture { onTap(item) }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}
```

- [ ] **Step 2: Create HomeHero**

```swift
import SwiftUI
import LunaCore

struct HomeHero: View {
    let item: MetaPreview
    let rowTitle: String
    let onTap: () -> Void
    let dotCount: Int
    let activeIndex: Int
    let onDotTap: (Int) -> Void

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Backdrop
            Group {
                if let banner = item.banner ?? item.poster, let url = URL(string: banner) {
                    AsyncImage(url: url) { phase in
                        if case .success(let img) = phase {
                            img.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            LunaTheme.surface
                        }
                    }
                } else {
                    LunaTheme.surface
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 480)
            .clipped()

            // Bottom fade gradient
            LinearGradient(
                colors: [.clear, LunaTheme.background.opacity(0.7), LunaTheme.background],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 480)

            // Left-to-right darkening for text readability
            LinearGradient(
                colors: [.black.opacity(0.5), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 480)

            // Content
            VStack(alignment: .leading, spacing: 0) {
                Text(rowTitle.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(LunaTheme.accent)
                    .tracking(2)
                    .padding(.bottom, 8)

                Text(item.name)
                    .font(.system(size: 44, weight: .black))
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
                        Text(release)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                    }
                    if let genres = item.genres?.prefix(2) {
                        Text(genres.joined(separator: ", "))
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                .padding(.bottom, 18)

                HStack(spacing: 12) {
                    Button(action: onTap) {
                        Label("Watch Now", systemImage: "play.fill")
                            .font(.subheadline.bold())
                            .foregroundColor(.black)
                            .padding(.horizontal, 22)
                            .padding(.vertical, 11)
                            .background(Color.white)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Button(action: onTap) {
                        Label("My List", systemImage: "plus")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 11)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .leading)

            // Page dots
            if dotCount > 1 {
                HStack(spacing: 5) {
                    ForEach(0..<dotCount, id: \.self) { i in
                        Button { onDotTap(i) } label: {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(i == activeIndex ? Color.white : Color.white.opacity(0.3))
                                .frame(width: i == activeIndex ? 20 : 6, height: 3)
                        }
                        .buttonStyle(.plain)
                        .animation(.easeInOut(duration: 0.25), value: activeIndex)
                    }
                }
                .padding(.trailing, 20)
                .padding(.bottom, 18)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .frame(height: 480)
        .clipped()
    }
}
```

- [ ] **Step 4: Commit**

```bash
git add Apps/LunaMac/Sources/Components/MediaRow.swift Apps/LunaMac/Sources/Components/HomeHero.swift
git commit -m "feat: MediaRow and HomeHero carousel components"
```

### Task 12: Create FolderTile

**Files:**
- Create: `Apps/LunaMac/Sources/Components/FolderTile.swift`

- [ ] **Step 1: Create FolderTile**

```swift
import SwiftUI
import LunaCore

struct FolderTile: View {
    let row: CatalogRow
    let onTap: () -> Void
    @State private var isHovering = false
    @State private var gifLoaded = false

    private var isLandscape: Bool {
        row.tileShape == "landscape"
    }

    private var cardWidth: CGFloat { isLandscape ? 220 : 140 }
    private var cardHeight: CGFloat { isLandscape ? 124 : 210 }

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomLeading) {
                Rectangle()
                    .fill(LunaTheme.surfaceElevated)
                    .frame(width: cardWidth, height: cardHeight)

                if let coverURL = row.coverImage ?? row.items.first?.poster,
                   let url = URL(string: coverURL) {
                    AsyncImage(url: url) { phase in
                        if case .success(let img) = phase {
                            img.resizable().aspectRatio(contentMode: .fill)
                                .frame(width: cardWidth, height: cardHeight)
                                .clipped()
                        }
                    }
                }

                // Gradient overlay for text readability
                LinearGradient(
                    colors: [.clear, .black.opacity(0.7)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                Text(row.title)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: cardWidth, height: cardHeight)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        isHovering && (row.focusGlowEnabled ?? false)
                            ? LunaTheme.accent.opacity(0.6)
                            : Color.clear,
                        lineWidth: 2
                    )
            )
            .shadow(
                color: (isHovering && (row.focusGlowEnabled ?? false))
                    ? LunaTheme.accent.opacity(0.35)
                    : Color.clear,
                radius: 16, y: 0
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Apps/LunaMac/Sources/Components/FolderTile.swift
git commit -m "feat: FolderTile with focus glow hover effect"
```

### Task 13: Create MacHomeView

**Files:**
- Create: `Apps/LunaMac/Sources/Screens/MacHomeView.swift`

- [ ] **Step 1: Create full MacHomeView**

```swift
import SwiftUI
import LunaCore

struct MacHomeView: View {
    @EnvironmentObject var profileManager: ProfileManager
    @StateObject private var catalogRepo = CatalogRepository.shared
    @StateObject private var collectionRepo = CollectionRepository.shared
    @StateObject private var homeRepo = HomeRepository.shared
    @StateObject private var addonRepo = AddonRepository.shared
    @State private var heroIndex = 0
    @State private var heroTimer: Timer?
    @State private var selectedMedia: MetaPreview?
    @State private var showDetail = false

    private let mainRowNames: Set<String> = [
        "Popular Movies", "Popular TV Shows",
        "Trending Movies", "Trending TV Shows"
    ]

    private var featuredItems: [MetaPreview] {
        let mainRows = catalogRepo.catalogRows.filter { mainRowNames.contains($0.title) }
        var seen = Set<String>()
        var candidates: [MetaPreview] = []
        for row in mainRows {
            for item in row.items where !seen.contains(item.id) {
                seen.insert(item.id)
                candidates.append(item)
            }
        }
        return candidates
            .sorted { ($0.popularity ?? 0) > ($1.popularity ?? 0) }
            .prefix(5)
            .map { $0 }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Hero (pulled up behind navbar via negative top padding handled by ZStack in MacMainView)
                if !featuredItems.isEmpty {
                    let safeIndex = heroIndex % featuredItems.count
                    let rowTitle = catalogRepo.catalogRows
                        .first(where: { $0.items.contains(where: { $0.id == featuredItems[safeIndex].id }) })?
                        .title ?? "Featured"

                    HomeHero(
                        item: featuredItems[safeIndex],
                        rowTitle: rowTitle,
                        onTap: {
                            selectedMedia = featuredItems[safeIndex]
                            showDetail = true
                        },
                        dotCount: featuredItems.count,
                        activeIndex: safeIndex,
                        onDotTap: { i in
                            withAnimation(.easeInOut(duration: 0.4)) {
                                heroIndex = i
                            }
                            startHeroTimer()
                        }
                    )

                    Spacer().frame(height: 24)
                }

                // Continue Watching
                if !homeRepo.continueWatchingItems.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Continue Watching")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal)

                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 12) {
                                ForEach(homeRepo.continueWatchingItems) { item in
                                    ContinueWatchingCard(item: item)
                                        .onTapGesture {
                                            if let match = catalogRepo.catalogRows
                                                .flatMap({ $0.items })
                                                .first(where: { $0.id == item.mediaId }) {
                                                selectedMedia = match
                                            } else {
                                                selectedMedia = MetaPreview(
                                                    id: item.mediaId,
                                                    type: item.mediaType == "movie" ? .movie : .series,
                                                    name: item.name,
                                                    poster: item.poster
                                                )
                                            }
                                            showDetail = true
                                        }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.bottom, 24)
                }

                // Catalog Rows
                if !catalogRepo.catalogRows.isEmpty {
                    let mainRows = catalogRepo.catalogRows.filter { mainRowNames.contains($0.title) }
                    let folderRows = catalogRepo.catalogRows.filter { !mainRowNames.contains($0.title) }

                    VStack(spacing: 28) {
                        ForEach(mainRows) { row in
                            MediaRow(title: row.title, items: row.items) { item in
                                selectedMedia = item
                                showDetail = true
                            }
                        }
                    }

                    // Collection folder grid
                    if !folderRows.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Browse")
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.horizontal)

                            LazyVGrid(columns: [
                                GridItem(.adaptive(minimum: 140), spacing: 10)
                            ], spacing: 10) {
                                ForEach(folderRows) { row in
                                    FolderTile(row: row) {
                                        if let first = row.items.first {
                                            selectedMedia = first
                                            showDetail = true
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                        .padding(.top, 8)
                    }
                } else if catalogRepo.isLoading {
                    ProgressView()
                        .tint(LunaTheme.accent)
                        .padding(.top, 100)
                }

                Spacer().frame(height: 32)
            }
        }
        .background(LunaTheme.background)
        .sheet(isPresented: $showDetail) {
            if let media = selectedMedia {
                MacDetailView(mediaId: media.id, type: media.type.rawValue, name: media.name)
                    .frame(minWidth: 800, minHeight: 600)
            }
        }
        .task {
            guard let profile = profileManager.currentProfile else { return }
            await addonRepo.loadAddons(profileId: profile.id)
            await collectionRepo.load()
            await catalogRepo.loadAllCatalogs(addons: addonRepo.enabledAddons)
            await homeRepo.loadContinueWatching(profileId: profile.id)
            startHeroTimer()
        }
        .onDisappear {
            heroTimer?.invalidate()
            heroTimer = nil
        }
        .onChange(of: featuredItems.count) { _ in
            heroIndex = 0
            startHeroTimer()
        }
    }

    private func startHeroTimer() {
        heroTimer?.invalidate()
        guard featuredItems.count > 1 else { return }
        heroTimer = Timer.scheduledTimer(withTimeInterval: 6, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.4)) {
                heroIndex = (heroIndex + 1) % featuredItems.count
            }
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Apps/LunaMac/Sources/Screens/MacHomeView.swift
git commit -m "feat: MacHomeView with hero, continue watching, catalog rows, collection folders"
```

---

## Phase 5: Search, Library, Settings, Admin

### Task 14: Create MacSearchView

**Files:**
- Create: `Apps/LunaMac/Sources/Screens/MacSearchView.swift`

- [ ] **Step 1: Create MacSearchView**

```swift
import SwiftUI
import LunaCore

struct MacSearchView: View {
    @StateObject private var searchRepo = SearchRepository.shared
    @StateObject private var addonRepo = AddonRepository.shared
    @State private var query = ""
    @State private var selectedFilter: String? = nil

    var filteredResults: [MetaPreview] {
        guard let filter = selectedFilter else { return searchRepo.results }
        return searchRepo.results.filter { $0.type.rawValue == filter }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(LunaTheme.textTertiary)
                TextField("Search movies & shows...", text: $query)
                    .textFieldStyle(.plain)
                    .foregroundColor(.white)
                    .onSubmit {
                        Task { await searchRepo.search(query: query, addons: addonRepo.enabledAddons) }
                    }
                if !query.isEmpty {
                    Button {
                        query = ""
                        selectedFilter = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(LunaTheme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(LunaTheme.surface)
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.08), lineWidth: 1))
            .padding(.horizontal)
            .padding(.top, 56) // Clear the pill navbar

            // Filter pills
            if !searchRepo.results.isEmpty {
                HStack(spacing: 8) {
                    FilterPill(label: "All", isSelected: selectedFilter == nil) {
                        selectedFilter = nil
                    }
                    FilterPill(label: "Movies", isSelected: selectedFilter == "movie") {
                        selectedFilter = "movie"
                    }
                    FilterPill(label: "TV Shows", isSelected: selectedFilter == "series") {
                        selectedFilter = "series"
                    }
                }
                .padding(.horizontal)
                .padding(.top, 12)
            }

            // Results
            if searchRepo.isLoading {
                Spacer()
                ProgressView().tint(LunaTheme.accent)
                Spacer()
            } else if !searchRepo.results.isEmpty {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 16)], spacing: 16) {
                        ForEach(filteredResults) { item in
                            MediaCard(item: item)
                        }
                    }
                    .padding()
                }
            } else if !query.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.title)
                        .foregroundColor(LunaTheme.textTertiary)
                    Text("No results for \"\(query)\"")
                        .foregroundColor(LunaTheme.textSecondary)
                }
                Spacer()
            } else {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 36))
                        .foregroundColor(LunaTheme.textTertiary)
                    Text("Search movies & shows")
                        .font(.title3)
                        .foregroundColor(LunaTheme.textSecondary)
                    Text("Find your next watch across all addons")
                        .font(.caption)
                        .foregroundColor(LunaTheme.textTertiary)
                }
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LunaTheme.background)
    }
}

struct FilterPill: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(isSelected ? LunaTheme.accent : LunaTheme.surface)
                .foregroundColor(isSelected ? .white : LunaTheme.textSecondary)
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(isSelected ? Color.clear : Color.white.opacity(0.1), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Apps/LunaMac/Sources/Screens/MacSearchView.swift
git commit -m "feat: MacSearchView with filter pills and grid results"
```

### Task 15: Create MacLibraryView

**Files:**
- Create: `Apps/LunaMac/Sources/Screens/MacLibraryView.swift`

- [ ] **Step 1: Create MacLibraryView**

```swift
import SwiftUI
import LunaCore

struct MacLibraryView: View {
    @StateObject private var libraryRepo = LibraryRepository.shared
    @EnvironmentObject var profileManager: ProfileManager

    var body: some View {
        VStack(spacing: 0) {
            if libraryRepo.isLoading {
                Spacer()
                ProgressView().tint(LunaTheme.accent)
                Spacer()
            } else if libraryRepo.libraryItems.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "bookmark")
                        .font(.system(size: 40))
                        .foregroundColor(LunaTheme.textTertiary)
                    Text("Your library is empty")
                        .font(.title2)
                        .foregroundColor(.white)
                    Text("Save movies and shows to watch later")
                        .font(.subheadline)
                        .foregroundColor(LunaTheme.textTertiary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 16)], spacing: 16) {
                        ForEach(libraryRepo.libraryItems) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                ZStack(alignment: .topTrailing) {
                                    Rectangle()
                                        .fill(LunaTheme.surfaceElevated)
                                        .frame(height: 220)
                                        .cornerRadius(10)
                                        .overlay(
                                            Text(item.mediaType == "series" ? "📺" : "🎬")
                                                .font(.title)
                                        )

                                    Menu {
                                        Button("Remove from Library", role: .destructive) {
                                            Task {
                                                guard let profile = profileManager.currentProfile else { return }
                                                await libraryRepo.removeFromLibrary(profileId: profile.id, mediaId: item.mediaId)
                                            }
                                        }
                                    } label: {
                                        Image(systemName: "ellipsis.circle.fill")
                                            .font(.system(size: 20))
                                            .foregroundColor(.white.opacity(0.8))
                                            .shadow(radius: 2)
                                            .padding(6)
                                    }
                                    .menuStyle(.borderlessButton)
                                    .frame(width: 28, height: 28)
                                    .opacity(0.7)
                                }
                                .frame(height: 220)

                                Text(item.name ?? item.mediaId)
                                    .font(.caption)
                                    .foregroundColor(.white)
                                    .lineLimit(2)
                            }
                        }
                    }
                    .padding()
                    .padding(.top, 48)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LunaTheme.background)
        .task {
            guard let profile = profileManager.currentProfile else { return }
            await libraryRepo.loadLibrary(profileId: profile.id)
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Apps/LunaMac/Sources/Screens/MacLibraryView.swift
git commit -m "feat: MacLibraryView with grid and context menu remove"
```

### Task 16: Create MacSettingsView

**Files:**
- Create: `Apps/LunaMac/Sources/Screens/MacSettingsView.swift`

- [ ] **Step 1: Create MacSettingsView**

```swift
import SwiftUI
import LunaCore

struct MacSettingsView: View {
    @EnvironmentObject var profileManager: ProfileManager
    @StateObject private var addonRepo = AddonRepository.shared
    @State private var newUrl = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Profile card
                if let profile = profileManager.currentProfile {
                    HStack(spacing: 14) {
                        Circle()
                            .fill(profile.avatarColor.map { Color(hex: $0) } ?? LunaTheme.accent)
                            .frame(width: 48, height: 48)
                            .overlay(
                                Text(String(profile.name.prefix(1).uppercased()))
                                    .font(.title3)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                            )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile.name)
                                .font(.headline)
                                .foregroundColor(.white)
                            Text(profile.isAdmin ? "Admin" : "User")
                                .font(.caption)
                                .foregroundColor(LunaTheme.textTertiary)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(LunaTheme.surface)
                    .cornerRadius(10)
                    .padding(.horizontal)
                    .padding(.top, 56)

                    Button("Switch Profile") {
                        profileManager.currentProfile = nil
                    }
                    .font(.subheadline)
                    .foregroundColor(LunaTheme.textSecondary)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }

                // Addons section
                VStack(alignment: .leading, spacing: 0) {
                    Text("Addons (\(addonRepo.managedAddons.count))")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(LunaTheme.textTertiary)
                        .tracking(1)
                        .textCase(.uppercase)
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        .padding(.bottom, 6)

                    VStack(spacing: 0) {
                        ForEach(addonRepo.managedAddons) { addon in
                            HStack {
                                Text(addon.displayName)
                                    .font(.subheadline)
                                    .foregroundColor(.white)
                                Spacer()
                                Circle()
                                    .fill(addon.enabled ? Color.green : LunaTheme.textTertiary)
                                    .frame(width: 8, height: 8)
                                Text(addon.enabled ? "Enabled" : "Disabled")
                                    .font(.caption)
                                    .foregroundColor(addon.enabled ? .green : LunaTheme.textTertiary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(LunaTheme.surface)
                            if addon.id != addonRepo.managedAddons.last?.id {
                                Divider().background(Color.white.opacity(0.06))
                            }
                        }

                        HStack(spacing: 8) {
                            TextField("Add addon URL...", text: $newUrl)
                                .textFieldStyle(.plain)
                                .padding(8)
                                .background(LunaTheme.background)
                                .cornerRadius(6)
                                .foregroundColor(.white)
                            Button("Install") {
                                Task {
                                    await addonRepo.installAddon(url: newUrl)
                                    newUrl = ""
                                }
                            }
                            .font(.caption)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(newUrl.isEmpty ? LunaTheme.surfaceElevated : LunaTheme.accent)
                            .foregroundColor(.white)
                            .cornerRadius(6)
                            .disabled(newUrl.isEmpty)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(LunaTheme.surface)
                    }
                    .cornerRadius(10)
                    .padding(.horizontal)
                }

                // Sign Out
                Button("Sign Out") {
                    Task { await profileManager.signOut() }
                }
                .foregroundColor(.red)
                .font(.subheadline)
                .padding(.horizontal, 20)
                .padding(.top, 24)

                // Version
                Text("Luna for macOS · v1.0")
                    .font(.caption2)
                    .foregroundColor(LunaTheme.textTertiary)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                Spacer().frame(height: 32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LunaTheme.background)
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Apps/LunaMac/Sources/Screens/MacSettingsView.swift
git commit -m "feat: MacSettingsView with profile card and addon management"
```

### Task 17: Create MacAdminView

**Files:**
- Create: `Apps/LunaMac/Sources/Screens/MacAdminView.swift`

- [ ] **Step 1: Create MacAdminView**

```swift
import SwiftUI
import LunaCore

struct MacAdminView: View {
    @StateObject private var adminService = AdminService.shared
    @State private var maxUses = 1

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Admin Panel")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal)
                    .padding(.top, 56)
                    .padding(.bottom, 16)

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Max uses:")
                            .font(.subheadline)
                            .foregroundColor(LunaTheme.textSecondary)
                        Stepper("\(maxUses)", value: $maxUses, in: 1...100)
                            .labelsHidden()
                    }

                    Button("Generate Invite Code") {
                        Task { try await adminService.generateInviteCode(maxUses: maxUses) }
                    }
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(LunaTheme.accent)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .padding()
                .background(LunaTheme.surface)
                .cornerRadius(10)
                .padding(.horizontal)

                // Invite codes list
                VStack(alignment: .leading, spacing: 0) {
                    Text("Invite Codes (\(adminService.inviteCodes.count))")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(LunaTheme.textTertiary)
                        .tracking(1)
                        .textCase(.uppercase)
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        .padding(.bottom, 6)

                    VStack(spacing: 0) {
                        ForEach(adminService.inviteCodes) { code in
                            HStack {
                                Text(code.code)
                                    .font(.system(.body, design: .monospaced))
                                    .fontWeight(.bold)
                                    .foregroundColor(LunaTheme.accent)
                                Spacer()
                                Circle()
                                    .fill(code.isActive && !code.isUsed ? Color.green : Color.red)
                                    .frame(width: 8, height: 8)
                                Text(code.isActive && !code.isUsed ? "Active" : "Revoked")
                                    .font(.caption)
                                    .foregroundColor(LunaTheme.textTertiary)
                                if code.isActive && !code.isUsed {
                                    Button("Revoke") {
                                        Task { try await adminService.revokeInviteCode(code.code) }
                                    }
                                    .font(.caption)
                                    .foregroundColor(.red)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(LunaTheme.surface)
                            if code.id != adminService.inviteCodes.last?.id {
                                Divider().background(Color.white.opacity(0.06))
                            }
                        }
                    }
                    .cornerRadius(10)
                    .padding(.horizontal)
                }

                Spacer().frame(height: 32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LunaTheme.background)
        .task { await adminService.loadInviteCodes() }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Apps/LunaMac/Sources/Screens/MacAdminView.swift
git commit -m "feat: MacAdminView with invite code generation and management"
```

---

## Phase 6: Detail + Player

### Task 18: Create MacDetailView

**Files:**
- Create: `Apps/LunaMac/Sources/Screens/MacDetailView.swift`

- [ ] **Step 1: Create MacDetailView (port from iOS DetailScreen)**

```swift
import SwiftUI
import LunaCore

struct MacDetailView: View {
    let mediaId: String
    let type: String
    let name: String

    @StateObject private var metaRepo = MetaRepository.shared
    @StateObject private var libraryRepo = LibraryRepository.shared
    @StateObject private var watchedRepo = WatchProgressRepository.shared
    @EnvironmentObject var profileManager: ProfileManager
    @StateObject private var addonRepo = AddonRepository.shared
    @State private var showSourcePicker = false
    @State private var showPlayer = false
    @State private var playerLaunch: PlayerLaunch?
    @State private var selectedSeasonId: String?
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ScrollView {
            if let detail = metaRepo.detail {
                VStack(alignment: .leading, spacing: 0) {
                    // Hero backdrop
                    ZStack(alignment: .bottomLeading) {
                        if let bg = detail.background, let url = URL(string: bg) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let image):
                                    image.resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(height: 320)
                                        .clipped()
                                        .overlay(
                                            LinearGradient(
                                                colors: [.clear, LunaTheme.background],
                                                startPoint: .center,
                                                endPoint: .bottom
                                            )
                                        )
                                default:
                                    LunaTheme.surfaceElevated.frame(height: 320)
                                }
                            }
                        } else {
                            LunaTheme.surfaceElevated.frame(height: 200)
                        }

                        HStack(alignment: .bottom, spacing: 16) {
                            if let poster = detail.poster, let url = URL(string: poster) {
                                AsyncImage(url: url) { phase in
                                    if case .success(let image) = phase {
                                        image.resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(width: 110, height: 165)
                                            .cornerRadius(8)
                                    } else {
                                        LunaTheme.surfaceElevated
                                            .frame(width: 110, height: 165)
                                            .cornerRadius(8)
                                    }
                                }
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(detail.name)
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                if let info = detail.releaseInfo {
                                    Text(info)
                                        .font(.subheadline)
                                        .foregroundColor(LunaTheme.textSecondary)
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 20)
                    }

                    // Action buttons
                    HStack(spacing: 12) {
                        Button {
                            showSourcePicker = true
                        } label: {
                            HStack {
                                Image(systemName: "play.fill")
                                Text("Play")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(LunaTheme.accent)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        .buttonStyle(.plain)

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
                                .background(LunaTheme.surface)
                                .foregroundColor(libraryRepo.isInLibrary(mediaId: detail.id) ? LunaTheme.accent : .white)
                                .cornerRadius(10)
                        }
                        .buttonStyle(.plain)

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
                                .background(LunaTheme.surface)
                                .foregroundColor(watchedRepo.isWatched(mediaId: detail.id) ? .green : .white)
                                .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)

                    // Overview
                    if let description = detail.description, !description.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Overview")
                                .font(.headline)
                                .foregroundColor(.white)
                            Text(description)
                                .font(.body)
                                .foregroundColor(LunaTheme.textSecondary)
                                .lineLimit(6)
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 20)
                    }

                    // Genres
                    if let genres = detail.genres, !genres.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(genres, id: \.self) { genre in
                                    Text(genre)
                                        .font(.caption)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(LunaTheme.surface)
                                        .foregroundColor(LunaTheme.textSecondary)
                                        .cornerRadius(16)
                                }
                            }
                            .padding(.horizontal, 24)
                        }
                        .padding(.top, 16)
                    }

                    // Cast
                    if let cast = detail.cast, !cast.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Cast")
                                .font(.headline)
                                .foregroundColor(.white)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 14) {
                                    ForEach(cast.prefix(15)) { person in
                                        VStack(spacing: 4) {
                                            Circle()
                                                .fill(LunaTheme.surfaceElevated)
                                                .frame(width: 56, height: 56)
                                                .overlay(
                                                    Text(String(person.name.prefix(1)))
                                                        .font(.headline)
                                                        .foregroundColor(LunaTheme.textSecondary)
                                                )
                                            Text(person.name)
                                                .font(.caption2)
                                                .foregroundColor(LunaTheme.textSecondary)
                                                .lineLimit(1)
                                                .frame(width: 64)
                                        }
                                    }
                                }
                                .padding(.horizontal, 24)
                            }
                        }
                        .padding(.top, 20)
                    }

                    // Seasons
                    if let seasons = detail.seasons, !seasons.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Episodes")
                                .font(.headline)
                                .foregroundColor(.white)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(seasons.sorted(by: { $0.number < $1.number })) { season in
                                        Button {
                                            selectedSeasonId = season.id
                                        } label: {
                                            Text("Season \(season.number)")
                                                .font(.subheadline)
                                                .fontWeight(.medium)
                                                .padding(.horizontal, 16)
                                                .padding(.vertical, 8)
                                                .background(
                                                    (selectedSeasonId == season.id || (selectedSeasonId == nil && seasons.first?.id == season.id))
                                                        ? Color.white : LunaTheme.surface
                                                )
                                                .foregroundColor(
                                                    (selectedSeasonId == season.id || (selectedSeasonId == nil && seasons.first?.id == season.id))
                                                        ? .black : LunaTheme.textSecondary
                                                )
                                                .clipShape(Capsule())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 24)
                            }

                            if let activeSeason = seasons.first(where: { $0.id == (selectedSeasonId ?? seasons.first?.id) }),
                               let episodes = activeSeason.episodes {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    LazyHStack(spacing: 12) {
                                        ForEach(episodes) { ep in
                                            EpisodeCard(episode: ep)
                                                .onTapGesture {
                                                    showSourcePicker = true
                                                }
                                        }
                                    }
                                    .padding(.horizontal, 24)
                                }
                            }
                        }
                        .padding(.top, 20)
                        .padding(.horizontal, 0)
                    }

                    Spacer().frame(height: 32)
                }
            } else if metaRepo.isLoading {
                VStack {
                    Spacer().frame(height: 200)
                    ProgressView().tint(LunaTheme.accent)
                    Spacer()
                }
            } else if let error = metaRepo.errorMessage {
                Text(error).foregroundColor(.red).padding()
            }
        }
        .background(LunaTheme.background)
        .sheet(isPresented: $showSourcePicker) {
            MacSourcePickerView(
                mediaType: MediaType(rawValue: type) ?? .movie,
                mediaId: mediaId,
                mediaName: metaRepo.detail?.name ?? name,
                poster: metaRepo.detail?.poster,
                logo: metaRepo.detail?.logo,
                onLaunch: { launch in
                    playerLaunch = launch
                    showSourcePicker = false
                    showPlayer = true
                }
            )
            .frame(minWidth: 500, minHeight: 400)
        }
        .sheet(isPresented: $showPlayer) {
            if let launch = playerLaunch {
                MacPlayerView(launch: launch)
                    .frame(minWidth: 900, minHeight: 550)
            }
        }
        .task {
            await metaRepo.loadDetail(type: type, id: mediaId, addons: addonRepo.findAddonWithMetaResource(type: type))
            if let profile = profileManager.currentProfile {
                await libraryRepo.loadLibrary(profileId: profile.id)
                await watchedRepo.loadAll(profileId: profile.id)
            }
        }
    }
}

struct EpisodeCard: View {
    let episode: MetaVideo

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(LunaTheme.surfaceElevated)
                    .frame(width: 220, height: 124)

                if let thumb = episode.thumbnail, let url = URL(string: thumb) {
                    AsyncImage(url: url) { phase in
                        if case .success(let img) = phase {
                            img.resizable().aspectRatio(contentMode: .fill)
                        }
                    }
                    .frame(width: 220, height: 124)
                    .clipped()
                    .cornerRadius(10)
                }

                Color.black.opacity(0.3).cornerRadius(10)

                Circle()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: "play.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                            .offset(x: 1.5)
                    )
            }
            .frame(width: 220, height: 124)

            Text(episode.title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .lineLimit(1)
                .frame(width: 220, alignment: .leading)

            if let overview = episode.overview {
                Text(overview)
                    .font(.caption2)
                    .foregroundColor(LunaTheme.textSecondary)
                    .lineLimit(2)
                    .frame(width: 220, alignment: .leading)
            }
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Apps/LunaMac/Sources/Screens/MacDetailView.swift
git commit -m "feat: MacDetailView with backdrop, cast, seasons, and source picker"
```

### Task 19: Create MacSourcePickerView

**Files:**
- Create: `Apps/LunaMac/Sources/Screens/MacSourcePickerView.swift`

- [ ] **Step 1: Create MacSourcePickerView**

```swift
import SwiftUI
import LunaCore

struct MacSourcePickerView: View {
    let mediaType: MediaType
    let mediaId: String
    let mediaName: String
    let poster: String?
    let logo: String?
    let onLaunch: (PlayerLaunch) -> Void

    @StateObject private var streamRepo = StreamRepository.shared
    @StateObject private var addonRepo = AddonRepository.shared
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Select Source")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .foregroundColor(LunaTheme.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            if streamRepo.isLoading {
                Spacer()
                ProgressView().tint(LunaTheme.accent)
                Spacer()
            } else if streamRepo.streams.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "play.slash")
                        .font(.title)
                        .foregroundColor(LunaTheme.textTertiary)
                    Text("No streams available")
                        .foregroundColor(LunaTheme.textSecondary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(groupedByAddon, id: \.key) { addonName, streams in
                            VStack(alignment: .leading, spacing: 0) {
                                Text(addonName)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(LunaTheme.textTertiary)
                                    .tracking(1)
                                    .textCase(.uppercase)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)

                                ForEach(streams) { stream in
                                    Button {
                                        guard let url = stream.url else { return }
                                        let launch = PlayerLaunch(
                                            title: mediaName,
                                            sourceUrl: url,
                                            sourceHeaders: stream.behaviorHints?.proxyHeaders?.request,
                                            logo: logo,
                                            poster: poster,
                                            streamTitle: stream.displayName,
                                            providerName: stream.addonName,
                                            contentType: mediaType,
                                            videoId: mediaId,
                                            subtitles: nil
                                        )
                                        onLaunch(launch)
                                    } label: {
                                        StreamRowView(stream: stream)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.bottom, 8)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .background(LunaTheme.background)
        .task {
            await streamRepo.fetchStreams(
                type: mediaType.rawValue,
                id: mediaId,
                addons: addonRepo.enabledAddons
            )
        }
    }

    private var groupedByAddon: [(key: String, value: [StreamItem])] {
        let grouped = Dictionary(grouping: streamRepo.streams) { $0.addonName ?? "Unknown" }
        return grouped.sorted { $0.key < $1.key }
    }
}

struct StreamRowView: View {
    let stream: StreamItem
    @State private var isHovering = false

    private var meta: StreamMetadata { stream.parseMetadata() }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if let res = meta.resolution {
                        Text(res)
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(resolutionColor)
                            .foregroundColor(.black)
                            .cornerRadius(4)
                    }
                    if let codec = meta.videoCodec {
                        Text(codec)
                            .font(.system(size: 10))
                            .foregroundColor(LunaTheme.textTertiary)
                    }
                    if let audio = meta.audioCodec {
                        Text(audio)
                            .font(.system(size: 10))
                            .foregroundColor(LunaTheme.textTertiary)
                    }
                    if let hdr = meta.hdr {
                        Text(hdr)
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.3))
                            .foregroundColor(LunaTheme.accent)
                            .cornerRadius(4)
                    }
                }

                Text(stream.displayName)
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .lineLimit(1)

                if let desc = stream.description, !desc.isEmpty {
                    Text(desc)
                        .font(.caption2)
                        .foregroundColor(LunaTheme.textTertiary)
                        .lineLimit(2)
                }
            }

            Spacer()

            Image(systemName: "play.circle.fill")
                .font(.title3)
                .foregroundColor(LunaTheme.accent)
                .opacity(isHovering ? 1 : 0.5)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(isHovering ? LunaTheme.surfaceElevated : LunaTheme.surface)
        .onHover { isHovering = $0 }
    }

    private var resolutionColor: Color {
        guard let res = meta.resolution?.uppercased() else { return .gray }
        if res.contains("4K") || res.contains("2160") { return .yellow }
        if res.contains("1080") { return .blue }
        return .green
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Apps/LunaMac/Sources/Screens/MacSourcePickerView.swift
git commit -m "feat: MacSourcePickerView with stream metadata badges"
```

### Task 20: Create PlayerControls + SpeedPicker

**Files:**
- Create: `Apps/LunaMac/Sources/Components/PlayerControls.swift`
- Create: `Apps/LunaMac/Sources/Components/SpeedPicker.swift`

- [ ] **Step 1: Create SpeedPicker**

```swift
import SwiftUI
import LunaCore

struct SpeedPicker: View {
    @ObservedObject var engine: PlayerEngine

    private let speeds: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

    var body: some View {
        VStack(spacing: 0) {
            Text("Playback Speed")
                .font(.caption)
                .foregroundColor(LunaTheme.textTertiary)
                .padding(.vertical, 8)

            ForEach(speeds, id: \.self) { speed in
                Button {
                    engine.setPlaybackSpeed(speed)
                } label: {
                    HStack {
                        Text("\(speed, specifier: "%.2f")x")
                            .font(.subheadline)
                            .foregroundColor(engine.playbackSpeed == speed ? .white : LunaTheme.textSecondary)
                        Spacer()
                        if engine.playbackSpeed == speed {
                            Image(systemName: "checkmark")
                                .font(.caption)
                                .foregroundColor(LunaTheme.accent)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 140)
        .background(LunaTheme.surfaceElevated)
        .cornerRadius(8)
    }
}
```

- [ ] **Step 2: Create PlayerControls**

```swift
import SwiftUI
import LunaCore

struct PlayerControls: View {
    @ObservedObject var engine: PlayerEngine
    let launch: PlayerLaunch
    let onDismiss: () -> Void

    @State private var showSources = false
    @State private var showSpeed = false
    @State private var isDragging = false
    @State private var dragPosition: Double = 0

    var body: some View {
        VStack(spacing: 0) {
            // Top zone
            HStack {
                Button(action: onDismiss) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .font(.subheadline)
                    .foregroundColor(.white)
                }
                .buttonStyle(.plain)

                Spacer()

                Text(launch.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .lineLimit(1)

                Spacer()

                // Stream info button
                Button { showSources = true } label: {
                    HStack(spacing: 4) {
                        if let streamTitle = launch.streamTitle {
                            Text(streamTitle)
                                .font(.caption)
                                .foregroundColor(LunaTheme.textSecondary)
                                .lineLimit(1)
                        }
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10))
                            .foregroundColor(LunaTheme.textTertiary)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 4)

            Spacer()

            // Center zone — play/pause + skip
            HStack(spacing: 32) {
                Button { engine.skipBack15() } label: {
                    Image(systemName: "gobackward.15")
                        .font(.title2)
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)

                Button { engine.togglePlayPause() } label: {
                    Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 44))
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                .scaleEffect(1.0)
                .onHover { hovering in
                    // SwiftUI implicit animation on the icon
                }

                Button { engine.skipForward15() } label: {
                    Image(systemName: "goforward.15")
                        .font(.title2)
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 20)

            // Bottom zone
            VStack(spacing: 8) {
                // Title
                Text(launch.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Scrubber
                ScrubberView(
                    value: engine.currentPosition,
                    duration: engine.duration,
                    onSeek: { pos in
                        engine.seek(to: pos)
                    }
                )

                // Controls row
                HStack {
                    Text(formatTime(engine.currentPosition))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(LunaTheme.textTertiary)

                    Spacer()

                    // Mute button
                    Button { engine.toggleMute() } label: {
                        Image(systemName: engine.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)

                    // Subtitles button
                    Button { engine.cycleSubtitle() } label: {
                        Image(systemName: engine.selectedSubtitle != nil ? "captions.bubble.fill" : "captions.bubble")
                            .font(.system(size: 16))
                            .foregroundColor(engine.selectedSubtitle != nil ? LunaTheme.accent : .white)
                    }
                    .buttonStyle(.plain)

                    // Speed button
                    Button { showSpeed.toggle() } label: {
                        Text("\(engine.playbackSpeed, specifier: "%.1f")x")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showSpeed, arrowEdge: .bottom) {
                        SpeedPicker(engine: engine)
                    }

                    Text(formatTime(engine.duration))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(LunaTheme.textTertiary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(
            LinearGradient(
                colors: [.black.opacity(0.7), .clear, .clear, .black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func formatTime(_ seconds: Double) -> String {
        let s = Int(seconds)
        let m = s / 60
        let sec = s % 60
        if m >= 60 {
            let h = m / 60
            let min = m % 60
            return String(format: "%d:%02d:%02d", h, min, sec)
        }
        return String(format: "%d:%02d", m, sec)
    }
}

struct ScrubberView: View {
    let value: Double
    let duration: Double
    let onSeek: (Double) -> Void

    var body: some View {
        Slider(
            value: Binding(
                get: { value },
                set: { onSeek($0) }
            ),
            in: 0...max(duration, 1)
        )
        .tint(LunaTheme.accent)
        .frame(height: 20)
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add Apps/LunaMac/Sources/Components/PlayerControls.swift Apps/LunaMac/Sources/Components/SpeedPicker.swift
git commit -m "feat: PlayerControls overlay and SpeedPicker for macOS player"
```

### Task 21: Create MacPlayerView

**Files:**
- Create: `Apps/LunaMac/Sources/Screens/MacPlayerView.swift`

- [ ] **Step 1: Create MacPlayerView**

```swift
import SwiftUI
import LunaCore
import AVKit

struct MacPlayerView: View {
    let launch: PlayerLaunch
    @StateObject private var engine = PlayerEngine.shared
    @StateObject private var controlsState = PlayerControlsState()
    @Environment(\.dismiss) var dismiss
    @State private var showSources = false
    @State private var streams: [StreamItem] = []
    @State private var selectedStreamIdx = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Video layer
            if let player = engine.player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            } else if engine.isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.5)
                    Text("Loading...")
                        .foregroundColor(.white)
                }
            }

            // Controls overlay
            if controlsState.showControls || !engine.isPlaying {
                PlayerControls(
                    engine: engine,
                    launch: launch,
                    onDismiss: { dismiss() }
                )
            }
        }
        .onTapGesture {
            controlsState.toggleControls()
        }
        .onAppear {
            engine.launch(launch)
            engine.play()
            controlsState.showTemporarily()
            setupKeyboardShortcuts()
        }
        .onDisappear {
            engine.pause()
            removeKeyboardShortcuts()
        }
    }

    private func setupKeyboardShortcuts() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch event.keyCode {
            case 49: // Space
                engine.togglePlayPause()
                return nil
            case 40: // K
                engine.togglePlayPause()
                return nil
            case 46: // M
                engine.toggleMute()
                return nil
            case 8: // C
                engine.cycleSubtitle()
                return nil
            case 3: // F
                NSApp.keyWindow?.toggleFullScreen(nil)
                return nil
            case 123: // Left arrow
                engine.skipBack15()
                return nil
            case 124: // Right arrow
                engine.skipForward15()
                return nil
            case 126: // Up arrow
                // Volume up
                return nil
            case 125: // Down arrow
                // Volume down
                return nil
            default:
                break
            }
            return event
        }
    }

    private func removeKeyboardShortcuts() {
        // Monitors are removed automatically on deinit via NSEvent.removeMonitor
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Apps/LunaMac/Sources/Screens/MacPlayerView.swift
git commit -m "feat: MacPlayerView with AVPlayer, controls overlay, and keyboard shortcuts"
```

### Task 22: Build and verify

**Files:** No new files — verify the entire app compiles.

- [ ] **Step 1: Build LunaCore**

```bash
cd /Users/zain/projects/Luna && xcodebuild -scheme LunaCore build 2>&1 | tail -10
```

- [ ] **Step 2: Build LunaMac**

```bash
cd /Users/zain/projects/Luna && xcodebuild -scheme LunaMac -destination 'platform=macOS' build 2>&1 | tail -10
```

- [ ] **Step 3: Fix any compilation errors**

Review build output. Common issues to check:
- Missing `import LunaCore` in new files
- `Color(hex:)` initializer — if not defined in LunaCore, add it
- macOS-specific API availability (`NSApp`, `NSEvent`, `NSVisualEffectView`)
- `NavigationStack` usage — macOS doesn't support `navigationDestination` the same way; verify

- [ ] **Step 4: Commit any fixes**

```bash
git add -A && git commit -m "fix: compilation fixes for LunaMac redesign"
```

---

## Phase 7: Polish

### Task 23: Remove iOS-local Color(hex:) duplicate + final verification

**Files:**
- Modify: `Apps/LunaApp/Sources/Screens/ProfileSelectionScreen.swift` (remove `extension Color { init(hex:) }` at line ~208)
- Verify both apps compile

- [ ] **Step 1: Remove duplicate Color(hex:) from ProfileSelectionScreen**

Delete the `extension Color { init(hex: String) { ... } }` block at the bottom of ProfileSelectionScreen.swift (it's now provided by LunaCore).

- [ ] **Step 2: Build LunaCore**

```bash
cd /Users/zain/projects/Luna && xcodebuild -scheme LunaCore build 2>&1 | tail -5
```

- [ ] **Step 3: Build LunaMac**

```bash
cd /Users/zain/projects/Luna && xcodebuild -scheme LunaMac -destination 'platform=macOS' build 2>&1 | tail -5
```

- [ ] **Step 4: Build LunaApp (no regressions)**

```bash
cd /Users/zain/projects/Luna && xcodebuild -scheme LunaApp -destination 'platform=iOS Simulator,name=iPhone 15' build 2>&1 | tail -5
```

- [ ] **Step 5: Fix any compilation errors and commit**

```bash
git add -A && git commit -m "chore: remove duplicate Color(hex:), final verification for LunaMac redesign"
```

- [ ] **Step 1: Clean build macOS app**

```bash
cd /Users/zain/projects/Luna && xcodebuild -scheme LunaMac -destination 'platform=macOS' clean build 2>&1 | grep -E "(error:|BUILD SUCCEEDED|BUILD FAILED)"
```

- [ ] **Step 2: Verify iOS app still builds (no regressions)**

```bash
cd /Users/zain/projects/Luna && xcodebuild -scheme LunaApp -destination 'platform=iOS Simulator,name=iPhone 15' build 2>&1 | grep -E "(error:|BUILD SUCCEEDED|BUILD FAILED)"
```

- [ ] **Step 3: Commit final state**

```bash
git add -A && git commit -m "chore: final build verification and fixes for LunaMac redesign"
```
