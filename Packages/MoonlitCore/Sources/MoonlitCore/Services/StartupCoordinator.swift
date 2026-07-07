import Foundation

@globalActor public actor StartupCoordinator: GlobalActor {
    public static let shared = StartupCoordinator()

    public enum Phase: Sendable { case phase1, phase2, phase3 }

    private var completedPhases: Set<Phase> = []

    public var catalogRows: [CatalogRow] = []
    public var collectionRows: [CatalogRow] = []
    public var allFolderRows: [String: CatalogRow] = [:]

    private var phaseContinuations: [Phase: [CheckedContinuation<Void, Never>]] = [
        .phase1: [], .phase2: [], .phase3: []
    ]

    private init() {}

    private func prerequisitesSatisfied(for phase: Phase) -> Bool {
        let order: [Phase] = [.phase1, .phase2, .phase3]
        for p in order {
            if p == phase { break }
            if !completedPhases.contains(p) { return false }
        }
        return true
    }

    public func startPhase1(
        profileId: String,
        collectionRepo: CollectionRepository,
        addonRepo: AddonRepository,
        catalogRepo: CatalogRepository,
        homeRepo: HomeRepository,
        recsService: RecommendationsService,
        libraryRepo: LibraryRepository
    ) {
        guard prerequisitesSatisfied(for: .phase1), !completedPhases.contains(.phase1) else { return }

        Task {
            async let organizerDone: Void = {
                guard let bundledURL = Bundle.main.url(forResource: "home-organizer", withExtension: "json"),
                      let bundledData = try? Data(contentsOf: bundledURL) else { return }
                await collectionRepo.loadOrganizer(
                    bundledData: bundledData,
                    remoteURL: MoonlitConfig.homeOrganizerRemoteURL.flatMap(URL.init),
                    store: CollectionOrganizerStore.shared
                )
            }()
            async let addonsDone: Void = addonRepo.loadAddons(profileId: profileId)

            _ = await (organizerDone, addonsDone)
            completedPhases.insert(.phase1)
            resumeContinuations(for: .phase1)

            let addons = await addonRepo.enabledAddons
            async let catalogsDone: Void = {
                if await collectionRepo.collections.isEmpty {
                    await catalogRepo.loadAllCatalogs(addons: addons)
                } else {
                    await catalogRepo.loadFromCollections(
                        collectionRepo: collectionRepo,
                        addons: addons,
                        mode: .replaceCache
                    )
                }
            }()
            async let recsDone: Void = recsService.load(profileId: profileId)
            async let libraryDone: Void = libraryRepo.loadLibrary(profileId: profileId)
            async let cwDone: Void = homeRepo.loadContinueWatching(profileId: profileId)

            _ = await (catalogsDone, recsDone, libraryDone, cwDone)

            catalogRows = await catalogRepo.catalogRows
            collectionRows = await catalogRepo.collectionRows
            allFolderRows = await catalogRepo.allFolderRows

            completedPhases.insert(.phase2)
            resumeContinuations(for: .phase2)
        }
    }

    public func startPhase3(
        catalogRepo: CatalogRepository,
        collectionRepo: CollectionRepository,
        addonRepo: AddonRepository
    ) {
        guard prerequisitesSatisfied(for: .phase3), !completedPhases.contains(.phase3) else { return }

        Task(priority: .background) {
            let collections = await collectionRepo.collections
            let pinned = collections.filter { $0.pinToTop == true }
            let others = collections.filter { $0.pinToTop != true }
            let ordered = (pinned + others).prefix(5)
            let addons = await addonRepo.enabledAddons
            let folders = await collectionRepo.folders

            for collection in ordered {
                guard Task.isCancelled == false else { break }
                let matching = folders.filter { $0.collectionId == collection.id }
                for folder in matching.prefix(3) {
                    guard Task.isCancelled == false else { break }
                    await catalogRepo.loadFolderItems(
                        folderId: folder.id,
                        collectionRepo: collectionRepo,
                        addons: addons
                    )
                }
            }
            completedPhases.insert(.phase3)
            resumeContinuations(for: .phase3)
        }
    }

    public func waitForPhase(_ phase: Phase) async {
        if completedPhases.contains(phase) { return }
        await withCheckedContinuation { cont in
            var arr = phaseContinuations[phase] ?? []
            arr.append(cont)
            phaseContinuations[phase] = arr
        }
    }

    public func isPhaseComplete(_ phase: Phase) -> Bool {
        completedPhases.contains(phase)
    }

    private func resumeContinuations(for phase: Phase) {
        let conts = phaseContinuations[phase] ?? []
        phaseContinuations[phase] = []
        for cont in conts { cont.resume() }
    }
}
