import SwiftUI
import MoonlitCore

/// A dedicated page for a single episode, reached via "Episode Details" in
/// the episode grid's right-click menu — the grid's own tap-to-play is left
/// untouched. Unlike the in-player `EpisodeInfoPanel` (a compact modal card
/// meant to be skimmed without pausing), this is a full page: a hero built
/// from the episode's own still, guest cast, and a bigger overview — for
/// browsing before you've committed to playing anything.
struct MacEpisodeDetailView: View {
    let seriesId: String
    let seriesName: String
    let episode: MetaVideo
    let seasonNumber: Int
    let onPlay: () -> Void
    let onClose: () -> Void

    @State private var stillURL: URL?
    @State private var directors: [String] = []
    @State private var writers: [String] = []
    @State private var guestStars: [Person] = []
    @State private var guestStarIDs: Set<String> = []
    @State private var isLoadingCredits = false

    private let heroHeight: CGFloat = 260

    private var episodeNumber: Int { episode.episode ?? 0 }

    private var formattedAirDate: String? {
        guard let released = episode.released else { return nil }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withFullDate]
        guard let date = parser.date(from: released) else { return released }
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d, yyyy"
        return fmt.string(from: date)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero
                content
                    .padding(28)
            }
        }
        .frame(minWidth: 680, minHeight: 600)
        .background(MoonlitTheme.background)
        .overlay(alignment: .topTrailing) { closeButton }
        .task { await loadEpisodeExtras() }
    }

    // MARK: - Hero

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let url = stillURL ?? episode.thumbnail.flatMap(URL.init) {
                    CachedAsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        MoonlitTheme.surfaceElevated
                    }
                } else {
                    MoonlitTheme.surfaceElevated
                }
            }
            .frame(height: heroHeight)
            .clipped()

            LinearGradient(
                stops: [
                    .init(color: MoonlitTheme.background.opacity(0), location: 0.3),
                    .init(color: MoonlitTheme.background, location: 1.0),
                ],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: heroHeight)

            VStack(alignment: .leading, spacing: 12) {
                Button(action: onClose) {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left")
                        Text(seriesName)
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))
                }
                .buttonStyle(.plain)

                Text("S\(seasonNumber)E\(episodeNumber) — \(episode.title)")
                    .font(.system(size: 24, weight: .medium, design: .serif))
                    .foregroundColor(.white)
                    .lineLimit(2)

                HStack(spacing: 10) {
                    if let formattedAirDate {
                        pill("Aired \(formattedAirDate)")
                    }
                    if let runtime = episode.runtime, !runtime.isEmpty {
                        pill(runtime)
                    }
                    if let rating = episode.voteAverage, rating > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill").font(.system(size: 11))
                            Text(String(format: "%.1f", rating))
                        }
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundColor(MoonlitTheme.ratingGold)
                    }
                }

                Button(action: onPlay) {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                        Text("Play Episode")
                    }
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .background(Color.white, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .padding(24)
        }
        .frame(height: heroHeight)
    }

    private func pill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.white.opacity(0.75))
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.85))
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.black.opacity(0.5)))
        }
        .buttonStyle(.plain)
        .padding(16)
    }

    // MARK: - Content

    private var content: some View {
        VStack(alignment: .leading, spacing: 26) {
            if let overview = episode.overview, !overview.isEmpty {
                Text(overview)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(MoonlitTheme.textSecondary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !directors.isEmpty || !writers.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    if !directors.isEmpty { crewRow("DIRECTOR", directors) }
                    if !writers.isEmpty { crewRow("WRITER", writers) }
                }
            }

            if isLoadingCredits && guestStars.isEmpty {
                HStack(spacing: 8) {
                    MacStrokeSpinner(size: 18)
                    Text("Loading cast…")
                        .font(.system(size: 13))
                        .foregroundColor(MoonlitTheme.textTertiary)
                }
            } else if !guestStars.isEmpty {
                castSection
            }
        }
    }

    private func crewRow(_ label: String, _ names: [String]) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .tracking(1)
                .foregroundColor(MoonlitTheme.textTertiary)
                .frame(width: 74, alignment: .leading)
                .padding(.top, 1)
            Text(names.joined(separator: ", "))
                .font(.system(size: 12.5))
                .foregroundColor(MoonlitTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var castSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Guest Stars · \(guestStars.count)")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top), count: 5),
                alignment: .leading, spacing: 16
            ) {
                ForEach(guestStars) { person in
                    castCell(person)
                }
            }
        }
    }

    private func castCell(_ person: Person) -> some View {
        VStack(spacing: 5) {
            Group {
                if let url = person.photo.flatMap(URL.init) {
                    CachedAsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        castPlaceholder
                    }
                } else {
                    castPlaceholder
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(Circle())

            Text(person.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            if let character = person.character, !character.isEmpty {
                Text(character)
                    .font(.system(size: 10.5))
                    .foregroundColor(MoonlitTheme.textTertiary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var castPlaceholder: some View {
        Circle()
            .fill(MoonlitTheme.surfaceElevated)
            .overlay(Image(systemName: "person.fill").foregroundColor(.white.opacity(0.2)))
    }

    // MARK: - Data

    private func loadEpisodeExtras() async {
        if stillURL == nil, let poster = await MetaRepository.shared.fetchEpisodePoster(
            seriesId: seriesId, season: seasonNumber, episode: episodeNumber
        ) {
            stillURL = URL(string: poster)
        }
        guard guestStars.isEmpty else { return }
        isLoadingCredits = true
        let credits = await MetaRepository.shared.fetchEpisodeCredits(
            seriesId: seriesId, season: seasonNumber, episode: episodeNumber
        )
        guestStars = credits.cast
        guestStarIDs = credits.guestStarIDs
        directors = credits.directors
        writers = credits.writers
        isLoadingCredits = false
    }
}
