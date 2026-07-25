import SwiftUI
import MoonlitCore

/// "About this title" — the big in-player modal from a neutral cast-modal:
/// backdrop bleeding across the top, poster, ratings, genre chips, action
/// buttons, overview, crew rows, a cast strip, and More Like This. Opened by
/// the info button beside the player's title for movies and series alike.
struct TitleInfoPanel: View {
    let title: String
    let mediaId: String
    let mediaType: String
    let posterURL: URL?
    let backgroundURL: URL?
    let onClose: () -> Void
    var onOpenFullDetails: (() -> Void)?
    /// Series only — closes the modal and opens the in-player episodes panel.
    var onShowEpisodes: (() -> Void)?
    /// Open a different title's full details (More Like This tap).
    var onOpenMeta: ((MetaPreview) -> Void)?

    @State private var detail: MetaDetail?
    @State private var selectedPerson: Person?
    @State private var appeared = false

    private var isSeries: Bool { mediaType != "movie" }

    private var seasonCount: Int? {
        guard let seasons = detail?.seasons?.filter({ $0.number != 0 }), !seasons.isEmpty else { return nil }
        return seasons.count
    }

    private var relatedItems: [MetaPreview] {
        detail?.moreLikeThis ?? detail?.recommendations ?? []
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(0.68)
                    .background(.ultraThinMaterial)
                    .ignoresSafeArea()
                    .onTapGesture { onClose() }

                card
                    .frame(maxWidth: min(geo.size.width * 0.78, 980))
                    .frame(maxHeight: geo.size.height * 0.88)
                    .scaleEffect(appeared ? 1 : 0.97)
                    .padding(24)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .opacity(appeared ? 1 : 0)
        .ignoresSafeArea()
        .onAppear { withAnimation(.easeOut(duration: 0.22)) { appeared = true } }
        .task { await loadDetail() }
        .sheet(item: $selectedPerson) { person in
            MacActorBioView(name: person.name, tmdbPersonId: Int(person.id), onBack: { selectedPerson = nil })
                .frame(minWidth: 520, minHeight: 520)
        }
    }

    // MARK: - Card

