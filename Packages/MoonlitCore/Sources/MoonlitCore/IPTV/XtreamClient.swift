// Packages/MoonlitCore/Sources/MoonlitCore/IPTV/XtreamClient.swift
//
// Xtream Codes API client. Swift port of an external IPTV library's Xtream handler.
//
// Xtream panels are notoriously loosely-typed — the same field arrives as a String
// on one server and an Int on another — so responses are walked as untyped JSON
// (`[String: Any]`) via JSONSerialization rather than fought through Codable, which
// matches how the TS treats them as `unknown`.
import Foundation

public enum XtreamError: Error, LocalizedError {
    case auth(String)
    case empty
    case network(String)

    public var errorDescription: String? {
        switch self {
        case .auth(let message): return message
        case .empty: return "The Xtream server returned no channels."
        case .network(let message): return message
        }
    }
}

public enum XtreamContainer: String, Sendable {
    case ts
    case m3u8
}

/// What `fetchUserInfo` learns about a server: which stream containers it allows
/// and the base URL to build stream URLs against (may differ from the API base
/// when the panel reports an HTTPS port).
public struct XtreamServerCaps: Sendable {
    public let allowedFormats: [String]
    public let streamBase: String
}

/// One entry from a channel's short EPG (used by the Phase 2 fallback).
public struct XtreamShortEpgEntry: Sendable {
    public let title: String
    public let description: String?
    public let startMs: Double
    public let endMs: Double
}

public enum XtreamClient {

    /// Base URL + credentials, resolved to the scheme://host[:port] form the API
    /// and stream URLs are built against.
    public struct ResolvedCreds: Sendable {
        public let base: String
        public let username: String
        public let password: String
    }

    private static let userAgent = "IPTVSmartersPro/3.1.5"

    // MARK: - Credential resolution

    /// Resolve user-entered server/username/password into a usable base URL.
    /// Returns nil when the server isn't a valid http(s) URL or creds are blank.
    public static func resolve(_ creds: XtreamCredentials) -> ResolvedCreds? {
        let trimmedServer = creds.server.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
        let user = creds.username.trimmingCharacters(in: .whitespaces)
        let pass = creds.password.trimmingCharacters(in: .whitespaces)
        guard trimmedServer.range(of: "^https?://", options: [.regularExpression, .caseInsensitive]) != nil,
              !user.isEmpty, !pass.isEmpty,
              let comps = URLComponents(string: trimmedServer),
              let scheme = comps.scheme, let host = comps.host else { return nil }
        let portPart = comps.port.map { ":\($0)" } ?? ""
        return ResolvedCreds(base: "\(scheme)://\(host)\(portPart)", username: user, password: pass)
    }

    /// Extract credentials from a `get.php`/`player_api.php` URL that carries
    /// `username`/`password` query params.
    public static func parseUrl(_ url: String) -> ResolvedCreds? {
        guard let comps = URLComponents(string: url),
              let scheme = comps.scheme, let host = comps.host else { return nil }
        let path = comps.path
        guard path.range(of: "(get\\.php|player_api\\.php)$", options: [.regularExpression, .caseInsensitive]) != nil else { return nil }
        let items = comps.queryItems ?? []
        guard let user = items.first(where: { $0.name == "username" })?.value, !user.isEmpty,
              let pass = items.first(where: { $0.name == "password" })?.value, !pass.isEmpty else { return nil }
        let portPart = comps.port.map { ":\($0)" } ?? ""
        return ResolvedCreds(base: "\(scheme)://\(host)\(portPart)", username: user, password: pass)
    }

    // MARK: - URL building

    private static func apiUrl(_ creds: ResolvedCreds, action: String? = nil, extra: [String: String] = [:]) -> URL? {
        var comps = URLComponents(string: "\(creds.base)/player_api.php")
        var items = [
            URLQueryItem(name: "username", value: creds.username),
            URLQueryItem(name: "password", value: creds.password),
        ]
        if let action { items.append(URLQueryItem(name: "action", value: action)) }
        for (key, value) in extra.sorted(by: { $0.key < $1.key }) {
            items.append(URLQueryItem(name: key, value: value))
        }
        comps?.queryItems = items
        return comps?.url
    }

