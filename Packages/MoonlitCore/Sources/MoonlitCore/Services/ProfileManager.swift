import Foundation

@MainActor
public class ProfileManager: ObservableObject {
    public static let shared = ProfileManager()

    @Published public var profiles: [MoonlitProfile] = []
    @Published public var currentProfile: MoonlitProfile?
    @Published public var currentSession: UserSession?
    @Published public var isLoading = false
    @Published public var isAuthenticated = false
    @Published public var hasRestoredSession = false

    private let auth = SupabaseAuth.shared
    private let syncService = SyncService.shared
    private let client = SupabaseClient.shared

    private init() {
        Task {
            await client.setAuthRefreshHandler { [weak self] in
                await self?.refreshAccessToken()
            }
            await restoreSession()
        }
    }

    /// Called by SupabaseClient when a request 401s mid-session (access tokens
    /// expire after ~1h). Refreshes the session and returns the new access
    /// token so the failed request can be retried instead of silently dropped.
    private func refreshAccessToken() async -> String? {
        guard let stored = currentSession ?? SessionStore.load() else { return nil }
        guard let refreshed = try? await auth.refreshSession(refreshToken: stored.refreshToken) else {
            NSLog("[Moonlit][Auth] mid-session token refresh FAILED — sync writes will not persist")
            return nil
        }
        currentSession = refreshed
        SessionStore.save(refreshed)
        NSLog("[Moonlit][Auth] mid-session token refresh succeeded")
        return refreshed.accessToken
    }

    private func restoreSession() async {
        isLoading = true
        let startTime = Date()
        NSLog("[Moonlit][Perf] restoreSession start")
        defer {
            Task { @MainActor in
                let elapsed = Date().timeIntervalSince(startTime)
                NSLog("[Moonlit][Perf] restoreSession auth done in %.2fs, authenticated=%{public}@", elapsed, self.isAuthenticated ? "YES" : "NO")
                if self.isAuthenticated, let profile = self.currentProfile {
                    await StartupCoordinator.shared.startPhase1(
                        profileId: profile.id,
                        collectionRepo: CollectionRepository.shared,
                        addonRepo: AddonRepository.shared,
                        catalogRepo: CatalogRepository.shared,
                        homeRepo: HomeRepository.shared,
                        recsService: RecommendationsService.shared,
                        libraryRepo: LibraryRepository.shared
                    )
                }
                let remaining = 1.5 - elapsed
                if remaining > 0 {
                    NSLog("[Moonlit][Perf] restoreSession artificial delay %.2fs (elapsed %.2fs)", remaining, elapsed)
                    try? await Task.sleep(for: .seconds(remaining))
                }
                NSLog("[Moonlit][Perf] restoreSession complete, total elapsed %.2fs", Date().timeIntervalSince(startTime))
                self.isLoading = false
                self.hasRestoredSession = true
            }
        }

        guard let stored = SessionStore.load() else {
            self.isAuthenticated = false
            return
        }
        self.currentSession = stored
        await client.setAccessToken(stored.accessToken)

        // Restore from local cache immediately so the router never lands on
        // CreateFirstProfileScreen due to a transient network failure.
        restoreProfilesFromCache(userId: stored.userId)

        if stored.isExpired {
            guard let refreshed = try? await auth.refreshSession(refreshToken: stored.refreshToken) else {
                SessionStore.clear()
                self.currentSession = nil
                self.isAuthenticated = false
                return
            }
            self.currentSession = refreshed
            SessionStore.save(refreshed)
            try? await loadProfiles(userId: refreshed.userId)
        } else {
            try? await loadProfiles(userId: stored.userId)
        }
        self.isAuthenticated = true
    }

    private func profilesCacheKey(userId: String) -> String { "moonlit.cachedProfiles.\(userId)" }

    private func restoreProfilesFromCache(userId: String) {
        guard profiles.isEmpty,
              let data = UserDefaults.standard.data(forKey: profilesCacheKey(userId: userId)),
              let cached = try? JSONDecoder().decode([MoonlitProfile].self, from: data),
              !cached.isEmpty else { return }
        self.profiles = cached
        let savedId = UserDefaults.standard.string(forKey: "moonlit.currentProfileId")
        if let savedId, let match = cached.first(where: { $0.id == savedId }) {
            self.currentProfile = match
        } else {
            self.currentProfile = cached.first
        }
    }

    public func signIn(email: String, password: String) async throws {
        let session = try await auth.signIn(email: email, password: password)
        self.currentSession = session
        SessionStore.save(session)
        try await loadProfiles(userId: session.userId)
        self.isAuthenticated = true
    }

    public func signInWithApple(idToken: String, nonce: String) async throws {
        let session = try await auth.signInWithApple(idToken: idToken, nonce: nonce)
        self.currentSession = session
        SessionStore.save(session)
        try? await loadProfiles(userId: session.userId)
        NSLog("[Moonlit][AppleSignIn] resolved userId=%@ email=%@ profiles=%ld",
              session.userId, session.email ?? "nil", profiles.count)
        if profiles.isEmpty {
            NSLog("[Moonlit][AppleSignIn] no profiles for this user — this is a NEW/different Supabase account")
            try? await createProfile(name: "Profile")
        }
        self.isAuthenticated = true
    }

