import SwiftUI
import LunaCore

struct DetailScreen: View {
    let mediaId: String
    let type: String
    let name: String

    @StateObject private var metaRepo = MetaRepository.shared
    @StateObject private var libraryRepo = LibraryRepository.shared
    @StateObject private var watchedRepo = WatchProgressRepository.shared
    @EnvironmentObject var profileManager: ProfileManager
    @StateObject private var addonRepo = AddonRepository.shared

    @State private var showStreamSelection = false
    @State private var selectedSeasonId: String? = nil

    var body: some View {
        ScrollView {
            if let detail = metaRepo.detail {
                VStack(alignment: .leading, spacing: 0) {
                    ZStack(alignment: .bottomLeading) {
                        if let bg = detail.background, let url = URL(string: bg) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let image):
                                    image.resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(height: 300)
                                        .clipped()
                                        .overlay(
                                            LinearGradient(
                                                colors: [.clear, LunaTheme.background],
                                                startPoint: .center,
                                                endPoint: .bottom
                                            )
                                        )
                                default:
                                    Color(LunaTheme.surfaceElevated).frame(height: 300)
                                }
                            }
                        } else {
                            Color(LunaTheme.surfaceElevated).frame(height: 200)
                        }

                        HStack(alignment: .bottom, spacing: 16) {
                            if let poster = detail.poster, let url = URL(string: poster) {
                                AsyncImage(url: url) { phase in
                                    if case .success(let image) = phase {
                                        image.resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(width: 100, height: 150)
                                            .cornerRadius(8)
                                    } else {
                                        Color(LunaTheme.surfaceElevated)
                                            .frame(width: 100, height: 150)
                                            .cornerRadius(8)
                                    }
                                }
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(detail.name)
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                if let info = detail.releaseInfo {
                                    Text(info)
                                        .font(.subheadline)
                                        .foregroundColor(LunaTheme.textSecondary)
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 16)
                    }

                    VStack(spacing: 16) {
                        HStack(spacing: 12) {
                            Button {
                                showStreamSelection = true
                            } label: {
                                HStack {
                                    Image(systemName: "play.fill")
                                    Text("Play")
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .glassProminentButtonStyle(tint: LunaTheme.accent, cornerRadius: 12)
                            }

                            Button {
                                Task {
                                    guard let profile = profileManager.currentProfile else { return }
                                    await libraryRepo.toggleLibrary(
                                        profileId: profile.id,
                                        mediaId: detail.id,
                                        mediaType: type,
                                        name: detail.name,
                                        poster: detail.poster
                                    )
                                }
                            } label: {
                                Image(systemName: libraryRepo.isInLibrary(mediaId: detail.id) ? "bookmark.fill" : "bookmark")
                                    .font(.title3)
                                    .padding()
                                    .glassCard(cornerRadius: 12, interactive: true)
                                    .foregroundColor(libraryRepo.isInLibrary(mediaId: detail.id) ? LunaTheme.accent : .white)
                            }

                            Button {
                                Task {
                                    guard let profile = profileManager.currentProfile else { return }
                                    if watchedRepo.isWatched(mediaId: detail.id) {
                                        await watchedRepo.markUnwatched(mediaId: detail.id)
                                    } else {
                                        await watchedRepo.markWatched(
                                            profileId: profile.id,
                                            mediaId: detail.id,
                                            mediaType: type,
                                            name: detail.name,
                                            poster: detail.poster
                                        )
                                    }
                                }
                            } label: {
                                Image(systemName: watchedRepo.isWatched(mediaId: detail.id) ? "checkmark.circle.fill" : "checkmark.circle")
                                    .font(.title3)
                                    .padding()
                                    .glassCard(cornerRadius: 12, interactive: true)
                                    .foregroundColor(watchedRepo.isWatched(mediaId: detail.id) ? .green : .white)
                            }
                        }
                        .padding(.horizontal)

                        if let description = detail.description, !description.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Overview")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                Text(description)
                                    .font(.body)
                                    .foregroundColor(LunaTheme.textSecondary)
                                    .lineLimit(6)
                            }
                            .padding(.horizontal)
                        }

                        if let genres = detail.genres, !genres.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Genres")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(genres, id: \.self) { genre in
                                            Text(genre)
                                                .font(.caption)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 6)
                                                .glassCapsule(interactive: true)
                                                .foregroundColor(LunaTheme.textSecondary)
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }

