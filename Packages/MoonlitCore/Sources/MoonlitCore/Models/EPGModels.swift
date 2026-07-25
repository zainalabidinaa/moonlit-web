// Packages/MoonlitCore/Sources/MoonlitCore/Models/EPGModels.swift
//
// Electronic Program Guide models. Swift port of an external IPTV
// library's EPG types. Times are epoch milliseconds (matching the reference
// implementation and the Xtream short-EPG entries) so guide math stays in one unit.
import Foundation

/// A single programme entry from an XMLTV `<programme>` (or an Xtream short-EPG row).
public struct EPGProgram: Codable, Sendable, Identifiable, Hashable {
    /// The `channel` attribute — links back to a channel's `tvg-id`.
    public let channelTvgId: String
    public let title: String
    public let description: String?
    public let category: String?
    public let iconUrl: String?
    public let startMs: Double
    public let endMs: Double

    public var id: String { "\(channelTvgId)-\(Int(startMs))" }

    public init(
        channelTvgId: String,
        title: String,
        description: String? = nil,
        category: String? = nil,
        iconUrl: String? = nil,
        startMs: Double,
        endMs: Double
    ) {
        self.channelTvgId = channelTvgId
        self.title = title
        self.description = description
        self.category = category
        self.iconUrl = iconUrl
        self.startMs = startMs
        self.endMs = endMs
    }

    public var startDate: Date { Date(timeIntervalSince1970: startMs / 1000) }
    public var endDate: Date { Date(timeIntervalSince1970: endMs / 1000) }
    public var durationMs: Double { endMs - startMs }
}

/// A `<channel>` definition from XMLTV — display name + icon, keyed by its id.
public struct EPGChannelMeta: Codable, Sendable, Hashable {
    public let displayName: String?
    public let icon: String?

    public init(displayName: String?, icon: String?) {
        self.displayName = displayName
        self.icon = icon
    }
}

/// The result of parsing an XMLTV document.
public struct EPGParseResult: Sendable {
    public var programs: [EPGProgram]
    public var channelMeta: [String: EPGChannelMeta]

    public init(programs: [EPGProgram] = [], channelMeta: [String: EPGChannelMeta] = [:]) {
        self.programs = programs
        self.channelMeta = channelMeta
    }
}

/// Now/next for a channel.
public struct EPGNowNext: Sendable, Hashable {
    public let current: EPGProgram?
    public let next: EPGProgram?

    public init(current: EPGProgram?, next: EPGProgram?) {
        self.current = current
        self.next = next
    }

    public static let empty = EPGNowNext(current: nil, next: nil)
}
