import SwiftUI
import MoonlitCore

/// Episode info popup — a centered dark card over a dimmed player. Shows the
/// episode still, the episode's air date / rating / runtime, its synopsis, the
/// episode's director + writer, and a grid of the episode cast with guest stars
/// flagged. Scrolls internally; dismissed via the close button or a scrim tap.
struct EpisodeInfoPanel: View {
    let seriesTitle: String
    let episode: MetaVideo
    let episodePosterURL: URL?
    let backgroundURL: URL?
    let directors: [String]
    let writers: [String]
    let guestStarIDs: Set<String>
    let isLoadingGuestStars: Bool
    let onClose: () -> Void

    @State private var appeared = false

    private var people: [Person] { episode.guestStars ?? [] }

    private let castColumns = Array(
        repeating: GridItem(.flexible(), spacing: 8, alignment: .top),
        count: 5
    )

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
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(0.62)
                    .ignoresSafeArea()
                    .onTapGesture { onClose() }

                card
                    .frame(maxWidth: 560)
                    .frame(maxHeight: geo.size.height * 0.86)
                    .scaleEffect(appeared ? 1 : 0.96)
                    .padding(24)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .opacity(appeared ? 1 : 0)
        .ignoresSafeArea()
        .onAppear { withAnimation(.easeOut(duration: 0.22)) { appeared = true } }
    }

    // MARK: - Card

    private var card: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                header
                stillBanner
                metaAndOverview
                crewRows
                castSection
            }
            .padding(22)
        }
        .harborPanel(cornerRadius: 18)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("ABOUT THIS EPISODE")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(2.4)
                    .foregroundColor(PlayerPalette.inkSubtle)
                Text(episode.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(PlayerPalette.ink)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            closeButton
        }
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(PlayerPalette.inkMuted)
                .frame(width: 36, height: 36)
                .background(Circle().fill(PlayerPalette.elevated))
                .overlay(Circle().strokeBorder(PlayerPalette.edgeSoft, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Still banner

    private var stillBanner: some View {
        ZStack(alignment: .bottomLeading) {
            stillImage

            LinearGradient(
                colors: [Color.black.opacity(0.55), .clear],
                startPoint: .bottom, endPoint: .center
            )

            Text("S\(episode.season ?? 0) · E\(episode.episode ?? 0)")
                .font(.system(size: 11, weight: .bold))
                .tracking(0.8)
                .foregroundColor(.white.opacity(0.92))
                .shadow(color: .black.opacity(0.7), radius: 3, x: 0, y: 1)
                .padding(12)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 168)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(PlayerPalette.edgeSoft, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var stillImage: some View {
        if let url = episodePosterURL ?? backgroundURL ?? episode.thumbnail.flatMap(URL.init) {
            CachedAsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                PlayerPalette.surface
            }
        } else {
            PlayerPalette.surface.overlay(
                Image(systemName: "photo")
                    .font(.system(size: 24))
                    .foregroundColor(PlayerPalette.inkSubtle)
            )
        }
    }

    // MARK: - Meta + overview

    private var metaAndOverview: some View {
        VStack(alignment: .leading, spacing: 12) {
            metaRow
            Text("\(seriesTitle) · Season \(episode.season ?? 0)")
                .font(.system(size: 11.5))
                .foregroundColor(PlayerPalette.inkSubtle)

            if let overview = episode.overview, !overview.isEmpty {
                Text(overview)
                    .font(.system(size: 13))
                    .foregroundColor(PlayerPalette.inkMuted)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var metaRow: some View {
        let hasRating = (episode.voteAverage ?? 0) > 0
        let hasRuntime = !(episode.runtime ?? "").isEmpty
        return HStack(spacing: 8) {
            if let airDate = formattedAirDate {
                metaLabel("calendar", "Aired \(airDate)")
            }
            if hasRating, let rating = episode.voteAverage {
                if formattedAirDate != nil { metaDot }
                HStack(spacing: 3) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 11))
                        .foregroundColor(MoonlitTheme.harborGold)
                    Text(String(format: "%.1f", rating))
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(MoonlitTheme.harborGold)
                }
            }
            if hasRuntime, let runtime = episode.runtime {
                if formattedAirDate != nil || hasRating { metaDot }
                metaLabel("clock", runtime)
            }
            Spacer(minLength: 0)
        }
    }

    private func metaLabel(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(PlayerPalette.inkMuted)
            Text(text)
                .font(.system(size: 12.5))
                .foregroundColor(PlayerPalette.inkMuted)
        }
    }

    private var metaDot: some View {
        Text("·")
            .font(.system(size: 12.5))
            .foregroundColor(PlayerPalette.inkSubtle)
    }

    // MARK: - Crew

    @ViewBuilder
    private var crewRows: some View {
        if !directors.isEmpty || !writers.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                if !directors.isEmpty { crewRow("DIRECTOR", directors) }
                if !writers.isEmpty { crewRow("WRITER", writers) }
            }
        }
    }

    private func crewRow(_ label: String, _ names: [String]) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .tracking(1)
                .foregroundColor(PlayerPalette.inkSubtle)
                .frame(width: 74, alignment: .leading)
                .padding(.top, 1)
            Text(names.joined(separator: ", "))
                .font(.system(size: 12.5))
                .foregroundColor(PlayerPalette.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Cast

    private var castSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            Rectangle()
                .fill(PlayerPalette.edgeSoft)
                .frame(height: 1)

            HStack(spacing: 6) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 12))
                    .foregroundColor(PlayerPalette.inkSubtle)
                Text("CAST & GUEST STARS")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.6)
                    .foregroundColor(PlayerPalette.inkSubtle)
            }

            if isLoadingGuestStars && people.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading cast…")
                        .font(.system(size: 13))
                        .foregroundColor(PlayerPalette.inkSubtle)
                }
                .padding(.vertical, 4)
            } else if !people.isEmpty {
                LazyVGrid(columns: castColumns, alignment: .leading, spacing: 16) {
                    ForEach(people) { person in
                        castCell(person)
                    }
                }
            }
        }
    }

    private func castCell(_ person: Person) -> some View {
        VStack(spacing: 5) {
            avatar(person)

            if guestStarIDs.contains(person.id) {
                Text("GUEST")
                    .font(.system(size: 8, weight: .bold))
                    .tracking(0.5)
                    .foregroundColor(MoonlitTheme.harborGold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(MoonlitTheme.harborGold.opacity(0.14)))
            }

            Text(person.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(PlayerPalette.ink)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            if let character = person.character, !character.isEmpty {
                Text(character)
                    .font(.system(size: 10.5))
                    .foregroundColor(PlayerPalette.inkSubtle)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private func avatar(_ person: Person) -> some View {
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
        .frame(width: 54, height: 54)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(PlayerPalette.edgeSoft, lineWidth: 1))
    }

    private var castPlaceholder: some View {
        Circle()
            .fill(PlayerPalette.raised)
            .overlay(
                Image(systemName: "person.fill")
                    .font(.system(size: 18))
                    .foregroundColor(PlayerPalette.inkSubtle)
            )
    }
}
