import SwiftUI
import MoonlitCore

#Preview("Settings") {
    NavigationStack {
        SettingsScreen()
            .environmentObject(ProfileManager.shared)
            .environmentObject(RoleManager.shared)
    }
    .preferredColorScheme(.dark)
}

struct SettingsScreen: View {
    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var roleManager: RoleManager
    @StateObject private var addonRepo = AddonRepository.shared
    @StateObject private var metadataIntegrations = MetadataIntegrationStore.shared
    @StateObject private var traktAuth = TraktAuthService.shared
    @State private var showAddons = false
    @State private var showAuth = false
    @State private var showCatalogManagement = false
    @State private var showSubtitleAppearance = false
    @AppStorage("moonlit.cinematicModeEnabled") private var cinematicModeEnabled = false
    @AppStorage("moonlit.guestMode") private var guestMode = false
    @State private var showDeleteConfirm = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {

                    // ── IDENTITY ──────────────────────────────────────
                    // Uncarded, above the first group: who you are, and the two
                    // account actions that belong to that question.
                    if let profile = profileManager.currentProfile {
                        HStack(spacing: 12) {
                            ProfileAvatarView(profile: profile, size: 44)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(profile.name)
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundColor(.white)
                                    if roleManager.isAdmin {
                                        Text("ADMIN")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundColor(Color(red: 0.35, green: 0.34, blue: 0.84))
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2)
                                            .background(Color(red: 0.35, green: 0.34, blue: 0.84).opacity(0.15))
                                            .cornerRadius(MoonlitTheme.radiusSmall)
                                    }
                                }
                                if let email = profileManager.currentSession?.email {
                                    Text(email)
                                        .font(.caption)
                                        .foregroundColor(MoonlitTheme.textTertiary)
                                }
                            }
                            Spacer()
                            Button {
                                profileManager.currentProfile = nil
                            } label: {
                                Text("Switch")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 13)
                                    .padding(.vertical, 7)
                                    .background(Color.white.opacity(0.10), in: Capsule())
                                    .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(14)
                        .background(
                            LinearGradient(
                                colors: [MoonlitTheme.accent.opacity(0.13), Color.white.opacity(0.04)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(MoonlitTheme.accent.opacity(0.20), lineWidth: 1)
                        )
                        .padding(.horizontal, 16)
                    } else if !profileManager.isAuthenticated {
                        Button { showAuth = true } label: {
                            settingsRow(
                                icon: "person.crop.circle.badge.plus",
                                title: "Sign in",
                                subtitle: "Sync profiles and collections"
                            )
                        }
                        .buttonStyle(.plain)
                        .settingsGroupStyle()
                    }

                    // Apple ID sits directly under the profile card — it answers
                    // "which account is this?", not "what else can the app do?".
                    if profileManager.isAuthenticated {
                        ConnectAppleIDButton()
                            .padding(.top, 8)
                            .padding(.horizontal, 16)
                    }

                    // ── ACCOUNT ───────────────────────────────────────
                    settingsGroupLabel("Account")
                    VStack(spacing: 0) {
                        if profileManager.isAuthenticated {
                            if traktAuth.isConnected {
                                HStack(spacing: 12) {
                                    settingsIcon("checkmark.seal")
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Trakt")
                                            .font(.system(size: 15))
                                            .foregroundColor(.white)
                                        Text("Connected · watchlist synced to Upcoming")
                                            .font(.caption)
                                            .foregroundColor(MoonlitTheme.textTertiary)
                                    }
                                    Spacer()
                                    Button("Disconnect") {
                                        guard let profile = profileManager.currentProfile else { return }
                                        Task { await traktAuth.disconnect(profileId: profile.id) }
                                    }
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.red)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.red.opacity(0.1))
                                    .cornerRadius(MoonlitTheme.radiusControl)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                            } else {
                                if roleManager.isAdmin {
                                    settingsTextField(
                                        icon: "key.fill",
                                        placeholder: "Trakt Client ID",
                                        text: Binding(
                                            get: { metadataIntegrations.traktClientId },
                                            set: { metadataIntegrations.traktClientId = $0 }
                                        )
                                    )
                                    settingsRowDivider()
                                    settingsTextField(
                                        icon: "lock.fill",
                                        placeholder: "Trakt Client Secret",
                                        text: Binding(
                                            get: { metadataIntegrations.traktClientSecret },
                                            set: { metadataIntegrations.traktClientSecret = $0 }
                                        ),
                                        isSecure: true
                                    )
                                    settingsRowDivider()
                                }
                                Button {
                                    guard let profile = profileManager.currentProfile else { return }
                                    traktAuth.connect(profileId: profile.id)
                                } label: {
                                    settingsRow(
                                        icon: "tv.and.mediabox",
                                        title: "Connect Trakt",
                                        subtitle: traktAuth.isConnecting ? "Waiting for authorization..."
                                            : metadataIntegrations.traktClientId.isEmpty ? "Enter Client ID above first"
                                            : "Sync your watchlist to Upcoming"
                                    )
                                }
                                .buttonStyle(.plain)
                                .disabled(traktAuth.isConnecting || metadataIntegrations.traktClientId.isEmpty)
                            }
                            settingsRowDivider()
                        }
                        NavigationLink {
                            MetadataIntegrationsScreen()
                        } label: {
                            settingsRow(
                                icon: "text.magnifyingglass",
                                title: "Metadata",
                                subtitle: metadataIntegrations.effectiveTVDBAPIKey == nil ? "TMDB" : "TVDB + TMDB"
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .settingsGroupStyle()

                    // ── PLAYBACK ──────────────────────────────────────
                    settingsGroupLabel("Playback")
                    VStack(spacing: 0) {
                        NavigationLink { VideoPlayerSettingsScreen() } label: {
                            settingsRow(
                                icon: "play.circle",
                                title: "Video Player",
                                subtitle: "Skip Intro · Auto-detect"
                            )
                        }
                        .buttonStyle(.plain)
                        settingsRowDivider()
                        Button { showSubtitleAppearance = true } label: {
                            settingsRow(
                                icon: "captions.bubble",
                                title: "Subtitles",
                                subtitle: SubtitleAppearanceStore.shared.preset.displayName
                            )
                        }
                        .buttonStyle(.plain)
                        if profileManager.isAuthenticated {
                            settingsRowDivider()
                            NavigationLink { StreamAutoplaySettingsScreen() } label: {
                                settingsRow(
                                    icon: "bolt",
                                    title: "Stream Auto-Play",
                                    value: streamAutoplaySummary
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .settingsGroupStyle()

                    // ── APPEARANCE ────────────────────────────────────
                    settingsGroupLabel("Appearance")
                    VStack(spacing: 0) {
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                cinematicModeEnabled.toggle()
                            }
                        } label: {
                            cinematicModeRow
                        }
                        .buttonStyle(.plain)
                        settingsRowDivider()
                        NavigationLink { CollectionDesignScreen() } label: {
                            settingsRow(
                                icon: "rectangle.3.group",
                                title: "Collection Design",
                                subtitle: "Row layouts for Home"
                            )
                        }
                        .buttonStyle(.plain)
                        settingsRowDivider()
                        #if os(iOS)
                        NavigationLink { AppIconPickerScreen() } label: {
                            settingsRow(
                                icon: "app.dashed",
                                title: "App Icon",
                                subtitle: "Change the home screen icon"
                            )
                        }
                        .buttonStyle(.plain)
                        settingsRowDivider()
                        #endif
                        NavigationLink { PosterBadgesScreen() } label: {
                            settingsRow(
                                icon: "rectangle.badge.checkmark",
                                title: "Poster Badges",
                                subtitle: "Tags shown on posters"
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .settingsGroupStyle()

                    // ── CONTENT ───────────────────────────────────────
                    // Admin tooling folds in here rather than getting its own
                    // group; role gating already hides it from everyone else.
                    if roleManager.isAdmin {
                        settingsGroupLabel("Content")
                        VStack(spacing: 0) {
                            Button { showAddons = true } label: {
                                settingsRow(
                                    icon: "puzzlepiece.extension",
                                    title: "Addons",
                                    subtitle: "\(addonRepo.managedAddons.count) installed"
                                )
                            }
                            .buttonStyle(.plain)
                            settingsRowDivider()
                            Button { showCatalogManagement = true } label: {
                                settingsRow(icon: "folder", title: "Catalog Management")
                            }
                            .buttonStyle(.plain)
                            settingsRowDivider()
                            NavigationLink { HeroManagementScreen() } label: {
                                settingsRow(icon: "film", title: "Hero Management")
                            }
                            .buttonStyle(.plain)
                            settingsRowDivider()
                            NavigationLink { AdminDashboard() } label: {
                                settingsRow(icon: "shield", title: "Admin Dashboard")
                            }
                            .buttonStyle(.plain)
                        }
                        .settingsGroupStyle()
                    } else if roleManager.profileRole.canManageOwnAddons {
                        // Premium+ (self-manage): may add & manage their own addons,
                        // including their own stream addon. Other paid roles get
                        // addons provisioned for them and have no management entry.
                        settingsGroupLabel("Content")
                        VStack(spacing: 0) {
                            Button { showAddons = true } label: {
                                settingsRow(
                                    icon: "puzzlepiece.extension",
                                    title: "Addons",
                                    subtitle: "\(addonRepo.managedAddons.count) installed"
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        .settingsGroupStyle()
                    } else if !profileManager.isAuthenticated {
                        settingsGroupLabel("Content")
                        VStack(spacing: 0) {
                            Button { showAddons = true } label: {
                                settingsRow(
                                    icon: "puzzlepiece.extension",
                                    title: "Catalog & Metadata Addons",
                                    subtitle: "Streaming addons require sign in"
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        .settingsGroupStyle()
                    }

                    // ── ABOUT ─────────────────────────────────────────
                    settingsGroupLabel("About")
                    VStack(spacing: 0) {
                        settingsRow(icon: "info.circle", title: "Version", value: "1.0.0", showsChevron: false)
                        settingsRowDivider()
                        Link(destination: URL(string: "https://trymoonlit.app/privacy")!) {
                            settingsRow(icon: "lock.shield", title: "Privacy Policy")
                        }
                        .buttonStyle(.plain)
                        settingsRowDivider()
                        Link(destination: URL(string: "https://trymoonlit.app/terms")!) {
                            settingsRow(icon: "doc.text", title: "Terms of Use")
                        }
                        .buttonStyle(.plain)
                        settingsRowDivider()
                        Link(destination: URL(string: "https://www.themoviedb.org")!) {
                            settingsRow(
                                icon: "film.stack",
                                title: "Movie & TV Metadata",
                                subtitle: "This product uses the TMDB API but is not endorsed or certified by TMDB."
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .settingsGroupStyle()

                    // ── DESTRUCTIVE ───────────────────────────────────
                    if profileManager.isAuthenticated {
                        Button(role: .destructive) {
                            Task { await profileManager.signOut() }
                        } label: {
                            Text("Sign Out")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.red)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 15)
                                .background(Color.red.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(Color.red.opacity(0.18), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)
                        .padding(.top, 22)

                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Text("Delete Account")
                                .font(.system(size: 13))
                                .foregroundColor(.red.opacity(0.55))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                        .confirmationDialog(
                            "Delete Account",
                            isPresented: $showDeleteConfirm,
                            titleVisibility: .visible
                        ) {
                            Button("Delete Account and All Data", role: .destructive) {
                                Task { try? await profileManager.deleteAccount() }
                            }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("This permanently deletes your Moonlit account and all profiles. This cannot be undone.")
                        }
                    }

                    Spacer().frame(height: 40)
                }
                .padding(.top, 16)
            }
            .background(MoonlitTheme.background)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showAddons) { AddonsScreen() }
            .sheet(isPresented: $showAuth) {
                AuthScreen()
                    .environmentObject(profileManager)
            }
            .sheet(isPresented: $showCatalogManagement) { CatalogManagementScreen() }
            .sheet(isPresented: $showSubtitleAppearance) { SubtitleAppearanceScreen() }
            .task {
                if let profile = profileManager.currentProfile {
                    await TraktAuthService.shared.loadToken(profileId: profile.id)
                }
            }
            .onChange(of: profileManager.currentProfile) { _, profile in
                guard let profile else { return }
                Task { await TraktAuthService.shared.loadToken(profileId: profile.id) }
            }
            .onChange(of: profileManager.isAuthenticated) { _, isAuthenticated in
                if isAuthenticated {
                    guestMode = false
                    showAuth = false
                }
            }
        }
    }

    // MARK: - Helpers

    private var streamAutoplaySummary: String {
        guard let profile = profileManager.currentProfile else { return "Manual" }
        switch StreamAutoplayPreferenceStore.shared.mode(profileId: profile.id) {
        case .manual: return "Manual"
        case .automatic: return "Automatic"
        }
    }

    private var cinematicModeRow: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: MoonlitTheme.radiusSmall)
                    .fill(Color(red: 0.22, green: 0.42, blue: 0.72))
                    .frame(width: 28, height: 28)
                Image(systemName: "sparkles.tv.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Cinematic Mode")
                    .font(.subheadline)
                    .foregroundColor(.white)
                Text("Fusion-style media center Home")
                    .font(.caption)
                    .foregroundColor(MoonlitTheme.textTertiary)
            }

            Spacer()

            ZStack(alignment: cinematicModeEnabled ? .trailing : .leading) {
                Capsule()
                    .fill(cinematicModeEnabled ? MoonlitTheme.accent.opacity(0.95) : Color.white.opacity(0.16))
                    .frame(width: 52, height: 30)
                Circle()
                    .fill(.white)
                    .frame(width: 26, height: 26)
                    .padding(2)
                    .shadow(color: .black.opacity(0.22), radius: 3, x: 0, y: 1)
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.82), value: cinematicModeEnabled)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    /// A settings row in the reference aesthetic: a thin monoline glyph in plain
    /// white, a 15pt label, and a quiet chevron. Deliberately no coloured icon
    /// tile — the colour carried no meaning and eight competing hues read as noise.
    private func settingsRow(
        icon: String,
        title: String,
        subtitle: String? = nil,
        value: String? = nil,
        showsChevron: Bool = true
    ) -> some View {
        HStack(spacing: 12) {
            settingsIcon(icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15))
                    .foregroundColor(.white)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(MoonlitTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if let value {
                Text(value)
                    .font(.caption)
                    .foregroundColor(MoonlitTheme.textTertiary)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(MoonlitTheme.textTertiary.opacity(0.65))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func settingsIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 17, weight: .regular))
            .foregroundColor(.white)
            .frame(width: 24, height: 24)
    }

    /// Inset to the label, matching the reference — not full-bleed.
    private func settingsRowDivider() -> some View {
        Divider()
            .background(Color.white.opacity(0.06))
            .padding(.leading, 50)
    }

    @ViewBuilder
    private func settingsTextField(icon: String, placeholder: String, text: Binding<String>, isSecure: Bool = false) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: MoonlitTheme.radiusSmall)
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 28, height: 28)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(MoonlitTheme.textSecondary)
            }
            if isSecure {
                SecureField(placeholder, text: text)
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            } else {
                TextField(placeholder, text: text)
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }
}

@MainActor
private func settingsGroupLabel(_ text: String) -> some View {
    Text(text.uppercased())
        .font(.system(size: 11, weight: .semibold))
        .tracking(0.9)
        .foregroundColor(MoonlitTheme.textTertiary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 22)
        .padding(.top, 22)
        .padding(.bottom, 7)
}

/// One rounded container per group — 16pt radius, hairline border.
private struct SettingsGroupStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.055), lineWidth: 1)
            )
            .padding(.horizontal, 16)
    }
}

