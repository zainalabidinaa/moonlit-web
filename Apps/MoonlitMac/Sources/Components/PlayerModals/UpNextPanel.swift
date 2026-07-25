import SwiftUI
import MoonlitCore

/// reference-style "Up Next" side panel (`src/components/player/episode-panel`):
/// a solid-surface slide-in list with a season selector, per-episode
/// Play/Restart pills, and expandable episode details (air date, rating,
/// overview) behind a chevron toggle. "Restart" replays the current episode;
/// "Play" hands off to the same `goToEpisode` navigation.
struct UpNextPanel: View {
    let seriesTitle: String
    let seasons: [Season]
    @Binding var selectedSeasonNumber: Int
    let currentSeasonNumber: Int
    let currentEpisodeNumber: Int
    let currentEpisodeTitle: String
    let onRestart: () -> Void
    let onPlay: (MetaVideo) -> Void
    let onClose: () -> Void

    @State private var expandedEpisodeId: String?

    private var selectedSeason: Season? {
        seasons.first { $0.number == selectedSeasonNumber }
    }

    private var episodes: [MetaVideo] {
        (selectedSeason?.episodes ?? []).sorted { ($0.episode ?? 0) < ($1.episode ?? 0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().background(PlayerPalette.edgeSoft)

            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 12) {
                    ForEach(episodes) { episode in
                        UpNextRow(
                            episode: episode,
                            isNowPlaying: episode.season == currentSeasonNumber && episode.episode == currentEpisodeNumber,
                            isExpanded: expandedEpisodeId == episode.id,
                            onToggleExpand: {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    expandedEpisodeId = (expandedEpisodeId == episode.id) ? nil : episode.id
                                }
                            },
                            onRestart: onRestart,
                            onPlay: { onPlay(episode) }
                        )
                    }
                }
                .padding(16)
            }

            Divider().background(PlayerPalette.edgeSoft)
            Text("Instant Play: clicking Play queues the next stream automatically.")
                .font(.system(size: 12))
                .foregroundColor(PlayerPalette.inkSubtle)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
        }
        .frame(width: 440)
        .background(PlayerPalette.surface)
        .overlay(alignment: .leading) {
            Rectangle().fill(PlayerPalette.edgeSoft).frame(width: 1).ignoresSafeArea()
        }
        .shadow(color: .black.opacity(0.85), radius: 40, x: -10, y: 15)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("UP NEXT")
                        .font(.system(size: 10.5, weight: .semibold))
                        .tracking(3.2)
                        .foregroundColor(PlayerPalette.inkSubtle)
                    Text(seriesTitle)
                        .font(.system(size: 22, weight: .semibold, design: .serif))
                        .foregroundColor(PlayerPalette.ink)
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(PlayerPalette.inkMuted)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(PlayerPalette.elevated))
                }
                .buttonStyle(.plain)
            }

            HStack {
                Text("Now playing: S\(currentSeasonNumber) · E\(String(format: "%02d", currentEpisodeNumber)) · \(currentEpisodeTitle)")
                    .font(.system(size: 12.5))
                    .foregroundColor(PlayerPalette.inkSubtle)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                if seasons.count > 1 {
                    Menu {
                        ForEach(seasons.sorted { $0.number < $1.number }) { season in
                            Button("Season \(season.number)") { selectedSeasonNumber = season.number }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Text("Season \(selectedSeasonNumber)")
                            Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(PlayerPalette.ink)
                        .padding(.leading, 14)
                        .padding(.trailing, 10)
                        .frame(height: 36)
                        .background(PlayerPalette.elevated, in: Capsule())
                        .overlay(Capsule().strokeBorder(PlayerPalette.edgeSoft, lineWidth: 1))
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
            }
        }
        .padding(20)
    }
}

private struct UpNextRow: View {
    let episode: MetaVideo
    let isNowPlaying: Bool
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    let onRestart: () -> Void
    let onPlay: () -> Void
    @State private var hovering = false

    private var isUnaired: Bool {
        guard let released = episode.released,
              let date = ISO8601DateFormatter.releaseDateFormatter.date(from: released) else { return false }
        return date > Date()
    }

    private var formattedAirDate: String? {
        guard let released = episode.released else { return nil }
        guard let date = ISO8601DateFormatter.releaseDateFormatter.date(from: released) else { return released }
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d, yyyy"
        return fmt.string(from: date)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 16) {
                thumbnailView

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text(episode.title)
                            .font(.system(size: 14.5, weight: .semibold))
                            .foregroundColor(PlayerPalette.ink)
                            .lineLimit(2)
                        if isNowPlaying {
                            Text("NOW PLAYING")
                                .font(.system(size: 10, weight: .bold))
                                .tracking(1.0)
                                .foregroundColor(MoonlitTheme.accent)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(MoonlitTheme.accent.opacity(0.15), in: Capsule())
                                .overlay(Capsule().strokeBorder(MoonlitTheme.accent.opacity(0.3), lineWidth: 1))
                        }
                    }

