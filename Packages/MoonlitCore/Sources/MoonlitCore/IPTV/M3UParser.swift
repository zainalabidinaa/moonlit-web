// Packages/MoonlitCore/Sources/MoonlitCore/IPTV/M3UParser.swift
//
// Hand-rolled M3U / M3U8 playlist parser. Swift port of an external IPTV
// library's M3U handler, preserving its handling of:
//   - #EXTINF attributes (tvg-id, tvg-name, tvg-logo, group-title, catchup*)
//   - #EXTGRP sticky group, #EXTVLCOPT and #KODIPROP option lines
//   - pipe-delimited URL params (`url|User-Agent=...&Referer=...`) → request headers
//   - decorative "separator" rows (▓▓▓, ====, etc.) filtered out
//
// KODIPROP DRM license props are intentionally dropped: mpv can't play Widevine
// so carrying them would be misleading. Everything else follows the reference implementation.
import Foundation

public enum M3UParser {

    /// Parse an M3U/M3U8 document into channels. `baseId` scopes the synthesized
    /// channel ids to the owning source so ids stay unique across playlists.
    public static func parse(_ text: String, baseId: String) -> [IPTVChannel] {
        // Strip a leading UTF-8 BOM, normalize CRLF/CR to LF, then split on LF.
        let stripped = text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
        let normalized = stripped
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false)

        var out: [IPTVChannel] = []
        var pending: PendingEntry?
        var stickyGroup: String?
        var autoIndex = 0

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("#EXTM3U") { continue }

            if line.hasPrefix(Tag.extinf) {
                pending = parseExtinf(String(line.dropFirst(Tag.extinf.count)))
                continue
            }
            if line.hasPrefix(Tag.extgrp) {
                let g = line.dropFirst(Tag.extgrp.count).trimmingCharacters(in: .whitespaces)
                stickyGroup = g.isEmpty ? nil : g
                if pending != nil, !g.isEmpty { pending?.attrs["group-title"] = g }
                continue
            }
            if line.hasPrefix(Tag.extvlcopt) {
                if pending != nil { captureVlcOpt(String(line.dropFirst(Tag.extvlcopt.count)), into: &pending!.attrs) }
                continue
            }
            if line.hasPrefix(Tag.kodiprop) {
                // Parsed but discarded (DRM) — kept as a no-op for format fidelity.
                continue
            }
            if line.hasPrefix("#") { continue }

            // A non-comment line is a stream URL, optionally with `|k=v&k=v` params.
            let pipeIndex = line.firstIndex(of: "|")
            let url = pipeIndex.map { String(line[line.startIndex..<$0]) } ?? line

            if pending == nil {
                pending = PendingEntry(title: url, attrs: [:])
            }
            if let pipeIndex {
                capturePipeOpts(String(line[line.index(after: pipeIndex)...]), into: &pending!.attrs)
            }

            let attrs = pending!.attrs
            let displayName = attrs["tvg-name"]?.nonEmpty ?? pending!.title.nonEmpty ?? "Channel \(autoIndex)"
            if isDecorativeRow(displayName) {
                pending = nil
                continue
            }

            // Broken into locals so the type-checker doesn't choke on one long
            // optional-coalescing expression.
            let tvgId: String? = attrs["tvg-id"]?.nonEmpty ?? attrs["tvg-chno"]?.nonEmpty
            let idKey: String = tvgId ?? attrs["tvg-name"]?.nonEmpty ?? pending!.title.nonEmpty ?? "ch-\(autoIndex)"
            let id = "\(baseId)::\(idKey)::\(autoIndex)"
            let logo: String? = attrs["tvg-logo"]?.nonEmpty ?? attrs["logo"]?.nonEmpty
            let group: String? = attrs["group-title"]?.nonEmpty ?? attrs["group"]?.nonEmpty ?? stickyGroup
            let catchupType: String? = attrs["catchup"]?.nonEmpty ?? attrs["catchup-type"]?.nonEmpty
            let catchupSource: String? = attrs["catchup-source"]?.nonEmpty
            let catchupDays: Int? = attrs["catchup-days"].flatMap { Int($0) }
            let headers = buildHeaders(from: attrs)
            autoIndex += 1

