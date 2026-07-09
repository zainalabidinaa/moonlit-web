import SwiftUI
import MoonlitCore

struct MacSettingsView: View {
    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var roleManager: RoleManager
    @StateObject private var addonRepo = AddonRepository.shared
    @StateObject private var metadataIntegrations = MetadataIntegrationStore.shared
    @StateObject private var traktAuth = TraktAuthService.shared
    @State private var systemAddonName: String?
    @State private var systemAddonUrl: String?
    @State private var presentedSheet: SettingsSheet?
    @State private var selectedCategory: MacSettingsCategory = .general

    private struct SidebarGroup: Identifiable {
        let id = UUID()
        let heading: String?
        let categories: [MacSettingsCategory]
    }

    private var sidebarGroups: [SidebarGroup] {
        var groups: [SidebarGroup] = [
            SidebarGroup(heading: "Account", categories: [.general, .account]),
            SidebarGroup(heading: "Playback", categories: [.playback]),
            SidebarGroup(heading: "Appearance", categories: [.appearance, .addons]),
        ]
        if roleManager.isAdmin {
            groups.append(SidebarGroup(heading: "Admin", categories: [.admin]))
        }
        return groups
    }

    var body: some View {
        ZStack(alignment: .top) {
            MacFusionAmbientBackground(
                ambientColor: .clear,
                ambientColor2: .clear,
                isEnabled: true
            )

            HStack(spacing: 0) {
                sidebar

                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 1)

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        detailContent
                        Spacer(minLength: 32)
                    }
                    .frame(maxWidth: 640, alignment: .leading)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 28)
                    .padding(.top, MoonlitTheme.navBarTopInset + 6)
                    .padding(.bottom, 28)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(MoonlitTheme.background)
        .sheet(item: $presentedSheet) { sheet in
            NavigationStack {
                sheetView(sheet)
            }
            .frame(minWidth: 680, minHeight: 560)
            .preferredColorScheme(.dark)
        }
        .task { await loadSettingsSupportData() }
    }

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                sidebarProfileHeader
                    .padding(.horizontal, 8)

                ForEach(sidebarGroups) { group in
                    VStack(alignment: .leading, spacing: 2) {
                        if let heading = group.heading {
                            Text(heading.uppercased())
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white.opacity(0.35))
                                .tracking(1)
                                .padding(.horizontal, 8)
                                .padding(.bottom, 4)
                        }
                        ForEach(group.categories) { category in
                            sidebarRow(category)
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, MoonlitTheme.navBarTopInset + 6)
            .padding(.bottom, 20)
        }
        .frame(width: 230)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(MoonlitTheme.surface.opacity(0.35))
    }

    @ViewBuilder
    private var sidebarProfileHeader: some View {
        if let profile = profileManager.currentProfile {
            Button {
                selectedCategory = .account
            } label: {
                HStack(spacing: 10) {
                    Circle()
                        .fill(profile.avatarColor.map { Color(hex: $0) } ?? MoonlitTheme.accent)
                        .frame(width: 34, height: 34)
                        .overlay(
                            Text(String(profile.name.prefix(1).uppercased()))
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                        )
                    VStack(alignment: .leading, spacing: 1) {
                        Text(profile.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(roleManager.isAdmin ? "Admin" : "Profile")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(MoonlitTheme.harborGold)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func sidebarRow(_ category: MacSettingsCategory) -> some View {
        let isSelected = selectedCategory == category
        return Button {
            selectedCategory = category
        } label: {
            HStack(spacing: 11) {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.12) : Color.white.opacity(0.05))
                    .frame(width: 34, height: 34)
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Color.white.opacity(isSelected ? 0.1 : 0), lineWidth: 1)
                    )
                    .overlay(
                        Image(systemName: category.icon)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(isSelected ? MoonlitTheme.harborGold : .white.opacity(0.55))
                    )

                Text(category.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.7))

                Spacer()
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.06) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.white.opacity(isSelected ? 0.08 : 0), lineWidth: 1)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selectedCategory {
        case .general:
            generalDetail
        case .playback:
            playbackDetail
        case .appearance:
            appearanceDetail
        case .addons:
            addonsDetail
        case .admin:
            adminDetail
        case .account:
            accountDetail
        }
    }

    @ViewBuilder
    private var generalDetail: some View {
        detailHeader(MacSettingsCategory.general)

        settingsSection("Metadata") {
            settingsRow(
                icon: "key.horizontal.fill",
                title: "Metadata Integrations",
                subtitle: metadataStatus,
                action: { presentedSheet = .metadataIntegrations }
            )
        }

        if profileManager.isAuthenticated {
            settingsSection("Trakt") {
                if traktAuth.isConnected {
                    settingsRow(
                        icon: "t.circle.fill",
                        title: "Trakt Connected",
                        subtitle: "Watchlist syncing enabled",
                        action: {}
                    )
                    MacSettingsDivider()
                    Button {
                        Task {
                            guard let profile = profileManager.currentProfile else { return }
                            await traktAuth.disconnect(profileId: profile.id)
                        }
                    } label: {
                        Label("Disconnect Trakt", systemImage: "xmark.circle")
                            .font(.subheadline)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    settingsRow(
                        icon: "t.circle",
                        title: "Trakt",
                        subtitle: "Connect to sync watchlist and collections",
                        action: { presentedSheet = .trakt }
                    )
                }
            }
        }

        if let systemAddonUrl {
            settingsSection("System Addon") {
                HStack(spacing: 14) {
                    Image(systemName: "star.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(MoonlitTheme.accent)
                        .frame(width: 34)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(systemAddonName ?? "System Addon")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Text(systemAddonUrl)
                            .font(.caption)
                            .foregroundStyle(MoonlitTheme.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
            }
        }
    }

    @ViewBuilder
    private var playbackDetail: some View {
        detailHeader(MacSettingsCategory.playback)

        settingsSection("Playback") {
            settingsRow(
                icon: "play.rectangle.fill",
                title: "Video Player",
                subtitle: "Format compatibility, skip intro, player engine",
                action: { presentedSheet = .videoPlayer }
            )
            MacSettingsDivider()
            settingsRow(
                icon: "captions.bubble.fill",
                title: "Subtitles",
                subtitle: "Style and readability",
                action: { presentedSheet = .subtitleAppearance }
            )
            MacSettingsDivider()
            settingsRow(
                icon: "bolt.fill",
                title: "Stream Auto-Play",
                subtitle: autoplaySummary,
                action: { presentedSheet = .streamAutoplay }
            )
        }
    }

    @ViewBuilder
    private var appearanceDetail: some View {
        detailHeader(MacSettingsCategory.appearance)

        settingsSection("Appearance") {
            settingsRow(
                icon: "rectangle.3.group.bubble.left.fill",
                title: "Collection Design",
                subtitle: "Home row visibility and display styles",
                action: { presentedSheet = .collectionDesign }
            )
            MacSettingsDivider()
            cinematicModeRow
        }
    }

    @ViewBuilder
    private var addonsDetail: some View {
        detailHeader(MacSettingsCategory.addons)

        settingsSection("Addons") {
            settingsRow(
                icon: "puzzlepiece.extension.fill",
                title: "Addons",
                subtitle: "\(addonRepo.userAddons.count) installed",
                action: { presentedSheet = .addons }
            )
        }
    }

    @ViewBuilder
    private var adminDetail: some View {
        detailHeader(MacSettingsCategory.admin)

        settingsSection("Admin") {
            settingsRow(
                icon: "chart.bar.fill",
                title: "Admin Dashboard",
                subtitle: "Invite codes and user management",
                action: { presentedSheet = .adminDashboard }
            )
            MacSettingsDivider()
            settingsRow(
                icon: "rectangle.stack.fill",
                title: "Catalog Management",
                subtitle: "Home catalogs, folder rows, hidden folders",
                action: { presentedSheet = .catalogManagement }
            )
            MacSettingsDivider()
            settingsRow(
                icon: "sparkles.tv.fill",
                title: "Hero Management",
                subtitle: "Choose hero carousel sources and order",
                action: { presentedSheet = .heroManagement }
            )
        }
    }

    @ViewBuilder
    private var accountDetail: some View {
        detailHeader(MacSettingsCategory.account)

        profileCard

        settingsSection("About") {
            HStack {
                Text("Version")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer()
                Text(appVersion)
                    .font(.subheadline)
                    .foregroundStyle(MoonlitTheme.textSecondary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 15)
        }

        Button {
            Task { await profileManager.signOut() }
        } label: {
            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, minHeight: 46)
                .contentShape(Rectangle())
                .macDarkGlassCard(cornerRadius: MoonlitTheme.radiusCard, interactive: true)
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
    }

    private func detailHeader(_ category: MacSettingsCategory) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(category.title)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white)
            Text(category.subtitle)
                .font(.system(size: 13))
                .foregroundStyle(MoonlitTheme.textSecondary)
        }
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private var profileCard: some View {
        if let profile = profileManager.currentProfile {
            HStack(spacing: 16) {
                Circle()
                    .fill(profile.avatarColor.map { Color(hex: $0) } ?? MoonlitTheme.accent)
                    .frame(width: 62, height: 62)
                    .overlay(
                        Text(String(profile.name.prefix(1).uppercased()))
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)
                    )

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(profile.name)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)
                        if roleManager.isAdmin {
                            Text("Admin")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(MoonlitTheme.harborGold)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(MoonlitTheme.harborGold.opacity(0.18), in: Capsule())
                        }
                    }
                    if let email = profileManager.currentSession?.email {
                        Text(email)
                            .font(.subheadline)
                            .foregroundStyle(MoonlitTheme.textSecondary)
                    }
                }

                Spacer()

                Button {
                    profileManager.currentProfile = nil
                } label: {
                    Text("Switch")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .frame(height: 42)
                        .macDarkGlassCapsule(interactive: true)
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .macDarkGlassCard(cornerRadius: 20)
        }
    }

    private var cinematicModeRow: some View {
        Toggle(isOn: Binding(
            get: { UserDefaults.standard.object(forKey: "moonlit.cinematicModeEnabled") as? Bool ?? true },
            set: { UserDefaults.standard.set($0, forKey: "moonlit.cinematicModeEnabled") }
        )) {
            HStack(spacing: 14) {
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(MoonlitTheme.accent)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Cinematic Mode")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("Use ambient hero artwork behind Home")
                        .font(.caption)
                        .foregroundStyle(MoonlitTheme.textTertiary)
                }
            }
        }
        .toggleStyle(.switch)
        .tint(.blue)
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
    }

    private var metadataStatus: String {
        let connected = [
            metadataIntegrations.effectiveTVDBAPIKey != nil ? "TVDB" : nil,
            metadataIntegrations.effectiveTMDBAPIKey != nil ? "TMDB" : nil
        ].compactMap { $0 }
        return connected.isEmpty ? "No API keys configured" : connected.joined(separator: " and ")
    }

    private var autoplaySummary: String {
        guard let profile = profileManager.currentProfile else { return "Manual" }
        switch StreamAutoplayPreferenceStore.shared.mode(profileId: profile.id) {
        case .manual:
            return "Manual stream picker"
        case .automatic:
            return "Automatically choose a stream"
        }
    }

    private var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        return build.map { "Moonlit for macOS · v\(short) (\($0))" } ?? "Moonlit for macOS · v\(short)"
    }

    @ViewBuilder
    private func sheetView(_ sheet: SettingsSheet) -> some View {
        switch sheet {
        case .metadataIntegrations:
            MacMetadataIntegrationsView()
        case .addons:
            MacAddonsView().environmentObject(profileManager)
        case .catalogManagement:
            MacCatalogManagementView()
        case .heroManagement:
            MacHeroManagementView()
        case .videoPlayer:
            MacVideoPlayerSettingsView()
        case .subtitleAppearance:
            MacSubtitleAppearanceView()
        case .streamAutoplay:
            MacStreamAutoplaySettingsView().environmentObject(profileManager)
        case .collectionDesign:
            MacCollectionDesignView()
        case .trakt:
            MacTraktSettingsView()
        case .adminDashboard:
            MacAdminDashboardView()
        }
    }

    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(MoonlitTheme.textTertiary)
                .tracking(1)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                content()
            }
        .macDarkGlassCard(cornerRadius: MoonlitTheme.radiusLarge)
    }
}

