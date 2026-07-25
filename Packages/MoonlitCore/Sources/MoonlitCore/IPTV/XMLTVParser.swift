// Packages/MoonlitCore/Sources/MoonlitCore/IPTV/XMLTVParser.swift
//
// XMLTV EPG parser. Swift port of an external IPTV library's XMLTV handler. Like the
// avoids a full DOM parse (guides are big) and instead scans for <channel>/<programme>
// blocks. The scan advances a single cursor rather than re-slicing, so it's O(n).
//
// Non-streaming: fetches the whole body (gunzipping .xml.gz), then parses. A streaming
// progressive parse can be layered on later if
// memory pressure ever demands it.
import Foundation

public enum XMLTVParser {

    // MARK: - Fetch

    public static func fetchAndParse(url urlString: String) async throws -> EPGParseResult {
        guard let url = URL(string: urlString) else { throw XtreamError.network("Invalid EPG URL: \(urlString)") }
        var request = URLRequest(url: url)
        request.setValue("VLC/3.0.20 LibVLC/3.0.20", forHTTPHeaderField: "User-Agent")
        request.setValue("application/xml, text/xml, application/octet-stream, */*", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw XtreamError.network("EPG fetch failed: HTTP \(http.statusCode)")
        }
        let xmlData = Gzip.isGzipped(data) ? (Gzip.gunzip(data) ?? data) : data
        let text = String(decoding: xmlData, as: UTF8.self)
        return parse(text)
    }

    // MARK: - Parse

    public static func parse(_ text: String) -> EPGParseResult {
        var programs: [EPGProgram] = []
        var channelMeta: [String: EPGChannelMeta] = [:]
        let end = text.endIndex
        var cursor = text.startIndex

        while true {
            let chRange = text.range(of: "<channel ", range: cursor..<end)
            let prRange = text.range(of: "<programme", range: cursor..<end)
            if chRange == nil && prRange == nil { break }

            let channelFirst: Bool
            if let ch = chRange, let pr = prRange {
                channelFirst = ch.lowerBound < pr.lowerBound
            } else {
                channelFirst = chRange != nil
            }

            if channelFirst, let ch = chRange {
                guard let close = text.range(of: "</channel>", range: ch.lowerBound..<end) else { break }
                parseChannel(text[ch.lowerBound..<close.upperBound], into: &channelMeta)
                cursor = close.upperBound
            } else if let pr = prRange {
                guard let openClose = text.range(of: ">", range: pr.lowerBound..<end) else { break }
                guard let endTag = text.range(of: "</programme>", range: openClose.upperBound..<end) else { break }
                if let program = parseProgramme(text[pr.lowerBound..<endTag.upperBound]) {
                    programs.append(program)
                }
                cursor = endTag.upperBound
            } else {
                break
            }
        }
        return EPGParseResult(programs: programs, channelMeta: channelMeta)
    }

    // MARK: - Block parsers

    private static func parseChannel(_ block: Substring, into channelMeta: inout [String: EPGChannelMeta]) {
        guard let id = attrValue(block, "id") else { return }
        let displayName = childText(block, "display-name")
        let icon = childAttr(block, "icon", "src")
        // Don't overwrite a richer entry with an emptier duplicate.
        if channelMeta[id] != nil && displayName == nil && icon == nil { return }
        channelMeta[id] = EPGChannelMeta(displayName: displayName, icon: icon)
    }

    private static func parseProgramme(_ block: Substring) -> EPGProgram? {
        guard let start = attrValue(block, "start"),
              let stop = attrValue(block, "stop"),
              let channel = attrValue(block, "channel") else { return nil }
        let startMs = parseXmltvTime(start)
        let endMs = parseXmltvTime(stop)
        guard startMs.isFinite, endMs.isFinite, endMs > startMs else { return nil }
        return EPGProgram(
            channelTvgId: channel,
            title: childText(block, "title") ?? "Untitled",
            description: childText(block, "desc"),
            category: childText(block, "category"),
            iconUrl: childAttr(block, "icon", "src"),
            startMs: startMs,
            endMs: endMs
        )
    }

    // MARK: - Tag / attribute extraction

    /// Reads `name="value"` from a block, requiring the name to sit on an attribute
    /// boundary (preceded by whitespace) so `start` doesn't match inside another attr.
    private static func attrValue(_ s: Substring, _ name: String) -> String? {
        let needle = "\(name)=\""
        var searchStart = s.startIndex
        while let r = s.range(of: needle, range: searchStart..<s.endIndex) {
            if r.lowerBound != s.startIndex {
                let prev = s[s.index(before: r.lowerBound)]
                if prev == " " || prev == "\t" || prev == "\n" || prev == "\r" {
                    guard let q = s[r.upperBound...].firstIndex(of: "\"") else { return nil }
                    return String(s[r.upperBound..<q])
                }
            }
            searchStart = r.upperBound
        }
        return nil
    }

