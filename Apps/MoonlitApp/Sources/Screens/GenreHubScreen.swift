import SwiftUI
import MoonlitCore

/// A sectioned "genre room" for iOS: franchise/sub-genre/decade folder rails from
/// `GenreCatalog`, plus bundled browse rails (New / Popular / Top …). Pushed onto the
/// ambient NavigationStack; tiles push the existing FolderScreen / DetailScreen.
struct GenreHubScreen: View {
    let genre: String
    var mediaKind: MediaType? = nil

    @StateObject private var catalogRepo = CatalogRepository.shared
    @StateObject private var collectionRepo = CollectionRepository.shared

    @State private var browseRails: [GenreCatalog.LoadedBrowseRail] = []
    @State private var isLoading = true

    @State private var selectedFolder: CatalogRow?
    @State private var showFolder = false
    @State private var selectedMedia: MetaPreview?
    @State private var showDetail = false

    // Computed live from collectionRepo so sections update automatically when
    // the background Supabase refresh populates the Horror sub-collections.
    private var sectionRows: [CatalogRow] {
        GenreCatalog.sections(for: genre, in: collectionRepo.organized).map { $0.asRow() }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 26) {
                Text(genre)
                    .font(.system(size: 32, weight: .heavy))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                ForEach(sectionRows) { row in
                    rail(title: row.title, row: row)
                }

                ForEach(browseRails) { railContent in
                    rail(
                        title: railContent.title,
                        row: CatalogRow(id: railContent.id, title: railContent.title, items: railContent.items, tileShape: "poster")
                    )
                }

                // Only spin when there is genuinely nothing to look at. Once any
                // rail has landed, further loading happens quietly behind content.
                if isLoading && browseRails.isEmpty {
                    HStack { Spacer(); ProgressView().tint(.white); Spacer() }
                        .padding(.top, 40)
                }

                if !isLoading && sectionRows.isEmpty && browseRails.isEmpty {
                    Text("Nothing here yet")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.5))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                }

                Spacer().frame(height: 32)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle(genre)
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .task(id: genre) { await load() }
        .navigationDestination(isPresented: $showFolder) {
            if let folder = selectedFolder { FolderScreen(row: folder) }
        }
        .navigationDestination(isPresented: $showDetail) {
            if let media = selectedMedia {
                DetailScreen(mediaId: media.id, type: media.type.rawValue, name: media.name)
            }
        }
    }

    private func rail(title: String, row: CatalogRow) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 19, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(Array(row.items.enumerated()), id: \.element.id) { index, item in
                        ContentCard(item: item, row: row, index: index)
                            .onTapGesture { tap(item) }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func tap(_ item: MetaPreview) {
        if item.id.hasPrefix("folder_") {
            selectedFolder = catalogRepo.allFolderRows[item.id] ?? CatalogRow(
                id: item.id, title: item.name, items: [],
                tileShape: item.posterShape?.rawValue ?? "poster",
                coverImage: item.artworkString(preferring: .portrait)
            )
            showFolder = true
        } else {
            selectedMedia = item
            showDetail = true
        }
    }

    private func load() async {
        // Stale-while-revalidate: paint whatever we already have on the first
        // frame, then refresh behind it. A revisit within TTL never shows a
        // spinner at all.
        if let warm = catalogRepo.cachedGenreHub(genre: genre, mediaKind: mediaKind) {
            browseRails = warm.browse
            isLoading = false
        } else {
            isLoading = true
        }

        let hub = await catalogRepo.loadGenreHubProgressive(
            genre: genre,
            collectionRepo: collectionRepo,
            addons: AddonRepository.shared.enabledAddons,
            mediaKind: mediaKind,
            onPartial: { partial in
                merge(partial)
                isLoading = false
            }
        )
        merge(hub.browse)
        isLoading = false
    }

    /// Upserts rails by id, preserving first-seen order, so a partial batch never
    /// wipes rails that already landed.
    private func merge(_ incoming: [GenreCatalog.LoadedBrowseRail]) {
        guard !incoming.isEmpty else { return }
        var merged = browseRails
        for rail in incoming {
            if let index = merged.firstIndex(where: { $0.id == rail.id }) {
                merged[index] = rail
            } else {
                merged.append(rail)
            }
        }
        browseRails = merged
    }
}