// MARK: - Trakt Settings

private struct MacTraktSettingsView: View {
    @StateObject private var traktAuth = TraktAuthService.shared
    @StateObject private var metadataStore = MetadataIntegrationStore.shared
    @EnvironmentObject var profileManager: ProfileManager
    @State private var clientId = ""
    @State private var clientSecret = ""
    @State private var isConnecting = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if traktAuth.isConnected {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.title2)
                        Text("Connected to Trakt")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    .padding(.top, 12)

                    Button {
                        Task {
                            guard let profile = profileManager.currentProfile else { return }
                            await traktAuth.disconnect(profileId: profile.id)
                        }
                    } label: {
                        Text("Disconnect")
                            .foregroundStyle(.red)
                    }
                } else {
                    Text("Connect your Trakt account to sync watchlists and collections with Moonlit.")
                        .font(.subheadline)
                        .foregroundColor(MoonlitTheme.textSecondary)

                    TextField("Client ID", text: $clientId)
                        .textFieldStyle(.plain)
                        .padding(10)
                        .background(MoonlitTheme.surface)
                        .cornerRadius(MoonlitTheme.radiusControl)
                        .foregroundColor(.white)

                    TextField("Client Secret", text: $clientSecret)
                        .textFieldStyle(.plain)
                        .padding(10)
                        .background(MoonlitTheme.surface)
                        .cornerRadius(MoonlitTheme.radiusControl)
                        .foregroundColor(.white)

                    Button {
                        metadataStore.traktClientId = clientId
                        metadataStore.traktClientSecret = clientSecret
                        Task {
                            guard let profile = profileManager.currentProfile else { return }
                            await traktAuth.connect(profileId: profile.id)
                        }
                    } label: {
                        Text("Connect Trakt")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                (!clientId.isEmpty && !clientSecret.isEmpty)
                                    ? MoonlitTheme.accent : MoonlitTheme.surface
                            )
                            .foregroundColor(.white)
                            .cornerRadius(MoonlitTheme.radiusCard)
                    }
                    .buttonStyle(.plain)
                    .disabled(clientId.isEmpty || clientSecret.isEmpty)
                }
            }
            .padding(24)
            .frame(maxWidth: 520)
        }
        .background(MoonlitTheme.background)
        .task {
            if let profile = profileManager.currentProfile {
                await traktAuth.loadToken(profileId: profile.id)
            }
                        clientId = metadataStore.traktClientId
                        clientSecret = metadataStore.traktClientSecret
        }
    }
}