private extension View {
    func settingsGroupStyle() -> some View { modifier(SettingsGroupStyle()) }
}

struct StreamAutoplaySettingsScreen: View {
    @EnvironmentObject var profileManager: ProfileManager
    @StateObject private var addonRepo = AddonRepository.shared
    @State private var mode: StreamAutoplayMode = .manual
    @State private var selectedAddonUrls: [String] = []
    @State private var timeoutSeconds: Int?

    private let timeoutOptions: [Int?] = [nil, 0, 5, 10, 15, 30]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("STREAM AUTO-PLAY")
                    .font(.caption.weight(.bold))
                    .foregroundColor(MoonlitTheme.textTertiary)
                    .padding(.horizontal, 20)

                VStack(spacing: 0) {
                    modeSection

                    Divider().background(Color.white.opacity(0.08))

                    timeoutSection

                    Divider().background(Color.white.opacity(0.08))

                    sourceScopeSection

                    Divider().background(Color.white.opacity(0.08))

                    allowedAddonsSection
                }
                .glassCard(cornerRadius: MoonlitTheme.radiusCard)
                .padding(.horizontal, 16)

                Text("Manual opens the source picker. Automatic launches a ranked source from the allowed addons after the selected wait time.")
                    .font(.caption)
                    .foregroundColor(MoonlitTheme.textTertiary)
                    .padding(.horizontal, 20)
            }
            .padding(.top, 16)
        }
        .background(MoonlitTheme.background)
        .navigationTitle("Stream Auto-Play")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            loadPreferences()
            guard let profile = profileManager.currentProfile else { return }
            if addonRepo.managedAddons.isEmpty {
                await addonRepo.loadAddons(profileId: profile.id)
            }
        }
    }

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Auto Stream Selection")
                .font(.headline)
                .foregroundColor(.white)

            Picker("Auto Stream Selection", selection: Binding(
                get: { mode },
                set: { newValue in
                    mode = newValue
                    persistMode(newValue)
                }
            )) {
                Text("Manual").tag(StreamAutoplayMode.manual)
                Text("Automatic").tag(StreamAutoplayMode.automatic)
            }
            .pickerStyle(.segmented)

            Text(mode == .manual ? "Manual (choose stream)" : "Automatic (pick for me)")
                .font(.subheadline)
                .foregroundColor(MoonlitTheme.textSecondary)
        }
        .padding(16)
    }

    private var timeoutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Stream Selection Timeout")
                        .font(.headline)
                        .foregroundColor(.white)
                    Text("Wait time for addons before selecting.")
                        .font(.subheadline)
                        .foregroundColor(MoonlitTheme.textSecondary)
                }
                Spacer()
                Text(timeoutLabel(timeoutSeconds))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(MoonlitTheme.accent)
            }

            Picker("Timeout", selection: Binding(
                get: { timeoutTag(timeoutSeconds) },
                set: { tag in
                    timeoutSeconds = timeoutValue(tag)
                    persistTimeout(timeoutSeconds)
                }
            )) {
                ForEach(timeoutOptions.indices, id: \.self) { index in
                    Text(timeoutLabel(timeoutOptions[index])).tag(index)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(16)
        .opacity(mode == .automatic ? 1 : 0.45)
        .disabled(mode != .automatic)
    }

    private var sourceScopeSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Auto-play Source Scope")
                .font(.headline)
                .foregroundColor(.white)
            Text("Installed addons only")
                .font(.subheadline)
                .foregroundColor(MoonlitTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .opacity(mode == .automatic ? 1 : 0.45)
    }

    private var allowedAddonsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Allowed Addons")
                        .font(.headline)
                        .foregroundColor(.white)
                    Text(allowedAddonSummary)
                        .font(.subheadline)
                        .foregroundColor(MoonlitTheme.textSecondary)
                }
                Spacer()
                if !selectedAddonUrls.isEmpty {
                    Button("All") {
                        selectedAddonUrls = []
                        persistSelectedAddonUrls()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(MoonlitTheme.accent)
                }
            }

            if streamAddons.isEmpty {
                Text(addonRepo.isLoading ? "Loading addons..." : "No sources installed")
                    .font(.caption)
                    .foregroundColor(MoonlitTheme.textTertiary)
            } else {
                VStack(spacing: 0) {
                    ForEach(streamAddons) { addon in
                        Toggle(isOn: Binding(
                            get: { isAddonAllowed(addon) },
                            set: { isAllowed in setAddon(addon, isAllowed: isAllowed) }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(addon.displayName)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(.white)
                                Text(addon.manifestUrl)
                                    .font(.caption2)
                                    .foregroundColor(MoonlitTheme.textTertiary)
                                    .lineLimit(1)
                            }
                        }
                        .toggleStyle(.switch)
                        .padding(.vertical, 10)

                        if addon.id != streamAddons.last?.id {
                            Divider().background(Color.white.opacity(0.08))
                        }
                    }
                }
            }
        }
        .padding(16)
        .opacity(mode == .automatic ? 1 : 0.45)
        .disabled(mode != .automatic)
    }

    private var streamAddons: [ManagedAddon] {
        addonRepo.managedAddons.filter {
            $0.enabled && $0.manifest.hasResource("stream")
        }
    }

    private var allowedAddonSummary: String {
        if selectedAddonUrls.isEmpty {
            return "All enabled sources"
        }
        return "\(selectedAddonUrls.count) selected"
    }

    private func loadPreferences() {
        guard let profile = profileManager.currentProfile else { return }
        mode = StreamAutoplayPreferenceStore.shared.mode(profileId: profile.id)
        selectedAddonUrls = StreamAutoplayPreferenceStore.shared.automaticAddonUrls(profileId: profile.id)
        timeoutSeconds = StreamAutoplayPreferenceStore.shared.timeoutSeconds(profileId: profile.id)
    }

    private func persistMode(_ mode: StreamAutoplayMode) {
        guard let profile = profileManager.currentProfile else { return }
        StreamAutoplayPreferenceStore.shared.setMode(mode, profileId: profile.id)
    }

    private func persistTimeout(_ seconds: Int?) {
        guard let profile = profileManager.currentProfile else { return }
        StreamAutoplayPreferenceStore.shared.setTimeoutSeconds(seconds, profileId: profile.id)
    }

    private func persistSelectedAddonUrls() {
        guard let profile = profileManager.currentProfile else { return }
        StreamAutoplayPreferenceStore.shared.setAutomaticAddonUrls(selectedAddonUrls, profileId: profile.id)
    }

    private func isAddonAllowed(_ addon: ManagedAddon) -> Bool {
        selectedAddonUrls.isEmpty || selectedAddonUrls.contains(addon.manifestUrl)
    }

    private func setAddon(_ addon: ManagedAddon, isAllowed: Bool) {
        if selectedAddonUrls.isEmpty {
            selectedAddonUrls = streamAddons.map(\.manifestUrl)
        }
        if isAllowed {
            if !selectedAddonUrls.contains(addon.manifestUrl) {
                selectedAddonUrls.append(addon.manifestUrl)
            }
        } else {
            selectedAddonUrls.removeAll { $0 == addon.manifestUrl }
        }
        if selectedAddonUrls.count == streamAddons.count {
            selectedAddonUrls = []
        }
        persistSelectedAddonUrls()
    }

    private func timeoutTag(_ value: Int?) -> Int {
        timeoutOptions.firstIndex { $0 == value } ?? 0
    }

    private func timeoutValue(_ tag: Int) -> Int? {
        timeoutOptions.indices.contains(tag) ? timeoutOptions[tag] : nil
    }

    private func timeoutLabel(_ value: Int?) -> String {
        guard let value else { return "Unlimited" }
        return value == 0 ? "Instant" : "\(value)s"
    }
}

