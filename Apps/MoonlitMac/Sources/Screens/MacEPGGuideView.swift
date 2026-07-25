import SwiftUI
import MoonlitCore

/// Channels × time program guide. Port of a reference `guide/guide-view.tsx`. The time
/// axis is a single horizontal ScrollView shared by the ruler and every lane, with a
/// fixed left channel column overlaid so it stays put while the timeline scrolls.
struct MacEPGGuideView: View {
    @ObservedObject var repo: IPTVSourceRepository
    let channels: [IPTVChannel]
    /// Play the live channel (channel label tap).
    var onPlay: (IPTVChannel) -> Void
    /// Play a specific program: catch-up if it's over and the channel supports it,
    /// otherwise live. Owned by the caller (it builds the PlayerLaunch).
    var onPlayProgram: (IPTVChannel, EPGProgram) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showingMatch = false

    // Layout constants — the label column and lanes must share row metrics so the
    // overlaid left column stays vertically aligned with the timeline rows.
    private let labelWidth: CGFloat = 160
    private let rowHeight: CGFloat = 56
    private let rowSpacing: CGFloat = 4
    private let rulerHeight: CGFloat = 26
    private let pointsPerMinute: CGFloat = 4
    private let windowHours = 6

    private var windowStartMs: Double {
        // Floor "now" to the previous 30-minute mark.
        let now = Date().timeIntervalSince1970
        let half = 30.0 * 60
        return (now - now.truncatingRemainder(dividingBy: half)) * 1000
    }
    private var windowMinutes: CGFloat { CGFloat(windowHours) * 60 }
    private var timelineWidth: CGFloat { windowMinutes * pointsPerMinute }
    private var pointsPerMs: CGFloat { pointsPerMinute / 60_000 }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.white.opacity(0.08))
            guideBody
        }
        .frame(minWidth: 900, minHeight: 560)
        .background(MoonlitTheme.background)
        .sheet(isPresented: $showingMatch) {
            MacEPGMatchView(repo: repo, channels: unmatchedChannels)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("TV Guide")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(MoonlitTheme.textPrimary)
            Spacer()
            if !unmatchedChannels.isEmpty {
                Button {
                    showingMatch = true
                } label: {
                    Label("Match \(unmatchedChannels.count)", systemImage: "link")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(MoonlitTheme.textSecondary)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(MoonlitTheme.surface, in: Capsule())
                }
                .buttonStyle(.plain)
                .help("Manually match channels to EPG data")
            }
            Button("Done") { dismiss() }
                .buttonStyle(.plain)
                .foregroundColor(.black)
                .padding(.horizontal, 16).padding(.vertical, 7)
                .background(MoonlitTheme.accent, in: Capsule())
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var guideBody: some View {
        ScrollView(.vertical) {
            ZStack(alignment: .topLeading) {
                // Timeline (ruler + lanes), inset to leave room for the label column.
                ScrollView(.horizontal, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: rowSpacing) {
                        timeRuler
                        ForEach(channels) { channel in
                            lane(for: channel)
                        }
                    }
                    .overlay(alignment: .topLeading) { nowLine }
                    .padding(.vertical, 10)
                }
                .padding(.leading, labelWidth)

                // Fixed left channel labels, aligned row-for-row with the lanes.
                VStack(alignment: .leading, spacing: rowSpacing) {
                    Color.clear.frame(height: rulerHeight)
                    ForEach(channels) { channel in
                        channelLabel(channel)
                    }
                }
                .padding(.vertical, 10)
                .background(MoonlitTheme.background)
            }
        }
    }

    // MARK: - Ruler & now-line

    private var timeRuler: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(stride(from: 0, through: windowHours * 60, by: 30)), id: \.self) { minute in
                let date = Date(timeIntervalSince1970: windowStartMs / 1000 + Double(minute) * 60)
                Text(date, format: .dateTime.hour().minute())
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(MoonlitTheme.textTertiary)
                    .offset(x: CGFloat(minute) * pointsPerMinute + 4)
            }
        }
        .frame(width: timelineWidth, height: rulerHeight, alignment: .topLeading)
    }

    private var nowLine: some View {
        let x = CGFloat((Date().timeIntervalSince1970 * 1000 - windowStartMs)) * pointsPerMs
        let totalHeight = rulerHeight + (rowHeight + rowSpacing) * CGFloat(channels.count)
        return Rectangle()
            .fill(MoonlitTheme.accent)
            .frame(width: 1.5, height: totalHeight)
            .offset(x: x)
            .allowsHitTesting(false)
    }

    // MARK: - Lanes

    private func channelLabel(_ channel: IPTVChannel) -> some View {
        HStack(spacing: 8) {
            CachedAsyncImage(url: channel.logo.flatMap { URL(string: $0) }) { img in
                img.resizable().aspectRatio(contentMode: .fit)
            } placeholder: {
                Image(systemName: "tv").foregroundColor(MoonlitTheme.textTertiary)
            }
            .frame(width: 32, height: 32)

            Text(channel.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(MoonlitTheme.textPrimary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(width: labelWidth, height: rowHeight, alignment: .leading)
        .background(MoonlitTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture { onPlay(channel) }
    }

    private func lane(for channel: IPTVChannel) -> some View {
        let programs = repo.epg?.programs(for: channel, overrides: repo.epgOverrides) ?? []
        let windowEnd = windowStartMs + Double(windowHours) * 3_600_000
        let visible = programs.filter { $0.endMs > windowStartMs && $0.startMs < windowEnd }
        let nowMs = Date().timeIntervalSince1970 * 1000
        let hasCatchup = IPTVCatchup.channelHasCatchup(channel)

        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(0.02))
                .frame(width: timelineWidth, height: rowHeight)

            ForEach(visible) { program in
                let clampedStart = max(program.startMs, windowStartMs)
                let clampedEnd = min(program.endMs, windowEnd)
                let x = CGFloat(clampedStart - windowStartMs) * pointsPerMs
                let w = max(2, CGFloat(clampedEnd - clampedStart) * pointsPerMs)
                let isNow = nowMs >= program.startMs && nowMs < program.endMs
                let canCatchup = hasCatchup && program.endMs <= nowMs
                programBlock(program, isNow: isNow, canCatchup: canCatchup, width: w)
                    .offset(x: x)
                    .onTapGesture { onPlayProgram(channel, program) }
            }

            if visible.isEmpty {
                Text("No guide data")
                    .font(.system(size: 11))
                    .foregroundColor(MoonlitTheme.textTertiary)
                    .padding(.leading, 8)
                    .frame(height: rowHeight, alignment: .leading)
            }
        }
        .frame(width: timelineWidth, height: rowHeight, alignment: .topLeading)
    }

    private func programBlock(_ program: EPGProgram, isNow: Bool, canCatchup: Bool, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                if canCatchup {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(MoonlitTheme.accent)
                }
                Text(program.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(canCatchup ? MoonlitTheme.textPrimary : (isNow ? MoonlitTheme.textPrimary : MoonlitTheme.textSecondary))
                    .lineLimit(1)
            }
            Text(program.startDate, format: .dateTime.hour().minute())
                .font(.system(size: 9))
                .foregroundColor(MoonlitTheme.textTertiary)
        }
        .padding(.horizontal, 6)
        .frame(width: width, height: rowHeight - 4, alignment: .topLeading)
        .background(isNow ? MoonlitTheme.accent.opacity(0.22) : MoonlitTheme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isNow ? MoonlitTheme.accent.opacity(0.6) : Color.white.opacity(0.06), lineWidth: isNow ? 1 : 0.5)
        )
        .help(canCatchup ? "Play from catch-up" : program.title)
    }

    private var unmatchedChannels: [IPTVChannel] {
        guard repo.epg != nil else { return [] }
        return channels.filter { (repo.epg?.programs(for: $0, overrides: repo.epgOverrides)?.isEmpty ?? true) }
    }
}

