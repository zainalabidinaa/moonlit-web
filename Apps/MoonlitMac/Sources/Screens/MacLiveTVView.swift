import SwiftUI
import MoonlitCore

/// Top-level "Live TV" screen. Owns the source switcher + channel grid, the
/// add/edit source sheet, and channel playback (opens the shared player window,
/// same as `MacDownloadsView`). Port of a reference `views/live.tsx`.
struct MacLiveTVView: View {
    @EnvironmentObject private var profileManager: ProfileManager
    @StateObject private var repo = IPTVSourceRepository.shared
    @Environment(\.openWindow) private var openWindow

    @State private var showingForm = false
    @State private var editingSource: IPTVPlaylistSource?
    @State private var showingGuide = false
    /// nil = "All Channels"; otherwise a specific source id.
    @State private var selectedSourceId: String?

    /// Only playlist/Xtream sources have channels; EPG-only sources are excluded
    /// from the switcher.
    private var playlistSources: [IPTVPlaylistSource] {
        repo.sources.filter { $0.kind != .epg }
    }

    private var displayedChannels: [IPTVChannel] {
        if let id = selectedSourceId {
            return repo.playlists[id]?.channels ?? []
        }
        return repo.allChannels
    }

    var body: some View {
        ZStack {
            MoonlitTheme.background.ignoresSafeArea()

            if playlistSources.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    header
                    if let message = repo.errorMessage {
                        errorBanner(message)
                    }
                    MacChannelGridView(channels: displayedChannels, repo: repo, onSelect: play)
                }
            }
        }
        .task(id: profileManager.currentProfile?.id) {
            guard let profileId = profileManager.currentProfile?.id else { return }
            await repo.load(profileId: profileId)
        }
        .sheet(isPresented: $showingForm) { formSheet(existing: nil) }
        .sheet(item: $editingSource) { source in formSheet(existing: source) }
        .sheet(isPresented: $showingGuide) {
            MacEPGGuideView(repo: repo, channels: displayedChannels, onPlay: { channel in
                showingGuide = false
                play(channel)
            }, onPlayProgram: { channel, program in
                showingGuide = false
                playProgram(channel, program)
            })
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            sourceChip(title: "All Channels", isSelected: selectedSourceId == nil, source: nil)

            ForEach(playlistSources) { source in
                sourceChip(title: source.name, isSelected: selectedSourceId == source.id, source: source)
            }

            Spacer()

            if !repo.refreshing.isEmpty || repo.isLoadingEPG {
                ProgressView()
                    .controlSize(.small)
                    .padding(.trailing, 4)
            }

            if repo.epg != nil {
                iconButton("calendar", help: "TV Guide") { showingGuide = true }
            }
            iconButton("arrow.clockwise", help: "Refresh") {
                Task { await repo.refreshAll() }
            }
            iconButton("plus", help: "Add playlist") { showingForm = true }
        }
        .padding(.horizontal, 24)
        .padding(.top, 74) // clear the floating nav pill
        .padding(.bottom, 12)
    }

    private func sourceChip(title: String, isSelected: Bool, source: IPTVPlaylistSource?) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                selectedSourceId = source?.id
            }
        } label: {
            Text(title)
                .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                .foregroundColor(isSelected ? .black : MoonlitTheme.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isSelected ? MoonlitTheme.accent : MoonlitTheme.surface, in: Capsule())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let source {
                Button("Edit") { editingSource = source }
                Button("Refresh") { Task { await repo.refresh(source) } }
                Divider()
                Button("Delete", role: .destructive) {
                    if selectedSourceId == source.id { selectedSourceId = nil }
                    repo.removeSource(id: source.id)
                }
            }
        }
    }

    private func iconButton(_ systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(MoonlitTheme.textSecondary)
                .frame(width: 34, height: 34)
                .background(MoonlitTheme.surface, in: Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(MoonlitTheme.ratingGold)
            Text(message)
                .font(.system(size: 12))
                .foregroundColor(MoonlitTheme.textSecondary)
                .lineLimit(2)
            Spacer()
            Button {
                repo.errorMessage = nil
            } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
                    .foregroundColor(MoonlitTheme.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(MoonlitTheme.surface, in: RoundedRectangle(cornerRadius: MoonlitTheme.radiusControl))
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(MoonlitTheme.textTertiary)
            VStack(spacing: 6) {
                Text("No playlists yet")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(MoonlitTheme.textSecondary)
                Text("Add an M3U playlist or Xtream Codes account to watch live channels.")
                    .font(.system(size: 13))
                    .foregroundColor(MoonlitTheme.textTertiary)
                    .multilineTextAlignment(.center)
            }
            Button {
                showingForm = true
            } label: {
                Text("Add Playlist")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 10)
                    .background(MoonlitTheme.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: 380)
    }

    // MARK: - Actions

    private func formSheet(existing: IPTVPlaylistSource?) -> some View {
        MacIPTVSourceFormView(existing: existing) { source in
            Task {
                if existing == nil {
                    await repo.addSource(source)
                    selectedSourceId = source.kind == .epg ? selectedSourceId : source.id
                } else {
                    await repo.updateSource(source)
                }
            }
        }
    }

    /// The source name a channel came from, for the player's provider label.
    private func sourceName(for channel: IPTVChannel) -> String? {
        repo.sources.first { source in
            repo.playlists[source.id]?.channels.contains(where: { $0.id == channel.id }) ?? false
        }?.name
    }

    private func play(_ channel: IPTVChannel) {
        let launch = PlayerLaunch(
            title: channel.name,
            sourceUrl: channel.url,
            sourceHeaders: channel.headers,
            logo: channel.logo,
            poster: channel.logo,
            streamTitle: channel.group,
            providerName: sourceName(for: channel) ?? "Live TV",
            contentType: .channel,
            videoId: channel.id
        )
        openWindow(id: "player", value: launch)
    }

    /// Play a program from the guide: catch-up if it's over and the channel supports
    /// it, otherwise fall back to the live stream.
    private func playProgram(_ channel: IPTVChannel, _ program: EPGProgram) {
        let now = Date().timeIntervalSince1970 * 1000
        guard program.endMs <= now,
              let url = IPTVCatchup.buildURL(for: channel, startMs: program.startMs, endMs: program.endMs) else {
            play(channel)
            return
        }
        let launch = PlayerLaunch(
            title: "\(channel.name) — \(program.title)",
            sourceUrl: url,
            sourceHeaders: channel.headers,
            logo: channel.logo,
            poster: channel.logo,
            streamTitle: program.title,
            providerName: (sourceName(for: channel) ?? "Live TV") + " · Catch-up",
            contentType: .channel,
            videoId: "\(channel.id)::catchup::\(Int(program.startMs))"
        )
        openWindow(id: "player", value: launch)
    }
}