    private static func childText(_ block: Substring, _ tag: String) -> String? {
        guard let open = block.range(of: "<\(tag)") else { return nil }
        guard let openClose = block.range(of: ">", range: open.upperBound..<block.endIndex) else { return nil }
        guard let close = block.range(of: "</\(tag)>", range: openClose.upperBound..<block.endIndex) else { return nil }
        let raw = String(block[openClose.upperBound..<close.lowerBound])
        let decoded = decode(stripCdata(raw)).trimmingCharacters(in: .whitespacesAndNewlines)
        return decoded.isEmpty ? nil : decoded
    }

    private static func childAttr(_ block: Substring, _ tag: String, _ attrName: String) -> String? {
        guard let open = block.range(of: "<\(tag)") else { return nil }
        guard let openClose = block.range(of: ">", range: open.upperBound..<block.endIndex) else { return nil }
        return attrValue(block[open.lowerBound..<openClose.lowerBound], attrName)
    }

    // MARK: - Text decoding

    private static func stripCdata(_ s: String) -> String {
        guard s.contains("<![CDATA[") else { return s }
        var result = s
        while let open = result.range(of: "<![CDATA[") {
            guard let close = result.range(of: "]]>", range: open.upperBound..<result.endIndex) else { break }
            let inner = String(result[open.upperBound..<close.lowerBound])
            result.replaceSubrange(open.lowerBound..<close.upperBound, with: inner)
        }
        return result
    }

    private static func decode(_ s: String) -> String {
        guard s.contains("&") else { return s }
        var r = s
        r = r.replacingOccurrences(of: "&lt;", with: "<")
        r = r.replacingOccurrences(of: "&gt;", with: ">")
        r = r.replacingOccurrences(of: "&quot;", with: "\"")
        r = r.replacingOccurrences(of: "&apos;", with: "'")
        r = decodeNumericEntities(r)
        r = r.replacingOccurrences(of: "&amp;", with: "&")
        return r
    }

    private static func decodeNumericEntities(_ s: String) -> String {
        guard s.contains("&#") else { return s }
        var result = ""
        result.reserveCapacity(s.count)
        var i = s.startIndex
        while i < s.endIndex {
            if s[i] == "&",
               s.index(after: i) < s.endIndex, s[s.index(after: i)] == "#",
               let semi = s[i...].firstIndex(of: ";") {
                var numStr = s[s.index(i, offsetBy: 2)..<semi]
                var radix = 10
                if let f = numStr.first, f == "x" || f == "X" { radix = 16; numStr = numStr.dropFirst() }
                if let code = UInt32(numStr, radix: radix), let scalar = Unicode.Scalar(code) {
                    result.append(Character(scalar))
                    i = s.index(after: semi)
                    continue
                }
            }
            result.append(s[i])
            i = s.index(after: i)
        }
        return result
    }

    // MARK: - Timestamp

    /// Parse an XMLTV timestamp `YYYYMMDDHHMMSS [+/-HHMM]` to epoch milliseconds.
    /// Returns `.nan` on malformed input.
    public static func parseXmltvTime(_ raw: String) -> Double {
        let bytes = Array(raw.trimmingCharacters(in: .whitespaces).utf8)
        guard bytes.count >= 14 else { return .nan }
        func num(_ a: Int, _ b: Int) -> Int? {
            guard b <= bytes.count else { return nil }
            var v = 0
            for k in a..<b {
                let c = bytes[k]
                guard c >= 48, c <= 57 else { return nil }
                v = v * 10 + Int(c - 48)
            }
            return v
        }
        guard let y = num(0, 4), let mo = num(4, 6), let d = num(6, 8),
              let h = num(8, 10), let mi = num(10, 12), let sec = num(12, 14) else { return .nan }

        var offsetMin = 0
        var idx = 14
        while idx < bytes.count, bytes[idx] == 32 { idx += 1 } // skip spaces
        if idx < bytes.count, bytes[idx] == 43 || bytes[idx] == 45 { // '+' or '-'
            let sign = bytes[idx] == 45 ? -1 : 1
            if let hh = num(idx + 1, idx + 3), let mm = num(idx + 3, idx + 5) {
                offsetMin = sign * (hh * 60 + mm)
            }
        }

        var comps = DateComponents()
        comps.year = y; comps.month = mo; comps.day = d
        comps.hour = h; comps.minute = mi; comps.second = sec
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        guard let date = cal.date(from: comps) else { return .nan }
        return date.timeIntervalSince1970 * 1000 - Double(offsetMin) * 60_000
    }
}