// MARK: - Admin Dashboard

private struct MacAdminDashboardView: View {
    @StateObject private var adminService = AdminService.shared
    @State private var inviteMaxUses = 1

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Invite Codes")
                    .font(.headline)
                    .foregroundColor(.white)

                HStack(spacing: 12) {
                    Stepper("Max Uses: \(inviteMaxUses)", value: $inviteMaxUses, in: 1...100)
                        .foregroundColor(.white)
                    Button("Generate") {
                        Task {
                            _ = try? await adminService.generateInviteCode(maxUses: inviteMaxUses)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(MoonlitTheme.accent)
                }

                ForEach(adminService.inviteCodes) { code in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(code.code)
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.white)
                            HStack(spacing: 8) {
                                Text("Max \(code.maxUses) use(s)")
                                    .font(.caption)
                                    .foregroundColor(MoonlitTheme.textSecondary)
                                if !code.isActive {
                                    Text("Revoked")
                                        .font(.caption)
                                        .foregroundColor(.red)
                                }
                                if code.usedBy != nil {
                                    Text("Used")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                }
                            }
                        }
                        Spacer()
                        if code.isActive {
                            Button("Revoke") {
                                Task { try? await adminService.revokeInviteCode(code.code) }
                            }
                            .foregroundStyle(.red)
                        }
                    }
                    .padding(14)
                    .background(MoonlitTheme.surface, in: RoundedRectangle(cornerRadius: MoonlitTheme.radiusCard))
                }
            }
            .padding(24)
            .frame(maxWidth: 600)
        }
        .background(MoonlitTheme.background)
        .task {
            await adminService.loadInviteCodes()
        }
    }
}

    private func settingsRow(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(MoonlitTheme.accent)
                    .frame(width: 34)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(MoonlitTheme.textTertiary)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(MoonlitTheme.textTertiary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 15)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func loadSettingsSupportData() async {
        let info = try? await SyncService.shared.pullSystemAddonInfo()
        systemAddonUrl = info?.url
        systemAddonName = info?.name
        if addonRepo.managedAddons.isEmpty, let profile = profileManager.currentProfile {
            await addonRepo.loadAddons(profileId: profile.id, systemAddonUrl: info?.url)
        }
    }
}