struct MetadataIntegrationsScreen: View {
    @StateObject private var store = MetadataIntegrationStore.shared
    @State private var tvdbState: MetadataProviderConnectionState = .missing
    @State private var tmdbState: MetadataProviderConnectionState = .missing

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 0) {
                    integrationField(
                        title: "TVDB API Key",
                        subtitle: "Used first for episode thumbnails.",
                        value: Binding(
                            get: { store.tvdbAPIKey },
                            set: {
                                store.setTVDBAPIKey($0)
                                tvdbState = store.effectiveTVDBAPIKey == nil ? .missing : .checking
                            }
                        ),
                        state: tvdbState
                    )

                    Divider().background(Color.white.opacity(0.08))

                    integrationField(
                        title: "TMDB API Key",
                        subtitle: "Used as fallback for missing metadata and episode stills.",
                        value: Binding(
                            get: { store.tmdbAPIKey },
                            set: {
                                store.setTMDBAPIKey($0)
                                tmdbState = store.effectiveTMDBAPIKey == nil ? .missing : .checking
                            }
                        ),
                        state: tmdbState
                    )
                }
                .glassCard(cornerRadius: MoonlitTheme.radiusCard)
                .padding(.horizontal, 16)

                Button {
                    Task { await checkConnections() }
                } label: {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Check Connections")
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(14)
                }
                .glassProminentButtonStyle(cornerRadius: MoonlitTheme.radiusCard)
                .padding(.horizontal, 16)

                Text("Episode images resolve from TVDB first, then TMDB, then any usable addon image.")
                    .font(.caption)
                    .foregroundColor(MoonlitTheme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 32)
            }
            .padding(.top, 16)
        }
        .background(MoonlitTheme.background)
        .navigationTitle("Integrations")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await checkConnections()
        }
    }

    private func integrationField(
        title: String,
        subtitle: String,
        value: Binding<String>,
        state: MetadataProviderConnectionState
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                Spacer()
                Label(state.label, systemImage: stateIcon(for: state))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(stateColor(for: state))
            }

            SecureField("", text: value, prompt: Text("Paste API key").foregroundColor(MoonlitTheme.textTertiary))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundColor(.white)
                .font(.callout.monospaced())
                .padding(12)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: MoonlitTheme.radiusControl))
                .overlay(
                    RoundedRectangle(cornerRadius: MoonlitTheme.radiusControl)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )

            Text(subtitle)
                .font(.caption)
                .foregroundColor(MoonlitTheme.textTertiary)
        }
        .padding(16)
    }

    private func checkConnections() async {
        async let tvdb = checkTVDB()
        async let tmdb = checkTMDB()
        tvdbState = await tvdb
        tmdbState = await tmdb
    }

    private func checkTVDB() async -> MetadataProviderConnectionState {
        guard let apiKey = store.effectiveTVDBAPIKey else { return .missing }
        tvdbState = .checking

        guard let url = URL(string: "https://api4.thetvdb.com/v4/login") else {
            return .failed("Invalid URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(["apikey": apiKey])

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                return .failed("Rejected")
            }
            let decoded = try JSONDecoder().decode(TVDBConnectionResponse.self, from: data)
            return decoded.data.token.isEmpty ? .failed("No token") : .connected
        } catch {
            return .failed("Failed")
        }
    }

    private func checkTMDB() async -> MetadataProviderConnectionState {
        guard let apiKey = store.effectiveTMDBAPIKey else { return .missing }
        tmdbState = .checking

        var components = URLComponents(string: "https://api.themoviedb.org/3/find/tt9813792")
        components?.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "external_source", value: "imdb_id")
        ]
        guard let url = components?.url else { return .failed("Invalid URL") }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                return .failed("Rejected")
            }
            let decoded = try JSONDecoder().decode(TMDBConnectionResponse.self, from: data)
            return decoded.tv_results.isEmpty ? .failed("No results") : .connected
        } catch {
            return .failed("Failed")
        }
    }

    private func stateIcon(for state: MetadataProviderConnectionState) -> String {
        switch state {
        case .connected:
            "checkmark.circle.fill"
        case .checking:
            "clock"
        case .missing:
            "minus.circle"
        case .failed:
            "exclamationmark.triangle.fill"
        }
    }

    private func stateColor(for state: MetadataProviderConnectionState) -> Color {
        switch state {
        case .connected:
            .green
        case .checking:
            MoonlitTheme.textSecondary
        case .missing:
            MoonlitTheme.textTertiary
        case .failed:
            .orange
        }
    }
}

