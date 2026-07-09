import Foundation

/// Tracks which titles are award winners so a hero backdrop can show the matching
/// award-body badge ("award corner"). Built in the background from the Awards
/// collection's winner lists and cached to disk so it survives relaunches.
@MainActor
public final class AwardIndex: ObservableObject {
    public static let shared = AwardIndex()

    /// Maps a title id (IMDb/meta id) → the bundled asset name for its award body
    /// (e.g. "tt0468569" → "award-oscars").
    @Published public private(set) var winners: [String: String] = [:]

    private var hasBuilt = false

    private let cacheURL: URL? = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        return dir?.appendingPathComponent("moonlit-award-index.json")
    }()

    private init() {
        if let url = cacheURL, let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            winners = decoded
        }
    }

    /// The bundled asset name for a winning title, or nil if it isn't a known winner.
    public func assetName(forId id: String) -> String? {
        if let direct = winners[id] { return direct }
        // Episode/season ids look like "tt123:1:2" — fall back to the base title id.
        if let base = id.split(separator: ":").first.map(String.init), base != id {
            return winners[base]
        }
        return nil
    }

    /// Builds the index once per launch (background-safe). Pass the repositories from
    /// the UI layer; this avoids a hard dependency cycle.
    public func buildIfNeeded(
        catalogRepo: CatalogRepository,
        collectionRepo: CollectionRepository,
        addons: [AddonManifest]
    ) async {
        guard !hasBuilt else { return }
        hasBuilt = true
        let resolved = await catalogRepo.fetchAwardWinners(collectionRepo: collectionRepo, addons: addons)
        guard !resolved.isEmpty else { return }
        winners = resolved
        if let url = cacheURL, let data = try? JSONEncoder().encode(resolved) {
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Maps an award-body folder/collection name to its bundled logo asset.
    public static func assetName(forBody body: String) -> String? {
        let n = GenreCatalog.normalize(body)
        if n.contains("picture") { return "award-bestpicture" }
        if n.contains("oscar") || n.contains("academy") { return "award-oscars" }
        if n.contains("emmy") { return "award-emmy" }
        if n.contains("globe") { return "award-globe" }
        if n.contains("bafta") { return "award-bafta" }
        if n.contains("cannes") { return "award-cannes" }
        if n.contains("venice") { return "award-venice" }
        if n.contains("berlin") { return "award-berlin" }
        return nil
    }
}