/// Manual EPG matching: pick a channel with no guide data, then assign it a tvg-id
/// from the EPG feed. Port of a reference `guide/epg-match-modal.tsx`.
private struct MacEPGMatchView: View {
    @ObservedObject var repo: IPTVSourceRepository
    let channels: [IPTVChannel]

    @Environment(\.dismiss) private var dismiss
    @State private var selectedChannel: IPTVChannel?
    @State private var query = ""

    private var filteredTvgIds: [String] {
        let all = repo.epgTvgIds
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let matched = trimmed.isEmpty ? all : all.filter { $0.localizedCaseInsensitiveContains(trimmed) }
        return Array(matched.prefix(200))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Match Channels to EPG")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(MoonlitTheme.textPrimary)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundColor(.black)
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(MoonlitTheme.accent, in: Capsule())
            }
            .padding(16)
            Divider().overlay(Color.white.opacity(0.08))

            HStack(spacing: 0) {
                channelList
                Divider().overlay(Color.white.opacity(0.08))
                tvgIdList
            }
        }
        .frame(width: 640, height: 460)
        .background(MoonlitTheme.background)
    }

    private var channelList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(channels) { channel in
                    Button {
                        selectedChannel = channel
                    } label: {
                        HStack {
                            Text(channel.name)
                                .font(.system(size: 12, weight: selectedChannel?.id == channel.id ? .semibold : .regular))
                                .foregroundColor(MoonlitTheme.textPrimary)
                                .lineLimit(1)
                            Spacer()
                            if repo.epgOverrides[channel.id] != nil {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(MoonlitTheme.accent)
                                    .font(.system(size: 11))
                            }
                        }
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(selectedChannel?.id == channel.id ? MoonlitTheme.surface : .clear, in: RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
        }
        .frame(width: 280)
    }

    private var tvgIdList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12)).foregroundColor(MoonlitTheme.textTertiary)
                TextField("Search EPG channel id", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(MoonlitTheme.textPrimary)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(MoonlitTheme.surface, in: Capsule())
            .padding(10)

            if let channel = selectedChannel {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(filteredTvgIds, id: \.self) { tvgId in
                            Button {
                                repo.setOverride(channelId: channel.id, tvgId: tvgId)
                            } label: {
                                Text(tvgId)
                                    .font(.system(size: 12))
                                    .foregroundColor(repo.epgOverrides[channel.id] == tvgId ? MoonlitTheme.accent : MoonlitTheme.textSecondary)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 10)
                }
            } else {
                Spacer()
                Text("Select a channel to match")
                    .font(.system(size: 12))
                    .foregroundColor(MoonlitTheme.textTertiary)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity)
    }
}
