import SwiftUI
import LunaCore

struct SettingsScreen: View {
    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var roleManager: RoleManager
    @StateObject private var addonRepo = AddonRepository.shared
    @StateObject private var metadataIntegrations = MetadataIntegrationStore.shared
    @State private var showAddons = false
    @State private var showCatalogManagement = false
    @State private var showSubtitleAppearance = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 8) {

                    // ── PROFILE CARD ──────────────────────────────────
                    if let profile = profileManager.currentProfile {
                        HStack(spacing: 12) {
                            ProfileAvatarView(profile: profile, size: 44)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(profile.name)
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    if roleManager.isAdmin {
                                        Text("ADMIN")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundColor(LunaTheme.accent)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2)
                                            .background(LunaTheme.accent.opacity(0.15))
                                            .cornerRadius(4)
                                    }
                                }
                                if let email = profileManager.currentSession?.email {
                                    Text(email)
                                        .font(.caption)
                                        .foregroundColor(LunaTheme.textTertiary)
                                }
                            }
                            Spacer()
                            Button {
                                profileManager.currentProfile = nil
                            } label: {
                                Text("Switch")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(LunaTheme.accent)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(LunaTheme.accent.opacity(0.12))
                                    .cornerRadius(8)
                            }
                        }
                        .padding(16)
                        .glassCard(cornerRadius: 14)
                        .padding(.horizontal, 16)
                    }

                    // ── GENERAL ───────────────────────────────────────
                    settingsSectionLabel("General")
                    VStack(spacing: 0) {
                        NavigationLink {
                            MetadataIntegrationsScreen()
                        } label: {
                            settingsRowLabel(
                                icon: "key.horizontal.fill",
                                iconColor: Color(red: 0.43, green: 0.23, blue: 0.55),
                                title: "Metadata",
                                subtitle: metadataIntegrations.effectiveTVDBAPIKey == nil ? "TMDB" : "TVDB + TMDB"
                            )
                        }
                    }
                    .glassCard(cornerRadius: 14)
                    .padding(.horizontal, 16)

                    // ── CONTENT MANAGEMENT (admin only) ───────────────
                    if roleManager.isAdmin {
                        settingsSectionLabel("Content Management")
                        VStack(spacing: 0) {
                            Button { showAddons = true } label: {
                                settingsRowLabel(
                                    icon: "puzzlepiece.extension.fill",
                                    iconColor: LunaTheme.accent,
                                    title: "Addons",
                                    subtitle: "\(addonRepo.managedAddons.count) installed"
                                )
                            }
                            settingsDivider()
                            Button { showCatalogManagement = true } label: {
                                settingsRowLabel(icon: "folder.fill", iconColor: Color.orange, title: "Catalog Management")
                            }
                            settingsDivider()
                            NavigationLink { HeroManagementScreen() } label: {
                                settingsRowLabel(icon: "film.fill", iconColor: Color.blue, title: "Hero Management")
                            }
                        }
                        .glassCard(cornerRadius: 14)
                        .padding(.horizontal, 16)
                    }

                    // ── PLAYBACK ──────────────────────────────────────
                    settingsSectionLabel("Playback")
                    VStack(spacing: 0) {
                        NavigationLink { VideoPlayerSettingsScreen() } label: {
                            settingsRowLabel(
                                icon: "play.circle.fill",
                                iconColor: Color(red: 0.1, green: 0.42, blue: 0.8),
                                title: "Video Player",
                                subtitle: "Skip Intro · Auto-detect"
                            )
                        }
                        settingsDivider()
                        Button { showSubtitleAppearance = true } label: {
                            settingsRowLabel(
                                icon: "captions.bubble.fill",
                                iconColor: Color(red: 0.02, green: 0.37, blue: 0.27),
                                title: "Subtitles",
                                subtitle: SubtitleAppearanceStore.shared.preset.displayName
                            )
                        }
                        settingsDivider()
                        NavigationLink { StreamAutoplaySettingsScreen() } label: {
                            settingsRowLabel(
                                icon: "bolt.fill",
                                iconColor: Color(red: 0.49, green: 0.18, blue: 0.07),
                                title: "Stream Auto-Play",
                                value: streamAutoplaySummary
                            )
                        }
                    }
                    .glassCard(cornerRadius: 14)
                    .padding(.horizontal, 16)

                    // ── APP ───────────────────────────────────────────
                    settingsSectionLabel("App")
                    VStack(spacing: 0) {
                        settingsRowLabel(icon: "info.circle.fill", iconColor: Color(white: 0.25), title: "Luna v1.0.0")
                    }
                    .glassCard(cornerRadius: 14)
                    .padding(.horizontal, 16)

                    // ── SIGN OUT ──────────────────────────────────────
                    Button(role: .destructive) {
                        Task { await profileManager.signOut() }
                    } label: {
                        Text("Sign Out")
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity)
                            .padding(16)
                    }
                    .glassCard(cornerRadius: 14)
                    .padding(.horizontal, 16)

                    Spacer().frame(height: 40)
                }
                .padding(.top, 16)
            }
            .background(LunaTheme.background)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showAddons) { AddonsScreen() }
            .sheet(isPresented: $showCatalogManagement) { CatalogManagementScreen() }
            .sheet(isPresented: $showSubtitleAppearance) { SubtitleAppearanceScreen() }
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

    private func settingsRowLabel(icon: String, iconColor: Color, title: String, subtitle: String? = nil, value: String? = nil) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(iconColor)
                    .frame(width: 28, height: 28)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.white)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(LunaTheme.textTertiary)
                }
            }
            Spacer()
            if let value {
                Text(value)
                    .font(.caption)
                    .foregroundColor(LunaTheme.textSecondary)
            }
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(LunaTheme.textTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    private func settingsDivider() -> some View {
        Divider().background(Color.white.opacity(0.08)).padding(.leading, 56)
    }
}