    public func linkAppleAccount(idToken: String, nonce: String) async throws {
        guard let session = currentSession else { throw SupabaseError.notAuthenticated }
        try await auth.linkAppleAccount(idToken: idToken, nonce: nonce, accessToken: session.accessToken)
    }

    public func fetchAppleIdentityId() async throws -> String? {
        guard let session = currentSession else { return nil }
        return try await auth.fetchAppleIdentityId(accessToken: session.accessToken)
    }

    public func unlinkAppleAccount(identityId: String) async throws {
        guard let session = currentSession else { throw SupabaseError.notAuthenticated }
        try await auth.unlinkAppleAccount(identityId: identityId, accessToken: session.accessToken)
    }

    public func deleteAccount() async throws {
        guard let session = currentSession else { throw SupabaseError.notAuthenticated }
        try await auth.deleteAccount(accessToken: session.accessToken)
        SessionStore.clear()
        UserDefaults.standard.removeObject(forKey: "moonlit.currentProfileId")
        currentSession = nil
        currentProfile = nil
        profiles = []
        isAuthenticated = false
    }

    public func signUp(email: String, password: String, inviteCode: String) async throws {
        let session = try await auth.signUp(email: email, password: password, inviteCode: inviteCode)
        self.currentSession = session
        SessionStore.save(session)

        let profile = MoonlitProfile(
            id: UUID().uuidString,
            userId: session.userId,
            name: "Default",
            profileIndex: 0,
            role: "user"
        )
        _ = try await client.insert(into: "profiles", value: profile) as [MoonlitProfile]
        self.profiles = [profile]
        self.currentProfile = profile
        self.isAuthenticated = true
    }

    public func signOut() async {
        try? await auth.signOut()
        SessionStore.clear()
        currentSession = nil
        currentProfile = nil
        profiles = []
        isAuthenticated = false
    }

    public func loadProfiles(userId: String) async throws {
        isLoading = true
        defer { isLoading = false }

        let fetched: [MoonlitProfile] = try await syncService.pullProfiles(userId: userId)
        self.profiles = fetched

        // Persist fresh profiles so cache is always warm for next launch.
        if let data = try? JSONEncoder().encode(fetched) {
            UserDefaults.standard.set(data, forKey: profilesCacheKey(userId: userId))
        }

        let savedProfileId = UserDefaults.standard.string(forKey: "moonlit.currentProfileId")
        if let savedId = savedProfileId, let match = fetched.first(where: { $0.id == savedId }) {
            self.currentProfile = match
        } else if currentProfile == nil || !fetched.contains(where: { $0.id == currentProfile?.id }) {
            self.currentProfile = fetched.first
        }
    }

    public func selectProfile(_ profile: MoonlitProfile) {
        currentProfile = profile
        UserDefaults.standard.set(profile.id, forKey: "moonlit.currentProfileId")
    }

    public func createProfile(name: String, avatarId: Int? = nil) async throws {
        guard let session = currentSession else { throw SupabaseError.notAuthenticated }

        let nextIndex = (profiles.map { $0.profileIndex }.max() ?? -1) + 1
        let newProfile = MoonlitProfile(
            id: UUID().uuidString,
            userId: session.userId,
            name: name,
            avatarColor: randomColor(),
            avatarId: avatarId ?? Int.random(in: 0...30),
            profileIndex: nextIndex,
            role: "user"
        )
        _ = try await client.insert(into: "profiles", value: newProfile) as [MoonlitProfile]
        profiles.append(newProfile)
    }

    public func deleteProfile(_ profile: MoonlitProfile) async throws {
        try await client.delete(from: "profiles", where: ["id": profile.id])
        profiles.removeAll { $0.id == profile.id }
        if currentProfile?.id == profile.id {
            currentProfile = profiles.first
        }
    }

    public func updateProfile(_ profile: MoonlitProfile) async throws {
        try await client.update(table: "profiles", where: ["id": profile.id], value: profile)
        if let idx = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[idx] = profile
            if currentProfile?.id == profile.id {
                currentProfile = profile
            }
        }
    }

    private func randomColor() -> String {
        let colors = ["#FF6B6B", "#4ECDC4", "#45B7D1", "#96CEB4", "#FFEAA7",
                      "#DDA0DD", "#98D8C8", "#F7DC6F", "#BB8FCE", "#85C1E9"]
        return colors.randomElement() ?? "#4ECDC4"
    }

    public var isAdmin: Bool {
        currentProfile?.isAdmin ?? false
    }

    public func refreshCurrentProfile() async throws {
        guard let session = currentSession, let profile = currentProfile else { return }
        let fetched: [MoonlitProfile] = try await syncService.pullProfiles(userId: session.userId)
        if let updated = fetched.first(where: { $0.id == profile.id }) {
            currentProfile = updated
            if let idx = profiles.firstIndex(where: { $0.id == profile.id }) {
                profiles[idx] = updated
            }
        }
    }
}