                        if let cast = detail.cast, !cast.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Cast")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 12) {
                                        ForEach(cast.prefix(20)) { person in
                                            VStack(spacing: 4) {
                                                Circle()
                                                    .glassCircle()
                                                    .frame(width: 56, height: 56)
                                                    .overlay(
                                                        Text(person.name.prefix(1))
                                                            .font(.headline)
                                                            .foregroundColor(LunaTheme.textSecondary)
                                                    )
                                                Text(person.name)
                                                    .font(.caption2)
                                                    .foregroundColor(LunaTheme.textSecondary)
                                                    .lineLimit(1)
                                                    .frame(width: 64)
                                            }
                                        }
                                    }
                                    .padding(.horizontal)
                                }
                                .padding(.horizontal, -16)
                            }
                            .padding(.horizontal)
                        }

                        if let links = detail.links, !links.isEmpty {
                            let networks = links.filter { $0.category?.lowercased() == "network" }
                            let studios = links.filter { $0.category?.lowercased() == "production" }

                            if !networks.isEmpty || !studios.isEmpty {
                                VStack(alignment: .leading, spacing: 16) {
                                    if !networks.isEmpty {
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text("NETWORK")
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundColor(LunaTheme.textTertiary)
                                                .tracking(1.5)
                                            ScrollView(.horizontal, showsIndicators: false) {
                                                HStack(spacing: 8) {
                                                    ForEach(networks) { link in
                                                        Text(link.name)
                                                            .font(.caption).fontWeight(.semibold)
                                                            .foregroundColor(LunaTheme.textSecondary)
                                                            .padding(.horizontal, 12).padding(.vertical, 7)
                                                            .glassCapsule(interactive: true)
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    if !studios.isEmpty {
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text("PRODUCTION")
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundColor(LunaTheme.textTertiary)
                                                .tracking(1.5)
                                            ScrollView(.horizontal, showsIndicators: false) {
                                                HStack(spacing: 8) {
                                                    ForEach(studios) { link in
                                                        Text(link.name)
                                                            .font(.caption).fontWeight(.semibold)
                                                            .foregroundColor(LunaTheme.textSecondary)
                                                            .padding(.horizontal, 12).padding(.vertical, 7)
                                                            .background(LunaTheme.surface)
                                                            .cornerRadius(8)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }

                        if let seasons = detail.seasons, !seasons.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Episodes")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .padding(.horizontal)

                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(seasons.sorted(by: { $0.number < $1.number })) { season in
                                            Button {
                                                selectedSeasonId = season.id
                                            } label: {
                                                Text("Season \(season.number)")
                                                    .font(.subheadline).fontWeight(.medium)
                                                    .padding(.horizontal, 16).padding(.vertical, 8)
                                                    .glassCapsule(interactive: true)
                                                    .foregroundColor(selectedSeasonId == season.id || (selectedSeasonId == nil && seasons.sorted(by: { $0.number < $1.number }).first?.id == season.id) ? .white : LunaTheme.textSecondary)
                                            }
                                        }
                                    }
                                    .padding(.horizontal)
                                }

                                if let activeSeason = seasons.first(where: { $0.id == (selectedSeasonId ?? seasons.sorted(by: { $0.number < $1.number }).first?.id) }),
                                   let episodes = activeSeason.episodes {
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        LazyHStack(spacing: 12) {
                                            ForEach(episodes) { ep in
                                                EpisodeCard(episode: ep) {
                                                    showStreamSelection = true
                                                }
                                            }
                                        }
                                        .padding(.horizontal)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.top, 16)
                }
            } else if metaRepo.isLoading {
                VStack {
                    Spacer().frame(height: 200)
                    ProgressView().tint(LunaTheme.accent)
                    Spacer()
                }
            } else if let error = metaRepo.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .padding()
            }
        }
        .background(LunaTheme.background)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showStreamSelection) {
            StreamSelectionScreen(
                mediaType: MediaType(rawValue: type) ?? .movie,
                mediaId: mediaId,
                mediaName: metaRepo.detail?.name ?? name,
                poster: metaRepo.detail?.poster,
                logo: metaRepo.detail?.logo
            )
        }
        .task {
            await metaRepo.loadDetail(
                type: type,
                id: mediaId,
                addons: addonRepo.findAddonWithMetaResource(type: type)
            )
            if let profile = profileManager.currentProfile {
                await libraryRepo.loadLibrary(profileId: profile.id)
                await watchedRepo.loadAll(profileId: profile.id)
            }
        }
    }
}

struct EpisodeCard: View {
    let episode: MetaVideo
    let onPlay: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(LunaTheme.surfaceElevated)
                    .frame(width: 208, height: 117)

                if let thumb = episode.thumbnail, let url = URL(string: thumb) {
                    AsyncImage(url: url) { phase in
                        if case .success(let img) = phase {
                            img.resizable().aspectRatio(contentMode: .fill)
                        }
                    }
                    .frame(width: 208, height: 117)
                    .clipped()
                    .cornerRadius(10)
                } else {
                    Image(systemName: "play.rectangle.fill")
                        .font(.title2)
                        .foregroundColor(LunaTheme.textTertiary)
                }

                Color.black.opacity(0.3)
                    .cornerRadius(10)
                Button(action: onPlay) {
                    Circle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Image(systemName: "play.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.white)
                                .offset(x: 1.5)
                        )
                }
            }
            .frame(width: 208, height: 117)

            if let epNum = episode.episode {
                Text("Episode \(epNum)")
                    .font(.caption2)
                    .foregroundColor(LunaTheme.textTertiary)
            }

            Text(episode.title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .lineLimit(1)
                .frame(width: 208, alignment: .leading)

            if let overview = episode.overview {
                Text(overview)
                    .font(.caption2)
                    .foregroundColor(LunaTheme.textSecondary)
                    .lineLimit(2)
                    .frame(width: 208, alignment: .leading)
            }
        }
    }
}

struct SeasonDetailScreen: View {
    let season: Season
    let seriesName: String

    var body: some View {
        List {
            if let episodes = season.episodes {
                ForEach(episodes) { episode in
                    HStack {
                        VStack(alignment: .leading) {
                            Text("E\(episode.episode ?? 0): \(episode.title)")
                                .foregroundColor(.white)
                            if let overview = episode.overview {
                                Text(overview)
                                    .font(.caption)
                                    .foregroundColor(LunaTheme.textSecondary)
                                    .lineLimit(2)
                            }
                        }
                        Spacer()
                        if let runtime = episode.runtime {
                            Text(runtime)
                                .font(.caption2)
                                .foregroundColor(LunaTheme.textTertiary)
                        }
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(LunaTheme.surface)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(LunaTheme.background)
        .navigationTitle(season.name ?? "Season \(season.number)")
    }
}