    private var card: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                heroSection
                bodySection
            }
        }
        .background(Color(red: 0.055, green: 0.05, blue: 0.047))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.09), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.7), radius: 50, y: 24)
    }

    // MARK: - Hero (backdrop bleeding across the top)

    private var heroSection: some View {
        ZStack(alignment: .topLeading) {
            // Backdrop + fades — sized by the content laid over it.
            GeometryReader { _ in
                ZStack {
                    if let url = (detail?.background).flatMap(URL.init) ?? backgroundURL {
                        CachedAsyncImage(url: url) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Color.white.opacity(0.03)
                        }
                    } else {
                        Color.white.opacity(0.03)
                    }
                    LinearGradient(
                        colors: [Color(red: 0.055, green: 0.05, blue: 0.047).opacity(0.85), .clear],
                        startPoint: .leading, endPoint: .trailing
                    )
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.15),
                            .init(color: Color(red: 0.055, green: 0.05, blue: 0.047), location: 1.0),
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                }
            }
            .clipped()

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("ABOUT THIS TITLE")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(3)
                        .foregroundColor(.white.opacity(0.5))
                    Spacer()
                    circleButton("xmark", action: onClose)
                }
                .padding(.top, 18)

                HStack(alignment: .top, spacing: 20) {
                    poster
                    VStack(alignment: .leading, spacing: 9) {
                        Text(detail?.name ?? title)
                            .font(.system(size: 30, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(2)

                        HStack(spacing: 12) {
                            if let year = detail?.releaseInfo {
                                Text(year)
                            }
                            if let seasonCount {
                                Text("\(seasonCount) season\(seasonCount == 1 ? "" : "s")")
                            } else if let runtime = detail?.runtime, !runtime.isEmpty {
                                Text(runtime)
                            }
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.65))

                        if let rating = detail?.imdbRating {
                            HStack(spacing: 6) {
                                Text("IMDb")
                                    .font(.system(size: 9, weight: .black))
                                    .foregroundColor(.black)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color(red: 0.91, green: 0.72, blue: 0.03), in: RoundedRectangle(cornerRadius: 3))
                                Text(rating)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.white.opacity(0.9))
                            }
                        }

                        if let genres = detail?.genres, !genres.isEmpty {
                            HStack(spacing: 7) {
                                ForEach(genres.prefix(3), id: \.self) { genre in
                                    Text(genre)
                                        .font(.system(size: 11.5, weight: .medium))
                                        .foregroundColor(.white.opacity(0.75))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color.white.opacity(0.08), in: Capsule())
                                }
                            }
                        }

                        actionButtons
                            .padding(.top, 4)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 4)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 9) {
            if isSeries, let onShowEpisodes {
                Button(action: onShowEpisodes) {
                    HStack(spacing: 7) {
                        Image(systemName: "play.fill")
                        Text("Episodes")
                    }
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Color.white, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            if let onOpenFullDetails {
                Button(action: onOpenFullDetails) {
                    HStack(spacing: 7) {
                        Text(isSeries ? "All episodes & details" : "Full details")
                        Image(systemName: "arrow.right")
                    }
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.1), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var poster: some View {
        Group {
            if let url = (detail?.poster).flatMap(URL.init) ?? posterURL {
                CachedAsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.white.opacity(0.05)
                }
            } else {
                Color.white.opacity(0.05)
            }
        }
        .frame(width: 132, height: 198)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.55), radius: 18, y: 8)
    }

    private func circleButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.85))
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.white.opacity(0.1)))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Body

    private var bodySection: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let overview = detail?.description, !overview.isEmpty {
                Text(overview)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.72))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 7) {
                crewRow("DIRECTOR", detail?.director)
                crewRow("CREATOR", detail?.creators)
                crewRow("WRITER", detail?.writer)
            }

            if let cast = detail?.cast, !cast.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    sectionLabel("CAST", count: cast.count)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(cast.prefix(15)) { person in
                                castCard(person)
                            }
                        }
                    }
                }
            }

            if !relatedItems.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    sectionLabel("MORE LIKE THIS", count: nil)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(relatedItems.prefix(12)) { item in
                                Button { onOpenMeta?(item) } label: {
                                    Group {
                                        if let url = item.artworkURL(preferring: .portrait) {
                                            CachedAsyncImage(url: url) { img in
                                                img.resizable().scaledToFill()
                                            } placeholder: {
                                                Color.white.opacity(0.05)
                                            }
                                        } else {
                                            Color.white.opacity(0.05)
                                        }
                                    }
                                    .frame(width: 92, height: 138)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 24)
    }

    @ViewBuilder
    private func crewRow(_ label: String, _ people: [Person]?) -> some View {
        if let people, !people.isEmpty {
            HStack(alignment: .top, spacing: 12) {
                Text(label)
                    .font(.system(size: 9.5, weight: .bold))
                    .tracking(1.6)
                    .foregroundColor(.white.opacity(0.4))
                    .frame(width: 68, alignment: .leading)
                    .padding(.top, 2)
                Text(people.prefix(6).map(\.name).joined(separator: ", "))
                    .font(.system(size: 12.5))
                    .foregroundColor(.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func sectionLabel(_ text: String, count: Int?) -> some View {
        HStack(spacing: 7) {
            Text(text)
                .font(.system(size: 10.5, weight: .bold))
                .tracking(2)
                .foregroundColor(.white.opacity(0.45))
            if let count {
                Text("\(count)")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(.white.opacity(0.28))
            }
        }
    }

    private func castCard(_ person: Person) -> some View {
        Button { selectedPerson = person } label: {
            VStack(alignment: .leading, spacing: 6) {
                Group {
                    if let url = person.photo.flatMap(URL.init) {
                        CachedAsyncImage(url: url) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Color.white.opacity(0.06)
                        }
                    } else {
                        Color.white.opacity(0.06)
                            .overlay(Image(systemName: "person.fill").foregroundColor(.white.opacity(0.2)))
                    }
                }
                .frame(width: 96, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                Text(person.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                if let character = person.character, !character.isEmpty {
                    Text(character)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.45))
                        .lineLimit(1)
                }
            }
            .frame(width: 96)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Data

    private func loadDetail() async {
        guard detail == nil else { return }
        let normalizedType = mediaType == "movie" ? "movie" : "series"
        let addons = AddonRepository.shared.findAddonWithMetaResource(type: normalizedType)
        detail = await MetaRepository.shared.fetchDetail(type: normalizedType, id: mediaId, addons: addons)
    }
}
