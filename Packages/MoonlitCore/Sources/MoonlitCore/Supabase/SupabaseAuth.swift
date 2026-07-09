import Foundation

public actor SupabaseAuth {
    public static let shared = SupabaseAuth()
    private let client = SupabaseClient.shared
    private let baseURL = MoonlitConfig.supabaseURL
    private let anonKey = MoonlitConfig.supabaseAnonKey
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 20
        config.httpMaximumConnectionsPerHost = 2
        self.session = URLSession(configuration: config)
    }

    private struct AuthResponse: Codable {
        let access_token: String
        let refresh_token: String
        let expires_in: Int
        let user: AuthUser
    }

    private struct AuthUser: Codable {
        let id: String
        let email: String?
        let identities: [AuthIdentity]?
    }

    private struct AuthIdentity: Codable {
        let id: String
        let provider: String
    }

    public func signIn(email: String, password: String) async throws -> UserSession {
        let url = URL(string: "\(baseURL)/auth/v1/token?grant_type=password")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.assumesHTTP3Capable = false
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = ["email": email, "password": password]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(code) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw SupabaseError.authFailed(errorBody)
        }

        let decoder = JSONDecoder()
        let authResp = try decoder.decode(AuthResponse.self, from: data)

        let session = UserSession(
            accessToken: authResp.access_token,
            refreshToken: authResp.refresh_token,
            expiresAt: Date().addingTimeInterval(TimeInterval(authResp.expires_in)),
            userId: authResp.user.id,
            email: authResp.user.email
        )

        await client.setAccessToken(session.accessToken)
        return session
    }

    public func signUp(email: String, password: String, inviteCode: String) async throws -> UserSession {
        let isValid = try await validateInviteCode(inviteCode)
        guard isValid else {
            throw SupabaseError.signUpRequiresInvite
        }

        let url = URL(string: "\(baseURL)/auth/v1/signup")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.assumesHTTP3Capable = false
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "email": email,
            "password": password
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(code) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw SupabaseError.authFailed(errorBody)
        }

        let decoder = JSONDecoder()
        let authResp = try decoder.decode(AuthResponse.self, from: data)

        try await markInviteCodeUsed(code: inviteCode, userId: authResp.user.id)

        let session = UserSession(
            accessToken: authResp.access_token,
            refreshToken: authResp.refresh_token,
            expiresAt: Date().addingTimeInterval(TimeInterval(authResp.expires_in)),
            userId: authResp.user.id,
            email: authResp.user.email
        )

        await client.setAccessToken(session.accessToken)
        return session
    }

    public func refreshSession(refreshToken: String) async throws -> UserSession {
        let url = URL(string: "\(baseURL)/auth/v1/token?grant_type=refresh_token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.assumesHTTP3Capable = false
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = ["refresh_token": refreshToken]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw SupabaseError.authFailed("Refresh failed")
        }

        let decoder = JSONDecoder()
        let authResp = try decoder.decode(AuthResponse.self, from: data)

        let session = UserSession(
            accessToken: authResp.access_token,
            refreshToken: authResp.refresh_token,
            expiresAt: Date().addingTimeInterval(TimeInterval(authResp.expires_in)),
            userId: authResp.user.id,
            email: authResp.user.email
        )

        await client.setAccessToken(session.accessToken)
        return session
    }

    public func signOut() async throws {
        let url = URL(string: "\(baseURL)/auth/v1/logout")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.assumesHTTP3Capable = false
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = await client.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (_, _) = try await session.data(for: request)
        await client.setAccessToken(nil)
    }

    public func resetPassword(email: String) async throws {
        let url = URL(string: "\(baseURL)/auth/v1/recover")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.assumesHTTP3Capable = false
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "email": email,
            "redirect_to": "https://trymoonlit.app/login"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(code) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw SupabaseError.authFailed(errorBody)
        }
    }

    public func signInWithApple(idToken: String, nonce: String) async throws -> UserSession {
        let url = URL(string: "\(baseURL)/auth/v1/token?grant_type=id_token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.assumesHTTP3Capable = false
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = ["provider": "apple", "id_token": idToken, "nonce": nonce]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(code) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw SupabaseError.authFailed(errorBody)
        }

        let decoder = JSONDecoder()
        let authResp = try decoder.decode(AuthResponse.self, from: data)
        let sess = UserSession(
            accessToken: authResp.access_token,
            refreshToken: authResp.refresh_token,
            expiresAt: Date().addingTimeInterval(TimeInterval(authResp.expires_in)),
            userId: authResp.user.id,
            email: authResp.user.email
        )
        await client.setAccessToken(sess.accessToken)
        return sess
    }

    public func linkAppleAccount(idToken: String, nonce: String, accessToken: String) async throws {
        let url = URL(string: "\(baseURL)/functions/v1/link-apple")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.assumesHTTP3Capable = false
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let body: [String: String] = ["id_token": idToken]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(code) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw SupabaseError.authFailed(errorBody)
        }
    }

    public func fetchAppleIdentityId(accessToken: String) async throws -> String? {
        let url = URL(string: "\(baseURL)/auth/v1/user")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.assumesHTTP3Capable = false
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(code) else { return nil }
        let user = try JSONDecoder().decode(AuthUser.self, from: data)
        return user.identities?.first(where: { $0.provider == "apple" })?.id
    }

    public func unlinkAppleAccount(identityId: String, accessToken: String) async throws {
        let url = URL(string: "\(baseURL)/auth/v1/user/identities/\(identityId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.assumesHTTP3Capable = false
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(code) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw SupabaseError.authFailed(errorBody)
        }
    }

    public func deleteAccount(accessToken: String) async throws {
        let url = URL(string: "\(baseURL)/functions/v1/delete-user")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.assumesHTTP3Capable = false
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")

        let (_, response) = try await session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(code) else {
            throw SupabaseError.authFailed("Account deletion failed")
        }
        await client.setAccessToken(nil)
    }

    private func validateInviteCode(_ code: String) async throws -> Bool {
        let codes: [InviteCode] = try await client.select(
            from: "invite_codes",
            where: ["code": code]
        )
        guard let inviteCode = codes.first else { return false }
        return inviteCode.isActive && !inviteCode.isUsed
    }

    private func markInviteCodeUsed(code: String, userId: String) async throws {
        struct InviteUpdate: Encodable {
            let used_by: String
            let used_at: String
        }
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSZZZZZ"
        let update = InviteUpdate(
            used_by: userId,
            used_at: dateFormatter.string(from: Date())
        )
        try await client.update(
            table: "invite_codes",
            where: ["code": code],
            value: update
        )
    }
}
