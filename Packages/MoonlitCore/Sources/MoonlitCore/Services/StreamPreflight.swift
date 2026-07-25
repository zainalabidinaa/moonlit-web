import Foundation

public enum StreamPreflight {
    public static func isReachable(url: String, headers: [String: String] = [:]) async -> Bool {
        guard let requestUrl = URL(string: url) else { return false }
        var request = URLRequest(url: requestUrl, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 3)
        request.httpMethod = "GET"
        request.setValue("bytes=0-4095", forHTTPHeaderField: "Range")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse else { return false }

        let status = httpResponse.statusCode
        let statusOk = (200...208).contains(status) || status == 416
        guard statusOk, status != 401, status != 403, status != 429 else {
            return false
        }

        let contentType = (httpResponse.allHeaderFields["Content-Type"] as? String)?.lowercased() ?? ""
        if contentType.contains("text/html") { return false }

        // Stub-file heuristic: a source that
        // isn't actually ready often resolves to a tiny placeholder. If the total
        // size is known and implausibly small for real media (< 5 MB), treat it as
        // not-really-ready so the caller falls through to the next source.
        let minRealSizeBytes = 5 * 1024 * 1024
        if let total = Self.totalSize(from: httpResponse), total > 0, total < minRealSizeBytes {
            return false
        }

        guard !data.isEmpty else { return true }

        let chunk = data.prefix(4096)
        let body = String(data: chunk, encoding: .utf8)
            ?? String(data: chunk, encoding: .isoLatin1)
            ?? ""
        let lower = body.lowercased()

        var jsonFields = ""
        if let json = try? JSONSerialization.jsonObject(with: chunk) as? [String: Any] {
            jsonFields = json.compactMap { "\($0.key): \($0.value)" }.joined(separator: " ").lowercased()
        }

        let combined = lower + " " + jsonFields
        let errorMarkers: [String] = [
            "media_not_cached_yet",
            "not downloaded",
            "not cached",
            "not yet cached",
            "downloading",
            "caching",
            "queued",
            "try again shortly",
            "being prepared",
            "wait a short while",
            "something went wrong",
            "unexpected error resolving",
            "access denied",
            "invalid token",
            "subscription",
            "internal provider issue",
            "please retry later",
        ]
        for term in errorMarkers {
            if combined.contains(term) { return false }
        }

        if let json = try? JSONSerialization.jsonObject(with: chunk) as? [String: Any],
           let errorValue = json["error"] as? String, !errorValue.isEmpty,
           json["streams"] == nil, json["url"] == nil, json["data"] == nil {
            return false
        }
        return true
    }

    /// Total byte size of the resource from a range/length response, if known.
    /// Prefers the `Content-Range` total (`bytes 0-4095/12345678`) and falls back
    /// to `Content-Length` on a full `200` response.
    private static func totalSize(from response: HTTPURLResponse) -> Int? {
        if let range = response.allHeaderFields["Content-Range"] as? String,
           let slash = range.lastIndex(of: "/") {
            let totalPart = range[range.index(after: slash)...].trimmingCharacters(in: .whitespaces)
            if let total = Int(totalPart) { return total }
        }
        // A 206 partial without a total tells us nothing; only trust Content-Length
        // when the server returned the whole body (200).
        if response.statusCode == 200,
           let lengthStr = response.allHeaderFields["Content-Length"] as? String,
           let length = Int(lengthStr) {
            return length
        }
        return nil
    }
}
