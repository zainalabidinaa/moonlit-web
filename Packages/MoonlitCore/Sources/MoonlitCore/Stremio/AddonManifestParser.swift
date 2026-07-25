import Foundation

public enum AddonManifestParser {
    private static let decoder = JSONDecoder()

    public static func parse(json: String, manifestUrl: String) throws -> AddonManifest {
        guard let data = json.data(using: .utf8) else {
            throw StremioError.invalidManifest
        }

        struct RawManifest: Codable {
            let id: String?
            let name: String?
            let version: String?
            let description: String?
            let types: [String]?
            let idPrefixes: [String]?
            let resources: [RawResource]?
            let catalogs: [RawCatalog]?
            let addonCatalogs: [RawCatalog]?
            let behaviorHints: RawBehaviorHints?
            let transportUrl: String?
            let logo: String?
            let background: String?
        }
        // Stremio manifests express `resources` as EITHER plain strings
        // (e.g. "catalog", "meta", "stream") OR objects ({name, types, idPrefixes}).
        // Most addons (Cinemeta, AIOMetadata, OpenSubtitles) use the string form, so
        // we must accept both or the whole manifest fails to decode and is dropped.
        struct RawResource: Codable {
            let name: String?
            let types: [String]?
            let idPrefixes: [String]?

            enum CodingKeys: String, CodingKey { case name, types, idPrefixes }

            init(from decoder: Decoder) throws {
                let single = try decoder.singleValueContainer()
                if let str = try? single.decode(String.self) {
                    name = str
                    types = nil
                    idPrefixes = nil
                } else {
                    let c = try decoder.container(keyedBy: CodingKeys.self)
                    name = try c.decodeIfPresent(String.self, forKey: .name)
                    types = try c.decodeIfPresent([String].self, forKey: .types)
                    idPrefixes = try c.decodeIfPresent([String].self, forKey: .idPrefixes)
                }
            }
        }
        struct RawCatalog: Codable {
            let type: String?
            let id: String?
            let name: String?
            let extra: [RawExtra]?
        }
        struct RawExtra: Codable {
            let name: String?
            let isRequired: Bool?
            let options: [String]?
            let optionsLimit: Int?
        }
        struct RawBehaviorHints: Codable {
            let adult: Bool?
            let configurable: Bool?
            let configurationRequired: Bool?
        }

        let raw = try decoder.decode(RawManifest.self, from: data)

        let manifestId = raw.id ?? URL(string: manifestUrl)?.host ?? manifestUrl
        let base = resolveBaseURL(manifestUrl: manifestUrl, transportUrl: raw.transportUrl)

        return AddonManifest(
            id: manifestId,
            name: raw.name ?? manifestId,
            version: raw.version ?? "0.0.0",
            description: raw.description,
            types: raw.types,
            idPrefixes: raw.idPrefixes,
            resources: raw.resources?.map {
                AddonResource(
                    name: $0.name ?? "",
                    types: $0.types,
                    idPrefixes: $0.idPrefixes
                )
            },
            catalogs: raw.catalogs?.map {
                AddonCatalog(
                    type: $0.type ?? "",
                    id: $0.id ?? "",
                    name: $0.name,
                    extra: $0.extra?.map {
                        AddonCatalogExtra(
                            name: $0.name ?? "",
                            isRequired: $0.isRequired,
                            options: $0.options,
                            optionsLimit: $0.optionsLimit
                        )
                    }
                )
            },
            addonCatalogs: raw.addonCatalogs?.map {
                AddonCatalog(
                    type: $0.type ?? "",
                    id: $0.id ?? "",
                    name: $0.name,
                    extra: $0.extra?.map {
                        AddonCatalogExtra(
                            name: $0.name ?? "",
                            isRequired: $0.isRequired,
                            options: $0.options,
                            optionsLimit: $0.optionsLimit
                        )
                    }
                )
            },
            behaviorHints: raw.behaviorHints.map {
                AddonBehaviorHints(
                    adult: $0.adult,
                    configurable: $0.configurable,
                    configurationRequired: $0.configurationRequired
                )
            },
            transportUrl: base,
            logo: raw.logo.flatMap { resolveURL($0, base: base) },
            background: raw.background.flatMap { resolveURL($0, base: base) }
        )
    }

    private static func resolveBaseURL(manifestUrl: String, transportUrl: String?) -> String {
        let url = manifestUrl
        let derived: String = {
            if url.hasSuffix("/manifest.json") {
                return String(url.dropLast("/manifest.json".count))
            }
            if let lastSlash = url.lastIndex(of: "/") {
                return String(url[..<lastSlash])
            }
            return url
        }()
        // Prefer URL-derived base — it preserves credentials encoded in the path.
        // The manifest's transportUrl is often the bare domain.
        return derived.hasSuffix("/") ? String(derived.dropLast()) : derived
    }

    private static func resolveURL(_ path: String, base: String) -> String {
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            return path
        }
        if path.hasPrefix("/") {
            return base + path
        }
        return base + "/" + path
    }
}