                    HStack(spacing: 8) {
                        Button(action: isNowPlaying ? onRestart : onPlay) {
                            HStack(spacing: 6) {
                                Image(systemName: isNowPlaying ? "arrow.counterclockwise" : "play.fill")
                                    .font(.system(size: 12, weight: .semibold))
                                Text(isNowPlaying ? "Restart" : "Play")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundColor(.black)
                            .frame(height: 44)
                            .frame(maxWidth: .infinity)
                            .background(MoonlitTheme.accent, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(isUnaired)
                        .opacity(isUnaired ? 0.4 : 1)

                        Button(action: onToggleExpand) {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(PlayerPalette.inkMuted)
                                .frame(width: 44, height: 44)
                                .background(Circle().fill(PlayerPalette.elevated))
                                .overlay(Circle().strokeBorder(PlayerPalette.edgeSoft, lineWidth: 1))
                                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                                .animation(.easeOut(duration: 0.2), value: isExpanded)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(hovering || isExpanded ? PlayerPalette.elevated : PlayerPalette.elevated.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isNowPlaying ? MoonlitTheme.accent : PlayerPalette.edgeSoft,
                                  lineWidth: isNowPlaying ? 2 : 1)
            )
            .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hovering = h } }
            .animation(.easeOut(duration: 0.15), value: hovering)

            if isExpanded {
                expandedDetails
            }
        }
    }

    private var thumbnailView: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(PlayerPalette.raised)
            if let thumbnail = episode.thumbnail, let url = URL(string: thumbnail), !isUnaired {
                CachedAsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: { Color.clear }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                LinearGradient(
                    colors: [.clear, .black.opacity(0.45)],
                    startPoint: .center, endPoint: .bottom
                )
            } else {
                Image(systemName: "hourglass")
                    .foregroundColor(PlayerPalette.inkSubtle)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Text("S\(episode.season ?? 0) · E\(String(format: "%02d", episode.episode ?? 0))")
                .font(.system(size: 10.5, weight: .bold))
                .tracking(1.4)
                .textCase(.uppercase)
                .foregroundColor(.white.opacity(0.9))
                .shadow(color: .black.opacity(0.7), radius: 2, x: 0, y: 1)
                .padding(6)
        }
        .frame(width: 156, height: 88)
        .clipped()
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(PlayerPalette.edgeSoft.opacity(0.6), lineWidth: 1)
        )
    }

    private var expandedDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                if let voteAvg = episode.voteAverage, voteAvg > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill").font(.system(size: 11))
                            .foregroundColor(MoonlitTheme.ratingGold)
                        Text(String(format: "%.1f", voteAvg))
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(MoonlitTheme.ratingGold)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(MoonlitTheme.ratingGold.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(MoonlitTheme.ratingGold.opacity(0.25), lineWidth: 1))
                }

                if let airDate = formattedAirDate {
                    Text(airDate)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(PlayerPalette.inkSubtle)
                }

                if let runtime = episode.runtime, !runtime.isEmpty {
                    Text(runtime)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(PlayerPalette.inkSubtle)
                }
            }

            if let overview = episode.overview, !overview.isEmpty {
                Text(overview)
                    .font(.system(size: 13))
                    .foregroundColor(PlayerPalette.inkMuted)
                    .lineSpacing(3)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(PlayerPalette.canvas.opacity(0.4)))
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

/// reference-style vertical "UP NEXT" tab on the video's trailing edge
/// (`src/views/player/panels-layer.tsx`). Tapping opens `UpNextPanel`.
struct UpNextTab: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: "text.line.first.and.arrowtriangle.forward")
                    .font(.system(size: 15, weight: .semibold))
                Text("UP NEXT")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(2.8)
                    .fixedSize()
                    .rotationEffect(.degrees(90))
                    .frame(width: 16)
            }
            .foregroundColor(PlayerPalette.ink)
            .frame(height: 128)
            .padding(.leading, 8)
            .padding(.trailing, hovering ? 12 : 8)
            .background(
                UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 16)
                    .fill(PlayerPalette.elevated.opacity(0.95))
            )
            .overlay(
                UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 16)
                    .strokeBorder(PlayerPalette.edgeSoft, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.6), radius: 16, x: -6, y: 6)
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.2)) { hovering = h } }
    }
}

private extension ISO8601DateFormatter {
    static let releaseDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter
    }()
}