private struct TVDBConnectionResponse: Decodable {
    struct Payload: Decodable {
        let token: String
    }

    let data: Payload
}

private struct TMDBConnectionResponse: Decodable {
    let tv_results: [TMDBResult]

    struct TMDBResult: Decodable {
        let id: Int
    }
}

struct CatalogManagementScreen: View {
    @StateObject private var collectionRepo = CollectionRepository.shared
    @StateObject private var preferenceStore = CollectionDisplayPreferenceStore.shared

    var body: some View {
        NavigationStack {
            ZStack {
                MoonlitTheme.background.ignoresSafeArea()

                if collectionRepo.isLoading && collectionRepo.collections.isEmpty {
                    VStack(spacing: 16) {
                        LottieLoadingView(size: 36)
                        Text("Loading catalogs...")
                            .font(.subheadline)
                            .foregroundColor(MoonlitTheme.textSecondary)
                    }
                } else if collectionRepo.collections.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "rectangle.stack.badge.questionmark")
                            .font(.system(size: 42))
                            .foregroundColor(MoonlitTheme.textTertiary)
                        Text("No folder catalogs found")
                            .font(.headline)
                            .foregroundColor(.white)
                        Text("Collections from your configured folders will appear here.")
                            .font(.subheadline)
                            .foregroundColor(MoonlitTheme.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                } else {
                    List {
                        Section {
                            Text("Choose which folder catalogs appear on Home. Turning folders into rows changes a collection like Decades into separate 1980s, 1990s, and other rows.")
                                .font(.caption)
                                .foregroundColor(MoonlitTheme.textSecondary)
                        }

                        ForEach(collectionRepo.collections) { collection in
                            Section(collection.name) {
                                Toggle("Show catalog", isOn: Binding(
                                    get: { preferenceStore.isCollectionEnabled(collection) },
                                    set: { preferenceStore.setCollection(collection, enabled: $0) }
                                ))
                                Toggle("Turn folders into rows", isOn: Binding(
                                    get: { preferenceStore.isCollectionExpanded(collection) },
                                    set: { preferenceStore.setCollection(collection, expanded: $0) }
                                ))

                                let folders = collectionRepo.folders(for: collection)
                                if folders.isEmpty {
                                    Text("No folders in this catalog.")
                                        .font(.caption)
                                        .foregroundColor(MoonlitTheme.textTertiary)
                                } else {
                                    ForEach(folders.filter { !preferenceStore.isFolderHidden($0) }) { folder in
                                        HStack(spacing: 12) {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(folder.name)
                                                    .foregroundColor(.white)
                                                Text("Folder")
                                                    .font(.caption2)
                                                    .foregroundColor(MoonlitTheme.textTertiary)
                                            }
                                            Spacer()
                                            Button("Remove") {
                                                preferenceStore.setFolder(folder, hidden: true)
                                            }
                                            .font(.caption.weight(.semibold))
                                            .foregroundColor(.red)
                                        }
                                        .contentShape(Rectangle())
                                        .padding(.vertical, 4)
                                    }

                                    ForEach(folders.filter { preferenceStore.isFolderHidden($0) }) { folder in
                                        HStack(spacing: 12) {
                                            Text(folder.name)
                                                .foregroundColor(MoonlitTheme.textTertiary)
                                            Spacer()
                                            Button("Restore") {
                                                preferenceStore.setFolder(folder, hidden: false)
                                            }
                                            .font(.caption.weight(.semibold))
                                            .foregroundColor(MoonlitTheme.accent)
                                        }
                                        .padding(.vertical, 4)
                                    }
                                }
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Catalog Management")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                if collectionRepo.collections.isEmpty {
                    await collectionRepo.refreshForCatalogRows()
                }
            }
        }
    }
}

// MARK: - Addon category

private enum AddonCategory: String, CaseIterable {
    case streaming = "Streaming"
    case metadata  = "Metadata"
    case catalogs  = "Catalogs"
    case subtitles = "Subtitles"
    case other     = "Other"

