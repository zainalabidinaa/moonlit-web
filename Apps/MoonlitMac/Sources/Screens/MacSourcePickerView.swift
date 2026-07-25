import SwiftUI
import MoonlitCore

struct MacSourcePickerView: View {
    let mediaType: MediaType
    let mediaId: String
    let mediaName: String
    let poster: String?
    let logo: String?
    let background: String?
    let videoId: String?
    let seasonNumber: Int?
    let episodeNumber: Int?
    let onLaunch: (PlayerLaunch) -> Void
    /// When true, always show the manual list — ignores autoplay preference.
    /// Set by the in-player picker where the user explicitly asked to pick.
    var forceManual: Bool = false
    /// The player's current source URL, used to highlight the active stream row.
    var currentSourceUrl: String? = nil

    @StateObject private var streamRepo = StreamRepository.shared
    @StateObject private var addonRepo = AddonRepository.shared
    @Environment(\.dismiss) var dismiss
    @State private var selectedAddonFilter: String? = nil
    @State private var cachedOnlyFilter = false
    @State private var isAutoPlaying = false
    @State private var autoLaunchAttempts = 0
    @State private var autoLaunchStatus: String? = nil

    private var autoplayMode: AutoplayMode {
        if forceManual { return .manual }
        guard let profile = ProfileManager.shared.currentProfile else { return .manual }
        return StreamAutoplayPreferenceStore.shared.mode(profileId: profile.id) == .automatic ? .auto : .manual
    }

    private var prefer4K: Bool {
        guard let profile = ProfileManager.shared.currentProfile else { return false }
        return PlaybackQualityPreferenceStore.shared.prefers4K(profileId: profile.id)
    }

    private var installOrder: [String] {
        addonRepo.managedAddons.map(\.manifest.name)
    }

    private var preferredAudioLanguage: String? {
        VideoPlayerPreferenceStore.shared.preferredAudioLanguage
    }