private enum MacSettingsCategory: String, Identifiable, CaseIterable {
    case general
    case playback
    case appearance
    case addons
    case admin
    case account

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .playback: "Playback"
        case .appearance: "Appearance"
        case .addons: "Addons"
        case .admin: "Admin"
        case .account: "Account"
        }
    }

    var icon: String {
        switch self {
        case .general: "key.horizontal.fill"
        case .playback: "play.rectangle.fill"
        case .appearance: "paintpalette.fill"
        case .addons: "puzzlepiece.extension.fill"
        case .admin: "shield.fill"
        case .account: "person.crop.circle.fill"
        }
    }

    var subtitle: String {
        switch self {
        case .general: "Metadata sources, Trakt sync, and system addon status."
        case .playback: "Video engine, subtitle style, and stream auto-play behavior."
        case .appearance: "Home row layout and collection display styles."
        case .addons: "Install and manage the addons your library pulls from."
        case .admin: "Invite codes, catalogs, and hero carousel management."
        case .account: "Your profile, app version, and sign-out."
        }
    }
}

private enum SettingsSheet: String, Identifiable {
    case metadataIntegrations
    case addons
    case catalogManagement
    case heroManagement
    case videoPlayer
    case subtitleAppearance
    case streamAutoplay
    case collectionDesign
    case trakt
    case adminDashboard