    var icon: String {
        switch self {
        case .streaming: return "play.rectangle.fill"
        case .metadata:  return "info.circle.fill"
        case .catalogs:  return "square.grid.2x2.fill"
        case .subtitles: return "captions.bubble.fill"
        case .other:     return "puzzlepiece.fill"
        }
    }

    var color: Color {
        switch self {
        case .streaming: return .blue
        case .metadata:  return .purple
        case .catalogs:  return .orange
        case .subtitles: return .green
        case .other:     return .gray
        }
    }

    static func primary(for addon: ManagedAddon) -> AddonCategory {
        let m = addon.manifest
        if m.hasResource("stream")     { return .streaming }
        if m.hasResource("meta")       { return .metadata }
        if m.hasResource("catalog") || !(m.catalogs ?? []).isEmpty { return .catalogs }
        if m.hasResource("subtitles")  { return .subtitles }
        return .other
    }

    func badges(for addon: ManagedAddon) -> [String] {
        let m = addon.manifest
        var tags: [String] = []
        if m.hasResource("stream")    { tags.append("Stream") }
        if m.hasResource("meta")      { tags.append("Metadata") }
        if m.hasResource("catalog") || !(m.catalogs ?? []).isEmpty { tags.append("Catalogs") }
        if m.hasResource("subtitles") { tags.append("Subtitles") }
        return tags
    }
}

// MARK: - AddonsScreen

struct AddonsScreen: View {
    @StateObject private var addonRepo = AddonRepository.shared
    @AppStorage("moonlit.guestMode") private var guestMode = false
    @State private var newAddonURL = ""
    @State private var showAddSheet = false
    @State private var installError: String?
    @State private var isInstalling = false

