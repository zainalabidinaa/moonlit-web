import Foundation

@MainActor
public class SearchRepository: ObservableObject {
    public static let shared = SearchRepository()

    @Published public var results: [MetaPreview] = []
    @Published public var isLoading = false
    @Published public var searchQuery = ""

    private let catalogService = CatalogService.shared

    private init() {}

    public func search(query: String, addons: [AddonManifest]) async {
        guard !query.isEmpty else {
            results = []
            return
        }

        isLoading = true
        searchQuery = query
        defer { isLoading = false }

        var allResults: [MetaPreview] = []

        await withTaskGroup(of: [MetaPreview]?.self) { group in
            for addon in addons {
                guard addon.hasResource("catalog"),
                      let baseURL = addon.transportUrl else { continue }

                let searchableCatalogs = (addon.catalogs ?? []).filter { catalog in
                    catalog.extra?.contains { $0.name == "search" } == true
                }

                if searchableCatalogs.isEmpty {
                    // Fallback: try common search catalog patterns for movie and series
                    for type in ["movie", "series"] {
                        group.addTask {
                            await self.fetchSearch(type: type, id: "search", baseURL: baseURL, query: query)
                        }
                    }
                } else {
                    for catalog in searchableCatalogs {
                        group.addTask {
                            await self.fetchSearch(type: catalog.type, id: catalog.id, baseURL: baseURL, query: query)
                        }
                    }
                }
            }

            for await result in group {
                if let items = result {
                    allResults.append(contentsOf: items)
                }
            }
        }

        // Only keep proper media — drop raw stream/file results and release-name junk
        // (e.g. "Breaking.Bad.S01.Ger.En-g.EAC3D.DL.2160p.WEB...") that some addons echo
        // back from a search catalog.
        let mediaOnly = allResults.filter {
            ($0.type == .movie || $0.type == .series)
                && !$0.name.isEmpty
                && !Self.looksLikeReleaseName($0.name)
        }

        // First dedup pass: by IMDB/provider ID (canonical)
        let byId = Dictionary(grouping: mediaOnly, by: { $0.id })
            .compactMap { $0.value.first }

        // Second dedup pass: by (name, type) to collapse cross-addon duplicates
        // that have different IDs but represent the same title
        let byNameType = Dictionary(grouping: byId, by: { "\($0.type.rawValue):\($0.name.lowercased())" })
            .compactMap { $0.value.max(by: { ($0.popularity ?? 0) < ($1.popularity ?? 0) }) }

        // Rank by how well the title matches the query (exact → prefix → word → contains),
        // with popularity / rating only as tiebreakers, so the most accurate result is first.
        self.results = byNameType.sorted { a, b in
            let sa = Self.relevanceScore(name: a.name, query: query)
            let sb = Self.relevanceScore(name: b.name, query: query)
            if sa != sb { return sa > sb }
            if (a.popularity ?? 0) != (b.popularity ?? 0) {
                return (a.popularity ?? 0) > (b.popularity ?? 0)
            }
            return (Double(a.imdbRating ?? "0") ?? 0) > (Double(b.imdbRating ?? "0") ?? 0)
        }
    }

    /// Fetches one search catalog, bounded by a timeout so a single slow addon can't
    /// stall the whole search. Returns nil on failure or timeout.
    private func fetchSearch(type: String, id: String, baseURL: String, query: String) async -> [MetaPreview]? {
        await withTaskGroup(of: [MetaPreview]?.self) { group in
            group.addTask {
                try? await self.catalogService.fetchCatalog(
                    query: CatalogService.StremioCatalogQuery(
                        type: type, id: id, baseURL: baseURL, extras: ["search": query]
                    )
                )
            }
            group.addTask {
                // Per-addon cap: search results are painted per-source now,
                // so a slow addon only delays its own rows — but don't let a
                // dead one hold background tasks for long either.
                try? await Task.sleep(for: .seconds(4))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    // MARK: - Relevance + filtering (pure, testable)

    /// Higher is a better match for `query`. Exact title beats prefix beats whole-word
    /// beats substring beats token overlap.
    nonisolated public static func relevanceScore(name: String, query: String) -> Int {
        let n = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let q = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return 0 }
        if n == q { return 1000 }
        if n.hasPrefix(q) { return 700 }
        let words = n.split(separator: " ").map(String.init)
        if words.contains(where: { $0.hasPrefix(q) }) { return 500 }
        if n.contains(q) { return 300 }
        let qTokens = Set(q.split(separator: " ").map(String.init))
        let overlap = qTokens.intersection(Set(words)).count
        return overlap > 0 ? 100 + overlap * 10 : 0
    }

    /// True if the title looks like a scene/release filename rather than a real title.
    nonisolated public static func looksLikeReleaseName(_ name: String) -> Bool {
        let lower = name.lowercased()
        let releaseTokens = [
            "2160p", "1080p", "720p", "480p", "web-dl", "webrip", "web.", "bluray",
            "blu-ray", "brrip", "hdrip", "hdtv", "x264", "x265", "h264", "h265", "hevc",
            "eac3", "ac3", "ddp", "dts", "aac2", "remux"
        ]
        if releaseTokens.contains(where: { lower.contains($0) }) { return true }
        // "S01E02"/"S1E2" combined with dots → release name, not a clean title.
        if name.range(of: #"[sS]\d{1,2}[eE]\d{1,2}"#, options: .regularExpression) != nil,
           name.contains(".") { return true }
        // Dotted token soup with no spaces (e.g. "Breaking.Bad.S01.Ger...").
        if !name.contains(" "), name.filter({ $0 == "." }).count >= 2 { return true }
        return false
    }
}