            out.append(
                IPTVChannel(
                    id: id,
                    tvgId: tvgId,
                    name: displayName,
                    logo: logo,
                    group: group,
                    url: url,
                    catchupType: catchupType,
                    catchupSource: catchupSource,
                    catchupDays: catchupDays,
                    headers: headers
                )
            )
            pending = nil
        }
        return out
    }

    // MARK: - #EXTINF

    private struct PendingEntry {
        var title: String
        var attrs: [String: String]
    }

    private enum Tag {
        static let extinf = "#EXTINF:"
        static let extgrp = "#EXTGRP:"
        static let extvlcopt = "#EXTVLCOPT:"
        static let kodiprop = "#KODIPROP:"
    }

    /// Parses the part after `#EXTINF:` — `<duration> key="val" key=val,<title>`.
    private static func parseExtinf(_ rest: String) -> PendingEntry {
        let chars = Array(rest)
        let commaIdx = attrTitleSplit(chars)
        let attrsPart = commaIdx >= 0 ? String(chars[0..<commaIdx]) : rest
        let titlePart = commaIdx >= 0 ? String(chars[(commaIdx + 1)...]).trimmingCharacters(in: .whitespaces) : ""

        let tokens = attrsPart.trimmingCharacters(in: .whitespaces)
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .map(String.init)

        var attrs: [String: String] = [:]
        var i = 0
        while i < tokens.count {
            let tok = tokens[i]
            defer { i += 1 }
            if tok.isEmpty { continue }
            guard let eq = tok.firstIndex(of: "=") else {
                // A bare leading numeric token is the duration; we don't retain it.
                continue
            }
            let key = tok[tok.startIndex..<eq].lowercased()
            var val = String(tok[tok.index(after: eq)...])
            if val.hasPrefix("\"") {
                var combined = val
                // A quoted value can contain spaces, so keep absorbing tokens until
                // the quotes balance.
                while !isClosedQuoted(combined), i + 1 < tokens.count {
                    i += 1
                    combined += " " + tokens[i]
                }
                val = trimQuotes(combined)
            }
            attrs[key] = val
        }
        return PendingEntry(title: titlePart, attrs: attrs)
    }

    private static func isClosedQuoted(_ s: String) -> Bool {
        if s.count < 2 { return false }
        if !s.hasPrefix("\"") { return true }
        return s.hasSuffix("\"") && s.filter { $0 == "\"" }.count % 2 == 0
    }

    private static func trimQuotes(_ s: String) -> String {
        var result = s
        if result.hasPrefix("\"") { result.removeFirst() }
        if result.hasSuffix("\"") { result.removeLast() }
        return result
    }

    /// Finds the comma that separates the attribute block from the display title:
    /// the first unquoted comma after the last closing quote (falling back to the
    /// first unquoted comma overall).
    private static func attrTitleSplit(_ s: [Character]) -> Int {
        var inQuote = false
        var lastQuoteClose = -1
        for i in s.indices where s[i] == "\"" {
            if inQuote { lastQuoteClose = i }
            inQuote.toggle()
        }
        let after = firstUnquotedComma(s, start: lastQuoteClose >= 0 ? lastQuoteClose + 1 : 0)
        if after >= 0 { return after }
        return firstUnquotedComma(s, start: 0)
    }

    private static func firstUnquotedComma(_ s: [Character], start: Int) -> Int {
        var inQuote = false
        var i = start
        while i < s.count {
            let c = s[i]
            if c == "\"" { inQuote.toggle() }
            else if c == "," && !inQuote { return i }
            i += 1
        }
        return -1
    }

    // MARK: - Option lines & headers

    private static func captureVlcOpt(_ rest: String, into attrs: inout [String: String]) {
        guard let eq = rest.firstIndex(of: "=") else { return }
        let key = rest[rest.startIndex..<eq].trimmingCharacters(in: .whitespaces).lowercased()
        let val = trimQuotes(String(rest[rest.index(after: eq)...]).trimmingCharacters(in: .whitespaces))
        if val.isEmpty { return }
        if key == "http-user-agent" { attrs["vlcopt-user-agent"] = val }
        else if key == "http-referrer" { attrs["vlcopt-referrer"] = val }
    }

    private static func capturePipeOpts(_ rest: String, into attrs: inout [String: String]) {
        for pair in rest.split(separator: "&", omittingEmptySubsequences: true) {
            guard let eq = pair.firstIndex(of: "=") else { continue }
            let key = pair[pair.startIndex..<eq].trimmingCharacters(in: .whitespaces).lowercased()
            let val = safeDecode(String(pair[pair.index(after: eq)...]).trimmingCharacters(in: .whitespaces))
            if val.isEmpty { continue }
            if key == "user-agent", attrs["vlcopt-user-agent"] == nil { attrs["vlcopt-user-agent"] = val }
            else if (key == "referer" || key == "referrer"), attrs["vlcopt-referrer"] == nil { attrs["vlcopt-referrer"] = val }
            else if key == "cookie", attrs["vlcopt-cookie"] == nil { attrs["vlcopt-cookie"] = val }
        }
    }

    /// Maps the captured VLC/pipe options into real HTTP request headers for mpv.
    private static func buildHeaders(from attrs: [String: String]) -> [String: String]? {
        var headers: [String: String] = [:]
        if let ua = attrs["vlcopt-user-agent"]?.nonEmpty { headers["User-Agent"] = ua }
        if let ref = attrs["vlcopt-referrer"]?.nonEmpty { headers["Referer"] = ref }
        if let cookie = attrs["vlcopt-cookie"]?.nonEmpty { headers["Cookie"] = cookie }
        return headers.isEmpty ? nil : headers
    }

    private static func safeDecode(_ s: String) -> String {
        s.removingPercentEncoding ?? s
    }

    // MARK: - Decorative-row filtering

    private static let decorativeChars = Set("#=─━▓█▀▄░♦◆■▼▲★☆-_*+~|·•:. \t")

    /// A "channel" whose name is only box-drawing/separator glyphs (or has no
    /// letters/digits at all) is a visual divider row, not a real channel.
    private static func isDecorativeRow(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return true }
        if trimmed.allSatisfy({ decorativeChars.contains($0) }) { return true }
        let hasAlphanumeric = trimmed.contains { $0.isLetter || $0.isNumber }
        return !hasAlphanumeric
    }

    // MARK: - EPG derivation

    /// If `playlistUrl` is an Xtream `get.php`/`player_api.php` link with embedded
    /// credentials, derive the matching XMLTV EPG URLs (`xmltv.php`, `get.php?type=epg`).
    public static func deriveEpgUrls(from playlistUrl: String) -> [String] {
        guard let u = URLComponents(string: playlistUrl),
              let host = u.host,
              let scheme = u.scheme else { return [] }
        let path = u.path
        guard path.hasSuffix("get.php") || path.hasSuffix("player_api.php") else { return [] }
        let items = u.queryItems ?? []
        guard let username = items.first(where: { $0.name == "username" })?.value,
              let password = items.first(where: { $0.name == "password" })?.value else { return [] }
        let portPart = u.port.map { ":\($0)" } ?? ""
        let base = "\(scheme)://\(host)\(portPart)"

        var xmltv = URLComponents(string: "\(base)/xmltv.php")!
        xmltv.queryItems = [.init(name: "username", value: username), .init(name: "password", value: password)]
        var getPhp = URLComponents(string: "\(base)/get.php")!
        getPhp.queryItems = [
            .init(name: "username", value: username),
            .init(name: "password", value: password),
            .init(name: "type", value: "epg"),
        ]
        return [xmltv.string, getPhp.string].compactMap { $0 }
    }
}

private extension String {
    /// `nil` when the string is empty, otherwise itself — for the `?? fallback` chains.
    var nonEmpty: String? { isEmpty ? nil : self }
}
