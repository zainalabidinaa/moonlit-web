// Packages/MoonlitCore/Sources/MoonlitCore/IPTV/IPTVCatchup.swift
//
// Builds catch-up / timeshift playback URLs for a past program. Swift port of
// an external IPTV library's catchup handler. Supports flussonic archive URLs, Xtream
// timeshift, and generic `catchup-source` templates with ${token}/{token} and
// strftime-style date tokens.
import Foundation

public enum CatchupType: String, Sendable {
    case `default`
    case append
    case shift
    case flussonic
    case xtream
}

public enum IPTVCatchup {

    /// Matches an Xtream live stream URL, capturing host / user / pass / id.
    /// `^(https?://host)/(?:live/)?(user)/(pass)/(id).(ext)`
    private static let xtreamLivePattern =
        #"^(https?://[^/]+)/(?:live/)?([^/]+)/([^/]+)/(\d+)\.(\w+)(?:\?|$)"#

    public static func detectType(_ channel: IPTVChannel) -> CatchupType? {
        let raw = (channel.catchupType ?? "").lowercased().trimmingCharacters(in: .whitespaces)
        switch raw {
        case "flussonic", "fs": return .flussonic
        case "xc", "xtream": return .xtream
        case "append": return .append
        case "shift", "timeshift": return .shift
        case "default": return .default
        default: break
        }
        if channel.catchupSource != nil { return .default }
        if channel.url.range(of: xtreamLivePattern, options: [.regularExpression, .caseInsensitive]) != nil {
            return .xtream
        }
        return nil
    }

    public static func channelHasCatchup(_ channel: IPTVChannel) -> Bool {
        detectType(channel) != nil
    }

    /// Build the catch-up URL for the program spanning [startMs, endMs]. Returns nil
    /// when the channel has no catch-up strategy.
    public static func buildURL(for channel: IPTVChannel, startMs: Double, endMs: Double, nowMs: Double = Date().timeIntervalSince1970 * 1000) -> String? {
        guard let type = detectType(channel) else { return nil }
        let start = Int(floor(startMs / 1000))
        let end = Int(floor(endMs / 1000))
        let now = Int(floor(nowMs / 1000))
        let duration = max(60, end - start)

        switch type {
        case .flussonic:
            return flussonicURL(channel.url, start: start, duration: duration)

        case .xtream:
            guard let m = firstMatch(xtreamLivePattern, in: channel.url) else { return nil }
            let host = m[1], user = m[2], pass = m[3], id = m[4]
            let mins = Int(ceil(Double(duration) / 60))
            let stamp = strftime("Y-m-d:H-M", Date(timeIntervalSince1970: Double(start)))
            return "\(host)/timeshift/\(user)/\(pass)/\(mins)/\(stamp)/\(id).ts"

        case .default, .append, .shift:
            if let src = channel.catchupSource {
                if src.range(of: "^https?://", options: [.regularExpression, .caseInsensitive]) != nil {
                    return fillTemplate(src, start: start, end: end, now: now, duration: duration)
                }
                let filled = fillTemplate(src, start: start, end: end, now: now, duration: duration)
                // A relative template that already carries its own separator is appended
                // as-is; otherwise pick "?"/"&" based on whether the URL has a query.
                if src.hasPrefix("?") || src.hasPrefix("&") {
                    return channel.url + filled
                }
                let sep = channel.url.contains("?") ? "&" : "?"
                return channel.url + sep + filled
            }
            let sep = channel.url.contains("?") ? "&" : "?"
            return "\(channel.url)\(sep)utc=\(start)&lutc=\(now)"
        }
    }

    // MARK: - Flussonic

    private static func flussonicURL(_ base: String, start: Int, duration: Int) -> String? {
        let q = base.firstIndex(of: "?")
        let path = q.map { String(base[base.startIndex..<$0]) } ?? base
        let query = q.map { String(base[$0...]) } ?? ""

        if let m = firstMatch(#"^(.*)/([^/]+)\.(m3u8|ts|mpd)$"#, in: path, caseInsensitive: true) {
            let dir = m[1], file = m[2], ext = m[3]
            let stem = (file == "mpegts" || file == "mono") ? "index" : file
            return "\(dir)/\(stem)-\(start)-\(duration).\(ext)\(query)"
        }
        let trimmed = path.replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
        return "\(trimmed)/archive-\(start)-\(duration).ts\(query)"
    }

    // MARK: - Template substitution

    private static func fillTemplate(_ tpl: String, start: Int, end: Int, now: Int, duration: Int) -> String {
        let offset = max(0, now - start)
        let startDate = Date(timeIntervalSince1970: Double(start))
        var out = tpl

        // Date-format tokens first: ${start:Y-m-d} / {utc:H-M} etc.
        out = replaceRegex(out, #"\$\{(?:start|utc):([^}]+)\}"#) { groups in strftime(groups[1], startDate) }
        out = replaceRegex(out, #"\{(?:utc|start):([^}]+)\}"#) { groups in strftime(groups[1], startDate) }

        let map: [String: String] = [
            "start": String(start), "utc": String(start), "timestamp": String(start),
            "end": String(end), "utcend": String(end),
            "now": String(now), "lutc": String(now), "timenow": String(now),
            "duration": String(duration), "dur": String(duration),
            "offset": String(offset),
            "duration-minutes": String(Int(ceil(Double(duration) / 60))),
        ]
        let sub: ([String]) -> String = { groups in map[groups[1].lowercased()] ?? groups[0] }
        out = replaceRegex(out, #"\$\{(\w[\w-]*)\}"#, sub)
        out = replaceRegex(out, #"\{(\w[\w-]*)\}"#, sub)
        return out
    }

    // MARK: - Date formatting (strftime subset, UTC)

    private static func strftime(_ fmt: String, _ date: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        func pad(_ n: Int) -> String { String(format: "%02d", n) }
        return fmt
            .replacingOccurrences(of: "Y", with: String(c.year ?? 0))
            .replacingOccurrences(of: "m", with: pad(c.month ?? 0))
            .replacingOccurrences(of: "d", with: pad(c.day ?? 0))
            .replacingOccurrences(of: "H", with: pad(c.hour ?? 0))
            .replacingOccurrences(of: "M", with: pad(c.minute ?? 0))
            .replacingOccurrences(of: "S", with: pad(c.second ?? 0))
    }

    // MARK: - Regex helpers

    private static func firstMatch(_ pattern: String, in string: String, caseInsensitive: Bool = true) -> [String]? {
        let options: NSRegularExpression.Options = caseInsensitive ? [.caseInsensitive] : []
        guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        let range = NSRange(string.startIndex..., in: string)
        guard let match = re.firstMatch(in: string, range: range) else { return nil }
        return (0..<match.numberOfRanges).map { idx in
            guard let r = Range(match.range(at: idx), in: string) else { return "" }
            return String(string[r])
        }
    }

    /// Replace every match of `pattern` using a callback that receives the match's
    /// capture groups ([0] = whole match, [1] = first group, …).
    private static func replaceRegex(_ string: String, _ pattern: String, _ transform: ([String]) -> String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return string }
        let ns = string as NSString
        let matches = re.matches(in: string, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return string }
        var result = ""
        var last = 0
        for match in matches {
            let whole = match.range
            result += ns.substring(with: NSRange(location: last, length: whole.location - last))
            let groups = (0..<match.numberOfRanges).map { idx -> String in
                let r = match.range(at: idx)
                return r.location == NSNotFound ? "" : ns.substring(with: r)
            }
            result += transform(groups)
            last = whole.location + whole.length
        }
        result += ns.substring(from: last)
        return result
    }
}