    var id: String { rawValue }
}

private struct MacSettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(height: 1)
            .padding(.leading, 66)
    }
}

private struct MacSettingsSheetScaffold<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                content
            }
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(24)
        }
        .background(MoonlitTheme.background)
        .navigationTitle(title)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
            }
        }
    }
}

private struct MacMetadataIntegrationsView: View {
    @StateObject private var store = MetadataIntegrationStore.shared

    var body: some View {
        MacSettingsSheetScaffold(title: "Metadata Integrations") {
            MacInfoCard(
                title: "Episode images resolve from TVDB first, then TMDB, then addon artwork.",
                icon: "info.circle.fill"
            )

            MacFormCard {
                metadataField(
                    title: "TVDB API Key",
                    subtitle: "Used first for episode thumbnails.",
                    text: Binding(get: { store.tvdbAPIKey }, set: { store.setTVDBAPIKey($0) })
                )
                MacSettingsDivider()
                metadataField(
                    title: "TMDB API Key",
                    subtitle: "Used for hero artwork, missing metadata, and fallback episode stills.",
                    text: Binding(get: { store.tmdbAPIKey }, set: { store.setTMDBAPIKey($0) })
                )
            }
        }
    }

    private func metadataField(title: String, subtitle: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            SecureField("Paste API key", text: text)
                .textFieldStyle(.plain)
                .font(.callout.monospaced())
                .foregroundStyle(.white)
                .padding(12)
                .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: MoonlitTheme.radiusControl, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: MoonlitTheme.radiusControl).stroke(Color.white.opacity(0.09)))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(MoonlitTheme.textTertiary)
        }
        .padding(16)
    }
}

private struct MacStreamAutoplaySettingsView: View {
    @EnvironmentObject var profileManager: ProfileManager
    @StateObject private var addonRepo = AddonRepository.shared
    @State private var mode: StreamAutoplayMode = .manual
    @State private var selectedAddonUrls: [String] = []
    @State private var timeoutSeconds: Int?

    private let timeoutOptions: [Int?] = [nil, 0, 5, 10, 15, 20, 30]