    var body: some View {
        ZStack(alignment: .top) {
            MacFusionAmbientBackground(
                ambientColor: .clear,
                ambientColor2: .clear,
                isEnabled: true
            )
            Group {
                if streamRepo.isLoading {
                    loadingView
                } else if !forceManual && autoplayMode == .auto && (isAutoPlaying || !streamRepo.streams.isEmpty) {
                    autoPlayView
                } else if streamRepo.streams.isEmpty {
                    emptyView
                } else {
                    manualPickerView
                }
            }
            .frame(minWidth: 500, minHeight: 400)
            .task {
                await streamRepo.fetchStreams(
                    type: mediaType.rawValue,
                    id: videoId ?? mediaId,
                    addons: addonRepo.enabledAddons
                )
            }
            .onChange(of: streamRepo.streams) { _, streams in
                if !forceManual, autoplayMode == .auto, !streams.isEmpty, !isAutoPlaying {
                    startAutoPlay(streams: streams)
                }
            }
            .onChange(of: streamRepo.isLoading) { _, isLoading in
                guard !isLoading, !forceManual, autoplayMode == .auto,
                      !streamRepo.streams.isEmpty, !isAutoPlaying else { return }
                startAutoPlay(streams: streamRepo.streams)
            }
        }
        .background(MoonlitTheme.background)
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            MacStrokeSpinner(size: 28)
            Text("Finding streams...")
                .font(.headline)
                .foregroundColor(.white)
            Button("Cancel") { dismiss() }
                .buttonStyle(.borderedProminent)
                .tint(.white.opacity(0.2))
            Spacer()
        }
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "play.slash")
                .font(.largeTitle)
                .foregroundColor(MoonlitTheme.textTertiary)
            Text("No streams available")
                .foregroundColor(MoonlitTheme.textSecondary)
            Button("Dismiss") { dismiss() }
                .buttonStyle(.borderedProminent)
                .tint(.white.opacity(0.2))
            Spacer()
        }
    }

    private var autoPlayView: some View {
        ZStack {
            Color.black

            if let backdropURL = (poster ?? logo).flatMap(URL.init) {
                CachedAsyncImage(url: backdropURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: { Color.clear }
                .ignoresSafeArea()
            }

            LinearGradient(
                colors: [
                    .black.opacity(0.0),
                    .black.opacity(0.3),
                    .black.opacity(0.6),
                    .black.opacity(0.8),
                    .black.opacity(0.9),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                Spacer()

                if let logoURL = logo.flatMap(URL.init) {
                    CachedAsyncImage(url: logoURL) { image in
                        image.resizable().scaledToFit()
                            .frame(width: 300, height: 180)
                            .shadow(color: .black.opacity(0.6), radius: 12, x: 0, y: 4)
                    } placeholder: {
                        Text(mediaName)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                    }
                    .id(logo)
                    .scaleEffect(isAutoPlaying ? 1.04 : 1.0)
                    .animation(.linear(duration: 2.0).repeatForever(autoreverses: true), value: isAutoPlaying)
                } else {
                    Text(mediaName)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .shadow(color: .black.opacity(0.6), radius: 8, x: 0, y: 2)
                        .scaleEffect(isAutoPlaying ? 1.04 : 1.0)
                        .animation(.linear(duration: 2.0).repeatForever(autoreverses: true), value: isAutoPlaying)
                }

                if let status = autoLaunchStatus {
                    Text(status)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }

                Button {
                    dismiss()
                } label: {
                    Text("Cancel")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
                .padding(.top, 8)

                Spacer()
            }
            .padding(.horizontal, 32)
        }
    }

    private var manualPickerView: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Select Source")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .foregroundColor(MoonlitTheme.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            HStack(spacing: 8) {
                addonFilterBar
                Spacer()
                cachedOnlyPill
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            ScrollView {
                LazyVStack(spacing: 0) {
                    let filtered = filteredStreams
                    ForEach(groupedByAddon(filtered), id: \.key) { addonName, streams in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(addonName)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(MoonlitTheme.textTertiary)
                                .tracking(1)
                                .textCase(.uppercase)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)

                            ForEach(streams) { stream in
                                Button {
                                    launchStream(stream)
                                } label: {
                                    StreamRowView(stream: stream, isCurrent: stream.url == currentSourceUrl)
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

    private var addonFilterBar: some View {
        let addons = streamRepo.streams.compactMap(\.addonName)
        let uniqueAddons = Array(Set(addons)).sorted()

        return Group {
            if uniqueAddons.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        Button {
                            selectedAddonFilter = nil
                        } label: {
                            Text("All")
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                                .background(selectedAddonFilter == nil ? Color.white.opacity(0.2) : Color.white.opacity(0.08))
                                .cornerRadius(MoonlitTheme.radiusCard)
                        }
                        .buttonStyle(.plain)

                        ForEach(uniqueAddons, id: \.self) { addon in
                            let count = streamRepo.streams.filter { $0.addonName == addon }.count
                            Button {
                                selectedAddonFilter = addon
                            } label: {
                                Text("\(addon) (\(count))")
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 5)
                                    .background(selectedAddonFilter == addon ? Color.white.opacity(0.2) : Color.white.opacity(0.08))
                                    .cornerRadius(MoonlitTheme.radiusCard)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var cachedOnlyHiddenCount: Int {
        let ranked = StreamSourceSelector.rankedCandidates(from: streamRepo.streams, prefer4K: prefer4K, preferredAudioLanguage: preferredAudioLanguage)
            .filter { $0.url != nil && !($0.url?.isEmpty ?? true) }
        return ranked.filter { !StreamSourceSelector.isCachedStream($0) }.count
    }

    private var cachedOnlyPill: some View {
        Group {
            if cachedOnlyHiddenCount > 0 || cachedOnlyFilter {
                Button {
                    cachedOnlyFilter.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill").font(.system(size: 9))
                        Text(cachedOnlyFilter ? "Cached only · +\(cachedOnlyHiddenCount)" : "Show all sources")
                    }
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(cachedOnlyFilter ? MoonlitTheme.accent.opacity(0.18) : Color.white.opacity(0.08))
                    .foregroundColor(cachedOnlyFilter ? MoonlitTheme.accent : MoonlitTheme.textSecondary)
                    .cornerRadius(MoonlitTheme.radiusCard)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var filteredStreams: [StreamItem] {
        var ranked = StreamSourceSelector.rankedCandidates(from: streamRepo.streams, prefer4K: prefer4K, preferredAudioLanguage: preferredAudioLanguage)
            .filter { $0.url != nil && !($0.url?.isEmpty ?? true) }
        if cachedOnlyFilter {
            ranked = ranked.filter { StreamSourceSelector.isCachedStream($0) }
        }
        guard let filter = selectedAddonFilter else {
            return ranked
        }
        return ranked.filter { $0.addonName == filter }
    }

    private func groupedByAddon(_ streams: [StreamItem]) -> [(key: String, value: [StreamItem])] {
        let grouped = Dictionary(grouping: streams) { $0.addonName ?? "Unknown" }
        return grouped.sorted { $0.key < $1.key }
    }

    private func startAutoPlay(streams: [StreamItem]) {
        isAutoPlaying = true
        autoLaunchAttempts = 0
        autoLaunchStatus = "Finding best source..."

        let candidates = StreamSourceSelector.candidatesForAutoPlay(from: streams, prefer4K: prefer4K, preferredAudioLanguage: preferredAudioLanguage)

        guard !candidates.isEmpty else {
            autoLaunchStatus = "No playable streams found"
            return
        }

        tryNextAutoCandidate(candidates: candidates, index: 0)
    }

    private func tryNextAutoCandidate(candidates: [StreamItem], index: Int) {
        guard index < candidates.count else {
            autoLaunchStatus = "No working sources found"
            return
        }

        autoLaunchAttempts += 1
        autoLaunchStatus = autoLaunchAttempts > 1
            ? "Trying source \(autoLaunchAttempts)..."
            : "Starting playback..."

        let candidate = candidates[index]
        guard let url = candidate.url else {
            tryNextAutoCandidate(candidates: candidates, index: index + 1)
            return
        }

        let launch = PlayerLaunch(
            title: mediaName,
            sourceUrl: url,
            sourceHeaders: candidate.behaviorHints?.proxyHeaders?.request,
            logo: logo, poster: poster,
            background: background,
            seasonNumber: seasonNumber,
            episodeNumber: episodeNumber,
            streamTitle: candidate.displayName,
            providerName: candidate.addonName,
            contentType: mediaType,
            videoId: videoId ?? mediaId,
            parentMetaId: mediaId,
            parentMetaType: mediaType.rawValue
        )

        onLaunch(launch)
        dismiss()
    }

    private func launchStream(_ stream: StreamItem) {
        guard let url = stream.url else { return }
        let launch = PlayerLaunch(
            title: mediaName,
            sourceUrl: url,
            sourceHeaders: stream.behaviorHints?.proxyHeaders?.request,
            logo: logo, poster: poster,
            background: background,
            seasonNumber: seasonNumber,
            episodeNumber: episodeNumber,
            streamTitle: stream.displayName,
            providerName: stream.addonName,
            contentType: mediaType,
            videoId: videoId ?? mediaId,
            parentMetaId: mediaId,
            parentMetaType: mediaType.rawValue
        )
        onLaunch(launch)
    }
}

// MARK: - AutoplayMode enum for macOS

private enum AutoplayMode {
    case auto, manual
}

// MARK: - StreamRowView

struct StreamRowView: View {
    let stream: StreamItem
    var isCurrent: Bool = false
    @State private var isHovering = false

    private var meta: StreamMetadata { stream.parseMetadata() }
    private var isCached: Bool { StreamSourceSelector.isCachedStream(stream) }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    let quality = StreamSourceSelector.quality(of: stream)
                    if quality != .unknown {
                        Text(qualityLabel(for: quality))
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(qualityColor(for: quality))
                            .foregroundColor(.black)
                            .cornerRadius(MoonlitTheme.radiusSmall)
                    }
                    if let codec = meta.videoCodec {
                        Text(codec)
                            .font(.system(size: 10))
                            .foregroundColor(MoonlitTheme.textTertiary)
                    }
                    if let audio = meta.audioCodec {
                        Text(audio)
                            .font(.system(size: 10))
                            .foregroundColor(MoonlitTheme.textTertiary)
                    }
                    if let hdr = meta.hdr {
                        Text(hdr)
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.3))
                            .foregroundColor(MoonlitTheme.accent)
                            .cornerRadius(MoonlitTheme.radiusSmall)
                    }
                }

                Text(stream.displayName)
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .lineLimit(1)

                // Already parsed off the addon's title/description by
                // StreamMetadata — just wasn't drawn anywhere before.
                if meta.fileSize != nil || meta.releaseGroup != nil {
                    HStack(spacing: 4) {
                        if let size = meta.fileSize { Text(size) }
                        if meta.fileSize != nil, meta.releaseGroup != nil { Text("·") }
                        if let group = meta.releaseGroup { Text(group) }
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(MoonlitTheme.textTertiary)
                }

                if let desc = stream.description, !desc.isEmpty {
                    Text(desc)
                        .font(.caption2)
                        .foregroundColor(MoonlitTheme.textTertiary)
                        .lineLimit(2)
                }
            }

            Spacer()

            if isCached {
                Text("⚡ Instant")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(MoonlitTheme.accent)
            }

            if isCurrent {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(MoonlitTheme.accent)
            } else {
                Image(systemName: "play.circle.fill")
                    .font(.title3)
                    .foregroundColor(MoonlitTheme.accent)
                    .opacity(isHovering ? 1 : 0.5)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(isCurrent ? MoonlitTheme.accent.opacity(0.08) : (isHovering ? MoonlitTheme.surfaceElevated : MoonlitTheme.surface))
        .onHover { isHovering = $0 }
    }

    private func qualityLabel(for quality: StreamQuality) -> String {
        switch quality {
        case .ultraHD4K: return "4K"
        case .hd1080: return "1080p"
        case .unknown: return "Auto"
        }
    }

    private func qualityColor(for quality: StreamQuality) -> Color {
        switch quality {
        case .ultraHD4K: return .yellow
        case .hd1080: return .blue
        default: return .green
        }
    }
}
