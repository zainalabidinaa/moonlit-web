import Foundation

@MainActor
public class AddonRepository: ObservableObject {
    public static let shared = AddonRepository()

    @Published public var managedAddons: [ManagedAddon] = []
    @Published public var isLoading = false
    @Published public var errorMessage: String?

    private let syncService = SyncService.shared
    private var currentProfileId: String?

    // Caches parsed manifests for 5 minutes so repeated loads (e.g. tab switches)
    // don't re-hit the network. AIOMetadata sends no-store headers so URLCache
    // doesn't help here; we cache at the app layer instead.
    @MainActor
    private static var manifestCache: [String: (AddonManifest, Date)] = [:]
    private static let manifestTTL: TimeInterval = 300
    private var systemAddonUrl: String?
    private var disabledAddonUrls: Set<String> = []
    /// Admin-curated addons inherited via get_shared_addons(). Tracked so they are
    /// never written back into the user's own `installed_addons` (they aren't the
    /// user's; they're provisioned each load and stream-guarded).
    private var sharedAddonUrls: Set<String> = []

    private init() {}

    private func disabledKey(for profileId: String) -> String { "moonlit.disabledAddons.\(profileId)" }

    private func loadDisabledUrls(profileId: String) {
        let raw = UserDefaults.standard.stringArray(forKey: disabledKey(for: profileId)) ?? []
        disabledAddonUrls = Set(raw)
    }

    private func saveDisabledUrls(profileId: String) {
        UserDefaults.standard.set(Array(disabledAddonUrls), forKey: disabledKey(for: profileId))
    }

    /// URLs that are provided automatically (defaults + admin system addon) and must
    /// NOT be written back into the per-user `installed_addons` table. Mirrors the web
    /// app, which merges these in-memory and persists only user-added extras.
    private var managedURLs: Set<String> {
        var set = Set(MoonlitConfig.defaultAddons)
        if let systemAddonUrl { set.insert(systemAddonUrl) }
        set.formUnion(sharedAddonUrls)
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
        loadDisabledUrls(profileId: profileId)
        isLoading = true
        defer { isLoading = false }

        let remoteUrls = (try? await syncService.pullAddons(profileId: profileId)) ?? []
        if remoteUrls.isEmpty {
            print("[Moonlit] No remote addons found for profile \(profileId), using defaults only.")
        }
        // Always include defaults; append any user extras that aren't in defaults
        var merged = MoonlitConfig.defaultAddons
        for url in remoteUrls where !merged.contains(url) {
            merged.append(url)
        }
        #if os(macOS)
        // The admin-controlled `system_addon` is broadcast to every user and force-inserted
        // at the top of the list. It is provisioned ONLY on macOS. On iOS this path is
        // compiled out entirely: the App Store build must never let the backend deliver a
        // stream source to users (App Store Review Guidelines 2.3.1 / 5.2.3). On iOS the
        // addon list is only the bundled metadata/subtitle defaults plus addons the user
        // installs themselves; those sync per-user via `installed_addons` (owner-scoped RLS).
        if let systemUrl = systemAddonUrl, !merged.contains(systemUrl) {
            merged.insert(systemUrl, at: 0)
        }
        #endif

        // Shared/admin-curated addons: authenticated non-admin users inherit the
        // admin's own installed addons (via the get_shared_addons RPC). These are
        // STREAM-GUARDED below — any `stream` resource is stripped, so the admin
        // can provision catalog/metadata/subtitle addons to everyone but can never
        // deliver a stream source through this channel (guideline 5.2.3 / 2.3.1).
        // The admin themselves loads their own list directly, so they don't inherit.
        var streamGuardedUrls: Set<String> = []
        if ProfileManager.shared.isAuthenticated,
           ProfileManager.shared.currentProfile?.profileRole != .admin {
            let sharedUrls = (try? await syncService.pullSharedAddons()) ?? []
            for url in sharedUrls where !merged.contains(url) {
                merged.append(url)
                streamGuardedUrls.insert(url)
            }
        }
        self.sharedAddonUrls = streamGuardedUrls

        await refreshFromUrls(merged, streamGuardedUrls: streamGuardedUrls)
    }

    public func refreshFromUrls(_ urls: [String], streamGuardedUrls: Set<String> = []) async {
        var addons: [ManagedAddon] = []
        let existing = managedAddons

        let disabledSnapshot = disabledAddonUrls
        await withTaskGroup(of: ManagedAddon?.self) { group in
            for (index, url) in urls.enumerated() {
                group.addTask {
                    do {
                        var manifest = try await self.fetchManifest(url: url)
                        // Strip streams from shared/admin-provisioned addons: the
                        // backend must never deliver a playable source to users.
                        if streamGuardedUrls.contains(url), manifest.hasResource("stream") {
                            manifest = manifest.strippingStreamResource()
                        }
                        return ManagedAddon(
                            manifest: manifest,
                            manifestUrl: url,
                            enabled: !disabledSnapshot.contains(url),
                            sortOrder: index
                        )
                    } catch {
                        print("[Moonlit] Addon fetch failed: \(url) — \(error.localizedDescription)")
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
            print("[Moonlit] All addon fetches failed. \(urls.count) URLs attempted.")
        } else if !addons.isEmpty {
            errorMessage = nil
        }

        addons.sort { $0.sortOrder < $1.sortOrder }
        self.managedAddons = addons
    }

    private func fetchManifest(url: String) async throws -> AddonManifest {
        // Return cached manifest if fresh (server sends no-store so URLCache is useless)
        if let (cached, stamp) = Self.manifestCache[url],
           Date().timeIntervalSince(stamp) < Self.manifestTTL {
            return cached
        }
        // No cache-buster: the timestamp suffix was defeating ETags on every launch
        let text = try await StremioHTTPClient.shared.getText(url: url)
        let manifest = try AddonManifestParser.parse(json: text, manifestUrl: url)
        Self.manifestCache[url] = (manifest, Date())
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
        guard let index = managedAddons.firstIndex(where: { $0.manifestUrl == url }) else { return }
        managedAddons[index].enabled.toggle()
        let isNowEnabled = managedAddons[index].enabled
        if isNowEnabled {
            disabledAddonUrls.remove(url)
        } else {
            disabledAddonUrls.insert(url)
        }
        if let profileId = currentProfileId { saveDisabledUrls(profileId: profileId) }
        Task { await persistAddons() }
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
        // and pin stale defaults forever. Matches MoonlitWebV2's saveInstalledAddons.
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

    public func findAddonWithMetaResource(type: String, id: String? = nil) -> [AddonManifest] {
        guard let id else {
            return enabledAddons.filter { $0.hasResource("meta") }
        }
        return enabledAddons.filter { $0.canHandleMeta(type: type, id: id) }
    }
}
