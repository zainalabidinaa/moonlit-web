// Packages/MoonlitCore/Sources/MoonlitCore/Models/IPTVModels.swift
//
// IPTV / Live TV data models. Deliberately separate from MetaPreview / CatalogRow /
// StreamItem: an IPTV channel already *is* its own playable URL, so it doesn't need
// the addon → meta → stream-resolution round-trip that VOD content goes through.
//
// Swift port of an external IPTV library's type definitions.
import Foundation

/// How a user-added IPTV source is fetched.
public enum IPTVSourceKind: String, Codable, Sendable, CaseIterable {
    /// A plain M3U/M3U8 playlist URL.
    case m3u
    /// Xtream Codes login (server + username + password).
    case xtream
    /// A standalone XMLTV EPG feed (no channels of its own — attached to other sources).
    case epg

    public var displayName: String {
        switch self {
        case .m3u:    return "M3U Playlist"
        case .xtream: return "Xtream Codes"
        case .epg:    return "EPG Only"
        }
    }
}

/// Xtream Codes credentials. Stored in `UserDefaults` (see `IPTVSourceRepository`).
public struct XtreamCredentials: Codable, Sendable, Hashable {
    /// Base server URL, e.g. `http://example.com:8080`. No trailing slash, no path.
    public var server: String
    public var username: String
    public var password: String

    public init(server: String, username: String, password: String) {
        self.server = server
        self.username = username
        self.password = password
    }
}

/// A user-added IPTV source. This is the thing the user creates/edits in the source
/// form; fetching it produces an `IPTVPlaylist`.
public struct IPTVPlaylistSource: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public var name: String
    /// The playlist/EPG URL. For `.xtream` sources this is derived from `xtream`
    /// and may be empty when the source is first created.
    public var url: String
    /// Optional XMLTV EPG URL attached to this source (used in Phase 2).
    public var epgUrl: String?
    public var kind: IPTVSourceKind
    /// Present only for `.xtream` sources.
    public var xtream: XtreamCredentials?
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        name: String,
        url: String,
        epgUrl: String? = nil,
        kind: IPTVSourceKind,
        xtream: XtreamCredentials? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.epgUrl = epgUrl
        self.kind = kind
        self.xtream = xtream
        self.createdAt = createdAt
    }
}

/// A single live channel parsed from an M3U playlist or the Xtream live API.
public struct IPTVChannel: Codable, Sendable, Identifiable, Hashable {
    /// Stable id, unique within a playlist. For M3U we synthesize one; for Xtream
    /// it's the stream id.
    public let id: String
    /// The `tvg-id` attribute — the key that links a channel to its EPG entries.
    public let tvgId: String?
    public let name: String
    /// `tvg-logo` (M3U) or `stream_icon` (Xtream).
    public let logo: String?
    /// `group-title` (M3U) or the Xtream category name. Used to section the grid.
    public let group: String?
    /// The resolved, directly-playable stream URL (`.ts`/`.m3u8`/…).
    public let url: String
    /// The `catchup` / `catchup-type` attribute value (e.g. "flussonic", "xtream",
    /// "append", "shift", "default") — the catch-up *strategy*. Distinct from the
    /// `catchupSource` template below. (Phase 3)
    public let catchupType: String?
    /// `catchup-source` template URL, when the provider advertises one.
    public let catchupSource: String?
    /// How many days of catch-up the channel retains, when advertised.
    public let catchupDays: Int?
    /// Extra request headers derived from M3U pipe-params / `#EXTVLCOPT`
    /// (user-agent / referrer / cookie), applied at playback time.
    public let headers: [String: String]?

    public init(
        id: String,
        tvgId: String? = nil,
        name: String,
        logo: String? = nil,
        group: String? = nil,
        url: String,
        catchupType: String? = nil,
        catchupSource: String? = nil,
        catchupDays: Int? = nil,
        headers: [String: String]? = nil
    ) {
        self.id = id
        self.tvgId = tvgId
        self.name = name
        self.logo = logo
        self.group = group
        self.url = url
        self.catchupType = catchupType
        self.catchupSource = catchupSource
        self.catchupDays = catchupDays
        self.headers = headers
    }

    /// The channel as a `MetaPreview` so it can flow into the existing tile/grid
    /// components. Uses the unused `.channel` media type; the logo doubles as poster.
    public var asMetaPreview: MetaPreview {
        MetaPreview(
            id: id,
            type: .channel,
            name: name,
            poster: logo,
            posterShape: .square
        )
    }
}

/// The fetched, parsed result of an `IPTVPlaylistSource`. Cached by the repository
/// so tab switches don't re-hit the network.
public struct IPTVPlaylist: Codable, Sendable, Identifiable, Hashable {
    /// Same id as the source it was fetched from.
    public let id: String
    public let name: String
    public var channels: [IPTVChannel]
    /// Distinct `group` values, in first-seen order — the section headers for the grid.
    public var groups: [String]
    public var fetchedAt: Date

    public init(
        id: String,
        name: String,
        channels: [IPTVChannel],
        groups: [String],
        fetchedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.channels = channels
        self.groups = groups
        self.fetchedAt = fetchedAt
    }

    /// Channels bucketed by group, preserving `groups` order. Channels with no group
    /// fall under a synthesized "Ungrouped" bucket appended last.
    public var channelsByGroup: [(group: String, channels: [IPTVChannel])] {
        var buckets: [String: [IPTVChannel]] = [:]
        for channel in channels {
            let key = channel.group?.isEmpty == false ? channel.group! : Self.ungrouped
            buckets[key, default: []].append(channel)
        }
        var ordered = groups.compactMap { group -> (String, [IPTVChannel])? in
            guard let items = buckets[group], !items.isEmpty else { return nil }
            return (group, items)
        }
        if let ungroupedItems = buckets[Self.ungrouped], !ungroupedItems.isEmpty {
            ordered.append((Self.ungrouped, ungroupedItems))
        }
        return ordered
    }

    public static let ungrouped = "Ungrouped"
}