    /// `{base}/live/{user}/{pass}/{streamId}.{container}`
    public static func buildLiveStreamURL(
        _ creds: ResolvedCreds,
        streamId: String,
        container: XtreamContainer,
        streamBase: String? = nil
    ) -> String {
        let base = streamBase ?? creds.base
        let user = creds.username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? creds.username
        let pass = creds.password.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? creds.password
        return "\(base)/live/\(user)/\(pass)/\(streamId).\(container.rawValue)"
    }

    // MARK: - User info / capabilities

    public static func fetchUserInfo(_ creds: ResolvedCreds) async throws -> XtreamServerCaps {
        guard let url = apiUrl(creds) else { throw XtreamError.auth("Invalid Xtream server URL.") }
        let raw = try await fetchJSON(url)
        guard let dict = raw as? [String: Any],
              let info = dict["user_info"] as? [String: Any] else {
            throw XtreamError.auth("Xtream login did not return account info. Check the server URL.")
        }
        if asInt(info["auth"]) == 0 {
            throw XtreamError.auth("Xtream rejected these credentials (auth failed). Check the server URL, username, and password.")
        }
        switch asString(info["status"])?.lowercased() {
        case "expired": throw XtreamError.auth("This Xtream account is expired.")
        case "banned":  throw XtreamError.auth("This Xtream account is banned by the provider.")
        case "disabled": throw XtreamError.auth("This Xtream account is disabled by the provider.")
        default: break
        }
        let allowedFormats = (info["allowed_output_formats"] as? [Any])?.compactMap { asString($0)?.lowercased() } ?? []
        let streamBase = deriveStreamBase(creds, serverInfo: dict["server_info"] as? [String: Any])
        return XtreamServerCaps(allowedFormats: allowedFormats, streamBase: streamBase)
    }

    private static func deriveStreamBase(_ creds: ResolvedCreds, serverInfo: [String: Any]?) -> String {
        guard let serverInfo,
              asString(serverInfo["server_protocol"])?.lowercased() == "https",
              let comps = URLComponents(string: creds.base), let host = comps.host else {
            return creds.base
        }
        let port = asString(serverInfo["https_port"])?.nonEmpty ?? asString(serverInfo["port"])?.nonEmpty
        return port.map { "https://\(host):\($0)" } ?? "https://\(host)"
    }

    private static func pickContainer(_ pref: XtreamContainer, allowed: [String]) -> XtreamContainer {
        if allowed.isEmpty { return pref }
        if allowed.contains(pref.rawValue) { return pref }
        if allowed.contains("ts") { return .ts }
        if allowed.contains("m3u8") { return .m3u8 }
        return pref
    }

    // MARK: - Live channels

    public static func fetchLiveChannels(
        _ creds: ResolvedCreds,
        baseId: String,
        container: XtreamContainer = .ts,
        caps: XtreamServerCaps? = nil
    ) async throws -> [IPTVChannel] {
        let resolvedContainer = pickContainer(container, allowed: caps?.allowedFormats ?? [])
        let streamBase = caps?.streamBase ?? creds.base
        guard let categoriesURL = apiUrl(creds, action: "get_live_categories"),
              let streamsURL = apiUrl(creds, action: "get_live_streams") else {
            throw XtreamError.network("Could not build Xtream API URLs.")
        }

        async let categoriesRaw = fetchJSON(categoriesURL)
        async let streamsRaw = fetchJSON(streamsURL)
        let (categories, streams) = try await (categoriesRaw, streamsRaw)

        var categoryName: [String: String] = [:]
        if let rows = categories as? [[String: Any]] {
            for row in rows {
                if let id = asString(row["category_id"]) {
                    categoryName[id] = asString(row["category_name"]) ?? ""
                }
            }
        }

        guard let streamRows = streams as? [[String: Any]] else { return [] }
        var out: [IPTVChannel] = []
        out.reserveCapacity(streamRows.count)
        for row in streamRows {
            guard let streamId = asString(row["stream_id"]) else { continue }
            let tvgId = asString(row["epg_channel_id"])?.trimmingCharacters(in: .whitespaces).nonEmpty
            let group = asString(row["category_id"]).flatMap { categoryName[$0] }?.nonEmpty
            let url = buildLiveStreamURL(creds, streamId: streamId, container: resolvedContainer, streamBase: streamBase)

            var catchupType: String?
            var catchupDays: Int?
            if let archive = asInt(row["tv_archive"]), archive > 0 {
                catchupType = "xtream"
                if let days = asInt(row["tv_archive_duration"]), days > 0 { catchupDays = days }
            }

            let name = asString(row["name"])?.trimmingCharacters(in: .whitespaces).nonEmpty ?? "Stream \(streamId)"
            let logo = asString(row["stream_icon"])?.trimmingCharacters(in: .whitespaces).nonEmpty

            out.append(
                IPTVChannel(
                    id: "\(baseId)::xt::\(streamId)",
                    tvgId: tvgId,
                    name: name,
                    logo: logo,
                    group: group,
                    url: url,
                    catchupType: catchupType,
                    catchupDays: catchupDays,
                    headers: nil
                )
            )
        }
        return out
    }

