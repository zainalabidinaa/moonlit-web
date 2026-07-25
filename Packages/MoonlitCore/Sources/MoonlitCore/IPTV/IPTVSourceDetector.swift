// Packages/MoonlitCore/Sources/MoonlitCore/IPTV/IPTVSourceDetector.swift
//
// Classifies a user-added IPTV source into a concrete "shape" (Xtream / M3U / EPG /
// invalid) so the repository knows how to fetch it. Swift port of an external IPTV
// library's source detector, plus the middleware fallback candidate list from
// `ingest/load.ts`.
import Foundation

/// The resolved kind of an IPTV source, ready to fetch.
public enum IPTVProviderShape: Sendable {
    case xtream(XtreamClient.ResolvedCreds)
    /// A plain playlist URL. `middleware` marks proxy/panel URLs (bare host or
    /// `/iptv|/m3u|…` paths) whose initial fetch may need fallback probing.
    case m3u(url: String, middleware: Bool)
    case epg(url: String)
    case invalid(reason: String)
}

public enum IPTVSourceDetector {

    /// Path fragments that indicate a middleware/proxy playlist endpoint rather
    /// than a direct `.m3u` file.
    private static let middlewarePathPattern = "/(iptv|m3u|playlist|xmltv|threadfin|xteve)\\b"
    /// A direct `.m3u`/`.m3u8` file path (optionally followed by a query string).
    private static let rawM3UPattern = "\\.m3u8?(\\?|$)"

    /// Fallback paths tried, in order, when a middleware M3U URL's initial fetch
    /// isn't valid `#EXTM3U` content. Combined with the URL's origin.
    public static let middlewareCandidatePaths = ["/iptv/m3u", "/m3u", "/playlist.m3u", "/get.php?type=m3u_plus"]

    public static func detect(_ source: IPTVPlaylistSource) -> IPTVProviderShape {
        if source.kind == .epg {
            let url = (source.epgUrl?.nonEmpty ?? source.url).trimmingCharacters(in: .whitespaces)
            return url.isEmpty ? .invalid(reason: "EPG source has no URL.") : .epg(url: url)
        }

        // Try to derive Xtream credentials, either from explicit fields or by
        // sniffing a get.php/player_api.php URL.
        let creds = credsFromSource(source)
        if creds != nil || source.kind == .xtream {
            if let creds { return .xtream(creds) }
            return .invalid(reason: "Xtream credentials are incomplete. Check server URL, username, and password.")
        }

        let url = source.url.trimmingCharacters(in: .whitespaces)
        if url.isEmpty { return .invalid(reason: "Playlist source has no URL.") }
        guard url.range(of: "^https?://", options: [.regularExpression, .caseInsensitive]) != nil else {
            return .invalid(reason: "That does not look like a playlist URL. Use an http(s) M3U link or Xtream server.")
        }
        return .m3u(url: url, middleware: isMiddlewareURL(url))
    }

    /// Resolve Xtream credentials from a source: explicit `xtream` fields first,
    /// else a credential-bearing playlist URL.
    public static func credsFromSource(_ source: IPTVPlaylistSource) -> XtreamClient.ResolvedCreds? {
        if let xtream = source.xtream, let resolved = XtreamClient.resolve(xtream) {
            return resolved
        }
        if !source.url.isEmpty, let parsed = XtreamClient.parseUrl(source.url) {
            return parsed
        }
        return nil
    }

    private static func isMiddlewareURL(_ url: String) -> Bool {
        guard let comps = URLComponents(string: url) else { return false }
        let path = comps.path
        if path.range(of: rawM3UPattern, options: [.regularExpression, .caseInsensitive]) != nil { return false }
        if path.range(of: middlewarePathPattern, options: [.regularExpression, .caseInsensitive]) != nil { return true }
        let isBareHost = path == "/" || path.isEmpty
        return isBareHost && (comps.query?.isEmpty ?? true)
    }

    /// Middleware fallback URLs to try (origin + each candidate path), excluding
    /// the original URL. Used by the repository when the first fetch isn't M3U.
    public static func middlewareCandidates(for url: String) -> [String] {
        guard let comps = URLComponents(string: url), let scheme = comps.scheme, let host = comps.host else { return [] }
        let portPart = comps.port.map { ":\($0)" } ?? ""
        let origin = "\(scheme)://\(host)\(portPart)"
        return middlewareCandidatePaths
            .map { origin + $0 }
            .filter { $0 != url }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