    private var isGuestAddonsMode: Bool {
        guestMode && !ProfileManager.shared.isAuthenticated
    }

    private var visibleManagedAddons: [ManagedAddon] {
        guard isGuestAddonsMode else { return addonRepo.managedAddons }
        return addonRepo.managedAddons.filter { addon in
            let manifest = addon.manifest
            return !manifest.hasResource("stream")
                && (manifest.hasResource("catalog")
                    || !(manifest.catalogs ?? []).isEmpty
                    || manifest.hasResource("meta"))
        }
    }

    private var grouped: [(AddonCategory, [ManagedAddon])] {
        var dict: [AddonCategory: [ManagedAddon]] = [:]
        for addon in visibleManagedAddons {
            let cat = AddonCategory.primary(for: addon)
            dict[cat, default: []].append(addon)
        }
        let categories = isGuestAddonsMode ? [AddonCategory.metadata, .catalogs] : AddonCategory.allCases
        return categories.compactMap { cat in
            guard let addons = dict[cat], !addons.isEmpty else { return nil }
            return (cat, addons)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                MoonlitTheme.background.ignoresSafeArea()

                if addonRepo.isLoading {
                    VStack(spacing: 16) {
                        LottieLoadingView(size: 36)
                        Text("Loading addons...")
                            .font(.subheadline)
                            .foregroundColor(MoonlitTheme.textSecondary)
                    }
                } else if let error = addonRepo.errorMessage, visibleManagedAddons.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 44))
                            .foregroundColor(.orange)
                        Text("Failed to load addons")
                            .font(.headline)
                            .foregroundColor(.white)
                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(MoonlitTheme.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        Button {
                            Task {
                                await loadAddonsForCurrentMode()
                            }
                        } label: {
                            Label("Retry", systemImage: "arrow.clockwise")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 24)
                                .padding(.vertical, 10)
                        }
                        .glassCard(cornerRadius: MoonlitTheme.radiusCard, interactive: true)
                        .foregroundColor(.white)
                    }
                } else {
                    List {
                        if isGuestAddonsMode {
                            Section {
                                Text("Guest mode supports catalog and metadata addons only. Streaming addons require sign in.")
                                    .font(.caption)
                                    .foregroundColor(MoonlitTheme.textSecondary)
                            }
                        }

                        ForEach(grouped, id: \.0) { category, addons in
                            Section {
                                ForEach(addons) { addon in
                                    AddonRow(addon: addon, category: category)
                                }
                                .onDelete { indexSet in
                                    let deletable = addons.filter { !addonRepo.isManaged($0) }
                                    for idx in indexSet where idx < addons.count {
                                        let target = addons[idx]
                                        if !addonRepo.isManaged(target) {
                                            addonRepo.removeAddon(url: target.manifestUrl)
                                        }
                                    }
                                    _ = deletable // suppress warning
                                }
                            } header: {
                                HStack(spacing: 6) {
                                    Image(systemName: category.icon)
                                        .foregroundColor(category.color)
                                    Text(category.rawValue)
                                        .foregroundColor(MoonlitTheme.textSecondary)
                                }
                                .font(.subheadline.weight(.semibold))
                                .textCase(nil)
                            }
                        }

                        if grouped.isEmpty {
                            Section {
                                Text("No catalog or metadata addons available.")
                                    .font(.caption)
                                    .foregroundColor(MoonlitTheme.textTertiary)
                            }
                        }

                        if let error = addonRepo.errorMessage, !visibleManagedAddons.isEmpty {
                            Section {
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            } header: {
                                Text("Warning").foregroundColor(.orange)
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .refreshable {
                        await loadAddonsForCurrentMode()
                    }
                }
            }
            .navigationTitle(isGuestAddonsMode ? "Catalog Addons" : "Addons")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { showAddSheet = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                NavigationStack {
                    VStack(spacing: 20) {
                        Text("Enter an addon manifest URL")
                            .font(.headline)
                            .foregroundColor(.white)

                        TextField("https://.../manifest.json", text: $newAddonURL)
                            .padding()
                            .background(MoonlitTheme.surface)
                            .cornerRadius(MoonlitTheme.radiusCard)
                            .foregroundColor(.white)
                            .padding(.horizontal)
                            .autocapitalization(.none)
                            .keyboardType(.URL)

                        if let error = installError {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }

                        Button {
                            installError = nil
                            isInstalling = true
                            Task {
                                let prevCount = addonRepo.managedAddons.count
                                await addonRepo.installAddon(url: newAddonURL)
                                isInstalling = false
                                if isGuestAddonsMode,
                                   let installed = addonRepo.managedAddons.first(where: { $0.manifestUrl == newAddonURL }),
                                   installed.manifest.hasResource("stream") {
                                    addonRepo.removeAddon(url: installed.manifestUrl)
                                    installError = "Streaming addons require sign in."
                                } else if addonRepo.managedAddons.count > prevCount {
                                    newAddonURL = ""
                                    showAddSheet = false
                                } else if let err = addonRepo.errorMessage {
                                    installError = err
                                } else {
                                    installError = "Addon is already installed."
                                }
                            }
                        } label: {
                            if isInstalling {
                                LottieLoadingView(size: 18)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                            } else {
                                Text("Install")
                                    .frame(maxWidth: .infinity)
                                    .padding()
                            }
                        }
                        .glassProminentButtonStyle(cornerRadius: MoonlitTheme.radiusCard)
                        .disabled(newAddonURL.isEmpty || isInstalling)
                        .padding(.horizontal)

                        Spacer()
                    }
                    .padding(.top)
                    .background(MoonlitTheme.background)
                    .navigationTitle("Add Addon")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                installError = nil
                                showAddSheet = false
                            }
                        }
                    }
                }
            }
            .task {
                if addonRepo.managedAddons.isEmpty {
                    await loadAddonsForCurrentMode()
                }
            }
        }
    }

    private func loadAddonsForCurrentMode() async {
        if isGuestAddonsMode {
            await addonRepo.refreshFromUrls(MoonlitConfig.defaultAddons)
            return
        }

        guard let profile = ProfileManager.shared.currentProfile else { return }
        await addonRepo.loadAddons(profileId: profile.id)
    }
}

// MARK: - AddonRow

private struct AddonRow: View {
    let addon: ManagedAddon
    let category: AddonCategory
    @StateObject private var addonRepo = AddonRepository.shared

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(addon.displayName)
                        .foregroundColor(addon.enabled ? .white : MoonlitTheme.textSecondary)
                        .font(.body)
                    if addonRepo.isManaged(addon) {
                        Text("DEFAULT")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(category.color)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(category.color.opacity(0.15))
                            .cornerRadius(MoonlitTheme.radiusSmall)
                    }
                }

                // Capability badges
                let badges = category.badges(for: addon)
                if !badges.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(badges, id: \.self) { badge in
                            Text(badge)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(MoonlitTheme.textTertiary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.07))
                                .cornerRadius(MoonlitTheme.radiusSmall)
                        }
                    }
                }

                if let err = addon.errorMessage {
                    Text("Error: \(err)")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { addon.enabled },
                set: { _ in addonRepo.toggleAddon(url: addon.manifestUrl) }
            ))
            .labelsHidden()
        }
        .opacity(addon.enabled ? 1 : 0.5)
    }
}