@MainActor
private func settingsSectionLabel(_ text: String) -> some View {
    Text(text.uppercased())
        .font(.caption.weight(.semibold))
        .foregroundColor(LunaTheme.textTertiary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 2)
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
                    .foregroundColor(LunaTheme.textTertiary)
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
                .glassCard(cornerRadius: 14)
                .padding(.horizontal, 16)

                Text("Manual opens the source picker. Automatic launches a ranked source from the allowed addons after the selected wait time.")
                    .font(.caption)
                    .foregroundColor(LunaTheme.textTertiary)
                    .padding(.horizontal, 20)
            }
            .padding(.top, 16)
        }
        .background(LunaTheme.background)
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
                .foregroundColor(LunaTheme.textSecondary)
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
                        .foregroundColor(LunaTheme.textSecondary)
                }
                Spacer()
                Text(timeoutLabel(timeoutSeconds))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(LunaTheme.accent)
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
                .foregroundColor(LunaTheme.textSecondary)
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
                        .foregroundColor(LunaTheme.textSecondary)
                }
                Spacer()
                if !selectedAddonUrls.isEmpty {
                    Button("All") {
                        selectedAddonUrls = []
                        persistSelectedAddonUrls()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(LunaTheme.accent)
                }
            }

            if streamAddons.isEmpty {
                Text(addonRepo.isLoading ? "Loading addons..." : "No stream addons installed")
                    .font(.caption)
                    .foregroundColor(LunaTheme.textTertiary)
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
                                    .foregroundColor(LunaTheme.textTertiary)
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
            return "All enabled stream addons"
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
                .glassCard(cornerRadius: 14)
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
                .glassProminentButtonStyle(cornerRadius: 12)
                .padding(.horizontal, 16)

                Text("Episode images resolve from TVDB first, then TMDB, then any usable addon image.")
                    .font(.caption)
                    .foregroundColor(LunaTheme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 32)
            }
            .padding(.top, 16)
        }
        .background(LunaTheme.background)
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

            SecureField("", text: value, prompt: Text("Paste API key").foregroundColor(LunaTheme.textTertiary))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundColor(.white)
                .font(.callout.monospaced())
                .padding(12)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )

            Text(subtitle)
                .font(.caption)
                .foregroundColor(LunaTheme.textTertiary)
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
            LunaTheme.textSecondary
        case .missing:
            LunaTheme.textTertiary
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
                LunaTheme.background.ignoresSafeArea()

                if collectionRepo.isLoading && collectionRepo.collections.isEmpty {
                    VStack(spacing: 16) {
                        ProgressView().tint(LunaTheme.accent)
                        Text("Loading catalogs...")
                            .font(.subheadline)
                            .foregroundColor(LunaTheme.textSecondary)
                    }
                } else if collectionRepo.collections.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "rectangle.stack.badge.questionmark")
                            .font(.system(size: 42))
                            .foregroundColor(LunaTheme.textTertiary)
                        Text("No folder catalogs found")
                            .font(.headline)
                            .foregroundColor(.white)
                        Text("Collections from your configured folders will appear here.")
                            .font(.subheadline)
                            .foregroundColor(LunaTheme.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                } else {
                    List {
                        Section {
                            Text("Choose which folder catalogs appear on Home. Turning folders into rows changes a collection like Decades into separate 1980s, 1990s, and other rows.")
                                .font(.caption)
                                .foregroundColor(LunaTheme.textSecondary)
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
                                        .foregroundColor(LunaTheme.textTertiary)
                                } else {
                                    ForEach(folders.filter { !preferenceStore.isFolderHidden($0) }) { folder in
                                        HStack(spacing: 12) {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(folder.name)
                                                    .foregroundColor(.white)
                                                Text("Folder")
                                                    .font(.caption2)
                                                    .foregroundColor(LunaTheme.textTertiary)
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
                                                .foregroundColor(LunaTheme.textTertiary)
                                            Spacer()
                                            Button("Restore") {
                                                preferenceStore.setFolder(folder, hidden: false)
                                            }
                                            .font(.caption.weight(.semibold))
                                            .foregroundColor(LunaTheme.accent)
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
                    await collectionRepo.load()
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
    @State private var newAddonURL = ""
    @State private var showAddSheet = false

    private var grouped: [(AddonCategory, [ManagedAddon])] {
        var dict: [AddonCategory: [ManagedAddon]] = [:]
        for addon in addonRepo.managedAddons {
            let cat = AddonCategory.primary(for: addon)
            dict[cat, default: []].append(addon)
        }
        return AddonCategory.allCases.compactMap { cat in
            guard let addons = dict[cat], !addons.isEmpty else { return nil }
            return (cat, addons)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LunaTheme.background.ignoresSafeArea()

                if addonRepo.isLoading {
                    VStack(spacing: 16) {
                        ProgressView().tint(LunaTheme.accent)
                        Text("Loading addons...")
                            .font(.subheadline)
                            .foregroundColor(LunaTheme.textSecondary)
                    }
                } else if let error = addonRepo.errorMessage, addonRepo.managedAddons.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 44))
                            .foregroundColor(.orange)
                        Text("Failed to load addons")
                            .font(.headline)
                            .foregroundColor(.white)
                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(LunaTheme.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        Button {
                            Task {
                                guard let profile = ProfileManager.shared.currentProfile else { return }
                                await addonRepo.loadAddons(profileId: profile.id)
                            }
                        } label: {
                            Label("Retry", systemImage: "arrow.clockwise")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 24)
                                .padding(.vertical, 10)
                        }
                        .glassCard(cornerRadius: 12, interactive: true)
                        .foregroundColor(.white)
                    }
                } else {
                    List {
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
                                        .foregroundColor(LunaTheme.textSecondary)
                                }
                                .font(.subheadline.weight(.semibold))
                                .textCase(nil)
                            }
                        }

                        if let error = addonRepo.errorMessage, !addonRepo.managedAddons.isEmpty {
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
                        guard let profile = ProfileManager.shared.currentProfile else { return }
                        await addonRepo.loadAddons(profileId: profile.id)
                    }
                }
            }
            .navigationTitle("Addons")
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
                        Text("Enter a Stremio addon URL")
                            .font(.headline)
                            .foregroundColor(.white)

                        TextField("https://.../manifest.json", text: $newAddonURL)
                            .padding()
                            .background(LunaTheme.surface)
                            .cornerRadius(12)
                            .foregroundColor(.white)
                            .padding(.horizontal)
                            .autocapitalization(.none)
                            .keyboardType(.URL)

                        Button {
                            Task {
                                await addonRepo.installAddon(url: newAddonURL)
                                newAddonURL = ""
                                showAddSheet = false
                            }
                        } label: {
                            Text("Install")
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                        .glassProminentButtonStyle(cornerRadius: 12)
                        .disabled(newAddonURL.isEmpty)
                        .padding(.horizontal)

                        Spacer()
                    }
                    .padding(.top)
                    .background(LunaTheme.background)
                    .navigationTitle("Add Addon")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showAddSheet = false }
                        }
                    }
                }
            }
            .task {
                guard let profile = ProfileManager.shared.currentProfile else { return }
                if addonRepo.managedAddons.isEmpty {
                    await addonRepo.loadAddons(profileId: profile.id)
                }
            }
        }
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
                        .foregroundColor(addon.enabled ? .white : LunaTheme.textSecondary)
                        .font(.body)
                    if addonRepo.isManaged(addon) {
                        Text("DEFAULT")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(category.color)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(category.color.opacity(0.15))
                            .cornerRadius(4)
                    }
                }

                // Capability badges
                let badges = category.badges(for: addon)
                if !badges.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(badges, id: \.self) { badge in
                            Text(badge)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(LunaTheme.textTertiary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.07))
                                .cornerRadius(4)
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
