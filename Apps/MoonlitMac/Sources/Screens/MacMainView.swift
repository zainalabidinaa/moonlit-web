import SwiftUI
import MoonlitCore

struct MacMainView: View {
    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var roleManager: RoleManager
    @StateObject private var addonRepo = AddonRepository.shared
    @StateObject private var catalogRepo = CatalogRepository.shared
    @StateObject private var collectionRepo = CollectionRepository.shared
    @State private var selectedTab: MacMainTab = .home
    @State private var detailItem: DetailItem?
    @State private var folderItem: FolderItem?
    @State private var genreHub: String?
    @State private var genreHubMediaKind: MediaType?
    @State private var streamingServiceRow: CatalogRow?
    @State private var actorItem: ActorItem?
    @State private var languageHubIso: String?
    @State private var languageHubName: String?
    @State private var awardHub: AwardHubItem?
    @State private var isSearchPresented = false

    struct DetailItem: Identifiable {
        let id: String
        let type: String
        let name: String
    }

    struct ActorItem: Identifiable {
        let id: String
        let name: String
    }

    struct FolderItem: Identifiable {
        let id: String
        let row: CatalogRow
    }

    struct AwardHubItem: Identifiable {
        let id: String
        let body: AwardBody
        let row: CatalogRow
    }

    private var isShowingNavBar: Bool {
        detailItem == nil && folderItem == nil && genreHub == nil && streamingServiceRow == nil && actorItem == nil && languageHubIso == nil && awardHub == nil
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .home:
            MacHomeView(onSelectMedia: { item in
                handleSelect(item)
            }, onSelectFolder: { row in
                openFolderRow(row)
            }, onSelectGenre: { genre, kind in
                genreHub = genre
                genreHubMediaKind = kind
            }, onSelectLanguage: { iso, name in
                languageHubIso = iso
                languageHubName = name
            })
        case .movies:
            MacMediaBrowseView(mediaKind: .movie, onSelectMedia: { item in
                openMedia(item)
            }, onSelectFolder: { row in
                folderItem = FolderItem(id: row.id, row: row)
            })
        case .series:
            MacMediaBrowseView(mediaKind: .series, onSelectMedia: { item in
                openMedia(item)
            }, onSelectFolder: { row in
                folderItem = FolderItem(id: row.id, row: row)
            })
        case .library:
            MacLibraryView(onSelectMedia: { item in
                detailItem = DetailItem(id: item.id, type: item.type.rawValue, name: item.name)
            })
        case .downloads:
            MacDownloadsView(onSelectMedia: { item in
                detailItem = DetailItem(id: item.id, type: item.type.rawValue, name: item.name)
            })
        case .settings: MacSettingsView()
        case .admin: MacSettingsView()
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            ZStack {
                tabContent
                    .opacity(isShowingNavBar ? 1 : 0)
                    .disabled(!isShowingNavBar)

                if let actor = actorItem {
                    MacActorBioView(name: actor.name, tmdbPersonId: nil, onBack: { actorItem = nil })
                        .background(MoonlitTheme.background)
                } else if let serviceRow = streamingServiceRow {
                    MacStreamingServiceView(row: serviceRow, onBack: { streamingServiceRow = nil }) { item in
                        handleSelect(item)
                    }
                    .background(MoonlitTheme.background)
                } else if let folder = folderItem {
                    MacFolderView(row: folder.row, onBack: { folderItem = nil }) { item in
                        handleSelect(item)
                    } onSelectFolder: { row in
                        openFolderRow(row)
                    }
                    .background(MoonlitTheme.background)
                } else if let detail = detailItem {
                    MacDetailView(
                        mediaId: detail.id,
                        type: detail.type,
                        name: detail.name,
                        onBack: { detailItem = nil },
                        onSelectActor: { person in
                            actorItem = ActorItem(id: person.id, name: person.name)
                        }
                    )
                    .background(MoonlitTheme.background)
                } else if let genre = genreHub {
                    MacGenreHubView(
                        genre: genre,
                        mediaKind: genreHubMediaKind,
                        onBack: { genreHub = nil; genreHubMediaKind = nil },
                        onSelectMedia: { item in openMedia(item) },
                        onSelectFolder: { row in openFolderRow(row) }
                    )
                    .background(MoonlitTheme.background)
                } else if let langIso = languageHubIso, let langName = languageHubName {
                    MacLanguageHubView(
                        iso: langIso,
                        name: langName,
                        onBack: { languageHubIso = nil; languageHubName = nil },
                        onSelectMedia: { item in openMedia(item) }
                    )
                    .background(MoonlitTheme.background)
                } else if let award = awardHub {
                    MacAwardHubView(
                        award: award.body,
                        row: award.row,
                        onBack: { awardHub = nil },
                        onSelectMedia: { item in openMedia(item) }
                    )
                    .background(MoonlitTheme.background)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if isShowingNavBar {
                PillNavBar(selectedTab: $selectedTab, onSearchTapped: { isSearchPresented = true })
            }

            if isSearchPresented {
                MacSearchOverlay(
                    onDismiss: { isSearchPresented = false },
                    onSelectMedia: { item in
                        isSearchPresented = false
                        detailItem = DetailItem(id: item.id, type: item.type.rawValue, name: item.name)
                    },
                    onSelectGenre: { genre in
                        isSearchPresented = false
                        genreHub = genre
                        genreHubMediaKind = nil
                    },
                    onJumpToTab: { tab in
                        isSearchPresented = false
                        detailItem = nil
                        folderItem = nil
                        genreHub = nil
                        streamingServiceRow = nil
                        actorItem = nil
                        languageHubIso = nil
                        languageHubName = nil
                        selectedTab = tab
                    }
                )
            }
        }
    }

    /// Tile tap from a row of mixed media/folder tiles. Genre browse folders open the
    /// genre hub; other folders open the folder view; media opens detail.
    private func handleSelect(_ item: MetaPreview) {
        guard item.id.hasPrefix("folder_") else {
            folderItem = nil
            genreHub = nil
            streamingServiceRow = nil
            languageHubIso = nil
            languageHubName = nil
            openMedia(item)
            return
        }
        let row = catalogRepo.allFolderRows[item.id] ?? CatalogRow(
            id: item.id,
            title: item.name,
            items: [],
            tileShape: item.posterShape?.rawValue ?? "poster",
            coverImage: item.artworkString(preferring: .portrait)
        )
        if collectionRepo.streamingServiceName(forFolderRowId: item.id) != nil {
            folderItem = nil
            detailItem = nil
            genreHub = nil
            genreHubMediaKind = nil
            languageHubIso = nil
            languageHubName = nil
            streamingServiceRow = row
            return
        }
        if let genre = collectionRepo.genreName(forFolderRowId: item.id) {
            folderItem = nil
            detailItem = nil
            streamingServiceRow = nil
            languageHubIso = nil
            languageHubName = nil
            genreHub = genre
            genreHubMediaKind = nil
            return
        }
        detailItem = nil
        genreHub = nil
        genreHubMediaKind = nil
        streamingServiceRow = nil
        languageHubIso = nil
        languageHubName = nil
        folderItem = FolderItem(id: item.id, row: row)
    }

    private func openFolderRow(_ row: CatalogRow) {
        if collectionRepo.streamingServiceName(forFolderRowId: row.id) != nil {
            folderItem = nil
            detailItem = nil
            genreHub = nil
            genreHubMediaKind = nil
            languageHubIso = nil
            languageHubName = nil
            awardHub = nil
            streamingServiceRow = row
            return
        }
        if let genre = collectionRepo.genreName(forFolderRowId: row.id) {
            folderItem = nil
            detailItem = nil
            streamingServiceRow = nil
            languageHubIso = nil
            languageHubName = nil
            awardHub = nil
            genreHub = genre
            genreHubMediaKind = nil
            return
        }
        // Award folders (Academy Awards, Golden Globes, BAFTA…) open the rich
        // cinematic awards hub instead of a plain grid.
        if let body = AwardBody.fromTitle(row.title) {
            detailItem = nil
            genreHub = nil
            genreHubMediaKind = nil
            streamingServiceRow = nil
            languageHubIso = nil
            languageHubName = nil
            folderItem = nil
            awardHub = AwardHubItem(id: row.id, body: body, row: row)
            return
        }
        detailItem = nil
        genreHub = nil
        genreHubMediaKind = nil
        streamingServiceRow = nil
        languageHubIso = nil
        languageHubName = nil
        awardHub = nil
        folderItem = FolderItem(id: row.id, row: row)
    }

    private func openMedia(_ item: MetaPreview) {
        folderItem = nil
        genreHub = nil
        genreHubMediaKind = nil
        streamingServiceRow = nil
        languageHubIso = nil
        languageHubName = nil
        detailItem = DetailItem(id: item.id, type: item.type.rawValue, name: item.name)
    }
}
