import Foundation

public struct AddonResource: Codable, Sendable, Identifiable {
    public let name: String
    public let types: [String]?
    public let idPrefixes: [String]?

    public var id: String { name }

    public init(name: String, types: [String]? = nil, idPrefixes: [String]? = nil) {
        self.name = name
        self.types = types
        self.idPrefixes = idPrefixes
    }
}

public struct AddonCatalog: Codable, Sendable, Identifiable {
    public let type: String
    public let id: String
    public let name: String?
    public let extra: [AddonCatalogExtra]?

    public init(type: String, id: String, name: String? = nil, extra: [AddonCatalogExtra]? = nil) {
        self.type = type
        self.id = id
        self.name = name
        self.extra = extra
    }
}

public struct AddonCatalogExtra: Codable, Sendable {
    public let name: String
    public let isRequired: Bool?
    public let options: [String]?
    public let optionsLimit: Int?

    public init(
        name: String,
        isRequired: Bool? = nil,
        options: [String]? = nil,
        optionsLimit: Int? = nil
    ) {
        self.name = name
        self.isRequired = isRequired
        self.options = options
        self.optionsLimit = optionsLimit
    }
}

public struct AddonBehaviorHints: Codable, Sendable {
    public let adult: Bool?
    public let configurable: Bool?
    public let configurationRequired: Bool?

    public init(adult: Bool? = nil, configurable: Bool? = nil, configurationRequired: Bool? = nil) {
        self.adult = adult
        self.configurable = configurable
        self.configurationRequired = configurationRequired
    }
}

public struct AddonManifest: Codable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let version: String
    public let description: String?
    public let types: [String]?
    public let idPrefixes: [String]?
    public let resources: [AddonResource]?
    public let catalogs: [AddonCatalog]?
    public let addonCatalogs: [AddonCatalog]?
    public let behaviorHints: AddonBehaviorHints?
    public let transportUrl: String?
    public let logo: String?
    public let background: String?

    public init(
        id: String,
        name: String,
        version: String,
        description: String? = nil,
        types: [String]? = nil,
        idPrefixes: [String]? = nil,
        resources: [AddonResource]? = nil,
        catalogs: [AddonCatalog]? = nil,
        addonCatalogs: [AddonCatalog]? = nil,
        behaviorHints: AddonBehaviorHints? = nil,
        transportUrl: String? = nil,
        logo: String? = nil,
        background: String? = nil
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.description = description
        self.types = types
        self.idPrefixes = idPrefixes
        self.resources = resources
        self.catalogs = catalogs
        self.addonCatalogs = addonCatalogs
        self.behaviorHints = behaviorHints
        self.transportUrl = transportUrl
        self.logo = logo
        self.background = background
    }

    public func baseURL(manifestUrl: String) -> String {
        if let transportUrl = transportUrl, !transportUrl.isEmpty {
            return transportUrl.hasSuffix("/") ? String(transportUrl.dropLast()) : transportUrl
        }
        if let lastSlash = manifestUrl.lastIndex(of: "/") {
            var base = String(manifestUrl[..<lastSlash])
            if base.hasSuffix("/manifest") {
                base = String(base.dropLast("/manifest".count))
            }
            return base
        }
        return manifestUrl
    }

    /// Returns true if this addon can serve streams for the given media type.
    /// Respects resource-level `types` when top-level `types` is nil — some addons
    /// define type support per-resource instead of at the manifest level.
    public func canHandleStream(type: String) -> Bool {
        guard let streamResource = resources?.first(where: { $0.name == "stream" }) else { return false }
        let effectiveTypes = streamResource.types ?? types
        if let effectiveTypes {
            return effectiveTypes.contains(where: { $0.lowercased() == type.lowercased() })
        }
        return true
    }

    public func hasResource(_ name: String) -> Bool {
        resources?.contains(where: { $0.name == name }) ?? false
    }

    /// Returns a copy of this manifest with its `stream` resource removed, so the
    /// addon can no longer serve streams. Used to stream-guard addons that arrive
    /// through the admin/shared channel — the backend must never deliver a stream
    /// source to users (App Store Review Guidelines 5.2.3 / 2.3.1).
    public func strippingStreamResource() -> AddonManifest {
        AddonManifest(
            id: id,
            name: name,
            version: version,
            description: description,
            types: types,
            idPrefixes: idPrefixes,
            resources: resources?.filter { $0.name != "stream" },
            catalogs: catalogs,
            addonCatalogs: addonCatalogs,
            behaviorHints: behaviorHints,
            transportUrl: transportUrl,
            logo: logo,
            background: background
        )
    }

    /// Returns true if this addon can serve a meta response for the given type+id.
    /// Respects resource-level `types` and `idPrefixes` when present.
    public func canHandleMeta(type: String, id: String) -> Bool {
        guard let metaResource = resources?.first(where: { $0.name == "meta" }) else { return false }
        let effectiveTypes = metaResource.types ?? types
        if let effectiveTypes, !effectiveTypes.contains(where: { $0.lowercased() == type.lowercased() }) {
            return false
        }
        let effectivePrefixes = metaResource.idPrefixes ?? idPrefixes
        if let effectivePrefixes, !effectivePrefixes.isEmpty {
            if !effectivePrefixes.contains(where: { id.hasPrefix($0) }) { return false }
        }
        return true
    }
}

public struct ManagedAddon: Codable, Sendable, Identifiable {
    public var manifest: AddonManifest
    public var manifestUrl: String
    public var enabled: Bool
    public var sortOrder: Int
    public var refreshing: Bool
    public var errorMessage: String?
    public var userSetName: String?

    public var id: String { manifestUrl }

    public var displayName: String {
        if let name = userSetName, !name.isEmpty { return name }
        return manifest.name
    }

    public init(
        manifest: AddonManifest,
        manifestUrl: String,
        enabled: Bool = true,
        sortOrder: Int = 0,
        refreshing: Bool = false,
        errorMessage: String? = nil,
        userSetName: String? = nil
    ) {
        self.manifest = manifest
        self.manifestUrl = manifestUrl
        self.enabled = enabled
        self.sortOrder = sortOrder
        self.refreshing = refreshing
        self.errorMessage = errorMessage
        self.userSetName = userSetName
    }
}
