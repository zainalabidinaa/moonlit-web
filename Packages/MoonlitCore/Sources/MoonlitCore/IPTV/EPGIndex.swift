// Packages/MoonlitCore/Sources/MoonlitCore/IPTV/EPGIndex.swift
//
// Indexes parsed EPG programs for fast lookup and resolves a channel to its program
// list. Swift port of an external IPTV library's EPG index logic plus the matching
// in `epg-resolver.ts` (direct tvg-id, normalized-name fallback, manual overrides).
import Foundation

public struct EPGIndex: Sendable {
    /// Programs keyed by tvg-id, each list sorted ascending by start time.
    public let byChannel: [String: [EPGProgram]]
    /// `<channel>` display-name / icon defs, keyed by id.
    public let channelMeta: [String: EPGChannelMeta]
    /// Normalized display-name → tvg-id, for the name fallback.
    private let nameKeyToTvgId: [String: String]

    public init(programs: [EPGProgram], channelMeta: [String: EPGChannelMeta]) {
        // Group + sort.
        var grouped: [String: [EPGProgram]] = [:]
        for program in programs {
            grouped[program.channelTvgId, default: []].append(program)
        }
        for key in grouped.keys {
            grouped[key]?.sort { $0.startMs < $1.startMs }
        }
        self.byChannel = grouped
        self.channelMeta = channelMeta

        // Build the name-fallback index from channel defs, and from tvg-ids that have
        // programs but no <channel> def (use the id itself as a name source).
        var nameIndex: [String: String] = [:]
        for (id, meta) in channelMeta {
            if let name = meta.displayName {
                let key = Self.nameKey(name)
                if key.count >= 3 { nameIndex[key] = id }
            }
        }
        self.nameKeyToTvgId = nameIndex
    }

    public init(from result: EPGParseResult) {
        self.init(programs: result.programs, channelMeta: result.channelMeta)
    }

    public var isEmpty: Bool { byChannel.isEmpty }

    // MARK: - Resolution

    /// The program list for a channel: manual override → direct tvg-id → name
    /// fallback. `overrides` maps a channel id to a forced tvg-id.
    public func programs(for channel: IPTVChannel, overrides: [String: String] = [:]) -> [EPGProgram]? {
        if let forced = overrides[channel.id], let programs = byChannel[forced] {
            return programs
        }
        if let tvgId = channel.tvgId, let programs = byChannel[tvgId] {
            return programs
        }
        // Name fallback: normalize the channel name and match against display names.
        let key = Self.nameKey(channel.name)
        if key.count >= 3, let tvgId = nameKeyToTvgId[key], let programs = byChannel[tvgId] {
            return programs
        }
        return nil
    }

    /// Now/next for a channel at `date`.
    public func nowNext(for channel: IPTVChannel, at date: Date = Date(), overrides: [String: String] = [:]) -> EPGNowNext {
        Self.findCurrent(programs(for: channel, overrides: overrides), nowMs: date.timeIntervalSince1970 * 1000)
    }

    // MARK: - Binary search (port of xmltv.ts findCurrent)

    public static func findCurrent(_ programs: [EPGProgram]?, nowMs: Double) -> EPGNowNext {
        guard let arr = programs, !arr.isEmpty else { return .empty }
        var lo = 0, hi = arr.count - 1, foundIdx = -1
        while lo <= hi {
            let mid = (lo + hi) / 2
            let p = arr[mid]
            if nowMs < p.startMs { hi = mid - 1 }
            else if nowMs >= p.endMs { lo = mid + 1 }
            else { foundIdx = mid; break }
        }
        if foundIdx < 0 {
            return EPGNowNext(current: nil, next: lo < arr.count ? arr[lo] : nil)
        }
        return EPGNowNext(current: arr[foundIdx], next: foundIdx + 1 < arr.count ? arr[foundIdx + 1] : nil)
    }

    // MARK: - Normalization (port of epg-resolver.ts)

    /// Normalize a channel/display name to a comparison key: lowercase, strip
    /// everything but a–z0–9. (The reference implementation also special-cases Arabic; omitted here.)
    public static func nameKey(_ s: String) -> String {
        String(s.lowercased().unicodeScalars.filter { ($0 >= "a" && $0 <= "z") || ($0 >= "0" && $0 <= "9") })
    }
}