    // MARK: - Short EPG (Phase 2 fallback)

    public static func fetchShortEpg(_ creds: ResolvedCreds, streamId: String, limit: Int = 8) async throws -> [XtreamShortEpgEntry] {
        guard let url = apiUrl(creds, action: "get_short_epg", extra: ["stream_id": streamId, "limit": String(limit)]) else {
            return []
        }
        let raw = (try? await fetchJSON(url)) ?? [:]
        guard let dict = raw as? [String: Any],
              let listings = dict["epg_listings"] as? [[String: Any]] else { return [] }
        var out: [XtreamShortEpgEntry] = []
        for row in listings {
            guard let start = asDouble(row["start_timestamp"]), let stop = asDouble(row["stop_timestamp"]) else { continue }
            let startMs = start * 1000, endMs = stop * 1000
            guard endMs > startMs else { continue }
            out.append(
                XtreamShortEpgEntry(
                    title: decodeBase64(asString(row["title"])).nonEmpty ?? "Untitled",
                    description: decodeBase64(asString(row["description"])).nonEmpty,
                    startMs: startMs,
                    endMs: endMs
                )
            )
        }
        return out
    }

    // MARK: - Networking

    private static func fetchJSON(_ url: URL) async throws -> Any {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw XtreamError.network("Xtream server returned HTTP \(http.statusCode).")
            }
            return try JSONSerialization.jsonObject(with: data, options: [])
        } catch let error as XtreamError {
            throw error
        } catch {
            throw XtreamError.network(error.localizedDescription)
        }
    }

    // MARK: - Loose JSON accessors

    private static func asString(_ value: Any?) -> String? {
        switch value {
        case let s as String: return s
        case let i as Int: return String(i)
        case let d as Double: return d == d.rounded() ? String(Int(d)) : String(d)
        case let b as Bool: return b ? "1" : "0"
        default: return nil
        }
    }

    private static func asInt(_ value: Any?) -> Int? {
        switch value {
        case let i as Int: return i
        case let d as Double: return Int(d)
        case let s as String: return Int(s) ?? Double(s).map(Int.init)
        case let b as Bool: return b ? 1 : 0
        default: return nil
        }
    }

    private static func asDouble(_ value: Any?) -> Double? {
        switch value {
        case let d as Double: return d
        case let i as Int: return Double(i)
        case let s as String: return Double(s)
        default: return nil
        }
    }

    /// Base64-decode Xtream's title/description fields, but only when the input
    /// really looks like base64 and decodes to clean UTF-8 — otherwise return it
    /// unchanged (many panels send plain text here).
    private static func decodeBase64(_ input: String?) -> String {
        guard let raw = input?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return "" }
        guard raw.range(of: "^[A-Za-z0-9+/]+={0,2}$", options: .regularExpression) != nil,
              raw.count % 4 == 0,
              let data = Data(base64Encoded: raw),
              let decoded = String(data: data, encoding: .utf8) else { return raw }
        let trimmed = decoded.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || hasControlChars(trimmed) { return raw }
        return trimmed
    }

    private static func hasControlChars(_ s: String) -> Bool {
        for scalar in s.unicodeScalars {
            let v = scalar.value
            if v < 0x20, v != 0x09, v != 0x0A, v != 0x0D { return true }
        }
        return false
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
