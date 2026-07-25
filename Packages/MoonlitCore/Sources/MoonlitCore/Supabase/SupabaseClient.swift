import Foundation

public actor SupabaseClient {
    public static let shared = SupabaseClient()

    private let baseURL: String
    private let anonKey: String
    var accessToken: String?
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    private init() {
        self.baseURL = MoonlitConfig.supabaseURL
        self.anonKey = MoonlitConfig.supabaseAnonKey
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            if let date = isoFormatter.date(from: dateString) { return date }
            // Fallback: try without fractional seconds
            let noFraction = ISO8601DateFormatter()
            noFraction.formatOptions = [.withInternetDateTime]
            if let date = noFraction.date(from: dateString) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(dateString)")
        }
        self.encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(isoFormatter.string(from: date))
        }

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 20
        config.httpMaximumConnectionsPerHost = 3
        self.session = URLSession(configuration: config)
    }

    public func setAccessToken(_ token: String?) {
        self.accessToken = token
    }

    /// Invoked when a request comes back 401 (access token expired mid-session).
    /// Should refresh the Supabase session and return the new access token, or
    /// nil if refresh failed. Registered by ProfileManager.
    private var authRefreshHandler: (@Sendable () async -> String?)?
    private var refreshTask: Task<String?, Never>?

    public func setAuthRefreshHandler(_ handler: @escaping @Sendable () async -> String?) {
        self.authRefreshHandler = handler
    }

    /// Single-flight token refresh: concurrent 401s await the same refresh so
    /// the rotated refresh token is never used twice (Supabase revokes the
    /// whole session family on refresh-token reuse).
    private func refreshedToken() async -> String? {
        if let task = refreshTask { return await task.value }
        guard let handler = authRefreshHandler else { return nil }
        let task = Task { await handler() }
        refreshTask = task
        let token = await task.value
        refreshTask = nil
        if let token { accessToken = token }
        return token
    }

    /// All PostgREST traffic goes through here. Tokens expire ~1h in; without
    /// this, every sync write after expiry fails 401 and marked-watched /
    /// progress data is silently lost until the next app launch.
    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 401 else { return (data, response) }
        guard let newToken = await refreshedToken() else { return (data, response) }
        var retried = request
        retried.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
        return try await session.data(for: retried)
    }

    private func makeRequest(
        path: String,
        method: String = "GET",
        body: Data? = nil,
        prefer: String? = nil,
        range: (lower: Int, upper: Int)? = nil
    ) -> URLRequest {
        let url = URL(string: "\(baseURL)/rest/v1\(path)")!
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.assumesHTTP3Capable = false
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let prefer = prefer {
            request.setValue(prefer, forHTTPHeaderField: "Prefer")
        }
        if let range = range {
            // PostgREST range pagination: `Range: lower-upper` (inclusive, 0-based).
            request.setValue("items", forHTTPHeaderField: "Range-Unit")
            request.setValue("\(range.lower)-\(range.upper)", forHTTPHeaderField: "Range")
        }
        if let body = body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
            request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        }
        return request
    }

    public func select<T: Decodable>(
        from table: String,
        where query: [String: String] = [:],
        order: String? = nil,
        limit: Int? = nil
    ) async throws -> [T] {
        var path = "/\(table)?select=*"
        for (key, value) in query {
            path += "&\(key)=eq.\(value)"
        }

        // Explicit-limit callers keep single-request semantics.
        if let limit = limit {
            if let order = order {
                path += "&order=\(order)"
            }
            path += "&limit=\(limit)"
            return try await decodePage(path: path, range: nil)
        }

        // No explicit limit: page through ALL rows. Hosted Supabase's PostgREST
        // caps a single response at `max-rows` (1000), so an unpaginated fetch
        // silently drops everything past row 1000 (this is what left ~40% of
        // folders with no catalogs). Range pagination needs a STABLE, unique sort
        // key or page boundaries can dupe/skip rows, so always end the sort on
        // `id` (unique). Every no-limit caller's table has an `id` column.
        let effectiveOrder = order.map { "\($0),id" } ?? "id"
        path += "&order=\(effectiveOrder)"

        let pageSize = 1000
        var offset = 0
        var all: [T] = []
        while true {
            let page: [T] = try await decodePage(
                path: path,
                range: (lower: offset, upper: offset + pageSize - 1)
            )
            all.append(contentsOf: page)
            if page.count < pageSize { break }
            offset += pageSize
        }
        return all
    }

    private func decodePage<T: Decodable>(
        path: String,
        range: (lower: Int, upper: Int)?
    ) async throws -> [T] {
        let request = makeRequest(path: path, prefer: "return=representation", range: range)
        let (data, response) = try await perform(request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw SupabaseError.requestFailed((response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        if data.isEmpty { return [] }
        return try decoder.decode([T].self, from: data)
    }

    public func insert<T: Encodable, R: Decodable>(
        into table: String,
        value: T
    ) async throws -> R {
        let body = try encoder.encode(value)
        let request = makeRequest(path: "/\(table)", method: "POST", body: body)
        let (data, response) = try await perform(request)

        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(statusCode) else {
            throw SupabaseError.requestFailed(statusCode)
        }

        if data.isEmpty { throw SupabaseError.emptyResponse }
        return try decoder.decode(R.self, from: data)
    }

    public func insertAndReturnArray<T: Encodable, R: Decodable>(
        into table: String,
        value: T
    ) async throws -> [R] {
        let body = try encoder.encode(value)
        let request = makeRequest(path: "/\(table)", method: "POST", body: body)
        let (data, response) = try await perform(request)

        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(code) else {
            throw SupabaseError.requestFailed(code)
        }

        if data.isEmpty { return [] }
        return try decoder.decode([R].self, from: data)
    }

    public func update<T: Encodable>(
        table: String,
        where query: [String: String],
        value: T
    ) async throws {
        var path = "/\(table)?"
        path += query.map { "\($0.key)=eq.\($0.value)" }.joined(separator: "&")

        let body = try encoder.encode(value)
        let request = makeRequest(path: path, method: "PATCH", body: body)
        let (_, response) = try await perform(request)

        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(code) else {
            throw SupabaseError.requestFailed(code)
        }
    }

    public func upsert<T: Encodable>(
        into table: String,
        onConflict: String,
        value: T
    ) async throws {
        let path = "/\(table)?on_conflict=\(onConflict)"
        let body = try encoder.encode(value)
        var request = makeRequest(path: path, method: "POST", body: body)
        request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")

        let (_, response) = try await perform(request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(code) else {
            throw SupabaseError.requestFailed(code)
        }
    }

    public func delete(
        from table: String,
        where query: [String: String]
    ) async throws {
        var path = "/\(table)?"
        path += query.map { "\($0.key)=eq.\($0.value)" }.joined(separator: "&")

        let request = makeRequest(path: path, method: "DELETE")
        let (_, response) = try await perform(request)

        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(code) else {
            throw SupabaseError.requestFailed(code)
        }
    }

    public func rpc<T: Decodable>(
        function: String,
        params: [String: Any] = [:]
    ) async throws -> T {
        let url = URL(string: "\(baseURL)/rest/v1/rpc/\(function)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let body = try JSONSerialization.data(withJSONObject: params)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await perform(request)

        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(code) else {
            throw SupabaseError.requestFailed(code)
        }

        return try decoder.decode(T.self, from: data)
    }
}

public enum SupabaseError: Error, LocalizedError {
    case requestFailed(Int)
    case emptyResponse
    case authFailed(String)
    case signUpRequiresInvite
    case notAuthenticated
    case profileNotFound

    public var errorDescription: String? {
        switch self {
        case .requestFailed(let code):
            return "Request failed (HTTP \(code))"
        case .emptyResponse:
            return "Empty response from server"
        case .authFailed(let body):
            // Try to extract a readable error message from the Supabase error body
            if let data = body.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let msg = json["msg"] as? String { return msg }
                if let reason = json["error_description"] as? String { return reason }
                if let err = json["error"] as? String { return err }
            }
            return body.isEmpty ? "Authentication failed" : body
        case .signUpRequiresInvite:
            return "Invalid or expired invite code"
        case .notAuthenticated:
            return "Not authenticated — please sign in"
        case .profileNotFound:
            return "Profile not found"
        }
    }
}
