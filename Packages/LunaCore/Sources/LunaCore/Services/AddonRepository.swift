import Foundation

@MainActor
public class AddonRepository: ObservableObject {
    public static let shared = AddonRepository()

    @Published public var managedAddons: [ManagedAddon] = []
    @Published public var isLoading = false
    @Published public var errorMessage: String?

    private let syncService = SyncService()
    private var currentProfileId: String?

    // Caches parsed manifests for 5 minutes so repeated loads (e.g. tab switches)
    // don't re-hit the network. AIOMetadata sends no-store headers so URLCache
    // doesn't help here; we cache at the app layer instead.
    private nonisolated(unsafe) static var manifestCache: [String: (AddonManifest, Date)] = [:]
    private static let manifestTTL: TimeInterval = 300
    private var systemAddonUrl: String?

    private init() {}

    /// URLs that are provided automatically (defaults + admin system addon) and must
    /// NOT be written back into the per-user `installed_addons` table. Mirrors the web
    /// app, which merges these in-memory and persists only user-added extras.
    private var managedURLs: Set<String> {
        var set = Set(LunaConfig.defaultAddons)
        if let systemAddonUrl { set.insert(systemAddonUrl) }
        return set
    }

    /// The user's own installed addons — everything except defaults and the system addon.
    public var userAddons: [ManagedAddon] {
        managedAddons.filter { !managedURLs.contains($0.manifestUrl) }
    }

    /// True when this addon comes from defaults or the admin system addon (not user-added).
    public func isManaged(_ addon: ManagedAddon) -> Bool {
        managedURLs.contains(addon.manifestUrl)
    }

    public func loadAddons(profileId: String, systemAddonUrl: String? = nil) async {
        self.currentProfileId = profileId
        self.systemAddonUrl = systemAddonUrl
        isLoading = true
        defer { isLoading = false }

        let remoteUrls = (try? await syncService.pullAddons(profileId: profileId)) ?? []
        if remoteUrls.isEmpty {
            print("[Luna] No remote addons found for profile \(profileId), using defaults only.")
        }
        // Always include defaults; append any user extras that aren't in defaults
        var merged = LunaConfig.defaultAddons
        for url in remoteUrls where !merged.contains(url) {
            merged.append(url)
        }
        if let systemUrl = systemAddonUrl, !merged.contains(systemUrl) {
            merged.insert(systemUrl, at: 0)
        }
        await refreshFromUrls(merged)
    }

    public func refreshFromUrls(_ urls: [String]) async {
        var addons: [ManagedAddon] = []
        var fetchErrors: [String] = []
        let existing = managedAddons

        await withTaskGroup(of: ManagedAddon?.self) { group in
            for (index, url) in urls.enumerated() {
                group.addTask {
                    do {
                        let manifest = try await self.fetchManifest(url: url)
                        return ManagedAddon(
                            manifest: manifest,
                            manifestUrl: url,
                            enabled: true,
                            sortOrder: index
                        )
                    } catch {
                        print("[Luna] Addon fetch failed: \(url) — \(error.localizedDescription)")
                        if let found = existing.first(where: { $0.manifestUrl == url }) {
                            var copy = found
                            copy.errorMessage = error.localizedDescription
                            return copy
                        }
                        return nil
                    }
                }
            }

            for await addon in group {
                if let addon = addon {
                    addons.append(addon)
                }
            }
        }

        if addons.isEmpty, !urls.isEmpty {
            errorMessage = "Failed to load any addons. Check your connection."
            print("[Luna] All addon fetches failed. \(urls.count) URLs attempted.")
        } else if !addons.isEmpty {
            errorMessage = nil
        }

        addons.sort { $0.sortOrder < $1.sortOrder }
        self.managedAddons = addons
    }

    private func fetchManifest(url: String) async throws -> AddonManifest {
        // Return cached manifest if fresh (server sends no-store so URLCache is useless)
        if let (cached, stamp) = AddonRepository.manifestCache[url],
           Date().timeIntervalSince(stamp) < AddonRepository.manifestTTL {
            return cached
        }
        // No cache-buster: the timestamp suffix was defeating ETags on every launch
        let text = try await StremioHTTPClient.shared.getText(url: url)
        let manifest = try AddonManifestParser.parse(json: text, manifestUrl: url)
        AddonRepository.manifestCache[url] = (manifest, Date())
        return manifest
    }

    public func installAddon(url: String) async {
        guard !managedAddons.contains(where: { $0.manifestUrl == url }) else { return }
        do {
            let manifest = try await fetchManifest(url: url)
            let addon = ManagedAddon(
                manifest: manifest,
                manifestUrl: url,
                enabled: true,
                sortOrder: managedAddons.count
            )
            managedAddons.append(addon)
            await persistAddons()
        } catch {
            errorMessage = "Failed to install addon: \(error.localizedDescription)"
        }
    }

    public func removeAddon(url: String) {
        managedAddons.removeAll { $0.manifestUrl == url }
        Task { await persistAddons() }
    }

    public func toggleAddon(url: String) {
        if let index = managedAddons.firstIndex(where: { $0.manifestUrl == url }) {
            managedAddons[index].enabled.toggle()
            Task { await persistAddons() }
        }
    }

    public func reorderAddons(from source: IndexSet, to destination: Int) {
        managedAddons.move(fromOffsets: source, toOffset: destination)
        for i in managedAddons.indices {
            managedAddons[i].sortOrder = i
        }
        Task { await persistAddons() }
    }

    private func persistAddons() async {
        guard let profileId = currentProfileId else { return }
        // Persist only user-added addons. Defaults and the system addon are merged
        // in-memory on load, so writing them here would pollute the per-user table
        // and pin stale defaults forever. Matches LunaWebV2's saveInstalledAddons.
        let urls = userAddons.map { $0.manifestUrl }
        try? await syncService.pushAddons(profileId: profileId, addonUrls: urls)
    }

    public var enabledAddons: [AddonManifest] {
        managedAddons.filter { $0.enabled }.map { $0.manifest }
    }

    public var enabledAddonsForType: [MediaType: [AddonManifest]] {
        var result: [MediaType: [AddonManifest]] = [:]
        for addon in enabledAddons {
            guard let types = addon.types else { continue }
            for typeStr in types {
                if let mediaType = MediaType(rawValue: typeStr) {
                    result[mediaType, default: []].append(addon)
                }
            }
        }
        return result
    }

    public func addonForCatalog(catalogId: String) -> AddonManifest? {
        for addon in managedAddons where addon.enabled {
            if let catalogs = addon.manifest.catalogs {
                if catalogs.contains(where: { $0.id == catalogId }) {
                    return addon.manifest
                }
            }
        }
        return nil
    }

    public func findAddonWithMetaResource(type: String?) -> [AddonManifest] {
        enabledAddons.filter { addon in
            guard addon.hasResource("meta") else { return false }
            if let type = type, let types = addon.types {
                return types.contains(type)
            }
            return true
        }
    }
}
