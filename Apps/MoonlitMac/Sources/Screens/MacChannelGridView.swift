import SwiftUI
import MoonlitCore

/// A searchable, category-grouped grid of live channels. Port of a reference
/// `channel-grid.tsx`. Presentation-only: the owner supplies channels and handles
/// selection (playback lives in `MacLiveTVView`).
struct MacChannelGridView: View {
    let channels: [IPTVChannel]
    /// Supplies now/next for a channel; the grid also prefetches Xtream fallback.
    @ObservedObject var repo: IPTVSourceRepository
    var onSelect: (IPTVChannel) -> Void

    @State private var query = ""

    private var filtered: [IPTVChannel] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return channels }
        return channels.filter { channel in
            channel.name.localizedCaseInsensitiveContains(trimmed)
                || (channel.group?.localizedCaseInsensitiveContains(trimmed) ?? false)
        }
    }

    /// Channels bucketed by group, preserving first-seen group order; ungrouped last.
    private var groups: [(group: String, channels: [IPTVChannel])] {
        var buckets: [String: [IPTVChannel]] = [:]
        var order: [String] = []
        for channel in filtered {
            let key = channel.group?.isEmpty == false ? channel.group! : IPTVPlaylist.ungrouped
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(channel)
        }
        // Push the synthesized "Ungrouped" bucket to the end.
        let ordered = order.filter { $0 != IPTVPlaylist.ungrouped } + order.filter { $0 == IPTVPlaylist.ungrouped }
        return ordered.map { ($0, buckets[$0] ?? []) }
    }

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 16)]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24, pinnedViews: [.sectionHeaders]) {
                searchBar
                    .padding(.horizontal, 24)
                    .padding(.top, 8)

                if filtered.isEmpty {
                    emptyState
                } else {
                    ForEach(groups, id: \.group) { section in
                        Section {
                            LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                                ForEach(section.channels) { channel in
                                    ChannelTile(channel: channel, nowNext: repo.nowNext(for: channel))
                                        .onTapGesture { onSelect(channel) }
                                        .task(id: channel.id) { await repo.prefetchXtreamNowNext(for: channel) }
                                }
                            }
                            .padding(.horizontal, 24)
                        } header: {
                            sectionHeader(section.group, count: section.channels.count)
                        }
                    }
                }
            }
            .padding(.bottom, 40)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(MoonlitTheme.textTertiary)
            TextField("Search channels", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundColor(MoonlitTheme.textPrimary)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(MoonlitTheme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(MoonlitTheme.surface, in: Capsule())
        .frame(maxWidth: 360, alignment: .leading)
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(MoonlitTheme.textSecondary)
                .tracking(1)
            Text("\(count)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(MoonlitTheme.textTertiary)
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .background(MoonlitTheme.background.opacity(0.95))
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32, weight: .light))
                .foregroundColor(MoonlitTheme.textTertiary)
            Text("No channels match “\(query)”")
                .font(.system(size: 14))
                .foregroundColor(MoonlitTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

/// A single channel tile: logo in a rounded square (letterboxed, since channel
/// logos vary wildly in aspect), name underneath, with the same hover treatment as
/// `MediaCard`.
private struct ChannelTile: View, Equatable {
    let channel: IPTVChannel
    let nowNext: EPGNowNext
    @State private var isHovering = false
    @State private var logoFailed = false

    static func == (lhs: ChannelTile, rhs: ChannelTile) -> Bool {
        lhs.channel == rhs.channel && lhs.nowNext == rhs.nowNext
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                MoonlitTheme.surfaceElevated
                logo
            }
            .frame(width: 150, height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(isHovering ? 0.16 : 0.05), lineWidth: 0.75)
            )
            .overlay(alignment: .center) {
                if isHovering {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(.white, .black.opacity(0.35))
                        .transition(.opacity.combined(with: .scale))
                }
            }
            .overlay(alignment: .bottom) {
                if let current = nowNext.current {
                    nowBadge(current)
                }
            }
            .scaleEffect(isHovering ? 1.04 : 1.0)
            .animation(.spring(response: 0.30, dampingFraction: 0.78), value: isHovering)
            .onHover { isHovering = $0 }

            Text(channel.name)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundColor(MoonlitTheme.textPrimary)
                .lineLimit(2)
                .frame(width: 150, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// "Now playing" strip with a thin progress bar for the live program.
    private func nowBadge(_ program: EPGProgram) -> some View {
        let now = Date().timeIntervalSince1970 * 1000
        let progress = program.durationMs > 0
            ? max(0, min(1, (now - program.startMs) / program.durationMs))
            : 0
        return VStack(spacing: 0) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Color.white.opacity(0.18)
                    MoonlitTheme.accent.frame(width: geo.size.width * progress)
                }
            }
            .frame(height: 2)

            Text(program.title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(.black.opacity(0.6))
        }
        .clipShape(RoundedRectangle(cornerRadius: 0))
    }

    @ViewBuilder
    private var logo: some View {
        if let logoStr = channel.logo, !logoStr.isEmpty, !logoFailed, let url = URL(string: logoStr) {
            CachedAsyncImage(url: url) { image in
                image.resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(14)
            } placeholder: {
                placeholder.onAppear {
                    // CachedAsyncImage shows the placeholder on failure; latch it so a
                    // broken logo URL falls back to the icon rather than staying blank.
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "tv")
                .font(.system(size: 26))
                .foregroundColor(.white.opacity(0.22))
            Text(channel.name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.45))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 10)
        }
    }
}
