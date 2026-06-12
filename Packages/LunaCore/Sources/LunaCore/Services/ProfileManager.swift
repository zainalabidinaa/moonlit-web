import Foundation

@MainActor
public class ProfileManager: ObservableObject {
    public static let shared = ProfileManager()

    @Published public var profiles: [LunaProfile] = []
    @Published public var currentProfile: LunaProfile?
    @Published public var currentSession: UserSession?
    @Published public var isLoading = false
    @Published public var isAuthenticated = false
    @Published public var hasRestoredSession = false

    private let auth = SupabaseAuth.shared
    private let syncService = SyncService.shared
    private let client = SupabaseClient.shared

    private init() {
        Task { await restoreSession() }
    }

    private func restoreSession() async {
        isLoading = true
        let startTime = Date()
        defer {
            Task { @MainActor in
                let elapsed = Date().timeIntervalSince(startTime)
                let remaining = 1.5 - elapsed
                if remaining > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
                }
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

    private func profilesCacheKey(userId: String) -> String { "luna.cachedProfiles.\(userId)" }

    private func restoreProfilesFromCache(userId: String) {
        guard profiles.isEmpty,
              let data = UserDefaults.standard.data(forKey: profilesCacheKey(userId: userId)),
              let cached = try? JSONDecoder().decode([LunaProfile].self, from: data),
              !cached.isEmpty else { return }
        self.profiles = cached
        let savedId = UserDefaults.standard.string(forKey: "luna.currentProfileId")
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

    public func signUp(email: String, password: String, inviteCode: String) async throws {
        let session = try await auth.signUp(email: email, password: password, inviteCode: inviteCode)
        self.currentSession = session
        SessionStore.save(session)

        let profile = LunaProfile(
            id: UUID().uuidString,
            userId: session.userId,
            name: "Default",
            profileIndex: 0,
            role: "user"
        )
        _ = try await client.insert(into: "profiles", value: profile) as [LunaProfile]
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

        let fetched: [LunaProfile] = try await syncService.pullProfiles(userId: userId)
        self.profiles = fetched

        // Persist fresh profiles so cache is always warm for next launch.
        if let data = try? JSONEncoder().encode(fetched) {
            UserDefaults.standard.set(data, forKey: profilesCacheKey(userId: userId))
        }

        let savedProfileId = UserDefaults.standard.string(forKey: "luna.currentProfileId")
        if let savedId = savedProfileId, let match = fetched.first(where: { $0.id == savedId }) {
            self.currentProfile = match
        } else if currentProfile == nil || !fetched.contains(where: { $0.id == currentProfile?.id }) {
            self.currentProfile = fetched.first
        }
    }

    public func selectProfile(_ profile: LunaProfile) {
        currentProfile = profile
        UserDefaults.standard.set(profile.id, forKey: "luna.currentProfileId")
    }

    public func createProfile(name: String) async throws {
        guard let session = currentSession else { throw SupabaseError.notAuthenticated }

        let nextIndex = (profiles.map { $0.profileIndex }.max() ?? -1) + 1
        let newProfile = LunaProfile(
            id: UUID().uuidString,
            userId: session.userId,
            name: name,
            avatarColor: randomColor(),
            avatarId: Int.random(in: 0...30),
            profileIndex: nextIndex,
            role: "user"
        )
        _ = try await client.insert(into: "profiles", value: newProfile) as [LunaProfile]
        profiles.append(newProfile)
    }

    public func deleteProfile(_ profile: LunaProfile) async throws {
        try await client.delete(from: "profiles", where: ["id": profile.id])
        profiles.removeAll { $0.id == profile.id }
        if currentProfile?.id == profile.id {
            currentProfile = profiles.first
        }
    }

    public func updateProfile(_ profile: LunaProfile) async throws {
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
        let fetched: [LunaProfile] = try await syncService.pullProfiles(userId: session.userId)
        if let updated = fetched.first(where: { $0.id == profile.id }) {
            currentProfile = updated
            if let idx = profiles.firstIndex(where: { $0.id == profile.id }) {
                profiles[idx] = updated
            }
        }
    }
}
