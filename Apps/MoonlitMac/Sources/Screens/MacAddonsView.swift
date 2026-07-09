import SwiftUI
import MoonlitCore

struct MacAddonsView: View {
    @EnvironmentObject var profileManager: ProfileManager
    @StateObject private var addonRepo = AddonRepository.shared
    @Environment(\.dismiss) private var dismiss
    @State private var newUrl = ""
    @State private var installError: String?
    @State private var isInstalling = false

    private var groupedAddons: [(MacAddonCategory, [ManagedAddon])] {
        var groups: [MacAddonCategory: [ManagedAddon]] = [:]
        for addon in addonRepo.managedAddons {
            groups[MacAddonCategory.primary(for: addon), default: []].append(addon)
        }
        return MacAddonCategory.allCases.compactMap { category in
            guard let addons = groups[category], !addons.isEmpty else { return nil }
            return (category, addons.sorted { $0.sortOrder < $1.sortOrder })
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            MacFusionAmbientBackground(
                ambientColor: .clear,
                ambientColor2: .clear,
                isEnabled: true
            )
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        installCard

                        if addonRepo.isLoading {
                            MacLoadingView(size: 32)
                                .frame(maxWidth: .infinity, minHeight: 160)
                        } else if groupedAddons.isEmpty {
                            emptyState
                        } else {
                            ForEach(groupedAddons, id: \.0) { category, addons in
                                addonSection(category: category, addons: addons)
                            }
                        }

                        Spacer(minLength: 28)
                    }
                    .frame(maxWidth: 760, alignment: .leading)
                    .frame(maxWidth: .infinity)
                    .padding(24)
                }
                .navigationTitle("Addons")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                            .buttonStyle(.borderedProminent)
                            .tint(.blue)
                    }
                }
            }
            .frame(minWidth: 680, minHeight: 560)
            .preferredColorScheme(.dark)
            .task {
                if addonRepo.managedAddons.isEmpty, let profile = profileManager.currentProfile {
                    let info = try? await SyncService.shared.pullSystemAddonInfo()
                    await addonRepo.loadAddons(profileId: profile.id, systemAddonUrl: info?.url)
                }
            }
        }
        .background(MoonlitTheme.background)
    }

    private var installCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Install Addon")
                .font(.headline)
                .foregroundStyle(.white)

            HStack(spacing: 10) {
                TextField("https://.../manifest.json", text: $newUrl)
                    .textFieldStyle(.plain)
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: MoonlitTheme.radiusControl))

                Button {
                    installAddon()
                } label: {
                    HStack(spacing: 7) {
                        if isInstalling {
                            MacLottieLoadingView(size: 18)
                        }
                        Text(isInstalling ? "Installing" : "Install")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(minWidth: 96, minHeight: 40)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(newUrl.isEmpty || isInstalling)
            }

            if let installError {
                Text(installError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(16)
        .macDarkGlassCard(cornerRadius: MoonlitTheme.radiusLarge)
    }

    private func addonSection(category: MacAddonCategory, addons: [ManagedAddon]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(category.rawValue, systemImage: category.icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(category.color)
                .textCase(.uppercase)

            VStack(spacing: 0) {
                ForEach(addons) { addon in
                    addonRow(addon, category: category)
                    if addon.id != addons.last?.id {
                        Rectangle()
                            .fill(Color.white.opacity(0.08))
                            .frame(height: 1)
                            .padding(.leading, 62)
                    }
                }
            }
            .macDarkGlassCard(cornerRadius: MoonlitTheme.radiusLarge)
        }
    }

    private func addonRow(_ addon: ManagedAddon, category: MacAddonCategory) -> some View {
        HStack(spacing: 14) {
            Image(systemName: category.icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(category.color)
                .frame(width: 36, height: 36)
                .background(category.color.opacity(0.16), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(addon.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    if addonRepo.isManaged(addon) {
                        Text("System")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.16), in: Capsule())
                    }
                }
                Text(addon.manifestUrl)
                    .font(.caption)
                    .foregroundStyle(MoonlitTheme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 6) {
                    ForEach(category.badges(for: addon), id: \.self) { badge in
                        Text(badge)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.78))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(0.10), in: Capsule())
                    }
                }
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { addon.enabled },
                set: { enabled in
                    if enabled != addon.enabled {
                        addonRepo.toggleAddon(url: addon.manifestUrl)
                    }
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .tint(.blue)

            if !addonRepo.isManaged(addon) {
                Button("Remove") {
                    addonRepo.removeAddon(url: addon.manifestUrl)
                }
                .foregroundStyle(.red)
                .buttonStyle(.plain)
            }
        }
        .padding(16)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "puzzlepiece.extension")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(MoonlitTheme.textTertiary)
            Text("No addons loaded")
                .font(.headline)
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, minHeight: 190)
        .macDarkGlassCard(cornerRadius: MoonlitTheme.radiusLarge)
    }

    private func installAddon() {
        installError = nil
        isInstalling = true
        Task {
            let previousCount = addonRepo.managedAddons.count
            await addonRepo.installAddon(url: newUrl)
            isInstalling = false
            if addonRepo.managedAddons.count > previousCount {
                newUrl = ""
            } else if let error = addonRepo.errorMessage {
                installError = error
            } else {
                installError = "Addon is already installed."
            }
        }
    }
}

private enum MacAddonCategory: String, CaseIterable {
    case streaming = "Streaming"
    case metadata = "Metadata"
    case catalogs = "Catalogs"
    case subtitles = "Subtitles"
    case other = "Other"

    var icon: String {
        switch self {
        case .streaming: "play.rectangle.fill"
        case .metadata: "info.circle.fill"
        case .catalogs: "square.grid.2x2.fill"
        case .subtitles: "captions.bubble.fill"
        case .other: "puzzlepiece.extension.fill"
        }
    }

    var color: Color {
        switch self {
        case .streaming: .blue
        case .metadata: .purple
        case .catalogs: .orange
        case .subtitles: .green
        case .other: .gray
        }
    }

    static func primary(for addon: ManagedAddon) -> MacAddonCategory {
        let manifest = addon.manifest
        if manifest.hasResource("stream") { return .streaming }
        if manifest.hasResource("meta") { return .metadata }
        if manifest.hasResource("catalog") || !(manifest.catalogs ?? []).isEmpty { return .catalogs }
        if manifest.hasResource("subtitles") { return .subtitles }
        return .other
    }

    func badges(for addon: ManagedAddon) -> [String] {
        let manifest = addon.manifest
        var badges: [String] = []
        if manifest.hasResource("stream") { badges.append("Stream") }
        if manifest.hasResource("meta") { badges.append("Metadata") }
        if manifest.hasResource("catalog") || !(manifest.catalogs ?? []).isEmpty { badges.append("Catalogs") }
        if manifest.hasResource("subtitles") { badges.append("Subtitles") }
        return badges
    }
}