    var body: some View {
        MacSettingsSheetScaffold(title: "Stream Auto-Play") {
            MacFormCard {
                Picker("Mode", selection: Binding(
                    get: { mode },
                    set: {
                        mode = $0
                        persistMode()
                    }
                )) {
                    Text("Manual").tag(StreamAutoplayMode.manual)
                    Text("Automatic").tag(StreamAutoplayMode.automatic)
                }
                .pickerStyle(.segmented)
                .tint(.blue)
                .padding(16)

                MacSettingsDivider()

                Picker("Timeout", selection: Binding(
                    get: { timeoutTag(timeoutSeconds) },
                    set: {
                        timeoutSeconds = timeoutValue($0)
                        persistTimeout()
                    }
                )) {
                    ForEach(timeoutOptions.indices, id: \.self) { index in
                        Text(timeoutLabel(timeoutOptions[index])).tag(index)
                    }
                }
                .disabled(mode != .automatic)
                .tint(.blue)
                .padding(16)
            }

            MacInfoCard(title: "Leave addons unselected to allow all enabled stream addons.", icon: "bolt.fill")
                .opacity(mode == .automatic ? 1 : 0.55)

            MacFormCard {
                if streamAddons.isEmpty {
                    Text("No enabled stream addons available.")
                        .font(.subheadline)
                        .foregroundStyle(MoonlitTheme.textSecondary)
                        .padding(16)
                } else {
                    ForEach(streamAddons) { addon in
                        Toggle(isOn: Binding(
                            get: { isAddonAllowed(addon) },
                            set: { setAddon(addon, allowed: $0) }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(addon.manifest.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                                Text(addon.manifestUrl)
                                    .font(.caption)
                                    .foregroundStyle(MoonlitTheme.textTertiary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                        .toggleStyle(.switch)
                        .tint(.blue)
                        .padding(16)

                        if addon.id != streamAddons.last?.id {
                            MacSettingsDivider()
                        }
                    }
                }
            }
            .disabled(mode != .automatic)
            .opacity(mode == .automatic ? 1 : 0.55)
        }
        .task {
            loadPreferences()
            if addonRepo.managedAddons.isEmpty, let profile = profileManager.currentProfile {
                await addonRepo.loadAddons(profileId: profile.id)
            }
        }
    }

    private var streamAddons: [ManagedAddon] {
        addonRepo.managedAddons.filter { $0.enabled && $0.manifest.hasResource("stream") }
    }

    private func loadPreferences() {
        guard let profile = profileManager.currentProfile else { return }
        mode = StreamAutoplayPreferenceStore.shared.mode(profileId: profile.id)
        selectedAddonUrls = StreamAutoplayPreferenceStore.shared.automaticAddonUrls(profileId: profile.id)
        timeoutSeconds = StreamAutoplayPreferenceStore.shared.timeoutSeconds(profileId: profile.id)
    }

    private func persistMode() {
        guard let profile = profileManager.currentProfile else { return }
        StreamAutoplayPreferenceStore.shared.setMode(mode, profileId: profile.id)
    }

    private func persistTimeout() {
        guard let profile = profileManager.currentProfile else { return }
        StreamAutoplayPreferenceStore.shared.setTimeoutSeconds(timeoutSeconds, profileId: profile.id)
    }

    private func persistAddons() {
        guard let profile = profileManager.currentProfile else { return }
        StreamAutoplayPreferenceStore.shared.setAutomaticAddonUrls(selectedAddonUrls, profileId: profile.id)
    }

    private func isAddonAllowed(_ addon: ManagedAddon) -> Bool {
        selectedAddonUrls.isEmpty || selectedAddonUrls.contains(addon.manifestUrl)
    }

    private func setAddon(_ addon: ManagedAddon, allowed: Bool) {
        if selectedAddonUrls.isEmpty {
            selectedAddonUrls = streamAddons.map(\.manifestUrl)
        }
        if allowed {
            if !selectedAddonUrls.contains(addon.manifestUrl) {
                selectedAddonUrls.append(addon.manifestUrl)
            }
        } else {
            selectedAddonUrls.removeAll { $0 == addon.manifestUrl }
        }
        if selectedAddonUrls.count == streamAddons.count {
            selectedAddonUrls = []
        }
        persistAddons()
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

private struct MacCatalogManagementView: View {
    @StateObject private var collectionRepo = CollectionRepository.shared
    @StateObject private var preferenceStore = CollectionDisplayPreferenceStore.shared

    var body: some View {
        MacSettingsSheetScaffold(title: "Catalog Management") {
            MacInfoCard(
                title: "Choose which folder catalogs appear on Home. Expanding a collection turns folders into rows.",
                icon: "rectangle.stack.fill"
            )

            if collectionRepo.isLoading && collectionRepo.collections.isEmpty {
                MacLoadingBlock(text: "Loading catalogs...")
            } else if collectionRepo.collections.isEmpty {
                MacEmptyBlock(icon: "rectangle.stack.badge.questionmark", title: "No folder catalogs found")
            } else {
                ForEach(collectionRepo.collections) { collection in
                    MacFormCard {
                        VStack(spacing: 0) {
                            Text(collection.name)
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.bottom, 14)
                            MacSettingsToggleRow(title: "Show catalog", subtitle: "Display this collection on Home", isOn: Binding(
                                get: { preferenceStore.isCollectionEnabled(collection) },
                                set: { preferenceStore.setCollection(collection, enabled: $0) }
                            ))
                            MacSettingsDivider()
                            MacSettingsToggleRow(title: "Turn folders into rows", subtitle: "Show each folder as its own Home row", isOn: Binding(
                                get: { preferenceStore.isCollectionExpanded(collection) },
                                set: { preferenceStore.setCollection(collection, expanded: $0) }
                            ))
                        }
                        .padding(16)

                        let folders = collectionRepo.folders(for: collection)
                        if !folders.isEmpty {
                            MacSettingsDivider()
                            ForEach(folders) { folder in
                                MacSettingsToggleRow(title: folder.name, subtitle: folder.tileShape == "landscape" ? "Landscape folder" : "Folder", isOn: Binding(
                                    get: { !preferenceStore.isFolderHidden(folder) },
                                    set: { preferenceStore.setFolder(folder, hidden: !$0) }
                                ))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)

                                if folder.id != folders.last?.id {
                                    MacSettingsDivider()
                                }
                            }
                        }
                    }
                }
            }
        }
        .task {
            if collectionRepo.collections.isEmpty {
                await collectionRepo.refreshForCatalogRows()
            }
        }
    }
}

private struct MacCollectionDesignView: View {
    @StateObject private var catalogRepo = CatalogRepository.shared
    @StateObject private var rowStyleStore = CollectionRowDisplayStyleStore.shared

    var body: some View {
        MacSettingsSheetScaffold(title: "Collection Design") {
            MacInfoCard(
                title: "Set the display style for each Home row. Folder rows keep landscape tiles when their metadata calls for it.",
                icon: "rectangle.3.group.bubble.left.fill"
            )

            if catalogRepo.catalogRows.isEmpty {
                MacEmptyBlock(icon: "square.grid.2x2", title: "Load Home once to populate row design choices")
            } else {
                ForEach(catalogRepo.catalogRows) { row in
                    MacFormCard {
                        HStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(row.title)
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                Text("\(row.items.count) items")
                                    .font(.caption)
                                    .foregroundStyle(MoonlitTheme.textTertiary)
                            }
                            Spacer()
                            Picker("", selection: Binding(
                                get: { rowStyleStore.style(forRowTitle: row.title) },
                                set: { rowStyleStore.setStyle($0, forRowTitle: row.title) }
                            )) {
                                ForEach(RowDisplayStyle.allCases) { style in
                                    Text(style.displayName).tag(style)
                                }
                            }
                            .frame(width: 220)
                        }
                        .padding(16)
                    }
                }
            }
        }
    }
}

private struct MacHeroManagementView: View {
    @StateObject private var catalogRepo = CatalogRepository.shared
    @StateObject private var heroStore = HeroPreferenceStore.shared

    private let defaultHeroTitles: Set<String> = [
        "Popular Movies", "Popular TV Shows",
        "Trending Movies", "Trending TV Shows"
    ]

    private var allRows: [CatalogRow] {
        catalogRepo.catalogRows.filter { !$0.items.isEmpty }
    }

    private var orderedRows: [CatalogRow] {
        let titles = heroStore.rowOrder.isEmpty
            ? allRows.filter { defaultHeroTitles.contains($0.title) }.map(\.title)
            : heroStore.rowOrder.filter { heroStore.isEnabled(rowTitle: $0) }
        return titles.compactMap { title in allRows.first { $0.title == title } }
    }

    var body: some View {
        MacSettingsSheetScaffold(title: "Hero Management") {
            MacInfoCard(
                title: "Choose which catalog rows feed the hero carousel and set their priority order.",
                icon: "sparkles.tv.fill"
            )

            if allRows.isEmpty {
                MacEmptyBlock(icon: "sparkles.tv", title: "No loaded Home rows yet")
            } else {
                if !orderedRows.isEmpty {
                    MacFormCard {
                        Text("Hero Priority")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding([.horizontal, .top], 16)
                        ForEach(Array(orderedRows.enumerated()), id: \.element.id) { index, row in
                            HStack {
                                Text(row.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                                Spacer()
                                Button {
                                    move(row, by: -1)
                                } label: {
                                    Image(systemName: "chevron.up")
                                        .frame(width: 34, height: 34)
                                        .macDarkGlassCapsule(interactive: true)
                                }
                                .buttonStyle(.plain)
                                .disabled(index == 0)
                                Button {
                                    move(row, by: 1)
                                } label: {
                                    Image(systemName: "chevron.down")
                                        .frame(width: 34, height: 34)
                                        .macDarkGlassCapsule(interactive: true)
                                }
                                .buttonStyle(.plain)
                                .disabled(index == orderedRows.count - 1)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                        }
                    }
                }

                MacFormCard {
                    Text("Available Catalogs")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding([.horizontal, .top], 16)
                    ForEach(allRows) { row in
                        Toggle(isOn: Binding(
                            get: { isEnabled(row) },
                            set: { setEnabled($0, row: row) }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                                if let addonName = row.addonName {
                                    Text(addonName)
                                        .font(.caption)
                                        .foregroundStyle(MoonlitTheme.textTertiary)
                                }
                            }
                        }
                        .toggleStyle(.switch)
                        .tint(MoonlitTheme.accent)
                        .padding(16)
                    }
                }
            }
        }
    }

    private func isEnabled(_ row: CatalogRow) -> Bool {
        heroStore.rowOrder.isEmpty ? defaultHeroTitles.contains(row.title) : heroStore.isEnabled(rowTitle: row.title)
    }

    private func setEnabled(_ enabled: Bool, row: CatalogRow) {
        initializeHeroOrderIfNeeded()
        heroStore.setEnabled(enabled, for: row.title)
    }

    private func move(_ row: CatalogRow, by offset: Int) {
        initializeHeroOrderIfNeeded()
        var order = orderedRows.map(\.title)
        guard let index = order.firstIndex(of: row.title) else { return }
        let destination = index + offset
        guard order.indices.contains(destination) else { return }
        order.swapAt(index, destination)
        let disabled = heroStore.rowOrder.filter { !heroStore.isEnabled(rowTitle: $0) }
        heroStore.setOrder(order + disabled)
    }

    private func initializeHeroOrderIfNeeded() {
        guard heroStore.rowOrder.isEmpty else { return }
        heroStore.setOrder(allRows.filter { defaultHeroTitles.contains($0.title) }.map(\.title))
    }
}

private struct MacFormCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .macDarkGlassCard(cornerRadius: MoonlitTheme.radiusLarge)
    }
}

private struct MacSettingsToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(MoonlitTheme.textTertiary)
            }
        }
        .toggleStyle(.switch)
        .tint(.blue)
    }
}

private struct MacInfoCard: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(MoonlitTheme.accent)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(MoonlitTheme.textSecondary)
            Spacer()
        }
        .padding(16)
        .macDarkGlassCard(cornerRadius: MoonlitTheme.radiusLarge)
    }
}

private struct MacLoadingBlock: View {
    let text: String

    var body: some View {
        VStack(spacing: 14) {
            MacLottieLoadingView(size: 42)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(MoonlitTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
    }
}

private struct MacEmptyBlock: View {
    let icon: String
    let title: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(MoonlitTheme.textTertiary)
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, minHeight: 190)
        .macDarkGlassCard(cornerRadius: MoonlitTheme.radiusLarge)
    }
}
